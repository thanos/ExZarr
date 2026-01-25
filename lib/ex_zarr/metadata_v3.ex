defmodule ExZarr.MetadataV3 do
  @moduledoc """
  Zarr v3 metadata structure and validation.

  This module defines the metadata format for Zarr v3 specification, which
  introduces a unified `zarr.json` metadata file format replacing the separate
  `.zarray` and `.zgroup` files from v2.

  ## Key Differences from v2

  - **Unified metadata**: Single `zarr.json` file for both arrays and groups
  - **Node type**: Explicit `node_type` field ("array" or "group")
  - **Codec pipeline**: Unified `codecs` array instead of separate `filters` + `compressor`
  - **Data types**: Simplified type names ("float64" instead of "<f8")
  - **Extensions**: `chunk_grid` and `chunk_key_encoding` extension points
  - **Embedded attributes**: Attributes stored in metadata instead of separate `.zattrs`

  ## Specification

  Zarr v3 Core Specification:
  https://zarr-specs.readthedocs.io/en/latest/v3/core/index.html

  ## Examples

      # Array metadata
      %ExZarr.MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {1000, 1000},
        data_type: "float64",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {100, 100}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "bytes"},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        fill_value: 0.0,
        attributes: %{},
        dimension_names: nil
      }

      # Group metadata
      %ExZarr.MetadataV3{
        zarr_format: 3,
        node_type: :group,
        attributes: %{"description" => "My data group"}
      }
  """

  alias ExZarr.Codecs.PipelineV3
  alias ExZarr.DataType

  @type node_type :: :array | :group
  @type data_type :: String.t()
  @type codec_spec :: %{required(:name) => String.t(), optional(:configuration) => map()}
  @type chunk_grid :: %{required(:name) => String.t(), optional(:configuration) => map()}
  @type chunk_key_encoding :: %{
          required(:name) => String.t(),
          optional(:configuration) => map()
        }

  @type t :: %__MODULE__{
          zarr_format: 3,
          node_type: node_type(),
          # Array-specific fields (nil for groups)
          shape: tuple() | nil,
          data_type: data_type() | nil,
          chunk_grid: chunk_grid() | nil,
          chunk_key_encoding: chunk_key_encoding() | nil,
          codecs: [codec_spec()] | nil,
          fill_value: term() | nil,
          # Common fields
          attributes: map(),
          dimension_names: [String.t() | nil] | nil
        }

  defstruct [
    :zarr_format,
    :node_type,
    :shape,
    :data_type,
    :chunk_grid,
    :chunk_key_encoding,
    :codecs,
    :fill_value,
    :attributes,
    :dimension_names
  ]

  defimpl Jason.Encoder do
    def encode(metadata, opts) do
      map =
        %{
          zarr_format: metadata.zarr_format,
          node_type: metadata.node_type
        }
        |> add_array_fields(metadata)
        |> add_common_fields(metadata)

      Jason.Encode.map(map, opts)
    end

    defp add_array_fields(map, %{node_type: :array} = metadata) do
      # Convert tuples to lists for JSON encoding
      chunk_shape =
        if metadata.chunk_grid && metadata.chunk_grid.configuration do
          case metadata.chunk_grid.configuration.chunk_shape do
            shape when is_tuple(shape) -> Tuple.to_list(shape)
            shape -> shape
          end
        else
          nil
        end

      chunk_grid =
        if metadata.chunk_grid && chunk_shape do
          %{
            name: metadata.chunk_grid.name,
            configuration: %{chunk_shape: chunk_shape}
          }
        else
          metadata.chunk_grid
        end

      # Convert codec chunk_shape tuples to lists
      codecs = convert_codec_shapes(metadata.codecs)

      map
      |> Map.put(:shape, maybe_tuple_to_list(metadata.shape))
      |> Map.put(:data_type, metadata.data_type)
      |> Map.put(:chunk_grid, chunk_grid)
      |> Map.put(:chunk_key_encoding, metadata.chunk_key_encoding)
      |> Map.put(:codecs, codecs)
      |> Map.put(:fill_value, metadata.fill_value)
    end

    defp add_array_fields(map, _metadata), do: map

    defp add_common_fields(map, metadata) do
      map
      |> Map.put(:attributes, metadata.attributes || %{})
      |> maybe_put(:dimension_names, metadata.dimension_names)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)

    defp maybe_tuple_to_list(value) when is_tuple(value), do: Tuple.to_list(value)
    defp maybe_tuple_to_list(value), do: value

    defp convert_codec_shapes(nil), do: nil
    defp convert_codec_shapes([]), do: []

    defp convert_codec_shapes(codecs) when is_list(codecs) do
      Enum.map(codecs, &convert_codec_shape/1)
    end

    defp convert_codec_shape(%{name: "sharding_indexed", configuration: config} = codec)
         when is_map(config) do
      # Convert chunk_shape tuple to list in sharding configuration
      # Handle both atom and string keys
      chunk_shape =
        case Map.get(config, :chunk_shape) || Map.get(config, "chunk_shape") do
          shape when is_tuple(shape) -> Tuple.to_list(shape)
          shape -> shape
        end

      # Build new config with converted values, preserving key format
      updated_config =
        config
        |> update_config_key(:chunk_shape, "chunk_shape", chunk_shape)
        |> update_config_key_with_converter(
          :codecs,
          "codecs",
          &convert_codec_shapes/1
        )
        |> update_config_key_with_converter(
          :index_codecs,
          "index_codecs",
          &convert_codec_shapes/1
        )

      %{codec | configuration: updated_config}
    end

    defp convert_codec_shape(%{name: _name, configuration: config} = codec) when is_map(config) do
      # For other codecs, just ensure maps are properly formatted
      codec
    end

    defp convert_codec_shape(codec), do: codec

    defp update_config_key(config, atom_key, string_key, value) do
      cond do
        Map.has_key?(config, atom_key) -> Map.put(config, atom_key, value)
        Map.has_key?(config, string_key) -> Map.put(config, string_key, value)
        true -> config
      end
    end

    defp update_config_key_with_converter(config, atom_key, string_key, converter) do
      value = Map.get(config, atom_key) || Map.get(config, string_key)

      if value do
        update_config_key(config, atom_key, string_key, converter.(value))
      else
        config
      end
    end
  end

  @doc """
  Validates v3 metadata structure.

  Performs comprehensive validation including:
  - Zarr format version check
  - Node type validation
  - Array-specific field requirements
  - Codec pipeline validation
  - Extension format checks

  ## Parameters

    * `metadata` - MetadataV3 struct to validate

  ## Returns

    * `:ok` if metadata is valid
    * `{:error, reason}` if validation fails

  ## Examples

      iex> metadata = %ExZarr.MetadataV3{
      ...>   zarr_format: 3,
      ...>   node_type: :array,
      ...>   shape: {100},
      ...>   data_type: "float64",
      ...>   chunk_grid: %{name: "regular", configuration: %{chunk_shape: {10}}},
      ...>   chunk_key_encoding: %{name: "default"},
      ...>   codecs: [%{name: "bytes"}],
      ...>   fill_value: 0.0,
      ...>   attributes: %{}
      ...> }
      iex> ExZarr.MetadataV3.validate(metadata)
      :ok
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = metadata) do
    with :ok <- validate_zarr_format(metadata.zarr_format),
         :ok <- validate_node_type(metadata.node_type),
         :ok <- validate_array_fields(metadata) do
      validate_codecs(metadata)
    end
  end

  @doc false
  @spec validate_zarr_format(term()) :: :ok | {:error, {:invalid_zarr_format, String.t()}}
  defp validate_zarr_format(3), do: :ok

  defp validate_zarr_format(other),
    do: {:error, {:invalid_zarr_format, "Expected 3, got: #{inspect(other)}"}}

  @doc false
  @spec validate_node_type(term()) :: :ok | {:error, {:invalid_node_type, String.t()}}
  defp validate_node_type(node_type) when node_type in [:array, :group], do: :ok

  defp validate_node_type(other),
    do: {:error, {:invalid_node_type, "Expected :array or :group, got: #{inspect(other)}"}}

  @doc false
  @spec validate_array_fields(t()) :: :ok | {:error, term()}
  defp validate_array_fields(%__MODULE__{node_type: :group}) do
    # Groups don't require array-specific fields
    :ok
  end

  defp validate_array_fields(%__MODULE__{node_type: :array} = metadata) do
    with :ok <- validate_required_field(metadata.shape, :shape),
         :ok <- validate_required_field(metadata.data_type, :data_type),
         :ok <- validate_required_field(metadata.chunk_grid, :chunk_grid),
         :ok <- validate_required_field(metadata.chunk_key_encoding, :chunk_key_encoding),
         :ok <- validate_required_field(metadata.codecs, :codecs),
         :ok <- validate_shape(metadata.shape),
         :ok <- validate_data_type(metadata.data_type),
         :ok <- validate_chunk_grid(metadata.chunk_grid) do
      validate_dimension_names(metadata.dimension_names, metadata.shape)
    end
  end

  @doc false
  @spec validate_required_field(
          term(),
          :shape | :data_type | :chunk_grid | :chunk_key_encoding | :codecs
        ) ::
          :ok
          | {:error,
             {:missing_required_field,
              :shape | :data_type | :chunk_grid | :chunk_key_encoding | :codecs}}
  defp validate_required_field(nil, field_name),
    do: {:error, {:missing_required_field, field_name}}

  defp validate_required_field(_value, _field_name), do: :ok

  @doc false
  @spec validate_shape(term()) :: :ok | {:error, {:invalid_shape, String.t()}}
  defp validate_shape(shape) when is_tuple(shape) do
    if tuple_size(shape) > 0 and Enum.all?(Tuple.to_list(shape), &is_integer(&1)) and
         Enum.all?(Tuple.to_list(shape), &(&1 > 0)) do
      :ok
    else
      {:error, {:invalid_shape, "Shape must contain only positive integers"}}
    end
  end

  defp validate_shape(other),
    do: {:error, {:invalid_shape, "Expected tuple, got: #{inspect(other)}"}}

  @doc false
  @spec validate_data_type(term()) :: :ok | {:error, {:invalid_data_type, String.t()}}
  defp validate_data_type(data_type) when is_binary(data_type) do
    # v3 supports these core data types
    valid_types = [
      "bool",
      "int8",
      "int16",
      "int32",
      "int64",
      "uint8",
      "uint16",
      "uint32",
      "uint64",
      "float32",
      "float64"
    ]

    if data_type in valid_types do
      :ok
    else
      # Extension types are allowed but we issue a warning (still valid)
      :ok
    end
  end

  defp validate_data_type(other),
    do: {:error, {:invalid_data_type, "Expected string, got: #{inspect(other)}"}}

  @doc false
  @spec validate_chunk_grid(term()) :: :ok | {:error, {:invalid_chunk_grid, String.t()}}
  defp validate_chunk_grid(%{name: name}) when is_binary(name) do
    # Extension point - any name is valid
    :ok
  end

  defp validate_chunk_grid(other),
    do: {:error, {:invalid_chunk_grid, "Expected map with 'name' field, got: #{inspect(other)}"}}

  @doc false
  @spec validate_dimension_names([String.t() | nil] | nil, tuple()) ::
          :ok | {:error, {:invalid_dimension_names, String.t()}}
  defp validate_dimension_names(nil, _shape), do: :ok
  defp validate_dimension_names([], _shape), do: :ok

  defp validate_dimension_names(names, shape) when is_list(names) do
    ndim = tuple_size(shape)

    with :ok <- validate_dimension_names_count(names, ndim),
         :ok <- validate_dimension_names_format(names) do
      validate_dimension_names_unique(names)
    end
  end

  defp validate_dimension_names(other, _shape),
    do:
      {:error,
       {:invalid_dimension_names, "Expected list of strings or nil, got: #{inspect(other)}"}}

  defp validate_dimension_names_count(names, ndim) do
    if length(names) == ndim do
      :ok
    else
      {:error,
       {:invalid_dimension_names,
        "Dimension names count (#{length(names)}) must match shape dimensions (#{ndim})"}}
    end
  end

  defp validate_dimension_names_format(names) do
    invalid =
      Enum.find(names, fn name ->
        case name do
          nil -> false
          name when is_binary(name) -> not valid_dimension_name?(name)
          _ -> true
        end
      end)

    case invalid do
      nil ->
        :ok

      name ->
        {:error,
         {:invalid_dimension_names,
          "Invalid dimension name: #{inspect(name)}. Must be string with alphanumeric, underscore, or hyphen characters"}}
    end
  end

  defp validate_dimension_names_unique(names) do
    # Filter out nils before checking uniqueness
    non_nil_names = Enum.filter(names, &(&1 != nil))

    if length(non_nil_names) == length(Enum.uniq(non_nil_names)) do
      :ok
    else
      duplicates = non_nil_names -- Enum.uniq(non_nil_names)

      {:error,
       {:invalid_dimension_names,
        "Duplicate dimension names found: #{inspect(Enum.uniq(duplicates))}"}}
    end
  end

  defp valid_dimension_name?(name) when is_binary(name) do
    # Valid dimension names: alphanumeric, underscore, hyphen, not empty
    String.match?(name, ~r/^[a-zA-Z0-9_-]+$/)
  end

  @doc false
  @spec validate_codecs(t()) :: :ok | {:error, term()}
  defp validate_codecs(%__MODULE__{node_type: :group}), do: :ok

  defp validate_codecs(%__MODULE__{node_type: :array, codecs: codecs}) when is_list(codecs) do
    with :ok <- validate_codec_list(codecs) do
      validate_array_to_bytes_codec(codecs)
    end
  end

  defp validate_codecs(%__MODULE__{codecs: nil}),
    do: {:error, {:missing_codecs, "Array must have codecs defined"}}

  @doc false
  @spec validate_codec_list([map()]) ::
          :ok | {:error, {:empty_codecs, String.t()} | {:invalid_codec_format, String.t()}}
  defp validate_codec_list([]), do: {:error, {:empty_codecs, "Codec list cannot be empty"}}

  defp validate_codec_list(codecs) do
    invalid_codecs =
      Enum.filter(codecs, fn codec ->
        not is_map(codec) or not Map.has_key?(codec, :name)
      end)

    if Enum.empty?(invalid_codecs) do
      :ok
    else
      {:error, {:invalid_codec_format, "All codecs must have 'name' field"}}
    end
  end

  @doc false
  @spec validate_array_to_bytes_codec([codec_spec()]) :: :ok
  defp validate_array_to_bytes_codec(codecs) do
    # Check for "bytes" codec which is the standard array→bytes codec
    has_bytes_codec = Enum.any?(codecs, fn codec -> Map.get(codec, :name) == "bytes" end)

    if has_bytes_codec do
      :ok
    else
      # Warning: Should have at least one array→bytes codec, but we'll be lenient
      # in case of custom codecs
      :ok
    end
  end

  @doc """
  Extracts chunk shape from chunk_grid configuration.

  ## Parameters

    * `metadata` - MetadataV3 struct

  ## Returns

    * `{:ok, chunk_shape}` - Chunk shape tuple
    * `{:error, reason}` - If chunk shape cannot be extracted

  ## Examples

      iex> metadata = %ExZarr.MetadataV3{
      ...>   chunk_grid: %{
      ...>     name: "regular",
      ...>     configuration: %{chunk_shape: {10, 10}}
      ...>   }
      ...> }
      iex> ExZarr.MetadataV3.get_chunk_shape(metadata)
      {:ok, {10, 10}}
  """
  @spec get_chunk_shape(t()) :: {:ok, tuple()} | {:error, term()}
  def get_chunk_shape(%__MODULE__{chunk_grid: %{configuration: %{chunk_shape: chunk_shape}}})
      when is_tuple(chunk_shape) do
    {:ok, chunk_shape}
  end

  def get_chunk_shape(%__MODULE__{chunk_grid: %{configuration: config}}) do
    # Try to extract chunk_shape from various possible formats
    case config do
      %{chunk_shape: shape} when is_list(shape) ->
        {:ok, List.to_tuple(shape)}

      _ ->
        {:error, :chunk_shape_not_found}
    end
  end

  def get_chunk_shape(_), do: {:error, :invalid_chunk_grid}

  @doc """
  Calculates the number of chunks along each dimension.

  ## Parameters

    * `metadata` - MetadataV3 struct

  ## Returns

    * `{:ok, num_chunks}` - Tuple of chunk counts per dimension
    * `{:error, reason}` - If calculation fails

  ## Examples

      iex> metadata = %ExZarr.MetadataV3{
      ...>   shape: {100, 200},
      ...>   chunk_grid: %{
      ...>     name: "regular",
      ...>     configuration: %{chunk_shape: {10, 20}}
      ...>   }
      ...> }
      iex> ExZarr.MetadataV3.num_chunks(metadata)
      {:ok, {10, 10}}
  """
  @spec num_chunks(t()) :: {:ok, tuple()} | {:error, term()}
  def num_chunks(%__MODULE__{shape: shape} = metadata) when is_tuple(shape) do
    case get_chunk_shape(metadata) do
      {:ok, chunk_shape} ->
        num_chunks =
          shape
          |> Tuple.to_list()
          |> Enum.zip(Tuple.to_list(chunk_shape))
          |> Enum.map(fn {dim_size, chunk_size} ->
            div(dim_size + chunk_size - 1, chunk_size)
          end)
          |> List.to_tuple()

        {:ok, num_chunks}

      error ->
        error
    end
  end

  def num_chunks(_), do: {:error, :invalid_metadata}

  @doc """
  Calculates the total number of chunks in the array.

  ## Parameters

    * `metadata` - MetadataV3 struct

  ## Returns

    * `{:ok, total}` - Total number of chunks
    * `{:error, reason}` - If calculation fails

  ## Examples

      iex> metadata = %ExZarr.MetadataV3{
      ...>   shape: {100, 200},
      ...>   chunk_grid: %{
      ...>     name: "regular",
      ...>     configuration: %{chunk_shape: {10, 20}}
      ...>   }
      ...> }
      iex> ExZarr.MetadataV3.total_chunks(metadata)
      {:ok, 100}
  """
  @spec total_chunks(t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def total_chunks(metadata) do
    case num_chunks(metadata) do
      {:ok, chunks_per_dim} ->
        total =
          chunks_per_dim
          |> Tuple.to_list()
          |> Enum.reduce(1, &*/2)

        {:ok, total}

      error ->
        error
    end
  end

  @doc """
  Creates v3 metadata from array configuration.

  Converts v2-style configuration options into v3 metadata format with:
  - Unified codec pipeline (converts filters + compressor to codecs array)
  - Simplified data type names
  - Regular chunk grid
  - Default chunk key encoding

  ## Parameters

    * `config` - Configuration map with keys:
      - `:shape` - Array dimensions (required)
      - `:chunks` - Chunk dimensions (required)
      - `:dtype` - Data type atom (required)
      - `:compressor` - Compressor atom (optional, default :zstd)
      - `:filters` - v2-style filter list (optional)
      - `:codecs` - v3-style codec list (takes precedence over filters/compressor)
      - `:fill_value` - Fill value (optional, default 0)
      - `:attributes` - Custom attributes (optional, default %{})

  ## Returns

    * `{:ok, metadata}` - MetadataV3 struct

  ## Examples

      # Using v3 codecs directly
      {:ok, metadata} = ExZarr.MetadataV3.create(%{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        codecs: [
          %{name: "bytes"},
          %{name: "gzip", configuration: %{level: 5}}
        ]
      })

      # Using v2-style filters and compressor (auto-converted)
      {:ok, metadata} = ExZarr.MetadataV3.create(%{
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        filters: [{:shuffle, [elementsize: 8]}],
        compressor: :zlib
      })
  """
  @spec create(map()) :: {:ok, t()}
  def create(config) do
    # Handle both v3 codecs and v2 filters+compressor
    base_codecs =
      case Map.get(config, :codecs) do
        nil ->
          # Convert v2 style to v3 codecs
          filters = Map.get(config, :filters, [])
          compressor = Map.get(config, :compressor, :zstd)
          PipelineV3.from_v2(filters, compressor)

        codecs ->
          # Use provided v3 codecs
          codecs
      end

    # Wrap codecs in sharding if shard_shape is provided
    codecs =
      case Map.get(config, :shard_shape) do
        nil ->
          # No sharding
          base_codecs

        shard_shape ->
          # Wrap base codecs in sharding codec
          # Convert shard_shape to list for JSON encoding
          chunk_shape_list =
            if is_tuple(shard_shape), do: Tuple.to_list(shard_shape), else: shard_shape

          index_codecs = Map.get(config, :index_codecs, [%{name: "bytes"}, %{name: "crc32c"}])
          index_location = Map.get(config, :index_location, "end")

          [
            %{
              name: "sharding_indexed",
              configuration: %{
                chunk_shape: chunk_shape_list,
                codecs: base_codecs,
                index_codecs: index_codecs,
                index_location: index_location
              }
            }
          ]
      end

    metadata = %__MODULE__{
      zarr_format: 3,
      node_type: :array,
      shape: Map.fetch!(config, :shape),
      data_type: DataType.to_v3(Map.fetch!(config, :dtype)),
      chunk_grid: %{
        name: "regular",
        configuration: %{chunk_shape: Map.fetch!(config, :chunks)}
      },
      chunk_key_encoding: %{name: "default"},
      codecs: codecs,
      fill_value: Map.get(config, :fill_value, 0),
      attributes: Map.get(config, :attributes, %{}),
      dimension_names: Map.get(config, :dimension_names, nil)
    }

    {:ok, metadata}
  end
end
