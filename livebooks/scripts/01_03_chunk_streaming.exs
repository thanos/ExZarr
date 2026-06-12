# Run as: iex --dot-iex path/to/notebook.exs

# Title: Chunk Streaming: Sequential vs Parallel

Mix.install([
  {:ex_zarr, path: Path.join(__DIR__, "../..")},
  {:kino, "~> 0.13"}
])

# ── Introduction ──

# Chunk streaming is how you process large Zarr arrays without loading everything into memory. This livebook explores the differences between sequential and parallel chunk streaming, when to use each, and how to tune concurrency for optimal performance.

# **What you'll learn:**

# * Sequential chunk streaming for ordered processing
# * Parallel chunk streaming for maximum throughput
# * Bounded concurrency to avoid overwhelming the system
# * Progress tracking for long-running operations
# * When each approach makes sense

# **Core principle:** Chunks are independent. This independence enables parallel I/O, the key to Zarr's performance on large datasets and remote storage.

# ── Setup ──

alias ExZarr.Array
alias ExZarr.Gallery.{Pack, SampleData, Metrics}

# ── Sequential vs Parallel Streaming ──

# ```mermaid
# graph TD
#     A[Array with 100 chunks] --> B[Sequential Streaming]
#     A --> C[Parallel Streaming]

#     B --> D["Read chunk 0<br/>Process<br/>Read chunk 1<br/>Process<br/>..."]
#     C --> E["Read chunks 0-3<br/>Process all<br/>Read chunks 4-7<br/>Process all<br/>..."]

#     style A fill:#e1f5ff
#     style B fill:#fff9c4
#     style C fill:#c8e6c9
# ```

# **Sequential:** One chunk at a time. Simple, predictable, preserves order.

# **Parallel:** Multiple chunks concurrently. Faster, especially for remote storage, but results arrive out of order unless you buffer.

# ── Step 1: Create a Test Array ──

# We'll create a 1000×1000 array with 100×100 chunks, giving us 100 chunks total. We'll write data to make chunk reads realistic.

{:ok, array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    compressor: :zstd,
    storage: :memory
  )

# Write data across all chunks
IO.puts("Writing data to array...")

data = SampleData.matrix(1000, 1000)
binary = Pack.pack(data, :int32)

Array.set_slice(array, binary, start: {0, 0}, stop: {1000, 1000})

IO.puts("Array ready: #{inspect(array.shape)} with #{inspect(array.chunks)} chunks")
:ok

# **Why write all chunks:** To simulate realistic access patterns. Empty chunks are skipped by ExZarr, so we need actual data to see streaming behavior.

# ── Step 2: Sequential Streaming Basics ──

# Sequential streaming processes chunks in grid order: (0,0), (0,1), ..., (0,9), (1,0), ...

IO.puts("Sequential streaming first 10 chunks:\n")

{chunks_info, elapsed_us} =
  Metrics.time(fn ->
    Array.chunk_stream(array)
    |> Stream.take(10)
    |> Enum.map(fn {chunk_index, chunk_binary} ->
      %{
        index: chunk_index,
        size_bytes: byte_size(chunk_binary),
        element_count: div(byte_size(chunk_binary), 4)
      }
    end)
  end)

Enum.each(chunks_info, fn info ->
  IO.puts("Chunk #{inspect(info.index)}: #{info.element_count} elements, #{info.size_bytes} bytes")
end)

IO.puts("\nElapsed: #{Metrics.human_us(elapsed_us)}")

# **What happened:**

# * `Array.chunk_stream/1` returns a lazy stream
# * Each item is `{chunk_index, chunk_binary}`
# * Binary is decompressed and ready to process
# * Order is guaranteed: chunks arrive in grid order

# ── Step 3: Processing Chunks Sequentially ──

# Let's simulate processing by computing a simple statistic (sum) for each chunk.

IO.puts("Computing sum for each chunk (sequential):\n")

{chunk_sums, elapsed_us} =
  Metrics.time(fn ->
    Array.chunk_stream(array)
    |> Stream.take(5)
    |> Enum.map(fn {chunk_index, chunk_binary} ->
      values = Pack.unpack(chunk_binary, :int32)
      chunk_sum = Enum.sum(values)
      {chunk_index, chunk_sum}
    end)
  end)

Enum.each(chunk_sums, fn {index, sum} ->
  IO.puts("Chunk #{inspect(index)}: sum = #{sum}")
end)

IO.puts("\nElapsed: #{Metrics.human_us(elapsed_us)}")

# **Sequential use cases:**

# * Order matters (time series data)
# * Processing depends on previous chunks
# * Low memory systems where parallel I/O isn't needed
# * Simple debugging and logging

# ── Step 4: Parallel Streaming Basics ──

# Parallel streaming reads multiple chunks concurrently. Specify `parallel: N` to read up to N chunks at once.

IO.puts("Parallel streaming (4 concurrent chunks):\n")

{chunks_info, elapsed_us} =
  Metrics.time(fn ->
    Array.chunk_stream(array, parallel: 4, ordered: false)
    |> Stream.take(10)
    |> Enum.map(fn {chunk_index, chunk_binary} ->
      %{
        index: chunk_index,
        size_bytes: byte_size(chunk_binary)
      }
    end)
  end)

Enum.each(chunks_info, fn info ->
  IO.puts("Chunk #{inspect(info.index)}: #{info.size_bytes} bytes")
end)

IO.puts("\nElapsed: #{Metrics.human_us(elapsed_us)}")

# **Key difference:** With `ordered: false`, chunks arrive as soon as they're ready, not in grid order. This maximizes throughput but breaks sequential guarantees.

# **Parallel use cases:**

# * Remote storage (S3, GCS) where network latency dominates
# * Large arrays where processing time < I/O time
# * Stateless processing (each chunk is independent)
# * Fast local SSDs with high IOPS

# ── Step 5: Ordered Parallel Streaming ──

# If you need parallelism but also want results in order, use `ordered: true`. ExZarr buffers chunks internally to maintain order.

IO.puts("Parallel streaming with ordering (4 concurrent chunks):\n")

{chunks_info, elapsed_us} =
  Metrics.time(fn ->
    Array.chunk_stream(array, parallel: 4, ordered: true)
    |> Stream.take(10)
    |> Enum.map(fn {chunk_index, _chunk_binary} ->
      chunk_index
    end)
  end)

IO.puts("Chunk order: #{inspect(chunks_info)}")
IO.puts("Elapsed: #{Metrics.human_us(elapsed_us)}")

# **Trade-off:** Ordered parallel is faster than sequential (due to concurrent I/O) but slower than unordered parallel (due to buffering overhead).

# ```mermaid
# graph LR
#     A[Sequential] -->|Slowest| B[Ordered Parallel]
#     B -->|Medium| C[Unordered Parallel]
#     C -->|Fastest| D[Maximum Throughput]

#     style A fill:#ffebee
#     style B fill:#fff9c4
#     style C fill:#c8e6c9
#     style D fill:#e1f5ff
# ```

# ── Step 6: Bounded Concurrency ──

# Unbounded parallelism can overwhelm memory or network connections. Use `parallel: N` to limit concurrent chunk reads.

concurrency_levels = [1, 2, 4, 8]

IO.puts("Comparing concurrency levels (processing 50 chunks):\n")

results =
  Enum.map(concurrency_levels, fn n ->
    {_chunks, elapsed_us} =
      Metrics.time(fn ->
        Array.chunk_stream(array, parallel: n, ordered: false)
        |> Stream.take(50)
        |> Enum.map(fn {_index, binary} -> byte_size(binary) end)
      end)

    %{concurrency: n, elapsed_us: elapsed_us}
  end)

Enum.each(results, fn r ->
  IO.puts("Concurrency #{r.concurrency}: #{Metrics.human_us(r.elapsed_us)}")
end)

# **Expected pattern:**

# * Concurrency 1 (sequential): Slowest
# * Concurrency 2-4: Significant speedup
# * Concurrency 8+: Diminishing returns (especially on memory storage)

# **For remote storage:** Higher concurrency helps more, often scaling up to 16-32 concurrent chunks.

# ── Step 7: Progress Tracking ──

# For long-running operations, track progress with a callback.

IO.puts("Streaming all chunks with progress tracking:\n")

progress_fn = fn done, total ->
  if rem(done, 10) == 0 or done == total do
    percent = Float.round(done / total * 100, 1)
    IO.puts("Progress: #{done}/#{total} chunks (#{percent}%)")
  end
end

{count, elapsed_us} =
  Metrics.time(fn ->
    Array.chunk_stream(array, parallel: 4, progress_callback: progress_fn)
    |> Enum.count()
  end)

IO.puts("\nProcessed #{count} chunks in #{Metrics.human_us(elapsed_us)}")

# **Use progress tracking when:**

# * Processing takes more than a few seconds
# * You need to monitor long-running jobs
# * Building interactive tools or UIs

# ── Step 8: Chunk Streaming with Filtering ──

# Often you don't need all chunks. Filter the stream to process only relevant chunks.

IO.puts("Processing only chunks in first two rows (chunks 0-19):\n")

{filtered_count, elapsed_us} =
  Metrics.time(fn ->
    Array.chunk_stream(array, parallel: 4)
    |> Stream.filter(fn {{row, _col}, _binary} -> row < 2 end)
    |> Enum.count()
  end)

IO.puts("Filtered to #{filtered_count} chunks")
IO.puts("Elapsed: #{Metrics.human_us(elapsed_us)}")

# **Important:** Filtering happens after reading. ExZarr still reads all chunks from storage, then you filter in memory. For selective reads, use slicing instead of streaming.

# **When to filter streams:**

# * Metadata-based filtering (chunk index patterns)
# * Post-read validation or quality checks
# * Debugging specific chunk ranges

# ── Step 9: Memory Considerations ──

# Each chunk in the stream is held in memory until processed. With parallel streaming, you can have N chunks in memory simultaneously.

# Estimate memory usage
chunk_size = 100 * 100 * 4  # 100×100 elements × 4 bytes per int32
parallel_level = 4
estimated_memory = chunk_size * parallel_level

IO.puts("Memory estimate for parallel=#{parallel_level}:")
IO.puts("  Chunk size: #{div(chunk_size, 1024)} KB")
IO.puts("  Max concurrent: #{parallel_level} chunks")
IO.puts("  Peak memory: ~#{div(estimated_memory, 1024)} KB")

# **For large chunks:** Reduce parallelism to avoid memory pressure. A 1000×1000 chunk at float64 is 8 MB. With parallel=16, that's 128 MB in flight.

# **Rule of thumb:** Keep total in-flight memory under 10% of available RAM.

# ── Visualizing Parallel Chunk Access ──

# ```mermaid
# graph TD
#     A[Chunk Stream] --> B[Worker Pool]
#     B --> C[Worker 1<br/>Reading chunk 0]
#     B --> D[Worker 2<br/>Reading chunk 1]
#     B --> E[Worker 3<br/>Reading chunk 2]
#     B --> F[Worker 4<br/>Reading chunk 3]

#     C --> G[Process & Yield]
#     D --> G
#     E --> G
#     F --> G

#     G --> H[Next 4 chunks...]

#     style A fill:#e1f5ff
#     style B fill:#f3e5f5
#     style C fill:#c8e6c9
#     style D fill:#c8e6c9
#     style E fill:#c8e6c9
#     style F fill:#c8e6c9
# ```

# Workers read chunks concurrently. As each chunk is processed, the next chunk starts loading. This pipeline keeps I/O and processing overlapped.

# ── Why This Matters ──

# **Scalability:**
# Chunk streaming enables processing arrays larger than memory. Load, process, discard. Repeat for millions of chunks.

# **Performance:**
# Parallel I/O is critical for remote storage. S3 or GCS can serve hundreds of chunks per second if you request them in parallel.

# **BEAM advantage:**
# Elixir's lightweight processes make parallel chunk streaming natural. Each chunk can be processed in its own process without heavyweight threading.

# **Real-world applicability:**

# * **Climate data:** Process 10TB datasets chunk-by-chunk
# * **ML training:** Stream batches from Zarr without loading full dataset
# * **Finance:** Scan tick data across thousands of chunks
# * **Genomics:** Process microscopy images tile-by-tile

# ── Key Takeaways ──

# 1. **Sequential streaming** preserves order, simple, good for dependent processing
# 2. **Parallel streaming** maximizes throughput, critical for remote storage
# 3. **Bounded concurrency** prevents memory/network overload
# 4. **Ordered parallel** balances speed and order guarantees
# 5. **Progress tracking** monitors long-running operations
# 6. **Memory scales with parallelism** — each concurrent chunk occupies RAM
# 7. **Chunk independence** is what makes parallelism possible

# ── What's Next ──

# **Continue in Core Zarr Concepts:**

# * `01_04_codecs_and_pipelines.livemd` - Zarr v2 compressors vs v3 codec pipelines

# **Dive deeper:**

# * `02_concurrency/02_01_parallel_reads.livemd` - Parallel chunk reads with task supervision
# * `02_concurrency/02_03_profiling_exzarr.livemd` - Understanding I/O vs decode vs scheduling costs

# **Apply to domains:**

# * `04_ai_genai/04_03_chunk_parallel_similarity.livemd` - Chunk-parallel similarity search
# * `05_finance/05_11_stress_testing_load.livemd` - Stress testing parallel query patterns
