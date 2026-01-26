defmodule ExZarr.ArrayServer do
  @moduledoc """
  GenServer for coordinating concurrent access to Zarr arrays.

  Provides chunk-level locking to prevent write conflicts while allowing
  concurrent reads. Monitors processes holding locks and automatically
  cleans up on process crashes.

  ## Features

  - Chunk-level read/write locks
  - Multiple concurrent readers
  - Exclusive writers
  - Automatic lock cleanup on process crash
  - Deadlock prevention via timeouts
  - Process monitoring

  ## Lock Semantics

  - **Read locks**: Multiple processes can hold read locks on the same chunk simultaneously
  - **Write locks**: Only one process can hold a write lock on a chunk at a time
  - A chunk with a write lock cannot have any read locks (and vice versa)
  - Locks are automatically released when the process terminates

  ## Usage

      # Start server for an array
      {:ok, pid} = ExZarr.ArrayServer.start_link(array_id: "my_array")

      # Acquire write lock on chunk {0, 0}
      :ok = ExZarr.ArrayServer.lock_chunk(pid, {0, 0}, :write)

      # Do write operation...

      # Release lock
      :ok = ExZarr.ArrayServer.unlock_chunk(pid, {0, 0})

      # Acquire read lock (multiple processes can do this)
      :ok = ExZarr.ArrayServer.lock_chunk(pid, {0, 0}, :read)
  """

  use GenServer
  require Logger

  @type chunk_index :: tuple()
  @type lock_type :: :read | :write
  @type lock_timeout :: timeout()

  # 5 seconds
  @default_timeout 5_000

  defmodule State do
    @moduledoc false
    @type lock_info :: %{
            type: :read | :write,
            holders: MapSet.t(pid()),
            queue: :queue.queue()
          }

    @type t :: %__MODULE__{
            array_id: String.t(),
            locks: %{(chunk_index :: tuple()) => lock_info()},
            monitors: %{reference() => {pid(), chunk_index :: tuple()}}
          }

    defstruct array_id: nil,
              locks: %{},
              monitors: %{}
  end

  ## Client API

  @doc """
  Starts the ArrayServer for coordinating access to an array.

  ## Options

  - `:array_id` - Unique identifier for the array (required)
  - `:name` - Process name (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _array_id = Keyword.fetch!(opts, :array_id)
    {gen_opts, server_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, server_opts, gen_opts)
  end

  @doc """
  Acquires a lock on a specific chunk.

  ## Parameters

  - `server` - The ArrayServer process
  - `chunk_index` - Tuple identifying the chunk (e.g., `{0, 0}`)
  - `lock_type` - Either `:read` or `:write`
  - `timeout` - Maximum time to wait for lock (default: 5000ms)

  ## Returns

  - `:ok` if lock acquired
  - `{:error, :timeout}` if lock couldn't be acquired within timeout
  - `{:error, reason}` for other errors
  """
  @spec lock_chunk(GenServer.server(), chunk_index(), lock_type(), lock_timeout()) ::
          :ok | {:error, term()}
  def lock_chunk(server, chunk_index, lock_type, timeout \\ @default_timeout) do
    GenServer.call(server, {:lock_chunk, chunk_index, lock_type, self()}, timeout)
  end

  @doc """
  Releases a lock on a chunk.

  The calling process must currently hold a lock on the chunk.
  """
  @spec unlock_chunk(GenServer.server(), chunk_index()) :: :ok | {:error, term()}
  def unlock_chunk(server, chunk_index) do
    GenServer.call(server, {:unlock_chunk, chunk_index, self()})
  end

  @doc """
  Attempts to acquire a lock without blocking.

  Returns immediately with `:ok` if lock acquired or `{:error, :locked}` if not available.
  """
  @spec try_lock_chunk(GenServer.server(), chunk_index(), lock_type()) ::
          :ok | {:error, :locked | term()}
  def try_lock_chunk(server, chunk_index, lock_type) do
    GenServer.call(server, {:try_lock_chunk, chunk_index, lock_type, self()})
  end

  @doc """
  Returns information about all current locks.

  Useful for debugging and monitoring.
  """
  @spec get_locks(GenServer.server()) :: map()
  def get_locks(server) do
    GenServer.call(server, :get_locks)
  end

  @doc """
  Releases all locks held by the calling process.

  Useful for cleanup in error scenarios.
  """
  @spec release_all_locks(GenServer.server()) :: :ok
  def release_all_locks(server) do
    GenServer.call(server, {:release_all_locks, self()})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    array_id = Keyword.fetch!(opts, :array_id)
    Logger.debug("Starting ArrayServer for array_id=#{array_id}")

    {:ok,
     %State{
       array_id: array_id
     }}
  end

  @impl true
  def handle_call({:lock_chunk, chunk_index, lock_type, pid}, from, state) do
    case can_acquire_lock?(state.locks, chunk_index, lock_type) do
      true ->
        # Grant lock immediately
        updated_state = grant_lock(state, chunk_index, lock_type, pid)
        {:reply, :ok, updated_state}

      false ->
        # Queue the request
        updated_state = queue_lock_request(state, chunk_index, lock_type, pid, from)
        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_call({:try_lock_chunk, chunk_index, lock_type, pid}, _from, state) do
    case can_acquire_lock?(state.locks, chunk_index, lock_type) do
      true ->
        updated_state = grant_lock(state, chunk_index, lock_type, pid)
        {:reply, :ok, updated_state}

      false ->
        {:reply, {:error, :locked}, state}
    end
  end

  @impl true
  def handle_call({:unlock_chunk, chunk_index, pid}, _from, state) do
    case release_lock(state, chunk_index, pid) do
      {:ok, updated_state} ->
        # Process any queued requests for this chunk
        final_state = process_queue(updated_state, chunk_index)
        {:reply, :ok, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_locks, _from, state) do
    locks_info =
      Map.new(state.locks, fn {chunk_index, lock_info} ->
        {chunk_index,
         %{
           type: lock_info.type,
           holders: MapSet.to_list(lock_info.holders),
           queue_length: :queue.len(lock_info.queue)
         }}
      end)

    {:reply, locks_info, state}
  end

  @impl true
  def handle_call({:release_all_locks, pid}, _from, state) do
    updated_state = release_all_locks_for_pid(state, pid)
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    # Process died, release all its locks
    Logger.debug("Process #{inspect(pid)} died, releasing locks")

    # Find which chunk this monitor was for
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      {^pid, _chunk_index} ->
        # Remove monitor reference
        updated_state = %{state | monitors: Map.delete(state.monitors, ref)}

        # Release all locks for this pid
        final_state = release_all_locks_for_pid(updated_state, pid)

        {:noreply, final_state}
    end
  end

  ## Private Helpers

  defp can_acquire_lock?(locks, chunk_index, lock_type) do
    case Map.get(locks, chunk_index) do
      nil ->
        # No locks exist, can acquire
        true

      %{type: :read} when lock_type == :read ->
        # Multiple readers allowed
        true

      %{type: :read} when lock_type == :write ->
        # Can't get write lock while readers exist
        false

      %{type: :write} ->
        # Can't get any lock while writer exists
        false
    end
  end

  defp grant_lock(state, chunk_index, lock_type, pid) do
    # Monitor the process if not already monitored
    {updated_state, _ref} = ensure_monitored(state, pid, chunk_index)

    # Add or update lock
    lock_info =
      case Map.get(updated_state.locks, chunk_index) do
        nil ->
          # New lock
          %{
            type: lock_type,
            holders: MapSet.new([pid]),
            queue: :queue.new()
          }

        %{type: :read} = existing when lock_type == :read ->
          # Add to existing read locks
          %{existing | holders: MapSet.put(existing.holders, pid)}

        %{holders: holders} = existing ->
          # Lock exists but no holders (just released), grant new lock
          if MapSet.size(holders) == 0 do
            %{existing | type: lock_type, holders: MapSet.new([pid])}
          else
            # Shouldn't reach here if can_acquire_lock? is correct
            raise "Cannot grant lock: holders exist"
          end
      end

    %{updated_state | locks: Map.put(updated_state.locks, chunk_index, lock_info)}
  end

  defp release_lock(state, chunk_index, pid) do
    case Map.get(state.locks, chunk_index) do
      nil ->
        {:error, :not_locked}

      lock_info ->
        if MapSet.member?(lock_info.holders, pid) do
          updated_holders = MapSet.delete(lock_info.holders, pid)

          updated_state =
            if MapSet.size(updated_holders) == 0 and :queue.is_empty(lock_info.queue) do
              # No more holders and no queue, remove lock entirely
              %{state | locks: Map.delete(state.locks, chunk_index)}
            else
              # Update holders
              updated_lock_info = %{lock_info | holders: updated_holders}
              %{state | locks: Map.put(state.locks, chunk_index, updated_lock_info)}
            end

          {:ok, updated_state}
        else
          {:error, :not_holder}
        end
    end
  end

  defp queue_lock_request(state, chunk_index, lock_type, pid, from) do
    lock_info =
      Map.get(state.locks, chunk_index, %{type: nil, holders: MapSet.new(), queue: :queue.new()})

    updated_queue = :queue.in({lock_type, pid, from}, lock_info.queue)
    updated_lock_info = %{lock_info | queue: updated_queue}
    %{state | locks: Map.put(state.locks, chunk_index, updated_lock_info)}
  end

  defp process_queue(state, chunk_index) do
    case Map.get(state.locks, chunk_index) do
      nil ->
        # No lock info, nothing to process
        state

      %{queue: queue} = _lock_info ->
        # Check if queue is empty (can't use guard with :queue.is_empty/1)
        if :queue.is_empty(queue) do
          # Empty queue, nothing to process
          state
        else
          # Process queue
          process_queue_with_items(state, chunk_index, queue)
        end
    end
  end

  defp process_queue_with_items(state, chunk_index, queue) do
    lock_info = Map.get(state.locks, chunk_index)
    %{holders: holders} = lock_info

    # Check if we can grant next request
    if MapSet.size(holders) == 0 do
      # No current holders, can grant next in queue
      case :queue.out(queue) do
        {{:value, {lock_type, pid, from}}, remaining_queue} ->
          # Check if process is still alive
          if Process.alive?(pid) do
            updated_state = grant_lock(state, chunk_index, lock_type, pid)
            GenServer.reply(from, :ok)

            # Update queue
            updated_lock_info = %{
              Map.get(updated_state.locks, chunk_index)
              | queue: remaining_queue
            }

            updated_state = %{
              updated_state
              | locks: Map.put(updated_state.locks, chunk_index, updated_lock_info)
            }

            # Recursively process queue (for multiple readers)
            process_queue(updated_state, chunk_index)
          else
            # Process died, skip and process next
            updated_lock_info = %{lock_info | queue: remaining_queue}
            updated_state = %{state | locks: Map.put(state.locks, chunk_index, updated_lock_info)}
            process_queue(updated_state, chunk_index)
          end

        {:empty, _} ->
          state
      end
    else
      # Still have holders, can't grant yet
      state
    end
  end

  defp ensure_monitored(state, pid, chunk_index) do
    # Check if already monitored
    existing_ref =
      Enum.find_value(state.monitors, fn {ref, {monitored_pid, _}} ->
        if monitored_pid == pid, do: ref
      end)

    case existing_ref do
      nil ->
        # Not monitored, create monitor
        ref = Process.monitor(pid)
        {%{state | monitors: Map.put(state.monitors, ref, {pid, chunk_index})}, ref}

      ref ->
        # Already monitored
        {state, ref}
    end
  end

  defp release_all_locks_for_pid(state, pid) do
    # Find all chunks where this pid holds a lock
    chunks_to_release =
      state.locks
      |> Enum.filter(fn {_chunk_index, lock_info} ->
        MapSet.member?(lock_info.holders, pid)
      end)
      |> Enum.map(fn {chunk_index, _} -> chunk_index end)

    # Release each lock
    Enum.reduce(chunks_to_release, state, fn chunk_index, acc_state ->
      case release_lock(acc_state, chunk_index, pid) do
        {:ok, updated_state} ->
          process_queue(updated_state, chunk_index)

        {:error, _} ->
          acc_state
      end
    end)
  end
end
