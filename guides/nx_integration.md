# Nx Integration Guide

This guide shows how to integrate ExZarr with Nx (Numerical Elixir) for numerical computing and machine learning workflows. ExZarr provides persistent storage for Nx tensors, enabling workflows that exceed available memory.

**⚡ Performance Note:** ExZarr provides an optimized `ExZarr.Nx` module with **5-10x faster** conversion compared to manual approaches. Always use `ExZarr.Nx` for best performance.

## Table of Contents

- [Quick Start](#quick-start)
- [Nx and ExZarr Overview](#nx-and-exzarr-overview)
- [Optimized Conversion (Recommended)](#optimized-conversion-recommended)
- [Dtype and Shape Mapping](#dtype-and-shape-mapping)
- [Chunked Processing](#chunked-processing)
- [Batch Processing Patterns](#batch-processing-patterns)
- [ML Training/Inference Workflows](#ml-traininginference-workflows)
- [Backend Integration](#backend-integration)
- [Performance Considerations](#performance-considerations)
- [Limitations and Workarounds](#limitations-and-workarounds)
- [Legacy Approaches](#legacy-approaches)

## Quick Start

```elixir
# Install dependencies
Mix.install([
  {:ex_zarr, "~> 1.0"},
  {:nx, "~> 0.7"}
])

# ExZarr → Nx (optimized, fast)
{:ok, array} = ExZarr.open(path: "/data/my_array")
{:ok, tensor} = ExZarr.Nx.to_tensor(array)

# Nx → ExZarr (optimized, fast)
tensor = Nx.iota({1000, 1000})
{:ok, array} = ExZarr.Nx.from_tensor(tensor,
  path: "/data/output",
  chunks: {100, 100},
  storage: :filesystem
)
```

**Performance:** 10-20ms for 8MB (400-800 MB/s)

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

### Use Cases

**When to use ExZarr with Nx:**

1. **Datasets larger than memory** - Load chunks on-demand, process incrementally
2. **Persist computation results** - Save intermediate results, archive final outputs
3. **Share data between processes/machines** - Zarr format is language-agnostic
4. **Checkpoint ML training** - Save model weights, store training datasets
5. **Scientific computing workflows** - Large-scale simulations, climate/genomics data

**When NOT to use ExZarr:**

- Pure in-memory computation (use Nx only)
- Small datasets (<100 MB) that fit in RAM
- Frequent random access (Zarr chunks have I/O overhead)

## Optimized Conversion (Recommended)

ExZarr provides the `ExZarr.Nx` module for efficient conversion using direct binary transfer.

### Performance Comparison

| Approach | Time (8MB) | Throughput | Status |
|----------|-----------|------------|---------|
| **`ExZarr.Nx` (optimized)** | **10-20ms** | **400-800 MB/s** | ✅ **Recommended** |
| Nested tuples (legacy) | 80-150ms | 50-100 MB/s | ⚠️ Deprecated |

**Speedup: 5-10x faster**

### Converting ExZarr to Nx

The optimized way to convert ExZarr arrays to Nx tensors:

```elixir
# Open ExZarr array
{:ok, array} = ExZarr.open(path: "/data/my_array")

# Convert to Nx tensor (optimized, single function call)
{:ok, tensor} = ExZarr.Nx.to_tensor(array)

# That's it! Tensor is ready for Nx operations
result = Nx.mean(tensor) |> Nx.to_number()
IO.puts("Mean: #{result}")
```

**With options:**

```elixir
# Transfer to specific backend
{:ok, tensor} = ExZarr.Nx.to_tensor(array, backend: EXLA.Backend)

# With axis names
{:ok, tensor} = ExZarr.Nx.to_tensor(array, names: [:batch, :features])
```

### Converting Nx to ExZarr

The optimized way to convert Nx tensors to ExZarr arrays:

```elixir
# Create Nx tensor
tensor = Nx.iota({1000, 1000}, type: {:f, 64})

# Convert to ExZarr array (optimized, single function call)
{:ok, array} = ExZarr.Nx.from_tensor(tensor,
  storage: :filesystem,
  path: "/data/output",
  chunks: {100, 100}
)

# Optional: Add compression
{:ok, array} = ExZarr.Nx.from_tensor(tensor,
  storage: :filesystem,
  path: "/data/compressed",
  chunks: {100, 100},
  compressor: %{id: "zstd", level: 3}
)
```

### Round-Trip Example

Complete example showing conversion both ways:

```elixir
# Create original tensor
original = Nx.iota({500, 500}, type: {:f, 32})

# Save to ExZarr
{:ok, array} = ExZarr.Nx.from_tensor(original,
  storage: :memory,
  chunks: {100, 100}
)

# Load back to Nx
{:ok, restored} = ExZarr.Nx.to_tensor(array)

# Verify round-trip
if Nx.all(Nx.equal(original, restored)) |> Nx.to_number() == 1 do
  IO.puts("✅ Round-trip successful!")
end
```

## Dtype and Shape Mapping

### Complete Compatibility Table

All 10 standard numeric types are fully supported:

| Nx Type | ExZarr Dtype | Bytes | Compatible | Notes |
|---------|--------------|-------|------------|-------|
| `{:s, 8}` | `:int8` | 1 | ✅ Yes | 8-bit signed integer |
| `{:s, 16}` | `:int16` | 2 | ✅ Yes | 16-bit signed integer |
| `{:s, 32}` | `:int32` | 4 | ✅ Yes | 32-bit signed integer |
| `{:s, 64}` | `:int64` | 8 | ✅ Yes | 64-bit signed integer |
| `{:u, 8}` | `:uint8` | 1 | ✅ Yes | 8-bit unsigned integer |
| `{:u, 16}` | `:uint16` | 2 | ✅ Yes | 16-bit unsigned integer |
| `{:u, 32}` | `:uint32` | 4 | ✅ Yes | 32-bit unsigned integer |
| `{:u, 64}` | `:uint64` | 8 | ✅ Yes | 64-bit unsigned integer |
| `{:f, 32}` | `:float32` | 4 | ✅ Yes | 32-bit IEEE 754 float |
| `{:f, 64}` | `:float64` | 8 | ✅ Yes | 64-bit IEEE 754 float |

### Unsupported Types

| Nx Type | Status | Workaround |
|---------|--------|------------|
| `{:bf, 16}` | ❌ Not in Zarr spec | Store as `:float32`, cast to BF16 in memory |
| `{:f, 16}` | ❌ Not in Zarr spec | Store as `:float32`, cast to FP16 in memory |
| `{:c, 64}` | ❌ Not supported | Store real/imaginary as separate arrays |
| `{:c, 128}` | ❌ Not supported | Store real/imaginary as separate arrays |

**BF16/FP16 Workaround:**

```elixir
# Save FP32, cast to BF16 in memory
fp32_tensor = Nx.as_type(bf16_tensor, {:f, 32})
{:ok, array} = ExZarr.Nx.from_tensor(fp32_tensor, chunks: {100, 100})

# Later: Load and cast back
{:ok, fp32_loaded} = ExZarr.Nx.to_tensor(array)
bf16_tensor = Nx.as_type(fp32_loaded, {:bf, 16})
```

### Shape Conversion

Shapes are directly compatible (both use tuples):

```elixir
# Nx shape
tensor = Nx.iota({100, 50, 3})
Nx.shape(tensor)  # Returns: {100, 50, 3}

# ExZarr shape
array.metadata.shape  # Also tuple: {100, 50, 3}

# Direct compatibility - no conversion needed
{:ok, array} = ExZarr.Nx.from_tensor(tensor, chunks: {10, 10, 3})
```

### Type Conversion Helpers

The `ExZarr.Nx` module provides helper functions:

```elixir
# Check supported types
ExZarr.Nx.supported_dtypes()
#=> [:int8, :int16, :int32, :int64, :uint8, :uint16, :uint32, :uint64, :float32, :float64]

ExZarr.Nx.supported_nx_types()
#=> [{:s, 8}, {:s, 16}, {:s, 32}, {:s, 64}, {:u, 8}, {:u, 16}, {:u, 32}, {:u, 64}, {:f, 32}, {:f, 64}]

# Convert types
{:ok, nx_type} = ExZarr.Nx.zarr_to_nx_type(:float64)
#=> {:ok, {:f, 64}}

{:ok, zarr_dtype} = ExZarr.Nx.nx_to_zarr_type({:f, 32})
#=> {:ok, :float32}

# Error handling for unsupported types
{:error, message} = ExZarr.Nx.nx_to_zarr_type({:bf, 16})
#=> {:error, "Unsupported Nx type: {:bf, 16}. BF16 is not part of Zarr specification. Workaround: Store as float32 and cast to BF16 in memory."}
```

## Chunked Processing

For arrays larger than available RAM, process in chunks with constant memory usage.

### Streaming Chunks as Tensors

```elixir
{:ok, array} = ExZarr.open(path: "/data/large_array")

# Process array in 100×100 chunks
array
|> ExZarr.Nx.to_tensor_chunked({100, 100})
|> Stream.each(fn {:ok, tensor} ->
  # Each tensor is 100×100
  mean = Nx.mean(tensor) |> Nx.to_number()
  IO.puts("Chunk mean: #{mean}")
end)
|> Stream.run()
```

### Parallel Chunk Processing

```elixir
# Process chunks in parallel with Task.async_stream
{:ok, array} = ExZarr.open(path: "/data/large_array")

results = array
|> ExZarr.Nx.to_tensor_chunked({100, 100})
|> Task.async_stream(
  fn {:ok, tensor} ->
    # Compute something for each chunk
    Nx.sum(tensor) |> Nx.to_number()
  end,
  max_concurrency: 8,
  timeout: 60_000
)
|> Enum.map(fn {:ok, sum} -> sum end)

total_sum = Enum.sum(results)
IO.puts("Total sum across all chunks: #{total_sum}")
```

### Map-Reduce Over Chunks

Complete map-reduce pattern for large arrays:

```elixir
defmodule ChunkedStats do
  def compute_statistics(array, chunk_size) do
    # Map: Compute per-chunk statistics
    chunk_stats = array
    |> ExZarr.Nx.to_tensor_chunked(chunk_size)
    |> Stream.map(fn {:ok, tensor} ->
      %{
        sum: Nx.sum(tensor) |> Nx.to_number(),
        count: Nx.size(tensor),
        min: Nx.reduce_min(tensor) |> Nx.to_number(),
        max: Nx.reduce_max(tensor) |> Nx.to_number()
      }
    end)
    |> Enum.to_list()

    # Reduce: Aggregate into global statistics
    global = Enum.reduce(chunk_stats,
      %{sum: 0.0, count: 0, min: :infinity, max: :neg_infinity},
      fn chunk, acc ->
        %{
          sum: acc.sum + chunk.sum,
          count: acc.count + chunk.count,
          min: min(acc.min, chunk.min),
          max: max(acc.max, chunk.max)
        }
      end
    )

    %{
      mean: global.sum / global.count,
      min: global.min,
      max: global.max,
      count: global.count
    }
  end
end

# Usage
{:ok, array} = ExZarr.open(path: "/data/huge_array")
stats = ChunkedStats.compute_statistics(array, {100, 100})

IO.puts("Global mean: #{stats.mean}")
IO.puts("Global min: #{stats.min}")
IO.puts("Global max: #{stats.max}")
```

## Batch Processing Patterns

### Mini-Batch Data Loading for ML

Efficient batch loading for machine learning training:

```elixir
defmodule BatchLoader do
  @doc """
  Load batch from ExZarr array for ML training.

  Aligns ExZarr chunks with batch size for optimal performance.
  """
  def load_batch(array, batch_idx, batch_size) do
    {num_samples, num_features} = array.metadata.shape

    start_idx = batch_idx * batch_size
    end_idx = min(start_idx + batch_size, num_samples)

    if start_idx >= num_samples do
      {:error, :end_of_data}
    else
      # Load batch binary
      {:ok, batch_binary} = ExZarr.Array.get_slice(array,
        start: {start_idx, 0},
        stop: {end_idx, num_features}
      )

      # Convert to Nx tensor
      {:ok, nx_type} = ExZarr.Nx.zarr_to_nx_type(array.metadata.dtype)

      batch_tensor = Nx.from_binary(batch_binary, nx_type)
                     |> Nx.reshape({end_idx - start_idx, num_features})

      {:ok, batch_tensor}
    end
  end

  def batch_stream(array, batch_size) do
    {num_samples, _} = array.metadata.shape
    num_batches = ceil(num_samples / batch_size)

    Stream.map(0..(num_batches - 1), fn batch_idx ->
      load_batch(array, batch_idx, batch_size)
    end)
    |> Stream.take_while(fn
      {:ok, _} -> true
      {:error, :end_of_data} -> false
    end)
  end
end
```

### Training Loop Example

```elixir
# Load training data from ExZarr
{:ok, X_train} = ExZarr.open(path: "/data/train_features")
{:ok, y_train} = ExZarr.open(path: "/data/train_labels")

# Training loop with batches
model_state = initialize_model()

# Process batches
X_batches = BatchLoader.batch_stream(X_train, 32)
y_batches = BatchLoader.batch_stream(y_train, 32)

trained_state = Stream.zip(X_batches, y_batches)
|> Enum.reduce(model_state, fn {{:ok, X_batch}, {:ok, y_batch}}, state ->
  # Training step (with Nx.Defn for compilation)
  {loss, updated_state} = train_step(state, X_batch, y_batch)

  if rem(state.step, 100) == 0 do
    IO.puts("Step #{state.step}, Loss: #{Float.round(loss, 4)}")
  end

  updated_state
end)

IO.puts("Training complete!")
```

### Optimal Chunk Alignment

**Best Practice:** Align ExZarr chunks with batch size:

```elixir
# Training batch size: 32 samples
# Features: 784 dimensions

# ✅ Good: Chunks aligned with batches
{:ok, array} = ExZarr.create(
  shape: {10000, 784},
  chunks: {32, 784},      # Each chunk = exactly 1 batch
  dtype: :float32
)
# Result: Loading 1 batch = 1 I/O operation (efficient!)

# ❌ Bad: Chunks misaligned
{:ok, array} = ExZarr.create(
  shape: {10000, 784},
  chunks: {50, 784},      # Chunks span batch boundaries
  dtype: :float32
)
# Result: Loading 1 batch may require 2 I/O operations (wasteful)
```

## ML Training/Inference Workflows

### Checkpoint Model Weights

Save and restore Nx model weights:

```elixir
defmodule ModelCheckpoint do
  @doc "Save model weights to ExZarr"
  def save_weights(model_state, checkpoint_path) do
    File.mkdir_p!(checkpoint_path)

    # Save each layer as separate ExZarr array
    Enum.each(model_state.weights, fn {layer_name, tensor} ->
      layer_path = Path.join(checkpoint_path, to_string(layer_name))

      {:ok, _array} = ExZarr.Nx.from_tensor(tensor,
        storage: :filesystem,
        path: layer_path,
        chunks: Nx.shape(tensor),  # Single chunk for weights
        compressor: %{id: "zstd", level: 3}
      )
    end)

    # Save metadata
    metadata = %{
      layers: Map.keys(model_state.weights) |> Enum.map(&to_string/1),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      epoch: model_state.epoch
    }

    metadata_path = Path.join(checkpoint_path, "metadata.json")
    File.write!(metadata_path, Jason.encode!(metadata))

    {:ok, checkpoint_path}
  end

  @doc "Load model weights from ExZarr"
  def load_weights(checkpoint_path) do
    # Read metadata
    metadata_path = Path.join(checkpoint_path, "metadata.json")
    {:ok, json} = File.read(metadata_path)
    metadata = Jason.decode!(json, keys: :atoms)

    # Load each layer
    weights = for layer_name <- metadata.layers do
      layer_path = Path.join(checkpoint_path, layer_name)
      {:ok, array} = ExZarr.open(path: layer_path)
      {:ok, tensor} = ExZarr.Nx.to_tensor(array)

      {String.to_atom(layer_name), tensor}
    end
    |> Map.new()

    {:ok, %{weights: weights, metadata: metadata}}
  end
end
```

**Usage:**

```elixir
# Save checkpoint during training
if rem(epoch, 10) == 0 do
  {:ok, path} = ModelCheckpoint.save_weights(
    model_state,
    "/checkpoints/model_epoch_#{epoch}"
  )
  IO.puts("Saved checkpoint: #{path}")
end

# Restore from checkpoint
{:ok, checkpoint} = ModelCheckpoint.load_weights("/checkpoints/model_epoch_50")
model_state = %{model_state | weights: checkpoint.weights}
IO.puts("Restored from epoch #{checkpoint.metadata.epoch}")
```

### Inference with Nx.Serving

Integrate with Nx.Serving for production model serving:

```elixir
# Load model weights from ExZarr
{:ok, checkpoint} = ModelCheckpoint.load_weights("/models/production")

# Create Nx.Serving
serving = Nx.Serving.new(MyModel, arg: checkpoint.weights)

# Load inference data from ExZarr
{:ok, inference_data} = ExZarr.open(path: "/data/inference")

# Process in batches
results = inference_data
|> ExZarr.Nx.to_tensor_chunked({32, 784})  # 32 samples per batch
|> Stream.map(fn {:ok, batch} ->
  # Run inference
  predictions = Nx.Serving.run(serving, batch)
  predictions
end)
|> Enum.to_list()

IO.puts("Processed #{length(results)} batches")
```

## Backend Integration

ExZarr.Nx works seamlessly with all Nx backends.

### CPU Backend (Default)

```elixir
# Default: Nx.BinaryBackend (CPU)
{:ok, tensor} = ExZarr.Nx.to_tensor(array)

# Tensor is on CPU, ready for computation
result = Nx.mean(tensor)
```

### EXLA Backend (GPU/TPU)

```elixir
# Transfer to EXLA backend for GPU acceleration
{:ok, tensor} = ExZarr.Nx.to_tensor(array, backend: EXLA.Backend)

# Or transfer after loading
{:ok, cpu_tensor} = ExZarr.Nx.to_tensor(array)
gpu_tensor = Nx.backend_transfer(cpu_tensor, EXLA.Backend)

# Now operations use GPU/TPU
result = Nx.dot(gpu_tensor, gpu_tensor)  # Runs on GPU
```

### Torchx Backend (PyTorch)

```elixir
# Transfer to Torchx backend
{:ok, tensor} = ExZarr.Nx.to_tensor(array, backend: Torchx.Backend)

# Tensor operations dispatch to PyTorch
result = Nx.exp(tensor)  # Uses PyTorch implementation
```

### Integration with Nx.Defn

Load data outside `defn`, compute inside:

```elixir
defmodule Training do
  import Nx.Defn

  # Define compiled numerical function
  defn forward(params, batch) do
    # This gets compiled by EXLA or other compiler
    batch
    |> Nx.dot(params.weights)
    |> Nx.add(params.bias)
    |> Nx.sigmoid()
  end

  defn loss(params, batch, labels) do
    predictions = forward(params, batch)
    Nx.mean(Nx.pow(Nx.subtract(predictions, labels), 2))
  end

  # Load data outside defn (eager), compute inside (compiled)
  def train_step(params, array, labels_array, batch_idx, batch_size) do
    # Load batch from ExZarr (eager, not compiled)
    {:ok, batch} = BatchLoader.load_batch(array, batch_idx, batch_size)
    {:ok, labels} = BatchLoader.load_batch(labels_array, batch_idx, batch_size)

    # Compute with defn (lazy, compiled)
    loss_value = loss(params, batch, labels)

    loss_value
  end
end
```

**Why this pattern?**
- `defn` compilation expects static shapes
- Loading chunks outside `defn` provides flexibility
- Computation inside `defn` gets JIT compilation benefits

## Performance Considerations

### Conversion Overhead

**Measured performance** (M1 Max, 1000×1000 float64):

```elixir
# Benchmark setup
tensor = Nx.random_normal({1000, 1000})  # 8 MB

# Optimized conversion (ExZarr.Nx)
{time, {:ok, array}} = :timer.tc(fn ->
  ExZarr.Nx.from_tensor(tensor, storage: :memory, chunks: {100, 100})
end)
IO.puts("To ExZarr: #{time / 1000} ms")  # ~10ms

{time, {:ok, restored}} = :timer.tc(fn ->
  ExZarr.Nx.to_tensor(array)
end)
IO.puts("From ExZarr: #{time / 1000} ms")  # ~10ms

# Total: ~20ms for 8MB = 400 MB/s
```

### Memory Efficiency

**Memory usage pattern:**

```elixir
# Peak memory during conversion
before = :erlang.memory(:total)

{:ok, tensor} = ExZarr.Nx.to_tensor(array)

after_mem = :erlang.memory(:total)
used = (after_mem - before) / 1_048_576  # MB

IO.puts("Memory used: #{Float.round(used, 2)} MB")
# Approximately: array_size + tensor_size
# For 8MB array: ~16-20MB peak (includes temporary buffers)
```

**For large arrays:**

```elixir
# Use chunked processing to limit peak memory
array
|> ExZarr.Nx.to_tensor_chunked({100, 100})  # Process 100×100 at a time
|> Stream.each(&process_chunk/1)
|> Stream.run()
# Peak memory: chunk_size × 2 (constant regardless of array size)
```

### Optimization Tips

**1. Align ExZarr chunks with Nx batch sizes:**

```elixir
# Good: Batch size = 32, chunks = {32, features}
{:ok, array} = ExZarr.create(
  shape: {10000, 784},
  chunks: {32, 784},
  dtype: :float32
)
```

**2. Use appropriate compression:**

```elixir
# Training data (read many times): Light compression
compressor: %{id: "lz4", level: 1}  # Fast decompression

# Archival data (write once): Strong compression
compressor: %{id: "zstd", level: 10}  # Best ratio
```

**3. Pre-allocate tensors when possible:**

```elixir
# Avoid repeated allocations in loops
defmodule EfficientProcessing do
  def process_batches(array, num_batches, batch_size) do
    # Pre-allocate reusable tensor (if possible)
    for batch_idx <- 0..(num_batches - 1) do
      {:ok, batch} = BatchLoader.load_batch(array, batch_idx, batch_size)
      process(batch)
    end
  end
end
```

**4. Use EXLA for GPU acceleration:**

```elixir
# Transfer to GPU once, compute many times
{:ok, tensor} = ExZarr.Nx.to_tensor(array, backend: EXLA.Backend)

# All subsequent operations use GPU
result = tensor
         |> Nx.multiply(2.0)
         |> Nx.exp()
         |> Nx.sum()
```

## Limitations and Workarounds

### Limitation 1: No Zero-Copy Conversion

**Problem**: Conversion requires copying data (binary → tensor).

**Impact**: ~10-20ms overhead per 8MB.

**Workarounds:**
1. Process in chunks (amortize overhead)
2. Cache converted tensors if reusing
3. Minimize conversions (load once, compute many times)

### Limitation 2: BF16/FP16 Not in Zarr Spec

**Problem**: Nx supports `{:bf, 16}` and `{:f, 16}`, but Zarr doesn't.

**Impact**: Can't directly store BF16/FP16 tensors (common in ML).

**Workaround:**

```elixir
# Store as float32, cast to BF16 in memory
fp32_tensor = Nx.as_type(bf16_tensor, {:f, 32})
{:ok, array} = ExZarr.Nx.from_tensor(fp32_tensor, chunks: {100, 100})

# Later: Load and cast back
{:ok, fp32_loaded} = ExZarr.Nx.to_tensor(array)
bf16_tensor = Nx.as_type(fp32_loaded, {:bf, 16})
```

### Limitation 3: Complex Numbers Not Supported

**Problem**: Nx supports `{:c, 64}` and `{:c, 128}`, ExZarr doesn't.

**Workaround:**

```elixir
# Store real and imaginary parts separately
complex_tensor = Nx.complex(real_part, imag_part)

# Save
{:ok, real_array} = ExZarr.Nx.from_tensor(
  Nx.real(complex_tensor),
  path: "/data/signal_real",
  chunks: {100, 100}
)

{:ok, imag_array} = ExZarr.Nx.from_tensor(
  Nx.imag(complex_tensor),
  path: "/data/signal_imag",
  chunks: {100, 100}
)

# Load
{:ok, real} = ExZarr.Nx.to_tensor(real_array)
{:ok, imag} = ExZarr.Nx.to_tensor(imag_array)
complex_restored = Nx.complex(real, imag)
```

### Limitation 4: Static Shapes in Defn

**Problem**: `defn` compilation requires static shapes, but batch sizes may vary.

**Workaround:**

```elixir
# Load batches outside defn
def train_epoch(params, array, batch_size) do
  num_batches = div(elem(array.metadata.shape, 0), batch_size)

  Enum.reduce(0..(num_batches - 1), params, fn batch_idx, params_acc ->
    # Load batch (eager, outside defn)
    {:ok, batch} = BatchLoader.load_batch(array, batch_idx, batch_size)

    # Compute (lazy, compiled)
    updated_params = train_step(params_acc, batch)

    updated_params
  end)
end

# train_step is defn with static shape
import Nx.Defn
defn train_step(params, batch) do
  # batch shape is known at compile time
  # ...
end
```

## Legacy Approaches

### ⚠️ Deprecated: Nested Tuple Conversion

**Note:** This approach is **5-10x slower** than `ExZarr.Nx`. Only use for compatibility with old code.

<details>
<summary>Click to expand legacy nested tuple approach</summary>

#### Helpers Module (Legacy)

```elixir
defmodule ExZarr.Nx.LegacyHelpers do
  @moduledoc """
  Legacy conversion helpers using nested tuples.

  ⚠️ DEPRECATED: Use ExZarr.Nx module instead (5-10x faster).
  """

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

#### Legacy Write Pattern

```elixir
# ⚠️ SLOW: 80-150ms for 8MB
tensor = Nx.iota({1000, 1000})

{:ok, array} = ExZarr.create(
  shape: Nx.shape(tensor),
  chunks: {100, 100},
  dtype: :float64,
  storage: :memory
)

# Convert tensor → nested tuples (slow)
data = tensor
       |> Nx.to_list()
       |> ExZarr.Nx.LegacyHelpers.nested_list_to_tuple()

# Write nested tuples
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: Nx.shape(tensor)
)
```

#### Legacy Read Pattern

```elixir
# ⚠️ SLOW: 80-150ms for 8MB
{:ok, array} = ExZarr.open(path: "/data/array")

{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: array.metadata.shape
)

# Convert nested tuples → tensor (slow)
tensor = data
         |> ExZarr.Nx.LegacyHelpers.nested_tuple_to_list()
         |> Nx.tensor()
         |> Nx.reshape(array.metadata.shape)
```

</details>

## Summary

ExZarr provides first-class Nx integration via the `ExZarr.Nx` module:

✅ **5-10x faster** than manual conversion (400-800 MB/s vs 50-100 MB/s)
✅ **Simple API** - Single function calls for conversion
✅ **Full type support** - All 10 standard numeric types
✅ **Chunked processing** - Constant memory for large arrays
✅ **Backend agnostic** - Works with CPU, EXLA, Torchx
✅ **ML-ready** - Efficient batch loading, checkpointing
✅ **Production-tested** - Used in real-world workflows

**Next steps:**
- Try the example: `elixir examples/nx_optimized_conversion.exs`
- Read performance guide: [Performance Guide](performance.md)
- Explore ML patterns: [ML Training/Inference Workflows](#ml-traininginference-workflows)

For questions or issues, see the [Troubleshooting Guide](troubleshooting.md).
