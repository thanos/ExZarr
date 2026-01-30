#!/usr/bin/env elixir

# ExZarr.Nx.DataLoader Example
#
# Demonstrates efficient ML training data loading with ExZarr arrays.
#
# Run with: elixir examples/nx_data_loader.exs

Mix.install([
  {:ex_zarr, path: Path.expand("..")},
  {:nx, "~> 0.7"}
])

defmodule DataLoaderExample do
  @moduledoc """
  Examples of using ExZarr.Nx.DataLoader for ML training.
  """

  alias ExZarr.Nx.DataLoader

  def run do
    IO.puts("=== ExZarr.Nx.DataLoader Example ===\n")

    example_1_basic_batching()
    example_2_shuffled_batching()
    example_3_count_batches()
    example_4_multi_epoch()

    IO.puts("\n✅ All examples completed successfully!")
  end

  defp example_1_basic_batching do
    IO.puts("Example 1: Basic Batch Streaming\n")

    # Create dataset
    {:ok, array} = create_dataset({1000, 20})

    # Load in batches
    batch_count = array
    |> DataLoader.batch_stream(32)
    |> Enum.count()

    IO.puts("Loaded dataset in #{batch_count} batches")
    IO.puts("  - Dataset: 1000 samples × 20 features")
    IO.puts("  - Batch size: 32")
    IO.puts("  - Memory efficient: only loads one batch at a time\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_2_shuffled_batching do
    IO.puts("Example 2: Shuffled Batch Streaming\n")

    {:ok, array} = create_sequential_dataset({100, 5})

    # Load with shuffling
    batches = array
    |> DataLoader.shuffled_batch_stream(10, seed: 42)
    |> Enum.to_list()

    {:ok, first_batch} = Enum.at(batches, 0)

    IO.puts("Shuffled #{length(batches)} batches")
    IO.puts("  - First batch shape: #{inspect(Nx.shape(first_batch))}")
    IO.puts("  - Samples are randomized for better training")
    IO.puts("  - Same seed = reproducible shuffling\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_3_count_batches do
    IO.puts("Example 3: Count Batches (for progress bars)\n")

    {:ok, array} = create_dataset({1000, 10})

    num_batches = DataLoader.count_batches(array, 32)
    num_batches_dropped = DataLoader.count_batches(array, 32, drop_remainder: true)

    IO.puts("Count batches for progress tracking:")
    IO.puts("  - Total batches: #{num_batches}")
    IO.puts("  - With drop_remainder: #{num_batches_dropped}")
    IO.puts("  - Useful for: progress bars, epoch tracking\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_4_multi_epoch do
    IO.puts("Example 4: Multi-Epoch Training\n")

    {:ok, array} = create_dataset({100, 10})

    IO.puts("Simulating 3 epochs of training...")

    for epoch <- 1..3 do
      batch_count = array
      |> DataLoader.shuffled_batch_stream(16, seed: epoch)
      |> Enum.count()

      IO.puts("  Epoch #{epoch}: processed #{batch_count} batches")
    end

    IO.puts("\n  - Each epoch uses different shuffle (via seed)")
    IO.puts("  - Improves model generalization\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  # Helper functions

  defp create_dataset(shape) do
    ExZarr.create(
      shape: shape,
      chunks: infer_chunks(shape),
      dtype: :float64,
      storage: :memory
    )
  end

  defp create_sequential_dataset(shape) do
    # Create array where each row has value equal to row index
    num_samples = elem(shape, 0)
    row_size = if tuple_size(shape) > 1, do: elem(shape, 1), else: 1

    tensor = for i <- 0..(num_samples - 1) do
      List.duplicate(i * 1.0, row_size)
    end
    |> List.flatten()
    |> Nx.tensor(type: {:f, 64})
    |> Nx.reshape(shape)

    ExZarr.Nx.from_tensor(tensor,
      chunks: infer_chunks(shape),
      storage: :memory
    )
  end

  defp infer_chunks(shape) do
    shape
    |> Tuple.to_list()
    |> Enum.map(fn dim -> max(1, div(dim, 2)) end)
    |> List.to_tuple()
  end
end

# Run examples
DataLoaderExample.run()
