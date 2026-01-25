defmodule ExZarr.ChunkGrid do
  @moduledoc """
  Behavior for chunk grid implementations in Zarr v3.

  Chunk grids define how arrays are partitioned into chunks. The Zarr v3
  specification supports multiple chunk grid types:

  - **Regular**: All chunks have the same shape (except edge chunks)
  - **Irregular**: Chunks can have variable sizes
  - **Custom**: User-defined chunk grid patterns via extensions

  ## Behavior Callbacks

  Implementations must provide:

  - `init/1` - Initialize chunk grid state from configuration
  - `chunk_shape/2` - Get shape of a specific chunk by index
  - `chunk_count/1` - Calculate total number of chunks
  - `validate/2` - Validate chunk grid configuration against array shape

  ## Example

      defmodule MyChunkGrid do
        @behaviour ExZarr.ChunkGrid

        defstruct [:chunk_size]

        @impl true
        def init(config) do
          {:ok, %__MODULE__{chunk_size: config["chunk_size"]}}
        end

        @impl true
        def chunk_shape(_chunk_index, state) do
          {state.chunk_size, state.chunk_size}
        end

        @impl true
        def chunk_count(state) do
          # Calculate based on array shape
          100
        end

        @impl true
        def validate(config, array_shape) do
          # Validate configuration
          :ok
        end
      end

  ## Specification

  Zarr v3 Chunk Grids:
  https://zarr-specs.readthedocs.io/en/latest/v3/core/index.html#chunk-grids
  """

  alias ExZarr.ChunkGrid.{Irregular, Regular}

  @type chunk_index :: tuple()
  @type chunk_shape :: tuple()
  @type array_shape :: tuple()
  @type config :: map()
  @type state :: struct()

  @doc """
  Initialize chunk grid state from configuration.

  ## Parameters

    * `config` - Chunk grid configuration map

  ## Returns

    * `{:ok, state}` - Initialized chunk grid state
    * `{:error, reason}` - Initialization failure
  """
  @callback init(config()) :: {:ok, state()} | {:error, term()}

  @doc """
  Get the shape of a specific chunk.

  ## Parameters

    * `chunk_index` - Tuple of chunk coordinates (e.g., `{0, 1, 2}`)
    * `state` - Chunk grid state

  ## Returns

    * `chunk_shape` - Tuple representing chunk dimensions
  """
  @callback chunk_shape(chunk_index(), state()) :: chunk_shape()

  @doc """
  Calculate the total number of chunks in the grid.

  ## Parameters

    * `state` - Chunk grid state

  ## Returns

    * Non-negative integer representing total chunk count
  """
  @callback chunk_count(state()) :: non_neg_integer()

  @doc """
  Validate chunk grid configuration against array shape.

  ## Parameters

    * `config` - Chunk grid configuration map
    * `array_shape` - Shape of the array

  ## Returns

    * `:ok` - Configuration is valid
    * `{:error, reason}` - Validation failure
  """
  @callback validate(config(), array_shape()) :: :ok | {:error, term()}

  @doc """
  Parse and initialize a chunk grid from v3 metadata.

  Dispatches to the appropriate chunk grid implementation based on the `name` field.

  ## Parameters

    * `chunk_grid_config` - Map with `"name"` and `"configuration"` keys

  ## Returns

    * `{:ok, {module, state}}` - Initialized chunk grid with module and state
    * `{:error, reason}` - Parse or initialization failure

  ## Examples

      iex> config = %{
      ...>   "name" => "regular",
      ...>   "configuration" => %{"chunk_shape" => [10, 20, 30]}
      ...> }
      iex> {:ok, {module, _state}} = ExZarr.ChunkGrid.parse(config)
      iex> module
      ExZarr.ChunkGrid.Regular

  """
  @spec parse(map()) :: {:ok, {module(), state()}} | {:error, term()}
  def parse(%{"name" => "regular", "configuration" => config}) do
    case Regular.init(config) do
      {:ok, state} -> {:ok, {Regular, state}}
      error -> error
    end
  end

  def parse(%{"name" => "irregular", "configuration" => config}) do
    case Irregular.init(config) do
      {:ok, state} -> {:ok, {Irregular, state}}
      error -> error
    end
  end

  def parse(%{"name" => name}) do
    {:error, {:unknown_chunk_grid, name}}
  end

  def parse(_) do
    {:error, :invalid_chunk_grid_config}
  end

  @doc """
  Validate a chunk grid configuration.

  ## Parameters

    * `chunk_grid_config` - Map with `"name"` and `"configuration"` keys
    * `array_shape` - Shape of the array

  ## Returns

    * `:ok` - Configuration is valid
    * `{:error, reason}` - Validation failure
  """
  @spec validate(map(), array_shape()) :: :ok | {:error, term()}
  def validate(%{"name" => "regular", "configuration" => config}, array_shape) do
    Regular.validate(config, array_shape)
  end

  def validate(%{"name" => "irregular", "configuration" => config}, array_shape) do
    Irregular.validate(config, array_shape)
  end

  def validate(%{"name" => name}, _array_shape) do
    {:error, {:unknown_chunk_grid, name}}
  end

  def validate(_, _) do
    {:error, :invalid_chunk_grid_config}
  end
end
