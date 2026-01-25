defmodule ExZarr.Codecs.ShardingIndexed do
  @moduledoc """
  Implements the Zarr v3 sharding-indexed codec.

  Sharding combines multiple logical chunks into single physical shard files,
  dramatically reducing metadata overhead for cloud storage systems.

  ## Benefits

  - **Reduced cloud API calls**: 100 chunks in 1 shard = 99% fewer S3 requests
  - **Lower metadata overhead**: Less filesystem or object storage metadata
  - **Better caching**: Larger units suitable for block-based caching

  ## Shard Structure

  Per the Zarr v3 specification:

      [Chunk 0 data][Chunk 1 data]...[Chunk N data][Index][Index Size (8 bytes)]

  The index is a list of (offset, size) pairs for each chunk, encoded as
  little-endian uint64 pairs. The last 8 bytes store the index size.

  ## Configuration

    * `:chunk_shape` - Tuple defining shard dimensions in chunks (e.g., `{10, 10}`)
    * `:codecs` - Codec pipeline for individual chunks within the shard
    * `:index_codecs` - Codec pipeline for the shard index (default: bytes + crc32c)
    * `:index_location` - `:start` or `:end` (default: `:end`)

  ## Example

      config = %{
        "chunk_shape" => [10, 10],
        "codecs" => [
          %{name: "bytes"},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        "index_codecs" => [
          %{name: "bytes"},
          %{name: "crc32c"}
        ],
        "index_location" => "end"
      }

      {:ok, shard_codec} = ShardingIndexed.init(config)

      # Encode multiple chunks into shard
      chunks = %{
        {0, 0} => <<1, 2, 3, 4>>,
        {0, 1} => <<5, 6, 7, 8>>,
        {1, 0} => <<9, 10, 11, 12>>
      }
      {:ok, shard_binary} = ShardingIndexed.encode(chunks, shard_codec)

      # Extract specific chunk from shard
      {:ok, chunk_data} = ShardingIndexed.decode_chunk(shard_binary, {0, 1}, shard_codec)

      # Decode all chunks from shard
      {:ok, all_chunks} = ShardingIndexed.decode(shard_binary, shard_codec)

  ## Specification

  Zarr v3 Sharding Extension:
  https://zarr-specs.readthedocs.io/en/latest/v3/codecs/sharding-indexed/v1.0.html
  """

  alias ExZarr.Codecs.PipelineV3

  @type chunk_index :: tuple()
  @type chunk_data :: binary()
  @type chunks_map :: %{chunk_index() => chunk_data()}
  @type shard_binary :: binary()
  @type shard_index :: %{
          chunk_offsets: %{
            chunk_index() => {offset :: non_neg_integer(), size :: non_neg_integer()}
          },
          chunk_indices: [chunk_index()]
        }
  @type index_location :: :start | :end

  @type t :: %__MODULE__{
          chunk_shape: tuple(),
          codecs: [map()],
          index_codecs: [map()],
          index_location: index_location()
        }

  defstruct [:chunk_shape, :codecs, :index_codecs, :index_location]

  @doc """
  Initializes the sharding codec with configuration.

  ## Parameters

    * `config` - Configuration map with chunk_shape, codecs, index_codecs, index_location

  ## Returns

    * `{:ok, codec}` - Initialized codec struct
    * `{:error, reason}` - Invalid configuration
  """
  @spec init(map()) :: {:ok, t()} | {:error, term()}
  def init(config) when is_map(config) do
    with {:ok, chunk_shape} <- parse_chunk_shape(config),
         {:ok, codecs} <- parse_codecs(config),
         {:ok, index_codecs} <- parse_index_codecs(config),
         {:ok, index_location} <- parse_index_location(config) do
      {:ok,
       %__MODULE__{
         chunk_shape: chunk_shape,
         codecs: codecs,
         index_codecs: index_codecs,
         index_location: index_location
       }}
    end
  end

  @doc """
  Encodes multiple chunks into a shard with embedded index.

  ## Parameters

    * `chunks` - Map of chunk_index => binary_data
    * `codec` - Initialized sharding codec

  ## Returns

    * `{:ok, shard_binary}` - Shard with chunks and index
    * `{:error, reason}` - Encoding failure
  """
  @spec encode(chunks_map(), t()) :: {:ok, shard_binary()} | {:error, term()}
  def encode(chunks, %__MODULE__{} = codec) when is_map(chunks) do
    with {:ok, encoded_chunks} <- encode_individual_chunks(chunks, codec.codecs),
         {:ok, shard_data, index} <- pack_chunks_into_shard(encoded_chunks),
         {:ok, encoded_index} <- encode_index(index, codec.index_codecs) do
      embed_index(shard_data, encoded_index, codec.index_location)
    end
  end

  @doc """
  Decodes specific chunk from shard.

  ## Parameters

    * `shard_binary` - The shard data
    * `chunk_index` - Index of chunk to extract
    * `codec` - Initialized sharding codec

  ## Returns

    * `{:ok, chunk_data}` - Decoded chunk data
    * `{:error, reason}` - Decoding failure or chunk not found
  """
  @spec decode_chunk(shard_binary(), chunk_index(), t()) :: {:ok, chunk_data()} | {:error, term()}
  def decode_chunk(shard_binary, chunk_index, %__MODULE__{} = codec)
      when is_binary(shard_binary) and is_tuple(chunk_index) do
    with {:ok, index} <- extract_and_decode_index(shard_binary, codec),
         {:ok, chunk_data} <-
           extract_chunk_from_shard(shard_binary, chunk_index, index, codec.index_location) do
      decode_individual_chunk(chunk_data, codec.codecs)
    end
  end

  @doc """
  Decodes all chunks from shard into a map.

  ## Parameters

    * `shard_binary` - The shard data
    * `codec` - Initialized sharding codec

  ## Returns

    * `{:ok, chunks_map}` - Map of chunk_index => decoded_data
    * `{:error, reason}` - Decoding failure
  """
  @spec decode(shard_binary(), t()) :: {:ok, chunks_map()} | {:error, term()}
  def decode(shard_binary, %__MODULE__{} = codec) when is_binary(shard_binary) do
    with {:ok, index} <- extract_and_decode_index(shard_binary, codec) do
      extract_all_chunks(shard_binary, index, codec.index_location, codec.codecs)
    end
  end

  # Private helper functions

  defp parse_chunk_shape(%{"chunk_shape" => shape}) when is_list(shape) do
    {:ok, List.to_tuple(shape)}
  end

  defp parse_chunk_shape(%{chunk_shape: shape}) when is_tuple(shape) do
    {:ok, shape}
  end

  defp parse_chunk_shape(_), do: {:error, :missing_chunk_shape}

  defp parse_codecs(%{"codecs" => codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_codecs(%{codecs: codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_codecs(_), do: {:error, :missing_codecs}

  defp parse_index_codecs(%{"index_codecs" => codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_index_codecs(%{index_codecs: codecs}) when is_list(codecs), do: {:ok, codecs}

  defp parse_index_codecs(_) do
    # Default index codecs: bytes + crc32c
    {:ok,
     [
       %{"name" => "bytes", "configuration" => %{}},
       %{"name" => "crc32c", "configuration" => %{}}
     ]}
  end

  defp parse_index_location(%{"index_location" => "start"}), do: {:ok, :start}
  defp parse_index_location(%{"index_location" => "end"}), do: {:ok, :end}
  defp parse_index_location(%{index_location: :start}), do: {:ok, :start}
  defp parse_index_location(%{index_location: :end}), do: {:ok, :end}
  # Default to end
  defp parse_index_location(_), do: {:ok, :end}

  # Encode individual chunks using the chunk codec pipeline
  defp encode_individual_chunks(chunks, codecs) do
    Enum.reduce_while(chunks, {:ok, %{}}, fn {chunk_idx, chunk_data}, {:ok, acc} ->
      case apply_codecs(chunk_data, codecs, :encode) do
        {:ok, encoded} -> {:cont, {:ok, Map.put(acc, chunk_idx, encoded)}}
        error -> {:halt, error}
      end
    end)
  end

  # Pack encoded chunks into shard data and build index
  defp pack_chunks_into_shard(encoded_chunks) do
    # Sort chunks by index for consistent ordering
    sorted_chunks = Enum.sort(encoded_chunks)

    {shard_data, offsets, chunk_indices} =
      Enum.reduce(sorted_chunks, {<<>>, %{}, []}, fn {chunk_idx, chunk_data},
                                                     {data_acc, index_acc, indices_acc} ->
        offset = byte_size(data_acc)
        size = byte_size(chunk_data)
        new_data = <<data_acc::binary, chunk_data::binary>>
        new_index = Map.put(index_acc, chunk_idx, {offset, size})
        new_indices = indices_acc ++ [chunk_idx]
        {new_data, new_index, new_indices}
      end)

    {:ok, shard_data, %{chunk_offsets: offsets, chunk_indices: chunk_indices}}
  end

  # Encode index as binary
  defp encode_index(index, index_codecs) do
    index_binary = encode_index_to_binary(index)
    apply_codecs(index_binary, index_codecs, :encode)
  end

  # Convert index structure to binary format (little-endian uint64 pairs + chunk indices)
  defp encode_index_to_binary(%{chunk_offsets: offsets, chunk_indices: indices}) do
    # First encode the number of chunks
    num_chunks = length(indices)

    # Encode chunk indices metadata (dimensions and values)
    indices_binary =
      for chunk_idx <- indices, into: <<>> do
        # Encode tuple size and values
        idx_list = Tuple.to_list(chunk_idx)
        dim_count = length(idx_list)

        dim_header = <<dim_count::little-unsigned-32>>

        idx_values =
          for val <- idx_list, into: <<>> do
            <<val::little-signed-32>>
          end

        <<dim_header::binary, idx_values::binary>>
      end

    # Encode offset/size pairs in the same order as indices
    offsets_binary =
      for chunk_idx <- indices, into: <<>> do
        {offset, size} = Map.fetch!(offsets, chunk_idx)
        <<offset::little-unsigned-64, size::little-unsigned-64>>
      end

    # Format: [num_chunks][indices_binary][offsets_binary]
    <<num_chunks::little-unsigned-32, indices_binary::binary, offsets_binary::binary>>
  end

  # Embed index into shard at specified location
  defp embed_index(shard_data, encoded_index, :end) do
    index_size = byte_size(encoded_index)
    {:ok, <<shard_data::binary, encoded_index::binary, index_size::little-unsigned-64>>}
  end

  defp embed_index(shard_data, encoded_index, :start) do
    index_size = byte_size(encoded_index)
    {:ok, <<index_size::little-unsigned-64, encoded_index::binary, shard_data::binary>>}
  end

  # Extract and decode index from shard
  defp extract_and_decode_index(shard_binary, %{index_location: :end, index_codecs: codecs}) do
    total_size = byte_size(shard_binary)

    # Last 8 bytes contain index size
    <<_::binary-size(total_size - 8), index_size::little-unsigned-64>> = shard_binary

    # Extract index
    data_size = total_size - 8 - index_size

    <<_data::binary-size(data_size), index_binary::binary-size(index_size), _::binary>> =
      shard_binary

    # Decode and parse index
    with {:ok, decoded_index} <- apply_codecs(index_binary, codecs, :decode) do
      parse_index_binary(decoded_index)
    end
  end

  defp extract_and_decode_index(shard_binary, %{index_location: :start, index_codecs: codecs}) do
    # First 8 bytes contain index size
    <<index_size::little-unsigned-64, rest::binary>> = shard_binary
    <<index_binary::binary-size(index_size), _data::binary>> = rest

    # Decode and parse index
    with {:ok, decoded_index} <- apply_codecs(index_binary, codecs, :decode) do
      parse_index_binary(decoded_index)
    end
  end

  # Parse binary index back to structure
  defp parse_index_binary(<<num_chunks::little-unsigned-32, rest::binary>>) do
    # Parse chunk indices
    {chunk_indices, offsets_binary} = parse_chunk_indices(rest, num_chunks, [])

    # Parse offset/size pairs
    offsets =
      for {chunk_idx, <<offset::little-unsigned-64, size::little-unsigned-64>>} <-
            Enum.zip(chunk_indices, chunk_offsets_list(offsets_binary)),
          into: %{} do
        {chunk_idx, {offset, size}}
      end

    {:ok, %{chunk_offsets: offsets, chunk_indices: chunk_indices}}
  end

  # Helper to parse chunk indices with variable dimensions
  defp parse_chunk_indices(binary, 0, acc), do: {Enum.reverse(acc), binary}

  defp parse_chunk_indices(<<dim_count::little-unsigned-32, rest::binary>>, remaining, acc) do
    # Extract dim_count signed integers
    # 4 bytes per int32
    idx_size = dim_count * 4
    <<idx_binary::binary-size(idx_size), rest2::binary>> = rest

    idx_list =
      for <<val::little-signed-32 <- idx_binary>> do
        val
      end

    chunk_idx = List.to_tuple(idx_list)
    parse_chunk_indices(rest2, remaining - 1, [chunk_idx | acc])
  end

  # Helper to split offsets binary into list of binaries (16 bytes each)
  defp chunk_offsets_list(binary) do
    for <<pair::binary-size(16) <- binary>>, do: pair
  end

  # Extract specific chunk data from shard using index
  defp extract_chunk_from_shard(shard_binary, chunk_index, index, index_location) do
    case Map.get(index.chunk_offsets, chunk_index) do
      {offset, size} ->
        data_binary = extract_data_portion(shard_binary, index_location, index)

        if offset + size <= byte_size(data_binary) do
          <<_skip::binary-size(offset), chunk_data::binary-size(size), _rest::binary>> =
            data_binary

          {:ok, chunk_data}
        else
          {:error, {:invalid_chunk_offset, chunk_index}}
        end

      nil ->
        {:error, {:chunk_not_found, chunk_index}}
    end
  end

  # Extract the data portion of shard (excluding index)
  defp extract_data_portion(shard_binary, :end, _index) do
    total_size = byte_size(shard_binary)
    <<_::binary-size(total_size - 8), index_size::little-unsigned-64>> = shard_binary
    data_size = total_size - 8 - index_size
    <<data::binary-size(data_size), _::binary>> = shard_binary
    data
  end

  defp extract_data_portion(shard_binary, :start, _index) do
    <<index_size::little-unsigned-64, rest::binary>> = shard_binary
    <<_index::binary-size(index_size), data::binary>> = rest
    data
  end

  # Extract all chunks from shard
  defp extract_all_chunks(shard_binary, index, index_location, codecs) do
    data_binary = extract_data_portion(shard_binary, index_location, index)

    Enum.reduce_while(index.chunk_offsets, {:ok, %{}}, fn {chunk_idx, {offset, size}},
                                                          {:ok, acc} ->
      if offset + size <= byte_size(data_binary) do
        <<_skip::binary-size(offset), chunk_data::binary-size(size), _rest::binary>> = data_binary

        case decode_individual_chunk(chunk_data, codecs) do
          {:ok, decoded} -> {:cont, {:ok, Map.put(acc, chunk_idx, decoded)}}
          error -> {:halt, error}
        end
      else
        {:halt, {:error, {:invalid_chunk_offset, chunk_idx}}}
      end
    end)
  end

  # Decode individual chunk using codec pipeline
  defp decode_individual_chunk(chunk_data, codecs) do
    apply_codecs(chunk_data, codecs, :decode)
  end

  # Apply codec pipeline (forward or reverse)
  defp apply_codecs(data, codecs, :encode) do
    normalized_codecs = normalize_codecs(codecs)

    case PipelineV3.parse_codecs(normalized_codecs) do
      {:ok, pipeline} -> PipelineV3.encode(data, pipeline)
      error -> error
    end
  end

  defp apply_codecs(data, codecs, :decode) do
    normalized_codecs = normalize_codecs(codecs)

    case PipelineV3.parse_codecs(normalized_codecs) do
      {:ok, pipeline} -> PipelineV3.decode(data, pipeline)
      error -> error
    end
  end

  # Normalize codec format to use atom keys expected by PipelineV3
  defp normalize_codecs(codecs) when is_list(codecs) do
    Enum.map(codecs, fn codec ->
      %{
        name: Map.get(codec, "name") || Map.get(codec, :name),
        configuration: Map.get(codec, "configuration") || Map.get(codec, :configuration, %{})
      }
    end)
  end
end
