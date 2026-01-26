defmodule ExZarr.Indexing do
  @moduledoc """
  Advanced indexing operations for ExZarr arrays.

  This module provides comprehensive indexing support including:

  - Basic slicing with step support
  - Negative index handling
  - Fancy indexing (integer arrays)
  - Boolean indexing (masks)
  - Block indexing (chunk-aligned access)

  ## Index Normalization

  Indices can be negative (counting from the end) and are automatically
  normalized to positive values:

      normalize_index(-1, 10) # => 9
      normalize_index(-5, 10) # => 5
      normalize_index(5, 10)  # => 5

  ## Slice Specifications

  Slices can include start, stop, and step:

      %{start: 0, stop: 10, step: 1}    # Every element from 0 to 9
      %{start: 0, stop: 10, step: 2}    # Every other element
      %{start: 10, stop: 0, step: -1}   # Reverse order

  """

  @type index :: integer()
  @type slice_spec :: %{
          start: index() | nil,
          stop: index() | nil,
          step: integer()
        }
  @type index_spec :: index() | slice_spec() | list(index()) | {:boolean, tuple()}

  @doc """
  Normalizes an index to a positive value within bounds.

  Handles negative indices by counting from the end of the dimension.
  Validates that the index is within the valid range [0, size).

  ## Examples

      iex> ExZarr.Indexing.normalize_index(5, 10)
      {:ok, 5}

      iex> ExZarr.Indexing.normalize_index(-1, 10)
      {:ok, 9}

      iex> ExZarr.Indexing.normalize_index(-5, 10)
      {:ok, 5}

      iex> ExZarr.Indexing.normalize_index(15, 10)
      {:error, :index_out_of_bounds}
  """
  @spec normalize_index(index(), pos_integer()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def normalize_index(index, size) when is_integer(index) and is_integer(size) and size > 0 do
    normalized =
      if index < 0 do
        size + index
      else
        index
      end

    if normalized >= 0 and normalized < size do
      {:ok, normalized}
    else
      {:error, :index_out_of_bounds}
    end
  end

  @doc """
  Normalizes a slice specification to have explicit start, stop, and step values.

  Fills in defaults for missing values:
  - start defaults to 0 (or size-1 for negative step)
  - stop defaults to size (or -1 for negative step)
  - step defaults to 1

  Handles negative indices and validates the slice is within bounds.

  ## Examples

      iex> ExZarr.Indexing.normalize_slice(%{start: 0, stop: 10, step: 1}, 20)
      {:ok, %{start: 0, stop: 10, step: 1}}

      iex> ExZarr.Indexing.normalize_slice(%{start: -5, stop: nil, step: 1}, 20)
      {:ok, %{start: 15, stop: 20, step: 1}}

      iex> ExZarr.Indexing.normalize_slice(%{start: nil, stop: nil, step: -1}, 20)
      {:ok, %{start: 19, stop: -1, step: -1}}
  """
  @spec normalize_slice(slice_spec(), pos_integer()) ::
          {:ok, slice_spec()} | {:error, term()}
  def normalize_slice(slice, size) when is_map(slice) and is_integer(size) and size > 0 do
    step = Map.get(slice, :step, 1)

    if step == 0 do
      {:error, :step_cannot_be_zero}
    else
      # Determine defaults based on step direction
      {default_start, default_stop} =
        if step > 0 do
          {0, size}
        else
          {size - 1, -1}
        end

      # Get and normalize start
      start = Map.get(slice, :start, default_start)

      start_normalized =
        if start == nil do
          default_start
        else
          case normalize_index(start, size) do
            {:ok, idx} -> idx
            # Allow -1 as stop for negative step
            {:error, :index_out_of_bounds} when start == -1 and step < 0 -> -1
            {:error, reason} -> {:error, reason}
          end
        end

      # Get and normalize stop
      stop = Map.get(slice, :stop, default_stop)

      stop_normalized =
        if stop == nil do
          default_stop
        else
          case normalize_index(stop, size) do
            {:ok, idx} -> idx
            # Allow size as stop (exclusive upper bound)
            {:error, :index_out_of_bounds} when stop == size -> size
            # Allow -1 as stop for negative step
            {:error, :index_out_of_bounds} when stop == -1 and step < 0 -> -1
            {:error, reason} -> {:error, reason}
          end
        end

      case {start_normalized, stop_normalized} do
        {{:error, reason}, _} -> {:error, reason}
        {_, {:error, reason}} -> {:error, reason}
        {start_idx, stop_idx} -> {:ok, %{start: start_idx, stop: stop_idx, step: step}}
      end
    end
  end

  @doc """
  Computes the effective slice range from a normalized slice specification.

  Returns a list of indices that the slice covers, handling step correctly.
  This is useful for computing the actual size of a slice result.

  ## Examples

      iex> ExZarr.Indexing.slice_indices(%{start: 0, stop: 10, step: 1})
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

      iex> ExZarr.Indexing.slice_indices(%{start: 0, stop: 10, step: 2})
      [0, 2, 4, 6, 8]

      iex> ExZarr.Indexing.slice_indices(%{start: 10, stop: 0, step: -2})
      [10, 8, 6, 4, 2]
  """
  @spec slice_indices(slice_spec()) :: list(integer())
  def slice_indices(%{start: start, stop: stop, step: step}) do
    cond do
      step > 0 and start < stop ->
        Stream.iterate(start, &(&1 + step))
        |> Enum.take_while(&(&1 < stop))

      step < 0 and start > stop ->
        Stream.iterate(start, &(&1 + step))
        |> Enum.take_while(&(&1 > stop))

      true ->
        []
    end
  end

  @doc """
  Computes the size (number of elements) of a slice.

  ## Examples

      iex> ExZarr.Indexing.slice_size(%{start: 0, stop: 10, step: 1})
      10

      iex> ExZarr.Indexing.slice_size(%{start: 0, stop: 10, step: 2})
      5

      iex> ExZarr.Indexing.slice_size(%{start: 10, stop: 0, step: -1})
      10
  """
  @spec slice_size(slice_spec()) :: non_neg_integer()
  def slice_size(%{start: start, stop: stop, step: step}) do
    cond do
      step > 0 and start < stop ->
        div(stop - start + step - 1, step)

      step < 0 and start > stop ->
        div(start - stop - step - 1, abs(step))

      true ->
        0
    end
  end

  @doc """
  Converts a multidimensional slice specification to start/stop tuples for each dimension.

  Takes a list of index specifications (integers, slices, or arrays) and converts
  them to normalized start/stop tuples per dimension.

  ## Examples

      iex> ExZarr.Indexing.parse_slice_spec([5, %{start: 0, stop: 10, step: 1}], {100, 100})
      {:ok, {[5], [%{start: 0, stop: 10, step: 1}]}}
  """
  @spec parse_slice_spec(list(index_spec()), tuple()) ::
          {:ok, {list(), list()}} | {:error, term()}
  def parse_slice_spec(specs, shape) when is_list(specs) and is_tuple(shape) do
    shape_list = Tuple.to_list(shape)

    if length(specs) > length(shape_list) do
      {:error, :too_many_indices}
    else
      # Pad specs with full slices if fewer specs than dimensions
      padded_specs =
        specs ++
          List.duplicate(%{start: nil, stop: nil, step: 1}, length(shape_list) - length(specs))

      # Normalize each spec against its dimension size
      result =
        Enum.zip(padded_specs, shape_list)
        |> Enum.reduce_while({[], []}, fn {spec, dim_size}, {indices, slices} ->
          case normalize_index_spec(spec, dim_size) do
            {:ok, :integer, idx} ->
              {:cont, {[idx | indices], slices}}

            {:ok, :slice, slice_spec} ->
              {:cont, {indices, [slice_spec | slices]}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      case result do
        {:error, reason} -> {:error, reason}
        {indices, slices} -> {:ok, {Enum.reverse(indices), Enum.reverse(slices)}}
      end
    end
  end

  @doc false
  defp normalize_index_spec(spec, dim_size) when is_integer(spec) do
    case normalize_index(spec, dim_size) do
      {:ok, idx} -> {:ok, :integer, idx}
      error -> error
    end
  end

  defp normalize_index_spec(spec, dim_size) when is_map(spec) do
    case normalize_slice(spec, dim_size) do
      {:ok, normalized} -> {:ok, :slice, normalized}
      error -> error
    end
  end

  defp normalize_index_spec(spec, _dim_size) do
    {:error, {:invalid_index_spec, spec}}
  end

  @doc """
  Validates fancy indexing with integer arrays.

  Ensures all indices in the array are within bounds for the dimension.

  ## Examples

      iex> ExZarr.Indexing.validate_fancy_indices([0, 5, 9], 10)
      :ok

      iex> ExZarr.Indexing.validate_fancy_indices([0, 5, 15], 10)
      {:error, :index_out_of_bounds}
  """
  @spec validate_fancy_indices(list(integer()), pos_integer()) :: :ok | {:error, term()}
  def validate_fancy_indices(indices, dim_size) when is_list(indices) and is_integer(dim_size) do
    invalid =
      Enum.find(indices, fn idx ->
        case normalize_index(idx, dim_size) do
          {:ok, _} -> false
          {:error, _} -> true
        end
      end)

    if invalid do
      {:error, :index_out_of_bounds}
    else
      :ok
    end
  end

  @doc """
  Validates boolean indexing with a mask.

  Ensures the mask has the same shape as the dimension being indexed.

  ## Examples

      iex> mask = {true, false, true, false, true}
      iex> ExZarr.Indexing.validate_boolean_mask(mask, 5)
      :ok

      iex> mask = {true, false, true}
      iex> ExZarr.Indexing.validate_boolean_mask(mask, 5)
      {:error, :mask_size_mismatch}
  """
  @spec validate_boolean_mask(tuple(), pos_integer()) :: :ok | {:error, term()}
  def validate_boolean_mask(mask, dim_size) when is_tuple(mask) and is_integer(dim_size) do
    if tuple_size(mask) == dim_size do
      # Verify all elements are boolean
      all_boolean? =
        mask
        |> Tuple.to_list()
        |> Enum.all?(&is_boolean/1)

      if all_boolean? do
        :ok
      else
        {:error, :mask_must_contain_only_booleans}
      end
    else
      {:error, :mask_size_mismatch}
    end
  end

  @doc """
  Extracts indices from a boolean mask.

  Returns a list of indices where the mask is true.

  ## Examples

      iex> mask = {true, false, true, false, true}
      iex> ExZarr.Indexing.mask_to_indices(mask)
      [0, 2, 4]
  """
  @spec mask_to_indices(tuple()) :: list(integer())
  def mask_to_indices(mask) when is_tuple(mask) do
    mask
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.filter(fn {value, _idx} -> value == true end)
    |> Enum.map(fn {_value, idx} -> idx end)
  end

  @doc """
  Computes chunk-aligned block boundaries for efficient access.

  Given a start/stop range and chunk size, computes the blocks that
  fully or partially overlap with the range. Returns block boundaries
  that are chunk-aligned.

  ## Examples

      iex> ExZarr.Indexing.compute_block_indices(5, 25, 10)
      [{0, 10}, {10, 20}, {20, 30}]

      iex> ExZarr.Indexing.compute_block_indices(10, 20, 10)
      [{10, 20}]
  """
  @spec compute_block_indices(non_neg_integer(), non_neg_integer(), pos_integer()) ::
          list({non_neg_integer(), non_neg_integer()})
  def compute_block_indices(start, stop, chunk_size)
      when is_integer(start) and is_integer(stop) and is_integer(chunk_size) and chunk_size > 0 do
    # Find first block that contains start
    first_block = div(start, chunk_size) * chunk_size

    # Generate all blocks until we reach or exceed stop
    Stream.iterate(first_block, &(&1 + chunk_size))
    |> Enum.take_while(&(&1 < stop))
    |> Enum.map(fn block_start ->
      block_end = min(block_start + chunk_size, stop)
      {block_start, block_end}
    end)
  end
end
