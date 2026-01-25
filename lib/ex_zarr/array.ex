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

  alias ExZarr.{Codecs, DataType, Metadata, MetadataV3, Storage}
  alias ExZarr.Codecs.PipelineV3
  alias ExZarr.Codecs.Registry

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
          metadata: Metadata.t() | MetadataV3.t(),
          version: 2 | 3
        }

  defstruct [
    :shape,
    :chunks,
    :dtype,
    :compressor,
    :fill_value,
    :storage,
    :metadata,
    # Default to v2 for backward compatibility
    version: 2
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
    # Get version from opts (default to 2 for backward compatibility)
    version = Keyword.get(opts, :zarr_version, 2)

    with {:ok, config} <- validate_config(opts),
         {:ok, storage} <- Storage.init(config),
         {:ok, metadata} <- create_metadata(config, version) do
      array =
        struct(
          __MODULE__,
          config
          |> Map.put(:storage, storage)
          |> Map.put(:metadata, metadata)
          |> Map.put(:version, version)
        )

      {:ok, array}
    end
  end

  # Create metadata based on version
  defp create_metadata(config, 2), do: Metadata.create(config)
  defp create_metadata(config, 3), do: MetadataV3.create(config)

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
      # Auto-detect version from metadata type
      {version, chunks, dtype, compressor} =
        case metadata do
          %Metadata{} ->
            # v2 metadata
            {2, metadata.chunks, metadata.dtype, metadata.compressor}

          %MetadataV3{} ->
            # v3 metadata - extract chunks and dtype
            {:ok, chunk_shape} = MetadataV3.get_chunk_shape(metadata)
            dtype = ExZarr.DataType.from_v3(metadata.data_type)
            # For v3, compressor is not a single field - set to :none for compatibility
            {3, chunk_shape, dtype, :none}
        end

      array = %__MODULE__{
        shape: metadata.shape,
        chunks: chunks,
        dtype: dtype,
        compressor: compressor,
        fill_value: metadata.fill_value,
        storage: storage,
        metadata: metadata,
        version: version
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

    with :ok <- validate_indices(start, stop, array.shape),
         {:ok, chunk_indices} <- calculate_chunk_indices(array, start, stop),
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
    # Validate that data is binary
    if is_binary(data) do
      start = Keyword.get(opts, :start, tuple_of_zeros(array.shape))
      stop = Keyword.get(opts, :stop)

      # Calculate stop from data size if not provided (for 1D arrays)
      stop =
        if stop do
          stop
        else
          calculate_stop_from_data(array, data, start)
        end

      with :ok <- validate_indices(start, stop, array.shape),
           :ok <- validate_write_data_size(data, start, stop, array.dtype),
           {:ok, chunk_indices} <- calculate_chunk_indices(array, start, stop),
           {:ok, chunks} <- split_into_chunks(array, data, start, stop) do
        write_chunks(array, chunks, chunk_indices)
      end
    else
      {:error, {:invalid_data, "data must be binary, got: #{inspect(data)}"}}
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
      # Base config with validated/default values
      base_config = %{
        shape: shape,
        chunks: chunks,
        dtype: Keyword.get(opts, :dtype, :float64),
        compressor: Keyword.get(opts, :compressor, :zstd),
        fill_value: Keyword.get(opts, :fill_value, 0),
        filters: Keyword.get(opts, :filters, nil),
        storage_type: Keyword.get(opts, :storage, :memory),
        path: opts[:path]
      }

      # Pass through all backend-specific options by merging with opts
      # Backend-specific keys like :array_id, :table_name, :bucket, etc. will be preserved
      config = Enum.into(opts, base_config)

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
            # Version-aware codec decoding
            apply_codec_pipeline_decode(array, compressed_data)

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
        # Version-aware codec encoding
        with {:ok, compressed} <- apply_codec_pipeline_encode(array, chunk_data) do
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
    # Use reduce_while to stop on first error
    chunk_indices
    |> Enum.reduce_while({:ok, []}, fn chunk_index, {:ok, acc_chunks} ->
      # Get the bounds of this chunk in array coordinates
      {chunk_start, chunk_stop} =
        ExZarr.Chunk.chunk_bounds(chunk_index, array.chunks, array.shape)

      # Calculate the overlap between the chunk and the write region
      overlap_start = tuple_max(chunk_start, start)
      overlap_stop = tuple_min(chunk_stop, stop)

      # Create or read the existing chunk
      case read_or_create_chunk(array, chunk_index) do
        {:ok, existing_chunk} ->
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

          {:cont, {:ok, acc_chunks ++ [modified_chunk]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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
    Enum.reduce(overlap_start_y..(overlap_stop_y - 1), output, fn y, acc ->
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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
    Enum.reduce(overlap_start_y..(overlap_stop_y - 1), chunk_data, fn y, acc ->
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

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
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
      <<before::binary-size(chunk_byte_offset), _::binary-size(element_size), after_part::binary>> =
        acc

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

  # Index validation functions

  defp validate_indices(start, stop, shape) do
    with :ok <- validate_tuple(start, "start"),
         :ok <- validate_tuple(stop, "stop"),
         :ok <- validate_dimensionality(start, stop, shape),
         :ok <- validate_non_negative(start, "start"),
         :ok <- validate_non_negative(stop, "stop"),
         :ok <- validate_start_less_than_stop(start, stop) do
      validate_within_bounds(stop, shape)
    end
  end

  defp validate_tuple(value, name) do
    if is_tuple(value) do
      :ok
    else
      {:error, {:invalid_index, "#{name} must be a tuple, got: #{inspect(value)}"}}
    end
  end

  defp validate_dimensionality(start, stop, shape) do
    ndim = tuple_size(shape)
    start_dim = tuple_size(start)
    stop_dim = tuple_size(stop)

    cond do
      start_dim != ndim ->
        {:error,
         {:dimension_mismatch,
          "start has #{start_dim} dimensions but array has #{ndim} dimensions"}}

      stop_dim != ndim ->
        {:error,
         {:dimension_mismatch, "stop has #{stop_dim} dimensions but array has #{ndim} dimensions"}}

      true ->
        :ok
    end
  end

  defp validate_non_negative(indices, name) do
    indices_list = Tuple.to_list(indices)

    if Enum.all?(indices_list, &(is_integer(&1) and &1 >= 0)) do
      :ok
    else
      negative = Enum.find(indices_list, &(not is_integer(&1) or &1 < 0))

      {:error,
       {:invalid_index,
        "#{name} indices must be non-negative integers, found: #{inspect(negative)}"}}
    end
  end

  defp validate_start_less_than_stop(start, stop) do
    violations =
      Tuple.to_list(start)
      |> Enum.zip(Tuple.to_list(stop))
      |> Enum.with_index()
      |> Enum.filter(fn {{s, e}, _idx} -> s > e end)

    if Enum.empty?(violations) do
      :ok
    else
      {{start_val, stop_val}, dim} = hd(violations)

      {:error,
       {:invalid_range,
        "start must be <= stop in all dimensions. Dimension #{dim}: start=#{start_val}, stop=#{stop_val}"}}
    end
  end

  defp validate_within_bounds(stop, shape) do
    violations =
      Tuple.to_list(stop)
      |> Enum.zip(Tuple.to_list(shape))
      |> Enum.with_index()
      |> Enum.filter(fn {{idx, bound}, _dim} -> idx > bound end)

    if Enum.empty?(violations) do
      :ok
    else
      {{idx, bound}, dim} = hd(violations)

      {:error,
       {:out_of_bounds,
        "Index out of bounds in dimension #{dim}: stop=#{idx} exceeds shape=#{bound}"}}
    end
  end

  defp validate_write_data_size(data, start, stop, dtype) do
    element_size = dtype_size(dtype)
    data_size = byte_size(data)

    expected_elements =
      Tuple.to_list(start)
      |> Enum.zip(Tuple.to_list(stop))
      |> Enum.map(fn {s, e} -> e - s end)
      |> Enum.reduce(1, &(&1 * &2))

    expected_bytes = expected_elements * element_size

    cond do
      rem(data_size, element_size) != 0 ->
        {:error,
         {:data_size_mismatch,
          "Data size (#{data_size} bytes) is not a multiple of element size (#{element_size} bytes)"}}

      data_size != expected_bytes ->
        num_elements = Kernel.div(data_size, element_size)

        {:error,
         {:data_size_mismatch,
          "Data size mismatch: expected #{expected_elements} elements (#{expected_bytes} bytes), got #{num_elements} elements (#{data_size} bytes)"}}

      true ->
        :ok
    end
  end

  defp read_or_create_chunk(array, chunk_index) do
    case Storage.read_chunk(array.storage, chunk_index) do
      {:ok, compressed} ->
        case Codecs.decompress(compressed, array.compressor) do
          {:ok, decompressed} -> {:ok, decompressed}
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        {:ok, create_fill_chunk(array)}

      {:error, reason} ->
        # Propagate other storage errors (e.g., from mock backend in error mode)
        {:error, reason}
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

  # Filter pipeline helpers

  # Version-aware codec pipeline functions
  defp apply_codec_pipeline_decode(array, compressed_data) do
    case array.version do
      2 ->
        # v2 path: decompress first, then apply filters in reverse order
        with {:ok, decompressed} <- Codecs.decompress(compressed_data, array.compressor) do
          apply_filters_decode(decompressed, array.metadata.filters)
        end

      3 ->
        # v3 path: use unified codec pipeline
        {:ok, pipeline} = PipelineV3.parse_codecs(array.metadata.codecs)
        opts = [itemsize: ExZarr.DataType.itemsize(array.dtype), dtype: array.dtype]
        PipelineV3.decode(compressed_data, pipeline, opts)
    end
  end

  defp apply_codec_pipeline_encode(array, chunk_data) do
    case array.version do
      2 ->
        # v2 path: apply filters in forward order, then compress
        with {:ok, filtered} <- apply_filters_encode(chunk_data, array.metadata.filters) do
          Codecs.compress(filtered, array.compressor)
        end

      3 ->
        # v3 path: use unified codec pipeline
        {:ok, pipeline} = PipelineV3.parse_codecs(array.metadata.codecs)
        opts = [itemsize: DataType.itemsize(array.dtype), dtype: array.dtype]
        PipelineV3.encode(chunk_data, pipeline, opts)
    end
  end

  defp apply_filters_decode(data, nil), do: {:ok, data}
  defp apply_filters_decode(data, []), do: {:ok, data}

  defp apply_filters_decode(data, filters) when is_list(filters) do
    # Reverse order for decoding
    filters
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, data}, fn {filter_id, opts}, {:ok, acc_data} ->
      case Codecs.Registry.get(filter_id) do
        {:ok, :builtin_delta} ->
          case decode_builtin_filter(acc_data, :delta, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_quantize} ->
          case decode_builtin_filter(acc_data, :quantize, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_shuffle} ->
          case decode_builtin_filter(acc_data, :shuffle, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_fixedscaleoffset} ->
          case decode_builtin_filter(acc_data, :fixedscaleoffset, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_astype} ->
          case decode_builtin_filter(acc_data, :astype, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_packbits} ->
          case decode_builtin_filter(acc_data, :packbits, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_categorize} ->
          case decode_builtin_filter(acc_data, :categorize, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_bitround} ->
          case decode_builtin_filter(acc_data, :bitround, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:ok, module} when is_atom(module) ->
          # Custom filter
          case module.decode(acc_data, opts) do
            {:ok, decoded} -> {:cont, {:ok, decoded}}
            error -> {:halt, error}
          end

        {:error, :not_found} ->
          # Unknown filter - skip with warning
          require Logger
          Logger.warning("Unknown filter #{filter_id}, skipping during decode")
          {:cont, {:ok, acc_data}}
      end
    end)
  end

  defp apply_filters_encode(data, nil), do: {:ok, data}
  defp apply_filters_encode(data, []), do: {:ok, data}

  defp apply_filters_encode(data, filters) when is_list(filters) do
    # Forward order for encoding
    Enum.reduce_while(filters, {:ok, data}, fn {filter_id, opts}, {:ok, acc_data} ->
      case Registry.get(filter_id) do
        {:ok, :builtin_delta} ->
          case encode_builtin_filter(acc_data, :delta, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_quantize} ->
          case encode_builtin_filter(acc_data, :quantize, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_shuffle} ->
          case encode_builtin_filter(acc_data, :shuffle, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_fixedscaleoffset} ->
          case encode_builtin_filter(acc_data, :fixedscaleoffset, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_astype} ->
          case encode_builtin_filter(acc_data, :astype, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_packbits} ->
          case encode_builtin_filter(acc_data, :packbits, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_categorize} ->
          case encode_builtin_filter(acc_data, :categorize, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, :builtin_bitround} ->
          case encode_builtin_filter(acc_data, :bitround, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:ok, module} when is_atom(module) ->
          # Custom filter
          case module.encode(acc_data, opts) do
            {:ok, encoded} -> {:cont, {:ok, encoded}}
            error -> {:halt, error}
          end

        {:error, :not_found} ->
          # Unknown filter - skip with warning
          require Logger
          Logger.warning("Unknown filter #{filter_id}, skipping during encode")
          {:cont, {:ok, acc_data}}
      end
    end)
  end

  # Built-in filter implementations

  # Delta filter: encodes data as differences between adjacent values
  defp encode_builtin_filter(data, :delta, opts) when is_binary(data) do
    dtype = Keyword.fetch!(opts, :dtype)
    astype = Keyword.get(opts, :astype, dtype)

    try do
      # Convert binary to list of values
      values = binary_to_values(data, dtype)

      # Compute deltas: [first, diff1, diff2, ...]
      deltas =
        case values do
          [] ->
            []

          [first | rest] ->
            {_, result} =
              Enum.reduce(rest, {first, [first]}, fn current, {previous, acc} ->
                diff = current - previous
                {current, [diff | acc]}
              end)

            Enum.reverse(result)
        end

      # Convert back to binary with astype
      encoded = values_to_binary(deltas, astype)
      {:ok, encoded}
    rescue
      e -> {:error, {:delta_encode_failed, e}}
    end
  end

  defp encode_builtin_filter(data, :quantize, opts) when is_binary(data) do
    digits = Keyword.fetch!(opts, :digits)
    dtype = Keyword.fetch!(opts, :dtype)

    # Quantize: round to specified decimal digits
    # Formula: round(value * 10^digits) / 10^digits
    scale = :math.pow(10, digits)

    values = binary_to_values(data, dtype)

    quantized =
      case dtype do
        dt when dt in [:float32, :float64] ->
          Enum.map(values, fn value ->
            Float.round(value * scale) / scale
          end)

        _ ->
          # For non-float types, quantization doesn't apply
          values
      end

    encoded = values_to_binary(quantized, dtype)
    {:ok, encoded}
  end

  defp encode_builtin_filter(data, :shuffle, opts) when is_binary(data) do
    elementsize = Keyword.fetch!(opts, :elementsize)

    # Shuffle: transpose byte matrix to group similar byte positions
    # Input:  [A0 A1 A2 A3] [B0 B1 B2 B3] [C0 C1 C2 C3]
    # Output: [A0 B0 C0] [A1 B1 C1] [A2 B2 C2] [A3 B3 C3]

    num_elements = div(byte_size(data), elementsize)

    if num_elements == 0 do
      {:ok, data}
    else
      # Split data into elements
      elements =
        for i <- 0..(num_elements - 1) do
          :binary.part(data, i * elementsize, elementsize)
        end

      # Transpose: for each byte position, collect all bytes at that position
      shuffled =
        for byte_pos <- 0..(elementsize - 1), into: <<>> do
          for element <- elements, into: <<>> do
            <<:binary.at(element, byte_pos)>>
          end
        end

      {:ok, shuffled}
    end
  end

  defp encode_builtin_filter(data, :fixedscaleoffset, opts) when is_binary(data) do
    offset = Keyword.fetch!(opts, :offset)
    scale = Keyword.fetch!(opts, :scale)
    dtype = Keyword.fetch!(opts, :dtype)
    astype = Keyword.fetch!(opts, :astype)

    # FixedScaleOffset: encode = round((value - offset) / scale)
    values = binary_to_values(data, dtype)

    encoded =
      Enum.map(values, fn value ->
        round((value - offset) / scale)
      end)

    encoded_binary = values_to_binary(encoded, astype)
    {:ok, encoded_binary}
  end

  defp encode_builtin_filter(data, :astype, opts) when is_binary(data) do
    decode_dtype = Keyword.fetch!(opts, :decode_dtype)
    encode_dtype = Keyword.fetch!(opts, :encode_dtype)

    # AsType: convert from decode_dtype to encode_dtype
    values = binary_to_values(data, decode_dtype)
    encoded = values_to_binary(values, encode_dtype)
    {:ok, encoded}
  end

  defp encode_builtin_filter(data, :packbits, _opts) do
    # Placeholder: just return data as-is until PackBits filter is implemented
    {:ok, data}
  end

  defp encode_builtin_filter(data, :categorize, _opts) do
    # Placeholder: just return data as-is until Categorize filter is implemented
    {:ok, data}
  end

  defp encode_builtin_filter(data, :bitround, opts) when is_binary(data) do
    keepbits = Keyword.fetch!(opts, :keepbits)

    # BitRound: zero out least significant mantissa bits
    # This is a simplified implementation using rounding to achieve similar compression
    # For float64, we approximate by rounding to reduce precision based on keepbits
    # keepbits controls how much precision to retain (higher = more precision)

    # For simplicity, we'll round to a number of significant figures based on keepbits
    # This achieves similar compression goals without low-level bit manipulation
    scale = :math.pow(2, max(0, 52 - keepbits))

    # Process as float64 values
    <<values_binary::binary>> = data
    size = byte_size(data)

    rounded =
      for <<value::float-little-64 <- values_binary>>, into: <<>> do
        # Round to reduce precision based on keepbits
        rounded_value = Float.round(value / scale) * scale
        <<rounded_value::float-little-64>>
      end

    if byte_size(rounded) == size do
      {:ok, rounded}
    else
      {:ok, data}
    end
  end

  defp decode_builtin_filter(data, :delta, opts) when is_binary(data) do
    dtype = Keyword.fetch!(opts, :dtype)

    try do
      # Convert binary to list of deltas
      deltas = binary_to_values(data, dtype)

      # Reconstruct values by computing cumulative sum
      values =
        case deltas do
          [] ->
            []

          [first | rest] ->
            {_, result} =
              Enum.reduce(rest, {first, [first]}, fn diff, {previous, acc} ->
                current = previous + diff
                {current, [current | acc]}
              end)

            Enum.reverse(result)
        end

      # Convert back to binary
      decoded = values_to_binary(values, dtype)
      {:ok, decoded}
    rescue
      e -> {:error, {:delta_decode_failed, e}}
    end
  end

  defp decode_builtin_filter(data, :quantize, _opts) do
    # Quantization is lossy and irreversible - decode is passthrough
    {:ok, data}
  end

  defp decode_builtin_filter(data, :shuffle, opts) when is_binary(data) do
    elementsize = Keyword.fetch!(opts, :elementsize)

    # Unshuffle: transpose back to original byte order
    num_elements = div(byte_size(data), elementsize)

    if num_elements == 0 do
      {:ok, data}
    else
      # Split shuffled data into byte position groups
      byte_groups =
        for byte_pos <- 0..(elementsize - 1) do
          :binary.part(data, byte_pos * num_elements, num_elements)
        end

      # Reconstruct elements by taking one byte from each group
      unshuffled =
        for elem_idx <- 0..(num_elements - 1), into: <<>> do
          for byte_group <- byte_groups, into: <<>> do
            <<:binary.at(byte_group, elem_idx)>>
          end
        end

      {:ok, unshuffled}
    end
  end

  defp decode_builtin_filter(data, :fixedscaleoffset, opts) when is_binary(data) do
    offset = Keyword.fetch!(opts, :offset)
    scale = Keyword.fetch!(opts, :scale)
    dtype = Keyword.fetch!(opts, :dtype)
    astype = Keyword.fetch!(opts, :astype)

    # FixedScaleOffset: decode = (value * scale) + offset
    values = binary_to_values(data, astype)

    decoded =
      Enum.map(values, fn value ->
        value * scale + offset
      end)

    decoded_binary = values_to_binary(decoded, dtype)
    {:ok, decoded_binary}
  end

  defp decode_builtin_filter(data, :astype, opts) when is_binary(data) do
    decode_dtype = Keyword.fetch!(opts, :decode_dtype)
    encode_dtype = Keyword.fetch!(opts, :encode_dtype)

    # AsType: convert from encode_dtype back to decode_dtype
    values = binary_to_values(data, encode_dtype)
    decoded = values_to_binary(values, decode_dtype)
    {:ok, decoded}
  end

  defp decode_builtin_filter(data, :packbits, _opts) do
    # Placeholder: just return data as-is until PackBits filter is implemented
    {:ok, data}
  end

  defp decode_builtin_filter(data, :categorize, _opts) do
    # Placeholder: just return data as-is until Categorize filter is implemented
    {:ok, data}
  end

  defp decode_builtin_filter(data, :bitround, _opts) do
    # BitRound is lossy and irreversible - decode is passthrough
    {:ok, data}
  end

  # Helper: Convert binary to list of values based on dtype
  defp binary_to_values(<<>>, _dtype), do: []

  defp binary_to_values(data, :int8) do
    for <<value::signed-8 <- data>>, do: value
  end

  defp binary_to_values(data, :int16) do
    for <<value::signed-little-16 <- data>>, do: value
  end

  defp binary_to_values(data, :int32) do
    for <<value::signed-little-32 <- data>>, do: value
  end

  defp binary_to_values(data, :int64) do
    for <<value::signed-little-64 <- data>>, do: value
  end

  defp binary_to_values(data, :uint8) do
    for <<value::unsigned-8 <- data>>, do: value
  end

  defp binary_to_values(data, :uint16) do
    for <<value::unsigned-little-16 <- data>>, do: value
  end

  defp binary_to_values(data, :uint32) do
    for <<value::unsigned-little-32 <- data>>, do: value
  end

  defp binary_to_values(data, :uint64) do
    for <<value::unsigned-little-64 <- data>>, do: value
  end

  defp binary_to_values(data, :float32) do
    for <<value::float-little-32 <- data>>, do: value
  end

  defp binary_to_values(data, :float64) do
    for <<value::float-little-64 <- data>>, do: value
  end

  # Helper: Convert list of values to binary based on dtype
  defp values_to_binary(values, :int8) do
    for value <- values, into: <<>>, do: <<value::signed-8>>
  end

  defp values_to_binary(values, :int16) do
    for value <- values, into: <<>>, do: <<value::signed-little-16>>
  end

  defp values_to_binary(values, :int32) do
    for value <- values, into: <<>>, do: <<value::signed-little-32>>
  end

  defp values_to_binary(values, :int64) do
    for value <- values, into: <<>>, do: <<value::signed-little-64>>
  end

  defp values_to_binary(values, :uint8) do
    for value <- values, into: <<>>, do: <<value::unsigned-8>>
  end

  defp values_to_binary(values, :uint16) do
    for value <- values, into: <<>>, do: <<value::unsigned-little-16>>
  end

  defp values_to_binary(values, :uint32) do
    for value <- values, into: <<>>, do: <<value::unsigned-little-32>>
  end

  defp values_to_binary(values, :uint64) do
    for value <- values, into: <<>>, do: <<value::unsigned-little-64>>
  end

  defp values_to_binary(values, :float32) do
    for value <- values, into: <<>>, do: <<value::float-little-32>>
  end

  defp values_to_binary(values, :float64) do
    for value <- values, into: <<>>, do: <<value::float-little-64>>
  end
end
