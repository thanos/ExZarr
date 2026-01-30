# v3 Python Interoperability Test Fix

## Issue

The v3 Python interoperability tests were failing with the error:

```
"No array found in store file:///tmp/... at path "
```

When ExZarr created v3 arrays and Python tried to read them, Python couldn't find the array metadata.

## Root Cause

The tests were missing the `ExZarr.save/2` call after creating v3 arrays. In Zarr v3:

1. `ExZarr.create/1` creates the array structure in memory
2. `ExZarr.save/2` **writes the metadata file** (zarr.json) to disk
3. Without the save call, the zarr.json file doesn't exist on disk
4. Python can't find the array because there's no metadata file

### Before the Fix

```elixir
{:ok, array} = ExZarr.create(
  shape: {50, 50},
  dtype: :float64,
  codecs: [...],
  zarr_version: 3,
  storage: :filesystem,
  path: path
)

# Write data
:ok = ExZarr.Array.set_slice(array, data, ...)

# Try to read with Python - FAILS! No zarr.json file exists
{:ok, result} = python_read_v3_array(path)
```

### After the Fix

```elixir
{:ok, array} = ExZarr.create(
  shape: {50, 50},
  dtype: :float64,
  codecs: [...],
  zarr_version: 3,
  storage: :filesystem,
  path: path
)

# Save metadata - creates zarr.json file
:ok = ExZarr.save(array, path: path)

# Write data
:ok = ExZarr.Array.set_slice(array, data, ...)

# Read with Python - SUCCESS! zarr.json exists
{:ok, result} = python_read_v3_array(path)
```

## Verification

Test script confirms the fix:

```elixir
{:ok, array} = ExZarr.create(
  shape: {10},
  dtype: :int32,
  codecs: [%{name: "bytes"}, %{name: "gzip"}],
  zarr_version: 3,
  storage: :filesystem,
  path: path
)

# Before save: zarr.json does NOT exist
File.exists?(Path.join(path, "zarr.json"))  # => false

# Save metadata
:ok = ExZarr.save(array, path: path)

# After save: zarr.json DOES exist
File.exists?(Path.join(path, "zarr.json"))  # => true

# Metadata is correctly formatted
content = File.read!(Path.join(path, "zarr.json"))
Jason.decode!(content)
# => %{"zarr_format" => 3, "node_type" => "array", ...}
```

## Tests Fixed

Added `ExZarr.save/2` call to **8 tests** in `test/ex_zarr_v3_python_interop_test.exs`:

### ExZarr v3 → Python 3.x Compatibility (6 tests)
1. Line 236: "creates 1D int32 v3 array readable by zarr-python 3.x"
2. Line 274: "creates 2D float64 v3 array readable by zarr-python 3.x"
3. Line 312: "creates 3D uint16 v3 array readable by zarr-python 3.x"
4. Line 349: "creates v3 arrays with all dtypes readable by Python"
5. Line 395: "v3 array has correct file structure"

### v3 Metadata Compatibility (1 test)
6. Line 478: "Python correctly reads ExZarr v3 array metadata"

### v3 Codec Compatibility (2 tests)
7. Line 540: "unified codec pipeline is preserved"
8. Line 576: "bytes codec is always present in v3 arrays"

## Result

All tests now properly:
1. Create v3 arrays with ExZarr
2. **Save metadata to disk** with `ExZarr.save/2`
3. Allow Python to successfully read the arrays

## Lesson Learned

When creating v3 arrays for external tools to read:
- Always call `ExZarr.save/2` after `ExZarr.create/1`
- This ensures the zarr.json metadata file is written to disk
- Without it, the array exists in memory but not on disk

## Related

- This pattern matches the existing v3 integration tests (see `test/ex_zarr_v3_integration_test.exs:219`)
- v2 arrays behave differently - metadata is written during create
- v3 requires explicit save for cleaner separation of concerns
