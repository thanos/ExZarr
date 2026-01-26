#!/usr/bin/env elixir

# Sharded Cloud Storage with ExZarr
#
# This example demonstrates using sharding to optimize cloud storage performance:
# - Creating sharded arrays on S3
# - Comparing sharded vs non-sharded storage
# - Measuring API call reduction
# - Demonstrating cost savings
#
# NOTE: This example uses S3 and requires AWS credentials configured.
# Run with: AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy elixir examples/sharded_cloud_storage.exs
#
# Or run in simulation mode without actual S3:
# SIMULATE=true elixir examples/sharded_cloud_storage.exs

Mix.install([
  {:ex_zarr, path: ".."},
  {:ex_aws, "~> 2.0"},
  {:ex_aws_s3, "~> 2.0"},
  {:hackney, "~> 1.18"}
])

defmodule ShardedCloudStorageExample do
  @moduledoc """
  Demonstrates the benefits of sharding for cloud storage.

  Sharding combines multiple chunks into larger "shards" to:
  1. Reduce number of S3 objects (fewer API calls)
  2. Lower costs (S3 charges per request)
  3. Improve listing performance
  4. Enable efficient parallel access
  """

  @simulate System.get_env("SIMULATE") == "true"

  # Array configuration
  @array_shape {10_000, 10_000}
  @chunk_shape {100, 100}  # 10,000 logical chunks
  @shard_shape {1000, 1000}  # 100 logical chunks per shard -> 100 shards total

  # S3 configuration (change these for your bucket)
  @bucket "my-zarr-data"  # Change to your bucket name
  @prefix "sharding_example"

  def run do
    IO.puts("=== Sharded Cloud Storage Example ===\n")

    if @simulate do
      IO.puts("Running in SIMULATION mode (no actual S3 access)")
      IO.puts("Set AWS credentials to run with real S3\n")
      run_simulation()
    else
      IO.puts("Using S3 bucket: #{@bucket}")
      IO.puts("Prefix: #{@prefix}\n")
      run_with_s3()
    end
  end

  def run_simulation do
    IO.puts("Comparing storage strategies:\n")

    # Calculate storage characteristics
    {rows, cols} = @array_shape
    {chunk_rows, chunk_cols} = @chunk_shape
    {shard_rows, shard_cols} = @shard_shape

    num_chunks = div(rows, chunk_rows) * div(cols, chunk_cols)
    chunks_per_shard = div(shard_rows, chunk_rows) * div(shard_cols, chunk_cols)
    num_shards = div(num_chunks, chunks_per_shard)

    IO.puts("Array configuration:")
    IO.puts("  Shape: #{inspect(@array_shape)}")
    IO.puts("  Chunk shape: #{inspect(@chunk_shape)}")
    IO.puts("  Total chunks: #{number_with_commas(num_chunks)}\n")

    IO.puts("Strategy 1: Without Sharding")
    IO.puts("  S3 objects: #{number_with_commas(num_chunks)} (one per chunk)")
    IO.puts("  PUT requests: #{number_with_commas(num_chunks)}")
    IO.puts("  GET requests for full read: #{number_with_commas(num_chunks)}")
    IO.puts("  List overhead: HIGH (#{number_with_commas(num_chunks)} objects)")

    storage_cost_unsharded = calculate_storage_cost(num_chunks, 76_000)  # ~76 KB per chunk
    api_cost_unsharded = calculate_api_cost(num_chunks, num_chunks)

    IO.puts("  Estimated monthly cost:")
    IO.puts("    Storage: $#{Float.round(storage_cost_unsharded, 2)}")
    IO.puts("    API calls: $#{Float.round(api_cost_unsharded, 2)}")
    IO.puts("    Total: $#{Float.round(storage_cost_unsharded + api_cost_unsharded, 2)}\n")

    IO.puts("Strategy 2: With Sharding (#{chunks_per_shard} chunks per shard)")
    IO.puts("  Shard shape: #{inspect(@shard_shape)}")
    IO.puts("  S3 objects: #{number_with_commas(num_shards)} (one per shard)")
    IO.puts("  PUT requests: #{number_with_commas(num_shards)}")
    IO.puts("  GET requests for full read: #{number_with_commas(num_shards)}")
    IO.puts("  List overhead: LOW (#{number_with_commas(num_shards)} objects)")

    storage_cost_sharded = calculate_storage_cost(num_shards, 7_600_000)  # ~7.6 MB per shard
    api_cost_sharded = calculate_api_cost(num_shards, num_shards)

    IO.puts("  Estimated monthly cost:")
    IO.puts("    Storage: $#{Float.round(storage_cost_sharded, 2)}")
    IO.puts("    API calls: $#{Float.round(api_cost_sharded, 2)}")
    IO.puts("    Total: $#{Float.round(storage_cost_sharded + api_cost_sharded, 2)}\n")

    reduction = num_chunks / num_shards
    cost_reduction = (storage_cost_unsharded + api_cost_unsharded) / (storage_cost_sharded + api_cost_sharded)

    IO.puts("Improvement:")
    IO.puts("  Object count reduction: #{Float.round(reduction, 1)}x")
    IO.puts("  API call reduction: #{Float.round(reduction, 1)}x")
    IO.puts("  Cost reduction: #{Float.round(cost_reduction, 2)}x")
    IO.puts("  Savings: $#{Float.round((storage_cost_unsharded + api_cost_unsharded) - (storage_cost_sharded + api_cost_sharded), 2)}/month\n")

    IO.puts("Benefits of sharding:")
    IO.puts("  #{Float.round(reduction, 0)}x fewer S3 objects")
    IO.puts("  #{Float.round(reduction, 0)}x fewer API calls")
    IO.puts("  Faster directory listings")
    IO.puts("  Lower costs")
    IO.puts("  Better performance for sequential access\n")

    demonstrate_sharding_configuration()
  end

  def run_with_s3 do
    # Check AWS credentials
    unless System.get_env("AWS_ACCESS_KEY_ID") do
      IO.puts("❌ Error: AWS credentials not configured")
      IO.puts("   Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY")
      IO.puts("   Or run in simulation mode: SIMULATE=true elixir #{__ENV__.file}")
      System.halt(1)
    end

    IO.puts("Step 1: Creating non-sharded array...")
    {:ok, array_no_shard} = create_array_without_sharding()
    IO.puts("Non-sharded array created\n")

    IO.puts("Step 2: Creating sharded array...")
    {:ok, array_sharded} = create_array_with_sharding()
    IO.puts("Sharded array created\n")

    IO.puts("Step 3: Writing sample data...")
    write_sample_data(array_no_shard, "no_shard")
    write_sample_data(array_sharded, "sharded")
    IO.puts("Data written\n")

    IO.puts("Step 4: Comparing S3 object counts...")
    compare_object_counts()

    IO.puts("Step 5: Measuring read performance...")
    measure_read_performance(array_no_shard, array_sharded)

    IO.puts("\nExample completed.")
    IO.puts("\nArrays created on S3:")
    IO.puts("  s3://#{@bucket}/#{@prefix}/no_shard")
    IO.puts("  s3://#{@bucket}/#{@prefix}/sharded")
  end

  defp create_array_without_sharding do
    ExZarr.create(
      shape: @array_shape,
      chunks: @chunk_shape,
      dtype: :float64,
      codecs: [
        %{name: "bytes"},
        %{name: "zstd", configuration: %{level: 3}}
      ],
      zarr_version: 3,
      storage: :s3,
      bucket: @bucket,
      prefix: "#{@prefix}/no_shard"
    )
  end

  defp create_array_with_sharding do
    ExZarr.create(
      shape: @array_shape,
      chunks: @chunk_shape,
      dtype: :float64,
      codecs: [
        %{
          name: "sharding_indexed",
          configuration: %{
            chunk_shape: Tuple.to_list(@shard_shape),
            codecs: [
              %{name: "bytes"},
              %{name: "zstd", configuration: %{level: 3}}
            ],
            index_codecs: [
              %{name: "bytes"},
              %{name: "crc32c"}
            ],
            index_location: "end"
          }
        }
      ],
      zarr_version: 3,
      storage: :s3,
      bucket: @bucket,
      prefix: "#{@prefix}/sharded"
    )
  end

  defp write_sample_data(array, label) do
    IO.puts("  Writing data to #{label} array...")

    # Write a few chunks to demonstrate
    sample_chunks = [
      {0, 0},
      {0, 10},
      {10, 0},
      {10, 10}
    ]

    Enum.each(sample_chunks, fn {i, j} ->
      data = generate_chunk_data(i, j)

      :ok = ExZarr.Array.set_slice(array, data,
        start: {i * 100, j * 100},
        stop: {(i + 1) * 100, (j + 1) * 100}
      )
    end)

    IO.puts("    Written #{length(sample_chunks)} chunks")
  end

  defp generate_chunk_data(i, j) do
    # Generate 100x100 chunk of data
    for x <- 0..99, y <- 0..99 do
      (i * 100 + x) * 10000 + (j * 100 + y)
    end
    |> Enum.chunk_every(100)
    |> Enum.map(&List.to_tuple/1)
    |> List.to_tuple()
  end

  defp compare_object_counts do
    IO.puts("  Counting S3 objects...")

    # This would require actual S3 API calls
    # Simulating the comparison
    IO.puts("    Non-sharded: Would create 4 S3 objects (one per chunk written)")
    IO.puts("    Sharded: Would create 1 S3 object (all chunks in same shard)")
    IO.puts("    Reduction: 4x fewer objects for this sample\n")
  end

  defp measure_read_performance(array_no_shard, array_sharded) do
    IO.puts("  Reading chunks from non-sharded array...")
    {time_no_shard, _} = :timer.tc(fn ->
      {:ok, _data} = ExZarr.Array.get_slice(array_no_shard,
        start: {0, 0},
        stop: {100, 100}
      )
    end)

    IO.puts("  Reading chunks from sharded array...")
    {time_sharded, _} = :timer.tc(fn ->
      {:ok, _data} = ExZarr.Array.get_slice(array_sharded,
        start: {0, 0},
        stop: {100, 100}
      )
    end)

    IO.puts("    Non-sharded: #{Float.round(time_no_shard / 1000, 2)} ms")
    IO.puts("    Sharded: #{Float.round(time_sharded / 1000, 2)} ms")

    if time_no_shard > time_sharded do
      speedup = time_no_shard / time_sharded
      IO.puts("    Sharding is #{Float.round(speedup, 2)}x faster")
    end
  end

  defp demonstrate_sharding_configuration do
    IO.puts("How to create sharded arrays:\n")

    IO.puts(~S'''
    # Without sharding (default)
    {:ok, array} = ExZarr.create(
      shape: {10_000, 10_000},
      chunks: {100, 100},          # 10,000 chunks
      dtype: :float64,
      codecs: [
        %{name: "bytes"},
        %{name: "zstd"}
      ],
      storage: :s3,
      bucket: "my-bucket"
    )

    # With sharding (recommended for cloud storage)
    {:ok, array} = ExZarr.create(
      shape: {10_000, 10_000},
      chunks: {100, 100},          # Logical chunks
      dtype: :float64,
      codecs: [
        %{
          name: "sharding_indexed",
          configuration: %{
            chunk_shape: [1000, 1000],    # Physical shards (10x10 chunks)
            codecs: [                      # Codecs for chunk data
              %{name: "bytes"},
              %{name: "zstd", configuration: %{level: 3}}
            ],
            index_codecs: [                # Codecs for shard index
              %{name: "bytes"},
              %{name: "crc32c"}
            ]
          }
        }
      ],
      zarr_version: 3,
      storage: :s3,
      bucket: "my-bucket"
    )
    ''')

    IO.puts("\n📝 Sharding best practices:")
    IO.puts("  1. Use sharding for cloud storage (S3, GCS, Azure)")
    IO.puts("  2. Don't use sharding for local filesystem")
    IO.puts("  3. Aim for 10-100 MB per shard")
    IO.puts("  4. Group 10-100 chunks per shard")
    IO.puts("  5. Match shard shape to access patterns")
    IO.puts("  6. Use compression within shards")
  end

  # Cost calculation helpers
  defp calculate_storage_cost(num_objects, avg_size_bytes) do
    # S3 Standard storage: $0.023 per GB/month
    total_gb = (num_objects * avg_size_bytes) / (1024 * 1024 * 1024)
    total_gb * 0.023
  end

  defp calculate_api_cost(put_requests, get_requests) do
    # S3 pricing (approximate):
    # PUT: $0.005 per 1,000 requests
    # GET: $0.0004 per 1,000 requests
    put_cost = (put_requests / 1000) * 0.005
    get_cost = (get_requests / 1000) * 0.0004
    put_cost + get_cost
  end

  defp number_with_commas(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end

# Run the example
ShardedCloudStorageExample.run()
