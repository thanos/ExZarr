defmodule ExZarr.Chunk do
  @moduledoc """
  Chunk handling utilities for Zarr arrays.

  Provides functions for:
  - Calculating chunk indices from array indices
  - Converting between flat and multi-dimensional indices
  - Chunk coordinate operations
  """

  @doc """
  Calculates which chunk contains a given array index.

  ## Examples

      iex> ExZarr.Chunk.index_to_chunk({150, 250}, {100, 100})
      {1, 2}
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

  Returns a tuple of {start_index, end_index} for the chunk.

  ## Examples

      iex> ExZarr.Chunk.chunk_bounds({1, 2}, {100, 100}, {1000, 1000})
      {{100, 200}, {200, 300}}
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

  ## Examples

      iex> ExZarr.Chunk.slice_to_chunks({0, 0}, {250, 250}, {100, 100})
      [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}, {2, 0}, {2, 1}, {2, 2}]
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

    cartesian_product(ranges)
  end

  @doc """
  Converts a flat index to a multi-dimensional index.

  ## Examples

      iex> ExZarr.Chunk.flat_to_multi(15, {10, 10})
      {1, 5}
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

  ## Examples

      iex> ExZarr.Chunk.multi_to_flat({1, 5}, {10, 10})
      15
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

  # Generate cartesian product of ranges
  defp cartesian_product([]), do: [[]]

  defp cartesian_product([range | rest]) do
    rest_product = cartesian_product(rest)

    for x <- range, rest <- rest_product do
      [x | rest]
    end
    |> Enum.map(&List.to_tuple/1)
  end
end
