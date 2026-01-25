# Migrating from Zarr v2 to v3 in ExZarr

This guide helps you migrate existing Zarr v2 code to use the v3 specification in ExZarr.

## Overview

Zarr v3 introduces several improvements over v2:

- **Unified codec pipeline**: Single `codecs` array replaces separate `filters` and `compressor`
- **Improved metadata format**: Consolidated `zarr.json` replaces multiple files
- **Better extensibility**: Built-in support for custom extensions
- **Simplified data types**: Human-readable type names like `"float64"` instead of `"<f8"`
- **Hierarchical chunk storage**: Chunks stored in `c/` directory with slash-separated paths

ExZarr supports both v2 and v3 simultaneously, allowing gradual migration.

## Quick Migration Checklist

- [ ] Update array creation to specify `zarr_version: 3`
- [ ] Convert `filters` and `compressor` to unified `codecs` array
- [ ] Verify chunk key format in storage (if directly manipulating files)
- [ ] Update tests to handle both v2 and v3 metadata files
- [ ] Consider whether existing v2 arrays need conversion

## Breaking Changes

### 1. Metadata File Names

**v2**:
```
my_array/
  .zarray          # Array metadata
  .zgroup          # Group metadata (if applicable)
  .zattrs          # Attributes (optional)
  0.0              # Chunk files
  0.1
```

**v3**:
```
my_array/
  zarr.json        # Unified metadata (includes attributes)
  c/               # Chunk directory
    0/
      0            # Chunk files
      1
```

**Impact**: Code that directly reads `.zarray` files will not work with v3 arrays.

**Solution**: Use ExZarr's `open/1` function which automatically detects the version:
```elixir
# Works for both v2 and v3
{:ok, array} = ExZarr.open(path: "/path/to/array")
```

### 2. Codec Configuration

**v2**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 2
)
```

**v3**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "bytes"},  # Required
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3
)
```

**Impact**: The `filters` and `compressor` options are replaced by a single `codecs` array.

**Solution**: Convert your codec configuration using the mapping below.

### 3. Chunk Key Format

**v2**: Dot-separated indices
```
0.0
0.1
1.0
1.1
```

**v3**: Slash-separated with prefix
```
c/0/0
c/0/1
c/1/0
c/1/1
```

**Impact**: Direct file path manipulation breaks.

**Solution**: Use ExZarr's chunk operations instead of direct file access:
```elixir
# Don't do this
File.read!("#{path}/0.0")  # v2 specific

# Do this instead
{:ok, array} = ExZarr.open(path: path)
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
```

## Step-by-Step Migration

### Step 1: Update Array Creation

Change from v2 to v3 format:

**Before (v2)**:
```elixir
def create_my_array do
  ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    compressor: :zlib,
    filters: [{:shuffle, [elementsize: 8]}],
    storage: :filesystem,
    path: "/data/my_array"
  )
end
```

**After (v3)**:
```elixir
def create_my_array do
  ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    codecs: [
      %{name: "shuffle", configuration: %{elementsize: 8}},
      %{name: "bytes"},
      %{name: "gzip", configuration: %{level: 5}}
    ],
    zarr_version: 3,
    storage: :filesystem,
    path: "/data/my_array"
  )
end
```

### Step 2: Codec Mapping Reference

Use this table to convert v2 configuration to v3 codecs:

#### Compressor Mapping

| v2 Compressor | v3 Codec |
|---------------|----------|
| `:zlib` | `%{name: "gzip", configuration: %{level: 5}}` |
| `:zstd` | `%{name: "zstd", configuration: %{level: 5}}` |
| `:lz4` | `%{name: "lz4"}` |
| `:blosc` | `%{name: "blosc"}` |
| `:bzip2` | `%{name: "bz2"}` |
| `:crc32c` | `%{name: "crc32c"}` |
| `:none` | (omit bytes-to-bytes codec) |

#### Filter Mapping

| v2 Filter | v3 Codec |
|-----------|----------|
| `{:shuffle, [elementsize: N]}` | `%{name: "shuffle", configuration: %{elementsize: N}}` |
| `{:delta, [dtype: T]}` | `%{name: "delta", configuration: %{dtype: "typeN"}}` |
| `{:quantize, [digits: N, dtype: T]}` | `%{name: "quantize", configuration: %{digits: N, dtype: "typeN"}}` |
| `{:astype, [encode_dtype: T]}` | `%{name: "astype", configuration: %{encode_dtype: "typeN"}}` |
| `{:bitround, [keepbits: N]}` | `%{name: "bitround", configuration: %{keepbits: N}}` |

#### Data Type Mapping

| v2 Atom | v3 String |
|---------|-----------|
| `:int8` | `"int8"` |
| `:int16` | `"int16"` |
| `:int32` | `"int32"` |
| `:int64` | `"int64"` |
| `:uint8` | `"uint8"` |
| `:uint16` | `"uint16"` |
| `:uint32` | `"uint32"` |
| `:uint64` | `"uint64"` |
| `:float32` | `"float32"` |
| `:float64` | `"float64"` |

### Step 3: Update Array Opening

Version detection is automatic:

**Before**:
```elixir
{:ok, array} = ExZarr.open(path: "/data/my_array")
# Assume it's v2
```

**After**:
```elixir
{:ok, array} = ExZarr.open(path: "/data/my_array")
# Automatically detects v2 or v3

# Optionally check version
case array.version do
  2 -> handle_v2_array(array)
  3 -> handle_v3_array(array)
end
```

### Step 4: Codec Ordering in v3

v3 enforces strict codec ordering:

1. **Array → Array** codecs (zero or more): Filters like shuffle, delta
2. **Array → Bytes** codec (exactly one, required): Always `bytes`
3. **Bytes → Bytes** codecs (zero or more): Compression like gzip, zstd

**Correct order**:
```elixir
codecs: [
  %{name: "shuffle", configuration: %{elementsize: 8}},  # 1. Array→Array
  %{name: "delta", configuration: %{dtype: "int64"}},    # 1. Array→Array
  %{name: "bytes"},                                       # 2. Array→Bytes (required)
  %{name: "gzip", configuration: %{level: 5}},          # 3. Bytes→Bytes
  %{name: "zstd", configuration: %{level: 3}}           # 3. Bytes→Bytes
]
```

**Incorrect order** (will fail validation):
```elixir
# Wrong: compression before bytes codec
codecs: [
  %{name: "gzip"},    # Error: bytes→bytes before array→bytes
  %{name: "bytes"}
]

# Wrong: filter after bytes codec
codecs: [
  %{name: "bytes"},
  %{name: "shuffle"}  # Error: array→array after array→bytes
]
```

## Automatic v2-to-v3 Conversion

ExZarr automatically converts v2-style configuration when you specify `zarr_version: 3`:

```elixir
# Specify v2-style filters/compressor but request v3 format
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 3  # Request v3 format
)

# ExZarr automatically converts to:
# codecs: [
#   %{name: "shuffle", configuration: %{elementsize: 8}},
#   %{name: "bytes"},
#   %{name: "gzip", configuration: %{level: 5}}
# ]
```

This allows gradual migration without immediately rewriting all codec specifications.

## Compatibility Mode

### Reading v2 Arrays

v2 arrays open transparently:

```elixir
# v2 array on disk
{:ok, v2_array} = ExZarr.open(path: "/data/old_v2_array")
assert v2_array.version == 2

# All operations work normally
{:ok, data} = ExZarr.Array.get_slice(v2_array, start: {0}, stop: {100})
```

### Reading v3 Arrays

v3 arrays also open transparently:

```elixir
# v3 array on disk
{:ok, v3_array} = ExZarr.open(path: "/data/new_v3_array")
assert v3_array.version == 3

# Same API as v2
{:ok, data} = ExZarr.Array.get_slice(v3_array, start: {0}, stop: {100})
```

### Mixed v2/v3 Usage

You can work with both versions simultaneously:

```elixir
# Open both versions
{:ok, v2} = ExZarr.open(path: "/data/legacy_v2")
{:ok, v3} = ExZarr.open(path: "/data/modern_v3")

# Use identical API for both
{:ok, v2_data} = ExZarr.Array.to_binary(v2)
{:ok, v3_data} = ExZarr.Array.to_binary(v3)

# Version is tracked internally
IO.puts("v2 array version: #{v2.version}")  # 2
IO.puts("v3 array version: #{v3.version}")  # 3
```

## Common Patterns

### Pattern 1: Simple Compression

**v2**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :float64,
  compressor: :zlib
)
```

**v3**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3
)
```

### Pattern 2: No Compression

**v2**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int32,
  compressor: :none
)
```

**v3**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int32,
  codecs: [%{name: "bytes"}],  # Only required codec, no compression
  zarr_version: 3
)
```

### Pattern 3: Shuffle + Compression

**v2**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib
)
```

**v3**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  codecs: [
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "bytes"},
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3
)
```

### Pattern 4: Multiple Filters

**v2**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [
    {:quantize, [digits: 2, dtype: :float64]},
    {:shuffle, [elementsize: 8]}
  ],
  compressor: :zstd
)
```

**v3**:
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "quantize", configuration: %{digits: 2, dtype: "float64"}},
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "bytes"},
    %{name: "zstd", configuration: %{level: 5}}
  ],
  zarr_version: 3
)
```

## Testing Your Migration

### Test Both Versions

Ensure your code handles both v2 and v3:

```elixir
defmodule MyApp.ArrayTest do
  use ExUnit.Case

  test "handles v2 arrays" do
    {:ok, array} = ExZarr.create(
      shape: {100},
      chunks: {10},
      dtype: :int32,
      compressor: :zlib,
      zarr_version: 2,
      storage: :memory
    )

    assert array.version == 2

    # Test your operations
    :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
    {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})
    assert read_data == data
  end

  test "handles v3 arrays" do
    {:ok, array} = ExZarr.create(
      shape: {100},
      chunks: {10},
      dtype: :int32,
      codecs: [%{name: "bytes"}, %{name: "gzip"}],
      zarr_version: 3,
      storage: :memory
    )

    assert array.version == 3

    # Same operations should work
    :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
    {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})
    assert read_data == data
  end
end
```

### Verify File Structure

Check that persisted arrays have the correct structure:

```elixir
# v2 structure
assert File.exists?("#{v2_path}/.zarray")
assert File.exists?("#{v2_path}/0")  # Chunk with dot notation

# v3 structure
assert File.exists?("#{v3_path}/zarr.json")
assert File.dir?("#{v3_path}/c")  # Chunk directory
assert File.exists?("#{v3_path}/c/0")  # Chunk with slash notation
```

## Troubleshooting

### Problem: "Unknown codec" error with v3 array

**Symptom**: Error when opening v3 array with custom codecs

**Solution**: Ensure codec names match v3 specification. v2 uses atoms (`:shuffle`), v3 uses strings (`"shuffle"`).

### Problem: Chunks not found after migration

**Symptom**: `{:error, :not_found}` when reading chunks from v3 array

**Cause**: Chunk key format changed from dot-notation to slash-notation

**Solution**: Don't manually construct chunk paths. Use ExZarr's API:
```elixir
# Wrong: Manual path construction
File.read!("#{path}/0.0")

# Correct: Use ExZarr API
{:ok, array} = ExZarr.open(path: path)
{:ok, data} = ExZarr.Array.get_slice(array, ...)
```

### Problem: Metadata parse error

**Symptom**: `{:error, :invalid_metadata}` when opening array

**Cause**: Mixed v2/v3 metadata files in same directory

**Solution**: Keep v2 and v3 arrays in separate directories. Don't try to convert in-place.

### Problem: Codec ordering validation fails

**Symptom**: `{:error, :invalid_codec_order}`

**Cause**: v3 enforces strict codec ordering

**Solution**: Follow this order:
1. Array→Array codecs (filters)
2. Array→Bytes codec (`bytes` - required)
3. Bytes→Bytes codecs (compression)

## Best Practices

### 1. Use v3 for New Arrays

Unless you need compatibility with older tools, use v3 for all new arrays:

```elixir
# Prefer this for new arrays
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :float64,
  codecs: [%{name: "bytes"}, %{name: "gzip"}],
  zarr_version: 3
)
```

### 2. Keep v2 Arrays as v2

Don't convert existing v2 arrays to v3 unless necessary. Both formats work seamlessly:

```elixir
# It's fine to keep v2 arrays as v2
{:ok, legacy_array} = ExZarr.open(path: "/data/legacy_v2_array")
# All operations work normally
```

### 3. Use Automatic Conversion for Gradual Migration

When creating new arrays, use v2-style syntax with `zarr_version: 3` for gradual migration:

```elixir
# Transitional approach: v2 syntax, v3 format
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  filters: [{:shuffle, [elementsize: 8]}],  # v2 style
  compressor: :zlib,                          # v2 style
  zarr_version: 3                             # But save as v3
)

# Later, migrate to explicit v3 syntax
# codecs: [
#   %{name: "shuffle", configuration: %{elementsize: 8}},
#   %{name: "bytes"},
#   %{name: "gzip", configuration: %{level: 5}}
# ]
```

### 4. Version-Agnostic Code

Write code that works with both versions:

```elixir
def process_array(path) do
  {:ok, array} = ExZarr.open(path: path)

  # Version-agnostic operations
  {:ok, data} = ExZarr.Array.to_binary(array)
  process_data(data)
end
```

### 5. Document Version Requirements

If your code requires a specific version, document it:

```elixir
@doc """
Processes a Zarr array.

Requires: Zarr v3 format for optimal performance.
"""
def process_modern_array(path) do
  {:ok, array} = ExZarr.open(path: path)

  unless array.version == 3 do
    {:error, :requires_v3_format}
  else
    # Process array
  end
end
```

## Additional Resources

- [Zarr v3 Specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/index.html)
- [Zarr v2 Specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html)
- [ExZarr Documentation](https://hexdocs.pm/ex_zarr)
- [Zarr-Python v3 Migration Guide](https://zarr.readthedocs.io/en/stable/user-guide/v3_migration/)

## Summary

Migrating from v2 to v3 in ExZarr:

1. **For new arrays**: Use `zarr_version: 3` with unified `codecs` array
2. **For existing arrays**: No migration needed - both versions work seamlessly
3. **Gradual migration**: Use v2-style syntax with `zarr_version: 3` for automatic conversion
4. **Testing**: Ensure your code handles both v2 and v3 arrays
5. **Best practice**: Write version-agnostic code using ExZarr's API

The transition from v2 to v3 is designed to be gradual and non-breaking. ExZarr handles version differences internally, allowing you to focus on your application logic.
