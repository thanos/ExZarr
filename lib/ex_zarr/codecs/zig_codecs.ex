defmodule ExZarr.Codecs.ZigCodecs do
  @moduledoc """
  Compression codec implementations.

  Currently uses Erlang's built-in :zlib module and Elixir implementations.
  Future versions will use Zig NIFs for higher performance.

  Supported codecs:
  - ZLIB compression/decompression (via Erlang :zlib)
  - Zstandard (ZSTD) - placeholder using zlib
  - LZ4 - placeholder using zlib

  TODO: Implement Zig NIFs for better performance once Ziggler environment is properly configured.
  """

  @doc """
  Compresses data using ZLIB.
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
  Compresses data using ZSTD (currently uses ZLIB as placeholder).
  """
  def zstd_compress(data, _level \\ 3) when is_binary(data) do
    # TODO: Implement proper ZSTD compression
    # For now, use zlib as a fallback
    zlib_compress(data)
  end

  @doc """
  Decompresses ZSTD data (currently uses ZLIB as placeholder).
  """
  def zstd_decompress(data) when is_binary(data) do
    # TODO: Implement proper ZSTD decompression
    # For now, use zlib as a fallback
    zlib_decompress(data)
  end

  @doc """
  Compresses data using LZ4 (currently uses ZLIB as placeholder).
  """
  def lz4_compress(data) when is_binary(data) do
    # TODO: Implement proper LZ4 compression
    # For now, use zlib as a fallback
    zlib_compress(data)
  end

  @doc """
  Decompresses LZ4 data (currently uses ZLIB as placeholder).
  """
  def lz4_decompress(data) when is_binary(data) do
    # TODO: Implement proper LZ4 decompression
    # For now, use zlib as a fallback
    zlib_decompress(data)
  end
end
