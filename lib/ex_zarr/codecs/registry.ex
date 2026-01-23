defmodule ExZarr.Codecs.Registry do
  @moduledoc """
  Registry for managing built-in and custom codecs.

  The registry maintains a mapping of codec IDs to codec modules and provides
  functions for registering, querying, and using codecs.

  ## Overview

  The registry is started automatically as part of ExZarr's supervision tree
  and is initialized with all built-in codecs. Custom codecs can be registered
  at application startup (via configuration) or at runtime.

  ## Built-in Codecs

  The following codecs are registered by default:
  - `:none` - No compression (passthrough)
  - `:zlib` - Zlib compression
  - `:crc32c` - CRC32C checksum
  - `:zstd` - Zstandard compression (if available)
  - `:lz4` - LZ4 compression (if available)
  - `:snappy` - Snappy compression (if available)
  - `:blosc` - Blosc meta-compressor (if available)
  - `:bzip2` - Bzip2 compression (if available)

  ## Registering Custom Codecs

  ### Via Configuration

  Add to `config/config.exs`:

      config :ex_zarr, :custom_codecs, [
        MyApp.CustomCodec,
        MyApp.AnotherCodec
      ]

  ### Programmatically

      ExZarr.Codecs.Registry.register(MyApp.CustomCodec)

  ### At Application Start

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          # Register custom codecs
          ExZarr.Codecs.Registry.register(MyApp.CustomCodec)

          # ... rest of supervision tree
        end
      end

  ## Querying Codecs

      # Get a codec module
      {:ok, module} = ExZarr.Codecs.Registry.get(:zstd)

      # List all registered codec IDs
      ids = ExZarr.Codecs.Registry.list()

      # List only available codecs
      available = ExZarr.Codecs.Registry.available()

      # Get codec information
      {:ok, info} = ExZarr.Codecs.Registry.info(:zstd)
  """

  use GenServer
  require Logger

  alias Codec

  @type codec_module :: module()
  @type codec_id :: atom()
  @type registry_state :: %{
          codecs: %{codec_id() => codec_module()},
          opts: keyword()
        }

  ## Client API

  @doc """
  Starts the codec registry.

  This is typically called automatically by the application supervision tree.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a custom codec module.

  The module must implement the `Codec` behavior.

  ## Options

  - `:force` - If `true`, overwrites existing codec with same ID (default: `false`)

  ## Examples

      iex> ExZarr.Codecs.Registry.register(MyCustomCodec)
      :ok

      iex> ExZarr.Codecs.Registry.register(MyCodec, force: true)
      :ok

  ## Returns

  - `:ok` - Codec registered successfully
  - `{:error, :already_registered}` - Codec ID already in use (unless `force: true`)
  - `{:error, :invalid_codec}` - Module doesn't implement Codec behavior
  """
  @spec register(codec_module(), keyword()) :: :ok | {:error, term()}
  def register(codec_module, opts \\ []) when is_atom(codec_module) do
    GenServer.call(__MODULE__, {:register, codec_module, opts})
  end

  @doc """
  Unregisters a codec by ID.

  Built-in codecs cannot be unregistered.

  ## Examples

      iex> ExZarr.Codecs.Registry.unregister(:my_codec)
      :ok

      iex> ExZarr.Codecs.Registry.unregister(:zlib)
      {:error, :cannot_unregister_builtin}

  ## Returns

  - `:ok` - Codec unregistered successfully
  - `{:error, :not_found}` - Codec not registered
  - `{:error, :cannot_unregister_builtin}` - Cannot unregister built-in codec
  """
  @spec unregister(codec_id()) :: :ok | {:error, term()}
  def unregister(codec_id) when is_atom(codec_id) do
    GenServer.call(__MODULE__, {:unregister, codec_id})
  end

  @doc """
  Gets a codec module by ID.

  ## Examples

      iex> ExZarr.Codecs.Registry.get(:zstd)
      {:ok, ExZarr.Codecs.ZstdCodec}

      iex> ExZarr.Codecs.Registry.get(:nonexistent)
      {:error, :not_found}

  ## Returns

  - `{:ok, module()}` - Codec found
  - `{:error, :not_found}` - Codec not registered
  """
  @spec get(codec_id()) :: {:ok, codec_module()} | {:error, :not_found}
  def get(codec_id) when is_atom(codec_id) do
    GenServer.call(__MODULE__, {:get, codec_id})
  end

  @doc """
  Lists all registered codec IDs.

  Returns codec IDs regardless of whether they're currently available.

  ## Examples

      iex> ExZarr.Codecs.Registry.list()
      [:none, :zlib, :crc32c, :zstd, :lz4, :snappy, :blosc, :bzip2, :my_codec]
  """
  @spec list() :: [codec_id()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Lists only available codecs.

  A codec is available if it's registered and its `available?/0` callback
  returns `true`.

  ## Examples

      iex> ExZarr.Codecs.Registry.available()
      [:none, :zlib, :crc32c, :zstd, :lz4]
  """
  @spec available() :: [codec_id()]
  def available do
    GenServer.call(__MODULE__, :available)
  end

  @doc """
  Gets information about a codec.

  Returns the codec's metadata from its `codec_info/0` callback.

  ## Examples

      iex> ExZarr.Codecs.Registry.info(:zstd)
      {:ok, %{
        name: "Zstandard",
        version: "1.0.0",
        type: :compression,
        description: "Zstandard compression algorithm"
      }}

  ## Returns

  - `{:ok, map()}` - Codec information
  - `{:error, :not_found}` - Codec not registered
  """
  @spec info(codec_id()) :: {:ok, map()} | {:error, :not_found}
  def info(codec_id) when is_atom(codec_id) do
    GenServer.call(__MODULE__, {:info, codec_id})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Initialize with built-in codecs and filters
    # Note: These will be replaced with actual codec modules in phase 2
    built_in = %{
      # Compression codecs
      none: :builtin_none,
      zlib: :builtin_zlib,
      crc32c: :builtin_crc32c,
      zstd: :builtin_zstd,
      lz4: :builtin_lz4,
      snappy: :builtin_snappy,
      blosc: :builtin_blosc,
      bzip2: :builtin_bzip2,
      # Transformation filters
      delta: :builtin_delta,
      quantize: :builtin_quantize,
      shuffle: :builtin_shuffle,
      fixedscaleoffset: :builtin_fixedscaleoffset,
      astype: :builtin_astype,
      packbits: :builtin_packbits,
      categorize: :builtin_categorize,
      bitround: :builtin_bitround
    }

    # Load custom codecs from application config
    custom_codecs =
      Application.get_env(:ex_zarr, :custom_codecs, [])
      |> Enum.reduce(%{}, fn module, acc ->
        if ExZarr.Codecs.Codec.implements?(module) do
          codec_id = module.codec_id()
          Logger.info("Registering custom codec from config: #{inspect(codec_id)}")
          Map.put(acc, codec_id, module)
        else
          Logger.warning("Module #{inspect(module)} does not implement Codec behavior, skipping")
          acc
        end
      end)

    # Merge custom codecs (they can override built-ins if explicitly configured)
    all_codecs = Map.merge(built_in, custom_codecs)

    Logger.debug("Codec registry initialized with #{map_size(all_codecs)} codecs")

    {:ok, %{codecs: all_codecs, opts: opts, built_in: Map.keys(built_in)}}
  end

  @impl true
  def handle_call({:register, codec_module, opts}, _from, state) do
    # Validate that module implements behavior
    if ExZarr.Codecs.Codec.implements?(codec_module) do
      codec_id = codec_module.codec_id()
      force = Keyword.get(opts, :force, false)

      if Map.has_key?(state.codecs, codec_id) and not force do
        {:reply, {:error, :already_registered}, state}
      else
        new_codecs = Map.put(state.codecs, codec_id, codec_module)
        Logger.debug("Registered codec: #{inspect(codec_id)} -> #{inspect(codec_module)}")
        {:reply, :ok, %{state | codecs: new_codecs}}
      end
    else
      {:reply, {:error, :invalid_codec}, state}
    end
  end

  @impl true
  def handle_call({:unregister, codec_id}, _from, state) do
    cond do
      codec_id in state.built_in ->
        {:reply, {:error, :cannot_unregister_builtin}, state}

      not Map.has_key?(state.codecs, codec_id) ->
        {:reply, {:error, :not_found}, state}

      true ->
        new_codecs = Map.delete(state.codecs, codec_id)
        Logger.debug("Unregistered codec: #{inspect(codec_id)}")
        {:reply, :ok, %{state | codecs: new_codecs}}
    end
  end

  @impl true
  def handle_call({:get, codec_id}, _from, state) do
    case Map.fetch(state.codecs, codec_id) do
      {:ok, module} -> {:reply, {:ok, module}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    codec_ids = Map.keys(state.codecs) |> Enum.sort()
    {:reply, codec_ids, state}
  end

  @impl true
  def handle_call(:available, _from, state) do
    available_codecs =
      state.codecs
      |> Enum.filter(fn {_id, module} ->
        # Built-in codecs (atoms starting with :builtin_) are checked differently
        case module do
          :builtin_none ->
            true

          :builtin_zlib ->
            true

          :builtin_crc32c ->
            true

          atom
          when is_atom(atom) and
                 atom in [
                   :builtin_zstd,
                   :builtin_lz4,
                   :builtin_snappy,
                   :builtin_blosc,
                   :builtin_bzip2
                 ] ->
            # These will be checked through the old system until phase 2
            check_builtin_available(atom)

          _module ->
            # Custom codec - call its available? callback
            try do
              module.available?()
            rescue
              _ -> false
            end
        end
      end)
      |> Enum.map(fn {id, _module} -> id end)
      |> Enum.sort()

    {:reply, available_codecs, state}
  end

  @impl true
  def handle_call({:info, codec_id}, _from, state) do
    case Map.fetch(state.codecs, codec_id) do
      {:ok, module}
      when is_atom(module) and
             module in [
               :builtin_none,
               :builtin_zlib,
               :builtin_crc32c,
               :builtin_zstd,
               :builtin_lz4,
               :builtin_snappy,
               :builtin_blosc,
               :builtin_bzip2
             ] ->
        # Built-in codec info
        info = get_builtin_info(module)
        {:reply, {:ok, info}, state}

      {:ok, module} ->
        # Custom codec - call its codec_info callback
        try do
          info = module.codec_info()
          {:reply, {:ok, info}, state}
        rescue
          e ->
            {:reply, {:error, {:info_failed, e}}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  ## Private Helpers

  # Temporary helper for checking built-in codec availability (Phase 1)
  defp check_builtin_available(:builtin_zstd) do
    function_exported?(ExZarr.Codecs.ZigCodecs, :zstd_compress, 2)
  end

  defp check_builtin_available(:builtin_lz4) do
    function_exported?(ExZarr.Codecs.ZigCodecs, :lz4_compress, 1)
  end

  defp check_builtin_available(:builtin_snappy) do
    function_exported?(ExZarr.Codecs.ZigCodecs, :snappy_compress, 1)
  end

  defp check_builtin_available(:builtin_blosc) do
    function_exported?(ExZarr.Codecs.ZigCodecs, :blosc_compress, 2)
  end

  defp check_builtin_available(:builtin_bzip2) do
    function_exported?(ExZarr.Codecs.ZigCodecs, :bzip2_compress, 2)
  end

  defp check_builtin_available(_), do: false

  # Temporary helper for built-in codec info (Phase 1)
  defp get_builtin_info(:builtin_none) do
    %{
      name: "None (Passthrough)",
      version: "1.0.0",
      type: :compression,
      description: "No compression - data passthrough"
    }
  end

  defp get_builtin_info(:builtin_zlib) do
    %{
      name: "Zlib",
      version: "1.0.0",
      type: :compression,
      description: "Zlib compression via Erlang's :zlib module"
    }
  end

  defp get_builtin_info(:builtin_crc32c) do
    %{
      name: "CRC32C",
      version: "1.0.0",
      type: :checksum,
      description: "RFC 3720 CRC32C checksum codec"
    }
  end

  defp get_builtin_info(:builtin_zstd) do
    %{
      name: "Zstandard",
      version: "1.0.0",
      type: :compression,
      description: "Zstandard compression via Zig NIF"
    }
  end

  defp get_builtin_info(:builtin_lz4) do
    %{
      name: "LZ4",
      version: "1.0.0",
      type: :compression,
      description: "LZ4 compression via Zig NIF"
    }
  end

  defp get_builtin_info(:builtin_snappy) do
    %{
      name: "Snappy",
      version: "1.0.0",
      type: :compression,
      description: "Snappy compression via Zig NIF"
    }
  end

  defp get_builtin_info(:builtin_blosc) do
    %{
      name: "Blosc",
      version: "1.0.0",
      type: :compression,
      description: "Blosc meta-compressor via Zig NIF"
    }
  end

  defp get_builtin_info(:builtin_bzip2) do
    %{
      name: "Bzip2",
      version: "1.0.0",
      type: :compression,
      description: "Bzip2 compression via Zig NIF"
    }
  end

  defp get_builtin_info(_),
    do: %{name: "Unknown", version: "0.0.0", type: :unknown, description: "Unknown codec"}
end
