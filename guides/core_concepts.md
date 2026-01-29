# Core Concepts

This guide explains the fundamental mental model of Zarr and how ExZarr implements it. Understanding these concepts will help you use the API effectively, make informed design decisions about chunk sizes and compression, and reason about how your data is stored and accessed.

## Arrays vs Groups

Zarr provides two primary organizational structures: arrays for storing data and groups for organizing collections of arrays.

### Arrays: Typed Data Containers

An **array** is an N-dimensional container for homogeneous typed data. It has a fixed shape, data type, and chunking scheme:

```elixir
# Create a 3D array representing temperature over time and space
# Shape: 365 days × 180 latitude points × 360 longitude points
{:ok, temperature} = ExZarr.create(
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32,
  compressor: :zstd,
  storage: :filesystem,
  path: "/data/climate/temperature"
)
```

**Array components:**
- **Shape**: Dimensions of the array (e.g., `{365, 180, 360}`)
- **Dtype**: Data type of all elements (`:float32`, `:float64`, `:int32`, etc.)
- **Chunks**: Size of storage units (e.g., `{1, 180, 360}`)
- **Fill value**: Default value for uninitialized elements (typically 0)
- **Compressor**: Compression codec applied to chunks (`:zstd`, `:zlib`, `:none`, etc.)

**Physical storage:**
- Metadata file: `.zarray` (v2) or `zarr.json` (v3)
- Chunk files: One file per chunk (e.g., `0.0.0`, `0.0.1`, etc.)

All elements in an array have the same type. To store heterogeneous data (integers and floats, or multiple variables), use multiple arrays organized in a group.

### Groups: Hierarchical Organization

A **group** is a hierarchical container for arrays and subgroups. It functions like a filesystem directory:

```elixir
# Create root group
{:ok, root} = ExZarr.Group.create("/",
  storage: :filesystem,
  path: "/data/climate"
)

# Create arrays in the group
{:ok, temperature} = ExZarr.Group.create_array(root, "temperature",
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32
)

{:ok, pressure} = ExZarr.Group.create_array(root, "pressure",
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32
)

# Create subgroups for organization
{:ok, experiments} = ExZarr.Group.create_group(root, "experiments")
{:ok, baseline} = ExZarr.Group.create_array(experiments, "baseline",
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64
)
```

**Group structure:**
- **Arrays**: Named arrays stored within the group
- **Subgroups**: Nested groups for hierarchical organization
- **Attributes**: Metadata describing the group contents

**Filesystem layout example:**
```
/data/climate/
  .zgroup              # Group metadata
  temperature/
    .zarray            # Temperature array metadata
    0.0.0, 0.0.1, ...  # Temperature chunks
  pressure/
    .zarray            # Pressure array metadata
    0.0.0, 0.0.1, ...  # Pressure chunks
  experiments/
    .zgroup            # Subgroup metadata
    baseline/
      .zarray
      0.0, 0.1, ...
```

Groups contain no data themselves. They provide structure and can carry attributes describing their contents.

### Comparison to Python and HDF5 Terms

If you're coming from other ecosystems:

- **ExZarr Array** ≈ `zarr-python` Array ≈ NumPy `ndarray` (but chunked, compressed, persistent)
- **ExZarr Group** ≈ `zarr-python` Group ≈ HDF5 Group ≈ filesystem directory
- **ExZarr nested tuples** ≈ NumPy array (conceptually, not implementation)

The key difference: Zarr arrays are persistent and chunked, while NumPy arrays are in-memory and contiguous.

## Attributes and Metadata

Zarr distinguishes between **metadata** (required structural information) and **attributes** (optional user-defined metadata).

### Metadata: Required Structural Information

Metadata defines the array's structure and is required for ExZarr to read and write data correctly:

```elixir
# View array metadata
array.metadata.shape        # {1000, 1000}
array.metadata.chunks       # {100, 100}
array.metadata.dtype        # :float64
array.metadata.compressor   # :zstd
array.metadata.fill_value   # 0.0
array.metadata.order        # "C" (row-major)
array.metadata.zarr_format  # 2 or 3
```

**Storage locations:**
- **Zarr v2**: Stored in `.zarray` JSON file
- **Zarr v3**: Stored in `zarr.json` with consolidated structure

Metadata is typically immutable after array creation. Changing shape, dtype, or chunks requires creating a new array and copying data.

### Attributes: Optional User Metadata

Attributes are arbitrary key-value pairs you can attach to arrays or groups:

```elixir
# Set attributes when creating array
{:ok, array} = ExZarr.create(
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32,
  attributes: %{
    "units" => "degrees_celsius",
    "description" => "Daily average temperature",
    "source" => "weather_station_42",
    "version" => "1.0",
    "processing_date" => "2026-01-29"
  },
  storage: :filesystem,
  path: "/data/temperature"
)

# Read attributes later
array.metadata.attributes["units"]  # "degrees_celsius"
```

**Common attribute uses:**
- Physical units (meters, celsius, pascals)
- Data provenance (source, instrument, processing steps)
- Version information (schema version, data version)
- Descriptions (human-readable context)
- Timestamps (creation date, last modified)

**Storage locations:**
- **Zarr v2**: Stored in separate `.zattrs` JSON file
- **Zarr v3**: Embedded in `zarr.json` under `attributes` key

Attributes are JSON-serializable, so you can store strings, numbers, booleans, lists, and nested maps. Binary data or functions cannot be stored as attributes.

### Metadata vs Attributes: Key Distinction

| Aspect | Metadata | Attributes |
|--------|----------|------------|
| Purpose | Define structure | Describe content |
| Required | Yes | No |
| Mutability | Immutable (usually) | Mutable |
| Used by | ExZarr for I/O | Your application |
| Examples | shape, chunks, dtype | units, description, version |

## Chunking and the Indexing Model

Chunking is central to Zarr's design. It enables efficient partial reads, parallel I/O, and per-chunk compression.

### Why Chunks Exist

Without chunking, you'd need to read an entire array into memory to access any part of it. A 10,000 × 10,000 array of float64 values is 800 MB. If you only need a 100 × 100 slice (80 KB), reading 800 MB is wasteful.

Chunking solves this by dividing the array into fixed-size blocks:

```
Array: 10,000 × 10,000 elements (800 MB)
Chunks: 100 × 100 elements (80 KB each)
Result: 100 × 100 = 10,000 chunks

Reading a 100 × 100 slice: Load 1-4 chunks (80-320 KB)
Reading a 1,000 × 1,000 slice: Load 100 chunks (8 MB)
```

**Benefits of chunking:**
- **Partial reads**: Load only needed chunks
- **Memory efficiency**: Process large arrays incrementally
- **Parallel I/O**: Read/write multiple chunks concurrently
- **Compression**: Compress each chunk independently

### Chunk Coordinate System

Chunks form an N-dimensional grid. A 2D array with shape `{1000, 1000}` and chunks `{100, 100}` creates a 10×10 grid:

```
Chunk Grid (10 × 10):

   0   1   2   3   4   5   6   7   8   9  (chunk column)
 ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
0│0,0│0,1│0,2│0,3│0,4│0,5│0,6│0,7│0,8│0,9│
 ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
1│1,0│1,1│1,2│1,3│1,4│1,5│1,6│1,7│1,8│1,9│
 ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
2│2,0│2,1│2,2│2,3│2,4│2,5│2,6│2,7│2,8│2,9│
 ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
3│3,0│3,1│3,2│3,3│3,4│3,5│3,6│3,7│3,8│3,9│
 ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤
4│4,0│4,1│4,2│4,3│4,4│4,5│4,6│4,7│4,8│4,9│
 └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
(chunk row)

Each cell represents a 100×100 block of the array.
Chunk (0,0) contains array indices [0:100, 0:100].
Chunk (2,3) contains array indices [200:300, 300:400].
```

**Chunk index calculation:**
```elixir
# Which chunk contains array index {250, 350}?
chunk_row = div(250, 100)    # 2
chunk_col = div(350, 100)    # 3
# Answer: Chunk (2, 3)

# Or use ExZarr.Chunk utility:
ExZarr.Chunk.index_to_chunk({250, 350}, {100, 100})
# => {2, 3}
```

### Chunk Keys: Mapping to Storage

Zarr maps chunk coordinates to storage keys:

**Zarr v2 format:**
- Chunk keys use dot-separated notation: `"0.0"`, `"0.1"`, `"2.3"`
- Flat namespace (all chunks in same directory)
- Example: `/data/array/2.3` stores chunk (2, 3)

**Zarr v3 format:**
- Chunk keys use slash-separated notation with prefix: `"c/0/0"`, `"c/0/1"`, `"c/2/3"`
- Hierarchical namespace (chunks under `c/` prefix)
- Example: `/data/array/c/2/3` stores chunk (2, 3)

The storage backend translates chunk keys into actual storage locations (filesystem paths, S3 keys, etc.).

### Indexing Model: Slices to Chunks

When you read a slice, ExZarr calculates which chunks overlap the requested region:

```elixir
# Read array slice [0:250, 0:350]
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {250, 350}
)

# ExZarr internally determines affected chunks:
# Rows: 0:250 spans chunks 0, 1, 2 (0:100, 100:200, 200:250)
# Cols: 0:350 spans chunks 0, 1, 2, 3 (0:100, 100:200, 200:300, 300:350)
# Affected chunks: (0,0), (0,1), (0,2), (0,3)
#                  (1,0), (1,1), (1,2), (1,3)
#                  (2,0), (2,1), (2,2), (2,3)
# Total: 12 chunks
```

**Slice to chunks visualization:**
```
Requested slice: [0:250, 0:350]

   0   1   2   3   4  ...
 ┌───┬───┬───┬───┬───┐
0│ X │ X │ X │ X │   │  Row 0-99
 ├───┼───┼───┼───┼───┤
1│ X │ X │ X │ X │   │  Row 100-199
 ├───┼───┼───┼───┼───┤
2│ X │ X │ X │ X │   │  Row 200-249 (partial)
 ├───┼───┼───┼───┼───┤
3│   │   │   │   │   │
 └───┴───┴───┴───┴───┘
 Col Col Col Col
 0-  100 200 300
 99  199 299 349

X = chunk needs to be read
```

ExZarr reads all affected chunks, decompresses them, and extracts only the requested slice region from each chunk.

### Uninitialized Chunks

Chunks you haven't written are not stored on disk. Reading an uninitialized chunk returns the fill value:

```elixir
# Create array but write nothing
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  fill_value: -999.0,
  storage: :filesystem,
  path: "/data/sparse_array"
)

# Read uninitialized region
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {500, 500},
  stop: {600, 600}
)

# All values are -999.0 (the fill value)
# No chunk file was created on disk
```

This makes Zarr efficient for sparse arrays where most values are zero or undefined.

### Chunk Size Design Considerations

Choosing chunk size involves trade-offs:

| Factor | Small Chunks (10×10) | Medium Chunks (100×100) | Large Chunks (1000×1000) |
|--------|----------------------|-------------------------|--------------------------|
| Memory per chunk | 800 bytes | 80 KB | 8 MB |
| I/O granularity | Fine-grained | Balanced | Coarse |
| Compression ratio | Poor | Good | Excellent |
| Parallel opportunities | Many chunks | Moderate | Few chunks |
| Cloud API calls | Many | Moderate | Few |

**General guidelines:**
- **Memory-constrained**: Use smaller chunks (fit in available RAM)
- **Cloud storage**: Larger chunks reduce API calls (S3 charges per request)
- **Sequential access**: Chunks aligned with access pattern (e.g., full rows)
- **Random access**: Smaller chunks reduce read overhead
- **Compression priority**: Larger chunks compress better (more context)

**Common patterns:**
- Time-series (3D): Chunk along time axis for sequential reads `{1, 1000, 1000}`
- Images (2D): Chunks match tile size `{256, 256}`
- Tabular (2D): Full rows `{1, 10000}` or balanced `{100, 100}`

## Codecs and Filter Pipeline

Codecs transform chunk data before storage. This includes compression (reduce size), filtering (improve compression), and checksums (verify integrity).

### Codec Types

**Compression codecs** (reduce size):
- `:zlib` - Standard compression (Erlang built-in, always available)
- `:gzip` - Compatible with gzip tools (Erlang built-in)
- `:zstd` - Fast compression with excellent ratio (Zig NIF)
- `:lz4` - Very fast compression, lower ratio (Zig NIF)
- `:blosc` - Multi-threaded compression (Zig NIF)
- `:bzip2` - High compression ratio, slower (Zig NIF)
- `:snappy` - Fast compression, moderate ratio (Zig NIF)

**Checksum codecs** (verify integrity):
- `:crc32c` - CRC32 checksum for error detection (Zig NIF)

**Filter codecs** (transform before compression):
- `Shuffle` - Reorder bytes by element position (improves compression for numeric data)
- `Delta` - Encode differences between adjacent values (good for time-series)
- `Quantize` - Reduce precision for better compression (lossy)

### Pipeline Execution Order

Zarr v3 introduces an explicit codec pipeline. Data flows through codecs in order:

```
Write Pipeline:
┌─────────────┐
│ Array Data  │  Typed N-dimensional data (e.g., float64)
└──────┬──────┘
       ↓
┌──────────────────┐
│ Array-to-Array   │  Filters: Delta, Quantize
│ Codecs           │  (operate on typed arrays)
└──────┬───────────┘
       ↓
┌──────────────────┐
│ Array-to-Bytes   │  Convert to binary representation
│ Codec            │  (handles endianness, shaping)
└──────┬───────────┘
       ↓
┌──────────────────┐
│ Bytes-to-Bytes   │  Filters: Shuffle
│ Codecs           │  (reorder bytes)
└──────┬───────────┘
       ↓
┌──────────────────┐
│ Bytes-to-Bytes   │  Compression: zstd, lz4, etc.
│ Codec            │  (reduce size)
└──────┬───────────┘
       ↓
┌──────────────────┐
│ Storage          │  Write compressed bytes to backend
└──────────────────┘

Read Pipeline: Reverse order
```

**Example v3 codec configuration:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    # Step 1: Shuffle bytes (improves compression)
    %{name: "transpose", configuration: %{order: [0, 1]}},
    # Step 2: Convert array to bytes
    %{name: "bytes", configuration: %{endian: "little"}},
    # Step 3: Shuffle bytes within elements
    %{name: "shuffle", configuration: %{elementsize: 8}},
    # Step 4: Compress with zstd
    %{name: "zstd", configuration: %{level: 3}}
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/data/array"
)
```

### Zarr v2 Codec Configuration

Zarr v2 has an implicit pipeline: filters run before the compressor:

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [
    {:shuffle, [elementsize: 8]}
  ],
  compressor: :zstd,
  zarr_version: 2,
  storage: :filesystem,
  path: "/data/array"
)

# Implicit pipeline:
# 1. Apply shuffle filter
# 2. Compress with zstd
# 3. Write to storage
```

ExZarr internally converts v2 configuration to v3 pipeline for consistent execution.

### Codec Selection Guidance

**Prioritize availability:**
- `:zlib` is always available (Erlang built-in)
- Other codecs require Zig NIFs (see [Installation Guide](../README.md#installation))

**Compression vs speed trade-offs:**
- **Fastest**: `:lz4` (good for hot data, frequent access)
- **Balanced**: `:zstd` at level 3 (default, recommended)
- **Best compression**: `:zstd` at level 9 or `:bzip2` (cold storage, archival)

**Filter recommendations:**
- Use `shuffle` for numeric arrays (float32, float64, int64)
- Use `delta` for time-series with smooth gradients
- Avoid quantize unless you can tolerate precision loss

**Testing your workload:**
```elixir
# Benchmark different codecs with your data
ExZarr.Benchmarks.compression_ratio(data, [:zlib, :zstd, :lz4])
# Returns: %{zlib: 0.42, zstd: 0.38, lz4: 0.52}
# (lower ratio = better compression)
```

## Storage Abstraction

ExZarr separates array logic from storage implementation. The same array API works with any storage backend.

### Backend Architecture

A storage backend implements five operations:

1. **Read metadata** - Load `.zarray` or `zarr.json`
2. **Write metadata** - Save array structure
3. **Read chunk** - Load chunk data by key
4. **Write chunk** - Save chunk data by key
5. **List chunks** - Enumerate existing chunks

ExZarr coordinates these operations while the backend handles storage-specific details.

### Available Backends

**In-memory storage** (`:memory`):
- Stores chunks in Elixir process memory (map)
- Fast, no I/O overhead
- Non-persistent (lost on process exit)
- Use for: testing, temporary arrays, caching

**Filesystem storage** (`:filesystem`):
- Stores chunks as individual files
- POSIX filesystem layout (`.zarray`, `0.0`, `0.1`, ...)
- Portable across systems
- Use for: local processing, shared network storage

**ETS storage** (`:ets`):
- Stores chunks in Erlang Term Storage table
- Fast in-memory storage shared across processes
- Non-persistent (lost on VM restart)
- Use for: multi-process coordination, faster than memory backend

**Mnesia storage** (`:mnesia`):
- Stores chunks in Mnesia distributed database
- Persistent, replicated across nodes
- ACID transactions, queries
- Use for: distributed systems, replication

**S3 storage** (`:s3`):
- Stores chunks in AWS S3
- Object storage, HTTP API
- Scalable, durable, cloud-native
- Use for: cloud deployments, large datasets, shared access

**GCS storage** (`:gcs`):
- Stores chunks in Google Cloud Storage
- Similar to S3, different API
- Use for: Google Cloud Platform deployments

**Azure Blob storage** (`:azure`):
- Stores chunks in Azure Blob Storage
- Similar to S3, Microsoft Azure
- Use for: Azure deployments

**MongoDB GridFS** (`:gridfs`):
- Stores chunks in MongoDB GridFS
- Document database with file storage
- Use for: MongoDB-centric applications

### Storage Backend Transparency

The key insight: Zarr doesn't care where data lives. The chunk format is identical regardless of backend:

```elixir
# Development: use memory storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd,
  storage: :memory
)

# Staging: use filesystem
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd,
  storage: :filesystem,
  path: "/mnt/staging/arrays"
)

# Production: use S3
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd,
  storage: :s3,
  bucket: "prod-data",
  prefix: "arrays/experiment_42"
)

# All three have identical chunk format on disk/cloud
# Can copy chunks between backends without transformation
```

### Backend Responsibilities

**Metadata serialization:**
- Convert ExZarr metadata struct to JSON
- Write to `.zarray` (v2) or `zarr.json` (v3)
- Handle storage-specific paths

**Chunk key mapping:**
- Map chunk coordinates like `{2, 3}` to storage keys
- v2: `"2.3"` → `/path/to/array/2.3`
- v3: `{2, 3}` → `/path/to/array/c/2/3`
- S3: `{2, 3}` → `s3://bucket/prefix/c/2/3`

**Error handling:**
- Network errors (S3, GCS, Azure)
- Permission errors (filesystem)
- Storage full (filesystem)
- Missing chunks (return fill value)

**Concurrency:**
- Safe concurrent reads (all backends)
- Safe concurrent writes to different chunks (most backends)
- Atomic metadata writes (backend-dependent)

### Custom Storage Backends

You can implement your own storage backend:

```elixir
defmodule MyApp.CustomStorage do
  @behaviour ExZarr.Storage.Backend

  @impl true
  def init(config), do: {:ok, %{config: config}}

  @impl true
  def read_chunk(state, chunk_key) do
    # Your storage read logic
  end

  @impl true
  def write_chunk(state, chunk_key, data) do
    # Your storage write logic
  end

  # ... implement other callbacks
end

# Register and use
ExZarr.Storage.Registry.register(:custom, MyApp.CustomStorage)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :custom,
  custom_config: "value"
)
```

See the [Custom Storage Backend Guide](custom_storage_backend.md) for details.

## Zarr v2 vs v3 Conceptual Differences

ExZarr supports both Zarr v2 and v3 specifications. They differ in file organization, codec configuration, and features.

### File Organization

**Zarr v2 structure:**
```
/path/to/array/
  .zarray          # Metadata (shape, chunks, dtype, compressor)
  .zattrs          # Attributes (optional user metadata)
  0.0              # Chunk at index (0, 0)
  0.1              # Chunk at index (0, 1)
  1.0              # Chunk at index (1, 0)
  ...
```

**Zarr v3 structure:**
```
/path/to/array/
  zarr.json        # Consolidated metadata + attributes
  c/0/0            # Chunk at index (0, 0)
  c/0/1            # Chunk at index (0, 1)
  c/1/0            # Chunk at index (1, 0)
  ...
```

**Key differences:**
- v2 uses multiple files (`.zarray`, `.zattrs`); v3 uses single `zarr.json`
- v2 has flat chunk namespace (`0.0`); v3 has hierarchical namespace (`c/0/0`)
- v3 adds `c/` prefix to separate chunks from metadata

### Codec Configuration

**Zarr v2 approach (implicit pipeline):**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [
    {:shuffle, [elementsize: 8]}  # Applied first
  ],
  compressor: :zstd,  # Applied second
  zarr_version: 2
)

# Pipeline order is implicit: filters → compressor
```

**Zarr v3 approach (explicit pipeline):**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "transpose", configuration: %{order: [0, 1]}},
    %{name: "bytes", configuration: %{endian: "little"}},
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "zstd", configuration: %{level: 3}}
  ],
  zarr_version: 3
)

# Pipeline order is explicit: user specifies sequence
```

v3 gives you control over codec order, which matters for some transformations.

### Data Type Representation

**Zarr v2 dtype format (NumPy-style):**
- Little-endian int32: `"<i4"`
- Big-endian float64: `">f8"`
- Little-endian uint16: `"<u2"`

**Zarr v3 dtype format (simplified):**
- int32: `"int32"`
- float64: `"float64"`
- uint16: `"uint16"`

v3 removes endianness from dtype string (configured separately in codec pipeline).

### Chunk Keys

**Zarr v2 chunk keys:**
- Dot-separated: `"0.0"`, `"5.3"`, `"10.20.30"`
- Flat namespace (no prefix)

**Zarr v3 chunk keys:**
- Slash-separated with prefix: `"c/0/0"`, `"c/5/3"`, `"c/10/20/30"`
- Hierarchical namespace (chunks under `c/`)

This allows v3 to support other prefixes (e.g., `meta/` for shard indices).

### Advanced Features (v3 Only)

**Sharding:**
Combine multiple chunks into a single storage object:
```elixir
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {100, 100},  # Logical chunks
  shard_shape: {1000, 1000},  # Physical storage units
  zarr_version: 3
)

# Creates 10×10 = 100 logical chunks
# Stored as 1×1 = 1 shard file
# Reduces cloud API calls from 100 to 1
```

**Dimension names:**
Semantic labels for array axes:
```elixir
{:ok, array} = ExZarr.create(
  shape: {365, 180, 360},
  dimension_names: ["time", "latitude", "longitude"],
  zarr_version: 3
)
```

**Custom chunk grids:**
Irregular chunk sizes:
```elixir
# Variable-sized chunks for irregular data
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunk_grid: %{
    type: "irregular",
    chunks: [[0, 100, 300, 1000], [0, 200, 1000]]
  },
  zarr_version: 3
)
```

These features are not available in v2.

### Version Selection Guidance

**Use Zarr v2 when:**
- You need maximum compatibility with existing tools
- You're sharing data with users on Python, Julia, or other platforms
- You're working with legacy Zarr arrays
- Stability and broad support matter more than new features

**Use Zarr v3 when:**
- You need sharding to reduce cloud storage API calls
- You want dimension names for self-describing arrays
- You require custom chunk grids (irregular sizes)
- You're starting a new project and can control the tool ecosystem
- You want explicit control over codec pipeline order

**Migration:**
ExZarr reads both formats transparently:
```elixir
# Open any version automatically
{:ok, array} = ExZarr.open(path: "/data/some_array")

# Check detected version
array.metadata.zarr_format  # 2 or 3

# Same API regardless of version
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
```

See the [V2 to V3 Migration Guide](../docs/V2_TO_V3_MIGRATION.md) for converting existing v2 arrays to v3.

### Interoperability Validation

ExZarr's v2 and v3 implementations are validated against:
- Python `zarr-python` 2.x (v2 format)
- Python `zarr-python` 3.x beta (v3 format)
- Zarr specification test suite
- Property-based tests for correctness

Arrays created by ExZarr can be read by Python and vice versa (see [Python Interoperability Guide](python_interop.md)).

## Summary

This guide covered the fundamental concepts underlying Zarr and ExZarr:

- **Arrays** store N-dimensional typed data; **Groups** organize collections hierarchically
- **Metadata** defines structure (required); **Attributes** describe content (optional)
- **Chunking** enables partial reads, parallel I/O, and per-chunk compression
- **Codecs** transform data through explicit (v3) or implicit (v2) pipelines
- **Storage backends** abstract physical storage locations
- **Zarr v2** prioritizes compatibility; **v3** adds sharding, dimension names, and explicit pipelines

With these concepts, you can reason about chunk sizes, select appropriate codecs, choose storage backends, and make informed design decisions for your arrays.

## Next Steps

Now that you understand core concepts:

1. **Learn Parallel I/O**: See [Parallel I/O Guide](parallel_io.md) for concurrent chunk operations
2. **Configure Storage**: Set up S3, GCS, or Azure in [Storage Providers Guide](storage_providers.md)
3. **Optimize Compression**: Benchmark codecs in [Compression and Codecs Guide](compression_codecs.md)
4. **Integrate with Nx**: Connect to tensor workflows in [Nx Integration Guide](nx_integration.md)
5. **Python Interop**: Share data with Python in [Python Interoperability Guide](python_interop.md)
