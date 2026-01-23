defmodule ExZarr do
  @moduledoc """
  ExZarr: Compressed, chunked, N-dimensional arrays for Elixir.

  ExZarr is an Elixir implementation of the Zarr storage format for chunked,
  compressed, N-dimensional arrays designed for use in parallel computing.

  ## Features

  - N-dimensional arrays with 10 data types (int8-64, uint8-64, float32/64)
  - Chunking along arbitrary dimensions for efficient I/O
  - Compression using Erlang zlib (with zstd/lz4 fallbacks)
  - Flexible storage backends (in-memory and filesystem)
  - Hierarchical organization with groups
  - Compatible with Zarr v2 specification
  - **Full interoperability with Python's zarr library**

  ## Quick Start

      # Create an array in memory
      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        storage: :memory
      )

      # Save array to filesystem
      :ok = ExZarr.save(array, path: "/tmp/my_array")

      # Open existing array
      {:ok, array} = ExZarr.open(path: "/tmp/my_array")

      # Load entire array into memory
      {:ok, data} = ExZarr.load(path: "/tmp/my_array")

  ## Interoperability with Python

  ExZarr implements the Zarr v2 specification, making it fully compatible with
  Python's zarr library. Arrays created by either implementation can be read
  by the other:

      # Create with ExZarr
      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib,
        storage: :filesystem,
        path: "/shared/data"
      )
      :ok = ExZarr.save(array, path: "/shared/data")

      # Read with Python
      # import zarr
      # z = zarr.open_array('/shared/data', mode='r')
      # print(z.shape)  # (1000, 1000)

  See `INTEROPERABILITY.md` for detailed examples and guidelines.

  ## Data Types

  Supported dtypes:
  - `:int8`, `:int16`, `:int32`, `:int64` - Signed integers
  - `:uint8`, `:uint16`, `:uint32`, `:uint64` - Unsigned integers
  - `:float32`, `:float64` - Floating point numbers

  ## Compression

  Available compressors:
  - `:none` - No compression
  - `:zlib` - Standard zlib compression (recommended for compatibility)
  - `:zstd` - Zstandard (falls back to zlib)
  - `:lz4` - LZ4 compression (falls back to zlib)

  ## Storage

  Two storage backends are available:
  - `:memory` - Fast, non-persistent in-memory storage
  - `:filesystem` - Persistent storage using Zarr v2 directory structure

  ## Testing

  ExZarr includes extensive tests including integration tests with zarr-python:

      # Run all tests
      mix test

      # Run Python integration tests
      mix test test/ex_zarr_python_integration_test.exs

  Integration tests verify bidirectional compatibility with Python across all
  data types, compression methods, and array dimensions.
  """

  alias ExZarr.Array

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

  - `:shape` - Tuple specifying array dimensions (required). Can be 1D to N-dimensional.
  - `:chunks` - Tuple specifying chunk dimensions (required). Must match shape dimensionality.
  - `:dtype` - Data type (default: `:float64`). One of: `:int8`, `:int16`, `:int32`, `:int64`,
    `:uint8`, `:uint16`, `:uint32`, `:uint64`, `:float32`, `:float64`.
  - `:compressor` - Compression codec (default: `:zstd`). One of: `:none`, `:zlib`, `:zstd`, `:lz4`.
  - `:storage` - Storage backend (default: `:memory`). Either `:memory` or `:filesystem`.
  - `:path` - Path for filesystem storage (required if `:storage` is `:filesystem`).
  - `:fill_value` - Fill value for uninitialized chunks (default: `0`).

  ## Examples

      # Create a 2D array in memory
      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64,
        compressor: :zlib
      )

      # Create a 1D array on filesystem
      {:ok, array} = ExZarr.create(
        shape: {10000},
        chunks: {1000},
        dtype: :int32,
        storage: :filesystem,
        path: "/tmp/my_data"
      )

      # Create a 3D array with custom fill value
      {:ok, array} = ExZarr.create(
        shape: {100, 200, 300},
        chunks: {10, 20, 30},
        dtype: :uint8,
        fill_value: 255
      )

  ## Returns

  - `{:ok, array}` on success
  - `{:error, :shape_required}` if shape is missing
  - `{:error, :chunks_required}` if chunks is missing
  - `{:error, :invalid_shape}` if shape is malformed
  - `{:error, :invalid_chunks}` if chunks is malformed or doesn't match shape
  """
  @spec create(keyword()) :: {:ok, Array.t()} | {:error, term()}
  def create(opts) do
    Array.create(opts)
  end

  @doc """
  Opens an existing Zarr array from storage.

  Reads the array metadata from the specified path and initializes
  the array structure. The array must have been previously created
  and saved using ExZarr or another Zarr v2 compatible implementation.

  ## Options

  - `:path` - Path to the array directory (required for filesystem storage)
  - `:storage` - Storage backend (default: `:filesystem`). Use `:filesystem` to open
    persisted arrays.

  ## Examples

      # Open array from filesystem
      {:ok, array} = ExZarr.open(path: "/tmp/my_array")

      # Open with explicit storage backend
      {:ok, array} = ExZarr.open(
        path: "/data/scientific_results",
        storage: :filesystem
      )

  ## Returns

  - `{:ok, array}` on success
  - `{:error, :path_not_found}` if the path does not exist
  - `{:error, :metadata_not_found}` if .zarray file is missing
  - `{:error, reason}` for other failures
  """
  @spec open(keyword()) :: {:ok, Array.t()} | {:error, term()}
  def open(opts) do
    Array.open(opts)
  end

  @doc """
  Saves an array to filesystem storage.

  Writes the array metadata to a `.zarray` file in the specified directory.
  The array structure and configuration will be persisted, allowing it to be
  reopened later with `open/1`. Note that chunk data is written separately
  when chunks are modified.

  ## Options

  - `:path` - Path where the array should be saved (required)

  ## Examples

      # Create and save an array
      {:ok, array} = ExZarr.create(
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float64
      )
      :ok = ExZarr.save(array, path: "/tmp/my_array")

      # Later, reopen the array
      {:ok, array} = ExZarr.open(path: "/tmp/my_array")

  ## Returns

  - `:ok` on success
  - `{:error, reason}` if the save operation fails
  """
  @spec save(Array.t(), keyword()) :: :ok | {:error, term()}
  def save(array, opts) do
    Array.save(array, opts)
  end

  @doc """
  Loads an entire array into memory as a binary.

  Opens the array from the specified path and reads all data into a single
  binary. This is convenient for loading complete arrays but may use significant
  memory for large arrays. The binary data is in row-major (C-order) format
  with elements encoded according to the array's dtype.

  ## Options

  - `:path` - Path to the array directory (required)
  - `:storage` - Storage backend (default: `:filesystem`)

  ## Examples

      # Load entire array
      {:ok, data} = ExZarr.load(path: "/tmp/my_array")

      # For a {10, 10} float64 array, data will be 800 bytes
      # (10 * 10 * 8 bytes per float64)

  ## Returns

  - `{:ok, binary}` containing all array data
  - `{:error, reason}` if the array cannot be opened or read

  ## Memory Usage

  Be cautious when loading large arrays. A `{1000, 1000}` array of `:float64`
  will require 8MB of memory (1000 * 1000 * 8 bytes).
  """
  @spec load(keyword()) :: {:ok, binary()} | {:error, term()}
  def load(opts) do
    with {:ok, array} <- open(opts) do
      Array.to_binary(array)
    end
  end
end
