# Simple Performance Profiling
#
# Uses :timer.tc for timing measurements
# Run with: mix run benchmarks/profile_simple.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array
alias ExZarr.Codecs

defmodule Profiler do
  def measure(description, func) do
    # Warm up
    func.()

    # Measure
    times =
      for _ <- 1..10 do
        {time, _} = :timer.tc(func)
        time
      end

    avg = Enum.sum(times) / length(times)
    min = Enum.min(times)
    max = Enum.max(times)

    IO.puts("#{description}:")
    IO.puts("  Average: #{Float.round(avg / 1000, 2)} ms")
    IO.puts("  Min: #{Float.round(min / 1000, 2)} ms")
    IO.puts("  Max: #{Float.round(max / 1000, 2)} ms")
    IO.puts("")

    avg
  end

  def measure_memory(description, func) do
    # Force GC before measurement
    :erlang.garbage_collect()
    mem_before = :erlang.memory(:total)

    func.()

    :erlang.garbage_collect()
    mem_after = :erlang.memory(:total)

    diff = mem_after - mem_before

    IO.puts("#{description}:")
    IO.puts("  Memory delta: #{Float.round(diff / 1024 / 1024, 2)} MB")
    IO.puts("")
  end
end

IO.puts("\n=== Performance Analysis ===\n")

# Create test array
IO.puts("Creating test array...")

{:ok, array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

chunk_data = for _ <- 1..10_000, into: <<>>, do: <<1::signed-little-32>>

# Populate array
for x <- 0..9, y <- 0..9 do
  Array.set_slice(array, chunk_data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

IO.puts("Array populated with 100 chunks\n")
IO.puts("=== Read Performance ===\n")

# Single chunk read
single_chunk_time =
  Profiler.measure("Single chunk read (100x100)", fn ->
    {:ok, _} = Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  end)

# 2x2 chunks
four_chunks_time =
  Profiler.measure("2x2 chunk read (200x200)", fn ->
    {:ok, _} = Array.get_slice(array, start: {0, 0}, stop: {200, 200})
  end)

# 4x4 chunks
sixteen_chunks_time =
  Profiler.measure("4x4 chunk read (400x400)", fn ->
    {:ok, _} = Array.get_slice(array, start: {0, 0}, stop: {400, 400})
  end)

IO.puts("Scaling analysis:")
IO.puts("  2x2 chunks: #{Float.round(four_chunks_time / single_chunk_time, 2)}x single chunk time")
IO.puts("  4x4 chunks: #{Float.round(sixteen_chunks_time / single_chunk_time, 2)}x single chunk time")
IO.puts("")

IO.puts("=== Write Performance ===\n")

# Create fresh array for writes
{:ok, write_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

Profiler.measure("Single chunk write (100x100)", fn ->
  Array.set_slice(write_array, chunk_data, start: {0, 0}, stop: {100, 100})
end)

Profiler.measure("Cross-chunk write (150x150)", fn ->
  Array.set_slice(write_array, chunk_data, start: {50, 50}, stop: {200, 200})
end)

IO.puts("=== Compression Performance ===\n")

data_1kb = :crypto.strong_rand_bytes(1024)
data_100kb = :crypto.strong_rand_bytes(100 * 1024)
data_1mb = :crypto.strong_rand_bytes(1024 * 1024)

Profiler.measure("Compress 1KB (zlib)", fn ->
  {:ok, _} = Codecs.compress(data_1kb, :zlib)
end)

Profiler.measure("Compress 100KB (zlib)", fn ->
  {:ok, _} = Codecs.compress(data_100kb, :zlib)
end)

Profiler.measure("Compress 1MB (zlib)", fn ->
  {:ok, _} = Codecs.compress(data_1mb, :zlib)
end)

# Decompress
{:ok, compressed_1mb} = Codecs.compress(data_1mb, :zlib)

Profiler.measure("Decompress 1MB (zlib)", fn ->
  {:ok, _} = Codecs.decompress(compressed_1mb, :zlib)
end)

IO.puts("=== Memory Usage Analysis ===\n")

Profiler.measure_memory("Create 1000x1000 array", fn ->
  {:ok, _} =
    Array.create(
      shape: {1000, 1000},
      chunks: {100, 100},
      dtype: :int32,
      storage: :memory
    )
end)

Profiler.measure_memory("Read 100 chunks", fn ->
  for x <- 0..9, y <- 0..9 do
    Array.get_slice(array, start: {x * 100, y * 100}, stop: {(x + 1) * 100, (y + 1) * 100})
  end
end)

Profiler.measure_memory("Write 100 chunks", fn ->
  for x <- 0..9, y <- 0..9 do
    Array.set_slice(write_array, chunk_data,
      start: {x * 100, y * 100},
      stop: {(x + 1) * 100, (y + 1) * 100}
    )
  end
end)

IO.puts("=== Analysis Complete ===\n")
