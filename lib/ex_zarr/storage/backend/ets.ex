defmodule ExZarr.Storage.Backend.ETS do
  @moduledoc """
  ETS (Erlang Term Storage) storage backend for Zarr arrays.

  Stores chunks and metadata in ETS tables, providing fast in-memory storage
  with multi-process access capabilities. Unlike the Memory backend which uses
  an Agent, ETS tables are shared memory accessible by multiple processes.

  ## Configuration

  Optional configuration:
  - `:table_name` - ETS table name (optional, auto-generated if not provided)
  - `:named_table` - Use named table (optional, default: `true`)
  - `:table_type` - Table type (optional, default: `:set`)
  - `:access` - Access level (optional, default: `:public`)
  - `:heir` - Heir process for table (optional, default: `:none`)

  ## Dependencies

  No external dependencies - ETS is built into Erlang/OTP.

  ## Example

  ```elixir
  # Register the ETS backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.ETS)

  # Create array with ETS storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :ets,
    table_name: :my_array_data
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## Table Types

  - `:set` - One value per unique key (default)
  - `:ordered_set` - Sorted set (slower writes, faster ordered access)
  - `:bag` - Multiple values per key allowed
  - `:duplicate_bag` - Multiple identical values per key allowed

  ## Access Levels

  - `:public` - Any process can read/write (default)
  - `:protected` - Any process can read, only owner can write
  - `:private` - Only owner process can read/write

  ## Named Tables

  Named tables can be accessed by name from any process:

  ```elixir
  # Create with named table
  {:ok, array} = ExZarr.create(
    storage: :ets,
    table_name: :shared_array,
    named_table: true,
    access: :public
  )

  # Access from different process
  :ets.lookup(:shared_array, {:chunk, {0}})
  ```

  ## Table Ownership

  ETS tables are owned by the creating process by default. When that process
  dies, the table is deleted. Use the `:heir` option to transfer ownership:

  ```elixir
  {:ok, array} = ExZarr.create(
    storage: :ets,
    heir: self()
  )
  ```

  ## Performance Characteristics

  - **Very fast**: Direct memory access, no message passing
  - **Concurrent**: Multiple readers, single writer
  - **Scalable**: Efficient for large datasets
  - **Non-persistent**: Data lost on table deletion

  ## Use Cases

  - Multi-process data sharing
  - High-performance caching
  - Concurrent read workloads
  - Inter-process communication
  - When you need faster access than Agent/GenServer

  ## Comparison with Memory Backend

  | Feature | Memory (Agent) | ETS |
  |---------|---------------|-----|
  | Access | Message passing | Direct memory |
  | Concurrency | Sequential | Concurrent reads |
  | Speed | Fast | Very fast |
  | Sharing | Via messages | Direct access |
  | Best for | Single process | Multi-process |

  ## Error Handling

  ETS errors are returned as `{:error, reason}` tuples.
  Common errors:
  - `:table_not_found` - Table doesn't exist
  - `:not_found` - Key doesn't exist
  - `:access_denied` - Permission error
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :ets

  @impl true
  def init(config) do
    table_name = Keyword.get(config, :table_name, generate_table_name())
    named_table = Keyword.get(config, :named_table, true)
    table_type = Keyword.get(config, :table_type, :set)
    access = Keyword.get(config, :access, :public)
    heir = Keyword.get(config, :heir, :none)

    # Build ETS options
    opts = [table_type, access]
    opts = if named_table, do: [:named_table | opts], else: opts

    opts =
      case heir do
        :none -> opts
        pid when is_pid(pid) -> [{:heir, pid, []} | opts]
        _ -> opts
      end

    # Create ETS table
    table =
      try do
        :ets.new(table_name, opts)
      rescue
        ArgumentError ->
          # Table might already exist if it's a named table
          if named_table and table_exists?(table_name) do
            table_name
          else
            reraise ArgumentError, __STACKTRACE__
          end
      end

    state = %{
      table: table,
      table_name: table_name,
      named_table: named_table,
      owner: self()
    }

    {:ok, state}
  end

  @impl true
  def open(config) do
    table_name = Keyword.get(config, :table_name)
    named_table = Keyword.get(config, :named_table, true)

    cond do
      is_nil(table_name) ->
        {:error, :table_name_required}

      named_table and table_exists?(table_name) ->
        state = %{
          table: table_name,
          table_name: table_name,
          named_table: true,
          owner: nil
        }

        {:ok, state}

      named_table ->
        {:error, :table_not_found}

      true ->
        {:error, :cannot_open_unnamed_table}
    end
  end

  @impl true
  def read_chunk(state, chunk_index) do
    key = {:chunk, chunk_index}

    case :ets.lookup(state.table, key) do
      [{^key, data}] ->
        {:ok, data}

      [] ->
        {:error, :not_found}
    end
  rescue
    ArgumentError ->
      {:error, :table_not_found}
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    key = {:chunk, chunk_index}

    :ets.insert(state.table, {key, data})
    :ok
  rescue
    ArgumentError ->
      {:error, :table_not_found}
  end

  @impl true
  def read_metadata(state) do
    key = :metadata

    case :ets.lookup(state.table, key) do
      [{^key, metadata}] ->
        {:ok, metadata}

      [] ->
        {:error, :not_found}
    end
  rescue
    ArgumentError ->
      {:error, :table_not_found}
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    key = :metadata

    :ets.insert(state.table, {key, metadata})
    :ok
  rescue
    ArgumentError ->
      {:error, :table_not_found}
  end

  @impl true
  def list_chunks(state) do
    # Match all chunk keys
    pattern = {{:chunk, :"$1"}, :_}

    try do
      chunk_indices = :ets.match(state.table, pattern)
      # match returns list of lists, extract the chunk indices
      chunks = Enum.map(chunk_indices, fn [index] -> index end)
      {:ok, chunks}
    rescue
      ArgumentError ->
        {:error, :table_not_found}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    key = {:chunk, chunk_index}

    :ets.delete(state.table, key)
    :ok
  rescue
    ArgumentError ->
      {:error, :table_not_found}
  end

  @impl true
  def exists?(config) do
    table_name = Keyword.get(config, :table_name)
    named_table = Keyword.get(config, :named_table, true)

    named_table and not is_nil(table_name) and table_exists?(table_name)
  end

  ## Public Helper Functions

  @doc """
  Delete an ETS table.

  Useful for cleanup in tests or when you want to explicitly remove a table.

  ## Example

      :ok = ExZarr.Storage.Backend.ETS.delete_table(:my_array_data)
  """
  @spec delete_table(atom() | :ets.tid()) :: :ok | {:error, :table_not_found}
  def delete_table(table) do
    if table_exists?(table) do
      :ets.delete(table)
      :ok
    else
      {:error, :table_not_found}
    end
  end

  @doc """
  Get information about an ETS table.

  ## Example

      info = ExZarr.Storage.Backend.ETS.table_info(:my_array_data)
      IO.inspect(info.size)
  """
  @spec table_info(atom() | :ets.tid()) :: map() | {:error, :table_not_found}
  def table_info(table) do
    if table_exists?(table) do
      %{
        name: :ets.info(table, :name),
        size: :ets.info(table, :size),
        memory: :ets.info(table, :memory),
        type: :ets.info(table, :type),
        protection: :ets.info(table, :protection),
        owner: :ets.info(table, :owner)
      }
    else
      {:error, :table_not_found}
    end
  end

  @doc """
  Get the current state (all chunks and metadata) from an ETS table.

  Useful for debugging and testing.

  ## Example

      state = ExZarr.Storage.Backend.ETS.get_state(:my_array_data)
      assert map_size(state.chunks) == 5
  """
  @spec get_state(atom() | :ets.tid()) :: %{chunks: map(), metadata: binary() | nil}
  def get_state(table) do
    chunks =
      :ets.match(table, {{:chunk, :"$1"}, :"$2"})
      |> Enum.map(fn [index, data] -> {index, data} end)
      |> Map.new()

    metadata =
      case :ets.lookup(table, :metadata) do
        [{:metadata, data}] -> data
        [] -> nil
      end

    %{chunks: chunks, metadata: metadata}
  end

  @doc """
  Clear all data from an ETS table without deleting it.

  ## Example

      :ok = ExZarr.Storage.Backend.ETS.clear_table(:my_array_data)
  """
  @spec clear_table(atom() | :ets.tid()) :: :ok | {:error, :table_not_found}
  def clear_table(table) do
    if table_exists?(table) do
      :ets.delete_all_objects(table)
      :ok
    else
      {:error, :table_not_found}
    end
  end

  @doc """
  Check if an ETS table exists.

  ## Example

      if ExZarr.Storage.Backend.ETS.table_exists?(:my_array_data) do
        IO.puts("Table exists")
      end
  """
  @spec table_exists?(atom() | :ets.tid()) :: boolean()
  def table_exists?(table) do
    case :ets.info(table) do
      :undefined -> false
      _ -> true
    end
  end

  ## Private Helpers

  defp generate_table_name do
    :"zarr_ets_#{:erlang.unique_integer([:positive])}"
  end
end
