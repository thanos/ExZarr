#!/usr/bin/env elixir

# S3 Storage Backend Example
#
# This example demonstrates how to use ExZarr with AWS S3 storage for
# cloud-based Zarr arrays. It covers:
# - Creating arrays in S3
# - Writing and reading data
# - Chunk operations
# - Error handling
# - Best practices for cloud storage
#
# Prerequisites:
# 1. Add dependencies to mix.exs:
#    {:ex_aws, "~> 2.5"},
#    {:ex_aws_s3, "~> 2.5"}
#
# 2. Configure AWS credentials (one of):
#    - Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#    - AWS credentials file: ~/.aws/credentials
#    - IAM role (when running on EC2/ECS)
#
# 3. For local testing with minio:
#    docker run -p 9000:9000 \
#      -e MINIO_ROOT_USER=minioadmin \
#      -e MINIO_ROOT_PASSWORD=minioadmin \
#      minio/minio server /data
#
#    export AWS_ACCESS_KEY_ID=minioadmin
#    export AWS_SECRET_ACCESS_KEY=minioadmin
#    export AWS_ENDPOINT_URL=http://localhost:9000
#
# Usage:
#   ./examples/s3_storage.exs

Mix.install([
  {:ex_zarr, path: Path.expand("..", __DIR__)},
  {:ex_aws, "~> 2.5"},
  {:ex_aws_s3, "~> 2.5"},
  {:hackney, "~> 1.18"}
])

defmodule S3StorageExample do
  @moduledoc """
  Comprehensive example of using ExZarr with S3 storage.
  """

  # Configuration
  @bucket "ex-zarr-examples"
  @region "us-east-1"
  @array_prefix "climate-data/temperature"

  def run do
    IO.puts("\n╔════════════════════════════════════════════════════════════╗")
    IO.puts("║        ExZarr S3 Storage Backend Example                  ║")
    IO.puts("╚════════════════════════════════════════════════════════════╝\n")

    # Register the S3 backend
    :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)
    IO.puts("✓ S3 backend registered")

    # Check if S3 is configured
    case check_s3_configuration() do
      :ok ->
        run_examples()

      {:error, reason} ->
        IO.puts("\nS3 configuration error: #{reason}")
        IO.puts("\nPlease configure AWS credentials to run this example.")
        IO.puts("See file header for configuration instructions.")
    end
  end

  defp check_s3_configuration do
    # Try to check if bucket exists
    case ExZarr.Storage.Backend.S3.exists?(bucket: @bucket, region: @region) do
      true ->
        :ok

      false ->
        # Try to create bucket
        create_bucket()
    end
  rescue
    _ -> {:error, "AWS credentials not configured or S3 service unreachable"}
  end

  defp create_bucket do
    IO.puts("\nBucket '#{@bucket}' doesn't exist. Attempting to create...")

    case ExAws.S3.put_bucket(@bucket, @region) |> ExAws.request() do
      {:ok, _} ->
        IO.puts("✓ Bucket created successfully")
        :ok

      {:error, {:http_error, 409, _}} ->
        # Bucket already exists (in another region or account)
        IO.puts("✓ Bucket exists (may be in different region)")
        :ok

      {:error, reason} ->
        {:error, "Failed to create bucket: #{inspect(reason)}"}
    end
  end

  defp run_examples do
    example_1_basic_array_creation()
    example_2_write_and_read_data()
    example_3_chunk_operations()
    example_4_multiple_arrays_with_prefixes()
    example_5_error_handling()
    example_6_performance_tips()

    IO.puts("\nAll examples completed successfully!")
    IO.puts("\nData stored in: s3://#{@bucket}/#{@array_prefix}\n")
  end

  ## Example 1: Basic Array Creation
  def example_1_basic_array_creation do
    IO.puts("\n─────────────────────────────────────────────────────")
    IO.puts("Example 1: Creating a Zarr Array in S3")
    IO.puts("─────────────────────────────────────────────────────\n")

    # Create a 2D array for storing temperature data
    # Shape: 365 days × 100 locations
    # Chunks: 31 days × 10 locations (roughly monthly chunks)
    {:ok, array} =
      ExZarr.create(
        storage: :s3,
        bucket: @bucket,
        prefix: @array_prefix,
        region: @region,
        shape: {365, 100},
        chunks: {31, 10},
        dtype: :float32,
        fill_value: -999.0
      )

    IO.puts("✓ Created array with S3 storage:")
    IO.puts("  - Shape: #{inspect(array.metadata.shape)}")
    IO.puts("  - Chunks: #{inspect(array.metadata.chunks)}")
    IO.puts("  - Dtype: #{array.metadata.dtype}")
    IO.puts("  - Location: s3://#{@bucket}/#{@array_prefix}")

    {:ok, array}
  end

  ## Example 2: Writing and Reading Data
  def example_2_write_and_read_data do
    IO.puts("\n─────────────────────────────────────────────────────")
    IO.puts("Example 2: Writing and Reading Data")
    IO.puts("─────────────────────────────────────────────────────\n")

    # Open existing array
    {:ok, array} =
      ExZarr.open(
        storage: :s3,
        bucket: @bucket,
        prefix: @array_prefix,
        region: @region
      )

    # Generate sample temperature data (first month, first 10 locations)
    # Temperatures in Celsius: 15-25 degrees
    import Nx

    temperature_data =
      Nx.add(
        Nx.multiply(Nx.random_uniform({31, 10}), 10.0),
        15.0
      )

    IO.puts("Writing temperature data (31 days × 10 locations)...")

    # Write data to array
    :ok =
      ExZarr.Array.set_slice(array, temperature_data,
        start: {0, 0},
        stop: {31, 10}
      )

    IO.puts("✓ Data written to S3")

    # Read data back
    {:ok, read_data} =
      ExZarr.Array.get_slice(array,
        start: {0, 0},
        stop: {31, 10}
      )

    IO.puts("✓ Data read from S3")
    IO.puts("  - Read shape: #{inspect(Nx.shape(read_data))}")
    IO.puts("  - Sample values: #{inspect(Nx.to_flat_list(read_data) |> Enum.take(5))}")

    # Verify data integrity
    if Nx.all_close(temperature_data, read_data) do
      IO.puts("✓ Data integrity verified - read data matches written data")
    else
      IO.puts("Warning: Data mismatch detected")
    end
  end

  ## Example 3: Chunk Operations
  def example_3_chunk_operations do
    IO.puts("\n─────────────────────────────────────────────────────")
    IO.puts("Example 3: Direct Chunk Operations")
    IO.puts("─────────────────────────────────────────────────────\n")

    {:ok, array} =
      ExZarr.open(
        storage: :s3,
        bucket: @bucket,
        prefix: @array_prefix,
        region: @region
      )

    # List all chunks that have been written
    {:ok, chunk_list} = ExZarr.Storage.list_chunks(array.storage)

    IO.puts("Chunks in S3:")

    for chunk_index <- chunk_list do
      # Read chunk metadata
      {:ok, chunk_data} = ExZarr.Storage.read_chunk(array.storage, chunk_index)
      size_kb = byte_size(chunk_data) / 1024

      IO.puts("  - Chunk #{inspect(chunk_index)}: #{Float.round(size_kb, 2)} KB")
    end

    IO.puts("\n✓ Total chunks: #{length(chunk_list)}")
  end

  ## Example 4: Multiple Arrays with Prefixes
  def example_4_multiple_arrays_with_prefixes do
    IO.puts("\n─────────────────────────────────────────────────────")
    IO.puts("Example 4: Multiple Arrays with Different Prefixes")
    IO.puts("─────────────────────────────────────────────────────\n")

    # Create temperature array
    {:ok, temp_array} =
      ExZarr.create(
        storage: :s3,
        bucket: @bucket,
        prefix: "climate-data/temperature",
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float32
      )

    IO.puts("✓ Created temperature array")

    # Create humidity array (same bucket, different prefix)
    {:ok, humidity_array} =
      ExZarr.create(
        storage: :s3,
        bucket: @bucket,
        prefix: "climate-data/humidity",
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float32
      )

    IO.puts("✓ Created humidity array")

    # Create pressure array
    {:ok, _pressure_array} =
      ExZarr.create(
        storage: :s3,
        bucket: @bucket,
        prefix: "climate-data/pressure",
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float32
      )

    IO.puts("✓ Created pressure array")

    IO.puts("\nAll arrays stored in bucket '#{@bucket}' with different prefixes:")
    IO.puts("  - s3://#{@bucket}/climate-data/temperature/")
    IO.puts("  - s3://#{@bucket}/climate-data/humidity/")
    IO.puts("  - s3://#{@bucket}/climate-data/pressure/")

    # Arrays are completely isolated by prefix
    {:ok, temp_chunks} = ExZarr.Storage.list_chunks(temp_array.storage)
    {:ok, humidity_chunks} = ExZarr.Storage.list_chunks(humidity_array.storage)

    IO.puts("\n✓ Arrays are isolated:")
    IO.puts("  - Temperature chunks: #{length(temp_chunks)}")
    IO.puts("  - Humidity chunks: #{length(humidity_chunks)}")
  end

  ## Example 5: Error Handling
  def example_5_error_handling do
    IO.puts("\n─────────────────────────────────────────────────────")
    IO.puts("Example 5: Error Handling")
    IO.puts("─────────────────────────────────────────────────────\n")

    # Try to open non-existent array
    case ExZarr.open(
           storage: :s3,
           bucket: @bucket,
           prefix: "non-existent-array",
           region: @region
         ) do
      {:ok, _array} ->
        IO.puts("Array opened")

      {:error, :not_found} ->
        IO.puts("✓ Correctly handled missing array error")

      {:error, reason} ->
        IO.puts("✓ Error: #{inspect(reason)}")
    end

    # Try to open with invalid bucket
    case ExZarr.open(
           storage: :s3,
           bucket: "this-bucket-definitely-does-not-exist-#{:rand.uniform(1_000_000)}",
           prefix: "data",
           region: @region
         ) do
      {:ok, _array} ->
        IO.puts("Array opened")

      {:error, reason} ->
        IO.puts("✓ Correctly handled invalid bucket: #{inspect(reason)}")
    end

    # Read non-existent chunk
    {:ok, array} =
      ExZarr.open(
        storage: :s3,
        bucket: @bucket,
        prefix: @array_prefix,
        region: @region
      )

    case ExZarr.Storage.read_chunk(array.storage, {999, 999}) do
      {:ok, _data} ->
        IO.puts("Chunk read")

      {:error, :not_found} ->
        IO.puts("✓ Correctly handled missing chunk")

      {:error, reason} ->
        IO.puts("✓ Error: #{inspect(reason)}")
    end

    IO.puts("\n✓ All error cases handled gracefully")
  end

  ## Example 6: Performance Tips
  def example_6_performance_tips do
    IO.puts("\n─────────────────────────────────────────────────────")
    IO.puts("Example 6: Performance Tips for S3 Storage")
    IO.puts("─────────────────────────────────────────────────────\n")

    IO.puts("Best Practices for S3 Storage:\n")

    IO.puts("1. Chunk Size:")
    IO.puts("   - Aim for 1-10 MB per chunk for optimal S3 performance")
    IO.puts("   - Too small: excessive S3 API calls and costs")
    IO.puts("   - Too large: inefficient for partial reads\n")

    IO.puts("2. Parallel Operations:")
    IO.puts("   - S3 is highly parallelizable")
    IO.puts("   - Use Task.async for concurrent chunk operations")
    IO.puts("   - Example: Read multiple chunks in parallel\n")

    # Demonstrate parallel reads
    {:ok, array} =
      ExZarr.open(
        storage: :s3,
        bucket: @bucket,
        prefix: @array_prefix,
        region: @region
      )

    chunks_to_read = [{0, 0}, {0, 1}, {0, 2}]

    IO.puts("   Reading #{length(chunks_to_read)} chunks in parallel...")
    start_time = System.monotonic_time(:millisecond)

    tasks =
      for chunk_index <- chunks_to_read do
        Task.async(fn ->
          ExZarr.Storage.read_chunk(array.storage, chunk_index)
        end)
      end

    results = Task.await_many(tasks, 10_000)
    elapsed = System.monotonic_time(:millisecond) - start_time

    successful_reads = Enum.count(results, &match?({:ok, _}, &1))
    IO.puts("   ✓ Read #{successful_reads} chunks in #{elapsed}ms\n")

    IO.puts("3. Region Selection:")
    IO.puts("   - Choose region close to compute resources")
    IO.puts("   - Use same region for bucket and EC2/Lambda\n")

    IO.puts("4. Compression:")
    IO.puts("   - Use compression to reduce storage costs and transfer time")
    IO.puts("   - Recommended: zstd for good compression/speed balance\n")

    IO.puts("5. Prefixes for Organization:")
    IO.puts("   - Use meaningful prefixes for logical grouping")
    IO.puts("   - Example: experiment-name/dataset-name/array-name")
    IO.puts("   - Makes bucket management and cleanup easier\n")

    IO.puts("6. Access Patterns:")
    IO.puts("   - S3 is optimized for reads >> writes")
    IO.puts("   - Consider write-once, read-many patterns")
    IO.puts("   - Batch writes when possible\n")

    IO.puts("7. Costs:")
    IO.puts("   - S3 charges per request (GET, PUT, LIST)")
    IO.puts("   - Larger chunks = fewer requests = lower costs")
    IO.puts("   - Consider S3 Intelligent-Tiering for infrequent access\n")
  end
end

# Run the example
S3StorageExample.run()
