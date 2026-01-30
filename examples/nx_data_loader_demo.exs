# Run with: mix run examples/nx_data_loader_demo.exs

alias ExZarr.Nx.DataLoader

IO.puts("=== ExZarr.Nx.DataLoader Demo ===\n")

# Create test dataset
{:ok, array} = ExZarr.create(
  shape: {1000, 20},
  chunks: {100, 20},
  dtype: :float64,
  storage: :memory
)

IO.puts("Example 1: Basic Batch Streaming")
batch_count = array
|> DataLoader.batch_stream(32)
|> Enum.count()
IO.puts("  Loaded 1000 samples in #{batch_count} batches\n")

IO.puts("Example 2: Shuffled Batching")
{:ok, seq_array} = ExZarr.Nx.from_tensor(
  Nx.iota({100, 5}, type: {:f, 64}),
  chunks: {50, 5},
  storage: :memory
)
shuffled_batches = seq_array
|> DataLoader.shuffled_batch_stream(10, seed: 42)
|> Enum.count()
IO.puts("  Shuffled #{shuffled_batches} batches\n")

IO.puts("Example 3: Count Batches")
num_batches = DataLoader.count_batches(array, 32)
IO.puts("  Dataset has #{num_batches} batches of size 32\n")

IO.puts("Example 4: Multi-Epoch Training")
for epoch <- 1..3 do
  count = array
  |> DataLoader.shuffled_batch_stream(64, seed: epoch)
  |> Enum.count()
  IO.puts("  Epoch #{epoch}: #{count} batches")
end

IO.puts("\nAll examples completed successfully!")
