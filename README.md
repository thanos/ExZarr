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

## Supported Data Types

ExZarr supports the following data types:

- **Integers**: `:int8`, `:int16`, `:int32`, `:int64`
- **Unsigned integers**: `:uint8`, `:uint16`, `:uint32`, `:uint64`
- **Floating point**: `:float32`, `:float64`

All data types use little-endian byte order by default, consistent with the Zarr specification.

## Compression Codecs

ExZarr provides the following compression options:

- **`:none`** - No compression (fastest, largest size)
- **`:zlib`** - Standard zlib compression (good balance of speed and compression)
- **`:zstd`** - Zstandard compression (currently falls back to zlib)
- **`:lz4`** - LZ4 compression (currently falls back to zlib)

The `:zlib` codec uses Erlang's built-in `:zlib` module for maximum reliability and compatibility.

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

- **Unit tests** for individual modules and end-to-end workflows (128 tests)
- **Property-based tests** using StreamData (21 properties, 2,100+ generated test cases)
- **Python integration tests** verifying interoperability with zarr-python (14 tests)
- **Total**: 142 tests + 21 properties
- **Test coverage**: 72.5%

Key testing areas:
- Compression and decompression invariants
- Chunk index calculations for N-dimensional arrays
- Metadata round-trip serialization
- Storage backend operations
- Array creation and manipulation
- Edge cases and boundary conditions
- Zarr v2 specification compatibility with Python implementation

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

Future improvements planned for ExZarr:

- Native ZSTD and LZ4 compression implementations
- Zig NIFs for high-performance compression codecs
- S3 and cloud storage backends
- Zarr v3 specification support
- Concurrent chunk reading and writing
- Array slicing and indexing operations
- Filter pipeline support
- Blosc meta-compressor support
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
