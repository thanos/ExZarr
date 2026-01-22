# ExZarr

Elixir implementation of [Zarr](https://zarr.dev): compressed, chunked, N-dimensional arrays designed for parallel computing and scientific data storage.

## Features

- **N-dimensional arrays** with support for various data types
- **Chunking** along arbitrary dimensions for optimized I/O
- **Compression** using high-performance Zig-based codecs (zlib, blosc, lz4, zstd)
- **Flexible storage** backends (memory, filesystem, eventually S3)
- **Concurrent access** with safe parallel reads/writes
- **Hierarchical groups** for organizing arrays
- **Metadata** support compatible with Zarr specification

## Installation

Add `ex_zarr` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_zarr, "~> 0.1.0"}
  ]
end
```

**Note:** This package uses [Ziggler](https://hexdocs.pm/zigler/) for Zig NIFs, which requires Zig 0.15.2+ to be installed.

## Quick Start

```elixir
# Create a new array
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd
)

# Write data
ExZarr.Array.set_slice(array, data, start: {0, 0})

# Read data
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})

# Create hierarchical groups
{:ok, group} = ExZarr.Group.create("/data")
{:ok, subarray} = ExZarr.Group.create_array(group, "measurements",
  shape: {100}, dtype: :int32)
```

## Architecture

ExZarr uses:
- **Zig NIFs via Ziggler** for high-performance compression/decompression
- **GenServer** for concurrent access coordination
- **Pluggable storage backends** for flexibility
- **Zarr v2 specification** for compatibility

## Development

```bash
# Install dependencies
mix deps.get

# Compile (including Zig NIFs)
mix compile

# Run tests
mix test

# Generate documentation
mix docs
```

## License

MIT

## Credits

Port of [zarr-python](https://github.com/zarr-developers/zarr-python) to Elixir.

