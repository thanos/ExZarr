defmodule ExZarr.Storage.Registry do
  @moduledoc """
  Registry for managing storage backends.

  The registry maintains a mapping of backend IDs to backend modules and provides
  functions for registering, querying, and using storage backends.

  ## Built-in Backends

  The following backends are registered by default:
  - `:memory` - In-memory storage (fast, non-persistent)
  - `:filesystem` - Local filesystem storage
  - `:zip` - Zip archive storage

  ## Registering Custom Backends

  ### Via Configuration

  Add to `config/config.exs`:

      config :ex_zarr, :custom_storage_backends, [
        MyApp.S3Storage,
        MyApp.DatabaseStorage
      ]

  ### Programmatically

      ExZarr.Storage.Registry.register(MyApp.S3Storage)

  ### At Application Start

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          # Register custom storage backends
          ExZarr.Storage.Registry.register(MyApp.S3Storage)

          # ... rest of supervision tree
        end
      end

  ## Querying Backends

      # Get a backend module
      {:ok, module} = ExZarr.Storage.Registry.get(:s3)

      # List all registered backend IDs
      ids = ExZarr.Storage.Registry.list()

      # Get backend information
      {:ok, info} = ExZarr.Storage.Registry.info(:s3)
  """

  use GenServer
  require Logger

  alias Backend

  @type backend_module :: module()
  @type backend_id :: atom()
  @type registry_state :: %{
          backends: %{backend_id() => backend_module()},
          built_in: [backend_id()]
        }

  ## Client API

  @doc """
  Starts the storage backend registry.

  This is typically called automatically by the application supervision tree.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a custom storage backend module.

  The module must implement the `Backend` behavior.

  ## Options

  - `:force` - If `true`, overwrites existing backend with same ID (default: `false`)

  ## Examples

      iex> ExZarr.Storage.Registry.register(MyApp.S3Storage)
      :ok

      iex> ExZarr.Storage.Registry.register(MyBackend, force: true)
      :ok

  ## Returns

  - `:ok` - Backend registered successfully
  - `{:error, :already_registered}` - Backend ID already in use (unless `force: true`)
  - `{:error, :invalid_backend}` - Module doesn't implement Backend behavior
  """
  @spec register(backend_module(), keyword()) :: :ok | {:error, term()}
  def register(backend_module, opts \\ []) when is_atom(backend_module) do
    GenServer.call(__MODULE__, {:register, backend_module, opts})
  end

  @doc """
  Unregisters a storage backend by ID.

  Built-in backends cannot be unregistered.

  ## Examples

      iex> ExZarr.Storage.Registry.unregister(:my_backend)
      :ok

      iex> ExZarr.Storage.Registry.unregister(:filesystem)
      {:error, :cannot_unregister_builtin}

  ## Returns

  - `:ok` - Backend unregistered successfully
  - `{:error, :not_found}` - Backend not registered
  - `{:error, :cannot_unregister_builtin}` - Cannot unregister built-in backend
  """
  @spec unregister(backend_id()) :: :ok | {:error, term()}
  def unregister(backend_id) when is_atom(backend_id) do
    GenServer.call(__MODULE__, {:unregister, backend_id})
  end

  @doc """
  Gets a storage backend module by ID.

  ## Examples

      iex> ExZarr.Storage.Registry.get(:filesystem)
      {:ok, ExZarr.Storage.Backend.Filesystem}

      iex> ExZarr.Storage.Registry.get(:nonexistent)
      {:error, :not_found}

  ## Returns

  - `{:ok, module()}` - Backend found
  - `{:error, :not_found}` - Backend not registered
  """
  @spec get(backend_id()) :: {:ok, backend_module()} | {:error, :not_found}
  def get(backend_id) when is_atom(backend_id) do
    GenServer.call(__MODULE__, {:get, backend_id})
  end

  @doc """
  Lists all registered backend IDs.

  ## Examples

      iex> ExZarr.Storage.Registry.list()
      [:memory, :filesystem, :zip, :s3, :database]
  """
  @spec list() :: [backend_id()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Gets information about a storage backend.

  Returns backend metadata if the module provides a `backend_info/0` callback,
  otherwise returns basic information.

  ## Examples

      iex> ExZarr.Storage.Registry.info(:filesystem)
      {:ok, %{
        id: :filesystem,
        module: ExZarr.Storage.Backend.Filesystem,
        description: "Local filesystem storage"
      }}

  ## Returns

  - `{:ok, map()}` - Backend information
  - `{:error, :not_found}` - Backend not registered
  """
  @spec info(backend_id()) :: {:ok, map()} | {:error, :not_found}
  def info(backend_id) when is_atom(backend_id) do
    GenServer.call(__MODULE__, {:info, backend_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize with built-in backends
    built_in = %{
      memory: ExZarr.Storage.Backend.Memory,
      filesystem: ExZarr.Storage.Backend.Filesystem,
      zip: ExZarr.Storage.Backend.Zip
    }

    # Load custom backends from application config
    custom_backends =
      Application.get_env(:ex_zarr, :custom_storage_backends, [])
      |> Enum.reduce(%{}, fn module, acc ->
        if ExZarr.Storage.Backend.implements?(module) do
          backend_id = module.backend_id()
          Logger.info("Registering custom storage backend from config: #{inspect(backend_id)}")
          Map.put(acc, backend_id, module)
        else
          Logger.warning(
            "Module #{inspect(module)} does not implement Storage.Backend behavior, skipping"
          )

          acc
        end
      end)

    # Merge custom backends (they can override built-ins if explicitly configured)
    all_backends = Map.merge(built_in, custom_backends)

    Logger.debug("Storage backend registry initialized with #{map_size(all_backends)} backends")

    {:ok, %{backends: all_backends, built_in: Map.keys(built_in)}}
  end

  @impl true
  def handle_call({:register, backend_module, opts}, _from, state) do
    # Validate that module implements behavior
    if ExZarr.Storage.Backend.implements?(backend_module) do
      backend_id = backend_module.backend_id()
      force = Keyword.get(opts, :force, false)

      if Map.has_key?(state.backends, backend_id) and not force do
        {:reply, {:error, :already_registered}, state}
      else
        new_backends = Map.put(state.backends, backend_id, backend_module)

        Logger.debug(
          "Registered storage backend: #{inspect(backend_id)} -> #{inspect(backend_module)}"
        )

        {:reply, :ok, %{state | backends: new_backends}}
      end
    else
      {:reply, {:error, :invalid_backend}, state}
    end
  end

  @impl true
  def handle_call({:unregister, backend_id}, _from, state) do
    cond do
      backend_id in state.built_in ->
        {:reply, {:error, :cannot_unregister_builtin}, state}

      not Map.has_key?(state.backends, backend_id) ->
        {:reply, {:error, :not_found}, state}

      true ->
        new_backends = Map.delete(state.backends, backend_id)
        Logger.debug("Unregistered storage backend: #{inspect(backend_id)}")
        {:reply, :ok, %{state | backends: new_backends}}
    end
  end

  @impl true
  def handle_call({:get, backend_id}, _from, state) do
    case Map.fetch(state.backends, backend_id) do
      {:ok, module} -> {:reply, {:ok, module}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    backend_ids = Map.keys(state.backends) |> Enum.sort()
    {:reply, backend_ids, state}
  end

  @impl true
  def handle_call({:info, backend_id}, _from, state) do
    case Map.fetch(state.backends, backend_id) do
      {:ok, module} when is_atom(module) ->
        info = get_backend_info(module, backend_id, state.built_in)
        {:reply, {:ok, info}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  defp get_backend_info(module, backend_id, built_in) do
    if function_exported?(module, :backend_info, 0) do
      module.backend_info()
    else
      %{
        id: backend_id,
        module: module,
        description: get_backend_description(backend_id, built_in),
        type: if(backend_id in built_in, do: :built_in, else: :custom)
      }
    end
  end

  defp get_backend_description(backend_id, built_in) do
    cond do
      backend_id in built_in and backend_id == :memory ->
        "In-memory storage (non-persistent)"

      backend_id in built_in and backend_id == :filesystem ->
        "Local filesystem storage"

      backend_id in built_in and backend_id == :zip ->
        "Zip archive storage"

      true ->
        "Custom storage backend"
    end
  end
end
