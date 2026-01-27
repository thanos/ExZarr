# Detailed timing test
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

# Manually time each step
IO.puts("\n=== Detailed Timing for 4x4 Chunk Read ===\n")

# Step 1: Calculate chunk indices
{time1, {:ok, chunk_indices}} =
  :timer.tc(fn ->
    # This mimics what get_slice does
    start = {0, 0}
    stop = {400, 400}
    ExZarr.Indexing.calculate_chunk_indices(array.chunks, start, stop)
  end)

IO.puts("1. Calculate chunk indices (#{length(chunk_indices)} chunks): #{Float.round(time1 / 1000, 3)} ms")

# Step 2: Read chunks
{time2, result} =
  :timer.tc(fn ->
    # Call the private function via the public API
    # We'll just measure the full get_slice for now
    Array.get_slice(array, start: {0, 0}, stop: {400, 400})
  end)

IO.puts("2. Full get_slice operation: #{Float.round(time2 / 1000, 3)} ms")

IO.puts("\nRatio: get_slice is #{Float.round(time2 / time1, 1)}x slower than just index calculation")
IO.puts("\nThis suggests the bottleneck is in chunk reading or data assembly, not index calculation")
