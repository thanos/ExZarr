# Python Integration Test Support

This directory contains supporting files for integration tests between ExZarr and zarr-python.

## Files

- **`zarr_python_helper.py`** - Python script that creates and reads Zarr arrays using zarr-python
- **`requirements.txt`** - Python dependencies (zarr 2.x, numpy)
- **`setup_python_tests.sh`** - Setup script to install Python dependencies

## Setup

Install the required Python dependencies:

```bash
./test/support/setup_python_tests.sh
```

This script will:
1. Check for Python 3 installation
2. Install zarr-python 2.x and numpy
3. Verify the installation

## Usage

The integration tests are located in `test/ex_zarr_python_integration_test.exs`.

Run them with:

```bash
mix test test/ex_zarr_python_integration_test.exs
```

Or run all tests including integration tests:

```bash
mix test
```

## Python Helper Script

The `zarr_python_helper.py` script provides commands for creating and reading Zarr arrays:

```bash
# Create a test array
python3 zarr_python_helper.py create_test_array <path> <shape> <dtype>

# Read an array
python3 zarr_python_helper.py read_array <path>

# Verify array data
python3 zarr_python_helper.py read_and_verify <path> <shape> <dtype> <checksum>
```

Example:

```bash
# Create a 100x100 int32 array
python3 test/support/zarr_python_helper.py create_test_array /tmp/test '[100, 100]' 'int32'

# Read it back
python3 test/support/zarr_python_helper.py read_array /tmp/test
```

## What the Integration Tests Verify

The integration tests ensure Zarr v2 specification compliance by testing:

1. **Python to ExZarr**:
   - Arrays created by zarr-python can be opened and read by ExZarr
   - Metadata is correctly interpreted
   - All data types are compatible
   - Chunk organization is understood

2. **ExZarr to Python**:
   - Arrays created by ExZarr can be opened and read by zarr-python
   - Metadata follows Zarr v2 specification
   - Dtype encoding is correct
   - Compression is compatible

3. **Data Types Tested**:
   - All 10 integer and float types (int8-64, uint8-64, float32/64)
   - 1D, 2D, and 3D arrays
   - Various chunk sizes

4. **Compression**:
   - zlib compression compatibility
   - No compression (none codec)

## Requirements

- **Python**: 3.6 or later
- **zarr-python**: 2.10.0 or later, but less than 3.0.0 (Zarr v2 API)
- **numpy**: 1.20.0 or later

## Troubleshooting

If tests fail with "zarr-python or numpy not installed":

```bash
# Install manually
python3 -m pip install 'zarr>=2.10.0,<3.0.0' numpy

# Or use the setup script
./test/support/setup_python_tests.sh
```

If tests are skipped:

- Check that Python 3 is installed: `python3 --version`
- Verify zarr is installed: `python3 -c "import zarr; print(zarr.__version__)"`
- Ensure zarr version is 2.x, not 3.x

## Implementation Notes

The integration tests use `System.cmd/3` to execute the Python helper script from Elixir tests. This approach:

- Avoids complex FFI or port communication
- Tests the actual Zarr files on disk (true integration)
- Verifies byte-level compatibility
- Works consistently across platforms
