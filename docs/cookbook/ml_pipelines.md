# Machine Learning Pipelines with ExZarr

## Streaming Tensors from Chunks

```elixir
{:ok, array} = ExZarr.open(path: "/data/training_features")

batches =
  array
  |> ExZarr.Array.stream_chunks(concurrency: 4)
  |> Stream.map(fn {_index, data} -> Nx.tensor(data, type: :f32) end)
  |> Stream.chunk_every(32)
  |> Enum.to_list()
```

## Using DataLoader

For sample-level batching with shuffle:

```elixir
{:ok, array} = ExZarr.open(path: "/data/features")

array
|> ExZarr.Nx.DataLoader.shuffled_batch_stream(64, seed: 42)
|> Enum.each(fn {:ok, batch} -> train_step(model, batch) end)
```

## Broadway Pipeline

For production training data preparation:

```elixir
defmodule MyApp.TrainingPipeline do
  use Broadway

  def start_link(array) do
    ExZarr.Broadway.start_chunk_pipeline(__MODULE__, array,
      concurrency: System.schedulers_online(),
      stream_opts: [ordered: false]
    )
  end

  @impl Broadway
  def handle_message(_processor, %{data: {_index, data}} = message, _ctx) do
    tensor = Nx.tensor(data, type: :f32) |> normalize()
    Broadway.Message.put_data(message, tensor)
  end
end
```
