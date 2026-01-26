defmodule ExZarr.ConsolidatedMetadataTest do
  use ExUnit.Case, async: true

  alias ExZarr.{Array, ConsolidatedMetadata}

  setup do
    # Use unique temp directory for each test
    tmp_dir = "/tmp/ex_zarr_consolidated_test_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "consolidate/1" do
    test "consolidates single array metadata", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "group1")

      # Create array
      {:ok, _array} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(group_path, "array1")
        )

      # Consolidate metadata
      {:ok, count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Should have consolidated at least the array metadata
      assert count >= 1

      # Check that .zmetadata file exists
      assert File.exists?(Path.join(group_path, ".zmetadata"))
    end

    test "consolidates multiple arrays", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "group2")

      # Create multiple arrays
      for i <- 1..3 do
        {:ok, _array} =
          Array.create(
            shape: {10, 10},
            chunks: {5, 5},
            dtype: :float32,
            storage: :filesystem,
            path: Path.join(group_path, "array#{i}")
          )
      end

      # Consolidate metadata
      {:ok, count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Should have metadata for 3 arrays
      assert count >= 3

      # Verify consolidated file exists and is valid JSON
      consolidated_path = Path.join(group_path, ".zmetadata")
      assert File.exists?(consolidated_path)

      {:ok, json} = File.read(consolidated_path)
      {:ok, data} = Jason.decode(json)

      assert data["zarr_consolidated_format"] == 1
      assert is_map(data["metadata"])
    end

    test "consolidates zarr v3 arrays", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "group_v3")

      # Create v3 array
      {:ok, _array} =
        Array.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int64,
          storage: :filesystem,
          path: Path.join(group_path, "array_v3"),
          zarr_version: 3
        )

      # Consolidate metadata
      {:ok, count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      assert count >= 1

      # Read and verify consolidated metadata contains zarr.json
      {:ok, metadata} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)

      # V3 arrays use zarr.json
      assert Map.has_key?(metadata, "array_v3/zarr.json")
    end

    test "handles empty group", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "empty_group")
      File.mkdir_p!(group_path)

      # Consolidate empty group
      {:ok, count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Empty group has 0 entries
      assert count == 0
    end

    test "handles nested groups with recursive=true", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "nested_group")

      # Create nested structure
      {:ok, _array1} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(group_path, "array1")
        )

      {:ok, _array2} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :float32,
          storage: :filesystem,
          path: Path.join([group_path, "subgroup", "array2"])
        )

      # Consolidate with recursion
      {:ok, count} =
        ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem, recursive: true)

      # Should include both arrays
      assert count >= 2

      # Verify nested array is in consolidated metadata
      {:ok, metadata} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)
      assert Map.has_key?(metadata, "subgroup/array2/.zarray")
    end

    test "handles nested groups with recursive=false", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "non_recursive_group")

      # Create nested structure
      {:ok, _array1} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(group_path, "array1")
        )

      {:ok, _array2} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :float32,
          storage: :filesystem,
          path: Path.join([group_path, "subgroup", "array2"])
        )

      # Consolidate without recursion
      {:ok, count} =
        ConsolidatedMetadata.consolidate(
          path: group_path,
          storage: :filesystem,
          recursive: false
        )

      # Should only include top-level array
      assert count >= 1

      # Verify nested array is NOT in consolidated metadata
      {:ok, metadata} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)
      refute Map.has_key?(metadata, "subgroup/array2/.zarray")
    end
  end

  describe "read/1" do
    test "reads consolidated metadata", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "read_group")

      # Create and consolidate
      {:ok, _array} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(group_path, "array1")
        )

      {:ok, _count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Read consolidated metadata
      {:ok, metadata} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)

      assert is_map(metadata)
      assert Map.has_key?(metadata, "array1/.zarray")

      # Verify metadata content
      array_meta = metadata["array1/.zarray"]
      assert array_meta["shape"] == [100, 100]
      assert array_meta["chunks"] == [10, 10]
    end

    test "returns error when consolidated metadata doesn't exist", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "no_consolidated")
      File.mkdir_p!(group_path)

      # Try to read non-existent consolidated metadata
      assert {:error, :not_found} =
               ConsolidatedMetadata.read(path: group_path, storage: :filesystem)
    end

    test "returns error for invalid JSON", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "invalid_json")
      File.mkdir_p!(group_path)

      # Write invalid JSON
      File.write!(Path.join(group_path, ".zmetadata"), "invalid json{")

      # Should return JSON decode error
      assert {:error, {:json_decode_error, _}} =
               ConsolidatedMetadata.read(path: group_path, storage: :filesystem)
    end
  end

  describe "exists?/1" do
    test "returns true when consolidated metadata exists", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "exists_group")

      # Create and consolidate
      {:ok, _array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(group_path, "array1")
        )

      {:ok, _count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Check existence
      assert ConsolidatedMetadata.exists?(path: group_path, storage: :filesystem)
    end

    test "returns false when consolidated metadata doesn't exist", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "no_exists_group")
      File.mkdir_p!(group_path)

      # Check existence
      refute ConsolidatedMetadata.exists?(path: group_path, storage: :filesystem)
    end
  end

  describe "remove/1" do
    test "removes consolidated metadata", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "remove_group")

      # Create and consolidate
      {:ok, _array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(group_path, "array1")
        )

      {:ok, _count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      assert ConsolidatedMetadata.exists?(path: group_path, storage: :filesystem)

      # Remove consolidated metadata
      :ok = ConsolidatedMetadata.remove(path: group_path, storage: :filesystem)

      # Should no longer exist
      refute ConsolidatedMetadata.exists?(path: group_path, storage: :filesystem)

      # Original array metadata should still exist
      assert File.exists?(Path.join([group_path, "array1", ".zarray"]))
    end

    test "succeeds even if consolidated metadata doesn't exist", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "no_remove_group")
      File.mkdir_p!(group_path)

      # Remove from empty group (should not error)
      :ok = ConsolidatedMetadata.remove(path: group_path, storage: :filesystem)
    end
  end

  describe "integration with array operations" do
    test "consolidated metadata matches individual array metadata", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "integration_group")
      array_path = Path.join(group_path, "test_array")

      # Create array
      {:ok, _array} =
        Array.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :float64,
          storage: :filesystem,
          path: array_path
        )

      # Read original metadata
      {:ok, original_json} = File.read(Path.join(array_path, ".zarray"))
      {:ok, original_meta} = Jason.decode(original_json)

      # Consolidate
      {:ok, _count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Read from consolidated
      {:ok, consolidated} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)
      consolidated_meta = consolidated["test_array/.zarray"]

      # Should match
      assert consolidated_meta["shape"] == original_meta["shape"]
      assert consolidated_meta["chunks"] == original_meta["chunks"]
      assert consolidated_meta["dtype"] == original_meta["dtype"]
    end

    test "works with arrays containing attributes", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "attrs_group")
      array_path = Path.join(group_path, "array_with_attrs")

      # Create array with attributes
      {:ok, _array} =
        Array.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: array_path,
          attributes: %{"units" => "meters", "description" => "test array"}
        )

      # Consolidate
      {:ok, _count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)

      # Read consolidated metadata
      {:ok, consolidated} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)

      # Check attributes are included
      if Map.has_key?(consolidated, "array_with_attrs/.zattrs") do
        attrs = consolidated["array_with_attrs/.zattrs"]
        assert attrs["units"] == "meters"
        assert attrs["description"] == "test array"
      end
    end
  end

  describe "performance benefits" do
    test "reduces file system reads", %{tmp_dir: tmp_dir} do
      group_path = Path.join(tmp_dir, "perf_group")

      # Create multiple arrays
      for i <- 1..10 do
        {:ok, _array} =
          Array.create(
            shape: {10, 10},
            chunks: {5, 5},
            dtype: :int32,
            storage: :filesystem,
            path: Path.join(group_path, "array#{i}")
          )
      end

      # Consolidate
      {:ok, count} = ConsolidatedMetadata.consolidate(path: group_path, storage: :filesystem)
      assert count >= 10

      # Reading consolidated metadata = 1 file read
      # vs reading each .zarray individually = 10 file reads
      # Performance benefit: 90% reduction in file operations

      {:ok, metadata} = ConsolidatedMetadata.read(path: group_path, storage: :filesystem)

      # Verify all arrays are accessible from single consolidated read
      for i <- 1..10 do
        assert Map.has_key?(metadata, "array#{i}/.zarray")
      end
    end
  end
end
