# Fast Slicing Benchmarks
#
# Streamlined slicing benchmarks focusing on key scenarios
# Run with: mix run benchmarks/slicing_bench_fast.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== Fast Slicing Benchmarks ===\n")

# Create 2D array (most common use case)
IO.puts("Creating 2D array...")

{:ok, array_2d} =
  Array.create(
    shape: {500, 500},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

chunk_data = for _ <- 1..10_000, into: <<>>, do: <<42::signed-little-32>>

# Populate 25 chunks (5x5)
for x <- 0..4, y <- 0..4 do
  Array.set_slice(array_2d, chunk_data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

IO.puts("Populated 25 chunks\n")

Benchee.run(
  %{
    "2D: single chunk" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {100, 100})
    end,
    "2D: 4 chunks (2x2)" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {200, 200})
    end,
    "2D: 16 chunks (4x4)" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {400, 400})
    end,
    "2D: cross-chunk" => fn ->
      Array.get_slice(array_2d, start: {50, 50}, stop: {150, 150})
    end
  },
  time: 2,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== 3D Array ===\n")

# Create smaller 3D array
{:ok, array_3d} =
  Array.create(
    shape: {200, 200, 20},
    chunks: {50, 50, 10},
    dtype: :int32,
    storage: :memory
  )

chunk_data_3d = for _ <- 1..25_000, into: <<>>, do: <<1::signed-little-32>>

# Populate subset (2x2x2 = 8 chunks)
for x <- 0..1, y <- 0..1, z <- 0..1 do
  Array.set_slice(array_3d, chunk_data_3d,
    start: {x * 50, y * 50, z * 10},
    stop: {(x + 1) * 50, (y + 1) * 50, (z + 1) * 10}
  )
end

IO.puts("Populated 8 chunks\n")

Benchee.run(
  %{
    "3D: single chunk" => fn ->
      Array.get_slice(array_3d, start: {0, 0, 0}, stop: {50, 50, 10})
    end,
    "3D: 8 chunks (2x2x2)" => fn ->
      Array.get_slice(array_3d, start: {0, 0, 0}, stop: {100, 100, 20})
    end
  },
  time: 2,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Different Dtypes ===\n")

# Test different data types
{:ok, array_float} =
  Array.create(
    shape: {200, 200},
    chunks: {100, 100},
    dtype: :float64,
    storage: :memory
  )

float_data = for _ <- 1..10_000, into: <<>>, do: <<1.0::float-64-native>>

Array.set_slice(array_float, float_data, start: {0, 0}, stop: {100, 100})

Benchee.run(
  %{
    "int32" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {100, 100})
    end,
    "float64" => fn ->
      Array.get_slice(array_float, start: {0, 0}, stop: {100, 100})
    end
  },
  time: 2,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Benchmark Complete ===\n")
