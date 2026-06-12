# ExZarr Gap Analysis: v1.1.0

## Comparison Matrix

| Capability | Python Zarr | TensorStore | TileDB | ExZarr v1.0 | ExZarr v1.1 |
|------------|-------------|-------------|--------|-------------|-------------|
| Lazy chunk iteration | Yes | Yes | Yes | Partial (`chunk_stream`) | Yes (`stream_chunks`) |
| Parallel reads | Thread pool | Async I/O | Thread pool | Task.async_stream | Task + Flow + GenStage |
| Write streaming | Yes | Yes | Yes | No | Yes (`write_stream`) |
| Backpressure | Limited | Yes | Yes | No | GenStage + Flow |
| Fault-tolerant pipelines | External (Dask) | Limited | Yes | No | Broadway integration |
| Cloud storage | fsspec | Native GCS/S3 | S3 | S3/GCS/Azure | Hardened patterns doc |
| Nx/torch integration | Via Dask/Xarray | TF/JAX | Limited | ExZarr.Nx | Streaming tensors |
| Distributed processing | Dask | Limited | Yes | No | Stretch goal |
| Telemetry | Limited | Yes | Yes | Documented only | Implemented |

## BEAM Unique Advantages

1. **Process isolation:** Each chunk read runs in an isolated process. A failing
   chunk decode does not crash the entire pipeline when `:on_error` is configured.

2. **Preemptive scheduling:** CPU-bound decompression scales across cores without
   a GIL, unlike Python threading.

3. **Supervision:** Broadway pipelines restart failed stages without losing the
   entire array processing job.

4. **Cheap concurrency:** Spawning 100+ concurrent chunk reads is practical on the
   BEAM where OS thread pools would be expensive.

5. **Hot code upgrades:** Long-running streaming pipelines can be upgraded in
   place on production nodes.

## Remaining Gaps (Post v1.1.0)

- Multi-node distributed chunk processing (Horde/Swarm)
- Explorer direct streaming integration
- Async codec pipeline (overlap I/O and decode)
- Zarr v3 async store interface alignment

## Opportunities

- Elixir/Phoenix data pipelines that need Zarr streaming without leaving the BEAM
- Livebook-first education for scientific Elixir community
- Cloud-native deployments on Fly.io/Gigalixir with Broadway pipelines
