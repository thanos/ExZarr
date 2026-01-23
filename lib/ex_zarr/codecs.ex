defmodule ExZarr.Codecs do
  @moduledoc """
  Compression and decompression codecs for Zarr arrays.

  Supports both built-in and custom codecs through an extensible codec registry.

  ## Built-in Codecs

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

  ## Custom Codecs

  ExZarr supports custom codecs through the `ExZarr.Codecs.Codec` behavior.
  Implement the behavior and register your codec:

      defmodule MyApp.CustomCodec do
        @behaviour ExZarr.Codecs.Codec

        def codec_id, do: :my_codec
        def codec_info, do: %{name: "My Codec", version: "1.0", type: :compression}
        def available?, do: true
        def encode(data, _opts), do: {:ok, data}
        def decode(data, _opts), do: {:ok, data}
      end

      # Register the codec
      ExZarr.Codecs.register_codec(MyApp.CustomCodec)

      # Use it like built-in codecs
      {:ok, encoded} = ExZarr.Codecs.compress(data, :my_codec)

  See `ExZarr.Codecs.Codec` for full documentation on implementing custom codecs.

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
  alias ExZarr.Codecs.Registry

  @type codec :: atom()  # Changed from fixed atoms to allow custom codecs
  @type codec_module :: module()

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

  # First try to use custom codec from registry
  def compress(data, codec, opts) when is_binary(data) and is_atom(codec) do
    case Registry.get(codec) do
      {:ok, :builtin_none} -> compress_builtin(data, :none, opts)
      {:ok, :builtin_zlib} -> compress_builtin(data, :zlib, opts)
      {:ok, :builtin_crc32c} -> compress_builtin(data, :crc32c, opts)
      {:ok, :builtin_zstd} -> compress_builtin(data, :zstd, opts)
      {:ok, :builtin_lz4} -> compress_builtin(data, :lz4, opts)
      {:ok, :builtin_snappy} -> compress_builtin(data, :snappy, opts)
      {:ok, :builtin_blosc} -> compress_builtin(data, :blosc, opts)
      {:ok, :builtin_bzip2} -> compress_builtin(data, :bzip2, opts)
      {:ok, codec_module} ->
        # Custom codec
        codec_module.encode(data, opts)
      {:error, :not_found} ->
        {:error, {:unsupported_codec, codec}}
    end
  end

  # Built-in codec implementations
  defp compress_builtin(data, :none, _opts), do: {:ok, data}

  defp compress_builtin(data, :zlib, _opts) when is_binary(data) do
    ZigCodecs.zlib_compress(data)
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  defp compress_builtin(data, :zstd, opts) when is_binary(data) do
    level = Keyword.get(opts, :level, 3)
    case ZigCodecs.zstd_compress(data, level) do
      {:ok, compressed} -> {:ok, compressed}
      compressed when is_binary(compressed) -> {:ok, compressed}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  defp compress_builtin(data, :lz4, _opts) when is_binary(data) do
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

  defp compress_builtin(data, :snappy, _opts) when is_binary(data) do
    case ZigCodecs.snappy_compress(data) do
      {:ok, compressed} -> {:ok, compressed}
      compressed when is_binary(compressed) -> {:ok, compressed}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  defp compress_builtin(data, :blosc, opts) when is_binary(data) do
    level = Keyword.get(opts, :level, 5)
    case ZigCodecs.blosc_compress(data, level) do
      {:ok, compressed} -> {:ok, compressed}
      compressed when is_binary(compressed) -> {:ok, compressed}
      {:error, reason} -> {:error, {:compression_failed, reason}}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  defp compress_builtin(data, :bzip2, opts) when is_binary(data) do
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

  defp compress_builtin(data, :crc32c, _opts) when is_binary(data) do
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

  # First try to use custom codec from registry
  def decompress(data, codec) when is_binary(data) and is_atom(codec) do
    case Registry.get(codec) do
      {:ok, :builtin_none} -> decompress_builtin(data, :none)
      {:ok, :builtin_zlib} -> decompress_builtin(data, :zlib)
      {:ok, :builtin_crc32c} -> decompress_builtin(data, :crc32c)
      {:ok, :builtin_zstd} -> decompress_builtin(data, :zstd)
      {:ok, :builtin_lz4} -> decompress_builtin(data, :lz4)
      {:ok, :builtin_snappy} -> decompress_builtin(data, :snappy)
      {:ok, :builtin_blosc} -> decompress_builtin(data, :blosc)
      {:ok, :builtin_bzip2} -> decompress_builtin(data, :bzip2)
      {:ok, codec_module} ->
        # Custom codec
        codec_module.decode(data, [])
      {:error, :not_found} ->
        {:error, {:unsupported_codec, codec}}
    end
  end

  # Built-in codec implementations
  defp decompress_builtin(data, :none), do: {:ok, data}

  defp decompress_builtin(data, :zlib) when is_binary(data) do
    ZigCodecs.zlib_decompress(data)
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  defp decompress_builtin(data, :zstd) when is_binary(data) do
    case ZigCodecs.zstd_decompress(data) do
      {:ok, decompressed} -> {:ok, decompressed}
      decompressed when is_binary(decompressed) -> {:ok, decompressed}
      {:error, reason} -> {:error, {:decompression_failed, reason}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  defp decompress_builtin(data, :lz4) when is_binary(data) do
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

  defp decompress_builtin(data, :snappy) when is_binary(data) do
    case ZigCodecs.snappy_decompress(data) do
      {:ok, decompressed} -> {:ok, decompressed}
      decompressed when is_binary(decompressed) -> {:ok, decompressed}
      {:error, reason} -> {:error, {:decompression_failed, reason}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  defp decompress_builtin(data, :blosc) when is_binary(data) do
    case ZigCodecs.blosc_decompress(data) do
      {:ok, decompressed} -> {:ok, decompressed}
      decompressed when is_binary(decompressed) -> {:ok, decompressed}
      {:error, reason} -> {:error, {:decompression_failed, reason}}
    end
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  defp decompress_builtin(data, :bzip2) when is_binary(data) do
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

  defp decompress_builtin(data, :crc32c) when is_binary(data) do
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
    # Use the registry's available function which checks all codecs
    Registry.available()
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
  def codec_available?(codec) when is_atom(codec) do
    case Registry.get(codec) do
      {:ok, :builtin_none} -> true
      {:ok, :builtin_zlib} -> true
      {:ok, :builtin_crc32c} -> true
      {:ok, :builtin_zstd} -> nif_codec_available?(:zstd)
      {:ok, :builtin_lz4} -> nif_codec_available?(:lz4)
      {:ok, :builtin_snappy} -> nif_codec_available?(:snappy)
      {:ok, :builtin_blosc} -> nif_codec_available?(:blosc)
      {:ok, :builtin_bzip2} -> nif_codec_available?(:bzip2)
      {:ok, codec_module} ->
        # Custom codec - call its available? callback
        try do
          codec_module.available?()
        rescue
          _ -> false
        end
      {:error, :not_found} ->
        false
    end
  end

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

  # === Custom Codec Support ===

  @doc """
  Registers a custom codec.

  The codec module must implement the `ExZarr.Codecs.Codec` behavior.

  ## Examples

      defmodule MyApp.CustomCodec do
        @behaviour ExZarr.Codecs.Codec

        def codec_id, do: :my_codec
        def codec_info, do: %{name: "My Codec", version: "1.0", type: :compression, description: "..."}
        def available?, do: true
        def encode(data, _opts), do: {:ok, my_encode(data)}
        def decode(data, _opts), do: {:ok, my_decode(data)}
      end

      ExZarr.Codecs.register_codec(MyApp.CustomCodec)
      {:ok, encoded} = ExZarr.Codecs.compress(data, :my_codec)

  ## Options

  - `:force` - Overwrite existing codec with same ID (default: false)

  ## Returns

  - `:ok` - Codec registered successfully
  - `{:error, :already_registered}` - Codec ID already in use
  - `{:error, :invalid_codec}` - Module doesn't implement Codec behavior
  """
  @spec register_codec(codec_module(), keyword()) :: :ok | {:error, term()}
  def register_codec(codec_module, opts \\ []) do
    Registry.register(codec_module, opts)
  end

  @doc """
  Unregisters a custom codec.

  Built-in codecs cannot be unregistered.

  ## Examples

      ExZarr.Codecs.unregister_codec(:my_codec)

  ## Returns

  - `:ok` - Codec unregistered successfully
  - `{:error, :not_found}` - Codec not registered
  - `{:error, :cannot_unregister_builtin}` - Cannot unregister built-in codec
  """
  @spec unregister_codec(codec()) :: :ok | {:error, term()}
  def unregister_codec(codec_id) do
    Registry.unregister(codec_id)
  end

  @doc """
  Gets information about a codec.

  Returns metadata including name, version, type, and description.

  ## Examples

      {:ok, info} = ExZarr.Codecs.codec_info(:zstd)
      # => %{
      #   name: "Zstandard",
      #   version: "1.0.0",
      #   type: :compression,
      #   description: "Zstandard compression algorithm"
      # }

  ## Returns

  - `{:ok, map()}` - Codec information
  - `{:error, :not_found}` - Codec not registered
  """
  @spec codec_info(codec()) :: {:ok, map()} | {:error, :not_found}
  def codec_info(codec_id) do
    Registry.info(codec_id)
  end

  @doc """
  Lists all registered codec IDs.

  Includes both built-in and custom codecs, regardless of availability.

  ## Examples

      ExZarr.Codecs.list_codecs()
      # => [:none, :zlib, :crc32c, :zstd, :lz4, :my_codec]
  """
  @spec list_codecs() :: [codec()]
  def list_codecs do
    Registry.list()
  end
end
