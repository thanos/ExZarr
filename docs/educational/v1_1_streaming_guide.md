# ExZarr v1.1.0 Streaming Learning Guide

## Zarr Architecture

Zarr splits N-dimensional arrays into chunks stored as independent compressed
blobs. Metadata (`.zarray` or `zarr.json`) describes shape, chunk size, and
codec pipeline. This design enables random access and parallel I/O.

## Chunked Storage

A `{1000, 1000}` array with `{100, 100}` chunks creates 100 independent storage
objects. Each chunk is compressed separately, so reading one region does not
decompress the entire array.

## Array Streaming

`stream_chunks/2` uses lazy `Stream.resource/3` for sequential reads and
`Task.async_stream/3` for concurrent reads. Memory stays bounded because only
in-flight chunks are held.

```elixir
array
|> ExZarr.Array.stream_chunks(concurrency: 4)
|> Stream.map(&process/1)
|> Stream.run()
```

## Concurrent I/O

The BEAM schedules each chunk read as an independent process. For cloud storage,
network latency dominates, so concurrency 16-32 is often optimal. For local SSD,
concurrency matching `System.schedulers_online/0` is a good starting point.

## Backpressure

Without backpressure, fast producers overwhelm slow consumers. Options:

- **GenStage:** Consumers call `GenStage.ask/2` to request chunks
- **Flow:** `Flow.from_enumerable` partitions work with automatic backpressure
- **Broadway:** Supervised pipelines with `max_demand` and `min_demand`

## GenStage

`ExZarr.GenStage.ChunkProducer` emits chunks only when downstream demands them.
This prevents memory growth when processing is slower than I/O.

## Broadway

Broadway adds supervision, batching, and error isolation. Use for production
pipelines that must survive transient cloud failures.

## Flow

Flow partitions chunk streams across BEAM schedulers. Use when you need
map-reduce style processing over large arrays.

## Task Supervision

`Task.async_stream` provides bounded concurrency with timeout and ordering
options. It is the simplest parallelism layer for chunk processing.

## Nx Interoperability

```elixir
array
|> ExZarr.Array.stream_chunks()
|> Stream.map(fn {_i, data} -> Nx.from_binary(data, {:f, 32}) end)
```

See `livebooks/nx_streaming.livemd` for a complete example.
