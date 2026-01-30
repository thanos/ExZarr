# ExZarr content plan (Medium + Livebook gallery)

This file is meant to live in the ExZarr repo as an editorial / tutorial roadmap.
It’s biased toward *domain-rich*, runnable demos and toward Elixir/OTP strengths
(concurrency, fault tolerance, pipelines, distributed systems).

---

## Guiding principles

- **Every tutorial is runnable** (Livebook first). The Medium article is the narrative wrapper.
- **Prefer “small, real” datasets** that fit in the repo (or generated deterministically).
- **Show the Zarr concepts** (chunking, compression, partial reads, metadata layout) *and* the Elixir concepts
  (Task.async_stream, supervision, backpressure, streaming).
- **Include interoperability**: write a store in Elixir, read it in Python (and vice‑versa).
- **Always include a “performance/ops” section**: chunk sizing, throughput vs. latency, and what to monitor.

---

## A. Medium article ideas (detailed)

Each entry: *working title* → reader goal → ExZarr features to showcase → suggested Livebook(s).

### A1. Core fundamentals (10)

1) **ExZarr 101: Cloud‑native arrays in Elixir (Zarr v2)**
   - Goal: create/open/save, write a slice, read a slice, stream chunks.
   - Features: `Array.create/1`, `set_slice/3`, `get_slice/2`, `chunk_stream/2`, filesystem storage.

2) **Chunking is the “index”: picking chunks that make reads fast**
   - Goal: chunk heuristics by access pattern (scan, window, random, ML batch).
   - Features: compare shapes/chunks, latency and IO counts; show “too small vs too big”.

3) **Compression pipelines: zstd vs zlib vs lz4 (and when “none” wins)**
   - Goal: demonstrate CPU vs IO tradeoff, parallel read behavior.
   - Features: compressor option, chunk_stream parallelism.

4) **Metadata consolidation & “one RTT” dataset discovery**
   - Goal: explain `.zarray`, `.zattrs`, `.zmetadata` (v2), why it matters in object stores.
   - Features: show store layout, implement a helper to consolidate metadata.

5) **Interoperability: write in Elixir, read in Python**
   - Goal: prove compatibility with reference zarr-python.
   - Features: dtype mapping, endianness, row-major layout, `to_binary/1`.

6) **Parallel chunk processing patterns in OTP**
   - Goal: map-reduce over chunks with bounded concurrency and timeouts.
   - Features: `parallel_chunk_map/3`, Task async stream, progress callbacks.

7) **Appendable datasets for time-series: building growing cubes**
   - Goal: append along time, handle resize, avoid write conflicts.
   - Features: `append/3`, `resize/2`, chunk design for append-only.

8) **S3/object-store tuning for Zarr access**
   - Goal: request patterns, parallelism, cost.
   - Features: storage backend config, concurrency caps, retry/backoff strategies.

9) **Profiling ExZarr: where the time goes**
   - Goal: show how to profile chunk decode/encode, IO, scheduling.
   - Features: `:fprof`, `:eprof`, telemetry hooks (if added).

10) **Building your own codec / backend plugin**
   - Goal: extend ExZarr for proprietary stores or transforms.
   - Features: plugin interfaces, test harness, fuzz tests.

### A2. AI / GenAI (8)

11) **Embeddings at scale: store vectors in Zarr and do fast similarity search**
    - Goal: embeddings dataset, cosine similarity scan, chunked top‑K.
    - Features: 2D float array, chunk-stream batch scoring, Nx optional.

12) **RAG dataset cache: chunked doc shards for fast re-ranking**
    - Goal: store token IDs / logits / feature matrices; minimize reload.
    - Features: mixed arrays (int32 tokens, float32 scores), partial reads by doc ids.

13) **Training data loader: stream mini-batches from Zarr into Nx**
    - Goal: implement a batch iterator that reads only needed chunks.
    - Features: chunk-aware batching, prefetch, backpressure.

14) **Evaluation at scale: confusion matrices and calibration bins stored as Zarr**
    - Goal: write metrics cubes for many runs and slices.
    - Features: write small slices in parallel safely.

15) **Multimodal features: vision patch embeddings as Zarr pyramids (OME-Zarr inspired)**
    - Goal: store multi-scale feature maps, read pyramid levels.
    - Features: groups + arrays per level (phase 2, if groups API exposed).

16) **Vector quantization / product quantization experiments**
    - Goal: store codebooks, assignments, do fast lookups.
    - Features: int arrays + float arrays, chunk alignment.

17) **Telemetry for LLM agents: store “trace tensors” (time × step × feature)**
    - Goal: analyze agent runs like time-series.
    - Features: 3D arrays, partial reads for a run id.

18) **Synthetic data pipelines: generate → store → train**
    - Goal: reproducible dataset generation with deterministic seeds.
    - Features: chunked writes with Task.async_stream.

### A3. Finance (6)

19) **Tick data cubes: time × symbol × field**
    - Goal: store generated tick data, compute OHLC / VWAP quickly.
    - Features: 3D float arrays, block reads, parallel map.

20) **Order book snapshots: level × side × field × time**
    - Goal: store L2 book, reconstruct midprice, slippage curves.
    - Features: 4D arrays, chunking by time windows.

21) **Risk grids: scenario × factor × portfolio**
    - Goal: shock grids stored for fast slice by portfolio.
    - Features: 3D float array, partial reads.

22) **Intraday factor research: windows and rolling stats**
    - Goal: compute rolling vol/corr from chunk streams.
    - Features: chunk stream, incremental reducers.

23) **Reconciliation at scale: store diffs as sparse-ish chunked arrays**
    - Goal: compare big datasets, store only mismatch masks/values.
    - Features: boolean mask arrays, int index arrays.

24) **Backtest artifacts: store “feature matrices” per run**
    - Goal: reproducibility & fast slicing by date or feature id.
    - Features: append, metadata versioning strategy.

### A4. Crypto (4)

25) **OHLCV across venues: time × venue × symbol × field**
    - Goal: unify exchange data, query slices per venue.
    - Features: chunk design for “single venue, many symbols”.

26) **On-chain analytics: block × metric**
    - Goal: store chain metrics, update incrementally, query windows.
    - Features: append, resize.

27) **MEV / mempool features: event × feature**
    - Goal: store fast-changing features, do batching.
    - Features: stream writes and reads, cost-aware chunk sizing.

28) **Price impact curves: trade_size × venue × symbol**
    - Goal: store calibration surfaces.
    - Features: 3D array, partial reads.

### A5. Geospatial, bioimaging, genomics, and “everything else” (12)

29) **Geo: climate cubes (time × lat × lon) and window reads**
30) **Geo: satellite tiles as (t, y, x, band)**
31) **Geo: converting NetCDF via Kerchunk references (phase 2)**
32) **Bioimaging: multiscale pyramids (OME-Zarr style) (phase 2)**
33) **Bioimaging: chunked segmentation masks and lazy viewers**
34) **Genomics: VCF-Zarr style matrices (sample × variant)**
35) **IoT: sensor fleets (device × time × metric)**
36) **Manufacturing: quality inspection feature maps**
37) **Robotics: trajectory logs (time × joint × feature)**
38) **Healthcare: cohort × measure × time**
39) **Energy: grid × time × load**
40) **A/B experimentation: metric × segment × day**

> That’s 40 topics total; you can pick ~10 “pillars” and then spin variants quickly.

---

## B. Livebook gallery (tutorial set)

### B1. Shipping now (already drafted in this patch)

- `01_01_first_zarr_array.livemd` — create/write/read/save/open + chunk streaming
- `04_01_embeddings_in_zarr.livemd` — toy embeddings + similarity search + chunked scan
- `05_01_tick_data_cube.livemd` — tick cube + OHLC/VWAP + parallel chunk map

### B2. Next 10 Livebooks to add (high leverage)

1) Chunk sizing “lab” (benchmark tool)
2) Compression shootout
3) Append-only time series
4) Multi-array “dataset layout” conventions (group-like structure)
5) Interop: write Elixir, read Python (with a small Python snippet)
6) Parallel ingestion with backpressure
7) Fault-tolerant ingestion with supervision + retries
8) S3 backend + tuning cookbook
9) Profiling guide
10) “Real-world” case study: climate cube window reads (generated data)

---

## C. Where to put things in the repo

Recommended layout:

- `livebooks/` — runnable gallery (your users will clone and run)
- `lib/ex_zarr/gallery/` — small helper modules (no core dependency)
- `docs/articles/medium/` — drafts that you can paste into Medium
- `docs/content/` — this content roadmap + checklists
- `docs/RELEASE_NOTES_*.md` — release announcements / changelog snippets

