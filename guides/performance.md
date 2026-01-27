# ExZarr Performance Guide

This guide provides recommendations for optimizing ExZarr performance and understanding performance characteristics.

## Table of Contents

- [Quick Start](#quick-start)
- [Chunk Size Optimization](#chunk-size-optimization)
- [Compression Selection](#compression-selection)
- [Memory Management](#memory-management)
- [Concurrent Access](#concurrent-access)
- [Storage Backend Selection](#storage-backend-selection)
- [Profiling and Benchmarking](#profiling-and-benchmarking)
- [Common Patterns](#common-patterns)

## Quick Start

### Running Benchmarks

```bash
# Install dependencies
mix deps.get

# Run all benchmarks
mix run benchmarks/compression_bench.exs
mix run benchmarks/io_bench.exs
mix run benchmarks/slicing_bench.exs
mix run benchmarks/concurrent_bench.exs
```

### Performance Checklist

- Choose appropriate chunk size (typically 1-10 MB uncompressed)
- Enable caching for read-heavy workloads
- Use parallel streaming for large arrays
- Select compression based on data characteristics
- Use memory storage for temporary data
- Batch operations when possible

## Chunk Size Optimization

### Principles

Chunk size affects:
- **Memory usage**: Larger chunks = more memory per operation
- **I/O efficiency**: Larger chunks = fewer storage operations
- **Parallelism**: More chunks = better parallel scalability
- **Compression ratio**: Larger chunks = better compression

### Recommendations

```elixir
# Good: Balanced chunk size
{:ok, array} = ExZarr.create(
  shape: {10_000, 10_000},
  chunks: {1000, 1000},  # ~4 MB per chunk
  dtype: :float32
)

# Too small: Excessive overhead
chunks: {10, 10}  # Only 400 bytes

# Too large: High memory usage
chunks: {10_000, 10_000}  # 400 MB per chunk
```

### Chunk Size Formula

Target 1-10 MB uncompressed:

```
chunk_size_bytes = product(chunk_shape) * dtype_bytes
target_range: 1_000_000 to 10_000_000 bytes
```

For `float32` (4 bytes):
- 1D: 250K to 2.5M elements
- 2D: 500x500 to 1500x1500
- 3D: 100x100x25 to 250x250x40

## Compression Selection

### Codec Comparison

| Codec | Speed | Ratio | Best For |
|-------|-------|-------|----------|
| Blosc/LZ4 | Fastest | Low | Real-time data, fast access |
| Blosc/Zstd | Fast | Medium | Balanced performance |
| Zlib | Medium | Medium | General purpose |
| Gzip | Medium | Medium | Compatibility |
| Blosc/LZ4HC | Slow | High | Long-term storage |

### Usage Examples

```elixir
# Fast access (minimal compression)
compressor: %{id: "blosc", cname: "lz4", clevel: 3, shuffle: "shuffle"}

# Balanced (recommended)
compressor: %{id: "blosc", cname: "zstd", clevel: 5, shuffle: "bitshuffle"}

# Maximum compression
compressor: %{id: "blosc", cname: "lz4hc", clevel: 9, shuffle: "bitshuffle"}

# No compression (fastest)
compressor: nil
```

### Data-Specific Recommendations

**Floating-point data**: Use `bitshuffle` for better compression

```elixir
compressor: %{
  id: "blosc",
  cname: "zstd",
  clevel: 5,
  shuffle: "bitshuffle"  # Important for floats
}
```

**Integer data**: Use standard `shuffle`

```elixir
compressor: %{
  id: "blosc",
  cname: "lz4",
  clevel: 3,
  shuffle: "shuffle"
}
```

**Random/encrypted data**: Disable compression

```elixir
compressor: nil
```

## Memory Management

### Enable Caching for Read-Heavy Workloads

```elixir
{:ok, array} = ExZarr.create(
  shape: {10_000, 10_000},
  chunks: {1000, 1000},
  dtype: :float32,
  cache_enabled: true  # Enable LRU cache
)
```

Cache is most effective when:
- Reading same chunks repeatedly
- Random access patterns
- Working set fits in memory

### Streaming for Large Arrays

Process large arrays without loading into memory:

```elixir
# Sequential streaming (constant memory)
array
|> ExZarr.Array.chunk_stream(parallel: 1)
|> Stream.each(fn {index, data} ->
  process_chunk(index, data)
end)
|> Stream.run()

# Parallel streaming with controlled concurrency
array
|> ExZarr.Array.chunk_stream(parallel: 4)
|> Enum.each(fn {index, data} ->
  process_chunk(index, data)
end)
```

### Memory Profiling

```elixir
# Profile memory usage
:erlang.memory(:total) |> IO.inspect(label: "Before")
result = your_operation()
:erlang.garbage_collect()
:erlang.memory(:total) |> IO.inspect(label: "After")
```

## Concurrent Access

### Parallel Reads

Multiple processes can read concurrently:

```elixir
tasks = for chunk_index <- chunk_indices do
  Task.async(fn ->
    Array.get_slice(array, ...)
  end)
end

results = Task.await_many(tasks)
```

### Parallel Writes

Writes to different chunks are automatically serialized for safety:

```elixir
# Safe: Different chunks
tasks = [
  Task.async(fn -> Array.set_slice(array, data1, start: {0, 0}, ...) end),
  Task.async(fn -> Array.set_slice(array, data2, start: {100, 100}, ...) end)
]

Task.await_many(tasks)
```

### Chunk Streaming Performance

```elixir
# Sequential: Lowest memory, good for I/O bound
parallel: 1

# Moderate parallelism: Balanced (recommended)
parallel: 4

# High parallelism: Best for CPU-bound processing
parallel: System.schedulers_online()
```

## Storage Backend Selection

### Memory Storage

**Best for**: Temporary data, testing, small arrays

```elixir
storage: :memory
```

Pros:
- Fastest access
- No I/O overhead
- No cleanup needed

Cons:
- Limited by RAM
- Not persistent
- No sharing between processes

### Filesystem Storage

**Best for**: Local persistence, development

```elixir
storage: :filesystem,
path: "/path/to/data"
```

Pros:
- Simple and reliable
- Good performance on SSDs
- Easy debugging

Cons:
- Limited to single machine
- File system overhead

### S3 Storage

**Best for**: Cloud deployment, shared data, archival

```elixir
storage: :s3,
bucket: "my-bucket",
prefix: "arrays/dataset1"
```

Pros:
- Scalable
- Durable
- Shareable

Cons:
- Higher latency
- Network costs
- Eventual consistency

### Performance Comparison

| Operation | Memory | Filesystem | S3 |
|-----------|--------|------------|-----|
| Read 1 chunk | ~1 μs | ~100 μs | ~50 ms |
| Write 1 chunk | ~1 μs | ~500 μs | ~100 ms |
| Create array | ~10 μs | ~1 ms | ~50 ms |

## Profiling and Benchmarking

### Basic Profiling

```elixir
# Time measurement
{time_us, result} = :timer.tc(fn ->
  your_operation()
end)

IO.puts("Operation took #{time_us / 1000} ms")
```

### CPU Profiling with :fprof

```elixir
:fprof.trace([:start])
your_operation()
:fprof.trace([:stop])
:fprof.profile()
:fprof.analyse(dest: 'profile_results.txt')
```

### Memory Profiling

```elixir
# Track allocations
:redbug.start('erlang:binary_to_term/1 -> return', [msgs: 100])
your_operation()
```

### Using :observer

```elixir
# Start observer GUI
:observer.start()

# Monitor while running operations
your_operation()
```

## Common Patterns

### Batch Processing

Process chunks in batches for efficiency:

```elixir
array
|> Array.chunk_stream(parallel: 4)
|> Stream.chunk_every(100)
|> Stream.each(fn batch ->
  process_batch(batch)
end)
|> Stream.run()
```

### Progressive Loading

Load data progressively to show results early:

```elixir
array
|> Array.chunk_stream(
  parallel: 4,
  progress_callback: fn done, total ->
    IO.write("\rProgress: #{done}/#{total}")
  end
)
|> Stream.each(&process_chunk/1)
|> Stream.run()
```

### Selective Processing

Process only specific chunks:

```elixir
array
|> Array.chunk_stream(
  filter: fn chunk_index ->
    # Only process chunks where x is even
    {x, _y} = chunk_index
    rem(x, 2) == 0
  end
)
|> Enum.each(&process_chunk/1)
```

### Aggregation

Efficiently aggregate large arrays:

```elixir
sum = array
  |> Array.chunk_stream(parallel: 8)
  |> Stream.map(fn {_index, data} ->
    # Sum this chunk
    data
    |> :binary.bin_to_list()
    |> Enum.sum()
  end)
  |> Enum.sum()
```

## Performance Tips

### DO

- Choose chunk size based on access patterns
- Enable caching for repeated reads
- Use parallel streaming for large operations
- Batch operations when possible
- Profile before optimizing
- Use appropriate compression for data type

### DON'T

- Make chunks too small (<100 KB) or too large (>100 MB)
- Read entire large arrays into memory
- Use high compression for real-time data
- Enable caching for write-heavy workloads
- Ignore memory constraints
- Optimize without measuring

## Troubleshooting

### Slow Reads

1. Check chunk size (aim for 1-10 MB)
2. Enable caching if reading repeatedly
3. Use parallel streaming
4. Profile I/O with `:fprof`
5. Consider storage backend latency

### High Memory Usage

1. Use streaming instead of loading full arrays
2. Reduce chunk size
3. Disable caching or reduce cache size
4. Process chunks individually
5. Force garbage collection between operations

### Slow Compression

1. Lower compression level
2. Switch to faster codec (LZ4)
3. Disable shuffle if not beneficial
4. Consider no compression for random data
5. Profile codec performance

## Benchmarking Guidelines

### Warm-up

Always warm up before benchmarking:

```elixir
# Warm-up iteration
your_operation()

# Now measure
{time_us, _result} = :timer.tc(fn ->
  your_operation()
end)
```

### Multiple Runs

Average over multiple runs:

```elixir
times = for _ <- 1..10 do
  {time, _} = :timer.tc(fn -> your_operation() end)
  time
end

avg_time = Enum.sum(times) / length(times)
```

### Realistic Data

Use realistic data patterns:

```elixir
# Good: Realistic scientific data
data = generate_normal_distribution(shape)

# Bad: All zeros
data = <<0::size(total_bytes)-unit(8)>>
```

## Further Reading

- [Zarr Specification](https://zarr-specs.readthedocs.io/)
- [Blosc Documentation](https://www.blosc.org/)
- [Elixir Performance](https://hexdocs.pm/elixir/performance.html)
- [ExZarr Examples](https://github.com/thanos/ExZarr/tree/main/examples)

## Contributing

Found a performance issue or have optimization suggestions? Please open an issue or pull request!
