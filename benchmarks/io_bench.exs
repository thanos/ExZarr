# I/O Benchmarks
#
# Benchmarks read and write performance for different storage backends
# Run with: mix run benchmarks/io_bench.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

# Setup temporary directory
tmp_dir = "/tmp/ex_zarr_io_bench_#{System.unique_integer()}"
File.mkdir_p!(tmp_dir)

IO.puts("\n=== Array Creation Benchmarks ===\n")

# Note: Using filesystem storage for large arrays to avoid process limit
# Memory backend creates Agent processes which accumulate during benchmarking
Benchee.run(
  %{
    "create_small_int32_memory" => fn ->
      {:ok, _} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory
        )
    end,
    "create_medium_float64_fs" => fn ->
      path = Path.join(tmp_dir, "bench_medium_#{:erlang.unique_integer()}")

      {:ok, _} =
        Array.create(
          shape: {1000, 1000},
          chunks: {100, 100},
          dtype: :float64,
          storage: :filesystem,
          path: path
        )

      File.rm_rf!(path)
    end,
    "create_large_int32_fs" => fn ->
      path = Path.join(tmp_dir, "bench_large_#{:erlang.unique_integer()}")

      {:ok, _} =
        Array.create(
          shape: {10000, 1000},
          chunks: {1000, 100},
          dtype: :int32,
          storage: :filesystem,
          path: path
        )

      File.rm_rf!(path)
    end
  },
  time: 1,
  memory_time: 0.5,
  warmup: 0.5
)

IO.puts("\n=== Write Performance Benchmarks ===\n")

# Create test arrays
{:ok, small_array} =
  Array.create(
    shape: {100, 100},
    chunks: {10, 10},
    dtype: :int32,
    storage: :memory
  )

{:ok, medium_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

# Generate test data
small_data = for _ <- 1..100, into: <<>>, do: <<1::signed-little-32>>
medium_data = for _ <- 1..10000, into: <<>>, do: <<1::signed-little-32>>

Benchee.run(
  %{
    "write_single_chunk_10x10" => fn ->
      Array.set_slice(small_array, small_data, start: {0, 0}, stop: {10, 10})
    end,
    "write_single_chunk_100x100" => fn ->
      Array.set_slice(medium_array, medium_data, start: {0, 0}, stop: {100, 100})
    end,
    "write_multiple_chunks_100x100" => fn ->
      Array.set_slice(medium_array, medium_data, start: {0, 0}, stop: {100, 100})
      Array.set_slice(medium_array, medium_data, start: {100, 100}, stop: {200, 200})
    end,
    "write_cross_chunk_100x100" => fn ->
      # Write data that spans multiple chunks
      Array.set_slice(medium_array, medium_data, start: {50, 50}, stop: {150, 150})
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Read Performance Benchmarks ===\n")

# Pre-populate arrays with data
Array.set_slice(small_array, small_data, start: {0, 0}, stop: {10, 10})
Array.set_slice(medium_array, medium_data, start: {0, 0}, stop: {100, 100})

Benchee.run(
  %{
    "read_single_chunk_10x10" => fn ->
      Array.get_slice(small_array, start: {0, 0}, stop: {10, 10})
    end,
    "read_single_chunk_100x100" => fn ->
      Array.get_slice(medium_array, start: {0, 0}, stop: {100, 100})
    end,
    "read_multiple_chunks_200x200" => fn ->
      Array.get_slice(medium_array, start: {0, 0}, stop: {200, 200})
    end,
    "read_cross_chunk_150x150" => fn ->
      Array.get_slice(medium_array, start: {50, 50}, stop: {200, 200})
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Filesystem vs Memory Storage ===\n")

{:ok, fs_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :filesystem,
    path: Path.join(tmp_dir, "fs_test")
  )

{:ok, mem_array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

Benchee.run(
  %{
    "write_filesystem" => fn ->
      Array.set_slice(fs_array, medium_data, start: {0, 0}, stop: {100, 100})
    end,
    "write_memory" => fn ->
      Array.set_slice(mem_array, medium_data, start: {0, 0}, stop: {100, 100})
    end,
    "read_filesystem" => fn ->
      Array.get_slice(fs_array, start: {0, 0}, stop: {100, 100})
    end,
    "read_memory" => fn ->
      Array.get_slice(mem_array, start: {0, 0}, stop: {100, 100})
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

# Cleanup
File.rm_rf!(tmp_dir)

IO.puts("\n=== Benchmark Complete ===\n")
