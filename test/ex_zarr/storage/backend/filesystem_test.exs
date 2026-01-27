defmodule ExZarr.Storage.Backend.FilesystemTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.Filesystem

  @temp_dir_base System.tmp_dir!()

  setup do
    # Create unique temp directory for each test
    temp_dir = Path.join(@temp_dir_base, "zarr_test_#{:rand.uniform(1_000_000)}")
    on_exit(fn -> File.rm_rf(temp_dir) end)
    {:ok, temp_dir: temp_dir}
  end

  describe "init/1" do
    test "initializes with valid path", %{temp_dir: temp_dir} do
      assert {:ok, state} = Filesystem.init(path: temp_dir)
      assert state.path == temp_dir
      assert state.use_file_locks == true
      assert File.exists?(temp_dir)
    end

    test "initializes with use_file_locks disabled", %{temp_dir: temp_dir} do
      assert {:ok, state} = Filesystem.init(path: temp_dir, use_file_locks: false)
      assert state.use_file_locks == false
    end

    test "creates directory if it doesn't exist", %{temp_dir: temp_dir} do
      nested_path = Path.join(temp_dir, "nested/deep/path")
      assert {:ok, _state} = Filesystem.init(path: nested_path)
      assert File.exists?(nested_path)
    end

    test "returns error for missing path" do
      assert {:error, :path_required} = Filesystem.init([])
    end

    test "returns error for nil path" do
      assert {:error, :path_required} = Filesystem.init(path: nil)
    end

    test "returns error for invalid path type" do
      assert {:error, :invalid_path} = Filesystem.init(path: 123)
    end
  end

  describe "open/1" do
    test "opens existing path", %{temp_dir: temp_dir} do
      File.mkdir_p!(temp_dir)
      assert {:ok, state} = Filesystem.open(path: temp_dir)
      assert state.path == temp_dir
      assert state.use_file_locks == true
    end

    test "opens with use_file_locks disabled", %{temp_dir: temp_dir} do
      File.mkdir_p!(temp_dir)
      assert {:ok, state} = Filesystem.open(path: temp_dir, use_file_locks: false)
      assert state.use_file_locks == false
    end

    test "returns error for nonexistent path", %{temp_dir: temp_dir} do
      nonexistent = Path.join(temp_dir, "does_not_exist")
      assert {:error, :not_found} = Filesystem.open(path: nonexistent)
    end

    test "returns error for missing path config" do
      assert {:error, :path_required} = Filesystem.open([])
    end

    test "returns error for nil path" do
      assert {:error, :path_required} = Filesystem.open(path: nil)
    end

    test "returns error for invalid path type" do
      assert {:error, :invalid_path} = Filesystem.open(path: :invalid)
    end
  end

  describe "write_chunk/3 and read_chunk/2" do
    test "writes and reads chunk with file locks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir, use_file_locks: true)
      chunk_data = <<1, 2, 3, 4, 5>>
      chunk_index = {0, 0}

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)
    end

    test "writes and reads chunk without file locks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir, use_file_locks: false)
      chunk_data = <<10, 20, 30>>
      chunk_index = {1, 2}

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)
    end

    test "reads nonexistent chunk returns error", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      assert {:error, :not_found} = Filesystem.read_chunk(state, {99, 99})
    end

    test "writes and reads 1D chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      chunk_data = <<42>>
      chunk_index = {5}

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)
    end

    test "writes and reads 3D chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      chunk_data = <<1, 2, 3>>
      chunk_index = {1, 2, 3}

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)
    end

    test "overwrites existing chunk", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      chunk_index = {0, 0}
      original = <<1, 2, 3>>
      updated = <<4, 5, 6, 7>>

      assert :ok = Filesystem.write_chunk(state, chunk_index, original)
      assert {:ok, ^original} = Filesystem.read_chunk(state, chunk_index)

      assert :ok = Filesystem.write_chunk(state, chunk_index, updated)
      assert {:ok, ^updated} = Filesystem.read_chunk(state, chunk_index)
    end

    test "handles large chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      # 1MB chunk
      chunk_data = :binary.copy(<<42>>, 1_000_000)
      chunk_index = {0}

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)
    end

    test "handles empty chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      chunk_data = <<>>
      chunk_index = {0}

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)
    end
  end

  describe "write_metadata/3 and read_metadata/1" do
    test "writes and reads v2 metadata", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)

      metadata = %{
        "zarr_format" => 2,
        "shape" => [100, 100],
        "chunks" => [10, 10],
        "dtype" => "<f8",
        "compressor" => %{"id" => "zlib", "level" => 5},
        "fill_value" => 0.0,
        "order" => "C"
      }

      json = Jason.encode!(metadata, pretty: true)
      assert :ok = Filesystem.write_metadata(state, json, [])

      # Verify .zarray file was created
      assert File.exists?(Path.join(temp_dir, ".zarray"))

      assert {:ok, read_json} = Filesystem.read_metadata(state)
      assert {:ok, read_map} = Jason.decode(read_json)
      assert read_map["zarr_format"] == 2
      assert read_map["shape"] == [100, 100]
    end

    test "writes and reads v3 metadata", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)

      metadata = %{
        "zarr_format" => 3,
        "node_type" => "array",
        "shape" => [100, 100],
        "data_type" => "float64",
        "chunk_grid" => %{
          "name" => "regular",
          "configuration" => %{"chunk_shape" => [10, 10]}
        }
      }

      json = Jason.encode!(metadata, pretty: true)
      assert :ok = Filesystem.write_metadata(state, json, [])

      # Verify zarr.json file was created
      assert File.exists?(Path.join(temp_dir, "zarr.json"))

      assert {:ok, read_json} = Filesystem.read_metadata(state)
      assert {:ok, read_map} = Jason.decode(read_json)
      assert read_map["zarr_format"] == 3
    end

    test "writes metadata from map", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)

      metadata_map = %{
        "zarr_format" => 2,
        "shape" => [50],
        "chunks" => [10],
        "dtype" => "<i4"
      }

      assert :ok = Filesystem.write_metadata(state, metadata_map, [])
      assert File.exists?(Path.join(temp_dir, ".zarray"))
    end

    test "reads nonexistent metadata returns error", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      assert {:error, :not_found} = Filesystem.read_metadata(state)
    end

    test "overwrites existing metadata", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)

      metadata1 = %{"zarr_format" => 2, "shape" => [100]}
      json1 = Jason.encode!(metadata1)
      assert :ok = Filesystem.write_metadata(state, json1, [])

      metadata2 = %{"zarr_format" => 2, "shape" => [200]}
      json2 = Jason.encode!(metadata2)
      assert :ok = Filesystem.write_metadata(state, json2, [])

      assert {:ok, read_json} = Filesystem.read_metadata(state)
      assert {:ok, read_map} = Jason.decode(read_json)
      assert read_map["shape"] == [200]
    end
  end

  describe "list_chunks/1" do
    test "lists no chunks when empty", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      assert {:ok, []} = Filesystem.list_chunks(state)
    end

    test "lists single chunk", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      chunk_index = {0, 0}
      assert :ok = Filesystem.write_chunk(state, chunk_index, <<1, 2, 3>>)

      assert {:ok, chunks} = Filesystem.list_chunks(state)
      assert length(chunks) == 1
      assert chunk_index in chunks
    end

    test "lists multiple chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      indices = [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      for index <- indices do
        assert :ok = Filesystem.write_chunk(state, index, <<1>>)
      end

      assert {:ok, chunks} = Filesystem.list_chunks(state)
      assert length(chunks) == 4

      for index <- indices do
        assert index in chunks
      end
    end

    test "ignores metadata files", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)

      # Write metadata file
      File.write!(Path.join(temp_dir, ".zarray"), "{}")
      File.write!(Path.join(temp_dir, ".zattrs"), "{}")

      # Write chunk
      assert :ok = Filesystem.write_chunk(state, {0}, <<1>>)

      assert {:ok, chunks} = Filesystem.list_chunks(state)
      assert length(chunks) == 1
      assert {0} in chunks
    end

    test "lists 1D chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)

      for i <- 0..3 do
        assert :ok = Filesystem.write_chunk(state, {i}, <<i>>)
      end

      assert {:ok, chunks} = Filesystem.list_chunks(state)
      assert length(chunks) == 4
    end

    test "lists 3D chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      indices = [{0, 0, 0}, {0, 0, 1}, {1, 1, 1}]

      for index <- indices do
        assert :ok = Filesystem.write_chunk(state, index, <<1>>)
      end

      assert {:ok, chunks} = Filesystem.list_chunks(state)
      assert length(chunks) == 3

      for index <- indices do
        assert index in chunks
      end
    end
  end

  describe "delete_chunk/2" do
    test "deletes existing chunk", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3>>

      assert :ok = Filesystem.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Filesystem.read_chunk(state, chunk_index)

      assert :ok = Filesystem.delete_chunk(state, chunk_index)
      assert {:error, :not_found} = Filesystem.read_chunk(state, chunk_index)
    end

    test "deleting nonexistent chunk returns ok (idempotent)", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      assert :ok = Filesystem.delete_chunk(state, {99, 99})
    end

    test "deletes multiple chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      indices = [{0, 0}, {0, 1}, {1, 0}]

      for index <- indices do
        assert :ok = Filesystem.write_chunk(state, index, <<1>>)
      end

      for index <- indices do
        assert :ok = Filesystem.delete_chunk(state, index)
        assert {:error, :not_found} = Filesystem.read_chunk(state, index)
      end
    end

    test "list_chunks excludes deleted chunks", %{temp_dir: temp_dir} do
      {:ok, state} = Filesystem.init(path: temp_dir)
      indices = [{0, 0}, {0, 1}, {1, 0}]

      for index <- indices do
        assert :ok = Filesystem.write_chunk(state, index, <<1>>)
      end

      assert :ok = Filesystem.delete_chunk(state, {0, 1})

      assert {:ok, chunks} = Filesystem.list_chunks(state)
      assert length(chunks) == 2
      assert {0, 0} in chunks
      assert {1, 0} in chunks
      refute {0, 1} in chunks
    end
  end

  describe "exists?/1" do
    test "returns true for existing path", %{temp_dir: temp_dir} do
      File.mkdir_p!(temp_dir)
      assert Filesystem.exists?(path: temp_dir) == true
    end

    test "returns false for nonexistent path", %{temp_dir: temp_dir} do
      nonexistent = Path.join(temp_dir, "does_not_exist")
      assert Filesystem.exists?(path: nonexistent) == false
    end

    test "returns false for missing path config" do
      assert Filesystem.exists?([]) == false
    end

    test "returns false for nil path" do
      assert Filesystem.exists?(path: nil) == false
    end

    test "returns false for invalid path type" do
      assert Filesystem.exists?(path: 123) == false
    end
  end

  describe "backend_id/0" do
    test "returns :filesystem" do
      assert Filesystem.backend_id() == :filesystem
    end
  end
end
