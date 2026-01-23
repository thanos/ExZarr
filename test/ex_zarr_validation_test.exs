defmodule ExZarr.ValidationTest do
  use ExUnit.Case

  alias ExZarr.Array

  @moduledoc """
  Tests for index validation and bounds checking in array operations.

  These tests verify that:
  - Indices are validated for type, dimensionality, and range
  - Out-of-bounds access is properly rejected
  - Data size mismatches are detected
  - Clear error messages are provided
  """

  setup do
    # Create test arrays with different dimensions
    {:ok, array_1d} =
      ExZarr.create(
        shape: {100},
        chunks: {10},
        dtype: :int32,
        storage: :memory
      )

    {:ok, array_2d} =
      ExZarr.create(
        shape: {50, 50},
        chunks: {10, 10},
        dtype: :int32,
        storage: :memory
      )

    {:ok, array_3d} =
      ExZarr.create(
        shape: {20, 20, 20},
        chunks: {10, 10, 10},
        dtype: :float64,
        storage: :memory
      )

    %{array_1d: array_1d, array_2d: array_2d, array_3d: array_3d}
  end

  describe "get_slice validation" do
    test "rejects non-tuple indices", %{array_1d: array} do
      assert {:error, {:invalid_index, msg}} = Array.get_slice(array, start: [0], stop: [10])
      assert msg =~ "start must be a tuple"
    end

    test "rejects dimension mismatch for start", %{array_2d: array} do
      assert {:error, {:dimension_mismatch, msg}} =
               Array.get_slice(array, start: {0}, stop: {10, 10})

      assert msg =~ "start has 1 dimensions but array has 2 dimensions"
    end

    test "rejects dimension mismatch for stop", %{array_2d: array} do
      assert {:error, {:dimension_mismatch, msg}} =
               Array.get_slice(array, start: {0, 0}, stop: {10})

      assert msg =~ "stop has 1 dimensions but array has 2 dimensions"
    end

    test "rejects negative indices in start", %{array_1d: array} do
      assert {:error, {:invalid_index, msg}} = Array.get_slice(array, start: {-1}, stop: {10})
      assert msg =~ "start indices must be non-negative"
    end

    test "rejects negative indices in stop", %{array_1d: array} do
      assert {:error, {:invalid_index, msg}} = Array.get_slice(array, start: {0}, stop: {-1})
      assert msg =~ "stop indices must be non-negative"
    end

    test "rejects non-integer indices", %{array_1d: array} do
      assert {:error, {:invalid_index, msg}} =
               Array.get_slice(array, start: {0.5}, stop: {10})

      assert msg =~ "start indices must be non-negative integers"
    end

    test "rejects start > stop", %{array_1d: array} do
      assert {:error, {:invalid_range, msg}} = Array.get_slice(array, start: {10}, stop: {5})
      assert msg =~ "start must be <= stop"
      assert msg =~ "Dimension 0"
    end

    test "rejects start > stop in 2D", %{array_2d: array} do
      assert {:error, {:invalid_range, msg}} =
               Array.get_slice(array, start: {0, 10}, stop: {10, 5})

      assert msg =~ "Dimension 1"
    end

    test "rejects out of bounds stop index in 1D", %{array_1d: array} do
      assert {:error, {:out_of_bounds, msg}} = Array.get_slice(array, start: {0}, stop: {101})
      assert msg =~ "Index out of bounds in dimension 0"
      assert msg =~ "stop=101 exceeds shape=100"
    end

    test "rejects out of bounds stop index in 2D", %{array_2d: array} do
      assert {:error, {:out_of_bounds, msg}} =
               Array.get_slice(array, start: {0, 0}, stop: {10, 51})

      assert msg =~ "dimension 1"
      assert msg =~ "stop=51 exceeds shape=50"
    end

    test "rejects out of bounds in 3D", %{array_3d: array} do
      assert {:error, {:out_of_bounds, msg}} =
               Array.get_slice(array, start: {0, 0, 0}, stop: {10, 10, 25})

      assert msg =~ "dimension 2"
      assert msg =~ "stop=25 exceeds shape=20"
    end

    test "accepts valid indices at boundaries", %{array_1d: array} do
      # Should succeed - reading the entire array
      assert {:ok, _data} = Array.get_slice(array, start: {0}, stop: {100})
    end

    test "accepts valid empty slice", %{array_1d: array} do
      # Should succeed - zero-sized slice
      assert {:ok, data} = Array.get_slice(array, start: {10}, stop: {10})
      assert byte_size(data) == 0
    end
  end

  describe "set_slice validation" do
    test "rejects non-binary data", %{array_1d: array} do
      assert {:error, {:invalid_data, msg}} =
               Array.set_slice(array, [1, 2, 3], start: {0}, stop: {3})

      assert msg =~ "data must be binary"
    end

    test "rejects non-tuple indices", %{array_1d: array} do
      data = <<0::32, 1::32, 2::32>>
      assert {:error, {:invalid_index, msg}} = Array.set_slice(array, data, start: [0], stop: [3])
      assert msg =~ "start must be a tuple"
    end

    test "rejects dimension mismatch", %{array_2d: array} do
      data = <<0::32, 1::32, 2::32>>

      assert {:error, {:dimension_mismatch, msg}} =
               Array.set_slice(array, data, start: {0}, stop: {3})

      assert msg =~ "start has 1 dimensions but array has 2 dimensions"
    end

    test "rejects negative indices", %{array_1d: array} do
      data = <<0::32, 1::32, 2::32>>

      assert {:error, {:invalid_index, msg}} =
               Array.set_slice(array, data, start: {-1}, stop: {2})

      assert msg =~ "start indices must be non-negative"
    end

    test "rejects start > stop", %{array_1d: array} do
      data = <<0::32, 1::32, 2::32>>

      assert {:error, {:invalid_range, msg}} =
               Array.set_slice(array, data, start: {10}, stop: {5})

      assert msg =~ "start must be <= stop"
    end

    test "rejects out of bounds", %{array_1d: array} do
      data = <<0::32, 1::32, 2::32>>

      assert {:error, {:out_of_bounds, msg}} =
               Array.set_slice(array, data, start: {98}, stop: {101})

      assert msg =~ "Index out of bounds"
      assert msg =~ "stop=101 exceeds shape=100"
    end

    test "rejects data size mismatch - too few elements", %{array_1d: array} do
      data = <<0::32, 1::32>>

      assert {:error, {:data_size_mismatch, msg}} =
               Array.set_slice(array, data, start: {0}, stop: {10})

      assert msg =~ "expected 10 elements"
      assert msg =~ "got 2 elements"
    end

    test "rejects data size mismatch - too many elements", %{array_1d: array} do
      data =
        0..19
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert {:error, {:data_size_mismatch, msg}} =
               Array.set_slice(array, data, start: {0}, stop: {10})

      assert msg =~ "expected 10 elements"
      assert msg =~ "got 20 elements"
    end

    test "rejects data not multiple of element size", %{array_1d: array} do
      data = <<0::32, 1::32, 2::8>>

      assert {:error, {:data_size_mismatch, msg}} =
               Array.set_slice(array, data, start: {0}, stop: {3})

      assert msg =~ "Data size (9 bytes) is not a multiple of element size (4 bytes)"
    end

    test "rejects data size mismatch in 2D", %{array_2d: array} do
      # Should be 5x5 = 25 elements = 100 bytes
      data = <<0::32, 1::32>>

      assert {:error, {:data_size_mismatch, msg}} =
               Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      assert msg =~ "expected 25 elements"
      assert msg =~ "got 2 elements"
    end

    test "accepts valid data with correct size", %{array_1d: array} do
      data =
        0..9
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert :ok = Array.set_slice(array, data, start: {0}, stop: {10})
    end

    test "accepts valid 2D data with correct size", %{array_2d: array} do
      # 5x5 = 25 elements
      data =
        0..24
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})
    end
  end

  describe "edge cases" do
    test "accepts zero-sized write", %{array_1d: array} do
      data = <<>>
      assert :ok = Array.set_slice(array, data, start: {10}, stop: {10})
    end

    test "accepts write at array boundary", %{array_1d: array} do
      data =
        0..9
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert :ok = Array.set_slice(array, data, start: {90}, stop: {100})
    end

    test "accepts single element write", %{array_1d: array} do
      data = <<42::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {50}, stop: {51})
    end

    test "rejects write starting exactly at boundary + 1", %{array_1d: array} do
      data = <<42::signed-little-32>>

      assert {:error, {:out_of_bounds, _msg}} =
               Array.set_slice(array, data, start: {100}, stop: {101})
    end
  end

  describe "different dtypes" do
    test "validates data size for int8", _context do
      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int8,
          storage: :memory
        )

      # 10 bytes for 10 int8 elements
      data = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
      assert :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      # Wrong size - 11 bytes
      data_wrong = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

      assert {:error, {:data_size_mismatch, _msg}} =
               Array.set_slice(array, data_wrong, start: {0}, stop: {10})
    end

    test "validates data size for float64", _context do
      {:ok, array} =
        ExZarr.create(
          shape: {5},
          chunks: {5},
          dtype: :float64,
          storage: :memory
        )

      # 5 elements * 8 bytes = 40 bytes
      data =
        [1.0, 2.0, 3.0, 4.0, 5.0]
        |> Enum.map(&<<&1::float-little-64>>)
        |> IO.iodata_to_binary()

      assert :ok = Array.set_slice(array, data, start: {0}, stop: {5})

      # Wrong size - 41 bytes (not multiple of 8)
      data_wrong = <<data::binary, 1>>

      assert {:error, {:data_size_mismatch, msg}} =
               Array.set_slice(array, data_wrong, start: {0}, stop: {5})

      assert msg =~ "not a multiple of element size (8 bytes)"
    end

    test "validates data size for uint16", _context do
      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :uint16,
          storage: :memory
        )

      # 10 elements * 2 bytes = 20 bytes
      data =
        0..9
        |> Enum.map(&<<&1::unsigned-little-16>>)
        |> IO.iodata_to_binary()

      assert :ok = Array.set_slice(array, data, start: {0}, stop: {10})
    end
  end

  describe "multi-dimensional validation" do
    test "validates all dimensions for 3D array", %{array_3d: array} do
      # Try to write 2x2x2 = 8 elements
      data =
        0..7
        |> Enum.map(&<<&1::float-little-64>>)
        |> IO.iodata_to_binary()

      assert :ok = Array.set_slice(array, data, start: {0, 0, 0}, stop: {2, 2, 2})
    end

    test "rejects out of bounds in any dimension", %{array_3d: array} do
      data =
        0..7
        |> Enum.map(&<<&1::float-little-64>>)
        |> IO.iodata_to_binary()

      # Out of bounds in first dimension
      assert {:error, {:out_of_bounds, _}} =
               Array.set_slice(array, data, start: {19, 0, 0}, stop: {21, 2, 2})

      # Out of bounds in second dimension
      assert {:error, {:out_of_bounds, _}} =
               Array.set_slice(array, data, start: {0, 19, 0}, stop: {2, 21, 2})

      # Out of bounds in third dimension
      assert {:error, {:out_of_bounds, _}} =
               Array.set_slice(array, data, start: {0, 0, 19}, stop: {2, 2, 21})
    end

    test "rejects start > stop in any dimension", %{array_3d: array} do
      # start > stop in first dimension
      assert {:error, {:invalid_range, msg}} =
               Array.get_slice(array, start: {10, 0, 0}, stop: {5, 10, 10})

      assert msg =~ "Dimension 0"

      # start > stop in second dimension
      assert {:error, {:invalid_range, msg}} =
               Array.get_slice(array, start: {0, 10, 0}, stop: {10, 5, 10})

      assert msg =~ "Dimension 1"

      # start > stop in third dimension
      assert {:error, {:invalid_range, msg}} =
               Array.get_slice(array, start: {0, 0, 10}, stop: {10, 10, 5})

      assert msg =~ "Dimension 2"
    end
  end
end
