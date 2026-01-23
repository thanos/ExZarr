defmodule ExZarr.Metadata do
  @moduledoc """
  Metadata management for Zarr arrays.

  Handles the `.zarray` metadata file that describes an array's structure,
  data type, compression, and other attributes according to the Zarr v2
  specification.

  ## Metadata Structure

  Each Zarr array has associated metadata containing:

  - **shape**: The dimensions of the array
  - **chunks**: The size of each chunk
  - **dtype**: The data type of elements
  - **compressor**: The compression codec used
  - **fill_value**: Default value for uninitialized elements
  - **order**: Memory layout order ("C" for row-major)
  - **zarr_format**: Version of the Zarr specification (2)
  - **filters**: Optional transformation pipeline (currently unused)

  ## Zarr v2 Specification

  The metadata is stored as JSON in a `.zarray` file. ExZarr reads and writes
  this format for compatibility with other Zarr implementations including
  Python (zarr-python), Julia (Zarr.jl), and others.

  ## Examples

      # Create metadata
      config = %{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0
      }
      {:ok, metadata} = ExZarr.Metadata.create(config)

      # Calculate chunk information
      ExZarr.Metadata.num_chunks(metadata)    # => {10, 10}
      ExZarr.Metadata.total_chunks(metadata)  # => 100
      ExZarr.Metadata.chunk_size_bytes(metadata)  # => 80000 (100*100*8)
  """

  @type t :: %__MODULE__{
          shape: tuple(),
          chunks: tuple(),
          dtype: ExZarr.dtype(),
          compressor: ExZarr.compressor(),
          fill_value: number(),
          order: String.t(),
          zarr_format: integer(),
          filters: list() | nil
        }

  defstruct [
    :shape,
    :chunks,
    :dtype,
    :compressor,
    fill_value: 0,
    order: "C",
    zarr_format: 2,
    filters: nil
  ]

  @doc """
  Creates metadata from a configuration map.

  Takes a configuration map and creates a Metadata struct with all necessary
  fields for a Zarr array. Uses defaults for optional fields.

  ## Parameters

  - `config` - Map with keys `:shape`, `:chunks`, `:dtype`, `:compressor`, `:fill_value`

  ## Examples

      config = %{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0
      }
      {:ok, metadata} = ExZarr.Metadata.create(config)

  ## Returns

  `{:ok, metadata}` with initialized Metadata struct.
  """
  @spec create(map()) :: {:ok, t()}
  def create(config) do
    metadata = %__MODULE__{
      shape: config.shape,
      chunks: config.chunks,
      dtype: config.dtype,
      compressor: config.compressor,
      fill_value: config.fill_value,
      order: Map.get(config, :order, "C"),
      zarr_format: 2,
      filters: nil
    }

    {:ok, metadata}
  end

  @doc """
  Validates metadata structure.

  Checks that the metadata has valid values for required fields.

  ## Examples

      ExZarr.Metadata.validate(metadata)
      # => :ok

  ## Returns

  - `:ok` if metadata is valid
  - `{:error, :invalid_shape}` if shape is empty
  - `{:error, :chunks_shape_mismatch}` if chunks and shape have different dimensions
  - `{:error, :unsupported_zarr_format}` if zarr_format is not 2
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = metadata) do
    cond do
      tuple_size(metadata.shape) == 0 ->
        {:error, :invalid_shape}

      tuple_size(metadata.chunks) != tuple_size(metadata.shape) ->
        {:error, :chunks_shape_mismatch}

      metadata.zarr_format != 2 ->
        {:error, :unsupported_zarr_format}

      true ->
        :ok
    end
  end

  @doc """
  Returns the number of chunks along each dimension.

  Calculates how many chunks are needed in each dimension to cover the entire
  array. Uses ceiling division to handle arrays that don't divide evenly by
  chunk size.

  ## Examples

      metadata = %ExZarr.Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        # ... other fields
      }
      ExZarr.Metadata.num_chunks(metadata)
      # => {10, 10}

      metadata = %ExZarr.Metadata{
        shape: {1000, 950},
        chunks: {100, 100},
        # ... other fields
      }
      ExZarr.Metadata.num_chunks(metadata)
      # => {10, 10} (last chunk in second dimension is only 50 elements)

  ## Returns

  Tuple with the number of chunks in each dimension.
  """
  @spec num_chunks(t()) :: tuple()
  def num_chunks(%__MODULE__{shape: shape, chunks: chunks}) do
    shape
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(chunks))
    |> Enum.map(fn {dim_size, chunk_size} ->
      div(dim_size + chunk_size - 1, chunk_size)
    end)
    |> List.to_tuple()
  end

  @doc """
  Returns the total number of chunks in the array.

  Calculates the product of chunks in all dimensions. This is the total number
  of chunk files that will be created when the array is fully populated.

  ## Examples

      metadata = %ExZarr.Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        # ... other fields
      }
      ExZarr.Metadata.total_chunks(metadata)
      # => 100 (10 * 10)

      metadata = %ExZarr.Metadata{
        shape: {1000, 1000, 1000},
        chunks: {100, 100, 100},
        # ... other fields
      }
      ExZarr.Metadata.total_chunks(metadata)
      # => 1000 (10 * 10 * 10)

  ## Returns

  Non-negative integer representing total chunk count.
  """
  @spec total_chunks(t()) :: non_neg_integer()
  def total_chunks(metadata) do
    metadata
    |> num_chunks()
    |> Tuple.to_list()
    |> Enum.reduce(1, &(&1 * &2))
  end

  @doc """
  Returns the size of a chunk in bytes (uncompressed).

  Calculates the number of bytes required to store one chunk in memory.
  This is the product of chunk dimensions multiplied by the size of the
  data type.

  ## Examples

      metadata = %ExZarr.Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        # ... other fields
      }
      ExZarr.Metadata.chunk_size_bytes(metadata)
      # => 80000 (100 * 100 * 8 bytes per float64)

      metadata = %ExZarr.Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :int32,
        # ... other fields
      }
      ExZarr.Metadata.chunk_size_bytes(metadata)
      # => 400 (100 * 4 bytes per int32)

  ## Returns

  Non-negative integer representing uncompressed chunk size in bytes.

  ## Note

  Compressed chunks on disk may be smaller depending on the compression codec
  and data compressibility.
  """
  @spec chunk_size_bytes(t()) :: non_neg_integer()
  def chunk_size_bytes(%__MODULE__{chunks: chunks, dtype: dtype}) do
    elements =
      chunks
      |> Tuple.to_list()
      |> Enum.reduce(1, &(&1 * &2))

    elements * dtype_size(dtype)
  end

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
