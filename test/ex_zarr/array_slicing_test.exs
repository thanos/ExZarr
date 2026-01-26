defmodule ExZarr.ArraySlicingTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

  describe "basic slicing" do
    setup do
      # Create test array with known data
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      # Fill with sequential data: 0, 1, 2, ..., 99
      data =
        for i <- 0..99 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      {:ok, array: array}
    end

    test "reads full array", %{array: array} do
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert is_binary(data)
      # 10x10 array with int32 elements = 400 bytes
      assert byte_size(data) == 400
      # Verify first element (4 bytes)
      <<first::32-little, _::binary>> = data
      assert first == 0
      # Verify last element
      <<_::binary-size(396), last::32-little>> = data
      assert last == 99
    end

    test "reads subset", %{array: array} do
      {:ok, data} = Array.get_slice(array, start: {2, 3}, stop: {5, 7})
      assert is_binary(data)
      # 3x4 array with int32 elements = 48 bytes
      assert byte_size(data) == 48
      # Element at [2, 3] in original array is 2*10 + 3 = 23
      <<first::32-little, _::binary>> = data
      assert first == 23
    end

    test "reads single element as 1x1 slice", %{array: array} do
      {:ok, data} = Array.get_slice(array, start: {5, 5}, stop: {6, 6})
      assert is_binary(data)
      # Single int32 element = 4 bytes
      assert byte_size(data) == 4
      <<value::32-little>> = data
      assert value == 55
    end

    test "handles out of bounds gracefully", %{array: array} do
      result = Array.get_slice(array, start: {0, 0}, stop: {20, 20})
      assert {:error, _} = result
    end

    test "handles empty slice", %{array: array} do
      {:ok, data} = Array.get_slice(array, start: {5, 5}, stop: {5, 5})
      # Empty slice returns empty binary
      assert data == <<>>
    end
  end

  describe "step slicing with map format" do
    setup do
      # Create 1D array for easier step testing
      {:ok, array} =
        Array.create(
          shape: {20},
          chunks: {10},
          dtype: :int32,
          storage: :memory
        )

      # Fill with 0, 1, 2, ..., 19
      data =
        for i <- 0..19 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {20})

      {:ok, array: array}
    end

    test "step of 2", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 0},
          stop: %{0 => 20},
          step: 2
        )

      list = Tuple.to_list(data)
      assert length(list) == 10
      assert list == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
    end

    test "step of 3", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 0},
          stop: %{0 => 20},
          step: 3
        )

      list = Tuple.to_list(data)
      assert length(list) == 7
      assert list == [0, 3, 6, 9, 12, 15, 18]
    end

    test "step of 5 with partial last step", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 0},
          stop: %{0 => 19},
          step: 5
        )

      list = Tuple.to_list(data)
      assert length(list) == 4
      assert list == [0, 5, 10, 15]
    end

    test "negative step for reverse", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 19},
          stop: %{0 => -1},
          step: -1
        )

      list = Tuple.to_list(data)
      assert length(list) == 20
      assert list == Enum.to_list(19..0//-1)
    end

    test "negative step of -2", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 19},
          stop: %{0 => -1},
          step: -2
        )

      list = Tuple.to_list(data)
      assert length(list) == 10
      assert list == [19, 17, 15, 13, 11, 9, 7, 5, 3, 1]
    end
  end

  describe "negative indices with map format" do
    setup do
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

    test "negative start index", %{array: array} do
      # -3 means index 7 (10 - 3)
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => -3},
          stop: %{0 => 10}
        )

      assert is_binary(data)
      # 3 int32 elements
      assert byte_size(data) == 12
      # Decode and verify
      <<v1::32-little, v2::32-little, v3::32-little>> = data
      assert [v1, v2, v3] == [7, 8, 9]
    end

    test "negative stop index", %{array: array} do
      # Stop at -2 means stop at index 8 (10 - 2)
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 0},
          stop: %{0 => -2}
        )

      assert is_binary(data)
      # 8 int32 elements
      assert byte_size(data) == 32
      # Decode and verify
      values = for <<v::32-little <- data>>, do: v
      assert values == [0, 1, 2, 3, 4, 5, 6, 7]
    end

    test "both negative indices", %{array: array} do
      # Start at -5 (index 5), stop at -1 (index 9)
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => -5},
          stop: %{0 => -1}
        )

      assert is_binary(data)
      # 4 int32 elements
      assert byte_size(data) == 16
      values = for <<v::32-little <- data>>, do: v
      assert values == [5, 6, 7, 8]
    end

    test "negative index -1 selects last element", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => -1},
          stop: %{0 => 10}
        )

      assert is_binary(data)
      # 1 int32 element
      assert byte_size(data) == 4
      <<value::32-little>> = data
      assert value == 9
    end
  end

  describe "2D step slicing" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      # Fill with row * 10 + col
      data =
        for row <- 0..9, col <- 0..9 do
          <<row * 10 + col::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      {:ok, array: array}
    end

    test "step in one dimension", %{array: array} do
      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 0, 1 => 0},
          stop: %{0 => 10, 1 => 10},
          step: 2
        )

      # Step applies to first dimension by default
      assert tuple_size(data) == 5

      # Check first row (row 0)
      first_row = elem(data, 0)
      assert tuple_size(first_row) == 10
      assert elem(first_row, 0) == 0
      assert elem(first_row, 9) == 9

      # Check second row (row 2)
      second_row = elem(data, 1)
      assert elem(second_row, 0) == 20
    end
  end

  describe "step with set_slice" do
    setup do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          fill_value: 0,
          storage: :memory
        )

      {:ok, array: array}
    end

    test "writes with step of 2", %{array: array} do
      # Write values 100, 101, 102, 103, 104 at indices 0, 2, 4, 6, 8
      data =
        for i <- 100..104 do
          <<i::32-little>>
        end
        |> IO.iodata_to_binary()

      :ok =
        Array.set_slice(array, data,
          start: %{0 => 0},
          stop: %{0 => 10},
          step: 2
        )

      # Read back entire array (returns binary)
      {:ok, result} = Array.get_slice(array, start: {0}, stop: {10})
      assert is_binary(result)

      # Decode binary to list of values
      list = for <<v::32-little <- result>>, do: v

      # Stepped positions should have our values, others should be fill_value (0)
      assert Enum.at(list, 0) == 100
      assert Enum.at(list, 1) == 0
      assert Enum.at(list, 2) == 101
      assert Enum.at(list, 3) == 0
      assert Enum.at(list, 4) == 102
      assert Enum.at(list, 5) == 0
      assert Enum.at(list, 6) == 103
      assert Enum.at(list, 7) == 0
      assert Enum.at(list, 8) == 104
      assert Enum.at(list, 9) == 0
    end
  end

  describe "edge cases" do
    test "step of 0 returns error" do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      result =
        Array.get_slice(array,
          start: %{0 => 0},
          stop: %{0 => 10},
          step: 0
        )

      assert {:error, _} = result
    end

    test "start > stop with positive step returns error" do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      result =
        Array.get_slice(array,
          start: %{0 => 5},
          stop: %{0 => 2},
          step: 1
        )

      # Invalid range should return error
      assert {:error, {:invalid_range, _}} = result
    end

    test "start < stop with negative step returns empty" do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      {:ok, data} =
        Array.get_slice(array,
          start: %{0 => 2},
          stop: %{0 => 5},
          step: -1
        )

      assert data == {}
    end
  end

  describe "backward compatibility" do
    test "keyword list format still works" do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      # Old format should still work and return binary
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert is_binary(data)
      # 5x5 array with int32 elements = 100 bytes
      assert byte_size(data) == 100
    end

    test "keyword list format rejects negative indices" do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      # Negative indices not supported in keyword format (backward compat)
      result = Array.get_slice(array, start: {-1}, stop: {10})
      assert {:error, _} = result
    end
  end
end
