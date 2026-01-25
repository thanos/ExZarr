defmodule ExZarr.ChunkGrid.Regular do
  @moduledoc """
  Regular chunk grid implementation for Zarr v3.

  In a regular chunk grid, all chunks have the same shape, except for edge chunks
  which may be smaller if the array dimensions are not evenly divisible by the
  chunk dimensions.

  ## Configuration

  The configuration map must contain:

    * `"chunk_shape"` - List of integers defining chunk dimensions

  ## Example

      config = %{
        "chunk_shape" => [100, 100, 100]
      }

      {:ok, grid} = ExZarr.ChunkGrid.Regular.init(config)

  ## Specification

  Zarr v3 Regular Chunk Grid:
  https://zarr-specs.readthedocs.io/en/latest/v3/core/index.html#regular-chunk-grid
  """

  @behaviour ExZarr.ChunkGrid

  defstruct [:chunk_shape, :array_shape]

  @type t :: %__MODULE__{
          chunk_shape: tuple(),
          array_shape: tuple() | nil
        }

  @impl true
  def init(config) when is_map(config) do
    chunk_shape =
      case Map.get(config, "chunk_shape") || Map.get(config, :chunk_shape) do
        shape when is_list(shape) -> List.to_tuple(shape)
        shape when is_tuple(shape) -> shape
        nil -> nil
      end

    if chunk_shape do
      {:ok, %__MODULE__{chunk_shape: chunk_shape, array_shape: nil}}
    else
      {:error, {:missing_chunk_shape, "chunk_shape is required for regular grid"}}
    end
  end

  @doc """
  Set the array shape for this chunk grid.

  Required for calculating edge chunk shapes and total chunk count.
  """
  @spec set_array_shape(t(), tuple()) :: t()
  def set_array_shape(%__MODULE__{} = grid, array_shape) when is_tuple(array_shape) do
    %{grid | array_shape: array_shape}
  end

  @impl true
  def chunk_shape(chunk_index, %__MODULE__{chunk_shape: chunk_shape, array_shape: nil})
      when is_tuple(chunk_index) do
    # No array shape set, return regular chunk shape
    chunk_shape
  end

  def chunk_shape(chunk_index, %__MODULE__{chunk_shape: chunk_shape, array_shape: array_shape})
      when is_tuple(chunk_index) and is_tuple(array_shape) do
    # Calculate actual chunk shape considering edge chunks
    ndim = tuple_size(chunk_shape)

    if tuple_size(chunk_index) != ndim or tuple_size(array_shape) != ndim do
      chunk_shape
    else
      index_list = Tuple.to_list(chunk_index)
      chunk_list = Tuple.to_list(chunk_shape)
      array_list = Tuple.to_list(array_shape)

      Enum.zip([index_list, chunk_list, array_list])
      |> Enum.map(fn {idx, chunk_dim, array_dim} ->
        # Calculate chunk start and end
        chunk_start = idx * chunk_dim
        chunk_end = min((idx + 1) * chunk_dim, array_dim)
        chunk_end - chunk_start
      end)
      |> List.to_tuple()
    end
  end

  @impl true
  def chunk_count(%__MODULE__{chunk_shape: _chunk_shape, array_shape: nil}) do
    # Without array shape, can't determine count
    # Return 0 or error
    0
  end

  def chunk_count(%__MODULE__{chunk_shape: chunk_shape, array_shape: array_shape})
      when is_tuple(chunk_shape) and is_tuple(array_shape) do
    # Calculate number of chunks in each dimension
    chunk_shape
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(array_shape))
    |> Enum.map(fn {chunk_dim, array_dim} ->
      # Ceiling division: (array_dim + chunk_dim - 1) / chunk_dim
      div(array_dim + chunk_dim - 1, chunk_dim)
    end)
    |> Enum.reduce(1, &Kernel.*/2)
  end

  @impl true
  def validate(config, array_shape) when is_map(config) and is_tuple(array_shape) do
    chunk_shape =
      case Map.get(config, "chunk_shape") || Map.get(config, :chunk_shape) do
        shape when is_list(shape) -> List.to_tuple(shape)
        shape when is_tuple(shape) -> shape
        nil -> nil
      end

    cond do
      is_nil(chunk_shape) ->
        {:error, {:missing_chunk_shape, "chunk_shape is required"}}

      tuple_size(chunk_shape) != tuple_size(array_shape) ->
        {:error,
         {:dimension_mismatch,
          "chunk_shape dimensions (#{tuple_size(chunk_shape)}) must match array dimensions (#{tuple_size(array_shape)})"}}

      not all_positive?(chunk_shape) ->
        {:error, {:invalid_chunk_shape, "all chunk dimensions must be positive"}}

      true ->
        :ok
    end
  end

  defp all_positive?(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.all?(fn dim -> is_integer(dim) and dim > 0 end)
  end

  @doc """
  Get all chunk indices for an array with the given shape.

  ## Parameters

    * `grid` - Regular chunk grid state
    * `array_shape` - Shape of the array

  ## Returns

    * List of chunk index tuples

  ## Examples

      iex> grid = %ExZarr.ChunkGrid.Regular{chunk_shape: {10, 10}, array_shape: {25, 15}}
      iex> ExZarr.ChunkGrid.Regular.all_chunk_indices(grid)
      [{0, 0}, {0, 1}, {1, 0}, {1, 1}, {2, 0}, {2, 1}]

  """
  @spec all_chunk_indices(t()) :: [tuple()]
  def all_chunk_indices(%__MODULE__{chunk_shape: chunk_shape, array_shape: array_shape})
      when is_tuple(chunk_shape) and is_tuple(array_shape) do
    # Calculate chunk counts per dimension
    chunk_counts =
      chunk_shape
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(array_shape))
      |> Enum.map(fn {chunk_dim, array_dim} ->
        div(array_dim + chunk_dim - 1, chunk_dim)
      end)

    # Generate all combinations of indices
    generate_indices(chunk_counts)
  end

  defp generate_indices([count]) do
    for i <- 0..(count - 1), do: {i}
  end

  defp generate_indices([count | rest]) do
    rest_indices = generate_indices(rest)

    for i <- 0..(count - 1), rest_tuple <- rest_indices do
      List.to_tuple([i | Tuple.to_list(rest_tuple)])
    end
  end
end
