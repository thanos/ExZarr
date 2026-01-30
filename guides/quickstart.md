# Quickstart

Get up and running with ExZarr in under 5 minutes. This guide shows you how to create an array, write data, read it back, and inspect metadata using the simplest possible setup.

## Prerequisites

You should have ExZarr installed. If not, see the [Installation Guide](../README.md#installation).

## Create a Store and Array

Start IEx and create a small in-memory array:

```elixir
# Start IEx with your project
iex -S mix

# Create a 100x100 array with 10x10 chunks
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  storage: :memory
)
```

What just happened:
- Created a 100×100 array (10,000 elements)
- Divided it into 10×10 chunks (100 chunks total)
- Each element is a 64-bit float (8 bytes)
- Stored in memory (no files created)

The array is ready to use immediately.

## Write Data

You can write data in two ways: using nested tuples (no dependencies) or using Nx (requires Nx library).

### Option 1: Nested Tuples (No Dependencies)

Generate data as nested tuples:

```elixir
# Generate a 10x10 block of data
data = for i <- 0..9 do
  for j <- 0..9 do
    i * 10.0 + j * 1.0
  end
  |> List.to_tuple()
end
|> List.to_tuple()

# Write to array starting at origin (0, 0)
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {10, 10}
)
```

This writes a 10×10 slice to the array. The data covers coordinates [0:10, 0:10], which fills exactly one chunk.

### Option 2: Using Nx (Optional)

If you have Nx installed:

```elixir
# Generate data with Nx
data = Nx.iota({10, 10}, type: :f64)

# Convert to nested tuples for ExZarr
tuple_data = data
  |> Nx.to_list()
  |> Enum.map(&List.to_tuple/1)
  |> List.to_tuple()

# Write to array
:ok = ExZarr.Array.set_slice(array, tuple_data,
  start: {0, 0},
  stop: {10, 10}
)
```

Both approaches produce the same result. Use nested tuples for simplicity, or Nx if you're already using it for numerical computing.

## Read Data Back and Verify

Read the data you just wrote:

```elixir
# Read the same slice back
{:ok, retrieved} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {10, 10}
)

# Verify data matches what we wrote
data == retrieved
# => true
```

The data returned is in nested tuple format:
```elixir
# Structure: outer tuple of row tuples
{{0.0, 1.0, 2.0, ..., 9.0},
 {10.0, 11.0, 12.0, ..., 19.0},
 ...
 {90.0, 91.0, 92.0, ..., 99.0}}
```

### Spot Check Values

Verify specific elements:

```elixir
# Access first element [0, 0]
elem(elem(retrieved, 0), 0)
# => 0.0

# Access element [5, 5]
elem(elem(retrieved, 5), 5)
# => 55.0

# Access element [9, 9]
elem(elem(retrieved, 9), 9)
# => 99.0
```

## Inspect Metadata

ExZarr arrays carry metadata describing their structure:

```elixir
# View array shape
array.metadata.shape
# => {100, 100}

# View chunk dimensions
array.metadata.chunks
# => {10, 10}

# View data type
array.metadata.dtype
# => :float64

# View compressor (none by default for in-memory)
array.metadata.compressor
# => :none

# View Zarr format version
array.metadata.zarr_format
# => 2
```

All metadata is human-readable and accessible as struct fields.

## Complete Example

Here's the entire workflow in one code block:

```elixir
# Create array
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  storage: :memory
)

# Generate data (10x10 block)
data = for i <- 0..9 do
  for j <- 0..9 do
    i * 10.0 + j * 1.0
  end |> List.to_tuple()
end |> List.to_tuple()

# Write data
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {10, 10}
)

# Read back
{:ok, retrieved} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {10, 10}
)

# Verify
data == retrieved
# => true

# Inspect
IO.inspect(array.metadata.shape, label: "Shape")
IO.inspect(array.metadata.dtype, label: "Dtype")
```

This example is 24 lines and takes under a minute to run.

## Working with Multiple Chunks

Write to multiple regions of the array:

```elixir
# Write to top-left chunk [0:10, 0:10]
data1 = for i <- 0..9, do: Tuple.duplicate(1.0, 10) |> Tuple.to_list() end |> List.to_tuple()
:ok = ExZarr.Array.set_slice(array, data1, start: {0, 0}, stop: {10, 10})

# Write to adjacent chunk [0:10, 10:20]
data2 = for i <- 0..9, do: Tuple.duplicate(2.0, 10) |> Tuple.to_list() end |> List.to_tuple()
:ok = ExZarr.Array.set_slice(array, data2, start: {0, 10}, stop: {10, 20})

# Read a region spanning both chunks [0:10, 0:20]
{:ok, combined} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {10, 20}
)

# combined now contains data from both chunks
```

ExZarr automatically determines which chunks are needed and reads them efficiently.

## Reading Uninitialized Regions

Regions you haven't written yet return the fill value (default is 0):

```elixir
# Read a region we haven't written to yet
{:ok, empty_region} = ExZarr.Array.get_slice(array,
  start: {50, 50},
  stop: {60, 60}
)

# All values are 0.0 (the fill value for float64)
elem(elem(empty_region, 0), 0)
# => 0.0
```

This is expected behavior. Only chunks you write are stored; unwritten chunks return the fill value without using storage space.

## Adding Compression

To enable compression, specify a compressor:

```elixir
# Create array with zlib compression
{:ok, compressed_array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  compressor: :zlib,
  storage: :memory
)

# Use exactly as before - compression is automatic
:ok = ExZarr.Array.set_slice(compressed_array, data,
  start: {0, 0},
  stop: {10, 10}
)

{:ok, retrieved} = ExZarr.Array.get_slice(compressed_array,
  start: {0, 0},
  stop: {10, 10}
)
```

Compression and decompression happen automatically. The API is identical.

## Persisting to Filesystem

To save your array to disk, use filesystem storage:

```elixir
# Create array with filesystem storage
{:ok, persistent_array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  compressor: :zlib,
  storage: :filesystem,
  path: "/tmp/my_array"
)

# Write data (automatically saved to disk)
:ok = ExZarr.Array.set_slice(persistent_array, data,
  start: {0, 0},
  stop: {10, 10}
)

# Later, open the existing array
{:ok, reopened} = ExZarr.open(path: "/tmp/my_array")

# Read the data
{:ok, retrieved} = ExZarr.Array.get_slice(reopened,
  start: {0, 0},
  stop: {10, 10}
)
```

The data persists across sessions. You can open the same array from different processes or even different machines (if on shared storage).

## Error Handling

ExZarr functions return `{:ok, result}` or `{:error, reason}` tuples:

```elixir
# Successful operation
case ExZarr.create(shape: {10, 10}, chunks: {5, 5}, dtype: :float64) do
  {:ok, array} ->
    IO.puts("Array created successfully")
  {:error, reason} ->
    IO.puts("Failed: #{inspect(reason)}")
end

# Common errors:
# {:error, :invalid_shape} - Shape dimensions invalid
# {:error, :invalid_chunks} - Chunk size doesn't divide shape
# {:error, :invalid_dtype} - Unsupported data type
# {:error, :dimension_mismatch} - Data shape doesn't match slice
```

Always pattern match on results to handle errors gracefully.

## Quick Tips

**Memory Usage:**
Each chunk is loaded entirely when accessed. A 10×10 chunk of float64 is 800 bytes. A 100×100 chunk is 80KB. Choose chunk sizes based on your access patterns and memory constraints.

**Chunk Alignment:**
Writing full chunks (e.g., [0:10, 0:10] for 10×10 chunks) is most efficient. Partial chunk writes work but may require read-modify-write cycles.

**Data Type:**
The nested tuple format may feel unfamiliar if you're coming from NumPy. This is Elixir's native representation. You can convert to/from Nx tensors when needed (see [Nx Integration Guide](nx_integration.md)).

**Compression Trade-offs:**
Compression reduces storage but adds CPU overhead. For in-memory arrays, compression may not be worth it. For disk/cloud storage, compression usually helps.

## What You've Learned

In 5 minutes, you've learned how to:
- Create an in-memory array with specified dimensions
- Write data as nested tuples
- Read data back and verify correctness
- Inspect array metadata
- Understand chunk-based storage
- Add compression and filesystem persistence

## Next Steps

Now that you have the basics:

1. **Understand Core Concepts**: Learn about chunking, codecs, and storage backends in the [Core Concepts Guide](core_concepts.md)

2. **Explore Storage Options**: Configure S3, GCS, or Azure in the [Storage Providers Guide](storage_providers.md)

3. **Optimize Performance**: Tune chunk sizes and compression for your workload in the [Performance Guide](performance.md)

4. **Use Parallel I/O**: Speed up multi-chunk operations with BEAM concurrency in the [Parallel I/O Guide](parallel_io.md)

5. **Integrate with Nx**: Learn tensor persistence patterns in the [Nx Integration Guide](nx_integration.md)

6. **Python Interoperability**: Share data with Python in the [Python Interoperability Guide](python_interop.md)

## Complete Working Session

Here's a transcript of a complete IEx session using everything from this guide:

```elixir
iex(1)> {:ok, array} = ExZarr.create(shape: {100, 100}, chunks: {10, 10}, dtype: :float64, storage: :memory)
{:ok, %ExZarr.Array{...}}

iex(2)> data = for i <- 0..9, do: (for j <- 0..9, do: i * 10.0 + j * 1.0) |> List.to_tuple() end |> List.to_tuple()
{{0.0, 1.0, 2.0, ..., 9.0}, ...}

iex(3)> :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
:ok

iex(4)> {:ok, retrieved} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10, 10})
{:ok, {{0.0, 1.0, 2.0, ..., 9.0}, ...}}

iex(5)> data == retrieved
true

iex(6)> array.metadata.shape
{100, 100}

iex(7)> elem(elem(retrieved, 5), 5)
55.0
```

Success! You now have a working ExZarr installation and understand the basic workflow.
