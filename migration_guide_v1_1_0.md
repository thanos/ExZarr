# Migration Guide: v1.0.x to v1.1.0

## No Breaking Changes

v1.1.0 is fully backward compatible with v1.0.x.

## Recommended API Updates

### Rename chunk_stream to stream_chunks

```elixir
# Before (still works)
Array.chunk_stream(array, parallel: 4)

# After (recommended)
Array.stream_chunks(array, concurrency: 4)
```

The `:parallel` option is still accepted as an alias for `:concurrency`.

### Add Telemetry Handlers

```elixir
:telemetry.attach(
  "ex-zarr-streams",
  [:ex_zarr, :stream, :stop],
  &MyApp.Metrics.handle_stream/4,
  nil
)
```

### Optional Dependencies

To use Flow, GenStage, or Broadway integrations:

```elixir
{:ex_zarr, "~> 1.1"},
{:flow, "~> 1.2"},
{:gen_stage, "~> 1.2"},
{:broadway, "~> 1.0"}
```

## New Capabilities

### Write from Streams

```elixir
ExZarr.Array.write_stream(array, chunk_source, batch_size: 4, checkpoint: &save_progress/1)
```

### Slice Streaming

```elixir
array
|> ExZarr.Array.stream_slices(0, start: {0, 0}, stop: {1000, 500})
|> Enum.each(&process_row/1)
```
