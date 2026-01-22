defmodule ExZarr do
  @moduledoc """
  ExZarr: Compressed, chunked, N-dimensional arrays for Elixir.

  ExZarr is an Elixir implementation of the Zarr storage format for chunked,
  compressed, N-dimensional arrays designed for use in parallel computing.

  ## Features

  - N-dimensional arrays with various data types
  - Chunking along arbitrary dimensions
  - High-performance compression using Zig NIFs (zlib, zstd, lz4, blosc)
  - Flexible storage backends (memory, filesystem)
  - Concurrent read/write access
  - Hierarchical organization with groups

  ## Quick Start

      # Create an array
      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zstd
      )

      # Write data
      ExZarr.Array.set_slice(array, data, start: {0, 0})

      # Read data
      {:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  """

  alias ExZarr.{Array, Group, Storage}

  @type shape :: tuple()
  @type chunks :: tuple()
  @type dtype ::
          :int8
          | :int16
          | :int32
          | :int64
          | :uint8
          | :uint16
          | :uint32
          | :uint64
          | :float32
          | :float64
  @type compressor :: :none | :zlib | :zstd | :lz4 | :blosc

  @doc """
  Creates a new Zarr array with the specified configuration.

  ## Options

  - `:shape` - Tuple specifying array dimensions (required)
  - `:chunks` - Tuple specifying chunk dimensions (required)
  - `:dtype` - Data type (default: `:float64`)
  - `:compressor` - Compression codec (default: `:zstd`)
  - `:storage` - Storage backend (default: `:memory`)
  - `:path` - Path for filesystem storage
  - `:fill_value` - Fill value for uninitialized chunks

  ## Examples

      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64
      )
  """
  @spec create(keyword()) :: {:ok, Array.t()} | {:error, term()}
  def create(opts) do
    Array.create(opts)
  end

  @doc """
  Opens an existing Zarr array from storage.

  ## Examples

      {:ok, array} = ExZarr.open(path: "/path/to/array")
  """
  @spec open(keyword()) :: {:ok, Array.t()} | {:error, term()}
  def open(opts) do
    Array.open(opts)
  end

  @doc """
  Saves an array completely to storage.

  ## Examples

      :ok = ExZarr.save(array, path: "/path/to/array")
  """
  @spec save(Array.t(), keyword()) :: :ok | {:error, term()}
  def save(array, opts) do
    Array.save(array, opts)
  end

  @doc """
  Loads an entire array into memory.

  ## Examples

      {:ok, data} = ExZarr.load(path: "/path/to/array")
  """
  @spec load(keyword()) :: {:ok, binary()} | {:error, term()}
  def load(opts) do
    with {:ok, array} <- open(opts) do
      Array.to_binary(array)
    end
  end
end
