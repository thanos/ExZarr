defmodule ExZarr.Storage.Backend.Filesystem do
  @moduledoc """
  Local filesystem storage backend for Zarr arrays.

  Stores chunks and metadata on the local filesystem following the Zarr v2
  directory structure specification. Each chunk is stored as a separate file
  with dot-separated indices.

  ## Directory Structure

  ```
  /path/to/array/
    .zarray          # JSON metadata file
    0                # Chunk at index {0} (1D)
    0.0              # Chunk at index {0, 0} (2D)
    0.1              # Chunk at index {0, 1}
    1.0              # Chunk at index {1, 0}
    ...
  ```

  ## Characteristics

  - **Persistent**: Data survives process restarts
  - **Portable**: Standard Zarr format, interoperable with Python zarr
  - **Inspectable**: Files can be examined with standard tools
  - **Hierarchical**: Supports nested directory structures
  - **Concurrent**: Multiple processes can read simultaneously

  ## Configuration

  Requires a `:path` option specifying the directory location:

  ```elixir
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    dtype: :float64,
    storage: :filesystem,
    path: "/tmp/my_array"
  )
  ```

  ## Python Interoperability

  Arrays created with this backend can be read by Python zarr:

  ```python
  import zarr
  z = zarr.open('/tmp/my_array', mode='r')
  data = z[:]
  ```
  """

  alias ExZarr.Storage.FileLock

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :filesystem

  @impl true
  def init(config) do
    case Keyword.fetch(config, :path) do
      {:ok, path} when is_binary(path) ->
        use_file_locks = Keyword.get(config, :use_file_locks, true)

        with :ok <- ensure_directory(path) do
          {:ok, %{path: path, use_file_locks: use_file_locks}}
        end

      {:ok, nil} ->
        {:error, :path_required}

      {:ok, _} ->
        {:error, :invalid_path}

      :error ->
        {:error, :path_required}
    end
  end

  @impl true
  def open(config) do
    case Keyword.fetch(config, :path) do
      {:ok, path} when is_binary(path) ->
        use_file_locks = Keyword.get(config, :use_file_locks, true)

        if File.exists?(path) do
          {:ok, %{path: path, use_file_locks: use_file_locks}}
        else
          {:error, :not_found}
        end

      {:ok, nil} ->
        {:error, :path_required}

      {:ok, _} ->
        {:error, :invalid_path}

      :error ->
        {:error, :path_required}
    end
  end

  @impl true
  def read_chunk(state, chunk_index) do
    version = detect_version(state.path)
    chunk_path = build_chunk_path(state.path, chunk_index, version)

    if Map.get(state, :use_file_locks, true) do
      # Use file locking for safe reads
      case FileLock.with_read_lock(chunk_path, [timeout: 5000], fn ->
             File.read(chunk_path)
           end) do
        {:ok, {:ok, data}} -> {:ok, data}
        {:ok, {:error, :enoent}} -> {:error, :not_found}
        {:ok, {:error, reason}} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    else
      # Original logic without file locking
      case File.read(chunk_path) do
        {:ok, data} -> {:ok, data}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    version = detect_version(state.path)
    chunk_path = build_chunk_path(state.path, chunk_index, version)
    chunk_dir = Path.dirname(chunk_path)

    with :ok <- ensure_directory(chunk_dir) do
      if Map.get(state, :use_file_locks, true) do
        # Use file locking for atomic writes with fsync
        case FileLock.with_write_lock(chunk_path, [timeout: 5000], fn ->
               with :ok <- File.write(chunk_path, data) do
                 # Ensure data is fully written to disk before releasing lock
                 case :file.open(chunk_path, [:read, :raw]) do
                   {:ok, fd} ->
                     _ = :file.sync(fd)
                     _ = :file.close(fd)
                     :ok

                   {:error, reason} ->
                     {:error, reason}
                 end
               end
             end) do
          {:ok, :ok} -> :ok
          {:ok, {:error, reason}} -> {:error, reason}
          {:error, reason} -> {:error, reason}
        end
      else
        # Original logic without file locking
        File.write(chunk_path, data)
      end
    end
  end

  @impl true
  def read_metadata(state) do
    # Try v3 first (zarr.json), then v2 (.zarray)
    v3_path = Path.join(state.path, "zarr.json")
    v2_path = Path.join(state.path, ".zarray")

    case File.read(v3_path) do
      {:ok, json} ->
        {:ok, json}

      {:error, :enoent} ->
        # Try v2 format
        case File.read(v2_path) do
          {:ok, json} -> {:ok, json}
          {:error, :enoent} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    # Determine filename based on zarr_format in the JSON
    case Jason.decode(metadata) do
      {:ok, %{"zarr_format" => 3}} ->
        metadata_path = Path.join(state.path, "zarr.json")
        File.write(metadata_path, metadata)

      {:ok, %{"zarr_format" => 2}} ->
        metadata_path = Path.join(state.path, ".zarray")
        File.write(metadata_path, metadata)

      _ ->
        # Default to v2 for backward compatibility
        metadata_path = Path.join(state.path, ".zarray")
        File.write(metadata_path, metadata)
    end
  end

  def write_metadata(state, metadata, opts) do
    # If metadata is not a binary, encode it first
    json = Jason.encode!(metadata, pretty: true)
    write_metadata(state, json, opts)
  end

  @impl true
  def list_chunks(state) do
    case File.ls(state.path) do
      {:ok, files} ->
        chunks =
          files
          |> Enum.filter(&chunk_file?/1)
          |> Enum.map(&parse_chunk_filename/1)
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    chunk_path = build_chunk_path(state.path, chunk_index)

    case File.rm(chunk_path) do
      :ok -> :ok
      # Already deleted
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(config) do
    case Keyword.fetch(config, :path) do
      {:ok, path} when is_binary(path) ->
        File.exists?(path)

      _ ->
        false
    end
  end

  ## Private Helpers

  defp ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  # Detect zarr format version by checking which metadata file exists
  defp detect_version(base_path) do
    v3_path = Path.join(base_path, "zarr.json")
    v2_path = Path.join(base_path, ".zarray")

    cond do
      File.exists?(v3_path) -> 3
      File.exists?(v2_path) -> 2
      # Default to v2 for new arrays
      true -> 2
    end
  end

  defp build_chunk_path(base_path, chunk_index, version) do
    chunk_key = ExZarr.ChunkKey.encode(chunk_index, version)
    Path.join(base_path, chunk_key)
  end

  # Legacy function for backward compatibility
  defp build_chunk_path(base_path, chunk_index) do
    build_chunk_path(base_path, chunk_index, 2)
  end

  defp chunk_file?(filename) do
    # Chunk files are numeric with optional dots (0, 0.0, 0.1.2, etc.)
    # Exclude .zarray and other metadata files
    String.match?(filename, ~r/^\d+(\.\d+)*$/)
  end

  defp parse_chunk_filename(filename) do
    case String.split(filename, ".") do
      [] ->
        nil

      parts ->
        parts
        |> Enum.map(&String.to_integer/1)
        |> List.to_tuple()
    end
  rescue
    _ -> nil
  end
end
