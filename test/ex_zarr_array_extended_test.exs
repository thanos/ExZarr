defmodule ExZarr.ArrayExtendedTest do
  use ExUnit.Case
  alias ExZarr.Array

  @test_dir "/tmp/ex_zarr_array_test_#{System.unique_integer([:positive])}"

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  describe "Array creation with various dtypes" do
    test "creates arrays with all integer dtypes" do
      dtypes = [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64]

      for dtype <- dtypes do
        assert {:ok, array} =
                 ExZarr.create(
                   shape: {10, 10},
                   chunks: {5, 5},
                   dtype: dtype,
                   compressor: :none
                 )

        assert array.dtype == dtype
      end
    end

    test "creates arrays with float dtypes" do
      for dtype <- [:float32, :float64] do
        assert {:ok, array} =
                 ExZarr.create(
                   shape: {20, 20},
                   chunks: {10, 10},
                   dtype: dtype
                 )

        assert array.dtype == dtype
      end
    end

    test "creates 1D array" do
      assert {:ok, array} = ExZarr.create(shape: {1000}, chunks: {100}, dtype: :float64)
      assert Array.ndim(array) == 1
      assert Array.size(array) == 1000
    end

    test "creates 3D array" do
      assert {:ok, array} =
               ExZarr.create(shape: {10, 20, 30}, chunks: {5, 10, 15}, dtype: :int32)

      assert Array.ndim(array) == 3
      assert Array.size(array) == 6000
    end

    test "creates 4D array" do
      assert {:ok, array} =
               ExZarr.create(shape: {5, 5, 5, 5}, chunks: {2, 2, 2, 2}, dtype: :float32)

      assert Array.ndim(array) == 4
      assert Array.size(array) == 625
    end
  end

  describe "Array creation with compressors" do
    test "creates array with no compression" do
      assert {:ok, array} =
               ExZarr.create(
                 shape: {100, 100},
                 chunks: {10, 10},
                 compressor: :none
               )

      assert array.compressor == :none
    end

    test "creates array with zlib compression" do
      assert {:ok, array} =
               ExZarr.create(
                 shape: {100, 100},
                 chunks: {10, 10},
                 compressor: :zlib
               )

      assert array.compressor == :zlib
    end

    test "creates array with zstd compression" do
      assert {:ok, array} =
               ExZarr.create(
                 shape: {100, 100},
                 chunks: {10, 10},
                 compressor: :zstd
               )

      assert array.compressor == :zstd
    end
  end

  describe "Array persistence (filesystem)" do
    test "saves and opens array" do
      path = Path.join(@test_dir, "persistent_array")

      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :float64,
          compressor: :zlib,
          storage: :filesystem,
          path: path
        )

      assert :ok = ExZarr.save(array, path: path)
      assert {:ok, loaded_array} = ExZarr.open(path: path, backend: :filesystem)

      assert loaded_array.shape == {50, 50}
      assert loaded_array.chunks == {10, 10}
      assert loaded_array.dtype == :float64
      assert loaded_array.compressor == :zlib
    end

    test "opens existing array from disk" do
      path = Path.join(@test_dir, "existing_array")

      {:ok, array} =
        ExZarr.create(
          shape: {30, 40},
          chunks: {10, 20},
          dtype: :int32,
          storage: :filesystem,
          path: path
        )

      Array.save(array, path: path)

      assert {:ok, reopened} = Array.open(backend: :filesystem, path: path)
      assert reopened.shape == {30, 40}
      assert reopened.chunks == {10, 20}
      assert reopened.dtype == :int32
    end
  end

  describe "Array validation" do
    test "rejects invalid shape" do
      assert {:error, :shape_required} = ExZarr.create(chunks: {10, 10})
      assert {:error, :invalid_shape} = ExZarr.create(shape: {}, chunks: {10})
      assert {:error, :invalid_shape} = ExZarr.create(shape: {-1, 10}, chunks: {10, 10})
      assert {:error, :invalid_shape} = ExZarr.create(shape: {0, 10}, chunks: {10, 10})
    end

    test "rejects invalid chunks" do
      assert {:error, :chunks_required} = ExZarr.create(shape: {100, 100})

      assert {:error, :invalid_chunks} =
               ExZarr.create(shape: {100, 100}, chunks: {10, 10, 10})

      assert {:error, :invalid_chunks} = ExZarr.create(shape: {100, 100}, chunks: {-1, 10})
      assert {:error, :invalid_chunks} = ExZarr.create(shape: {100, 100}, chunks: {0, 10})
    end

    test "uses default values" do
      {:ok, array} = ExZarr.create(shape: {100, 100}, chunks: {10, 10})
      assert array.dtype == :float64
      assert array.compressor == :zstd
      assert array.fill_value == 0.0
    end
  end

  describe "Array properties and calculations" do
    test "itemsize for all dtypes" do
      dtypes_sizes = [
        {:int8, 1},
        {:uint8, 1},
        {:int16, 2},
        {:uint16, 2},
        {:int32, 4},
        {:uint32, 4},
        {:float32, 4},
        {:int64, 8},
        {:uint64, 8},
        {:float64, 8}
      ]

      for {dtype, expected_size} <- dtypes_sizes do
        {:ok, array} = ExZarr.create(shape: {10, 10}, chunks: {5, 5}, dtype: dtype)
        assert Array.itemsize(array) == expected_size
      end
    end

    test "calculates total bytes via size and itemsize" do
      {:ok, array} = ExZarr.create(shape: {100, 200}, chunks: {10, 20}, dtype: :float64)
      # 100 * 200 * 8 bytes
      total_bytes = Array.size(array) * Array.itemsize(array)
      assert total_bytes == 160_000
    end

    test "calculates bytes for different dtypes" do
      {:ok, array} = ExZarr.create(shape: {50, 50}, chunks: {10, 10}, dtype: :int32)
      # 50 * 50 * 4 bytes
      total_bytes = Array.size(array) * Array.itemsize(array)
      assert total_bytes == 10_000
    end

    test "accesses shape property directly" do
      {:ok, array} = ExZarr.create(shape: {100, 200, 300}, chunks: {10, 20, 30})
      assert array.shape == {100, 200, 300}
    end
  end

  describe "Array to_binary" do
    test "converts array to binary" do
      {:ok, array} = ExZarr.create(shape: {10, 10}, chunks: {5, 5})
      assert {:ok, binary} = Array.to_binary(array)
      assert is_binary(binary)
    end
  end

  describe "Fill values" do
    test "creates array with custom fill value" do
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :float64,
          fill_value: 99.9
        )

      assert array.fill_value == 99.9
    end

    test "creates array with negative fill value" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          fill_value: -1
        )

      assert array.fill_value == -1
    end
  end

  describe "Error handling" do
    test "handles invalid storage backend" do
      assert {:error, :invalid_storage_config} =
               ExZarr.create(
                 shape: {10, 10},
                 chunks: {5, 5},
                 storage: :invalid_backend
               )
    end

    test "handles missing path for filesystem storage" do
      assert {:error, :path_required} =
               ExZarr.create(
                 shape: {10, 10},
                 chunks: {5, 5},
                 storage: :filesystem
               )
    end
  end

  describe "Chunk calculations" do
    test "calculates chunk indices for various positions" do
      {:ok, array} = ExZarr.create(shape: {1000, 2000}, chunks: {100, 200})

      # Test boundaries
      assert ExZarr.Chunk.index_to_chunk({0, 0}, array.chunks) == {0, 0}
      assert ExZarr.Chunk.index_to_chunk({99, 199}, array.chunks) == {0, 0}
      assert ExZarr.Chunk.index_to_chunk({100, 200}, array.chunks) == {1, 1}
      assert ExZarr.Chunk.index_to_chunk({999, 1999}, array.chunks) == {9, 9}
    end
  end
end
