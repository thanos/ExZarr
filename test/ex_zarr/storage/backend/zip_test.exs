defmodule ExZarr.Storage.Backend.ZipTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.Zip

  @temp_dir_base System.tmp_dir!()

  setup do
    # Create unique temp file for each test
    zip_path = Path.join(@temp_dir_base, "zarr_test_#{:rand.uniform(1_000_000)}.zip")
    on_exit(fn -> File.rm(zip_path) end)
    {:ok, zip_path: zip_path}
  end

  describe "init/1" do
    test "initializes with valid path", %{zip_path: zip_path} do
      assert {:ok, state} = Zip.init(path: zip_path)
      assert state.path == zip_path
      assert is_pid(state.agent)
    end

    test "returns error for missing path" do
      assert {:error, :path_required} = Zip.init([])
    end

    test "returns error for nil path" do
      assert {:error, :path_required} = Zip.init(path: nil)
    end

    test "returns error for invalid path type" do
      assert {:error, :invalid_path} = Zip.init(path: 123)
    end
  end

  describe "open/1" do
    test "opens existing zip file with chunks", %{zip_path: zip_path} do
      # Create a zip file first
      {:ok, state} = Zip.init(path: zip_path)
      chunk_data = <<1, 2, 3, 4>>
      chunk_index = {0, 0}
      :ok = Zip.write_chunk(state, chunk_index, chunk_data)

      metadata = %{"zarr_format" => 2, "shape" => [10], "chunks" => [5]}
      :ok = Zip.write_metadata(state, metadata, [])

      # Now open the zip file
      assert {:ok, opened_state} = Zip.open(path: zip_path)
      assert opened_state.path == zip_path
      assert is_pid(opened_state.agent)

      # Verify chunk was loaded
      assert {:ok, ^chunk_data} = Zip.read_chunk(opened_state, chunk_index)
    end

    test "opens existing zip file with metadata", %{zip_path: zip_path} do
      # Create a zip file with metadata
      {:ok, state} = Zip.init(path: zip_path)
      metadata = %{"zarr_format" => 2, "shape" => [100]}
      json = Jason.encode!(metadata)
      :ok = Zip.write_metadata(state, json, [])

      # Open and verify metadata
      assert {:ok, opened_state} = Zip.open(path: zip_path)
      assert {:ok, read_metadata} = Zip.read_metadata(opened_state)
      assert {:ok, decoded} = Jason.decode(read_metadata)
      assert decoded["zarr_format"] == 2
      assert decoded["shape"] == [100]
    end

    test "returns error for nonexistent file", %{zip_path: zip_path} do
      nonexistent = zip_path <> ".nonexistent"
      assert {:error, :not_found} = Zip.open(path: nonexistent)
    end

    test "returns error for missing path" do
      assert {:error, :path_required} = Zip.open([])
    end

    test "returns error for nil path" do
      assert {:error, :path_required} = Zip.open(path: nil)
    end

    test "returns error for invalid path type" do
      assert {:error, :invalid_path} = Zip.open(path: :invalid)
    end
  end

  describe "write_chunk/3 and read_chunk/2" do
    test "writes and reads chunk from cache", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_data = <<1, 2, 3, 4, 5>>
      chunk_index = {0, 0}

      assert :ok = Zip.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Zip.read_chunk(state, chunk_index)
    end

    test "reads nonexistent chunk returns error", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      assert {:error, :not_found} = Zip.read_chunk(state, {99, 99})
    end

    test "writes and reads 1D chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_data = <<42>>
      chunk_index = {5}

      assert :ok = Zip.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Zip.read_chunk(state, chunk_index)
    end

    test "writes and reads 3D chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_data = <<1, 2, 3>>
      chunk_index = {1, 2, 3}

      assert :ok = Zip.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Zip.read_chunk(state, chunk_index)
    end

    test "overwrites existing chunk", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_index = {0, 0}
      original = <<1, 2, 3>>
      updated = <<4, 5, 6, 7>>

      assert :ok = Zip.write_chunk(state, chunk_index, original)
      assert {:ok, ^original} = Zip.read_chunk(state, chunk_index)

      assert :ok = Zip.write_chunk(state, chunk_index, updated)
      assert {:ok, ^updated} = Zip.read_chunk(state, chunk_index)
    end

    test "handles multiple chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      chunks = [
        {{0, 0}, <<1, 2>>},
        {{0, 1}, <<3, 4>>},
        {{1, 0}, <<5, 6>>}
      ]

      for {index, data} <- chunks do
        assert :ok = Zip.write_chunk(state, index, data)
      end

      for {index, expected} <- chunks do
        assert {:ok, ^expected} = Zip.read_chunk(state, index)
      end
    end

    test "handles empty chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_data = <<>>
      chunk_index = {0}

      assert :ok = Zip.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Zip.read_chunk(state, chunk_index)
    end
  end

  describe "write_metadata/3 and read_metadata/1" do
    test "writes and reads metadata", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      metadata = %{
        "zarr_format" => 2,
        "shape" => [100, 100],
        "chunks" => [10, 10],
        "dtype" => "<f8"
      }

      json = Jason.encode!(metadata, pretty: true)
      assert :ok = Zip.write_metadata(state, json, [])

      # Verify zip file was created
      assert File.exists?(zip_path)

      assert {:ok, read_json} = Zip.read_metadata(state)
      assert {:ok, read_map} = Jason.decode(read_json)
      assert read_map["zarr_format"] == 2
      assert read_map["shape"] == [100, 100]
    end

    test "writes metadata from map", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      metadata_map = %{
        "zarr_format" => 2,
        "shape" => [50],
        "chunks" => [10]
      }

      assert :ok = Zip.write_metadata(state, metadata_map, [])
      assert File.exists?(zip_path)
    end

    test "reads nonexistent metadata returns error", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      assert {:error, :not_found} = Zip.read_metadata(state)
    end

    test "write_metadata persists chunks to zip", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      # Write chunks (only in memory)
      chunk1_data = <<1, 2, 3>>
      chunk2_data = <<4, 5, 6>>
      assert :ok = Zip.write_chunk(state, {0, 0}, chunk1_data)
      assert :ok = Zip.write_chunk(state, {0, 1}, chunk2_data)

      # Write metadata (triggers zip save)
      metadata = %{"zarr_format" => 2, "shape" => [10]}
      assert :ok = Zip.write_metadata(state, metadata, [])

      # Open in new process and verify chunks persisted
      assert {:ok, new_state} = Zip.open(path: zip_path)
      assert {:ok, ^chunk1_data} = Zip.read_chunk(new_state, {0, 0})
      assert {:ok, ^chunk2_data} = Zip.read_chunk(new_state, {0, 1})
    end

    test "overwrites existing metadata", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      metadata1 = %{"zarr_format" => 2, "shape" => [100]}
      json1 = Jason.encode!(metadata1)
      assert :ok = Zip.write_metadata(state, json1, [])

      metadata2 = %{"zarr_format" => 2, "shape" => [200]}
      json2 = Jason.encode!(metadata2)
      assert :ok = Zip.write_metadata(state, json2, [])

      assert {:ok, read_json} = Zip.read_metadata(state)
      assert {:ok, read_map} = Jason.decode(read_json)
      assert read_map["shape"] == [200]
    end
  end

  describe "list_chunks/1" do
    test "lists no chunks when empty", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      assert {:ok, []} = Zip.list_chunks(state)
    end

    test "lists single chunk", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_index = {0, 0}
      assert :ok = Zip.write_chunk(state, chunk_index, <<1, 2, 3>>)

      assert {:ok, chunks} = Zip.list_chunks(state)
      assert length(chunks) == 1
      assert chunk_index in chunks
    end

    test "lists multiple chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      indices = [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      for index <- indices do
        assert :ok = Zip.write_chunk(state, index, <<1>>)
      end

      assert {:ok, chunks} = Zip.list_chunks(state)
      assert length(chunks) == 4

      for index <- indices do
        assert index in chunks
      end
    end

    test "lists 1D chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      for i <- 0..3 do
        assert :ok = Zip.write_chunk(state, {i}, <<i>>)
      end

      assert {:ok, chunks} = Zip.list_chunks(state)
      assert length(chunks) == 4
    end

    test "lists 3D chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      indices = [{0, 0, 0}, {0, 0, 1}, {1, 1, 1}]

      for index <- indices do
        assert :ok = Zip.write_chunk(state, index, <<1>>)
      end

      assert {:ok, chunks} = Zip.list_chunks(state)
      assert length(chunks) == 3

      for index <- indices do
        assert index in chunks
      end
    end

    test "lists chunks after opening zip file", %{zip_path: zip_path} do
      # Create zip with chunks
      {:ok, state} = Zip.init(path: zip_path)
      indices = [{0, 0}, {0, 1}, {1, 0}]

      for index <- indices do
        assert :ok = Zip.write_chunk(state, index, <<1>>)
      end

      metadata = %{"zarr_format" => 2}
      assert :ok = Zip.write_metadata(state, metadata, [])

      # Open and verify chunks listed
      assert {:ok, opened_state} = Zip.open(path: zip_path)
      assert {:ok, chunks} = Zip.list_chunks(opened_state)
      assert length(chunks) == 3

      for index <- indices do
        assert index in chunks
      end
    end
  end

  describe "delete_chunk/2" do
    test "deletes existing chunk", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3>>

      assert :ok = Zip.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Zip.read_chunk(state, chunk_index)

      assert :ok = Zip.delete_chunk(state, chunk_index)
      assert {:error, :not_found} = Zip.read_chunk(state, chunk_index)
    end

    test "deleting nonexistent chunk returns ok", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      assert :ok = Zip.delete_chunk(state, {99, 99})
    end

    test "deletes multiple chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      indices = [{0, 0}, {0, 1}, {1, 0}]

      for index <- indices do
        assert :ok = Zip.write_chunk(state, index, <<1>>)
      end

      for index <- indices do
        assert :ok = Zip.delete_chunk(state, index)
        assert {:error, :not_found} = Zip.read_chunk(state, index)
      end
    end

    test "list_chunks excludes deleted chunks", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      indices = [{0, 0}, {0, 1}, {1, 0}]

      for index <- indices do
        assert :ok = Zip.write_chunk(state, index, <<1>>)
      end

      assert :ok = Zip.delete_chunk(state, {0, 1})

      assert {:ok, chunks} = Zip.list_chunks(state)
      assert length(chunks) == 2
      assert {0, 0} in chunks
      assert {1, 0} in chunks
      refute {0, 1} in chunks
    end

    test "delete persists when metadata saved", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)

      # Write chunks
      assert :ok = Zip.write_chunk(state, {0, 0}, <<1>>)
      assert :ok = Zip.write_chunk(state, {0, 1}, <<2>>)

      # Delete one
      assert :ok = Zip.delete_chunk(state, {0, 1})

      # Save to zip
      metadata = %{"zarr_format" => 2}
      assert :ok = Zip.write_metadata(state, metadata, [])

      # Open and verify deletion persisted
      assert {:ok, opened_state} = Zip.open(path: zip_path)
      assert {:ok, chunks} = Zip.list_chunks(opened_state)
      assert length(chunks) == 1
      assert {0, 0} in chunks
      refute {0, 1} in chunks
    end
  end

  describe "exists?/1" do
    test "returns true for existing zip file", %{zip_path: zip_path} do
      {:ok, state} = Zip.init(path: zip_path)
      metadata = %{"zarr_format" => 2}
      :ok = Zip.write_metadata(state, metadata, [])

      assert Zip.exists?(path: zip_path) == true
    end

    test "returns false for nonexistent file", %{zip_path: zip_path} do
      nonexistent = zip_path <> ".nonexistent"
      assert Zip.exists?(path: nonexistent) == false
    end

    test "returns false for missing path config" do
      assert Zip.exists?([]) == false
    end

    test "returns false for nil path" do
      assert Zip.exists?(path: nil) == false
    end

    test "returns false for invalid path type" do
      assert Zip.exists?(path: 123) == false
    end
  end

  describe "backend_id/0" do
    test "returns :zip" do
      assert Zip.backend_id() == :zip
    end
  end

  describe "persistence" do
    test "full write/save/open workflow", %{zip_path: zip_path} do
      # Create and populate array
      {:ok, state} = Zip.init(path: zip_path)

      # Write multiple chunks
      for i <- 0..9 do
        assert :ok = Zip.write_chunk(state, {i}, <<i>>)
      end

      # Write metadata (saves to zip)
      metadata = %{
        "zarr_format" => 2,
        "shape" => [100],
        "chunks" => [10]
      }

      assert :ok = Zip.write_metadata(state, metadata, [])
      assert File.exists?(zip_path)

      # Open in new process
      assert {:ok, opened_state} = Zip.open(path: zip_path)

      # Verify all chunks
      for i <- 0..9 do
        assert {:ok, <<^i>>} = Zip.read_chunk(opened_state, {i})
      end

      # Verify metadata
      assert {:ok, meta_json} = Zip.read_metadata(opened_state)
      assert {:ok, meta_map} = Jason.decode(meta_json)
      assert meta_map["zarr_format"] == 2
      assert meta_map["shape"] == [100]
    end
  end
end
