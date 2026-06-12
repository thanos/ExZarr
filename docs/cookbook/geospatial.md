# Geospatial Zarr Datasets

Climate and earth observation datasets typically use `(time, lat, lon)` layouts.

```elixir
# Stream time steps
array
|> ExZarr.Array.stream_slices(0,
  start: {0, 0, 0},
  stop: {365, 180, 360},
  concurrency: 4
)
|> Enum.map(fn {start, data} -> {elem(start, 0), compute_anomaly(data)} end)
```

For spatial window extraction, use `get_slice/2` with named dimensions on
v3 arrays or explicit start/stop coordinates.
