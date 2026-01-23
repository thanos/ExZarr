# ExZarr

Elixir implementation of [Zarr](https://zarr.dev): compressed, chunked, N-dimensional arrays designed for parallel computing and scientific data storage.

## Features

- **N-dimensional arrays** with support for 10 data types (int8-64, uint8-64, float32/64)
- **Chunking** along arbitrary dimensions for optimized I/O operations
- **Compression** using Erlang zlib (with fallback support for zstd and lz4)
- **Flexible storage** backends (in-memory and filesystem)
- **Hierarchical groups** for organizing multiple arrays
- **Zarr v2 specification** compatibility for interoperability with other Zarr implementations
- **Property-based testing** with comprehensive test coverage (72.5%)

## Installation

Add `ex_zarr` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_zarr, "~> 0.1.0"}
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

ExZarr supports two storage backends:

- **`:memory`** - In-memory storage for temporary arrays (non-persistent)
- **`:filesystem`** - Local filesystem storage using Zarr v2 directory structure

Arrays stored on the filesystem use the standard Zarr format:
- Metadata stored in `.zarray` JSON files
- Chunks stored as separate files with dot notation (e.g., `0.0`, `0.1`)
- Groups marked with `.zgroup` JSON files

## Architecture

ExZarr uses:
- **Erlang :zlib** for compression and decompression
- **GenServer** for array state management
- **Pluggable storage backends** for memory and filesystem storage
- **Zarr v2 specification** for interoperability with Python, Julia, and other Zarr implementations

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

- **Unit tests** for individual modules and end-to-end workflows (209 tests)
- **Property-based tests** using StreamData (21 properties, 2,100+ generated test cases)
- **Python integration tests** verifying interoperability with zarr-python (14 tests)
- **Custom codec tests** verifying the plugin system (29 tests)
- **Total**: 238 tests + 21 properties
- **Test coverage**: 72.5%

Key testing areas:
- Compression and decompression invariants
- Chunk index calculations for N-dimensional arrays
- Metadata round-trip serialization
- Storage backend operations
- Array creation and manipulation
- Edge cases and boundary conditions
- Zarr v2 specification compatibility with Python implementation
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

## Roadmap

Completed features:
- ✅ Zig NIFs for high-performance compression codecs (zstd, lz4, snappy, blosc, bzip2)
- ✅ CRC32C checksum codec (RFC 3720 compatible with Python zarr)
- ✅ Custom codec plugin system with behavior-based architecture

Future improvements planned for ExZarr:

- S3 and cloud storage backends
- Zarr v3 specification support
- Concurrent chunk reading and writing
- Array slicing and indexing operations
- Filter pipeline support
- Distributed computing integration with Broadway or GenStage

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

Inspired by [zarr-python](https://github.com/zarr-developers/zarr-python). Implements the Zarr v2 specification for compatibility with the broader Zarr ecosystem.
