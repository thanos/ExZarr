defmodule ExZarr.Storage.Backend do
  @moduledoc """
  Behavior for implementing custom storage backends.

  Storage backends handle the persistence and retrieval of Zarr array chunks
  and metadata. ExZarr provides built-in backends (`:memory`, `:filesystem`, `:zip`),
  and you can implement custom backends for other storage systems (S3, GCS, databases, etc.).

  ## Behavior Callbacks

  All storage backends must implement:

  - `backend_id/0` - Returns the unique identifier atom for this backend
  - `init/1` - Initializes the storage backend with configuration
  - `open/1` - Opens an existing storage location
  - `read_chunk/2` - Reads a chunk from storage
  - `write_chunk/3` - Writes a chunk to storage
  - `read_metadata/1` - Reads array metadata
  - `write_metadata/3` - Writes array metadata
  - `list_chunks/1` - Lists all chunk indices
  - `delete_chunk/2` - Deletes a chunk (optional)
  - `exists?/1` - Checks if storage location exists

  ## Example: Custom Database Backend

      defmodule MyApp.DatabaseStorage do
        @behaviour ExZarr.Storage.Backend

        @impl true
        def backend_id, do: :database

        @impl true
        def init(config) do
          # Initialize database connection
          {:ok, conn} = MyApp.DB.connect(config[:connection_string])
          {:ok, %{conn: conn, table: config[:table]}}
        end

        @impl true
        def read_chunk(state, chunk_index) do
          # Read chunk from database
          query = "SELECT data FROM \#{state.table} WHERE chunk_index = $1"
          case MyApp.DB.query(state.conn, query, [encode_index(chunk_index)]) do
            {:ok, [row]} -> {:ok, row.data}
            {:ok, []} -> {:error, :not_found}
            {:error, reason} -> {:error, reason}
          end
        end

        @impl true
        def write_chunk(state, chunk_index, data) do
          # Write chunk to database
          query = "INSERT INTO \#{state.table} (chunk_index, data) VALUES ($1, $2)
                   ON CONFLICT (chunk_index) DO UPDATE SET data = $2"
          case MyApp.DB.query(state.conn, query, [encode_index(chunk_index), data]) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

        # ... implement other callbacks
      end

      # Register the custom backend
      ExZarr.Storage.Registry.register(MyApp.DatabaseStorage)

      # Use the custom backend
      {:ok, array} = ExZarr.create(
        shape: {1000},
        chunks: {100},
        dtype: :float64,
        storage: :database,
        connection_string: "postgresql://...",
        table: "zarr_chunks"
      )

  ## Thread Safety

  Backend implementations must be thread-safe. If your backend maintains mutable state,
  use appropriate synchronization mechanisms (Agent, GenServer, ETS, etc.).

  ## Error Handling

  Callbacks should return `{:ok, result}` on success or `{:error, reason}` on failure.
  The `:not_found` error is reserved for missing chunks/metadata.
  """

  @type state :: term()
  @type chunk_index :: tuple()
  @type config :: keyword() | map()
  @type metadata :: ExZarr.Metadata.t()

  @doc """
  Returns the unique identifier for this storage backend.

  This atom is used when specifying `storage: :backend_id` in array creation.

  ## Examples

      def backend_id, do: :s3
      def backend_id, do: :database
  """
  @callback backend_id() :: atom()

  @doc """
  Initializes the storage backend with the given configuration.

  Called when creating a new array. Should set up any necessary connections,
  create directories/tables, allocate resources, etc.

  ## Parameters

  - `config` - Configuration map/keyword list containing backend-specific options

  ## Returns

  - `{:ok, state}` - Initialization successful, returns backend state
  - `{:error, reason}` - Initialization failed

  ## Examples

      def init(config) do
        path = Keyword.fetch!(config, :path)
        File.mkdir_p!(path)
        {:ok, %{path: path}}
      end
  """
  @callback init(config()) :: {:ok, state()} | {:error, term()}

  @doc """
  Opens an existing storage location.

  Called when opening an existing array. Should verify the location exists
  and set up necessary connections.

  ## Parameters

  - `config` - Configuration map/keyword list

  ## Returns

  - `{:ok, state}` - Successfully opened, returns backend state
  - `{:error, :not_found}` - Storage location doesn't exist
  - `{:error, reason}` - Other error

  ## Examples

      def open(config) do
        path = Keyword.fetch!(config, :path)
        if File.exists?(path) do
          {:ok, %{path: path}}
        else
          {:error, :not_found}
        end
      end
  """
  @callback open(config()) :: {:ok, state()} | {:error, term()}

  @doc """
  Reads a chunk from storage.

  ## Parameters

  - `state` - Backend state from init/open
  - `chunk_index` - Tuple identifying the chunk (e.g., `{0, 1}`)

  ## Returns

  - `{:ok, binary}` - Chunk data (compressed)
  - `{:error, :not_found}` - Chunk doesn't exist
  - `{:error, reason}` - Read error

  ## Examples

      def read_chunk(state, chunk_index) do
        path = build_chunk_path(state.path, chunk_index)
        case File.read(path) do
          {:ok, data} -> {:ok, data}
          {:error, :enoent} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
      end
  """
  @callback read_chunk(state(), chunk_index()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Writes a chunk to storage.

  ## Parameters

  - `state` - Backend state
  - `chunk_index` - Tuple identifying the chunk
  - `data` - Binary chunk data (compressed)

  ## Returns

  - `:ok` - Write successful
  - `{:error, reason}` - Write failed

  ## Examples

      def write_chunk(state, chunk_index, data) do
        path = build_chunk_path(state.path, chunk_index)
        File.write(path, data)
      end
  """
  @callback write_chunk(state(), chunk_index(), binary()) :: :ok | {:error, term()}

  @doc """
  Reads array metadata from storage.

  ## Parameters

  - `state` - Backend state

  ## Returns

  - `{:ok, metadata}` - Metadata struct
  - `{:error, :not_found}` - Metadata doesn't exist
  - `{:error, reason}` - Read error

  ## Examples

      def read_metadata(state) do
        path = Path.join(state.path, ".zarray")
        case File.read(path) do
          {:ok, json} ->
            {:ok, parsed} = Jason.decode(json, keys: :atoms)
            {:ok, parse_metadata(parsed)}
          {:error, :enoent} ->
            {:error, :not_found}
        end
      end
  """
  @callback read_metadata(state()) :: {:ok, metadata()} | {:error, term()}

  @doc """
  Writes array metadata to storage.

  ## Parameters

  - `state` - Backend state
  - `metadata` - Metadata struct
  - `opts` - Additional options (backend-specific)

  ## Returns

  - `:ok` - Write successful
  - `{:error, reason}` - Write failed

  ## Examples

      def write_metadata(state, metadata, _opts) do
        json = encode_metadata(metadata)
        path = Path.join(state.path, ".zarray")
        File.write(path, json)
      end
  """
  @callback write_metadata(state(), metadata(), keyword()) :: :ok | {:error, term()}

  @doc """
  Lists all chunk indices in storage.

  ## Parameters

  - `state` - Backend state

  ## Returns

  - `{:ok, [chunk_indices]}` - List of chunk index tuples
  - `{:error, reason}` - List failed

  ## Examples

      def list_chunks(state) do
        {:ok, files} = File.ls(state.path)
        chunks = files
          |> Enum.filter(&is_chunk_file?/1)
          |> Enum.map(&parse_chunk_index/1)
        {:ok, chunks}
      end
  """
  @callback list_chunks(state()) :: {:ok, [chunk_index()]} | {:error, term()}

  @doc """
  Deletes a chunk from storage (optional).

  ## Parameters

  - `state` - Backend state
  - `chunk_index` - Tuple identifying the chunk

  ## Returns

  - `:ok` - Delete successful or chunk didn't exist
  - `{:error, reason}` - Delete failed

  ## Examples

      def delete_chunk(state, chunk_index) do
        path = build_chunk_path(state.path, chunk_index)
        File.rm(path)
        :ok
      end
  """
  @callback delete_chunk(state(), chunk_index()) :: :ok | {:error, term()}

  @doc """
  Checks if storage location exists.

  ## Parameters

  - `config` - Configuration map/keyword list

  ## Returns

  - `true` if storage exists
  - `false` if storage doesn't exist

  ## Examples

      def exists?(config) do
        path = Keyword.fetch!(config, :path)
        File.exists?(path)
      end
  """
  @callback exists?(config()) :: boolean()

  @doc """
  Helper function to check if a module implements the Backend behavior.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    Code.ensure_loaded?(module) &&
      function_exported?(module, :backend_id, 0) &&
      function_exported?(module, :init, 1) &&
      function_exported?(module, :open, 1) &&
      function_exported?(module, :read_chunk, 2) &&
      function_exported?(module, :write_chunk, 3) &&
      function_exported?(module, :read_metadata, 1) &&
      function_exported?(module, :write_metadata, 3) &&
      function_exported?(module, :list_chunks, 1) &&
      function_exported?(module, :delete_chunk, 2) &&
      function_exported?(module, :exists?, 1)
  end
end
