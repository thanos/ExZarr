defmodule ExZarr.StorageTest do
  use ExUnit.Case
  alias ExZarr.{Metadata, Storage}

  @test_dir "/tmp/ex_zarr_test_#{System.unique_integer([:positive])}"

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  describe "Memory storage" do
    test "initializes memory storage" do
      assert {:ok, storage} = Storage.init(%{storage_type: :memory})
      assert storage.backend == :memory
      assert storage.state.chunks == %{}
    end

    test "writes and reads chunks in memory" do
      {:ok, storage} = Storage.init(%{storage_type: :memory})
      chunk_data = "test chunk data"

      {:ok, updated_storage} = Storage.write_chunk(storage, {0, 0}, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(updated_storage, {0, 0})
    end

    test "returns error for missing chunk in memory" do
      {:ok, storage} = Storage.init(%{storage_type: :memory})
      assert {:error, :not_found} = Storage.read_chunk(storage, {0, 0})
    end

    test "writes and reads metadata in memory" do
      {:ok, storage} = Storage.init(%{storage_type: :memory})

      metadata = %Metadata{
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0,
        order: "C",
        zarr_format: 2
      }

      {:ok, updated_storage} = Storage.write_metadata(storage, metadata, [])
      assert {:ok, read_metadata} = Storage.read_metadata(updated_storage)
      assert read_metadata.shape == {100, 100}
      assert read_metadata.chunks == {10, 10}
    end

    test "lists chunks in memory storage" do
      {:ok, storage} = Storage.init(%{storage_type: :memory})

      {:ok, storage} = Storage.write_chunk(storage, {0, 0}, "data1")
      {:ok, storage} = Storage.write_chunk(storage, {0, 1}, "data2")
      {:ok, storage} = Storage.write_chunk(storage, {1, 0}, "data3")

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert length(chunks) == 3
      assert {0, 0} in chunks
      assert {0, 1} in chunks
      assert {1, 0} in chunks
    end
  end

  describe "Filesystem storage" do
    test "initializes filesystem storage" do
      path = Path.join(@test_dir, "array1")
      assert {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})
      assert storage.backend == :filesystem
      assert storage.path == path
      assert File.dir?(path)
    end

    test "opens existing filesystem storage" do
      path = Path.join(@test_dir, "array2")
      File.mkdir_p!(path)

      assert {:ok, storage} = Storage.open(storage: :filesystem, path: path)
      assert storage.backend == :filesystem
      assert storage.path == path
    end

    test "writes and reads chunks to filesystem" do
      path = Path.join(@test_dir, "array3")
      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})

      chunk_data = "filesystem chunk data"
      assert :ok = Storage.write_chunk(storage, {2, 3}, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, {2, 3})

      # Verify file exists on disk (Zarr uses dot notation: 2.3)
      chunk_path = Path.join(path, "2.3")
      assert File.exists?(chunk_path)
    end

    test "returns error for missing chunk on filesystem" do
      path = Path.join(@test_dir, "array4")
      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})

      assert {:error, :not_found} = Storage.read_chunk(storage, {99, 99})
    end

    test "writes and reads metadata to filesystem" do
      path = Path.join(@test_dir, "array5")
      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})

      metadata = %Metadata{
        shape: {200, 300},
        chunks: {20, 30},
        dtype: :int32,
        compressor: :zlib,
        fill_value: -1,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Storage.write_metadata(storage, metadata, [])

      # Verify .zarray file exists
      zarray_path = Path.join(path, ".zarray")
      assert File.exists?(zarray_path)

      assert {:ok, read_metadata} = Storage.read_metadata(storage)
      assert read_metadata.shape == {200, 300}
      assert read_metadata.dtype == :int32
    end

    test "handles 3D chunk indices" do
      path = Path.join(@test_dir, "array6")
      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})

      # Write chunk with 3D indexing (Zarr uses dot notation: 10.20.30)
      assert :ok = Storage.write_chunk(storage, {10, 20, 30}, "deep chunk")
      assert {:ok, "deep chunk"} = Storage.read_chunk(storage, {10, 20, 30})

      chunk_path = Path.join(path, "10.20.30")
      assert File.exists?(chunk_path)
    end

    test "lists chunks on filesystem" do
      path = Path.join(@test_dir, "array7")
      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})

      Storage.write_chunk(storage, {0, 0}, "data1")
      Storage.write_chunk(storage, {0, 1}, "data2")
      Storage.write_chunk(storage, {1, 0}, "data3")

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert length(chunks) >= 3
    end

    test "verifies chunk persistence on filesystem" do
      path = Path.join(@test_dir, "array8")
      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})

      assert :ok = Storage.write_chunk(storage, {5, 5}, "data")
      # Zarr uses dot notation for chunks
      chunk_path = Path.join(path, "5.5")
      assert File.exists?(chunk_path)
      assert {:ok, "data"} = Storage.read_chunk(storage, {5, 5})
    end
  end

  describe "Storage backend validation" do
    test "rejects invalid backend" do
      assert {:error, :invalid_storage_config} = Storage.init(%{storage_type: :invalid})
    end

    test "requires path for filesystem backend" do
      assert {:error, :path_required} = Storage.init(%{storage_type: :filesystem})
    end
  end

  # Note: format_chunk_key is a private function, tested implicitly through write/read

  describe "Metadata JSON encoding" do
    test "encodes all dtypes correctly" do
      dtypes = [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64, :float32, :float64]

      for dtype <- dtypes do
        metadata = %Metadata{
          shape: {100},
          chunks: {10},
          dtype: dtype,
          compressor: :none,
          fill_value: 0,
          order: "C",
          zarr_format: 2
        }

        path = Path.join(@test_dir, "dtype_#{dtype}")
        {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})
        assert :ok = Storage.write_metadata(storage, metadata, [])
        assert {:ok, read_back} = Storage.read_metadata(storage)
        assert read_back.dtype == dtype
      end
    end

    test "encodes all compressors correctly" do
      compressors = [:none, :zlib, :zstd, :lz4]

      for compressor <- compressors do
        metadata = %Metadata{
          shape: {100},
          chunks: {10},
          dtype: :float64,
          compressor: compressor,
          fill_value: 0,
          order: "C",
          zarr_format: 2
        }

        path = Path.join(@test_dir, "comp_#{compressor}")
        {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})
        assert :ok = Storage.write_metadata(storage, metadata, [])
        assert {:ok, read_back} = Storage.read_metadata(storage)
        assert read_back.compressor == compressor
      end
    end
  end
end
