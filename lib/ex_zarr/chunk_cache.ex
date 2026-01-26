defmodule ExZarr.ChunkCache do
  @moduledoc """
  LRU (Least Recently Used) cache for array chunks.

  Provides a GenServer-based cache for recently accessed chunks to improve
  performance for repeated reads. The cache automatically evicts the least
  recently used entries when the size limit is reached.

  ## Features

  - Thread-safe concurrent access
  - Configurable size limit
  - LRU eviction policy
  - Automatic cleanup

  ## Configuration

  Configure the cache size in your application config:

      config :ex_zarr, chunk_cache_size: 1000  # Number of chunks to cache

  ## Usage

      # Cache is automatically started with ExZarr application
      {:ok, pid} = ExZarr.ChunkCache.start_link(max_size: 1000)

      # Put chunk in cache
      :ok = ExZarr.ChunkCache.put(cache_key, chunk_data)

      # Get chunk from cache
      {:ok, chunk_data} = ExZarr.ChunkCache.get(cache_key)
      # or
      :not_found = ExZarr.ChunkCache.get(cache_key)

      # Clear entire cache
      :ok = ExZarr.ChunkCache.clear()
  """

  use GenServer
  require Logger

  # {array_path, chunk_index}
  @type cache_key :: {String.t(), tuple()}
  @type chunk_data :: binary()

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            cache: %{(cache_key :: term()) => {chunk_data :: binary(), access_time :: integer()}},
            lru_order: [cache_key :: term()],
            max_size: pos_integer(),
            hits: non_neg_integer(),
            misses: non_neg_integer()
          }

    defstruct cache: %{},
              lru_order: [],
              max_size: 1000,
              hits: 0,
              misses: 0
  end

  ## Client API

  @doc """
  Starts the chunk cache GenServer.

  ## Options

  - `:max_size` - Maximum number of chunks to cache (default: 1000)
  - `:name` - Process name (default: `ExZarr.ChunkCache`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, cache_opts} = Keyword.split(opts, [:name])
    gen_opts = Keyword.put_new(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, cache_opts, gen_opts)
  end

  @doc """
  Retrieves a chunk from the cache.

  Returns `{:ok, chunk_data}` if found, or `:not_found` if not in cache.
  Updates the access time for LRU tracking.
  """
  @spec get(cache_key(), GenServer.server()) :: {:ok, chunk_data()} | :not_found
  def get(key, server \\ __MODULE__) do
    GenServer.call(server, {:get, key})
  end

  @doc """
  Stores a chunk in the cache.

  If the cache is full, evicts the least recently used chunk.
  """
  @spec put(cache_key(), chunk_data(), GenServer.server()) :: :ok
  def put(key, data, server \\ __MODULE__) do
    GenServer.cast(server, {:put, key, data})
  end

  @doc """
  Removes a specific chunk from the cache.

  Used when a chunk is modified to invalidate the cached copy.
  """
  @spec invalidate(cache_key(), GenServer.server()) :: :ok
  def invalidate(key, server \\ __MODULE__) do
    GenServer.cast(server, {:invalidate, key})
  end

  @doc """
  Clears the entire cache.
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(server \\ __MODULE__) do
    GenServer.cast(server, :clear)
  end

  @doc """
  Returns cache statistics.

  Returns a map with:
  - `:size` - Current number of cached chunks
  - `:max_size` - Maximum cache capacity
  - `:hits` - Number of cache hits
  - `:misses` - Number of cache misses
  - `:hit_rate` - Percentage of requests that were hits
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, 1000)
    Logger.debug("Starting ChunkCache with max_size=#{max_size}")

    {:ok,
     %State{
       max_size: max_size
     }}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case Map.get(state.cache, key) do
      nil ->
        {:reply, :not_found, %{state | misses: state.misses + 1}}

      {data, _old_time} ->
        # Update access time and move to front of LRU order
        new_time = System.monotonic_time(:millisecond)
        updated_cache = Map.put(state.cache, key, {data, new_time})
        updated_lru = move_to_front(state.lru_order, key)

        {:reply, {:ok, data},
         %{state | cache: updated_cache, lru_order: updated_lru, hits: state.hits + 1}}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_requests = state.hits + state.misses
    hit_rate = if total_requests > 0, do: state.hits / total_requests * 100, else: 0.0

    stats = %{
      size: map_size(state.cache),
      max_size: state.max_size,
      hits: state.hits,
      misses: state.misses,
      hit_rate: hit_rate
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:put, key, data}, state) do
    access_time = System.monotonic_time(:millisecond)

    # Check if already in cache (just update)
    if Map.has_key?(state.cache, key) do
      updated_cache = Map.put(state.cache, key, {data, access_time})
      updated_lru = move_to_front(state.lru_order, key)
      {:noreply, %{state | cache: updated_cache, lru_order: updated_lru}}
    else
      # Need to add new entry
      {updated_cache, updated_lru} =
        if map_size(state.cache) >= state.max_size do
          # Evict LRU entry
          evict_lru(state.cache, state.lru_order, key, data, access_time)
        else
          # Just add
          {Map.put(state.cache, key, {data, access_time}), [key | state.lru_order]}
        end

      {:noreply, %{state | cache: updated_cache, lru_order: updated_lru}}
    end
  end

  @impl true
  def handle_cast({:invalidate, key}, state) do
    updated_cache = Map.delete(state.cache, key)
    updated_lru = List.delete(state.lru_order, key)
    {:noreply, %{state | cache: updated_cache, lru_order: updated_lru}}
  end

  @impl true
  def handle_cast(:clear, state) do
    Logger.debug("Clearing ChunkCache")
    {:noreply, %{state | cache: %{}, lru_order: [], hits: 0, misses: 0}}
  end

  ## Private Helpers

  defp move_to_front(lru_order, key) do
    # Remove key from its current position and add to front
    [key | List.delete(lru_order, key)]
  end

  defp evict_lru(cache, lru_order, new_key, new_data, access_time) do
    # Remove the last (least recently used) item
    lru_key = List.last(lru_order)
    updated_cache = cache |> Map.delete(lru_key) |> Map.put(new_key, {new_data, access_time})
    updated_lru = [new_key | List.delete(lru_order, lru_key)]
    {updated_cache, updated_lru}
  end
end
