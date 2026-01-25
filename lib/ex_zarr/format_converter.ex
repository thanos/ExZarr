defmodule ExZarr.FormatConverter do
  @moduledoc """
  Convert Zarr arrays between v2 and v3 formats.

  Provides utilities for converting entire Zarr arrays from one format version
  to another, including metadata conversion and chunk copying with proper key
  encoding.

  ## Features

  - Convert v2 arrays to v3 format
  - Convert v3 arrays to v2 format (with limitations)
  - Preserve data during conversion
  - Handle different chunk key encodings
  - Clear error messages for incompatible features

  ## Limitations

  ### v3 → v2 Conversion

  The following v3 features cannot be converted to v2:
  - Sharding codec
  - Dimension names (lost in conversion)
  - Irregular chunk grids
  - Array→Array codecs (transpose, quantize, bitround)
  - Custom chunk key encodings

  ### v2 → v3 Conversion

  v2 arrays can be fully converted to v3, with the following transformations:
  - Filters and compressor become unified codec pipeline
  - NumPy dtypes become v3 data types
  - Regular chunking becomes regular chunk grid
  - Attributes are preserved

  ## Examples

      # Convert v2 array to v3
      ExZarr.FormatConverter.convert(
        source_path: "/data/array_v2.zarr",
        target_path: "/data/array_v3.zarr",
        target_version: 3
      )

      # Convert v3 array to v2 (if compatible)
      ExZarr.FormatConverter.convert(
        source_path: "/data/array_v3.zarr",
        target_path: "/data/array_v2.zarr",
        target_version: 2
      )

      # Convert with explicit storage options
      ExZarr.FormatConverter.convert(
        source_path: "/data/array_v2.zarr",
        source_storage: :filesystem,
        target_path: "/data/array_v3.zarr",
        target_storage: :filesystem,
        target_version: 3
      )
  """

  alias ExZarr.{Array, Metadata, MetadataV3, Storage}

  @type convert_opts :: [
          source_path: String.t(),
          source_storage: atom(),
          target_path: String.t(),
          target_storage: atom(),
          target_version: 2 | 3
        ]

  @doc """
  Convert a Zarr array from one format version to another.

  Reads the source array, converts metadata to the target format, and copies
  all chunks with proper key encoding for the target format.

  ## Parameters

    * `opts` - Keyword list with:
      - `:source_path` - Path to source array (required)
      - `:source_storage` - Source storage backend (default: `:filesystem`)
      - `:target_path` - Path to target array (required)
      - `:target_storage` - Target storage backend (default: `:filesystem`)
      - `:target_version` - Target Zarr version, 2 or 3 (required)

  ## Returns

    * `:ok` - Conversion successful
    * `{:error, reason}` - Conversion failed

  ## Examples

      # Basic conversion from v2 to v3
      :ok = ExZarr.FormatConverter.convert(
        source_path: "/data/my_array.zarr",
        target_path: "/data/my_array_v3.zarr",
        target_version: 3
      )

      # Conversion with custom storage
      :ok = ExZarr.FormatConverter.convert(
        source_path: "/data/my_array.zarr",
        source_storage: :filesystem,
        target_path: "/data/my_array_v3.zarr",
        target_storage: :memory,
        target_version: 3
      )
  """
  @spec convert(convert_opts()) :: :ok | {:error, term()}
  def convert(opts) do
    source_path = Keyword.fetch!(opts, :source_path)
    target_path = Keyword.fetch!(opts, :target_path)
    target_version = Keyword.fetch!(opts, :target_version)
    source_storage = Keyword.get(opts, :source_storage, :filesystem)
    target_storage = Keyword.get(opts, :target_storage, :filesystem)

    with {:ok, source_array} <- open_source_array(source_path, source_storage),
         {:ok, target_metadata} <- convert_metadata(source_array, target_version),
         {:ok, target_array} <-
           create_target_array(target_path, target_storage, target_metadata, target_version) do
      copy_chunks(source_array, target_array)
    end
  end

  @doc false
  defp open_source_array(path, storage) do
    # Try to open as v3 first, fall back to v2
    case ExZarr.open(path: path, storage: storage, zarr_version: 3) do
      {:ok, array} ->
        {:ok, array}

      {:error, _} ->
        # Try v2
        case ExZarr.open(path: path, storage: storage, zarr_version: 2) do
          {:ok, array} ->
            {:ok, array}

          {:error, reason} ->
            {:error, {:cannot_open_source, reason}}
        end
    end
  end

  @doc false
  defp convert_metadata(%Array{metadata: metadata}, 3) when is_struct(metadata, Metadata) do
    # v2 → v3 conversion
    MetadataV3.from_v2(metadata)
  end

  defp convert_metadata(%Array{metadata: metadata}, 2) when is_struct(metadata, MetadataV3) do
    # v3 → v2 conversion
    MetadataV3.to_v2(metadata)
  end

  defp convert_metadata(%Array{metadata: metadata}, target_version) do
    {:error,
     {:invalid_conversion,
      "Cannot convert from #{metadata.__struct__} to version #{target_version}"}}
  end

  @doc false
  defp create_target_array(path, storage, %MetadataV3{} = metadata, 3) do
    # Create v3 array
    {:ok, chunk_shape} = MetadataV3.get_chunk_shape(metadata)
    dtype_atom = ExZarr.DataType.from_v3(metadata.data_type)

    ExZarr.create(
      path: path,
      storage: storage,
      shape: metadata.shape,
      chunks: chunk_shape,
      dtype: dtype_atom,
      zarr_version: 3,
      codecs: metadata.codecs,
      fill_value: metadata.fill_value,
      attributes: metadata.attributes,
      dimension_names: metadata.dimension_names
    )
  end

  defp create_target_array(path, storage, %Metadata{} = metadata, 2) do
    # Create v2 array
    ExZarr.create(
      path: path,
      storage: storage,
      shape: metadata.shape,
      chunks: metadata.chunks,
      dtype: metadata.dtype,
      zarr_version: 2,
      compressor: metadata.compressor,
      filters: metadata.filters,
      fill_value: metadata.fill_value
    )
  end

  @doc false
  defp copy_chunks(source_array, target_array) do
    # Get all chunk indices from source
    source_metadata = source_array.metadata

    chunk_indices =
      case get_all_chunk_indices(source_metadata) do
        {:ok, indices} -> indices
        {:error, reason} -> raise "Failed to get chunk indices: #{inspect(reason)}"
      end

    # Copy each chunk
    Enum.reduce_while(chunk_indices, :ok, fn chunk_index, :ok ->
      case copy_single_chunk(source_array, target_array, chunk_index) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:chunk_copy_failed, chunk_index, reason}}}
      end
    end)
  end

  @doc false
  defp get_all_chunk_indices(%Metadata{} = metadata) do
    # v2 metadata
    num_chunks =
      metadata.shape
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(metadata.chunks))
      |> Enum.map(fn {dim_size, chunk_size} ->
        div(dim_size + chunk_size - 1, chunk_size)
      end)
      |> List.to_tuple()

    indices = generate_chunk_indices(num_chunks)
    {:ok, indices}
  end

  defp get_all_chunk_indices(%MetadataV3{} = metadata) do
    # v3 metadata
    case MetadataV3.num_chunks(metadata) do
      {:ok, num_chunks} ->
        indices = generate_chunk_indices(num_chunks)
        {:ok, indices}

      error ->
        error
    end
  end

  @doc false
  defp generate_chunk_indices(num_chunks) when is_tuple(num_chunks) do
    num_chunks
    |> Tuple.to_list()
    |> generate_indices_recursive()
  end

  defp generate_indices_recursive([count]) do
    for i <- 0..(count - 1), do: {i}
  end

  defp generate_indices_recursive([count | rest]) do
    rest_indices = generate_indices_recursive(rest)

    for i <- 0..(count - 1), rest_tuple <- rest_indices do
      List.to_tuple([i | Tuple.to_list(rest_tuple)])
    end
  end

  @doc false
  defp copy_single_chunk(source_array, target_array, chunk_index) do
    # Read encoded chunk from source
    case Storage.read_chunk(source_array.storage, chunk_index) do
      {:ok, encoded_data} ->
        # Write encoded data to target
        # Note: Data is already encoded in the source format, and the storage
        # backend will handle the key encoding for the target format
        Storage.write_chunk(target_array.storage, chunk_index, encoded_data)

      {:error, :not_found} ->
        # Chunk doesn't exist in source (sparse array) - skip it
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a v3 array can be converted to v2 without data loss.

  Returns `:ok` if conversion is possible, or `{:error, reason}` with details
  about incompatible features.

  ## Parameters

    * `metadata` - MetadataV3 struct to check

  ## Returns

    * `:ok` - Can be converted to v2
    * `{:error, {reason, details}}` - Cannot be converted

  ## Examples

      iex> metadata = %ExZarr.MetadataV3{
      ...>   zarr_format: 3,
      ...>   node_type: :array,
      ...>   shape: {100},
      ...>   data_type: "int32",
      ...>   chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
      ...>   codecs: [%{name: "bytes"}]
      ...> }
      iex> ExZarr.FormatConverter.check_v2_compatibility(metadata)
      :ok
  """
  @spec check_v2_compatibility(MetadataV3.t()) :: :ok | {:error, {atom(), String.t()}}
  def check_v2_compatibility(%MetadataV3{node_type: :group}) do
    {:error, {:incompatible_feature, "Groups are not supported in v2"}}
  end

  def check_v2_compatibility(%MetadataV3{} = metadata) do
    checks = [
      check_chunk_grid_compatibility(metadata.chunk_grid),
      check_sharding_compatibility(metadata.codecs),
      check_dimension_names_compatibility(metadata.dimension_names)
    ]

    case Enum.find(checks, fn result -> result != :ok end) do
      nil -> :ok
      error -> error
    end
  end

  @doc false
  defp check_chunk_grid_compatibility(%{name: "regular"}), do: :ok

  defp check_chunk_grid_compatibility(%{name: name}) do
    {:error,
     {:incompatible_feature, "Chunk grid '#{name}' not supported in v2 (only 'regular' allowed)"}}
  end

  @doc false
  defp check_sharding_compatibility(nil), do: :ok
  defp check_sharding_compatibility([]), do: :ok

  defp check_sharding_compatibility(codecs) when is_list(codecs) do
    has_sharding = Enum.any?(codecs, fn codec -> Map.get(codec, :name) == "sharding_indexed" end)

    if has_sharding do
      {:error, {:incompatible_feature, "Sharding codec is not supported in v2"}}
    else
      :ok
    end
  end

  @doc false
  defp check_dimension_names_compatibility(nil), do: :ok
  defp check_dimension_names_compatibility([]), do: :ok

  defp check_dimension_names_compatibility(names) when is_list(names) do
    # Dimension names will be lost but don't prevent conversion
    {:warning, {:feature_will_be_lost, "Dimension names: #{inspect(names)}"}}
  end
end
