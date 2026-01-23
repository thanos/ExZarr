defmodule ExZarr.Storage do
  @moduledoc """
  Storage backend abstraction for Zarr arrays.

  Supports multiple storage backends:
  - `:memory` - In-memory storage (default, non-persistent)
  - `:filesystem` - Local filesystem storage
  - Future: `:s3` - Amazon S3 storage
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
  """
  @spec init(map()) :: {:ok, t()} | {:error, term()}
  def init(%{storage_type: :memory} = _config) do
    {:ok,
     %__MODULE__{
       backend: :memory,
       state: %{chunks: %{}, metadata: nil}
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
  """
  @spec read_chunk(t(), tuple()) :: {:ok, binary()} | {:error, term()}
  def read_chunk(%__MODULE__{backend: :memory, state: state}, chunk_index) do
    case Map.get(state.chunks, chunk_index) do
      nil -> {:error, :not_found}
      data -> {:ok, data}
    end
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
  """
  @spec write_chunk(t(), tuple(), binary()) :: :ok | {:error, term()}
  def write_chunk(%__MODULE__{backend: :memory, state: state} = storage, chunk_index, data) do
    new_chunks = Map.put(state.chunks, chunk_index, data)
    new_state = Map.put(state, :chunks, new_chunks)
    # Note: In real implementation, we'd need to update the storage reference
    # This is a simplified version
    {:ok, %{storage | state: new_state}}
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
  """
  @spec read_metadata(t()) :: {:ok, map()} | {:error, term()}
  def read_metadata(%__MODULE__{backend: :memory, state: state}) do
    case Map.get(state, :metadata) do
      nil -> {:error, :metadata_not_found}
      metadata -> {:ok, metadata}
    end
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
        zarr_format: metadata.zarr_format
      }

      {:ok, parsed_metadata}
    else
      {:error, :enoent} -> {:error, :metadata_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes metadata to storage.
  """
  @spec write_metadata(t(), ExZarr.Metadata.t(), keyword()) :: :ok | {:error, term()}
  def write_metadata(%__MODULE__{backend: :memory, state: state} = storage, metadata, _opts) do
    new_state = Map.put(state, :metadata, metadata)
    {:ok, %{storage | state: new_state}}
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
      filters: nil
    }

    with {:ok, json} <- Jason.encode(metadata_json, pretty: true) do
      File.write(metadata_path, json)
    end
  end

  @doc """
  Lists all chunk keys in the storage.
  """
  @spec list_chunks(t()) :: {:ok, [tuple()]} | {:error, term()}
  def list_chunks(%__MODULE__{backend: :memory, state: state}) do
    {:ok, Map.keys(state.chunks)}
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
  # Handle big-endian variants
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
end
