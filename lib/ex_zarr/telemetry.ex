defmodule ExZarr.Telemetry do
  @moduledoc """
  Telemetry instrumentation for ExZarr operations.

  ExZarr emits `:telemetry` events for chunk I/O, streaming, and storage
  operations. Attach handlers to monitor throughput, latency, and errors
  in production.

  Chunk read and write use `:telemetry.span/3`, which emits `:start`, `:stop`,
  and `:exception` suffixed events. Attach to the `:stop` events for duration
  measurements.

  ## Events

  | Event | Measurements | Metadata |
  |-------|-------------|----------|
  | `[:ex_zarr, :chunk, :read, :stop]` | `%{duration: native_time}` | `%{array: ref, chunk_index: tuple}` |
  | `[:ex_zarr, :chunk, :write, :stop]` | `%{duration: native_time, bytes: integer}` | `%{array: ref, chunk_index: tuple}` |
  | `[:ex_zarr, :stream, :start]` | `%{}` | `%{array: ref, type: atom, opts: keyword}` |
  | `[:ex_zarr, :stream, :stop]` | `%{duration: native_time, count: integer}` | `%{array: ref, type: atom}` |

  ## Examples

      :telemetry.attach(
        "ex-zarr-chunk-reads",
        [:ex_zarr, :chunk, :read, :stop],
        fn _event, measurements, metadata, _config ->
          IO.inspect({measurements.duration, metadata.chunk_index})
        end,
        nil
      )

      array
      |> ExZarr.Array.stream_chunks()
      |> Enum.to_list()
  """

  @chunk_read [:ex_zarr, :chunk, :read]
  @chunk_write [:ex_zarr, :chunk, :write]
  @stream_start [:ex_zarr, :stream, :start]
  @stream_stop [:ex_zarr, :stream, :stop]

  @doc false
  @spec chunk_read(tuple(), tuple(), (-> term())) :: term()
  def chunk_read(array_ref, chunk_index, fun) do
    metadata = %{array: array_ref, chunk_index: chunk_index}

    :telemetry.span(@chunk_read, metadata, fn ->
      result = fun.()
      {result, %{}}
    end)
  end

  @doc false
  @spec chunk_write(tuple(), tuple(), non_neg_integer(), (-> term())) :: term()
  def chunk_write(array_ref, chunk_index, bytes, fun) do
    metadata = %{array: array_ref, chunk_index: chunk_index}

    :telemetry.span(@chunk_write, metadata, fn ->
      result = fun.()
      {result, %{bytes: bytes}}
    end)
  end

  @doc false
  @spec stream_start(tuple(), atom(), keyword()) :: :ok
  def stream_start(array_ref, type, opts) do
    :telemetry.execute(@stream_start, %{}, %{array: array_ref, type: type, opts: opts})
    :ok
  end

  @doc false
  @spec stream_stop(tuple(), atom(), non_neg_integer(), non_neg_integer()) :: :ok
  def stream_stop(array_ref, type, count, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(@stream_stop, %{duration: duration, count: count}, %{
      array: array_ref,
      type: type
    })

    :ok
  end

  @doc """
  Returns telemetry event names for attaching handlers.

  Chunk events include `:start`, `:stop`, and `:exception` variants from
  `:telemetry.span/3`. Stream events are single `:execute` calls.
  """
  @spec events() :: [[atom()]]
  def events do
    [
      @chunk_read ++ [:start],
      @chunk_read ++ [:stop],
      @chunk_read ++ [:exception],
      @chunk_write ++ [:start],
      @chunk_write ++ [:stop],
      @chunk_write ++ [:exception],
      @stream_start,
      @stream_stop
    ]
  end
end
