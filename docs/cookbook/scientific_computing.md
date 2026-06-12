# Scientific Computing Patterns

## Map-Reduce over Chunks

```elixir
partial_sums =
  array
  |> ExZarr.Array.stream_chunks(concurrency: System.schedulers_online())
  |> Enum.map(fn {_idx, data} -> sum_chunk(data) end)

total = Enum.sum(partial_sums)
```

## GenStage Backpressure

When downstream processing is slower than I/O:

```elixir
{:ok, producer} = ExZarr.GenStage.start_chunk_producer(array)
{:ok, consumer} = SlowConsumer.start_link(producer: producer)
GenStage.ask(producer, 10)
```

The producer reads only what the consumer requests.
