# Run as: iex --dot-iex path/to/notebook.exs

# Title: Codecs and Pipelines: v2 Compressors vs v3 Codec Chains

Mix.install([
  {:ex_zarr, path: Path.join(__DIR__, "../..")},
  {:kino, "~> 0.13"}
])

# ── Introduction ──

# Compression is critical for Zarr arrays — it reduces storage costs, speeds up I/O, and enables working with larger datasets. Zarr v2 uses simple compressors. Zarr v3 introduces codec pipelines: composable, multi-stage transformations. This livebook explores both approaches, when to use each codec, and how to measure compression effectiveness.

# **What you'll learn:**

# * Zarr v2 compressor model (single-stage)
# * Zarr v3 codec pipelines (multi-stage)
# * Common codecs: gzip, zstd, zlib, blosc
# * Compression ratio vs speed trade-offs
# * Choosing codecs for different data types
# * Measuring compression effectiveness

# **Core principle:** Chunks compress independently. This enables parallel compression, but also means codecs can't exploit inter-chunk patterns.

# ── Setup ──

alias ExZarr.Array
alias ExZarr.Gallery.{Pack, SampleData, Metrics}

# ── Zarr v2: Simple Compressors ──

# In Zarr v2, each chunk goes through a single compressor:

# ```mermaid
# graph LR
#     A[Raw Chunk Data] --> B[Compressor<br/>e.g. zstd, gzip]
#     B --> C[Compressed Chunk]
#     C --> D[Storage]

#     style A fill:#e1f5ff
#     style B fill:#fff9c4
#     style C fill:#c8e6c9
#     style D fill:#f3e5f5
# ```

# **Simple and effective:** For most use cases, a single compressor is enough. v2 supports:

# * `gzip` - Widely compatible, moderate speed
# * `zlib` - Similar to gzip, slightly different format
# * `zstd` - Faster, better ratios, modern choice
# * `blosc` - Optimized for numerical data, multiple algorithms
# * `lz4` - Extremely fast, lower compression ratio

# ── Zarr v3: Codec Pipelines ──

# Zarr v3 allows chaining codecs into pipelines:

# ```mermaid
# graph LR
#     A[Raw Chunk Data] --> B[Codec 1<br/>Transpose]
#     B --> C[Codec 2<br/>ByteShuffle]
#     C --> D[Codec 3<br/>zstd]
#     D --> E[Compressed Chunk]
#     E --> F[Storage]

#     style A fill:#e1f5ff
#     style B fill:#fff4e1
#     style C fill:#ffe0b2
#     style D fill:#fff9c4
#     style E fill:#c8e6c9
#     style F fill:#f3e5f5
# ```

# **Why pipelines:** Some transformations improve compression without being compressors themselves. For example:

# * **Transpose:** Reorder dimensions to improve locality
# * **ByteShuffle:** Separate bytes by position, helping compressors
# * **Delta encoding:** Store differences instead of absolute values

# These are called "array-to-array" or "array-to-bytes" codecs, followed by a "bytes-to-bytes" compressor.

# ── Step 1: Create Arrays with Different Compressors (v2) ──

# Let's create the same logical array with different v2 compressors and compare.

compressors = [:zstd, :gzip, :zlib, :blosc]

arrays =
  Enum.map(compressors, fn comp ->
    {:ok, array} =
      Array.create(
        shape: {500, 500},
        chunks: {100, 100},
        dtype: :float32,
        compressor: comp,
        zarr_version: 2,
        storage: :memory
      )

    {comp, array}
  end)

IO.puts("Created #{length(arrays)} arrays with different compressors")
:ok

# **Same structure, different compression:** All arrays have identical shape and chunks, only the compressor differs.

# ── Step 2: Write Data and Measure Compression ──

# We'll write the same data to each array and measure compressed size.

# Generate test data: 500×500 matrix
data = SampleData.matrix(500, 500)
binary = Pack.pack(data, :float32)
uncompressed_size = byte_size(binary)

IO.puts("Uncompressed data size: #{div(uncompressed_size, 1024)} KB\n")

compression_results =
  Enum.map(arrays, fn {comp, array} ->
    # Write data
    {_result, write_time_us} =
      Metrics.time(fn ->
        Array.set_slice(array, binary, start: {0, 0}, stop: {500, 500})
      end)

    # Estimate compressed size (for memory storage, we'd need to save to disk)
    # For demonstration, we'll read it back and time it
    {_read_data, read_time_us} =
      Metrics.time(fn ->
        Array.get_slice(array, start: {0, 0}, stop: {500, 500})
      end)

    %{
      compressor: comp,
      write_time_us: write_time_us,
      read_time_us: read_time_us
    }
  end)

IO.puts("Compression performance:\n")

Enum.each(compression_results, fn result ->
  IO.puts("#{result.compressor}:")
  IO.puts("  Write: #{Metrics.human_us(result.write_time_us)}")
  IO.puts("  Read:  #{Metrics.human_us(result.read_time_us)}")
  IO.puts("")
end)

# **What we measured:**

# * **Write time:** Includes compression time
# * **Read time:** Includes decompression time

# **Expected patterns:**

# * `zstd`: Fast, good compression
# * `gzip/zlib`: Slower, decent compression
# * `blosc`: Very fast, excellent for numerical data
# * `lz4`: Fastest, lower compression ratio

# ── Step 3: Understanding Blosc ──

# Blosc is special: it's a meta-compressor that combines:

# * **Blocking:** Splits data into blocks for cache efficiency
# * **Shuffling:** Reorders bytes to improve compression
# * **Compression:** Uses an underlying codec (lz4, zstd, etc.)

# ```mermaid
# graph TD
#     A[Raw Data] --> B[Blosc Meta-Compressor]
#     B --> C[Split into Blocks]
#     C --> D[Byte Shuffle Each Block]
#     D --> E[Compress with LZ4/zstd]
#     E --> F[Compressed Blocks]

#     style A fill:#e1f5ff
#     style B fill:#f3e5f5
#     style F fill:#c8e6c9
# ```

# **Why Blosc works well:** Numerical arrays have structure (nearby values are similar). Shuffling bytes by position (all high bytes together, all low bytes together) creates long runs that compress better.

# ── Step 4: Zarr v3 Codec Pipelines ──

# Let's create a v3 array with an explicit codec pipeline. We'll use:

# 1. Transpose (if beneficial)
# 2. ByteShuffle
# 3. zstd compression

# For this example, we'll create a simple v3 array with zstd
# Full pipeline support depends on ExZarr codec implementation

{:ok, array_v3} =
  Array.create(
    shape: {500, 500},
    chunks: {100, 100},
    dtype: :float32,
    compressor: :zstd,
    zarr_version: 3,
    storage: :memory
  )

# Write the same data
Array.set_slice(array_v3, binary, start: {0, 0}, stop: {500, 500})

IO.puts("Created v3 array with codec pipeline")

# **v3 advantage:** Explicit codec specification in metadata makes the transformation pipeline transparent. You can see exactly what operations are applied.

# **Future extensibility:** v3's codec model allows custom codecs without format changes. Want a domain-specific transformation? Implement it as a codec and register it.

# ── Step 5: Comparing Compression Ratios ──

# Let's save arrays to disk and measure actual compressed sizes.

base_dir = Path.join(System.tmp_dir!(), "exzarr_codec_comparison")
File.rm_rf!(base_dir)
File.mkdir_p!(base_dir)

size_results =
  Enum.map(arrays, fn {comp, array} ->
    path = Path.join(base_dir, "array_#{comp}")
    File.mkdir_p!(path)
    Array.save(array, path: path)

    # Measure directory size (includes metadata + chunks)
    {size_output, 0} = System.cmd("du", ["-sk", path])
    size_kb = size_output |> String.trim() |> String.split("\t") |> hd() |> String.to_integer()

    %{compressor: comp, size_kb: size_kb}
  end)

IO.puts("Compressed sizes on disk:\n")

Enum.each(size_results, fn result ->
  ratio = Float.round(uncompressed_size / 1024 / result.size_kb, 2)
  IO.puts("#{result.compressor}: #{result.size_kb} KB (#{ratio}x compression)")
end)

# **Compression ratio:** Original size / compressed size. Higher is better (more compression).

# **Real-world ratios depend on:**

# * Data type (integers compress better than random floats)
# * Data patterns (repeated values, smooth gradients)
# * Chunk size (larger chunks can find more patterns)
# * Compressor settings (level, window size)

# ── Step 6: When to Use Each Codec ──

# ```mermaid
# graph TD
#     A[Choosing a Codec] --> B{Priority?}

#     B -->|Speed| C[lz4 or blosc:lz4]
#     B -->|Compression| D[zstd level 9+]
#     B -->|Compatibility| E[gzip]
#     B -->|Numerical Data| F[blosc:zstd]

#     style A fill:#e1f5ff
#     style C fill:#c8e6c9
#     style D fill:#fff9c4
#     style E fill:#f3e5f5
#     style F fill:#ffe0b2
# ```

# **Decision guide:**

# * **zstd (default):** Best general-purpose choice. Fast, good compression, widely supported.
# * **blosc:** Excellent for numerical arrays (satellite data, simulation results). Use with zstd or lz4 backend.
# * **gzip:** Maximum compatibility. Slower, but readable by any tool.
# * **zlib:** Similar to gzip, slight differences in format.
# * **lz4:** When speed is critical and compression ratio is secondary (e.g., temporary intermediate data).

# **For Zarr v3:** Start with zstd. Add byte shuffle if working with numerical data. Consider transpose for multidimensional arrays with non-uniform access patterns.

# ── Step 7: Codec Choice by Data Type ──

# Different data types benefit from different codecs:

# Integer data (highly compressible)
{:ok, int_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    compressor: :zstd,
    storage: :memory
  )

# Integer data with pattern: sequential IDs
int_data =
  for r <- 0..999, c <- 0..999 do
    r * 1000 + c
  end

int_binary = Pack.pack(int_data, :int32)
Array.set_slice(int_array, int_binary, start: {0, 0}, stop: {1000, 1000})

# Random floats (barely compressible)
{:ok, float_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    compressor: :zstd,
    storage: :memory
  )

float_data = SampleData.rand_floats(1_000_000, 12345)
float_binary = Pack.pack(float_data, :float64)
Array.set_slice(float_array, float_binary, start: {0, 0}, stop: {1000, 1000})

IO.puts("Created arrays with different data patterns")
IO.puts("Integer array: sequential pattern (highly compressible)")
IO.puts("Float array: pseudo-random (low compressibility)")

# **Compression by data type:**

# * **Integers with patterns:** 5-20x compression (counters, IDs, sparse data)
# * **Floats from simulations:** 2-5x compression (smooth fields, sensor data)
# * **Random data:** 1-1.5x compression (encrypted, already compressed, true random)
# * **Sparse arrays:** 100-1000x compression with appropriate fill values

# ── Step 8: Codec Pipeline Benefits (v3) ──

# Zarr v3 codec pipelines shine when you need multi-stage transformations:

# **Example pipeline for climate data:**

# 1. **Transpose:** Reorder dimensions to group similar values
# 2. **Delta encoding:** Store differences between adjacent values
# 3. **ByteShuffle:** Separate bytes by position
# 4. **zstd:** Final compression

# Each stage improves compression or processing efficiency.

# Conceptual example (actual pipeline depends on ExZarr codec support)
IO.puts("""
Example v3 codec pipeline for climate model output:

1. Transpose: (time, lat, lon) → (lat, lon, time)
   - Groups spatial neighbors for better compression

2. Delta encoding: Store temporal differences
   - Temperature changes slowly over time

3. ByteShuffle: Separate high/low bytes
   - Creates long runs of similar bytes

4. zstd: Final compression
   - Compresses the transformed data

Result: 10-30x compression for typical climate data
""")

# **When to use pipelines:**

# * Data has specific structure (spatial, temporal)
# * Multiple dimensions with different access patterns
# * Need to balance compression and decoding speed
# * Custom transformations for domain-specific data

# ── Step 9: Measuring Codec Overhead ──

# Compression isn't free. Let's measure the overhead.

# No compression
{:ok, uncompressed_array} =
  Array.create(
    shape: {500, 500},
    chunks: {100, 100},
    dtype: :float32,
    compressor: nil,
    storage: :memory
  )

# With compression
{:ok, compressed_array} =
  Array.create(
    shape: {500, 500},
    chunks: {100, 100},
    dtype: :float32,
    compressor: :zstd,
    storage: :memory
  )

test_data = SampleData.matrix(500, 500)
test_binary = Pack.pack(test_data, :float32)

# Time writes
{_, uncompressed_write_us} =
  Metrics.time(fn ->
    Array.set_slice(uncompressed_array, test_binary, start: {0, 0}, stop: {500, 500})
  end)

{_, compressed_write_us} =
  Metrics.time(fn ->
    Array.set_slice(compressed_array, test_binary, start: {0, 0}, stop: {500, 500})
  end)

# Time reads
{_, uncompressed_read_us} =
  Metrics.time(fn ->
    Array.get_slice(uncompressed_array, start: {0, 0}, stop: {500, 500})
  end)

{_, compressed_read_us} =
  Metrics.time(fn ->
    Array.get_slice(compressed_array, start: {0, 0}, stop: {500, 500})
  end)

IO.puts("Codec overhead comparison:\n")
IO.puts("Uncompressed:")
IO.puts("  Write: #{Metrics.human_us(uncompressed_write_us)}")
IO.puts("  Read:  #{Metrics.human_us(uncompressed_read_us)}")
IO.puts("\nCompressed (zstd):")
IO.puts("  Write: #{Metrics.human_us(compressed_write_us)}")
IO.puts("  Read:  #{Metrics.human_us(compressed_read_us)}")

# **Overhead insights:**

# * **Write time:** Compression adds CPU cost
# * **Read time:** Decompression adds CPU cost
# * **For remote storage:** Compression reduces transfer time, often making total time faster despite CPU overhead
# * **For local storage:** Compression reduces disk I/O, especially on slow drives

# **Rule of thumb:** If I/O time > CPU time, compression is almost always worth it.

# ── Why This Matters ──

# **Cost reduction:**
# Cloud storage costs $0.02-0.10 per GB/month. 10x compression saves 90% of storage costs.

# **Performance:**
# Transferring 1 GB at 100 MB/s takes 10 seconds. With 10x compression, it's 1 second. Compression trades cheap CPU cycles for expensive I/O bandwidth.

# **Accessibility:**
# Smaller datasets are easier to share, download, and distribute. Compressed arrays enable collaboration across labs, teams, and continents.

# **Use cases:**

# * **Scientific data:** Climate, astronomy, genomics datasets are huge. Compression makes them tractable.
# * **Machine learning:** Embedding matrices, training datasets, checkpoints benefit from compression.
# * **Finance:** Tick data compresses extremely well (repeated timestamps, small price changes).
# * **Crypto:** On-chain data has structure (sequential blocks, repeated addresses).

# ── Key Takeaways ──

# 1. **v2 uses simple compressors** — one-stage, easy to configure
# 2. **v3 uses codec pipelines** — multi-stage, composable, extensible
# 3. **zstd is the default** — fast, good compression, widely supported
# 4. **blosc excels for numerical data** — built-in shuffling improves compression
# 5. **Compression ratios depend on data** — structured data compresses better
# 6. **Codec overhead is usually worth it** — I/O savings outweigh CPU cost
# 7. **Choose based on priority** — speed (lz4), compression (zstd high level), compatibility (gzip)

# ── What's Next ──

# **Explore concurrency:**

# * `02_concurrency/02_01_parallel_reads.livemd` - Parallel chunk reads with task supervision
# * `02_concurrency/02_03_profiling_exzarr.livemd` - Understanding I/O vs decode vs compression costs

# **Apply to domains:**

# * `04_ai_genai/04_01_embeddings_in_zarr.livemd` - Storing embedding matrices with optimal compression
# * `05_finance/05_01_tick_data_cubes.livemd` - Compressing financial time series
# * `07_geospatial/07_02_cmip_climate_slices.livemd` - Climate data compression strategies
