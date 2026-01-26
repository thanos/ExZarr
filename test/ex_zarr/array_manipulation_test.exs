defmodule ExZarr.ArrayManipulationTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

  describe "array resize - growing" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          fill_value: -1,
          storage: :memory
        )

      # Fill initial array with sequential data
      data =
        for i <- 0..99 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      {:ok, array: array}
    end

    test "grows array dimensions", %{array: array} do
      # Resize to 20x20
      {:ok, array} = Array.resize(array, {20, 20})

      # Check that shape is updated
      assert array.shape == {20, 20}

      # Original data should still be accessible
      {:ok, original_data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert is_binary(original_data)
      # 10x10 int32 = 400 bytes
      assert byte_size(original_data) == 400

      # Verify first and last elements of original data
      <<first::32-little, _::binary>> = original_data
      assert first == 0
      <<_::binary-size(396), last::32-little>> = original_data
      assert last == 99

      # New areas should have fill value (-1) when read
      {:ok, new_data} = Array.get_slice(array, start: {10, 10}, stop: {11, 11})
      <<fill::signed-32-little>> = new_data
      assert fill == -1
    end

    test "grows one dimension", %{array: array} do
      {:ok, array} = Array.resize(array, {10, 20})

      assert array.shape == {10, 20}

      # Original 10x10 section should be intact
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert is_binary(data)
      # 10x10 int32 = 400 bytes
      assert byte_size(data) == 400
    end

    test "can grow multiple times", %{array: array} do
      {:ok, array} = Array.resize(array, {15, 15})
      assert array.shape == {15, 15}

      {:ok, array} = Array.resize(array, {20, 20})
      assert array.shape == {20, 20}

      # Original data still accessible
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert is_binary(data)
      <<first::32-little, _::binary>> = data
      assert first == 0
    end
  end

  describe "array resize - shrinking" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory
        )

      # Fill array with sequential data
      data =
        for i <- 0..399 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})

      {:ok, array: array}
    end

    test "shrinks array dimensions", %{array: array} do
      {:ok, array} = Array.resize(array, {10, 10})

      assert array.shape == {10, 10}

      # Should still be able to read the kept portion
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert is_binary(data)
      # 10x10 int32 = 400 bytes
      assert byte_size(data) == 400

      # Verify data is correct
      <<first::32-little, _::binary>> = data
      assert first == 0
      <<_::binary-size(396), last::32-little>> = data
      assert last == 9 * 20 + 9
    end

    test "shrinks one dimension", %{array: array} do
      {:ok, array} = Array.resize(array, {20, 10})

      assert array.shape == {20, 10}

      # Can read 20x10 region
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {20, 10})
      assert is_binary(data)
      # 20x10 int32 = 800 bytes
      assert byte_size(data) == 800
    end

    test "shrinking deletes out-of-bounds chunks", %{array: array} do
      # Write data to a chunk that will be deleted
      data = <<999::32-little>>
      :ok = Array.set_slice(array, data, start: {15, 15}, stop: {16, 16})

      # Verify it's there
      {:ok, read_data} = Array.get_slice(array, start: {15, 15}, stop: {16, 16})
      <<value::32-little>> = read_data
      assert value == 999

      # Shrink array to exclude that chunk
      {:ok, array} = Array.resize(array, {10, 10})

      # Attempting to read beyond new bounds should fail
      result = Array.get_slice(array, start: {15, 15}, stop: {16, 16})
      assert {:error, _} = result
    end
  end

  describe "array resize - same size" do
    test "no-op for same shape" do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      {:ok, array} = Array.resize(array, {10, 10})

      # Should still work
      assert array.shape == {10, 10}
    end
  end

  describe "array resize - validation" do
    test "rejects invalid shapes" do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      # Wrong number of dimensions
      result = Array.resize(array, {10, 10, 10})
      assert {:error, _} = result

      # Negative dimensions
      result = Array.resize(array, {-10, 10})
      assert {:error, _} = result

      # Zero dimension
      result = Array.resize(array, {0, 10})
      assert {:error, _} = result
    end
  end

  describe "array append - 1D" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      # Fill with 0-9
      data =
        for i <- 0..9 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      {:ok, array: array}
    end

    test "appends data", %{array: array} do
      # Append 3 more elements: 10, 11, 12
      new_data =
        for i <- 10..12 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      {:ok, array} = Array.append(array, new_data, axis: 0)

      # Array should now be size 13
      assert array.shape == {13}

      # Read all data
      {:ok, all_data} = Array.get_slice(array, start: {0}, stop: {13})
      assert is_binary(all_data)
      list = for <<v::32-little <- all_data>>, do: v

      assert length(list) == 13
      assert list == Enum.to_list(0..12)
    end

    test "appends multiple times", %{array: array} do
      # First append
      {:ok, array} = Array.append(array, <<10::32-little, 11::32-little>>, axis: 0)
      assert array.shape == {12}

      # Second append
      {:ok, array} = Array.append(array, <<12::32-little>>, axis: 0)
      assert array.shape == {13}

      # Verify all data
      {:ok, data} = Array.get_slice(array, start: {0}, stop: {13})
      assert is_binary(data)
      list = for <<v::32-little <- data>>, do: v
      assert list == Enum.to_list(0..12)
    end

    test "appends single element", %{array: array} do
      {:ok, array} = Array.append(array, <<100::32-little>>, axis: 0)

      assert array.shape == {11}

      {:ok, data} = Array.get_slice(array, start: {10}, stop: {11})
      assert is_binary(data)
      <<value::32-little>> = data
      assert value == 100
    end
  end

  describe "array append - 2D" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {5, 10},
          chunks: {5, 10},
          dtype: :int32,
          storage: :memory
        )

      # Fill with row * 10 + col
      data =
        for row <- 0..4, col <- 0..9 do
          <<row * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 10})

      {:ok, array: array}
    end

    test "appends along axis 0 (adds rows)", %{array: array} do
      # Add 2 new rows: row 5 and row 6
      new_data =
        for row <- 5..6, col <- 0..9 do
          <<row * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      {:ok, array} = Array.append(array, new_data, axis: 0)

      # Shape should be {7, 10}
      assert array.shape == {7, 10}

      # Read new rows
      {:ok, data} = Array.get_slice(array, start: {5, 0}, stop: {7, 10})
      assert is_binary(data)
      # 2x10 int32 = 80 bytes
      assert byte_size(data) == 80

      # Verify first element of row 5
      <<first::32-little, _::binary>> = data
      assert first == 50
    end

    test "appends along axis 1 (adds columns)", %{array: array} do
      # Add 3 new columns
      new_data =
        for row <- 0..4, col <- 10..12 do
          <<row * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      {:ok, array} = Array.append(array, new_data, axis: 1)

      # Shape should be {5, 13}
      assert array.shape == {5, 13}

      # Read new columns
      {:ok, data} = Array.get_slice(array, start: {0, 10}, stop: {5, 13})
      assert is_binary(data)
      # 5x3 int32 = 60 bytes
      assert byte_size(data) == 60
    end

    test "default axis is 0", %{array: array} do
      # Append without specifying axis (should default to 0)
      new_data =
        for col <- 0..9 do
          <<5 * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      {:ok, array} = Array.append(array, new_data)

      assert array.shape == {6, 10}
    end
  end

  describe "array append - validation" do
    test "validates data size matches other dimensions" do
      {:ok, array} =
        Array.create(
          shape: {5, 10},
          chunks: {5, 10},
          dtype: :int32,
          storage: :memory
        )

      # Try to append data with wrong size (should be 10 elements for axis 0)
      wrong_data = <<1::32-little, 2::32-little, 3::32-little>>

      result = Array.append(array, wrong_data, axis: 0)
      assert {:error, _} = result
    end

    test "validates axis is valid" do
      {:ok, array} =
        Array.create(
          shape: {5, 10},
          chunks: {5, 10},
          dtype: :int32,
          storage: :memory
        )

      # Invalid axis (only 0 and 1 valid for 2D)
      result = Array.append(array, <<1::32-little>>, axis: 2)
      assert {:error, _} = result
    end

    test "validates data is binary" do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      result = Array.append(array, "not_binary", axis: 0)
      assert {:error, _} = result
    end
  end

  describe "combined operations" do
    test "resize then append" do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      # Fill with 0-4
      data = for i <- 0..4, do: <<i::32-little>>, into: <<>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {5})

      # Resize to 10
      {:ok, array} = Array.resize(array, {10})

      # Append 5 more elements
      new_data = for i <- 10..14, do: <<i::32-little>>, into: <<>>
      {:ok, array} = Array.append(array, new_data, axis: 0)

      # Should now be size 15
      assert array.shape == {15}

      # Read first 5 (original data)
      {:ok, original} = Array.get_slice(array, start: {0}, stop: {5})
      assert is_binary(original)
      list = for <<v::32-little <- original>>, do: v
      assert list == [0, 1, 2, 3, 4]

      # Read appended data
      {:ok, appended} = Array.get_slice(array, start: {10}, stop: {15})
      assert is_binary(appended)
      list = for <<v::32-little <- appended>>, do: v
      assert list == [10, 11, 12, 13, 14]
    end

    test "append multiple times then resize down" do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      data = for i <- 0..4, do: <<i::32-little>>, into: <<>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {5})

      # Append twice
      {:ok, array} = Array.append(array, <<5::32-little, 6::32-little>>, axis: 0)
      {:ok, array} = Array.append(array, <<7::32-little, 8::32-little>>, axis: 0)

      assert array.shape == {9}

      # Resize down to 7
      {:ok, array} = Array.resize(array, {7})

      assert array.shape == {7}

      # Verify data
      {:ok, result} = Array.get_slice(array, start: {0}, stop: {7})
      assert is_binary(result)
      list = for <<v::32-little <- result>>, do: v
      assert list == [0, 1, 2, 3, 4, 5, 6]
    end
  end
end
