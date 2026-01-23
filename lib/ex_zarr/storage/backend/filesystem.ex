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

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :filesystem

  @impl true
  def init(config) do
    case Keyword.fetch(config, :path) do
      {:ok, path} when is_binary(path) ->
        with :ok <- ensure_directory(path) do
          {:ok, %{path: path}}
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
        if File.exists?(path) do
          {:ok, %{path: path}}
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
    chunk_path = build_chunk_path(state.path, chunk_index)

    case File.read(chunk_path) do
      {:ok, data} -> {:ok, data}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    chunk_path = build_chunk_path(state.path, chunk_index)
    chunk_dir = Path.dirname(chunk_path)

    with :ok <- ensure_directory(chunk_dir) do
      File.write(chunk_path, data)
    end
  end

  @impl true
  def read_metadata(state) do
    metadata_path = Path.join(state.path, ".zarray")

    case File.read(metadata_path) do
      {:ok, json} -> {:ok, json}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    metadata_path = Path.join(state.path, ".zarray")
    File.write(metadata_path, metadata)
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
          |> Enum.filter(&is_chunk_file?/1)
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
      {:error, :enoent} -> :ok  # Already deleted
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

  defp build_chunk_path(base_path, chunk_index) do
    # Zarr uses dot-separated notation for chunk indices: 0.0, 0.1, etc.
    chunk_name =
      chunk_index
      |> Tuple.to_list()
      |> Enum.join(".")

    Path.join(base_path, chunk_name)
  end

  defp is_chunk_file?(filename) do
    # Chunk files are numeric with optional dots (0, 0.0, 0.1.2, etc.)
    # Exclude .zarray and other metadata files
    String.match?(filename, ~r/^\d+(\.\d+)*$/)
  end

  defp parse_chunk_filename(filename) do
    case String.split(filename, ".") do
      parts when length(parts) >= 1 ->
        parts
        |> Enum.map(&String.to_integer/1)
        |> List.to_tuple()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
