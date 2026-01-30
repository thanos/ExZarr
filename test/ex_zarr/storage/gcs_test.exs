defmodule ExZarr.Storage.GCSTest do
  use ExUnit.Case

  alias ExZarr.Storage.Backend.GCS

  @moduletag :gcs

  # These tests require a running fake-gcs-server
  # To run these tests:
  #
  # 1. Start fake-gcs-server:
  #    docker run -d -p 4443:4443 \
  #      fsouza/fake-gcs-server \
  #      -scheme http \
  #      -port 4443
  #
  # 2. Set environment variable (use http, not https!):
  #    export GCS_ENDPOINT_URL=http://localhost:4443
  #
  # 3. Run tests:
  #    mix test --include gcs
  #
  # Note: fake-gcs-server doesn't require real authentication.
  # The tests use a MockGoth that returns fake tokens.

  @test_bucket "ex-zarr-test-bucket"
  @test_project "test-project"

  # Mock Goth for fake-gcs-server testing (doesn't validate tokens)
  defmodule MockGoth do
    def start_link(_opts) do
      # fake-gcs-server doesn't require real authentication
      {:ok, self()}
    end

    def fetch(_name) do
      # fake-gcs-server accepts any token
      {:ok, %{token: "fake-gcs-server-token"}}
    end
  end

  setup_all do
    # Register GCS backend
    :ok = ExZarr.Storage.Registry.register(GCS)

    # Check if fake-gcs-server is available
    endpoint = System.get_env("GCS_ENDPOINT_URL")

    if is_nil(endpoint) do
      IO.puts("""

      WARNING:  GCS tests require fake-gcs-server configuration.
      See test file for setup instructions.
      """)
    else
      # Create test bucket
      ensure_bucket_exists(@test_bucket, endpoint)
    end

    %{gcs_configured: !is_nil(endpoint)}
  end

  setup %{gcs_configured: configured} = context do
    if configured do
      # Inject MockGoth for fake-gcs-server (doesn't validate authentication)
      Application.put_env(:ex_zarr, :goth_module, MockGoth)

      on_exit(fn ->
        Application.delete_env(:ex_zarr, :goth_module)
      end)

      # Generate unique prefix for this test
      prefix = "test-#{:erlang.unique_integer([:positive])}"

      # Create mock credentials for fake-gcs-server
      # This is a valid test RSA key (generated for testing only, not used for real authentication)
      test_private_key = """
      -----BEGIN PRIVATE KEY-----
      MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC0WmpXuOp7cBGi
      OlyaeQc+eEdX3XZiPOzOAdTknWMDgbPJts4wYJuzoAp+BUPDhsmCLH4DyLQ8rp7W
      H9bq/kEwPIUFxNUoKT/z+xjHgDBUfcREjWBYb5/q+0/F9+MFSqfmm/SFJprO4qdK
      t9WQcFwIbrVkSiHiN3PfRax4bSr+D78mcZECRMOQovAvY//O+Iz0iDSzrQQaemtX
      Qgn9jmw7DzT4K9j7XOvVX+Nc67zjbDQkCNZUeewOxTdiyf6YdE+syuLUqsjYWGwl
      CLH+KuWRWMUNp75zrSTkqVknYU+c3m1bLpmjTVjTbxOdE8T+B8hFZA7b1UnQ8xTD
      rA0GeZ67AgMBAAECggEAP2q1jv/+L4ZiJPW5nzWkdvJrP7mnSXbb27poJjUzXkXK
      tsiZawhlZ32EgviN8eBg1e2YJ/N4cQgD4Q4UD9B0kqYNLlCelT8f9kYaWfg4xlTs
      4SAHO0GQ7VsOG3IFOVSdgmjfS7yd3dZz9cF7joz7x5lKHig1Durpyx4gPb5BSlEf
      DI48YUOi36ueeg1wM5Tgo7e/v4+YfWDSr+HoOj+VpCsHGJPXa0ktPm5MS/EdjVhh
      8/WZhIMxiXqtbsX2Y6vMAgJ/Oi+cso8IvumF5DL0uGYlFMKlNeZr9zo1iP9EPUuY
      ECv3FNOuDHZXFxLAi/wZbI2Ob5uQWaeQUT0GZUhAcQKBgQDW6D1khXRQtxzJxlpZ
      oZWx1i9Mg9DaLyTC6x5r5m2qr4k/15nYerSDsnyFqEMV46NQGlLAgjc6BiGyCSDB
      sPKetXCH1gRaEZnsr+nAquYsj0CDnHxWMjJ6xl8jdhMG+n2qI7S8bIeWmwDrlUiK
      reo6Xt8hYsuv5avXs+uSCrNvqwKBgQDW1r+lsnynALX9MyTDY1X6bCfSj1lBYx/Y
      cEPavlHR5QJsuwCArRZEsSeC5VEi29ZAY2jqz9NIh7vYS7LEf6LMqyPXW3eVAYCX
      BSl3C/NjtEieXpIX05f11dAuP1BH3I1C0Q0ggji1tzqfFJOSFm4+v2CKWIyl+bLZ
      5OrkkhC9MQKBgQCITi66NgbrNuj0dXFSzjDi5aWEU0rBSAt58aSO7Uz7aHCV5Ip4
      ioM50Jg4Mduy43nu0XNRFIYwsDjo8e8ryq5nyU7BaRXDhsxpGb4Z7IsnEgjqMPOP
      vDDWPEGVfUteLrxLkHAO3os1E8UGpt2mz93y/b9qLn5gZzySCFTOgSkEFwKBgQCG
      /ygr2W0kj3jL4sA+GoRjOGUJlVPzl3LiUSECKcdGCg4s/pDBSoIMpfj68le6fMMz
      cIPz0KWmFMx/jImHmeBVlVCPOYV51xjTTMYSbSsCQr3C7hAE8suxCSqodNZgYYFO
      NAh4nfs+jCVE4uwbxwZ9XUovhJbUkIPHEWZcPEBScQKBgBUuVl4O4LSVyiVwvomh
      KsbF6ZiO94HMH2N+5r/cuqACTKx+jVJovm/YsYWDEdiia19hqvP/MSJWlSSWsfA9
      EZRbBU0jYDY/x81utHm/gSY7NI29VeTmPF6CeppRDbL4O1XKXxz/TKq9hy2usGKd
      0trkBmytkm4OXA38qNiHkJ79
      -----END PRIVATE KEY-----
      """

      credentials = %{
        "type" => "service_account",
        "project_id" => @test_project,
        "private_key_id" => "test-key-id",
        "private_key" => String.trim(test_private_key),
        "client_email" => "test@test-project.iam.gserviceaccount.com",
        "client_id" => "123456789",
        "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
        "token_uri" => "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs"
      }

      config = [
        bucket: @test_bucket,
        prefix: prefix,
        credentials: credentials
      ]

      # Clean up after test
      on_exit(fn ->
        cleanup_prefix(@test_bucket, prefix)
      end)

      {:ok, Map.merge(context, %{config: config, prefix: prefix})}
    else
      {:ok, context}
    end
  end

  describe "backend registration" do
    test "GCS backend is registered" do
      assert {:ok, GCS} = ExZarr.Storage.Registry.get(:gcs)
    end

    test "GCS backend_id returns :gcs" do
      assert GCS.backend_id() == :gcs
    end
  end

  describe "init and open" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "init creates backend state", %{config: config} do
      assert {:ok, state} = GCS.init(config)
      assert state.bucket == @test_bucket
      assert is_binary(state.prefix)
      assert is_atom(state.goth_name)
    end

    test "open works same as init", %{config: config} do
      assert {:ok, state} = GCS.open(config)
      assert state.bucket == @test_bucket
    end
  end

  describe "metadata operations" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "writes and reads metadata", %{config: config} do
      {:ok, state} = GCS.init(config)

      metadata_json =
        Jason.encode!(%{
          zarr_format: 2,
          shape: [1000, 1000],
          chunks: [100, 100],
          dtype: "<f8",
          compressor: nil,
          fill_value: 0,
          order: "C",
          filters: nil
        })

      assert :ok = GCS.write_metadata(state, metadata_json, [])

      assert {:ok, read_json} = GCS.read_metadata(state)
      assert is_binary(read_json)

      {:ok, metadata} = Jason.decode(read_json, keys: :atoms)
      assert metadata.zarr_format == 2
      assert metadata.shape == [1000, 1000]
    end

    test "read_metadata returns :not_found for missing metadata", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert {:error, :not_found} = GCS.read_metadata(state)
    end

    test "overwrites existing metadata", %{config: config} do
      {:ok, state} = GCS.init(config)

      metadata1 = Jason.encode!(%{zarr_format: 2, shape: [100]})
      assert :ok = GCS.write_metadata(state, metadata1, [])

      metadata2 = Jason.encode!(%{zarr_format: 2, shape: [200]})
      assert :ok = GCS.write_metadata(state, metadata2, [])

      assert {:ok, read_json} = GCS.read_metadata(state)
      {:ok, metadata} = Jason.decode(read_json, keys: :atoms)
      assert metadata.shape == [200]
    end
  end

  describe "chunk operations" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "writes and reads chunk", %{config: config} do
      {:ok, state} = GCS.init(config)

      chunk_data = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      chunk_index = {0, 0}

      assert :ok = GCS.write_chunk(state, chunk_index, chunk_data)
      assert {:ok, read_data} = GCS.read_chunk(state, chunk_index)
      assert read_data == chunk_data
    end

    test "reads non-existent chunk returns :not_found", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert {:error, :not_found} = GCS.read_chunk(state, {99, 99})
    end

    test "writes multiple chunks", %{config: config} do
      {:ok, state} = GCS.init(config)

      chunks = [
        {{0, 0}, <<1, 2, 3>>},
        {{0, 1}, <<4, 5, 6>>},
        {{1, 0}, <<7, 8, 9>>},
        {{1, 1}, <<10, 11, 12>>}
      ]

      for {index, data} <- chunks do
        assert :ok = GCS.write_chunk(state, index, data)
      end

      for {index, expected_data} <- chunks do
        assert {:ok, data} = GCS.read_chunk(state, index)
        assert data == expected_data
      end
    end

    test "overwrites existing chunk", %{config: config} do
      {:ok, state} = GCS.init(config)

      chunk_index = {0, 0}

      assert :ok = GCS.write_chunk(state, chunk_index, <<1, 2, 3>>)
      assert :ok = GCS.write_chunk(state, chunk_index, <<4, 5, 6>>)

      assert {:ok, data} = GCS.read_chunk(state, chunk_index)
      assert data == <<4, 5, 6>>
    end

    test "handles empty chunk data", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert :ok = GCS.write_chunk(state, {0}, <<>>)
      assert {:ok, <<>>} = GCS.read_chunk(state, {0})
    end

    test "handles large chunk data", %{config: config} do
      {:ok, state} = GCS.init(config)

      large_data = :binary.copy(<<42>>, 1_000_000)

      assert :ok = GCS.write_chunk(state, {0}, large_data)
      assert {:ok, read_data} = GCS.read_chunk(state, {0})
      assert byte_size(read_data) == 1_000_000
      assert read_data == large_data
    end

    test "handles 1D chunk indices", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert :ok = GCS.write_chunk(state, {42}, <<1, 2, 3>>)
      assert {:ok, _} = GCS.read_chunk(state, {42})
    end

    test "handles 3D chunk indices", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert :ok = GCS.write_chunk(state, {1, 2, 3}, <<4, 5, 6>>)
      assert {:ok, data} = GCS.read_chunk(state, {1, 2, 3})
      assert data == <<4, 5, 6>>
    end
  end

  describe "list_chunks" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "lists all chunks", %{config: config} do
      {:ok, state} = GCS.init(config)

      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = GCS.write_metadata(state, metadata, [])

      chunks = [
        {0, 0},
        {0, 1},
        {1, 0},
        {1, 1},
        {2, 0}
      ]

      for index <- chunks do
        assert :ok = GCS.write_chunk(state, index, <<1, 2, 3>>)
      end

      assert {:ok, listed_chunks} = GCS.list_chunks(state)
      assert Enum.sort(listed_chunks) == Enum.sort(chunks)
    end

    test "returns empty list when no chunks exist", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert {:ok, []} = GCS.list_chunks(state)
    end

    test "does not include metadata file in chunk list", %{config: config} do
      {:ok, state} = GCS.init(config)

      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = GCS.write_metadata(state, metadata, [])

      assert {:ok, []} = GCS.list_chunks(state)
    end

    test "lists 1D chunks correctly", %{config: config} do
      {:ok, state} = GCS.init(config)

      chunks = [{0}, {1}, {2}, {10}, {42}]

      for index <- chunks do
        assert :ok = GCS.write_chunk(state, index, <<>>)
      end

      assert {:ok, listed_chunks} = GCS.list_chunks(state)
      assert Enum.sort(listed_chunks) == Enum.sort(chunks)
    end
  end

  describe "delete_chunk" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "deletes existing chunk", %{config: config} do
      {:ok, state} = GCS.init(config)

      chunk_index = {0, 0}

      assert :ok = GCS.write_chunk(state, chunk_index, <<1, 2, 3>>)
      assert {:ok, _} = GCS.read_chunk(state, chunk_index)

      assert :ok = GCS.delete_chunk(state, chunk_index)

      assert {:error, :not_found} = GCS.read_chunk(state, chunk_index)
    end

    test "delete non-existent chunk succeeds", %{config: config} do
      {:ok, state} = GCS.init(config)

      assert :ok = GCS.delete_chunk(state, {99, 99})
    end

    test "deleting chunk removes it from list", %{config: config} do
      {:ok, state} = GCS.init(config)

      for i <- 0..2, j <- 0..2 do
        assert :ok = GCS.write_chunk(state, {i, j}, <<>>)
      end

      assert :ok = GCS.delete_chunk(state, {1, 1})

      assert {:ok, chunks} = GCS.list_chunks(state)
      refute {1, 1} in chunks
      assert length(chunks) == 8
    end
  end

  describe "concurrent operations" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "concurrent writes to different chunks", %{config: config} do
      {:ok, state} = GCS.init(config)

      tasks =
        for i <- 0..9 do
          Task.async(fn ->
            GCS.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &(&1 == :ok))

      assert {:ok, chunks} = GCS.list_chunks(state)
      assert length(chunks) == 10
    end

    test "concurrent reads", %{config: config} do
      {:ok, state} = GCS.init(config)

      for i <- 0..4 do
        assert :ok = GCS.write_chunk(state, {i}, <<i>>)
      end

      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            GCS.read_chunk(state, {i})
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "prefix handling" do
    setup context, do: {:ok, require_gcs_config!(context)}

    test "different prefixes isolate arrays", %{config: config} do
      prefix1 = "#{config[:prefix]}/array1"
      prefix2 = "#{config[:prefix]}/array2"

      {:ok, state1} = GCS.init(Keyword.put(config, :prefix, prefix1))
      {:ok, state2} = GCS.init(Keyword.put(config, :prefix, prefix2))

      assert :ok = GCS.write_chunk(state1, {0}, <<1, 2, 3>>)

      assert {:ok, []} = GCS.list_chunks(state2)

      assert :ok = GCS.write_chunk(state2, {0}, <<4, 5, 6>>)

      assert {:ok, [{0}]} = GCS.list_chunks(state1)
      assert {:ok, [{0}]} = GCS.list_chunks(state2)

      assert {:ok, <<1, 2, 3>>} = GCS.read_chunk(state1, {0})
      assert {:ok, <<4, 5, 6>>} = GCS.read_chunk(state2, {0})
    end

    test "empty prefix works correctly", %{config: config} do
      config = Keyword.put(config, :prefix, "")
      {:ok, state} = GCS.init(config)

      assert :ok = GCS.write_chunk(state, {0}, <<1>>)
      assert {:ok, <<1>>} = GCS.read_chunk(state, {0})

      GCS.delete_chunk(state, {0})
    end
  end

  ## Helper Functions

  defp require_gcs_config!(context) do
    unless Map.has_key?(context, :config) do
      flunk("""
      GCS service not configured. To run GCS tests:

      1. Start fake-gcs-server:
         docker run -d -p 4443:4443 fsouza/fake-gcs-server -scheme http -port 4443

      2. Set environment variable (use http, not https!):
         export GCS_ENDPOINT_URL=http://localhost:4443

      3. Run tests:
         mix test --include gcs
      """)
    end

    context
  end

  defp ensure_bucket_exists(bucket, endpoint) do
    # Create bucket in fake-gcs-server using the JSON API
    url = "#{endpoint}/storage/v1/b?project=#{@test_project}"

    body = Jason.encode!(%{name: bucket})

    case Req.post(url,
           headers: [{"content-type", "application/json"}],
           body: body
         ) do
      {:ok, %{status: status}} when status in [200, 409] ->
        # 200 = created, 409 = already exists
        IO.puts("✓ Using bucket: #{bucket}")
        :ok

      {:ok, response} ->
        IO.puts("Warning: Failed to create bucket #{bucket}: #{response.status}")
        :ok

      {:error, reason} ->
        IO.puts("Warning: Failed to create bucket #{bucket}: #{inspect(reason)}")
        :ok
    end
  end

  defp cleanup_prefix(_bucket, _prefix) do
    # Cleanup is not critical for fake-gcs-server in tests
    # Objects will be cleaned up when container is restarted
    :ok
  end
end
