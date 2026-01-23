defmodule ExZarr.Chunk do
  @moduledoc """
  Chunk handling utilities for Zarr arrays.

  Zarr arrays are divided into chunks for efficient storage and I/O.
  This module provides utilities for working with chunk indices and coordinates.

  ## Chunk Indexing

  An array with shape `{1000, 1000}` and chunk size `{100, 100}` is divided
  into a 10x10 grid of chunks. Each chunk is identified by a tuple index like
  `{2, 3}`, representing the chunk's position in the grid.

  ## Functions

  - **index_to_chunk/2** - Converts array index to chunk index
  - **chunk_bounds/3** - Calculates the array region covered by a chunk
  - **slice_to_chunks/3** - Finds all chunks overlapping with a slice
  - **flat_to_multi/2** - Converts flat index to multi-dimensional index
  - **multi_to_flat/2** - Converts multi-dimensional index to flat index
  - **calculate_strides/1** - Calculates strides for row-major layout

  ## Examples

      # Which chunk contains array index {250, 350}?
      ExZarr.Chunk.index_to_chunk({250, 350}, {100, 100})
      # => {2, 3}

      # What array region does chunk {1, 2} cover?
      ExZarr.Chunk.chunk_bounds({1, 2}, {100, 100}, {1000, 1000})
      # => {{100, 200}, {200, 300}}

      # Which chunks overlap with a slice?
      ExZarr.Chunk.slice_to_chunks({0, 0}, {250, 250}, {100, 100})
      # => [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}, {2, 0}, {2, 1}, {2, 2}]
  """

  @doc """
  Calculates which chunk contains a given array index.

  Takes an array index and chunk size, and returns the chunk index that
  contains that array position. Uses integer division for each dimension.

  ## Parameters

  - `array_index` - Tuple of array coordinates (e.g., `{150, 250}`)
  - `chunk_shape` - Tuple of chunk dimensions (e.g., `{100, 100}`)

  ## Examples

      iex> ExZarr.Chunk.index_to_chunk({150, 250}, {100, 100})
      {1, 2}

      iex> ExZarr.Chunk.index_to_chunk({0, 0}, {100, 100})
      {0, 0}

      iex> ExZarr.Chunk.index_to_chunk({99, 199}, {100, 100})
      {0, 1}

  ## Returns

  Tuple representing the chunk index.
  """
  @spec index_to_chunk(tuple(), tuple()) :: tuple()
  def index_to_chunk(array_index, chunk_shape) do
    array_index
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(chunk_shape))
    |> Enum.map(fn {idx, chunk_size} -> div(idx, chunk_size) end)
    |> List.to_tuple()
  end

  @doc """
  Calculates the array indices that a chunk covers.

  Returns the start and end coordinates of the region covered by a chunk.
  The end coordinates are exclusive (standard range notation). For edge chunks,
  the end is clamped to the array shape.

  ## Parameters

  - `chunk_index` - Tuple identifying the chunk (e.g., `{1, 2}`)
  - `chunk_shape` - Tuple of chunk dimensions (e.g., `{100, 100}`)
  - `array_shape` - Tuple of array dimensions (e.g., `{1000, 1000}`)

  ## Examples

      iex> ExZarr.Chunk.chunk_bounds({1, 2}, {100, 100}, {1000, 1000})
      {{100, 200}, {200, 300}}

      iex> ExZarr.Chunk.chunk_bounds({0, 0}, {100, 100}, {1000, 1000})
      {{0, 0}, {100, 100}}

      # Edge chunk (last chunk may be smaller)
      iex> ExZarr.Chunk.chunk_bounds({9, 9}, {100, 100}, {950, 950})
      {{900, 900}, {950, 950}}

  ## Returns

  Tuple of `{start_indices, end_indices}` where both are tuples of coordinates.
  End indices are exclusive.
  """
  @spec chunk_bounds(tuple(), tuple(), tuple()) :: {tuple(), tuple()}
  def chunk_bounds(chunk_index, chunk_shape, array_shape) do
    start_indices =
      chunk_index
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(chunk_shape))
      |> Enum.map(fn {cidx, csize} -> cidx * csize end)
      |> List.to_tuple()

    end_indices =
      start_indices
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(chunk_shape))
      |> Enum.zip(Tuple.to_list(array_shape))
      |> Enum.map(fn {{start, csize}, asize} -> min(start + csize, asize) end)
      |> List.to_tuple()

    {start_indices, end_indices}
  end

  @doc """
  Calculates all chunk indices that overlap with a slice.

  Given a rectangular region defined by start and stop indices, returns a list
  of all chunk indices that contain at least one element from that region.
  This is used to determine which chunks need to be read or written for a
  slice operation.

  ## Parameters

  - `start_index` - Starting coordinates of the slice (inclusive)
  - `stop_index` - Ending coordinates of the slice (exclusive)
  - `chunk_shape` - Tuple of chunk dimensions

  ## Examples

      iex> ExZarr.Chunk.slice_to_chunks({0, 0}, {250, 250}, {100, 100})
      [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}, {2, 0}, {2, 1}, {2, 2}]

      iex> ExZarr.Chunk.slice_to_chunks({0, 0}, {100, 100}, {100, 100})
      [{0, 0}]

      iex> ExZarr.Chunk.slice_to_chunks({50, 50}, {150, 150}, {100, 100})
      [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

  ## Returns

  List of chunk index tuples, ordered by chunk position (row-major).
  """
  @spec slice_to_chunks(tuple(), tuple(), tuple()) :: [tuple()]
  def slice_to_chunks(start_index, stop_index, chunk_shape) do
    start_chunk = index_to_chunk(start_index, chunk_shape)
    # Subtract 1 from stop to get the last included index
    stop_adjusted =
      stop_index
      |> Tuple.to_list()
      |> Enum.map(&max(0, &1 - 1))
      |> List.to_tuple()

    stop_chunk = index_to_chunk(stop_adjusted, chunk_shape)

    ranges =
      start_chunk
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(stop_chunk))
      |> Enum.map(fn {start, stop} -> start..stop end)

    cartesian_product_to_tuples(ranges)
  end

  @doc """
  Converts a flat index to a multi-dimensional index.

  Converts a single integer index (as used in linear array representations)
  to a tuple of coordinates for an N-dimensional array. Uses row-major
  (C-order) layout.

  ## Parameters

  - `flat_index` - Non-negative integer index (0-based)
  - `shape` - Tuple of array dimensions

  ## Examples

      iex> ExZarr.Chunk.flat_to_multi(15, {10, 10})
      {1, 5}

      iex> ExZarr.Chunk.flat_to_multi(0, {10, 10})
      {0, 0}

      iex> ExZarr.Chunk.flat_to_multi(99, {10, 10})
      {9, 9}

      # 3D example
      iex> ExZarr.Chunk.flat_to_multi(25, {5, 5, 5})
      {1, 0, 0}

  ## Returns

  Tuple of coordinates in the N-dimensional array.
  """
  @spec flat_to_multi(non_neg_integer(), tuple()) :: tuple()
  def flat_to_multi(flat_index, shape) do
    shape
    |> Tuple.to_list()
    |> Enum.reverse()
    |> Enum.reduce({flat_index, []}, fn dim_size, {remaining, indices} ->
      idx = rem(remaining, dim_size)
      {div(remaining, dim_size), [idx | indices]}
    end)
    |> elem(1)
    |> List.to_tuple()
  end

  @doc """
  Converts a multi-dimensional index to a flat index.

  Converts a tuple of coordinates to a single integer index for row-major
  (C-order) layout. This is the inverse of `flat_to_multi/2`.

  ## Parameters

  - `multi_index` - Tuple of coordinates
  - `shape` - Tuple of array dimensions

  ## Examples

      iex> ExZarr.Chunk.multi_to_flat({1, 5}, {10, 10})
      15

      iex> ExZarr.Chunk.multi_to_flat({0, 0}, {10, 10})
      0

      iex> ExZarr.Chunk.multi_to_flat({9, 9}, {10, 10})
      99

      # 3D example
      iex> ExZarr.Chunk.multi_to_flat({1, 0, 0}, {5, 5, 5})
      25

  ## Returns

  Non-negative integer representing the flat index.
  """
  @spec multi_to_flat(tuple(), tuple()) :: non_neg_integer()
  def multi_to_flat(multi_index, shape) do
    multi_index
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(shape))
    |> Enum.reduce({0, 1}, fn {idx, dim_size}, {acc, multiplier} ->
      # Calculate from rightmost dimension
      strides =
        shape
        |> Tuple.to_list()
        |> Enum.reverse()
        |> Enum.take_while(&(&1 != dim_size))
        |> Enum.reduce(1, &(&1 * &2))

      {acc + idx * strides, multiplier * dim_size}
    end)
    |> elem(0)
  end

  @doc """
  Calculates the strides for C-order (row-major) layout.

  Strides define the number of elements to skip in memory to move one position
  along each dimension. For C-order (row-major), the rightmost dimension has
  stride 1, and each dimension to the left has a stride equal to the product
  of all dimensions to its right.

  ## Parameters

  - `shape` - Tuple of array dimensions

  ## Examples

      # 2D array: {10, 10}
      iex> ExZarr.Chunk.calculate_strides({10, 10})
      {10, 1}

      # To move one row: skip 10 elements
      # To move one column: skip 1 element

      # 3D array: {5, 10, 20}
      iex> ExZarr.Chunk.calculate_strides({5, 10, 20})
      {200, 20, 1}

      # To move in first dimension: skip 200 elements (10 * 20)
      # To move in second dimension: skip 20 elements
      # To move in third dimension: skip 1 element

  ## Returns

  Tuple of stride values (same length as shape), in descending order for
  C-order layout.
  """
  @spec calculate_strides(tuple()) :: tuple()
  def calculate_strides(shape) do
    shape
    |> Tuple.to_list()
    |> Enum.reverse()
    |> Enum.reduce({[], 1}, fn dim, {strides, stride} ->
      {[stride | strides], stride * dim}
    end)
    |> elem(0)
    |> List.to_tuple()
  end

  ## Private Functions

  # Generate cartesian product of ranges and convert to tuples
  defp cartesian_product_to_tuples(ranges) do
    cartesian_product(ranges)
    |> Enum.map(&List.to_tuple/1)
  end

  # Generate cartesian product of ranges (returns list of lists)
  defp cartesian_product([]), do: [[]]

  defp cartesian_product([range | rest]) do
    rest_product = cartesian_product(rest)

    for x <- range, rest_item <- rest_product do
      [x | rest_item]
    end
  end
end
