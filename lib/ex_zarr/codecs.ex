defmodule ExZarr.Codecs do
  @moduledoc """
  Compression and decompression codecs for Zarr arrays.

  Provides compression and decompression operations for chunk data using
  the following codecs:

  - `:none` - No compression (fastest, but largest storage size)
  - `:zlib` - Standard zlib compression using Erlang's built-in `:zlib` module
  - `:zstd` - Zstandard compression (currently falls back to zlib)
  - `:lz4` - LZ4 compression (currently falls back to zlib)

  The `:zlib` codec uses Erlang's battle-tested `:zlib` module for maximum
  reliability and compatibility across all platforms. Future versions may
  add native implementations of zstd and lz4 using Zig NIFs or other approaches.

  ## Compression Performance

  The `:zlib` codec provides a good balance between compression ratio and speed.
  For repetitive data, compression ratios of 10:1 or better are common.
  Random data typically sees minimal compression.

  ## Examples

      # Compress data
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)

      # Decompress data
      {:ok, original} = ExZarr.Codecs.decompress(compressed, :zlib)

      # No compression
      {:ok, data} = ExZarr.Codecs.compress("hello", :none)
      # data == "hello"

      # Check codec availability
      ExZarr.Codecs.codec_available?(:zlib)  # => true
      ExZarr.Codecs.codec_available?(:blosc) # => false
  """

  alias ExZarr.Codecs.ZigCodecs

  @type codec :: :none | :zlib | :zstd | :lz4 | :blosc

  @doc """
  Compresses data using the specified codec.

  Takes binary data and compresses it using the chosen compression algorithm.
  The `:none` codec returns the data unchanged. Other codecs apply compression
  and return the compressed binary.

  ## Parameters

  - `data` - Binary data to compress
  - `codec` - Compression codec (`:none`, `:zlib`, `:zstd`, or `:lz4`)

  ## Examples

      # Compress with zlib
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)

      # No compression
      {:ok, same} = ExZarr.Codecs.compress("hello", :none)
      # same == "hello"

      # Compress binary data
      data = :crypto.strong_rand_bytes(1000)
      {:ok, compressed} = ExZarr.Codecs.compress(data, :zlib)

  ## Returns

  - `{:ok, compressed_binary}` on success
  - `{:error, {:unsupported_codec, codec}}` if codec is not available
  - `{:error, {:compression_failed, reason}}` if compression fails
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

  Takes compressed binary data and decompresses it using the chosen algorithm.
  The codec must match the one used for compression. The `:none` codec returns
  the data unchanged.

  ## Parameters

  - `data` - Compressed binary data
  - `codec` - Compression codec (`:none`, `:zlib`, `:zstd`, or `:lz4`)

  ## Examples

      # Compress and decompress
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)
      {:ok, original} = ExZarr.Codecs.decompress(compressed, :zlib)
      # original == "hello world"

      # No decompression needed
      {:ok, same} = ExZarr.Codecs.decompress("hello", :none)
      # same == "hello"

  ## Returns

  - `{:ok, decompressed_binary}` on success
  - `{:error, {:unsupported_codec, codec}}` if codec is not available
  - `{:error, {:decompression_failed, reason}}` if decompression fails

  ## Errors

  Decompression will fail if:
  - The data is not validly compressed with the specified codec
  - The data is corrupted
  - The wrong codec is specified
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

  Note that `:zstd` and `:lz4` are listed but currently fall back to
  `:zlib` compression. Future versions may provide native implementations.

  ## Examples

      ExZarr.Codecs.available_codecs()
      # => [:none, :zlib, :zstd, :lz4]

  ## Returns

  List of codec atoms that can be used with `compress/2` and `decompress/2`.
  """
  @spec available_codecs() :: [codec(), ...]
  def available_codecs do
    [:none, :zlib, :zstd, :lz4]
  end

  @doc """
  Checks if a codec is available for use.

  Returns `true` if the codec can be used with `compress/2` and `decompress/2`,
  `false` otherwise.

  ## Examples

      ExZarr.Codecs.codec_available?(:zlib)
      # => true

      ExZarr.Codecs.codec_available?(:blosc)
      # => false

      ExZarr.Codecs.codec_available?(:unknown)
      # => false

  ## Parameters

  - `codec` - Codec atom to check

  ## Returns

  Boolean indicating codec availability.
  """
  @spec codec_available?(codec()) :: boolean()
  def codec_available?(codec) do
    codec in available_codecs()
  end
end
