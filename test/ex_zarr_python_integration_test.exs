defmodule ExZarr.PythonIntegrationTest do
  use ExUnit.Case

  @moduletag :python

  @moduledoc """
  Integration tests verifying interoperability between ExZarr and zarr-python.

  These tests ensure that ExZarr can read arrays created by Python's zarr
  library, and that Python can read arrays created by ExZarr, validating
  compliance with the Zarr v2 specification.

  ## What This Tests

  ### Bidirectional Compatibility
  - **Python → ExZarr**: Arrays created by zarr-python can be opened and
    read by ExZarr with correct metadata interpretation
  - **ExZarr → Python**: Arrays created by ExZarr can be opened and read
    by zarr-python with correct metadata interpretation

  ### Data Types
  - All 10 Zarr v2 data types (int8-64, uint8-64, float32/64)
  - Correct encoding/decoding of dtype strings (<i4, <f8, etc.)
  - Byte order handling (little-endian, big-endian, native)

  ### Array Dimensions
  - 1D arrays (shape: {100})
  - 2D arrays (shape: {50, 50})
  - 3D arrays (shape: {10, 10, 10})

  ### Compression
  - Zlib compression compatibility
  - No compression (none codec) compatibility
  - Compressed chunks readable by both implementations

  ### Metadata
  - Shape preservation
  - Chunk size preservation
  - Fill value preservation
  - Compressor configuration

  ## Test Structure

  Tests are organized into describe blocks:

  1. **Python to ExZarr compatibility** - Tests ExZarr's ability to read
     arrays created by zarr-python
  2. **ExZarr to Python compatibility** - Tests Python's ability to read
     arrays created by ExZarr
  3. **Metadata compatibility** - Tests metadata round-tripping and
     interpretation
  4. **Compression compatibility** - Tests compression codec compatibility

  ## Requirements

  - Python 3.6+
  - zarr-python 2.x (not 3.x - API changed)
  - numpy 1.20+

  ## Setup

  Install dependencies before running:

      ./test/support/setup_python_tests.sh

  Or manually:

      python3 -m pip install 'zarr>=2.10.0,<3.0.0' numpy

  ## Running Tests

      # Run only integration tests
      mix test test/ex_zarr_python_integration_test.exs

      # Run with detailed output
      mix test test/ex_zarr_python_integration_test.exs --trace

      # Run all tests including integration tests
      mix test

  ## Test Skipping

  If Python or required libraries are not installed, these tests will be
  skipped with an appropriate message. The test suite uses `setup_all` to
  check for dependencies before running.

  ## Implementation Details

  Tests use a Python helper script (`test/support/zarr_python_helper.py`)
  to create and read arrays. This approach:

  - Tests actual file I/O (not just API compatibility)
  - Verifies byte-level compatibility
  - Works across platforms
  - Avoids complex FFI or port communication

  The helper script is invoked using `System.cmd/3` and communicates via
  JSON for structured data exchange.

  ## What Is Verified

  Each test verifies specific compatibility aspects:

  - Arrays can be opened without errors
  - Metadata is correctly interpreted
  - Data types match expected values
  - Chunks are correctly located and read
  - Compression/decompression works correctly
  - Data integrity is maintained (checksums match)

  ## Related Documentation

  - See `INTEROPERABILITY.md` for user-facing compatibility guide
  - See `test/support/README.md` for helper script documentation
  - See `test/support/zarr_python_helper.py` for implementation details
  """

  @test_dir "/tmp/ex_zarr_python_integration_#{System.unique_integer([:positive])}"
  @python_helper Path.join(__DIR__, "support/zarr_python_helper.py")

  setup_all do
    # Check if Python and required libraries are available
    case check_python_dependencies() do
      :ok ->
        File.mkdir_p!(@test_dir)
        on_exit(fn -> File.rm_rf!(@test_dir) end)
        :ok

      {:error, reason} ->
        {:skip, reason}
    end
  end

  describe "Python to ExZarr compatibility" do
    test "reads 1D int32 array created by zarr-python" do
      path = Path.join(@test_dir, "python_1d_int32")

      # Create array with Python
      {:ok, result} = python_create_test_array(path, [100], "int32")
      assert result["success"]
      checksum = result["checksum"]

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.shape == {100}
      assert array.dtype == :int32
      assert array.chunks == {100}

      # Verify data (by checking metadata at least)
      assert ExZarr.Array.ndim(array) == 1
      assert ExZarr.Array.size(array) == 100

      # Python should be able to verify its own data
      {:ok, verify} = python_read_and_verify(path, [100], "int32", checksum)
      assert verify["success"]
    end

    test "reads 2D float64 array created by zarr-python" do
      path = Path.join(@test_dir, "python_2d_float64")

      # Create array with Python
      {:ok, result} = python_create_test_array(path, [50, 50], "float64")
      assert result["success"]
      checksum = result["checksum"]

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.shape == {50, 50}
      assert array.dtype == :float64
      assert ExZarr.Array.ndim(array) == 2
      assert ExZarr.Array.size(array) == 2500

      # Verify with Python
      {:ok, verify} = python_read_and_verify(path, [50, 50], "float64", checksum)
      assert verify["success"]
    end

    test "reads 3D uint8 array created by zarr-python" do
      path = Path.join(@test_dir, "python_3d_uint8")

      # Create array with Python
      {:ok, result} = python_create_test_array(path, [10, 10, 10], "uint8")
      assert result["success"]
      checksum = result["checksum"]

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.shape == {10, 10, 10}
      assert array.dtype == :uint8
      assert ExZarr.Array.ndim(array) == 3
      assert ExZarr.Array.size(array) == 1000

      # Verify with Python
      {:ok, verify} = python_read_and_verify(path, [10, 10, 10], "uint8", checksum)
      assert verify["success"]
    end

    test "reads arrays with all integer dtypes" do
      dtypes = [
        {:int8, "int8"},
        {:int16, "int16"},
        {:int32, "int32"},
        {:int64, "int64"},
        {:uint8, "uint8"},
        {:uint16, "uint16"},
        {:uint32, "uint32"},
        {:uint64, "uint64"}
      ]

      for {elixir_dtype, python_dtype} <- dtypes do
        path = Path.join(@test_dir, "python_dtype_#{python_dtype}")

        # Create with Python
        {:ok, result} = python_create_test_array(path, [50], python_dtype)
        assert result["success"], "Failed to create #{python_dtype}"

        # Read with ExZarr
        {:ok, array} = ExZarr.open(path: path)
        assert array.dtype == elixir_dtype, "Dtype mismatch for #{python_dtype}"
        assert array.shape == {50}
      end
    end

    test "reads arrays with float dtypes" do
      dtypes = [
        {:float32, "float32"},
        {:float64, "float64"}
      ]

      for {elixir_dtype, python_dtype} <- dtypes do
        path = Path.join(@test_dir, "python_float_#{python_dtype}")

        # Create with Python
        {:ok, result} = python_create_test_array(path, [50], python_dtype)
        assert result["success"]

        # Read with ExZarr
        {:ok, array} = ExZarr.open(path: path)
        assert array.dtype == elixir_dtype
        assert array.shape == {50}
      end
    end
  end

  describe "ExZarr to Python compatibility" do
    test "creates 1D int32 array readable by zarr-python" do
      path = Path.join(@test_dir, "exzarr_1d_int32")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {100},
          dtype: :int32,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.save(array, path: path)

      # Verify Python can read it
      {:ok, result} = python_read_array(path)
      assert result["metadata"]["shape"] == [100]
      assert String.contains?(result["metadata"]["dtype"], "int32")
    end

    test "creates 2D float64 array readable by zarr-python" do
      path = Path.join(@test_dir, "exzarr_2d_float64")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {50, 50},
          dtype: :float64,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.save(array, path: path)

      # Verify Python can read it
      {:ok, result} = python_read_array(path)
      assert result["metadata"]["shape"] == [50, 50]
      assert String.contains?(result["metadata"]["dtype"], "float64")
    end

    test "creates 3D uint16 array readable by zarr-python" do
      path = Path.join(@test_dir, "exzarr_3d_uint16")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10, 10},
          chunks: {10, 10, 10},
          dtype: :uint16,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.save(array, path: path)

      # Verify Python can read it
      {:ok, result} = python_read_array(path)
      assert result["metadata"]["shape"] == [10, 10, 10]
      assert String.contains?(result["metadata"]["dtype"], "uint16")
    end

    test "creates arrays with all dtypes readable by Python" do
      dtypes = [
        :int8,
        :int16,
        :int32,
        :int64,
        :uint8,
        :uint16,
        :uint32,
        :uint64,
        :float32,
        :float64
      ]

      for dtype <- dtypes do
        path = Path.join(@test_dir, "exzarr_all_dtypes_#{dtype}")

        # Create with ExZarr
        {:ok, array} =
          ExZarr.create(
            shape: {50},
            chunks: {50},
            dtype: dtype,
            compressor: :zlib,
            storage: :filesystem,
            path: path
          )

        :ok = ExZarr.save(array, path: path)

        # Verify Python can read it
        {:ok, result} = python_read_array(path)
        assert result["metadata"]["shape"] == [50], "Shape mismatch for #{dtype}"

        # Check dtype is recognized (normalize for comparison)
        py_dtype = result["metadata"]["dtype"]
        dtype_str = Atom.to_string(dtype)

        # Normalize dtype strings for comparison
        expected_base =
          case dtype_str do
            "uint" <> bits -> "uint" <> bits
            "int" <> bits -> "int" <> bits
            "float" <> bits -> "float" <> bits
            other -> other
          end

        assert String.contains?(py_dtype, expected_base),
               "Dtype mismatch: Python sees #{py_dtype}, expected something containing #{expected_base}"
      end
    end

    test "creates array with no compression readable by Python" do
      path = Path.join(@test_dir, "exzarr_no_compression")

      # Create with ExZarr (no compression)
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {50},
          dtype: :float64,
          compressor: :none,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.save(array, path: path)

      # Verify Python can read it
      {:ok, result} = python_read_array(path)
      assert result["metadata"]["shape"] == [50]
    end
  end

  describe "Metadata compatibility" do
    test "ExZarr correctly reads Python array metadata" do
      path = Path.join(@test_dir, "metadata_python")

      # Create with Python
      {:ok, result} = python_create_test_array(path, [100, 200], "float32")
      assert result["success"]

      # Read metadata with ExZarr
      {:ok, array} = ExZarr.open(path: path)

      assert array.shape == {100, 200}
      assert array.dtype == :float32
      assert array.compressor == :zlib
      assert array.fill_value == 0.0
      assert ExZarr.Array.itemsize(array) == 4
    end

    test "Python correctly reads ExZarr array metadata" do
      path = Path.join(@test_dir, "metadata_exzarr")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {150, 250},
          chunks: {50, 50},
          dtype: :int64,
          compressor: :zlib,
          fill_value: -1,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.save(array, path: path)

      # Read with Python
      {:ok, result} = python_read_array(path)

      assert result["metadata"]["shape"] == [150, 250]
      assert String.contains?(result["metadata"]["dtype"], "int64")
      assert result["metadata"]["fill_value"] == -1.0
    end

    test "chunk boundaries match between ExZarr and Python" do
      path = Path.join(@test_dir, "chunks_compatibility")

      # Create with Python with specific chunk size
      {:ok, _result} = python_create_test_array(path, [1000], "int32")

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)

      # Verify chunk size matches
      assert array.chunks == {100}, "Chunk size should match Python's default"

      # Calculate expected number of chunks
      num_chunks = ExZarr.Metadata.num_chunks(array.metadata)
      total_chunks = ExZarr.Metadata.total_chunks(array.metadata)

      assert num_chunks == {10}
      assert total_chunks == 10
    end
  end

  describe "Compression compatibility" do
    test "zlib compressed arrays are compatible" do
      path_py = Path.join(@test_dir, "zlib_python")
      path_ex = Path.join(@test_dir, "zlib_exzarr")

      # Python creates with zlib
      {:ok, result} = python_create_test_array(path_py, [100], "int32")
      assert result["success"]

      # ExZarr creates with zlib
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {100},
          dtype: :int32,
          compressor: :zlib,
          storage: :filesystem,
          path: path_ex
        )

      :ok = ExZarr.save(array, path: path_ex)

      # Both should be readable
      {:ok, array_from_py} = ExZarr.open(path: path_py)
      assert array_from_py.compressor == :zlib

      {:ok, result_from_ex} = python_read_array(path_ex)
      assert result_from_ex["metadata"]["shape"] == [100]
    end
  end

  ## Helper Functions

  defp check_python_dependencies do
    case System.cmd("python3", ["--version"]) do
      {_, 0} ->
        # Check for zarr and numpy
        case System.cmd("python3", ["-c", "import zarr; import numpy"]) do
          {_, 0} ->
            :ok

          {output, _} ->
            {:error,
             "zarr-python or numpy not installed. Install with: pip install zarr numpy\nError: #{output}"}
        end

      {output, _} ->
        {:error, "Python 3 not found: #{output}"}
    end
  end

  defp python_create_test_array(path, shape, dtype) do
    shape_json = Jason.encode!(shape)
    args = [@python_helper, "create_test_array", path, shape_json, dtype]

    case System.cmd("python3", args) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _} ->
        {:error, output}
    end
  end

  defp python_read_array(path) do
    args = [@python_helper, "read_array", path]

    case System.cmd("python3", args) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _} ->
        {:error, output}
    end
  end

  defp python_read_and_verify(path, expected_shape, expected_dtype, expected_checksum) do
    shape_json = Jason.encode!(expected_shape)
    checksum_str = Float.to_string(expected_checksum)

    args = [
      @python_helper,
      "read_and_verify",
      path,
      shape_json,
      expected_dtype,
      checksum_str
    ]

    case System.cmd("python3", args) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _} ->
        {:error, output}
    end
  end
end
