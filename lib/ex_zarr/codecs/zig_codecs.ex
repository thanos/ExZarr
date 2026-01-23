defmodule ExZarr.Codecs.ZigCodecs do
  @moduledoc """
  High-performance compression codec implementations using Zig NIFs.

  This module provides compression and decompression functions for various codecs
  by binding to C libraries through Zig's excellent C interop capabilities.

  ## Available Codecs

  - **ZLIB**: Erlang's built-in :zlib (always available)
  - **ZSTD**: Zstandard compression via libzstd (requires system library)
  - **LZ4**: LZ4 compression via liblz4 (requires system library)
  - **Snappy**: Snappy compression via libsnappy (requires system library)
  - **Blosc**: Blosc meta-compressor via libblosc (requires system library)
  - **Bzip2**: Bzip2 compression via libbz2 (requires system library)

  ## System Library Requirements

  To use the Zig NIFs, you need to install the compression libraries:

  ### macOS
  ```bash
  brew install zstd lz4 snappy c-blosc bzip2
  ```

  ### Ubuntu/Debian
  ```bash
  apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev
  ```

  ### Fedora/RHEL
  ```bash
  dnf install zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel
  ```

  ## Setup

  The Zig NIFs are compiled automatically when you run:

  ```bash
  mix zig.get    # Download Zig for zigler
  mix compile    # Compile NIFs
  ```

  ## Implementation Notes

  - ZLIB uses Erlang's battle-tested :zlib module (no NIF needed)
  - Other codecs use Zig NIFs that call C libraries via Zig's @cImport
  - Memory is managed by the BEAM allocator for safety
  - Errors are converted to Elixir-friendly tuples

  See ZIG_NIFS_GUIDE.md for detailed implementation information.
  """

  # Import compression configuration helper
  alias ExZarr.Codecs.CompressionConfig

  # Get library paths from configuration (supports environment variable overrides)
  @library_dirs CompressionConfig.library_dirs()
  @bzip2_static_lib CompressionConfig.bzip2_static_lib()

  use Zig,
    otp_app: :ex_zarr,
    c: [
      library_dirs: @library_dirs,
      link_lib: [
        {:system, "zstd"},
        {:system, "lz4"},
        {:system, "snappy"},
        {:system, "blosc"},
        @bzip2_static_lib  # Static library (full path)
      ]
    ]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  // Import C libraries
  const c_zstd = @cImport(@cInclude("zstd.h"));
  const c_lz4 = @cImport({
      @cInclude("lz4.h");
      @cInclude("lz4hc.h");
  });
  const c_snappy = @cImport(@cInclude("snappy-c.h"));
  const c_blosc = @cImport(@cInclude("blosc.h"));
  const c_bz2 = @cImport(@cInclude("bzlib.h"));

  /// Compresses data using ZSTD
  pub fn zstd_compress(data: []const u8, level: i32) !beam.term {
      const max_size = c_zstd.ZSTD_compressBound(data.len);
      const buffer = try beam.allocator.alloc(u8, max_size);
      defer beam.allocator.free(buffer);

      const size = c_zstd.ZSTD_compress(
          buffer.ptr,
          max_size,
          data.ptr,
          data.len,
          level
      );

      if (c_zstd.ZSTD_isError(size) != 0) {
          return beam.make(.{.@"error", .zstd_compression_failed}, .{});
      }

      const result = try beam.allocator.alloc(u8, size);
      @memcpy(result, buffer[0..size]);

      return beam.make(result, .{});
  }

  /// Decompresses ZSTD data
  pub fn zstd_decompress(data: []const u8) !beam.term {
      const content_size = c_zstd.ZSTD_getFrameContentSize(data.ptr, data.len);

      // Check for errors (ZSTD_CONTENTSIZE_ERROR or UNKNOWN are very large values)
      if (content_size >= 0xFFFFFFFFFFFFFFFE) {
          return beam.make(.{.@"error", .zstd_invalid_data}, .{});
      }

      const buffer = try beam.allocator.alloc(u8, content_size);

      const result_size = c_zstd.ZSTD_decompress(
          buffer.ptr,
          content_size,
          data.ptr,
          data.len
      );

      if (c_zstd.ZSTD_isError(result_size) != 0) {
          beam.allocator.free(buffer);
          return beam.make(.{.@"error", .zstd_decompression_failed}, .{});
      }

      return beam.make(buffer, .{});
  }

  /// Compresses data using LZ4
  pub fn lz4_compress(data: []const u8) !beam.term {
      const max_size = c_lz4.LZ4_compressBound(@intCast(data.len));
      const buffer = try beam.allocator.alloc(u8, @intCast(max_size));
      defer beam.allocator.free(buffer);

      const size = c_lz4.LZ4_compress_default(
          @ptrCast(data.ptr),
          @ptrCast(buffer.ptr),
          @intCast(data.len),
          max_size
      );

      if (size <= 0) {
          return beam.make(.{.@"error", .lz4_compression_failed}, .{});
      }

      const result = try beam.allocator.alloc(u8, @intCast(size));
      @memcpy(result, buffer[0..@intCast(size)]);

      return beam.make(result, .{});
  }

  /// Decompresses LZ4 data
  pub fn lz4_decompress(data: []const u8, original_size: usize) !beam.term {
      const buffer = try beam.allocator.alloc(u8, original_size);

      const result_size = c_lz4.LZ4_decompress_safe(
          @ptrCast(data.ptr),
          @ptrCast(buffer.ptr),
          @intCast(data.len),
          @intCast(original_size)
      );

      if (result_size < 0) {
          beam.allocator.free(buffer);
          return beam.make(.{.@"error", .lz4_decompression_failed}, .{});
      }

      return beam.make(buffer, .{});
  }

  /// Compresses data using Snappy
  pub fn snappy_compress(data: []const u8) !beam.term {
      const max_size = c_snappy.snappy_max_compressed_length(data.len);

      const buffer = try beam.allocator.alloc(u8, max_size);
      defer beam.allocator.free(buffer);

      var output_length: usize = max_size;
      const status = c_snappy.snappy_compress(
          @ptrCast(data.ptr),
          data.len,
          @ptrCast(buffer.ptr),
          &output_length
      );

      if (status != c_snappy.SNAPPY_OK) {
          return beam.make(.{.@"error", .snappy_compression_failed}, .{});
      }

      const result = try beam.allocator.alloc(u8, output_length);
      @memcpy(result, buffer[0..output_length]);

      return beam.make(result, .{});
  }

  /// Decompresses Snappy data
  pub fn snappy_decompress(data: []const u8) !beam.term {
      var uncompressed_length: usize = undefined;
      var status = c_snappy.snappy_uncompressed_length(
          @ptrCast(data.ptr),
          data.len,
          &uncompressed_length
      );

      if (status != c_snappy.SNAPPY_OK) {
          return beam.make(.{.@"error", .snappy_invalid_input}, .{});
      }

      const buffer = try beam.allocator.alloc(u8, uncompressed_length);

      status = c_snappy.snappy_uncompress(
          @ptrCast(data.ptr),
          data.len,
          @ptrCast(buffer.ptr),
          &uncompressed_length
      );

      if (status != c_snappy.SNAPPY_OK) {
          beam.allocator.free(buffer);
          return beam.make(.{.@"error", .snappy_decompression_failed}, .{});
      }

      return beam.make(buffer, .{});
  }

  /// Compresses data using Blosc
  pub fn blosc_compress(data: []const u8, level: i32) !beam.term {
      c_blosc.blosc_init();

      const max_size = data.len + c_blosc.BLOSC_MAX_OVERHEAD;
      const buffer = try beam.allocator.alloc(u8, max_size);
      defer beam.allocator.free(buffer);

      const size = c_blosc.blosc_compress(
          level,
          1,
          1,
          data.len,
          data.ptr,
          buffer.ptr,
          max_size
      );

      if (size <= 0) {
          return beam.make(.{.@"error", .blosc_compression_failed}, .{});
      }

      const result = try beam.allocator.alloc(u8, @intCast(size));
      @memcpy(result, buffer[0..@intCast(size)]);

      return beam.make(result, .{});
  }

  /// Decompresses Blosc data
  pub fn blosc_decompress(data: []const u8) !beam.term {
      c_blosc.blosc_init();

      var nbytes: usize = undefined;
      var cbytes: usize = undefined;
      var blocksize: usize = undefined;
      c_blosc.blosc_cbuffer_sizes(
          data.ptr,
          &nbytes,
          &cbytes,
          &blocksize
      );

      const buffer = try beam.allocator.alloc(u8, nbytes);

      const size = c_blosc.blosc_decompress(
          data.ptr,
          buffer.ptr,
          nbytes
      );

      if (size <= 0) {
          beam.allocator.free(buffer);
          return beam.make(.{.@"error", .blosc_decompression_failed}, .{});
      }

      return beam.make(buffer, .{});
  }

  /// Compresses data using Bzip2
  pub fn bzip2_compress(data: []const u8, level: i32) !beam.term {
      const max_size = data.len + (data.len / 100) + 600;
      const buffer = try beam.allocator.alloc(u8, max_size);
      defer beam.allocator.free(buffer);

      var dest_len: c_uint = @intCast(max_size);
      const result = c_bz2.BZ2_bzBuffToBuffCompress(
          @ptrCast(buffer.ptr),
          &dest_len,
          @ptrCast(@constCast(data.ptr)),
          @intCast(data.len),
          level,
          0,
          30
      );

      if (result != c_bz2.BZ_OK) {
          return beam.make(.{.@"error", .bzip2_compression_failed}, .{});
      }

      const output = try beam.allocator.alloc(u8, dest_len);
      @memcpy(output, buffer[0..dest_len]);

      return beam.make(output, .{});
  }

  /// Decompresses Bzip2 data
  pub fn bzip2_decompress(data: []const u8, original_size: usize) !beam.term {
      const buffer = try beam.allocator.alloc(u8, original_size);

      var dest_len: c_uint = @intCast(original_size);
      const result = c_bz2.BZ2_bzBuffToBuffDecompress(
          @ptrCast(buffer.ptr),
          &dest_len,
          @ptrCast(@constCast(data.ptr)),
          @intCast(data.len),
          0,
          0
      );

      if (result != c_bz2.BZ_OK) {
          beam.allocator.free(buffer);
          return beam.make(.{.@"error", .bzip2_decompression_failed}, .{});
      }

      return beam.make(buffer, .{});
  }
  """

  @doc """
  Compresses data using ZLIB.
  Uses Erlang's battle-tested :zlib for maximum compatibility.
  """
  def zlib_compress(data) when is_binary(data) do
    compressed = :zlib.compress(data)
    {:ok, compressed}
  rescue
    e -> {:error, {:zlib_compress_failed, e}}
  end

  @doc """
  Decompresses ZLIB data.
  """
  def zlib_decompress(data) when is_binary(data) do
    decompressed = :zlib.uncompress(data)
    {:ok, decompressed}
  rescue
    e -> {:error, {:zlib_decompress_failed, e}}
  end

  # Note: The Zig NIF functions (zstd_compress, zstd_decompress, etc.)
  # are automatically generated by zigler from the ~Z""" block above.
  # They can be called directly as:
  # - zstd_compress(data, level)
  # - zstd_decompress(data)
  # - lz4_compress(data)
  # - lz4_decompress(data, original_size)
  # - snappy_compress(data)
  # - snappy_decompress(data)
  # - blosc_compress(data, level)
  # - blosc_decompress(data)
  # - bzip2_compress(data, level)
  # - bzip2_decompress(data, original_size)
end
