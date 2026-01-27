# Slicing and Indexing Benchmarks
#
# Benchmarks slicing and indexing performance
# Run with: mix run benchmarks/slicing_bench.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== Slicing Performance Benchmarks ===\n")

# Create smaller test array to avoid memory issues
{:ok, array} =
  Array.create(
    shape: {500, 500, 50},
    chunks: {100, 100, 10},
    dtype: :int32,
    storage: :memory
  )

# Populate with test data
chunk_data = for _ <- 1..100_000, into: <<>>, do: <<42::signed-little-32>>

for x <- 0..4, y <- 0..4, z <- 0..4 do
  Array.set_slice(array, chunk_data,
    start: {x * 100, y * 100, z * 10},
    stop: {(x + 1) * 100, (y + 1) * 100, (z + 1) * 10}
  )
end

IO.puts("Array populated with #{5 * 5 * 5} chunks\n")

Benchee.run(
  %{
    "single_chunk_slice" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {100, 100, 10})
    end,
    "2x2x1_chunk_slice" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {200, 200, 10})
    end,
    "4x4x1_chunk_slice" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {400, 400, 10})
    end,
    "cross_chunk_slice" => fn ->
      Array.get_slice(array, start: {50, 50, 5}, stop: {150, 150, 15})
    end,
    "full_z_slice" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {100, 100, 50})
    end,
    "single_row" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {1, 500, 10})
    end,
    "single_column" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {500, 1, 10})
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Different Array Shapes ===\n")

# 1D array (smaller)
{:ok, array_1d} =
  Array.create(
    shape: {100_000},
    chunks: {10_000},
    dtype: :int32,
    storage: :memory
  )

data_1d = for _ <- 1..10_000, into: <<>>, do: <<1::signed-little-32>>
Array.set_slice(array_1d, data_1d, start: {0}, stop: {10_000})

# 2D array (smaller)
{:ok, array_2d} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

data_2d = for _ <- 1..10_000, into: <<>>, do: <<1::signed-little-32>>
Array.set_slice(array_2d, data_2d, start: {0, 0}, stop: {100, 100})

# 4D array (smaller)
{:ok, array_4d} =
  Array.create(
    shape: {50, 50, 50, 10},
    chunks: {10, 10, 10, 10},
    dtype: :int32,
    storage: :memory
  )

data_4d = for _ <- 1..10_000, into: <<>>, do: <<1::signed-little-32>>
Array.set_slice(array_4d, data_4d, start: {0, 0, 0, 0}, stop: {10, 10, 10, 10})

Benchee.run(
  %{
    "1D_slice_10k" => fn ->
      Array.get_slice(array_1d, start: {0}, stop: {10_000})
    end,
    "2D_slice_100x100" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {100, 100})
    end,
    "3D_slice_100x100x10" => fn ->
      Array.get_slice(array, start: {0, 0, 0}, stop: {100, 100, 10})
    end,
    "4D_slice_10x10x10x10" => fn ->
      Array.get_slice(array_4d, start: {0, 0, 0, 0}, stop: {10, 10, 10, 10})
    end
  },
  time: 2,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Strided Access Patterns ===\n")

# Create smaller array for strided access
{:ok, strided_array} =
  Array.create(
    shape: {500, 500},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

data = for _ <- 1..10_000, into: <<>>, do: <<1::signed-little-32>>

for x <- 0..4, y <- 0..4 do
  Array.set_slice(strided_array, data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

Benchee.run(
  %{
    "contiguous_read" => fn ->
      Array.get_slice(strided_array, start: {0, 0}, stop: {100, 100})
    end,
    "every_other_row" => fn ->
      for i <- 0..24 do
        Array.get_slice(strided_array, start: {i * 2, 0}, stop: {i * 2 + 1, 100})
      end
    end,
    "every_10th_row" => fn ->
      for i <- 0..4 do
        Array.get_slice(strided_array, start: {i * 10, 0}, stop: {i * 10 + 1, 100})
      end
    end,
    "random_access_5_chunks" => fn ->
      indices = Enum.take_random(0..24, 5)

      for i <- indices do
        x = rem(i, 5) * 100
        y = div(i, 5) * 100
        Array.get_slice(strided_array, start: {x, y}, stop: {x + 100, y + 100})
      end
    end
  },
  time: 2,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Benchmark Complete ===\n")
