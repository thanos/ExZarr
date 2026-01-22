defmodule ExZarr.Codecs do
  @moduledoc """
  Compression and decompression codecs for Zarr arrays.

  Uses Zig NIFs for high-performance compression with the following codecs:
  - `:none` - No compression
  - `:zlib` - ZLIB compression (via Zig std.compress.zlib)
  - `:zstd` - Zstandard compression (high compression ratio, fast)
  - `:lz4` - LZ4 compression (extremely fast)
  - `:blosc` - Blosc meta-compressor (future)

  All compression operations are implemented as NIFs in Zig for maximum performance.
  """

  alias ExZarr.Codecs.ZigCodecs

  @type codec :: :none | :zlib | :zstd | :lz4 | :blosc

  @doc """
  Compresses data using the specified codec.

  ## Examples

      {:ok, compressed} = ExZarr.Codecs.compress(data, :zstd)
  """
  @spec compress(binary(), codec()) :: {:ok, binary()} | {:error, term()}
  def compress(data, :none), do: {:ok, data}

  def compress(data, :zlib) when is_binary(data) do
    ZigCodecs.zlib_compress(data)
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :zstd) when is_binary(data) do
    ZigCodecs.zstd_compress(data, 3)
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :lz4) when is_binary(data) do
    ZigCodecs.lz4_compress(data)
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(_data, codec), do: {:error, {:unsupported_codec, codec}}

  @doc """
  Decompresses data using the specified codec.

  ## Examples

      {:ok, decompressed} = ExZarr.Codecs.decompress(compressed_data, :zstd)
  """
  @spec decompress(binary(), codec()) :: {:ok, binary()} | {:error, term()}
  def decompress(data, :none), do: {:ok, data}

  def decompress(data, :zlib) when is_binary(data) do
    ZigCodecs.zlib_decompress(data)
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :zstd) when is_binary(data) do
    ZigCodecs.zstd_decompress(data)
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :lz4) when is_binary(data) do
    ZigCodecs.lz4_decompress(data)
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(_data, codec), do: {:error, {:unsupported_codec, codec}}

  @doc """
  Returns the list of available codecs.
  """
  @spec available_codecs() :: [codec()]
  def available_codecs do
    [:none, :zlib, :zstd, :lz4]
  end

  @doc """
  Checks if a codec is available.
  """
  @spec codec_available?(codec()) :: boolean()
  def codec_available?(codec) do
    codec in available_codecs()
  end
end
