defmodule ExZarr.GenStage do
  @moduledoc """
  GenStage integration for demand-driven Zarr chunk and slice processing.

  GenStage producers emit chunks or slices only when downstream consumers
  request them, providing explicit backpressure for large array pipelines.

  GenStage is an optional dependency:

      {:gen_stage, "~> 1.2"}

  ## Modules

    * `ExZarr.GenStage.ChunkProducer` - emits `{index, data}` chunk events
    * `ExZarr.GenStage.SliceProducer` - emits `{start, data}` slice events

  ## Examples

      # Chunk producer with a consumer
      {:ok, producer} =
        ExZarr.GenStage.ChunkProducer.start_link(array: array, stream_opts: [metadata: true])

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
  """
  @spec start_chunk_producer(Array.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_chunk_producer(array, opts \\ []) do
    ChunkProducer.start_link(Keyword.put(opts, :array, array))
  end

  @doc """
  Starts a supervised slice producer for the given array and dimension.
  """
  @spec start_slice_producer(Array.t(), non_neg_integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_slice_producer(array, along, opts \\ []) do
    SliceProducer.start_link(array: array, along: along, stream_opts: opts)
  end
end
