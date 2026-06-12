# Image Archives in Zarr

Store image tiles as chunks and process with Broadway:

```elixir
array
|> ExZarr.Array.stream_chunks(concurrency: 16, metadata: true)
|> Stream.map(fn %{index: idx, data: tile, metadata: meta} ->
  {idx, meta.bounds, process_tile(tile)}
end)
|> then(&ExZarr.Array.write_stream(output_array, &1, batch_size: 8))
```

Each chunk corresponds to a spatial tile. Use `metadata: true` to recover
pixel bounds without separate coordinate math.
