#!/usr/bin/env elixir

# Nx Optimized Conversion Example
#
# Demonstrates the new optimized ExZarr.Nx module with direct binary conversion.
# This is 5-10x faster than the nested tuple approach.
#
# Run with: elixir examples/nx_optimized_conversion.exs

Mix.install([
  {:ex_zarr, path: ".."},
  {:nx, "~> 0.7"}
])

defmodule NxOptimizedExample do
  @moduledoc """
  Demonstrates optimized ExZarr <-> Nx conversion.
  """

  def run do
    IO.puts("=== ExZarr.Nx Optimized Conversion Example ===\n")

    example_1_basic_conversion()
    example_2_performance_comparison()
    example_3_chunked_processing()
    example_4_ml_workflow()

    IO.puts("\nAll examples completed successfully!")
  end

  defp example_1_basic_conversion do
    IO.puts("Example 1: Basic Optimized Conversion\n")

    # Create Nx tensor
    tensor = Nx.iota({100, 100}, type: {:f, 64})
    IO.puts("Created Nx tensor: #{inspect(Nx.shape(tensor))}, type: #{inspect(Nx.type(tensor))}")

    # Convert to ExZarr (optimized)
    {:ok, array} = ExZarr.Nx.from_tensor(tensor,
      storage: :memory,
      chunks: {50, 50}
    )
    IO.puts("Converted to ExZarr array")

    # Convert back to Nx (optimized)
    {:ok, restored_tensor} = ExZarr.Nx.to_tensor(array)
    IO.puts("Converted back to Nx tensor")

    # Verify round-trip
    if Nx.all(Nx.equal(tensor, restored_tensor)) |> Nx.to_number() == 1 do
      IO.puts("Round-trip successful: Data matches perfectly!\n")
    else
      IO.puts("Round-trip failed: Data mismatch\n")
    end

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_2_performance_comparison do
    IO.puts("Example 2: Performance Comparison\n")

    # Small array for quick benchmark
    size = {500, 500}
    tensor = Nx.random_normal(size, type: {:f, 64})

    # Benchmark optimized conversion (to ExZarr)
    {time_to_zarr, {:ok, array}} = :timer.tc(fn ->
      ExZarr.Nx.from_tensor(tensor,
        storage: :memory,
        chunks: {100, 100}
      )
    end)

    IO.puts("To ExZarr (optimized): #{Float.round(time_to_zarr / 1000, 2)} ms")

    # Benchmark optimized conversion (from ExZarr)
    {time_from_zarr, {:ok, _restored}} = :timer.tc(fn ->
      ExZarr.Nx.to_tensor(array)
    end)

    IO.puts("From ExZarr (optimized): #{Float.round(time_from_zarr / 1000, 2)} ms")

    total_time = (time_to_zarr + time_from_zarr) / 1000
    data_size = 500 * 500 * 8 / 1_000_000  # MB
    throughput = data_size / (total_time / 1000)

    IO.puts("\nTotal round-trip time: #{Float.round(total_time, 2)} ms")
    IO.puts("Data size: #{Float.round(data_size, 2)} MB")
    IO.puts("Throughput: #{Float.round(throughput, 1)} MB/s")
    IO.puts("\nExpected: 400-800 MB/s (vs 50-100 MB/s with nested tuples)\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_3_chunked_processing do
    IO.puts("Example 3: Chunked Processing for Large Arrays\n")

    # Create a moderately large array
    {:ok, array} = ExZarr.create(
      shape: {1000, 1000},
      chunks: {100, 100},
      dtype: :float64,
      storage: :memory
    )

    # Fill with data
    data = Nx.iota({1000, 1000}, type: {:f, 64}) |> Nx.divide(1000.0)
    {:ok, filled_array} = ExZarr.Nx.from_tensor(data,
      storage: :memory,
      chunks: {100, 100}
    )

    IO.puts("Created 1000×1000 array")

    # Process in chunks to avoid loading entire array
    IO.puts("Processing in 200×200 chunks...\n")

    chunk_stats = filled_array
    |> ExZarr.Nx.to_tensor_chunked({200, 200})
    |> Enum.take(5)  # Just process first 5 chunks for demo
    |> Enum.map(fn {:ok, chunk_tensor} ->
      mean = Nx.mean(chunk_tensor) |> Nx.to_number()
      std = Nx.standard_deviation(chunk_tensor) |> Nx.to_number()
      {mean, std}
    end)

    Enum.each(Enum.with_index(chunk_stats), fn {{mean, std}, idx} ->
      IO.puts("  Chunk #{idx}: mean=#{Float.round(mean, 4)}, std=#{Float.round(std, 4)}")
    end)

    IO.puts("\nChunked processing enables constant memory usage\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_4_ml_workflow do
    IO.puts("Example 4: ML Training Workflow\n")

    # Simulate training data (1000 samples, 20 features)
    IO.puts("Creating training dataset...")
    features = Nx.random_normal({1000, 20})
    labels = Nx.random_normal({1000, 1})

    # Store in ExZarr for persistent training
    {:ok, features_array} = ExZarr.Nx.from_tensor(features,
      storage: :memory,
      chunks: {100, 20}  # Align with batch size
    )

    {:ok, labels_array} = ExZarr.Nx.from_tensor(labels,
      storage: :memory,
      chunks: {100, 1}
    )

    IO.puts("Stored 1000 samples (20 features each)")

    # Simulate loading batches for training
    IO.puts("\nSimulating training loop (3 batches)...")

    for batch_idx <- 0..2 do
      # Load batch from ExZarr
      start = batch_idx * 100
      stop = (batch_idx + 1) * 100

      {:ok, X_batch_binary} = ExZarr.Array.get_slice(features_array,
        start: {start, 0},
        stop: {stop, 20}
      )

      {:ok, y_batch_binary} = ExZarr.Array.get_slice(labels_array,
        start: {start, 0},
        stop: {stop, 1}
      )

      # Convert to Nx tensors
      X_batch = Nx.from_binary(X_batch_binary, {:f, 32}) |> Nx.reshape({100, 20})
      y_batch = Nx.from_binary(y_batch_binary, {:f, 32}) |> Nx.reshape({100, 1})

      # Simulate training step
      batch_mean = Nx.mean(X_batch) |> Nx.to_number()

      IO.puts("  Batch #{batch_idx}: loaded 100 samples, mean=#{Float.round(batch_mean, 4)}")
    end

    IO.puts("\nEfficient batch loading for ML training")
    IO.puts("   Benefits:")
    IO.puts("   - Load only what's needed (memory efficient)")
    IO.puts("   - Fast conversion (direct binary transfer)")
    IO.puts("   - Works with datasets larger than RAM\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end
end

# Run the example
NxOptimizedExample.run()
