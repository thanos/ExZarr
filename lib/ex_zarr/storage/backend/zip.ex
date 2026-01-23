defmodule ExZarr.Storage.Backend.Zip do
  @moduledoc """
  Zip archive storage backend for Zarr arrays.

  Stores chunks and metadata in a single zip file, providing a compact,
  portable format for archiving and distributing Zarr arrays.

  ## Architecture

  Uses an in-memory cache (Agent) for reads and writes, with deferred disk
  writes. The zip file is only written when metadata is saved, reducing I/O
  overhead.

  ## Zip Structure

  ```
  array.zip
    ├── .zarray          # JSON metadata
    ├── 0.0              # Chunk at index {0, 0}
    ├── 0.1              # Chunk at index {0, 1}
    └── ...
  ```

  ## Characteristics

  - **Compact**: Single file, compressed storage
  - **Portable**: Easy to share and distribute
  - **Persistent**: Data survives process restarts
  - **Efficient**: Reduces file count for arrays with many chunks
  - **Read-optimized**: Fast random access to chunks

  ## Configuration

  Requires a `:path` option specifying the zip file location:

  ```elixir
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    dtype: :float64,
    storage: :zip,
    path: "/tmp/my_array.zip"
  )
  ```

  ## Usage Pattern

  1. **Create**: Initialize in-memory cache
  2. **Write**: Chunks go to cache (fast)
  3. **Save**: Call save to write zip file to disk
  4. **Open**: Load entire zip into cache
  5. **Read**: Fast access from cache

  ## Important Notes

  - Metadata save triggers disk write of entire zip
  - All chunks kept in memory for fast access
  - Not suitable for very large arrays (memory constraints)
  - Write operations require calling `ExZarr.save/2` to persist
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :zip

  @impl true
  def init(config) do
    case Keyword.fetch(config, :path) do
      {:ok, path} when is_binary(path) ->
        # Create in-memory cache
        {:ok, agent} =
          Agent.start_link(fn ->
            %{chunks: %{}, metadata: nil, modified: false, path: path}
          end)

        {:ok, %{agent: agent, path: path}}

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
          # Load entire zip file into memory cache
          case :zip.unzip(to_charlist(path), [:memory]) do
            {:ok, files} ->
              {:ok, agent} =
                Agent.start_link(fn ->
                  %{chunks: %{}, metadata: nil, modified: false, path: path}
                end)

              # Load all files from zip into agent
              Enum.each(files, fn {filename, content} ->
                filename_str = to_string(filename)

                cond do
                  filename_str == ".zarray" ->
                    Agent.update(agent, fn state ->
                      %{state | metadata: content}
                    end)

                  String.match?(filename_str, ~r/^\d+(\.\d+)*$/) ->
                    # Parse chunk index from filename
                    chunk_index = parse_chunk_filename(filename_str)

                    Agent.update(agent, fn state ->
                      new_chunks = Map.put(state.chunks, chunk_index, content)
                      %{state | chunks: new_chunks}
                    end)

                  true ->
                    :ok
                end
              end)

              {:ok, %{agent: agent, path: path}}

            {:error, reason} ->
              {:error, {:zip_error, reason}}
          end
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
    Agent.get(state.agent, fn agent_state ->
      case Map.get(agent_state.chunks, chunk_index) do
        nil -> {:error, :not_found}
        data -> {:ok, data}
      end
    end)
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    Agent.update(state.agent, fn agent_state ->
      new_chunks = Map.put(agent_state.chunks, chunk_index, data)
      %{agent_state | chunks: new_chunks, modified: true}
    end)

    :ok
  end

  @impl true
  def read_metadata(state) do
    Agent.get(state.agent, fn agent_state ->
      case Map.get(agent_state, :metadata) do
        nil -> {:error, :not_found}
        metadata -> {:ok, metadata}
      end
    end)
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    Agent.update(state.agent, fn agent_state ->
      %{agent_state | metadata: metadata, modified: true}
    end)

    # Write entire zip file to disk
    write_zip_file(state)
  end

  def write_metadata(state, metadata, opts) do
    # If metadata is not a binary, encode it first
    json = Jason.encode!(metadata, pretty: true)
    write_metadata(state, json, opts)
  end

  @impl true
  def list_chunks(state) do
    Agent.get(state.agent, fn agent_state ->
      {:ok, Map.keys(agent_state.chunks)}
    end)
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    Agent.update(state.agent, fn agent_state ->
      new_chunks = Map.delete(agent_state.chunks, chunk_index)
      %{agent_state | chunks: new_chunks, modified: true}
    end)

    :ok
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

  defp write_zip_file(state) do
    # Get all chunks and metadata from agent
    {chunks, metadata, path} =
      Agent.get(state.agent, fn agent_state ->
        {agent_state.chunks, agent_state.metadata, agent_state.path}
      end)

    # Build list of files for zip archive
    files =
      if metadata do
        [{~c".zarray", metadata}]
      else
        []
      end

    # Add all chunks
    chunk_files =
      Enum.map(chunks, fn {chunk_index, data} ->
        chunk_name =
          chunk_index
          |> Tuple.to_list()
          |> Enum.join(".")
          |> to_charlist()

        {chunk_name, data}
      end)

    all_files = files ++ chunk_files

    # Write zip file
    case :zip.create(to_charlist(path), all_files, [:memory]) do
      {:ok, {_filename, zip_content}} ->
        File.write(path, zip_content)

      {:error, reason} ->
        {:error, {:zip_error, reason}}
    end
  end

  defp parse_chunk_filename(filename) do
    filename
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end
end
