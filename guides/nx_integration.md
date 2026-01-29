# Nx Integration Guide

This guide shows how to integrate ExZarr with Nx (Numerical Elixir) for numerical computing and machine learning workflows. ExZarr provides persistent storage for Nx tensors, enabling workflows that exceed available memory.

## Table of Contents

- [Nx and ExZarr Overview](#nx-and-exzarr-overview)
- [Persisting Nx Tensors to ExZarr](#persisting-nx-tensors-to-exzarr)
- [Reading ExZarr Arrays into Nx Tensors](#reading-exzarr-arrays-into-nx-tensors)
- [Dtype and Shape Mapping](#dtype-and-shape-mapping)
- [Batch Processing Patterns](#batch-processing-patterns)
- [ML Training/Inference Workflows](#ml-traininginference-workflows)
- [Performance Considerations](#performance-considerations)
- [Limitations and Workarounds](#limitations-and-workarounds)

## Nx and ExZarr Overview

### The Relationship

**Nx** (Numerical Elixir) provides NumPy-like functionality for Elixir:
- In-memory numerical computing
- Multi-dimensional tensors
- Vectorized operations
- Defn numerical definitions
- Backend support (CPU, GPU via EXLA)

**ExZarr** provides persistent, chunked array storage:
- Disk/cloud-backed arrays
- Chunked storage for large datasets
- Compression and codecs
- Zarr format compatibility

**Together**: Complete numerical computing stack for Elixir.

```
┌─────────────┐         ┌──────────────┐
│ Nx.Tensor   │ ←──────→│ ExZarr.Array │
│ (in-memory) │         │ (persistent) │
└─────────────┘         └──────────────┘
     Fast                    Durable
  Computation              Storage
```

### Conceptual Mapping

| Nx Concept | ExZarr Equivalent | Notes |
|------------|-------------------|-------|
| `Nx.Tensor` | `ExZarr.Array` | In-memory vs persistent |
| `Nx.shape(tensor)` | `array.metadata.shape` | Same tuple format |
| `Nx.type(tensor)` | `array.metadata.dtype` | Similar type systems |
| Nx operations | `get_slice/set_slice` | Explicit I/O vs automatic |
| `Nx.to_binary()` | Chunk binary | Different endianness/layout |

### Use Cases

**When to use ExZarr with Nx:**

1. **Datasets larger than memory**
   - Load chunks on-demand
   - Process incrementally

2. **Persist computation results**
   - Save intermediate results
   - Archive final outputs

3. **Share data between processes/machines**
   - Zarr format is language-agnostic
   - Compatible with Python zarr/NumPy

4. **Checkpoint ML training**
   - Save model weights
   - Store training datasets
   - Resume from checkpoints

5. **Scientific computing workflows**
   - Large-scale simulations
   - Climate/genomics data
   - Image processing pipelines

**When NOT to use ExZarr:**

- Pure in-memory computation (use Nx only)
- Small datasets (<100 MB) that fit in RAM
- Frequent random access (Zarr chunks have I/O overhead)

## Persisting Nx Tensors to ExZarr

### Basic Pattern (Full Tensor)

Write complete Nx tensor to Zarr array:

```elixir
# Create Nx tensor
tensor = Nx.iota({1000, 1000}, type: {:f, 64})

# Create ExZarr array with matching shape/dtype
{:ok, array} = ExZarr.create(
  shape: Nx.shape(tensor),              # {1000, 1000}
  chunks: {100, 100},                    # Choose appropriate chunk size
  dtype: nx_to_zarr_dtype(Nx.type(tensor)),  # :float64
  storage: :filesystem,
  path: "/data/my_tensor",
  compressor: %{id: "zstd", level: 3}
)

# Convert tensor to nested tuples (ExZarr format)
data = tensor
       |> Nx.to_list()
       |> nested_list_to_tuple()

# Write to array
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: Nx.shape(tensor)
)

IO.puts("Tensor persisted to #{array.storage.path}")
```

### Helper Module for Dtype Conversion

Reusable helper functions for converting between Nx and ExZarr types:

```elixir
defmodule ExZarr.Nx.Helpers do
  @moduledoc """
  Conversion utilities for Nx ↔ ExZarr integration.
  """

  # Nx type → ExZarr dtype
  def nx_to_zarr_dtype({:s, 8}), do: :int8
  def nx_to_zarr_dtype({:s, 16}), do: :int16
  def nx_to_zarr_dtype({:s, 32}), do: :int32
  def nx_to_zarr_dtype({:s, 64}), do: :int64
  def nx_to_zarr_dtype({:u, 8}), do: :uint8
  def nx_to_zarr_dtype({:u, 16}), do: :uint16
  def nx_to_zarr_dtype({:u, 32}), do: :uint32
  def nx_to_zarr_dtype({:u, 64}), do: :uint64
  def nx_to_zarr_dtype({:f, 32}), do: :float32
  def nx_to_zarr_dtype({:f, 64}), do: :float64

  # ExZarr dtype → Nx type
  def zarr_to_nx_dtype(:int8), do: {:s, 8}
  def zarr_to_nx_dtype(:int16), do: {:s, 16}
  def zarr_to_nx_dtype(:int32), do: {:s, 32}
  def zarr_to_nx_dtype(:int64), do: {:s, 64}
  def zarr_to_nx_dtype(:uint8), do: {:u, 8}
  def zarr_to_nx_dtype(:uint16), do: {:u, 16}
  def zarr_to_nx_dtype(:uint32), do: {:u, 32}
  def zarr_to_nx_dtype(:uint64), do: {:u, 64}
  def zarr_to_nx_dtype(:float32), do: {:f, 32}
  def zarr_to_nx_dtype(:float64), do: {:f, 64}

  # Nested list ↔ tuple conversion
  def nested_list_to_tuple(list) when is_list(list) do
    list
    |> Enum.map(&nested_list_to_tuple/1)
    |> List.to_tuple()
  end
  def nested_list_to_tuple(value), do: value

  def nested_tuple_to_list(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&nested_tuple_to_list/1)
  end
  def nested_tuple_to_list(value), do: value
end
```

### Chunked Write Pattern (Large Tensors)

For tensors that don't fit in memory, write chunk-by-chunk:

```elixir
defmodule ExZarr.Nx.ChunkedWrite do
  @moduledoc """
  Write large Nx tensors to Zarr arrays in chunks.
  Avoids loading entire tensor into memory.
  """

  alias ExZarr.Nx.Helpers

  @doc """
  Write tensor to array in chunks matching array's chunk size.

  ## Options
  - `:parallel` - Number of concurrent writes (default: 1)
  - `:show_progress` - Print progress updates (default: false)
  """
  def write_tensor_chunked(tensor, array, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, 1)
    show_progress = Keyword.get(opts, :show_progress, false)

    shape = Nx.shape(tensor)
    chunk_shape = array.metadata.chunks
    ndims = tuple_size(shape)

    # Calculate chunk indices
    chunk_ranges = calculate_chunk_ranges(shape, chunk_shape)
    total_chunks = length(chunk_ranges)

    if show_progress do
      IO.puts("Writing #{total_chunks} chunks...")
    end

    # Write chunks (parallel or sequential)
    chunk_ranges
    |> then(fn ranges ->
      if parallel > 1 do
        Task.async_stream(
          ranges,
          fn {start, stop} ->
            write_chunk(tensor, array, start, stop)
          end,
          max_concurrency: parallel,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)
      else
        Enum.map(ranges, fn {start, stop} ->
          write_chunk(tensor, array, start, stop)
        end)
      end
    end)

    if show_progress do
      IO.puts("Finished writing #{total_chunks} chunks")
    end

    :ok
  end

  defp write_chunk(tensor, array, start, stop) do
    # Calculate slice dimensions
    slice_starts = Tuple.to_list(start)
    slice_lengths = Tuple.to_list(stop)
                    |> Enum.zip(slice_starts)
                    |> Enum.map(fn {s, start} -> s - start end)

    # Extract chunk from tensor
    chunk_tensor = Nx.slice(tensor, slice_starts, slice_lengths)

    # Convert to nested tuples
    chunk_data = chunk_tensor
                 |> Nx.to_list()
                 |> Helpers.nested_list_to_tuple()

    # Write to Zarr
    :ok = ExZarr.Array.set_slice(array, chunk_data,
      start: start,
      stop: stop
    )
  end

  defp calculate_chunk_ranges(array_shape, chunk_shape) do
    # Generate all chunk coordinate ranges
    dimensions = Tuple.to_list(array_shape)
                |> Enum.zip(Tuple.to_list(chunk_shape))

    dimension_ranges = for {size, chunk_size} <- dimensions do
      for i <- 0..div(size - 1, chunk_size) do
        start = i * chunk_size
        stop = min(start + chunk_size, size)
        {start, stop}
      end
    end

    # Cartesian product of ranges
    cartesian_product(dimension_ranges)
  end

  defp cartesian_product([]), do: [[]]
  defp cartesian_product([head | tail]) do
    for item <- head, rest <- cartesian_product(tail) do
      [item | rest]
    end
  end
  |> Enum.map(fn ranges ->
    starts = Enum.map(ranges, fn {s, _} -> s end) |> List.to_tuple()
    stops = Enum.map(ranges, fn {_, e} -> e end) |> List.to_tuple()
    {starts, stops}
  end)
end
```

**Usage:**

```elixir
# Large tensor (10,000 × 10,000 = 800 MB as float64)
large_tensor = Nx.random_normal({10_000, 10_000})

{:ok, array} = ExZarr.create(
  shape: {10_000, 10_000},
  chunks: {1000, 1000},
  dtype: :float64,
  storage: :filesystem,
  path: "/data/large_tensor"
)

# Write in chunks (avoids loading entire 800 MB into memory)
ExZarr.Nx.ChunkedWrite.write_tensor_chunked(
  large_tensor,
  array,
  parallel: 4,
  show_progress: true
)
```

## Reading ExZarr Arrays into Nx Tensors

### Basic Pattern (Full Array)

Read complete array into Nx tensor:

```elixir
# Open ExZarr array
{:ok, array} = ExZarr.open(path: "/data/my_tensor")

# Read entire array
{:ok, data} = ExZarr.Array.get_slice(array,
  start: tuple_of_zeros(array.metadata.shape),
  stop: array.metadata.shape
)

# Convert to Nx tensor
tensor = data
         |> ExZarr.Nx.Helpers.nested_tuple_to_list()
         |> Nx.tensor(type: ExZarr.Nx.Helpers.zarr_to_nx_dtype(array.metadata.dtype))
         |> Nx.reshape(array.metadata.shape)

IO.inspect(tensor)

# Helper
defp tuple_of_zeros(shape) do
  tuple_size(shape)
  |> List.duplicate(0, _)
  |> List.to_tuple()
end
```

### Slice Reading (Memory-Efficient)

Read only needed portions:

```elixir
# Read 100×100 region from larger array
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {500, 500},
  stop: {600, 600}
)

# Convert to Nx tensor
slice_tensor = data
               |> ExZarr.Nx.Helpers.nested_tuple_to_list()
               |> Nx.tensor(type: {:f, 64})
               |> Nx.reshape({100, 100})

# Perform Nx operations on slice
result = slice_tensor
         |> Nx.add(10.0)
         |> Nx.multiply(2.0)
         |> Nx.mean()
         |> Nx.to_number()

IO.puts("Mean of slice after transform: #{result}")
```

### Streaming Pattern (Process Chunks Sequentially)

Process large arrays chunk-by-chunk without loading into memory:

```elixir
defmodule ExZarr.Nx.StreamProcessor do
  @moduledoc """
  Stream-process ExZarr arrays with Nx operations.
  Constant memory usage regardless of array size.
  """

  alias ExZarr.Nx.Helpers

  @doc """
  Process array in chunks, applying processor_fn to each.

  Returns list of results from each chunk.
  """
  def process_array_chunked(array, chunk_size, processor_fn, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, 1)

    {height, width} = array.metadata.shape
    {chunk_h, chunk_w} = chunk_size

    # Generate chunk coordinates
    chunk_coords = for i <- 0..div(height - 1, chunk_h),
                       j <- 0..div(width - 1, chunk_w) do
      start = {i * chunk_h, j * chunk_w}
      stop = {min((i + 1) * chunk_h, height), min((j + 1) * chunk_w, width)}
      {start, stop, {i, j}}
    end

    # Process chunks
    results = if parallel > 1 do
      Task.async_stream(
        chunk_coords,
        fn {start, stop, coords} ->
          process_chunk(array, start, stop, coords, processor_fn)
        end,
        max_concurrency: parallel,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
    else
      Enum.map(chunk_coords, fn {start, stop, coords} ->
        process_chunk(array, start, stop, coords, processor_fn)
      end)
    end

    {:ok, results}
  end

  defp process_chunk(array, start, stop, coords, processor_fn) do
    # Read chunk
    {:ok, data} = ExZarr.Array.get_slice(array, start: start, stop: stop)

    # Convert to tensor
    {start_h, start_w} = start
    {stop_h, stop_w} = stop
    shape = {stop_h - start_h, stop_w - start_w}

    tensor = data
             |> Helpers.nested_tuple_to_list()
             |> Nx.tensor(type: Helpers.zarr_to_nx_dtype(array.metadata.dtype))
             |> Nx.reshape(shape)

    # Process with user function
    processor_fn.(tensor, coords)
  end
end
```

**Usage:**

```elixir
{:ok, array} = ExZarr.open(path: "/data/large_array")

# Compute statistics for each chunk
{:ok, stats} = ExZarr.Nx.StreamProcessor.process_array_chunked(
  array,
  {100, 100},
  fn tensor, coords ->
    %{
      coords: coords,
      mean: Nx.mean(tensor) |> Nx.to_number(),
      std: Nx.standard_deviation(tensor) |> Nx.to_number(),
      max: Nx.reduce_max(tensor) |> Nx.to_number()
    }
  end,
  parallel: 4
)

IO.inspect(stats, label: "Per-chunk statistics")

# Aggregate global statistics
global_mean = Enum.map(stats, & &1.mean) |> Enum.sum() |> Kernel./(length(stats))
IO.puts("Global mean: #{global_mean}")
```

## Dtype and Shape Mapping

### Complete Compatibility Table

| Nx Type | ExZarr Dtype | Compatible | Size | Notes |
|---------|--------------|------------|------|-------|
| `{:s, 8}` | `:int8` | Yes | 1 byte | 8-bit signed integer |
| `{:s, 16}` | `:int16` | Yes | 2 bytes | 16-bit signed integer |
| `{:s, 32}` | `:int32` | Yes | 4 bytes | 32-bit signed integer |
| `{:s, 64}` | `:int64` | Yes | 8 bytes | 64-bit signed integer |
| `{:u, 8}` | `:uint8` | Yes | 1 byte | 8-bit unsigned integer |
| `{:u, 16}` | `:uint16` | Yes | 2 bytes | 16-bit unsigned integer |
| `{:u, 32}` | `:uint32` | Yes | 4 bytes | 32-bit unsigned integer |
| `{:u, 64}` | `:uint64` | Yes | 8 bytes | 64-bit unsigned integer |
| `{:f, 32}` | `:float32` | Yes | 4 bytes | 32-bit IEEE 754 float |
| `{:f, 64}` | `:float64` | Yes | 8 bytes | 64-bit IEEE 754 float |
| `{:bf, 16}` | N/A | **No** | - | BF16 not in Zarr spec |
| `{:f, 16}` | N/A | **No** | - | FP16 not in Zarr spec |
| `{:c, 64}` | N/A | **No** | - | Complex not supported |
| `{:c, 128}` | N/A | **No** | - | Complex not supported |

### Shape Conversion

Shapes are directly compatible:

```elixir
# Nx shape
nx_shape = {100, 50, 3}
Nx.shape(tensor)  # Returns tuple

# ExZarr shape
array.metadata.shape  # Also tuple: {100, 50, 3}

# No conversion needed!
{:ok, array} = ExZarr.create(
  shape: Nx.shape(tensor),  # Direct usage
  ...
)
```

Both use tuples with positive integers, so no conversion is required.

### Type Safety Helper

Ensure type compatibility before operations:

```elixir
defmodule ExZarr.Nx.TypeSafety do
  @doc """
  Verify Nx tensor is compatible with ExZarr array.
  Returns :ok or {:error, reason}.
  """
  def verify_compatible(tensor, array) do
    with :ok <- verify_shape(tensor, array),
         :ok <- verify_dtype(tensor, array) do
      :ok
    end
  end

  defp verify_shape(tensor, array) do
    if Nx.shape(tensor) == array.metadata.shape do
      :ok
    else
      {:error, {:shape_mismatch, Nx.shape(tensor), array.metadata.shape}}
    end
  end

  defp verify_dtype(tensor, array) do
    nx_type = Nx.type(tensor)
    expected_nx = ExZarr.Nx.Helpers.zarr_to_nx_dtype(array.metadata.dtype)

    if nx_type == expected_nx do
      :ok
    else
      {:error, {:dtype_mismatch, nx_type, expected_nx}}
    end
  end
end

# Usage
tensor = Nx.iota({100, 100}, type: {:f, 32})
{:ok, array} = ExZarr.open(path: "/data/array")

case ExZarr.Nx.TypeSafety.verify_compatible(tensor, array) do
  :ok ->
    # Safe to write
    data = ExZarr.Nx.Helpers.nested_list_to_tuple(Nx.to_list(tensor))
    ExZarr.Array.set_slice(array, data, ...)

  {:error, reason} ->
    IO.puts("Type mismatch: #{inspect(reason)}")
end
```

## Batch Processing Patterns

### Map-Reduce Over Chunks

Parallel map-reduce for array-wide computations:

```elixir
defmodule ExZarr.Nx.MapReduce do
  @moduledoc """
  Parallel map-reduce operations on Zarr arrays using Nx.
  """

  alias ExZarr.Nx.Helpers

  @doc """
  Apply map_fn to each chunk, then reduce results.

  ## Arguments
  - `array` - ExZarr array to process
  - `chunk_size` - Processing chunk size (may differ from array chunks)
  - `map_fn` - Function to apply to each tensor chunk
  - `reduce_fn` - Function to combine mapped results
  - `initial` - Initial accumulator value

  ## Options
  - `:parallel` - Concurrency level (default: 4)
  """
  def map_reduce(array, chunk_size, map_fn, reduce_fn, initial, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, 4)

    {height, width} = array.metadata.shape
    {chunk_h, chunk_w} = chunk_size

    # Generate chunk coordinates
    chunk_coords = for i <- 0..div(height - 1, chunk_h),
                       j <- 0..div(width - 1, chunk_w) do
      {i, j}
    end

    # Map phase (parallel)
    mapped = Task.async_stream(
      chunk_coords,
      fn {i, j} ->
        # Read chunk
        start_h = i * chunk_h
        start_w = j * chunk_w
        stop_h = min(start_h + chunk_h, height)
        stop_w = min(start_w + chunk_w, width)

        {:ok, data} = ExZarr.Array.get_slice(array,
          start: {start_h, start_w},
          stop: {stop_h, stop_w}
        )

        # Convert to tensor
        shape = {stop_h - start_h, stop_w - start_w}
        tensor = data
                 |> Helpers.nested_tuple_to_list()
                 |> Nx.tensor(type: Helpers.zarr_to_nx_dtype(array.metadata.dtype))
                 |> Nx.reshape(shape)

        # Apply map function
        map_fn.(tensor, {i, j})
      end,
      max_concurrency: parallel,
      timeout: 60_000
    )

    # Reduce phase (sequential)
    Enum.reduce(mapped, initial, fn {:ok, mapped_result}, acc ->
      reduce_fn.(mapped_result, acc)
    end)
  end
end
```

**Example: Compute global statistics**

```elixir
{:ok, array} = ExZarr.open(path: "/data/my_array")

# Map: compute per-chunk sum and count
# Reduce: aggregate into global statistics
result = ExZarr.Nx.MapReduce.map_reduce(
  array,
  {100, 100},
  # Map function: compute chunk stats
  fn tensor, _coords ->
    %{
      sum: Nx.sum(tensor) |> Nx.to_number(),
      count: Nx.size(tensor),
      min: Nx.reduce_min(tensor) |> Nx.to_number(),
      max: Nx.reduce_max(tensor) |> Nx.to_number()
    }
  end,
  # Reduce function: aggregate stats
  fn chunk_stats, acc ->
    %{
      sum: acc.sum + chunk_stats.sum,
      count: acc.count + chunk_stats.count,
      min: min(acc.min, chunk_stats.min),
      max: max(acc.max, chunk_stats.max)
    }
  end,
  # Initial accumulator
  %{sum: 0.0, count: 0, min: :infinity, max: :neg_infinity},
  parallel: 8
)

# Compute global mean
global_mean = result.sum / result.count

IO.puts("Global statistics:")
IO.puts("  Mean: #{global_mean}")
IO.puts("  Min: #{result.min}")
IO.puts("  Max: #{result.max}")
IO.puts("  Total elements: #{result.count}")
```

### Filter and Transform

Process and filter chunks based on criteria:

```elixir
defmodule ExZarr.Nx.Filter do
  @doc """
  Filter chunks by predicate and apply transformation.
  Returns list of {coords, transformed_tensor} for matching chunks.
  """
  def filter_and_transform(array, chunk_size, predicate_fn, transform_fn, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, 4)

    {:ok, results} = ExZarr.Nx.StreamProcessor.process_array_chunked(
      array,
      chunk_size,
      fn tensor, coords ->
        if predicate_fn.(tensor) do
          {:match, coords, transform_fn.(tensor)}
        else
          :skip
        end
      end,
      parallel: parallel
    )

    # Filter out :skip results
    Enum.filter(results, fn
      {:match, _, _} -> true
      :skip -> false
    end)
    |> Enum.map(fn {:match, coords, result} -> {coords, result} end)
  end
end

# Example: Find chunks with mean > threshold
{:ok, array} = ExZarr.open(path: "/data/my_array")

hot_chunks = ExZarr.Nx.Filter.filter_and_transform(
  array,
  {100, 100},
  # Predicate: mean > 100
  fn tensor -> Nx.mean(tensor) |> Nx.to_number() > 100.0 end,
  # Transform: normalize matching chunks
  fn tensor ->
    mean = Nx.mean(tensor)
    std = Nx.standard_deviation(tensor)
    Nx.divide(Nx.subtract(tensor, mean), std)
  end
)

IO.puts("Found #{length(hot_chunks)} chunks with mean > 100")
```

## ML Training/Inference Workflows

### Checkpoint Model Weights

Save and restore Nx tensors as Zarr arrays:

```elixir
defmodule ExZarr.Nx.MLCheckpoint do
  @moduledoc """
  Checkpoint and restore ML model weights using ExZarr.
  """

  alias ExZarr.Nx.Helpers

  @doc """
  Save model weights (map of layer_name => Nx.Tensor).

  ## Options
  - `:compressor` - Compression codec (default: zstd level 3)
  - `:storage` - Storage backend (default: :filesystem)
  """
  def save_model_weights(model_state, checkpoint_path, opts \\ []) do
    compressor = Keyword.get(opts, :compressor, %{id: "zstd", level: 3})
    storage = Keyword.get(opts, :storage, :filesystem)

    File.mkdir_p!(checkpoint_path)

    # Save each layer as separate array
    Enum.each(model_state, fn {layer_name, tensor} ->
      layer_path = Path.join(checkpoint_path, to_string(layer_name))

      {:ok, array} = ExZarr.create(
        shape: Nx.shape(tensor),
        chunks: chunk_shape_for_tensor(Nx.shape(tensor)),
        dtype: Helpers.nx_to_zarr_dtype(Nx.type(tensor)),
        storage: storage,
        path: layer_path,
        compressor: compressor
      )

      # Write tensor
      data = tensor |> Nx.to_list() |> Helpers.nested_list_to_tuple()
      start = List.duplicate(0, tuple_size(Nx.shape(tensor))) |> List.to_tuple()

      :ok = ExZarr.Array.set_slice(array, data,
        start: start,
        stop: Nx.shape(tensor)
      )
    end)

    # Save metadata
    metadata = %{
      layers: Map.keys(model_state) |> Enum.map(&to_string/1),
      shapes: Enum.map(model_state, fn {k, v} -> {k, Nx.shape(v)} end) |> Map.new(),
      saved_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    metadata_path = Path.join(checkpoint_path, "checkpoint_metadata.json")
    File.write!(metadata_path, Jason.encode!(metadata))

    {:ok, checkpoint_path}
  end

  @doc """
  Load model weights from checkpoint.
  Returns map of layer_name => Nx.Tensor.
  """
  def load_model_weights(checkpoint_path) do
    # Read metadata
    metadata_path = Path.join(checkpoint_path, "checkpoint_metadata.json")
    {:ok, metadata_json} = File.read(metadata_path)
    metadata = Jason.decode!(metadata_json, keys: :atoms)

    # Load each layer
    weights = for layer_name <- metadata.layers do
      layer_path = Path.join(checkpoint_path, layer_name)
      {:ok, array} = ExZarr.open(path: layer_path)

      # Read entire layer
      start = List.duplicate(0, tuple_size(array.metadata.shape)) |> List.to_tuple()
      {:ok, data} = ExZarr.Array.get_slice(array,
        start: start,
        stop: array.metadata.shape
      )

      # Convert to tensor
      tensor = data
               |> Helpers.nested_tuple_to_list()
               |> Nx.tensor(type: Helpers.zarr_to_nx_dtype(array.metadata.dtype))
               |> Nx.reshape(array.metadata.shape)

      {String.to_atom(layer_name), tensor}
    end

    {:ok, Map.new(weights), metadata}
  end

  # Heuristic for choosing chunk size based on tensor shape
  defp chunk_shape_for_tensor(shape) do
    # For weight matrices, use full chunks (they're usually small)
    shape
  end
end
```

**Usage:**

```elixir
# Save model
model_state = %{
  dense1_weights: Nx.random_normal({784, 128}),
  dense1_bias: Nx.random_normal({128}),
  dense2_weights: Nx.random_normal({128, 10}),
  dense2_bias: Nx.random_normal({10})
}

{:ok, path} = ExZarr.Nx.MLCheckpoint.save_model_weights(
  model_state,
  "/checkpoints/model_epoch_10"
)

IO.puts("Model saved to #{path}")

# Load model later
{:ok, restored_weights, metadata} = ExZarr.Nx.MLCheckpoint.load_model_weights(
  "/checkpoints/model_epoch_10"
)

IO.puts("Loaded model from #{metadata.saved_at}")
IO.inspect(Map.keys(restored_weights), label: "Layers")
```

### Mini-Batch Data Loading

Efficient batch loading for training:

```elixir
defmodule ExZarr.Nx.DataLoader do
  @moduledoc """
  Mini-batch data loader for ML training with ExZarr arrays.
  """

  alias ExZarr.Nx.Helpers

  @doc """
  Create stream of mini-batches from ExZarr array.

  ## Arguments
  - `array` - ExZarr array containing dataset [num_samples, ...]
  - `batch_size` - Number of samples per batch

  ## Options
  - `:shuffle` - Shuffle samples (default: false)
  - `:drop_last` - Drop incomplete final batch (default: false)
  """
  def create_batch_stream(array, batch_size, opts \\ []) do
    shuffle = Keyword.get(opts, :shuffle, false)
    drop_last = Keyword.get(opts, :drop_last, false)

    {num_samples, _} = array.metadata.shape
    num_batches = if drop_last do
      div(num_samples, batch_size)
    else
      ceil(num_samples / batch_size)
    end

    # Generate sample indices
    indices = 0..(num_samples - 1)
              |> Enum.to_list()
              |> then(fn idxs ->
                if shuffle, do: Enum.shuffle(idxs), else: idxs
              end)

    # Create stream of batches
    Stream.chunk_every(indices, batch_size, batch_size, if(drop_last, do: [], else: :discard))
    |> Stream.map(fn batch_indices ->
      load_batch(array, batch_indices)
    end)
  end

  defp load_batch(array, indices) do
    # For contiguous indices, use single slice (efficient)
    # For non-contiguous, read individual rows (slower)

    if contiguous?(indices) do
      load_contiguous_batch(array, indices)
    else
      load_scattered_batch(array, indices)
    end
  end

  defp contiguous?(indices) do
    indices
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> b == a + 1 end)
  end

  defp load_contiguous_batch(array, indices) do
    start_idx = List.first(indices)
    end_idx = List.last(indices) + 1
    batch_size = length(indices)

    {_num_samples, feature_dim} = array.metadata.shape

    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {start_idx, 0},
      stop: {end_idx, feature_dim}
    )

    data
    |> Helpers.nested_tuple_to_list()
    |> Nx.tensor(type: Helpers.zarr_to_nx_dtype(array.metadata.dtype))
    |> Nx.reshape({batch_size, feature_dim})
  end

  defp load_scattered_batch(array, indices) do
    # Read each row individually (slower, but works for shuffled data)
    {_num_samples, feature_dim} = array.metadata.shape

    rows = Enum.map(indices, fn idx ->
      {:ok, row_data} = ExZarr.Array.get_slice(array,
        start: {idx, 0},
        stop: {idx + 1, feature_dim}
      )

      row_data
      |> Helpers.nested_tuple_to_list()
    end)

    rows
    |> List.flatten()
    |> Nx.tensor(type: Helpers.zarr_to_nx_dtype(array.metadata.dtype))
    |> Nx.reshape({length(indices), feature_dim})
  end
end
```

**Training loop example:**

```elixir
# Setup training data
{:ok, X_train} = ExZarr.open(path: "/data/train_features")
{:ok, y_train} = ExZarr.open(path: "/data/train_labels")

# Create data loaders
X_batches = ExZarr.Nx.DataLoader.create_batch_stream(
  X_train,
  32,
  shuffle: true,
  drop_last: true
)

y_batches = ExZarr.Nx.DataLoader.create_batch_stream(
  y_train,
  32,
  shuffle: true,
  drop_last: true
)

# Training loop
initial_state = initialize_model()

trained_state = Stream.zip(X_batches, y_batches)
|> Enum.reduce(initial_state, fn {X_batch, y_batch}, state ->
  # Training step (pseudocode)
  {loss, gradients} = compute_loss_and_gradients(state, X_batch, y_batch)
  updated_state = apply_gradients(state, gradients, learning_rate: 0.001)

  if rem(state.step, 100) == 0 do
    IO.puts("Step #{state.step}, Loss: #{loss}")
  end

  updated_state
end)

IO.puts("Training complete")

# Save trained model
ExZarr.Nx.MLCheckpoint.save_model_weights(
  trained_state.weights,
  "/checkpoints/trained_model"
)
```

## Performance Considerations

### Conversion Overhead

Nx ↔ ExZarr conversion has measurable cost:

```elixir
# Benchmark conversion overhead
tensor = Nx.random_normal({1000, 1000})

# Measure: Tensor → Zarr format
{to_zarr_time, _} = :timer.tc(fn ->
  tensor |> Nx.to_list() |> ExZarr.Nx.Helpers.nested_list_to_tuple()
end)

IO.puts("Tensor → Zarr: #{to_zarr_time / 1000} ms")

# Measure: Zarr format → Tensor
zarr_data = tensor |> Nx.to_list() |> ExZarr.Nx.Helpers.nested_list_to_tuple()

{to_nx_time, _} = :timer.tc(fn ->
  zarr_data
  |> ExZarr.Nx.Helpers.nested_tuple_to_list()
  |> Nx.tensor()
  |> Nx.reshape({1000, 1000})
end)

IO.puts("Zarr → Tensor: #{to_nx_time / 1000} ms")
IO.puts("Round-trip overhead: #{(to_zarr_time + to_nx_time) / 1000} ms")
```

**Typical overhead** (1000×1000 float64 on M1 Max):
- Tensor → Zarr: ~50-100 ms
- Zarr → Tensor: ~30-50 ms
- **Total: ~80-150 ms for 8 MB**

**Mitigation strategies:**

1. **Work in larger chunks**: Amortize conversion cost over more data
2. **Cache converted tensors**: If reusing same data
3. **Process in Zarr-native format**: Avoid conversion for simple operations
4. **Use binary directly**: For custom operations, work with binaries

### Memory Efficiency

Nx tensors and ExZarr arrays use different memory:

```elixir
# ExZarr binary (stored in shared binary heap)
{:ok, array} = ExZarr.open(path: "/data/array")
{:ok, zarr_data} = ExZarr.Array.get_slice(array, ...)
# Memory: ~chunk_size (reference counted)

# Nx tensor (stored in process heap)
tensor = zarr_data |> to_nx_tensor()
# Memory: tensor_size + overhead (copied to process heap)
```

**Memory spikes during conversion:**

```
Initial: Zarr binary (~10 MB)
    ↓
Convert to nested list (~20 MB temporary)
    ↓
Create Nx tensor (~10 MB in process heap)
    ↓
Peak: ~40 MB (both binary and tensor in memory)
    ↓
After GC: ~10 MB (if binary freed)
```

**Best practices:**

- Process arrays in chunks (< 100 MB per chunk)
- Free intermediate data explicitly: `zarr_data = nil`
- Use streaming patterns for large arrays
- Monitor memory with `:erlang.memory(:total)`

### Optimization Tips

**1. Align chunk sizes:**

```elixir
# Good: Array chunks match processing chunks
{:ok, array} = ExZarr.create(
  chunks: {128, 128},  # Processing batch size: 128
  ...
)

# Each read loads exactly one batch (efficient)
```

**2. Pre-allocate tensors:**

```elixir
# Avoid repeated allocations in loops
template = Nx.template({100, 100}, {:f, 32})

for chunk <- chunks do
  # Reuse tensor shape
  tensor = chunk_data |> Nx.tensor(type: {:f, 32})
  process(tensor)
end
```

**3. Use Nx backends (EXLA):**

```elixir
# CPU backend (default)
Nx.mean(tensor)  # ~10 ms

# EXLA backend (GPU)
Nx.mean(tensor, backend: EXLA)  # ~1 ms (after warmup)

# For batch processing, EXLA can provide 10-100× speedup
```

**4. Batch conversions:**

```elixir
# Bad: Convert many small tensors
for small_chunk <- many_small_chunks do
  tensor = to_nx_tensor(small_chunk)  # Overhead per conversion
  process(tensor)
end

# Good: Combine first, then convert
combined = combine_chunks(many_small_chunks)
tensor = to_nx_tensor(combined)  # Single conversion
process(tensor)
```

## Limitations and Workarounds

### Limitation 1: No Zero-Copy Conversion

**Problem**: Zarr binary chunks → nested tuples → Nx tensor requires 2 copies.

**Impact**: Conversion overhead scales with data size.

**Workarounds:**

1. **Process in chunks**: Amortize overhead
   ```elixir
   # Process 100 MB array in 10 MB chunks (10× overhead reduction)
   ```

2. **Cache frequently accessed data**:
   ```elixir
   # Load once, reuse tensor multiple times
   tensor = load_and_convert(array)
   result1 = process_a(tensor)
   result2 = process_b(tensor)
   ```

3. **Skip conversion for simple ops**:
   ```elixir
   # If you just need sum, compute on binary directly
   # (custom binary parsing, faster than Nx conversion)
   ```

### Limitation 2: BF16/FP16 Not in Zarr Spec

**Problem**: Nx supports `{:bf, 16}` and `{:f, 16}`, but Zarr doesn't.

**Impact**: Can't directly store BF16/FP16 tensors (common in ML).

**Workarounds:**

1. **Store as FP32, quantize in memory**:
   ```elixir
   # Save FP32 to Zarr
   fp32_tensor = Nx.as_type(bf16_tensor, {:f, 32})
   save_to_zarr(fp32_tensor, array)

   # Load and quantize
   fp32_tensor = load_from_zarr(array)
   bf16_tensor = Nx.as_type(fp32_tensor, {:bf, 16})
   ```

2. **Use quantization codec**:
   ```elixir
   # Store as uint16 with scale/offset
   # (lossy, but saves storage)
   ```

3. **Store as uint16 bit pattern**:
   ```elixir
   # Interpret BF16 bits as uint16 (lossless)
   bf16_tensor = ...
   uint16_data = reinterpret_as_uint16(bf16_tensor)
   save_to_zarr(uint16_data, array)

   # Load and reinterpret
   uint16_data = load_from_zarr(array)
   bf16_tensor = reinterpret_as_bf16(uint16_data)
   ```

### Limitation 3: Complex Numbers Not Supported

**Problem**: Nx supports `{:c, 64}` and `{:c, 128}`, ExZarr doesn't.

**Impact**: Can't store complex-valued tensors directly.

**Workarounds:**

1. **Store real/imaginary as separate arrays**:
   ```elixir
   # Split complex tensor
   complex_tensor = Nx.tensor([Complex.new(1, 2), Complex.new(3, 4)])
   real_part = Nx.real(complex_tensor)
   imag_part = Nx.imag(complex_tensor)

   # Store separately
   save_to_zarr(real_part, "/data/signal_real")
   save_to_zarr(imag_part, "/data/signal_imag")

   # Load and reconstruct
   real = load_from_zarr("/data/signal_real")
   imag = load_from_zarr("/data/signal_imag")
   complex_tensor = Nx.complex(real, imag)
   ```

2. **Interleave real/imaginary**:
   ```elixir
   # Store as [..., 2] with last dim = [real, imag]
   # More compact but requires custom packing/unpacking
   ```

### Limitation 4: Ragged/Variable-Length Tensors

**Problem**: Zarr requires fixed-shape arrays, but some ML tasks use variable-length sequences.

**Impact**: Can't directly store variable-length data.

**Workarounds:**

1. **Pad to maximum size + store mask**:
   ```elixir
   # Pad sequences to max length
   max_len = 512
   padded = pad_sequences(sequences, max_len, padding_value: 0)

   # Store data and mask separately
   save_to_zarr(padded, "/data/sequences")
   save_to_zarr(mask, "/data/mask")  # 1 = valid, 0 = padding

   # Load and apply mask
   data = load_from_zarr("/data/sequences")
   mask = load_from_zarr("/data/mask")
   valid_data = Nx.select(mask, data, 0)
   ```

2. **Store as separate arrays**:
   ```elixir
   # Store each sequence as individual array
   for {seq, i} <- Enum.with_index(sequences) do
     save_to_zarr(seq, "/data/sequences/seq_#{i}")
   end
   ```

3. **Use variable-length encoding**:
   ```elixir
   # Store lengths + flattened data
   # (requires custom packing/unpacking logic)
   ```

### Limitation 5: Lazy Evaluation Mismatch

**Problem**: Nx uses lazy evaluation (defn), ExZarr is eager (explicit I/O).

**Impact**: Can't automatically fetch chunks as needed in defn.

**Workarounds:**

1. **Load data before defn**:
   ```elixir
   # Load from Zarr (eager)
   batch = load_batch_from_zarr(array, batch_idx)

   # Process with defn (lazy)
   result = MyModel.predict(batch)
   ```

2. **Wrap I/O in defn transform hooks** (advanced):
   ```elixir
   # Use Nx.Defn.Kernel hooks to integrate I/O
   # (complex, not recommended for most users)
   ```

## Summary

ExZarr and Nx integration provides:

**Strengths:**
- Persist large datasets beyond memory
- Efficient chunked processing
- ML checkpoint/restore workflows
- Python interoperability (zarr format)
- Complete dtype compatibility for numeric types

**Considerations:**
- Conversion overhead (mitigate with chunking)
- No zero-copy conversion (fundamental limitation)
- BF16/FP16 requires workarounds
- Complex numbers need separate arrays

**When to use:**
- Datasets > 1 GB
- ML training with checkpointing
- Incremental/streaming processing
- Cross-language data sharing

**When NOT to use:**
- Small datasets (< 100 MB) → use pure Nx
- Frequent random access → use in-memory tensors
- Real-time inference → pre-load data

For complete examples, see `/examples/nx_integration.exs`.

**Next steps:**
- Try the example script: `elixir examples/nx_integration.exs`
- Experiment with chunking strategies for your workload
- Measure conversion overhead with your data types
- Explore EXLA backend for GPU acceleration
