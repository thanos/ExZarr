# Processing 100GB Zarr Arrays

## Problem

A 100GB array exceeds available RAM. You need to compute statistics or
transform data without loading the full array.

## Solution

Use `stream_chunks/2` with bounded concurrency:

```elixir
{:ok, array} = ExZarr.open(path: "/data/large_dataset")

{sum, count} =
  array
  |> ExZarr.Array.stream_chunks(concurrency: 8, ordered: false)
  |> Enum.reduce({0, 0}, fn {_index, data}, {acc_sum, acc_count} ->
    chunk_sum =
      for(<<val::float-little-64 <- data>>, reduce: 0, acc -> acc + val)

    {acc_sum + chunk_sum, acc_count + div(byte_size(data), 8)}
  end)

mean = sum / count
```

## Memory Budget

With 1MB chunks and concurrency 8, peak memory is approximately 8MB of chunk
data plus decompression buffers. Keep concurrency below 10% of available RAM
divided by average chunk size.

## When to Use Slices Instead

If you need row-wise access (e.g., time series), use `stream_slices/3`:

```elixir
array
|> ExZarr.Array.stream_slices(0, concurrency: 4)
|> Enum.each(&process_timestep/1)
```
