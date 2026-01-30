# Overview and Philosophy

ExZarr is a pure Elixir implementation of the Zarr storage specification for compressed, chunked, N-dimensional arrays. This guide explains what ExZarr is, why it exists, and how its architecture leverages BEAM concurrency and Zig acceleration to provide high-performance array storage for scientific computing and machine learning workloads.

## What is ExZarr

ExZarr implements the Zarr specification entirely in Elixir, providing persistent storage for N-dimensional typed arrays with chunking and compression. Unlike wrapper libraries that call Python or other languages via FFI, ExZarr is a native BEAM implementation that integrates naturally with Elixir applications.

**Target Use Cases:**
- Scientific computing workflows requiring persistent array storage
- Machine learning pipelines with large training datasets
- Cloud-native data processing with S3/GCS/Azure backends
- Real-time data ingestion with concurrent writes
- Cross-language data exchange (Elixir <-> Python/Julia/R)

**Production Status:**
ExZarr v1.0.0+ is production-ready, with comprehensive test coverage including property-based tests and Python interoperability validation. The library provides full production support for both Zarr v2 and Zarr v3 specifications, with automatic format detection and seamless interoperability.

**Not a Python Wrapper:**
ExZarr does not wrap Python's zarr-python library or call Python code. It is a ground-up implementation in Elixir that reads and writes the same on-disk/cloud format, ensuring interoperability through specification compliance rather than library coupling.

## The BEAM Advantage

The BEAM virtual machine provides ExZarr with concurrency and fault-tolerance capabilities that are difficult to achieve in other ecosystems.

### Native Concurrency Model

The BEAM's lightweight process model enables true parallelism for chunk operations:

```elixir
# Read 16 chunks concurrently
chunk_coords = for i <- 0..3, j <- 0..3, do: {i, j}

results = Task.async_stream(
  chunk_coords,
  fn {i, j} ->
    ExZarr.Array.get_slice(array,
      start: {i * 100, j * 100},
      stop: {(i + 1) * 100, (j + 1) * 100}
    )
  end,
  max_concurrency: 8
)
|> Enum.to_list()
```

Each chunk operation runs in its own BEAM process, with true OS-level parallelism across CPU cores. There is no global interpreter lock limiting concurrent CPU-bound work.

### Comparison to Python's GIL

Python's Global Interpreter Lock (GIL) prevents threads from executing Python bytecode in parallel. This means:

- **Python with GIL**: Multiple threads can perform I/O concurrently, but CPU-bound operations (decompression, codec pipeline) are serialized. Only one thread executes Python code at a time.
- **ExZarr on BEAM**: Multiple processes decompress and process chunks simultaneously across all CPU cores. Each BEAM scheduler runs independently on a separate OS thread.

This architectural difference is why ExZarr can achieve significant performance improvements in multi-chunk operations. Internal benchmarks show a 26x improvement in multi-chunk read performance compared to a prior single-threaded implementation. This represents optimization of ExZarr's own implementation, not a direct comparison to Python's zarr-python (which would require identical test conditions and workloads).

### Supervisor Trees for Fault Tolerance

ExZarr uses OTP supervision patterns to manage long-running services:

- Codec registry (GenServer) tracks available compression codecs
- Storage backend registry manages pluggable storage implementations
- Array processes handle concurrent access coordination
- Automatic restart on failure ensures service availability

This design provides robustness for long-running data pipelines where temporary failures (network issues, transient storage errors) should not crash the application.

### Concurrent I/O Benefits

When reading from cloud storage (S3, GCS, Azure), network latency dominates total time. BEAM's async I/O model allows hundreds of concurrent chunk requests:

```
Sequential S3 reads (100 chunks):
  100 chunks × 100ms latency = 10,000ms total

Parallel S3 reads (10 concurrent):
  100 chunks / 10 × 100ms = 1,000ms total
  Speedup: 10x
```

The BEAM's process model makes this parallelism natural to express and safe to execute.

## Zig Acceleration Explained

ExZarr uses Zig for performance-critical compression codecs while keeping coordination logic in Elixir.

### Why Zig Over Alternatives

- **Simpler C interop**: Zig can directly import C libraries (`@cImport`) without bindings
- **Zigler integration**: The Zigler library provides seamless Zig NIF compilation in Mix
- **Smaller footprint**: Zig produces compact binaries compared to alternative approaches
- **No runtime dependency**: Unlike Rustler (which requires Rust toolchain at compile time), Zig is more lightweight

### What Runs Where

**Elixir handles:**
- Metadata parsing and validation (JSON deserialization)
- Chunk coordinate calculations and indexing
- Storage I/O coordination (backend selection, error handling)
- Concurrent task scheduling (Task.async_stream orchestration)
- Array lifecycle management (GenServer state)

**Zig NIFs handle:**
- Compression: zstd, lz4, snappy, blosc, bzip2
- Decompression: reverse operations
- CRC32C checksum calculation
- Direct calls to C libraries (libzstd, liblz4, etc.)

This division keeps the hot path (compression/decompression) in native code while maintaining high-level logic in readable Elixir.

### Fallback Behavior

ExZarr gracefully degrades when Zig NIFs are unavailable:

```elixir
# Zig codecs fail to compile (missing system libraries)
# ExZarr falls back to Erlang's built-in :zlib

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd  # Attempts Zig NIF first
)

# If zstd NIF unavailable, uses :zlib automatically
# Or specify fallback explicitly:
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib  # Always available (Erlang built-in)
)
```

The Erlang `:zlib` module is always available and provides reliable compression without any native dependencies. This ensures ExZarr works even in environments where Zig compilation is not possible.

### NIF Safety

Native code in the BEAM requires care to avoid crashing the VM. ExZarr's Zig NIFs follow safety practices:

- **Memory management**: Uses BEAM allocator for all allocations
- **Error handling**: Returns `{:error, reason}` tuples rather than crashing
- **Bounded execution**: Compression operations are bounded by chunk size
- **No blocking**: NIFs release scheduler during long operations where possible

The Zigler library handles much of this complexity automatically, generating safe NIF wrappers from Zig code.

## Zarr in the Elixir Stack

ExZarr fills the persistent array storage role in the Elixir numerical computing ecosystem.

### Relationship to Nx

[Nx (Numerical Elixir)](https://hexdocs.pm/nx) provides in-memory tensor operations similar to NumPy. ExZarr complements Nx by providing persistent storage:

```elixir
# Compute with Nx
tensor = Nx.tensor([[1, 2], [3, 4]])
result = Nx.add(tensor, 10)

# Persist with ExZarr
{:ok, array} = ExZarr.create(
  shape: Nx.shape(result),
  chunks: {2, 2},
  dtype: :int32,
  storage: :filesystem,
  path: "/data/results"
)

# Convert and write
data = result |> Nx.to_list() |> list_to_nested_tuple()
ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {2, 2})
```

This separation of concerns allows Nx to focus on computation while ExZarr handles persistence, compression, and cloud storage.

### Integration with Data Pipelines

ExZarr arrays can serve as data sources or sinks in BEAM-based pipelines:

- **Broadway**: Stream processing framework can read chunks as job batches
- **GenStage**: Back-pressure aware pipelines can consume chunks on demand
- **Phoenix LiveView**: Serve array slices as real-time data updates
- **Oban**: Background jobs can process array chunks asynchronously

The BEAM's message-passing model makes it natural to pipe chunk data between processes.

### Cloud-Native Architecture

ExZarr's storage backend abstraction aligns with cloud-native deployment:

```elixir
# Development: local filesystem
{:ok, array} = ExZarr.create(storage: :filesystem, path: "/tmp/dev_data")

# Staging: S3 with test credentials
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "staging-data",
  prefix: "experiments/test"
)

# Production: S3 with IAM role (no credentials in code)
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "prod-data",
  prefix: "experiments/prod"
)
```

The same array API works regardless of storage backend, simplifying environment-specific configuration.

### Interoperability Bridge

ExZarr enables data exchange between BEAM applications and the broader scientific computing ecosystem:

- **Python → Elixir**: ML training (Python scikit-learn) → inference service (Elixir Phoenix)
- **Elixir → Python**: Data pipeline (Elixir Broadway) → analysis (Python Pandas)
- **Elixir → Julia**: Simulation (Elixir) → statistical analysis (Julia)
- **Multi-language**: Collaborative research with mixed technology stacks

This interoperability is achieved through Zarr specification compliance, not runtime coupling.

## Version Support

ExZarr supports both Zarr v2 and Zarr v3 specifications, with automatic format detection.

### Zarr v2 (Stable, Widely Supported)

Zarr v2 is the mature, stable specification with broad tool support:

- **Status**: Full specification compliance, production-ready
- **Python compatibility**: Works with zarr-python 2.x (stable)
- **File format**: Separate `.zarray`, `.zattrs` files, dot-separated chunk keys
- **Codec configuration**: Implicit pipeline (filters → compressor)
- **Recommendation**: Use v2 for maximum interoperability

Example:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 2,
  storage: :filesystem,
  path: "/data/v2_array"
)
```

### Zarr v3 (Modern, Recommended for New Projects)

Zarr v3 introduces improvements and new capabilities:

- **Status**: Fully implemented in ExZarr, production-ready
- **Python compatibility**: Full interoperability with zarr-python 3.x
- **File format**: Unified `zarr.json`, slash-separated chunk keys with prefix
- **Codec configuration**: Explicit pipeline with user-controlled order
- **Advanced features**: Sharding support (multiple chunks per storage object), dimension names, custom chunk grids
- **Recommendation**: Use v3 for new projects (modern standard)

Example:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "bytes"},  # Explicit array-to-bytes
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/data/v3_array"
)
```

### Automatic Version Detection

When opening existing arrays, ExZarr automatically detects the format version:

```elixir
# Opens v2 or v3 arrays transparently
{:ok, array} = ExZarr.open(path: "/data/some_array")

# Check detected version
array.metadata.zarr_format  # Returns 2 or 3

# Both versions use the same API
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
```

This allows applications to work with arrays created by different tools without modification.

### Choosing a Version

**Use Zarr v3 when (recommended default):**
- Starting new projects (modern standard)
- Need unified codec pipeline for flexibility
- Want improved metadata format with embedded attributes
- Require sharding to reduce API calls on cloud storage
- Want dimension names for semantic array axes
- Working with zarr-python 3.x or other modern Zarr implementations

**Use Zarr v2 when:**
- Maximum compatibility with older tools is required
- Working with legacy Python zarr-python 2.x codebases
- Sharing data with users on older platforms
- Compatibility with legacy tools is more important than modern features

**Migration:**
ExZarr can read both formats, so migration is gradual. Existing v2 arrays can coexist with new v3 arrays. See the [V2 to V3 Migration Guide](../docs/V2_TO_V3_MIGRATION.md) for detailed conversion guidance.

### Compatibility Validation

ExZarr's v2 and v3 implementations are validated against:
- Zarr specifications from zarr-specs repository
- Python zarr-python reference implementation (integration tests)
- Property-based tests for codec pipeline correctness
- Interoperability test suite (14 tests, bidirectional read/write)

This validation ensures ExZarr arrays work correctly with other tools in the Zarr ecosystem.

---

## Summary

ExZarr brings Zarr array storage to the BEAM with:

- **Pure Elixir implementation**: No Python dependencies, native BEAM integration
- **BEAM concurrency**: True parallelism for multi-chunk operations without GIL constraints
- **Zig acceleration**: High-performance codecs via NIFs, graceful fallback to Erlang zlib
- **Ecosystem integration**: Complements Nx, integrates with Broadway/GenStage, cloud-native design
- **Specification compliance**: Full Zarr v2 and v3 support with automatic format detection

This architecture positions ExZarr as a robust foundation for scientific computing and machine learning workloads in Elixir, while maintaining interoperability with the broader data science ecosystem.
