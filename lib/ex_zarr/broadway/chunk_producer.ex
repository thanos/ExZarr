if Code.ensure_loaded?(Broadway) do
  defmodule ExZarr.Broadway.ChunkProducer do
    @moduledoc false

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

      messages =
        Enum.map(events, fn
          {index, data} -> chunk_message({index, data})
          %{index: index, data: data} -> chunk_message({index, data})
        end)

      {:noreply, messages, new_state}
    end

    defp chunk_message(data) do
      %Broadway.Message{
        data: data,
        acknowledger: Broadway.NoopAcknowledger.init()
      }
    end
  end
else
  defmodule ExZarr.Broadway.ChunkProducer do
    @moduledoc false

    @doc false
    def start_link(_opts) do
      {:error,
       %ArgumentError{
         message: "Broadway is required. Add {:broadway, \"~> 1.0\"} to your deps."
       }}
    end
  end
end
