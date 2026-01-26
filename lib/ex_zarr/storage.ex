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

  - **`:zip`** - Zip archive storage. All chunks and metadata are stored in a single
    zip file. Useful for archiving, distribution, and reducing file count. Uses Erlang's
    built-in `:zip` module.

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

  @type backend :: :memory | :filesystem | :zip | :http | :s3
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
  def init(%{storage_type: backend_id} = config) when is_atom(backend_id) do
    # Look up backend module from registry
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        # Convert config map to keyword list for backend
        backend_config =
          config
          |> Map.delete(:storage_type)
          |> Enum.to_list()

        # Initialize backend
        case backend_module.init(backend_config) do
          {:ok, backend_state} ->
            {:ok,
             %__MODULE__{
               backend: backend_id,
               path: Map.get(config, :path),
               state: backend_state
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        # Map to invalid_storage_config for backward compatibility
        {:error, :invalid_storage_config}
    end
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
    backend_id = Keyword.get(opts, :storage, :filesystem)

    # Look up backend module from registry
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        # Open backend
        case backend_module.open(opts) do
          {:ok, backend_state} ->
            {:ok,
             %__MODULE__{
               backend: backend_id,
               path: Keyword.get(opts, :path),
               state: backend_state
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
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
  def read_chunk(%__MODULE__{backend: backend_id, state: backend_state}, chunk_index) do
    # Look up backend module and delegate
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        backend_module.read_chunk(backend_state, chunk_index)

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
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
  def write_chunk(%__MODULE__{backend: backend_id, state: backend_state}, chunk_index, data) do
    # Look up backend module and delegate
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        backend_module.write_chunk(backend_state, chunk_index, data)

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
    end
  end

  @doc """
  Deletes a chunk from storage.

  Removes a chunk from the storage backend. This is used when resizing arrays
  to shrink dimensions.

  ## Parameters

  - `storage` - Storage instance
  - `chunk_index` - Tuple identifying the chunk to delete

  ## Examples

      # Delete a specific chunk
      :ok = ExZarr.Storage.delete_chunk(storage, {0, 0})

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec delete_chunk(t(), tuple()) :: :ok | {:error, term()}
  def delete_chunk(%__MODULE__{backend: backend_id, state: backend_state}, chunk_index) do
    # Look up backend module and delegate
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        backend_module.delete_chunk(backend_state, chunk_index)

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
    end
  end

  @doc """
  Reads metadata from storage.

  Loads array metadata from storage. Automatically detects Zarr format version
  (v2 or v3) and returns the appropriate metadata struct:
  - v2: Loads `.zarray` file, returns `ExZarr.Metadata` struct
  - v3: Loads `zarr.json` file, returns `ExZarr.MetadataV3` struct

  Converts JSON data types back to internal format (e.g., `"<f8"` to `:float64`
  for v2, or `"float64"` to `:float64` for v3).

  ## Examples

      # Reading v2 array
      {:ok, metadata} = ExZarr.Storage.read_metadata(storage)
      metadata.shape    # => {1000, 1000}
      metadata.dtype    # => :float64
      metadata.compressor  # => :zlib

      # Reading v3 array
      {:ok, metadata} = ExZarr.Storage.read_metadata(storage)
      metadata.shape    # => {1000, 1000}
      metadata.data_type  # => "float64"
      metadata.codecs   # => [%{name: "bytes"}, %{name: "gzip"}]

  ## Returns

  - `{:ok, metadata}` with parsed Metadata struct (v2) or MetadataV3 struct (v3)
  - `{:error, :metadata_not_found}` if metadata file doesn't exist
  - `{:error, reason}` for other failures
  """
  @spec read_metadata(t()) ::
          {:ok, ExZarr.Metadata.t() | ExZarr.MetadataV3.t()} | {:error, term()}
  def read_metadata(%__MODULE__{backend: backend_id, state: backend_state}) do
    # Look up backend module and delegate
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        case backend_module.read_metadata(backend_state) do
          {:ok, json} when is_binary(json) ->
            # Parse JSON to Metadata struct
            parse_metadata_json(json)

          {:ok, metadata} ->
            # Already parsed (e.g., memory backend might store parsed metadata)
            {:ok, metadata}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
    end
  end

  # Parse JSON metadata into Metadata struct (with version detection)
  defp parse_metadata_json(json) when is_binary(json) do
    case Jason.decode(json, keys: :atoms) do
      {:ok, metadata} ->
        # Detect version and route to appropriate parser
        case ExZarr.Version.detect_version(metadata) do
          {:ok, 2} -> parse_metadata_v2(metadata)
          {:ok, 3} -> parse_metadata_v3(metadata)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parse v2 metadata
  defp parse_metadata_v2(metadata) do
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
  end

  # Parse v3 metadata
  defp parse_metadata_v3(metadata) do
    parsed_metadata = %ExZarr.MetadataV3{
      zarr_format: 3,
      node_type: String.to_atom(Map.get(metadata, :node_type, "array")),
      shape: if(metadata[:shape], do: List.to_tuple(metadata.shape), else: nil),
      data_type: Map.get(metadata, :data_type),
      chunk_grid: Map.get(metadata, :chunk_grid),
      chunk_key_encoding: Map.get(metadata, :chunk_key_encoding),
      codecs: parse_codecs_v3(Map.get(metadata, :codecs, [])),
      fill_value: Map.get(metadata, :fill_value),
      attributes: Map.get(metadata, :attributes, %{}),
      dimension_names: Map.get(metadata, :dimension_names)
    }

    {:ok, parsed_metadata}
  end

  # Parse v3 codec specifications
  defp parse_codecs_v3(codecs) when is_list(codecs) do
    Enum.map(codecs, fn codec ->
      %{
        name: Map.get(codec, :name),
        configuration: Map.get(codec, :configuration, %{})
      }
    end)
  end

  defp parse_codecs_v3(_), do: []

  @doc """
  Writes metadata to storage.

  Saves array metadata to storage. Automatically handles both Zarr v2 and v3 formats:
  - v2: Saves to `.zarray` file, converts `:float64` to `"<f8"` format
  - v3: Saves to `zarr.json` file, converts `:float64` to `"float64"` format

  ## Parameters

  - `storage` - Storage instance
  - `metadata` - Metadata struct (v2) or MetadataV3 struct (v3) to write
  - `opts` - Options (currently unused)

  ## Examples

      # Write v2 metadata
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

      # Write v3 metadata
      metadata = %ExZarr.MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {1000, 1000},
        data_type: "float64",
        chunk_grid: %{name: "regular", configuration: %{chunk_shape: {100, 100}}},
        chunk_key_encoding: %{name: "default"},
        codecs: [%{name: "bytes"}, %{name: "gzip", configuration: %{level: 5}}],
        fill_value: 0.0,
        attributes: %{}
      }
      :ok = ExZarr.Storage.write_metadata(storage, metadata, [])

  ## Returns

  - `:ok` for filesystem storage
  - `{:ok, updated_storage}` for memory storage
  - `{:error, reason}` on failure
  """
  @spec write_metadata(t(), ExZarr.Metadata.t() | ExZarr.MetadataV3.t(), keyword()) ::
          :ok | {:error, term()}
  def write_metadata(%__MODULE__{backend: backend_id, state: backend_state}, metadata, opts) do
    # Look up backend module and delegate
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        # Convert Metadata struct to JSON (version-aware)
        metadata_json =
          case metadata do
            %ExZarr.Metadata{} -> encode_metadata_v2(metadata)
            %ExZarr.MetadataV3{} -> encode_metadata_v3(metadata)
          end

        with {:ok, json} <- Jason.encode(metadata_json, pretty: true) do
          backend_module.write_metadata(backend_state, json, opts)
        end

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
    end
  end

  # Encode v2 metadata to JSON map
  defp encode_metadata_v2(metadata) do
    %{
      zarr_format: 2,
      shape: Tuple.to_list(metadata.shape),
      chunks: Tuple.to_list(metadata.chunks),
      dtype: dtype_to_string(metadata.dtype),
      compressor: compressor_to_json(metadata.compressor),
      fill_value: metadata.fill_value,
      order: metadata.order,
      filters: encode_filters(metadata.filters)
    }
  end

  # Encode v3 metadata to JSON map
  defp encode_metadata_v3(metadata) do
    base = %{
      zarr_format: 3,
      node_type: Atom.to_string(metadata.node_type),
      attributes: metadata.attributes || %{}
    }

    # Add array-specific fields if this is an array
    if metadata.node_type == :array do
      Map.merge(base, %{
        shape: Tuple.to_list(metadata.shape),
        data_type: metadata.data_type,
        chunk_grid: encode_chunk_grid(metadata.chunk_grid),
        chunk_key_encoding: metadata.chunk_key_encoding || %{name: "default"},
        codecs: encode_codecs_v3(metadata.codecs),
        fill_value: metadata.fill_value,
        dimension_names: metadata.dimension_names
      })
    else
      base
    end
  end

  # Convert chunk_grid to JSON-compatible format (tuples to lists)
  defp encode_chunk_grid(%{name: name, configuration: %{chunk_shape: chunk_shape} = config}) do
    %{
      name: name,
      configuration: Map.put(config, :chunk_shape, Tuple.to_list(chunk_shape))
    }
  end

  defp encode_chunk_grid(chunk_grid), do: chunk_grid

  # Encode v3 codec specifications to JSON format
  defp encode_codecs_v3(codecs) when is_list(codecs) do
    Enum.map(codecs, fn codec ->
      # zarr-python 3.x requires 'configuration' key to always be present
      config = Map.get(codec, :configuration, %{})
      %{name: codec.name, configuration: config}
    end)
  end

  defp encode_codecs_v3(_), do: []

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
  def list_chunks(%__MODULE__{backend: backend_id, state: backend_state}) do
    # Look up backend module and delegate
    case ExZarr.Storage.Registry.get(backend_id) do
      {:ok, backend_module} ->
        backend_module.list_chunks(backend_state)

      {:error, :not_found} ->
        {:error, {:unknown_backend, backend_id}}
    end
  end

  ## Private Functions

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
  defp string_to_dtype("<c8"), do: :complex64
  defp string_to_dtype("<c16"), do: :complex128
  defp string_to_dtype("<M8"), do: :datetime64
  defp string_to_dtype("<m8"), do: :timedelta64
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
  defp string_to_dtype(">c8"), do: :complex64
  defp string_to_dtype(">c16"), do: :complex128
  defp string_to_dtype(">M8"), do: :datetime64
  defp string_to_dtype(">m8"), do: :timedelta64
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
  defp string_to_dtype("|b1"), do: :bool
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
  defp dtype_to_string(:bool), do: "|b1"
  defp dtype_to_string(:complex64), do: "<c8"
  defp dtype_to_string(:complex128), do: "<c16"
  defp dtype_to_string(:datetime64), do: "<M8"
  defp dtype_to_string(:timedelta64), do: "<m8"

  # Filter serialization helpers

  defp encode_filters(nil), do: nil
  defp encode_filters([]), do: nil

  defp encode_filters(filters) when is_list(filters) do
    Enum.map(filters, fn {filter_id, opts} ->
      case ExZarr.Codecs.Registry.get(filter_id) do
        {:ok, :builtin_delta} ->
          encode_builtin_filter(:delta, opts)

        {:ok, :builtin_quantize} ->
          encode_builtin_filter(:quantize, opts)

        {:ok, :builtin_shuffle} ->
          encode_builtin_filter(:shuffle, opts)

        {:ok, :builtin_fixedscaleoffset} ->
          encode_builtin_filter(:fixedscaleoffset, opts)

        {:ok, :builtin_astype} ->
          encode_builtin_filter(:astype, opts)

        {:ok, :builtin_packbits} ->
          encode_builtin_filter(:packbits, opts)

        {:ok, :builtin_categorize} ->
          encode_builtin_filter(:categorize, opts)

        {:ok, :builtin_bitround} ->
          encode_builtin_filter(:bitround, opts)

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
