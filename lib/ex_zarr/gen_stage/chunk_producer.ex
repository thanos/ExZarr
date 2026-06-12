if Code.ensure_loaded?(GenStage) do
  defmodule ExZarr.GenStage.ChunkProducer do
    @moduledoc """
    GenStage producer that emits Zarr chunks on demand.

    The producer stops with `:normal` after all chunk indices are consumed.

    ## Examples

        children = [
          {ExZarr.GenStage.ChunkProducer, array: array}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
    """

    use GenStage

    alias ExZarr.Streaming.Producer

    @doc false
    def start_link(opts) do
      GenStage.start_link(__MODULE__, opts)
    end

    @impl GenStage
    def init(opts) do
      array = Keyword.fetch!(opts, :array)
      stream_opts = Keyword.get(opts, :stream_opts, [])

      {:producer, Producer.chunk_init(array, stream_opts)}
    end

    @impl GenStage
    def handle_demand(_demand, %{remaining: []} = state) do
      {:stop, :normal, state}
    end

    def handle_demand(demand, state) when demand > 0 do
      {events, new_state} = Producer.chunk_demand(demand, state)
      {:noreply, events, new_state}
    end
  end
else
  defmodule ExZarr.GenStage.ChunkProducer do
    @moduledoc false

    @doc false
    def start_link(_opts) do
      {:error,
       %ArgumentError{
         message: "GenStage is required. Add {:gen_stage, \"~> 1.2\"} to your deps."
       }}
    end
  end
end
