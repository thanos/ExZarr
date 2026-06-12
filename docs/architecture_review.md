# ExZarr v1.1.0 Architecture Review

## Current State Assessment

### Storage Architecture

ExZarr uses a pluggable storage backend behaviour (`ExZarr.Storage.Backend`) with
built-in implementations for memory, filesystem, zip, ETS, Mnesia, S3, GCS, Azure
Blob, and MongoDB GridFS. Storage is accessed through a thin `ExZarr.Storage`
facade that handles backend dispatch, chunk key encoding, and metadata I/O.

**Strengths:** Clean separation between array logic and persistence. Custom backends
can be registered at runtime. Chunk keys follow Zarr v2/v3 conventions.

**Gaps before v1.1.0:** No unified retry or idempotency layer across cloud backends.
Streaming APIs read only stored chunks by default, not all logical chunk indices.

### Codec Architecture

Compression and filters are handled through a registry-based codec pipeline.
Zig NIFs provide high-performance compression. v3 uses `PipelineV3` with sharding
support via `ShardingIndexed`.

**Strengths:** Extensible registry, v2/v3 interoperability, property-tested roundtrips.

**Gaps:** Codec execution is synchronous per chunk. Streaming does not yet pipeline
decode with downstream processing automatically.

### Chunk Handling

Chunks are addressed by N-dimensional indices. `ExZarr.Chunk` provides coordinate
math. `ExZarr.Array` handles read/write with optional `ArrayServer` locking and
`ChunkCache`.

**Strengths:** Mature slice assembly, sharding support, fill value handling.

**Gaps before v1.1.0:** No first-class lazy streaming API (`stream_chunks/2`).
Parallel reads existed via `chunk_stream/2` but lacked telemetry and metadata events.

### Nx Integration

`ExZarr.Nx` and `ExZarr.Nx.DataLoader` provide tensor conversion and batch
streaming for ML workflows.

**Strengths:** Batch streams with shuffling, paired feature/label loading.

**Gaps:** No direct `stream_chunks |> Stream.map(&Nx.tensor/1)` documentation
or livebook until v1.1.0.

### API Ergonomics

Top-level `ExZarr.create/open/save/load` provides a simple entry point. Array
module exposes comprehensive slice, indexing, and manipulation APIs.

**Strengths:** Consistent `{:ok, result}` / `{:error, reason}` patterns.

**Gaps:** Streaming APIs used internal name `chunk_stream` instead of discoverable
`stream_chunks`. No write streaming or Flow/GenStage/Broadway integration.

### Extensibility

Plugin systems for storage backends and codecs. Group hierarchy for multi-array
datasets.

**Strengths:** Well-documented behaviours, registry pattern.

### Concurrency Model

`Task.async_stream` used for parallel chunk reads in `chunk_stream/2` and
`parallel_chunk_map/3`. `ArrayServer` provides coordinated locking.

**Strengths:** BEAM-native parallelism without GIL constraints.

**Gaps before v1.1.0:** No demand-driven backpressure (GenStage), no supervised
pipeline integration (Broadway), no Flow partitioning.

## v1.1.0 Changes

v1.1.0 introduces:

- `ExZarr.Array.stream_chunks/2` - canonical lazy chunk streaming
- `ExZarr.Array.stream_slices/3` - dimension-wise slice streaming
- `ExZarr.Array.write_stream/3` - chunk ingestion from enumerables
- `ExZarr.Telemetry` - observability events
- `ExZarr.Flow`, `ExZarr.GenStage`, `ExZarr.Broadway` - optional pipeline integrations
- Shared streaming internals (internal module behind Array streaming APIs)

## BEAM-Specific Considerations

- Lazy `Stream.resource/3` for sequential reads keeps memory bounded
- `Task.async_stream/3` provides bounded concurrency with timeout and ordering
- GenStage producers enable demand-driven backpressure for overloaded consumers
- Broadway adds supervision, batching, and retry semantics for production pipelines
- Telemetry uses `:telemetry.span/3` for chunk read/write duration measurement
