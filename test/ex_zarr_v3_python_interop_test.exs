defmodule ExZarr.V3PythonInteropTest do
  use ExUnit.Case

  @moduletag :python
  @moduletag :python_v3

  @moduledoc """
  Integration tests verifying interoperability between ExZarr and zarr-python 3.x.

  These tests ensure that ExZarr can read Zarr v3 arrays created by Python's zarr
  library 3.x, and that Python can read v3 arrays created by ExZarr, validating
  compliance with the Zarr v3 specification.

  ## Requirements

  - Python 3.9+
  - **zarr-python 3.x** (specifically >= 3.0.0) - **NOT 2.x**
  - numpy 1.20+

  ## Setup

  Install zarr-python 3.x:

      pip install 'zarr>=3.0.0' numpy

  **Note**: zarr-python 3.x has significant API changes from 2.x. These tests
  require version 3.x specifically.

  ## Running Tests

      # Run v3 Python interop tests (requires zarr-python 3.x)
      mix test --include python_v3

      # Or run all Python tests (both v2 and v3)
      mix test --include python
  """

  @test_dir "/tmp/ex_zarr_v3_python_interop_#{System.unique_integer([:positive])}"
  @python_helper Path.join(__DIR__, "support/zarr_python_helper.py")

  setup_all do
    # Check if Python and zarr-python 3.x are available
    case check_python_v3_dependencies() do
      :ok ->
        File.mkdir_p!(@test_dir)
        on_exit(fn -> File.rm_rf!(@test_dir) end)
        {:ok, python_v3_available: true}

      {:error, _reason} ->
        # Tests will be skipped, no setup needed
        {:ok, python_v3_available: false}
    end
  end

  describe "Python 3.x to ExZarr v3 compatibility" do
    test "reads 1D int32 v3 array created by zarr-python 3.x", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "py3_v3_1d_int32")

      # Create v3 array with Python
      {:ok, result} = python_create_v3_array(path, [100], [100], "int32")
      assert result["success"], "Failed to create v3 array: #{inspect(result)}"
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
      assert verify["success"], "Python verification failed: #{inspect(verify)}"
    end

    test "reads 2D float64 v3 array created by zarr-python 3.x", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "py3_v3_2d_float64")

      # Create v3 array with Python
      {:ok, result} = python_create_v3_array(path, [50, 50], [10, 10], "float64")
      assert result["success"]
      checksum = result["checksum"]

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.version == 3
      assert array.shape == {50, 50}
      assert array.dtype == :float64
      assert match?(%ExZarr.MetadataV3{}, array.metadata)

      # Verify chunk grid
      {:ok, chunk_shape} = ExZarr.MetadataV3.get_chunk_shape(array.metadata)
      assert chunk_shape == {10, 10}

      # Verify with Python
      {:ok, verify} = python_verify_v3_array(path, [50, 50], "float64", checksum)
      assert verify["success"]
    end

    test "reads 3D uint16 v3 array created by zarr-python 3.x", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "py3_v3_3d_uint16")

      # Create v3 array with Python
      {:ok, result} = python_create_v3_array(path, [10, 10, 10], [5, 5, 5], "uint16")
      assert result["success"]

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.version == 3
      assert array.shape == {10, 10, 10}
      assert array.dtype == :uint16
      assert match?(%ExZarr.MetadataV3{}, array.metadata)
      assert ExZarr.Array.ndim(array) == 3
    end

    test "reads v3 arrays with all integer dtypes", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

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
        path = Path.join(@test_dir, "py3_v3_dtype_#{python_dtype}")

        # Create with Python
        {:ok, result} = python_create_v3_array(path, [50], [50], python_dtype)
        assert result["success"], "Failed to create v3 #{python_dtype}"

        # Read with ExZarr
        {:ok, array} = ExZarr.open(path: path)
        assert array.version == 3
        assert array.dtype == elixir_dtype, "Dtype mismatch for #{python_dtype}"
        assert array.shape == {50}
        assert match?(%ExZarr.MetadataV3{}, array.metadata)
      end
    end

    test "reads v3 arrays with float dtypes", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      dtypes = [
        {:float32, "float32"},
        {:float64, "float64"}
      ]

      for {elixir_dtype, python_dtype} <- dtypes do
        path = Path.join(@test_dir, "py3_v3_float_#{python_dtype}")

        # Create with Python
        {:ok, result} = python_create_v3_array(path, [50], [50], python_dtype)
        assert result["success"]

        # Read with ExZarr
        {:ok, array} = ExZarr.open(path: path)
        assert array.version == 3
        assert array.dtype == elixir_dtype
        assert match?(%ExZarr.MetadataV3{}, array.metadata)
      end
    end

    test "v3 array has correct chunk directory structure", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "py3_v3_chunk_structure")

      # Create v3 array with Python
      {:ok, result} = python_create_v3_array(path, [100], [20], "int32")
      assert result["success"]

      # Verify zarr.json exists (not .zarray)
      assert File.exists?(Path.join(path, "zarr.json"))
      refute File.exists?(Path.join(path, ".zarray"))

      # Verify c/ chunk directory exists
      chunk_dir = Path.join(path, "c")
      assert File.dir?(chunk_dir)

      # Verify chunks are in c/ directory (not root)
      chunks = File.ls!(chunk_dir)
      assert Enum.empty?(chunks) == false

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.version == 3
    end
  end

  describe "ExZarr v3 to Python 3.x compatibility" do
    test "creates 1D int32 v3 array readable by zarr-python 3.x", %{
      python_v3_available: available
    } do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "exzarr_v3_1d_int32")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {100},
          dtype: :int32,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert array.version == 3

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Write some data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Verify Python can read it
      {:ok, result} = python_read_v3_array(path)
      assert result["success"], "Python failed to read v3 array: #{inspect(result)}"
      assert result["metadata"]["zarr_format"] == 3
      assert result["metadata"]["shape"] == [100]
      assert String.contains?(result["metadata"]["dtype"], "int32")
    end

    test "creates 2D float64 v3 array readable by zarr-python 3.x", %{
      python_v3_available: available
    } do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "exzarr_v3_2d_float64")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :float64,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert array.version == 3

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Write some data
      data = for i <- 0..2499, into: <<>>, do: <<i * 1.0::float-little-64>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {50, 50})

      # Verify Python can read it
      {:ok, result} = python_read_v3_array(path)
      assert result["success"]
      assert result["metadata"]["zarr_format"] == 3
      assert result["metadata"]["shape"] == [50, 50]
      assert String.contains?(result["metadata"]["dtype"], "float64")
    end

    test "creates 3D uint16 v3 array readable by zarr-python 3.x", %{
      python_v3_available: available
    } do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "exzarr_v3_3d_uint16")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10, 10},
          chunks: {5, 5, 5},
          dtype: :uint16,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert array.version == 3

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Verify Python can read it
      {:ok, result} = python_read_v3_array(path)
      assert result["success"]
      assert result["metadata"]["zarr_format"] == 3
      assert result["metadata"]["shape"] == [10, 10, 10]
      assert String.contains?(result["metadata"]["dtype"], "uint16")
    end

    test "creates v3 arrays with all dtypes readable by Python", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

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
        path = Path.join(@test_dir, "exzarr_v3_all_dtypes_#{dtype}")

        # Create with ExZarr
        {:ok, array} =
          ExZarr.create(
            shape: {50},
            chunks: {50},
            dtype: dtype,
            codecs: [
              %{name: "bytes"},
              %{name: "gzip", configuration: %{level: 5}}
            ],
            zarr_version: 3,
            storage: :filesystem,
            path: path
          )

        assert array.version == 3

        # Save metadata
        :ok = ExZarr.save(array, path: path)

        # Verify Python can read it
        {:ok, result} = python_read_v3_array(path)
        assert result["success"], "Python failed to read v3 #{dtype}: #{inspect(result)}"
        assert result["metadata"]["zarr_format"] == 3
        assert result["metadata"]["shape"] == [50]

        # Check dtype is recognized
        py_dtype = result["metadata"]["dtype"]
        dtype_str = Atom.to_string(dtype)

        expected_base =
          case dtype_str do
            "uint" <> bits -> "uint" <> bits
            "int" <> bits -> "int" <> bits
            "float" <> bits -> "float" <> bits
            other -> other
          end

        assert String.contains?(py_dtype, expected_base),
               "Dtype mismatch: Python sees #{py_dtype}, expected #{expected_base}"
      end
    end

    test "v3 array has correct file structure", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "exzarr_v3_structure")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "gzip"}],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert array.version == 3

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Write data to create chunks
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Verify file structure
      assert File.exists?(Path.join(path, "zarr.json"))
      refute File.exists?(Path.join(path, ".zarray"))

      # Verify c/ chunk directory
      chunk_dir = Path.join(path, "c")
      assert File.dir?(chunk_dir)

      # Verify chunks use v3 naming (0, 1, 2 not 0.0, 0.1)
      chunks = File.ls!(chunk_dir)
      # 100 / 20 = 5 chunks
      assert length(chunks) == 5
      assert "0" in chunks
      assert "4" in chunks

      # Python should be able to read it
      {:ok, result} = python_read_v3_array(path)
      assert result["success"]
    end
  end

  describe "v3 metadata compatibility" do
    test "ExZarr correctly reads Python v3 array metadata", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "py3_v3_metadata")

      # Create with Python
      {:ok, result} = python_create_v3_array(path, [100, 200], [50, 50], "float32")
      assert result["success"]

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)

      # Verify v3 metadata
      assert array.version == 3
      assert match?(%ExZarr.MetadataV3{}, array.metadata)
      assert array.metadata.zarr_format == 3
      assert array.metadata.node_type == :array
      assert array.metadata.shape == {100, 200}
      assert array.metadata.data_type == "float32"

      # Verify chunk grid
      assert array.metadata.chunk_grid.name == "regular"
      {:ok, chunk_shape} = ExZarr.MetadataV3.get_chunk_shape(array.metadata)
      assert chunk_shape == {50, 50}

      # Verify codecs exist (unified pipeline)
      assert is_list(array.metadata.codecs)
      assert Enum.empty?(array.metadata.codecs) == false
    end

    test "Python correctly reads ExZarr v3 array metadata", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "exzarr_v3_metadata")

      # Create with ExZarr
      {:ok, array} =
        ExZarr.create(
          shape: {150, 250},
          chunks: {50, 50},
          dtype: :int64,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          fill_value: -1,
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert array.version == 3

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Read with Python
      {:ok, result} = python_read_v3_array(path)
      assert result["success"]
      assert result["metadata"]["zarr_format"] == 3
      assert result["metadata"]["shape"] == [150, 250]
      assert String.contains?(result["metadata"]["dtype"], "int64")
      assert result["metadata"]["fill_value"] == -1.0
    end

    test "v3 chunk calculations match between ExZarr and Python", %{
      python_v3_available: available
    } do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "v3_chunks_compatibility")

      # Create with Python
      {:ok, _result} = python_create_v3_array(path, [1000], [100], "int32")

      # Read with ExZarr
      {:ok, array} = ExZarr.open(path: path)
      assert array.version == 3

      # Verify chunk shape
      {:ok, chunk_shape} = ExZarr.MetadataV3.get_chunk_shape(array.metadata)
      assert chunk_shape == {100}

      # Calculate number of chunks
      {:ok, num_chunks} = ExZarr.MetadataV3.num_chunks(array.metadata)
      assert num_chunks == {10}

      {:ok, total} = ExZarr.MetadataV3.total_chunks(array.metadata)
      assert total == 10
    end
  end

  describe "v3 codec compatibility" do
    test "unified codec pipeline is preserved", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "v3_codec_pipeline")

      # Create with ExZarr using specific codecs
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {100},
          dtype: :float64,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert array.version == 3

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Verify codec list structure
      assert is_list(array.metadata.codecs)
      assert length(array.metadata.codecs) == 2

      # Verify bytes codec is present (required)
      assert Enum.any?(array.metadata.codecs, fn codec -> codec.name == "bytes" end)

      # Verify gzip codec is present
      assert Enum.any?(array.metadata.codecs, fn codec -> codec.name == "gzip" end)

      # Python should be able to read it
      {:ok, result} = python_read_v3_array(path)
      assert result["success"]
    end

    test "bytes codec is always present in v3 arrays", %{python_v3_available: available} do
      assert available,
             "zarr-python 3.x not available. Install with: pip install 'zarr>=3.0.0' numpy"

      path = Path.join(@test_dir, "v3_bytes_codec")

      # Create v3 array
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {50},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "gzip"}],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      # Save metadata
      :ok = ExZarr.save(array, path: path)

      # Read metadata
      metadata = array.metadata
      assert metadata.zarr_format == 3

      # Verify bytes codec exists
      has_bytes = Enum.any?(metadata.codecs, fn codec -> codec.name == "bytes" end)
      assert has_bytes, "v3 array must have bytes codec"

      # Python should be able to read it
      {:ok, result} = python_read_v3_array(path)
      assert result["success"]
    end
  end

  ## Helper Functions

  defp check_python_v3_dependencies do
    case System.cmd("python3", ["--version"]) do
      {_, 0} ->
        # Check for zarr 3.x
        args = [@python_helper, "check_version"]

        case System.cmd("python3", args) do
          {output, 0} ->
            result = Jason.decode!(output)

            case result do
              %{"version" => _version, "supports_v3" => true} ->
                :ok

              %{"version" => version, "supports_v3" => false} ->
                {:error,
                 "zarr-python 3.x required, found #{version}. Install with: pip install 'zarr>=3.0.0'"}

              %{"error" => error} ->
                {:error, "zarr-python check failed: #{error}"}
            end

          {output, _} ->
            {:error, "Failed to check zarr-python version: #{output}"}
        end

      {output, _} ->
        {:error, "Python 3 not found: #{output}"}
    end
  end

  defp python_create_v3_array(path, shape, chunks, dtype) do
    shape_json = Jason.encode!(shape)
    chunks_json = Jason.encode!(chunks)
    args = [@python_helper, "create_v3_array", path, shape_json, chunks_json, dtype]

    case System.cmd("python3", args) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _} ->
        {:error, output}
    end
  end

  defp python_read_v3_array(path) do
    args = [@python_helper, "read_v3_array", path]

    case System.cmd("python3", args) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _} ->
        {:error, output}
    end
  end

  defp python_verify_v3_array(path, expected_shape, expected_dtype, expected_checksum) do
    shape_json = Jason.encode!(expected_shape)
    checksum_str = Float.to_string(expected_checksum)

    args = [@python_helper, "verify_v3_array", path, shape_json, expected_dtype, checksum_str]

    case System.cmd("python3", args) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _} ->
        {:error, output}
    end
  end
end
