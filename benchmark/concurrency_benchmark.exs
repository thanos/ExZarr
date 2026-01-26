# Concurrency Performance Benchmark
#
# Run with: mix run benchmark/concurrency_benchmark.exs
#
# Measures:
# 1. Lock acquisition overhead
# 2. Cache hit performance
# 3. Concurrent read throughput
# 4. Concurrent write throughput

defmodule ConcurrencyBenchmark do
  alias ExZarr.{ArrayServer, ChunkCache, Array}

  def run do
    IO.puts("\n=== ExZarr Concurrency Performance Benchmark ===\n")

    benchmark_lock_overhead()
    benchmark_cache_performance()
    benchmark_concurrent_reads()
    benchmark_concurrent_writes()

    IO.puts("\n=== Benchmark Complete ===\n")
  end

  defp benchmark_lock_overhead do
    IO.puts("1. Lock Acquisition Overhead")
    IO.puts("   Testing ArrayServer lock/unlock performance...\n")

    {:ok, server} = ArrayServer.start_link(array_id: "bench_array")

    # Warm up
    for _ <- 1..100 do
      ArrayServer.lock_chunk(server, {0, 0}, :read)
      ArrayServer.unlock_chunk(server, {0, 0})
    end

    # Benchmark read locks
    iterations = 10_000

    {time_read, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          ArrayServer.lock_chunk(server, {0, 0}, :read)
          ArrayServer.unlock_chunk(server, {0, 0})
        end
      end)

    avg_read = time_read / iterations / 1000
    IO.puts("   Read lock:  #{Float.round(avg_read, 3)}ms average (#{iterations} iterations)")

    # Benchmark write locks
    {time_write, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          ArrayServer.lock_chunk(server, {0, 0}, :write)
          ArrayServer.unlock_chunk(server, {0, 0})
        end
      end)

    avg_write = time_write / iterations / 1000
    IO.puts("   Write lock: #{Float.round(avg_write, 3)}ms average (#{iterations} iterations)")

    if avg_read < 10.0 and avg_write < 10.0 do
      IO.puts("   ✓ PASS: Lock overhead < 10ms\n")
    else
      IO.puts("   ✗ FAIL: Lock overhead >= 10ms\n")
    end
  end

  defp benchmark_cache_performance do
    IO.puts("2. Cache Performance")
    IO.puts("   Testing ChunkCache hit/miss performance...\n")

    {:ok, cache} = ChunkCache.start_link(max_size: 1000)

    key = {"/tmp/array", {0, 0}}
    data = :crypto.strong_rand_bytes(1024 * 10)  # 10KB chunk

    # Cache miss
    iterations = 1000

    {time_miss, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          ChunkCache.get(key, cache)
        end
      end)

    avg_miss = time_miss / iterations
    IO.puts("   Cache miss: #{Float.round(avg_miss, 1)}μs average")

    # Cache hit
    ChunkCache.put(key, data, cache)
    Process.sleep(10)  # Let cache settle

    {time_hit, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          ChunkCache.get(key, cache)
        end
      end)

    avg_hit = time_hit / iterations
    IO.puts("   Cache hit:  #{Float.round(avg_hit, 1)}μs average")

    speedup = time_miss / time_hit
    IO.puts("   Speedup:    #{Float.round(speedup, 1)}x faster\n")
  end

  defp benchmark_concurrent_reads do
    IO.puts("3. Concurrent Read Throughput")
    IO.puts("   Testing multiple processes reading simultaneously...\n")

    # Create test array
    tmp_dir = "/tmp/ex_zarr_bench_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)

    {:ok, array} =
      Array.create(
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :int32,
        storage: :filesystem,
        path: Path.join(tmp_dir, "read_array"),
        enable_server: true,
        enable_cache: true
      )

    # Populate array
    data = for i <- 0..9999, into: <<>>, do: <<i::32-little>>
    Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

    # Benchmark concurrent reads
    num_processes = 50
    reads_per_process = 20

    {time, _results} =
      :timer.tc(fn ->
        tasks =
          for _ <- 1..num_processes do
            Task.async(fn ->
              for _ <- 1..reads_per_process do
                row = :rand.uniform(90)
                col = :rand.uniform(90)
                {:ok, _} = Array.get_slice(array, start: {row, col}, stop: {row + 10, col + 10})
              end
            end)
          end

        Task.await_many(tasks, 60_000)
      end)

    total_reads = num_processes * reads_per_process
    throughput = total_reads / (time / 1_000_000)

    IO.puts("   Processes:  #{num_processes}")
    IO.puts("   Total reads: #{total_reads}")
    IO.puts("   Time:       #{Float.round(time / 1000, 1)}ms")
    IO.puts("   Throughput: #{Float.round(throughput, 0)} reads/sec\n")

    File.rm_rf(tmp_dir)
  end

  defp benchmark_concurrent_writes do
    IO.puts("4. Concurrent Write Throughput")
    IO.puts("   Testing multiple processes writing to different chunks...\n")

    # Create test array
    tmp_dir = "/tmp/ex_zarr_bench_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)

    {:ok, array} =
      Array.create(
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :int32,
        storage: :filesystem,
        path: Path.join(tmp_dir, "write_array"),
        enable_server: true
      )

    # Benchmark concurrent writes to different chunks
    num_processes = 25
    writes_per_process = 4

    {time, _results} =
      :timer.tc(fn ->
        tasks =
          for i <- 1..num_processes do
            Task.async(fn ->
              for j <- 0..(writes_per_process - 1) do
                chunk_idx = rem(i * writes_per_process + j, 100)
                row = div(chunk_idx, 10) * 10
                col = rem(chunk_idx, 10) * 10

                data = for k <- 0..99, into: <<>>, do: <<(i * 1000 + k)::32-little>>

                :ok =
                  Array.set_slice(array, data,
                    start: {row, col},
                    stop: {row + 10, col + 10}
                  )
              end
            end)
          end

        Task.await_many(tasks, 60_000)
      end)

    total_writes = num_processes * writes_per_process
    throughput = total_writes / (time / 1_000_000)

    IO.puts("   Processes:   #{num_processes}")
    IO.puts("   Total writes: #{total_writes}")
    IO.puts("   Time:        #{Float.round(time / 1000, 1)}ms")
    IO.puts("   Throughput:  #{Float.round(throughput, 0)} writes/sec\n")

    File.rm_rf(tmp_dir)
  end
end

# Run benchmark
ConcurrencyBenchmark.run()
