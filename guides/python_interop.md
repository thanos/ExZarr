# Python Interoperability

ExZarr implements the Zarr specification to enable reliable cross-language collaboration between Elixir and Python. This guide shows how to read and write arrays across languages, maps data types, and identifies compatibility boundaries.

## Overview and Use Cases

### Why Cross-Language Compatibility Matters

Scientific and data engineering workflows increasingly span multiple languages:

- **Python ecosystem:** NumPy, Pandas, Xarray, scikit-learn for analysis and ML
- **Elixir/BEAM:** Distributed data pipelines, web services, fault-tolerant systems
- **Shared storage format:** Enables specialization without vendor lock-in

Zarr provides the interoperability layer. ExZarr and zarr-python both implement the same specification, ensuring arrays can be exchanged reliably.

### Common Interoperability Patterns

**1. Python Producer, Elixir Consumer**

ML training in Python, inference service in Elixir:

```
Python (scikit-learn) → Train model → Export weights to Zarr
  ↓
Elixir (Phoenix) → Load weights → Serve predictions via HTTP
```

**Use case:** Training happens offline in Python (rich ML ecosystem), production inference runs in Elixir (high concurrency, low latency).

**2. Elixir Producer, Python Consumer**

Data pipeline in Elixir, analysis in Python:

```
Elixir (Broadway) → Process stream → Write results to Zarr
  ↓
Python (Pandas/Jupyter) → Load results → Analyze and visualize
```

**Use case:** Real-time ingestion in Elixir (distributed, fault-tolerant), exploratory analysis in Python (interactive, visualization-rich).

**3. Bidirectional Collaboration**

Incremental processing across languages:

```
Python → Initial processing → Zarr
  ↓
Elixir → Additional processing → Update Zarr
  ↓
Python → Final analysis → Results
```

**Use case:** Collaborative workflows where each language handles steps best suited to its strengths.

**4. Archive Interchange**

Share datasets between teams using different stacks:

```
Team A (Python) → Publish dataset as Zarr archive
  ↓
Team B (Elixir) → Consume dataset for production workload
```

**Use case:** Cross-team collaboration without forcing tool standardization.

### Zarr Specification Compliance

**How interoperability works:**

- **Zarr specification:** Defines file format, metadata structure, compression
- **zarr-python:** Reference implementation (Python)
- **ExZarr:** Full implementation (Elixir)
- **Specification compliance:** Ensures compatibility

ExZarr implements:
- **Zarr v2:** Full compliance (stable, widely supported)
- **Zarr v3:** Full compliance, production-ready (modern features, works with zarr-python 3.x)

When both sides follow the spec, arrays are interchangeable.

## Reading Python Arrays from Elixir

### Complete Example: Python to Elixir

**Step 1: Create array in Python**

```python
# create_array.py
import zarr
import numpy as np

# Create array with zarr-python
z = zarr.open_array(
    '/shared/data/measurements',
    mode='w',
    shape=(1000, 500),
    chunks=(100, 50),
    dtype='float64',
    compressor=zarr.Blosc(cname='zstd', clevel=3)
)

# Fill with random data
z[:, :] = np.random.randn(1000, 500)

# Add metadata for consumers
z.attrs['units'] = 'meters'
z.attrs['description'] = 'Sensor measurements'
z.attrs['created_by'] = 'Python zarr-python 2.16.0'

print(f"Created array: shape={z.shape}, dtype={z.dtype}")
print(f"Chunks: {z.chunks}")
print(f"Compressor: {z.compressor}")
```

Run the Python script:
```bash
$ python create_array.py
Created array: shape=(1000, 500), dtype=float64
Chunks: (100, 50)
Compressor: Blosc(cname='zstd', clevel=3, shuffle=SHUFFLE, blocksize=0)
```

**Step 2: Read array in Elixir**

```elixir
# read_array.exs

# Open array created by Python
{:ok, array} = ExZarr.open(
  storage: :filesystem,
  path: "/shared/data/measurements"
)

# Inspect metadata (automatically detected from Python format)
IO.puts("Shape: #{inspect(array.metadata.shape)}")
IO.puts("Dtype: #{inspect(array.metadata.dtype)}")
IO.puts("Chunks: #{inspect(array.metadata.chunks)}")
IO.puts("Compressor: #{inspect(array.metadata.compressor)}")

# Read attributes created by Python
IO.puts("\nAttributes:")
IO.puts("  Units: #{array.metadata.attributes["units"]}")
IO.puts("  Description: #{array.metadata.attributes["description"]}")
IO.puts("  Created by: #{array.metadata.attributes["created_by"]}")

# Read a slice of data
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 50}
)

# Data is nested tuples (Elixir native format)
IO.puts("\nRead slice [0:100, 0:50]")
IO.puts("First value: #{elem(elem(data, 0), 0)}")
IO.puts("Data structure: nested tuples")

# Optionally convert to Nx tensor for numerical operations
tensor = data
  |> Tuple.to_list()
  |> Enum.map(&Tuple.to_list/1)
  |> Nx.tensor()

IO.puts("Converted to Nx tensor: #{inspect(Nx.shape(tensor))}")
```

Run the Elixir script:
```bash
$ elixir read_array.exs
Shape: {1000, 500}
Dtype: :float64
Chunks: {100, 50}
Compressor: :blosc

Attributes:
  Units: meters
  Description: Sensor measurements
  Created by: Python zarr-python 2.16.0

Read slice [0:100, 0:50]
First value: -0.4532891
Data structure: nested tuples
Converted to Nx tensor: {100, 50}
```

### Key Considerations

**Automatic format detection:**
ExZarr automatically detects Zarr v2 or v3 format by inspecting metadata files (`.zarray` for v2, `zarr.json` for v3).

**Dtype mapping:**
Python dtype `float64` automatically maps to ExZarr `:float64`. See [Data Type Compatibility Matrix](#data-type-compatibility-matrix) for full mapping.

**Compressor compatibility:**
If Blosc (or another optional codec) is not available in ExZarr, the read will fail. Use `ExZarr.Codecs.codec_available?(:blosc)` to check. See [Compression Codec Compatibility](#compression-codec-compatibility).

**Data structure differences:**
- Python: NumPy `ndarray` (C-contiguous memory)
- Elixir: Nested tuples (immutable, BEAM-native)
- Conversion: Use Nx for numerical operations

## Writing Elixir Arrays for Python

### Complete Example: Elixir to Python

**Step 1: Create array in Elixir**

```elixir
# create_array.exs

# Create array for Python consumption
{:ok, array} = ExZarr.create(
  shape: {500, 500},
  chunks: {50, 50},
  dtype: :int32,
  compressor: :zlib,  # Universally supported
  storage: :filesystem,
  path: "/shared/data/results",
  zarr_version: 2  # Use v2 for maximum compatibility
)

# Generate data (nested tuples)
data = for i <- 0..499 do
  for j <- 0..499 do
    i * 500 + j
  end
  |> List.to_tuple()
end
|> List.to_tuple()

# Write data
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {500, 500}
)

# Add attributes for Python users
# (Provides context for consumers)
:ok = ExZarr.Array.put_attributes(array, %{
  "units" => "counts",
  "description" => "Processing results from Elixir pipeline",
  "created_by" => "ExZarr v1.0.0",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
})

IO.puts("Created array for Python consumption")
IO.puts("Path: /shared/data/results")
IO.puts("Format: Zarr v2 (compatible with zarr-python 2.x)")
IO.puts("Compressor: zlib (universally supported)")
```

Run the Elixir script:
```bash
$ elixir create_array.exs
Created array for Python consumption
Path: /shared/data/results
Format: Zarr v2 (compatible with zarr-python 2.x)
Compressor: zlib (universally supported)
```

**Step 2: Read array in Python**

```python
# read_array.py
import zarr
import numpy as np

# Read array created by Elixir
z = zarr.open_array('/shared/data/results', mode='r')

print(f"Shape: {z.shape}")
print(f"Dtype: {z.dtype}")
print(f"Chunks: {z.chunks}")
print(f"Compressor: {z.compressor}")

# Read attributes written by Elixir
print("\nAttributes:")
for key, value in z.attrs.items():
    print(f"  {key}: {value}")

# Read data (returns NumPy array)
data = z[:]
print(f"\nData type: {type(data)}")
print(f"First value: {data[0, 0]}")
print(f"Last value: {data[499, 499]}")

# Verify data integrity
expected_first = 0 * 500 + 0  # i * 500 + j
expected_last = 499 * 500 + 499
assert data[0, 0] == expected_first
assert data[499, 499] == expected_last
print("\nData integrity verified!")
```

Run the Python script:
```bash
$ python read_array.py
Shape: (500, 500)
Dtype: int32
Chunks: (50, 50)
Compressor: Zlib(level=6)

Attributes:
  units: counts
  description: Processing results from Elixir pipeline
  created_by: ExZarr v1.0.0
  timestamp: 2026-01-29T10:30:00Z

Data type: <class 'numpy.ndarray'>
First value: 0
Last value: 249999

Data integrity verified!
```

### Best Practices for Python Compatibility

**1. Choose appropriate Zarr version**
```elixir
# For modern Python tools (zarr-python 3.x)
zarr_version: 3  # Recommended for new projects

# For legacy compatibility (zarr-python 2.x)
zarr_version: 2  # Maximum compatibility with older tools
```

Both Zarr v2 and v3 are production-ready in ExZarr. Use v3 for new projects with modern Python tools, or v2 for compatibility with older zarr-python 2.x installations.

**2. Use standard compressors**
```elixir
compressor: :zlib  # Always available
# OR
compressor: :zstd  # Widely available, better compression
```

Avoid custom codecs unless coordinated with Python consumers.

**3. Use common dtypes**
```elixir
dtype: :int32      # Standard 32-bit integer
dtype: :float64    # Standard 64-bit float
```

Avoid exotic types. See [Data Type Compatibility Matrix](#data-type-compatibility-matrix).

**4. Include descriptive attributes**
```elixir
ExZarr.Array.put_attributes(array, %{
  "units" => "meters",
  "description" => "Clear description of data",
  "schema_version" => "1.0"
})
```

Attributes help Python users understand the data without reading source code.

**5. Test with zarr-python before deploying**
```bash
# After creating array in Elixir
$ python -c "import zarr; z = zarr.open('/path/to/array'); print(z.shape)"
```

Verify Python can read the array before committing to format.

## Data Type Compatibility Matrix

ExZarr supports 10 standard numeric dtypes with full bidirectional compatibility:

| ExZarr Atom | Python NumPy | Zarr v2 String | Zarr v3 Name | Bytes | Interoperable |
|-------------|--------------|----------------|--------------|-------|---------------|
| `:int8`     | `int8`       | `\|i1`, `<i1`  | `int8`       | 1     | ✓ Yes         |
| `:int16`    | `int16`      | `<i2`          | `int16`      | 2     | ✓ Yes         |
| `:int32`    | `int32`      | `<i4`          | `int32`      | 4     | ✓ Yes         |
| `:int64`    | `int64`      | `<i8`          | `int64`      | 8     | ✓ Yes         |
| `:uint8`    | `uint8`      | `\|u1`, `<u1`  | `uint8`      | 1     | ✓ Yes         |
| `:uint16`   | `uint16`     | `<u2`          | `uint16`     | 2     | ✓ Yes         |
| `:uint32`   | `uint32`     | `<u4`          | `uint32`     | 4     | ✓ Yes         |
| `:uint64`   | `uint64`     | `<u8`          | `uint64`     | 8     | ✓ Yes         |
| `:float32`  | `float32`    | `<f4`          | `float32`    | 4     | ✓ Yes         |
| `:float64`  | `float64`    | `<f8`          | `float64`    | 8     | ✓ Yes         |

### Byte Order

Zarr v2 uses byte order prefixes:
- `<` - Little-endian (default, most common)
- `>` - Big-endian
- `|` - Native/not applicable (for single-byte types like int8, uint8)

ExZarr automatically handles all byte orders when reading. When writing, ExZarr defaults to little-endian (matching NumPy default).

### Unsupported Python Types

ExZarr does **not** support:

| Python Type | Description | Status | Workaround |
|-------------|-------------|--------|------------|
| `bool` | Boolean (True/False) | Not supported | Use `uint8` with 0/1 values |
| `complex64` | 64-bit complex number | Not supported | Store real/imaginary in separate arrays |
| `complex128` | 128-bit complex number | Not supported | Store real/imaginary in separate arrays |
| `datetime64` | Temporal data | Not supported | Store as int64 Unix timestamps |
| `timedelta64` | Time duration | Not supported | Store as int64 (e.g., microseconds) |
| `object` | Variable-length strings | Not supported | Store as attributes or external file |
| `str`, `unicode` | Text data | Not supported | Use attributes or external format |
| Structured dtypes | Record/struct types | Not supported | Use multiple arrays or external format |

### Workarounds for Unsupported Types

**Boolean data:**
```elixir
# Instead of Python bool
# Store as uint8
{:ok, array} = ExZarr.create(
  dtype: :uint8,  # 0 = false, 1 = true
  # ... other options
)

# Document in attributes
ExZarr.Array.put_attributes(array, %{
  "dtype_semantic" => "boolean",
  "false_value" => 0,
  "true_value" => 1
})
```

```python
# Read in Python
z = zarr.open_array('/path/to/array')
bool_data = z[:].astype(bool)  # Convert uint8 to bool
```

**Datetime data:**
```elixir
# Store as int64 Unix timestamps (microseconds since epoch)
{:ok, array} = ExZarr.create(
  dtype: :int64,
  # ... other options
)

# Document in attributes
ExZarr.Array.put_attributes(array, %{
  "dtype_semantic" => "datetime64[us]",
  "epoch" => "1970-01-01T00:00:00Z"
})

# Convert DateTime to int64 microseconds
timestamp = DateTime.utc_now()
  |> DateTime.to_unix(:microsecond)
```

```python
# Read in Python
z = zarr.open_array('/path/to/array')
timestamps = z[:]
datetimes = pd.to_datetime(timestamps, unit='us')  # Convert to datetime
```

**Complex numbers:**
```elixir
# Store real and imaginary parts in separate arrays
{:ok, real_array} = ExZarr.create(
  path: "/data/complex_real",
  dtype: :float64,
  # ... options
)

{:ok, imag_array} = ExZarr.create(
  path: "/data/complex_imag",
  dtype: :float64,
  # ... options
)
```

```python
# Read in Python
real = zarr.open_array('/data/complex_real')[:]
imag = zarr.open_array('/data/complex_imag')[:]
complex_data = real + 1j * imag  # Reconstruct complex array
```

**String data:**
```elixir
# Store strings as attributes (for small datasets)
ExZarr.Array.put_attributes(array, %{
  "labels" => ["label1", "label2", "label3"]
})

# Or store in separate JSON file
labels = ["label1", "label2", "label3"]
File.write!("/data/labels.json", Jason.encode!(labels))
```

## Metadata Translation Details

### Zarr v2 Metadata Files

**Structure:**
```
/path/to/array/
  .zarray          # Array metadata (shape, dtype, chunks, compressor)
  .zattrs          # User attributes (optional, JSON object)
  0.0, 0.1, ...    # Chunk files
```

**`.zarray` example (Python-created):**
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

**ExZarr equivalent:**
```elixir
%ExZarr.Metadata{
  zarr_format: 2,
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  compressor_config: [level: 5],
  fill_value: 0.0,
  order: "C",
  filters: nil
}
```

### Dtype String Parsing

ExZarr automatically converts between NumPy dtype strings and Elixir atoms:

| NumPy String | ExZarr Atom | Notes |
|--------------|-------------|-------|
| `<i4` | `:int32` | Little-endian 32-bit int |
| `>i4` | `:int32` | Big-endian 32-bit int (handled) |
| `\|i1` | `:int8` | Native byte order (single byte) |
| `<f8` | `:float64` | Little-endian 64-bit float |
| `<u2` | `:uint16` | Little-endian 16-bit unsigned int |

### Dimension Separator (v2 Quirk)

Zarr v2 allows two chunk key formats:

**Dot separator (default):**
```
0.0, 0.1, 1.0, 1.1  # Chunks named with dots
```

**Slash separator:**
```
0/0, 0/1, 1/0, 1/1  # Chunks named with slashes
```

ExZarr supports both formats:
- **Reading:** Automatically detects separator from metadata
- **Writing:** Defaults to `.` for compatibility with Python default

Override with `dimension_separator` option:
```elixir
{:ok, array} = ExZarr.create(
  dimension_separator: "/",  # Use slash separator
  # ... other options
)
```

## Compression Codec Compatibility

### Codec Compatibility Matrix

| Codec  | ExZarr Support | zarr-python Support | Interoperable | Notes |
|--------|----------------|---------------------|---------------|-------|
| **zlib** | Always (Erlang) | Always | ✓ Yes | **Recommended for compatibility** |
| **gzip** | Always (Erlang) | Always | ✓ Yes | Same as zlib with gzip headers |
| **zstd** | Optional (Zig NIF) | Yes (numcodecs) | ✓ Yes | Requires libzstd on both sides |
| **lz4** | Optional (Zig NIF) | Yes (numcodecs) | ✓ Yes | Requires liblz4 on both sides |
| **blosc** | Optional (Zig NIF) | Yes (numcodecs) | ✓ Yes | Requires libblosc on both sides |
| **snappy** | Optional (Zig NIF) | Yes (numcodecs) | Partial | Less common in Python ecosystem |
| **bzip2** | Optional (Zig NIF) | Yes (numcodecs) | ✓ Yes | Requires libbz2 on both sides |
| **Custom** | Via behavior | Via numcodecs | ✗ No | Requires identical codec implementation |

### Recommendation for Maximum Compatibility

**Use zlib:**
```elixir
# Always works, no dependencies
compressor: :zlib
```

**For better compression (if both sides have zstd):**
```elixir
# Check availability first
if ExZarr.Codecs.codec_available?(:zstd) do
  compressor: :zstd
else
  compressor: :zlib  # Fallback
end
```

### Checking Codec Availability

**In Elixir:**
```elixir
ExZarr.Codecs.codec_available?(:zstd)
# => true (if libzstd installed)

ExZarr.Codecs.available_codecs()
# => [:zlib, :gzip, :zstd, :lz4, :blosc, :bzip2, :crc32c]
```

**In Python:**
```python
import numcodecs
print(numcodecs.blosc.list_compressors())
# ['blosclz', 'lz4', 'lz4hc', 'snappy', 'zlib', 'zstd']
```

## Compatibility Boundaries

### What Works ✓

**Fully compatible:**
- All 10 standard numeric dtypes (int8-int64, uint8-uint64, float32-float64)
- Zarr v2 format (ExZarr ↔ zarr-python 2.x)
- Zarr v3 format (ExZarr ↔ zarr-python 3.x)
- Standard compressors (zlib, gzip, zstd, lz4, blosc, bzip2)
- N-dimensional arrays (1D, 2D, 3D, ..., any dimension count)
- Chunked reading and writing
- Attributes and metadata (JSON-serializable)
- Hierarchical groups (nested arrays)
- Fill values (uninitialized chunks)
- Standard filters (shuffle, delta)

### What Partially Works ⚠️

**Requires coordination:**

**Zarr v3 core features:**
- **Unified codec pipeline:** Full support in ExZarr and zarr-python 3.x
- **Dimension names:** Full support in ExZarr and zarr-python 3.x
- **Improved metadata format:** Full support in ExZarr and zarr-python 3.x

**Zarr v3 extension features:**
- **Sharding:** ExZarr supports, requires zarr-python 3.x with sharding extension
- **Custom chunk grids:** ExZarr supports, requires zarr-python 3.x

**Recommendation:** Use v3 for new projects with modern Python tools (zarr-python 3.x). Use v2 for maximum compatibility with legacy zarr-python 2.x installations.

**Filters:**
- **Shuffle, Delta:** ExZarr supports, zarr-python requires `numcodecs` package
- **Quantize:** ExZarr supports, zarr-python requires `numcodecs` package

**Recommendation:** Ensure Python side has `numcodecs` installed: `pip install numcodecs`

### What Doesn't Work ✗

**Not supported in ExZarr:**
- Complex dtypes (`complex64`, `complex128`)
- Boolean dtype (`bool`) - use uint8 workaround
- Datetime dtype (`datetime64`) - use int64 timestamp workaround
- Timedelta dtype (`timedelta64`)
- Object dtype (`object`, variable-length strings)
- Structured dtypes (record arrays)
- Custom codecs without matching implementation on both sides

### Edge Cases

**Very large arrays (> 1 TB):**
- Both implementations handle large arrays
- Test at scale before production deployment
- Monitor memory usage (chunks loaded into RAM)

**Concurrent writes:**
- Both implementations support concurrent writes to different chunks
- Need external coordination for writes to same chunk
- Use file locking or application-level coordination

**Symbolic links:**
- Filesystem backend behavior may differ between implementations
- Test if using symlinks in storage paths

**Network filesystems:**
- NFS, SMB may have different consistency guarantees
- Test cross-language access on shared network storage

## Troubleshooting Cross-Language Issues

### Issue: Python Can't Read ExZarr Array

**Symptom:**
```python
>>> import zarr
>>> z = zarr.open_array('/data/array')
ValueError: Unsupported compressor: 'custom_codec'
```

**Diagnosis:**
1. Check Zarr version compatibility:
   ```bash
   # Is array v3? Does Python have zarr-python 3.0+?
   cat /data/array/zarr.json  # v3 indicator
   ```

2. Check compressor availability:
   ```python
   import numcodecs
   print(numcodecs.blosc.list_compressors())
   ```

3. Validate `.zarray` file:
   ```bash
   cat /data/array/.zarray | python -m json.tool
   ```

**Fix:**
- Use Zarr v2: `zarr_version: 2` in ExZarr
- Use standard codec: `compressor: :zlib`
- Install missing codec: `pip install numcodecs`

### Issue: ExZarr Can't Read Python Array

**Symptom:**
```elixir
{:error, {:unsupported_dtype, "complex128"}}
```

**Diagnosis:**
1. Check dtype:
   ```python
   import zarr
   z = zarr.open_array('/data/array')
   print(z.dtype)  # Is it in compatibility matrix?
   ```

2. Check compressor:
   ```python
   print(z.compressor)
   ```

3. Check for custom filters:
   ```python
   print(z.filters)  # ExZarr may not support all filters
   ```

**Fix:**
- Use supported dtype (see compatibility matrix)
- Use standard codec: `compressor=zarr.Zlib()`
- Remove unsupported filters

### Issue: Data Values Don't Match

**Symptom:**
Values read in Python differ from values written in Elixir.

**Diagnosis:**
1. Check dtype matches exactly:
   ```elixir
   # Elixir
   array.metadata.dtype  # :int32

   # Python
   z.dtype  # int32 (must match)
   ```

2. Check byte order (should both be little-endian):
   ```elixir
   # ExZarr always writes little-endian
   ```

3. Check fill value handling:
   ```elixir
   # Uninitialized chunks return fill_value
   array.metadata.fill_value  # 0.0
   ```

4. Read small slice and compare byte-by-byte:
   ```elixir
   {:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {2, 2})
   ```
   ```python
   data = z[0:2, 0:2]
   print(data)
   ```

**Fix:**
- Ensure dtype is identical
- Verify both use same fill_value
- Check that data was actually written (not returning fill_value)

### Issue: Metadata Looks Correct But Reading Fails

**Symptom:**
Metadata parses correctly, but chunk reading fails.

**Diagnosis:**
1. Check file permissions:
   ```bash
   ls -la /data/array/
   # All files readable?
   ```

2. Check dimension separator:
   ```bash
   cat /data/array/.zarray | grep dimension_separator
   # "." or "/"?
   ```

3. Verify chunk files exist:
   ```bash
   ls /data/array/ | grep -E '^[0-9]+\.[0-9]+$'
   # Or: ls /data/array/ | grep -E '^[0-9]+/[0-9]+$'
   ```

4. Compare chunk file names to expected coordinates:
   ```elixir
   # Expected chunk (0, 0)
   # v2 dot: "0.0"
   # v2 slash: "0/0"
   ```

**Fix:**
- Fix file permissions: `chmod -R a+r /data/array`
- Ensure dimension_separator matches chunk naming
- Verify chunks were actually written to storage

### Issue: Performance Differs Between Python and Elixir

**Symptom:**
Same operation takes different time in each language.

**Expected behavior:**
- Different compression implementations may have different speeds
- BEAM parallelism may give ExZarr advantage on multi-chunk reads
- Python NumPy operations may be faster (C-optimized)

**Diagnosis:**
1. Check chunk size appropriate for workload:
   ```elixir
   array.metadata.chunks  # Too small? Too large?
   ```

2. Check compression level:
   ```elixir
   array.metadata.compressor_config
   ```

3. Profile both implementations:
   ```elixir
   # Elixir
   {time_us, _result} = :timer.tc(fn ->
     ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1000, 1000})
   end)
   IO.puts("#{div(time_us, 1000)}ms")
   ```

   ```python
   # Python
   import time
   start = time.time()
   data = z[0:1000, 0:1000]
   print(f"{(time.time() - start) * 1000}ms")
   ```

**Not a bug if:**
- Both complete successfully with correct results
- Performance difference explained by implementation choices
- Both meet production requirements

## Summary

This guide covered Python interoperability:

- **Use cases:** Python producer/Elixir consumer, bidirectional, archive interchange
- **Reading Python arrays:** Automatic format detection, dtype mapping, codec compatibility
- **Writing for Python:** Use v2, standard codecs, common dtypes, descriptive attributes
- **Dtype compatibility:** 10 standard types fully supported, workarounds for unsupported
- **Metadata translation:** Automatic conversion between NumPy strings and Elixir atoms
- **Codec compatibility:** zlib recommended, zstd widely available, custom codecs incompatible
- **Boundaries:** What works (numeric types), partial (v3 features), doesn't work (complex, bool, datetime)
- **Troubleshooting:** 5 common issues with diagnosis steps and fixes

**Key recommendations:**
- Use Zarr v2 for maximum compatibility
- Use zlib compressor (always works)
- Test cross-language before deploying
- Document dtype semantics in attributes
- Check codec availability on both sides

## Next Steps

Now that you understand Python interoperability:

1. **Performance Tuning:** Optimize for your workload in [Performance Guide](performance.md)
2. **Nx Integration:** Work with tensors in [Nx Integration Guide](nx_integration.md)
3. **Storage Providers:** Apply interop knowledge to cloud storage in [Storage Providers Guide](storage_providers.md)
4. **Troubleshooting:** Debug issues in [Troubleshooting Guide](troubleshooting.md)
