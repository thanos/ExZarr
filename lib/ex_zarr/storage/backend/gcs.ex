defmodule ExZarr.Storage.Backend.GCS do
  @moduledoc """
  Google Cloud Storage (GCS) backend for Zarr arrays.

  Stores chunks and metadata in Google Cloud Storage, providing globally
  distributed object storage with strong consistency.

  ## Configuration

  Requires the following options:
  - `:bucket` - GCS bucket name (required)
  - `:prefix` - Object prefix/path within bucket (optional, default: "")
  - `:credentials` - Path to service account JSON file or credentials map (required)
  - `:endpoint_url` - Custom endpoint URL for fake-gcs-server or compatible services (optional)

  For testing with fake-gcs-server, set the `GCS_ENDPOINT_URL` environment variable:
  ```bash
  export GCS_ENDPOINT_URL=http://localhost:4443  # fake-gcs-server
  ```

  ## Dependencies

  Requires the `goth` and `req` packages:

  ```elixir
  {:goth, "~> 1.4"},
  {:req, "~> 0.4"}
  ```

  ## Authentication

  Uses Google Cloud service account credentials. Credentials can be provided:
  - As a path to a JSON key file: `credentials: "/path/to/service-account.json"`
  - As a decoded map: `credentials: %{...}`
  - Via GOOGLE_APPLICATION_CREDENTIALS environment variable

  ## Example

  ```elixir
  # Register the GCS backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.GCS)

  # Create array with GCS storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :gcs,
    bucket: "my-zarr-bucket",
    prefix: "experiments/array1",
    credentials: System.get_env("GOOGLE_APPLICATION_CREDENTIALS")
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## GCS Structure

  Arrays are stored with the following object paths:
  ```
  gs://bucket/prefix/.zarray           # Metadata
  gs://bucket/prefix/0.0               # Chunk at index (0, 0)
  gs://bucket/prefix/0.1               # Chunk at index (0, 1)
  ```

  ## Performance Considerations

  - Objects are read/written individually
  - Use appropriate chunk sizes for your access patterns
  - Consider using Cloud CDN for read-heavy workloads
  - Configure appropriate storage classes (Standard/Nearline/Coldline/Archive)

  ## Error Handling

  GCS errors are returned as `{:error, reason}` tuples.
  Common errors:
  - `:bucket_not_found` - Bucket doesn't exist
  - `:access_denied` - Insufficient permissions
  - `:network_error` - Network connectivity issues
  """

  @behaviour ExZarr.Storage.Backend

  @base_url "https://storage.googleapis.com/storage/v1"
  @upload_url "https://storage.googleapis.com/upload/storage/v1"

  @impl true
  def backend_id, do: :gcs

  @impl true
  def init(config) do
    with {:ok, bucket} <- fetch_required(config, :bucket),
         {:ok, goth_name} <- setup_goth(config) do
      prefix = Keyword.get(config, :prefix, "")
      endpoint_url = Keyword.get(config, :endpoint_url) || System.get_env("GCS_ENDPOINT_URL")

      {base_url, upload_url} = build_urls(endpoint_url)

      state = %{
        bucket: bucket,
        prefix: prefix,
        goth_name: goth_name,
        base_url: base_url,
        upload_url: upload_url
      }

      {:ok, state}
    end
  end

  @impl true
  def open(config) do
    # Same as init for GCS
    init(config)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    object_name = build_object_name(state.prefix, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url =
        "#{state.base_url}/b/#{state.bucket}/o/#{URI.encode(object_name, &URI.char_unreserved?/1)}"

      case req().get(url,
             params: [alt: "media"],
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          {:ok, body}

        {:ok, %{status: 200, body: body}} ->
          # Handle case where body might be decoded - should not happen for chunks
          {:ok, IO.iodata_to_binary([body])}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    object_name = build_object_name(state.prefix, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.upload_url}/b/#{state.bucket}/o"

      case req().post(url,
             params: [uploadType: "media", name: object_name],
             headers: [
               {"authorization", "Bearer #{token}"},
               {"content-type", "application/octet-stream"}
             ],
             body: data
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def read_metadata(state) do
    object_name = build_metadata_name(state.prefix)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url =
        "#{state.base_url}/b/#{state.bucket}/o/#{URI.encode(object_name, &URI.char_unreserved?/1)}"

      case req().get(url,
             params: [alt: "media"],
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          {:ok, body}

        {:ok, %{status: 200, body: body}} when is_map(body) ->
          # Req auto-decoded JSON, re-encode it
          {:ok, Jason.encode!(body)}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    object_name = build_metadata_name(state.prefix)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.upload_url}/b/#{state.bucket}/o"

      case req().post(url,
             params: [uploadType: "media", name: object_name],
             headers: [
               {"authorization", "Bearer #{token}"},
               {"content-type", "application/json"}
             ],
             body: metadata
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def list_chunks(state) do
    prefix = if state.prefix == "", do: "", else: "#{state.prefix}/"

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.base_url}/b/#{state.bucket}/o"

      case req().get(url,
             params: [prefix: prefix],
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
        {:ok, %{status: 200, body: %{"items" => items}}} when is_list(items) ->
          chunks =
            items
            |> Enum.map(& &1["name"])
            |> Enum.filter(&chunk_name?/1)
            |> Enum.map(&parse_object_name(&1, state.prefix))
            |> Enum.reject(&is_nil/1)

          {:ok, chunks}

        {:ok, %{status: 200, body: _}} ->
          {:ok, []}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    object_name = build_object_name(state.prefix, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url =
        "#{state.base_url}/b/#{state.bucket}/o/#{URI.encode(object_name, &URI.char_unreserved?/1)}"

      case req().delete(url, headers: [{"authorization", "Bearer #{token}"}]) do
        {:ok, %{status: status}} when status in 200..299 or status == 404 ->
          :ok

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def exists?(config) do
    with {:ok, bucket} <- fetch_required(config, :bucket),
         {:ok, goth_name} <- setup_goth(config),
         {:ok, token} <- get_access_token(goth_name) do
      endpoint_url = Keyword.get(config, :endpoint_url) || System.get_env("GCS_ENDPOINT_URL")
      {base_url, _upload_url} = build_urls(endpoint_url)
      url = "#{base_url}/b/#{bucket}"

      case req().get(url, headers: [{"authorization", "Bearer #{token}"}]) do
        {:ok, %{status: 200}} -> true
        _ -> false
      end
    else
      _ -> false
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

  defp setup_goth(config) do
    credentials = Keyword.get(config, :credentials)

    cond do
      is_binary(credentials) and File.exists?(credentials) ->
        # Credentials file path
        name = :"goth_#{:erlang.unique_integer([:positive])}"

        case goth().start_link(
               name: name,
               source: {:service_account, credentials}
             ) do
          {:ok, _pid} -> {:ok, name}
          {:error, reason} -> {:error, {:goth_error, reason}}
        end

      is_map(credentials) ->
        # Credentials map
        name = :"goth_#{:erlang.unique_integer([:positive])}"

        case goth().start_link(
               name: name,
               source: {:service_account, credentials}
             ) do
          {:ok, _pid} -> {:ok, name}
          {:error, reason} -> {:error, {:goth_error, reason}}
        end

      is_nil(credentials) ->
        # Try default credentials
        name = :"goth_#{:erlang.unique_integer([:positive])}"

        case goth().start_link(name: name) do
          {:ok, _pid} -> {:ok, name}
          {:error, reason} -> {:error, {:goth_error, reason}}
        end

      true ->
        {:error, :invalid_credentials}
    end
  end

  defp get_access_token(goth_name) do
    case goth().fetch(goth_name) do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, reason} -> {:error, {:goth_error, reason}}
    end
  end

  defp build_object_name(prefix, chunk_index, version \\ 2) do
    chunk_name = ExZarr.ChunkKey.encode(chunk_index, version)

    if prefix == "" do
      chunk_name
    else
      Path.join(prefix, chunk_name)
    end
  end

  defp build_metadata_name(""), do: ".zarray"
  defp build_metadata_name(prefix), do: "#{prefix}/.zarray"

  defp chunk_name?(name) do
    # Use ChunkKey pattern matching for v2 format (default for GCS)
    basename = Path.basename(name)
    pattern = ExZarr.ChunkKey.chunk_key_pattern(2)
    String.match?(basename, pattern)
  end

  defp parse_object_name(name, "") do
    name
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  rescue
    _ -> nil
  end

  defp parse_object_name(name, prefix) do
    relative_name =
      name
      |> String.trim_leading(prefix)
      |> String.trim_leading("/")

    relative_name
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  rescue
    _ -> nil
  end

  defp build_urls(nil) do
    # Use default GCS URLs
    {@base_url, @upload_url}
  end

  defp build_urls(endpoint_url) when is_binary(endpoint_url) do
    # Use custom endpoint for fake-gcs-server or compatible services
    base_url = "#{endpoint_url}/storage/v1"
    upload_url = "#{endpoint_url}/upload/storage/v1"
    {base_url, upload_url}
  end

  # Allow injection for testing
  defp req do
    Application.get_env(:ex_zarr, :req_module, Req)
  end

  defp goth do
    Application.get_env(:ex_zarr, :goth_module, Goth)
  end
end
