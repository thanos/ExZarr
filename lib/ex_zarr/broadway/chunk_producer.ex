if Code.ensure_loaded?(Broadway) do
  defmodule ExZarr.Broadway.ChunkProducer do
    @moduledoc false

    use GenStage

    defstruct [:array, :opts, :indices, :position]

    @doc false
    def start_link(opts) do
      GenStage.start_link(__MODULE__, opts)
    end

    @impl GenStage
    def init(opts) do
      array = Keyword.fetch!(opts, :array)
      stream_opts = Keyword.get(opts, :stream_opts, [])
      indices = ExZarr.Streaming.chunk_indices(array, stream_opts)

      {:producer, %__MODULE__{array: array, opts: stream_opts, indices: indices, position: 0}}
    end

    @impl GenStage
    def handle_demand(demand, %{array: array, opts: opts, indices: indices, position: pos} = state)
        when demand > 0 do
      events =
        indices
        |> Enum.drop(pos)
        |> Enum.take(demand)
        |> Enum.map(fn chunk_index ->
          case ExZarr.Streaming.build_chunk_from_read(array, chunk_index, opts) do
            nil ->
              nil

            {index, data} ->
              chunk_message({index, data})

            %{index: index, data: data} ->
              chunk_message({index, data})
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:noreply, events, %{state | position: pos + length(events)}}
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
