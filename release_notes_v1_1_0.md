# ExZarr v1.1.0 Release Notes

## BEAM-Native Streaming and Concurrent Zarr Processing

ExZarr v1.1.0 adds streaming APIs for reading and writing large Zarr arrays
with controlled concurrency, backpressure, and observability.

## Highlights

### Streaming Read APIs

- `ExZarr.Array.stream_chunks/2` - lazy chunk streaming with concurrency control
- `ExZarr.Array.stream_slices/3` - dimension-wise slice streaming
- `chunk_stream/2` retained as backward-compatible alias

### Streaming Write API

- `ExZarr.Array.write_stream/3` - ingest chunks from enumerables with
  validation, batching, and checkpoint support

### Pipeline Integrations (Optional Dependencies)

- `ExZarr.Flow` - Flow-based parallel processing
- `ExZarr.GenStage` - demand-driven chunk and slice producers
- `ExZarr.Broadway` - fault-tolerant pipeline helpers

### Telemetry

Chunk read/write events use `:telemetry.span/3` and emit `:start`, `:stop`, and
`:exception` suffixes. Attach to the `:stop` events for measurements:

- `[:ex_zarr, :chunk, :read, :stop]`
- `[:ex_zarr, :chunk, :write, :stop]`
- `[:ex_zarr, :stream, :start]`
- `[:ex_zarr, :stream, :stop]`

### Documentation

- Architecture review, gap analysis, and design documents
- Cloud storage patterns guide
- Production cookbook
- New livebooks for Broadway and Nx streaming

## Upgrade

No breaking changes. Existing `chunk_stream/2` code continues to work.
New code should use `stream_chunks/2`.

See [migration_guide_v1_1_0.md](migration_guide_v1_1_0.md).
