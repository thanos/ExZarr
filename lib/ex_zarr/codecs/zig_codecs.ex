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
  # On Linux, library_dirs can be empty as the linker finds system libraries automatically
  @library_dirs (case :os.type() do
                   {:unix, :darwin} -> CompressionConfig.library_dirs()
                   _ -> []
                 end)

  # Get include paths from configuration
  @include_dirs (case :os.type() do
                   {:unix, :darwin} -> CompressionConfig.include_dirs()
                   _ -> []
                 end)

  use Zig,
    otp_app: :ex_zarr,
    c: [
      include_dirs: @include_dirs,
      library_dirs: @library_dirs,
      link_lib: [
        {:system, "zstd"},
        {:system, "lz4"},
        {:system, "snappy"},
        {:system, "blosc"},
        # Use dynamic linking for bzip2 to avoid PIC issues on Linux
        {:system, "bz2"}
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

  // CRC32C lookup table (Castagnoli polynomial 0x1EDC6F41)
  const crc32c_table = [256]u32{
      0x00000000, 0xF26B8303, 0xE13B70F7, 0x1350F3F4, 0xC79A971F, 0x35F1141C, 0x26A1E7E8, 0xD4CA64EB,
      0x8AD958CF, 0x78B2DBCC, 0x6BE22838, 0x9989AB3B, 0x4D43CFD0, 0xBF284CD3, 0xAC78BF27, 0x5E133C24,
      0x105EC76F, 0xE235446C, 0xF165B798, 0x030E349B, 0xD7C45070, 0x25AFD373, 0x36FF2087, 0xC494A384,
      0x9A879FA0, 0x68EC1CA3, 0x7BBCEF57, 0x89D76C54, 0x5D1D08BF, 0xAF768BBC, 0xBC267848, 0x4E4DFB4B,
      0x20BD8EDE, 0xD2D60DDD, 0xC186FE29, 0x33ED7D2A, 0xE72719C1, 0x154C9AC2, 0x061C6936, 0xF477EA35,
      0xAA64D611, 0x580F5512, 0x4B5FA6E6, 0xB93425E5, 0x6DFE410E, 0x9F95C20D, 0x8CC531F9, 0x7EAEB2FA,
      0x30E349B1, 0xC288CAB2, 0xD1D83946, 0x23B3BA45, 0xF779DEAE, 0x05125DAD, 0x1642AE59, 0xE4292D5A,
      0xBA3A117E, 0x4851927D, 0x5B016189, 0xA96AE28A, 0x7DA08661, 0x8FCB0562, 0x9C9BF696, 0x6EF07595,
      0x417B1DBC, 0xB3109EBF, 0xA0406D4B, 0x522BEE48, 0x86E18AA3, 0x748A09A0, 0x67DAFA54, 0x95B17957,
      0xCBA24573, 0x39C9C670, 0x2A993584, 0xD8F2B687, 0x0C38D26C, 0xFE53516F, 0xED03A29B, 0x1F682198,
      0x5125DAD3, 0xA34E59D0, 0xB01EAA24, 0x42752927, 0x96BF4DCC, 0x64D4CECF, 0x77843D3B, 0x85EFBE38,
      0xDBFC821C, 0x2997011F, 0x3AC7F2EB, 0xC8AC71E8, 0x1C661503, 0xEE0D9600, 0xFD5D65F4, 0x0F36E6F7,
      0x61C69362, 0x93AD1061, 0x80FDE395, 0x72966096, 0xA65C047D, 0x5437877E, 0x4767748A, 0xB50CF789,
      0xEB1FCBAD, 0x197448AE, 0x0A24BB5A, 0xF84F3859, 0x2C855CB2, 0xDEEEDFB1, 0xCDBE2C45, 0x3FD5AF46,
      0x7198540D, 0x83F3D70E, 0x90A324FA, 0x62C8A7F9, 0xB602C312, 0x44694011, 0x5739B3E5, 0xA55230E6,
      0xFB410CC2, 0x092A8FC1, 0x1A7A7C35, 0xE811FF36, 0x3CDB9BDD, 0xCEB018DE, 0xDDE0EB2A, 0x2F8B6829,
      0x82F63B78, 0x709DB87B, 0x63CD4B8F, 0x91A6C88C, 0x456CAC67, 0xB7072F64, 0xA457DC90, 0x563C5F93,
      0x082F63B7, 0xFA44E0B4, 0xE9141340, 0x1B7F9043, 0xCFB5F4A8, 0x3DDE77AB, 0x2E8E845F, 0xDCE5075C,
      0x92A8FC17, 0x60C37F14, 0x73938CE0, 0x81F80FE3, 0x55326B08, 0xA759E80B, 0xB4091BFF, 0x466298FC,
      0x1871A4D8, 0xEA1A27DB, 0xF94AD42F, 0x0B21572C, 0xDFEB33C7, 0x2D80B0C4, 0x3ED04330, 0xCCBBC033,
      0xA24BB5A6, 0x502036A5, 0x4370C551, 0xB11B4652, 0x65D122B9, 0x97BAA1BA, 0x84EA524E, 0x7681D14D,
      0x2892ED69, 0xDAF96E6A, 0xC9A99D9E, 0x3BC21E9D, 0xEF087A76, 0x1D63F975, 0x0E330A81, 0xFC588982,
      0xB21572C9, 0x407EF1CA, 0x532E023E, 0xA145813D, 0x758FE5D6, 0x87E466D5, 0x94B49521, 0x66DF1622,
      0x38CC2A06, 0xCAA7A905, 0xD9F75AF1, 0x2B9CD9F2, 0xFF56BD19, 0x0D3D3E1A, 0x1E6DCDEE, 0xEC064EED,
      0xC38D26C4, 0x31E6A5C7, 0x22B65633, 0xD0DDD530, 0x0417B1DB, 0xF67C32D8, 0xE52CC12C, 0x1747422F,
      0x49547E0B, 0xBB3FFD08, 0xA86F0EFC, 0x5A048DFF, 0x8ECEE914, 0x7CA56A17, 0x6FF599E3, 0x9D9E1AE0,
      0xD3D3E1AB, 0x21B862A8, 0x32E8915C, 0xC083125F, 0x144976B4, 0xE622F5B7, 0xF5720643, 0x07198540,
      0x590AB964, 0xAB613A67, 0xB831C993, 0x4A5A4A90, 0x9E902E7B, 0x6CFBAD78, 0x7FAB5E8C, 0x8DC0DD8F,
      0xE330A81A, 0x115B2B19, 0x020BD8ED, 0xF0605BEE, 0x24AA3F05, 0xD6C1BC06, 0xC5914FF2, 0x37FACCF1,
      0x69E9F0D5, 0x9B8273D6, 0x88D28022, 0x7AB90321, 0xAE7367CA, 0x5C18E4C9, 0x4F48173D, 0xBD23943E,
      0xF36E6F75, 0x0105EC76, 0x12551F82, 0xE03E9C81, 0x34F4F86A, 0xC69F7B69, 0xD5CF889D, 0x27A40B9E,
      0x79B737BA, 0x8BDCB4B9, 0x988C474D, 0x6AE7C44E, 0xBE2DA0A5, 0x4C4623A6, 0x5F16D052, 0xAD7D5351,
  };

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

  /// Computes CRC32C checksum using Castagnoli polynomial
  fn compute_crc32c(data: []const u8) u32 {
      var crc: u32 = 0xFFFFFFFF;
      for (data) |byte| {
          const index = @as(u8, @truncate(crc ^ byte));
          crc = (crc >> 8) ^ crc32c_table[index];
      }
      return crc ^ 0xFFFFFFFF;
  }

  /// Encodes data with CRC32C checksum appended (bytes-to-bytes codec)
  /// Appends 4-byte checksum in little-endian format to the end of data
  pub fn crc32c_encode(data: []const u8) !beam.term {
      // Calculate checksum
      const checksum = compute_crc32c(data);

      // Allocate buffer for data + 4-byte checksum
      const result = try beam.allocator.alloc(u8, data.len + 4);

      // Copy original data
      @memcpy(result[0..data.len], data);

      // Append checksum as little-endian u32
      result[data.len] = @truncate(checksum);
      result[data.len + 1] = @truncate(checksum >> 8);
      result[data.len + 2] = @truncate(checksum >> 16);
      result[data.len + 3] = @truncate(checksum >> 24);

      return beam.make(result, .{});
  }

  /// Decodes data with CRC32C checksum validation (bytes-to-bytes codec)
  /// Validates and removes the 4-byte checksum from the end of data
  pub fn crc32c_decode(data: []const u8) !beam.term {
      // Need at least 4 bytes for checksum
      if (data.len < 4) {
          return beam.make(.{.@"error", .crc32c_invalid_data}, .{});
      }

      // Extract the stored checksum (little-endian)
      const stored_checksum: u32 =
          @as(u32, data[data.len - 4]) |
          (@as(u32, data[data.len - 3]) << 8) |
          (@as(u32, data[data.len - 2]) << 16) |
          (@as(u32, data[data.len - 1]) << 24);

      // Extract inner data (everything except last 4 bytes)
      const inner_data = data[0..data.len - 4];

      // Compute checksum of inner data
      const computed_checksum = compute_crc32c(inner_data);

      // Validate checksums match
      if (stored_checksum != computed_checksum) {
          return beam.make(.{.@"error", .crc32c_checksum_mismatch}, .{});
      }

      // Allocate and return validated data (without checksum)
      const result = try beam.allocator.alloc(u8, inner_data.len);
      @memcpy(result, inner_data);

      return beam.make(result, .{});
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
