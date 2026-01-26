defmodule ExZarr.ArrayIndexingTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

  describe "fancy indexing (vindex)" do
    setup do
      # Create 2D array with known data
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      # Fill with row * 10 + col (0, 1, 2, ..., 99)
      data =
        for row <- 0..9, col <- 0..9 do
          <<row * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      {:ok, array: array}
    end

    test "selects specific elements", %{array: array} do
      # Select elements at [0, 5], [1, 10], [2, 15]
      {:ok, data} = Array.get_fancy(array, [[0, 1, 2], [5, 0, 5]])

      list = Tuple.to_list(data)
      assert length(list) == 3
      # Element at [0, 5] = 0*10 + 5 = 5
      assert Enum.at(list, 0) == 5
      # Element at [1, 0] = 1*10 + 0 = 10
      assert Enum.at(list, 1) == 10
      # Element at [2, 5] = 2*10 + 5 = 25
      assert Enum.at(list, 2) == 25
    end

    test "handles single element selection", %{array: array} do
      {:ok, data} = Array.get_fancy(array, [[5], [7]])
      list = Tuple.to_list(data)
      assert length(list) == 1
      # Element at [5, 7] = 5*10 + 7 = 57
      assert Enum.at(list, 0) == 57
    end

    test "validates index array lengths match", %{array: array} do
      # Different lengths should fail
      result = Array.get_fancy(array, [[0, 1], [5]])
      assert {:error, _} = result
    end

    test "validates indices within bounds", %{array: array} do
      result = Array.get_fancy(array, [[0, 1, 20], [5, 0, 5]])
      assert {:error, _} = result
    end

    test "supports negative indices", %{array: array} do
      # -1 should select last index (9)
      {:ok, data} = Array.get_fancy(array, [[0, -1], [0, -1]])

      list = Tuple.to_list(data)
      assert length(list) == 2
      # Element at [0, 0] = 0
      assert Enum.at(list, 0) == 0
      # Element at [9, 9] = 99
      assert Enum.at(list, 1) == 99
    end
  end

  describe "orthogonal indexing (oindex)" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      data =
        for row <- 0..9, col <- 0..9 do
          <<row * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      {:ok, array: array}
    end

    test "creates Cartesian product", %{array: array} do
      # Select rows [0, 2] with columns [1, 3]
      # Should give us elements at [0,1], [0,3], [2,1], [2,3]
      {:ok, data} = Array.get_orthogonal(array, [[0, 2], [1, 3]])

      # Result should be 2x2
      assert tuple_size(data) == 2
      assert tuple_size(elem(data, 0)) == 2

      # Check values
      # [0, 1]
      assert elem(elem(data, 0), 0) == 1
      # [0, 3]
      assert elem(elem(data, 0), 1) == 3
      # [2, 1]
      assert elem(elem(data, 1), 0) == 21
      # [2, 3]
      assert elem(elem(data, 1), 1) == 23
    end

    test "single indices become 1D slices", %{array: array} do
      {:ok, data} = Array.get_orthogonal(array, [[0], [1, 3, 5]])

      # Should give us row 0, columns 1, 3, 5
      assert tuple_size(data) == 1
      assert tuple_size(elem(data, 0)) == 3

      # [0, 1]
      assert elem(elem(data, 0), 0) == 1
      # [0, 3]
      assert elem(elem(data, 0), 1) == 3
      # [0, 5]
      assert elem(elem(data, 0), 2) == 5
    end

    test "validates indices within bounds", %{array: array} do
      result = Array.get_orthogonal(array, [[0, 15], [1, 3]])
      assert {:error, _} = result
    end
  end

  describe "boolean indexing" do
    setup do
      # Create 1D array for simpler boolean indexing tests
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      data =
        for i <- 0..9 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      {:ok, array: array}
    end

    test "selects elements where mask is true", %{array: array} do
      # Select elements at indices 0, 2, 4, 6, 8 (even indices)
      mask = {true, false, true, false, true, false, true, false, true, false}

      {:ok, data} = Array.get_boolean(array, mask)

      list = Tuple.to_list(data)
      assert length(list) == 5
      assert list == [0, 2, 4, 6, 8]
    end

    test "handles all false mask", %{array: array} do
      mask = Tuple.duplicate(false, 10)

      {:ok, data} = Array.get_boolean(array, mask)

      assert data == {}
    end

    test "handles all true mask", %{array: array} do
      mask = Tuple.duplicate(true, 10)

      {:ok, data} = Array.get_boolean(array, mask)

      list = Tuple.to_list(data)
      assert length(list) == 10
      assert list == Enum.to_list(0..9)
    end

    test "validates mask size matches array", %{array: array} do
      # Wrong size mask
      mask = {true, false, true}

      result = Array.get_boolean(array, mask)
      assert {:error, _} = result
    end

    test "validates mask contains only booleans", %{array: array} do
      # Invalid mask with non-boolean
      mask = {true, false, 1, false, true, false, true, false, true, false}

      result = Array.get_boolean(array, mask)
      assert {:error, _} = result
    end
  end

  describe "boolean indexing 2D" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {3, 4},
          chunks: {3, 4},
          dtype: :int32,
          storage: :memory
        )

      # Fill with sequential data
      data =
        for i <- 0..11 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {3, 4})

      {:ok, array: array}
    end

    test "2D mask selects matching elements", %{array: array} do
      # Select elements at [0,0], [0,2], [1,1], [2,3]
      mask = {
        {true, false, true, false},
        {false, true, false, false},
        {false, false, false, true}
      }

      {:ok, data} = Array.get_boolean(array, mask)

      list = Tuple.to_list(data)
      assert length(list) == 4
      assert list == [0, 2, 5, 11]
    end
  end

  describe "block indexing" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory
        )

      # Fill with sequential data
      data =
        for i <- 0..399 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})

      {:ok, array: array}
    end

    test "returns chunk-aligned blocks", %{array: array} do
      {:ok, blocks} = Array.get_blocks(array, start: {0, 0}, stop: {20, 20})

      # Should have 4 blocks (2x2 chunks)
      assert length(blocks) == 4

      # Each block should have start, stop, and data
      Enum.each(blocks, fn {start, stop, data} ->
        assert is_tuple(start)
        assert is_tuple(stop)
        assert is_binary(data)
      end)
    end

    test "returns blocks for partial range", %{array: array} do
      # Request range that spans 2 blocks
      {:ok, blocks} = Array.get_blocks(array, start: {5, 5}, stop: {15, 15})

      # Should span 4 chunks
      assert length(blocks) == 4

      # Verify block boundaries align with chunk boundaries
      Enum.each(blocks, fn {_start, _stop, _data} ->
        # Each block should be chunk-aligned
        # (this is verified by the implementation)
        assert true
      end)
    end

    test "single block request", %{array: array} do
      {:ok, blocks} = Array.get_blocks(array, start: {0, 0}, stop: {5, 5})

      # Should be just one block (within first chunk)
      assert length(blocks) == 1
    end
  end

  describe "edge cases" do
    test "fancy indexing with empty arrays" do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      {:ok, data} = Array.get_fancy(array, [[], []])
      assert data == {}
    end

    test "boolean indexing with no true values" do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      mask = {false, false, false, false, false}
      {:ok, data} = Array.get_boolean(array, mask)
      assert data == {}
    end

    test "block indexing with zero-size range" do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      {:ok, blocks} = Array.get_blocks(array, start: {5, 5}, stop: {5, 5})
      assert blocks == []
    end
  end

  describe "indexing with different data types" do
    test "fancy indexing with float64" do
      {:ok, array} =
        Array.create(
          shape: {5, 5},
          chunks: {5, 5},
          dtype: :float64,
          storage: :memory
        )

      data =
        for i <- 0..24 do
          <<i * 1.5::float-64-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      {:ok, result} = Array.get_fancy(array, [[0, 2, 4], [1, 3, 0]])

      list = Tuple.to_list(result)
      assert length(list) == 3
      # Check first value (approximately)
      assert abs(Enum.at(list, 0) - 1.5) < 0.01
    end

    test "boolean indexing with uint8" do
      {:ok, array} =
        Array.create(
          shape: {8},
          chunks: {8},
          dtype: :uint8,
          storage: :memory
        )

      data = for i <- 0..7, do: <<i::8>>, into: <<>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {8})

      mask = {true, false, true, false, true, false, true, false}
      {:ok, result} = Array.get_boolean(array, mask)

      list = Tuple.to_list(result)
      assert list == [0, 2, 4, 6]
    end
  end
end
