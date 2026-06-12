# ExZarr Roadmap

## v1.1.0 (Current) — BEAM-Native Streaming

Released 2026-06-12. Backward compatible with v1.0.

### Shipped

- [x] `ExZarr.Array.stream_chunks/2` and `stream_slices/3` read APIs
- [x] `ExZarr.Array.write_stream/3` write API with validation and checkpoints
- [x] `chunk_stream/2` retained as alias for `stream_chunks/2`
- [x] `ExZarr.Telemetry` — chunk read/write and stream start/stop events
- [x] Optional `ExZarr.Flow`, `ExZarr.GenStage`, `ExZarr.Broadway` integrations
- [x] Architecture review, gap analysis, v1.1 design docs
- [x] Cloud storage patterns guide and production cookbook
- [x] Livebooks: Broadway pipeline, Nx streaming
- [x] Streaming benchmarks (`benchmarks/streaming_bench.exs`)
- [x] Review hardening: producer deduplication, timeout handling, telemetry docs,
      CI Zig 0.16 alignment, 1,500+ test suite with streaming property tests

### Public API entry points

Use `ExZarr.Array` streaming functions — not `ExZarr.Streaming` (internal).

---

## v1.2.0 (Planned) — Cloud Storage & Reliability

Focus: production-grade cloud backends and fewer operational surprises.

- [ ] Unified retry/backoff layer across S3, GCS, and Azure backends
- [ ] Migrate Azure backend from `azurex` to `azure_sdk` (keep `azurex` optional)
- [ ] Rate-limit awareness and configurable timeouts per backend
- [ ] Zarr v3 async store interface alignment (read path)
- [ ] Cloud backend integration tests behind CI feature flags
- [ ] Document credential patterns (env, Goth, managed identity)

**Why now:** Cloud storage is the primary use case for streaming; backends share
little retry logic today and Azure depends on a transitive `azurex` chain.

---

## v1.3.0 (Planned) — Data Science Interop

Focus: connect streaming APIs to the Elixir numeric stack.

- [ ] Explorer direct streaming integration (chunk → DataFrame without full load)
- [ ] `ExZarr.Nx` streaming recipes: batched tensors from `stream_chunks/2`
- [ ] Livebook curriculum (`livebooks/01_core_zarr/` series completion)
- [ ] Cookbook expansion: geospatial and time-series worked examples
- [ ] Property tests for cross-format roundtrips (write_stream → Nx → write_stream)

**Why now:** v1.1 streaming is BEAM-native; v1.3 makes it useful for ML/science
workflows without copying through Python.

---

## v1.4.0 (Planned) — Performance & Packaging

Focus: throughput and install friction.

- [ ] Async codec pipeline — overlap chunk I/O with decompression/compression
- [ ] Vendored or statically linked codec libraries (remove system lib apt/brew deps)
- [ ] Additional v3 filters: PackBits, Categorize (pending dtype support)
- [ ] v3 sharding extension improvements and storage transformers
- [ ] Benchmark suite comparing sequential vs concurrent vs async codec paths

**Why now:** Zig NIFs still require five system libraries; async codecs unlock
the next performance tier for cloud-backed arrays.

---

## v2.0.0 (Future) — Distributed Processing

Focus: multi-node arrays on the BEAM.

- [ ] Multi-node chunk processing with Horde or `:pg` coordination
- [ ] `PartitionSupervisor`-based worker pools for chunk reads/writes
- [ ] Cross-node telemetry aggregation
- [ ] Distributed Broadway/Flow topologies over shared Zarr stores
- [ ] Failure-domain documentation (network partitions, partial writes)

**Why later:** Requires breaking supervision and storage contract decisions;
builds on stable cloud + streaming foundations from v1.2–v1.4.

---

## Completed (Pre-v1.1)

- Zig NIF codecs (zstd, lz4, snappy, blosc, bzip2) and CRC32C
- Custom codec and storage backend plugin systems
- Zarr v3 with automatic version detection
- Zip archive storage, filter pipeline (Delta, Quantize, Shuffle, etc.)
- 26× multi-chunk read optimization (v0.8+)
