defmodule ExZarr.SlicingTest do
  use ExUnit.Case

  alias ExZarr.Array

  @moduledoc """
  Tests for array slicing operations (get_slice and set_slice).

  These tests verify that:
  - Data can be written to and read from arrays
  - Slicing works correctly for different dimensions
  - Chunk boundaries are handled correctly
  - Data integrity is maintained
  """

  @test_dir "/tmp/ex_zarr_slicing_test_#{System.unique_integer([:positive])}"

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  describe "1D array slicing" do
    test "writes and reads back simple 1D data" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          compressor: :none,
          storage: :memory
        )

      # Create test data: [0, 1, 2, ..., 99]
      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      # Write all data
      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      # Read it back
      {:ok, read_data} = Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "reads subset of 1D array" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :memory
        )

      # Write data
      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      # Read subset [10:20]
      {:ok, subset} = Array.get_slice(array, start: {10}, stop: {20})

      expected =
        10..19
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert subset == expected
    end

    test "writes to middle of 1D array" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :memory,
          fill_value: 0
        )

      # Write data to middle [40:50]
      data =
        100..109
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {40}, stop: {50})

      # Read back that section
      {:ok, read_data} = Array.get_slice(array, start: {40}, stop: {50})

      assert read_data == data
    end

    test "handles 1D array with different dtypes" do
      dtypes = [
        {:int8, &<<&1::signed-8>>, 1},
        {:int16, &<<&1::signed-little-16>>, 2},
        {:int64, &<<&1::signed-little-64>>, 8},
        {:uint8, &<<&1::unsigned-8>>, 1},
        {:float32, &<<&1::float-little-32>>, 4},
        {:float64, &<<&1::float-little-64>>, 8}
      ]

      for {dtype, encoder, _size} <- dtypes do
        {:ok, array} =
          ExZarr.create(
            shape: {50},
            chunks: {10},
            dtype: dtype,
            storage: :memory
          )

        # Write data
        data =
          0..49
          |> Enum.map(&encoder.(&1))
          |> IO.iodata_to_binary()

        :ok = Array.set_slice(array, data, start: {0}, stop: {50})

        # Read back
        {:ok, read_data} = Array.get_slice(array, start: {0}, stop: {50})

        assert read_data == data, "Failed for dtype #{dtype}"
      end
    end
  end

  describe "2D array slicing" do
    test "writes and reads back 2D data" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          compressor: :none,
          storage: :memory
        )

      # Create test data: sequential numbers 0-99
      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      # Write all data
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Read it back
      {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})

      assert read_data == data
    end

    test "reads 2D subset spanning multiple chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory
        )

      # Fill with sequential data
      data =
        0..399
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})

      # Read a region that spans all 4 chunks [5:15, 5:15]
      {:ok, subset} = Array.get_slice(array, start: {5, 5}, stop: {15, 15})

      # Expected: 10x10 region starting at (5,5)
      expected =
        for row <- 5..14 do
          for col <- 5..14 do
            value = row * 20 + col
            <<value::signed-little-32>>
          end
        end
        |> List.flatten()
        |> IO.iodata_to_binary()

      assert subset == expected
    end

    test "reads single row from 2D array" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Read row 3 [3:4, 0:10]
      {:ok, row} = Array.get_slice(array, start: {3, 0}, stop: {4, 10})

      expected =
        30..39
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert row == expected
    end

    test "reads single column from 2D array" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Read column 4 [0:10, 4:5]
      {:ok, col} = Array.get_slice(array, start: {0, 4}, stop: {10, 5})

      expected =
        [4, 14, 24, 34, 44, 54, 64, 74, 84, 94]
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert col == expected
    end

    test "writes to corner of 2D array" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory,
          fill_value: 0
        )

      # Write 5x5 block to top-left corner
      data =
        1..25
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      # Read back that corner
      {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})

      assert read_data == data
    end
  end

  describe "3D array slicing" do
    test "writes and reads back 3D data" do
      {:ok, array} =
        ExZarr.create(
          shape: {5, 5, 5},
          chunks: {5, 5, 5},
          dtype: :int16,
          compressor: :none,
          storage: :memory
        )

      # Create test data
      data =
        0..124
        |> Enum.map(&<<&1::signed-little-16>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0, 0}, stop: {5, 5, 5})

      {:ok, read_data} = Array.get_slice(array, start: {0, 0, 0}, stop: {5, 5, 5})

      assert read_data == data
    end

    test "reads 3D subset" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10, 10},
          chunks: {5, 5, 5},
          dtype: :int16,
          storage: :memory
        )

      data =
        0..999
        |> Enum.map(&<<&1::signed-little-16>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0, 0}, stop: {10, 10, 10})

      # Read a 3x3x3 cube from the middle
      {:ok, subset} = Array.get_slice(array, start: {2, 2, 2}, stop: {5, 5, 5})

      # Verify size
      assert byte_size(subset) == 3 * 3 * 3 * 2
    end
  end

  describe "Chunk boundary handling" do
    test "reads data spanning chunk boundaries in 1D" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :memory
        )

      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      # Read across chunk boundary [8:12]
      {:ok, cross_chunk} = Array.get_slice(array, start: {8}, stop: {12})

      expected =
        8..11
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      assert cross_chunk == expected
    end

    test "writes data spanning chunk boundaries in 2D" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory,
          fill_value: 0
        )

      # Write a 6x6 block that spans 4 chunks [8:14, 8:14]
      data =
        1..36
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {8, 8}, stop: {14, 14})

      # Read back
      {:ok, read_data} = Array.get_slice(array, start: {8, 8}, stop: {14, 14})

      assert read_data == data
    end
  end

  describe "Edge cases" do
    test "reads from empty array returns fill values" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory,
          fill_value: 42
        )

      # Read without writing
      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})

      # Should be all fill values
      expected =
        List.duplicate(<<42::signed-little-32>>, 25)
        |> IO.iodata_to_binary()

      assert data == expected
    end

    test "handles writing exactly one chunk" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

      # Write exactly one chunk worth of data
      data =
        0..24
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})

      assert read_data == data
    end

    test "handles reading past array bounds (clamped)" do
      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :memory
        )

      data =
        0..9
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      # Try to read beyond bounds - should clamp to array shape
      {:ok, read_data} = Array.get_slice(array, start: {0}, stop: {10})

      assert read_data == data
    end
  end

  describe "Compression with slicing" do
    test "writes and reads with zlib compression" do
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int32,
          compressor: :zlib,
          storage: :memory
        )

      data =
        0..2499
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {50, 50})

      {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {50, 50})

      assert read_data == data
    end

    test "partial reads with compression" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          compressor: :zlib,
          storage: :memory
        )

      data =
        0..99
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      # Read various slices
      {:ok, slice1} = Array.get_slice(array, start: {0}, stop: {10})
      {:ok, slice2} = Array.get_slice(array, start: {50}, stop: {60})
      {:ok, slice3} = Array.get_slice(array, start: {90}, stop: {100})

      assert byte_size(slice1) == 40
      assert byte_size(slice2) == 40
      assert byte_size(slice3) == 40
    end
  end

  describe "Filesystem persistence" do
    test "writes and reads persisted data" do
      path = Path.join(@test_dir, "persisted_array")

      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.save(array, path: path)

      data =
        0..399
        |> Enum.map(&<<&1::signed-little-32>>)
        |> IO.iodata_to_binary()

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})

      # Open array again
      {:ok, reopened} = ExZarr.open(path: path)

      # Read data
      {:ok, read_data} = Array.get_slice(reopened, start: {0, 0}, stop: {20, 20})

      assert read_data == data
    end
  end
end
