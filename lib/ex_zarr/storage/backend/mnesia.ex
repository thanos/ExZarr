defmodule ExZarr.Storage.Backend.Mnesia do
  @moduledoc """
  Mnesia distributed database storage backend for Zarr arrays.

  Stores chunks and metadata in Mnesia, Erlang's built-in distributed database.
  Provides ACID transactions, replication, and fault tolerance.

  ## Configuration

  Requires the following options:
  - `:table_name` - Mnesia table name for storing array data (optional, default: `:zarr_storage`)
  - `:array_id` - Unique identifier for this array (required)
  - `:node` - Mnesia node (optional, default: current node)
  - `:ram_copies` - Use RAM copies instead of disc copies (optional, default: `false`)

  ## Dependencies

  No external dependencies - Mnesia is built into Erlang/OTP.

  ## Setup

  Mnesia must be initialized before use:

  ```elixir
  # In your application startup
  :mnesia.create_schema([node()])
  :mnesia.start()
  ```

  ## Example

  ```elixir
  # Register the Mnesia backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mnesia)

  # Create array with Mnesia storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :mnesia,
    array_id: "experiment_001"
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## Mnesia Table Structure

  Data is stored in a table with the following schema:
  ```
  {:zarr_storage, {array_id, chunk_index}, data}
  {:zarr_storage, {array_id, :metadata}, metadata_json}
  ```

  ## Performance Considerations

  - RAM tables provide fastest access but limited by memory
  - Disc tables persist across restarts
  - Distributed tables can be replicated across nodes
  - Consider fragmentation for very large tables

  ## Distributed Operation

  Mnesia supports multi-node operation:

  ```elixir
  # Create distributed table
  {:ok, array} = ExZarr.create(
    storage: :mnesia,
    array_id: "shared_array",
    nodes: [node(), :"node2@host", :"node3@host"]
  )
  ```

  ## Error Handling

  Mnesia errors are returned as `{:error, reason}` tuples.
  Common errors:
  - `:table_not_found` - Table doesn't exist
  - `:not_found` - Record doesn't exist
  - `:transaction_error` - Transaction failed
  """

  @behaviour ExZarr.Storage.Backend

  @default_table :zarr_storage

  @impl true
  def backend_id, do: :mnesia

  @impl true
  def init(config) do
    with {:ok, array_id} <- fetch_required(config, :array_id) do
      table_name = Keyword.get(config, :table_name, @default_table)
      ram_copies = Keyword.get(config, :ram_copies, false)
      nodes = Keyword.get(config, :nodes, [node()])

      # Ensure Mnesia is started
      ensure_mnesia_started()

      # Create table if it doesn't exist
      case create_table(table_name, ram_copies, nodes) do
        :ok ->
          state = %{
            table_name: table_name,
            array_id: array_id
          }

          {:ok, state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def open(config) do
    # Same as init for Mnesia
    with {:ok, array_id} <- fetch_required(config, :array_id) do
      table_name = Keyword.get(config, :table_name, @default_table)

      # Verify table exists
      try do
        case :mnesia.table_info(table_name, :size) do
          {:badrpc, _} ->
            {:error, :table_not_found}

          _ ->
            state = %{
              table_name: table_name,
              array_id: array_id
            }

            {:ok, state}
        end
      rescue
        _ -> {:error, :table_not_found}
      end
    end
  end

  @impl true
  def read_chunk(state, chunk_index) do
    key = {state.array_id, {:chunk, chunk_index}}

    case mnesia_transaction(fn ->
           :mnesia.read(state.table_name, key)
         end) do
      {:ok, [{_table, ^key, data}]} ->
        {:ok, data}

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    key = {state.array_id, {:chunk, chunk_index}}
    record = {state.table_name, key, data}

    case mnesia_transaction(fn ->
           :mnesia.write(record)
         end) do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  @impl true
  def read_metadata(state) do
    key = {state.array_id, :metadata}

    case mnesia_transaction(fn ->
           :mnesia.read(state.table_name, key)
         end) do
      {:ok, [{_table, ^key, metadata}]} ->
        {:ok, metadata}

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    key = {state.array_id, :metadata}
    record = {state.table_name, key, metadata}

    case mnesia_transaction(fn ->
           :mnesia.write(record)
         end) do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  @impl true
  def list_chunks(state) do
    pattern = {state.table_name, {state.array_id, {:chunk, :"$1"}}, :_}

    case mnesia_transaction(fn ->
           :mnesia.select(state.table_name, [{pattern, [], [:"$1"]}])
         end) do
      {:ok, chunk_indices} ->
        {:ok, chunk_indices}

      {:error, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    key = {state.array_id, {:chunk, chunk_index}}

    case mnesia_transaction(fn ->
           :mnesia.delete(state.table_name, key, :write)
         end) do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  @impl true
  def exists?(config) do
    table_name = Keyword.get(config, :table_name, @default_table)

    try do
      # Check if table exists
      :mnesia.table_info(table_name, :size)
      true
    rescue
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

  defp ensure_mnesia_started do
    case :mnesia.system_info(:is_running) do
      :yes ->
        :ok

      :no ->
        :mnesia.start()
        :ok

      _ ->
        :mnesia.start()
        :ok
    end
  end

  defp create_table(table_name, ram_copies, nodes) do
    attributes = [:key, :data]

    storage_type =
      if ram_copies do
        [ram_copies: nodes]
      else
        [disc_copies: nodes]
      end

    # Try to create table - will fail if it already exists
    case :mnesia.create_table(table_name, [attributes: attributes] ++ storage_type) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, ^table_name}} ->
        :ok

      {:aborted, reason} ->
        {:error, {:mnesia_error, reason}}
    end
  end

  defp mnesia_transaction(fun) do
    case :mnesia.transaction(fun) do
      {:atomic, result} -> {:ok, result}
      {:aborted, reason} -> {:error, reason}
    end
  end
end
