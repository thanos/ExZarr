defmodule ExZarr.Codecs.ZigCodecs do
  @moduledoc """
  High-performance compression codec implementations.

  Currently uses Erlang's battle-tested :zlib module for all compression operations.

  Future optimizations:
  - Zig NIFs for deflate/flate compression
  - Native ZSTD support (currently falls back to zlib)
  - Native LZ4 support (currently falls back to zlib)  - Blosc meta-compressor

  See ZIG_NIFS_GUIDE.md for information on adding Zig-based compression.
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

  @doc """
  Compresses data using ZSTD (currently uses ZLIB as fallback).

  TODO: Implement native ZSTD compression using either:
  - Zig NIF with std.compress.zstd
  - Elixir NIF binding to libzstd C library
  - Pure Elixir implementation
  """
  def zstd_compress(data, _level \\ 3) when is_binary(data) do
    # Use zlib as a fallback until ZSTD is implemented
    zlib_compress(data)
  end

  @doc """
  Decompresses ZSTD data (currently uses ZLIB as fallback).
  """
  def zstd_decompress(data) when is_binary(data) do
    # Use zlib as a fallback until ZSTD is implemented
    zlib_decompress(data)
  end

  @doc """
  Compresses data using LZ4 (currently uses ZLIB as fallback).

  TODO: Implement native LZ4 compression using either:
  - Zig NIF binding to lz4 C library
  - Elixir NIF binding to liblz4
  - Pure Elixir implementation
  """
  def lz4_compress(data) when is_binary(data) do
    # Use zlib as a fallback until LZ4 is implemented
    zlib_compress(data)
  end

  @doc """
  Decompresses LZ4 data (currently uses ZLIB as fallback).
  """
  def lz4_decompress(data) when is_binary(data) do
    # Use zlib as a fallback until LZ4 is implemented
    zlib_decompress(data)
  end
end
