# ExZarr Roadmap

## v1.1.0 (Current) - BEAM-Native Streaming

- [x] `stream_chunks/2` and `stream_slices/3` read APIs
- [x] `write_stream/3` write API
- [x] Telemetry instrumentation
- [x] Flow, GenStage, Broadway integrations
- [x] Cloud storage patterns documentation
- [x] Production cookbook

## v1.2.0 (Planned) - Storage and Interop

- [ ] Unified cloud retry layer across S3/GCS/Azure
- [ ] Async codec pipeline (overlap I/O and decode)
- [ ] Explorer streaming integration
- [ ] Enhanced Zarr v3 async store alignment

## v2.0.0 (Future) - Distributed Processing

- [ ] Multi-node chunk processing with Horde/Swarm
- [ ] PartitionSupervisor-based worker pools
- [ ] Cross-node telemetry aggregation
