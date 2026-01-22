defmodule ExZarr.Array do
  @moduledoc """
  N-dimensional array implementation with chunking and compression support.

  Arrays are the core data structure in ExZarr. They support:
  - Arbitrary N-dimensional shapes
  - Chunked storage for efficient I/O
  - Various compression codecs
  - Concurrent access via GenServer
  """

  use GenServer
  alias ExZarr.{Codecs, Storage, Metadata, Chunk}

  @type t :: %__MODULE__{
          shape: tuple(),
          chunks: tuple(),
          dtype: ExZarr.dtype(),
          compressor: ExZarr.compressor(),
          fill_value: number() | nil,
          storage: Storage.t(),
          metadata: Metadata.t()
        }

  defstruct [
    :shape,
    :chunks,
    :dtype,
    :compressor,
    :fill_value,
    :storage,
    :metadata
  ]

  ## Public API

  @doc """
  Creates a new array with the specified configuration.
  """
  @spec create(keyword()) :: {:ok, t()} | {:error, term()}
  def create(opts) do
    with {:ok, config} <- validate_config(opts),
         {:ok, storage} <- Storage.init(config),
         {:ok, metadata} <- Metadata.create(config) do
      array = struct(__MODULE__, Map.put(config, :storage, storage) |> Map.put(:metadata, metadata))
      {:ok, array}
    end
  end

  @doc """
  Opens an existing array from storage.
  """
  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts) do
    with {:ok, storage} <- Storage.open(opts),
         {:ok, metadata} <- Storage.read_metadata(storage) do
      array = %__MODULE__{
        shape: metadata.shape,
        chunks: metadata.chunks,
        dtype: metadata.dtype,
        compressor: metadata.compressor,
        fill_value: metadata.fill_value,
        storage: storage,
        metadata: metadata
      }

      {:ok, array}
    end
  end

  @doc """
  Saves the array to storage.
  """
  @spec save(t(), keyword()) :: :ok | {:error, term()}
  def save(array, opts) do
    Storage.write_metadata(array.storage, array.metadata, opts)
  end

  @doc """
  Gets a slice of data from the array.

  ## Examples

      {:ok, data} = ExZarr.Array.get_slice(array,
        start: {0, 0},
        stop: {100, 100}
      )
  """
  @spec get_slice(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get_slice(array, opts) do
    start = Keyword.get(opts, :start, tuple_of_zeros(array.shape))
    stop = Keyword.get(opts, :stop, array.shape)

    with {:ok, chunk_indices} <- calculate_chunk_indices(array, start, stop),
         {:ok, chunks} <- read_chunks(array, chunk_indices),
         {:ok, data} <- assemble_slice(array, chunks, start, stop) do
      {:ok, data}
    end
  end

  @doc """
  Sets a slice of data in the array.

  ## Examples

      :ok = ExZarr.Array.set_slice(array, data, start: {0, 0})
  """
  @spec set_slice(t(), binary(), keyword()) :: :ok | {:error, term()}
  def set_slice(array, data, opts) do
    start = Keyword.get(opts, :start, tuple_of_zeros(array.shape))

    with {:ok, chunk_indices} <- calculate_chunk_indices_for_write(array, data, start),
         {:ok, chunks} <- split_into_chunks(array, data, start),
         :ok <- write_chunks(array, chunks, chunk_indices) do
      :ok
    end
  end

  @doc """
  Converts the entire array to a binary.
  """
  @spec to_binary(t()) :: {:ok, binary()} | {:error, term()}
  def to_binary(array) do
    get_slice(array, start: tuple_of_zeros(array.shape), stop: array.shape)
  end

  @doc """
  Returns the number of dimensions in the array.
  """
  @spec ndim(t()) :: non_neg_integer()
  def ndim(array), do: tuple_size(array.shape)

  @doc """
  Returns the total number of elements in the array.
  """
  @spec size(t()) :: non_neg_integer()
  def size(array) do
    array.shape
    |> Tuple.to_list()
    |> Enum.reduce(1, &(&1 * &2))
  end

  @doc """
  Returns the size of each element in bytes.
  """
  @spec itemsize(t()) :: non_neg_integer()
  def itemsize(array) do
    dtype_size(array.dtype)
  end

  ## Private Functions

  defp validate_config(opts) do
    with {:ok, shape} <- validate_shape(opts[:shape]),
         {:ok, chunks} <- validate_chunks(opts[:chunks], shape) do
      config = %{
        shape: shape,
        chunks: chunks,
        dtype: Keyword.get(opts, :dtype, :float64),
        compressor: Keyword.get(opts, :compressor, :zstd),
        fill_value: Keyword.get(opts, :fill_value, 0),
        storage_type: Keyword.get(opts, :storage, :memory),
        path: opts[:path]
      }

      {:ok, config}
    end
  end

  defp validate_shape(nil), do: {:error, :shape_required}
  defp validate_shape(shape) when is_tuple(shape) and tuple_size(shape) > 0 do
    if Enum.all?(Tuple.to_list(shape), &(is_integer(&1) and &1 > 0)) do
      {:ok, shape}
    else
      {:error, :invalid_shape}
    end
  end
  defp validate_shape(_), do: {:error, :invalid_shape}

  defp validate_chunks(nil, _shape), do: {:error, :chunks_required}
  defp validate_chunks(chunks, shape) when is_tuple(chunks) do
    if tuple_size(chunks) == tuple_size(shape) and
         Enum.all?(Tuple.to_list(chunks), &(is_integer(&1) and &1 > 0)) do
      {:ok, chunks}
    else
      {:error, :invalid_chunks}
    end
  end
  defp validate_chunks(_, _), do: {:error, :invalid_chunks}

  defp tuple_of_zeros(shape) do
    size = tuple_size(shape)
    0
    |> List.duplicate(size)
    |> List.to_tuple()
  end

  defp calculate_chunk_indices(_array, _start, _stop) do
    # TODO: Implement chunk index calculation
    {:ok, []}
  end

  defp calculate_chunk_indices_for_write(_array, _data, _start) do
    # TODO: Implement chunk index calculation for writes
    {:ok, []}
  end

  defp read_chunks(array, chunk_indices) do
    chunks =
      chunk_indices
      |> Enum.map(fn index ->
        case Storage.read_chunk(array.storage, index) do
          {:ok, compressed_data} ->
            Codecs.decompress(compressed_data, array.compressor)

          {:error, :not_found} ->
            {:ok, create_fill_chunk(array)}
        end
      end)
      |> Enum.map(fn
        {:ok, data} -> data
        {:error, reason} -> {:error, reason}
      end)

    if Enum.any?(chunks, &match?({:error, _}, &1)) do
      {:error, :read_failed}
    else
      {:ok, chunks}
    end
  end

  defp write_chunks(array, chunks, indices) do
    results =
      Enum.zip(chunks, indices)
      |> Enum.map(fn {chunk_data, index} ->
        with {:ok, compressed} <- Codecs.compress(chunk_data, array.compressor) do
          Storage.write_chunk(array.storage, index, compressed)
        end
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, :write_failed}
    end
  end

  defp split_into_chunks(_array, _data, _start) do
    # TODO: Implement data splitting into chunks
    {:ok, []}
  end

  defp assemble_slice(_array, _chunks, _start, _stop) do
    # TODO: Implement slice assembly from chunks
    {:ok, <<>>}
  end

  defp create_fill_chunk(array) do
    chunk_size =
      array.chunks
      |> Tuple.to_list()
      |> Enum.reduce(1, &(&1 * &2))

    element_size = dtype_size(array.dtype)
    fill_bytes = encode_fill_value(array.fill_value, array.dtype)

    List.duplicate(fill_bytes, chunk_size)
    |> IO.iodata_to_binary()
  end

  defp encode_fill_value(value, :int8), do: <<value::signed-8>>
  defp encode_fill_value(value, :int16), do: <<value::signed-little-16>>
  defp encode_fill_value(value, :int32), do: <<value::signed-little-32>>
  defp encode_fill_value(value, :int64), do: <<value::signed-little-64>>
  defp encode_fill_value(value, :uint8), do: <<value::unsigned-8>>
  defp encode_fill_value(value, :uint16), do: <<value::unsigned-little-16>>
  defp encode_fill_value(value, :uint32), do: <<value::unsigned-little-32>>
  defp encode_fill_value(value, :uint64), do: <<value::unsigned-little-64>>
  defp encode_fill_value(value, :float32), do: <<value::float-little-32>>
  defp encode_fill_value(value, :float64), do: <<value::float-little-64>>

  defp dtype_size(:int8), do: 1
  defp dtype_size(:uint8), do: 1
  defp dtype_size(:int16), do: 2
  defp dtype_size(:uint16), do: 2
  defp dtype_size(:int32), do: 4
  defp dtype_size(:uint32), do: 4
  defp dtype_size(:int64), do: 8
  defp dtype_size(:uint64), do: 8
  defp dtype_size(:float32), do: 4
  defp dtype_size(:float64), do: 8
end
