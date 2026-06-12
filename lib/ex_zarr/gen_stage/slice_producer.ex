if Code.ensure_loaded?(GenStage) do
  defmodule ExZarr.GenStage.SliceProducer do
    @moduledoc """
    GenStage producer that emits Zarr array slices on demand.
    """

    use GenStage

    alias ExZarr.Array

    defstruct [:array, :along, :opts, :specs, :position]

    @doc false
    def start_link(opts) do
      GenStage.start_link(__MODULE__, opts)
    end

    @impl GenStage
    def init(opts) do
      array = Keyword.fetch!(opts, :array)
      along = Keyword.fetch!(opts, :along)
      stream_opts = Keyword.get(opts, :stream_opts, [])
      specs = ExZarr.Streaming.slice_specs(array, along, stream_opts)

      {:producer,
       %__MODULE__{array: array, along: along, opts: stream_opts, specs: specs, position: 0}}
    end

    @impl GenStage
    def handle_demand(demand, %{array: array, opts: opts, specs: specs, position: pos} = state)
        when demand > 0 do
      {events, new_pos} = read_events(array, specs, pos, demand, opts)
      {:noreply, events, %{state | position: new_pos}}
    end

    defp read_events(array, specs, pos, demand, opts) do
      specs
      |> Enum.drop(pos)
      |> Enum.reduce_while({[], pos}, fn {start_coords, stop_coords}, {events, position} ->
        if length(events) == demand do
          {:halt, {events, position}}
        else
          case Array.get_slice(array, start: start_coords, stop: stop_coords) do
            {:ok, data} ->
              event =
                if Keyword.get(opts, :metadata, false) do
                  %{
                    index: start_coords,
                    data: data,
                    metadata: %{stop: stop_coords, bytes: byte_size(data)}
                  }
                else
                  {start_coords, data}
                end

              {:cont, {[event | events], position + 1}}

            {:error, _} ->
              {:cont, {events, position + 1}}
          end
        end
      end)
      |> then(fn {events, new_pos} -> {Enum.reverse(events), new_pos} end)
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
