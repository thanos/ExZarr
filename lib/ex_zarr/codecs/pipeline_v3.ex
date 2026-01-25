defmodule ExZarr.Codecs.PipelineV3 do
  import Bitwise

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
  @array_to_array_codecs [
    "transpose",
    "shuffle",
    "delta",
    "bitround",
    "quantize",
    "fixedscaleoffset",
    "astype",
    "packbits"
  ]
  @array_to_bytes_codecs ["bytes"]
  @bytes_to_bytes_codecs ["gzip", "zstd", "blosc", "lz4", "bz2", "crc32c", "sharding_indexed"]

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
      {:ok,
       %Pipeline{
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

          {:array_to_array, _} when b2b != [] ->
            # Array→Array after Bytes→Bytes (wrong order)
            {:halt, {:error, :invalid_codec_order}}

          {:array_to_array, codec} ->
            {:cont, {:ok, [codec | a2a], a2b, b2b}}

          {:array_to_bytes, _} when not is_nil(a2b) ->
            # Multiple Array→Bytes codecs
            {:halt, {:error, :multiple_array_to_bytes_codecs}}

          {:array_to_bytes, _} when b2b != [] ->
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
        {:ok,
         %{
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
  @spec validate_pipeline(map()) :: :ok | {:error, :missing_array_to_bytes_codec}
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
         {:ok, serialized} <-
           apply_array_to_bytes_encode(transformed, pipeline.array_to_bytes, opts) do
      apply_bytes_to_bytes_encode(serialized, pipeline.bytes_to_bytes, opts)
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
         {:ok, deserialized} <-
           apply_array_to_bytes_decode(decompressed, pipeline.array_to_bytes, opts) do
      apply_array_to_array_decode(deserialized, pipeline.array_to_array, opts)
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

    elementsize =
      Map.get(
        config,
        :elementsize,
        Map.get(config, "elementsize", Keyword.get(opts, :itemsize, 8))
      )

    # Shuffle: transpose byte matrix to group similar byte positions
    shuffle_bytes(data, elementsize)
  end

  defp apply_codec_encode(%{name: "delta"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    dtype_str = Map.get(config, :dtype, Map.get(config, "dtype"))

    dtype =
      if is_binary(dtype_str),
        do: ExZarr.DataType.from_v3(dtype_str),
        else: Keyword.get(opts, :dtype, :int64)

    # Delta encoding: store differences
    encode_delta(data, dtype)
  end

  defp apply_codec_encode(%{name: "transpose"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    order = Map.get(config, :order, Map.get(config, "order"))
    shape = Keyword.get(opts, :shape)
    dtype = Keyword.get(opts, :dtype, :float64)

    if is_nil(order) or is_nil(shape) do
      {:error, {:missing_transpose_config, "order and shape required"}}
    else
      transpose_array(data, shape, order, dtype)
    end
  end

  defp apply_codec_encode(%{name: "quantize"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    dtype_str = Map.get(config, :dtype, Map.get(config, "dtype"))
    scale = Map.get(config, :scale, Map.get(config, "scale", 1.0))
    offset = Map.get(config, :offset, Map.get(config, "offset", 0.0))

    source_dtype = Keyword.get(opts, :dtype, :float64)

    target_dtype =
      if is_binary(dtype_str),
        do: ExZarr.DataType.from_v3(dtype_str),
        else: :int16

    quantize_encode(data, source_dtype, target_dtype, scale, offset)
  end

  defp apply_codec_encode(%{name: "bitround"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    keepbits = Map.get(config, :keepbits, Map.get(config, "keepbits", 10))
    dtype = Keyword.get(opts, :dtype, :float64)

    bitround_encode(data, dtype, keepbits)
  end

  defp apply_codec_encode(%{name: name}, _data, _opts) do
    {:error, {:unsupported_array_to_array_codec, name}}
  end

  # Apply individual array→array codec (decode)
  @doc false
  defp apply_codec_decode(%{name: "shuffle"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})

    elementsize =
      Map.get(
        config,
        :elementsize,
        Map.get(config, "elementsize", Keyword.get(opts, :itemsize, 8))
      )

    # Unshuffle: transpose back to original byte order
    unshuffle_bytes(data, elementsize)
  end

  defp apply_codec_decode(%{name: "delta"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    dtype_str = Map.get(config, :dtype, Map.get(config, "dtype"))

    dtype =
      if is_binary(dtype_str),
        do: ExZarr.DataType.from_v3(dtype_str),
        else: Keyword.get(opts, :dtype, :int64)

    # Delta decoding: reconstruct from differences
    decode_delta(data, dtype)
  end

  defp apply_codec_decode(%{name: "transpose"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    order = Map.get(config, :order, Map.get(config, "order"))
    shape = Keyword.get(opts, :shape)
    dtype = Keyword.get(opts, :dtype, :float64)

    if is_nil(order) or is_nil(shape) do
      {:error, {:missing_transpose_config, "order and shape required"}}
    else
      # For decoding, we need to invert the transpose operation
      inverse_order = invert_permutation(order)
      # Apply transpose with transposed shape
      transposed_shape = permute_shape(shape, order)
      transpose_array(data, transposed_shape, inverse_order, dtype)
    end
  end

  defp apply_codec_decode(%{name: "quantize"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    dtype_str = Map.get(config, :dtype, Map.get(config, "dtype"))
    scale = Map.get(config, :scale, Map.get(config, "scale", 1.0))
    offset = Map.get(config, :offset, Map.get(config, "offset", 0.0))

    target_dtype = Keyword.get(opts, :dtype, :float64)

    source_dtype =
      if is_binary(dtype_str),
        do: ExZarr.DataType.from_v3(dtype_str),
        else: :int16

    quantize_decode(data, source_dtype, target_dtype, scale, offset)
  end

  defp apply_codec_decode(%{name: "bitround"} = codec, data, opts) do
    config = Map.get(codec, :configuration, %{})
    keepbits = Map.get(config, :keepbits, Map.get(config, "keepbits", 10))
    dtype = Keyword.get(opts, :dtype, :float64)

    # Bitround is lossy - decoding is a no-op since precision is already lost
    # The data is already rounded, so just pass through
    bitround_decode(data, dtype, keepbits)
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
        |> Enum.scan(first, fn current, _previous ->
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
        # Use actual gzip format (not zlib/deflate)
        gzip_compress(data, level)

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
      "gzip" ->
        # Use actual gzip format (not zlib/deflate)
        gzip_decompress(data)

      "zstd" ->
        Codecs.decompress(data, :zstd)

      "blosc" ->
        Codecs.decompress(data, :blosc)

      "lz4" ->
        Codecs.decompress(data, :lz4)

      "bz2" ->
        Codecs.decompress(data, :bzip2)

      "crc32c" ->
        Codecs.decompress(data, :crc32c)

      _ ->
        {:error, {:unsupported_compression_codec, name}}
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
        nil ->
          []

        [] ->
          []

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

    %{
      name: "quantize",
      configuration: %{
        digits: opts[:digits] || 3,
        dtype: ExZarr.DataType.to_v3(dtype)
      }
    }
  end

  defp filter_to_v3_codec(filter_id, _opts) do
    # Generic conversion for other filters
    %{name: Atom.to_string(filter_id), configuration: %{}}
  end

  # Transpose codec implementation
  @doc false
  defp transpose_array(data, shape, order, dtype) do
    shape_list = if is_tuple(shape), do: Tuple.to_list(shape), else: shape
    ndim = length(shape_list)

    # Validate order
    if length(order) != ndim or Enum.sort(order) != Enum.to_list(0..(ndim - 1)) do
      {:error, {:invalid_transpose_order, "order must be a permutation of 0..#{ndim - 1}"}}
    else
      itemsize = ExZarr.DataType.itemsize(dtype)
      num_elements = div(byte_size(data), itemsize)

      # For small dimensions, do the transpose
      if ndim == 1 do
        # 1D: no-op
        {:ok, data}
      else
        # General N-dimensional transpose
        transpose_nd(data, shape_list, order, itemsize, num_elements)
      end
    end
  end

  @doc false
  defp transpose_nd(data, shape, order, itemsize, num_elements) do
    # Compute strides for original and transposed array
    original_strides = compute_strides(shape)
    new_shape = permute_shape(shape, order)
    new_strides = compute_strides(new_shape)

    # Reorder elements: for each position in OUTPUT array, find corresponding position in INPUT
    transposed =
      for output_idx <- 0..(num_elements - 1), into: <<>> do
        # Convert output flat index to multi-index in transposed array
        output_multi_idx = flat_to_multi_index(output_idx, new_strides)
        # Reverse permute to get input multi-index
        input_multi_idx = reverse_permute_index(output_multi_idx, order)
        # Convert to flat index in original array
        input_flat_idx = multi_to_flat_index(input_multi_idx, original_strides)
        # Extract element from input position
        offset = input_flat_idx * itemsize
        <<_::binary-size(offset), element::binary-size(itemsize), _::binary>> = data
        element
      end

    {:ok, transposed}
  end

  @doc false
  defp compute_strides(shape) do
    # Row-major (C-order) strides
    shape
    |> Enum.reverse()
    |> Enum.scan(1, &*/2)
    |> Enum.reverse()
    |> tl()
    |> Kernel.++([1])
  end

  @doc false
  defp flat_to_multi_index(flat_idx, strides) do
    {multi_idx, _} =
      Enum.reduce(strides, {[], flat_idx}, fn stride, {acc, remainder} ->
        idx = div(remainder, stride)
        {acc ++ [idx], rem(remainder, stride)}
      end)

    multi_idx
  end

  @doc false
  defp multi_to_flat_index(multi_idx, strides) do
    Enum.zip(multi_idx, strides)
    |> Enum.reduce(0, fn {idx, stride}, acc -> acc + idx * stride end)
  end

  @doc false
  defp reverse_permute_index(output_multi_idx, order) do
    # If output dimension j came from input dimension order[j],
    # then input dimension i goes to output dimension (position of i in order)
    # So output_multi_idx[j] corresponds to input dimension order[j]
    order
    |> Enum.with_index()
    |> Enum.sort_by(fn {source_dim, _output_pos} -> source_dim end)
    |> Enum.map(fn {_source_dim, output_pos} -> Enum.at(output_multi_idx, output_pos) end)
  end

  @doc false
  defp permute_shape(shape, order) when is_tuple(shape) do
    permute_shape(Tuple.to_list(shape), order)
  end

  defp permute_shape(shape, order) when is_list(shape) do
    Enum.map(order, fn i -> Enum.at(shape, i) end)
  end

  @doc false
  defp invert_permutation(order) do
    # Create inverse: if order[i] = j, then inverse[j] = i
    order
    |> Enum.with_index()
    |> Enum.sort_by(fn {val, _idx} -> val end)
    |> Enum.map(fn {_val, idx} -> idx end)
  end

  # Quantize codec implementation
  @doc false
  defp quantize_encode(data, source_dtype, target_dtype, scale, offset) do
    if byte_size(data) == 0 do
      {:ok, <<>>}
    else
      source_itemsize = ExZarr.DataType.itemsize(source_dtype)
      target_itemsize = ExZarr.DataType.itemsize(target_dtype)
      num_elements = div(byte_size(data), source_itemsize)

      # Parse floats, quantize, pack as integers
      quantized =
        for i <- 0..(num_elements - 1), into: <<>> do
          offset_bytes = i * source_itemsize

          <<_::binary-size(offset_bytes), element::binary-size(source_itemsize), _::binary>> =
            data

          float_val = parse_float(element, source_dtype)
          # Quantize: round((value - offset) / scale)
          quantized_val = round((float_val - offset) / scale)
          # Clamp to target type range
          clamped_val = clamp_to_int_range(quantized_val, target_dtype)
          pack_int(clamped_val, target_dtype, target_itemsize)
        end

      {:ok, quantized}
    end
  end

  @doc false
  defp quantize_decode(data, source_dtype, target_dtype, scale, offset) do
    if byte_size(data) == 0 do
      {:ok, <<>>}
    else
      source_itemsize = ExZarr.DataType.itemsize(source_dtype)
      target_itemsize = ExZarr.DataType.itemsize(target_dtype)
      num_elements = div(byte_size(data), source_itemsize)

      # Parse integers, dequantize, pack as floats
      dequantized =
        for i <- 0..(num_elements - 1), into: <<>> do
          offset_bytes = i * source_itemsize

          <<_::binary-size(offset_bytes), element::binary-size(source_itemsize), _::binary>> =
            data

          int_val = parse_int(element, source_dtype)
          # Dequantize: value = quantized * scale + offset
          float_val = int_val * scale + offset
          pack_float(float_val, target_dtype, target_itemsize)
        end

      {:ok, dequantized}
    end
  end

  @doc false
  defp parse_float(<<value::float-little-32>>, :float32), do: value
  defp parse_float(<<value::float-little-64>>, :float64), do: value
  defp parse_float(_, _), do: 0.0

  @doc false
  defp parse_int(<<value::signed-little-16>>, :int16), do: value
  defp parse_int(<<value::signed-little-32>>, :int32), do: value
  defp parse_int(<<value::signed-little-64>>, :int64), do: value
  defp parse_int(<<value::unsigned-little-8>>, :uint8), do: value
  defp parse_int(<<value::unsigned-little-16>>, :uint16), do: value
  defp parse_int(<<value::unsigned-little-32>>, :uint32), do: value
  defp parse_int(_, _), do: 0

  @doc false
  defp pack_int(value, :int16, _), do: <<value::signed-little-16>>
  defp pack_int(value, :int32, _), do: <<value::signed-little-32>>
  defp pack_int(value, :int64, _), do: <<value::signed-little-64>>
  defp pack_int(value, :uint8, _), do: <<value::unsigned-little-8>>
  defp pack_int(value, :uint16, _), do: <<value::unsigned-little-16>>
  defp pack_int(value, :uint32, _), do: <<value::unsigned-little-32>>

  @doc false
  defp pack_float(value, :float32, _), do: <<value::float-little-32>>
  defp pack_float(value, :float64, _), do: <<value::float-little-64>>

  @doc false
  defp clamp_to_int_range(value, :int16),
    do: max(-32_768, min(32_767, value))

  defp clamp_to_int_range(value, :int32),
    do: max(-2_147_483_648, min(2_147_483_647, value))

  defp clamp_to_int_range(value, :int64),
    do: value

  defp clamp_to_int_range(value, :uint8),
    do: max(0, min(255, value))

  defp clamp_to_int_range(value, :uint16),
    do: max(0, min(65_535, value))

  defp clamp_to_int_range(value, :uint32),
    do: max(0, min(4_294_967_295, value))

  # Bitround codec implementation
  @doc false
  defp bitround_encode(data, dtype, keepbits) do
    if byte_size(data) == 0 do
      {:ok, <<>>}
    else
      itemsize = ExZarr.DataType.itemsize(dtype)
      num_elements = div(byte_size(data), itemsize)

      rounded =
        for i <- 0..(num_elements - 1), into: <<>> do
          offset_bytes = i * itemsize
          <<_::binary-size(offset_bytes), element::binary-size(itemsize), _::binary>> = data
          round_mantissa_bits(element, dtype, keepbits)
        end

      {:ok, rounded}
    end
  end

  @doc false
  defp bitround_decode(data, _dtype, _keepbits) do
    # Bitround is lossy - decoding is a no-op
    {:ok, data}
  end

  @doc false
  defp round_mantissa_bits(<<_::binary>> = element, :float32, keepbits) do
    # Float32: 1 sign bit, 8 exponent bits, 23 mantissa bits
    # Read as 32-bit integer to manipulate bits, then convert back to float
    <<int_bits::unsigned-little-32>> = element

    # Round by zeroing lower (23 - keepbits) mantissa bits
    if keepbits >= 23 do
      element
    else
      mask_bits = 23 - keepbits
      # Create mask that zeros out lower mantissa bits
      # The mantissa is the lower 23 bits of the float
      mask = bnot((1 <<< mask_bits) - 1) &&& 0xFFFFFFFF
      rounded_bits = int_bits &&& mask
      <<rounded_bits::unsigned-little-32>>
    end
  end

  defp round_mantissa_bits(<<_::binary>> = element, :float64, keepbits) do
    # Float64: 1 sign bit, 11 exponent bits, 52 mantissa bits
    # Read as 64-bit integer to manipulate bits, then convert back to float
    <<int_bits::unsigned-little-64>> = element

    # Round by zeroing lower (52 - keepbits) mantissa bits
    if keepbits >= 52 do
      element
    else
      mask_bits = 52 - keepbits
      # Create mask that zeros out lower mantissa bits
      mask = bnot((1 <<< mask_bits) - 1) &&& 0xFFFFFFFFFFFFFFFF
      rounded_bits = int_bits &&& mask
      <<rounded_bits::unsigned-little-64>>
    end
  end

  defp round_mantissa_bits(element, _dtype, _keepbits), do: element

  # Gzip compression/decompression helpers
  # Use actual gzip format (RFC 1952) not zlib format (RFC 1950)

  @doc false
  defp gzip_compress(data, level) when is_binary(data) do
    z = :zlib.open()

    try do
      # windowBits = 16 + 15 enables gzip format
      # 15 is the max window size, +16 adds gzip wrapper
      :ok = :zlib.deflateInit(z, level, :deflated, 16 + 15, 8, :default)
      compressed = :zlib.deflate(z, data, :finish)
      :ok = :zlib.deflateEnd(z)
      {:ok, IO.iodata_to_binary(compressed)}
    catch
      kind, reason ->
        {:error, {:gzip_compression_failed, {kind, reason}}}
    after
      :zlib.close(z)
    end
  end

  @doc false
  defp gzip_decompress(data) when is_binary(data) do
    z = :zlib.open()

    try do
      # windowBits = 16 + 15 enables gzip format
      :ok = :zlib.inflateInit(z, 16 + 15)
      decompressed = :zlib.inflate(z, data)
      :ok = :zlib.inflateEnd(z)
      {:ok, IO.iodata_to_binary(decompressed)}
    catch
      kind, reason ->
        {:error, {:gzip_decompression_failed, {kind, reason}}}
    after
      :zlib.close(z)
    end
  end
end
