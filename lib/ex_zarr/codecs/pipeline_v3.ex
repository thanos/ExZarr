defmodule ExZarr.Codecs.PipelineV3 do
  @moduledoc """
  Zarr v3 codec pipeline implementation.

  The v3 specification introduces a unified codec pipeline with strict ordering
  requirements to ensure predictable data transformations.

  ## Codec Ordering

  The pipeline must follow this exact order:

  1. **Array → Array codecs** (zero or more): Transforms that operate on array
     data, such as transpose, delta encoding, bit rounding, etc.

  2. **Array → Bytes codec** (exactly one, required): Serializes array data to
     bytes. The standard codec is "bytes" which handles endianness and packing.

  3. **Bytes → Bytes codecs** (zero or more): Compression codecs that operate
     on byte streams, such as gzip, zstd, blosc, etc.

  ## Example Pipeline

      codecs = [
        # Array → Array: shuffle bytes for better compression
        %{name: "shuffle", configuration: %{elementsize: 8}},
        # Array → Array: delta encoding
        %{name: "delta", configuration: %{dtype: "int64"}},
        # Array → Bytes: serialize to bytes (required)
        %{name: "bytes", configuration: %{}},
        # Bytes → Bytes: compress with gzip
        %{name: "gzip", configuration: %{level: 5}}
      ]

      {:ok, pipeline} = ExZarr.Codecs.PipelineV3.parse_codecs(codecs)
      {:ok, encoded} = ExZarr.Codecs.PipelineV3.encode(data, pipeline)
      {:ok, decoded} = ExZarr.Codecs.PipelineV3.decode(encoded, pipeline)

  ## Specification

  Zarr v3 Core Specification - Codecs:
  https://zarr-specs.readthedocs.io/en/latest/v3/core/index.html#codecs
  """

  alias ExZarr.Codecs

  @type codec_spec :: %{required(:name) => String.t(), optional(:configuration) => map()}
  @type codec_stage :: :array_to_array | :array_to_bytes | :bytes_to_bytes

  defmodule Pipeline do
    @moduledoc """
    Represents a validated v3 codec pipeline.

    The pipeline is organized into three stages:
    - `array_to_array`: List of array transformation codecs
    - `array_to_bytes`: Single serialization codec (required)
    - `bytes_to_bytes`: List of compression codecs
    """

    @type t :: %__MODULE__{
            array_to_array: [map()],
            array_to_bytes: map(),
            bytes_to_bytes: [map()]
          }

    defstruct array_to_array: [],
              array_to_bytes: nil,
              bytes_to_bytes: []
  end

  # Codec stage classifications
  @array_to_array_codecs ["transpose", "shuffle", "delta", "bitround", "quantize", "fixedscaleoffset", "astype", "packbits"]
  @array_to_bytes_codecs ["bytes"]
  @bytes_to_bytes_codecs ["gzip", "zstd", "blosc", "lz4", "bz2", "crc32c"]

  @doc """
  Parses and validates a list of codec specifications.

  Validates:
  - At least one codec is present
  - Exactly one array→bytes codec exists
  - Codecs are in the correct order
  - All codec names are recognized

  ## Parameters

    * `codec_specs` - List of codec specification maps

  ## Returns

    * `{:ok, pipeline}` - Validated pipeline struct
    * `{:error, reason}` - Validation failure

  ## Examples

      iex> codecs = [
      ...>   %{name: "bytes"},
      ...>   %{name: "gzip", configuration: %{level: 5}}
      ...> ]
      iex> {:ok, _pipeline} = ExZarr.Codecs.PipelineV3.parse_codecs(codecs)

      iex> codecs = [%{name: "gzip"}]  # Missing required bytes codec
      iex> ExZarr.Codecs.PipelineV3.parse_codecs(codecs)
      {:error, :missing_array_to_bytes_codec}
  """
  @spec parse_codecs([codec_spec()]) :: {:ok, Pipeline.t()} | {:error, term()}
  def parse_codecs([]), do: {:error, :empty_codec_list}

  def parse_codecs(codec_specs) when is_list(codec_specs) do
    with {:ok, stages} <- classify_codecs(codec_specs),
         :ok <- validate_pipeline(stages) do
      {:ok, %Pipeline{
        array_to_array: stages.array_to_array,
        array_to_bytes: stages.array_to_bytes,
        bytes_to_bytes: stages.bytes_to_bytes
      }}
    end
  end

  @doc false
  @spec classify_codecs([codec_spec()]) :: {:ok, map()} | {:error, term()}
  defp classify_codecs(codec_specs) do
    # Classify each codec and track order
    classified =
      Enum.reduce_while(codec_specs, {:ok, [], nil, []}, fn codec, {:ok, a2a, a2b, b2b} ->
        case classify_codec(codec) do
          {:array_to_array, _} when not is_nil(a2b) ->
            # Array→Array after Array→Bytes (wrong order)
            {:halt, {:error, :invalid_codec_order}}

          {:array_to_array, _} when length(b2b) > 0 ->
            # Array→Array after Bytes→Bytes (wrong order)
            {:halt, {:error, :invalid_codec_order}}

          {:array_to_array, codec} ->
            {:cont, {:ok, [codec | a2a], a2b, b2b}}

          {:array_to_bytes, _} when not is_nil(a2b) ->
            # Multiple Array→Bytes codecs
            {:halt, {:error, :multiple_array_to_bytes_codecs}}

          {:array_to_bytes, _} when length(b2b) > 0 ->
            # Array→Bytes after Bytes→Bytes (wrong order)
            {:halt, {:error, :invalid_codec_order}}

          {:array_to_bytes, codec} ->
            {:cont, {:ok, a2a, codec, b2b}}

          {:bytes_to_bytes, codec} ->
            {:cont, {:ok, a2a, a2b, [codec | b2b]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case classified do
      {:ok, a2a, a2b, b2b} ->
        {:ok, %{
          array_to_array: Enum.reverse(a2a),
          array_to_bytes: a2b,
          bytes_to_bytes: Enum.reverse(b2b)
        }}

      error ->
        error
    end
  end

  @doc false
  @spec classify_codec(codec_spec()) :: {codec_stage(), map()} | {:error, term()}
  defp classify_codec(%{name: name} = codec) when is_binary(name) do
    cond do
      name in @array_to_array_codecs ->
        {:array_to_array, codec}

      name in @array_to_bytes_codecs ->
        {:array_to_bytes, codec}

      name in @bytes_to_bytes_codecs ->
        {:bytes_to_bytes, codec}

      true ->
        # Unknown codec - could be an extension
        # Try to infer from name or allow it as custom
        {:error, {:unknown_codec, name}}
    end
  end

  defp classify_codec(_), do: {:error, :invalid_codec_format}

  @doc false
  @spec validate_pipeline(map()) :: :ok | {:error, term()}
  defp validate_pipeline(%{array_to_bytes: nil}) do
    {:error, :missing_array_to_bytes_codec}
  end

  defp validate_pipeline(_stages), do: :ok

  @doc """
  Encodes data through the codec pipeline.

  Applies codecs in forward order:
  1. Array→Array transformations
  2. Array→Bytes serialization
  3. Bytes→Bytes compression

  ## Parameters

    * `data` - Binary data to encode
    * `pipeline` - Validated pipeline struct
    * `opts` - Additional options (shape, dtype, etc.)

  ## Returns

    * `{:ok, encoded_data}` - Successfully encoded binary
    * `{:error, reason}` - Encoding failure
  """
  @spec encode(binary(), Pipeline.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(data, %Pipeline{} = pipeline, opts \\ []) do
    with {:ok, transformed} <- apply_array_to_array_encode(data, pipeline.array_to_array, opts),
         {:ok, serialized} <- apply_array_to_bytes_encode(transformed, pipeline.array_to_bytes, opts),
         {:ok, compressed} <- apply_bytes_to_bytes_encode(serialized, pipeline.bytes_to_bytes, opts) do
      {:ok, compressed}
    end
  end

  @doc """
  Decodes data through the codec pipeline.

  Applies codecs in reverse order:
  1. Bytes→Bytes decompression
  2. Bytes→Array deserialization
  3. Array→Array reverse transformations

  ## Parameters

    * `data` - Binary data to decode
    * `pipeline` - Validated pipeline struct
    * `opts` - Additional options (shape, dtype, etc.)

  ## Returns

    * `{:ok, decoded_data}` - Successfully decoded binary
    * `{:error, reason}` - Decoding failure
  """
  @spec decode(binary(), Pipeline.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def decode(data, %Pipeline{} = pipeline, opts \\ []) do
    with {:ok, decompressed} <- apply_bytes_to_bytes_decode(data, pipeline.bytes_to_bytes, opts),
         {:ok, deserialized} <- apply_array_to_bytes_decode(decompressed, pipeline.array_to_bytes, opts),
         {:ok, untransformed} <- apply_array_to_array_decode(deserialized, pipeline.array_to_array, opts) do
      {:ok, untransformed}
    end
  end

  # Apply array→array codecs in forward order
  @doc false
  defp apply_array_to_array_encode(data, codecs, opts) do
    Enum.reduce_while(codecs, {:ok, data}, fn codec, {:ok, acc_data} ->
      case apply_codec_encode(codec, acc_data, opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        error -> {:halt, error}
      end
    end)
  end

  # Apply array→array codecs in reverse order
  @doc false
  defp apply_array_to_array_decode(data, codecs, opts) do
    codecs
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, data}, fn codec, {:ok, acc_data} ->
      case apply_codec_decode(codec, acc_data, opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        error -> {:halt, error}
      end
    end)
  end

  # Apply array→bytes codec
  @doc false
  defp apply_array_to_bytes_encode(data, codec, _opts) do
    # The "bytes" codec is typically a no-op for encoding in Elixir
    # since we already have binary data. Just pass through.
    case codec.name do
      "bytes" -> {:ok, data}
      _ -> {:error, {:unsupported_array_to_bytes_codec, codec.name}}
    end
  end

  @doc false
  defp apply_array_to_bytes_decode(data, codec, _opts) do
    # The "bytes" codec is typically a no-op for decoding
    case codec.name do
      "bytes" -> {:ok, data}
      _ -> {:error, {:unsupported_array_to_bytes_codec, codec.name}}
    end
  end

  # Apply bytes→bytes codecs in forward order
  @doc false
  defp apply_bytes_to_bytes_encode(data, codecs, opts) do
    Enum.reduce_while(codecs, {:ok, data}, fn codec, {:ok, acc_data} ->
      case apply_compression_encode(codec, acc_data, opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        error -> {:halt, error}
      end
    end)
  end

  # Apply bytes→bytes codecs in reverse order
  @doc false
  defp apply_bytes_to_bytes_decode(data, codecs, opts) do
    codecs
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, data}, fn codec, {:ok, acc_data} ->
      case apply_compression_decode(codec, acc_data, opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        error -> {:halt, error}
      end
    end)
  end

  # Apply individual array→array codec
  @doc false
  defp apply_codec_encode(%{name: "shuffle"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    elementsize = Map.get(config, :elementsize, Map.get(config, "elementsize", Keyword.get(opts, :itemsize, 8)))

    # Shuffle: transpose byte matrix to group similar byte positions
    shuffle_bytes(data, elementsize)
  end

  defp apply_codec_encode(%{name: "delta"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    dtype_str = Map.get(config, :dtype, Map.get(config, "dtype"))
    dtype = if is_binary(dtype_str), do: ExZarr.DataType.from_v3(dtype_str), else: Keyword.get(opts, :dtype, :int64)

    # Delta encoding: store differences
    encode_delta(data, dtype)
  end

  defp apply_codec_encode(%{name: name}, _data, _opts) do
    {:error, {:unsupported_array_to_array_codec, name}}
  end

  # Apply individual array→array codec (decode)
  @doc false
  defp apply_codec_decode(%{name: "shuffle"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    elementsize = Map.get(config, :elementsize, Map.get(config, "elementsize", Keyword.get(opts, :itemsize, 8)))

    # Unshuffle: transpose back to original byte order
    unshuffle_bytes(data, elementsize)
  end

  defp apply_codec_decode(%{name: "delta"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    dtype_str = Map.get(config, :dtype, Map.get(config, "dtype"))
    dtype = if is_binary(dtype_str), do: ExZarr.DataType.from_v3(dtype_str), else: Keyword.get(opts, :dtype, :int64)

    # Delta decoding: reconstruct from differences
    decode_delta(data, dtype)
  end

  defp apply_codec_decode(%{name: name}, _data, _opts) do
    {:error, {:unsupported_array_to_array_codec, name}}
  end

  # Shuffle filter implementation
  @doc false
  defp shuffle_bytes(data, elementsize) when is_binary(data) do
    num_elements = div(byte_size(data), elementsize)

    if num_elements * elementsize != byte_size(data) do
      {:error, :invalid_data_size}
    else
      # Transpose byte matrix
      shuffled =
        for byte_pos <- 0..(elementsize - 1), into: <<>> do
          for elem_idx <- 0..(num_elements - 1), into: <<>> do
            offset = elem_idx * elementsize + byte_pos
            <<_::binary-size(offset), byte::8, _::binary>> = data
            <<byte>>
          end
        end

      {:ok, shuffled}
    end
  end

  @doc false
  defp unshuffle_bytes(data, elementsize) when is_binary(data) do
    num_elements = div(byte_size(data), elementsize)

    if num_elements * elementsize != byte_size(data) do
      {:error, :invalid_data_size}
    else
      # Reverse transpose
      unshuffled =
        for elem_idx <- 0..(num_elements - 1), into: <<>> do
          for byte_pos <- 0..(elementsize - 1), into: <<>> do
            offset = byte_pos * num_elements + elem_idx
            <<_::binary-size(offset), byte::8, _::binary>> = data
            <<byte>>
          end
        end

      {:ok, unshuffled}
    end
  end

  # Delta encoding implementation (simplified)
  @doc false
  defp encode_delta(data, dtype) do
    itemsize = ExZarr.DataType.itemsize(dtype)
    num_elements = div(byte_size(data), itemsize)

    if num_elements == 0 do
      {:ok, data}
    else
      # Store first element as-is, then differences
      <<first::binary-size(itemsize), rest::binary>> = data

      deltas =
        rest
        |> :binary.bin_to_list()
        |> Enum.chunk_every(itemsize)
        |> Enum.map(&:binary.list_to_bin/1)
        |> Enum.scan(first, fn current, previous ->
          # Compute difference (simplified for now)
          current
        end)
        |> Enum.join()

      {:ok, first <> deltas}
    end
  end

  @doc false
  defp decode_delta(data, dtype) do
    itemsize = ExZarr.DataType.itemsize(dtype)
    num_elements = div(byte_size(data), itemsize)

    if num_elements == 0 do
      {:ok, data}
    else
      # Reconstruct from differences (simplified for now)
      {:ok, data}
    end
  end

  # Apply compression codec
  @doc false
  defp apply_compression_encode(%{name: name} = codec, data, _opts) do
    config = Map.get(codec, :configuration, %{})

    case name do
      "gzip" ->
        level = Map.get(config, :level, Map.get(config, "level", 5))
        Codecs.compress(data, :zlib, level: level)

      "zstd" ->
        level = Map.get(config, :level, Map.get(config, "level", 5))
        Codecs.compress(data, :zstd, level: level)

      "blosc" ->
        Codecs.compress(data, :blosc)

      "lz4" ->
        Codecs.compress(data, :lz4)

      "bz2" ->
        Codecs.compress(data, :bzip2)

      "crc32c" ->
        Codecs.compress(data, :crc32c)

      _ ->
        {:error, {:unsupported_compression_codec, name}}
    end
  end

  @doc false
  defp apply_compression_decode(%{name: name}, data, _opts) do
    case name do
      "gzip" -> Codecs.decompress(data, :zlib)
      "zstd" -> Codecs.decompress(data, :zstd)
      "blosc" -> Codecs.decompress(data, :blosc)
      "lz4" -> Codecs.decompress(data, :lz4)
      "bz2" -> Codecs.decompress(data, :bzip2)
      "crc32c" -> Codecs.decompress(data, :crc32c)
      _ -> {:error, {:unsupported_compression_codec, name}}
    end
  end

  @doc """
  Converts v2-style filters and compressor to v3 codec list.

  ## Parameters

    * `filters` - List of v2 filter tuples `{:filter_id, opts}`
    * `compressor` - v2 compressor atom (`:zlib`, `:zstd`, etc.)

  ## Returns

    * List of v3 codec specifications

  ## Examples

      iex> filters = [{:shuffle, [elementsize: 8]}, {:delta, [dtype: :int64]}]
      iex> codecs = ExZarr.Codecs.PipelineV3.from_v2(filters, :zlib)
      iex> length(codecs)
      4
  """
  @spec from_v2(list() | nil, atom()) :: [codec_spec()]
  def from_v2(filters, compressor) do
    # Convert filters to v3 array→array codecs
    filter_codecs =
      case filters do
        nil -> []
        [] -> []
        list when is_list(list) ->
          Enum.map(list, fn {filter_id, opts} ->
            filter_to_v3_codec(filter_id, opts)
          end)
      end

    # Required bytes codec
    bytes_codec = %{name: "bytes", configuration: %{}}

    # Convert compressor to v3 bytes→bytes codec
    compressor_codec =
      case compressor do
        :none -> []
        :zlib -> [%{name: "gzip", configuration: %{level: 5}}]
        :zstd -> [%{name: "zstd", configuration: %{level: 5}}]
        :lz4 -> [%{name: "lz4", configuration: %{}}]
        :blosc -> [%{name: "blosc", configuration: %{}}]
        :bzip2 -> [%{name: "bz2", configuration: %{}}]
        :crc32c -> [%{name: "crc32c", configuration: %{}}]
        _ -> []
      end

    filter_codecs ++ [bytes_codec] ++ compressor_codec
  end

  @doc false
  defp filter_to_v3_codec(:shuffle, opts) do
    %{name: "shuffle", configuration: %{elementsize: opts[:elementsize] || 8}}
  end

  defp filter_to_v3_codec(:delta, opts) do
    dtype = opts[:dtype] || :int64
    %{name: "delta", configuration: %{dtype: ExZarr.DataType.to_v3(dtype)}}
  end

  defp filter_to_v3_codec(:quantize, opts) do
    dtype = opts[:dtype] || :float64
    %{name: "quantize", configuration: %{
      digits: opts[:digits] || 3,
      dtype: ExZarr.DataType.to_v3(dtype)
    }}
  end

  defp filter_to_v3_codec(filter_id, _opts) do
    # Generic conversion for other filters
    %{name: Atom.to_string(filter_id), configuration: %{}}
  end
end
