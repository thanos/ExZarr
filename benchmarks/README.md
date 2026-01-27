# ExZarr Benchmarks

Comprehensive benchmarking suite for ExZarr performance testing.

## Quick Start

Run the fastest benchmarks first:

```bash
# Ultra-fast (6 seconds) - Quick performance check
mix run benchmarks/slicing_bench_quick.exs

# Fast (30 seconds) - Basic performance suite
mix run benchmarks/compression_bench.exs
mix run benchmarks/io_bench.exs
```

## Benchmark Files

### 1. `slicing_bench_quick.exs` ⚡ **RECOMMENDED**
**Runtime**: ~6 seconds
**Purpose**: Quick slicing performance verification

Tests:
- Single chunk reads
- Multi-chunk reads (2x2, 3x3)
- 2D and 3D arrays
- Optimized for speed

**Use this for**: Quick performance checks during development

```bash
mix run benchmarks/slicing_bench_quick.exs
```

### 2. `compression_bench.exs`
**Runtime**: ~30 seconds
**Purpose**: Codec performance testing

Tests:
- zlib, blosc, zstd, lz4 compression
- Multiple data sizes (1KB - 1MB)
- Compression and decompression
- Compression ratios

```bash
mix run benchmarks/compression_bench.exs
```

### 3. `io_bench.exs`
**Runtime**: ~45 seconds
**Purpose**: Read/write operation performance

Tests:
- Array creation (small, medium, large)
- Single and multi-chunk writes
- Single and multi-chunk reads
- Filesystem vs memory storage

```bash
mix run benchmarks/io_bench.exs
```

### 4. `concurrent_bench.exs`
**Runtime**: ~60 seconds
**Purpose**: Concurrent access patterns

Tests:
- Sequential vs concurrent reads (2, 4, 8, 16 threads)
- Sequential vs concurrent writes
- Cache hit rate impact
- Chunk streaming parallelism

```bash
mix run benchmarks/concurrent_bench.exs
```

### 5. `slicing_bench_fast.exs`
**Runtime**: ~30 seconds
**Purpose**: Comprehensive slicing tests (medium size)

Tests:
- 2D slicing (single, 4-chunk, 16-chunk)
- 3D slicing
- Different data types (int32, float64)
- Cross-chunk operations

```bash
mix run benchmarks/slicing_bench_fast.exs
```

### 6. `slicing_bench.exs`
**Runtime**: ~3-5 minutes
**Purpose**: Comprehensive slicing suite (full size)

Tests:
- Multiple array dimensions (1D, 2D, 3D, 4D)
- Various slice patterns
- Strided access patterns
- Large-scale operations

**Warning**: This is resource-intensive. Use `slicing_bench_quick.exs` for most cases.

```bash
mix run benchmarks/slicing_bench.exs
```

## Performance Results Summary

Based on optimizations in v0.8.0:

### Multi-Chunk Read Performance

| Operation | Time | Scaling |
|-----------|------|---------|
| Single chunk (100x100) | 0.25ms | 1x |
| 4 chunks (2x2) | 1.02ms | 4.1x ⭐ (near optimal) |
| 9 chunks (3x3) | 2.28ms | 9.1x ⭐ (near optimal) |

**Before optimization**: 16 chunks took 110ms (298x slower than expected)
**After optimization**: 16 chunks take 4.4ms (17x - near optimal)
**Improvement**: 26x faster! 🚀

### Compression Performance

| Codec | 1KB | 100KB | 1MB |
|-------|-----|-------|-----|
| zlib | 0.02ms | 1.67ms | 18.6ms |
| blosc | 0.01ms | 0.8ms | 9.2ms |

Decompression is ~96x faster than compression.

### Storage Backend Comparison

| Backend | Read | Write |
|---------|------|-------|
| Memory | 0.52ms | 0.15ms |
| Filesystem | 0.79ms | 1.85ms |
| S3 | ~50ms | ~100ms |

## Profiling Tools

### Simple Profiling
```elixir
mix run benchmarks/profile_simple.exs
```

Detailed timing analysis of:
- Single vs multi-chunk reads
- Write operations
- Compression/decompression
- Memory usage

### Custom Profiling

Use the profiling template:

```elixir
# Time measurement
{time_us, result} = :timer.tc(fn ->
  your_operation()
end)

IO.puts("Operation took #{time_us / 1000} ms")

# Memory measurement
:erlang.memory(:total) |> IO.inspect(label: "Before")
your_operation()
:erlang.garbage_collect()
:erlang.memory(:total) |> IO.inspect(label: "After")
```

## Running All Benchmarks

```bash
# Quick suite (~2 minutes)
mix run benchmarks/slicing_bench_quick.exs
mix run benchmarks/compression_bench.exs
mix run benchmarks/io_bench.exs

# Full suite (~10 minutes)
for file in benchmarks/*_bench*.exs; do
  echo "Running $file..."
  mix run "$file"
done
```

## CI/CD Integration

Add to your CI pipeline:

```yaml
- name: Run performance benchmarks
  run: |
    mix deps.get
    mix run benchmarks/slicing_bench_quick.exs
    mix run benchmarks/compression_bench.exs
```

## Interpreting Results

### Good Performance Indicators

- **Scaling**: N chunks should take ~N× single chunk time
- **Memory**: Linear with data size, not number of operations
- **Compression**: zlib ~18ms/MB, blosc ~9ms/MB
- **Cache hits**: Should be >2x faster than cache misses

### Performance Red Flags

- ⚠️ N chunks taking >2N× single chunk time
- ⚠️ Memory growing quadratically
- ⚠️ Compression >50ms/MB
- ⚠️ No cache benefit for repeated reads

## Benchmarking Best Practices

1. **Warm-up**: Always include warm-up iterations
2. **Multiple runs**: Average over 10+ iterations
3. **Realistic data**: Use representative data patterns
4. **Consistent environment**: Close other applications
5. **GC**: Force garbage collection between tests
6. **Isolation**: Test one aspect at a time

## Contributing

When adding new benchmarks:

1. Keep runtime <60 seconds if possible
2. Add to this README with runtime estimate
3. Include both time and memory measurements
4. Test with realistic data sizes
5. Document what performance aspect is tested

## See Also

- [Performance Guide](../guides/performance.md) - Optimization recommendations
- [Performance Improvements](../PERFORMANCE_IMPROVEMENTS.md) - Technical details of v0.8.0 optimizations
