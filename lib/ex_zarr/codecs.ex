defmodule ExZarr.Codecs do
  @moduledoc """
  Compression and decompression codecs for Zarr arrays.

  Provides compression and decompression operations for chunk data using
  the following codecs:

  - `:none` - No compression (fastest, but largest storage size)
  - `:zlib` - Standard zlib compression using Erlang's built-in `:zlib` module
  - `:zstd` - Zstandard compression using `ezstd` (optional dependency)
  - `:lz4` - LZ4 compression using `nimble_lz4` (optional dependency)
  - `:snappy` - Snappy compression using `snappyer` (optional dependency)
  - `:blosc` - Blosc meta-compressor using Zig NIF (optional)
  - `:bzip2` - Bzip2 compression using Zig NIF (optional)
  - `:crc32c` - CRC32C checksum codec (bytes-to-bytes, adds 4-byte checksum)

  ## Compression Performance

  Different codecs offer different trade-offs between compression speed,
  decompression speed, and compression ratio:

  - `:none` - Fastest (no CPU overhead), largest files
  - `:lz4` - Very fast compression and decompression, moderate compression ratio
  - `:snappy` - Very fast compression, good for real-time data
  - `:zlib` - Balanced performance and compression ratio (default level 6)
  - `:zstd` - Best compression ratio, fast decompression, configurable levels
  - `:blosc` - Meta-compressor with SIMD acceleration, excellent for numerical data
  - `:bzip2` - High compression ratio, slower speed
  - `:crc32c` - Checksum codec for data integrity (not compression, adds 4-byte overhead)

  ## Optional Dependencies

  Some codecs require optional dependencies. To use them, add to your `mix.exs`:

      def deps do
        [
          {:ex_zarr, "~> 0.1"},
          {:ezstd, "~> 1.1"},        # For :zstd
          {:nimble_lz4, "~> 0.1.3"}, # For :lz4
          {:snappyer, "~> 1.2"}      # For :snappy
        ]
      end

  Check codec availability at runtime with `codec_available?/1`.

  ## Examples

      # Compress data with zlib (always available)
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)

      # Decompress data
      {:ok, original} = ExZarr.Codecs.decompress(compressed, :zlib)

      # Use zstd with compression level
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zstd, level: 5)

      # Use blosc (excellent for numerical data)
      {:ok, compressed} = ExZarr.Codecs.compress(float_data, :blosc, level: 9)

      # Use CRC32C checksum (adds 4-byte checksum for data integrity)
      {:ok, checksummed} = ExZarr.Codecs.compress(data, :crc32c)

      # No compression
      {:ok, data} = ExZarr.Codecs.compress("hello", :none)
      # data == "hello"

      # Check codec availability
      ExZarr.Codecs.codec_available?(:zlib)   # => true (always)
      ExZarr.Codecs.codec_available?(:zstd)   # => true if libzstd is installed
      ExZarr.Codecs.codec_available?(:blosc)  # => true if libblosc is installed
      ExZarr.Codecs.codec_available?(:crc32c) # => true (always available)

  ## Compatibility Notes

  - All codecs are compatible with zarr-python when using the same compression
  - `:zlib` is always available (uses Erlang's built-in module)
  - Other codecs require system libraries and compiled Zig NIFs
  - If a codec is not available, compression/decompression will return an error
  - Use `codec_available?/1` to check availability before use
  """

  alias ExZarr.Codecs.ZigCodecs

  @type codec :: :none | :zlib | :zstd | :lz4 | :snappy | :blosc | :bzip2 | :crc32c

  @doc """
  Compresses data using the specified codec.

  Takes binary data and compresses it using the chosen compression algorithm.
  The `:none` codec returns the data unchanged. Other codecs apply compression
  and return the compressed binary.

  ## Parameters

  - `data` - Binary data to compress
  - `codec` - Compression codec (`:none`, `:zlib`, `:zstd`, `:lz4`, `:snappy`, `:blosc`, `:bzip2`, or `:crc32c`)
  - `opts` - Optional keyword list with compression options:
    - `:level` - Compression level (codec-specific, typically 1-9)

  ## Examples

      # Compress with zlib
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)

      # Compress with zstd at level 5
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zstd, level: 5)

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
  @spec compress(binary(), codec(), keyword()) :: {:ok, binary()} | {:error, term()}
  def compress(data, codec, opts \\ [])
  def compress(data, :none, _opts), do: {:ok, data}

  def compress(data, :zlib, _opts) when is_binary(data) do
    ZigCodecs.zlib_compress(data)
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :zstd, opts) when is_binary(data) do
    level = Keyword.get(opts, :level, 3)
    case ZigCodecs.zstd_compress(data, level) do
      {:ok, compressed} -> {:ok, compressed}
      compressed when is_binary(compressed) -> {:ok, compressed}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :lz4, _opts) when is_binary(data) do
    # LZ4 requires original size for decompression, so we prepend it (8 bytes)
    original_size = byte_size(data)
    case ZigCodecs.lz4_compress(data) do
      {:ok, compressed} -> {:ok, <<original_size::64-unsigned-native, compressed::binary>>}
      compressed when is_binary(compressed) ->
        {:ok, <<original_size::64-unsigned-native, compressed::binary>>}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :snappy, _opts) when is_binary(data) do
    case ZigCodecs.snappy_compress(data) do
      {:ok, compressed} -> {:ok, compressed}
      compressed when is_binary(compressed) -> {:ok, compressed}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :blosc, opts) when is_binary(data) do
    level = Keyword.get(opts, :level, 5)
    case ZigCodecs.blosc_compress(data, level) do
      {:ok, compressed} -> {:ok, compressed}
      compressed when is_binary(compressed) -> {:ok, compressed}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :bzip2, opts) when is_binary(data) do
    level = Keyword.get(opts, :level, 9)
    # Bzip2 also requires original size, prepend it (8 bytes)
    original_size = byte_size(data)
    case ZigCodecs.bzip2_compress(data, level) do
      {:ok, compressed} -> {:ok, <<original_size::64-unsigned-native, compressed::binary>>}
      compressed when is_binary(compressed) ->
        {:ok, <<original_size::64-unsigned-native, compressed::binary>>}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  def compress(data, :crc32c, _opts) when is_binary(data) do
    # CRC32C is a checksum codec, not compression
    # Appends 4-byte CRC32C checksum to data
    case ZigCodecs.crc32c_encode(data) do
      {:ok, checksummed} -> {:ok, checksummed}
      checksummed when is_binary(checksummed) -> {:ok, checksummed}
      {:error, reason} -> {:error, {:checksum_failed, reason}}
    end
  rescue
    e -> {:error, {:checksum_failed, e}}
  end

  def compress(_data, codec, _opts), do: {:error, {:unsupported_codec, codec}}

  @doc """
  Decompresses data using the specified codec.

  Takes compressed binary data and decompresses it using the chosen algorithm.
  The codec must match the one used for compression. The `:none` codec returns
  the data unchanged.

  ## Parameters

  - `data` - Compressed binary data
  - `codec` - Compression codec (`:none`, `:zlib`, `:zstd`, `:lz4`, `:snappy`, `:blosc`, `:bzip2`, or `:crc32c`)

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

  ## Notes

  For `:lz4` and `:bzip2`, the original size is stored in the first 8 bytes
  of the compressed data (prepended during compression).
  """
  @spec decompress(binary(), codec()) :: {:ok, binary()} | {:error, term()}
  def decompress(data, :none), do: {:ok, data}

  def decompress(data, :zlib) when is_binary(data) do
    ZigCodecs.zlib_decompress(data)
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :zstd) when is_binary(data) do
    case ZigCodecs.zstd_decompress(data) do
      {:ok, decompressed} -> {:ok, decompressed}
      decompressed when is_binary(decompressed) -> {:ok, decompressed}
      {:error, reason} -> {:error, {:decompression_failed, reason}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :lz4) when is_binary(data) do
    # Extract original size from first 8 bytes
    case data do
      <<original_size::64-unsigned-native, compressed::binary>> ->
        case ZigCodecs.lz4_decompress(compressed, original_size) do
          {:ok, decompressed} -> {:ok, decompressed}
          decompressed when is_binary(decompressed) -> {:ok, decompressed}
          {:error, reason} -> {:error, {:decompression_failed, reason}}
        end

      _ ->
        {:error, {:decompression_failed, :invalid_lz4_format}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :snappy) when is_binary(data) do
    case ZigCodecs.snappy_decompress(data) do
      {:ok, decompressed} -> {:ok, decompressed}
      decompressed when is_binary(decompressed) -> {:ok, decompressed}
      {:error, reason} -> {:error, {:decompression_failed, reason}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :blosc) when is_binary(data) do
    case ZigCodecs.blosc_decompress(data) do
      {:ok, decompressed} -> {:ok, decompressed}
      decompressed when is_binary(decompressed) -> {:ok, decompressed}
      {:error, reason} -> {:error, {:decompression_failed, reason}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :bzip2) when is_binary(data) do
    # Extract original size from first 8 bytes
    case data do
      <<original_size::64-unsigned-native, compressed::binary>> ->
        case ZigCodecs.bzip2_decompress(compressed, original_size) do
          {:ok, decompressed} -> {:ok, decompressed}
          decompressed when is_binary(decompressed) -> {:ok, decompressed}
          {:error, reason} -> {:error, {:decompression_failed, reason}}
        end

      _ ->
        {:error, {:decompression_failed, :invalid_bzip2_format}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  def decompress(data, :crc32c) when is_binary(data) do
    # CRC32C is a checksum codec
    # Validates and removes 4-byte CRC32C checksum from end of data
    case ZigCodecs.crc32c_decode(data) do
      {:ok, validated} -> {:ok, validated}
      validated when is_binary(validated) -> {:ok, validated}
      {:error, reason} -> {:error, {:checksum_validation_failed, reason}}
    end
  rescue
    e -> {:error, {:checksum_validation_failed, e}}
  end

  def decompress(_data, codec), do: {:error, {:unsupported_codec, codec}}

  @doc """
  Returns the list of available codecs.

  This function checks which codecs are actually available at runtime.
  `:none` and `:zlib` are always available. Other codecs require the
  Zig NIFs to be compiled with the system libraries installed.

  ## Examples

      ExZarr.Codecs.available_codecs()
      # => [:none, :zlib, :zstd, :lz4, :snappy, :blosc, :bzip2]
      # (if all system libraries are installed)

  ## Returns

  List of codec atoms that can be used with `compress/3` and `decompress/2`.
  """
  @spec available_codecs() :: [codec(), ...]
  def available_codecs do
    base = [:none, :zlib, :crc32c]

    # Check which Zig NIF codecs are available
    optional = [:zstd, :lz4, :snappy, :blosc, :bzip2]
    |> Enum.filter(&nif_codec_available?/1)

    base ++ optional
  end

  @doc """
  Checks if a codec is available for use.

  Returns `true` if the codec can be used with `compress/3` and `decompress/2`,
  `false` otherwise.

  This function actually tests if the codec can be used by checking if the
  necessary functions are exported from the ZigCodecs module.

  ## Examples

      ExZarr.Codecs.codec_available?(:zlib)
      # => true

      ExZarr.Codecs.codec_available?(:zstd)
      # => true (if libzstd is installed and NIFs are compiled)

      ExZarr.Codecs.codec_available?(:unknown)
      # => false

  ## Parameters

  - `codec` - Codec atom to check

  ## Returns

  Boolean indicating codec availability.
  """
  @spec codec_available?(codec()) :: boolean()
  def codec_available?(:none), do: true
  def codec_available?(:zlib), do: true
  def codec_available?(:crc32c), do: true

  def codec_available?(codec) when codec in [:zstd, :lz4, :snappy, :blosc, :bzip2] do
    nif_codec_available?(codec)
  end

  def codec_available?(_codec), do: false

  # Private helper to check if a NIF codec is available
  # Tests actual functionality instead of checking exports, since zigler
  # NIFs may not show up correctly with function_exported?
  defp nif_codec_available?(codec) do
    test_data = "test"

    case codec do
      :zstd ->
        case ZigCodecs.zstd_compress(test_data, 1) do
          bin when is_binary(bin) -> true
          {:ok, _} -> true
          _ -> false
        end

      :lz4 ->
        case ZigCodecs.lz4_compress(test_data) do
          bin when is_binary(bin) -> true
          {:ok, _} -> true
          _ -> false
        end

      :snappy ->
        case ZigCodecs.snappy_compress(test_data) do
          bin when is_binary(bin) -> true
          {:ok, _} -> true
          _ -> false
        end

      :blosc ->
        case ZigCodecs.blosc_compress(test_data, 1) do
          bin when is_binary(bin) -> true
          {:ok, _} -> true
          _ -> false
        end

      :bzip2 ->
        case ZigCodecs.bzip2_compress(test_data, 1) do
          bin when is_binary(bin) -> true
          {:ok, _} -> true
          _ -> false
        end

      :crc32c ->
        # CRC32C is always available (pure Zig implementation)
        case ZigCodecs.crc32c_encode(test_data) do
          bin when is_binary(bin) -> true
          {:ok, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
