defmodule ExZarr.ChunkGrid.Irregular do
  @moduledoc """
  Irregular chunk grid implementation for Zarr v3.

  In an irregular chunk grid, chunks can have different shapes. This is useful
  for arrays where different regions have different optimal chunk sizes, such
  as datasets with varying spatial or temporal resolution.

  ## Configuration

  The configuration map can specify chunk shapes in two ways:

  ### 1. Per-dimension chunk sizes

      %{
        "chunk_sizes" => [[50, 50, 25], [100, 50, 50]]
      }

  Each inner list specifies the chunk sizes along one dimension.

  ### 2. Explicit chunk index to shape mapping

      %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100],
          "{0,1}" => [50, 50],
          "{1,0}" => [25, 100],
          "{1,1}" => [25, 50]
        }
      }

  ## Example

      # Variable resolution: first chunks are larger
      config = %{
        "chunk_sizes" => [
          [500, 250, 250],  # First dim: 500, 250, 250
          [500, 500]        # Second dim: 500, 500
        ]
      }

      {:ok, grid} = ExZarr.ChunkGrid.Irregular.init(config)

  ## Specification

  Zarr v3 extensions may define irregular chunk grid patterns.
  This implementation provides a flexible foundation for such patterns.
  """

  @behaviour ExZarr.ChunkGrid

  defstruct [:chunk_sizes, :chunk_shapes_map, :array_shape]

  @type t :: %__MODULE__{
          chunk_sizes: list(list(non_neg_integer())) | nil,
          chunk_shapes_map: %{tuple() => tuple()} | nil,
          array_shape: tuple() | nil
        }

  @impl true
  def init(config) when is_map(config) do
    cond do
      Map.has_key?(config, "chunk_sizes") ->
        init_from_chunk_sizes(config)

      Map.has_key?(config, "chunk_shapes") ->
        init_from_chunk_shapes(config)

      true ->
        {:error, {:missing_config, "chunk_sizes or chunk_shapes required for irregular grid"}}
    end
  end

  defp init_from_chunk_sizes(config) do
    chunk_sizes = Map.get(config, "chunk_sizes")

    if is_list(chunk_sizes) and Enum.all?(chunk_sizes, &is_list/1) do
      {:ok, %__MODULE__{chunk_sizes: chunk_sizes, chunk_shapes_map: nil, array_shape: nil}}
    else
      {:error, {:invalid_chunk_sizes, "chunk_sizes must be a list of lists"}}
    end
  end

  defp init_from_chunk_shapes(config) do
    chunk_shapes = Map.get(config, "chunk_shapes")

    if is_map(chunk_shapes) do
      # Parse chunk index strings to tuples
      parsed =
        Enum.reduce_while(chunk_shapes, {:ok, %{}}, fn {key, shape}, {:ok, acc} ->
          case parse_chunk_index(key) do
            {:ok, index} ->
              shape_tuple = if is_list(shape), do: List.to_tuple(shape), else: shape
              {:cont, {:ok, Map.put(acc, index, shape_tuple)}}

            {:error, _} = error ->
              {:halt, error}
          end
        end)

      case parsed do
        {:ok, shapes_map} ->
          {:ok, %__MODULE__{chunk_sizes: nil, chunk_shapes_map: shapes_map, array_shape: nil}}

        error ->
          error
      end
    else
      {:error, {:invalid_chunk_shapes, "chunk_shapes must be a map"}}
    end
  end

  defp parse_chunk_index(str) when is_binary(str) do
    # Parse strings like "{0,1,2}" to tuples
    trimmed = String.trim(str)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      inner = String.slice(trimmed, 1..-2//1)

      indices =
        inner
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&Integer.parse/1)
        |> Enum.map(fn
          {int, ""} -> {:ok, int}
          _ -> :error
        end)

      if Enum.all?(indices, &match?({:ok, _}, &1)) do
        values = Enum.map(indices, fn {:ok, val} -> val end)
        {:ok, List.to_tuple(values)}
      else
        {:error, {:invalid_index_format, str}}
      end
    else
      {:error, {:invalid_index_format, str}}
    end
  end

  @doc """
  Set the array shape for this chunk grid.

  Required for validation and calculations.
  """
  @spec set_array_shape(t(), tuple()) :: t()
  def set_array_shape(%__MODULE__{} = grid, array_shape) when is_tuple(array_shape) do
    %{grid | array_shape: array_shape}
  end

  @impl true
  def chunk_shape(chunk_index, %__MODULE__{chunk_shapes_map: shapes_map})
      when is_map(shapes_map) do
    # Direct lookup
    Map.get(shapes_map, chunk_index, {0})
  end

  def chunk_shape(chunk_index, %__MODULE__{chunk_sizes: chunk_sizes, array_shape: _array_shape})
      when is_list(chunk_sizes) and is_tuple(chunk_index) do
    # Calculate from chunk_sizes
    chunk_index
    |> Tuple.to_list()
    |> Enum.zip(chunk_sizes)
    |> Enum.map(fn {idx, sizes} ->
      Enum.at(sizes, idx, 0)
    end)
    |> List.to_tuple()
  end

  def chunk_shape(_chunk_index, %__MODULE__{}) do
    {0}
  end

  @impl true
  def chunk_count(%__MODULE__{chunk_shapes_map: shapes_map}) when is_map(shapes_map) do
    map_size(shapes_map)
  end

  def chunk_count(%__MODULE__{chunk_sizes: chunk_sizes}) when is_list(chunk_sizes) do
    # Product of lengths of each dimension's size list
    chunk_sizes
    |> Enum.map(&length/1)
    |> Enum.reduce(1, &Kernel.*/2)
  end

  def chunk_count(%__MODULE__{}) do
    0
  end

  @impl true
  def validate(config, array_shape) when is_map(config) and is_tuple(array_shape) do
    cond do
      Map.has_key?(config, "chunk_sizes") ->
        validate_chunk_sizes(config, array_shape)

      Map.has_key?(config, "chunk_shapes") ->
        validate_chunk_shapes(config, array_shape)

      true ->
        {:error, {:missing_config, "chunk_sizes or chunk_shapes required"}}
    end
  end

  defp validate_chunk_sizes(config, array_shape) do
    chunk_sizes = Map.get(config, "chunk_sizes")
    ndim = tuple_size(array_shape)

    cond do
      not is_list(chunk_sizes) ->
        {:error, {:invalid_chunk_sizes, "chunk_sizes must be a list"}}

      length(chunk_sizes) != ndim ->
        {:error,
         {:dimension_mismatch,
          "chunk_sizes dimensions (#{length(chunk_sizes)}) must match array dimensions (#{ndim})"}}

      not Enum.all?(chunk_sizes, &is_list/1) ->
        {:error, {:invalid_chunk_sizes, "each dimension must have a list of sizes"}}

      true ->
        # Validate that sizes sum to array dimensions
        array_dims = Tuple.to_list(array_shape)

        results =
          Enum.zip(chunk_sizes, array_dims)
          |> Enum.map(fn {sizes, array_dim} ->
            total = Enum.sum(sizes)

            if total == array_dim do
              :ok
            else
              {:error,
               {:size_mismatch,
                "chunk sizes (total: #{total}) must sum to array dimension (#{array_dim})"}}
            end
          end)

        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> :ok
          error -> error
        end
    end
  end

  defp validate_chunk_shapes(config, array_shape) do
    chunk_shapes = Map.get(config, "chunk_shapes")
    ndim = tuple_size(array_shape)

    cond do
      not is_map(chunk_shapes) ->
        {:error, {:invalid_chunk_shapes, "chunk_shapes must be a map"}}

      map_size(chunk_shapes) == 0 ->
        {:error, {:invalid_chunk_shapes, "chunk_shapes cannot be empty"}}

      true ->
        # Validate each chunk shape
        Enum.reduce_while(chunk_shapes, :ok, fn {key, shape}, _acc ->
          shape_list = if is_list(shape), do: shape, else: Tuple.to_list(shape)

          cond do
            length(shape_list) != ndim ->
              {:halt,
               {:error,
                {:dimension_mismatch,
                 "chunk shape #{inspect(key)} dimensions (#{length(shape_list)}) must match array dimensions (#{ndim})"}}}

            not Enum.all?(shape_list, fn dim -> is_integer(dim) and dim > 0 end) ->
              {:halt,
               {:error,
                {:invalid_chunk_shape, "all dimensions in #{inspect(key)} must be positive"}}}

            true ->
              {:cont, :ok}
          end
        end)
    end
  end

  @doc """
  Get all chunk indices for this irregular grid.

  ## Parameters

    * `grid` - Irregular chunk grid state

  ## Returns

    * List of chunk index tuples
  """
  @spec all_chunk_indices(t()) :: [tuple()]
  def all_chunk_indices(%__MODULE__{chunk_shapes_map: shapes_map}) when is_map(shapes_map) do
    Map.keys(shapes_map)
  end

  def all_chunk_indices(%__MODULE__{chunk_sizes: chunk_sizes}) when is_list(chunk_sizes) do
    # Generate indices based on chunk_sizes
    chunk_counts = Enum.map(chunk_sizes, &length/1)
    generate_indices(chunk_counts)
  end

  def all_chunk_indices(%__MODULE__{}) do
    []
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
