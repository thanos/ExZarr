# ExZarr

[![Hex.pm](https://img.shields.io/hexpm/v/ex_zarr.svg)](https://hex.pm/packages/ex_zarr)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_zarr)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dt/ex_zarr.svg)](https://hex.pm/packages/ex_zarr)
[![License](https://img.shields.io/hexpm/l/ex_zarr.svg)](https://github.com/thanos/ExZarr/blob/main/LICENSE)
[![Build Status](https://github.com/thanos/ExZarr/workflows/CI/badge.svg)](https://github.com/thanos/ExZarr/actions)
[![Coverage Status](https://coveralls.io/repos/github/thanos/ExZarr/badge.svg?branch=main)](https://coveralls.io/github/thanos/ExZarr?branch=main)

Elixir implementation of [Zarr](https://zarr.dev): compressed, chunked, N-dimensional arrays designed for parallel computing and scientific data storage.

## Features

- **High Performance** - 26x faster multi-chunk reads with near-optimal scaling (see [Performance Guide](guides/performance.md))
- **N-dimensional arrays** with support for 10 data types (int8-64, uint8-64, float32/64)
- **Parallel chunk processing** - Automatic parallel I/O and decompression for large operations
- **Chunking** along arbitrary dimensions for optimized I/O operations
- **Compression** using Erlang zlib (with fallback support for zstd and lz4)
- **Flexible storage** backends (in-memory, filesystem, and zip archive)
- **Custom storage backends** with plugin architecture for S3, databases, and more
- **Hierarchical groups** for organizing multiple arrays
- **Zarr v2 and v3 specification** support with automatic version detection
- **Full backward compatibility** - seamlessly work with both v2 and v3 arrays
- **Property-based testing** with comprehensive test coverage

## Installation

Add `ex_zarr` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"}
  ]
end
```

## Quick Start

### Creating an Array

```elixir
# Create a 2D array in memory
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  storage: :memory
)
```

### Saving and Loading Arrays

```elixir
# Save array to filesystem
:ok = ExZarr.save(array, path: "/tmp/my_array")

# Open existing array
{:ok, array} = ExZarr.open(path: "/tmp/my_array")

# Load entire array into memory
{:ok, data} = ExZarr.load(path: "/tmp/my_array")
```

## Performance

ExZarr v0.8+ includes major performance optimizations:

- **26x faster multi-chunk reads** - Optimized from 110ms to 4.2ms for 16-chunk operations
- **Near-optimal scaling** - Reading N chunks takes ~N× single chunk time
- **Parallel I/O** - Automatic parallelization for multi-chunk operations
- **99% memory reduction** - Eliminated redundant binary copies

**Benchmark results** (400×400 array, 16 chunks):
- Before: 110ms per read
- After: 4.2ms per read
- **Speedup: 26×**

See [Performance Guide](guides/performance.md) for tuning recommendations and [Benchmarks](benchmarks/README.md) for running your own tests.

```bash
# Run quick performance check (completes in 6 seconds)
mix run benchmarks/slicing_bench_quick.exs
```

## Zarr Format Support

ExZarr supports both Zarr v2 and v3 specifications. Arrays can be created in either format, and opening arrays automatically detects the version.

### Zarr v3 (Recommended for New Projects)

Zarr v3 introduces a unified codec pipeline and improved metadata format:

```elixir
# Create v3 array with unified codec pipeline
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},  # Required array-to-bytes codec
    %{name: "gzip", configuration: %{level: 5}}  # Optional compression
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/tmp/my_v3_array"
)
```

### Zarr v2 (Default for Compatibility)

Zarr v2 uses separate filters and compressor configuration:

```elixir
# Create v2 array (explicit version)
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 2,
  storage: :filesystem,
  path: "/tmp/my_v2_array"
)
```

### Automatic Version Detection

When opening arrays, ExZarr automatically detects the format version:

```elixir
# Opens v2 or v3 transparently
{:ok, array} = ExZarr.open(path: "/tmp/my_array")

# Check which version was detected
array.version  # Returns 2 or 3
```

### Key Differences Between v2 and v3

| Feature | v2 | v3 |
|---------|----|----|
| Metadata file | `.zarray` | `zarr.json` |
| Chunk keys | Dot-separated (`0.1.2`) | Slash-separated with prefix (`c/0/1/2`) |
| Codec organization | Separate `filters` and `compressor` | Unified `codecs` array |
| Data types | NumPy-style strings (`<f8`) | Simplified names (`float64`) |
| Groups | Separate `.zgroup` files | Unified `zarr.json` with `node_type` |
| Attributes | Separate `.zattrs` files | Embedded in `zarr.json` |

### Converting from v2 to v3

v2-style configuration is automatically converted when creating v3 arrays:

```elixir
# This v2-style configuration
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 3  # Request v3 format
)

# Automatically converts to v3 codec pipeline:
# [
#   %{name: "shuffle", configuration: %{elementsize: 8}},
#   %{name: "bytes"},
#   %{name: "gzip", configuration: %{level: 5}}
# ]
```

For detailed migration guidance, see [docs/V2_TO_V3_MIGRATION.md](docs/V2_TO_V3_MIGRATION.md).

### Working with Groups

```elixir
# Create a hierarchical group structure
{:ok, root} = ExZarr.Group.create("/data",
  storage: :filesystem,
  path: "/tmp/zarr_data"
)

# Create arrays within the group
{:ok, measurements} = ExZarr.Group.create_array(root, "measurements",
  shape: {1000},
  chunks: {100},
  dtype: :float64
)

# Create subgroups
{:ok, subgroup} = ExZarr.Group.create_group(root, "experiments")
```

### Interoperability with Python

ExZarr is fully compatible with Python's zarr library. Arrays created by one can be read by the other:

```bash
# Run the interoperability demo
elixir examples/python_interop_demo.exs
```

This demonstrates:
- Creating arrays with ExZarr that Python can read
- Creating arrays with Python that ExZarr can read
- Compatible metadata and compression

**For detailed interoperability information, see [INTEROPERABILITY.md](INTEROPERABILITY.md)** which covers:
- Data type compatibility table
- Compression compatibility guidelines
- Metadata format details
- File structure specifications
- Complete examples of multi-language workflows
- Troubleshooting common issues

### Custom Codecs Example

See how to create and use custom compression codecs:

```bash
# Run the custom codec example
mix run examples/custom_codec_example.exs
```

This demonstrates:
- Creating custom transformation codecs (UppercaseCodec)
- Creating custom compression codecs (RleCodec)
- Registering and unregistering codecs at runtime
- Querying codec information
- Chaining custom codecs with built-in codecs

### Custom Storage Backend Example

See the test suite for a complete example of implementing a custom storage backend:

```bash
# View the custom storage tests
cat test/ex_zarr_custom_storage_test.exs
```

The example demonstrates:
- Implementing the `ExZarr.Storage.Backend` behavior
- Registering and using custom backends
- Integration with filters and compression
- Registry operations (list, get, info)

## Supported Data Types

ExZarr supports the following data types:

- **Integers**: `:int8`, `:int16`, `:int32`, `:int64`
- **Unsigned integers**: `:uint8`, `:uint16`, `:uint32`, `:uint64`
- **Floating point**: `:float32`, `:float64`

All data types use little-endian byte order by default, consistent with the Zarr specification.

## Compression Codecs

ExZarr provides the following built-in compression options:

- **`:none`** - No compression (fastest, largest size)
- **`:zlib`** - Standard zlib compression (good balance of speed and compression)
- **`:crc32c`** - CRC32C checksum codec (RFC 3720 compatible with Python zarr)
- **`:zstd`** - Zstandard compression (Zig NIF implementation)
- **`:lz4`** - LZ4 compression (Zig NIF implementation)
- **`:snappy`** - Snappy compression (Zig NIF implementation)
- **`:blosc`** - Blosc meta-compressor (Zig NIF implementation)
- **`:bzip2`** - Bzip2 compression (Zig NIF implementation)

The `:zlib` codec uses Erlang's built-in `:zlib` module for maximum reliability and compatibility.

### Custom Codecs

ExZarr supports custom codecs through a behavior-based plugin system. You can create your own compression, checksum, or transformation codecs:

```elixir
defmodule MyCustomCodec do
  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: :my_codec

  @impl true
  def codec_info do
    %{
      name: "My Custom Codec",
      version: "1.0.0",
      type: :compression,  # or :transformation
      description: "My custom compression algorithm"
    }
  end

  @impl true
  def available?, do: true

  @impl true
  def encode(data, opts) when is_binary(data) do
    # Your encoding logic here
    {:ok, compressed_data}
  end

  @impl true
  def decode(data, opts) when is_binary(data) do
    # Your decoding logic here
    {:ok, decompressed_data}
  end

  @impl true
  def validate_config(opts) do
    # Validate options
    :ok
  end
end

# Register your codec
:ok = ExZarr.Codecs.register_codec(MyCustomCodec)

# Use it like any built-in codec
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  compressor: :my_codec
)
```

For complete examples, see `examples/custom_codec_example.exs` which includes:
- `UppercaseCodec` - Simple transformation codec
- `RleCodec` - Run-length encoding compression

**Custom codec features:**
- Runtime registration and unregistration
- Behavior-based contract for consistency
- Seamless integration with built-in codecs
- Can be chained with other codecs
- Managed by supervised GenServer registry

## Storage Backends

ExZarr includes three built-in storage backends:

- **`:memory`** - In-memory storage for temporary arrays (non-persistent, fast)
- **`:filesystem`** - Local filesystem storage using Zarr v2 directory structure (persistent, interoperable)
- **`:zip`** - Zip archive storage for compact single-file arrays (portable, easy to distribute)

Arrays stored on the filesystem use the standard Zarr format:
- **v2 format**: Metadata in `.zarray` files, chunks as `0.0`, `0.1`, groups as `.zgroup`
- **v3 format**: Metadata in `zarr.json` files, chunks in `c/` directory as `c/0/0`, `c/0/1`
- Automatic format detection when opening existing arrays

### Using Zip Storage

Zip storage stores the entire array (metadata + all chunks) in a single zip file:

```elixir
# Create array with zip storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :zip,
  path: "/tmp/my_array.zip"
)

# Write data
ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

# Save to zip file
:ok = ExZarr.save(array, path: "/tmp/my_array.zip")

# Open existing zip
{:ok, reopened} = ExZarr.open(path: "/tmp/my_array.zip", storage: :zip)
```

### Custom Storage Backends

ExZarr supports custom storage backends through a behavior-based plugin system, similar to custom codecs. Create backends for S3, databases, cloud storage, or any other storage system:

```elixir
defmodule MyApp.S3Storage do
  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :s3

  @impl true
  def init(config) do
    # Initialize S3 connection
    bucket = Keyword.fetch!(config, :bucket)
    {:ok, %{bucket: bucket, client: setup_s3_client()}}
  end

  @impl true
  def read_chunk(state, chunk_index) do
    # Read chunk from S3
    key = build_s3_key(chunk_index)
    AWS.S3.get_object(state.client, state.bucket, key)
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    # Write chunk to S3
    key = build_s3_key(chunk_index)
    AWS.S3.put_object(state.client, state.bucket, key, data)
  end

  # Implement other required callbacks...
end

# Register your backend
:ok = ExZarr.Storage.Registry.register(MyApp.S3Storage)

# Use it like any built-in backend
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :s3,
  bucket: "my-zarr-data"
)
```

**Custom storage backend features:**
- Runtime registration and unregistration via Registry
- Behavior-based contract ensures all required operations are implemented
- Seamless integration with all ExZarr features (filters, compression, metadata)
- Can be configured via application config for automatic loading
- Thread-safe operations managed by OTP GenServer

**Required callbacks:**
- `backend_id/0` - Returns unique atom identifier
- `init/1` - Initialize storage with configuration
- `open/1` - Open existing storage location
- `read_chunk/2` - Read a chunk by index
- `write_chunk/3` - Write a chunk
- `read_metadata/1` - Read array metadata
- `write_metadata/3` - Write array metadata
- `list_chunks/1` - List all chunk indices
- `delete_chunk/2` - Delete a chunk
- `exists?/1` - Check if storage location exists

### Cloud and Database Storage Backends

ExZarr includes several pre-built storage backends for cloud services and databases:

#### AWS S3 Storage

```elixir
# Add dependencies
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :s3,
  bucket: "my-zarr-bucket",
  prefix: "experiments/array1",
  region: "us-west-2"
)
```

#### Azure Blob Storage

```elixir
# Add dependency
{:azurex, "~> 0.3"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.AzureBlob)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :azure_blob,
  account_name: "mystorageaccount",
  account_key: System.get_env("AZURE_STORAGE_KEY"),
  container: "zarr-data",
  prefix: "experiments/array1"
)
```

#### Google Cloud Storage

```elixir
# Add dependencies
{:goth, "~> 1.4"},
{:req, "~> 0.4"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.GCS)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :gcs,
  bucket: "my-zarr-bucket",
  prefix: "experiments/array1",
  credentials: "/path/to/service-account.json"
)
```

#### Mnesia (Distributed Database)

```elixir
# No external dependencies - Mnesia is built into Erlang/OTP

# Initialize Mnesia
:mnesia.create_schema([node()])
:mnesia.start()

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mnesia)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :mnesia,
  array_id: "experiment_001",
  table_name: :zarr_storage
)
```

#### MongoDB GridFS

```elixir
# Add dependency
{:mongodb_driver, "~> 1.4"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.MongoGridFS)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :mongo_gridfs,
  url: "mongodb://localhost:27017",
  database: "zarr_db",
  bucket: "arrays",
  array_id: "experiment_001"
)
```

#### Mock Storage (Testing)

```elixir
# No dependencies - built-in for testing

:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mock)

# Test with error simulation
{:ok, array} = ExZarr.create(
  shape: {100},
  chunks: {10},
  storage: :mock,
  pid: self(),
  error_mode: :random,
  delay: 50  # Simulate 50ms latency
)

# Verify operations
assert_received {:mock_storage, :write_chunk, _}
```

**Cloud Storage Features:**
- S3, Azure Blob, and GCS backends provide scalable object storage
- Automatic credential management from environment/config
- Support for custom regions, buckets, and access patterns
- Thread-safe concurrent access

**Database Storage Features:**
- Mnesia provides distributed ACID transactions
- MongoDB GridFS handles large files (> 16MB chunks)
- Both support replication and high availability

**Mock Storage Features:**
- Error simulation (always fail, random, or specific operations)
- Latency simulation for performance testing
- Message tracking for verification
- State inspection for debugging

## Architecture

ExZarr uses:
- **Erlang :zlib** for compression and decompression
- **GenServer** for array state management
- **Pluggable storage backends** for memory and filesystem storage
- **Zarr v2 and v3 specifications** for interoperability with Python, Julia, and other Zarr implementations
- **Version-aware codec pipeline** that automatically routes between v2 and v3 implementations
- **Automatic format detection** when opening existing arrays

## Development

```bash
# Install dependencies
mix deps.get

# Compile the project
mix compile

# Run tests
mix test

# Run tests with coverage
mix coveralls

# Run specific test suites
mix test test/ex_zarr_property_test.exs              # Property-based tests
mix test test/ex_zarr_python_integration_test.exs    # Python integration tests

# Run static analysis
mix credo

# Run type checking
mix dialyzer

# Generate documentation
mix docs
```

### Quality Checks

Before committing, ensure all quality checks pass:

```bash
# Run all tests
mix test

# Check code style
mix credo --strict

# Run type checker
mix dialyzer

# Verify test coverage
mix coveralls
```

### CI/CD

The project uses GitHub Actions for continuous integration. The CI pipeline:

- Tests on Elixir 1.16-1.19 and OTP 25-28
- Runs all test suites (unit, integration, property-based)
- Performs code quality checks (Credo, Dialyzer)
- Generates test coverage reports
- Validates across macOS and Ubuntu

## Testing

ExZarr includes comprehensive test coverage:

- **Unit tests** for individual modules and end-to-end workflows
- **Property-based tests** using StreamData (21 properties, 2,100+ generated test cases)
- **Python integration tests** verifying interoperability with zarr-python (14 tests)
- **v3 integration tests** verifying Zarr v3 specification compliance (23 tests)
- **Custom codec tests** verifying the codec plugin system (29 tests)
- **Custom storage tests** verifying the storage backend plugin system (20 tests)
- **Zip storage tests** verifying zip archive backend (6 tests)
- **Filter tests** verifying transformation pipeline (36 tests)
- **Total**: 466 tests + 21 properties

Key testing areas:
- Compression and decompression invariants
- Filter pipeline transformations (Delta, Quantize, Shuffle, etc.)
- Chunk index calculations for N-dimensional arrays
- Metadata round-trip serialization
- Storage backend operations (memory, filesystem, zip)
- Custom storage backend registration and usage
- Array creation and manipulation
- Edge cases and boundary conditions
- Zarr v2 specification compatibility with Python implementation
- Zarr v3 specification compliance (unified codec pipeline, new metadata format)
- v2/v3 interoperability and automatic version detection
- Custom codec registration and runtime behavior
- CRC32C checksum validation

### Python Integration Tests

ExZarr includes integration tests that verify compatibility with Python's zarr library:

```bash
# Install Python dependencies (one-time setup)
./test/support/setup_python_tests.sh

# Run integration tests
mix test test/ex_zarr_python_integration_test.exs
```

These tests verify that:
- ExZarr can read arrays created by zarr-python
- Python can read arrays created by ExZarr
- All 10 data types are compatible
- Metadata is correctly interpreted by both implementations
- Compression (zlib) works correctly across implementations

**Requirements**: Python 3.6+, zarr-python 2.x, numpy

## Documentation

### Guides

Comprehensive guides for all skill levels:

- **[Getting Started](guides/quickstart.md)** - New to ExZarr? Start here!
  - Installation and basic concepts
  - Creating and opening arrays
  - Reading and writing data
  - Choosing chunk sizes
  - Common patterns and best practices

- **[Advanced Usage](guides/performance.md)** - Deep dive into advanced features
  - Zarr v3 features (sharding, dimension names, codec pipeline)
  - Custom chunk grids (regular and irregular)
  - Cloud storage optimization (S3, GCS, Azure)
  - Performance tuning and profiling
  - Custom storage backends and codecs

- **[Migration from Python](guides/python_interop.md)** - For zarr-python users
  - API comparison and translation guide
  - Data structure differences (NumPy arrays vs nested tuples)
  - Converting between Python and Elixir
  - Interoperability examples
  - Common patterns and idioms

### Examples

Practical examples demonstrating real-world usage:

- **[Climate Data Processing](examples/climate_data.exs)** - Complete workflow for climate data
  - Multi-dimensional arrays with dimension names
  - Time-series data storage and analysis
  - Regional and temporal queries
  - Statistical computations
  - Compression and storage efficiency

- **[Sharded Cloud Storage](examples/sharded_cloud_storage.exs)** - Optimizing for S3/cloud storage
  - Comparing sharded vs non-sharded storage
  - Minimizing API calls and costs
  - Performance measurements
  - Configuration best practices
  - Cost analysis

- **[Dimension Names](examples/dimension_names.exs)** - Named dimension slicing
  - Creating arrays with semantic dimension labels
  - Intuitive slicing by name instead of index
  - Real-world examples (climate, medical imaging)
  - Validation and best practices

- **[Nx Integration](examples/nx_integration.exs)** - Numerical computing with Nx
  - Converting between Nx tensors and Zarr arrays
  - Machine learning workflows
  - Streaming large arrays
  - Performance optimization
  - Batch processing

- **[Python Interoperability](examples/python_interop_demo.exs)** - Working with Python zarr
  - Reading Python-created arrays
  - Writing arrays for Python consumption
  - Data format compatibility

- **[S3 Storage](examples/s3_storage.exs)** - Using Amazon S3 as storage backend
  - S3 configuration and authentication
  - Creating and accessing S3-backed arrays
  - Performance optimization for cloud storage

- **[Custom Codec](examples/custom_codec_example.exs)** - Creating custom codecs
  - Implementing transformation and compression codecs
  - Registering codecs at runtime
  - Codec chaining and configuration

### API Documentation

Full API documentation is available at [hexdocs.pm/ex_zarr](https://hexdocs.pm/ex_zarr).

Key modules:

- **`ExZarr`** - Main API for creating and opening arrays
- **`ExZarr.Array`** - Array operations (reading, writing, slicing)
- **`ExZarr.Group`** - Hierarchical organization of arrays
- **`ExZarr.Metadata`** - Zarr v2 metadata handling
- **`ExZarr.MetadataV3`** - Zarr v3 metadata handling
- **`ExZarr.Storage.Backend`** - Storage backend behavior
- **`ExZarr.Codecs.Codec`** - Codec behavior for custom transformations
- **`ExZarr.ChunkGrid`** - Chunk grid configuration

## Roadmap

Completed features:
- Zig NIFs for high-performance compression codecs (zstd, lz4, snappy, blosc, bzip2)
- CRC32C checksum codec (RFC 3720 compatible with Python zarr)
- Custom codec plugin system with behavior-based architecture
- Filter pipeline support (Delta, Quantize, Shuffle, FixedScaleOffset, AsType, BitRound)
- Zip archive storage backend
- Custom storage backend plugin system (for S3, databases, cloud storage, etc.)
- Zarr v3 specification support with automatic version detection
- Unified codec pipeline for v3 format
- Full backward compatibility with v2 arrays

Future improvements planned for ExZarr:

- Additional filters (PackBits, Categorize - require string/boolean dtype support)
- Concurrent chunk reading and writing
- Advanced array slicing and indexing operations
- Distributed computing integration with Broadway or GenStage
- Built-in S3 storage backend
- Streaming API for large arrays
- v3 storage transformers and sharding extension

## Contributing

Contributions are welcome. Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass with `mix test`
5. Run code quality checks with `mix credo` and `mix dialyzer`
6. Submit a pull request

## License

MIT

## Credits

Inspired by [zarr-python](https://github.com/zarr-developers/zarr-python). Implements both Zarr v2 and v3 specifications for full compatibility with the broader Zarr ecosystem.
