# Performance Profiling Script
#
# Profiles hot paths in ExZarr to identify bottlenecks
# Run with: mix run benchmarks/profile.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== Profiling ExZarr Hot Paths ===\n")

# Create test array
{:ok, array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

# Generate test data
chunk_data = for _ <- 1..10_000, into: <<>>, do: <<1::signed-little-32>>

# Populate some chunks
IO.puts("Populating test array...")

for x <- 0..4, y <- 0..4 do
  Array.set_slice(array, chunk_data,
    start: {x * 100, y * 100},
    stop: {(x + 1) * 100, (y + 1) * 100}
  )
end

IO.puts("Array populated with 25 chunks\n")

# Profile 1: Single chunk read
IO.puts("=== Profile 1: Single Chunk Read ===\n")

:fprof.trace([:start, {:procs, :all}])

for _ <- 1..100 do
  Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end

:fprof.trace(:stop)
:fprof.profile()
:fprof.analyse([dest: '/tmp/single_chunk_read.fprof', totals: true, sort: :own])

IO.puts("Profile saved to /tmp/single_chunk_read.fprof")
IO.puts("Top functions by own time:")

File.read!('/tmp/single_chunk_read.fprof')
|> String.split("\n")
|> Enum.filter(&String.contains?(&1, "ExZarr"))
|> Enum.take(20)
|> Enum.each(&IO.puts/1)

# Profile 2: Multiple chunk read
IO.puts("\n=== Profile 2: Multiple Chunk Read ===\n")

:fprof.trace([:start, {:procs, :all}])

for _ <- 1..10 do
  Array.get_slice(array, start: {0, 0}, stop: {200, 200})
end

:fprof.trace(:stop)
:fprof.profile()
:fprof.analyse([dest: '/tmp/multi_chunk_read.fprof', totals: true, sort: :own])

IO.puts("Profile saved to /tmp/multi_chunk_read.fprof")
IO.puts("Top functions by own time:")

File.read!('/tmp/multi_chunk_read.fprof')
|> String.split("\n")
|> Enum.filter(&String.contains?(&1, "ExZarr"))
|> Enum.take(20)
|> Enum.each(&IO.puts/1)

# Profile 3: Chunk writes
IO.puts("\n=== Profile 3: Chunk Writes ===\n")

:fprof.trace([:start, {:procs, :all}])

for x <- 5..9 do
  Array.set_slice(array, chunk_data,
    start: {x * 100, 0},
    stop: {(x + 1) * 100, 100}
  )
end

:fprof.trace(:stop)
:fprof.profile()
:fprof.analyse([dest: '/tmp/chunk_write.fprof', totals: true, sort: :own])

IO.puts("Profile saved to /tmp/chunk_write.fprof")
IO.puts("Top functions by own time:")

File.read!('/tmp/chunk_write.fprof')
|> String.split("\n")
|> Enum.filter(&String.contains?(&1, "ExZarr"))
|> Enum.take(20)
|> Enum.each(&IO.puts/1)

# Profile 4: Compression
IO.puts("\n=== Profile 4: Compression ===\n")

alias ExZarr.Codecs

test_data = :crypto.strong_rand_bytes(100 * 1024)

:fprof.trace([:start, {:procs, :all}])

for _ <- 1..50 do
  {:ok, _compressed} = Codecs.compress(test_data, :zlib)
end

:fprof.trace(:stop)
:fprof.profile()
:fprof.analyse([dest: '/tmp/compression.fprof', totals: true, sort: :own])

IO.puts("Profile saved to /tmp/compression.fprof")
IO.puts("Top functions by own time:")

File.read!('/tmp/compression.fprof')
|> String.split("\n")
|> Enum.filter(fn line ->
  String.contains?(line, "ExZarr") or String.contains?(line, "zlib")
end)
|> Enum.take(20)
|> Enum.each(&IO.puts/1)

IO.puts("\n=== Profiling Complete ===")
IO.puts("\nProfile files:")
IO.puts("  - /tmp/single_chunk_read.fprof")
IO.puts("  - /tmp/multi_chunk_read.fprof")
IO.puts("  - /tmp/chunk_write.fprof")
IO.puts("  - /tmp/compression.fprof")
IO.puts("\nUse :fprof.analyse([{:dest, []}, {:callers, true}]) for detailed call trees")
