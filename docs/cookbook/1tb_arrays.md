# Processing 1TB Zarr Arrays

For terabyte-scale arrays, combine streaming with Flow partitioning and
checkpointed writes.

```elixir
{:ok, array} = ExZarr.open(path: "s3://bucket/petabyte-subset")

array
|> ExZarr.Flow.chunk_flow(stages: System.schedulers_online())
|> Flow.map(&compute_partial/1)
|> Flow.reduce(fn -> %{} end, &merge_partials/2)
|> Flow.emit(:state)
|> Enum.to_list()
```

Use `write_stream/3` with checkpoints for ingestion pipelines that may restart.
See [cloud_storage_patterns.md](../cloud_storage_patterns.md) for retry guidance.
