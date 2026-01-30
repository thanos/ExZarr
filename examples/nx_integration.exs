#!/usr/bin/env elixir

# Nx Integration Example
#
# This example demonstrates integrating ExZarr with Nx (Numerical Elixir):
# - Converting between Nx tensors and Zarr arrays
# - Using Nx for numerical computations on Zarr data
# - Efficient workflows for machine learning and scientific computing
# - Best practices for tensor/array conversion
#
# Run with: elixir examples/nx_integration.exs

Mix.install([
  {:ex_zarr, path: ".."},
  {:nx, "~> 0.7"}
])

defmodule NxIntegrationExample do
  @moduledoc """
  Demonstrates integration between ExZarr and Nx.

  Nx provides NumPy-like functionality for Elixir, making it a natural
  fit for numerical computing with Zarr arrays.
  """

  def run do
    IO.puts("=== Nx Integration Example ===\n")

    example_1_basic_conversion()
    example_2_numerical_operations()
    example_3_machine_learning_workflow()
    example_4_large_array_streaming()
    example_5_performance_comparison()

    IO.puts("\nAll examples completed.")
  end

  defp example_1_basic_conversion do
    IO.puts("Example 1: Basic Tensor <-> Array Conversion\n")

    # Create sample Nx tensor
    IO.puts("Creating Nx tensor...")
    tensor = Nx.iota({10, 10})  # 10x10 matrix with values 0-99
    IO.inspect(tensor, label: "Original tensor")

    # Convert Nx tensor to nested tuples for Zarr
    IO.puts("\nConverting Nx tensor → Zarr array...")
    zarr_data = nx_to_zarr(tensor)

    # Store in Zarr
    data_dir = "/tmp/nx_integration_basic"
    File.rm_rf!(data_dir)

    {:ok, array} = ExZarr.create(
      shape: {10, 10},
      chunks: {10, 10},
      dtype: :int64,
      storage: :filesystem,
      path: data_dir
    )

    :ok = ExZarr.Array.set_slice(array, zarr_data,
      start: {0, 0},
      stop: {10, 10}
    )
    IO.puts("Stored in Zarr array\n")

    # Read back and convert to Nx
    IO.puts("Reading from Zarr → Nx tensor...")
    {:ok, read_data} = ExZarr.Array.get_slice(array,
      start: {0, 0},
      stop: {10, 10}
    )

    restored_tensor = zarr_to_nx(read_data, {10, 10})
    IO.inspect(restored_tensor, label: "Restored tensor")

    # Verify they match
    if Nx.all(Nx.equal(tensor, restored_tensor)) |> Nx.to_number() == 1 do
      IO.puts("\nRound-trip conversion successful.")
    else
      IO.puts("\nData mismatch after round-trip")
    end

    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")
  end

  defp example_2_numerical_operations do
    IO.puts("Example 2: Numerical Operations with Nx\n")

    data_dir = "/tmp/nx_integration_ops"
    File.rm_rf!(data_dir)

    # Create array with some data
    IO.puts("Creating array with sample data...")
    {:ok, array} = ExZarr.create(
      shape: {100, 100},
      chunks: {50, 50},
      dtype: :float32,
      storage: :filesystem,
      path: data_dir
    )

    # Generate data using Nx
    IO.puts("Generating random data with Nx...")
    tensor = Nx.random_normal({100, 100}, 0.0, 1.0)  # Mean=0, std=1

    # Store in Zarr
    :ok = ExZarr.Array.set_slice(array, nx_to_zarr(tensor),
      start: {0, 0},
      stop: {100, 100}
    )
    IO.puts("Data stored\n")

    # Read and perform operations
    IO.puts("Reading data and computing statistics...")
    {:ok, data} = ExZarr.Array.get_slice(array,
      start: {0, 0},
      stop: {100, 100}
    )

    tensor = zarr_to_nx(data, {100, 100})

    # Compute statistics using Nx
    mean = Nx.mean(tensor) |> Nx.to_number()
    std = Nx.standard_deviation(tensor) |> Nx.to_number()
    min = Nx.reduce_min(tensor) |> Nx.to_number()
    max = Nx.reduce_max(tensor) |> Nx.to_number()

    IO.puts("  Mean: #{Float.round(mean, 4)}")
    IO.puts("  Std: #{Float.round(std, 4)}")
    IO.puts("  Min: #{Float.round(min, 4)}")
    IO.puts("  Max: #{Float.round(max, 4)}\n")

    # Transform data
    IO.puts("Applying transformations with Nx...")
    normalized = Nx.divide(Nx.subtract(tensor, mean), std)
    squared = Nx.pow(tensor, 2)
    summed = Nx.sum(tensor) |> Nx.to_number()

    IO.puts("  Normalized to zero mean, unit variance")
    IO.puts("  Computed element-wise square")
    IO.puts("  Sum of all elements: #{Float.round(summed, 2)}\n")

    # Store transformed data
    IO.puts("Storing normalized data back to Zarr...")
    {:ok, normalized_array} = ExZarr.create(
      shape: {100, 100},
      chunks: {50, 50},
      dtype: :float32,
      storage: :filesystem,
      path: "#{data_dir}_normalized"
    )

    :ok = ExZarr.Array.set_slice(normalized_array, nx_to_zarr(normalized),
      start: {0, 0},
      stop: {100, 100}
    )
    IO.puts("Transformed data stored\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_3_machine_learning_workflow do
    IO.puts("Example 3: Machine Learning Workflow\n")

    data_dir = "/tmp/nx_integration_ml"
    File.rm_rf!(data_dir)

    IO.puts("Simulating ML workflow with Zarr + Nx:\n")

    # Step 1: Load training data from Zarr
    IO.puts("1. Creating training dataset...")
    {:ok, features_array} = ExZarr.create(
      shape: {1000, 20},  # 1000 samples, 20 features
      chunks: {100, 20},
      dtype: :float32,
      storage: :filesystem,
      path: "#{data_dir}/features"
    )

    {:ok, labels_array} = ExZarr.create(
      shape: {1000, 1},   # 1000 labels
      chunks: {100, 1},
      dtype: :float32,
      storage: :filesystem,
      path: "#{data_dir}/labels"
    )

    # Generate synthetic data
    features = Nx.random_normal({1000, 20})
    # Labels = sum of first 3 features + noise
    labels = Nx.add(
      Nx.sum(features[[.., 0..2]], axes: [1]) |> Nx.reshape({1000, 1}),
      Nx.random_normal({1000, 1}, 0.0, 0.1)
    )

    :ok = ExZarr.Array.set_slice(features_array, nx_to_zarr(features),
      start: {0, 0}, stop: {1000, 20}
    )
    :ok = ExZarr.Array.set_slice(labels_array, nx_to_zarr(labels),
      start: {0, 0}, stop: {1000, 1}
    )
    IO.puts("   1000 training samples stored\n")

    # Step 2: Load batch for training
    IO.puts("2. Loading mini-batch (samples 0-99)...")
    {:ok, batch_features} = ExZarr.Array.get_slice(features_array,
      start: {0, 0},
      stop: {100, 20}
    )
    {:ok, batch_labels} = ExZarr.Array.get_slice(labels_array,
      start: {0, 0},
      stop: {100, 1}
    )

    X = zarr_to_nx(batch_features, {100, 20})
    y = zarr_to_nx(batch_labels, {100, 1})
    IO.puts("   Batch loaded into Nx tensors\n")

    # Step 3: Simple linear model computation
    IO.puts("3. Computing with linear model...")
    # Random weights for demonstration
    W = Nx.random_normal({20, 1})

    # Forward pass: y_pred = X @ W
    y_pred = Nx.dot(X, W)

    # Compute loss (MSE)
    loss = Nx.mean(Nx.pow(Nx.subtract(y_pred, y), 2)) |> Nx.to_number()
    IO.puts("   Mean Squared Error: #{Float.round(loss, 4)}\n")

    # Step 4: Store predictions
    IO.puts("4. Storing predictions...")
    {:ok, pred_array} = ExZarr.create(
      shape: {1000, 1},
      chunks: {100, 1},
      dtype: :float32,
      storage: :filesystem,
      path: "#{data_dir}/predictions"
    )

    :ok = ExZarr.Array.set_slice(pred_array, nx_to_zarr(y_pred),
      start: {0, 0}, stop: {100, 1}
    )
    IO.puts("   Predictions stored to Zarr\n")

    IO.puts("Benefits for ML workflows:")
    IO.puts("  Store large datasets that don't fit in memory")
    IO.puts("  Load mini-batches efficiently")
    IO.puts("  Use Nx for fast numerical computation")
    IO.puts("  Store intermediate results and predictions")
    IO.puts("  Version datasets with Zarr's metadata\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_4_large_array_streaming do
    IO.puts("Example 4: Streaming Large Arrays\n")

    data_dir = "/tmp/nx_integration_stream"
    File.rm_rf!(data_dir)

    # Create large array
    IO.puts("Creating large array (1000 × 1000)...")
    {:ok, array} = ExZarr.create(
      shape: {1000, 1000},
      chunks: {100, 100},
      dtype: :float32,
      storage: :filesystem,
      path: data_dir
    )

    # Process in chunks to avoid loading everything
    IO.puts("Processing array in chunks (10 × 10 chunks)...\n")

    chunk_stats = for i <- 0..9, j <- 0..9 do
      # Read one chunk at a time
      {:ok, chunk_data} = ExZarr.Array.get_slice(array,
        start: {i * 100, j * 100},
        stop: {(i + 1) * 100, (j + 1) * 100}
      )

      # Convert to Nx and process
      chunk_tensor = zarr_to_nx(chunk_data, {100, 100})

      # Apply operations
      chunk_tensor
      |> Nx.multiply(2.0)  # Scale by 2
      |> Nx.add(1.0)       # Add offset

      # Could write back to another array here
      # For now, just compute statistics
      mean = Nx.mean(chunk_tensor) |> Nx.to_number()

      if rem(i * 10 + j, 20) == 0 do
        IO.puts("  Processed chunk (#{i}, #{j}) - mean: #{Float.round(mean, 2)}")
      end

      mean
    end

    avg_mean = Enum.sum(chunk_stats) / length(chunk_stats)
    IO.puts("\n  Processed 100 chunks")
    IO.puts("  Average chunk mean: #{Float.round(avg_mean, 4)}\n")

    IO.puts("Streaming benefits:")
    IO.puts("  Process arrays larger than memory")
    IO.puts("  Parallel chunk processing with Task")
    IO.puts("  Memory-efficient pipelines")
    IO.puts("  Progressive computation\n")

    IO.puts(String.duplicate("-", 60) <> "\n")
  end

  defp example_5_performance_comparison do
    IO.puts("Example 5: Performance Comparison\n")

    # Small benchmark: Nx operations on Zarr data
    size = {500, 500}

    IO.puts("Benchmarking Zarr + Nx operations (#{inspect(size)})...\n")

    data_dir = "/tmp/nx_integration_perf"
    File.rm_rf!(data_dir)

    {:ok, array} = ExZarr.create(
      shape: size,
      chunks: size,
      dtype: :float32,
      storage: :memory,  # Use memory for faster I/O
      path: data_dir
    )

    # Generate data
    tensor = Nx.random_normal(size)
    :ok = ExZarr.Array.set_slice(array, nx_to_zarr(tensor),
      start: {0, 0}, stop: size
    )

    # Benchmark: Read + convert + operation
    {read_time, _} = :timer.tc(fn ->
      {:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: size)
      tensor = zarr_to_nx(data, size)
      _result = Nx.mean(tensor)
    end)

    IO.puts("  Read + Convert + Mean: #{Float.round(read_time / 1000, 2)} ms\n")

    # Compare with pure Nx operations (in-memory)
    {nx_time, _} = :timer.tc(fn ->
      _result = Nx.mean(tensor)
    end)

    IO.puts("  Pure Nx Mean (no I/O): #{Float.round(nx_time / 1000, 2)} ms\n")

    overhead = read_time / nx_time
    IO.puts("Performance insights:")
    IO.puts("  - I/O + conversion overhead: #{Float.round(overhead, 1)}x")
    IO.puts("  - Zarr is for persistence, not in-memory speed")
    IO.puts("  - Use Nx for computation, Zarr for storage")
    IO.puts("  - Consider caching frequently accessed data\n")
  end

  # Conversion helpers

  @doc """
  Convert Nx tensor to nested tuples for Zarr storage.
  """
  def nx_to_zarr(tensor) do
    tensor
    |> Nx.to_list()
    |> list_to_nested_tuple()
  end

  @doc """
  Convert Zarr nested tuples to Nx tensor.
  """
  def zarr_to_nx(zarr_data, shape) do
    zarr_data
    |> nested_tuple_to_list()
    |> Nx.tensor()
    |> Nx.reshape(shape)
  end

  # Helper: Recursively convert lists to nested tuples
  defp list_to_nested_tuple(list) when is_list(list) do
    list
    |> Enum.map(fn
      item when is_list(item) -> list_to_nested_tuple(item)
      item -> item
    end)
    |> List.to_tuple()
  end

  defp list_to_nested_tuple(other), do: other

  # Helper: Recursively convert nested tuples to flat list
  defp nested_tuple_to_list(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(fn
      item when is_tuple(item) -> nested_tuple_to_list(item)
      item -> [item]
    end)
  end

  defp nested_tuple_to_list(other), do: [other]
end

# Run the example
NxIntegrationExample.run()
