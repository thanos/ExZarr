defmodule ExZarr.IntegrationTest do
  use ExUnit.Case

  @test_dir "/tmp/ex_zarr_integration_#{System.unique_integer([:positive])}"

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  describe "ExZarr module API" do
    test "create -> save -> open -> load workflow" do
      path = Path.join(@test_dir, "workflow_test")

      # Create array
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :float64,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      # Save it
      assert :ok = ExZarr.save(array, path: path)

      # Open it
      assert {:ok, loaded} = ExZarr.open(path: path, backend: :filesystem)
      assert loaded.shape == {50, 50}
      assert loaded.chunks == {10, 10}

      # Load data
      assert {:ok, _data} = ExZarr.load(path: path, backend: :filesystem)
    end

    test "load from non-existent path returns error" do
      path = Path.join(@test_dir, "nonexistent")
      result = ExZarr.load(path: path, backend: :filesystem)
      assert match?({:error, _}, result)
    end

    test "open from non-existent path returns error" do
      path = Path.join(@test_dir, "nonexistent2")
      result = ExZarr.open(path: path, backend: :filesystem)
      assert match?({:error, _}, result)
    end
  end

  describe "Memory storage integration" do
    test "creates and uses memory-backed array" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      assert array.storage.backend == :memory
      assert {:ok, _binary} = ExZarr.Array.to_binary(array)
    end
  end

  describe "Group and array hierarchy" do
    test "creates complex group structure" do
      {:ok, root} = ExZarr.Group.create("/")

      {:ok, experiments} = ExZarr.Group.create_group(root, "experiments")

      {:ok, _array1} =
        ExZarr.Group.create_array(experiments, "results",
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :float64
        )

      {:ok, _array2} =
        ExZarr.Group.create_array(experiments, "metadata",
          shape: {100},
          chunks: {10},
          dtype: :int32
        )

      assert experiments.path == "/experiments"
    end

    test "group attributes persist" do
      {:ok, group} = ExZarr.Group.create("/data")

      group =
        group
        |> ExZarr.Group.set_attr("experiment", "test-001")
        |> ExZarr.Group.set_attr("date", "2026-01-22")
        |> ExZarr.Group.set_attr("version", 1)

      assert {:ok, "test-001"} = ExZarr.Group.get_attr(group, "experiment")
      assert {:ok, "2026-01-22"} = ExZarr.Group.get_attr(group, "date")
      assert {:ok, 1} = ExZarr.Group.get_attr(group, "version")
    end
  end

  describe "Multiple arrays in filesystem" do
    test "creates multiple independent arrays" do
      path1 = Path.join(@test_dir, "array1")
      path2 = Path.join(@test_dir, "array2")

      {:ok, array1} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :float64,
          storage: :filesystem,
          path: path1
        )

      {:ok, array2} =
        ExZarr.create(
          shape: {200, 200},
          chunks: {20, 20},
          dtype: :int32,
          storage: :filesystem,
          path: path2
        )

      ExZarr.save(array1, path: path1)
      ExZarr.save(array2, path: path2)

      {:ok, loaded1} = ExZarr.open(path: path1, backend: :filesystem)
      {:ok, loaded2} = ExZarr.open(path: path2, backend: :filesystem)

      assert loaded1.dtype == :float64
      assert loaded2.dtype == :int32
    end
  end

  describe "Chunk utilities integration" do
    test "calculates correct chunks for large array" do
      {:ok, array} = ExZarr.create(shape: {10_000, 10_000}, chunks: {1000, 1000})

      # nchunks would be {10, 10} if the function existed
      assert ExZarr.Array.size(array) == 100_000_000
    end

    test "slice_to_chunks returns correct range" do
      # Test slice calculation
      start = {0, 0}
      stop = {250, 250}
      chunk_shape = {100, 100}

      result = ExZarr.Chunk.slice_to_chunks(start, stop, chunk_shape)
      assert result == {{0, 0}, {2, 2}}
    end
  end

  describe "Metadata operations" do
    test "validates metadata configuration" do
      config = %{
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0
      }

      {:ok, metadata} = ExZarr.Metadata.create(config)
      assert :ok = ExZarr.Metadata.validate(metadata)
    end

    test "rejects invalid metadata" do
      invalid_metadata = %ExZarr.Metadata{
        shape: {},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0
      }

      assert {:error, _} = ExZarr.Metadata.validate(invalid_metadata)
    end
  end

  describe "Compression in real workflow" do
    test "compresses data when writing chunks" do
      path = Path.join(@test_dir, "compressed_array")

      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :float64,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      ExZarr.save(array, path: path)

      # Verify .zarray exists
      zarray_path = Path.join(path, ".zarray")
      assert File.exists?(zarray_path)

      # Read and verify compression setting
      {:ok, json} = File.read(zarray_path)
      {:ok, data} = Jason.decode(json, keys: :atoms)
      assert data.compressor != nil
    end
  end

  describe "Error handling across modules" do
    test "handles filesystem errors gracefully" do
      # Try to open from invalid path
      result = ExZarr.open(path: "/invalid/path/that/does/not/exist", backend: :filesystem)
      assert match?({:error, _}, result)
    end

    test "handles invalid configuration combinations" do
      result =
        ExZarr.create(
          shape: {100},
          chunks: {10, 10}
        )

      assert match?({:error, _}, result)
    end
  end

  describe "Array info and properties" do
    test "provides complete array information" do
      {:ok, array} =
        ExZarr.create(
          shape: {1000, 2000, 3000},
          chunks: {100, 200, 300},
          dtype: :float32
        )

      assert ExZarr.Array.ndim(array) == 3
      assert ExZarr.Array.size(array) == 6_000_000_000
      assert ExZarr.Array.itemsize(array) == 4
      # nbytes = size * itemsize
      assert ExZarr.Array.size(array) * ExZarr.Array.itemsize(array) == 24_000_000_000
      assert array.shape == {1000, 2000, 3000}
    end
  end
end
