# Glossary

This glossary bridges terminology between Zarr/Python/NumPy and Elixir/BEAM ecosystems. Terms are organized by category for quick reference.

## Table of Contents

- [Zarr Concepts](#zarr-concepts)
- [NumPy/Python Terms](#numpypython-terms)
- [BEAM/Elixir Terms](#beamelixir-terms)
- [Storage and I/O Terms](#storage-and-io-terms)
- [Compression and Codec Terms](#compression-and-codec-terms)
- [Cross-Reference Table](#cross-reference-table)

## Zarr Concepts

Terms from the Zarr specification and format.

### Array

N-dimensional typed data container with chunked storage. Similar to NumPy ndarray but stored persistently on disk/cloud with compression. Each array has metadata specifying shape, chunks, dtype, and compressor.

### Attributes

User-defined metadata attached to arrays or groups. Stored as JSON in `.zattrs` (v2) or within `zarr.json` (v3). Used for describing data provenance, units, or custom application metadata.

### Chunk

Fixed-size subdivision of an array, serving as the atomic unit of I/O and compression. Example: A `{1000, 1000}` array with `{100, 100}` chunks contains 100 total chunks. Reading or writing any element in a chunk requires loading/saving the entire chunk.

### Chunk Grid

The layout scheme defining how an array is divided into chunks. In v2, this is implicit from the chunks shape. In v3, chunk grids are explicit and can include regular grids or sharding.

### Chunk Key

Identifier for a chunk's location in storage. In Zarr v2: `"0.1.2"` (dot-separated coordinates). In Zarr v3: `"c/0/1/2"` (slash-separated with `c/` prefix). See also: [Chunk key encoding](#chunk-key-encoding).

### Chunk Key Encoding

The scheme for converting chunk coordinates to storage keys. Zarr v2 uses dot-separated (`0.1.2`) or slash-separated (`0/1/2`) strings. Zarr v3 standardizes on slash-separated with a `c/` prefix (`c/0/1/2`).

### Codec

Transformation applied to chunk data, such as compression, filtering, or checksumming. In Zarr v3, codecs are chained in a pipeline. In v2, compressor and filters are separate concepts. See: [Codec Pipeline](#codec-pipeline).

### Codec Pipeline

Zarr v3 feature where multiple codecs are applied in sequence. Example: Shuffle → Quantize → Zstd compression. Each codec's output becomes the next codec's input.

### Compressor

A specific type of codec that reduces data size (zlib, zstd, lz4, blosc). In Zarr v2, the compressor is a top-level metadata field. In v3, it's one codec in the pipeline.

### Dimension Separator

Character separating chunk coordinates in v2 keys. Usually `"."` (dot) but can be `"/"` (slash). Zarr v3 always uses `"/"`. Controls how chunks are stored: `0.1.2` vs `0/1/2`.

### Dtype

Data type specification determining how bytes are interpreted as numbers. Examples: `:int32` (32-bit signed integer), `:float64` (64-bit IEEE 754 float). See: [Data Types](#data-types).

### Fill Value

Default value returned for uninitialized chunks. Typically `0` for numeric types, `false` for booleans, `""` for strings. Allows sparse arrays without storing empty chunks.

### Filter

Codec that transforms data before compression to improve compression ratio. Common filters: shuffle (byte reordering), delta (differences), quantize (precision reduction). In Zarr v3, filters are codecs in the pipeline.

### Group

Hierarchical container for arrays and subgroups, similar to a filesystem directory. Groups allow organizing related arrays. Metadata stored in `.zgroup` (v2) or `zarr.json` (v3).

### Metadata

Structural information about an array or group. For arrays: shape, chunks, dtype, compressor, filters. Stored in `.zarray` (v2) or `zarr.json` (v3). Must be valid JSON.

### Sharding

Zarr v3 optimization that bundles multiple logical chunks into a single storage object. Reduces API calls for small chunks while maintaining fine-grained logical chunking. See: [Sharding Codec](#sharding-codec).

### Shape

Dimensions of an array as a tuple. Example: `{1000, 500, 3}` represents 1000 rows, 500 columns, 3 channels. Determines total array size: 1000 × 500 × 3 = 1,500,000 elements.

### Zarr v2

Original Zarr specification (2016). Widely supported, stable, uses separate metadata files (`.zarray`, `.zattrs`, `.zgroup`). Compressor and filters are distinct concepts.

### Zarr v3

Updated specification (2023) with unified codec pipeline, sharding, dimension names, and cleaner metadata format. Single `zarr.json` file per array/group. See: [Codec Pipeline](#codec-pipeline).

## NumPy/Python Terms

Terms from the Python scientific computing ecosystem.

### Broadcasting

NumPy feature for automatic array shape alignment during operations. Example: `(3, 1)` array + `(3, 5)` array broadcasts to `(3, 5)`. Not directly applicable to ExZarr (persistent storage, not compute).

### C Order (Row-Major)

Memory layout where the last dimension varies fastest. Default in NumPy and ExZarr. For `{2, 3}` array: `[0,0], [0,1], [0,2], [1,0], [1,1], [1,2]`. Also called "row-major" order.

### Dtype String

NumPy's type notation using strings like `"<f8"` (little-endian float64) or `"<i4"` (little-endian int32). ExZarr uses atoms instead: `:float64`, `:int32`. See: [Dtype Conversion](#dtype-conversion).

### Fancy Indexing

Advanced NumPy indexing using boolean masks or integer arrays. Example: `arr[[0, 2, 4]]` or `arr[arr > 0]`. Not directly supported in ExZarr (would need application-level implementation).

### Fortran Order (Column-Major)

Memory layout where the first dimension varies fastest. For `{2, 3}` array: `[0,0], [1,0], [0,1], [1,1], [0,2], [1,2]`. Not currently supported in ExZarr.

### ndarray

NumPy's in-memory N-dimensional array type. ExZarr arrays are persistent, chunked equivalents stored on disk/cloud. To work with ndarray in Elixir, use Nx tensors. See: [Nx Integration](nx_integration.md).

### numcodecs

Python package providing compression codecs for zarr-python. Includes Blosc, Zstd, LZ4, etc. ExZarr uses Zig NIFs for equivalent codec implementations.

### Slicing

Extracting sub-arrays using index ranges. NumPy syntax: `arr[0:100, 0:50]`. ExZarr syntax: `get_slice(array, start: {0, 0}, stop: {100, 50})`. Both are inclusive of start, exclusive of stop.

### zarr-python

Reference Python implementation of the Zarr specification. Maintained by the Zarr community. ExZarr is fully interoperable with zarr-python for v2 arrays and compatible with v3 beta.

### View

NumPy feature where slicing returns a view (shared memory) rather than a copy. Not applicable to ExZarr (each slice operation reads from storage).

## BEAM/Elixir Terms

Terms from the Erlang/Elixir ecosystem.

### Atom

Elixir constant whose value is its name. Used extensively in ExZarr for dtypes (`:float64`), storage backends (`:filesystem`), and codecs (`:zstd`). Atoms are interned (only stored once in memory).

### BEAM

The Erlang virtual machine that runs Elixir. Provides lightweight processes (not OS processes), message passing, and fault tolerance. ExZarr leverages BEAM for concurrent chunk operations.

### Behavior (Behaviour)

Elixir/Erlang contract defining callbacks a module must implement. ExZarr defines behaviors for storage backends (`ExZarr.Storage.Backend`) and codecs (`ExZarr.Codecs.Codec`). See: [Implementing Behaviors](custom_storage_backend.md).

### Binary

BEAM's efficient representation for byte sequences. Chunk data in ExZarr is stored as binaries. Binaries over 64 bytes live in the shared binary heap (reference counted). See: [Memory Model](#memory-model).

### GenServer

OTP behavior for stateful servers using message passing. ExZarr uses GenServers for registries (codecs, storage backends) and optionally for array management. Provides synchronized access to state.

### Keyword List

Elixir's `[key: value]` syntax for function options. Used throughout ExZarr API. Example: `create(shape: {100, 100}, dtype: :float64)`. Order-preserving and allows duplicate keys.

### NIF (Native Implemented Function)

Erlang mechanism for calling native code (C, Zig, Rust) from BEAM. ExZarr uses Zig NIFs for high-performance compression codecs. NIFs run in the same OS process as BEAM (fast but can crash VM if buggy).

### Process

Lightweight BEAM execution unit (not OS process). Typical BEAM system runs millions of processes. ExZarr uses processes for concurrent chunk operations via `Task.async_stream`. Each process has isolated heap and message queue.

### Shared Binary Heap

BEAM memory area for large binaries (>64 bytes). When multiple processes reference the same binary, only one copy exists (reference counted). Enables efficient chunk sharing in ExZarr.

### Supervisor

OTP behavior for fault-tolerant process management. Supervisors automatically restart failed processes. ExZarr registries run under supervisors to ensure service availability.

### Task.async_stream

Elixir pattern for parallel map operations with controlled concurrency. ExZarr uses this for concurrent chunk processing. Example: `Task.async_stream(chunks, &process/1, max_concurrency: 8)`.

### Tuple

Elixir's immutable ordered collection with fixed size. ExZarr uses tuples for shapes (`{1000, 500}`), chunk coordinates (`{0, 2}`), and nested data representation. Access by index is O(1).

### Zigler

Elixir package for writing Zig NIFs. Handles compilation, type conversion, and resource management. ExZarr uses Zigler for codec implementations. Automatically downloads Zig toolchain on first compile.

## Storage and I/O Terms

Terms related to data storage and input/output operations.

### API Call

Single request to a cloud storage service (GET, PUT, LIST, DELETE). Each chunk operation typically requires one API call. Cloud providers charge per API call (e.g., $0.0004 per 1000 GETs on S3).

### Backend

Storage implementation conforming to `ExZarr.Storage.Backend` behavior. Examples: filesystem, memory, S3, GCS, Azure Blob, Mnesia, MongoDB GridFS. See: [Storage Providers](storage_providers.md).

### Block Storage

Persistent disk storage (AWS EBS, GCE Persistent Disks). Lower latency than object storage (~1-10ms vs ~50-200ms) but less scalable. Used for databases and local filesystems.

### Bucket

Top-level container in object storage. Example: S3 bucket `"my-datasets"`, GCS bucket `"eu-west-data"`. Bucket names are globally unique. Regional placement affects latency and cost.

### ETS (Erlang Term Storage)

BEAM's built-in in-memory key-value store. ExZarr offers ETS backend for shared in-memory arrays accessible across processes. Supports concurrent reads and writes with different consistency models.

### Latency

Time between request and response. High for cloud storage (50-200ms), low for local SSD (<1ms). ExZarr uses parallelism to hide latency. Latency determines minimum time to access any chunk.

### Object Storage

Cloud storage service for immutable objects (AWS S3, GCS, Azure Blob). Optimized for large files and parallel access. Eventually consistent (changes may take time to propagate). Cost: $0.02-0.03 per GB/month.

### Prefix

Path-like namespace within a bucket. Example: `"experiments/2024/dataset1/"`. Used to organize data hierarchically. S3 rate limits apply per prefix (5,500 GET/s per prefix).

### Region

Geographic location of cloud resources. Example: `us-east-1`, `eu-west-1`. Choosing region closest to compute reduces latency. Cross-region data transfer incurs costs ($0.02-0.05 per GB).

### Throughput

Data volume per unit time (MB/s or GB/s). Can be high with parallelism even if latency is high. Example: 50ms latency, 10 MB chunks, 8 parallel = 1.6 GB/s throughput.

## Compression and Codec Terms

Terms related to data compression and codec operations.

### Blosc

Meta-compressor combining blocking, shuffling, and multiple compression algorithms (LZ4, Zstd, Zlib). Optimized for typed arrays with SIMD operations. Provides both speed and compression ratio. See: [Compression Guide](compression_codecs.md).

### Bzip2

High-compression codec using Burrows-Wheeler transform. Slow (5-20 MB/s compression) but excellent ratios (4-8×). Best for archival storage where compression ratio matters more than speed.

### Compression Level

Tuning parameter controlling compression ratio vs speed tradeoff. Higher levels = better compression but slower. Ranges vary by codec: zlib (1-9), zstd (1-22), lz4 (1-12).

### Compression Ratio

Original size divided by compressed size. Higher is better. Example: 3× means 1 GB becomes 333 MB. Depends on data characteristics: repetitive data compresses well, random data doesn't.

### CRC (Cyclic Redundancy Check)

Checksum algorithm for detecting data corruption. CRC32C (Castagnoli variant) used in ExZarr for integrity verification. Computed on uncompressed data and stored with chunk.

### Delta Encoding

Storing differences between adjacent values instead of absolute values. Effective for slowly-changing time series or monotonic data. Example: `[100, 101, 103, 104]` becomes `[100, 1, 2, 1]`.

### Entropy

Measure of data randomness. High entropy (random data) compresses poorly or not at all. Low entropy (repetitive patterns) compresses well. Most real-world data has low entropy.

### Gzip

GNU implementation of DEFLATE algorithm. Compatible with zlib but adds header/footer. Compression ratio and speed similar to zlib. Widely supported across platforms and languages.

### Lossless Compression

Data can be perfectly reconstructed after decompression. All ExZarr compression codecs are lossless. Essential for scientific data requiring exact values. Contrast: lossy compression (JPEG, MP3).

### Lossy Compression

Some data is lost during compression (JPEG, MP3, video codecs). Achieves higher compression ratios than lossless. Not used in ExZarr as scientific data requires exact values. Can be implemented at application level via quantization filter.

### LZ4

Extremely fast compression codec (200-500 MB/s compression, 1-3 GB/s decompression). Modest compression ratios (1.5-2.5×). Best for real-time ingestion where speed matters more than ratio.

### Quantization

Reducing precision to save space. Example: converting 64-bit floats to 32-bit (halves size). Lossy but appropriate for some use cases. ExZarr v3 provides quantization filter.

### Shuffle

Byte-reordering filter that groups similar bytes together, improving compression. For typed arrays, shuffle collects all high bytes, then all next bytes, etc. Most effective for multi-byte types (float64, int32).

### Snappy

Fast compression codec by Google (250-500 MB/s compression). Modest ratios (1.5-2×). Focus on speed rather than compression. Good for streaming use cases.

### Zlib

Widely-available compression codec using DEFLATE algorithm. Moderate speed (10-50 MB/s compression) and ratios (2-4×). Always available in ExZarr (Erlang built-in). Default choice for compatibility.

### Zstd (Zstandard)

Modern compression codec by Facebook. Excellent balance: fast (50-200 MB/s compression, 200-800 MB/s decompression) with good ratios (3-6×). Recommended default for most ExZarr use cases. Wide level range (1-22).

## Cross-Reference Table

Mapping between Zarr/NumPy and ExZarr/Elixir concepts.

| Concept | Zarr/NumPy Term | ExZarr/Elixir Term | Notes |
|---------|-----------------|-------------------|-------|
| Array structure | `ndarray.shape` | `array.metadata.shape` | Both use tuples: `(1000, 500)` in Python, `{1000, 500}` in Elixir |
| Data type | dtype string `"<f8"` | dtype atom `:float64` | Different syntax, same meaning. See [Dtype Mapping](#dtype-mapping) |
| Array subdivision | chunk | chunk | Same concept and terminology |
| Chunk identifier | chunk key (string) | chunk coordinates (tuple) | Keys like `"0.1.2"` vs coords like `{0, 1, 2}` |
| Compression algorithm | compressor | compressor | Same term, same concept |
| Data transformation | filter (v2) or codec (v3) | filter or codec | v3 unifies as "codec" |
| In-memory array | NumPy array | Nested tuple or `Nx.Tensor` | Different data structures, need conversion |
| Extract sub-array | `arr[0:10, 0:20]` | `get_slice(start: {0,0}, stop: {10,20})` | Different syntax, same operation |
| Parallel processing | `multiprocessing`/`threading` | `Task.async_stream` | Different concurrency models (GIL vs processes) |
| Persistent storage | Directory of files | Storage backend | Same underlying Zarr format |
| Metadata storage | `.zarray`, `.zattrs`, `.zgroup` | Metadata struct | Same JSON format on disk |
| Hierarchical organization | Group hierarchy | Group hierarchy | Same concept and functionality |
| Memory layout | C order (row-major) | Row-major | Same default layout |
| Chunk compression | `compressor={'id': 'zstd'}` | `compressor: %{id: "zstd"}` | Similar configuration, different syntax |
| Read operation | `arr[0:100, :]` | `get_slice(array, start: {0,0}, stop: {100,n})` | Different interfaces, same result |
| Write operation | `arr[0:100, :] = data` | `set_slice(array, data, start: {0,0}, stop: {100,n})` | Different interfaces, same result |
| Iterate chunks | Manual or `zarr.convenience` | `chunk_stream/1` | ExZarr provides built-in streaming |

### Dtype Mapping

| NumPy/Python | ExZarr/Elixir | String Representation | Bytes |
|--------------|---------------|----------------------|-------|
| `np.int8` | `:int8` | `"<i1"` (v2) / `"int8"` (v3) | 1 |
| `np.int16` | `:int16` | `"<i2"` (v2) / `"int16"` (v3) | 2 |
| `np.int32` | `:int32` | `"<i4"` (v2) / `"int32"` (v3) | 4 |
| `np.int64` | `:int64` | `"<i8"` (v2) / `"int64"` (v3) | 8 |
| `np.uint8` | `:uint8` | `"<u1"` (v2) / `"uint8"` (v3) | 1 |
| `np.uint16` | `:uint16` | `"<u2"` (v2) / `"uint16"` (v3) | 2 |
| `np.uint32` | `:uint32` | `"<u4"` (v2) / `"uint32"` (v3) | 4 |
| `np.uint64` | `:uint64` | `"<u8"` (v2) / `"uint64"` (v3) | 8 |
| `np.float32` | `:float32` | `"<f4"` (v2) / `"float32"` (v3) | 4 |
| `np.float64` | `:float64` | `"<f8"` (v2) / `"float64"` (v3) | 8 |

Note: `<` indicates little-endian byte order (standard on most modern systems). ExZarr always uses little-endian for compatibility.

### Codec Mapping

| Codec | Python (numcodecs) | ExZarr/Elixir | Availability |
|-------|-------------------|---------------|--------------|
| Zlib | `numcodecs.Zlib` | `:zlib` | Always (Erlang built-in) |
| Gzip | `numcodecs.GZip` | `:gzip` | Always (Erlang built-in) |
| Zstd | `numcodecs.Zstd` | `:zstd` | Requires Zig NIFs + libzstd |
| LZ4 | `numcodecs.LZ4` | `:lz4` | Requires Zig NIFs + liblz4 |
| Blosc | `numcodecs.Blosc` | `:blosc` | Requires Zig NIFs + libblosc |
| Snappy | `numcodecs.Snappy` | `:snappy` | Requires Zig NIFs + libsnappy |
| Bzip2 | `numcodecs.BZ2` | `:bzip2` | Requires Zig NIFs + libbz2 |
| CRC32C | `numcodecs.CRC32C` | `:crc32c` | Requires Zig NIFs |
| Shuffle | `numcodecs.Shuffle` | `ExZarr.Filters.Shuffle` | Built-in (v3) |
| Delta | `numcodecs.Delta` | `ExZarr.Filters.Delta` | Built-in (v3) |

See [Compression Guide](compression_codecs.md) for codec selection and performance characteristics.

## Common Abbreviations

Quick reference for acronyms used throughout documentation:

- **API**: Application Programming Interface
- **AWS**: Amazon Web Services
- **BEAM**: Bogdan/Björn's Erlang Abstract Machine
- **CDN**: Content Delivery Network
- **CPU**: Central Processing Unit
- **CRC**: Cyclic Redundancy Check
- **EBS**: Elastic Block Store (AWS)
- **ETS**: Erlang Term Storage
- **GB**: Gigabyte (1,000,000,000 bytes)
- **GC**: Garbage Collection
- **GCS**: Google Cloud Storage
- **GPU**: Graphics Processing Unit
- **HDF5**: Hierarchical Data Format version 5
- **HTTP**: Hypertext Transfer Protocol
- **I/O**: Input/Output
- **IAM**: Identity and Access Management (AWS)
- **IOPS**: Input/Output Operations Per Second
- **JSON**: JavaScript Object Notation
- **JWT**: JSON Web Token
- **MB**: Megabyte (1,000,000 bytes)
- **ML**: Machine Learning
- **NIF**: Native Implemented Function
- **NumPy**: Numerical Python
- **Nx**: Numerical Elixir
- **OOM**: Out Of Memory
- **OTP**: Open Telecom Platform (Erlang/Elixir)
- **RAM**: Random Access Memory
- **S3**: Simple Storage Service (AWS)
- **SIMD**: Single Instruction, Multiple Data
- **SSD**: Solid State Drive
- **URL**: Uniform Resource Locator
- **UTF-8**: 8-bit Unicode Transformation Format
- **VM**: Virtual Machine
- **Zarr**: Chunked, compressed, N-dimensional array format

## See Also

For deeper explanations of concepts:

- **Array operations**: See [Core Concepts Guide](core_concepts.md)
- **Chunking strategies**: See [Performance Guide](performance.md#chunk-size-selection-strategy)
- **Codec selection**: See [Compression Guide](compression_codecs.md)
- **Storage backends**: See [Storage Providers Guide](storage_providers.md)
- **Python compatibility**: See [Python Interoperability Guide](python_interop.md)
- **BEAM concurrency**: See [Parallel I/O Guide](parallel_io.md)
- **Nx integration**: See [Nx Integration Guide](nx_integration.md)

## Contributing to This Glossary

Found a missing term or unclear definition? Please:

1. Check if the term is already defined under a different name
2. Submit an issue on GitHub with the proposed term and definition
3. Include context: where did you encounter this term?
4. Suggest related terms for cross-referencing

Keep definitions concise (2-3 sentences), avoid jargon in the definition itself, and provide examples where helpful.
