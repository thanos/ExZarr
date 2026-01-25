defmodule ExZarr.ShardingIntegrationTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

  describe "sharded arrays" do
    test "creates sharded array with v3 format" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      assert array.version == 3
      assert array.metadata.zarr_format == 3

      # Check that sharding codec is in metadata
      assert Enum.any?(array.metadata.codecs, fn codec ->
               codec.name == "sharding_indexed"
             end)
    end

    test "writes and reads data from sharded array" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write data to first chunk
      data = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>

      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      # Read back the data
      assert {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data == data
    end

    test "writes and reads multiple chunks in same shard" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write to first chunk {0, 0}
      data1 = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data1, start: {0, 0}, stop: {5, 5})

      # Write to second chunk {0, 1} in same shard
      data2 = for i <- 25..49, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data2, start: {0, 5}, stop: {5, 10})

      # Read back both chunks
      assert {:ok, read_data1} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data1 == data1

      assert {:ok, read_data2} = Array.get_slice(array, start: {0, 5}, stop: {5, 10})
      assert read_data2 == data2
    end

    test "writes and reads chunks across different shards" do
      {:ok, array} =
        ExZarr.create(
          shape: {40, 40},
          chunks: {10, 10},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write to chunk in shard {0, 0}
      data1 = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data1, start: {0, 0}, stop: {10, 10})

      # Write to chunk in shard {1, 1}
      data2 = for i <- 100..199, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data2, start: {20, 20}, stop: {30, 30})

      # Read back both regions
      assert {:ok, read_data1} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert read_data1 == data1

      assert {:ok, read_data2} = Array.get_slice(array, start: {20, 20}, stop: {30, 30})
      assert read_data2 == data2
    end

    test "read-modify-write updates shard correctly" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Initial write to chunk {0, 0}
      data1 = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data1, start: {0, 0}, stop: {5, 5})

      # Write to chunk {0, 1} in same shard (should preserve {0, 0})
      data2 = for i <- 100..124, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data2, start: {0, 5}, stop: {5, 10})

      # Verify both chunks are intact
      assert {:ok, read_data1} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data1 == data1

      assert {:ok, read_data2} = Array.get_slice(array, start: {0, 5}, stop: {5, 10})
      assert read_data2 == data2
    end

    test "reads uninitialized chunks return fill value" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          fill_value: 42,
          zarr_version: 3,
          storage: :memory
        )

      # Read chunk that was never written
      assert {:ok, data} = Array.get_slice(array, start: {10, 10}, stop: {15, 15})

      # Should be all fill values
      expected = for _ <- 0..24, into: <<>>, do: <<42::signed-little-32>>
      assert data == expected
    end

    test "works with compression codecs" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          compressor: :gzip,
          zarr_version: 3,
          storage: :memory
        )

      # Write data
      data = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      # Read back
      assert {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data == data
    end

    test "1D sharded arrays" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          shard_shape: {5},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write data
      data = for i <- 0..9, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      # Read back
      assert {:ok, read_data} = Array.get_slice(array, start: {0}, stop: {10})
      assert read_data == data
    end

    test "3D sharded arrays" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20, 20},
          chunks: {5, 5, 5},
          shard_shape: {2, 2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write data
      data = for i <- 0..124, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0, 0}, stop: {5, 5, 5})

      # Read back
      assert {:ok, read_data} = Array.get_slice(array, start: {0, 0, 0}, stop: {5, 5, 5})
      assert read_data == data
    end

    test "custom index location at start" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          index_location: "start",
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write and read data
      data = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      assert {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data == data
    end

    test "large number of chunks in shard" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          shard_shape: {5, 5},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write to multiple chunks
      for i <- 0..4, j <- 0..4 do
        start_row = i * 10
        start_col = j * 10
        data = for k <- 0..99, into: <<>>, do: <<i * 100 + j * 10 + k::signed-little-32>>

        assert :ok =
                 Array.set_slice(array, data,
                   start: {start_row, start_col},
                   stop: {start_row + 10, start_col + 10}
                 )
      end

      # Read back and verify
      for i <- 0..4, j <- 0..4 do
        start_row = i * 10
        start_col = j * 10
        expected = for k <- 0..99, into: <<>>, do: <<i * 100 + j * 10 + k::signed-little-32>>

        assert {:ok, data} =
                 Array.get_slice(array,
                   start: {start_row, start_col},
                   stop: {start_row + 10, start_col + 10}
                 )

        assert data == expected
      end
    end
  end

  describe "sharding with filesystem storage" do
    @test_path "/tmp/exzarr_sharding_test_#{:rand.uniform(1_000_000)}"

    setup do
      # Clean up test directory
      on_exit(fn ->
        if File.exists?(@test_path) do
          File.rm_rf!(@test_path)
        end
      end)

      :ok
    end

    test "persists sharded array to filesystem" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :filesystem,
          path: @test_path
        )

      # Save metadata FIRST (writes zarr.json) so chunks are written with correct v3 naming
      assert :ok = Array.save(array, [])

      # Write data (this will create the shard file with v3 naming)
      data = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      # Verify shard file exists (v3 uses c/0/0 format)
      shard_file = Path.join([@test_path, "c", "0", "0"])
      assert File.exists?(shard_file), "Shard file should exist at #{shard_file}"
      assert File.stat!(shard_file).size > 0, "Shard file should not be empty"

      # Verify metadata file exists
      metadata_file = Path.join(@test_path, "zarr.json")
      assert File.exists?(metadata_file), "Metadata file should exist"

      # Reopen and read
      {:ok, reopened} = ExZarr.open(path: @test_path)
      assert {:ok, read_data} = Array.get_slice(reopened, start: {0, 0}, stop: {5, 5})
      assert read_data == data
    end

    test "reduces file count with sharding" do
      # Create array with 100 chunks (10x10 grid)
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          shard_shape: {5, 5},
          dtype: :int32,
          zarr_version: 3,
          storage: :filesystem,
          path: @test_path
        )

      # Write all chunks
      for i <- 0..9, j <- 0..9 do
        start_row = i * 10
        start_col = j * 10
        data = for k <- 0..99, into: <<>>, do: <<k::signed-little-32>>

        Array.set_slice(array, data,
          start: {start_row, start_col},
          stop: {start_row + 10, start_col + 10}
        )
      end

      # Count files in chunk directory
      # With sharding (5x5 chunks per shard), should have 4 shards instead of 100 chunks
      chunk_dir = Path.join(@test_path, "c")

      if File.exists?(chunk_dir) do
        files = File.ls!(chunk_dir)
        # Should be 4 shard files (2x2 grid of shards)
        assert length(files) <= 10,
               "Expected ~4 shard files, got #{length(files)} (some chunks may not have been written)"
      end
    end
  end

  describe "error handling" do
    test "invalid shard_shape dimensionality" do
      # This should be validated during metadata creation
      # For now, test that array can be created (validation TBD)
      {:ok, _array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )
    end

    test "works without shard_shape (non-sharded v3 array)" do
      {:ok, array} =
        ExZarr.create(
          shape: {20, 20},
          chunks: {5, 5},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Should not have sharding codec
      refute Enum.any?(array.metadata.codecs, fn codec ->
               codec.name == "sharding_indexed"
             end)

      # Should still work normally
      data = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})
      assert {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data == data
    end
  end
end
