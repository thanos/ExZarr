# Zarr v2 Interoperability Guide

ExZarr implements the Zarr v2 specification for compatibility with other Zarr implementations, particularly Python's zarr-python library. This guide explains how to work with Zarr arrays across different languages and platforms.

## Table of Contents

- [Overview](#overview)
- [Python Integration](#python-integration)
- [Data Type Compatibility](#data-type-compatibility)
- [Compression Compatibility](#compression-compatibility)
- [Metadata Format](#metadata-format)
- [File Structure](#file-structure)
- [Examples](#examples)
- [Testing Interoperability](#testing-interoperability)
- [Troubleshooting](#troubleshooting)

## Overview

The Zarr v2 specification defines a standard format for storing chunked, compressed, N-dimensional arrays. ExZarr follows this specification to ensure arrays can be shared between:

- **Python** (zarr-python, dask, xarray)
- **Julia** (Zarr.jl)
- **JavaScript** (zarr.js)
- **Java** (N5-Zarr)
- **C++** (xtensor-zarr)
- **Rust** (zarr-rs)

This allows scientific workflows to span multiple languages while maintaining a single data format.

## Python Integration

### Creating Arrays with ExZarr for Python

```elixir
# Create an array in Elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  storage: :filesystem,
  path: "/shared/data/experiment_1"
)

:ok = ExZarr.save(array, path: "/shared/data/experiment_1")
```

```python
# Read in Python
import zarr
import numpy as np

z = zarr.open_array('/shared/data/experiment_1', mode='r')
print(z.shape)   # (1000, 1000)
print(z.dtype)   # float64
data = z[:]      # Read entire array
```

### Creating Arrays with Python for ExZarr

```python
# Create an array in Python
import zarr
import numpy as np

z = zarr.open_array(
    '/shared/data/results',
    mode='w',
    shape=(500, 500),
    chunks=(50, 50),
    dtype='int32',
    compressor=zarr.Zlib(level=5)
)

# Fill with data
z[:, :] = np.random.randint(0, 100, size=(500, 500))
```

```elixir
# Read in Elixir
{:ok, array} = ExZarr.open(path: "/shared/data/results")
IO.inspect(array.shape)      # {500, 500}
IO.inspect(array.dtype)      # :int32
IO.inspect(array.compressor) # :zlib
```

## Data Type Compatibility

ExZarr supports all standard Zarr v2 data types with full bidirectional compatibility:

| ExZarr Type | Python numpy | Bytes | Description |
|-------------|--------------|-------|-------------|
| `:int8` | `int8` | 1 | 8-bit signed integer |
| `:int16` | `int16` | 2 | 16-bit signed integer |
| `:int32` | `int32` | 4 | 32-bit signed integer |
| `:int64` | `int64` | 8 | 64-bit signed integer |
| `:uint8` | `uint8` | 1 | 8-bit unsigned integer |
| `:uint16` | `uint16` | 2 | 16-bit unsigned integer |
| `:uint32` | `uint32` | 4 | 32-bit unsigned integer |
| `:uint64` | `uint64` | 8 | 64-bit unsigned integer |
| `:float32` | `float32` | 4 | 32-bit floating point |
| `:float64` | `float64` | 8 | 64-bit floating point |

### Byte Order

Zarr uses byte order prefixes in metadata:
- `<` - Little-endian (most common)
- `>` - Big-endian
- `|` - Native/not applicable (for single-byte types)

ExZarr automatically handles all byte order formats when reading arrays.

## Compression Compatibility

### Zlib (Recommended)

The `:zlib` compressor is fully compatible across all implementations:

```elixir
# ExZarr
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int32,
  compressor: :zlib,  # Fully compatible
  storage: :filesystem,
  path: "/data/compressed"
)
```

```python
# Python
import zarr

z = zarr.open_array(
    '/data/compressed',
    mode='w',
    shape=(1000,),
    chunks=(100,),
    dtype='int32',
    compressor=zarr.Zlib(level=5)  # Compatible
)
```

### No Compression

Arrays with `:none` compressor are also fully compatible:

```elixir
# ExZarr - no compression
compressor: :none
```

```python
# Python - no compression
compressor=None
```

### Other Compressors

- **`:zstd`** and **`:lz4`** currently fall back to `:zlib` in ExZarr
- For maximum compatibility, use `:zlib` or `:none`
- Future versions will support native zstd and lz4

## Metadata Format

Zarr arrays store metadata in a `.zarray` JSON file. ExZarr follows this format exactly:

```json
{
  "zarr_format": 2,
  "shape": [1000, 1000],
  "chunks": [100, 100],
  "dtype": "<f8",
  "compressor": {
    "id": "zlib",
    "level": 5
  },
  "fill_value": 0.0,
  "order": "C",
  "filters": null
}
```

### Dtype Encoding

Data types are encoded as strings with byte order prefix and size:

| Zarr String | ExZarr Type | Description |
|-------------|-------------|-------------|
| `<i1` or `|i1` | `:int8` | 8-bit signed int |
| `<i4` | `:int32` | 32-bit signed int (little-endian) |
| `<u2` | `:uint16` | 16-bit unsigned int (little-endian) |
| `<f8` | `:float64` | 64-bit float (little-endian) |

### Compressor Encoding

Compressors are encoded as objects with codec ID:

```json
{
  "id": "zlib",
  "level": 5
}
```

For no compression: `"compressor": null`

## File Structure

Zarr arrays on disk follow a standard directory structure:

```
my_array/
├── .zarray          # Metadata JSON file
├── 0.0              # Chunk at index (0, 0)
├── 0.1              # Chunk at index (0, 1)
├── 1.0              # Chunk at index (1, 0)
└── 1.1              # Chunk at index (1, 1)
```

### Groups

Hierarchical groups use `.zgroup` files:

```
my_group/
├── .zgroup          # Group metadata
├── array1/
│   ├── .zarray
│   ├── 0.0
│   └── 0.1
└── subgroup/
    ├── .zgroup
    └── array2/
        ├── .zarray
        └── 0.0
```

### Chunk Naming

Chunks are named using dot notation:
- `0` - 1D chunk at index 0
- `0.0` - 2D chunk at index (0, 0)
- `0.0.0` - 3D chunk at index (0, 0, 0)

This is consistent across all Zarr implementations.

## Examples

### Example 1: Scientific Data Pipeline

Process data in Python, analyze in Elixir:

```python
# Python: Generate and save experimental data
import zarr
import numpy as np

# Create large dataset
z = zarr.open_array(
    '/data/experiment/raw',
    mode='w',
    shape=(10000, 10000),
    chunks=(1000, 1000),
    dtype='float32',
    compressor=zarr.Zlib(level=5)
)

# Simulate experimental data
z[:, :] = np.random.normal(loc=0, scale=1, size=(10000, 10000))
```

```elixir
# Elixir: Load and analyze
{:ok, array} = ExZarr.open(path: "/data/experiment/raw")

# Process in Elixir
IO.puts "Dataset shape: #{inspect(array.shape)}"
IO.puts "Data type: #{array.dtype}"
IO.puts "Total elements: #{ExZarr.Array.size(array)}"
IO.puts "Memory per element: #{ExZarr.Array.itemsize(array)} bytes"

# Could process chunks in parallel using Flow or Broadway
```

### Example 2: Multi-Language Workflow

```python
# Step 1: Data collection (Python)
import zarr
import numpy as np

data = zarr.open_array(
    '/shared/pipeline/step1',
    mode='w',
    shape=(5000, 100),
    chunks=(500, 100),
    dtype='int32'
)
data[:, :] = collect_sensor_data()
```

```elixir
# Step 2: Data validation (Elixir)
{:ok, input} = ExZarr.open(path: "/shared/pipeline/step1")

# Validate and create cleaned output
{:ok, output} = ExZarr.create(
  shape: input.shape,
  chunks: input.chunks,
  dtype: input.dtype,
  compressor: :zlib,
  storage: :filesystem,
  path: "/shared/pipeline/step2"
)

# Process and save validated data
:ok = ExZarr.save(output, path: "/shared/pipeline/step2")
```

```python
# Step 3: Machine learning (Python)
import zarr

cleaned = zarr.open_array('/shared/pipeline/step2', mode='r')
# Train model on cleaned data
```

### Example 3: Interactive Demo

Run the included demo script:

```bash
elixir examples/python_interop_demo.exs
```

This demonstrates:
1. Creating a 10×10 array with ExZarr
2. Reading it with zarr-python
3. Creating a 20×20 array with zarr-python
4. Reading it with ExZarr

## Testing Interoperability

### Running Integration Tests

ExZarr includes comprehensive integration tests:

```bash
# Setup Python environment (one time)
./test/support/setup_python_tests.sh

# Run integration tests
mix test test/ex_zarr_python_integration_test.exs
```

### What the Tests Verify

The integration tests ensure:

1. **Bidirectional Compatibility**
   - ExZarr → Python: Arrays created by ExZarr are readable by Python
   - Python → ExZarr: Arrays created by Python are readable by ExZarr

2. **Data Type Coverage**
   - All 10 data types tested in both directions
   - 1D, 2D, and 3D arrays
   - Various chunk sizes

3. **Metadata Correctness**
   - Shape, chunks, dtype preserved
   - Fill values maintained
   - Compressor settings retained

4. **Compression**
   - Zlib compression/decompression works across implementations
   - No compression mode compatible

### Manual Testing

Create test arrays to verify compatibility:

```elixir
# Create test array with ExZarr
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  compressor: :zlib,
  storage: :filesystem,
  path: "/tmp/test_array"
)
:ok = ExZarr.save(array, path: "/tmp/test_array")
```

```python
# Verify with Python
import zarr

z = zarr.open_array('/tmp/test_array', mode='r')
print(f"Shape: {z.shape}")
print(f"Dtype: {z.dtype}")
print(f"Chunks: {z.chunks}")
assert z.shape == (100, 100)
```

## Troubleshooting

### Common Issues

#### 1. "Cannot open array" Error

**Symptom**: Python or ExZarr cannot open an array created by the other

**Solutions**:
- Verify `.zarray` file exists
- Check file permissions
- Ensure Zarr v2 format (not v3)
- Validate JSON in `.zarray` is well-formed

#### 2. Dtype Mismatch

**Symptom**: Data appears corrupted or has wrong type

**Solutions**:
- Ensure consistent byte order (little-endian is default)
- Check dtype string in `.zarray` matches expected format
- Verify both implementations use Zarr v2 specification

#### 3. Compression Errors

**Symptom**: "Decompression failed" or "Unsupported codec"

**Solutions**:
- Use `:zlib` or `:none` for maximum compatibility
- Ensure zarr-python version is 2.x, not 3.x
- Check compressor configuration in `.zarray`

#### 4. Chunk Files Missing

**Symptom**: "Chunk not found" errors

**Solutions**:
- Verify chunk files use dot notation (e.g., `0.0`)
- Check directory permissions
- Ensure chunks were actually written
- Confirm path is correct

### Debugging Tips

1. **Inspect Metadata**
   ```bash
   cat /path/to/array/.zarray | jq
   ```

2. **List Chunk Files**
   ```bash
   ls -la /path/to/array/
   ```

3. **Verify with Python**
   ```python
   import zarr
   z = zarr.open_array('/path/to/array', mode='r')
   print(z.info)
   ```

4. **Check ExZarr Metadata**
   ```elixir
   {:ok, array} = ExZarr.open(path: "/path/to/array")
   IO.inspect(array.metadata, pretty: true)
   ```

### Reporting Issues

If you encounter compatibility issues:

1. Verify you're using Zarr v2 (not v3)
2. Check Python zarr version: `python3 -c "import zarr; print(zarr.__version__)"`
3. Run integration tests: `mix test test/ex_zarr_python_integration_test.exs`
4. Provide:
   - ExZarr version
   - Python zarr version
   - `.zarray` file contents
   - Error messages
   - Minimal reproduction steps

## Best Practices

### 1. Use Standard Compression

For maximum compatibility, use zlib:

```elixir
compressor: :zlib  # Best compatibility
```

### 2. Document Metadata

Add attributes to groups for documentation:

```python
# Python
import zarr
root = zarr.open_group('/data/experiment', mode='w')
root.attrs['description'] = 'Temperature measurements'
root.attrs['created'] = '2026-01-22'
```

### 3. Consistent Chunking

Choose chunk sizes that work well for both reading and writing:

```elixir
# Good: Balanced chunks
chunks: {100, 100}  # 10,000 elements per chunk

# Avoid: Too small (too many files)
chunks: {10, 10}    # Only 100 elements per chunk

# Avoid: Too large (memory intensive)
chunks: {10000, 10000}  # 100 million elements per chunk
```

### 4. Test Compatibility

Always test that arrays can be read by both implementations:

```bash
# Create with ExZarr
iex> {:ok, array} = ExZarr.create(...)
iex> :ok = ExZarr.save(array, path: "/test")

# Verify with Python
$ python3 -c "import zarr; z = zarr.open_array('/test', mode='r'); print(z.info)"
```

### 5. Use Zarr v2

ExZarr implements Zarr v2. Ensure Python uses v2 format:

```python
# Ensure Zarr v2
import zarr
assert zarr.__version__.startswith('2.')
```

## Resources

- [Zarr Specification v2](https://zarr.readthedocs.io/en/stable/spec/v2.html)
- [zarr-python Documentation](https://zarr.readthedocs.io/)
- [ExZarr Documentation](https://hexdocs.pm/ex_zarr/)
- [Integration Tests](test/ex_zarr_python_integration_test.exs)
- [Python Helper Script](test/support/zarr_python_helper.py)

## Summary

ExZarr provides full Zarr v2 compatibility, enabling seamless data exchange with Python and other Zarr implementations. The integration tests verify this compatibility across all data types, compression methods, and array dimensions. By following the Zarr specification and best practices, you can build multi-language scientific computing pipelines with confidence.
