# Advanced Usage Guide

This guide covers advanced features and optimization techniques for ExZarr.

## Table of Contents

1. [Zarr v3 Features](#zarr-v3-features)
2. [Sharding](#sharding)
3. [Dimension Names](#dimension-names)
4. [Custom Chunk Grids](#custom-chunk-grids)
5. [Cloud Storage](#cloud-storage)
6. [Performance Optimization](#performance-optimization)
7. [Custom Storage Backends](#custom-storage-backends)
8. [Custom Codecs](#custom-codecs)

## Zarr v3 Features

Zarr v3 introduces several improvements over v2:

### Unified Codec Pipeline

V3 uses a three-stage codec pipeline for data transformation:

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    # Stage 1: Array → Array transformations
    %{name: "transpose", configuration: %{order: [1, 0]}},

    # Stage 2: Array → Bytes (required)
    %{name: "bytes", configuration: %{endian: "little"}},

    # Stage 3: Bytes → Bytes transformations
    %{name: "gzip", configuration: %{level: 6}}
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/tmp/v3_array"
)
```

### Available Codecs

**Array → Array:**
- `transpose`: Reorder array dimensions
- `bitround`: Round mantissa bits for better compression

**Array → Bytes:**
- `bytes`: Convert array to byte representation (required)

**Bytes → Bytes:**
- `gzip`: GNU zip compression
- `zstd`: Zstandard compression (fast, high ratio)
- `lz4`: LZ4 compression (very fast)
- `blosc`: Blosc meta-compressor with multiple algorithms

### Metadata Structure

V3 uses improved metadata format:

```elixir
# Read v3 metadata
{:ok, array} = ExZarr.open(path: "/tmp/v3_array")

# Access metadata
IO.inspect(array.metadata.shape)           # {1000, 1000}
IO.inspect(array.metadata.data_type)       # :float64
IO.inspect(array.metadata.chunk_grid)      # Chunk grid configuration
IO.inspect(array.metadata.codecs)          # Codec pipeline
IO.inspect(array.metadata.dimension_names) # Optional dimension names
```

## Sharding

Sharding combines multiple chunks into larger "shards" to reduce metadata overhead, especially important for cloud storage.

### Why Use Sharding?

**Without sharding:**
- 10,000 chunks = 10,000 S3 objects
- High API call costs
- Slow directory listings

**With sharding:**
- 10,000 chunks in 100 shards = 100 S3 objects
- 100x fewer API calls
- Faster metadata operations

### Creating Sharded Arrays

```elixir
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {100, 100},        # Logical chunks for access
  codecs: [
    %{
      name: "sharding_indexed",
      configuration: %{
        chunk_shape: [1000, 1000],  # Physical shard size (10x10 chunks per shard)
        codecs: [
          %{name: "bytes"},
          %{name: "gzip", configuration: %{level: 6}}
        ],
        index_codecs: [
          %{name: "bytes"},
          %{name: "crc32c"}
        ]
      }
    }
  ],
  zarr_version: 3,
  storage: :s3,
  bucket: "my-data-bucket",
  path: "sharded_array"
)
```

### Shard Configuration

```elixir
# Shard parameters
shard_config = %{
  chunk_shape: [1000, 1000],      # Size of each shard
  codecs: [...],                   # Codecs for chunk data
  index_codecs: [...],             # Codecs for shard index
  index_location: "end"            # Index at start or end of shard
}

# Optimal shard size: 10-100 MB per shard
# Calculate: shard_elements * element_size * compression_ratio
```

### When to Use Sharding

**Use sharding when:**
- Storing arrays on cloud storage (S3, GCS, Azure)
- Arrays have many small chunks
- API call costs are significant
- Directory listing is slow

**Don't use sharding when:**
- Using local filesystem (no benefit)
- Chunks are already large (>1 MB each)
- Random access to individual chunks is critical
- Write performance is most important (sharding adds overhead)

## Dimension Names

Zarr v3 supports named dimensions for intuitive slicing:

### Creating Arrays with Dimension Names

```elixir
{:ok, array} = ExZarr.create(
  shape: {365, 180, 360},
  chunks: {1, 180, 360},
  dtype: :float32,
  dimension_names: ["time", "latitude", "longitude"],
  zarr_version: 3,
  storage: :filesystem,
  path: "/tmp/climate_data"
)
```

### Slicing by Dimension Names

```elixir
# Slice by dimension names instead of numeric indices
{:ok, january} = ExZarr.Array.get_slice(array,
  time: 0..30,           # First 31 days
  latitude: 0..179,      # All latitudes
  longitude: 0..359      # All longitudes
)

# Mix named and numeric indices
{:ok, data} = ExZarr.Array.get_slice(array,
  time: 100..200,        # Days 100-200
  latitude: 45..135,     # Mid-latitudes
  longitude: 0..179      # Eastern hemisphere
)

# Fall back to numeric when needed
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0, 0},
  stop: {365, 180, 360}
)
```

### Dimension Name Rules

```elixir
# Valid dimension names
dimension_names: ["time", "lat", "lon"]           # Simple names
dimension_names: ["sample_id", "feature_1"]       # Underscores
dimension_names: ["x-axis", "y-axis"]             # Hyphens

# Invalid dimension names
dimension_names: ["time", "time"]                 # Duplicates
dimension_names: ["time", "lat"]                  # Count mismatch with shape
dimension_names: ["", "lat", "lon"]               # Empty names
```

## Custom Chunk Grids

Zarr v3 supports flexible chunk grid systems beyond regular chunking.

### Regular Chunk Grid (Default)

Standard fixed-size chunks:

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunk_grid: %{
    name: "regular",
    configuration: %{
      chunk_shape: [100, 100]
    }
  },
  zarr_version: 3
)
```

### Irregular Chunk Grid

Variable-size chunks for non-uniform data:

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunk_grid: %{
    name: "irregular",
    configuration: %{
      chunk_shapes: %{
        [0, 0] => [500, 500],  # Large top-left region
        [0, 1] => [500, 500],  # Large top-right
        [1, 0] => [250, 500],  # Smaller bottom regions
        [1, 1] => [250, 500]
      }
    }
  },
  zarr_version: 3
)
```

### Use Cases for Irregular Grids

**Adaptive resolution:**
```elixir
# High resolution in area of interest, coarse elsewhere
chunk_shapes: %{
  [0, 0] => [50, 50],    # Fine detail (center)
  [0, 1] => [100, 100],  # Medium detail
  [0, 2] => [200, 200],  # Coarse detail (edges)
  # ...
}
```

**Non-uniform data distribution:**
```elixir
# Larger chunks where data is sparse
chunk_shapes: %{
  [0, 0] => [1000, 1000],  # Sparse region
  [1, 0] => [100, 100],    # Dense region
  # ...
}
```

## Cloud Storage

ExZarr supports major cloud storage providers with optimized performance.

### Amazon S3

```elixir
# Configure S3 credentials (in config/runtime.exs)
config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: "us-west-2"

# Create array on S3
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  storage: :s3,
  bucket: "my-data-bucket",
  prefix: "arrays/experiment_001",  # Optional prefix
  zarr_version: 3
)

# Use sharding to minimize API calls
{:ok, sharded_array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {100, 100},
  codecs: [
    %{
      name: "sharding_indexed",
      configuration: %{
        chunk_shape: [1000, 1000],  # 100 logical chunks per shard
        codecs: [
          %{name: "bytes"},
          %{name: "zstd"}
        ]
      }
    }
  ],
  storage: :s3,
  bucket: "my-data-bucket",
  zarr_version: 3
)
```

### Google Cloud Storage

```elixir
# Set up GCS authentication
# Export GOOGLE_APPLICATION_CREDENTIALS environment variable

# Create array on GCS
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  storage: :gcs,
  bucket: "my-gcs-bucket",
  prefix: "data/arrays",
  credentials: "/path/to/credentials.json",
  zarr_version: 3
)
```

### Azure Blob Storage

```elixir
# Configure Azure credentials
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  storage: :azure_blob,
  account_name: "myaccount",
  account_key: System.get_env("AZURE_STORAGE_KEY"),
  container: "data-container",
  prefix: "arrays/experiment",
  zarr_version: 3
)
```

### Cloud Storage Best Practices

**1. Use larger chunks:**
```elixir
# Good for cloud: fewer, larger chunks
chunks: {1000, 1000}  # ~76 MB per chunk for float64

# Less optimal: many small chunks
chunks: {100, 100}    # ~760 KB per chunk, 100x more API calls
```

**2. Enable sharding:**
```elixir
# Reduces object count and API calls
codecs: [
  %{
    name: "sharding_indexed",
    configuration: %{chunk_shape: [1000, 1000]}
  }
]
```

**3. Use compression:**
```elixir
# Reduce storage costs and transfer time
codecs: [
  %{name: "bytes"},
  %{name: "zstd", configuration: %{level: 3}}  # Fast, good ratio
]
```

**4. Batch operations:**
```elixir
# Write multiple chunks in parallel
tasks = Enum.map(chunk_list, fn {i, j, data} ->
  Task.async(fn ->
    ExZarr.Array.set_slice(array, data,
      start: {i * 1000, j * 1000},
      stop: {(i + 1) * 1000, (j + 1) * 1000}
    )
  end)
end)

Task.await_many(tasks, :infinity)
```

**5. Monitor costs:**
```elixir
# Track API operations
# S3: ~$0.0004 per 1,000 PUT requests
# S3: ~$0.0004 per 1,000 GET requests
# Storage: ~$0.023 per GB/month

# Example calculation:
# 10,000 chunks without sharding:
#   - 10,000 PUT requests = $0.004
#   - 10,000 GET requests = $0.004
#
# 100 shards (100 chunks each):
#   - 100 PUT requests = $0.00004
#   - 100 GET requests = $0.00004
#   - 100x cost reduction!
```

## Performance Optimization

### Chunk Size Tuning

**For sequential access:**
```elixir
# Large chunks in access direction
shape: {1000, 10000}
chunks: {100, 10000}  # Full width chunks for row-wise access
```

**For random access:**
```elixir
# Balanced chunks
shape: {10000, 10000}
chunks: {1000, 1000}  # Square chunks for flexible access
```

**For cloud storage:**
```elixir
# Minimize API calls with large chunks
shape: {10000, 10000}
chunks: {2000, 2000}  # ~305 MB per chunk for float64
```

### Compression Tuning

**Fast compression (low CPU, moderate ratio):**
```elixir
codecs: [
  %{name: "bytes"},
  %{name: "lz4"}  # Very fast, ~2-3x compression
]
```

**Balanced (moderate CPU, good ratio):**
```elixir
codecs: [
  %{name: "bytes"},
  %{name: "zstd", configuration: %{level: 3}}  # Fast, 5-10x compression
]
```

**Maximum compression (high CPU, best ratio):**
```elixir
codecs: [
  %{name: "bytes"},
  %{name: "zstd", configuration: %{level: 22}}  # Slow, >10x compression
]
```

**No compression (fastest I/O):**
```elixir
codecs: [
  %{name: "bytes"}  # No compression codec
]
```

### Parallel Processing

**Chunk-level parallelism:**
```elixir
# Process chunks in parallel using Flow
alias Experimental.Flow

chunk_indices = for i <- 0..99, j <- 0..99, do: {i, j}

Flow.from_enumerable(chunk_indices)
|> Flow.partition()
|> Flow.map(fn {i, j} ->
  # Read chunk
  {:ok, data} = ExZarr.Array.get_slice(array,
    start: {i * 100, j * 100},
    stop: {(i + 1) * 100, (j + 1) * 100}
  )

  # Process
  processed = expensive_computation(data)

  # Write result
  :ok = ExZarr.Array.set_slice(result_array, processed,
    start: {i * 100, j * 100},
    stop: {(i + 1) * 100, (j + 1) * 100}
  )

  {i, j}
end)
|> Enum.to_list()
```

**Task-based parallelism:**
```elixir
# Simple parallel processing with Task
tasks = for i <- 0..9 do
  Task.async(fn ->
    # Each task processes one row of chunks
    for j <- 0..9 do
      {:ok, data} = ExZarr.Array.get_slice(array,
        start: {i * 100, j * 100},
        stop: {(i + 1) * 100, (j + 1) * 100}
      )

      process_and_write(data, i, j)
    end
  end)
end

Task.await_many(tasks, :infinity)
```

### Memory Management

**Stream large arrays:**
```elixir
# Don't load entire array at once
# {:ok, huge_data} = ExZarr.Array.get_slice(array, ...)  # May exhaust memory

# Instead, stream chunks
Stream.unfold({0, 0}, fn
  nil -> nil
  {i, j} when i >= 100 -> nil
  {i, j} when j >= 100 -> {{i, j}, {i + 1, 0}}
  {i, j} -> {{i, j}, {i, j + 1}}
end)
|> Stream.map(fn {i, j} ->
  {:ok, chunk} = ExZarr.Array.get_slice(array,
    start: {i * 100, j * 100},
    stop: {(i + 1) * 100, (j + 1) * 100}
  )
  process_chunk(chunk)
end)
|> Enum.each(&write_result/1)
```

**Use ETS for caching:**
```elixir
# Cache frequently accessed chunks in ETS
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :ets,  # In-memory with fast concurrent access
  table_name: :my_array_cache
)
```

### Profiling

**Measure read performance:**
```elixir
# Benchmark chunk reads
{microseconds, {:ok, _data}} = :timer.tc(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)

IO.puts("Read time: #{microseconds / 1000} ms")
```

**Profile with :fprof:**
```elixir
:fprof.trace([:start])

# Run your code
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1000, 1000})

:fprof.trace([:stop])
:fprof.profile()
:fprof.analyse()
```

## Custom Storage Backends

Implement custom storage backends for specialized needs:

### Backend Behavior

```elixir
defmodule MyApp.CustomStorage do
  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :custom

  @impl true
  def init(config) do
    # Initialize storage
    state = %{connection: connect_to_storage(config)}
    {:ok, state}
  end

  @impl true
  def open(config) do
    # Open existing storage
    init(config)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    # Read chunk data
    case fetch_chunk(state, chunk_index) do
      {:ok, data} -> {:ok, data}
      :not_found -> {:error, :not_found}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    # Write chunk data
    store_chunk(state, chunk_index, data)
    :ok
  end

  @impl true
  def read_metadata(state) do
    # Read array metadata
    case fetch_metadata(state) do
      {:ok, json} -> {:ok, json}
      :not_found -> {:error, :not_found}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) do
    # Write array metadata
    store_metadata(state, metadata)
    :ok
  end

  @impl true
  def list_chunks(state) do
    # List all chunk indices
    chunks = get_all_chunk_indices(state)
    {:ok, chunks}
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    # Delete chunk
    remove_chunk(state, chunk_index)
    :ok
  end

  @impl true
  def exists?(config) do
    # Check if array exists
    check_existence(config)
  end
end
```

### Register Custom Backend

```elixir
# Register backend
:ok = ExZarr.Storage.Registry.register(MyApp.CustomStorage)

# Use custom backend
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :custom,
  custom_config: "value"
)
```

## Custom Codecs

Create custom codecs for specialized transformations:

### Codec Behavior

```elixir
defmodule MyApp.CustomCodec do
  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: "custom_transform"

  @impl true
  def encode(data, config) do
    # Transform data during encoding
    transformed = apply_transform(data, config)
    {:ok, transformed}
  end

  @impl true
  def decode(data, config) do
    # Reverse transformation during decoding
    original = reverse_transform(data, config)
    {:ok, original}
  end

  @impl true
  def validate_config(config) do
    # Validate codec configuration
    if valid_config?(config) do
      :ok
    else
      {:error, :invalid_configuration}
    end
  end

  @impl true
  def get_config_schema do
    # Return configuration schema
    %{
      type: :object,
      properties: %{
        parameter: %{type: :integer}
      }
    }
  end
end
```

### Register Custom Codec

```elixir
# Register codec
:ok = ExZarr.Codecs.Registry.register(MyApp.CustomCodec)

# Use in array
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},
    %{name: "custom_transform", configuration: %{parameter: 42}}
  ],
  zarr_version: 3
)
```

## Advanced Patterns

### Lazy Loading

```elixir
# Create proxy that loads data on demand
defmodule LazyArray do
  defstruct [:array, :cache]

  def new(path) do
    {:ok, array} = ExZarr.open(path: path)
    %__MODULE__{array: array, cache: %{}}
  end

  def get(lazy_array, indices) do
    chunk_index = compute_chunk_index(indices)

    case Map.get(lazy_array.cache, chunk_index) do
      nil ->
        # Load chunk on first access
        {:ok, chunk} = load_chunk(lazy_array.array, chunk_index)
        cache = Map.put(lazy_array.cache, chunk_index, chunk)
        value = extract_value(chunk, indices)
        {value, %{lazy_array | cache: cache}}

      chunk ->
        # Use cached chunk
        value = extract_value(chunk, indices)
        {value, lazy_array}
    end
  end
end
```

### Transactional Writes

```elixir
# Implement write-ahead logging
defmodule TransactionalArray do
  def write_with_transaction(array, updates) do
    # Start transaction
    tx_id = start_transaction()

    try do
      # Apply all updates
      Enum.each(updates, fn {indices, data} ->
        # Write to temporary location
        write_temp(tx_id, indices, data)
      end)

      # Commit transaction
      commit_transaction(tx_id, array)
      :ok
    rescue
      e ->
        # Rollback on error
        rollback_transaction(tx_id)
        {:error, e}
    end
  end
end
```

## Next Steps

- Explore example applications in `examples/`
- Read the [Migration Guide](migration_from_python.md) if coming from Python
- Browse the [API documentation](https://hexdocs.pm/ex_zarr)
- Check the [Zarr specification](https://zarr-specs.readthedocs.io/) for details
