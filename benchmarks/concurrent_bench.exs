# Concurrent Access Benchmarks
#
# Benchmarks concurrent read/write performance
# Run with: mix run benchmarks/concurrent_bench.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== Concurrent Read Benchmarks ===\n")

# Create and populate test array
{:ok, array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory,
    cache_enabled: true
  )

data = for _ <- 1..10_000, into: <<>>, do: <<42::signed-little-32>>

for x <- 0..9, y <- 0..9 do
  Array.set_slice(array, data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

IO.puts("Array populated with 100 chunks\n")

# Benchmark concurrent reads
Benchee.run(
  %{
    "sequential_10_reads" => fn ->
      for i <- 0..9 do
        x = rem(i, 10) * 100
        y = div(i, 10) * 100
        Array.get_slice(array, start: {x, y}, stop: {x + 100, y + 100})
      end
    end,
    "concurrent_2_reads" => fn ->
      tasks =
        for i <- 0..1 do
          Task.async(fn ->
            x = rem(i, 10) * 100
            y = div(i, 10) * 100
            Array.get_slice(array, start: {x, y}, stop: {x + 100, y + 100})
          end)
        end

      Task.await_many(tasks)
    end,
    "concurrent_4_reads" => fn ->
      tasks =
        for i <- 0..3 do
          Task.async(fn ->
            x = rem(i, 10) * 100
            y = div(i, 10) * 100
            Array.get_slice(array, start: {x, y}, stop: {x + 100, y + 100})
          end)
        end

      Task.await_many(tasks)
    end,
    "concurrent_8_reads" => fn ->
      tasks =
        for i <- 0..7 do
          Task.async(fn ->
            x = rem(i, 10) * 100
            y = div(i, 10) * 100
            Array.get_slice(array, start: {x, y}, stop: {x + 100, y + 100})
          end)
        end

      Task.await_many(tasks)
    end,
    "concurrent_16_reads" => fn ->
      tasks =
        for i <- 0..15 do
          Task.async(fn ->
            x = rem(i, 10) * 100
            y = div(i, 10) * 100
            Array.get_slice(array, start: {x, y}, stop: {x + 100, y + 100})
          end)
        end

      Task.await_many(tasks)
    end
  },
  time: 5,
  memory_time: 2,
  warmup: 1
)

IO.puts("\n=== Concurrent Write Benchmarks ===\n")

# Create fresh array for writes
{:ok, write_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

Benchee.run(
  %{
    "sequential_10_writes" => fn ->
      for i <- 0..9 do
        x = rem(i, 10) * 100
        y = div(i, 10) * 100
        Array.set_slice(write_array, data, start: {x, y}, stop: {x + 100, y + 100})
      end
    end,
    "concurrent_2_writes" => fn ->
      tasks =
        for i <- 0..1 do
          Task.async(fn ->
            x = rem(i, 10) * 100
            y = div(i, 10) * 100
            Array.set_slice(write_array, data, start: {x, y}, stop: {x + 100, y + 100})
          end)
        end

      Task.await_many(tasks)
    end,
    "concurrent_4_writes" => fn ->
      tasks =
        for i <- 0..3 do
          Task.async(fn ->
            x = rem(i, 10) * 100
            y = div(i, 10) * 100
            Array.set_slice(write_array, data, start: {x, y}, stop: {x + 100, y + 100})
          end)
        end

      Task.await_many(tasks)
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Cache Hit Rate Impact ===\n")

# Array with cache enabled
{:ok, cached_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory,
    cache_enabled: true
  )

# Array without cache
{:ok, uncached_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory,
    cache_enabled: false
  )

# Populate both
for x <- 0..9, y <- 0..9 do
  Array.set_slice(cached_array, data, start: {x, y}, stop: {x + 100, y + 100})
  Array.set_slice(uncached_array, data, start: {x, y}, stop: {x + 100, y + 100})
end

Benchee.run(
  %{
    "cached_repeated_reads" => fn ->
      # Read same chunk 10 times
      for _ <- 1..10 do
        Array.get_slice(cached_array, start: {0, 0}, stop: {100, 100})
      end
    end,
    "uncached_repeated_reads" => fn ->
      for _ <- 1..10 do
        Array.get_slice(uncached_array, start: {0, 0}, stop: {100, 100})
      end
    end,
    "cached_sequential_reads" => fn ->
      for i <- 0..9 do
        x = rem(i, 10) * 100
        y = div(i, 10) * 100
        Array.get_slice(cached_array, start: {x, y}, stop: {x + 100, y + 100})
      end
    end,
    "uncached_sequential_reads" => fn ->
      for i <- 0..9 do
        x = rem(i, 10) * 100
        y = div(i, 10) * 100
        Array.get_slice(uncached_array, start: {x, y}, stop: {x + 100, y + 100})
      end
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Chunk Streaming Parallel Performance ===\n")

{:ok, stream_array} =
  Array.create(
    shape: {500, 500},
    chunks: {50, 50},
    dtype: :int32,
    storage: :memory
  )

chunk_data = for _ <- 1..2500, into: <<>>, do: <<1::signed-little-32>>

for x <- 0..9, y <- 0..9 do
  Array.set_slice(stream_array, chunk_data,
    start: {x * 50, y * 50},
    stop: {(x + 1) * 50, (y + 1) * 50}
  )
end

Benchee.run(
  %{
    "stream_sequential" => fn ->
      stream_array
      |> Array.chunk_stream(parallel: 1)
      |> Enum.to_list()
    end,
    "stream_parallel_2" => fn ->
      stream_array
      |> Array.chunk_stream(parallel: 2)
      |> Enum.to_list()
    end,
    "stream_parallel_4" => fn ->
      stream_array
      |> Array.chunk_stream(parallel: 4)
      |> Enum.to_list()
    end,
    "stream_parallel_8" => fn ->
      stream_array
      |> Array.chunk_stream(parallel: 8)
      |> Enum.to_list()
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Benchmark Complete ===\n")
