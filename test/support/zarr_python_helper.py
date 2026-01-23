#!/usr/bin/env python3
"""
Helper script for zarr-python integration tests.

This script creates Zarr arrays using zarr-python that can be read by ExZarr,
and reads arrays created by ExZarr to verify compatibility.
"""

import sys
import json
import numpy as np
import zarr


def create_array(path, shape, chunks, dtype, compressor, fill_value):
    """Create a Zarr array using zarr-python."""
    # Map compressor names
    compressor_map = {
        'none': None,
        'zlib': zarr.Zlib(level=5),
        'zstd': zarr.Blosc(cname='zstd', clevel=5, shuffle=zarr.Blosc.SHUFFLE) if hasattr(zarr, 'Blosc') else zarr.Zlib(level=5),
        'lz4': zarr.Blosc(cname='lz4', clevel=5, shuffle=zarr.Blosc.SHUFFLE) if hasattr(zarr, 'Blosc') else zarr.Zlib(level=5),
    }

    comp = compressor_map.get(compressor, None)

    # Create array
    z = zarr.open_array(
        path,
        mode='w',
        shape=shape,
        chunks=chunks,
        dtype=dtype,
        compressor=comp,
        fill_value=fill_value
    )

    # Fill with test data
    if len(shape) == 1:
        z[:] = np.arange(shape[0], dtype=dtype)
    elif len(shape) == 2:
        z[:, :] = np.arange(shape[0] * shape[1], dtype=dtype).reshape(shape)
    elif len(shape) == 3:
        z[:, :, :] = np.arange(shape[0] * shape[1] * shape[2], dtype=dtype).reshape(shape)

    return True


def read_array(path):
    """Read a Zarr array and return its data and metadata."""
    z = zarr.open_array(path, mode='r')

    metadata = {
        'shape': list(z.shape),
        'chunks': list(z.chunks),
        'dtype': str(z.dtype),
        'fill_value': float(z.fill_value) if z.fill_value is not None else None,
    }

    # Read data
    data = z[:]

    return {
        'metadata': metadata,
        'data': data.tolist(),
        'checksum': float(np.sum(data))
    }


def verify_array_data(path, expected_checksum):
    """Verify array data matches expected checksum."""
    z = zarr.open_array(path, mode='r')
    data = z[:]
    actual_checksum = float(np.sum(data))

    return abs(actual_checksum - expected_checksum) < 0.0001


def create_test_array_simple(path, shape, dtype):
    """Create a simple test array with sequential data."""
    z = zarr.open_array(
        path,
        mode='w',
        shape=shape,
        chunks=tuple(min(s, 100) for s in shape),
        dtype=dtype,
        compressor=zarr.Zlib(level=5),
        fill_value=0
    )

    # Fill with sequential integers
    total_size = np.prod(shape)
    if len(shape) == 1:
        z[:] = np.arange(total_size, dtype=dtype)
    elif len(shape) == 2:
        z[:, :] = np.arange(total_size, dtype=dtype).reshape(shape)
    elif len(shape) == 3:
        z[:, :, :] = np.arange(total_size, dtype=dtype).reshape(shape)

    # Calculate and return checksum
    checksum = float(np.sum(z[:]))
    return checksum


def read_and_verify_array(path, expected_shape, expected_dtype, expected_checksum):
    """Read array and verify it matches expected properties."""
    try:
        z = zarr.open_array(path, mode='r')

        # Check metadata
        if list(z.shape) != list(expected_shape):
            return {'success': False, 'error': f'Shape mismatch: {z.shape} != {expected_shape}'}

        # Check dtype (normalize format)
        z_dtype = str(z.dtype)
        if z_dtype.startswith('int'):
            z_dtype = 'int' + str(z.dtype.itemsize * 8)
        elif z_dtype.startswith('uint'):
            z_dtype = 'uint' + str(z.dtype.itemsize * 8)
        elif z_dtype.startswith('float'):
            z_dtype = 'float' + str(z.dtype.itemsize * 8)

        exp_dtype = expected_dtype.replace('<', '').replace('>', '')
        if z_dtype != exp_dtype:
            return {'success': False, 'error': f'Dtype mismatch: {z_dtype} != {exp_dtype}'}

        # Check data checksum
        data = z[:]
        actual_checksum = float(np.sum(data))

        if abs(actual_checksum - expected_checksum) > 0.0001:
            return {
                'success': False,
                'error': f'Checksum mismatch: {actual_checksum} != {expected_checksum}'
            }

        return {'success': True, 'checksum': actual_checksum}

    except Exception as e:
        return {'success': False, 'error': str(e)}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({'error': 'No command specified'}))
        return 1

    command = sys.argv[1]

    try:
        if command == 'create_array':
            # create_array <path> <shape> <chunks> <dtype> <compressor> <fill_value>
            path = sys.argv[2]
            shape = json.loads(sys.argv[3])
            chunks = json.loads(sys.argv[4])
            dtype = sys.argv[5]
            compressor = sys.argv[6]
            fill_value = float(sys.argv[7])

            create_array(path, tuple(shape), tuple(chunks), dtype, compressor, fill_value)
            print(json.dumps({'success': True}))

        elif command == 'read_array':
            # read_array <path>
            path = sys.argv[2]
            result = read_array(path)
            print(json.dumps(result))

        elif command == 'verify_array_data':
            # verify_array_data <path> <expected_checksum>
            path = sys.argv[2]
            expected = float(sys.argv[3])
            success = verify_array_data(path, expected)
            print(json.dumps({'success': success}))

        elif command == 'create_test_array':
            # create_test_array <path> <shape> <dtype>
            path = sys.argv[2]
            shape = json.loads(sys.argv[3])
            dtype = sys.argv[4]
            checksum = create_test_array_simple(path, tuple(shape), dtype)
            print(json.dumps({'success': True, 'checksum': checksum}))

        elif command == 'read_and_verify':
            # read_and_verify <path> <expected_shape> <expected_dtype> <expected_checksum>
            path = sys.argv[2]
            expected_shape = json.loads(sys.argv[3])
            expected_dtype = sys.argv[4]
            expected_checksum = float(sys.argv[5])
            result = read_and_verify_array(path, expected_shape, expected_dtype, expected_checksum)
            print(json.dumps(result))

        else:
            print(json.dumps({'error': f'Unknown command: {command}'}))
            return 1

    except Exception as e:
        print(json.dumps({'error': str(e)}))
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
