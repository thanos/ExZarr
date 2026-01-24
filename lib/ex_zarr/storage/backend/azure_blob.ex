defmodule ExZarr.Storage.Backend.AzureBlob do
  @moduledoc """
  Azure Blob Storage backend for Zarr arrays.

  Stores chunks and metadata in Microsoft Azure Blob Storage, providing
  enterprise-grade cloud storage with global availability.

  ## Configuration

  Requires the following options:
  - `:account_name` - Azure storage account name (required)
  - `:account_key` - Azure storage account key (required)
  - `:container` - Blob container name (required)
  - `:prefix` - Blob prefix/path within container (optional, default: "")

  ## Dependencies

  Requires the `azurex` package:

  ```elixir
  {:azurex, "~> 0.3"}
  ```

  ## Example

  ```elixir
  # Register the Azure Blob backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.AzureBlob)

  # Create array with Azure Blob storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :azure_blob,
    account_name: "mystorageaccount",
    account_key: System.get_env("AZURE_STORAGE_KEY"),
    container: "zarr-data",
    prefix: "experiments/array1"
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## Blob Structure

  Arrays are stored with the following blob paths:
  ```
  container/prefix/.zarray           # Metadata
  container/prefix/0.0               # Chunk at index (0, 0)
  container/prefix/0.1               # Chunk at index (0, 1)
  ```

  ## Performance Considerations

  - Use blob block size appropriate for chunk sizes
  - Consider using Azure CDN for read-heavy workloads
  - Configure appropriate access tiers (Hot/Cool/Archive)
  - Use SAS tokens for delegated access

  ## Error Handling

  Azure Blob errors are returned as `{:error, reason}` tuples.
  Common errors:
  - `:container_not_found` - Container doesn't exist
  - `:access_denied` - Insufficient permissions
  - `:network_error` - Network connectivity issues
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :azure_blob

  @impl true
  def init(config) do
    with {:ok, account_name} <- fetch_required(config, :account_name),
         {:ok, account_key} <- fetch_required(config, :account_key),
         {:ok, container} <- fetch_required(config, :container) do
      prefix = Keyword.get(config, :prefix, "")

      state = %{
        account_name: account_name,
        account_key: account_key,
        container: container,
        prefix: prefix
      }

      {:ok, state}
    end
  end

  @impl true
  def open(config) do
    # Same as init for blob storage
    init(config)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    blob_name = build_blob_name(state.prefix, chunk_index)

    case azurex_blob().get_blob(
           state.account_name,
           state.account_key,
           state.container,
           blob_name
         ) do
      {:ok, blob_data} ->
        {:ok, blob_data}

      {:error, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:azure_error, reason}}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    blob_name = build_blob_name(state.prefix, chunk_index)

    case azurex_blob().put_block_blob(
           state.account_name,
           state.account_key,
           state.container,
           blob_name,
           data
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, {:azure_error, reason}}
    end
  end

  @impl true
  def read_metadata(state) do
    blob_name = build_metadata_name(state.prefix)

    case azurex_blob().get_blob(
           state.account_name,
           state.account_key,
           state.container,
           blob_name
         ) do
      {:ok, blob_data} ->
        {:ok, blob_data}

      {:error, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:azure_error, reason}}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    blob_name = build_metadata_name(state.prefix)

    case azurex_blob().put_block_blob(
           state.account_name,
           state.account_key,
           state.container,
           blob_name,
           metadata
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, {:azure_error, reason}}
    end
  end

  @impl true
  def list_chunks(state) do
    prefix = if state.prefix == "", do: "", else: "#{state.prefix}/"

    case azurex_blob().list_blobs(
           state.account_name,
           state.account_key,
           state.container,
           prefix: prefix
         ) do
      {:ok, blobs} ->
        chunks =
          blobs
          |> Enum.map(& &1.name)
          |> Enum.filter(&chunk_name?/1)
          |> Enum.map(&parse_blob_name(&1, state.prefix))
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, reason} ->
        {:error, {:azure_error, reason}}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    blob_name = build_blob_name(state.prefix, chunk_index)

    case azurex_blob().delete_blob(
           state.account_name,
           state.account_key,
           state.container,
           blob_name
         ) do
      {:ok, _} ->
        :ok

      {:error, %{status_code: 404}} ->
        :ok

      {:error, reason} ->
        {:error, {:azure_error, reason}}
    end
  end

  @impl true
  def exists?(config) do
    with {:ok, account_name} <- fetch_required(config, :account_name),
         {:ok, account_key} <- fetch_required(config, :account_key),
         {:ok, container} <- fetch_required(config, :container) do
      case azurex_blob().get_container_properties(account_name, account_key, container) do
        {:ok, _} -> true
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

  defp build_blob_name("", chunk_index) do
    chunk_index
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp build_blob_name(prefix, chunk_index) do
    chunk_name =
      chunk_index
      |> Tuple.to_list()
      |> Enum.join(".")

    "#{prefix}/#{chunk_name}"
  end

  defp build_metadata_name(""), do: ".zarray"
  defp build_metadata_name(prefix), do: "#{prefix}/.zarray"

  defp chunk_name?(name) do
    basename = Path.basename(name)
    String.match?(basename, ~r/^\d+(\.\d+)*$/)
  end

  defp parse_blob_name(name, "") do
    name
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  rescue
    _ -> nil
  end

  defp parse_blob_name(name, prefix) do
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

  # Allow injection for testing
  defp azurex_blob do
    Application.get_env(:ex_zarr, :azurex_blob_module, Azurex.Blob.Client)
  end
end
