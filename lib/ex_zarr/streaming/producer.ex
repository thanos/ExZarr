defmodule ExZarr.Streaming.Producer do
  @moduledoc false

  alias ExZarr.{Array, Streaming}

  @doc false
  @spec chunk_init(Array.t(), keyword()) :: map()
  def chunk_init(array, stream_opts) do
    %{
      array: array,
      opts: stream_opts,
      remaining: Streaming.chunk_indices(array, stream_opts)
    }
  end

  @doc false
  @spec chunk_demand(pos_integer(), map()) :: {[Streaming.chunk_event()], map()}
  def chunk_demand(demand, %{array: array, opts: opts, remaining: remaining} = state)
      when demand > 0 do
    {to_read, rest} = Enum.split(remaining, demand)

    events =
      Enum.flat_map(to_read, fn chunk_index ->
        case Streaming.build_chunk_from_read(array, chunk_index, opts) do
          nil -> []
          event -> [event]
        end
      end)

    {events, %{state | remaining: rest}}
  end

  @doc false
  @spec slice_init(Array.t(), non_neg_integer(), keyword()) :: map()
  def slice_init(array, along, stream_opts) do
    %{
      array: array,
      opts: stream_opts,
      remaining: Streaming.slice_specs(array, along, stream_opts)
    }
  end

  @doc false
  @spec slice_demand(pos_integer(), map()) :: {[Streaming.slice_event()], map()}
  def slice_demand(demand, %{array: array, opts: opts, remaining: remaining} = state)
      when demand > 0 do
    {to_read, rest} = Enum.split(remaining, demand)

    events =
      Enum.flat_map(to_read, fn {start_coords, stop_coords} ->
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

            [event]

          {:error, _} ->
            []
        end
      end)

    {events, %{state | remaining: rest}}
  end
end
