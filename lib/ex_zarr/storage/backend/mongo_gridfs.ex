defmodule ExZarr.Storage.Backend.MongoGridFS do
  @moduledoc """
  MongoDB GridFS storage backend for Zarr arrays.

  Stores chunks and metadata in MongoDB using GridFS, which is designed for
  storing and retrieving large files. Ideal for distributed deployments with
  MongoDB replication.

  ## Configuration

  Requires the following options:
  - `:url` - MongoDB connection URL (required)
  - `:database` - Database name (required)
  - `:bucket` - GridFS bucket name (optional, default: "zarr")
  - `:array_id` - Unique identifier for this array (required)

  ## Dependencies

  Requires the `mongodb_driver` package:

  ```elixir
  {:mongodb_driver, "~> 1.4"}
  ```

  ## Example

  ```elixir
  # Register the MongoDB GridFS backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.MongoGridFS)

  # Create array with MongoDB GridFS storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :mongo_gridfs,
    url: "mongodb://localhost:27017",
    database: "zarr_db",
    bucket: "arrays",
    array_id: "experiment_001"
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## GridFS Structure

  Files are stored with the following naming convention:
  ```
  {array_id}/.zarray           # Metadata
  {array_id}/0.0               # Chunk at index (0, 0)
  {array_id}/0.1               # Chunk at index (0, 1)
  ```

  ## Performance Considerations

  - GridFS chunks files into 255KB pieces by default
  - Suitable for storing arrays with chunk sizes > 16MB
  - Benefits from MongoDB sharding for large deployments
  - Consider using indexes on filename for faster lookups

  ## Error Handling

  MongoDB errors are returned as `{:error, reason}` tuples.
  Common errors:
  - `:connection_error` - Cannot connect to MongoDB
  - `:not_found` - File doesn't exist
  - `:database_error` - MongoDB operation failed
  """

  @behaviour ExZarr.Storage.Backend

  @default_bucket "zarr"

  @impl true
  def backend_id, do: :mongo_gridfs

  @impl true
  def init(config) do
    with {:ok, url} <- fetch_required(config, :url),
         {:ok, database} <- fetch_required(config, :database),
         {:ok, array_id} <- fetch_required(config, :array_id),
         {:ok, conn} <- connect_mongo(url, database) do
      bucket = Keyword.get(config, :bucket, @default_bucket)

      state = %{
        conn: conn,
        bucket: bucket,
        array_id: array_id
      }

      {:ok, state}
    end
  end

  @impl true
  def open(config) do
    # Same as init for MongoDB
    init(config)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    filename = build_filename(state.array_id, chunk_index)

    case gridfs_download(state.conn, state.bucket, filename) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:mongo_error, reason}}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    filename = build_filename(state.array_id, chunk_index)

    # Delete existing file if it exists
    gridfs_delete(state.conn, state.bucket, filename)

    # Upload new file
    case gridfs_upload(state.conn, state.bucket, filename, data) do
      {:ok, _file_id} ->
        :ok

      {:error, reason} ->
        {:error, {:mongo_error, reason}}
    end
  end

  @impl true
  def read_metadata(state) do
    filename = build_metadata_filename(state.array_id)

    case gridfs_download(state.conn, state.bucket, filename) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:mongo_error, reason}}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    filename = build_metadata_filename(state.array_id)

    # Delete existing metadata if it exists
    gridfs_delete(state.conn, state.bucket, filename)

    # Upload new metadata
    case gridfs_upload(state.conn, state.bucket, filename, metadata) do
      {:ok, _file_id} ->
        :ok

      {:error, reason} ->
        {:error, {:mongo_error, reason}}
    end
  end

  @impl true
  def list_chunks(state) do
    prefix = "#{state.array_id}/"

    case gridfs_list(state.conn, state.bucket, prefix) do
      {:ok, filenames} ->
        chunks =
          filenames
          |> Enum.filter(&chunk_filename?/1)
          |> Enum.map(&parse_filename(&1, state.array_id))
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, reason} ->
        {:error, {:mongo_error, reason}}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    filename = build_filename(state.array_id, chunk_index)
    # gridfs_delete always returns :ok (errors are ignored)
    gridfs_delete(state.conn, state.bucket, filename)
  end

  @impl true
  def exists?(config) do
    with {:ok, url} <- fetch_required(config, :url),
         {:ok, database} <- fetch_required(config, :database),
         {:ok, _conn} <- connect_mongo(url, database) do
      true
    else
      _ -> false
    end
  end

  ## Private Helpers

  defp fetch_required(config, key) do
    case Keyword.fetch(config, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {:ok, value}

      {:ok, value} when is_atom(value) and not is_nil(value) ->
        {:ok, value}

      {:ok, nil} ->
        {:error, :"#{key}_required"}

      {:ok, _} ->
        {:error, :"invalid_#{key}"}

      :error ->
        {:error, :"#{key}_required"}
    end
  end

  defp connect_mongo(url, database) do
    case mongo().start_link(url: url, database: database, pool_size: 5) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  defp build_filename(array_id, chunk_index) do
    chunk_name =
      chunk_index
      |> Tuple.to_list()
      |> Enum.join(".")

    "#{array_id}/#{chunk_name}"
  end

  defp build_metadata_filename(array_id), do: "#{array_id}/.zarray"

  defp chunk_filename?(filename) do
    basename = Path.basename(filename)
    String.match?(basename, ~r/^\d+(\.\d+)*$/)
  end

  defp parse_filename(filename, array_id) do
    relative_name =
      filename
      |> String.trim_leading("#{array_id}/")

    relative_name
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  rescue
    _ -> nil
  end

  defp gridfs_upload(conn, bucket, filename, data) do
    opts = [filename: filename]

    case mongo_gridfs().upload(conn, data, opts, bucket: bucket) do
      {:ok, file_id} ->
        {:ok, file_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gridfs_download(conn, bucket, filename) do
    case mongo_gridfs().download(conn, filename, bucket: bucket) do
      {:ok, data} ->
        {:ok, IO.iodata_to_binary(data)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gridfs_delete(conn, bucket, filename) do
    case mongo_gridfs().delete(conn, filename, bucket: bucket) do
      :ok ->
        :ok

      {:error, _reason} ->
        # Ignore errors for delete (file might not exist)
        :ok
    end
  end

  defp gridfs_list(conn, bucket, prefix) do
    collection = "#{bucket}.files"

    filter = %{"filename" => %{"$regex" => "^#{Regex.escape(prefix)}"}}

    case mongo().find(conn, collection, filter) |> Enum.to_list() do
      {:error, reason} ->
        {:error, reason}

      results when is_list(results) ->
        filenames = Enum.map(results, & &1["filename"])
        {:ok, filenames}
    end
  rescue
    error ->
      {:error, error}
  end

  # Allow injection for testing
  defp mongo do
    Application.get_env(:ex_zarr, :mongo_module, Mongo)
  end

  defp mongo_gridfs do
    Application.get_env(:ex_zarr, :mongo_gridfs_module, Mongo.GridFs)
  end
end
