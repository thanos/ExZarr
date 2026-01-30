defmodule ExZarr.Storage.S3Test do
  use ExUnit.Case

  alias ExZarr.Storage
  alias ExZarr.Storage.Backend.S3

  @moduletag :s3

  # These tests require a running S3-compatible service (localstack or minio)
  # To run these tests:
  #
  # 1. Start localstack:
  #    docker run -d -p 4566:4566 localstack/localstack
  #
  # 2. Or start minio:
  #    docker run -d -p 9000:9000 \
  #      -e MINIO_ROOT_USER=minioadmin \
  #      -e MINIO_ROOT_PASSWORD=minioadmin \
  #      minio/minio server /data
  #
  # 3. Set environment variables:
  #    export AWS_ACCESS_KEY_ID=test
  #    export AWS_SECRET_ACCESS_KEY=test
  #    export AWS_ENDPOINT_URL=http://localhost:4566  # for localstack
  #    # or
  #    export AWS_ENDPOINT_URL=http://localhost:9000  # for minio
  #
  # 4. Run tests:
  #    mix test --include s3

  @test_bucket "ex-zarr-test-bucket"
  @test_region "us-east-1"

  setup_all do
    # Register S3 backend
    :ok = ExZarr.Storage.Registry.register(S3)

    # Check if S3 service is available
    endpoint = System.get_env("AWS_ENDPOINT_URL")

    if is_nil(endpoint) do
      IO.puts("""

      WARNING:  S3 tests require AWS credentials and endpoint configuration.
      See test file for setup instructions.
      """)
    else
      # Create test bucket
      ensure_bucket_exists(@test_bucket, endpoint)
    end

    # Store whether S3 is configured for use in setup
    %{s3_configured: !is_nil(endpoint)}
  end

  setup %{s3_configured: configured} = context do
    # Skip tests if S3 is not configured
    if configured do
      # Generate unique prefix for this test to avoid conflicts
      prefix = "test-#{:erlang.unique_integer([:positive])}"

      config = [
        bucket: @test_bucket,
        prefix: prefix,
        region: @test_region
      ]

      # Clean up after test
      on_exit(fn ->
        cleanup_prefix(@test_bucket, prefix)
      end)

      Map.merge(context, %{config: config, prefix: prefix})
    else
      {:skip, "S3 service not configured - set AWS_ENDPOINT_URL environment variable"}
    end
  end

  describe "backend registration" do
    test "S3 backend is registered" do
      assert {:ok, S3} = ExZarr.Storage.Registry.get(:s3)
    end

    test "S3 backend_id returns :s3" do
      assert S3.backend_id() == :s3
    end
  end

  describe "init and open" do
    test "init creates backend state", %{config: config} do
      assert {:ok, state} = S3.init(config)
      assert state.bucket == @test_bucket
      assert is_binary(state.prefix)
      assert state.region == @test_region
    end

    test "open works same as init", %{config: config} do
      assert {:ok, state} = S3.open(config)
      assert state.bucket == @test_bucket
    end

    test "exists? returns true for existing bucket" do
      config = [bucket: @test_bucket, region: @test_region]
      assert S3.exists?(config) == true
    end

    test "exists? returns false for non-existent bucket" do
      config = [bucket: "this-bucket-definitely-does-not-exist-#{:rand.uniform(1_000_000)}"]
      assert S3.exists?(config) == false
    end
  end

  describe "metadata operations" do
    test "writes and reads metadata", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write metadata
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

      assert :ok = S3.write_metadata(state, metadata_json, [])

      # Read metadata back
      assert {:ok, read_json} = S3.read_metadata(state)
      assert is_binary(read_json)

      # Verify content
      {:ok, metadata} = Jason.decode(read_json, keys: :atoms)
      assert metadata.zarr_format == 2
      assert metadata.shape == [1000, 1000]
    end

    test "read_metadata returns :not_found for missing metadata", %{config: config} do
      {:ok, state} = S3.init(config)

      assert {:error, :not_found} = S3.read_metadata(state)
    end

    test "overwrites existing metadata", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write initial metadata
      metadata1 = Jason.encode!(%{zarr_format: 2, shape: [100]})
      assert :ok = S3.write_metadata(state, metadata1, [])

      # Overwrite with new metadata
      metadata2 = Jason.encode!(%{zarr_format: 2, shape: [200]})
      assert :ok = S3.write_metadata(state, metadata2, [])

      # Read should return new metadata
      assert {:ok, read_json} = S3.read_metadata(state)
      {:ok, metadata} = Jason.decode(read_json, keys: :atoms)
      assert metadata.shape == [200]
    end
  end

  describe "chunk operations" do
    test "writes and reads chunk", %{config: config} do
      {:ok, state} = S3.init(config)

      chunk_data = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      chunk_index = {0, 0}

      # Write chunk
      assert :ok = S3.write_chunk(state, chunk_index, chunk_data)

      # Read chunk back
      assert {:ok, read_data} = S3.read_chunk(state, chunk_index)
      assert read_data == chunk_data
    end

    test "reads non-existent chunk returns :not_found", %{config: config} do
      {:ok, state} = S3.init(config)

      assert {:error, :not_found} = S3.read_chunk(state, {99, 99})
    end

    test "writes multiple chunks", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write multiple chunks
      chunks = [
        {{0, 0}, <<1, 2, 3>>},
        {{0, 1}, <<4, 5, 6>>},
        {{1, 0}, <<7, 8, 9>>},
        {{1, 1}, <<10, 11, 12>>}
      ]

      for {index, data} <- chunks do
        assert :ok = S3.write_chunk(state, index, data)
      end

      # Read all chunks back
      for {index, expected_data} <- chunks do
        assert {:ok, data} = S3.read_chunk(state, index)
        assert data == expected_data
      end
    end

    test "overwrites existing chunk", %{config: config} do
      {:ok, state} = S3.init(config)

      chunk_index = {0, 0}

      # Write initial data
      assert :ok = S3.write_chunk(state, chunk_index, <<1, 2, 3>>)

      # Overwrite with new data
      assert :ok = S3.write_chunk(state, chunk_index, <<4, 5, 6>>)

      # Read should return new data
      assert {:ok, data} = S3.read_chunk(state, chunk_index)
      assert data == <<4, 5, 6>>
    end

    test "handles empty chunk data", %{config: config} do
      {:ok, state} = S3.init(config)

      assert :ok = S3.write_chunk(state, {0}, <<>>)
      assert {:ok, <<>>} = S3.read_chunk(state, {0})
    end

    test "handles large chunk data", %{config: config} do
      {:ok, state} = S3.init(config)

      # 1MB of data
      large_data = :binary.copy(<<42>>, 1_000_000)

      assert :ok = S3.write_chunk(state, {0}, large_data)
      assert {:ok, read_data} = S3.read_chunk(state, {0})
      assert byte_size(read_data) == 1_000_000
      assert read_data == large_data
    end

    test "handles 1D chunk indices", %{config: config} do
      {:ok, state} = S3.init(config)

      assert :ok = S3.write_chunk(state, {42}, <<1, 2, 3>>)
      assert {:ok, _} = S3.read_chunk(state, {42})
    end

    test "handles 3D chunk indices", %{config: config} do
      {:ok, state} = S3.init(config)

      assert :ok = S3.write_chunk(state, {1, 2, 3}, <<4, 5, 6>>)
      assert {:ok, data} = S3.read_chunk(state, {1, 2, 3})
      assert data == <<4, 5, 6>>
    end

    test "handles high-dimensional chunk indices", %{config: config} do
      {:ok, state} = S3.init(config)

      index = {0, 1, 2, 3, 4}
      data = <<1, 2, 3, 4, 5>>

      assert :ok = S3.write_chunk(state, index, data)
      assert {:ok, ^data} = S3.read_chunk(state, index)
    end
  end

  describe "list_chunks" do
    test "lists all chunks", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write metadata and chunks
      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = S3.write_metadata(state, metadata, [])

      chunks = [
        {0, 0},
        {0, 1},
        {1, 0},
        {1, 1},
        {2, 0}
      ]

      for index <- chunks do
        assert :ok = S3.write_chunk(state, index, <<1, 2, 3>>)
      end

      # List chunks
      assert {:ok, listed_chunks} = S3.list_chunks(state)
      assert Enum.sort(listed_chunks) == Enum.sort(chunks)
    end

    test "returns empty list when no chunks exist", %{config: config} do
      {:ok, state} = S3.init(config)

      assert {:ok, []} = S3.list_chunks(state)
    end

    test "does not include metadata file in chunk list", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write only metadata
      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = S3.write_metadata(state, metadata, [])

      # Should return empty list
      assert {:ok, []} = S3.list_chunks(state)
    end

    test "lists 1D chunks correctly", %{config: config} do
      {:ok, state} = S3.init(config)

      chunks = [{0}, {1}, {2}, {10}, {42}]

      for index <- chunks do
        assert :ok = S3.write_chunk(state, index, <<>>)
      end

      assert {:ok, listed_chunks} = S3.list_chunks(state)
      assert Enum.sort(listed_chunks) == Enum.sort(chunks)
    end
  end

  describe "delete_chunk" do
    test "deletes existing chunk", %{config: config} do
      {:ok, state} = S3.init(config)

      chunk_index = {0, 0}

      # Write chunk
      assert :ok = S3.write_chunk(state, chunk_index, <<1, 2, 3>>)
      assert {:ok, _} = S3.read_chunk(state, chunk_index)

      # Delete chunk
      assert :ok = S3.delete_chunk(state, chunk_index)

      # Should not be readable anymore
      assert {:error, :not_found} = S3.read_chunk(state, chunk_index)
    end

    test "delete non-existent chunk succeeds", %{config: config} do
      {:ok, state} = S3.init(config)

      # S3 delete is idempotent
      assert :ok = S3.delete_chunk(state, {99, 99})
    end

    test "deleting chunk removes it from list", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write multiple chunks
      for i <- 0..2, j <- 0..2 do
        assert :ok = S3.write_chunk(state, {i, j}, <<>>)
      end

      # Delete one chunk
      assert :ok = S3.delete_chunk(state, {1, 1})

      # List should not include deleted chunk
      assert {:ok, chunks} = S3.list_chunks(state)
      refute {1, 1} in chunks
      assert length(chunks) == 8
    end
  end

  describe "concurrent operations" do
    test "concurrent writes to different chunks", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write 10 chunks concurrently
      tasks =
        for i <- 0..9 do
          Task.async(fn ->
            S3.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &(&1 == :ok))

      # Verify all chunks were written
      assert {:ok, chunks} = S3.list_chunks(state)
      assert length(chunks) == 10
    end

    test "concurrent reads", %{config: config} do
      {:ok, state} = S3.init(config)

      # Write chunks first
      for i <- 0..4 do
        assert :ok = S3.write_chunk(state, {i}, <<i>>)
      end

      # Read concurrently
      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            S3.read_chunk(state, {i})
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "Storage module integration" do
    test "creates array with S3 storage", %{config: config} do
      # Test S3 backend directly
      {:ok, state} = S3.init(config)

      # Write some metadata
      metadata_json =
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

      assert :ok = S3.write_metadata(state, metadata_json, [])

      # Verify metadata was written
      assert {:ok, read_json} = S3.read_metadata(state)
      assert is_binary(read_json)

      # Verify it's valid JSON
      {:ok, parsed} = Jason.decode(read_json)
      assert parsed["zarr_format"] == 2
    end

    test "writes and reads data through Storage API", %{config: config} do
      # Create storage
      {:ok, storage} =
        Storage.init(%{
          storage_type: :s3,
          bucket: config[:bucket],
          prefix: config[:prefix],
          region: @test_region
        })

      # Write chunk
      chunk_data = <<1, 2, 3, 4, 5>>
      assert :ok = Storage.write_chunk(storage, {0, 0}, chunk_data)

      # Read chunk
      assert {:ok, read_data} = Storage.read_chunk(storage, {0, 0})
      assert read_data == chunk_data
    end
  end

  describe "prefix handling" do
    test "different prefixes isolate arrays", %{config: config} do
      # Create two arrays with different prefixes
      prefix1 = "#{config[:prefix]}/array1"
      prefix2 = "#{config[:prefix]}/array2"

      {:ok, state1} = S3.init(Keyword.put(config, :prefix, prefix1))
      {:ok, state2} = S3.init(Keyword.put(config, :prefix, prefix2))

      # Write to first array
      assert :ok = S3.write_chunk(state1, {0}, <<1, 2, 3>>)

      # Should not appear in second array
      assert {:ok, []} = S3.list_chunks(state2)

      # Write to second array
      assert :ok = S3.write_chunk(state2, {0}, <<4, 5, 6>>)

      # Each array should have one chunk
      assert {:ok, [{0}]} = S3.list_chunks(state1)
      assert {:ok, [{0}]} = S3.list_chunks(state2)

      # Chunks should have different data
      assert {:ok, <<1, 2, 3>>} = S3.read_chunk(state1, {0})
      assert {:ok, <<4, 5, 6>>} = S3.read_chunk(state2, {0})
    end

    test "empty prefix works correctly" do
      config = [bucket: @test_bucket, prefix: "", region: @test_region]
      {:ok, state} = S3.init(config)

      assert :ok = S3.write_chunk(state, {0}, <<1>>)
      assert {:ok, <<1>>} = S3.read_chunk(state, {0})

      # Clean up
      S3.delete_chunk(state, {0})
    end
  end

  ## Helper Functions

  defp ensure_bucket_exists(bucket, endpoint) do
    # Parse endpoint for ExAws configuration
    uri = URI.parse(endpoint)

    config = [
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID", "test"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "test"),
      region: @test_region,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port
    ]

    # Try to create bucket (ignore error if already exists)
    case ExAws.S3.put_bucket(bucket, @test_region) |> ExAws.request(config) do
      {:ok, _} ->
        IO.puts("✓ Created bucket: #{bucket}")
        :ok

      {:error, {:http_error, 409, _}} ->
        IO.puts("✓ Bucket already exists: #{bucket}")
        :ok

      {:error, error} ->
        IO.puts("WARNING:  Failed to create bucket: #{inspect(error)}")
        :ok
    end
  end

  defp cleanup_prefix(bucket, prefix) do
    # List and delete all objects with this prefix
    endpoint = System.get_env("AWS_ENDPOINT_URL")

    config =
      if endpoint do
        uri = URI.parse(endpoint)

        [
          access_key_id: System.get_env("AWS_ACCESS_KEY_ID", "test"),
          secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "test"),
          region: @test_region,
          scheme: "#{uri.scheme}://",
          host: uri.host,
          port: uri.port
        ]
      else
        [region: @test_region]
      end

    case ExAws.S3.list_objects_v2(bucket, prefix: prefix) |> ExAws.request(config) do
      {:ok, %{body: %{contents: objects}}} ->
        for object <- objects do
          ExAws.S3.delete_object(bucket, object.key) |> ExAws.request(config)
        end

      _ ->
        :ok
    end
  end
end
