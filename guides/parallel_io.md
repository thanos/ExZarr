# Parallel I/O and Concurrency Patterns

ExZarr's primary architectural strength is parallel chunk I/O using BEAM concurrency primitives. This guide explains how to leverage BEAM's lightweight processes for concurrent chunk operations, measure performance improvements, and understand when parallelism helps.

## Why Parallelism Matters for Zarr

Zarr's chunked storage design enables natural parallelism. Each chunk is an independent unit that can be read, written, compressed, and decompressed without coordinating with other chunks.

### Chunked Storage Enables Independent Operations

Consider a 1000×1000 array with 100×100 chunks:

```
Array: 1000×1000 elements
Chunks: 100×100 elements each
Total chunks: 10×10 = 100 chunks

Reading slice [0:400, 0:400]:
- Requires 16 chunks: (0,0) through (3,3)
- Each chunk can be read independently
- No coordination needed between chunk reads
```

Each chunk operation is independent:
1. Read compressed bytes from storage
2. Decompress using codec
3. Extract requested slice region
4. Return data

Steps 1-3 can happen in parallel for different chunks.

### I/O-Bound Parallelism

When reading from cloud storage (S3, GCS, Azure), network latency dominates:

```
Sequential reads (16 chunks from S3):
  16 chunks × 100ms latency = 1,600ms total

Parallel reads (8 concurrent):
  16 chunks / 8 workers × 100ms = 200ms total
  Speedup: 8×
```

The BEAM's async I/O model allows hundreds of concurrent requests without blocking. Each HTTP request runs in its own process, and the scheduler automatically multiplexes across available CPU cores.

### CPU-Bound Parallelism

Decompression is CPU-intensive. The BEAM's multi-core scheduling enables true parallel decompression:

```
Sequential decompression (16 chunks):
  16 chunks × 5ms decompression = 80ms total

Parallel decompression (8 cores):
  16 chunks / 8 cores × 5ms = 10ms total
  Speedup: 8×
```

**Contrast with Python's GIL:**
Python's Global Interpreter Lock prevents threads from executing Python bytecode in parallel. Python threads can perform I/O concurrently, but CPU-bound operations (decompression, codec pipeline execution) are serialized:

```
Python threading (16 chunks, 8 threads):
  I/O: Parallel (good)
  Decompression: Sequential (GIL constraint)
  Total time: 16 × 5ms = 80ms (no speedup for CPU work)

ExZarr on BEAM (16 chunks, 8 cores):
  I/O: Parallel (good)
  Decompression: Parallel (no GIL)
  Total time: 16 / 8 × 5ms = 10ms (8× speedup)
```

This architectural difference is why ExZarr can achieve significant performance improvements in multi-chunk operations.

### BEAM Lightweight Processes

BEAM processes are cheap:
- **Creation cost**: ~1-2 microseconds
- **Memory overhead**: ~2-3 KB per process
- **Scheduling**: Preemptive, fair across processes

You can spawn thousands of tasks without concern:

```elixir
# Spawn 1000 concurrent chunk reads
# Each task is a separate BEAM process
Task.async_stream(1..1000, fn i ->
  ExZarr.Array.get_slice(array, start: {i, 0}, stop: {i+1, 100})
end, max_concurrency: 100)
|> Enum.to_list()
```

The BEAM scheduler automatically distributes work across CPU cores.

## Task-Based Parallel Reads

Use `Task.async_stream/3` to read multiple chunks concurrently.

### Basic Pattern: Parallel Chunk Reads

```elixir
# Array: {1000, 1000} with chunks {100, 100}
{:ok, array} = ExZarr.open(path: "/data/large_array")

# Read region [0:400, 0:400] which spans 16 chunks
chunk_coords = for i <- 0..3, j <- 0..3, do: {i, j}

# Read chunks in parallel
results = Task.async_stream(
  chunk_coords,
  fn {i, j} ->
    ExZarr.Array.get_slice(array,
      start: {i * 100, j * 100},
      stop: {(i + 1) * 100, (j + 1) * 100}
    )
  end,
  max_concurrency: 8,
  timeout: 30_000,
  ordered: true
)
|> Enum.to_list()

# Results is a list of {:ok, {:ok, chunk_data}} tuples
# Extract data:
chunk_data_list = Enum.map(results, fn {:ok, {:ok, data}} -> data end)
```

**Parameters:**
- `max_concurrency`: Maximum parallel tasks (default: `System.schedulers_online()`)
- `timeout`: Per-task timeout in milliseconds (default: 5,000)
- `ordered`: Preserve input order in results (default: true)
- `on_timeout`: `:kill_task` or `:exit` (default: `:kill_task`)

### Choosing Concurrency Level

```elixir
# Conservative: 1× CPU cores (good for CPU-bound work)
max_concurrency: System.schedulers_online()

# Balanced: 2× CPU cores (handles I/O wait better)
max_concurrency: System.schedulers_online() * 2

# Aggressive: 4× CPU cores (maximizes I/O throughput for cloud storage)
max_concurrency: System.schedulers_online() * 4

# Fixed limit: Cap at specific value (avoid overwhelming storage)
max_concurrency: 10
```

**Guidelines:**
- CPU-bound (decompression): Use 1-2× CPU cores
- I/O-bound (S3, network): Use 4-8× CPU cores
- Cloud storage: Respect rate limits (see [Cloud Storage Performance](#cloud-storage-performance-considerations))

### Using ExZarr's Chunk Stream API

ExZarr provides `chunk_stream/2` for convenient parallel processing:

```elixir
# Stream all chunks in parallel
array
|> ExZarr.Array.chunk_stream(parallel: 4)
|> Stream.each(fn {chunk_index, chunk_data} ->
  process_chunk(chunk_index, chunk_data)
end)
|> Stream.run()

# Map chunks with parallel processing
results = array
|> ExZarr.Array.parallel_chunk_map(
  fn {chunk_index, chunk_data} ->
    transform(chunk_data)
  end,
  max_concurrency: 8,
  timeout: 30_000
)
|> Enum.to_list()
```

**Options:**
- `parallel`: Concurrency level (default: 1, sequential)
- `filter`: Function to filter which chunks to process
- `progress_callback`: Track progress `fn done, total -> ... end`
- `ordered`: Maintain chunk order (default: true)

**Example with progress tracking:**
```elixir
# Process 100 chunks with progress updates
ExZarr.Array.chunk_stream(array,
  parallel: 8,
  progress_callback: fn done, total ->
    IO.write("\rProcessed #{done}/#{total} chunks")
  end
)
|> Stream.each(fn {_index, data} -> analyze(data) end)
|> Stream.run()

IO.puts("\nComplete!")
```

### Unordered Processing for Better Performance

If result order doesn't matter, disable ordering:

```elixir
# Faster: results arrive as tasks complete
results = Task.async_stream(
  chunk_coords,
  fn coord -> read_chunk(coord) end,
  max_concurrency: 8,
  ordered: false  # Don't wait for earlier tasks
)
|> Enum.to_list()
```

With `ordered: true`, the stream waits for earlier tasks before yielding later results. With `ordered: false`, results arrive as soon as tasks complete, maximizing throughput.

## Task-Based Parallel Writes

Write independent chunks concurrently to improve ingestion throughput.

### Basic Pattern: Parallel Chunk Writes

```elixir
# Generate 100 chunks of data
chunk_data_list = for i <- 0..99 do
  generate_chunk_data(i)
end

# Write chunks in parallel
results = Task.async_stream(
  Enum.with_index(chunk_data_list),
  fn {data, index} ->
    # Calculate chunk position
    {i, j} = {div(index, 10), rem(index, 10)}

    ExZarr.Array.set_slice(array, data,
      start: {i * 100, j * 100},
      stop: {(i + 1) * 100, (j + 1) * 100}
    )
  end,
  max_concurrency: 10,
  timeout: 60_000
)
|> Enum.to_list()

# Check for errors
errors = Enum.filter(results, fn
  {:ok, {:error, _reason}} -> true
  {:exit, _reason} -> true
  _ -> false
end)

if Enum.empty?(errors) do
  IO.puts("All chunks written successfully")
else
  IO.puts("Errors occurred: #{inspect(errors)}")
end
```

**Caution:** Limit concurrency to avoid overwhelming storage:
- **Filesystem**: 10-20 concurrent writes
- **S3**: 50-100 concurrent writes (watch for rate limits)
- **GCS**: 100-200 concurrent writes
- **Memory/ETS**: 50-100 concurrent writes

### Partitioned Work Pattern

Assign each worker a disjoint set of chunks to eliminate coordination:

```elixir
# 10 workers, each writes 10 chunks (1 row of the chunk grid)
workers = 0..9

tasks = Enum.map(workers, fn worker_id ->
  Task.async(fn ->
    Enum.each(0..9, fn j ->
      data = generate_data(worker_id, j)

      ExZarr.Array.set_slice(array, data,
        start: {worker_id * 100, j * 100},
        stop: {(worker_id + 1) * 100, (j + 1) * 100}
      )
    end)
  end)
end)

# Wait for all workers to complete
Task.await_many(tasks, :infinity)
```

Each worker owns a row of chunks. No two workers write to the same chunk, eliminating race conditions.

### Handling Write Errors

Parallel writes can fail. Handle errors appropriately:

```elixir
results = Task.async_stream(
  chunk_list,
  fn {data, coord} ->
    case ExZarr.Array.set_slice(array, data,
           start: coord,
           stop: Tuple.to_list(coord) |> Enum.map(&(&1 + 100)) |> List.to_tuple()) do
      :ok -> {:ok, coord}
      {:error, reason} -> {:error, {coord, reason}}
    end
  end,
  max_concurrency: 10,
  timeout: 60_000
)
|> Enum.to_list()

# Separate successes and failures
{successes, failures} = Enum.split_with(results, fn
  {:ok, {:ok, _coord}} -> true
  _ -> false
end)

IO.puts("Wrote #{length(successes)} chunks successfully")
IO.puts("Failed to write #{length(failures)} chunks")

# Retry failed chunks
retry_coords = Enum.map(failures, fn
  {:ok, {:error, {coord, _reason}}} -> coord
  {:exit, _} -> nil
end) |> Enum.reject(&is_nil/1)

# Retry logic...
```

## Concurrent Read Safety

Reading is safe. Multiple processes can read the same chunk or different chunks simultaneously without coordination.

### Safe Concurrent Reads

```elixir
# Process 1: Read slice [0:100, 0:100]
task1 = Task.async(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)

# Process 2: Read different slice [100:200, 100:200]
task2 = Task.async(fn ->
  ExZarr.Array.get_slice(array, start: {100, 100}, stop: {200, 200})
end)

# Process 3: Read same slice as Process 1 (still safe)
task3 = Task.async(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)

# Wait for all reads
[result1, result2, result3] = Task.await_many([task1, task2, task3])
```

All three reads execute safely in parallel. ExZarr handles concurrent access internally.

### Why Reads Are Safe

**Immutable chunk data:**
Once a chunk is written, it doesn't change during reads. Multiple processes can read the same chunk bytes without conflict.

**Storage backend coordination:**
Storage backends serialize access if needed (GenServer for stateful backends). This prevents corruption but doesn't affect correctness of concurrent reads.

**No locking required:**
Your application code doesn't need mutexes or locks for reads. The BEAM message-passing model and storage backend implementation handle safety.

### Example: Multi-Client Access

```elixir
# Server process: manages array
defmodule ArrayServer do
  use GenServer

  def init(array_path) do
    {:ok, array} = ExZarr.open(path: array_path)
    {:ok, %{array: array}}
  end

  def handle_call({:get_slice, start, stop}, _from, state) do
    result = ExZarr.Array.get_slice(state.array, start: start, stop: stop)
    {:reply, result, state}
  end
end

{:ok, pid} = GenServer.start_link(ArrayServer, "/data/shared_array")

# Multiple clients reading concurrently
client_tasks = for i <- 0..15 do
  Task.async(fn ->
    start = {i * 100, 0}
    stop = {(i + 1) * 100, 100}
    GenServer.call(pid, {:get_slice, start, stop})
  end)
end

# All reads execute safely in parallel
Task.await_many(client_tasks)
```

## Concurrent Write Coordination

Writing requires coordination when multiple processes write to the same chunk.

### Safe: Writing Different Chunks

Writing to different chunks is safe and requires no coordination:

```elixir
# Safe: each write targets a different chunk
tasks = [
  Task.async(fn ->
    ExZarr.Array.set_slice(array, data1, start: {0, 0}, stop: {100, 100})
  end),
  Task.async(fn ->
    ExZarr.Array.set_slice(array, data2, start: {100, 100}, stop: {200, 200})
  end),
  Task.async(fn ->
    ExZarr.Array.set_slice(array, data3, start: {200, 200}, stop: {300, 300})
  end)
]

Task.await_many(tasks)
# All writes complete successfully
```

Each write targets a different chunk coordinate. No race conditions occur.

### Unsafe: Writing Same Chunk Concurrently

Writing to the same chunk from multiple processes causes a race condition:

```elixir
# UNSAFE: both writes touch chunk (0, 0)
# Last write wins, data may be corrupted
task1 = Task.async(fn ->
  # Writes to array[0:50, 0:100] which is part of chunk (0, 0)
  ExZarr.Array.set_slice(array, data1, start: {0, 0}, stop: {50, 100})
end)

task2 = Task.async(fn ->
  # Writes to array[50:100, 0:100] which is also part of chunk (0, 0)
  ExZarr.Array.set_slice(array, data2, start: {50, 0}, stop: {100, 100})
end)

Task.await_many([task1, task2])
# Result: unpredictable, may lose data from one task
```

Both writes touch chunk (0, 0), causing a read-modify-write race.

### Coordination Strategy 1: Partition Work

Assign each worker a disjoint set of chunks:

```elixir
# 4 workers, each writes 25 chunks
workers = 0..3

tasks = Enum.map(workers, fn worker_id ->
  Task.async(fn ->
    # Each worker gets a quadrant of the array
    row_start = div(worker_id, 2) * 500
    col_start = rem(worker_id, 2) * 500

    # Write 5×5 chunks in this quadrant
    for i <- 0..4, j <- 0..4 do
      data = generate_data(row_start + i * 100, col_start + j * 100)

      ExZarr.Array.set_slice(array, data,
        start: {row_start + i * 100, col_start + j * 100},
        stop: {row_start + (i + 1) * 100, col_start + (j + 1) * 100}
      )
    end
  end)
end)

Task.await_many(tasks, :infinity)
```

No overlap means no race conditions.

### Coordination Strategy 2: Application-Level Locking

Use a GenServer to serialize writes to the same chunk:

```elixir
defmodule ChunkWriteCoordinator do
  use GenServer

  def init(array) do
    {:ok, %{array: array, locks: %{}}}
  end

  def handle_call({:write_slice, data, start, stop}, from, state) do
    # Determine affected chunks
    affected_chunks = calculate_affected_chunks(start, stop, state.array.chunks)

    # Check if any chunk is locked
    locked = Enum.any?(affected_chunks, fn chunk -> Map.has_key?(state.locks, chunk) end)

    if locked do
      # Defer write until chunks are unlocked
      {:reply, {:error, :chunk_locked}, state}
    else
      # Lock chunks, perform write
      new_locks = Enum.reduce(affected_chunks, state.locks, fn chunk, acc ->
        Map.put(acc, chunk, from)
      end)

      # Perform actual write
      result = ExZarr.Array.set_slice(state.array, data, start: start, stop: stop)

      # Unlock chunks
      unlocked = Enum.reduce(affected_chunks, new_locks, fn chunk, acc ->
        Map.delete(acc, chunk)
      end)

      {:reply, result, %{state | locks: unlocked}}
    end
  end
end
```

This approach adds overhead but ensures correctness when multiple writers may collide.

### Coordination Strategy 3: Batch and Merge

Collect updates in memory, merge, and write once:

```elixir
# Collect all updates for a region
updates = [
  {data1, {0, 0}, {50, 100}},
  {data2, {50, 0}, {100, 100}}
]

# Merge into single chunk
merged_data = merge_updates(updates)

# Write once
ExZarr.Array.set_slice(array, merged_data,
  start: {0, 0},
  stop: {100, 100}
)
```

This avoids race conditions by eliminating concurrent writes to the same chunk.

## Performance Measurement

Measure the speedup from parallelism with benchmarks.

### Sequential vs Parallel Benchmark

```elixir
# Setup: create array and populate with data
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd,
  storage: :filesystem,
  path: "/tmp/benchmark_array"
)

# Write test data
for i <- 0..9, j <- 0..9 do
  data = generate_chunk_data(i, j)
  ExZarr.Array.set_slice(array, data,
    start: {i * 100, j * 100},
    stop: {(i + 1) * 100, (j + 1) * 100}
  )
end

# Benchmark: read 16 chunks sequentially
sequential_time = :timer.tc(fn ->
  for i <- 0..3, j <- 0..3 do
    ExZarr.Array.get_slice(array,
      start: {i * 100, j * 100},
      stop: {(i + 1) * 100, (j + 1) * 100}
    )
  end
end) |> elem(0)

# Benchmark: read 16 chunks in parallel
parallel_time = :timer.tc(fn ->
  chunk_coords = for i <- 0..3, j <- 0..3, do: {i, j}

  Task.async_stream(
    chunk_coords,
    fn {i, j} ->
      ExZarr.Array.get_slice(array,
        start: {i * 100, j * 100},
        stop: {(i + 1) * 100, (j + 1) * 100}
      )
    end,
    max_concurrency: 8
  )
  |> Enum.to_list()
end) |> elem(0)

# Calculate speedup
speedup = sequential_time / parallel_time
IO.puts("Sequential: #{div(sequential_time, 1000)}ms")
IO.puts("Parallel:   #{div(parallel_time, 1000)}ms")
IO.puts("Speedup:    #{Float.round(speedup, 2)}×")
```

**Expected results:**
```
Sequential: 240ms
Parallel:   35ms
Speedup:    6.86×
```

Actual speedup depends on:
- Storage latency (cloud vs local)
- Compression codec (zstd vs lz4)
- Chunk size (larger = more decompression work)
- CPU cores available

### Measuring Write Throughput

```elixir
# Write 100 chunks and measure throughput
chunk_count = 100
chunk_size_bytes = 100 * 100 * 8  # 80 KB per chunk
total_bytes = chunk_count * chunk_size_bytes

# Sequential write
seq_time = :timer.tc(fn ->
  for i <- 0..99 do
    {row, col} = {div(i, 10), rem(i, 10)}
    data = generate_chunk_data(row, col)
    ExZarr.Array.set_slice(array, data,
      start: {row * 100, col * 100},
      stop: {(row + 1) * 100, (col + 1) * 100}
    )
  end
end) |> elem(0)

# Parallel write (10 concurrent)
par_time = :timer.tc(fn ->
  Task.async_stream(
    0..99,
    fn i ->
      {row, col} = {div(i, 10), rem(i, 10)}
      data = generate_chunk_data(row, col)
      ExZarr.Array.set_slice(array, data,
        start: {row * 100, col * 100},
        stop: {(row + 1) * 100, (col + 1) * 100}
      )
    end,
    max_concurrency: 10
  )
  |> Enum.to_list()
end) |> elem(0)

seq_throughput = total_bytes / seq_time * 1_000_000 / 1024 / 1024
par_throughput = total_bytes / par_time * 1_000_000 / 1024 / 1024

IO.puts("Sequential throughput: #{Float.round(seq_throughput, 2)} MB/s")
IO.puts("Parallel throughput:   #{Float.round(par_throughput, 2)} MB/s")
```

**Sample results (S3 storage):**
```
Sequential throughput: 12.5 MB/s
Parallel throughput:   78.3 MB/s
Speedup: 6.3×
```

### Benchmarking Different Concurrency Levels

```elixir
concurrency_levels = [1, 2, 4, 8, 16]

results = for concurrency <- concurrency_levels do
  time = :timer.tc(fn ->
    Task.async_stream(
      0..31,
      fn i ->
        {row, col} = {div(i, 8), rem(i, 8)}
        ExZarr.Array.get_slice(array,
          start: {row * 100, col * 100},
          stop: {(row + 1) * 100, (col + 1) * 100}
        )
      end,
      max_concurrency: concurrency
    )
    |> Enum.to_list()
  end) |> elem(0) |> div(1000)

  {concurrency, time}
end

IO.puts("\nConcurrency Scaling:")
Enum.each(results, fn {concurrency, time} ->
  IO.puts("  #{concurrency} concurrent: #{time}ms")
end)
```

**Sample output:**
```
Concurrency Scaling:
  1 concurrent: 480ms
  2 concurrent: 245ms
  4 concurrent: 128ms
  8 concurrent: 68ms
  16 concurrent: 65ms
```

Notice diminishing returns beyond 8 concurrent tasks (approaching hardware limits).

## When NOT to Parallelize

Parallelism adds overhead. It's not always beneficial.

### Small Arrays (Single Chunk)

If your slice fits in one chunk, parallelism adds no benefit:

```elixir
# Array: {1000, 1000} with chunks {500, 500}
# Read: [0:100, 0:100] touches only chunk (0, 0)

# Don't parallelize - only one chunk involved
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)
```

**Rule:** Only parallelize when accessing 4+ chunks.

### Memory-Bound Workloads

Loading too many chunks causes memory pressure:

```elixir
# Array: {10000, 10000} with chunks {1000, 1000}
# Chunk size: 1000×1000×8 bytes = 8 MB per chunk

# Bad: Load 100 chunks in parallel
# 100 chunks × 8 MB = 800 MB in memory simultaneously
Task.async_stream(all_chunk_coords, &read_chunk/1,
  max_concurrency: 100  # Too many!
)
```

**Guidelines:**
- Limit in-flight chunks based on available memory
- Monitor memory usage during parallel operations
- Use streaming (process and discard) instead of collecting results

### Sequential Access Patterns

If you're reading one chunk at a time, parallelism adds overhead:

```elixir
# Sequential processing: analyze each chunk before next
for i <- 0..99 do
  {:ok, data} = get_chunk(array, i)
  result = analyze(data)
  decide_next_step(result)  # Next step depends on result
end
```

Use parallelism when chunks can be processed independently.

### Storage Rate Limits

Cloud providers throttle concurrent requests:

**AWS S3 limits (per prefix):**
- 3,500 PUT/COPY/POST/DELETE requests per second
- 5,500 GET/HEAD requests per second

**Exceeding limits:**
```elixir
# Bad: 10,000 concurrent S3 reads
# Exceeds 5,500 GET/s limit
Task.async_stream(1..10_000, &read_chunk/1,
  max_concurrency: 10_000  # Will be throttled/rate-limited
)
```

**Solution: Limit concurrency:**
```elixir
# Good: 100 concurrent S3 reads
# Well within 5,500 GET/s limit
Task.async_stream(1..10_000, &read_chunk/1,
  max_concurrency: 100  # Safe concurrency level
)
```

See [Cloud Storage Performance Considerations](storage_providers.md#cloud-storage-performance-considerations) for details.

### Development and Debugging

Sequential execution is easier to debug:

```elixir
# Development: sequential for clarity
for coord <- chunk_coords do
  case read_chunk(coord) do
    {:ok, data} ->
      IO.inspect(data, label: "Chunk #{inspect(coord)}")
    {:error, reason} ->
      IO.puts("Failed #{inspect(coord)}: #{inspect(reason)}")
  end
end

# Production: parallel for performance
Task.async_stream(chunk_coords, &read_chunk/1, max_concurrency: 8)
|> Enum.to_list()
```

Use sequential execution during development, enable parallelism in production.

### When to Parallelize: Decision Tree

```
Should I parallelize this operation?
│
├─ Accessing 1-3 chunks?
│  └─ No → Sequential is simpler
│
├─ Memory-constrained?
│  └─ Yes → Limit concurrency or use streaming
│
├─ Debugging?
│  └─ Yes → Sequential for clarity
│
├─ Cloud storage with rate limits?
│  └─ Yes → Moderate concurrency (50-100)
│
├─ Accessing 4+ chunks?
│  └─ Yes → Parallelize with 4-16 workers
│
└─ Large datasets (100+ chunks)?
   └─ Yes → Parallelize with max_concurrency tuned to:
      - I/O-bound: 4-8× CPU cores
      - CPU-bound: 1-2× CPU cores
      - Storage limits: Respect rate limits
```

## Practical Examples

### Example 1: Parallel Data Export

Export array to multiple CSV files in parallel:

```elixir
defmodule DataExporter do
  def export_to_csv(array, output_dir) do
    # Get all chunk coordinates
    num_chunks = ExZarr.Metadata.num_chunks(array.metadata)
    chunk_coords = for i <- 0..(elem(num_chunks, 0) - 1),
                       j <- 0..(elem(num_chunks, 1) - 1),
                       do: {i, j}

    # Export chunks in parallel
    Task.async_stream(
      chunk_coords,
      fn {i, j} ->
        # Read chunk
        {:ok, data} = ExZarr.Array.get_slice(array,
          start: {i * 100, j * 100},
          stop: {(i + 1) * 100, (j + 1) * 100}
        )

        # Write to CSV
        csv_path = Path.join(output_dir, "chunk_#{i}_#{j}.csv")
        write_csv(csv_path, data)

        {:ok, csv_path}
      end,
      max_concurrency: 8,
      timeout: 60_000
    )
    |> Enum.to_list()
  end

  defp write_csv(path, data) do
    # Convert nested tuples to CSV format
    rows = Tuple.to_list(data)
    csv_content = Enum.map_join(rows, "\n", fn row ->
      Tuple.to_list(row) |> Enum.join(",")
    end)

    File.write!(path, csv_content)
  end
end

# Use it
DataExporter.export_to_csv(array, "/tmp/export")
```

### Example 2: Parallel Data Ingestion from S3

Read data from S3 and write to ExZarr array in parallel:

```elixir
defmodule S3Ingestion do
  def ingest_from_s3(bucket, prefix, target_array) do
    # List all source files in S3
    {:ok, files} = list_s3_files(bucket, prefix)

    # Download and write in parallel
    Task.async_stream(
      files,
      fn {file_key, chunk_coord} ->
        # Download from S3
        {:ok, data} = ExAws.S3.get_object(bucket, file_key)
                      |> ExAws.request()

        # Parse data
        parsed = parse_data(data.body)

        # Write to ExZarr array
        {i, j} = chunk_coord
        ExZarr.Array.set_slice(target_array, parsed,
          start: {i * 100, j * 100},
          stop: {(i + 1) * 100, (j + 1) * 100}
        )
      end,
      max_concurrency: 20,  # Moderate for S3 rate limits
      timeout: 120_000       # Generous timeout for network
    )
    |> Enum.to_list()
  end
end
```

### Example 3: Parallel Statistical Analysis

Compute statistics across chunks in parallel:

```elixir
defmodule ParallelStats do
  def compute_statistics(array) do
    # Process all chunks in parallel
    chunk_stats = array
    |> ExZarr.Array.parallel_chunk_map(
      fn {_index, chunk_data} ->
        # Compute statistics for this chunk
        values = flatten_chunk(chunk_data)

        %{
          min: Enum.min(values),
          max: Enum.max(values),
          sum: Enum.sum(values),
          count: length(values)
        }
      end,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.to_list()

    # Aggregate chunk statistics
    aggregate_statistics(chunk_stats)
  end

  defp aggregate_statistics(chunk_stats) do
    %{
      global_min: Enum.min_by(chunk_stats, & &1.min).min,
      global_max: Enum.max_by(chunk_stats, & &1.max).max,
      total_sum: Enum.sum(Enum.map(chunk_stats, & &1.sum)),
      total_count: Enum.sum(Enum.map(chunk_stats, & &1.count))
    }
  end

  defp flatten_chunk(data) when is_tuple(data) do
    data
    |> Tuple.to_list()
    |> Enum.flat_map(&Tuple.to_list/1)
  end
end

# Use it
stats = ParallelStats.compute_statistics(array)
# %{global_min: -10.5, global_max: 99.8, total_sum: 45000.0, total_count: 100000}
```

This pattern works for any reduce operation (sum, average, histogram, etc.).

## Cloud Storage Performance Considerations

### S3 Latency and Parallelism

S3 requests have inherent latency (50-200ms). Parallelism amortizes this cost:

```
Single S3 GET request: 100ms latency + 5ms transfer = 105ms
Sequential 100 requests: 100 × 105ms = 10,500ms

Parallel 100 requests (10 concurrent): 100/10 × 105ms = 1,050ms
Speedup: 10×
```

**Recommendation:**
- Use 10-50 concurrent requests for S3 reads
- Monitor CloudWatch metrics for throttling
- Use S3 Transfer Acceleration for cross-region access

### Network Bandwidth Constraints

Parallel I/O is limited by network bandwidth:

```
Network bandwidth: 100 MB/s
Chunk size: 8 MB (compressed)
Theoretical max: 100 MB/s / 8 MB = 12.5 chunks/s

Parallel tasks: 50 concurrent
Actual throughput: ~12 chunks/s (bandwidth-limited)
```

Beyond the bandwidth limit, adding concurrency doesn't help.

### Compression Overhead

CPU-intensive compression can bottleneck parallel writes:

```elixir
# Benchmark: write with different compression levels
for level <- [1, 3, 5, 7, 9] do
  {:ok, array} = ExZarr.create(
    compressor: {:zstd, level: level},
    # ... other config
  )

  time = :timer.tc(fn ->
    Task.async_stream(chunk_data_list, fn data ->
      write_chunk(array, data)
    end, max_concurrency: 8)
    |> Enum.to_list()
  end) |> elem(0)

  IO.puts("Level #{level}: #{div(time, 1000)}ms")
end

# Results:
# Level 1: 120ms  (fast compression, more parallelism benefit)
# Level 3: 180ms  (balanced)
# Level 9: 450ms  (slow compression, CPU bottleneck)
```

Higher compression levels reduce parallelism benefit (CPU becomes bottleneck).

## Summary

This guide covered parallel I/O patterns in ExZarr:

- **Why parallelism helps**: I/O latency hiding, multi-core decompression, no GIL constraints
- **Task.async_stream pattern**: Read/write multiple chunks concurrently
- **Concurrent read safety**: Always safe, no coordination needed
- **Concurrent write coordination**: Safe when targeting different chunks, needs locking for same chunk
- **Performance measurement**: Benchmark sequential vs parallel to quantify speedup
- **When NOT to parallelize**: Small arrays, memory constraints, sequential dependencies, rate limits, debugging

**Key takeaways:**
- Parallelize when accessing 4+ chunks
- Tune `max_concurrency` to workload (I/O-bound vs CPU-bound)
- Partition work to avoid write race conditions
- Measure actual speedup (don't assume linear scaling)
- Respect cloud storage rate limits

## Next Steps

Now that you understand parallel I/O:

1. **Configure Storage**: Set up S3 or other backends in [Storage Providers Guide](storage_providers.md)
2. **Optimize Compression**: Choose codecs for your workload in [Compression and Codecs Guide](compression_codecs.md)
3. **Tune Performance**: Chunk size and concurrency tuning in [Performance Guide](performance.md)
4. **Stream Processing**: Integrate with Broadway in [Advanced Usage Guide](advanced_usage.md)
