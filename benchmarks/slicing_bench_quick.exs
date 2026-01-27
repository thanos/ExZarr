# Quick Slicing Benchmarks (completes in ~10 seconds)
#
# Minimal slicing performance tests
# Run with: mix run benchmarks/slicing_bench_quick.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== Quick Slicing Benchmarks ===\n")

# Create small 2D array
{:ok, array_2d} =
  Array.create(
    shape: {300, 300},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

chunk_data = for _ <- 1..10_000, into: <<>>, do: <<42::signed-little-32>>

# Populate 9 chunks (3x3)
for x <- 0..2, y <- 0..2 do
  Array.set_slice(array_2d, chunk_data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

IO.puts("2D array ready (9 chunks)\n")

Benchee.run(
  %{
    "single_chunk" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {100, 100})
    end,
    "4_chunks_2x2" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {200, 200})
    end,
    "9_chunks_3x3" => fn ->
      Array.get_slice(array_2d, start: {0, 0}, stop: {300, 300})
    end
  },
  time: 0.5,
  memory_time: 0.2,
  warmup: 0.2
)

IO.puts("\n=== 3D Array ===\n")

# Small 3D array
{:ok, array_3d} =
  Array.create(
    shape: {100, 100, 20},
    chunks: {50, 50, 10},
    dtype: :int32,
    storage: :memory
  )

chunk_data_3d = for _ <- 1..25_000, into: <<>>, do: <<1::signed-little-32>>

# Populate 4 chunks (2x2x1)
for x <- 0..1, y <- 0..1 do
  Array.set_slice(array_3d, chunk_data_3d,
    start: {x * 50, y * 50, 0},
    stop: {(x + 1) * 50, (y + 1) * 50, 10}
  )
end

IO.puts("3D array ready (4 chunks)\n")

Benchee.run(
  %{
    "3D_single_chunk" => fn ->
      Array.get_slice(array_3d, start: {0, 0, 0}, stop: {50, 50, 10})
    end,
    "3D_4_chunks" => fn ->
      Array.get_slice(array_3d, start: {0, 0, 0}, stop: {100, 100, 10})
    end
  },
  time: 0.5,
  memory_time: 0.2,
  warmup: 0.2
)

IO.puts("\n=== Benchmark Complete ===\n")
