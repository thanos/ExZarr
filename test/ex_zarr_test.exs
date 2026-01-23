defmodule ExZarrTest do
  use ExUnit.Case
  doctest ExZarr

  alias ExZarr.{Array, Chunk, Codecs, Group, Metadata}

  describe "Array creation" do
    test "creates an array with valid configuration" do
      assert {:ok, array} =
               ExZarr.create(
                 shape: {100, 100},
                 chunks: {10, 10},
                 dtype: :float64,
                 compressor: :zlib
               )

      assert array.shape == {100, 100}
      assert array.chunks == {10, 10}
      assert array.dtype == :float64
      assert array.compressor == :zlib
    end

    test "fails with missing shape" do
      assert {:error, :shape_required} =
               ExZarr.create(
                 chunks: {10, 10},
                 dtype: :float64
               )
    end

    test "fails with missing chunks" do
      assert {:error, :chunks_required} =
               ExZarr.create(
                 shape: {100, 100},
                 dtype: :float64
               )
    end

    test "fails with mismatched chunk dimensions" do
      assert {:error, :invalid_chunks} =
               ExZarr.create(
                 shape: {100, 100},
                 chunks: {10},
                 dtype: :float64
               )
    end
  end

  describe "Codecs" do
    test "zlib compression and decompression" do
      data = "Hello, Zarr!" |> String.duplicate(100)
      assert {:ok, compressed} = Codecs.compress(data, :zlib)
      assert byte_size(compressed) < byte_size(data)
      assert {:ok, decompressed} = Codecs.decompress(compressed, :zlib)
      assert decompressed == data
    end

    test "no compression passes through" do
      data = "Hello, Zarr!"
      assert {:ok, ^data} = Codecs.compress(data, :none)
      assert {:ok, ^data} = Codecs.decompress(data, :none)
    end

    test "lists available codecs" do
      codecs = Codecs.available_codecs()
      assert :none in codecs
      assert :zlib in codecs
      assert :zstd in codecs
      assert :lz4 in codecs
    end

    test "checks codec availability" do
      assert Codecs.codec_available?(:zlib)
      assert Codecs.codec_available?(:none)
      refute Codecs.codec_available?(:invalid_codec)
    end
  end

  describe "Chunk utilities" do
    test "converts array index to chunk index" do
      assert Chunk.index_to_chunk({150, 250}, {100, 100}) == {1, 2}
      assert Chunk.index_to_chunk({0, 0}, {100, 100}) == {0, 0}
      assert Chunk.index_to_chunk({99, 99}, {100, 100}) == {0, 0}
    end

    test "calculates chunk bounds" do
      assert Chunk.chunk_bounds({1, 2}, {100, 100}, {1000, 1000}) ==
               {{100, 200}, {200, 300}}

      assert Chunk.chunk_bounds({0, 0}, {100, 100}, {1000, 1000}) ==
               {{0, 0}, {100, 100}}
    end

    test "calculates strides for C-order layout" do
      assert Chunk.calculate_strides({10, 20, 30}) == {600, 30, 1}
      assert Chunk.calculate_strides({100, 100}) == {100, 1}
    end
  end

  describe "Metadata" do
    test "creates metadata from configuration" do
      config = %{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zstd,
        fill_value: 0.0
      }

      assert {:ok, metadata} = Metadata.create(config)
      assert metadata.shape == {1000, 1000}
      assert metadata.chunks == {100, 100}
      assert metadata.dtype == :float64
      assert metadata.compressor == :zstd
      assert metadata.zarr_format == 2
    end

    test "calculates number of chunks" do
      metadata = %Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zstd,
        fill_value: 0
      }

      assert Metadata.num_chunks(metadata) == {10, 10}
      assert Metadata.total_chunks(metadata) == 100
    end

    test "calculates chunk size in bytes" do
      metadata = %Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :none,
        fill_value: 0
      }

      # 100 * 100 elements * 8 bytes per float64
      assert Metadata.chunk_size_bytes(metadata) == 80_000
    end
  end

  describe "Group operations" do
    test "creates a group" do
      assert {:ok, group} = Group.create("/data")
      assert group.path == "/data"
      assert group.arrays == %{}
      assert group.groups == %{}
    end

    test "creates an array in a group" do
      {:ok, group} = Group.create("/data")

      assert {:ok, array} =
               Group.create_array(group, "measurements",
                 shape: {100},
                 chunks: {10},
                 dtype: :float64
               )

      assert array.shape == {100}
    end

    test "creates a subgroup" do
      {:ok, parent} = Group.create("/data")
      assert {:ok, subgroup} = Group.create_group(parent, "experiments")
      assert subgroup.path == "/data/experiments"
    end

    test "sets and gets group attributes" do
      {:ok, group} = Group.create("/data")
      updated = Group.set_attr(group, "description", "Test data")

      assert {:ok, "Test data"} = Group.get_attr(updated, "description")
      assert {:error, :not_found} = Group.get_attr(updated, "nonexistent")
    end
  end

  describe "Array properties" do
    test "calculates array ndim" do
      {:ok, array} = ExZarr.create(shape: {100, 200, 300}, chunks: {10, 20, 30})
      assert Array.ndim(array) == 3
    end

    test "calculates array size" do
      {:ok, array} = ExZarr.create(shape: {10, 20}, chunks: {5, 10})
      assert Array.size(array) == 200
    end

    test "calculates itemsize" do
      {:ok, array} = ExZarr.create(shape: {10, 10}, chunks: {5, 5}, dtype: :float64)
      assert Array.itemsize(array) == 8

      {:ok, array} = ExZarr.create(shape: {10, 10}, chunks: {5, 5}, dtype: :int32)
      assert Array.itemsize(array) == 4
    end
  end
end
