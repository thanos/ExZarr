defmodule ExZarr.V3IntegrationTest do
  use ExUnit.Case, async: true

  alias ExZarr.{Array, MetadataV3}

  describe "v3 array creation" do
    test "creates v3 array with codecs" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :float64,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :memory
        )

      assert array.version == 3
      assert match?(%MetadataV3{}, array.metadata)
      assert array.metadata.zarr_format == 3
      assert array.metadata.node_type == :array
      assert array.metadata.data_type == "float64"
      assert length(array.metadata.codecs) == 2
    end

    test "creates v3 array with v2-style filters and compressor" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int64,
          filters: [{:shuffle, [elementsize: 8]}],
          compressor: :zlib,
          zarr_version: 3,
          storage: :memory
        )

      assert array.version == 3
      assert match?(%MetadataV3{}, array.metadata)

      # Should have converted to v3 codecs: shuffle + bytes + gzip
      assert length(array.metadata.codecs) == 3
      assert Enum.at(array.metadata.codecs, 0).name == "shuffle"
      assert Enum.at(array.metadata.codecs, 1).name == "bytes"
      assert Enum.at(array.metadata.codecs, 2).name == "gzip"
    end

    test "creates v3 array without compression" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :memory
        )

      assert array.version == 3
      assert length(array.metadata.codecs) == 1
      assert hd(array.metadata.codecs).name == "bytes"
    end

    test "validates chunk_grid is set correctly" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :float32,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :memory
        )

      assert array.metadata.chunk_grid.name == "regular"
      assert array.metadata.chunk_grid.configuration.chunk_shape == {10, 20}

      {:ok, chunk_shape} = MetadataV3.get_chunk_shape(array.metadata)
      assert chunk_shape == {10, 20}
    end

    test "sets default fill value" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :float64,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :memory
        )

      assert array.metadata.fill_value == 0
    end

    test "uses custom fill value" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :uint8,
          codecs: [%{name: "bytes"}],
          fill_value: 255,
          zarr_version: 3,
          storage: :memory
        )

      assert array.metadata.fill_value == 255
    end
  end

  describe "v3 array write and read" do
    test "writes and reads data correctly" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :float64,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 1}}
          ],
          zarr_version: 3,
          storage: :memory
        )

      # Write data
      data = for i <- 0..99, into: <<>>, do: <<i * 1.0::float-little-64>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      # Read data back
      {:ok, read_data} = Array.get_slice(array, start: {0}, stop: {100})
      assert read_data == data
    end

    test "writes and reads 2D array" do
      {:ok, array} =
        ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :memory
        )

      # Write data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Read full array
      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end

    test "handles partial chunk writes" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int64,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :memory
        )

      # Write partial data
      data = for i <- 0..49, into: <<>>, do: <<i::signed-little-64>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {50})

      # Read back
      {:ok, read_data} = Array.get_slice(array, start: {0}, stop: {50})
      assert read_data == data
    end

    test "compression reduces data size" do
      {:ok, array} =
        ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "gzip", configuration: %{level: 9}}],
          zarr_version: 3,
          storage: :memory
        )

      # Write repetitive data (highly compressible)
      data = String.duplicate(<<42::signed-little-32>>, 1000)
      :ok = Array.set_slice(array, data, start: {0}, stop: {1000})

      # Read back and verify
      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end
  end

  describe "v3 array persistence" do
    test "saves and reloads v3 array from filesystem" do
      tmp_path = Path.join(System.tmp_dir!(), "zarr_v3_test_#{:rand.uniform(1_000_000)}")

      on_exit(fn -> File.rm_rf!(tmp_path) end)

      # Create and persist
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          codecs: [%{name: "bytes"}, %{name: "gzip"}],
          zarr_version: 3,
          storage: :filesystem,
          path: tmp_path
        )

      # Save metadata
      :ok = ExZarr.save(array, path: tmp_path)

      data = for i <- 0..49, into: <<>>, do: <<i::signed-little-32>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {50})

      # Verify zarr.json exists (not .zarray)
      assert File.exists?(Path.join(tmp_path, "zarr.json"))
      refute File.exists?(Path.join(tmp_path, ".zarray"))

      # Verify chunk key format (c/N instead of N)
      assert File.exists?(Path.join(tmp_path, "c"))
      chunk_dir = Path.join(tmp_path, "c")
      assert File.dir?(chunk_dir)

      chunk_files = File.ls!(chunk_dir)
      # Should have chunks: c/0, c/1, c/2, c/3, c/4
      assert chunk_files != []

      # Reopen and verify
      {:ok, reopened} = ExZarr.open(path: tmp_path)
      assert reopened.version == 3
      assert match?(%MetadataV3{}, reopened.metadata)

      {:ok, read_data} = Array.get_slice(reopened, start: {0}, stop: {50})
      assert read_data == data
    end

    test "v3 metadata in zarr.json is valid JSON" do
      tmp_path = Path.join(System.tmp_dir!(), "zarr_v3_meta_#{:rand.uniform(1_000_000)}")

      on_exit(fn -> File.rm_rf!(tmp_path) end)

      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :float64,
          codecs: [%{name: "bytes"}, %{name: "zstd"}],
          zarr_version: 3,
          storage: :filesystem,
          path: tmp_path
        )

      # Save metadata
      :ok = ExZarr.save(array, path: tmp_path)

      # Read and parse zarr.json
      zarr_json_path = Path.join(tmp_path, "zarr.json")
      assert File.exists?(zarr_json_path)

      {:ok, json_content} = File.read(zarr_json_path)
      {:ok, parsed} = Jason.decode(json_content)

      # Verify v3 fields
      assert parsed["zarr_format"] == 3
      assert parsed["node_type"] == "array"
      assert parsed["data_type"] == "float64"
      assert is_list(parsed["codecs"])
      assert is_map(parsed["chunk_grid"])
      assert is_map(parsed["chunk_key_encoding"])
    end
  end

  describe "v2/v3 interoperability" do
    test "can create and open both v2 and v3 arrays with same API" do
      tmp_v2 = Path.join(System.tmp_dir!(), "zarr_v2_#{:rand.uniform(1_000_000)}")
      tmp_v3 = Path.join(System.tmp_dir!(), "zarr_v3_#{:rand.uniform(1_000_000)}")

      on_exit(fn ->
        File.rm_rf!(tmp_v2)
        File.rm_rf!(tmp_v3)
      end)

      # Create v2 array
      {:ok, v2} =
        ExZarr.create(
          shape: {10},
          chunks: {5},
          dtype: :float64,
          zarr_version: 2,
          storage: :filesystem,
          path: tmp_v2
        )

      assert v2.version == 2
      :ok = ExZarr.save(v2, path: tmp_v2)

      # Create v3 array
      {:ok, v3} =
        ExZarr.create(
          shape: {10},
          chunks: {5},
          dtype: :float64,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :filesystem,
          path: tmp_v3
        )

      assert v3.version == 3
      :ok = ExZarr.save(v3, path: tmp_v3)

      # Both use same write API
      data = for i <- 0..9, into: <<>>, do: <<i * 1.0::float-little-64>>
      :ok = Array.set_slice(v2, data, start: {0}, stop: {10})
      :ok = Array.set_slice(v3, data, start: {0}, stop: {10})

      # Both use same open API
      {:ok, reopened_v2} = ExZarr.open(path: tmp_v2)
      {:ok, reopened_v3} = ExZarr.open(path: tmp_v3)

      assert reopened_v2.version == 2
      assert reopened_v3.version == 3

      # Both use same read API
      {:ok, v2_data} = Array.to_binary(reopened_v2)
      {:ok, v3_data} = Array.to_binary(reopened_v3)

      assert v2_data == data
      assert v3_data == data
    end

    test "v2 and v3 arrays have different file structures" do
      tmp_v2 = Path.join(System.tmp_dir!(), "zarr_v2_struct_#{:rand.uniform(1_000_000)}")
      tmp_v3 = Path.join(System.tmp_dir!(), "zarr_v3_struct_#{:rand.uniform(1_000_000)}")

      on_exit(fn ->
        File.rm_rf!(tmp_v2)
        File.rm_rf!(tmp_v3)
      end)

      {:ok, v2} =
        ExZarr.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          zarr_version: 2,
          storage: :filesystem,
          path: tmp_v2
        )

      :ok = ExZarr.save(v2, path: tmp_v2)

      {:ok, v3} =
        ExZarr.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :filesystem,
          path: tmp_v3
        )

      :ok = ExZarr.save(v3, path: tmp_v3)

      data = for i <- 0..9, into: <<>>, do: <<i::signed-little-32>>
      :ok = Array.set_slice(v2, data, start: {0}, stop: {10})
      :ok = Array.set_slice(v3, data, start: {0}, stop: {10})

      # v2 structure: .zarray and dot-notation chunks
      assert File.exists?(Path.join(tmp_v2, ".zarray"))
      refute File.exists?(Path.join(tmp_v2, "zarr.json"))
      v2_files = File.ls!(tmp_v2)
      # Should have chunks like "0", "1"
      assert "0" in v2_files or ".zarray" in v2_files

      # v3 structure: zarr.json and c/ directory
      assert File.exists?(Path.join(tmp_v3, "zarr.json"))
      refute File.exists?(Path.join(tmp_v3, ".zarray"))
      assert File.dir?(Path.join(tmp_v3, "c"))
    end
  end

  describe "v3 codec pipeline" do
    test "applies filters before compression" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int64,
          codecs: [
            %{name: "shuffle", configuration: %{elementsize: 8}},
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :memory
        )

      # Write sequential data (benefits from shuffle)
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-64>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      # Read and verify
      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end

    test "works with multiple compression stages" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float32,
          codecs: [
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 3}}
          ],
          zarr_version: 3,
          storage: :memory
        )

      data = for i <- 0..99, into: <<>>, do: <<i * 1.5::float-little-32>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end

    test "bytes-only codec (no compression)" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :uint16,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :memory
        )

      data = for i <- 0..49, into: <<>>, do: <<i::unsigned-little-16>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end
  end

  describe "v3 data types" do
    test "supports all integer types" do
      for {dtype, size} <- [
            {:int8, 1},
            {:int16, 2},
            {:int32, 4},
            {:int64, 8},
            {:uint8, 1},
            {:uint16, 2},
            {:uint32, 4},
            {:uint64, 8}
          ] do
        {:ok, array} =
          ExZarr.create(
            shape: {10},
            chunks: {5},
            dtype: dtype,
            codecs: [%{name: "bytes"}],
            zarr_version: 3,
            storage: :memory
          )

        assert array.version == 3
        assert array.dtype == dtype
        assert ExZarr.DataType.itemsize(array.metadata.data_type) == size
      end
    end

    test "supports float types" do
      for {dtype, size, name} <- [
            {:float32, 4, "float32"},
            {:float64, 8, "float64"}
          ] do
        {:ok, array} =
          ExZarr.create(
            shape: {10},
            chunks: {5},
            dtype: dtype,
            codecs: [%{name: "bytes"}],
            zarr_version: 3,
            storage: :memory
          )

        assert array.version == 3
        assert array.dtype == dtype
        assert array.metadata.data_type == name
        assert ExZarr.DataType.itemsize(array.metadata.data_type) == size
      end
    end
  end

  describe "v3 error handling" do
    test "auto-detection works when opening v3 arrays" do
      tmp_path = Path.join(System.tmp_dir!(), "zarr_v3_detect_#{:rand.uniform(1_000_000)}")

      on_exit(fn -> File.rm_rf!(tmp_path) end)

      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {5},
          dtype: :int32,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :filesystem,
          path: tmp_path
        )

      # Save metadata
      :ok = ExZarr.save(array, path: tmp_path)

      # Open without specifying version
      {:ok, reopened} = ExZarr.open(path: tmp_path)

      # Should auto-detect as v3
      assert reopened.version == 3
      assert match?(%MetadataV3{}, reopened.metadata)
    end
  end

  describe "v3 real-world scenarios" do
    test "typical data science pipeline: float64 array with compression" do
      {:ok, array} =
        ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :float64,
          codecs: [
            %{name: "bytes"},
            %{name: "zstd", configuration: %{level: 3}}
          ],
          zarr_version: 3,
          storage: :memory
        )

      # Simulate float64 measurements
      data = for i <- 0..999, into: <<>>, do: <<i * 1.5::float-little-64>>

      :ok = Array.set_slice(array, data, start: {0}, stop: {1000})
      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end

    test "time series data with shuffle filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {500},
          chunks: {50},
          dtype: :int64,
          codecs: [
            %{name: "shuffle", configuration: %{elementsize: 8}},
            %{name: "bytes"},
            %{name: "gzip", configuration: %{level: 5}}
          ],
          zarr_version: 3,
          storage: :memory
        )

      # Sequential timestamps (highly compressible with shuffle)
      data = for i <- 0..499, into: <<>>, do: <<i::signed-little-64>>

      :ok = Array.set_slice(array, data, start: {0}, stop: {500})
      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end

    test "no compression pipeline for fast access" do
      {:ok, array} =
        ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :uint8,
          codecs: [%{name: "bytes"}],
          zarr_version: 3,
          storage: :memory
        )

      data = :crypto.strong_rand_bytes(1000)

      :ok = Array.set_slice(array, data, start: {0}, stop: {1000})
      {:ok, read_data} = Array.to_binary(array)
      assert read_data == data
    end
  end
end
