# Quick test for parallel chunk reading
Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

# Create test array
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

IO.puts("\n=== Testing 4x4 chunk read (16 chunks) ===\n")

# Single test
{time, {:ok, _data}} =
  :timer.tc(fn ->
    Array.get_slice(array, start: {0, 0}, stop: {400, 400})
  end)

IO.puts("Time: #{Float.round(time / 1000, 2)} ms\n")

# Now with caching disabled explicitly
{:ok, array_nocache} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory,
    cache_enabled: false
  )

# Populate
for x <- 0..9, y <- 0..9 do
  Array.set_slice(array_nocache, chunk_data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

IO.puts("=== Testing with cache disabled ===\n")

{time2, {:ok, _data}} =
  :timer.tc(fn ->
    Array.get_slice(array_nocache, start: {0, 0}, stop: {400, 400})
  end)

IO.puts("Time: #{Float.round(time2 / 1000, 2)} ms\n")
