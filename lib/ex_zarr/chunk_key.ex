defmodule ExZarr.ChunkKey do
  @moduledoc """
  Chunk key encoding for Zarr v2 and v3 formats.

  Zarr uses chunk keys to identify individual chunk files in storage. The format
  differs between v2 and v3 specifications:

  ## Zarr v2 Format

  Dot-separated notation with optional dimension separator:
  - 1D: `"0"`, `"1"`, `"2"`
  - 2D: `"0.0"`, `"0.1"`, `"1.0"`
  - 3D: `"0.0.0"`, `"0.1.2"`, `"1.2.3"`

  ## Zarr v3 Format

  Slash-separated notation with `c/` prefix:
  - 1D: `"c/0"`, `"c/1"`, `"c/2"`
  - 2D: `"c/0/0"`, `"c/0/1"`, `"c/1/0"`
  - 3D: `"c/0/0/0"`, `"c/0/1/2"`, `"c/1/2/3"`

  ## Usage

      # Encode chunk indices to keys
      iex> ExZarr.ChunkKey.encode({0, 1, 2}, 2)
      "0.1.2"

      iex> ExZarr.ChunkKey.encode({0, 1, 2}, 3)
      "c/0/1/2"

      # Decode keys to indices
      iex> ExZarr.ChunkKey.decode("0.1.2", 2)
      {:ok, {0, 1, 2}}

      iex> ExZarr.ChunkKey.decode("c/0/1/2", 3)
      {:ok, {0, 1, 2}}

  ## Storage Backends

  Storage backends must use this module to ensure correct chunk key format for
  the array version being used.
  """

  @type version :: 2 | 3
  @type chunk_index :: tuple()
  @type chunk_key :: String.t()

  @doc """
  Encodes a chunk index tuple into a chunk key string.

  ## Parameters

    * `chunk_index` - Tuple of non-negative integers representing chunk coordinates
    * `version` - Zarr format version (2 or 3)

  ## Returns

    * Chunk key string in the appropriate format

  ## Examples

      # v2 format
      iex> ExZarr.ChunkKey.encode({0}, 2)
      "0"

      iex> ExZarr.ChunkKey.encode({0, 1}, 2)
      "0.1"

      iex> ExZarr.ChunkKey.encode({42}, 2)
      "42"

      # v3 format
      iex> ExZarr.ChunkKey.encode({0}, 3)
      "c/0"

      iex> ExZarr.ChunkKey.encode({0, 1, 2}, 3)
      "c/0/1/2"
  """
  @spec encode(chunk_index(), version()) :: chunk_key()
  def encode(chunk_index, 2) when is_tuple(chunk_index) do
    # v2: dot-separated notation
    chunk_index
    |> Tuple.to_list()
    |> Enum.map_join(".", &Integer.to_string/1)
  end

  def encode(chunk_index, 3) when is_tuple(chunk_index) do
    # v3: slash-separated with "c/" prefix
    indices =
      chunk_index
      |> Tuple.to_list()
      |> Enum.map_join("/", &Integer.to_string/1)

    "c/#{indices}"
  end

  @doc """
  Decodes a chunk key string into a chunk index tuple.

  ## Parameters

    * `chunk_key` - Chunk key string
    * `version` - Zarr format version (2 or 3)

  ## Returns

    * `{:ok, chunk_index}` - Tuple of integers
    * `{:error, :invalid_chunk_key}` - If key format is invalid

  ## Examples

      # v2 format
      iex> ExZarr.ChunkKey.decode("0", 2)
      {:ok, {0}}

      iex> ExZarr.ChunkKey.decode("0.1.2", 2)
      {:ok, {0, 1, 2}}

      # v3 format
      iex> ExZarr.ChunkKey.decode("c/0", 3)
      {:ok, {0}}

      iex> ExZarr.ChunkKey.decode("c/0/1/2", 3)
      {:ok, {0, 1, 2}}

      # Invalid keys
      iex> ExZarr.ChunkKey.decode("invalid", 2)
      {:error, :invalid_chunk_key}

      iex> ExZarr.ChunkKey.decode("0.1.2", 3)
      {:error, :invalid_chunk_key}
  """
  @spec decode(chunk_key(), version()) :: {:ok, chunk_index()} | {:error, :invalid_chunk_key}
  def decode(chunk_key, 2) when is_binary(chunk_key) do
    # v2: split by ".", parse integers
    indices =
      chunk_key
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    if indices != [] and Enum.all?(indices, &(&1 >= 0)) do
      {:ok, List.to_tuple(indices)}
    else
      {:error, :invalid_chunk_key}
    end
  rescue
    ArgumentError -> {:error, :invalid_chunk_key}
  end

  def decode(chunk_key, 3) when is_binary(chunk_key) do
    # v3: strip "c/" prefix, split by "/"
    case String.split(chunk_key, "/") do
      ["c" | [_ | _] = index_strings] ->
        indices = Enum.map(index_strings, &String.to_integer/1)

        if Enum.all?(indices, &(&1 >= 0)) do
          {:ok, List.to_tuple(indices)}
        else
          {:error, :invalid_chunk_key}
        end

      _ ->
        {:error, :invalid_chunk_key}
    end
  rescue
    ArgumentError -> {:error, :invalid_chunk_key}
  end

  @doc """
  Returns a regex pattern for matching valid chunk keys.

  ## Parameters

    * `version` - Zarr format version (2 or 3)

  ## Returns

    * Regex pattern for valid chunk keys

  ## Examples

      iex> pattern = ExZarr.ChunkKey.chunk_key_pattern(2)
      iex> Regex.match?(pattern, "0.1.2")
      true

      iex> pattern = ExZarr.ChunkKey.chunk_key_pattern(3)
      iex> Regex.match?(pattern, "c/0/1/2")
      true
  """
  @spec chunk_key_pattern(version()) :: Regex.t()
  def chunk_key_pattern(2) do
    # v2: one or more integers separated by dots
    ~r/^\d+(\.\d+)*$/
  end

  def chunk_key_pattern(3) do
    # v3: c/ prefix followed by slash-separated integers
    ~r/^c\/\d+(\/\d+)*$/
  end

  @doc """
  Validates that a chunk key matches the expected format for a version.

  ## Parameters

    * `chunk_key` - Chunk key string to validate
    * `version` - Zarr format version (2 or 3)

  ## Returns

    * `true` if chunk key is valid for the version
    * `false` otherwise

  ## Examples

      iex> ExZarr.ChunkKey.valid?("0.1.2", 2)
      true

      iex> ExZarr.ChunkKey.valid?("c/0/1/2", 2)
      false

      iex> ExZarr.ChunkKey.valid?("c/0/1/2", 3)
      true

      iex> ExZarr.ChunkKey.valid?("0.1.2", 3)
      false
  """
  @spec valid?(chunk_key(), version()) :: boolean()
  def valid?(chunk_key, version) when is_binary(chunk_key) do
    pattern = chunk_key_pattern(version)
    Regex.match?(pattern, chunk_key)
  end

  @doc """
  Lists all possible chunk keys for an array based on its shape and chunk size.

  ## Parameters

    * `shape` - Array shape tuple
    * `chunks` - Chunk size tuple
    * `version` - Zarr format version (2 or 3)

  ## Returns

    * List of all chunk key strings

  ## Examples

      iex> ExZarr.ChunkKey.list_all({10}, {5}, 2)
      ["0", "1"]

      iex> ExZarr.ChunkKey.list_all({10, 10}, {5, 5}, 3)
      ["c/0/0", "c/0/1", "c/1/0", "c/1/1"]
  """
  @spec list_all(tuple(), tuple(), version()) :: [chunk_key()]
  def list_all(shape, chunks, version)
      when is_tuple(shape) and is_tuple(chunks) and tuple_size(shape) == tuple_size(chunks) do
    # Calculate number of chunks per dimension
    num_chunks_per_dim =
      shape
      |> Tuple.to_list()
      |> Enum.zip(Tuple.to_list(chunks))
      |> Enum.map(fn {dim_size, chunk_size} ->
        div(dim_size + chunk_size - 1, chunk_size)
      end)

    # Generate all chunk indices
    generate_all_indices(num_chunks_per_dim)
    |> Enum.map(&encode(&1, version))
  end

  @doc false
  @spec generate_all_indices([non_neg_integer()]) :: [chunk_index()]
  defp generate_all_indices([]), do: [{}]

  defp generate_all_indices([count | rest]) do
    rest_indices = generate_all_indices(rest)

    for i <- 0..(count - 1), rest_index <- rest_indices do
      List.to_tuple([i | Tuple.to_list(rest_index)])
    end
  end

  @doc """
  Builds a chunk directory path for v3 format.

  In v3, chunks are stored in a `c/` subdirectory. This function returns
  the directory path where chunks should be stored.

  ## Parameters

    * `base_path` - Base array path
    * `version` - Zarr format version (2 or 3)

  ## Returns

    * Directory path for chunks

  ## Examples

      iex> ExZarr.ChunkKey.chunk_directory("/data/array", 2)
      "/data/array"

      iex> ExZarr.ChunkKey.chunk_directory("/data/array", 3)
      "/data/array/c"
  """
  @spec chunk_directory(String.t(), version()) :: String.t()
  def chunk_directory(base_path, 2), do: base_path

  def chunk_directory(base_path, 3) do
    Path.join(base_path, "c")
  end

  @doc """
  Builds the full path to a chunk file.

  ## Parameters

    * `base_path` - Base array path
    * `chunk_index` - Chunk index tuple
    * `version` - Zarr format version (2 or 3)

  ## Returns

    * Full path to chunk file

  ## Examples

      iex> ExZarr.ChunkKey.chunk_path("/data/array", {0, 1}, 2)
      "/data/array/0.1"

      iex> ExZarr.ChunkKey.chunk_path("/data/array", {0, 1}, 3)
      "/data/array/c/0/1"
  """
  @spec chunk_path(String.t(), chunk_index(), version()) :: String.t()
  def chunk_path(base_path, chunk_index, version) do
    chunk_key = encode(chunk_index, version)
    Path.join(base_path, chunk_key)
  end

  defmodule Encoder do
    @moduledoc """
    Behavior for custom chunk key encoding schemes.

    Implement this behavior to create custom chunk naming schemes beyond
    the standard v2 (dot-separated) and v3 (slash-separated) formats.

    ## Example

        defmodule MyApp.CustomChunkKey do
          @behaviour ExZarr.ChunkKey.Encoder

          @impl true
          def encode(chunk_index, _opts) do
            # Custom encoding: "chunk_0_1_2" instead of "0.1.2"
            indices = Tuple.to_list(chunk_index)
            "chunk_" <> Enum.join(indices, "_")
          end

          @impl true
          def decode(chunk_key, _opts) do
            case String.split(chunk_key, "_") do
              ["chunk" | indices] ->
                tuple = indices |> Enum.map(&String.to_integer/1) |> List.to_tuple()
                {:ok, tuple}
              _ ->
                {:error, :invalid_chunk_key}
            end
          end

          @impl true
          def pattern(_opts) do
            ~r/^chunk_\\d+(_\\d+)*$/
          end
        end

        # Register and use
        ExZarr.ChunkKey.register_encoder(:custom, MyApp.CustomChunkKey)

        # Use in array creation
        {:ok, array} = ExZarr.Array.create(
          shape: {100, 100},
          chunk_key_encoding: :custom
        )
    """
    @doc """
    Encodes a chunk index tuple into a string key.

    ## Parameters

      * `chunk_index` - Tuple of integers representing chunk position
      * `opts` - Keyword list of options

    ## Returns

    String representation of the chunk key
    """
    @callback encode(chunk_index :: tuple(), opts :: keyword()) :: String.t()

    @doc """
    Decodes a string key back into a chunk index tuple.

    ## Parameters

      * `chunk_key` - String representation of chunk key
      * `opts` - Keyword list of options

    ## Returns

    `{:ok, chunk_index}` or `{:error, reason}`
    """
    @callback decode(chunk_key :: String.t(), opts :: keyword()) ::
                {:ok, tuple()} | {:error, term()}

    @doc """
    Returns a regex pattern that matches valid chunk keys for this encoding.

    ## Parameters

      * `opts` - Keyword list of options

    ## Returns

    Regex pattern
    """
    @callback pattern(opts :: keyword()) :: Regex.t()
  end

  defmodule V2Encoder do
    @moduledoc """
    Default encoder for Zarr v2 format (dot-separated).
    """
    @behaviour ExZarr.ChunkKey.Encoder

    @impl true
    def encode(chunk_index, _opts), do: ExZarr.ChunkKey.encode(chunk_index, 2)

    @impl true
    def decode(chunk_key, _opts), do: ExZarr.ChunkKey.decode(chunk_key, 2)

    @impl true
    def pattern(_opts), do: ExZarr.ChunkKey.chunk_key_pattern(2)
  end

  defmodule V3Encoder do
    @moduledoc """
    Default encoder for Zarr v3 format (slash-separated with c/ prefix).
    """
    @behaviour ExZarr.ChunkKey.Encoder

    @impl true
    def encode(chunk_index, _opts), do: ExZarr.ChunkKey.encode(chunk_index, 3)

    @impl true
    def decode(chunk_key, _opts), do: ExZarr.ChunkKey.decode(chunk_key, 3)

    @impl true
    def pattern(_opts), do: ExZarr.ChunkKey.chunk_key_pattern(3)
  end

  defmodule Registry do
    @moduledoc """
    Encoder registry for managing custom chunk key encoders.

    This Agent-based registry stores encoder modules that can be looked up by name.
    """

    use Agent

    @doc """
    Starts the encoder registry with default encoders.
    """
    def start_link(_opts) do
      Agent.start_link(
        fn ->
          %{
            v2: ExZarr.ChunkKey.V2Encoder,
            v3: ExZarr.ChunkKey.V3Encoder,
            default: ExZarr.ChunkKey.V2Encoder
          }
        end,
        name: __MODULE__
      )
    end

    @doc """
    Registers a custom encoder module.
    """
    @spec register(atom(), module()) :: :ok
    def register(name, encoder_module) do
      Agent.update(__MODULE__, &Map.put(&1, name, encoder_module))
    end

    @doc """
    Retrieves an encoder module by name.
    """
    @spec get(atom()) :: {:ok, module()} | {:error, :not_found}
    def get(name) do
      case Agent.get(__MODULE__, &Map.get(&1, name)) do
        nil -> {:error, :not_found}
        encoder_module -> {:ok, encoder_module}
      end
    end

    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :worker,
        restart: :permanent
      }
    end
  end

  @doc """
  Registers a custom chunk key encoder.

  ## Parameters

    * `name` - Atom identifier for the encoder
    * `encoder_module` - Module implementing the `ExZarr.ChunkKey.Encoder` behavior

  ## Examples

      defmodule MyEncoder do
        @behaviour ExZarr.ChunkKey.Encoder
        # ... implement callbacks ...
      end

      ExZarr.ChunkKey.register_encoder(:my_format, MyEncoder)
  """
  @spec register_encoder(atom(), module()) :: :ok
  def register_encoder(name, encoder_module) do
    Registry.register(name, encoder_module)
  end

  @doc """
  Encodes a chunk index using a named encoder.

  Falls back to version-based encoding if encoder not found.

  ## Parameters

    * `chunk_index` - Tuple of integers
    * `encoder_name` - Atom identifying the encoder, or version number (2 | 3)
    * `opts` - Options to pass to encoder

  ## Examples

      ExZarr.ChunkKey.encode_with({0, 1, 2}, :custom, [])
      "chunk_0_1_2"

      ExZarr.ChunkKey.encode_with({0, 1}, :v2, [])
      "0.1"
  """
  @spec encode_with(chunk_index(), atom() | version(), keyword()) :: chunk_key()
  def encode_with(chunk_index, encoder_name, opts \\ [])

  # Handle version numbers directly
  def encode_with(chunk_index, version, _opts) when is_integer(version) do
    encode(chunk_index, version)
  end

  # Handle named encoders
  def encode_with(chunk_index, encoder_name, opts) when is_atom(encoder_name) do
    case Registry.get(encoder_name) do
      {:ok, encoder_module} ->
        encoder_module.encode(chunk_index, opts)

      {:error, :not_found} ->
        # Fallback to v2 encoding
        encode(chunk_index, 2)
    end
  end

  @doc """
  Decodes a chunk key using a named encoder.

  Falls back to version-based decoding if encoder not found.

  ## Parameters

    * `chunk_key` - String representation
    * `encoder_name` - Atom identifying the encoder, or version number (2 | 3)
    * `opts` - Options to pass to encoder

  ## Examples

      ExZarr.ChunkKey.decode_with("chunk_0_1_2", :custom, [])
      {:ok, {0, 1, 2}}

      ExZarr.ChunkKey.decode_with("0.1", :v2, [])
      {:ok, {0, 1}}
  """
  @spec decode_with(chunk_key(), atom() | version(), keyword()) ::
          {:ok, chunk_index()} | {:error, term()}
  def decode_with(chunk_key, encoder_name, opts \\ [])

  # Handle version numbers directly
  def decode_with(chunk_key, version, _opts) when is_integer(version) do
    decode(chunk_key, version)
  end

  # Handle named encoders
  def decode_with(chunk_key, encoder_name, opts) when is_atom(encoder_name) do
    case Registry.get(encoder_name) do
      {:ok, encoder_module} ->
        encoder_module.decode(chunk_key, opts)

      {:error, :not_found} ->
        # Try v2 decoding as fallback
        decode(chunk_key, 2)
    end
  end
end
