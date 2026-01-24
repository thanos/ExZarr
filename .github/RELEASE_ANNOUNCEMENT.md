# ExZarr v0.1.0 - Zarr Arrays for Elixir 🎉

We're thrilled to announce the first release of **ExZarr**, bringing chunked, compressed, N-dimensional arrays to the Elixir ecosystem with full Python interoperability!

## What is ExZarr?

ExZarr is a pure Elixir implementation of the [Zarr](https://zarr.dev) array storage format. It enables you to work with large N-dimensional arrays efficiently, with automatic chunking, compression, and lazy loading. Perfect for scientific computing, data science, machine learning, and any application dealing with large datasets.

## Highlights

### ✨ Complete Feature Set

- **Full array slicing** - Read and write rectangular regions from any dimension
- **10 data types** - All scientific computing types (int8-64, uint8-64, float32/64)
- **Compression** - Built-in zlib compression for reduced storage
- **Memory efficient** - Load only the chunks you need
- **N-dimensional** - 1D to N-D arrays with optimized implementations

### 🐍 Python Interoperability

**100% compatible with zarr-python!** Create arrays in Python and read them in Elixir, or vice versa. Verified with 14 integration tests.

```python
# Python
import zarr
z = zarr.open('data.zarr', mode='w', shape=(1000, 1000))
z[:100, :100] = data
```

```elixir
# Elixir - reads the same array!
{:ok, array} = ExZarr.open(path: "data.zarr")
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0}, stop: {100, 100})
```

### 🔒 Rock Solid

- **196 tests** with zero failures
- **21 property-based tests** for edge cases
- **35 validation tests** preventing errors
- **Passes Credo strict mode** for code quality

### 📚 Well Documented

- Comprehensive guides and examples
- [INTEROPERABILITY.md](INTEROPERABILITY.md) for Python integration
- Interactive demo script
- Complete API documentation

## Quick Example

```elixir
# Create a 10GB array (only metadata in memory!)
{:ok, array} = ExZarr.create(
  shape: {10_000, 10_000, 10_000},
  chunks: {100, 100, 100},
  dtype: :float64,
  compressor: :zlib,
  storage: :filesystem,
  path: "/data/huge_array"
)

# Write to a small region (loads only needed chunks)
data = generate_data(100, 100, 100)
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0, 0},
  stop: {100, 100, 100}
)

# Read a different region
{:ok, subset} = ExZarr.Array.get_slice(array,
  start: {500, 500, 500},
  stop: {600, 600, 600}
)
```

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_zarr, "~> 0.1.0"}
  ]
end
```

## Use Cases

Perfect for:
- 📊 **Data Science** - ETL pipelines with large datasets
- 🔬 **Scientific Computing** - Numerical simulations and analysis
- 🧠 **Machine Learning** - Training data management
- 🌍 **Geospatial** - Satellite imagery and climate data
- 🏥 **Medical Imaging** - 3D/4D medical scans
- 📹 **Video Processing** - Frame-by-frame analysis

## What's Next?

Planned for v0.2.0:
- Additional compression codecs (native zstd, lz4)
- S3 storage backend
- Parallel chunk operations
- Performance optimizations

## Get Started

- 📖 [Read the Documentation](https://hexdocs.pm/ex_zarr)
- 🚀 [Try the Quick Start](https://github.com/your-username/ex_zarr#quick-start)
- 🐍 [Python Interoperability Guide](https://github.com/your-username/ex_zarr/blob/main/INTEROPERABILITY.md)
- 💬 [Open an Issue](https://github.com/your-username/ex_zarr/issues)

## Acknowledgments

Built with inspiration from:
- The Zarr specification and community
- zarr-python reference implementation
- The Elixir community

## Full Release Notes

See [RELEASE_NOTES.md](RELEASE_NOTES.md) for complete details.

---

We're excited to see what you build with ExZarr! 🚀

Star ⭐ the repo if you find it useful!
