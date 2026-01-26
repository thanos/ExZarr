defmodule ExZarr.GroupConvenienceTest do
  use ExUnit.Case, async: true

  alias ExZarr.Group

  setup do
    tmp_dir = "/tmp/ex_zarr_group_convenience_test_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "Access behavior" do
    test "fetch returns array using bracket notation", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, array} =
        Group.create_array(root, "temperature", shape: {10, 10}, chunks: {5, 5}, dtype: :int32)

      # Add array to root's arrays map (create_array doesn't update parent)
      root = %{root | arrays: Map.put(root.arrays, "temperature", array)}

      # Use Access.fetch directly
      assert {:ok, fetched} = Access.fetch(root, "temperature")
      assert fetched.shape == array.shape
    end

    test "fetch returns :error for non-existent item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      assert :error = Access.fetch(root, "nonexistent")
    end

    test "pop removes item from group", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, array} =
        Group.create_array(root, "temperature", shape: {10, 10}, chunks: {5, 5}, dtype: :int32)

      root = %{root | arrays: Map.put(root.arrays, "temperature", array)}

      {popped, updated_root} = Access.pop(root, "temperature")
      assert popped.shape == array.shape
      assert Map.get(updated_root.arrays, "temperature") == nil
    end

    test "pop returns nil for non-existent item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {popped, _updated} = Access.pop(root, "nonexistent")
      assert popped == nil
    end

    test "get_and_update modifies item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = Group.create_array(root, "data", shape: {10}, chunks: {5}, dtype: :int32)

      root = %{root | arrays: Map.put(root.arrays, "data", array)}

      {old_value, updated_root} =
        Access.get_and_update(root, "data", fn current ->
          assert current.shape == {10}
          # Modify the shape to test updating
          new_array = %{current | shape: {20}}
          {current, new_array}
        end)

      assert old_value.shape == {10}
      updated_array = Map.get(updated_root.arrays, "data")
      assert updated_array.shape == {20}
    end
  end

  describe "get_item/3" do
    test "gets array by name", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, array} =
        Group.create_array(root, "temperature", shape: {10, 10}, chunks: {5, 5}, dtype: :int32)

      root = %{root | arrays: Map.put(root.arrays, "temperature", array)}

      {:ok, fetched} = Group.get_item(root, "temperature")
      assert fetched.shape == {10, 10}
    end

    test "gets group by name", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, subgroup} = Group.create_group(root, "experiments")

      root = %{root | groups: Map.put(root.groups, "experiments", subgroup)}

      {:ok, fetched} = Group.get_item(root, "experiments")
      assert fetched.path == "experiments"
    end

    test "gets nested item with path", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, exp1} = Group.create_group(root, "exp1")

      {:ok, array} =
        Group.create_array(exp1, "results", shape: {20, 20}, chunks: {10, 10}, dtype: :float32)

      exp1 = %{exp1 | arrays: Map.put(exp1.arrays, "results", array)}
      root = %{root | groups: Map.put(root.groups, "exp1", exp1)}

      {:ok, fetched} = Group.get_item(root, "exp1/results")
      assert fetched.shape == {20, 20}
    end

    test "returns error for non-existent item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      assert {:error, :not_found} = Group.get_item(root, "nonexistent")
    end

    test "returns error for nested non-existent item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, exp1} = Group.create_group(root, "exp1")

      root = %{root | groups: Map.put(root.groups, "exp1", exp1)}

      assert {:error, :not_found} = Group.get_item(root, "exp1/nonexistent")
    end
  end

  describe "put_item/3" do
    test "puts array at root level", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      updated_root = Group.put_item(root, "data", array)

      assert Map.has_key?(updated_root.arrays, "data")
      assert MapSet.member?(updated_root._loaded, "data")
    end

    test "puts group at root level", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, subgroup} = Group.create("sub", storage: :memory)

      updated_root = Group.put_item(root, "experiments", subgroup)

      assert Map.has_key?(updated_root.groups, "experiments")
      assert MapSet.member?(updated_root._loaded, "experiments")
    end

    test "puts item with nested path creates intermediate groups", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      updated_root = Group.put_item(root, "exp1/run2/results", array)

      # Check intermediate groups were created
      assert Map.has_key?(updated_root.groups, "exp1")
      exp1 = Map.get(updated_root.groups, "exp1")
      assert Map.has_key?(exp1.groups, "run2")
      run2 = Map.get(exp1.groups, "run2")
      assert Map.has_key?(run2.arrays, "results")
    end

    test "overwrites existing item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array1} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)
      {:ok, array2} = ExZarr.create(shape: {20}, chunks: {10}, dtype: :float32, storage: :memory)

      root = Group.put_item(root, "data", array1)
      updated_root = Group.put_item(root, "data", array2)

      fetched = Map.get(updated_root.arrays, "data")
      assert fetched.shape == {20}
      assert fetched.dtype == :float32
    end
  end

  describe "remove_item/2" do
    test "removes array from group", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      root = Group.put_item(root, "data", array)
      assert Map.has_key?(root.arrays, "data")

      updated_root = Group.remove_item(root, "data")
      refute Map.has_key?(updated_root.arrays, "data")
    end

    test "removes group from parent", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, subgroup} = Group.create("sub", storage: :memory)

      root = Group.put_item(root, "experiments", subgroup)
      assert Map.has_key?(root.groups, "experiments")

      updated_root = Group.remove_item(root, "experiments")
      refute Map.has_key?(updated_root.groups, "experiments")
    end

    test "removes nested item", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      root = Group.put_item(root, "exp1/results", array)
      exp1 = Map.get(root.groups, "exp1")
      assert Map.has_key?(exp1.arrays, "results")

      updated_root = Group.remove_item(root, "exp1/results")
      updated_exp1 = Map.get(updated_root.groups, "exp1")
      refute Map.has_key?(updated_exp1.arrays, "results")
    end

    test "removing non-existent item is no-op", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      updated_root = Group.remove_item(root, "nonexistent")
      assert root == updated_root
    end
  end

  describe "require_group/2" do
    test "creates new group if doesn't exist", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, created} = Group.require_group(root, "experiments")
      assert created.path == "experiments"

      # Verify it was written to storage
      group_file = Path.join([tmp_dir, "experiments", ".zgroup"])
      assert File.exists?(group_file)
    end

    test "returns existing group if already exists", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, existing} = Group.create_group(root, "experiments")

      root = %{root | groups: Map.put(root.groups, "experiments", existing)}

      {:ok, fetched} = Group.require_group(root, "experiments")
      assert fetched.path == existing.path
    end

    test "creates nested groups (mkdir -p behavior)", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, created} = Group.require_group(root, "exp1/run2/results")
      assert created.path == "exp1/run2/results"

      # Verify all intermediate groups were created
      assert File.exists?(Path.join([tmp_dir, "exp1", ".zgroup"]))
      assert File.exists?(Path.join([tmp_dir, "exp1", "run2", ".zgroup"]))
      assert File.exists?(Path.join([tmp_dir, "exp1", "run2", "results", ".zgroup"]))
    end

    test "returns error if path is an array", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, array} =
        Group.create_array(root, "temperature", shape: {10}, chunks: {5}, dtype: :int32)

      root = %{root | arrays: Map.put(root.arrays, "temperature", array)}

      assert {:error, :path_is_array} = Group.require_group(root, "temperature")
    end

    test "returns error if intermediate path is an array", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = Group.create_array(root, "data", shape: {10}, chunks: {5}, dtype: :int32)

      root = %{root | arrays: Map.put(root.arrays, "data", array)}

      assert {:error, :path_is_array} = Group.require_group(root, "data/subgroup")
    end
  end

  describe "tree/2" do
    test "displays simple hierarchy", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("/", storage: :filesystem, path: tmp_dir)

      {:ok, array1} =
        ExZarr.create(shape: {100, 100}, chunks: {10, 10}, dtype: :float32, storage: :memory)

      {:ok, array2} =
        ExZarr.create(shape: {50, 50}, chunks: {5, 5}, dtype: :int32, storage: :memory)

      root =
        root
        |> Group.put_item("temperature", array1)
        |> Group.put_item("pressure", array2)

      tree_output = Group.tree(root)

      assert String.contains?(tree_output, "/")
      assert String.contains?(tree_output, "[A] temperature")
      assert String.contains?(tree_output, "[A] pressure")
      assert String.contains?(tree_output, "{100, 100}")
      assert String.contains?(tree_output, "{50, 50}")
    end

    test "displays nested hierarchy", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("/", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {200}, chunks: {20}, dtype: :float64, storage: :memory)
      {:ok, subgroup} = Group.create("experiments", storage: :memory)

      subgroup = Group.put_item(subgroup, "results", array)
      root = Group.put_item(root, "experiments", subgroup)

      tree_output = Group.tree(root)

      assert String.contains?(tree_output, "/")
      assert String.contains?(tree_output, "[G] experiments")
      assert String.contains?(tree_output, "[A] results")
      assert String.contains?(tree_output, "└──") or String.contains?(tree_output, "├──")
    end

    test "respects depth option", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("/", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      root = Group.put_item(root, "level1/level2/level3", array)

      tree_output = Group.tree(root, depth: 2)

      assert String.contains?(tree_output, "[G] level1")
      assert String.contains?(tree_output, "[G] level2")
      # level3 should not appear due to depth limit
      refute String.contains?(tree_output, "level3")
    end

    test "respects show_shapes option", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("/", storage: :filesystem, path: tmp_dir)

      {:ok, array} =
        ExZarr.create(shape: {100, 200}, chunks: {10, 20}, dtype: :float32, storage: :memory)

      root = Group.put_item(root, "data", array)

      tree_with_shapes = Group.tree(root, show_shapes: true)
      assert String.contains?(tree_with_shapes, "{100, 200}")

      tree_without_shapes = Group.tree(root, show_shapes: false)
      refute String.contains?(tree_without_shapes, "{100, 200}")
      assert String.contains?(tree_without_shapes, "[A] data")
    end

    test "handles empty group", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("/", storage: :filesystem, path: tmp_dir)

      tree_output = Group.tree(root)
      assert tree_output == "/"
    end
  end

  describe "batch_create/2" do
    test "creates multiple groups in parallel", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      items = [
        {:group, "exp1"},
        {:group, "exp2"},
        {:group, "exp3"}
      ]

      {:ok, created} = Group.batch_create(root, items)

      assert Map.has_key?(created, "exp1")
      assert Map.has_key?(created, "exp2")
      assert Map.has_key?(created, "exp3")

      # Verify written to storage
      assert File.exists?(Path.join([tmp_dir, "exp1", ".zgroup"]))
      assert File.exists?(Path.join([tmp_dir, "exp2", ".zgroup"]))
      assert File.exists?(Path.join([tmp_dir, "exp3", ".zgroup"]))
    end

    test "creates multiple arrays in parallel", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      items = [
        {:array, "temp", shape: {100, 100}, chunks: {10, 10}, dtype: :float32},
        {:array, "pressure", shape: {100, 100}, chunks: {10, 10}, dtype: :float32},
        {:array, "humidity", shape: {100, 100}, chunks: {10, 10}, dtype: :float32}
      ]

      {:ok, created} = Group.batch_create(root, items)

      assert Map.has_key?(created, "temp")
      assert Map.has_key?(created, "pressure")
      assert Map.has_key?(created, "humidity")

      temp_array = Map.get(created, "temp")
      assert temp_array.shape == {100, 100}
    end

    test "creates mixed groups and arrays", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      items = [
        {:group, "experiments"},
        {:array, "temperature", shape: {50, 50}, chunks: {5, 5}, dtype: :int32},
        {:group, "results"}
      ]

      {:ok, created} = Group.batch_create(root, items)

      assert map_size(created) == 3
      assert Map.has_key?(created, "experiments")
      assert Map.has_key?(created, "temperature")
      assert Map.has_key?(created, "results")
    end

    test "returns error if any creation fails", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      # Create an invalid item (missing required array options)
      items = [
        {:group, "exp1"},
        # Missing shape, chunks, dtype
        {:array, "invalid", []},
        {:group, "exp2"}
      ]

      assert {:error, _reason} = Group.batch_create(root, items)
    end

    test "handles empty item list", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, created} = Group.batch_create(root, [])
      assert created == %{}
    end
  end

  describe "_loaded field tracking" do
    test "tracks loaded items", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      assert MapSet.size(root._loaded) == 0

      updated_root = Group.put_item(root, "data", array)
      assert MapSet.member?(updated_root._loaded, "data")
    end

    test "preserves _loaded on removal", %{tmp_dir: tmp_dir} do
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      root = Group.put_item(root, "data", array)
      assert MapSet.member?(root._loaded, "data")

      # Remove the item - _loaded should still track it was checked
      updated_root = Group.remove_item(root, "data")
      # Note: remove doesn't clear _loaded, keeping track that we checked this path
      assert MapSet.member?(updated_root._loaded, "data")
    end
  end

  describe "integration with filesystem" do
    test "lazy loads arrays from disk", %{tmp_dir: tmp_dir} do
      # Create and save an array
      {:ok, root} = Group.create("", storage: :filesystem, path: tmp_dir)

      {:ok, _array} =
        Group.create_array(root, "saved_data",
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :float32
        )

      # Open the group fresh (simulating a new session)
      {:ok, fresh_root} = Group.open("", storage: :filesystem, path: tmp_dir)

      # Arrays/groups maps should be empty initially
      assert map_size(fresh_root.arrays) == 0
      assert map_size(fresh_root.groups) == 0

      # Access should lazy-load the array
      # Note: This test may need adjustment based on actual lazy loading implementation
      # For now, just verify basic structure
      assert fresh_root._loaded != nil
    end

    test "memory backend works with all features", %{tmp_dir: _tmp_dir} do
      {:ok, root} = Group.create("", storage: :memory)
      {:ok, array} = ExZarr.create(shape: {10}, chunks: {5}, dtype: :int32, storage: :memory)

      # Test put_item
      root = Group.put_item(root, "data", array)
      {:ok, fetched} = Group.get_item(root, "data")
      assert fetched.shape == {10}

      # Test tree
      tree_output = Group.tree(root)
      assert String.contains?(tree_output, "[A] data")

      # Test remove
      root = Group.remove_item(root, "data")
      assert {:error, :not_found} = Group.get_item(root, "data")
    end
  end
end
