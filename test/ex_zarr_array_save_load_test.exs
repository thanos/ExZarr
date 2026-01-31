defmodule ExZarr.ArraySaveLoadTest do
  use ExUnit.Case, async: true
  alias ExZarr.Array

  @test_dir_base "/tmp/ex_zarr_save_load_test"

  setup do
    test_dir = "#{@test_dir_base}_#{System.unique_integer([:positive])}"
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  describe "Array.save for v2 format" do
    test "creates .zarray metadata file", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v2_array")

      {:ok, array} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          compressor: :zstd,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      # Save metadata
      assert :ok = Array.save(array, path: path)

      # Check .zarray file exists
      zarray_path = Path.join(path, ".zarray")
      assert File.exists?(zarray_path), ".zarray file should exist"

      # Check file has content
      stat = File.stat!(zarray_path)
      assert stat.size > 0, ".zarray file should have non-zero size"
      assert stat.size > 100, ".zarray should be at least 100 bytes"

      # Verify it's valid JSON
      {:ok, content} = File.read(zarray_path)
      {:ok, metadata} = Jason.decode(content)
      assert metadata["zarr_format"] == 2
      assert metadata["shape"] == [100, 100]
      assert metadata["chunks"] == [10, 10]
      assert metadata["dtype"] == "<i4"
    end

    test "writes chunk files with data", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v2_with_data")

      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          compressor: :zstd,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      # Save metadata first
      assert :ok = Array.save(array, path: path)

      # Write data to create chunks
      data = for i <- 0..399, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})

      # Check chunk files exist (v2 uses dot notation: 0.0, 0.1, 1.0, 1.1)
      expected_chunks = ["0.0", "0.1", "1.0", "1.1"]
      files = File.ls!(path)

      for chunk_name <- expected_chunks do
        assert chunk_name in files, "Chunk #{chunk_name} should exist"

        chunk_path = Path.join(path, chunk_name)
        stat = File.stat!(chunk_path)
        assert stat.size > 0, "Chunk #{chunk_name} should have non-zero size"
      end

      # Total files: .zarray + 4 chunks = 5 files
      assert length(files) >= 5, "Should have at least 5 files (.zarray + 4 chunks)"
    end

    test "Array.open can reopen saved v2 array", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v2_reopen")

      {:ok, array} =
        Array.create(
          shape: {30, 30},
          chunks: {10, 10},
          dtype: :float64,
          compressor: :gzip,
          fill_value: -1.0,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      # Save
      assert :ok = Array.save(array, path: path)

      # Write some data
      data = for i <- 0..299, into: <<>>, do: <<i * 1.0::float-little-64>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 30})

      # Reopen
      assert {:ok, reopened} = Array.open(path: path)

      # Verify structure
      assert reopened.shape == {30, 30}
      assert reopened.chunks == {10, 10}
      assert reopened.dtype == :float64
      assert reopened.compressor == :gzip
      assert reopened.fill_value == -1.0

      # Verify data
      {:ok, read_data} = Array.get_slice(reopened, start: {0, 0}, stop: {10, 30})
      assert read_data == data
    end

    test "measures v2 file sizes", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v2_sizes")

      {:ok, array} =
        Array.create(
          shape: {100, 100},
          chunks: {50, 50},
          dtype: :int32,
          compressor: :zstd,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      assert :ok = Array.save(array, path: path)

      # Write data to all 4 chunks (2x2 grid)
      data = for i <- 0..9999, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

      # Check total directory size
      files = File.ls!(path)

      total_size =
        files
        |> Enum.map(fn f -> File.stat!(Path.join(path, f)).size end)
        |> Enum.sum()

      # Uncompressed: 10,000 elements * 4 bytes = 40,000 bytes
      # With compression, should be much smaller
      uncompressed_size = 10_000 * 4
      assert total_size > 0, "Total size should be > 0"
      assert total_size < uncompressed_size, "Compressed size should be less than uncompressed"

      IO.puts("\nv2 Array statistics:")
      IO.puts("  Uncompressed: #{uncompressed_size} bytes")
      IO.puts("  On disk: #{total_size} bytes")
      IO.puts("  Compression ratio: #{Float.round(uncompressed_size / total_size, 2)}x")
    end
  end

  describe "Array.save for v3 format" do
    test "creates zarr.json metadata file", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v3_array")

      {:ok, array} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      # Save metadata
      assert :ok = Array.save(array, path: path)

      # Check zarr.json file exists (NOT .zarray)
      zarr_json_path = Path.join(path, "zarr.json")
      zarray_path = Path.join(path, ".zarray")

      assert File.exists?(zarr_json_path), "zarr.json file should exist"
      refute File.exists?(zarray_path), ".zarray file should NOT exist for v3"

      # Check file has content
      stat = File.stat!(zarr_json_path)
      assert stat.size > 0, "zarr.json file should have non-zero size"
      assert stat.size > 200, "zarr.json should be at least 200 bytes"

      # Verify it's valid JSON with v3 structure
      {:ok, content} = File.read(zarr_json_path)
      {:ok, metadata} = Jason.decode(content)
      assert metadata["zarr_format"] == 3
      assert metadata["node_type"] == "array"
      assert metadata["shape"] == [100, 100]
      assert is_map(metadata["chunk_grid"])
      assert is_list(metadata["codecs"])
      assert is_map(metadata["chunk_key_encoding"])
    end

    test "writes chunk files in c/ directory hierarchy", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v3_with_data")

      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      # Save metadata first
      assert :ok = Array.save(array, path: path)

      # Write data to create chunks
      data = for i <- 0..399, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})

      # Check c/ directory exists
      c_dir = Path.join(path, "c")
      assert File.exists?(c_dir), "c/ directory should exist"
      assert File.dir?(c_dir), "c/ should be a directory"

      # v3 uses hierarchical structure: c/0/0, c/0/1, c/1/0, c/1/1
      expected_chunk_paths = [
        Path.join([path, "c", "0", "0"]),
        Path.join([path, "c", "0", "1"]),
        Path.join([path, "c", "1", "0"]),
        Path.join([path, "c", "1", "1"])
      ]

      for chunk_path <- expected_chunk_paths do
        assert File.exists?(chunk_path), "Chunk #{chunk_path} should exist"

        stat = File.stat!(chunk_path)
        assert stat.size > 0, "Chunk #{chunk_path} should have non-zero size"
      end
    end

    test "Array.open can reopen saved v3 array", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v3_reopen")

      {:ok, array} =
        Array.create(
          shape: {30, 30},
          chunks: {10, 10},
          dtype: :float64,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          fill_value: -999.0,
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      # Save
      assert :ok = Array.save(array, path: path)

      # Write some data
      data = for i <- 0..299, into: <<>>, do: <<i * 1.5::float-little-64>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 30})

      # Reopen
      assert {:ok, reopened} = Array.open(path: path)

      # Verify structure
      assert reopened.shape == {30, 30}
      assert reopened.chunks == {10, 10}
      assert reopened.dtype == :float64
      assert reopened.fill_value == -999.0
      assert reopened.version == 3

      # Verify data
      {:ok, read_data} = Array.get_slice(reopened, start: {0, 0}, stop: {10, 30})
      assert read_data == data
    end

    test "measures v3 file sizes", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v3_sizes")

      {:ok, array} =
        Array.create(
          shape: {100, 100},
          chunks: {50, 50},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert :ok = Array.save(array, path: path)

      # Write data to all 4 chunks (2x2 grid)
      data = for i <- 0..9999, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

      # Recursively calculate directory size
      total_size = get_directory_size(path)
      uncompressed_size = 10_000 * 4

      assert total_size > 0, "Total size should be > 0"
      assert total_size < uncompressed_size, "Compressed size should be less than uncompressed"

      IO.puts("\nv3 Array statistics:")
      IO.puts("  Uncompressed: #{uncompressed_size} bytes")
      IO.puts("  On disk: #{total_size} bytes")
      IO.puts("  Compression ratio: #{Float.round(uncompressed_size / total_size, 2)}x")
    end

    test "auto-detects v3 format on open", %{test_dir: test_dir} do
      path = Path.join(test_dir, "v3_autodetect")

      {:ok, array} =
        Array.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      assert :ok = Array.save(array, path: path)

      # Open without specifying format
      assert {:ok, reopened} = Array.open(path: path)
      assert reopened.version == 3
    end
  end

  describe "v2 vs v3 file structure verification" do
    test "v2 creates flat chunk files, v3 creates hierarchical", %{test_dir: test_dir} do
      v2_path = Path.join(test_dir, "v2_structure")
      v3_path = Path.join(test_dir, "v3_structure")

      # Create v2 array
      {:ok, v2_array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          compressor: :zstd,
          zarr_version: 2,
          storage: :filesystem,
          path: v2_path
        )

      # Create v3 array
      {:ok, v3_array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :filesystem,
          path: v3_path
        )

      # Save both
      assert :ok = Array.save(v2_array, path: v2_path)
      assert :ok = Array.save(v3_array, path: v3_path)

      # Write same data to both
      data = for i <- 0..399, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(v2_array, data, start: {0, 0}, stop: {20, 20})
      assert :ok = Array.set_slice(v3_array, data, start: {0, 0}, stop: {20, 20})

      # Verify v2 structure
      v2_files = File.ls!(v2_path) |> Enum.sort()
      assert ".zarray" in v2_files, "v2 should have .zarray"
      assert "0.0" in v2_files, "v2 should have chunk 0.0"
      assert "0.1" in v2_files, "v2 should have chunk 0.1"
      assert "1.0" in v2_files, "v2 should have chunk 1.0"
      assert "1.1" in v2_files, "v2 should have chunk 1.1"
      refute "zarr.json" in v2_files, "v2 should NOT have zarr.json"
      refute "c" in v2_files, "v2 should NOT have c/ directory"

      # Verify v3 structure
      v3_files = File.ls!(v3_path) |> Enum.sort()
      assert "zarr.json" in v3_files, "v3 should have zarr.json"
      assert "c" in v3_files, "v3 should have c/ directory"
      refute ".zarray" in v3_files, "v3 should NOT have .zarray"

      # Verify v3 chunk hierarchy
      assert File.dir?(Path.join(v3_path, "c"))
      assert File.exists?(Path.join([v3_path, "c", "0", "0"]))
      assert File.exists?(Path.join([v3_path, "c", "0", "1"]))
      assert File.exists?(Path.join([v3_path, "c", "1", "0"]))
      assert File.exists?(Path.join([v3_path, "c", "1", "1"]))
    end

    test "both v2 and v3 store identical data correctly", %{test_dir: test_dir} do
      v2_path = Path.join(test_dir, "v2_data")
      v3_path = Path.join(test_dir, "v3_data")

      {:ok, v2_array} =
        Array.create(
          shape: {50, 50},
          chunks: {25, 25},
          dtype: :int32,
          compressor: :zstd,
          zarr_version: 2,
          storage: :filesystem,
          path: v2_path
        )

      {:ok, v3_array} =
        Array.create(
          shape: {50, 50},
          chunks: {25, 25},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :filesystem,
          path: v3_path
        )

      # Save both
      assert :ok = Array.save(v2_array, path: v2_path)
      assert :ok = Array.save(v3_array, path: v3_path)

      # Write same data to both
      data = for i <- 0..2499, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(v2_array, data, start: {0, 0}, stop: {50, 50})
      assert :ok = Array.set_slice(v3_array, data, start: {0, 0}, stop: {50, 50})

      # Reopen both
      {:ok, reopened_v2} = Array.open(path: v2_path)
      {:ok, reopened_v3} = Array.open(path: v3_path)

      # Read data from both
      {:ok, v2_data} = Array.get_slice(reopened_v2, start: {0, 0}, stop: {50, 50})
      {:ok, v3_data} = Array.get_slice(reopened_v3, start: {0, 0}, stop: {50, 50})

      # Both should return identical data
      assert v2_data == data
      assert v3_data == data
      assert v2_data == v3_data
    end
  end

  describe "Array.save edge cases" do
    test "save works without prior data writes", %{test_dir: test_dir} do
      path = Path.join(test_dir, "empty_array")

      {:ok, array} =
        Array.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      # Save without writing any data
      assert :ok = Array.save(array, path: path)

      # Metadata file should exist
      assert File.exists?(Path.join(path, ".zarray"))

      # Reopen
      assert {:ok, reopened} = Array.open(path: path)
      assert reopened.shape == {100}
    end

    test "save creates directory if it doesn't exist", %{test_dir: test_dir} do
      path = Path.join(test_dir, "nested/deep/path/array")

      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      # Array.create already creates the directory via Storage.init
      # This test verifies that save works with nested paths
      assert File.dir?(path)

      # Save should work
      assert :ok = Array.save(array, path: path)

      # Metadata file should exist
      assert File.exists?(Path.join(path, ".zarray"))
    end

    test "save with memory storage should return error or handle gracefully", %{
      test_dir: test_dir
    } do
      path = Path.join(test_dir, "memory_save_test")

      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          storage: :memory
        )

      # Attempting to save memory array to path
      # Should either:
      # 1. Return an error
      # 2. Switch to filesystem storage
      # 3. Ignore the operation
      result = Array.save(array, path: path)

      # Document actual behavior
      IO.puts("\nMemory array save result: #{inspect(result)}")

      case result do
        :ok ->
          # If it returns :ok, verify if files were created
          if File.exists?(path) do
            IO.puts("Files created: #{inspect(File.ls!(path))}")
          else
            IO.puts("No files created despite :ok return")
          end

        {:error, reason} ->
          IO.puts("Returned error as expected: #{inspect(reason)}")

        other ->
          IO.puts("Unexpected result: #{inspect(other)}")
      end
    end

    test "create in memory, save to file, then reopen from file (v2)", %{test_dir: test_dir} do
      path = Path.join(test_dir, "memory_to_file_v2")

      # Step 1: Create array in memory
      {:ok, mem_array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          compressor: :zstd,
          zarr_version: 2,
          storage: :memory
        )

      # Verify it's in memory
      assert mem_array.storage.backend == :memory

      # Step 2: Write some data to memory array
      data = for i <- 0..399, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(mem_array, data, start: {0, 0}, stop: {20, 20})

      # Verify we can read from memory
      {:ok, read_from_memory} = Array.get_slice(mem_array, start: {0, 0}, stop: {20, 20})
      assert read_from_memory == data

      # Step 3: Transfer from memory to filesystem
      # Create filesystem array with same structure
      {:ok, file_array} =
        Array.create(
          shape: mem_array.shape,
          chunks: mem_array.chunks,
          dtype: mem_array.dtype,
          compressor: mem_array.compressor,
          fill_value: mem_array.fill_value,
          zarr_version: 2,
          storage: :filesystem,
          path: path
        )

      # Copy data from memory to filesystem
      {:ok, mem_data} = Array.get_slice(mem_array, start: {0, 0}, stop: {20, 20})
      assert :ok = Array.set_slice(file_array, mem_data, start: {0, 0}, stop: {20, 20})

      # Save filesystem array metadata
      assert :ok = Array.save(file_array, path: path)

      # Verify files were created
      assert File.exists?(path)
      assert File.exists?(Path.join(path, ".zarray"))

      # Verify chunks were written
      chunk_files =
        File.ls!(path)
        |> Enum.reject(fn f -> String.starts_with?(f, ".") or String.contains?(f, ".lock") end)

      assert length(chunk_files) == 4, "Should have 4 chunks (2x2 grid)"

      # Step 4: Reopen from filesystem
      {:ok, reopened} = Array.open(path: path)

      # Verify it's now using filesystem storage
      assert reopened.storage.backend == :filesystem
      assert reopened.storage.state.path == path

      # Verify structure matches
      assert reopened.shape == {20, 20}
      assert reopened.chunks == {10, 10}
      assert reopened.dtype == :int32
      assert reopened.compressor == :zstd

      # Step 5: Verify data roundtrip
      {:ok, read_from_file} = Array.get_slice(reopened, start: {0, 0}, stop: {20, 20})
      assert read_from_file == data
    end

    test "create in memory, save to file, then reopen from file (v3)", %{test_dir: test_dir} do
      path = Path.join(test_dir, "memory_to_file_v3")

      # Step 1: Create array in memory
      {:ok, mem_array} =
        Array.create(
          shape: {30, 30},
          chunks: {10, 10},
          dtype: :float64,
          codecs: [%{name: "bytes"}, %{name: "zstd", configuration: %{level: 3}}],
          zarr_version: 3,
          storage: :memory
        )

      # Verify it's in memory
      assert mem_array.storage.backend == :memory
      assert mem_array.version == 3

      # Step 2: Write some data to memory array
      data = for i <- 0..899, into: <<>>, do: <<i * 1.0::float-little-64>>
      assert :ok = Array.set_slice(mem_array, data, start: {0, 0}, stop: {30, 30})

      # Verify we can read from memory
      {:ok, read_from_memory} = Array.get_slice(mem_array, start: {0, 0}, stop: {30, 30})
      assert read_from_memory == data

      # Step 3: Transfer from memory to filesystem
      # Create filesystem array with same structure
      {:ok, file_array} =
        Array.create(
          shape: mem_array.shape,
          chunks: mem_array.chunks,
          dtype: mem_array.dtype,
          codecs: mem_array.metadata.codecs,
          fill_value: mem_array.fill_value,
          zarr_version: 3,
          storage: :filesystem,
          path: path
        )

      # Copy data from memory to filesystem
      {:ok, mem_data} = Array.get_slice(mem_array, start: {0, 0}, stop: {30, 30})
      assert :ok = Array.set_slice(file_array, mem_data, start: {0, 0}, stop: {30, 30})

      # Save filesystem array metadata
      assert :ok = Array.save(file_array, path: path)

      # Verify files were created
      assert File.exists?(path)
      assert File.exists?(Path.join(path, "zarr.json"))

      # Verify v3 hierarchical structure
      c_dir = Path.join(path, "c")
      assert File.dir?(c_dir)

      # Step 4: Reopen from filesystem
      {:ok, reopened} = Array.open(path: path)

      # Verify it's now using filesystem storage
      assert reopened.storage.backend == :filesystem
      assert reopened.storage.state.path == path
      assert reopened.version == 3

      # Verify structure matches
      assert reopened.shape == {30, 30}
      assert reopened.chunks == {10, 10}
      assert reopened.dtype == :float64

      # Step 5: Verify data roundtrip
      {:ok, read_from_file} = Array.get_slice(reopened, start: {0, 0}, stop: {30, 30})
      assert read_from_file == data
    end
  end

  describe "Array.save with different compressors" do
    test "v2: save/load with gzip", %{test_dir: test_dir} do
      test_compressor_roundtrip(test_dir, "v2_gzip", 2, :gzip, nil)
    end

    test "v2: save/load with zlib", %{test_dir: test_dir} do
      test_compressor_roundtrip(test_dir, "v2_zlib", 2, :zlib, nil)
    end

    test "v2: save/load with zstd", %{test_dir: test_dir} do
      test_compressor_roundtrip(test_dir, "v2_zstd", 2, :zstd, nil)
    end

    test "v2: save/load with blosc", %{test_dir: test_dir} do
      test_compressor_roundtrip(test_dir, "v2_blosc", 2, :blosc, nil)
    end

    test "v2: save/load with no compression", %{test_dir: test_dir} do
      test_compressor_roundtrip(test_dir, "v2_none", 2, :none, nil)
    end

    test "v3: save/load with gzip", %{test_dir: test_dir} do
      codecs = [%{name: "bytes"}, %{name: "gzip"}]
      test_compressor_roundtrip(test_dir, "v3_gzip", 3, nil, codecs)
    end

    test "v3: save/load with zstd", %{test_dir: test_dir} do
      codecs = [%{name: "bytes"}, %{name: "zstd"}]
      test_compressor_roundtrip(test_dir, "v3_zstd", 3, nil, codecs)
    end

    test "v3: save/load with no compression", %{test_dir: test_dir} do
      codecs = [%{name: "bytes"}]
      test_compressor_roundtrip(test_dir, "v3_bytes_only", 3, nil, codecs)
    end
  end

  # Helper functions

  defp test_compressor_roundtrip(base_dir, name, zarr_format, compressor, codecs) do
    path = Path.join(base_dir, name)

    opts =
      [
        shape: {100},
        chunks: {20},
        dtype: :int32,
        storage: :filesystem,
        path: path,
        zarr_version: zarr_format
      ]
      |> maybe_add(:compressor, compressor)
      |> maybe_add(:codecs, codecs)

    {:ok, array} = Array.create(opts)

    # Save
    assert :ok = Array.save(array, path: path)

    # Verify metadata file exists
    metadata_file =
      if zarr_format == 2,
        do: Path.join(path, ".zarray"),
        else: Path.join(path, "zarr.json")

    assert File.exists?(metadata_file), "Metadata file #{metadata_file} should exist"
    assert File.stat!(metadata_file).size > 0, "Metadata file should have content"

    # Write data
    data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
    assert :ok = Array.set_slice(array, data, start: {0}, stop: {100})

    # Count chunk files
    chunk_count = count_chunk_files(path, zarr_format)
    assert chunk_count == 5, "Should have 5 chunks (100 elements / 20 chunk size)"

    # Verify each chunk has non-zero size
    verify_chunk_sizes(path, zarr_format)

    # Reopen
    {:ok, reopened} = Array.open(path: path)

    # Verify data roundtrip
    {:ok, read_data} = Array.get_slice(reopened, start: {0}, stop: {100})
    assert read_data == data
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp count_chunk_files(path, 2) do
    # v2: flat files like "0", "1", "2", etc.
    # Exclude metadata files (start with ".") and lock files (contain ".lock")
    File.ls!(path)
    |> Enum.reject(fn f -> String.starts_with?(f, ".") or String.contains?(f, ".lock") end)
    |> length()
  end

  defp count_chunk_files(path, 3) do
    # v3: hierarchical in c/ directory
    c_dir = Path.join(path, "c")

    if File.exists?(c_dir) do
      count_files_recursive(c_dir)
    else
      0
    end
  end

  defp count_files_recursive(dir) do
    File.ls!(dir)
    |> Enum.reduce(0, fn entry, acc ->
      full_path = Path.join(dir, entry)

      if File.dir?(full_path) do
        acc + count_files_recursive(full_path)
      else
        # Only count actual chunk files, not lock files
        if String.contains?(entry, ".lock") do
          acc
        else
          acc + 1
        end
      end
    end)
  end

  defp verify_chunk_sizes(path, 2) do
    File.ls!(path)
    |> Enum.reject(fn f -> String.starts_with?(f, ".") or String.contains?(f, ".lock") end)
    |> Enum.each(fn chunk_file ->
      chunk_path = Path.join(path, chunk_file)
      stat = File.stat!(chunk_path)
      assert stat.size > 0, "v2 chunk #{chunk_file} should have non-zero size"
    end)
  end

  defp verify_chunk_sizes(path, 3) do
    c_dir = Path.join(path, "c")
    verify_all_files_in_tree(c_dir)
  end

  defp verify_all_files_in_tree(dir) do
    File.ls!(dir)
    |> Enum.each(fn entry ->
      full_path = Path.join(dir, entry)

      if File.dir?(full_path) do
        verify_all_files_in_tree(full_path)
      else
        # Skip lock files
        unless String.contains?(entry, ".lock") do
          stat = File.stat!(full_path)
          assert stat.size > 0, "v3 chunk #{full_path} should have non-zero size"
        end
      end
    end)
  end

  defp get_directory_size(path) do
    File.ls!(path)
    |> Enum.reduce(0, fn entry, acc ->
      full_path = Path.join(path, entry)

      if File.dir?(full_path) do
        acc + get_directory_size(full_path)
      else
        acc + File.stat!(full_path).size
      end
    end)
  end
end
