defmodule ExZarr.Array do
  @moduledoc """
  N-dimensional array implementation with chunking and compression support.

  Arrays are the core data structure in ExZarr. They provide:

  - Arbitrary N-dimensional shapes (1D to N-D)
  - Chunked storage for efficient I/O and memory usage
  - Compression using various codecs (zlib, zstd, lz4, or none)
  - Support for 10 data types (integers, unsigned integers, and floats)
  - Persistent storage on filesystem or temporary in-memory storage
  - Lazy loading of chunks (only reads what is needed)

  ## Array Structure

  An array consists of:

  - **Shape**: The dimensions of the array (e.g., `{1000, 1000}` for a 2D array)
  - **Chunks**: The size of each chunk for storage (e.g., `{100, 100}`)
  - **Dtype**: The data type of elements (e.g., `:float64`, `:int32`)
  - **Compressor**: The compression codec used for chunks
  - **Fill value**: The default value for uninitialized elements

  ## Memory Efficiency

  Arrays use chunked storage to avoid loading entire arrays into memory.
  Only the chunks needed for a specific operation are loaded and decompressed.
  This allows working with arrays larger than available RAM.

  ## Examples

      # Create a 2D array
      {:ok, array} = ExZarr.Array.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        storage: :memory
      )

      # Query array properties
      ExZarr.Array.ndim(array)     # => 2
      ExZarr.Array.size(array)     # => 1000000
      ExZarr.Array.itemsize(array) # => 8 (bytes per float64)

      # Convert to binary
      {:ok, data} = ExZarr.Array.to_binary(array)
  """

  use GenServer
  alias ExZarr.{Codecs, Metadata, Storage}

  @impl GenServer
  def init(init_arg) do
    {:ok, init_arg}
  end

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

  Initializes a new Zarr array with the given shape, chunk size, data type,
  and compression settings. The array can be stored in memory or on the filesystem.

  ## Options

  - `:shape` - Tuple specifying array dimensions (required)
  - `:chunks` - Tuple specifying chunk dimensions (required)
  - `:dtype` - Data type (default: `:float64`)
  - `:compressor` - Compression codec (default: `:zstd`)
  - `:storage` - Storage backend (default: `:memory`)
  - `:path` - Path for filesystem storage
  - `:fill_value` - Fill value for uninitialized chunks (default: `0`)

  ## Examples

      # Simple 1D array
      {:ok, array} = ExZarr.Array.create(
        shape: {1000},
        chunks: {100}
      )

      # 2D array with specific dtype
      {:ok, array} = ExZarr.Array.create(
        shape: {500, 500},
        chunks: {50, 50},
        dtype: :int32,
        compressor: :zlib
      )

      # Array on filesystem
      {:ok, array} = ExZarr.Array.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        storage: :filesystem,
        path: "/tmp/my_array"
      )

  ## Returns

  - `{:ok, array}` on success
  - `{:error, reason}` on failure
  """
  @spec create(keyword()) :: {:ok, t()} | {:error, term()}
  def create(opts) do
    with {:ok, config} <- validate_config(opts),
         {:ok, storage} <- Storage.init(config),
         {:ok, metadata} <- Metadata.create(config) do
      array =
        struct(__MODULE__, Map.put(config, :storage, storage) |> Map.put(:metadata, metadata))

      {:ok, array}
    end
  end

  @doc """
  Opens an existing array from storage.

  Reads the array metadata from storage and initializes the array structure.
  The array must have been previously saved using ExZarr or another Zarr v2
  compatible implementation.

  ## Options

  - `:path` - Path to the array directory (required)
  - `:storage` - Storage backend (default: `:filesystem`)

  ## Examples

      # Open array from filesystem
      {:ok, array} = ExZarr.Array.open(path: "/tmp/my_array")

  ## Returns

  - `{:ok, array}` on success
  - `{:error, :path_not_found}` if path does not exist
  - `{:error, :metadata_not_found}` if .zarray file is missing
  - `{:error, reason}` for other failures
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
  Saves the array metadata to storage.

  Writes the array configuration to a `.zarray` file in the storage location.
  This persists the array structure, allowing it to be reopened later.
  Note that chunk data is written separately when chunks are modified.

  ## Options

  - `:path` - Path where metadata should be written (for new filesystem storage)

  ## Examples

      {:ok, array} = ExZarr.Array.create(shape: {1000}, chunks: {100})
      :ok = ExZarr.Array.save(array, path: "/tmp/my_array")

  ## Returns

  - `:ok` on success
  - `{:ok, storage}` for in-memory storage (returns updated storage)
  - `{:error, reason}` on failure
  """
  @spec save(t(), keyword()) :: :ok | {:error, term()}
  def save(array, opts) do
    Storage.write_metadata(array.storage, array.metadata, opts)
  end

  @doc """
  Gets a slice of data from the array.

  Reads a rectangular region from the array. Only the chunks that overlap
  with the requested region are loaded and decompressed. This allows efficient
  access to subsets of large arrays.

  ## Options

  - `:start` - Starting index for each dimension (default: all zeros)
  - `:stop` - Stopping index for each dimension (default: array shape)

  ## Examples

      # Read a 100x100 region from a larger array
      {:ok, data} = ExZarr.Array.get_slice(array,
        start: {0, 0},
        stop: {100, 100}
      )

      # Read entire first row of a 2D array
      {:ok, data} = ExZarr.Array.get_slice(array,
        start: {0, 0},
        stop: {1, 1000}
      )

  ## Returns

  - `{:ok, binary}` containing the requested data in row-major order
  - `{:error, reason}` on failure
  """
  @spec get_slice(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get_slice(array, opts) do
    start = Keyword.get(opts, :start, tuple_of_zeros(array.shape))
    stop = Keyword.get(opts, :stop, array.shape)

    with {:ok, chunk_indices} <- calculate_chunk_indices(array, start, stop),
         {:ok, chunks} <- read_chunks(array, chunk_indices) do
      assemble_slice(array, chunks, start, stop)
    end
  end

  @doc """
  Sets a slice of data in the array.

  Writes data to a rectangular region in the array. The data is automatically
  split into chunks, compressed, and written to storage. Only the affected
  chunks are modified.

  ## Parameters

  - `array` - The array to write to
  - `data` - Binary data to write (must match region size and dtype)
  - `opts` - Options including `:start` and `:stop` indices

  ## Options

  - `:start` - Starting index for the write (default: all zeros)
  - `:stop` - Stopping index for the write (required for correct multi-dimensional writes)

  ## Examples

      # Write 10x10 block of data
      data = <<...>>  # 100 int32 values = 400 bytes
      :ok = ExZarr.Array.set_slice(array, data,
        start: {0, 0},
        stop: {10, 10}
      )

      # Write to beginning of 1D array
      data = <<...>>  # 100 int32 values
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec set_slice(t(), binary(), keyword()) :: :ok | {:error, term()}
  def set_slice(array, data, opts) do
    start = Keyword.get(opts, :start, tuple_of_zeros(array.shape))
    stop = Keyword.get(opts, :stop)

    # Calculate stop from data size if not provided (for 1D arrays)
    stop =
      if stop do
        stop
      else
        calculate_stop_from_data(array, data, start)
      end

    with {:ok, chunk_indices} <- calculate_chunk_indices(array, start, stop),
         {:ok, chunks} <- split_into_chunks(array, data, start, stop) do
      write_chunks(array, chunks, chunk_indices)
    end
  end

  @doc """
  Converts the entire array to a binary.

  Reads all chunks from the array and assembles them into a single binary
  in row-major (C-order) format. This is useful for loading complete arrays
  but may use significant memory for large arrays.

  ## Examples

      {:ok, array} = ExZarr.Array.create(shape: {10, 10}, chunks: {5, 5})
      {:ok, data} = ExZarr.Array.to_binary(array)
      # data is a binary with 10 * 10 * itemsize bytes

  ## Returns

  - `{:ok, binary}` containing all array data
  - `{:error, reason}` on failure

  ## Memory Warning

  This loads the entire array into memory. For a `{1000, 1000}` array of
  `:float64`, this requires 8MB of memory.
  """
  @spec to_binary(t()) :: {:ok, binary()} | {:error, term()}
  def to_binary(array) do
    get_slice(array, start: tuple_of_zeros(array.shape), stop: array.shape)
  end

  @doc """
  Returns the number of dimensions in the array.

  ## Examples

      {:ok, array} = ExZarr.Array.create(shape: {100, 200, 300}, chunks: {10, 20, 30})
      ExZarr.Array.ndim(array)
      # => 3

  ## Returns

  Integer indicating the number of dimensions (1 for 1D, 2 for 2D, etc.)
  """
  @spec ndim(t()) :: non_neg_integer()
  def ndim(array), do: tuple_size(array.shape)

  @doc """
  Returns the total number of elements in the array.

  Calculates the product of all dimensions in the shape.

  ## Examples

      {:ok, array} = ExZarr.Array.create(shape: {100, 200}, chunks: {10, 20})
      ExZarr.Array.size(array)
      # => 20000 (100 * 200)

  ## Returns

  Non-negative integer representing total element count.
  """
  @spec size(t()) :: non_neg_integer()
  def size(array) do
    array.shape
    |> Tuple.to_list()
    |> Enum.reduce(1, &(&1 * &2))
  end

  @doc """
  Returns the size of each element in bytes.

  Different data types have different sizes:
  - `:int8`, `:uint8` - 1 byte
  - `:int16`, `:uint16` - 2 bytes
  - `:int32`, `:uint32`, `:float32` - 4 bytes
  - `:int64`, `:uint64`, `:float64` - 8 bytes

  ## Examples

      {:ok, array} = ExZarr.Array.create(
        shape: {100},
        chunks: {10},
        dtype: :float64
      )
      ExZarr.Array.itemsize(array)
      # => 8

      {:ok, array} = ExZarr.Array.create(
        shape: {100},
        chunks: {10},
        dtype: :uint8
      )
      ExZarr.Array.itemsize(array)
      # => 1

  ## Returns

  Integer representing bytes per element (1, 2, 4, or 8).
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

  defp calculate_chunk_indices(array, start, stop) do
    # Use Chunk module to find all chunks that overlap with this slice
    chunk_indices = ExZarr.Chunk.slice_to_chunks(start, stop, array.chunks)
    {:ok, chunk_indices}
  end

  defp calculate_stop_from_start_and_size(start, num_elements, shape) do
    # For now, assume 1D writing (can be extended for multi-dimensional)
    start_list = Tuple.to_list(start)
    shape_list = Tuple.to_list(shape)

    # Calculate how many elements fit in each dimension
    {stop_list, _remaining} =
      Enum.zip(start_list, shape_list)
      |> Enum.reduce({[], num_elements}, fn {start_val, dim_size}, {acc, remaining} ->
        available = dim_size - start_val
        to_use = min(available, remaining)
        {acc ++ [start_val + to_use], remaining - to_use}
      end)

    List.to_tuple(stop_list)
  end

  defp calculate_stop_from_data(array, data, start) do
    element_size = dtype_size(array.dtype)
    num_elements = Kernel.div(byte_size(data), element_size)
    calculate_stop_from_start_and_size(start, num_elements, array.shape)
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

  defp split_into_chunks(array, data, start, stop) do
    # Calculate which chunks are affected
    element_size = dtype_size(array.dtype)

    {:ok, chunk_indices} = calculate_chunk_indices(array, start, stop)

    # For each affected chunk, prepare the data to write
    chunks =
      chunk_indices
      |> Enum.map(fn chunk_index ->
        # Get the bounds of this chunk in array coordinates
        {chunk_start, chunk_stop} =
          ExZarr.Chunk.chunk_bounds(chunk_index, array.chunks, array.shape)

        # Calculate the overlap between the chunk and the write region
        overlap_start = tuple_max(chunk_start, start)
        overlap_stop = tuple_min(chunk_stop, stop)

        # Create or read the existing chunk
        existing_chunk =
          case Storage.read_chunk(array.storage, chunk_index) do
            {:ok, compressed} ->
              case Codecs.decompress(compressed, array.compressor) do
                {:ok, decompressed} -> decompressed
                {:error, _} -> create_fill_chunk(array)
              end

            {:error, :not_found} ->
              create_fill_chunk(array)
          end

        # Modify the chunk with new data
        modified_chunk =
          write_to_chunk(
            existing_chunk,
            data,
            array.chunks,
            chunk_start,
            overlap_start,
            overlap_stop,
            start,
            stop,
            element_size
          )

        modified_chunk
      end)

    {:ok, chunks}
  end

  defp assemble_slice(array, chunks, start, stop) do
    # Calculate the shape of the output slice
    slice_shape =
      Tuple.to_list(start)
      |> Enum.zip(Tuple.to_list(stop))
      |> Enum.map(fn {start_val, stop_val} -> stop_val - start_val end)
      |> List.to_tuple()

    slice_size =
      slice_shape
      |> Tuple.to_list()
      |> Enum.reduce(1, &(&1 * &2))

    element_size = dtype_size(array.dtype)
    output_size = slice_size * element_size

    # Initialize output buffer with fill values
    output = :binary.copy(<<0>>, output_size)

    # Get chunk indices that were read
    {:ok, chunk_indices} = calculate_chunk_indices(array, start, stop)

    # For each chunk, extract the relevant portion and place it in the output
    output =
      Enum.zip(chunks, chunk_indices)
      |> Enum.reduce(output, fn {chunk_data, chunk_index}, acc ->
        # Get the bounds of this chunk
        {chunk_start, chunk_stop} =
          ExZarr.Chunk.chunk_bounds(chunk_index, array.chunks, array.shape)

        # Calculate overlap between chunk and requested slice
        overlap_start = tuple_max(chunk_start, start)
        overlap_stop = tuple_min(chunk_stop, stop)

        # Extract data from chunk and place in output
        extract_and_place_chunk_data(
          acc,
          chunk_data,
          array.chunks,
          slice_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          start,
          element_size
        )
      end)

    {:ok, output}
  end

  defp extract_and_place_chunk_data(
         output,
         chunk_data,
         chunk_shape,
         slice_shape,
         chunk_start,
         overlap_start,
         overlap_stop,
         slice_start,
         element_size
       ) do
    # For simplicity, handle common cases (1D, 2D)
    case tuple_size(chunk_shape) do
      1 ->
        extract_1d(
          output,
          chunk_data,
          chunk_shape,
          slice_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          slice_start,
          element_size
        )

      2 ->
        extract_2d(
          output,
          chunk_data,
          chunk_shape,
          slice_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          slice_start,
          element_size
        )

      _ ->
        # For higher dimensions, fall back to element-by-element copy
        extract_nd(
          output,
          chunk_data,
          chunk_shape,
          slice_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          slice_start,
          element_size
        )
    end
  end

  defp extract_1d(
         output,
         chunk_data,
         _chunk_shape,
         _slice_shape,
         {chunk_start},
         {overlap_start},
         {overlap_stop},
         {slice_start},
         element_size
       ) do
    # Calculate positions
    chunk_offset = (overlap_start - chunk_start) * element_size
    output_offset = (overlap_start - slice_start) * element_size
    length = (overlap_stop - overlap_start) * element_size

    # Extract from chunk
    <<_::binary-size(chunk_offset), data::binary-size(length), _::binary>> = chunk_data

    # Place in output
    <<before::binary-size(output_offset), _::binary-size(length), after_part::binary>> = output
    <<before::binary, data::binary, after_part::binary>>
  end

  defp extract_2d(
         output,
         chunk_data,
         {_chunk_h, chunk_w},
         {_slice_h, slice_w},
         {chunk_start_y, chunk_start_x},
         {overlap_start_y, overlap_start_x},
         {overlap_stop_y, overlap_stop_x},
         {slice_start_y, slice_start_x},
         element_size
       ) do
    # Copy row by row
    Enum.reduce((overlap_start_y)..(overlap_stop_y - 1), output, fn y, acc ->
      # Position in chunk
      chunk_row = y - chunk_start_y
      chunk_offset = (chunk_row * chunk_w + (overlap_start_x - chunk_start_x)) * element_size
      row_length = (overlap_stop_x - overlap_start_x) * element_size

      # Extract row from chunk
      <<_::binary-size(chunk_offset), row_data::binary-size(row_length), _::binary>> =
        chunk_data

      # Position in output
      output_row = y - slice_start_y
      output_offset = (output_row * slice_w + (overlap_start_x - slice_start_x)) * element_size

      # Place row in output
      <<before::binary-size(output_offset), _::binary-size(row_length), after_part::binary>> =
        acc

      <<before::binary, row_data::binary, after_part::binary>>
    end)
  end

  defp extract_nd(
         output,
         chunk_data,
         chunk_shape,
         slice_shape,
         chunk_start,
         overlap_start,
         overlap_stop,
         slice_start,
         element_size
       ) do
    # Generate all indices in the overlap region
    overlap_ranges =
      Tuple.to_list(overlap_start)
      |> Enum.zip(Tuple.to_list(overlap_stop))
      |> Enum.map(fn {start, stop} -> start..(stop - 1) end)

    # Get strides for chunk and slice
    chunk_strides = ExZarr.Chunk.calculate_strides(chunk_shape)
    slice_strides = ExZarr.Chunk.calculate_strides(slice_shape)

    # Copy element by element
    indices = cartesian_product(overlap_ranges)

    Enum.reduce(indices, output, fn index_list, acc ->
      index = List.to_tuple(index_list)

      # Calculate offset in chunk
      chunk_offset =
        Tuple.to_list(index)
        |> Enum.zip(Tuple.to_list(chunk_start))
        |> Enum.zip(Tuple.to_list(chunk_strides))
        |> Enum.reduce(0, fn {{idx, start}, stride}, offset ->
          offset + (idx - start) * stride
        end)

      chunk_byte_offset = chunk_offset * element_size

      # Extract element from chunk
      <<_::binary-size(chunk_byte_offset), element::binary-size(element_size), _::binary>> =
        chunk_data

      # Calculate offset in output
      output_offset =
        Tuple.to_list(index)
        |> Enum.zip(Tuple.to_list(slice_start))
        |> Enum.zip(Tuple.to_list(slice_strides))
        |> Enum.reduce(0, fn {{idx, start}, stride}, offset ->
          offset + (idx - start) * stride
        end)

      output_byte_offset = output_offset * element_size

      # Place element in output
      <<before::binary-size(output_byte_offset), _::binary-size(element_size),
        after_part::binary>> = acc

      <<before::binary, element::binary, after_part::binary>>
    end)
  end

  defp write_to_chunk(
         chunk_data,
         input_data,
         chunk_shape,
         chunk_start,
         overlap_start,
         overlap_stop,
         write_start,
         write_stop,
         element_size
       ) do
    # Similar to extract but in reverse - write input data into chunk
    case tuple_size(chunk_shape) do
      1 ->
        write_1d(
          chunk_data,
          input_data,
          chunk_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          write_start,
          element_size
        )

      2 ->
        write_2d(
          chunk_data,
          input_data,
          chunk_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          write_start,
          write_stop,
          element_size
        )

      _ ->
        # Higher dimensions - element by element
        write_nd(
          chunk_data,
          input_data,
          chunk_shape,
          chunk_start,
          overlap_start,
          overlap_stop,
          write_start,
          write_stop,
          element_size
        )
    end
  end

  defp write_1d(
         chunk_data,
         input_data,
         _chunk_shape,
         {chunk_start},
         {overlap_start},
         {overlap_stop},
         {write_start},
         element_size
       ) do
    chunk_offset = (overlap_start - chunk_start) * element_size
    input_offset = (overlap_start - write_start) * element_size
    length = (overlap_stop - overlap_start) * element_size

    # Extract data from input
    <<_::binary-size(input_offset), data::binary-size(length), _::binary>> = input_data

    # Write to chunk
    <<before::binary-size(chunk_offset), _::binary-size(length), after_part::binary>> =
      chunk_data

    <<before::binary, data::binary, after_part::binary>>
  end

  defp write_2d(
         chunk_data,
         input_data,
         {_chunk_h, chunk_w},
         {chunk_start_y, chunk_start_x},
         {overlap_start_y, overlap_start_x},
         {overlap_stop_y, overlap_stop_x},
         {write_start_y, write_start_x},
         {_write_stop_y, write_stop_x},
         element_size
       ) do
    # Calculate input width from the full write region
    input_w = write_stop_x - write_start_x

    # Write row by row
    Enum.reduce((overlap_start_y)..(overlap_stop_y - 1), chunk_data, fn y, acc ->
      # Position in input
      input_row = y - write_start_y
      input_offset = (input_row * input_w + (overlap_start_x - write_start_x)) * element_size
      row_length = (overlap_stop_x - overlap_start_x) * element_size

      # Extract row from input
      <<_::binary-size(input_offset), row_data::binary-size(row_length), _::binary>> =
        input_data

      # Position in chunk
      chunk_row = y - chunk_start_y
      chunk_offset = (chunk_row * chunk_w + (overlap_start_x - chunk_start_x)) * element_size

      # Write row to chunk
      <<before::binary-size(chunk_offset), _::binary-size(row_length), after_part::binary>> = acc
      <<before::binary, row_data::binary, after_part::binary>>
    end)
  end

  defp write_nd(
         chunk_data,
         input_data,
         chunk_shape,
         chunk_start,
         overlap_start,
         overlap_stop,
         write_start,
         write_stop,
         element_size
       ) do
    # Calculate strides for both chunk and input
    chunk_strides = ExZarr.Chunk.calculate_strides(chunk_shape)

    input_shape =
      Tuple.to_list(write_start)
      |> Enum.zip(Tuple.to_list(write_stop))
      |> Enum.map(fn {start, stop} -> stop - start end)
      |> List.to_tuple()

    input_strides = ExZarr.Chunk.calculate_strides(input_shape)

    # Create ranges for each dimension in the overlap region
    overlap_ranges =
      Tuple.to_list(overlap_start)
      |> Enum.zip(Tuple.to_list(overlap_stop))
      |> Enum.map(fn {start, stop} -> start..(stop - 1) end)

    # Iterate through all indices in the overlap
    indices = cartesian_product(overlap_ranges)

    Enum.reduce(indices, chunk_data, fn index_list, acc ->
      index = List.to_tuple(index_list)

      # Calculate offset in input data
      input_offset =
        Tuple.to_list(index)
        |> Enum.zip(Tuple.to_list(write_start))
        |> Enum.zip(Tuple.to_list(input_strides))
        |> Enum.reduce(0, fn {{idx, start}, stride}, offset ->
          offset + (idx - start) * stride
        end)

      input_byte_offset = input_offset * element_size

      # Extract element from input
      <<_::binary-size(input_byte_offset), element::binary-size(element_size), _::binary>> =
        input_data

      # Calculate offset in chunk
      chunk_offset =
        Tuple.to_list(index)
        |> Enum.zip(Tuple.to_list(chunk_start))
        |> Enum.zip(Tuple.to_list(chunk_strides))
        |> Enum.reduce(0, fn {{idx, start}, stride}, offset ->
          offset + (idx - start) * stride
        end)

      chunk_byte_offset = chunk_offset * element_size

      # Write element to chunk
      <<before::binary-size(chunk_byte_offset), _::binary-size(element_size),
        after_part::binary>> = acc

      <<before::binary, element::binary, after_part::binary>>
    end)
  end

  # Helper functions
  defp tuple_max(t1, t2) do
    Tuple.to_list(t1)
    |> Enum.zip(Tuple.to_list(t2))
    |> Enum.map(fn {a, b} -> max(a, b) end)
    |> List.to_tuple()
  end

  defp tuple_min(t1, t2) do
    Tuple.to_list(t1)
    |> Enum.zip(Tuple.to_list(t2))
    |> Enum.map(fn {a, b} -> min(a, b) end)
    |> List.to_tuple()
  end

  defp cartesian_product([]), do: [[]]

  defp cartesian_product([range | rest]) do
    rest_product = cartesian_product(rest)

    for x <- range, rest_item <- rest_product do
      [x | rest_item]
    end
  end

  defp create_fill_chunk(array) do
    chunk_size =
      array.chunks
      |> Tuple.to_list()
      |> Enum.reduce(1, &(&1 * &2))

    _element_size = dtype_size(array.dtype)
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
