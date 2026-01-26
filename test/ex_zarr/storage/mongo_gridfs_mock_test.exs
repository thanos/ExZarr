defmodule ExZarr.Storage.MongoGridFSMockTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.MongoGridFS

  # Mock Mongo for MongoDB connection
  defmodule MockMongo do
    def start_link(opts) do
      send(self(), {:mongo_start_link, opts})
      {:ok, self()}
    end

    def find(conn, collection, filter, _opts \\ []) do
      send(self(), {:mongo_find, conn, collection, filter})

      # Return matching filenames based on prefix (return list, not {:ok, list})
      case filter do
        %{"filename" => %{"$regex" => regex}} ->
          # Extract prefix from regex (e.g., "^array1/" -> "array1/")
          prefix = String.replace_prefix(regex, "^", "")

          if String.contains?(regex, "/.zarray") do
            []
          else
            # Generate mock chunk filenames matching the prefix
            [
              %{"filename" => "#{prefix}0.0"},
              %{"filename" => "#{prefix}0.1"},
              %{"filename" => "#{prefix}1.0"}
            ]
          end

        _ ->
          []
      end
    end
  end

  # Mock Mongo.GridFs for GridFS operations
  defmodule MockGridFs do
    def upload(conn, data, opts \\ [], bucket: bucket) do
      # Extract filename from opts for verification
      filename = Keyword.get(opts, :filename, "unknown")
      send(self(), {:gridfs_upload, conn, bucket, filename, data})
      {:ok, %{_id: "mock_object_id"}}
    end

    def download(conn, filename, bucket: bucket) do
      send(self(), {:gridfs_download, conn, bucket, filename})

      cond do
        String.ends_with?(filename, ".zarray") ->
          {:ok, mock_metadata_json()}

        String.match?(filename, ~r/\d+(\.\d+)*$/) ->
          {:ok, <<1, 2, 3, 4, 5>>}

        true ->
          {:error, :not_found}
      end
    end

    def delete(conn, filename, bucket: bucket) do
      send(self(), {:gridfs_delete, conn, bucket, filename})
      :ok
    end

    defp mock_metadata_json do
      Jason.encode!(%{
        zarr_format: 2,
        shape: [100, 100],
        chunks: [10, 10],
        dtype: "<f8",
        compressor: nil,
        fill_value: 0,
        order: "C",
        filters: nil
      })
    end
  end

  setup do
    # Inject mock modules
    Application.put_env(:ex_zarr, :mongo_module, MockMongo)
    Application.put_env(:ex_zarr, :mongo_gridfs_module, MockGridFs)

    on_exit(fn ->
      Application.delete_env(:ex_zarr, :mongo_module)
      Application.delete_env(:ex_zarr, :mongo_gridfs_module)
    end)

    :ok
  end

  describe "backend_id/0" do
    test "returns :mongo_gridfs" do
      assert MongoGridFS.backend_id() == :mongo_gridfs
    end
  end

  describe "init/1" do
    test "initializes with required fields" do
      config = [
        url: "mongodb://localhost:27017",
        database: "zarr_test",
        bucket: "zarr_chunks",
        array_id: "array1"
      ]

      assert {:ok, state} = MongoGridFS.init(config)
      assert state.bucket == "zarr_chunks"
      assert state.array_id == "array1"
      assert is_pid(state.conn) or is_reference(state.conn)
    end

    test "uses default bucket when not specified" do
      config = [
        url: "mongodb://localhost:27017",
        database: "zarr_test",
        array_id: "array1"
      ]

      assert {:ok, state} = MongoGridFS.init(config)
      assert state.bucket == "zarr"
    end

    test "returns error for missing url" do
      config = [database: "zarr_test", array_id: "array1"]
      assert {:error, :url_required} = MongoGridFS.init(config)
    end

    test "returns error for missing database" do
      config = [url: "mongodb://localhost:27017", array_id: "array1"]
      assert {:error, :database_required} = MongoGridFS.init(config)
    end

    test "returns error for missing array_id" do
      config = [url: "mongodb://localhost:27017", database: "zarr_test"]
      assert {:error, :array_id_required} = MongoGridFS.init(config)
    end
  end

  describe "open/1" do
    test "works same as init" do
      config = [
        url: "mongodb://localhost:27017",
        database: "zarr_test",
        array_id: "array1"
      ]

      assert {:ok, state} = MongoGridFS.open(config)
      assert state.array_id == "array1"
    end
  end

  describe "read_chunk/2" do
    test "reads chunk" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert {:ok, data} = MongoGridFS.read_chunk(state, {0, 0})
      assert is_binary(data)
      assert data == <<1, 2, 3, 4, 5>>

      assert_receive {:gridfs_download, _, "zarr", "array1/0.0"}
    end

    test "handles 1D chunk indices" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert {:ok, _data} = MongoGridFS.read_chunk(state, {42})
      assert_receive {:gridfs_download, _, "zarr", "array1/42"}
    end

    test "handles 3D chunk indices" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert {:ok, _data} = MongoGridFS.read_chunk(state, {1, 2, 3})
      assert_receive {:gridfs_download, _, "zarr", "array1/1.2.3"}
    end
  end

  describe "write_chunk/3" do
    test "writes chunk" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      chunk_data = <<10, 20, 30>>
      assert :ok = MongoGridFS.write_chunk(state, {0, 0}, chunk_data)

      assert_receive {:gridfs_upload, _, "zarr", "array1/0.0", ^chunk_data}
    end

    test "writes chunk with different array_id" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "experiment/run1"
        )

      chunk_data = <<10, 20, 30>>
      assert :ok = MongoGridFS.write_chunk(state, {5, 10}, chunk_data)

      assert_receive {:gridfs_upload, _, "zarr", "experiment/run1/5.10", ^chunk_data}
    end

    test "writes chunk with custom bucket" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1",
          bucket: "custom_bucket"
        )

      chunk_data = <<10, 20, 30>>
      assert :ok = MongoGridFS.write_chunk(state, {0, 0}, chunk_data)

      assert_receive {:gridfs_upload, _, "custom_bucket", "array1/0.0", ^chunk_data}
    end
  end

  describe "read_metadata/1" do
    test "reads metadata" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert {:ok, json} = MongoGridFS.read_metadata(state)
      assert is_binary(json)

      assert_receive {:gridfs_download, _, "zarr", "array1/.zarray"}
    end

    test "reads metadata with custom bucket" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1",
          bucket: "metadata_bucket"
        )

      assert {:ok, _json} = MongoGridFS.read_metadata(state)

      assert_receive {:gridfs_download, _, "metadata_bucket", "array1/.zarray"}
    end
  end

  describe "write_metadata/3" do
    test "writes metadata" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = MongoGridFS.write_metadata(state, metadata, [])

      assert_receive {:gridfs_upload, _, "zarr", "array1/.zarray", ^metadata}
    end
  end

  describe "list_chunks/1" do
    test "lists chunks" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert {:ok, chunks} = MongoGridFS.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}]

      assert_receive {:mongo_find, _, "zarr.files", _}
    end

    test "does not include metadata file in chunk list" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert {:ok, chunks} = MongoGridFS.list_chunks(state)

      refute Enum.any?(chunks, fn chunk ->
               is_binary(chunk) and String.contains?(chunk, ".zarray")
             end)
    end
  end

  describe "delete_chunk/2" do
    test "deletes chunk" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      assert :ok = MongoGridFS.delete_chunk(state, {0, 0})
      assert_receive {:gridfs_delete, _, "zarr", "array1/0.0"}
    end

    test "deletes chunk with different array_id" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "arrays/test"
        )

      assert :ok = MongoGridFS.delete_chunk(state, {1, 2})
      assert_receive {:gridfs_delete, _, "zarr", "arrays/test/1.2"}
    end
  end

  describe "chunk key encoding" do
    test "encodes 1D indices" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      MongoGridFS.write_chunk(state, {42}, <<1, 2, 3>>)
      assert_receive {:gridfs_upload, _, "zarr", "array1/42", _}
    end

    test "encodes 2D indices" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      MongoGridFS.write_chunk(state, {1, 2}, <<1, 2, 3>>)
      assert_receive {:gridfs_upload, _, "zarr", "array1/1.2", _}
    end

    test "encodes 3D indices" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      MongoGridFS.write_chunk(state, {1, 2, 3}, <<1, 2, 3>>)
      assert_receive {:gridfs_upload, _, "zarr", "array1/1.2.3", _}
    end

    test "encodes ND indices" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      MongoGridFS.write_chunk(state, {1, 2, 3, 4, 5}, <<1, 2, 3>>)
      assert_receive {:gridfs_upload, _, "zarr", "array1/1.2.3.4.5", _}
    end
  end

  describe "integration scenarios" do
    test "complete read/write cycle" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "test"
        )

      # Write metadata
      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = MongoGridFS.write_metadata(state, metadata, [])

      # Write chunks
      assert :ok = MongoGridFS.write_chunk(state, {0, 0}, <<1, 2, 3>>)
      assert :ok = MongoGridFS.write_chunk(state, {0, 1}, <<4, 5, 6>>)

      # Read chunks
      assert {:ok, _} = MongoGridFS.read_chunk(state, {0, 0})
      assert {:ok, _} = MongoGridFS.read_chunk(state, {0, 1})

      # List chunks
      assert {:ok, chunks} = MongoGridFS.list_chunks(state)
      assert Enum.empty?(chunks) == false

      # Delete chunk
      assert :ok = MongoGridFS.delete_chunk(state, {0, 0})
    end
  end

  describe "concurrent operations" do
    test "handles concurrent writes" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            MongoGridFS.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :ok))
    end

    test "handles concurrent reads" do
      {:ok, state} =
        MongoGridFS.init(
          url: "mongodb://localhost:27017",
          database: "zarr_test",
          array_id: "array1"
        )

      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            MongoGridFS.read_chunk(state, {i})
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
