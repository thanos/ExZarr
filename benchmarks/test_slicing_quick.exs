# Quick slicing performance test
Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== Quick Slicing Performance Test ===\n")

# Create 2D array
{:ok, array_2d} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

chunk_data = for _ <- 1..10_000, into: <<>>, do: <<42::signed-little-32>>

# Populate
for x <- 0..9, y <- 0..9 do
  Array.set_slice(array_2d, chunk_data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

# Test different slice patterns
tests = [
  {"Single chunk (100x100)", {0, 0}, {100, 100}},
  {"2x2 chunks (200x200)", {0, 0}, {200, 200}},
  {"4x4 chunks (400x400)", {0, 0}, {400, 400}},
  {"Cross-chunk (50->150)", {50, 50}, {150, 150}},
  {"Single row (1x1000)", {0, 0}, {1, 1000}},
  {"Single column (1000x1)", {0, 0}, {1000, 1}}
]

IO.puts("2D Array Tests:")
for {name, start, stop} <- tests do
  {time, {:ok, _}} = :timer.tc(fn ->
    Array.get_slice(array_2d, start: start, stop: stop)
  end)
  IO.puts("  #{String.pad_trailing(name, 30)}: #{Float.round(time / 1000, 2)} ms")
end

# Create 3D array
IO.puts("\n3D Array Tests:")

{:ok, array_3d} =
  Array.create(
    shape: {100, 100, 100},
    chunks: {10, 10, 10},
    dtype: :int32,
    storage: :memory
  )

chunk_data_3d = for _ <- 1..1000, into: <<>>, do: <<1::signed-little-32>>

# Populate subset
for x <- 0..4, y <- 0..4, z <- 0..4 do
  Array.set_slice(array_3d, chunk_data_3d,
    start: {x * 10, y * 10, z * 10},
    stop: {(x + 1) * 10, (y + 1) * 10, (z + 1) * 10}
  )
end

tests_3d = [
  {"Single chunk (10x10x10)", {0, 0, 0}, {10, 10, 10}},
  {"2x2x2 chunks (20x20x20)", {0, 0, 0}, {20, 20, 20}},
  {"4x4x4 chunks (40x40x40)", {0, 0, 0}, {40, 40, 40}}
]

for {name, start, stop} <- tests_3d do
  {time, {:ok, _}} = :timer.tc(fn ->
    Array.get_slice(array_3d, start: start, stop: stop)
  end)
  IO.puts("  #{String.pad_trailing(name, 30)}: #{Float.round(time / 1000, 2)} ms")
end

IO.puts("\n=== All Tests Passed ===")
