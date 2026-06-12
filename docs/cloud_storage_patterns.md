# Cloud Storage Patterns for ExZarr v1.1.0

## Overview

ExZarr cloud backends (S3, GCS, Azure Blob) store each chunk as an independent
object. v1.1.0 streaming APIs are designed for high-concurrency cloud access.

## Retry Strategy

Cloud reads should use streaming with bounded concurrency and error handling:

```elixir
array
|> ExZarr.Array.stream_chunks(
  concurrency: 16,
  ordered: false,
  timeout: 120_000,
  on_error: fn index, reason ->
    Logger.warning("chunk #{inspect(index)} failed: #{inspect(reason)}")
  end
)
|> Stream.run()
```

For application-level retries, wrap chunk processing:

```elixir
retry_read = fn array, index, attempts ->
  Enum.reduce_while(1..attempts, {:error, :exhausted}, fn attempt, _acc ->
    case read_chunk(array, index) do
      {:ok, data} -> {:halt, {:ok, data}}
      {:error, reason} when attempt < attempts ->
        Process.sleep(attempt * 100)
        {:cont, {:error, reason}}
      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end)
end
```

## Partial Failures

Chunk writes are atomic per object. A failed `write_stream/3` leaves prior
chunks intact. Use checkpoints for resumable ingestion:

```elixir
ExZarr.Array.write_stream(chunk_stream, array,
  checkpoint: fn %{last_index: index, written: n} ->
    File.write!("checkpoint.json", Jason.encode!(%{index: index, written: n}))
  end
)
```

## Interrupted Writes

If a process crashes mid-stream, already-written chunks remain valid Zarr chunks.
Re-run with `:filter` to skip completed indices:

```elixir
completed = load_completed_indices("checkpoint.json")

array
|> ExZarr.Array.stream_chunks(filter: fn idx -> idx not in completed end)
```

## Idempotency

Writing the same chunk index twice with identical data is idempotent. Cloud PUT
operations overwrite the previous object. For pipelines, track written indices
externally or use deterministic chunk indices.

## Backend-Specific Notes

### S3

```elixir
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)

{:ok, array} = ExZarr.create(
  shape: {10_000, 10_000},
  chunks: {512, 512},
  storage: :s3,
  bucket: "my-data",
  prefix: "experiments/run-42"
)
```

- Use concurrency 16-32 for throughput
- Configure IAM with `s3:GetObject`, `s3:PutObject` on prefix
- Consider S3 Transfer Acceleration for global readers

### GCS

```elixir
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.GCS)

{:ok, array} = ExZarr.open(
  path: "gs://my-bucket/dataset",
  storage: :gcs
)
```

- Goth handles authentication via application credentials
- Use `concurrency: 8` initially, increase based on quota

### Azure Blob

```elixir
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.AzureBlob)

{:ok, array} = ExZarr.create(
  shape: {5000, 5000},
  chunks: {256, 256},
  storage: :azure_blob,
  container: "zarr-data",
  prefix: "v1/dataset"
)
```

- Connection string or managed identity via Azurex
- Monitor request rate limits on storage account

## Operational Considerations

- Monitor `[:ex_zarr, :chunk, :read]` and `[:ex_zarr, :chunk, :write]` telemetry
- Set timeouts based on chunk size and network latency
- Use `ordered: false` for maximum throughput when order is not required
- Size chunks 1-8 MB for cloud storage balance between request overhead and parallelism
