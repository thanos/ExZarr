# Performance and Tuning Guide

This guide provides actionable guidance for optimizing ExZarr performance across different workloads and environments. Performance is workload-dependent—the "optimal" configuration for your use case requires measurement and iteration.

## Table of Contents

- [Performance Model Overview](#performance-model-overview)
- [Chunk Size Selection Strategy](#chunk-size-selection-strategy)
- [Compressor Selection and Tuning](#compressor-selection-and-tuning)
- [Parallelism Configuration](#parallelism-configuration)
- [Memory Management (BEAM-Specific)](#memory-management-beam-specific)
- [Storage Backend Optimization](#storage-backend-optimization)
- [Measurement and Profiling](#measurement-and-profiling)
- [Rules of Thumb](#rules-of-thumb)

## Performance Model Overview

### Four Performance Dimensions

Every optimization affects multiple dimensions. Understand the tradeoffs:

1. **Throughput**: Data volume per unit time (MB/s)
2. **Latency**: Time to first byte (milliseconds)
3. **Memory**: Peak RAM usage during operations
4. **Cost**: Storage size, network transfer, compute resources

### Performance Tradeoff Triangle

```
        Fast Reads
           /\
          /  \
         /    \
        /      \
       /________\
  Small Storage  Low Write Cost
```

**Reality**: You can't optimize all three simultaneously. Choose your priorities:

- **Read-heavy workload**: Optimize for fast reads (larger chunks, light compression)
- **Storage-constrained**: Optimize for small storage (aggressive compression, larger chunks)
- **Write-heavy workload**: Optimize for low write cost (no compression, smaller chunks)

### Bottlenecks by Workload

Different storage backends have different bottlenecks:

| Storage Backend | Primary Bottleneck | Secondary Bottleneck |
|-----------------|-------------------|---------------------|
| Memory/ETS | Memory bandwidth | CPU (codecs) |
| Local SSD | CPU (decompression) | Memory bandwidth |
| Cloud (S3/GCS/Azure) | Network latency | API call rate limits |
| Database (Mnesia/MongoDB) | Query latency | Connection pool size |

**Optimization strategy**: Identify the bottleneck for your workload, then tune accordingly.

Example measurements:

```elixir
# Measure where time is spent
defmodule PerformanceBreakdown do
  def measure_operation(array, slice_spec) do
    # Time network/storage I/O
    {io_time, raw_data} = :timer.tc(fn ->
      # This would be the backend read
      fetch_raw_chunk(array)
    end)

    # Time decompression
    {decompress_time, data} = :timer.tc(fn ->
      decompress_chunk(raw_data)
    end)

    # Time binary assembly
    {assembly_time, result} = :timer.tc(fn ->
      assemble_slice(data, slice_spec)
    end)

    total = io_time + decompress_time + assembly_time

    %{
      io_pct: Float.round(io_time / total * 100, 1),
      decompress_pct: Float.round(decompress_time / total * 100, 1),
      assembly_pct: Float.round(assembly_time / total * 100, 1),
      total_ms: total / 1000
    }
  end
end

# Identify bottleneck:
# - If io_pct > 60%: Network/storage bound → parallelize, use CDN, larger chunks
# - If decompress_pct > 60%: CPU bound → lighter compression, more cores
# - If assembly_pct > 30%: Memory bound → optimize slice operations
```

## Chunk Size Selection Strategy

**The most important tuning parameter.** Chunk size affects all performance dimensions.

### Core Principles

1. **Match chunk shape to access patterns**
   - Row-wise access → Wide, short chunks
   - Column-wise access → Tall, narrow chunks
   - Random access → Square/cubic chunks

2. **Chunk size affects compression ratio**
   - Larger chunks = better compression (more context for compressor)
   - Typical improvement: 1 MB chunk vs 100 KB chunk = 10-20% better ratio

3. **Chunk is the unit of I/O**
   - Reading a single element loads the entire chunk
   - Accessing 2 bytes from a 10 MB chunk still transfers 10 MB

4. **More chunks enable more parallelism**
   - 100 chunks = up to 100-way parallelism
   - 4 chunks = maximum 4-way parallelism

### Size Guidelines by Storage Backend

| Storage Backend | Recommended Chunk Size | Rationale |
|----------------|------------------------|-----------|
| Memory/ETS | 100 KB - 1 MB | Balance memory vs granularity |
| Local SSD | 1 MB - 10 MB | Match filesystem block size, amortize syscall overhead |
| S3/Cloud | 5 MB - 50 MB | Amortize API call latency (~50ms), maximize throughput |
| Database | 1 MB - 16 MB | Match document/row size limits, avoid query overhead |

**Why these ranges?**

- **Memory**: Small chunks minimize peak memory, but too small increases process overhead
- **Local SSD**: Modern SSDs have 4KB-16KB page size; 1-10 MB balances read amplification vs memory
- **S3**: Each API call has ~50ms latency; 5 MB chunk = 100 MB/s effective, 50 MB = 1 GB/s effective
- **Database**: MongoDB document limit is 16 MB; staying below this avoids chunking within chunks

### Calculation Examples

#### Target: 10 MB chunks for S3

```elixir
# Array: {10000, 10000}, dtype: :float64 (8 bytes)

# Calculate chunk dimensions:
# 10 MB = 10_000_000 bytes
# Elements per chunk = 10_000_000 / 8 = 1_250_000
# Square chunks: sqrt(1_250_000) ≈ 1118

chunks = {1120, 1120}  # Results in 1120 * 1120 * 8 = 10,035,200 bytes (~10 MB)
```

#### Target: 1 MB chunks for local SSD

```elixir
# Array: {100, 1000, 1000}, dtype: :float32 (4 bytes)

# Target: 1 MB = 1_000_000 bytes
# Elements per chunk = 1_000_000 / 4 = 250_000

# Access pattern: Time-series (read full XY slices)
# Optimize: Single time step per chunk
chunks = {1, 500, 500}  # 1 * 500 * 500 * 4 = 1,000,000 bytes (1 MB)

# Result: Reading time step T requires reading 4 chunks (2x2 grid)
# vs {10, 100, 100} which would require reading 100 chunks (10x10 grid)
```

### Shape Guidelines

Match chunk shape to access patterns for maximum efficiency:

```elixir
# Row-wise access (read entire rows)
# Example: Processing images row-by-row
array_shape = {10000, 10000}
chunks = {10, 10000}  # Wide, short chunks
# Result: Reading 10 rows = 1 chunk read

# Column-wise access (read entire columns)
# Example: Time-series analysis across spatial dimension
array_shape = {10000, 10000}
chunks = {10000, 10}  # Tall, narrow chunks
# Result: Reading 10 columns = 1 chunk read

# Random access (access arbitrary regions)
# Example: Interactive visualization, random sampling
array_shape = {10000, 10000}
chunks = {100, 100}  # Square chunks
# Result: Any 100x100 region requires at most 4 chunks (2x2)

# Time-series (read XY slices at time T)
# Example: Climate data [time, lat, lon]
array_shape = {365, 180, 360}  # Daily data, 1° resolution
chunks = {1, 180, 360}  # Single time step per chunk
# Result: Reading one day = 1 chunk read
# Alternative: {1, 90, 90} for 4-way parallelism
```

### Testing Chunk Sizes

Always benchmark with your actual workload:

```elixir
defmodule ChunkSizeBenchmark do
  def test_sizes(array_shape, access_pattern, candidates) do
    results = for chunk_size <- candidates do
      # Create array with candidate chunk size
      {:ok, array} = ExZarr.create(
        shape: array_shape,
        chunks: chunk_size,
        dtype: :float64,
        storage: :memory,
        compressor: %{id: "zstd", level: 3}
      )

      # Populate with test data
      populate_array(array)

      # Measure typical operations
      {time_us, _} = :timer.tc(fn ->
        for _ <- 1..100 do
          perform_access(array, access_pattern)
        end
      end)

      # Calculate metrics
      chunk_bytes = calculate_chunk_bytes(chunk_size, :float64)
      num_chunks = calculate_num_chunks(array_shape, chunk_size)

      %{
        chunk_size: chunk_size,
        chunk_bytes: chunk_bytes,
        num_chunks: num_chunks,
        avg_time_ms: time_us / 100 / 1000,
        throughput_mbs: calculate_throughput(chunk_bytes, time_us)
      }
    end

    # Display results
    IO.puts("\nChunk Size Benchmark Results:")
    IO.puts("Array shape: #{inspect(array_shape)}")
    IO.puts("Access pattern: #{access_pattern}\n")

    Enum.each(results, fn r ->
      IO.puts("Chunks #{inspect(r.chunk_size)}: " <>
              "#{r.avg_time_ms} ms/op, " <>
              "#{r.throughput_mbs} MB/s, " <>
              "#{r.num_chunks} chunks total")
    end)

    results
  end

  defp perform_access(array, :row_wise) do
    ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10, 10000})
  end

  defp perform_access(array, :column_wise) do
    ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10000, 10})
  end

  defp perform_access(array, :random) do
    x = :rand.uniform(9000)
    y = :rand.uniform(9000)
    ExZarr.Array.get_slice(array, start: {x, y}, stop: {x + 100, y + 100})
  end

  defp calculate_chunk_bytes(chunk_shape, dtype) do
    elem_count = Tuple.to_list(chunk_shape) |> Enum.reduce(1, &*/2)
    elem_count * dtype_bytes(dtype)
  end

  defp dtype_bytes(:float64), do: 8
  defp dtype_bytes(:float32), do: 4
  defp dtype_bytes(:int32), do: 4
end

# Run benchmark
ChunkSizeBenchmark.test_sizes(
  {10000, 10000},
  :row_wise,
  [{10, 10000}, {100, 1000}, {1000, 100}]
)
```

**Interpretation guidelines:**

- Best chunk size should minimize time/op for your access pattern
- Throughput should be close to hardware limits (100-500 MB/s for SSD, 1-10 GB/s for memory)
- If all sizes perform similarly, choose larger chunks (better compression)
- If performance degrades with larger chunks, you're hitting memory limits

## Compressor Selection and Tuning

Compression affects read speed, write speed, storage size, and network transfer costs. See the [Compression and Codecs Guide](compression_codecs.md) for detailed codec characteristics.

### Quick Decision Tree

```
Need maximum Python compatibility?
  → Use zlib level 5-6 (always available)

Need maximum speed (real-time ingestion)?
  → Use lz4 level 1 or snappy (200-500 MB/s compression)

Need best compression ratio (archival)?
  → Use zstd level 10+ or bzip2 (3-6× compression)

Cloud storage (S3/GCS) with network costs?
  → Use zstd level 3-5 (balance network vs CPU)

Scientific/typed array data?
  → Use blosc with shuffle (optimized for numeric data)

Data integrity critical (checksums required)?
  → Add crc32c codec to pipeline

Data already compressed (images, video)?
  → Use no compression (compressor: nil)
```

### Compression Level Tuning

Higher levels = better compression, slower speed. Benchmark to find the sweet spot:

```elixir
defmodule CompressionBenchmark do
  def test_levels(codec, levels, data_generator) do
    # Generate test data (representative of your actual data)
    raw_data = data_generator.()
    raw_size = byte_size(raw_data)

    IO.puts("\n=== Compression Benchmark: #{codec} ===")
    IO.puts("Raw data size: #{format_bytes(raw_size)}\n")

    results = for level <- levels do
      # Benchmark compression
      {compress_times, compressed_results} =
        Enum.map(1..10, fn _ ->
          :timer.tc(fn ->
            compress(codec, raw_data, level: level)
          end)
        end)
        |> Enum.unzip()

      avg_compress_us = Enum.sum(compress_times) / length(compress_times)
      compressed = hd(compressed_results)
      compressed_size = byte_size(compressed)

      # Benchmark decompression
      {decompress_times, _} =
        Enum.map(1..10, fn _ ->
          :timer.tc(fn ->
            decompress(codec, compressed, level: level)
          end)
        end)
        |> Enum.unzip()

      avg_decompress_us = Enum.sum(decompress_times) / length(decompress_times)

      # Calculate metrics
      ratio = raw_size / compressed_size
      compress_mbs = raw_size / avg_compress_us
      decompress_mbs = raw_size / avg_decompress_us

      %{
        level: level,
        ratio: Float.round(ratio, 2),
        compressed_size: compressed_size,
        compress_ms: Float.round(avg_compress_us / 1000, 2),
        decompress_ms: Float.round(avg_decompress_us / 1000, 2),
        compress_mbs: Float.round(compress_mbs, 1),
        decompress_mbs: Float.round(decompress_mbs, 1)
      }
    end

    # Display results
    IO.puts("Level | Ratio | Size      | Comp(ms) | Decomp(ms) | Comp(MB/s) | Decomp(MB/s)")
    IO.puts("------|-------|-----------|----------|------------|------------|-------------")

    Enum.each(results, fn r ->
      IO.puts("#{String.pad_leading(to_string(r.level), 5)} | " <>
              "#{String.pad_leading("#{r.ratio}×", 5)} | " <>
              "#{String.pad_leading(format_bytes(r.compressed_size), 9)} | " <>
              "#{String.pad_leading(to_string(r.compress_ms), 8)} | " <>
              "#{String.pad_leading(to_string(r.decompress_ms), 10)} | " <>
              "#{String.pad_leading(to_string(r.compress_mbs), 10)} | " <>
              "#{String.pad_leading(to_string(r.decompress_mbs), 11)}")
    end)

    results
  end

  # Generate representative test data
  def generate_scientific_data do
    # Simulated float64 sensor readings (has structure, compresses well)
    for _ <- 1..125_000, into: <<>> do
      value = :rand.normal(100.0, 15.0)
      <<value::float-64-little>>
    end
  end

  def generate_random_data do
    # Random data (doesn't compress)
    :crypto.strong_rand_bytes(1_000_000)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)}MB"
end

# Test zstd levels 1-9 with scientific data
CompressionBenchmark.test_levels(
  :zstd,
  1..9,
  &CompressionBenchmark.generate_scientific_data/0
)
```

**Example output** (1 MB scientific data on M1 Max):

```
Level | Ratio | Size      | Comp(ms) | Decomp(ms) | Comp(MB/s) | Decomp(MB/s)
------|-------|-----------|----------|------------|------------|-------------
    1 |  2.8× |   357.1KB |     5.2  |       2.1  |      192.3 |       476.2
    3 |  3.2× |   312.5KB |     8.7  |       2.0  |      114.9 |       500.0
    5 |  3.5× |   285.7KB |    15.3  |       2.0  |       65.4 |       500.0
    7 |  3.7× |   270.3KB |    28.4  |       2.1  |       35.2 |       476.2
    9 |  3.8× |   263.2KB |    52.1  |       2.2  |       19.2 |       454.5
```

**Recommendation**: For this data, level 3 provides good balance (3.2× compression, 115 MB/s).

### Cloud Storage Cost Analysis

Network transfer costs can dominate for large datasets:

```elixir
defmodule CloudCostAnalysis do
  def calculate_transfer_cost(data_size_gb, compression_ratio, cost_per_gb \\ 0.09) do
    uncompressed_cost = data_size_gb * cost_per_gb
    compressed_cost = (data_size_gb / compression_ratio) * cost_per_gb

    %{
      uncompressed_gb: data_size_gb,
      compressed_gb: Float.round(data_size_gb / compression_ratio, 2),
      uncompressed_cost: Float.round(uncompressed_cost, 2),
      compressed_cost: Float.round(compressed_cost, 2),
      savings: Float.round(uncompressed_cost - compressed_cost, 2),
      savings_pct: Float.round((1 - 1/compression_ratio) * 100, 1)
    }
  end
end

# Example: 1 TB dataset read 10 times/month
data_size = 1000  # GB
reads_per_month = 10
compression_ratio = 3.2  # zstd level 3

cost = CloudCostAnalysis.calculate_transfer_cost(
  data_size * reads_per_month,
  compression_ratio,
  0.09  # AWS data transfer cost per GB
)

IO.inspect(cost)
# Output:
# %{
#   uncompressed_gb: 10000,
#   compressed_gb: 3125.0,
#   uncompressed_cost: 900.0,
#   compressed_cost: 281.25,
#   savings: 618.75,
#   savings_pct: 68.8
# }
```

**Conclusion**: For cloud workloads, compression typically pays for itself even with CPU overhead.

## Parallelism Configuration

BEAM provides lightweight processes and efficient scheduling. Use parallelism correctly to maximize throughput.

### BEAM Scheduler Utilization

```elixir
# Check available schedulers
cpu_cores = System.schedulers_online()
IO.puts("Available CPU cores: #{cpu_cores}")

# Optimal concurrency depends on workload:

# CPU-bound work (compression, computation)
cpu_bound_concurrency = cpu_cores
# Use 1× cores: CPU saturates quickly, more tasks = more overhead

# Balanced work (decompression + memory ops)
balanced_concurrency = cpu_cores * 2
# Use 2× cores: Some I/O wait, mild oversubscription helps

# I/O-bound work (S3 reads, database queries)
io_bound_concurrency = cpu_cores * 4  # or higher
# Use 4-8× cores: Mostly waiting on I/O, high concurrency hides latency
```

### Task.async_stream Configuration

ExZarr uses `Task.async_stream` for parallel chunk operations:

```elixir
# Conservative (prioritize memory, predictable latency)
array
|> ExZarr.Array.chunk_stream()
|> Task.async_stream(&process_chunk/1,
     max_concurrency: 4,      # Limit concurrent tasks
     ordered: true,            # Maintain chunk order
     timeout: 30_000           # 30 second timeout per chunk
   )
|> Enum.to_list()

# Aggressive (prioritize throughput, can handle latency spikes)
array
|> ExZarr.Array.chunk_stream()
|> Task.async_stream(&process_chunk/1,
     max_concurrency: 16,     # High concurrency
     ordered: false,           # Skip ordering overhead
     timeout: 60_000,          # Longer timeout for slow chunks
     on_timeout: :kill_task    # Don't wait for stragglers
   )
|> Enum.to_list()

# Adaptive (adjust based on array size)
concurrency = cond do
  num_chunks < 4 -> 1           # Sequential for tiny arrays
  num_chunks < 16 -> 4          # Moderate parallelism
  num_chunks < 64 -> 8          # Higher parallelism
  true -> 16                     # Maximum parallelism
end
```

### Measuring Parallel Efficiency

Parallelism doesn't always help. Measure speedup and efficiency:

```elixir
defmodule ParallelEfficiency do
  def measure_speedup(array, operation, concurrency_levels) do
    # Sequential baseline
    {seq_time, _} = :timer.tc(fn ->
      Enum.each(get_chunk_indices(array), fn idx ->
        operation.(array, idx)
      end)
    end)

    seq_time_ms = seq_time / 1000

    IO.puts("\n=== Parallel Efficiency Measurement ===")
    IO.puts("Sequential time: #{Float.round(seq_time_ms, 2)} ms\n")
    IO.puts("Concurrency | Time(ms) | Speedup | Efficiency")
    IO.puts("------------|----------|---------|------------")

    for concurrency <- concurrency_levels do
      {par_time, _} = :timer.tc(fn ->
        get_chunk_indices(array)
        |> Task.async_stream(
             fn idx -> operation.(array, idx) end,
             max_concurrency: concurrency
           )
        |> Enum.to_list()
      end)

      par_time_ms = par_time / 1000
      speedup = seq_time / par_time
      efficiency = speedup / concurrency * 100

      IO.puts("#{String.pad_leading(to_string(concurrency), 11)} | " <>
              "#{String.pad_leading(Float.round(par_time_ms, 2) |> to_string(), 8)} | " <>
              "#{String.pad_leading(Float.round(speedup, 2) |> to_string(), 7)}× | " <>
              "#{String.pad_leading(Float.round(efficiency, 1) |> to_string(), 9)}%")
    end
  end

  defp get_chunk_indices(array) do
    # Return list of all chunk indices for array
    # Implementation depends on array structure
  end
end

# Example usage
{:ok, array} = ExZarr.open(path: "/data/my_array")

ParallelEfficiency.measure_speedup(
  array,
  fn arr, idx -> ExZarr.Array.read_chunk(arr, idx) end,
  [1, 2, 4, 8, 16]
)
```

**Example output**:

```
Concurrency | Time(ms) | Speedup | Efficiency
------------|----------|---------|------------
          1 |   850.00 |    1.00× |     100.0%
          2 |   440.00 |    1.93× |      96.5%  # Good efficiency
          4 |   230.00 |    3.70× |      92.5%  # Good efficiency
          8 |   145.00 |    5.86× |      73.3%  # Acceptable
         16 |   125.00 |    6.80× |      42.5%  # Diminishing returns
```

**Interpretation:**
- 100% efficiency = perfect speedup (rare)
- >80% efficiency = excellent, keep increasing concurrency
- 50-80% efficiency = good, might be hitting limits
- <50% efficiency = poor, overhead dominates or resource contention

### When NOT to Use Parallelism

Parallelism has overhead. Skip it for:

```elixir
# 1. Small operations (< 1ms per chunk)
# Overhead: ~0.1-0.5ms per task spawn
# If operation is 0.5ms, overhead is 20-100%

# 2. Sequential dependencies
# If chunks must be processed in order with state

# 3. Memory-constrained environments
# Parallel processing peaks at: concurrency × chunk_size

# 4. Very small chunk counts
# Example: 2 chunks with 8-way parallelism = 6 wasted tasks

# Decision helper:
def should_parallelize?(num_chunks, chunk_time_estimate_ms) do
  cond do
    num_chunks < 3 -> false                        # Too few chunks
    chunk_time_estimate_ms < 1.0 -> false          # Too fast (overhead dominates)
    chunk_time_estimate_ms > 10.0 -> true          # Slow operations benefit
    num_chunks > 16 -> true                        # Many chunks = good parallelism
    true -> num_chunks > 4 && chunk_time_estimate_ms > 2.0  # Moderate case
  end
end
```

## Memory Management (BEAM-Specific)

Understanding BEAM's memory model helps optimize ExZarr memory usage.

### BEAM Memory Model

Key characteristics:

1. **Per-process heaps**: Each process has its own generational GC
2. **Shared binary heap**: Binaries >64 bytes stored separately (reference counted)
3. **Cheap binary passing**: Passing large binaries between processes is efficient (just copies reference)
4. **GC is per-process**: One slow process doesn't block others

**Implications for ExZarr:**

```elixir
# Chunk data is stored as binaries
chunk_data = <<...>>  # 10 MB binary

# This is efficient (just copies reference, not data)
Task.async(fn -> process_chunk(chunk_data) end)

# Multiple processes can hold references to same binary
# Only when all references are dropped does memory free
```

### Memory Usage Formula

Estimate peak memory for operations:

```
Peak Memory ≈ (concurrent_chunks × chunk_size × compression_overhead) + base_overhead

Where:
- concurrent_chunks: max_concurrency setting
- chunk_size: uncompressed chunk size in bytes
- compression_overhead: 1.5-2.0× (temporary buffers during decompression)
- base_overhead: 50-100 MB (BEAM VM, application code)

Example:
- Chunk size: 10 MB
- Concurrency: 8
- Compression overhead: 1.5×
- Peak: (8 × 10 MB × 1.5) + 100 MB = 220 MB
```

### Measuring Memory Usage

```elixir
defmodule MemoryMonitor do
  def measure_operation(operation_fn) do
    # Force GC to get clean baseline
    :erlang.garbage_collect()
    Process.sleep(100)

    before = :erlang.memory(:total)
    before_binary = :erlang.memory(:binary)

    # Run operation
    result = operation_fn.()

    after_total = :erlang.memory(:total)
    after_binary = :erlang.memory(:binary)

    # Force GC to see persistent memory
    :erlang.garbage_collect()
    Process.sleep(100)

    after_gc = :erlang.memory(:total)

    %{
      result: result,
      peak_mb: (after_total - before) / 1_024 / 1_024,
      binary_mb: (after_binary - before_binary) / 1_024 / 1_024,
      retained_mb: (after_gc - before) / 1_024 / 1_024
    }
  end
end

# Example usage
mem_stats = MemoryMonitor.measure_operation(fn ->
  {:ok, array} = ExZarr.open(path: "/data/my_array")
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1000, 1000})
end)

IO.puts("Peak memory: #{Float.round(mem_stats.peak_mb, 2)} MB")
IO.puts("Binary memory: #{Float.round(mem_stats.binary_mb, 2)} MB")
IO.puts("Retained after GC: #{Float.round(mem_stats.retained_mb, 2)} MB")
```

### Reducing Memory Usage

Four strategies:

#### 1. Smaller Chunks

```elixir
# High memory (10 MB chunks, 8 concurrent = 80+ MB peak)
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},  # 10 MB chunks
  dtype: :float64
)

# Lower memory (2.5 MB chunks, 8 concurrent = 20+ MB peak)
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {500, 500},  # 2.5 MB chunks
  dtype: :float64
)
```

#### 2. Lower Concurrency

```elixir
# High memory (16 concurrent tasks)
array
|> ExZarr.Array.chunk_stream()
|> Task.async_stream(&process/1, max_concurrency: 16)
|> Enum.to_list()

# Lower memory (4 concurrent tasks)
array
|> ExZarr.Array.chunk_stream()
|> Task.async_stream(&process/1, max_concurrency: 4)
|> Enum.to_list()
```

#### 3. Streaming (Constant Memory)

```elixir
# Loads entire result into memory
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10000, 10000})
# Peak memory: 10000 × 10000 × 8 = 800 MB

# Streams chunks (constant memory)
array
|> ExZarr.Array.chunk_stream(parallel: 1)  # Sequential for minimum memory
|> Stream.each(fn {_index, chunk_data} ->
     process_chunk(chunk_data)
     # chunk_data can be GC'd after processing
   end)
|> Stream.run()
# Peak memory: single chunk size (~10 MB)
```

#### 4. Avoid Intermediate Copies

```elixir
# Bad: Creates intermediate binary copies
def process_chunk(data) do
  data
  |> binary_to_list()      # Copy 1: binary → list
  |> Enum.map(&(&1 * 2))   # Copy 2: new list
  |> list_to_binary()      # Copy 3: list → binary
end

# Good: Use binary pattern matching (zero-copy)
def process_chunk(data) do
  for <<value::float-64-little <- data>>, into: <<>> do
    <<value * 2::float-64-little>>
  end
end
```

### Memory Limits

Set VM limits to protect against OOM:

```bash
# Limit maximum memory (in MB)
elixir --erl "+MMscs 4096" -S mix run my_script.exs

# Or in vm.args:
# +MMscs 4096
```

Monitor memory during development:

```elixir
# Start observer GUI
:observer.start()

# Or programmatically check memory
if :erlang.memory(:total) > 1_000_000_000 do  # > 1 GB
  IO.warn("High memory usage: #{:erlang.memory(:total) / 1_048_576} MB")
end
```

## Storage Backend Optimization

Different backends have different performance characteristics.

### Filesystem

**Best for**: Local development, single-machine deployments

Optimizations:

```elixir
# 1. Use SSD, not HDD
# SSD: 50,000+ IOPS, 500+ MB/s
# HDD: 100-200 IOPS, 100-200 MB/s

# 2. Avoid network filesystems (NFS, SMB)
# Local SSD: ~0.1ms read latency
# NFS: ~1-10ms read latency (10-100× slower)

# 3. Choose appropriate filesystem
# XFS: Good for many small files
# ext4: General purpose
# Avoid: NTFS on Linux (compatibility layer overhead)

# 4. Enable filesystem-level compression (transparent)
# ZFS: compression=lz4 (minimal overhead)
# Btrfs: compress=zstd:3
```

Performance tips:

```elixir
# Batch operations when possible
# Bad: 100 separate create calls
for i <- 1..100 do
  {:ok, _} = ExZarr.create(path: "/data/array_#{i}", ...)
end

# Better: Create fewer arrays with more chunks
{:ok, _} = ExZarr.create(path: "/data/batch_array", shape: {100, 1000, 1000}, ...)
```

### S3 (and compatible: Minio, DigitalOcean Spaces)

**Best for**: Cloud deployments, shared data, archival

Optimizations:

```elixir
# 1. Use S3 Transfer Acceleration for cross-region
config :ex_aws, :s3,
  scheme: "https://",
  host: "my-bucket.s3-accelerate.amazonaws.com"

# 2. Partition across multiple prefixes for high throughput
# S3 rate limits: 5,500 GET/s, 3,500 PUT/s per prefix
# Use multiple prefixes for higher aggregate throughput:
storage: :s3,
bucket: "my-bucket",
prefix: "arrays/dataset_#{rem(array_id, 10)}"  # 10 prefixes = 10× rate limit

# 3. Use CloudFront CDN for read-heavy workloads
# S3 direct: 50-100ms latency
# CloudFront: 10-30ms latency (edge caching)

# 4. Enable S3 Intelligent-Tiering for cost optimization
# Automatically moves old data to cheaper tiers
```

Cost considerations:

```elixir
# S3 cost breakdown (us-east-1, 2026)
# Storage: $0.023/GB/month (Standard), $0.0125/GB/month (IA)
# GET requests: $0.0004 per 1000 requests
# Data transfer: $0.09/GB out to internet

# Example: 1 TB array, read 100 times/month
storage_cost = 1000 * 0.023  # $23/month
request_cost = (100 * 1000) / 1000 * 0.0004  # Assume 1000 chunks = $0.04/month
transfer_cost = 100 * 1000 * 0.09  # $9,000/month (!!)

# WITH compression (3× ratio):
transfer_cost_compressed = 100 * (1000 / 3) * 0.09  # $3,000/month
savings = 9000 - 3000  # $6,000/month saved

# Conclusion: Compression is essential for S3
```

### GCS (Google Cloud Storage)

**Best for**: Google Cloud deployments, BigQuery integration

Optimizations similar to S3, with GCS-specific features:

```elixir
# 1. Use regional buckets (not multi-region) for lower latency
# Regional: ~20ms
# Multi-region: ~50ms

# 2. Enable requester pays for shared datasets
# Consumers pay for their own data transfer

# 3. Use signed URLs for temporary access
# Avoids authentication overhead
```

### Azure Blob Storage

**Best for**: Azure deployments, Windows environments

Optimizations:

```elixir
# 1. Use Premium Block Blobs for high IOPS
# Standard: ~500 IOPS/blob
# Premium: ~100,000 IOPS/blob

# 2. Use Azure CDN for edge caching
# Similar benefits to CloudFront

# 3. Enable blob index tags for metadata queries
# Fast filtering without reading blob data
```

### In-Memory (Memory/ETS)

**Best for**: Temporary data, testing, caching layer

```elixir
# Memory backend: Simple Agent-based
storage: :memory
# Pros: Simplest implementation
# Cons: Not shared between processes

# ETS backend: Shared ETS table
storage: :ets,
table_name: :my_cache
# Pros: Shared across processes, concurrent reads
# Cons: Single-node only, 2GB default table limit

# Configure ETS limits
:ets.new(:my_cache, [
  :named_table,
  :public,
  read_concurrency: true,       # Enable concurrent reads
  write_concurrency: true,      # Enable concurrent writes
  compressed: true              # Store data compressed (slower but less memory)
])
```

Use in-memory storage as a cache layer:

```elixir
# Two-tier storage: Memory cache + S3 backing
defmodule TwoTierStorage do
  def read_chunk(array, chunk_index) do
    # Try memory cache first
    case ExZarr.Array.read_chunk(memory_array, chunk_index) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        # Cache miss, fetch from S3
        {:ok, data} = ExZarr.Array.read_chunk(s3_array, chunk_index)
        # Populate cache
        ExZarr.Array.write_chunk(memory_array, chunk_index, data)
        {:ok, data}
    end
  end
end
```

### Database (Mnesia/MongoDB)

**Best for**: Applications already using these databases, need transactional semantics

```elixir
# Mnesia: Erlang native, ACID transactions
storage: :mnesia,
table_name: :my_array_chunks
# Pros: Distributed, transactions, Erlang native
# Cons: Not designed for large blobs, memory resident by default

# MongoDB GridFS: Document database with file support
storage: :mongo_gridfs,
database: "my_database",
collection: "my_arrays"
# Pros: Good for large blobs, distributed
# Cons: Slower than object storage, query overhead
```

Optimization tips:

```elixir
# 1. Use connection pooling
config :mongodb,
  pool_size: 10  # Concurrent connections

# 2. Batch writes when possible
# Group multiple chunk writes into single transaction

# 3. Index metadata fields
# If querying arrays by attributes
```

## Measurement and Profiling

**Rule**: Always measure before optimizing. Profile to find actual bottlenecks.

### Basic Timing

```elixir
# Simple timing
{time_us, result} = :timer.tc(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1000, 1000})
end)

IO.puts("Operation took #{time_us / 1000} ms")
```

### Detailed Profiling with :fprof

Find hot spots in your code:

```elixir
# Start profiling
:fprof.trace([:start, {:procs, [self()]}])

# Run your operation
{:ok, array} = ExZarr.open(path: "/data/my_array")
ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1000, 1000})

# Stop profiling and analyze
:fprof.trace(:stop)
:fprof.profile()
:fprof.analyse(dest: 'profile_results.txt', sort: :own)

# Read top results
File.read!('profile_results.txt')
|> String.split("\n")
|> Enum.take(50)
|> IO.puts()
```

Look for:
- High `own` time = function doing actual work
- High `acc` time = function + callees (may be coordinator)
- High call count with low time = overhead from small function calls

### Memory Profiling

```elixir
# Track memory during operation
:recon.proc_window(:memory, 10, 1000)

# Run your operation in a separate process
task = Task.async(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10000, 10000})
end)

# Monitor its memory
Process.monitor(task.pid)
receive do
  {:DOWN, _ref, :process, _pid, _reason} -> :ok
after
  60_000 -> :timeout
end
```

### Using :observer

Interactive monitoring:

```elixir
# Start observer GUI
:observer.start()

# Navigate to:
# - System tab: Overall memory, CPU usage
# - Load Charts tab: Scheduler utilization, memory growth
# - Applications tab: Per-application memory/process count
# - Processes tab: Per-process memory, reductions, message queue

# Run your operations and watch metrics change
```

### Benchmarking with Benchee

Comprehensive benchmarking:

```elixir
Mix.install([:benchee])

{:ok, array} = ExZarr.open(path: "/data/my_array")

Benchee.run(
  %{
    "read_single_chunk" => fn ->
      ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
    end,
    "read_four_chunks" => fn ->
      ExZarr.Array.get_slice(array, start: {0, 0}, stop: {200, 200})
    end,
    "read_sixteen_chunks" => fn ->
      ExZarr.Array.get_slice(array, start: {0, 0}, stop: {400, 400})
    end
  },
  time: 10,              # 10 seconds per benchmark
  memory_time: 2,        # 2 seconds memory measurement
  warmup: 2,             # 2 second warmup
  parallel: 1,           # Sequential (not parallel benchmarking)
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "benchmark_results.html"}
  ]
)
```

### Real-World Benchmark Script

Complete script for benchmarking your workload:

```elixir
#!/usr/bin/env elixir

Mix.install([:ex_zarr, :benchee])

defmodule WorkloadBenchmark do
  def run(array_path, workload_specs) do
    {:ok, array} = ExZarr.open(path: array_path)

    IO.puts("\n=== ExZarr Workload Benchmark ===")
    IO.puts("Array: #{array_path}")
    IO.puts("Shape: #{inspect(array.metadata.shape)}")
    IO.puts("Chunks: #{inspect(array.metadata.chunks)}")
    IO.puts("Dtype: #{array.metadata.dtype}")
    IO.puts("")

    # Build benchmark suite from workload specs
    suite = for {name, slice_spec} <- workload_specs, into: %{} do
      {name, fn -> ExZarr.Array.get_slice(array, slice_spec) end}
    end

    Benchee.run(suite,
      time: 5,
      memory_time: 1,
      warmup: 1,
      formatters: [Benchee.Formatters.Console]
    )
  end
end

# Define your typical workloads
workloads = [
  {"single_chunk_read", [start: {0, 0}, stop: {100, 100}]},
  {"row_slice", [start: {0, 0}, stop: {10, 10000}]},
  {"column_slice", [start: {0, 0}, stop: {10000, 10}]},
  {"small_random_region", [start: {500, 500}, stop: {600, 600}]},
  {"large_random_region", [start: {0, 0}, stop: {1000, 1000}]}
]

WorkloadBenchmark.run("/data/my_array", workloads)
```

Run with: `chmod +x benchmark.exs && ./benchmark.exs`

## Rules of Thumb

Quick reference for common scenarios.

### Chunk Size

- **Local storage**: 1-10 MB per chunk
- **Cloud storage**: 5-50 MB per chunk
- **Never**: <100 KB (too many files) or >100 MB (memory pressure)
- **Shape**: Match access pattern (wide for rows, tall for columns, square for random)

### Compression

- **Default**: zstd level 3 for cloud, zlib level 5-6 for compatibility
- **Speed priority**: lz4 level 1 or snappy (200-500 MB/s)
- **Compression priority**: zstd level 10+ or bzip2 (3-6× ratio)
- **Scientific data**: blosc with shuffle filter
- **Already compressed**: No compression (images, video, encrypted data)

### Parallelism

- **Start with**: 2× CPU cores for balanced workloads
- **I/O-bound (S3)**: 4-8× CPU cores
- **CPU-bound**: 1× CPU cores
- **Memory-constrained**: Reduce until peak memory acceptable
- **Always**: Measure efficiency, don't assume parallelism helps

### Memory

- **Budget formula**: concurrency × chunk_size × 2 (safety factor)
- **Monitor**: Use :observer during development
- **Test with**: Production data sizes, not toy examples
- **Streaming**: Use chunk_stream(parallel: 1) for constant memory

### Testing

- **Realistic data**: Don't benchmark with all zeros
- **Target infrastructure**: Laptop results don't predict server performance
- **Warm and cold**: Test both cached (warm) and uncached (cold) scenarios
- **Error cases**: Include network failures, missing chunks in tests
- **Multiple runs**: Average 5-10 runs to account for variance

### Optimization Priority

1. **Measure first**: Profile to find actual bottleneck
2. **Chunk size**: Most impactful parameter, tune first
3. **Compression**: Balance network/storage vs CPU cost
4. **Parallelism**: Adds complexity, only if measurements show benefit
5. **Advanced tuning**: Only after exhausting above options

### Red Flags

Stop and reconsider if you see:

- Chunk operations taking >1 second (investigate slow storage/compression)
- Memory growing unbounded (check for leaks, use streaming)
- Parallel efficiency <30% (overhead dominates, reduce concurrency)
- More than 1 million chunks (array too granular, increase chunk size)
- Compression ratio <1.1× (data doesn't compress, disable compression)
- 99% time in decompression (try faster codec: lz4, snappy, or no compression)

## Summary

Performance optimization is iterative:

1. **Measure** your workload's baseline performance
2. **Identify** the bottleneck (CPU, network, memory)
3. **Tune** the most relevant parameter (chunk size, compression, parallelism)
4. **Measure again** to verify improvement
5. **Repeat** until performance is acceptable

The "optimal" configuration depends on:
- Access patterns (row-wise, column-wise, random)
- Storage backend (memory, SSD, cloud)
- Data characteristics (structured, random, pre-compressed)
- Resource constraints (memory limits, cost budget, latency SLA)

**Next steps:**
- Run the benchmark scripts in this guide on your workload
- Profile your slowest operations with :fprof
- Experiment with 2-3 chunk sizes and compression levels
- Measure before and after each change

For workload-specific advice, see:
- [Parallel I/O Guide](parallel_io.md) for concurrent read/write patterns
- [Compression and Codecs Guide](compression_codecs.md) for codec selection
- [Storage Providers Guide](storage_providers.md) for backend configuration
