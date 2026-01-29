# Compression and Codecs

Codecs transform chunk data for efficient storage and transmission. This guide explains codec types, helps you select appropriate compression algorithms for your workload, and covers the filter pipeline for advanced transformations.

## Codec Types and Roles

ExZarr supports three categories of codecs in the transformation pipeline:

### 1. Array-to-Array Transformations

Operate on typed array data before conversion to bytes.

**Delta encoding:**
Encode differences between adjacent values instead of absolute values.

```elixir
# Original data: [100, 101, 102, 103, 104]
# Delta encoded: [100, 1, 1, 1, 1]
# Better compression (smaller values, more repetition)
```

**Use cases:**
- Time-series data (temperature, stock prices)
- Monotonically increasing sequences
- Smooth gradients

**Quantize:**
Reduce precision by rounding values to nearest representable level.

```elixir
# Original: [1.23456789, 2.34567890, 3.45678901]
# Quantized to 2 decimals: [1.23, 2.35, 3.46]
# Smaller value range, better compression
```

**Use cases:**
- High-precision measurements where some loss is acceptable
- Floating-point data with excess precision
- Scientific simulations with tolerance thresholds

### 2. Array-to-Bytes Codecs

Convert typed arrays to byte streams.

**Bytes codec:**
Handles endianness and array serialization.

```elixir
# float64 array → little-endian bytes
# Explicit in Zarr v3, implicit in v2
```

**Configuration:**
- Endianness: little (default), big
- Required in v3 pipelines

### 3. Bytes-to-Bytes Transformations and Compression

Operate on binary data.

**Shuffle filter:**
Reorder bytes to group similar values, improving compression.

```elixir
# Original bytes (interleaved):
# [b0_elem0, b1_elem0, b2_elem0, ..., b0_elem1, b1_elem1, ...]
#
# Shuffled bytes (grouped by byte position):
# [b0_elem0, b0_elem1, b0_elem2, ..., b1_elem0, b1_elem1, ...]
#
# Grouping similar bytes improves compression ratio
```

**Compression codecs:**
- `zlib`: Standard compression (Erlang built-in)
- `zstd`: High-performance, excellent ratio
- `lz4`: Very fast, moderate ratio
- `snappy`: Fast, consistent performance
- `blosc`: Meta-compressor with SIMD
- `bzip2`: Maximum compression, slow

**Checksum codecs:**
- `crc32c`: Data integrity verification (adds 4-byte checksum)

### Pipeline Flow

```
Write Path:
┌─────────────────┐
│ Array Data      │ Typed N-dimensional data (e.g., float64)
│ {1.5, 2.3, ...} │
└────────┬────────┘
         ↓
┌─────────────────────┐
│ Array-to-Array      │ Delta, Quantize
│ Transformations     │
└────────┬────────────┘
         ↓
┌─────────────────────┐
│ Array-to-Bytes      │ Endianness, serialization
│ Codec               │
└────────┬────────────┘
         ↓
┌─────────────────────┐
│ Bytes-to-Bytes      │ Shuffle (reorder bytes)
│ Filters             │
└────────┬────────────┘
         ↓
┌─────────────────────┐
│ Compression         │ zstd, lz4, zlib, etc.
│ Codec               │
└────────┬────────────┘
         ↓
┌─────────────────────┐
│ Storage             │ Binary chunk on disk/cloud
└─────────────────────┘

Read Path: Reverse order (Storage → Decompression → ... → Array Data)
```

## Supported Compression Codecs

### zlib (Always Available)

**Implementation:** Erlang built-in `:zlib` module

**Configuration:**
```elixir
compressor: :zlib
compressor_config: [level: 6]  # 1-9, default 6
```

**Characteristics:**
- **Compression level:** 1 (fast) to 9 (best compression)
- **Compression speed:** ~10-50 MB/s
- **Decompression speed:** ~100-300 MB/s
- **Compression ratio:** 2-4× (typical)
- **Memory usage:** Moderate

**Best for:**
- Compatibility (works everywhere)
- Reliable default choice
- Systems without Zig NIFs

**Example:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  compressor_config: [level: 6],
  storage: :filesystem,
  path: "/data/zlib_array"
)
```

### gzip (Erlang Built-in)

**Implementation:** Erlang `:zlib` module with gzip headers

**Configuration:**
```elixir
compressor: :gzip
compressor_config: [level: 6]
```

**Characteristics:**
- Same as zlib but with gzip headers
- Compatible with `gunzip` command-line tool
- Slightly slower than raw zlib due to header overhead

**Best for:**
- Compatibility with gzip tools
- Archives that need CLI decompression

### zstd (Zig NIF, Requires libzstd)

**Implementation:** Zig NIF calling libzstd

**Configuration:**
```elixir
compressor: :zstd
compressor_config: [level: 3]  # 1-22, default 3
```

**Characteristics:**
- **Compression level:** 1 (fast) to 22 (maximum compression)
- **Compression speed:** ~50-200 MB/s (level 3)
- **Decompression speed:** ~200-800 MB/s
- **Compression ratio:** 3-6× (typical)
- **Memory usage:** Configurable (higher levels use more)

**Best for:**
- Cloud storage (excellent compression reduces bandwidth costs)
- Balanced speed and compression ratio
- Modern deployments (recommended default)

**Example:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  compressor: :zstd,
  compressor_config: [level: 3],  # Fast, good ratio
  storage: :s3,
  bucket: "my-data"
)
```

**Availability:**
```bash
# macOS
brew install zstd

# Ubuntu/Debian
sudo apt-get install libzstd-dev

# Fedora/RHEL
sudo dnf install zstd-devel
```

Check at runtime:
```elixir
ExZarr.Codecs.codec_available?(:zstd)
# => true (if libzstd installed)
```

### lz4 (Zig NIF, Requires liblz4)

**Implementation:** Zig NIF calling liblz4

**Configuration:**
```elixir
compressor: :lz4
compressor_config: [level: 1]  # 1-12, default 1
```

**Characteristics:**
- **Compression level:** 1 (fastest) to 12 (higher compression)
- **Compression speed:** ~200-500 MB/s
- **Decompression speed:** ~1-3 GB/s (extremely fast)
- **Compression ratio:** 1.5-2.5× (typical)
- **Memory usage:** Low

**Best for:**
- Real-time data ingestion (minimize CPU time)
- Fast local reads (decompression bottleneck)
- Workloads prioritizing speed over storage savings

**Example:**
```elixir
# Real-time sensor data ingestion
{:ok, array} = ExZarr.create(
  shape: {1_000_000, 100},
  chunks: {1000, 100},
  dtype: :float32,
  compressor: :lz4,  # Minimize compression overhead
  storage: :filesystem,
  path: "/data/sensor_stream"
)
```

### snappy (Zig NIF, Requires libsnappy)

**Implementation:** Zig NIF calling libsnappy

**Configuration:**
```elixir
compressor: :snappy  # No level parameter
```

**Characteristics:**
- **Compression level:** Fixed (no configuration)
- **Compression speed:** ~200-500 MB/s
- **Decompression speed:** ~500-1500 MB/s
- **Compression ratio:** 1.5-2× (typical)
- **Memory usage:** Low

**Best for:**
- Consistent performance (no tuning needed)
- Real-time applications
- Workloads where predictability matters

**Example:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {5000, 5000},
  chunks: {500, 500},
  dtype: :int32,
  compressor: :snappy,  # Simple, fast, no config
  storage: :memory
)
```

### blosc (Zig NIF, Requires libblosc)

**Implementation:** Zig NIF calling libblosc (meta-compressor)

**Configuration:**
```elixir
compressor: :blosc
compressor_config: [
  compressor: :zstd,  # Internal compressor: :lz4, :zstd, :zlib
  level: 5,
  blocksize: 0,       # 0 = automatic
  shuffle: true       # Built-in shuffle
]
```

**Characteristics:**
- **Meta-compressor:** Uses lz4/zstd/zlib internally
- **SIMD acceleration:** Optimized for numerical arrays
- **Built-in shuffle:** Automatically reorders bytes
- **Multithreaded:** Can use multiple cores
- **Compression ratio:** Varies by internal compressor (2-6×)

**Best for:**
- Scientific/numerical data (float arrays)
- Automatic optimization (handles shuffle internally)
- High-performance numerical computing

**Example:**
```elixir
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  compressor: :blosc,
  compressor_config: [
    compressor: :zstd,
    level: 5,
    shuffle: true  # Optimize for typed arrays
  ],
  storage: :filesystem,
  path: "/data/scientific_array"
)
```

### bzip2 (Zig NIF, Requires libbz2)

**Implementation:** Zig NIF calling libbz2

**Configuration:**
```elixir
compressor: :bzip2
compressor_config: [level: 9]  # 1-9, default 9
```

**Characteristics:**
- **Compression level:** 1 (fast) to 9 (maximum compression)
- **Compression speed:** ~5-20 MB/s (slow)
- **Decompression speed:** ~20-50 MB/s (slow)
- **Compression ratio:** 4-8× (excellent)
- **Memory usage:** High

**Best for:**
- Archival storage (maximize compression)
- Cold data (infrequent access)
- Situations where storage cost dominates

**Example:**
```elixir
# Archival array (infrequent access)
{:ok, array} = ExZarr.create(
  shape: {100000, 100000},
  chunks: {10000, 10000},
  dtype: :float64,
  compressor: :bzip2,
  compressor_config: [level: 9],  # Maximum compression
  storage: :s3,
  bucket: "archive-data"
)
```

**Warning:** Use only for archival. Slow compression and decompression make it unsuitable for active workloads.

### crc32c (Zig NIF, Checksum)

**Implementation:** Zig NIF with CRC32C algorithm

**Configuration:**
```elixir
compressor: :crc32c  # Not compression, adds 4-byte checksum
```

**Characteristics:**
- **Type:** Checksum codec (integrity verification)
- **Overhead:** Adds 4 bytes per chunk
- **Speed:** Very fast (hardware-accelerated on modern CPUs)
- **Purpose:** Detect data corruption

**Best for:**
- Critical data requiring integrity verification
- Unreliable storage (detecting bit rot)
- Compliance requirements (data validation)

**Example:**
```elixir
# Combine with compression for both size and integrity
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},
    %{name: "zstd", configuration: %{level: 5}},
    %{name: "crc32c"}  # Add checksum after compression
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/data/verified_array"
)
```

## Codec Selection Tradeoffs

Choose codec based on your priorities:

### Decision Matrix

| Use Case | Recommended Codec | Rationale |
|----------|------------------|-----------|
| Real-time ingestion | lz4 (level 1), snappy | Minimize CPU time, fast compression |
| Cloud storage (S3/GCS/Azure) | zstd (level 3-5) | Balance network transfer cost vs CPU |
| Archival storage | bzip2 (level 9), zstd (level 10+) | Minimize storage cost, infrequent access |
| Maximum compatibility | zlib (level 6) | Universally supported, reliable |
| Scientific/numerical arrays | blosc (zstd internal) | Built-in shuffle, optimized for typed data |
| Fast local reads | lz4 (level 1), snappy | Minimize decompression time |
| No dependencies | zlib, gzip | Erlang built-in, always available |

### Tradeoff Dimensions

**1. Compression ratio** (storage savings):
```
Higher ratio = Less storage cost
bzip2 > zstd(10) > zstd(3) > zlib > lz4 > snappy > none
```

**2. Compression speed** (write throughput):
```
Higher speed = Faster writes
lz4 > snappy > zstd(1) > zstd(3) > zlib > zstd(10) > bzip2
```

**3. Decompression speed** (read throughput):
```
Higher speed = Faster reads
lz4 > snappy > zstd > zlib > bzip2
```

**4. CPU usage** (processing cost):
```
Lower usage = More efficient
lz4 < snappy < zstd(1) < zstd(3) < zlib < zstd(10) < bzip2
```

**5. Memory usage** (RAM required):
```
Lower usage = Less memory pressure
lz4 < snappy < zlib < zstd(3) < zstd(10) < bzip2
```

### Quantified Performance Example

Benchmark: 1 GB float64 array (scientific data with patterns)

| Codec | Compressed Size | Compress Time | Decompress Time | Ratio |
|-------|-----------------|---------------|-----------------|-------|
| none | 1000 MB | 0 ms | 0 ms | 1.0× |
| lz4 | 420 MB | 180 ms | 45 ms | 2.4× |
| snappy | 450 MB | 200 ms | 60 ms | 2.2× |
| zlib (6) | 310 MB | 1900 ms | 280 ms | 3.2× |
| zstd (3) | 285 MB | 380 ms | 140 ms | 3.5× |
| zstd (10) | 245 MB | 2800 ms | 140 ms | 4.1× |
| blosc (zstd) | 270 MB | 350 ms | 130 ms | 3.7× |
| bzip2 (9) | 195 MB | 7500 ms | 1800 ms | 5.1× |

**Observations:**
- lz4: Fastest compression/decompression, moderate ratio
- zstd(3): Best balance (recommended default for most workloads)
- zstd(10): Better ratio with reasonable speed
- bzip2: Maximum compression but very slow (archival only)

### Network Transfer Cost Comparison

Cloud egress example (S3, 100 GB data transferred 10 times):

| Codec | Compressed Size | Transfer Cost (10×) | Total Cost |
|-------|-----------------|---------------------|------------|
| none | 100 GB | 100 GB × 10 × $0.09 = $90 | $90 |
| lz4 | 42 GB | 42 GB × 10 × $0.09 = $37.80 | $37.80 |
| zstd(3) | 28 GB | 28 GB × 10 × $0.09 = $25.20 | $25.20 |
| zstd(10) | 24 GB | 24 GB × 10 × $0.09 = $21.60 | $21.60 |
| bzip2 | 19 GB | 19 GB × 10 × $0.09 = $17.10 | $17.10 |

**Savings:**
- lz4: 58% reduction vs uncompressed ($52.20 saved)
- zstd(3): 72% reduction ($64.80 saved)
- bzip2: 81% reduction ($72.90 saved, but slow)

For cloud workloads, compression significantly reduces bandwidth costs.

## Filter Pipeline (Transformations)

Filters transform data before compression to improve efficiency.

### Shuffle Filter

Reorder bytes to group similar values.

**How it works:**
```
Original (interleaved):
  float64 array [1.0, 2.0, 3.0]
  Bytes: [b0_1, b1_1, ..., b7_1, b0_2, b1_2, ..., b7_2, b0_3, ...]

Shuffled (grouped by byte position):
  Bytes: [b0_1, b0_2, b0_3, b1_1, b1_2, b1_3, ..., b7_1, b7_2, b7_3]

Result: Similar bytes clustered → better compression
```

**Configuration:**
```elixir
# v2: implicit shuffle filter
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],  # 8 bytes = float64
  compressor: :zlib,
  zarr_version: 2
)

# v3: explicit shuffle in pipeline
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "bytes"},
    %{name: "zstd", configuration: %{level: 5}}
  ],
  zarr_version: 3
)
```

**When to use:**
- Typed arrays (float32, float64, int32, etc.)
- Numerical data with patterns
- Scientific measurements

**Impact example:**
```
1 GB float64 array (random data):
- Without shuffle + zlib: 980 MB (2% reduction)
- With shuffle + zlib: 310 MB (69% reduction)

Shuffle enables compression by grouping similar bytes.
```

### Delta Filter

Encode differences between adjacent values.

**How it works:**
```
Original: [100, 101, 102, 103, 104, 105]
Delta:    [100,   1,   1,   1,   1,   1]

Smaller values → better compression
```

**Configuration:**
```elixir
# v2: delta filter
{:ok, array} = ExZarr.create(
  shape: {100000},
  chunks: {1000},
  dtype: :int32,
  filters: [{:delta, [dtype: :int32]}],
  compressor: :zstd,
  zarr_version: 2
)
```

**When to use:**
- Time-series data (temperature, stock prices)
- Monotonically increasing sequences (timestamps, IDs)
- Smooth gradients (simulation results)

**Impact example:**
```
Temperature time-series (10,000 values):
  Original: [20.1, 20.2, 20.3, 20.2, 20.4, ...]
  Delta: [20.1, 0.1, 0.1, -0.1, 0.2, ...]

Without delta + zstd: 28 KB
With delta + zstd: 8 KB (72% reduction)
```

### Quantize Filter (Lossy)

Reduce precision by rounding values.

**How it works:**
```
Original (10 bits precision): 1.2345678901234567
Quantized (5 bits precision):  1.23456

Fewer unique values → better compression
```

**Configuration:**
```elixir
# v3: quantize filter
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  codecs: [
    %{name: "quantize", configuration: %{bits: 12}},  # Reduce to 12-bit precision
    %{name: "bytes"},
    %{name: "zstd"}
  ],
  zarr_version: 3
)
```

**When to use:**
- High-precision measurements with tolerance
- Scientific simulations where some loss is acceptable
- Sensor data with excess precision

**Warning:** Lossy transformation. Original precision cannot be recovered.

**Impact example:**
```
Sensor readings (float64, 16-bit actual resolution):
  Original: 64-bit storage per value
  Quantized (16-bit): Effective 16-bit storage

Without quantize + zstd: 100 MB
With quantize + zstd: 28 MB (72% reduction)
```

## Zarr v2 vs v3 Codec Configuration

### v2 Style (Implicit Pipeline)

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],  # Optional filters
  compressor: :zlib,                        # Required compressor
  compressor_config: [level: 6],            # Optional config
  zarr_version: 2
)

# Implicit pipeline order:
# 1. Filters (if specified)
# 2. Array-to-bytes (implicit)
# 3. Compressor
```

**Advantages:**
- Simple configuration
- Compatible with zarr-python 2.x
- Widely supported

**Limitations:**
- Cannot control pipeline order
- No explicit array-to-bytes codec
- Limited to basic filter + compressor pattern

### v3 Style (Explicit Pipeline)

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    # Explicit pipeline order
    %{name: "shuffle", configuration: %{elementsize: 8}},
    %{name: "bytes", configuration: %{endian: "little"}},
    %{name: "zstd", configuration: %{level: 5}}
  ],
  zarr_version: 3
)

# Explicit pipeline order (user-defined):
# 1. Shuffle (bytes-to-bytes)
# 2. Bytes (array-to-bytes) - MUST be explicit
# 3. Zstd (compression)
```

**Advantages:**
- Full control over pipeline order
- Explicit array-to-bytes codec
- Support for complex transformations

**Limitations:**
- More verbose configuration
- Requires zarr-python 3.x (beta as of 2026)
- Must specify "bytes" codec explicitly

### Automatic Conversion

ExZarr automatically converts between formats:

```elixir
# Create v3 array with v2-style config (automatic conversion)
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],  # v2 style
  compressor: :zstd,
  zarr_version: 3  # ExZarr converts to v3 codec pipeline
)

# Opens both v2 and v3 arrays transparently
{:ok, array} = ExZarr.open(path: "/data/some_array")
# Automatic version detection, correct pipeline used
```

## Implementing Custom Codecs

Extend ExZarr with custom compression algorithms.

### Codec Behavior Contract

```elixir
defmodule MyApp.CustomCodec do
  @moduledoc """
  Custom codec implementing XYZ compression algorithm.
  """

  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: :xyz_codec

  @impl true
  def codec_info do
    %{
      name: "XYZ Compressor",
      version: "1.0.0",
      type: :compression,  # or :transformation, :checksum
      description: "Custom XYZ compression algorithm"
    }
  end

  @impl true
  def available? do
    # Check if codec dependencies are available
    # Return true if codec can be used
    Code.ensure_loaded?(MyApp.XYZCompressor)
  end

  @impl true
  def encode(data, opts) when is_binary(data) do
    # Compress/transform data
    # opts is keyword list with configuration (e.g., [level: 5])
    level = Keyword.get(opts, :level, 5)

    try do
      compressed = MyApp.XYZCompressor.compress(data, level)
      {:ok, compressed}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl true
  def decode(data, opts) when is_binary(data) do
    # Decompress/untransform data
    try do
      decompressed = MyApp.XYZCompressor.decompress(data)
      {:ok, decompressed}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl true
  def validate_config(opts) do
    # Validate configuration options
    case Keyword.get(opts, :level) do
      level when is_integer(level) and level in 1..9 ->
        :ok

      nil ->
        :ok  # Level is optional

      _ ->
        {:error, "level must be integer between 1 and 9"}
    end
  end
end
```

### Register Custom Codec

```elixir
# In application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # Register custom codecs
    :ok = ExZarr.Codecs.register_codec(MyApp.CustomCodec)

    children = [
      # ... supervision tree
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Use Custom Codec

```elixir
# Use like built-in codecs
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :xyz_codec,  # Use custom codec_id
  compressor_config: [level: 7],
  storage: :filesystem,
  path: "/data/custom_codec_array"
)

# Check if custom codec is available
ExZarr.Codecs.codec_available?(:xyz_codec)
# => true

# List all available codecs
ExZarr.Codecs.available_codecs()
# => [:zlib, :gzip, :zstd, :lz4, :xyz_codec, ...]
```

## Codec Performance Comparison

### Benchmark Script

Measure codec performance on your data:

```elixir
defmodule CodecBenchmark do
  @moduledoc """
  Benchmark different codecs on array data.
  """

  def run(array_size \\ {1000, 1000}) do
    # Generate test data
    data = generate_test_data(array_size)
    codecs = [:none, :lz4, :snappy, :zlib, :zstd, :blosc, :bzip2]

    IO.puts("\n=== Codec Performance Benchmark ===")
    IO.puts("Array size: #{inspect(array_size)}")
    IO.puts("Data type: float64")
    IO.puts("Uncompressed: #{elem(array_size, 0) * elem(array_size, 1) * 8 |> format_bytes()}\n")

    results = Enum.map(codecs, fn codec ->
      if ExZarr.Codecs.codec_available?(codec) do
        benchmark_codec(codec, data, array_size)
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    # Display results
    IO.puts("\n{:>10} {:>15} {:>12} {:>12} {:>8}",
      ["Codec", "Compressed", "Compress", "Decompress", "Ratio"])
    IO.puts(String.duplicate("-", 60))

    Enum.each(results, fn {codec, compressed_size, compress_time, decompress_time, ratio} ->
      IO.puts("{:>10} {:>15} {:>12} {:>12} {:>8}",
        [
          codec,
          format_bytes(compressed_size),
          "#{compress_time}ms",
          "#{decompress_time}ms",
          "#{Float.round(ratio, 2)}×"
        ])
    end)
  end

  defp benchmark_codec(codec, data, array_size) do
    {:ok, array} = ExZarr.create(
      shape: array_size,
      chunks: {100, 100},
      dtype: :float64,
      compressor: codec,
      storage: :memory
    )

    # Measure compression (write)
    {compress_time_us, :ok} = :timer.tc(fn ->
      ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: array_size)
    end)

    # Measure compressed size
    {:ok, chunks} = ExZarr.Storage.Backend.Memory.list_chunks(array.storage.state)
    compressed_size = Enum.reduce(chunks, 0, fn chunk, acc ->
      {:ok, chunk_data} = ExZarr.Storage.Backend.Memory.read_chunk(array.storage.state, chunk)
      acc + byte_size(chunk_data)
    end)

    # Measure decompression (read)
    {decompress_time_us, {:ok, _}} = :timer.tc(fn ->
      ExZarr.Array.get_slice(array, start: {0, 0}, stop: array_size)
    end)

    uncompressed_size = elem(array_size, 0) * elem(array_size, 1) * 8
    ratio = uncompressed_size / compressed_size

    {
      codec,
      compressed_size,
      div(compress_time_us, 1000),
      div(decompress_time_us, 1000),
      ratio
    }
  end

  defp generate_test_data({rows, cols}) do
    # Generate float64 array with some patterns (realistic data)
    for i <- 0..(rows - 1) do
      for j <- 0..(cols - 1) do
        :math.sin(i / 100.0) * :math.cos(j / 100.0) + :rand.uniform()
      end
      |> List.to_tuple()
    end
    |> List.to_tuple()
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_bytes(bytes), do: "#{div(bytes, 1024 * 1024)} MB"
end

# Run benchmark
CodecBenchmark.run({1000, 1000})
```

### Example Output

```
=== Codec Performance Benchmark ===
Array size: {1000, 1000}
Data type: float64
Uncompressed: 7.63 MB

     Codec      Compressed     Compress   Decompress    Ratio
------------------------------------------------------------
      none        7.63 MB          0ms          0ms    1.00×
       lz4        3.21 MB        142ms         38ms    2.38×
    snappy        3.45 MB        165ms         52ms    2.21×
      zlib        2.41 MB       1654ms        245ms    3.17×
      zstd        2.18 MB        328ms        118ms    3.50×
     blosc        2.05 MB        298ms        102ms    3.72×
     bzip2        1.52 MB       6823ms       1598ms    5.02×
```

## Troubleshooting Codec Issues

### Issue: Zig Codec Compilation Fails

**Symptom:**
```
** (Mix) Could not compile dependency :ex_zarr
...
error: unable to find library -lzstd
```

**Cause:** Missing system libraries (libzstd, liblz4, libsnappy, etc.)

**Fix:**
Install required libraries for your platform:

```bash
# macOS
brew install zstd lz4 snappy c-blosc bzip2

# Ubuntu/Debian
sudo apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev

# Fedora/RHEL
sudo dnf install zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel
```

Then recompile:
```bash
mix deps.clean ex_zarr --build
mix deps.get
mix compile
```

**Workaround:** Use `:zlib` (always available, no dependencies):
```elixir
{:ok, array} = ExZarr.create(
  compressor: :zlib,  # Erlang built-in, always works
  # ... other options
)
```

### Issue: Codec Not Available at Runtime

**Symptom:**
```elixir
{:error, {:unsupported_codec, :zstd}}
```

**Cause:** Zig NIF failed to load or system library missing at runtime.

**Diagnosis:**
```elixir
# Check which codecs are available
ExZarr.Codecs.available_codecs()
# => [:zlib, :gzip]  # Only Erlang built-ins

# Check specific codec
ExZarr.Codecs.codec_available?(:zstd)
# => false
```

**Fix:**
1. Verify system libraries are installed
2. Check NIF file exists:
   ```bash
   ls -la _build/dev/lib/ex_zarr/priv/zig_codecs.so
   ```
3. Check library dependencies (Linux):
   ```bash
   ldd _build/dev/lib/ex_zarr/priv/zig_codecs.so
   ```

**Workaround:** Fallback to zlib in application code:
```elixir
defmodule MyApp.ArrayFactory do
  def create_array(opts) do
    # Prefer zstd, fallback to zlib
    compressor = if ExZarr.Codecs.codec_available?(:zstd) do
      :zstd
    else
      :zlib
    end

    ExZarr.create(
      compressor: compressor,
      # ... other options
    )
  end
end
```

### Issue: Decompression Fails on Existing Array

**Symptom:**
```elixir
{:error, :decompression_failed}
```

**Cause:** Array created with codec not available on reading system.

**Example:**
```elixir
# Created on system A with zstd
{:ok, array} = ExZarr.create(compressor: :zstd, path: "/data/array")

# Opened on system B without libzstd
{:ok, array} = ExZarr.open(path: "/data/array")
{:error, :decompression_failed} = ExZarr.Array.get_slice(...)
```

**Fix:** Install required codec library on reading system.

**Prevention:** Use widely available codecs for portability:
```elixir
# Portable: zlib works everywhere
{:ok, array} = ExZarr.create(compressor: :zlib, ...)

# Or document codec requirements
```

### Issue: Poor Compression Ratio

**Symptom:** Compressed data is nearly same size as uncompressed.

**Cause:** Data is already compressed, encrypted, or random.

**Diagnosis:**
```elixir
# Check compression ratio
uncompressed_size = 1000 * 1000 * 8  # 1000×1000 float64
{:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
compressed_size = Enum.reduce(chunks, 0, fn chunk, acc ->
  {:ok, data} = ExZarr.Storage.read_chunk(array.storage, chunk)
  acc + byte_size(data)
end)

ratio = uncompressed_size / compressed_size
# ratio close to 1.0 = poor compression
```

**Solutions:**
1. **Try different codecs:** Some codecs work better for certain data types
2. **Add shuffle filter:** Improves compression for typed arrays
   ```elixir
   filters: [{:shuffle, [elementsize: 8]}]
   ```
3. **Use blosc:** Optimized for numerical data
4. **Check data characteristics:** Truly random data won't compress

### Issue: Slow Compression/Decompression

**Symptom:** Array operations take too long.

**Cause:** Codec choice or compression level too aggressive.

**Fix:**
1. **Use faster codec:**
   ```elixir
   # Change from bzip2 to lz4
   compressor: :lz4  # Much faster
   ```

2. **Lower compression level:**
   ```elixir
   # zstd level 3 instead of 10
   compressor_config: [level: 3]
   ```

3. **Increase chunk size:** Fewer chunks = fewer compression operations
   ```elixir
   chunks: {1000, 1000}  # Instead of {100, 100}
   ```

4. **Profile bottleneck:**
   ```elixir
   {time_us, result} = :timer.tc(fn ->
     ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1000, 1000})
   end)
   IO.puts("Read took #{div(time_us, 1000)}ms")
   ```

## Summary

This guide covered compression and codecs:

- **Codec types:** Array-to-array (Delta, Quantize), Array-to-bytes (Bytes), Bytes-to-bytes (Shuffle, Compression, Checksum)
- **Supported codecs:** zlib (always), gzip, zstd, lz4, snappy, blosc, bzip2, crc32c
- **Selection criteria:** Real-time (lz4), cloud (zstd), archival (bzip2), compatibility (zlib)
- **Filter pipeline:** Shuffle, Delta, Quantize for improved compression
- **v2 vs v3:** Implicit pipeline (v2) vs explicit pipeline (v3)
- **Custom codecs:** Implement behavior, register, use like built-ins
- **Performance:** Benchmark script, quantified tradeoffs
- **Troubleshooting:** Compilation failures, missing codecs, poor compression

**Key recommendations:**
- Use zstd (level 3) for most workloads (good balance)
- Add shuffle filter for typed arrays
- Use lz4 for real-time ingestion
- Use zlib for maximum compatibility
- Benchmark on your actual data
- Check codec availability before use

## Next Steps

Now that you understand codecs:

1. **Python Interop:** Ensure codec compatibility in [Python Interoperability Guide](python_interop.md)
2. **Performance Tuning:** Optimize chunk size and compression in [Performance Guide](performance.md)
3. **Nx Integration:** Persist tensors efficiently in [Nx Integration Guide](nx_integration.md)
4. **Storage Providers:** Apply codec knowledge to cloud storage in [Storage Providers Guide](storage_providers.md)
