if Code.ensure_loaded?(GenStage) do
  defmodule ExZarr.GenStage.ChunkProducer do
    @moduledoc """
    GenStage producer that emits Zarr chunks on demand.

    ## Examples

        children = [
          {ExZarr.GenStage.ChunkProducer, array: array}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
    """

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
      {events, new_pos} = read_events(array, indices, pos, demand, opts)
      {:noreply, events, %{state | position: new_pos}}
    end

    defp read_events(array, indices, pos, demand, opts) do
      indices
      |> Enum.drop(pos)
      |> Enum.reduce_while({[], pos}, fn chunk_index, {events, position} ->
        if length(events) == demand do
          {:halt, {events, position}}
        else
          case ExZarr.Streaming.build_chunk_from_read(array, chunk_index, opts) do
            nil -> {:cont, {events, position + 1}}
            event -> {:cont, {[event | events], position + 1}}
          end
        end
      end)
      |> then(fn {events, new_pos} -> {Enum.reverse(events), new_pos} end)
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
