# ExZarr v1.1.0 Design Document

## Theme

BEAM-native streaming and concurrent Zarr processing.

## Design Principles

1. **Backward compatibility:** `chunk_stream/2` remains as alias for `stream_chunks/2`
2. **Bounded memory:** All streaming APIs use lazy enumerables
3. **Composable:** Streams work with `Stream.*`, `Enum.*`, Flow, GenStage, Broadway
4. **Optional dependencies:** Flow, GenStage, Broadway are optional hex deps
5. **Observable:** Telemetry events on all streaming operations

## API Design

### stream_chunks/2

```elixir
@spec stream_chunks(Array.t(), keyword()) :: Enumerable.t()
```

Yields `{chunk_index, binary}` or `%{index:, data:, metadata:}` when
`:metadata` is true.

Options:
- `:concurrency` - parallel reads (default: 1)
- `:ordered` - preserve chunk order (default: true)
- `:timeout` - per-chunk timeout ms (default: 60_000)
- `:filter` - predicate on chunk index
- `:include_missing` - iterate all logical indices
- `:metadata` - include bounds and shape
- `:on_error` - `:skip`, `:halt`, or callback

### stream_slices/3

```elixir
@spec stream_slices(Array.t(), non_neg_integer(), keyword()) :: Enumerable.t()
```

Streams unit slices along dimension `along` within optional `:start`/`:stop` region.

### write_stream/3

```elixir
@spec write_stream(Enumerable.t(), Array.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

Accepts `{index, data}` tuples. Each chunk write is atomic. Supports `:checkpoint`
for resumable ingestion.

## Module Layout

```
lib/ex_zarr/
  streaming.ex          # Shared streaming logic
  telemetry.ex          # :telemetry events
  flow.ex               # Optional Flow integration
  gen_stage.ex          # GenStage facade
  gen_stage/
    chunk_producer.ex
    slice_producer.ex
  broadway.ex           # Broadway helpers
  broadway/
    chunk_producer.ex
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Memory pressure with high concurrency | Medium | High | Document concurrency tuning; default to 1 |
| Cloud backend partial failures | Medium | High | cloud_storage_patterns.md; on_error options |
| Optional dep compile failures | Low | Medium | Conditional compilation with Code.ensure_loaded? |
| API naming confusion (chunk_stream vs stream_chunks) | Medium | Low | Keep alias; document canonical name |
| Broadway message acknowledger requirements | Low | Low | Use NoopAcknowledger.init() |

## Implementation Plan

1. Extract streaming logic to `ExZarr.Streaming`
2. Add `stream_chunks`, `stream_slices`, `write_stream` to Array
3. Add `ExZarr.Telemetry`
4. Add optional Flow/GenStage/Broadway modules
5. Tests, benchmarks, documentation, livebooks
6. Version bump to 1.1.0

## Performance Targets

Benchmark `benchmarks/streaming_bench.exs` measures:
- Sequential vs concurrent chunk streaming
- Scaling at 1x and 2x scheduler count
- Row-wise slice streaming

No performance claims without benchmark results.
