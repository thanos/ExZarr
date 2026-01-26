defmodule ExZarr.Storage.GCSMockTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.GCS

  # Mock modules for Req and Goth
  defmodule MockReq do
    def get(url, opts) do
      send(self(), {:req_get, url, opts})

      cond do
        # List objects - URL ends with /o (without object name)
        String.ends_with?(url, "/o") ->
          {:ok, %{status: 200, body: %{"items" => []}}}

        String.ends_with?(url, ".zarray") ->
          {:ok, %{status: 200, body: mock_metadata_json()}}

        String.match?(url, ~r/\d+(\.\d+)*/) ->
          {:ok, %{status: 200, body: <<1, 2, 3, 4, 5>>}}

        true ->
          {:ok, %{status: 404}}
      end
    end

    def post(url, opts) do
      send(self(), {:req_post, url, opts})
      {:ok, %{status: 200}}
    end

    def delete(url, opts) do
      send(self(), {:req_delete, url, opts})
      {:ok, %{status: 204}}
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

  defmodule MockGoth do
    def start_link(opts) do
      name = Keyword.get(opts, :name)
      send(self(), {:goth_start, name, opts})
      {:ok, self()}
    end

    def fetch(_name) do
      {:ok, %{token: "mock_access_token_123"}}
    end
  end

  setup do
    # Configure mocks
    Application.put_env(:ex_zarr, :req_module, MockReq)
    Application.put_env(:ex_zarr, :goth_module, MockGoth)

    on_exit(fn ->
      Application.delete_env(:ex_zarr, :req_module)
      Application.delete_env(:ex_zarr, :goth_module)
    end)

    :ok
  end

  describe "backend_id/0" do
    test "returns :gcs" do
      assert GCS.backend_id() == :gcs
    end
  end

  describe "init/1" do
    test "initializes with required bucket and explicit prefix" do
      config = [
        bucket: "test-bucket",
        prefix: "data",
        credentials: %{
          "type" => "service_account",
          "project_id" => "test-project"
        }
      ]

      assert {:ok, state} = GCS.init(config)
      assert state.bucket == "test-bucket"
      assert state.prefix == "data"
      assert is_atom(state.goth_name)
      assert String.starts_with?(Atom.to_string(state.goth_name), "goth_")
    end

    test "initializes with credentials map" do
      config = [
        bucket: "test-bucket",
        credentials: %{
          "type" => "service_account",
          "project_id" => "test-project"
        }
      ]

      assert {:ok, state} = GCS.init(config)
      assert state.bucket == "test-bucket"
      assert is_atom(state.goth_name)
    end

    test "uses default prefix when not specified" do
      config = [bucket: "test-bucket", credentials: %{}]

      assert {:ok, state} = GCS.init(config)
      assert state.prefix == ""
    end

    test "returns error when bucket is missing" do
      config = [credentials: %{}]

      assert {:error, :bucket_required} = GCS.init(config)
    end

    test "returns error when bucket is empty string" do
      config = [bucket: "", credentials: %{}]

      assert {:error, :invalid_bucket} = GCS.init(config)
    end

    test "returns error when bucket is nil" do
      config = [bucket: nil, credentials: %{}]

      assert {:error, :bucket_required} = GCS.init(config)
    end
  end

  describe "open/1" do
    test "opens with same logic as init" do
      config = [bucket: "test-bucket", prefix: "data", credentials: %{}]

      assert {:ok, state} = GCS.open(config)
      assert state.bucket == "test-bucket"
      assert state.prefix == "data"
    end
  end

  describe "read_chunk/2" do
    test "reads chunk with empty prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "", credentials: %{})

      assert {:ok, data} = GCS.read_chunk(state, {0, 0})
      assert is_binary(data)
      assert data == <<1, 2, 3, 4, 5>>

      # Verify correct HTTP request
      assert_receive {:req_get, url, opts}
      assert String.contains?(url, "test-bucket")
      assert String.contains?(url, "0.0")

      assert Keyword.get(opts, :headers)
             |> Enum.any?(&match?({"authorization", "Bearer " <> _}, &1))
    end

    test "reads chunk with prefix" do
      {:ok, state} =
        GCS.init(bucket: "test-bucket", prefix: "arrays/experiment1", credentials: %{})

      assert {:ok, data} = GCS.read_chunk(state, {2, 5})
      assert is_binary(data)

      assert_receive {:req_get, url, _opts}
      assert String.contains?(url, "arrays%2Fexperiment1%2F2.5")
    end

    test "reads chunk with 1D index" do
      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:ok, _data} = GCS.read_chunk(state, {42})

      assert_receive {:req_get, url, _opts}
      assert String.contains?(url, "42")
    end

    test "reads chunk with 3D index" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "data", credentials: %{})

      assert {:ok, _data} = GCS.read_chunk(state, {1, 2, 3})

      assert_receive {:req_get, url, _opts}
      assert String.contains?(url, "data%2F1.2.3")
    end

    test "returns :not_found for missing chunk" do
      defmodule NotFoundReq do
        def get(_url, _opts) do
          {:ok, %{status: 404}}
        end
      end

      Application.put_env(:ex_zarr, :req_module, NotFoundReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:error, :not_found} = GCS.read_chunk(state, {0, 0})
    end

    test "returns error for other GCS errors" do
      defmodule ErrorReq do
        def get(_url, _opts) do
          {:ok, %{status: 403}}
        end
      end

      Application.put_env(:ex_zarr, :req_module, ErrorReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:error, {:gcs_error, 403}} = GCS.read_chunk(state, {0, 0})
    end
  end

  describe "write_chunk/3" do
    test "writes chunk with empty prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "", credentials: %{})

      chunk_data = <<1, 2, 3, 4, 5, 6, 7, 8>>
      assert :ok = GCS.write_chunk(state, {0, 1}, chunk_data)

      assert_receive {:req_post, url, opts}
      assert String.contains?(url, "test-bucket")
      assert Keyword.get(opts, :body) == chunk_data
    end

    test "writes chunk with prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "experiment/run1", credentials: %{})

      chunk_data = <<10, 20, 30>>
      assert :ok = GCS.write_chunk(state, {5, 10}, chunk_data)

      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      name = Keyword.get(params, :name)
      assert name == "experiment/run1/5.10"
    end

    test "writes empty chunk data" do
      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert :ok = GCS.write_chunk(state, {0}, <<>>)

      assert_receive {:req_post, _url, opts}
      assert Keyword.get(opts, :body) == <<>>
    end

    test "writes large chunk data" do
      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      large_data = :binary.copy(<<1>>, 1_000_000)
      assert :ok = GCS.write_chunk(state, {0, 0}, large_data)

      assert_receive {:req_post, _url, opts}
      assert byte_size(Keyword.get(opts, :body)) == 1_000_000
    end

    test "returns error on GCS failure" do
      defmodule WriteErrorReq do
        def post(_url, _opts) do
          {:ok, %{status: 500}}
        end
      end

      Application.put_env(:ex_zarr, :req_module, WriteErrorReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:error, {:gcs_error, 500}} = GCS.write_chunk(state, {0, 0}, <<1, 2, 3>>)
    end
  end

  describe "read_metadata/1" do
    test "reads metadata with empty prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "", credentials: %{})

      assert {:ok, json} = GCS.read_metadata(state)
      assert is_binary(json)

      assert_receive {:req_get, url, _opts}
      assert String.contains?(url, ".zarray")
    end

    test "reads metadata with prefix" do
      {:ok, state} =
        GCS.init(bucket: "test-bucket", prefix: "arrays/experiment1", credentials: %{})

      assert {:ok, json} = GCS.read_metadata(state)
      assert is_binary(json)

      assert_receive {:req_get, url, _opts}
      assert String.contains?(url, "arrays%2Fexperiment1%2F.zarray")
    end

    test "returns :not_found for missing metadata" do
      defmodule MetadataNotFoundReq do
        def get(_url, _opts) do
          {:ok, %{status: 404}}
        end
      end

      Application.put_env(:ex_zarr, :req_module, MetadataNotFoundReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:error, :not_found} = GCS.read_metadata(state)
    end
  end

  describe "write_metadata/3" do
    test "writes metadata with empty prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "", credentials: %{})

      metadata_json = Jason.encode!(%{zarr_format: 2, shape: [100]})

      assert :ok = GCS.write_metadata(state, metadata_json, [])

      assert_receive {:req_post, url, opts}
      assert String.contains?(url, "test-bucket")
      assert Keyword.get(opts, :body) == metadata_json
    end

    test "writes metadata with prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "data/arrays", credentials: %{})

      metadata_json = Jason.encode!(%{zarr_format: 3})

      assert :ok = GCS.write_metadata(state, metadata_json, [])

      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      name = Keyword.get(params, :name)
      assert name == "data/arrays/.zarray"
    end
  end

  describe "list_chunks/1" do
    test "lists chunks with empty prefix" do
      defmodule ListChunksReq do
        def get(url, _opts) do
          if String.ends_with?(url, "/o") do
            {:ok,
             %{
               status: 200,
               body: %{
                 "items" => [
                   %{"name" => ".zarray"},
                   %{"name" => "0.0"},
                   %{"name" => "0.1"},
                   %{"name" => "1.0"},
                   %{"name" => "readme.txt"}
                 ]
               }
             }}
          else
            {:ok, %{status: 404}}
          end
        end
      end

      Application.put_env(:ex_zarr, :req_module, ListChunksReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "", credentials: %{})

      assert {:ok, chunks} = GCS.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}]
    end

    test "lists chunks with prefix" do
      defmodule ListChunksWithPrefixReq do
        def get(url, _opts) do
          if String.ends_with?(url, "/o") do
            {:ok,
             %{
               status: 200,
               body: %{
                 "items" => [
                   %{"name" => "data/.zarray"},
                   %{"name" => "data/0.0"},
                   %{"name" => "data/1.2.3"}
                 ]
               }
             }}
          else
            {:ok, %{status: 404}}
          end
        end
      end

      Application.put_env(:ex_zarr, :req_module, ListChunksWithPrefixReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "data", credentials: %{})

      assert {:ok, chunks} = GCS.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {1, 2, 3}]
    end

    test "returns empty list when no chunks exist" do
      defmodule EmptyListReq do
        def get(url, _opts) do
          if String.ends_with?(url, "/o") do
            {:ok,
             %{
               status: 200,
               body: %{
                 "items" => [%{"name" => ".zarray"}]
               }
             }}
          else
            {:ok, %{status: 404}}
          end
        end
      end

      Application.put_env(:ex_zarr, :req_module, EmptyListReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:ok, []} = GCS.list_chunks(state)
    end
  end

  describe "delete_chunk/2" do
    test "deletes chunk with empty prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "", credentials: %{})

      assert :ok = GCS.delete_chunk(state, {0, 0})

      assert_receive {:req_delete, url, _opts}
      assert String.contains?(url, "0.0")
    end

    test "deletes chunk with prefix" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "arrays/data", credentials: %{})

      assert :ok = GCS.delete_chunk(state, {5, 10})

      assert_receive {:req_delete, url, _opts}
      assert String.contains?(url, "arrays%2Fdata%2F5.10")
    end

    test "returns error on GCS failure" do
      defmodule DeleteErrorReq do
        def delete(_url, _opts) do
          {:ok, %{status: 403}}
        end
      end

      Application.put_env(:ex_zarr, :req_module, DeleteErrorReq)

      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      assert {:error, {:gcs_error, 403}} = GCS.delete_chunk(state, {0, 0})
    end
  end

  describe "exists?/1" do
    test "returns true when bucket exists" do
      config = [bucket: "test-bucket", credentials: %{}]

      assert GCS.exists?(config) == true
    end

    test "returns false when bucket doesn't exist" do
      defmodule BucketNotFoundReq do
        def get(_url, _opts) do
          {:ok, %{status: 404}}
        end
      end

      Application.put_env(:ex_zarr, :req_module, BucketNotFoundReq)

      config = [bucket: "nonexistent-bucket", credentials: %{}]

      assert GCS.exists?(config) == false
    end

    test "returns false when bucket is missing" do
      config = [credentials: %{}]

      assert GCS.exists?(config) == false
    end
  end

  describe "chunk key encoding" do
    test "encodes 1D indices correctly" do
      {:ok, state} = GCS.init(bucket: "test", prefix: "", credentials: %{})

      GCS.write_chunk(state, {0}, <<>>)
      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      assert Keyword.get(params, :name) == "0"

      GCS.write_chunk(state, {42}, <<>>)
      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      assert Keyword.get(params, :name) == "42"
    end

    test "encodes 2D indices correctly" do
      {:ok, state} = GCS.init(bucket: "test", prefix: "", credentials: %{})

      GCS.write_chunk(state, {0, 0}, <<>>)
      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      assert Keyword.get(params, :name) == "0.0"

      GCS.write_chunk(state, {10, 20}, <<>>)
      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      assert Keyword.get(params, :name) == "10.20"
    end

    test "encodes 3D indices correctly" do
      {:ok, state} = GCS.init(bucket: "test", prefix: "", credentials: %{})

      GCS.write_chunk(state, {1, 2, 3}, <<>>)
      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      assert Keyword.get(params, :name) == "1.2.3"
    end

    test "includes prefix in object keys" do
      {:ok, state} = GCS.init(bucket: "test", prefix: "data/experiment", credentials: %{})

      GCS.write_chunk(state, {0, 0}, <<>>)
      assert_receive {:req_post, _url, opts}
      params = Keyword.get(opts, :params, [])
      assert Keyword.get(params, :name) == "data/experiment/0.0"
    end
  end

  describe "integration scenarios" do
    test "complete write and read workflow" do
      {:ok, state} = GCS.init(bucket: "test-bucket", prefix: "workflow", credentials: %{})

      # Write metadata
      metadata_json = Jason.encode!(%{zarr_format: 2, shape: [100]})
      assert :ok = GCS.write_metadata(state, metadata_json, [])

      # Write chunks
      assert :ok = GCS.write_chunk(state, {0}, <<1, 2, 3>>)
      assert :ok = GCS.write_chunk(state, {1}, <<4, 5, 6>>)

      # Read metadata
      assert {:ok, json} = GCS.read_metadata(state)
      assert is_binary(json)

      # Read chunks
      assert {:ok, data} = GCS.read_chunk(state, {0})
      assert is_binary(data)
    end

    test "handles concurrent operations" do
      {:ok, state} = GCS.init(bucket: "test-bucket", credentials: %{})

      # Simulate concurrent writes
      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            GCS.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
