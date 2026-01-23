defmodule ExZarr.Codecs.Codec do
  @moduledoc """
  Behavior for implementing custom compression/checksum codecs.

  Custom codecs can be registered and used alongside built-in codecs,
  allowing extensibility without modifying ExZarr's core.

  ## Overview

  A codec is responsible for encoding (compressing/transforming) and decoding
  (decompressing/transforming) binary data. Codecs implement this behavior to
  provide a consistent interface for data transformation.

  ## Codec Types

  - `:compression` - Reduces data size (zlib, zstd, lz4, etc.)
  - `:checksum` - Adds integrity verification (crc32c)
  - `:filter` - Transforms data without size reduction (shuffle, delta)
  - `:transformation` - General data transformation

  ## Implementing a Custom Codec

  To create a custom codec:

  1. Define a module implementing this behavior
  2. Implement all required callbacks
  3. Register the codec with `ExZarr.Codecs.register_codec/1`
  4. Use it like any built-in codec

  ## Example

      defmodule MyApp.UppercaseCodec do
        @moduledoc "Transforms text to uppercase (example codec)"
        @behaviour ExZarr.Codecs.Codec

        @impl true
        def codec_id, do: :uppercase

        @impl true
        def codec_info do
          %{
            name: "Uppercase Transform",
            version: "1.0.0",
            type: :transformation,
            description: "Converts text to uppercase"
          }
        end

        @impl true
        def available?, do: true

        @impl true
        def encode(data, _opts) when is_binary(data) do
          {:ok, String.upcase(data)}
        rescue
          e -> {:error, {:encode_failed, e}}
        end

        @impl true
        def decode(data, _opts) when is_binary(data) do
          {:ok, String.downcase(data)}
        rescue
          e -> {:error, {:decode_failed, e}}
        end

        @impl true
        def validate_config(_opts), do: :ok
      end

      # Register and use
      ExZarr.Codecs.register_codec(MyApp.UppercaseCodec)
      {:ok, encoded} = ExZarr.Codecs.compress("hello", :uppercase)
      # encoded = "HELLO"

  ## Codec Configuration

  Codecs can accept configuration options through the opts parameter:

      {:ok, compressed} = ExZarr.Codecs.compress(data, :zstd, level: 9)
      {:ok, encoded} = ExZarr.Codecs.compress(data, :my_codec, threshold: 100)

  ## Error Handling

  Encode and decode functions should return:
  - `{:ok, binary()}` on success
  - `{:error, term()}` on failure

  It's recommended to rescue exceptions and convert them to error tuples.

  ## Availability Checking

  The `available?/0` callback allows codecs to check runtime dependencies:

      def available? do
        case Application.ensure_loaded(:some_dependency) do
          :ok -> true
          _ -> false
        end
      end

  ## Thread Safety

  Codec implementations should be thread-safe as they may be called
  concurrently from multiple processes.
  """

  @type codec_config :: keyword()
  @type encode_result :: {:ok, binary()} | {:error, term()}
  @type decode_result :: {:ok, binary()} | {:error, term()}
  @type codec_type :: :compression | :checksum | :filter | :transformation
  @type codec_info :: %{
          name: String.t(),
          version: String.t(),
          type: codec_type(),
          description: String.t()
        }

  @doc """
  Returns the unique identifier for this codec.

  The codec ID is an atom that users will use to reference this codec.
  It must be unique across all registered codecs.

  ## Examples

      iex> MyCustomCodec.codec_id()
      :my_custom_codec
  """
  @callback codec_id() :: atom()

  @doc """
  Returns metadata about the codec.

  Should return a map with:
  - `:name` - Human-readable name
  - `:version` - Semantic version string
  - `:type` - One of `:compression`, `:checksum`, `:filter`, `:transformation`
  - `:description` - Brief description of what the codec does

  ## Examples

      iex> MyCustomCodec.codec_info()
      %{
        name: "My Custom Codec",
        version: "1.0.0",
        type: :compression,
        description: "Custom compression algorithm"
      }
  """
  @callback codec_info() :: codec_info()

  @doc """
  Checks if the codec is available at runtime.

  Should return `true` if the codec can be used, `false` otherwise.
  This allows codecs to check for required dependencies or system capabilities.

  ## Examples

      # Always available
      def available?, do: true

      # Check for dependency
      def available? do
        case Application.ensure_loaded(:my_dependency) do
          :ok -> true
          _ -> false
        end
      end

      # Check for system library
      def available? do
        System.find_executable("some_tool") != nil
      end
  """
  @callback available?() :: boolean()

  @doc """
  Encodes (compresses/transforms) the input data.

  Takes binary data and optional configuration, returns the encoded binary
  or an error tuple.

  ## Parameters

  - `data` - Binary data to encode
  - `config` - Keyword list of codec-specific options

  ## Returns

  - `{:ok, binary()}` - Successfully encoded data
  - `{:error, term()}` - Encoding failed

  ## Examples

      def encode(data, opts) when is_binary(data) do
        level = Keyword.get(opts, :level, 5)
        case my_compress(data, level) do
          {:ok, compressed} -> {:ok, compressed}
          error -> {:error, {:encode_failed, error}}
        end
      rescue
        e -> {:error, {:encode_failed, e}}
      end
  """
  @callback encode(data :: binary(), config :: codec_config()) :: encode_result()

  @doc """
  Decodes (decompresses/transforms) the input data.

  Takes encoded binary data and optional configuration, returns the decoded
  binary or an error tuple.

  ## Parameters

  - `data` - Binary data to decode
  - `config` - Keyword list of codec-specific options

  ## Returns

  - `{:ok, binary()}` - Successfully decoded data
  - `{:error, term()}` - Decoding failed

  ## Examples

      def decode(data, _opts) when is_binary(data) do
        case my_decompress(data) do
          {:ok, decompressed} -> {:ok, decompressed}
          error -> {:error, {:decode_failed, error}}
        end
      rescue
        e -> {:error, {:decode_failed, e}}
      end
  """
  @callback decode(data :: binary(), config :: codec_config()) :: decode_result()

  @doc """
  Validates codec configuration.

  Optional callback that validates the configuration before encoding/decoding.
  If not implemented, all configurations are considered valid.

  ## Parameters

  - `config` - Keyword list of codec-specific options

  ## Returns

  - `:ok` - Configuration is valid
  - `{:error, term()}` - Configuration is invalid

  ## Examples

      def validate_config(opts) do
        case Keyword.get(opts, :level) do
          nil -> :ok
          n when is_integer(n) and n >= 1 and n <= 9 -> :ok
          _ -> {:error, :invalid_level}
        end
      end
  """
  @callback validate_config(config :: codec_config()) :: :ok | {:error, term()}

  @optional_callbacks [validate_config: 1]

  @doc """
  Helper function to check if a module implements the Codec behavior.

  ## Examples

      iex> ExZarr.Codecs.Codec.implements?(MyCodec)
      true
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    function_exported?(module, :codec_id, 0) and
      function_exported?(module, :codec_info, 0) and
      function_exported?(module, :available?, 0) and
      function_exported?(module, :encode, 2) and
      function_exported?(module, :decode, 2)
  end
end
