defmodule ExZarr.GenStage do
  @moduledoc """
  GenStage integration for demand-driven Zarr chunk and slice processing.

  GenStage producers emit chunks or slices only when downstream consumers
  request them, providing explicit backpressure for large array pipelines.
  Producers stop with `:normal` after the array is fully consumed.

  GenStage is an optional dependency:

      {:gen_stage, "~> 1.2"}

  ## Modules

    * `ExZarr.GenStage.ChunkProducer` - emits `{index, data}` chunk events
    * `ExZarr.GenStage.SliceProducer` - emits `{start, data}` slice events

  ## Examples

      {:ok, producer} = ExZarr.GenStage.start_chunk_producer(array, metadata: true)

      {:ok, consumer} = MyApp.ChunkConsumer.start_link(producer: producer)
      GenStage.ask(producer, 10)

  ## Backpressure

  Downstream consumers control throughput by adjusting demand. When a consumer
  is overloaded, it stops asking for events and chunk reads pause automatically.
  """

  alias ExZarr.Array
  alias ExZarr.GenStage.{ChunkProducer, SliceProducer}

  @doc """
  Starts a supervised chunk producer for the given array.

  Stream options may be passed flat (e.g. `metadata: true`) or nested under
  `:stream_opts`.
  """
  @spec start_chunk_producer(Array.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_chunk_producer(array, opts \\ []) do
    ChunkProducer.start_link(chunk_producer_opts(array, opts))
  end

  @doc """
  Starts a supervised slice producer for the given array and dimension.

  Stream options may be passed flat or nested under `:stream_opts`.
  """
  @spec start_slice_producer(Array.t(), non_neg_integer(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_slice_producer(array, along, opts \\ []) do
    SliceProducer.start_link(slice_producer_opts(array, along, opts))
  end

  defp chunk_producer_opts(array, opts) do
    if Keyword.has_key?(opts, :stream_opts) do
      Keyword.put(opts, :array, array)
    else
      [array: array, stream_opts: opts]
    end
  end

  defp slice_producer_opts(array, along, opts) do
    if Keyword.has_key?(opts, :stream_opts) do
      Keyword.merge(opts, array: array, along: along)
    else
      [array: array, along: along, stream_opts: opts]
    end
  end
end
