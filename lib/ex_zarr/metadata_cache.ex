defmodule ExZarr.MetadataCache do
  @moduledoc """
  ETS-based cache for Zarr array and group metadata.

  Caches metadata to reduce repeated file system or cloud storage reads.
  Particularly beneficial for cloud storage where metadata reads have
  significant latency and cost.

  ## Features

  - **ETS-based storage**: Fast, concurrent reads
  - **TTL support**: Configurable time-to-live for cache entries
  - **Automatic invalidation**: Clear cache on metadata writes
  - **Statistics tracking**: Monitor cache hit/miss rates
  - **Process-safe**: GenServer manages cache lifecycle

  ## Configuration

      config :ex_zarr, :metadata_cache,
        enabled: true,
        ttl: 300_000,      # 5 minutes in milliseconds
        max_size: 1000      # Maximum cached entries

  ## Usage

      # Start the cache (usually done by Application supervisor)
      {:ok, pid} = ExZarr.MetadataCache.start_link()

      # Cache metadata
      :ok = ExZarr.MetadataCache.put("/path/to/array", metadata)

      # Retrieve cached metadata
      {:ok, metadata} = ExZarr.MetadataCache.get("/path/to/array")

      # Invalidate on write
      :ok = ExZarr.MetadataCache.invalidate("/path/to/array")

      # Check statistics
      %{hits: 100, misses: 10, hit_rate: 0.909} =
        ExZarr.MetadataCache.stats()

  ## Cache Key Format

  Cache keys are derived from storage path and type:
  - `"/path/to/array"` - Array metadata
  - `"/path/to/group"` - Group metadata
  """

  use GenServer
  require Logger

  # 5 minutes
  @default_ttl 300_000
  @default_max_size 1000
  # 1 minute
  @cleanup_interval 60_000

  ## Client API

  @doc """
  Start the metadata cache GenServer.

  ## Options

    * `:name` - Registered name (default: `__MODULE__`)
    * `:ttl` - Time-to-live in milliseconds (default: 300_000)
    * `:max_size` - Maximum cache entries (default: 1000)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Retrieve metadata from cache.

  ## Parameters

    * `path` - Storage path to the array or group

  ## Returns

    * `{:ok, metadata}` - Cache hit, metadata returned
    * `{:error, :not_found}` - Cache miss

  ## Examples

      case ExZarr.MetadataCache.get("/data/my_array") do
        {:ok, metadata} ->
          # Use cached metadata
          IO.puts("Cache hit!")
        {:error, :not_found} ->
          # Read from storage
          IO.puts("Cache miss, reading from disk")
      end
  """
  @spec get(String.t(), atom()) :: {:ok, term()} | {:error, :not_found}
  def get(path, name \\ __MODULE__) do
    GenServer.call(name, {:get, path})
  end

  @doc """
  Store metadata in cache.

  ## Parameters

    * `path` - Storage path to the array or group
    * `metadata` - Metadata to cache (any term)

  ## Returns

    * `:ok` - Metadata cached successfully

  ## Examples

      metadata = %ExZarr.MetadataV3{...}
      :ok = ExZarr.MetadataCache.put("/data/my_array", metadata)
  """
  @spec put(String.t(), term(), atom()) :: :ok
  def put(path, metadata, name \\ __MODULE__) do
    GenServer.cast(name, {:put, path, metadata})
  end

  @doc """
  Invalidate cached metadata for a path.

  Should be called whenever metadata is written to storage.

  ## Parameters

    * `path` - Storage path to invalidate

  ## Returns

    * `:ok` - Entry invalidated (or didn't exist)

  ## Examples

      # After writing new metadata
      :ok = ExZarr.Storage.write_metadata(backend, metadata)
      :ok = ExZarr.MetadataCache.invalidate("/data/my_array")
  """
  @spec invalidate(String.t(), atom()) :: :ok
  def invalidate(path, name \\ __MODULE__) do
    GenServer.cast(name, {:invalidate, path})
  end

  @doc """
  Clear all cached metadata.

  ## Returns

    * `:ok` - Cache cleared

  ## Examples

      :ok = ExZarr.MetadataCache.clear()
  """
  @spec clear(atom()) :: :ok
  def clear(name \\ __MODULE__) do
    GenServer.cast(name, :clear)
  end

  @doc """
  Get cache statistics.

  ## Returns

    * Map with `:hits`, `:misses`, `:entries`, `:hit_rate`

  ## Examples

      stats = ExZarr.MetadataCache.stats()
      hit_rate_pct = stats.hit_rate * 100
      IO.puts("Hit rate: \#{hit_rate_pct}%")
      IO.puts("Total entries: \#{stats.entries}")
  """
  @spec stats(atom()) :: map()
  def stats(name \\ __MODULE__) do
    GenServer.call(name, :stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    max_size = Keyword.get(opts, :max_size, @default_max_size)

    # Create ETS table for cache storage
    table = :ets.new(:metadata_cache, [:set, :protected, read_concurrency: true])

    # Schedule periodic cleanup of expired entries
    Process.send_after(self(), :cleanup_expired, @cleanup_interval)

    state = %{
      table: table,
      ttl: ttl,
      max_size: max_size,
      hits: 0,
      misses: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, path}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(state.table, path) do
      [{^path, metadata, expires_at}] when expires_at > now ->
        # Cache hit, entry not expired
        {:reply, {:ok, metadata}, %{state | hits: state.hits + 1}}

      [{^path, _metadata, _expires_at}] ->
        # Entry expired, remove it
        :ets.delete(state.table, path)
        {:reply, {:error, :not_found}, %{state | misses: state.misses + 1}}

      [] ->
        # Cache miss
        {:reply, {:error, :not_found}, %{state | misses: state.misses + 1}}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total = state.hits + state.misses
    hit_rate = if total > 0, do: state.hits / total, else: 0.0
    entries = :ets.info(state.table, :size)

    stats = %{
      hits: state.hits,
      misses: state.misses,
      entries: entries,
      hit_rate: hit_rate
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:put, path, metadata}, state) do
    # Check if cache is full
    state =
      if :ets.info(state.table, :size) >= state.max_size do
        evict_oldest(state)
      else
        state
      end

    now = System.monotonic_time(:millisecond)
    expires_at = now + state.ttl

    :ets.insert(state.table, {path, metadata, expires_at})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:invalidate, path}, state) do
    :ets.delete(state.table, path)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(state.table)
    {:noreply, %{state | hits: 0, misses: 0}}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = System.monotonic_time(:millisecond)

    # Delete expired entries
    expired_count =
      state.table
      |> :ets.select([{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
      |> length()

    :ets.select_delete(state.table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])

    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired metadata cache entries")
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired, @cleanup_interval)

    {:noreply, state}
  end

  ## Private Helpers

  defp evict_oldest(state) do
    # Find entry with earliest expiration time
    case :ets.select(state.table, [{{:"$1", :_, :"$2"}, [], [{{:"$1", :"$2"}}]}], 1) do
      {[{path, _expires_at}], _continuation} ->
        :ets.delete(state.table, path)
        state

      :"$end_of_table" ->
        state
    end
  end
end
