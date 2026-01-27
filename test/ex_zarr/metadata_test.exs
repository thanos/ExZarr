defmodule ExZarr.MetadataTest do
  use ExUnit.Case, async: true

  alias ExZarr.Metadata

  describe "create/1" do
    test "creates metadata with all required fields" do
      config = %{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert metadata.shape == {1000, 1000}
      assert metadata.chunks == {100, 100}
      assert metadata.dtype == :float64
      assert metadata.compressor == :zlib
      assert metadata.fill_value == 0.0
      assert metadata.order == "C"
      assert metadata.zarr_format == 2
      assert metadata.filters == nil
    end

    test "creates metadata with filters" do
      config = %{
        shape: {1000},
        chunks: {100},
        dtype: :int64,
        compressor: :zlib,
        filters: [{:delta, [dtype: :int64]}],
        fill_value: 0
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert metadata.filters == [{:delta, [dtype: :int64]}]
    end

    test "creates metadata with default fill_value" do
      config = %{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        fill_value: 0
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert metadata.fill_value == 0
    end

    test "creates metadata for 1D array" do
      config = %{
        shape: {1000},
        chunks: {100},
        dtype: :float32,
        compressor: :gzip,
        fill_value: 0.0
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert tuple_size(metadata.shape) == 1
      assert tuple_size(metadata.chunks) == 1
    end

    test "creates metadata for 3D array" do
      config = %{
        shape: {100, 200, 300},
        chunks: {10, 20, 30},
        dtype: :uint8,
        compressor: :zstd,
        fill_value: 0
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert tuple_size(metadata.shape) == 3
      assert tuple_size(metadata.chunks) == 3
    end

    test "creates metadata with different dtypes" do
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
        config = %{
          shape: {100},
          chunks: {10},
          dtype: dtype,
          compressor: :zlib,
          fill_value: 0
        }

        assert {:ok, metadata} = Metadata.create(config)
        assert metadata.dtype == dtype
      end
    end

    test "creates metadata with different compressors" do
      compressors = [:zlib, :gzip, :zstd, :lz4, :blosc, nil]

      for compressor <- compressors do
        config = %{
          shape: {100},
          chunks: {10},
          dtype: :float32,
          compressor: compressor,
          fill_value: 0.0
        }

        assert {:ok, metadata} = Metadata.create(config)
        assert metadata.compressor == compressor
      end
    end

    test "creates metadata with custom fill_value" do
      config = %{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        fill_value: -999.9
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert metadata.fill_value == -999.9
    end

    test "creates metadata with integer fill_value" do
      config = %{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        fill_value: -1
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert metadata.fill_value == -1
    end

    test "raises for missing shape" do
      config = %{
        chunks: {10},
        dtype: :float32,
        compressor: :zlib
      }

      assert_raise KeyError, fn ->
        Metadata.create(config)
      end
    end

    test "raises for missing chunks" do
      config = %{
        shape: {100},
        dtype: :float32,
        compressor: :zlib
      }

      assert_raise KeyError, fn ->
        Metadata.create(config)
      end
    end

    test "raises for missing dtype" do
      config = %{
        shape: {100},
        chunks: {10},
        compressor: :zlib
      }

      assert_raise KeyError, fn ->
        Metadata.create(config)
      end
    end
  end

  describe "validate/1" do
    test "validates correct metadata" do
      metadata = %Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "validates metadata with no compressor" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: nil,
        fill_value: 0,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "validates metadata with delta filter" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: [{:delta, []}],
        fill_value: 0,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "validates metadata with shuffle filter" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: [{:shuffle, []}],
        fill_value: 0,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "validates metadata with empty filters list" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: [],
        fill_value: 0,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "returns error for dimension mismatch" do
      metadata = %Metadata{
        shape: {1000, 1000},
        chunks: {100},
        dtype: :float64,
        compressor: :zlib
      }

      assert {:error, :chunks_shape_mismatch} = Metadata.validate(metadata)
    end

    test "returns error for empty shape" do
      metadata = %Metadata{
        shape: {},
        chunks: {},
        dtype: :float64,
        compressor: :zlib
      }

      assert {:error, :invalid_shape} = Metadata.validate(metadata)
    end

    test "returns error for unsupported zarr format" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        zarr_format: 3
      }

      assert {:error, :unsupported_zarr_format} = Metadata.validate(metadata)
    end

    test "returns error for unknown filter" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: [{:unknown_filter, []}],
        zarr_format: 2
      }

      assert {:error, _} = Metadata.validate(metadata)
    end

    test "returns error for invalid filter format" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: "invalid",
        zarr_format: 2
      }

      assert {:error, :invalid_filter_format} = Metadata.validate(metadata)
    end

    test "validates metadata with multiple filters" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: [{:shuffle, []}, {:delta, []}],
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "validates 1D metadata" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end

    test "validates 3D metadata" do
      metadata = %Metadata{
        shape: {100, 200, 300},
        chunks: {10, 20, 30},
        dtype: :float64,
        compressor: :zlib,
        zarr_format: 2
      }

      assert :ok = Metadata.validate(metadata)
    end
  end

  describe "num_chunks/1" do
    test "calculates num_chunks for 1D array" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {10}
    end

    test "calculates num_chunks for 2D array" do
      metadata = %Metadata{
        shape: {1000, 2000},
        chunks: {100, 200},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {10, 10}
    end

    test "calculates num_chunks for 3D array" do
      metadata = %Metadata{
        shape: {100, 200, 300},
        chunks: {10, 20, 30},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {10, 10, 10}
    end

    test "handles non-evenly divisible dimensions" do
      metadata = %Metadata{
        shape: {105},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib
      }

      # 105 / 10 = 10.5, should ceil to 11
      assert Metadata.num_chunks(metadata) == {11}
    end

    test "handles multiple non-evenly divisible dimensions" do
      metadata = %Metadata{
        shape: {105, 207},
        chunks: {10, 20},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {11, 11}
    end

    test "handles chunk size equal to dimension" do
      metadata = %Metadata{
        shape: {100},
        chunks: {100},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {1}
    end

    test "handles very small chunks" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {1},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {1000}
    end

    test "handles large dimensions" do
      metadata = %Metadata{
        shape: {1_000_000},
        chunks: {1000},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.num_chunks(metadata) == {1000}
    end
  end

  describe "total_chunks/1" do
    test "calculates total chunks for 1D array" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.total_chunks(metadata) == 10
    end

    test "calculates total chunks for 2D array" do
      metadata = %Metadata{
        shape: {1000, 2000},
        chunks: {100, 200},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.total_chunks(metadata) == 100
    end

    test "calculates total chunks for 3D array" do
      metadata = %Metadata{
        shape: {100, 200, 300},
        chunks: {10, 20, 30},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.total_chunks(metadata) == 1000
    end

    test "handles non-evenly divisible dimensions" do
      metadata = %Metadata{
        shape: {105, 207},
        chunks: {10, 20},
        dtype: :float64,
        compressor: :zlib
      }

      # 11 * 11 = 121
      assert Metadata.total_chunks(metadata) == 121
    end

    test "handles single chunk" do
      metadata = %Metadata{
        shape: {100, 100},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.total_chunks(metadata) == 1
    end

    test "handles many small chunks" do
      metadata = %Metadata{
        shape: {100, 100},
        chunks: {1, 1},
        dtype: :float64,
        compressor: :zlib
      }

      assert Metadata.total_chunks(metadata) == 10_000
    end

    test "handles 4D array" do
      metadata = %Metadata{
        shape: {10, 20, 30, 40},
        chunks: {5, 10, 15, 20},
        dtype: :float64,
        compressor: :zlib
      }

      # 2 * 2 * 2 * 2 = 16
      assert Metadata.total_chunks(metadata) == 16
    end
  end

  describe "chunk_size_bytes/1" do
    test "calculates chunk size for float64" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :float64,
        compressor: :zlib
      }

      # 100 elements * 8 bytes = 800 bytes
      assert Metadata.chunk_size_bytes(metadata) == 800
    end

    test "calculates chunk size for float32" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :float32,
        compressor: :zlib
      }

      # 100 elements * 4 bytes = 400 bytes
      assert Metadata.chunk_size_bytes(metadata) == 400
    end

    test "calculates chunk size for int32" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :int32,
        compressor: :zlib
      }

      # 100 elements * 4 bytes = 400 bytes
      assert Metadata.chunk_size_bytes(metadata) == 400
    end

    test "calculates chunk size for uint8" do
      metadata = %Metadata{
        shape: {1000},
        chunks: {100},
        dtype: :uint8,
        compressor: :zlib
      }

      # 100 elements * 1 byte = 100 bytes
      assert Metadata.chunk_size_bytes(metadata) == 100
    end

    test "calculates chunk size for 2D array" do
      metadata = %Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib
      }

      # 100 * 100 elements * 8 bytes = 80,000 bytes
      assert Metadata.chunk_size_bytes(metadata) == 80_000
    end

    test "calculates chunk size for 3D array" do
      metadata = %Metadata{
        shape: {100, 100, 100},
        chunks: {10, 10, 10},
        dtype: :float32,
        compressor: :zlib
      }

      # 10 * 10 * 10 elements * 4 bytes = 4,000 bytes
      assert Metadata.chunk_size_bytes(metadata) == 4_000
    end

    test "handles int8" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int8,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 10
    end

    test "handles int16" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int16,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 20
    end

    test "handles int64" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int64,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 80
    end

    test "handles uint16" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :uint16,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 20
    end

    test "handles uint32" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :uint32,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 40
    end

    test "handles uint64" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :uint64,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 80
    end

    test "calculates large chunk sizes" do
      metadata = %Metadata{
        shape: {10_000, 10_000},
        chunks: {1000, 1000},
        dtype: :float64,
        compressor: :zlib
      }

      # 1000 * 1000 * 8 = 8,000,000 bytes
      assert Metadata.chunk_size_bytes(metadata) == 8_000_000
    end

    test "calculates small chunk sizes" do
      metadata = %Metadata{
        shape: {100},
        chunks: {1},
        dtype: :uint8,
        compressor: :zlib
      }

      assert Metadata.chunk_size_bytes(metadata) == 1
    end
  end

  describe "struct defaults" do
    test "has correct default values" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib
      }

      assert metadata.fill_value == 0
      assert metadata.order == "C"
      assert metadata.zarr_format == 2
      assert metadata.filters == nil
    end

    test "can override defaults" do
      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 42,
        order: "F",
        zarr_format: 2,
        filters: [{:delta, []}]
      }

      assert metadata.fill_value == 42
      assert metadata.order == "F"
      assert metadata.filters == [{:delta, []}]
    end
  end
end
