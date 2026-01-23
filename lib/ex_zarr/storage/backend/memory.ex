defmodule ExZarr.Storage.Backend.Memory do
  @moduledoc """
  In-memory storage backend for Zarr arrays.

  Stores chunks and metadata in an Elixir Agent for fast, temporary storage.
  Data is not persisted and will be lost when the process terminates.

  ## Use Cases

  - Temporary arrays during computation
  - Testing and development
  - Intermediate results that don't need persistence
  - High-performance caching

  ## Characteristics

  - **Fast**: Direct memory access, no I/O overhead
  - **Non-persistent**: Data lost on process termination
  - **Thread-safe**: Uses Agent for concurrent access
  - **No configuration**: No paths or connection strings needed

  ## Example

      # Create array with memory storage
      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        dtype: :float64,
        storage: :memory
      )

      # Write and read data
      ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
      {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :memory

  @impl true
  def init(_config) do
    # Create Agent to hold chunks and metadata
    {:ok, agent} = Agent.start_link(fn -> %{chunks: %{}, metadata: nil} end)
    {:ok, %{agent: agent}}
  end

  @impl true
  def open(_config) do
    # Memory storage cannot be "opened" as it doesn't persist
    {:error, :cannot_open_memory_storage}
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
      %{agent_state | chunks: new_chunks}
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
  def write_metadata(state, metadata, _opts) do
    Agent.update(state.agent, fn agent_state ->
      %{agent_state | metadata: metadata}
    end)

    :ok
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
      %{agent_state | chunks: new_chunks}
    end)

    :ok
  end

  @impl true
  def exists?(_config) do
    # Memory storage never "exists" on disk
    false
  end
end
