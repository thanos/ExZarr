defmodule ExZarr.Storage.Backend.S3 do
  @moduledoc """
  AWS S3 storage backend for Zarr arrays.

  Stores chunks and metadata in Amazon S3, providing scalable cloud storage
  with high availability and durability.

  ## Configuration

  Requires the following options:
  - `:bucket` - S3 bucket name (required)
  - `:prefix` - Key prefix/path within bucket (optional, default: "")
  - `:region` - AWS region (optional, default: "us-east-1")
  - `:endpoint_url` - Custom endpoint URL for S3-compatible services (optional)

  AWS credentials are automatically loaded from standard AWS credential sources:
  - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  - Shared credentials file (~/.aws/credentials)
  - IAM role (when running on EC2/ECS)

  For testing with localstack or minio, set the `AWS_ENDPOINT_URL` environment variable:
  ```bash
  export AWS_ENDPOINT_URL=http://localhost:4566  # localstack
  export AWS_ENDPOINT_URL=http://localhost:9000  # minio
  ```

  ## Dependencies

  Requires `ex_aws` and `ex_aws_s3` packages:

  ```elixir
  {:ex_aws, "~> 2.5"},
  {:ex_aws_s3, "~> 2.5"}
  ```

  ## Example

  ```elixir
  # Register the S3 backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)

  # Create array with S3 storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :s3,
    bucket: "my-zarr-data",
    prefix: "experiments/array1"
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## S3 Structure

  Arrays are stored with the following key structure:
  ```
  s3://bucket/prefix/.zarray           # Metadata
  s3://bucket/prefix/0.0               # Chunk at index (0, 0)
  s3://bucket/prefix/0.1               # Chunk at index (0, 1)
  ```

  ## Performance Considerations

  - Chunks are read/written individually (parallel access recommended)
  - Consider chunk size vs. S3 request overhead
  - Use S3 Transfer Acceleration for global access
  - Configure appropriate IAM permissions

  ## Error Handling

  S3 errors are returned as `{:error, reason}` tuples with details from AWS.
  Common errors:
  - `:bucket_not_found` - Bucket doesn't exist
  - `:access_denied` - Insufficient permissions
  - `:network_error` - Network connectivity issues
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :s3

  @impl true
  def init(config) do
    with {:ok, bucket} <- fetch_required(config, :bucket) do
      prefix = Keyword.get(config, :prefix, "")
      region = Keyword.get(config, :region, "us-east-1")
      endpoint_url = Keyword.get(config, :endpoint_url) || System.get_env("AWS_ENDPOINT_URL")

      state = %{
        bucket: bucket,
        prefix: prefix,
        region: region,
        ex_aws_config: build_ex_aws_config(region, endpoint_url)
      }

      {:ok, state}
    end
  end

  @impl true
  def open(config) do
    # Same as init - S3 doesn't distinguish between init and open
    init(config)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    key = build_chunk_key(state.prefix, chunk_index)

    case ex_aws_s3().get_object(state.bucket, key) |> ex_aws().request(state.ex_aws_config) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    key = build_chunk_key(state.prefix, chunk_index)

    case ex_aws_s3().put_object(state.bucket, key, data)
         |> ex_aws().request(state.ex_aws_config) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @impl true
  def read_metadata(state) do
    key = build_metadata_key(state.prefix)

    case ex_aws_s3().get_object(state.bucket, key) |> ex_aws().request(state.ex_aws_config) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    key = build_metadata_key(state.prefix)

    case ex_aws_s3().put_object(state.bucket, key, metadata)
         |> ex_aws().request(state.ex_aws_config) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @impl true
  def list_chunks(state) do
    prefix = if state.prefix == "", do: "", else: "#{state.prefix}/"

    case ex_aws_s3().list_objects_v2(state.bucket, prefix: prefix)
         |> ex_aws().request(state.ex_aws_config) do
      {:ok, %{body: %{contents: objects}}} ->
        chunks =
          objects
          |> Enum.map(& &1.key)
          |> Enum.filter(&chunk_key?/1)
          |> Enum.map(&parse_chunk_key(&1, state.prefix))
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    key = build_chunk_key(state.prefix, chunk_index)

    case ex_aws_s3().delete_object(state.bucket, key) |> ex_aws().request(state.ex_aws_config) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, {:s3_error, reason}}
    end
  end

  @impl true
  def exists?(config) do
    case fetch_required(config, :bucket) do
      {:ok, bucket} ->
        region = Keyword.get(config, :region, "us-east-1")
        endpoint_url = Keyword.get(config, :endpoint_url) || System.get_env("AWS_ENDPOINT_URL")
        ex_aws_config = build_ex_aws_config(region, endpoint_url)

        case ex_aws_s3().head_bucket(bucket) |> ex_aws().request(ex_aws_config) do
          {:ok, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  ## Private Helpers

  defp fetch_required(config, key) do
    case Keyword.fetch(config, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {:ok, value}

      {:ok, nil} ->
        {:error, :"#{key}_required"}

      {:ok, _} ->
        {:error, :"invalid_#{key}"}

      :error ->
        {:error, :"#{key}_required"}
    end
  end

  defp build_ex_aws_config(region, nil) do
    # Use default AWS configuration
    [region: region]
  end

  defp build_ex_aws_config(region, endpoint_url) when is_binary(endpoint_url) do
    # Parse endpoint URL for localstack/minio support
    # ExAws expects: scheme, host, port instead of endpoint_url
    uri = URI.parse(endpoint_url)

    # Start with region and credentials (from env or default)
    config = [
      region: region,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID") || "test",
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY") || "test"
    ]

    config =
      if uri.scheme do
        Keyword.put(config, :scheme, "#{uri.scheme}://")
      else
        config
      end

    config =
      if uri.host do
        Keyword.put(config, :host, uri.host)
      else
        config
      end

    config =
      if uri.port do
        Keyword.put(config, :port, uri.port)
      else
        config
      end

    config
  end

  defp build_chunk_key("", chunk_index) do
    chunk_index
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp build_chunk_key(prefix, chunk_index) do
    chunk_name =
      chunk_index
      |> Tuple.to_list()
      |> Enum.join(".")

    "#{prefix}/#{chunk_name}"
  end

  defp build_metadata_key(""), do: ".zarray"
  defp build_metadata_key(prefix), do: "#{prefix}/.zarray"

  defp chunk_key?(key) do
    # Chunk keys are numeric with dots: 0, 0.0, 0.1.2, etc.
    basename = Path.basename(key)
    String.match?(basename, ~r/^\d+(\.\d+)*$/)
  end

  defp parse_chunk_key(key, "") do
    key
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  rescue
    _ -> nil
  end

  defp parse_chunk_key(key, prefix) do
    # Remove prefix and leading slash
    relative_key =
      key
      |> String.trim_leading(prefix)
      |> String.trim_leading("/")

    relative_key
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  rescue
    _ -> nil
  end

  # Allow injection for testing
  defp ex_aws do
    Application.get_env(:ex_zarr, :ex_aws_module, ExAws)
  end

  defp ex_aws_s3 do
    Application.get_env(:ex_zarr, :ex_aws_s3_module, ExAws.S3)
  end
end
