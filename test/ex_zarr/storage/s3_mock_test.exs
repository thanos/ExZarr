defmodule ExZarr.Storage.S3MockTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.S3

  # Mock modules for ExAws
  defmodule MockExAws do
    def request(operation, _config) do
      # Store the operation for inspection in tests
      send(self(), {:ex_aws_request, operation})

      # Default success response
      case operation do
        %{http_method: :get, path: path} ->
          cond do
            String.ends_with?(path, ".zarray") ->
              {:ok, %{body: mock_metadata_json()}}

            String.match?(path, ~r/\d+(\.\d+)*$/) ->
              {:ok, %{body: <<1, 2, 3, 4, 5>>}}

            true ->
              {:error, {:http_error, 404, "Not Found"}}
          end

        %{http_method: :put} ->
          {:ok, %{status_code: 200}}

        %{http_method: :delete} ->
          {:ok, %{status_code: 204}}

        %{http_method: :head} ->
          {:ok, %{status_code: 200}}

        _ ->
          {:error, :unknown_operation}
      end
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

  defmodule MockExAwsS3 do
    defstruct [:operation, :bucket, :key, :body, :http_method, :path]

    def get_object(bucket, key) do
      %__MODULE__{
        operation: :get_object,
        bucket: bucket,
        key: key,
        http_method: :get,
        path: "/#{bucket}/#{key}"
      }
    end

    def put_object(bucket, key, body) do
      %__MODULE__{
        operation: :put_object,
        bucket: bucket,
        key: key,
        body: body,
        http_method: :put,
        path: "/#{bucket}/#{key}"
      }
    end

    def delete_object(bucket, key) do
      %__MODULE__{
        operation: :delete_object,
        bucket: bucket,
        key: key,
        http_method: :delete,
        path: "/#{bucket}/#{key}"
      }
    end

    def head_bucket(bucket) do
      %__MODULE__{
        operation: :head_bucket,
        bucket: bucket,
        http_method: :head,
        path: "/#{bucket}"
      }
    end

    def list_objects_v2(bucket, opts) do
      prefix = Keyword.get(opts, :prefix, "")

      %__MODULE__{
        operation: :list_objects_v2,
        bucket: bucket,
        key: prefix,
        http_method: :get,
        path: "/#{bucket}?list-type=2&prefix=#{prefix}"
      }
    end
  end

  setup do
    # Configure mocks
    Application.put_env(:ex_zarr, :ex_aws_module, MockExAws)
    Application.put_env(:ex_zarr, :ex_aws_s3_module, MockExAwsS3)

    on_exit(fn ->
      Application.delete_env(:ex_zarr, :ex_aws_module)
      Application.delete_env(:ex_zarr, :ex_aws_s3_module)
    end)

    :ok
  end

  describe "backend_id/0" do
    test "returns :s3" do
      assert S3.backend_id() == :s3
    end
  end

  describe "init/1" do
    test "initializes with required bucket" do
      config = [bucket: "test-bucket", prefix: "arrays/data", region: "us-west-2"]

      assert {:ok, state} = S3.init(config)
      assert state.bucket == "test-bucket"
      assert state.prefix == "arrays/data"
      assert state.region == "us-west-2"
      assert state.ex_aws_config == [region: "us-west-2"]
    end

    test "uses default region when not specified" do
      config = [bucket: "test-bucket"]

      assert {:ok, state} = S3.init(config)
      assert state.region == "us-east-1"
      assert state.ex_aws_config == [region: "us-east-1"]
    end

    test "uses empty prefix when not specified" do
      config = [bucket: "test-bucket"]

      assert {:ok, state} = S3.init(config)
      assert state.prefix == ""
    end

    test "returns error when bucket is missing" do
      config = []

      assert {:error, :bucket_required} = S3.init(config)
    end

    test "returns error when bucket is empty string" do
      config = [bucket: ""]

      # Empty string is invalid, not missing
      assert {:error, :invalid_bucket} = S3.init(config)
    end

    test "returns error when bucket is nil" do
      config = [bucket: nil]

      assert {:error, :bucket_required} = S3.init(config)
    end
  end

  describe "open/1" do
    test "opens with same logic as init" do
      config = [bucket: "test-bucket", prefix: "data"]

      assert {:ok, state} = S3.open(config)
      assert state.bucket == "test-bucket"
      assert state.prefix == "data"
    end
  end

  describe "read_chunk/2" do
    test "reads chunk with empty prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "")

      assert {:ok, data} = S3.read_chunk(state, {0, 0})
      assert is_binary(data)
      assert data == <<1, 2, 3, 4, 5>>

      # Verify correct S3 operation
      assert_receive {:ex_aws_request, operation}
      assert operation.bucket == "test-bucket"
      assert operation.key == "0.0"
    end

    test "reads chunk with prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "arrays/experiment1")

      assert {:ok, data} = S3.read_chunk(state, {2, 5})
      assert is_binary(data)

      # Verify correct S3 key
      assert_receive {:ex_aws_request, operation}
      assert operation.key == "arrays/experiment1/2.5"
    end

    test "reads chunk with 1D index" do
      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:ok, _data} = S3.read_chunk(state, {42})

      assert_receive {:ex_aws_request, operation}
      assert operation.key == "42"
    end

    test "reads chunk with 3D index" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "data")

      assert {:ok, _data} = S3.read_chunk(state, {1, 2, 3})

      assert_receive {:ex_aws_request, operation}
      assert operation.key == "data/1.2.3"
    end

    test "returns :not_found for missing chunk" do
      # Override mock to return 404
      defmodule NotFoundMock do
        def request(_operation, _config) do
          {:error, {:http_error, 404, "Not Found"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, NotFoundMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, :not_found} = S3.read_chunk(state, {0, 0})
    end

    test "returns error for other S3 errors" do
      # Override mock to return error
      defmodule ErrorMock do
        def request(_operation, _config) do
          {:error, {:http_error, 403, "Access Denied"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, ErrorMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, {:s3_error, _}} = S3.read_chunk(state, {0, 0})
    end
  end

  describe "write_chunk/3" do
    test "writes chunk with empty prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "")

      chunk_data = <<1, 2, 3, 4, 5, 6, 7, 8>>
      assert :ok = S3.write_chunk(state, {0, 1}, chunk_data)

      # Verify correct S3 operation
      assert_receive {:ex_aws_request, operation}
      assert operation.bucket == "test-bucket"
      assert operation.key == "0.1"
      assert operation.body == chunk_data
    end

    test "writes chunk with prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "experiment/run1")

      chunk_data = <<10, 20, 30>>
      assert :ok = S3.write_chunk(state, {5, 10}, chunk_data)

      assert_receive {:ex_aws_request, operation}
      assert operation.key == "experiment/run1/5.10"
      assert operation.body == chunk_data
    end

    test "writes empty chunk data" do
      {:ok, state} = S3.init(bucket: "test-bucket")

      assert :ok = S3.write_chunk(state, {0}, <<>>)

      assert_receive {:ex_aws_request, operation}
      assert operation.body == <<>>
    end

    test "writes large chunk data" do
      {:ok, state} = S3.init(bucket: "test-bucket")

      # 1MB of data
      large_data = :binary.copy(<<1>>, 1_000_000)
      assert :ok = S3.write_chunk(state, {0, 0}, large_data)

      assert_receive {:ex_aws_request, operation}
      assert byte_size(operation.body) == 1_000_000
    end

    test "returns error on S3 failure" do
      defmodule WriteErrorMock do
        def request(_operation, _config) do
          {:error, {:http_error, 500, "Internal Server Error"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, WriteErrorMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, {:s3_error, _}} = S3.write_chunk(state, {0, 0}, <<1, 2, 3>>)
    end
  end

  describe "read_metadata/1" do
    test "reads metadata with empty prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "")

      assert {:ok, json} = S3.read_metadata(state)
      assert is_binary(json)

      # Verify correct S3 key
      assert_receive {:ex_aws_request, operation}
      assert operation.key == ".zarray"
    end

    test "reads metadata with prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "arrays/experiment1")

      assert {:ok, json} = S3.read_metadata(state)
      assert is_binary(json)

      assert_receive {:ex_aws_request, operation}
      assert operation.key == "arrays/experiment1/.zarray"
    end

    test "returns :not_found for missing metadata" do
      defmodule MetadataNotFoundMock do
        def request(_operation, _config) do
          {:error, {:http_error, 404, "Not Found"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, MetadataNotFoundMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, :not_found} = S3.read_metadata(state)
    end

    test "returns error for S3 failures" do
      defmodule MetadataErrorMock do
        def request(_operation, _config) do
          {:error, {:http_error, 403, "Access Denied"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, MetadataErrorMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, {:s3_error, _}} = S3.read_metadata(state)
    end
  end

  describe "write_metadata/3" do
    test "writes metadata with empty prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "")

      metadata_json = Jason.encode!(%{zarr_format: 2, shape: [100]})

      assert :ok = S3.write_metadata(state, metadata_json, [])

      # Verify correct S3 operation
      assert_receive {:ex_aws_request, operation}
      assert operation.key == ".zarray"
      assert operation.body == metadata_json
    end

    test "writes metadata with prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "data/arrays")

      metadata_json = Jason.encode!(%{zarr_format: 3})

      assert :ok = S3.write_metadata(state, metadata_json, [])

      assert_receive {:ex_aws_request, operation}
      assert operation.key == "data/arrays/.zarray"
    end

    test "returns error on S3 failure" do
      defmodule WriteMetadataErrorMock do
        def request(_operation, _config) do
          {:error, {:http_error, 403, "Forbidden"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, WriteMetadataErrorMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, {:s3_error, _}} = S3.write_metadata(state, "{}", [])
    end
  end

  describe "list_chunks/1" do
    test "lists chunks with empty prefix" do
      defmodule ListChunksMock do
        def request(_operation, _config) do
          {:ok,
           %{
             body: %{
               contents: [
                 %{key: ".zarray", size: 100},
                 %{key: "0.0", size: 1000},
                 %{key: "0.1", size: 1000},
                 %{key: "1.0", size: 1000},
                 %{key: "readme.txt", size: 50}
               ]
             }
           }}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, ListChunksMock)

      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "")

      assert {:ok, chunks} = S3.list_chunks(state)
      # Should filter out .zarray and non-chunk files
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}]
    end

    test "lists chunks with prefix" do
      defmodule ListChunksWithPrefixMock do
        def request(_operation, _config) do
          {:ok,
           %{
             body: %{
               contents: [
                 %{key: "data/.zarray", size: 100},
                 %{key: "data/0.0", size: 1000},
                 %{key: "data/1.2.3", size: 1000}
               ]
             }
           }}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, ListChunksWithPrefixMock)

      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "data")

      assert {:ok, chunks} = S3.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {1, 2, 3}]
    end

    test "returns empty list when no chunks exist" do
      defmodule EmptyListMock do
        def request(_operation, _config) do
          {:ok,
           %{
             body: %{
               contents: [
                 %{key: ".zarray", size: 100}
               ]
             }
           }}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, EmptyListMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:ok, []} = S3.list_chunks(state)
    end

    test "handles 1D chunk indices" do
      defmodule List1DChunksMock do
        def request(_operation, _config) do
          {:ok,
           %{
             body: %{
               contents: [
                 %{key: "0", size: 1000},
                 %{key: "1", size: 1000},
                 %{key: "42", size: 1000}
               ]
             }
           }}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, List1DChunksMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:ok, chunks} = S3.list_chunks(state)
      assert Enum.sort(chunks) == [{0}, {1}, {42}]
    end

    test "returns error on S3 failure" do
      defmodule ListErrorMock do
        def request(_operation, _config) do
          {:error, {:http_error, 403, "Access Denied"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, ListErrorMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, {:s3_error, _}} = S3.list_chunks(state)
    end
  end

  describe "delete_chunk/2" do
    test "deletes chunk with empty prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "")

      assert :ok = S3.delete_chunk(state, {0, 0})

      # Verify correct S3 operation
      assert_receive {:ex_aws_request, operation}
      assert operation.operation == :delete_object
      assert operation.key == "0.0"
    end

    test "deletes chunk with prefix" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "arrays/data")

      assert :ok = S3.delete_chunk(state, {5, 10})

      assert_receive {:ex_aws_request, operation}
      assert operation.key == "arrays/data/5.10"
    end

    test "returns error on S3 failure" do
      defmodule DeleteErrorMock do
        def request(_operation, _config) do
          {:error, {:http_error, 404, "Not Found"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, DeleteErrorMock)

      {:ok, state} = S3.init(bucket: "test-bucket")

      assert {:error, {:s3_error, _}} = S3.delete_chunk(state, {0, 0})
    end
  end

  describe "exists?/1" do
    test "returns true when bucket exists" do
      config = [bucket: "test-bucket", region: "us-west-2"]

      assert S3.exists?(config) == true
    end

    test "returns false when bucket doesn't exist" do
      defmodule BucketNotFoundMock do
        def request(_operation, _config) do
          {:error, {:http_error, 404, "Not Found"}}
        end
      end

      Application.put_env(:ex_zarr, :ex_aws_module, BucketNotFoundMock)

      config = [bucket: "nonexistent-bucket"]

      assert S3.exists?(config) == false
    end

    test "returns false when bucket is missing" do
      config = []

      assert S3.exists?(config) == false
    end

    test "uses default region when not specified" do
      config = [bucket: "test-bucket"]

      assert S3.exists?(config) == true

      # Verify head_bucket was called
      assert_receive {:ex_aws_request, operation}
      assert operation.operation == :head_bucket
    end
  end

  describe "chunk key encoding" do
    test "encodes 1D indices correctly" do
      {:ok, state} = S3.init(bucket: "test", prefix: "")

      S3.write_chunk(state, {0}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "0"

      S3.write_chunk(state, {42}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "42"
    end

    test "encodes 2D indices correctly" do
      {:ok, state} = S3.init(bucket: "test", prefix: "")

      S3.write_chunk(state, {0, 0}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "0.0"

      S3.write_chunk(state, {10, 20}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "10.20"
    end

    test "encodes 3D indices correctly" do
      {:ok, state} = S3.init(bucket: "test", prefix: "")

      S3.write_chunk(state, {1, 2, 3}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "1.2.3"
    end

    test "encodes ND indices correctly" do
      {:ok, state} = S3.init(bucket: "test", prefix: "")

      S3.write_chunk(state, {0, 1, 2, 3, 4}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "0.1.2.3.4"
    end

    test "includes prefix in chunk keys" do
      {:ok, state} = S3.init(bucket: "test", prefix: "data/experiment")

      S3.write_chunk(state, {0, 0}, <<>>)
      assert_receive {:ex_aws_request, op}
      assert op.key == "data/experiment/0.0"
    end
  end

  describe "integration scenarios" do
    test "complete write and read workflow" do
      {:ok, state} = S3.init(bucket: "test-bucket", prefix: "workflow")

      # Write metadata
      metadata_json = Jason.encode!(%{zarr_format: 2, shape: [100]})
      assert :ok = S3.write_metadata(state, metadata_json, [])

      # Write chunks
      assert :ok = S3.write_chunk(state, {0}, <<1, 2, 3>>)
      assert :ok = S3.write_chunk(state, {1}, <<4, 5, 6>>)

      # Read metadata
      assert {:ok, json} = S3.read_metadata(state)
      assert is_binary(json)

      # Read chunks
      assert {:ok, data} = S3.read_chunk(state, {0})
      assert is_binary(data)
    end

    test "handles concurrent operations" do
      {:ok, state} = S3.init(bucket: "test-bucket")

      # Simulate concurrent writes
      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            S3.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
