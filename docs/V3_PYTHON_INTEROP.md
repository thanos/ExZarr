# Zarr v3 Python Interoperability Testing

## Overview

ExZarr includes comprehensive integration tests to verify interoperability with zarr-python 3.x, ensuring full compliance with the Zarr v3 specification.

## Test Coverage

The v3 Python interoperability test suite (`test/ex_zarr_v3_python_interop_test.exs`) covers:

### Bidirectional Compatibility
- **Python 3.x → ExZarr**: Arrays created by zarr-python can be read by ExZarr
- **ExZarr → Python 3.x**: Arrays created by ExZarr can be read by zarr-python

### v3-Specific Features
- Unified codec pipeline (bytes + compression)
- zarr.json metadata format
- c/ chunk directory structure
- Simplified data type names (int32, float64, etc.)
- Regular chunk grid configuration
- Codec ordering validation

### Data Types
- All 10 core v3 data types (int8-64, uint8-64, float32/64)
- Correct v3 data_type string format
- Type preservation across implementations

### Array Dimensions
- 1D arrays (tested with shape {100})
- 2D arrays (tested with shape {50, 50})
- 3D arrays (tested with shape {10, 10, 10})

### Metadata Compatibility
- zarr_format: 3
- node_type: array
- Shape preservation
- Chunk grid configuration
- Codec list preservation
- Fill value preservation

## Requirements

To run v3 Python interoperability tests, you need:

- **Python 3.9+**
- **zarr-python 3.x** (>= 3.0.0) - **NOT 2.x**
- **numpy 1.20+**

### Installation

```bash
pip install 'zarr>=3.0.0' numpy
```

**Important**: zarr-python 3.x has significant API changes from 2.x. These tests specifically require version 3.x.

## Running Tests

The v3 Python interop tests are tagged with `:python` and `:python_v3` and are excluded by default.

### Run v3 Python Interop Tests Only

```bash
mix test --include python_v3 test/ex_zarr_v3_python_interop_test.exs
```

### Run All Python Tests (v2 and v3)

```bash
mix test --include python
```

### Run Specific Test

```bash
mix test --include python_v3 test/ex_zarr_v3_python_interop_test.exs:103
```

## Test Structure

The test suite is organized into four main sections:

### 1. Python 3.x to ExZarr v3 Compatibility (7 tests)
Tests ExZarr's ability to read v3 arrays created by zarr-python 3.x:
- 1D/2D/3D arrays
- All integer and float dtypes
- Correct chunk directory structure

### 2. ExZarr v3 to Python 3.x Compatibility (6 tests)
Tests zarr-python 3.x's ability to read v3 arrays created by ExZarr:
- 1D/2D/3D arrays
- All dtypes
- Correct file structure (zarr.json, c/ directory)

### 3. v3 Metadata Compatibility (3 tests)
Tests metadata round-tripping and interpretation:
- ExZarr reads Python metadata correctly
- Python reads ExZarr metadata correctly
- Chunk calculations match

### 4. v3 Codec Compatibility (2 tests)
Tests codec pipeline preservation:
- Unified codec pipeline
- Bytes codec presence (required in v3)

## Implementation Details

### Python Helper Script

Tests use `test/support/zarr_python_helper.py` to create and read arrays. The helper script provides:

#### v3-Specific Commands

1. **check_version**: Check if zarr-python supports v3
   ```bash
   python3 test/support/zarr_python_helper.py check_version
   ```
   Returns: `{"version": "3.x.x", "supports_v3": true}`

2. **create_v3_array**: Create a v3 array
   ```bash
   python3 test/support/zarr_python_helper.py create_v3_array \
     <path> <shape_json> <chunks_json> <dtype>
   ```

3. **read_v3_array**: Read a v3 array and return metadata
   ```bash
   python3 test/support/zarr_python_helper.py read_v3_array <path>
   ```

4. **verify_v3_array**: Verify a v3 array matches expected properties
   ```bash
   python3 test/support/zarr_python_helper.py verify_v3_array \
     <path> <expected_shape_json> <expected_dtype> <expected_checksum>
   ```

### Test Skipping

If zarr-python 3.x is not installed, tests are automatically skipped with an informative message:

```
All tests have been excluded.
Finished in 0.1 seconds
0 tests, 0 failures (16 excluded)
```

This allows the test suite to run without zarr-python 3.x installed, making it suitable for CI/CD pipelines where Python dependencies may not be available.

## Verification Approach

Each test verifies multiple aspects:

1. **File Structure**: Correct zarr.json format, c/ directory
2. **Metadata**: Proper v3 metadata fields and values
3. **Data Integrity**: Checksums match after round-trip
4. **Spec Compliance**: Chunk keys, codec ordering, etc.
5. **Cross-Platform**: Both implementations can read each other's arrays

## Example Test

```elixir
test "reads 1D int32 v3 array created by zarr-python 3.x" do
  path = Path.join(@test_dir, "py3_v3_1d_int32")

  # Create v3 array with Python
  {:ok, result} = python_create_v3_array(path, [100], [100], "int32")
  assert result["success"]
  checksum = result["checksum"]

  # Read with ExZarr
  {:ok, array} = ExZarr.open(path: path)
  assert array.version == 3
  assert array.shape == {100}
  assert array.dtype == :int32

  # Verify metadata is v3
  assert match?(%ExZarr.MetadataV3{}, array.metadata)
  assert array.metadata.zarr_format == 3
  assert array.metadata.node_type == :array

  # Verify with Python
  {:ok, verify} = python_verify_v3_array(path, [100], "int32", checksum)
  assert verify["success"]
end
```

## Benefits

- **Confidence**: Ensures ExZarr v3 implementation matches zarr-python behavior
- **Regression Prevention**: Catches compatibility issues early
- **Spec Compliance**: Validates adherence to Zarr v3 specification
- **Documentation**: Tests serve as examples of correct usage

## Future Enhancements

Potential additions to the test suite:

- [ ] Additional compression codecs (zstd, lz4)
- [ ] Sharding extension
- [ ] Custom codec extensions
- [ ] Group metadata (when implemented)
- [ ] Variable chunking patterns
- [ ] Performance benchmarks (ExZarr vs zarr-python)

## Related Documentation

- [Zarr v3 Specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/index.html)
- [zarr-python 3.x Documentation](https://zarr.readthedocs.io/en/stable/)
- [V2_TO_V3_MIGRATION.md](../V2_TO_V3_MIGRATION.md) - Migration guide for ExZarr users
- [README.md](../README.md) - General ExZarr documentation
