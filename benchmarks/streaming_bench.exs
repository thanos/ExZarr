# Streaming API benchmarks for v1.1.0
# Run with: mix run benchmarks/streaming_bench.exs

Application.ensure_all_started(:ex_zarr)

alias ExZarr.Array

IO.puts("\n=== ExZarr v1.1.0 Streaming Benchmarks ===\n")

{:ok, array} =
  Array.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :int32,
    storage: :memory
  )

data = for(_ <- 1..10_000, into: <<>>, do: <<42::signed-little-32>>)

for x <- 0..9, y <- 0..9 do
  Array.set_slice(array, data, start: {x * 100, y * 100}, stop: {(x + 1) * 100, (y + 1) * 100})
end

schedulers = System.schedulers_online()

Benchee.run(
  %{
    "stream_chunks sequential" => fn ->
      array |> Array.stream_chunks() |> Enum.take(50) |> Enum.to_list()
    end,
    "stream_chunks concurrency=#{schedulers}" => fn ->
      array
      |> Array.stream_chunks(concurrency: schedulers, ordered: false)
      |> Enum.take(50)
      |> Enum.to_list()
    end,
    "stream_chunks concurrency=#{schedulers * 2}" => fn ->
      array
      |> Array.stream_chunks(concurrency: schedulers * 2, ordered: false)
      |> Enum.take(50)
      |> Enum.to_list()
    end,
    "stream_slices rows" => fn ->
      array |> Array.stream_slices(0) |> Enum.take(50) |> Enum.to_list()
    end
  },
  time: 5,
  warmup: 1
)
