defmodule ExZarr.Storage.AzureBlobMockTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.AzureBlob

  # Mock Azurex.Blob.Client for Azure Blob testing
  defmodule MockAzurexBlob do
    def get_blob(_account_name, _account_key, _container, blob_name) do
      send(self(), {:azurex_get, blob_name})

      cond do
        String.ends_with?(blob_name, ".zarray") ->
          {:ok, mock_metadata_json()}

        String.match?(blob_name, ~r/\d+(\.\d+)*$/) ->
          {:ok, <<1, 2, 3, 4, 5>>}

        true ->
          {:error, %{status_code: 404, body: "Not Found"}}
      end
    end

    def put_block_blob(_account_name, _account_key, _container, blob_name, data) do
      send(self(), {:azurex_put, blob_name, data})
      {:ok, %{status_code: 201}}
    end

    def list_blobs(_account_name, _account_key, _container, opts \\ []) do
      prefix = Keyword.get(opts, :prefix, "")
      send(self(), {:azurex_list, prefix})

      items =
        case prefix do
          "" ->
            [
              %{name: ".zarray"},
              %{name: "0.0"},
              %{name: "0.1"},
              %{name: "1.0"}
            ]

          _ ->
            [
              %{name: "#{prefix}/.zarray"},
              %{name: "#{prefix}/0.0"},
              %{name: "#{prefix}/0.1"}
            ]
        end

      {:ok, items}
    end

    def delete_blob(_account_name, _account_key, _container, blob_name) do
      send(self(), {:azurex_delete, blob_name})
      {:ok, %{status_code: 202}}
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
    # Inject mock module
    Application.put_env(:ex_zarr, :azurex_blob_module, MockAzurexBlob)

    on_exit(fn ->
      Application.delete_env(:ex_zarr, :azurex_blob_module)
    end)

    :ok
  end

  describe "backend_id/0" do
    test "returns :azure_blob" do
      assert AzureBlob.backend_id() == :azure_blob
    end
  end

  describe "init/1" do
    test "initializes with required fields" do
      config = [
        account_name: "myaccount",
        account_key: "mykey",
        container: "test-container",
        prefix: "data"
      ]

      assert {:ok, state} = AzureBlob.init(config)
      assert state.account_name == "myaccount"
      assert state.account_key == "mykey"
      assert state.container == "test-container"
      assert state.prefix == "data"
    end

    test "uses default empty prefix when not specified" do
      config = [
        account_name: "myaccount",
        account_key: "mykey",
        container: "test-container"
      ]

      assert {:ok, state} = AzureBlob.init(config)
      assert state.prefix == ""
    end

    test "returns error for missing account_name" do
      config = [account_key: "mykey", container: "test-container"]
      assert {:error, :account_name_required} = AzureBlob.init(config)
    end

    test "returns error for missing account_key" do
      config = [account_name: "myaccount", container: "test-container"]
      assert {:error, :account_key_required} = AzureBlob.init(config)
    end

    test "returns error for missing container" do
      config = [account_name: "myaccount", account_key: "mykey"]
      assert {:error, :container_required} = AzureBlob.init(config)
    end
  end

  describe "open/1" do
    test "works same as init" do
      config = [
        account_name: "myaccount",
        account_key: "mykey",
        container: "test-container"
      ]

      assert {:ok, state} = AzureBlob.open(config)
      assert state.account_name == "myaccount"
    end
  end

  describe "read_chunk/2" do
    test "reads chunk with empty prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert {:ok, data} = AzureBlob.read_chunk(state, {0, 0})
      assert is_binary(data)
      assert data == <<1, 2, 3, 4, 5>>

      assert_receive {:azurex_get, "0.0"}
    end

    test "reads chunk with prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: "arrays/experiment1"
        )

      assert {:ok, data} = AzureBlob.read_chunk(state, {2, 5})
      assert is_binary(data)

      assert_receive {:azurex_get, "arrays/experiment1/2.5"}
    end

    test "handles 1D chunk indices" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert {:ok, _data} = AzureBlob.read_chunk(state, {42})
      assert_receive {:azurex_get, "42"}
    end

    test "handles 3D chunk indices" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert {:ok, _data} = AzureBlob.read_chunk(state, {1, 2, 3})
      assert_receive {:azurex_get, "1.2.3"}
    end
  end

  describe "write_chunk/3" do
    test "writes chunk with empty prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      chunk_data = <<10, 20, 30>>
      assert :ok = AzureBlob.write_chunk(state, {0, 0}, chunk_data)

      assert_receive {:azurex_put, "0.0", ^chunk_data}
    end

    test "writes chunk with prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: "experiment/run1"
        )

      chunk_data = <<10, 20, 30>>
      assert :ok = AzureBlob.write_chunk(state, {5, 10}, chunk_data)

      assert_receive {:azurex_put, "experiment/run1/5.10", ^chunk_data}
    end
  end

  describe "read_metadata/1" do
    test "reads metadata with empty prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert {:ok, json} = AzureBlob.read_metadata(state)
      assert is_binary(json)

      assert_receive {:azurex_get, ".zarray"}
    end

    test "reads metadata with prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: "arrays/experiment1"
        )

      assert {:ok, json} = AzureBlob.read_metadata(state)
      assert is_binary(json)

      assert_receive {:azurex_get, "arrays/experiment1/.zarray"}
    end
  end

  describe "write_metadata/3" do
    test "writes metadata" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = AzureBlob.write_metadata(state, metadata, [])

      assert_receive {:azurex_put, ".zarray", ^metadata}
    end
  end

  describe "list_chunks/1" do
    test "lists chunks with empty prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert {:ok, chunks} = AzureBlob.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}]

      assert_receive {:azurex_list, ""}
    end

    test "lists chunks with prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: "data"
        )

      assert {:ok, chunks} = AzureBlob.list_chunks(state)
      assert length(chunks) == 2

      assert_receive {:azurex_list, "data/"}
    end

    test "does not include metadata file in chunk list" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert {:ok, chunks} = AzureBlob.list_chunks(state)
      refute Enum.any?(chunks, fn chunk -> chunk == ".zarray" end)
    end
  end

  describe "delete_chunk/2" do
    test "deletes chunk" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      assert :ok = AzureBlob.delete_chunk(state, {0, 0})
      assert_receive {:azurex_delete, "0.0"}
    end

    test "deletes chunk with prefix" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: "arrays/test"
        )

      assert :ok = AzureBlob.delete_chunk(state, {1, 2})
      assert_receive {:azurex_delete, "arrays/test/1.2"}
    end
  end

  describe "chunk key encoding" do
    test "encodes 1D indices" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      AzureBlob.write_chunk(state, {42}, <<1, 2, 3>>)
      assert_receive {:azurex_put, "42", _}
    end

    test "encodes 2D indices" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      AzureBlob.write_chunk(state, {1, 2}, <<1, 2, 3>>)
      assert_receive {:azurex_put, "1.2", _}
    end

    test "encodes 3D indices" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      AzureBlob.write_chunk(state, {1, 2, 3}, <<1, 2, 3>>)
      assert_receive {:azurex_put, "1.2.3", _}
    end

    test "encodes ND indices" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      AzureBlob.write_chunk(state, {1, 2, 3, 4, 5}, <<1, 2, 3>>)
      assert_receive {:azurex_put, "1.2.3.4.5", _}
    end
  end

  describe "integration scenarios" do
    test "complete read/write cycle" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: "test"
        )

      # Write metadata
      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = AzureBlob.write_metadata(state, metadata, [])

      # Write chunks
      assert :ok = AzureBlob.write_chunk(state, {0, 0}, <<1, 2, 3>>)
      assert :ok = AzureBlob.write_chunk(state, {0, 1}, <<4, 5, 6>>)

      # Read chunks
      assert {:ok, _} = AzureBlob.read_chunk(state, {0, 0})
      assert {:ok, _} = AzureBlob.read_chunk(state, {0, 1})

      # List chunks
      assert {:ok, chunks} = AzureBlob.list_chunks(state)
      assert Enum.empty?(chunks) == false

      # Delete chunk
      assert :ok = AzureBlob.delete_chunk(state, {0, 0})
    end
  end

  describe "concurrent operations" do
    test "handles concurrent writes" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            AzureBlob.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :ok))
    end

    test "handles concurrent reads" do
      {:ok, state} =
        AzureBlob.init(
          account_name: "myaccount",
          account_key: "mykey",
          container: "test-container",
          prefix: ""
        )

      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            AzureBlob.read_chunk(state, {i})
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
