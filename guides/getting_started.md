# Getting Started with ExZarr

This guide will walk you through the basics of using ExZarr to work with chunked, compressed N-dimensional arrays in Elixir.

## What is Zarr?

Zarr is a format for storing chunked, compressed N-dimensional arrays. It's designed for:
- **Scientific computing**: Store large datasets that don't fit in memory
- **Cloud storage**: Efficient parallel access to array chunks
- **Data analysis**: Read and write array slices without loading everything
- **Interoperability**: Compatible with Python zarr, zarr-python, and other implementations

## Installation

Add `ex_zarr` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"}
  ]
end
```

Run `mix deps.get` to fetch the dependency.

## Basic Concepts

### Arrays

An array in ExZarr represents an N-dimensional grid of data with:
- **Shape**: Dimensions of the array, e.g., `{1000, 500}` for a 1000×500 2D array
- **Data type**: One of `:int8`, `:int16`, `:int32`, `:int64`, `:uint8`, `:uint16`, `:uint32`, `:uint64`, `:float32`, `:float64`
- **Chunks**: How the array is divided into smaller blocks for storage

### Chunks

Chunking divides arrays into smaller pieces that can be:
- Compressed independently
- Read/written in parallel
- Cached efficiently

For example, a `{1000, 1000}` array with `{100, 100}` chunks creates a 10×10 grid of 100 chunks.

### Storage Backends

ExZarr supports multiple storage backends:
- **`:memory`**: In-memory storage (fastest, non-persistent)
- **`:filesystem`**: Local filesystem (default, persistent)
- **`:ets`**: Erlang Term Storage (fast, in-memory, concurrent)
- **`:s3`**: Amazon S3 (cloud storage, scalable)
- **`:gcs`**: Google Cloud Storage
- **`:azure_blob`**: Azure Blob Storage
- **`:mnesia`**: Mnesia distributed database
- **`:mongo_gridfs`**: MongoDB GridFS

## Creating Your First Array

### In-Memory Array

The simplest way to create an array:

```elixir
# Create a 2D array in memory
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :memory
)

# The array is now ready to use
IO.inspect(array.metadata.shape)  # {1000, 1000}
```

### Persistent Array on Filesystem

Save arrays to disk for later use:

```elixir
# Create and save to filesystem
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/my_array"
)

# Array is automatically saved as you write data
```

## Writing Data

### Setting Array Slices

Write data to specific regions of the array:

```elixir
# Create some data (100x100 float matrix)
data = for i <- 0..99, j <- 0..99 do
  i * 100 + j
end
|> Enum.chunk_every(100)
|> Enum.map(&List.to_tuple/1)
|> List.to_tuple()

# Write to array starting at position (0, 0)
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {100, 100}
)
```

### Writing Full Chunks

For best performance, write complete chunks:

```elixir
# Array with 100x100 chunks
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :memory
)

# Writing a full 100x100 chunk is most efficient
chunk_data = create_100x100_data()
:ok = ExZarr.Array.set_slice(array, chunk_data,
  start: {0, 0},
  stop: {100, 100}
)
```

### Writing Multiple Slices

Build up an array piece by piece:

```elixir
# Write data in 100x100 blocks
for i <- 0..9, j <- 0..9 do
  data = generate_data_block(i, j)

  :ok = ExZarr.Array.set_slice(array, data,
    start: {i * 100, j * 100},
    stop: {(i + 1) * 100, (j + 1) * 100}
  )
end
```

## Reading Data

### Reading Array Slices

Read specific regions without loading the entire array:

```elixir
# Read a 100x100 region
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)

# data is a nested tuple: {{v00, v01, ...}, {v10, v11, ...}, ...}
```

### Reading Multiple Slices

Read non-contiguous regions:

```elixir
# Read top-left and bottom-right corners
{:ok, top_left} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)

{:ok, bottom_right} = ExZarr.Array.get_slice(array,
  start: {900, 900},
  stop: {1000, 1000}
)
```

### Loading Entire Array

For smaller arrays, load everything at once:

```elixir
# Load complete array into memory
{:ok, full_data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: array.metadata.shape  # Read entire array
)
```

## Opening Existing Arrays

### Open from Filesystem

```elixir
# Open previously created array
{:ok, array} = ExZarr.open(
  storage: :filesystem,
  path: "/tmp/my_array"
)

# Array metadata is loaded automatically
IO.inspect(array.metadata.shape)
```

### Quick Load

For convenience, load an entire array:

```elixir
# Load complete array in one step
{:ok, data} = ExZarr.load(
  storage: :filesystem,
  path: "/tmp/my_array"
)
```

## Compression

### Using Compression (Zarr v2)

Reduce storage size with compression:

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,      # Use zlib compression
  storage: :filesystem,
  path: "/tmp/compressed_array"
)
```

### Codec Pipeline (Zarr v3)

Zarr v3 uses a unified codec pipeline for transformations:

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},                              # Convert array to bytes
    %{name: "gzip", configuration: %{level: 6}}    # Compress with gzip
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/tmp/v3_compressed"
)
```

### Available Compressors

- **`:zlib`**: Standard compression (always available)
- **`:gzip`**: GNU zip compression
- **`:zstd`**: Zstandard (high compression ratio, requires native library)
- **`:lz4`**: LZ4 (very fast, requires native library)
- **`:blosc`**: Blosc meta-compressor (requires native library)

## Choosing Chunk Sizes

Chunk size affects performance. Consider:

### General Guidelines

1. **Memory usage**: Each chunk is loaded completely when accessed
2. **Compression ratio**: Larger chunks compress better
3. **I/O patterns**: Match chunk shape to typical access patterns
4. **Parallelism**: More chunks enable more parallel operations

### Examples

```elixir
# For row-wise access (reading entire rows)
# Use wide, short chunks
{:ok, array} = ExZarr.create(
  shape: {1000, 10000},
  chunks: {10, 10000},    # Full rows
  dtype: :float64
)

# For column-wise access (reading entire columns)
# Use tall, narrow chunks
{:ok, array} = ExZarr.create(
  shape: {10000, 1000},
  chunks: {10000, 10},    # Full columns
  dtype: :float64
)

# For random access (any region)
# Use square chunks
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},     # Square regions
  dtype: :float64
)

# For cloud storage (minimize API calls)
# Use larger chunks (1-10 MB each)
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},   # ~76 MB per chunk for float64
  dtype: :float64
)
```

### Chunk Size Calculation

Calculate chunk size in memory:

```elixir
# For float64: 8 bytes per element
chunk_shape = {100, 100}
elements = 100 * 100  # 10,000 elements
bytes = elements * 8   # 80,000 bytes = ~78 KB

# For int32: 4 bytes per element
chunk_shape = {200, 200}
elements = 200 * 200  # 40,000 elements
bytes = elements * 4   # 160,000 bytes = ~156 KB
```

## Working with Groups

Groups organize related arrays hierarchically:

```elixir
# Create a group
{:ok, root} = ExZarr.Group.create(
  storage: :filesystem,
  path: "/tmp/my_data"
)

# Create arrays in the group
{:ok, temperature} = ExZarr.create(
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32,
  storage: :filesystem,
  path: "/tmp/my_data/temperature"
)

{:ok, pressure} = ExZarr.create(
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32,
  storage: :filesystem,
  path: "/tmp/my_data/pressure"
)

# Groups maintain metadata and relationships
```

## Data Types

ExZarr supports standard numeric types:

```elixir
# Integer types
:int8    # -128 to 127
:int16   # -32,768 to 32,767
:int32   # -2,147,483,648 to 2,147,483,647
:int64   # -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807

# Unsigned integer types
:uint8   # 0 to 255
:uint16  # 0 to 65,535
:uint32  # 0 to 4,294,967,295
:uint64  # 0 to 18,446,744,073,709,551,615

# Floating-point types
:float32 # 32-bit floating point
:float64 # 64-bit floating point (double precision)
```

Choose the smallest type that fits your data:

```elixir
# For RGB image data (0-255)
{:ok, image} = ExZarr.create(
  shape: {1920, 1080, 3},
  chunks: {1920, 1080, 3},
  dtype: :uint8  # 1 byte per pixel channel
)

# For scientific measurements (high precision)
{:ok, measurements} = ExZarr.create(
  shape: {10000, 100},
  chunks: {1000, 100},
  dtype: :float64  # 8 bytes per measurement
)

# For count data (non-negative integers)
{:ok, counts} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :uint32  # 4 bytes per count
)
```

## Error Handling

ExZarr functions return `{:ok, result}` or `{:error, reason}`:

```elixir
case ExZarr.create(shape: {1000, 1000}, chunks: {100, 100}, dtype: :float64) do
  {:ok, array} ->
    # Success - use array
    :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

  {:error, reason} ->
    # Handle error
    IO.puts("Failed to create array: #{inspect(reason)}")
end
```

Common errors:
- **`:invalid_shape`**: Shape dimensions invalid
- **`:invalid_chunks`**: Chunk dimensions don't match shape
- **`:invalid_dtype`**: Unsupported data type
- **`:not_found`**: Array or chunk not found
- **`:dimension_mismatch`**: Data shape doesn't match slice dimensions

## Next Steps

Now that you understand the basics:

1. **Learn advanced features**: See `guides/advanced_usage.md` for:
   - Zarr v3 features (sharding, dimension names)
   - Cloud storage configuration
   - Custom chunk grids
   - Performance optimization

2. **Explore examples**: Check the `examples/` directory:
   - `climate_data.exs`: Real-world climate data workflow
   - `sharded_cloud_storage.exs`: Using sharding with S3
   - `dimension_names.exs`: Named dimension slicing
   - `nx_integration.exs`: Integration with Nx numerical library

3. **Read API documentation**: Browse the full API at https://hexdocs.pm/ex_zarr

4. **Migrate from Python**: See `guides/migration_from_python.md` if you're coming from zarr-python

## Common Patterns

### Read-Modify-Write

```elixir
# Read existing data
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})

# Modify it
modified_data = transform_data(data)

# Write back
:ok = ExZarr.Array.set_slice(array, modified_data, start: {0, 0}, stop: {100, 100})
```

### Parallel Processing

```elixir
# Process chunks in parallel using Task
chunk_indices = for i <- 0..9, j <- 0..9, do: {i, j}

tasks = Enum.map(chunk_indices, fn {i, j} ->
  Task.async(fn ->
    # Read chunk
    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {i * 100, j * 100},
      stop: {(i + 1) * 100, (j + 1) * 100}
    )

    # Process
    processed = process_chunk(data)

    # Write back
    :ok = ExZarr.Array.set_slice(array, processed,
      start: {i * 100, j * 100},
      stop: {(i + 1) * 100, (j + 1) * 100}
    )
  end)
end)

# Wait for all tasks
Task.await_many(tasks, :infinity)
```

### Progressive Array Building

```elixir
# Create array
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/progressive_array"
)

# Fill in chunks as data becomes available
Stream.interval(1000)  # Every second
|> Stream.take(100)    # 100 chunks
|> Stream.each(fn chunk_index ->
  data = fetch_data_from_source(chunk_index)

  {i, j} = divrem(chunk_index, 10)
  :ok = ExZarr.Array.set_slice(array, data,
    start: {i * 1000, j * 1000},
    stop: {(i + 1) * 1000, (j + 1) * 1000}
  )

  IO.puts("Written chunk #{chunk_index}/100")
end)
|> Stream.run()
```

## Tips and Best Practices

1. **Start with v3**: Use `zarr_version: 3` for new projects to get latest features
2. **Match chunk access**: Design chunks to match how you'll read data
3. **Test compression**: Try different compressors to find best ratio/speed
4. **Use cloud storage wisely**: Larger chunks reduce API call costs
5. **Profile before optimizing**: Measure actual performance before tuning
6. **Document metadata**: Use attributes to store array metadata
7. **Version your data**: Include version info in group/array attributes

## Getting Help

- **Documentation**: https://hexdocs.pm/ex_zarr
- **Examples**: Browse `examples/` directory
- **Issues**: https://github.com/elixir-zarr/ex_zarr/issues
- **Zarr specification**: https://zarr-specs.readthedocs.io/
