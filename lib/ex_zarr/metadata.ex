defmodule ExZarr.Metadata do
  @moduledoc """
  Metadata management for Zarr arrays.

  Handles the .zarray metadata file that describes the array's structure,
  data type, compression, and other attributes.
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
  """
  @spec total_chunks(t()) :: non_neg_integer()
  def total_chunks(metadata) do
    metadata
    |> num_chunks()
    |> Tuple.to_list()
    |> Enum.reduce(1, &(&1 * &2))
  end

  @doc """
  Returns the size of a chunk in bytes.
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
