defmodule ExZarr.Storage do
  @moduledoc """
  Storage backend abstraction for Zarr arrays.

  Provides a unified interface for storing and retrieving Zarr array data
  across different storage backends. Each backend handles chunks and metadata
  according to the Zarr v2 specification.

  ## Available Backends

  - **`:memory`** - In-memory storage using Elixir maps. Fast but non-persistent.
    Suitable for temporary arrays and testing.

  - **`:filesystem`** - Local filesystem storage using the Zarr v2 directory
    structure. Chunks are stored as individual files with dot notation (e.g., `0.0`).
    Metadata is stored in `.zarray` JSON files.

  ## Zarr Directory Structure

  For filesystem storage, arrays follow this structure:

      /path/to/array/
        .zarray          # JSON metadata file
        0.0              # Chunk at index (0, 0)
        0.1              # Chunk at index (0, 1)
        1.0              # Chunk at index (1, 0)
        ...

  ## Examples

      # Initialize memory storage
      {:ok, storage} = ExZarr.Storage.init(%{storage_type: :memory})

      # Initialize filesystem storage
      {:ok, storage} = ExZarr.Storage.init(%{
        storage_type: :filesystem,
        path: "/tmp/my_array"
      })

      # Write and read chunks
      :ok = ExZarr.Storage.write_chunk(storage, {0, 0}, data)
      {:ok, data} = ExZarr.Storage.read_chunk(storage, {0, 0})

      # Write and read metadata
      :ok = ExZarr.Storage.write_metadata(storage, metadata, [])
      {:ok, metadata} = ExZarr.Storage.read_metadata(storage)
  """

  @type backend :: :memory | :filesystem | :s3
  @type t :: %__MODULE__{
          backend: backend(),
          path: String.t() | nil,
          state: map()
        }

  defstruct [:backend, :path, state: %{}]

  @doc """
  Initializes a new storage backend.

  Creates a new storage instance for the specified backend type. For filesystem
  storage, creates the directory if it doesn't exist.

  ## Parameters

  - `config` - Map with `:storage_type` and optional `:path`

  ## Examples

      # Memory storage
      {:ok, storage} = ExZarr.Storage.init(%{storage_type: :memory})

      # Filesystem storage
      {:ok, storage} = ExZarr.Storage.init(%{
        storage_type: :filesystem,
        path: "/tmp/my_array"
      })

  ## Returns

  - `{:ok, storage}` on success
  - `{:error, :path_required}` if filesystem storage without path
  - `{:error, :invalid_storage_config}` for unsupported backends
  - `{:error, {:mkdir_failed, reason}}` if directory creation fails
  """
  @spec init(map()) :: {:ok, t()} | {:error, term()}
  def init(%{storage_type: :memory} = _config) do
    # Use Agent for mutable state
    {:ok, agent} = Agent.start_link(fn -> %{chunks: %{}, metadata: nil} end)

    {:ok,
     %__MODULE__{
       backend: :memory,
       state: %{agent: agent}
     }}
  end

  def init(%{storage_type: :filesystem, path: path} = _config) when is_binary(path) do
    with :ok <- ensure_directory(path) do
      {:ok,
       %__MODULE__{
         backend: :filesystem,
         path: path,
         state: %{}
       }}
    end
  end

  def init(%{storage_type: :filesystem}) do
    {:error, :path_required}
  end

  def init(_), do: {:error, :invalid_storage_config}

  @doc """
  Opens an existing storage backend.

  Opens a previously created storage location, typically for loading an
  existing array. The storage must already exist (use `init/1` to create new
  storage).

  ## Options

  - `:path` - Path to the storage directory (required for filesystem)
  - `:storage` - Backend type (default: `:filesystem`)

  ## Examples

      # Open filesystem storage
      {:ok, storage} = ExZarr.Storage.open(path: "/tmp/my_array")

      # Open with explicit backend
      {:ok, storage} = ExZarr.Storage.open(
        path: "/tmp/my_array",
        storage: :filesystem
      )

  ## Returns

  - `{:ok, storage}` on success
  - `{:error, :path_not_found}` if path does not exist
  - `{:error, :cannot_open_memory_storage}` for memory backend
  - `{:error, :invalid_storage_backend}` for unsupported backends
  """
  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts) do
    path = Keyword.get(opts, :path)
    backend = Keyword.get(opts, :storage, :filesystem)

    case backend do
      :filesystem when is_binary(path) ->
        if File.exists?(path) do
          {:ok, %__MODULE__{backend: :filesystem, path: path, state: %{}}}
        else
          {:error, :path_not_found}
        end

      :memory ->
        {:error, :cannot_open_memory_storage}

      _ ->
        {:error, :invalid_storage_backend}
    end
  end

  @doc """
  Reads a chunk from storage.

  Retrieves compressed chunk data from storage. The chunk must have been
  previously written.

  ## Parameters

  - `storage` - Storage instance
  - `chunk_index` - Tuple identifying the chunk (e.g., `{0, 0}`)

  ## Examples

      {:ok, data} = ExZarr.Storage.read_chunk(storage, {0, 0})
      {:error, :not_found} = ExZarr.Storage.read_chunk(storage, {99, 99})

  ## Returns

  - `{:ok, binary}` with compressed chunk data
  - `{:error, :not_found}` if chunk doesn't exist
  - `{:error, reason}` for other failures
  """
  @spec read_chunk(t(), tuple()) :: {:ok, binary()} | {:error, term()}
  def read_chunk(%__MODULE__{backend: :memory, state: %{agent: agent}}, chunk_index) do
    Agent.get(agent, fn state ->
      case Map.get(state.chunks, chunk_index) do
        nil -> {:error, :not_found}
        data -> {:ok, data}
      end
    end)
  end

  def read_chunk(%__MODULE__{backend: :filesystem, path: path}, chunk_index) do
    chunk_path = build_chunk_path(path, chunk_index)

    case File.read(chunk_path) do
      {:ok, data} -> {:ok, data}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes a chunk to storage.

  Stores compressed chunk data in the storage backend. For filesystem storage,
  creates a file using dot notation (e.g., `0.0` for chunk `{0, 0}`). For
  memory storage, returns an updated storage struct.

  ## Parameters

  - `storage` - Storage instance
  - `chunk_index` - Tuple identifying the chunk
  - `data` - Binary data to write (typically compressed)

  ## Examples

      # Filesystem storage
      :ok = ExZarr.Storage.write_chunk(storage, {0, 0}, compressed_data)

      # Memory storage (returns updated storage)
      {:ok, new_storage} = ExZarr.Storage.write_chunk(storage, {0, 0}, data)

  ## Returns

  - `:ok` for filesystem storage
  - `{:ok, updated_storage}` for memory storage
  - `{:error, reason}` on failure
  """
  @spec write_chunk(t(), tuple(), binary()) :: :ok | {:error, term()}
  def write_chunk(%__MODULE__{backend: :memory, state: %{agent: agent}}, chunk_index, data) do
    Agent.update(agent, fn state ->
      new_chunks = Map.put(state.chunks, chunk_index, data)
      %{state | chunks: new_chunks}
    end)

    :ok
  end

  def write_chunk(%__MODULE__{backend: :filesystem, path: path}, chunk_index, data) do
    chunk_path = build_chunk_path(path, chunk_index)
    chunk_dir = Path.dirname(chunk_path)

    with :ok <- ensure_directory(chunk_dir) do
      File.write(chunk_path, data)
    end
  end

  @doc """
  Reads metadata from storage.

  Loads the `.zarray` metadata file for a Zarr array. For filesystem storage,
  reads and parses the JSON file. Converts JSON data types back to internal
  format (e.g., `"<f8"` to `:float64`).

  ## Examples

      {:ok, metadata} = ExZarr.Storage.read_metadata(storage)
      metadata.shape    # => {1000, 1000}
      metadata.dtype    # => :float64
      metadata.compressor  # => :zlib

  ## Returns

  - `{:ok, metadata}` with parsed Metadata struct
  - `{:error, :metadata_not_found}` if .zarray file doesn't exist
  - `{:error, reason}` for other failures
  """
  @spec read_metadata(t()) :: {:ok, map()} | {:error, term()}
  def read_metadata(%__MODULE__{backend: :memory, state: %{agent: agent}}) do
    Agent.get(agent, fn state ->
      case Map.get(state, :metadata) do
        nil -> {:error, :metadata_not_found}
        metadata -> {:ok, metadata}
      end
    end)
  end

  def read_metadata(%__MODULE__{backend: :filesystem, path: path}) do
    metadata_path = Path.join(path, ".zarray")

    with {:ok, json} <- File.read(metadata_path),
         {:ok, metadata} <- Jason.decode(json, keys: :atoms) do
      # Convert JSON structure to internal metadata format
      parsed_metadata = %ExZarr.Metadata{
        shape: List.to_tuple(metadata.shape),
        chunks: List.to_tuple(metadata.chunks),
        dtype: string_to_dtype(metadata.dtype),
        compressor: parse_compressor(metadata.compressor),
        fill_value: metadata.fill_value,
        order: Map.get(metadata, :order, "C"),
        zarr_format: metadata.zarr_format,
        filters: parse_filters(Map.get(metadata, :filters))
      }

      {:ok, parsed_metadata}
    else
      {:error, :enoent} -> {:error, :metadata_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes metadata to storage.

  Saves array metadata to a `.zarray` JSON file following the Zarr v2
  specification. Converts internal data types to JSON format (e.g.,
  `:float64` to `"<f8"`).

  ## Parameters

  - `storage` - Storage instance
  - `metadata` - Metadata struct to write
  - `opts` - Options (currently unused)

  ## Examples

      metadata = %ExZarr.Metadata{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0,
        order: "C",
        zarr_format: 2
      }
      :ok = ExZarr.Storage.write_metadata(storage, metadata, [])

  ## Returns

  - `:ok` for filesystem storage
  - `{:ok, updated_storage}` for memory storage
  - `{:error, reason}` on failure
  """
  @spec write_metadata(t(), ExZarr.Metadata.t(), keyword()) :: :ok | {:error, term()}
  def write_metadata(%__MODULE__{backend: :memory, state: %{agent: agent}}, metadata, _opts) do
    Agent.update(agent, fn state ->
      %{state | metadata: metadata}
    end)

    :ok
  end

  def write_metadata(%__MODULE__{backend: :filesystem, path: path}, metadata, _opts) do
    metadata_path = Path.join(path, ".zarray")

    metadata_json = %{
      zarr_format: 2,
      shape: Tuple.to_list(metadata.shape),
      chunks: Tuple.to_list(metadata.chunks),
      dtype: dtype_to_string(metadata.dtype),
      compressor: compressor_to_json(metadata.compressor),
      fill_value: metadata.fill_value,
      order: metadata.order,
      filters: encode_filters(metadata.filters)
    }

    with {:ok, json} <- Jason.encode(metadata_json, pretty: true) do
      File.write(metadata_path, json)
    end
  end

  @doc """
  Lists all chunk keys in the storage.

  Returns a list of all chunk indices that have been written to storage.
  For filesystem storage, reads the directory and parses chunk filenames.
  For memory storage, returns the keys from the chunks map.

  ## Examples

      {:ok, chunks} = ExZarr.Storage.list_chunks(storage)
      # => [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

  ## Returns

  - `{:ok, [chunk_indices]}` with list of chunk index tuples
  - `{:error, reason}` on failure

  ## Note

  The order of chunks in the returned list is not guaranteed.
  """
  @spec list_chunks(t()) :: {:ok, [tuple()]} | {:error, term()}
  def list_chunks(%__MODULE__{backend: :memory, state: %{agent: agent}}) do
    Agent.get(agent, fn state ->
      {:ok, Map.keys(state.chunks)}
    end)
  end

  def list_chunks(%__MODULE__{backend: :filesystem, path: path}) do
    case File.ls(path) do
      {:ok, files} ->
        chunks =
          files
          |> Enum.filter(&String.contains?(&1, "."))
          |> Enum.map(&parse_chunk_filename/1)
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Functions

  defp ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp build_chunk_path(base_path, chunk_index) do
    # Zarr uses dot-separated notation for chunk indices: 0.0, 0.1, etc.
    chunk_name =
      chunk_index
      |> Tuple.to_list()
      |> Enum.join(".")

    Path.join(base_path, chunk_name)
  end

  defp parse_chunk_filename(filename) do
    case String.split(filename, ".") do
      parts when length(parts) > 1 ->
        parts
        |> Enum.map(&String.to_integer/1)
        |> List.to_tuple()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp parse_compressor(nil), do: :none
  defp parse_compressor(%{id: id}), do: String.to_atom(id)
  defp parse_compressor(_), do: :none

  defp compressor_to_json(:none), do: nil

  defp compressor_to_json(compressor) when is_atom(compressor) do
    %{
      id: Atom.to_string(compressor),
      level: 5
    }
  end

  # Little-endian (< prefix)
  defp string_to_dtype("<i1"), do: :int8
  defp string_to_dtype("<i2"), do: :int16
  defp string_to_dtype("<i4"), do: :int32
  defp string_to_dtype("<i8"), do: :int64
  defp string_to_dtype("<u1"), do: :uint8
  defp string_to_dtype("<u2"), do: :uint16
  defp string_to_dtype("<u4"), do: :uint32
  defp string_to_dtype("<u8"), do: :uint64
  defp string_to_dtype("<f4"), do: :float32
  defp string_to_dtype("<f8"), do: :float64
  # Big-endian (> prefix)
  defp string_to_dtype(">i1"), do: :int8
  defp string_to_dtype(">i2"), do: :int16
  defp string_to_dtype(">i4"), do: :int32
  defp string_to_dtype(">i8"), do: :int64
  defp string_to_dtype(">u1"), do: :uint8
  defp string_to_dtype(">u2"), do: :uint16
  defp string_to_dtype(">u4"), do: :uint32
  defp string_to_dtype(">u8"), do: :uint64
  defp string_to_dtype(">f4"), do: :float32
  defp string_to_dtype(">f8"), do: :float64
  # Native/platform byte order (| prefix)
  defp string_to_dtype("|i1"), do: :int8
  defp string_to_dtype("|i2"), do: :int16
  defp string_to_dtype("|i4"), do: :int32
  defp string_to_dtype("|i8"), do: :int64
  defp string_to_dtype("|u1"), do: :uint8
  defp string_to_dtype("|u2"), do: :uint16
  defp string_to_dtype("|u4"), do: :uint32
  defp string_to_dtype("|u8"), do: :uint64
  defp string_to_dtype("|f4"), do: :float32
  defp string_to_dtype("|f8"), do: :float64
  # Fallback for unknown formats
  defp string_to_dtype(dtype_str), do: String.to_atom(dtype_str)

  defp dtype_to_string(:int8), do: "<i1"
  defp dtype_to_string(:int16), do: "<i2"
  defp dtype_to_string(:int32), do: "<i4"
  defp dtype_to_string(:int64), do: "<i8"
  defp dtype_to_string(:uint8), do: "<u1"
  defp dtype_to_string(:uint16), do: "<u2"
  defp dtype_to_string(:uint32), do: "<u4"
  defp dtype_to_string(:uint64), do: "<u8"
  defp dtype_to_string(:float32), do: "<f4"
  defp dtype_to_string(:float64), do: "<f8"

  # Filter serialization helpers

  defp encode_filters(nil), do: nil
  defp encode_filters([]), do: nil

  defp encode_filters(filters) when is_list(filters) do
    Enum.map(filters, fn {filter_id, opts} ->
      case ExZarr.Codecs.Registry.get(filter_id) do
        {:ok, :builtin_delta} -> encode_builtin_filter(:delta, opts)
        {:ok, :builtin_quantize} -> encode_builtin_filter(:quantize, opts)
        {:ok, :builtin_shuffle} -> encode_builtin_filter(:shuffle, opts)
        {:ok, :builtin_fixedscaleoffset} -> encode_builtin_filter(:fixedscaleoffset, opts)
        {:ok, :builtin_astype} -> encode_builtin_filter(:astype, opts)
        {:ok, :builtin_packbits} -> encode_builtin_filter(:packbits, opts)
        {:ok, :builtin_categorize} -> encode_builtin_filter(:categorize, opts)
        {:ok, :builtin_bitround} -> encode_builtin_filter(:bitround, opts)
        {:ok, module} when is_atom(module) ->
          # Custom filter - ask module to encode
          module.to_json_config(opts)

        {:error, :not_found} ->
          # Shouldn't happen (validated in metadata), but handle gracefully
          %{"id" => Atom.to_string(filter_id)}
      end
    end)
  end

  defp encode_builtin_filter(:delta, opts) do
    %{
      "id" => "delta",
      "dtype" => dtype_to_string(opts[:dtype]),
      "astype" => dtype_to_string(opts[:astype] || opts[:dtype])
    }
  end

  defp encode_builtin_filter(:quantize, opts) do
    %{
      "id" => "quantize",
      "digits" => opts[:digits],
      "dtype" => dtype_to_string(opts[:dtype])
    }
  end

  defp encode_builtin_filter(:shuffle, opts) do
    %{
      "id" => "shuffle",
      "elementsize" => opts[:elementsize] || 4
    }
  end

  defp encode_builtin_filter(:fixedscaleoffset, opts) do
    %{
      "id" => "fixedscaleoffset",
      "offset" => opts[:offset],
      "scale" => opts[:scale],
      "dtype" => dtype_to_string(opts[:dtype]),
      "astype" => dtype_to_string(opts[:astype] || opts[:dtype])
    }
  end

  defp encode_builtin_filter(:astype, opts) do
    %{
      "id" => "astype",
      "encode_dtype" => dtype_to_string(opts[:encode_dtype]),
      "decode_dtype" => dtype_to_string(opts[:decode_dtype])
    }
  end

  defp encode_builtin_filter(:packbits, _opts) do
    %{"id" => "packbits"}
  end

  defp encode_builtin_filter(:categorize, opts) do
    %{
      "id" => "categorize",
      "dtype" => dtype_to_string(opts[:dtype])
    }
  end

  defp encode_builtin_filter(:bitround, opts) do
    %{
      "id" => "bitround",
      "keepbits" => opts[:keepbits]
    }
  end

  defp parse_filters(nil), do: nil
  defp parse_filters([]), do: nil

  defp parse_filters(filters) when is_list(filters) do
    filters
    |> Enum.map(fn filter_config ->
      filter_id = String.to_atom(filter_config[:id] || filter_config["id"])

      case ExZarr.Codecs.Registry.get(filter_id) do
        {:ok, :builtin_delta} ->
          {filter_id, parse_builtin_filter(:delta, filter_config)}

        {:ok, :builtin_quantize} ->
          {filter_id, parse_builtin_filter(:quantize, filter_config)}

        {:ok, :builtin_shuffle} ->
          {filter_id, parse_builtin_filter(:shuffle, filter_config)}

        {:ok, :builtin_fixedscaleoffset} ->
          {filter_id, parse_builtin_filter(:fixedscaleoffset, filter_config)}

        {:ok, :builtin_astype} ->
          {filter_id, parse_builtin_filter(:astype, filter_config)}

        {:ok, :builtin_packbits} ->
          {filter_id, parse_builtin_filter(:packbits, filter_config)}

        {:ok, :builtin_categorize} ->
          {filter_id, parse_builtin_filter(:categorize, filter_config)}

        {:ok, :builtin_bitround} ->
          {filter_id, parse_builtin_filter(:bitround, filter_config)}

        {:ok, module} when is_atom(module) ->
          # Custom filter
          opts = module.from_json_config(filter_config)
          {filter_id, opts}

        {:error, :not_found} ->
          # Unknown filter - log warning but allow reading
          require Logger
          Logger.warning("Unknown filter: #{filter_id}")
          {filter_id, []}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_builtin_filter(:delta, config) do
    [
      dtype: string_to_dtype(config[:dtype] || config["dtype"]),
      astype: string_to_dtype(config[:astype] || config["astype"])
    ]
  end

  defp parse_builtin_filter(:quantize, config) do
    [
      digits: config[:digits] || config["digits"],
      dtype: string_to_dtype(config[:dtype] || config["dtype"])
    ]
  end

  defp parse_builtin_filter(:shuffle, config) do
    [
      elementsize: config[:elementsize] || config["elementsize"] || 4
    ]
  end

  defp parse_builtin_filter(:fixedscaleoffset, config) do
    [
      offset: config[:offset] || config["offset"],
      scale: config[:scale] || config["scale"],
      dtype: string_to_dtype(config[:dtype] || config["dtype"]),
      astype: string_to_dtype(config[:astype] || config["astype"])
    ]
  end

  defp parse_builtin_filter(:astype, config) do
    [
      encode_dtype: string_to_dtype(config[:encode_dtype] || config["encode_dtype"]),
      decode_dtype: string_to_dtype(config[:decode_dtype] || config["decode_dtype"])
    ]
  end

  defp parse_builtin_filter(:packbits, _config) do
    []
  end

  defp parse_builtin_filter(:categorize, config) do
    [
      dtype: string_to_dtype(config[:dtype] || config["dtype"])
    ]
  end

  defp parse_builtin_filter(:bitround, config) do
    [
      keepbits: config[:keepbits] || config["keepbits"]
    ]
  end
end
