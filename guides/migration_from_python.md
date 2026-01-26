# Migration Guide: From Python zarr to ExZarr

This guide helps Python zarr users transition to ExZarr, highlighting key differences and providing translation examples.

## Table of Contents

1. [Quick Comparison](#quick-comparison)
2. [Installation](#installation)
3. [Creating Arrays](#creating-arrays)
4. [Reading and Writing Data](#reading-and-writing-data)
5. [Storage Backends](#storage-backends)
6. [Compression and Filters](#compression-and-filters)
7. [Groups](#groups)
8. [API Differences](#api-differences)
9. [Common Patterns](#common-patterns)
10. [Interoperability](#interoperability)

## Quick Comparison

| Feature | Python zarr | ExZarr |
|---------|-------------|--------|
| Language | Python | Elixir |
| Data structures | NumPy arrays | Nested tuples |
| Error handling | Exceptions | `{:ok, result}` / `{:error, reason}` |
| Parallelism | Threading/multiprocessing | Lightweight processes (BEAM) |
| Storage backends | Dict, filesystem, S3, etc. | Memory, filesystem, ETS, S3, GCS, Azure, etc. |
| Zarr versions | v2 and v3 | v2 and v3 |

## Installation

**Python:**
```bash
pip install zarr
```

**Elixir:**
```elixir
# In mix.exs
def deps do
  [
    {:ex_zarr, "~> 1.0"}
  ]
end
```

```bash
mix deps.get
```

## Creating Arrays

### Basic Array Creation

**Python:**
```python
import zarr
import numpy as np

# Create array
z = zarr.zeros((1000, 1000), chunks=(100, 100), dtype='f8')

# Or with explicit storage
store = zarr.DirectoryStore('/tmp/my_array')
z = zarr.zeros((1000, 1000), chunks=(100, 100), dtype='f8', store=store)
```

**Elixir:**
```elixir
# Create array in memory
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :memory
)

# Or with explicit filesystem storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/my_array"
)
```

### Array with Compression

**Python:**
```python
from numcodecs import Blosc

z = zarr.zeros(
    (1000, 1000),
    chunks=(100, 100),
    dtype='f8',
    compressor=Blosc(cname='zstd', clevel=3)
)
```

**Elixir (Zarr v2):**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd,  # or :zlib, :lz4, :blosc
  compression_level: 3
)
```

**Elixir (Zarr v3 - recommended):**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},
    %{name: "zstd", configuration: %{level: 3}}
  ],
  zarr_version: 3
)
```

## Reading and Writing Data

### Data Structure Differences

**Python uses NumPy arrays:**
```python
# NumPy array
data = np.arange(10000).reshape(100, 100)
print(data[0, 0])  # Access element: 0
print(type(data))   # <class 'numpy.ndarray'>
```

**Elixir uses nested tuples:**
```elixir
# Nested tuples (rows of columns)
data = for i <- 0..99 do
  for j <- 0..99 do
    i * 100 + j
  end |> List.to_tuple()
end |> List.to_tuple()

# Access: elem(elem(data, 0), 0) == 0
```

### Writing Data

**Python:**
```python
import numpy as np

# Write slice
data = np.arange(10000).reshape(100, 100)
z[0:100, 0:100] = data

# Write entire array
z[:] = np.random.rand(1000, 1000)
```

**Elixir:**
```elixir
# Write slice
data = generate_data(100, 100)  # Returns nested tuples
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {100, 100}
)

# Write entire array
full_data = generate_data(1000, 1000)
:ok = ExZarr.Array.set_slice(array, full_data,
  start: {0, 0},
  stop: {1000, 1000}
)
```

### Reading Data

**Python:**
```python
# Read slice
data = z[0:100, 0:100]

# Read entire array
full_data = z[:]

# Read single element
value = z[50, 50]
```

**Elixir:**
```elixir
# Read slice
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)

# Read entire array
{:ok, full_data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: array.metadata.shape
)

# Read single element (read containing chunk)
{:ok, chunk} = ExZarr.Array.get_slice(array,
  start: {50, 50},
  stop: {51, 51}
)
value = elem(elem(chunk, 0), 0)
```

## Storage Backends

### Filesystem Storage

**Python:**
```python
# Directory store
store = zarr.DirectoryStore('/tmp/my_array')
z = zarr.open(store, mode='w', shape=(1000, 1000), chunks=(100, 100))

# Or using convenience function
z = zarr.open('/tmp/my_array', mode='w', shape=(1000, 1000), chunks=(100, 100))
```

**Elixir:**
```elixir
# Filesystem storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/my_array"
)

# Or open existing
{:ok, array} = ExZarr.open(
  storage: :filesystem,
  path: "/tmp/my_array"
)
```

### Cloud Storage (S3)

**Python:**
```python
import s3fs

# S3 store
s3 = s3fs.S3FileSystem()
store = s3fs.S3Map(root='my-bucket/path/to/array', s3=s3)
z = zarr.open(store, mode='w', shape=(1000, 1000), chunks=(100, 100))
```

**Elixir:**
```elixir
# S3 storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :s3,
  bucket: "my-bucket",
  prefix: "path/to/array"
)
```

### In-Memory Storage

**Python:**
```python
# Memory store (dict-like)
store = {}
z = zarr.open(store, mode='w', shape=(1000, 1000), chunks=(100, 100))
```

**Elixir:**
```elixir
# Memory storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :memory
)
```

## Compression and Filters

### Zarr v2 Style

**Python:**
```python
from numcodecs import Blosc, Delta

z = zarr.array(
    np.arange(1000),
    chunks=100,
    compressor=Blosc(cname='zstd', clevel=5),
    filters=[Delta(dtype='i8')]
)
```

**Elixir:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  compressor: :zstd,
  compression_level: 5,
  filters: [:delta],
  zarr_version: 2
)
```

### Zarr v3 Style (Codec Pipeline)

**Python:**
```python
import zarr
from zarr.codecs import BytesCodec, GzipCodec, TransposeCodec

z = zarr.create(
    shape=(1000, 1000),
    chunks=(100, 100),
    dtype='f8',
    codecs=[
        TransposeCodec(order=(1, 0)),
        BytesCodec(),
        GzipCodec(level=6)
    ],
    zarr_format=3
)
```

**Elixir:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "transpose", configuration: %{order: [1, 0]}},
    %{name: "bytes"},
    %{name: "gzip", configuration: %{level: 6}}
  ],
  zarr_version: 3
)
```

## Groups

### Creating Groups

**Python:**
```python
# Create group
root = zarr.group(store='/tmp/my_group')

# Add arrays to group
root.create_dataset('array1', shape=(1000, 1000), chunks=(100, 100))
root.create_dataset('array2', shape=(500, 500), chunks=(50, 50))

# Access arrays
z1 = root['array1']
z2 = root['array2']
```

**Elixir:**
```elixir
# Create group
{:ok, root} = ExZarr.Group.create(
  storage: :filesystem,
  path: "/tmp/my_group"
)

# Create arrays in group (by path)
{:ok, array1} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/my_group/array1"
)

{:ok, array2} = ExZarr.create(
  shape: {500, 500},
  chunks: {50, 50},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/my_group/array2"
)
```

### Nested Groups

**Python:**
```python
root = zarr.group()
sub1 = root.create_group('sub1')
sub2 = sub1.create_group('sub2')
sub2.create_dataset('data', shape=(100, 100))
```

**Elixir:**
```elixir
# Create nested directory structure
{:ok, root} = ExZarr.Group.create(
  storage: :filesystem,
  path: "/tmp/root"
)

# Create nested arrays via paths
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/root/sub1/sub2/data"
)
```

## API Differences

### Error Handling

**Python (exceptions):**
```python
try:
    z = zarr.open('/tmp/nonexistent')
except Exception as e:
    print(f"Error: {e}")
```

**Elixir (result tuples):**
```elixir
case ExZarr.open(path: "/tmp/nonexistent") do
  {:ok, array} ->
    # Success - use array
    IO.puts("Opened array")

  {:error, reason} ->
    # Handle error
    IO.puts("Error: #{inspect(reason)}")
end
```

### Array Information

**Python:**
```python
print(z.shape)       # (1000, 1000)
print(z.chunks)      # (100, 100)
print(z.dtype)       # dtype('float64')
print(z.nbytes)      # 8000000
print(z.nchunks)     # 100
```

**Elixir:**
```elixir
IO.inspect(array.metadata.shape)        # {1000, 1000}
IO.inspect(array.metadata.chunks)       # {100, 100}
IO.inspect(array.metadata.dtype)        # :float64
IO.inspect(array.metadata.zarr_format)  # 3

# Calculate derived values
{rows, cols} = array.metadata.shape
bytes = rows * cols * 8  # 8000000
```

### Attributes

**Python:**
```python
z.attrs['description'] = 'My array'
z.attrs['created'] = '2024-01-01'

print(z.attrs['description'])  # 'My array'
```

**Elixir:**
```elixir
# Attributes in v3 metadata
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  attributes: %{
    "description" => "My array",
    "created" => "2024-01-01"
  },
  zarr_version: 3
)

# Access attributes
description = array.metadata.attributes["description"]
```

## Common Patterns

### Parallel Processing

**Python:**
```python
from multiprocessing import Pool

def process_chunk(i):
    data = z[i*100:(i+1)*100, :]
    result = expensive_computation(data)
    z_out[i*100:(i+1)*100, :] = result
    return i

with Pool(8) as pool:
    pool.map(process_chunk, range(10))
```

**Elixir:**
```elixir
# Use Task for parallel processing
tasks = for i <- 0..9 do
  Task.async(fn ->
    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {i * 100, 0},
      stop: {(i + 1) * 100, 1000}
    )

    result = expensive_computation(data)

    :ok = ExZarr.Array.set_slice(output_array, result,
      start: {i * 100, 0},
      stop: {(i + 1) * 100, 1000}
    )

    i
  end)
end

Task.await_many(tasks, :infinity)
```

### Iterating Over Chunks

**Python:**
```python
for i in range(0, z.shape[0], z.chunks[0]):
    for j in range(0, z.shape[1], z.chunks[1]):
        chunk = z[i:i+z.chunks[0], j:j+z.chunks[1]]
        process(chunk)
```

**Elixir:**
```elixir
{rows, cols} = array.metadata.shape
{chunk_rows, chunk_cols} = array.metadata.chunks

for i <- 0..div(rows, chunk_rows)-1,
    j <- 0..div(cols, chunk_cols)-1 do

  {:ok, chunk} = ExZarr.Array.get_slice(array,
    start: {i * chunk_rows, j * chunk_cols},
    stop: {(i + 1) * chunk_rows, (j + 1) * chunk_cols}
  )

  process(chunk)
end
```

### Appending Data

**Python:**
```python
# Resize and append
new_shape = (z.shape[0] + 100, z.shape[1])
z.resize(new_shape)
z[-100:, :] = new_data
```

**Elixir:**
```elixir
# ExZarr arrays are fixed size - create new array if needed
{old_rows, cols} = array.metadata.shape

{:ok, new_array} = ExZarr.create(
  shape: {old_rows + 100, cols},
  chunks: array.metadata.chunks,
  dtype: array.metadata.dtype,
  storage: :filesystem,
  path: "/tmp/expanded_array"
)

# Copy existing data
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {old_rows, cols}
)

:ok = ExZarr.Array.set_slice(new_array, data,
  start: {0, 0},
  stop: {old_rows, cols}
)

# Append new data
:ok = ExZarr.Array.set_slice(new_array, new_data,
  start: {old_rows, 0},
  stop: {old_rows + 100, cols}
)
```

## Interoperability

### Reading Python-created Arrays

ExZarr can read arrays created by Python zarr:

**Python (create):**
```python
import zarr
import numpy as np

z = zarr.open('/tmp/python_array', mode='w', shape=(100, 100), chunks=(10, 10))
z[:] = np.random.rand(100, 100)
```

**Elixir (read):**
```elixir
# Open and read Python-created array
{:ok, array} = ExZarr.open(
  storage: :filesystem,
  path: "/tmp/python_array"
)

{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)
```

### Writing for Python Consumption

ExZarr arrays can be read by Python:

**Elixir (create):**
```elixir
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  storage: :filesystem,
  path: "/tmp/elixir_array"
)

data = generate_data(100, 100)
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {100, 100}
)
```

**Python (read):**
```python
import zarr

z = zarr.open('/tmp/elixir_array', mode='r')
data = z[:]
print(data.shape)  # (100, 100)
```

### Data Format Compatibility

**Compatible formats:**
- Zarr v2 and v3 specifications
- Standard compressors (zlib, gzip)
- Common data types (int8-64, uint8-64, float32/64)
- Filesystem, S3, GCS storage

**Potential incompatibilities:**
- Custom Python compressors (must use standard ones)
- NumPy structured dtypes (not yet supported in ExZarr)
- Fortran order (ExZarr uses C order)

### Ensuring Compatibility

**Use standard features:**
```elixir
# Maximum compatibility configuration
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,        # Standard compressor
  zarr_version: 2,          # Widely supported
  storage: :filesystem,
  path: "/tmp/compatible_array"
)
```

## Data Conversion Helpers

### Converting Between Python and Elixir Data

**Python list to Elixir tuple:**
```python
# Python
data = [[1, 2, 3], [4, 5, 6]]

# Save as JSON for transfer
import json
with open('/tmp/data.json', 'w') as f:
    json.dump(data, f)
```

```elixir
# Elixir - read and convert
{:ok, json} = File.read("/tmp/data.json")
{:ok, list} = Jason.decode(json)

# Convert to nested tuples
data = list
|> Enum.map(&List.to_tuple/1)
|> List.to_tuple()
```

### Nx Integration (NumPy Alternative)

```elixir
# Use Nx for numerical computing (similar to NumPy)
tensor = Nx.iota({100, 100})  # Like np.arange(10000).reshape(100, 100)

# Convert Nx tensor to nested tuples for ExZarr
data = tensor
|> Nx.to_list()
|> Enum.map(&List.to_tuple/1)
|> List.to_tuple()

:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {100, 100}
)

# Read from ExZarr to Nx tensor
{:ok, tuple_data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)

list_data = tuple_data
|> Tuple.to_list()
|> Enum.map(&Tuple.to_list/1)

tensor = Nx.tensor(list_data)
```

## Key Takeaways

1. **Error handling**: Use pattern matching on `{:ok, result}` / `{:error, reason}` instead of try/catch
2. **Data structures**: Nested tuples replace NumPy arrays
3. **Concurrency**: BEAM processes instead of threads/multiprocessing
4. **API style**: Explicit function calls vs. object methods
5. **Interoperability**: Full compatibility with Python zarr for standard features

## Next Steps

- Read [Getting Started Guide](getting_started.md) for ExZarr basics
- Explore [Advanced Usage](advanced_usage.md) for Elixir-specific patterns
- See [examples/nx_integration.exs](../examples/nx_integration.exs) for Nx + ExZarr patterns
- Check [Python interop example](../examples/python_interop_demo.exs)
