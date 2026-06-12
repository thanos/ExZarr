if Code.ensure_loaded?(GenStage) do
  defmodule ExZarr.GenStage.SliceProducer do
    @moduledoc """
    GenStage producer that emits Zarr array slices on demand.

    The producer stops with `:normal` after all slice specs are consumed.
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
      along = Keyword.fetch!(opts, :along)
      stream_opts = Keyword.get(opts, :stream_opts, [])

      {:producer, Producer.slice_init(array, along, stream_opts)}
    end

    @impl GenStage
    def handle_demand(_demand, %{remaining: []} = state) do
      {:stop, :normal, state}
    end

    def handle_demand(demand, state) when demand > 0 do
      {events, new_state} = Producer.slice_demand(demand, state)
      {:noreply, events, new_state}
    end
  end
else
  defmodule ExZarr.GenStage.SliceProducer do
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
