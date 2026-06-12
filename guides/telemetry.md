# Telemetry Guide

ExZarr v1.1+ emits `:telemetry` events for streaming and chunk I/O.

## Events

Chunk read and write use `:telemetry.span/3`. Attach to the `:stop` events for
duration measurements. Stream start/stop use `:telemetry.execute/3`.

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:ex_zarr, :chunk, :read, :stop]` | `%{duration: native_time}` | `%{array: ref, chunk_index: tuple}` |
| `[:ex_zarr, :chunk, :write, :stop]` | `%{duration: native_time, bytes: integer}` | `%{array: ref, chunk_index: tuple}` |
| `[:ex_zarr, :stream, :start]` | `%{}` | `%{array: ref, type: atom, opts: keyword}` |
| `[:ex_zarr, :stream, :stop]` | `%{duration: native_time, count: integer}` | `%{array: ref, type: atom}` |

`ExZarr.Telemetry.events/0` returns all attachable event names, including
`:start` and `:exception` variants for chunk spans.

## Installation

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    :telemetry.attach(
      "ex-zarr-chunk-reads",
      [:ex_zarr, :chunk, :read, :stop],
      fn _event, measurements, metadata, _config ->
        IO.inspect({measurements.duration, metadata.chunk_index})
      end,
      nil
    )

    Supervisor.start_link([], strategy: :one_for_one)
  end
end
```

## Stream Monitoring

```elixir
:telemetry.attach(
  "ex-zarr-stream-stop",
  [:ex_zarr, :stream, :stop],
  fn _event, %{duration: duration, count: count}, %{type: type}, _config ->
    IO.inspect({type, count, duration})
  end,
  nil
)

array
|> ExZarr.Array.stream_chunks(concurrency: 4)
|> Enum.to_list()
```

## Notes

- `array` metadata is a tuple `{shape, chunks, dtype}`, not the full struct.
- Stream `:type` is `:chunks`, `:slices`, or `:write`.
- Chunk span `:exception` events include metadata but no duration measurement.
