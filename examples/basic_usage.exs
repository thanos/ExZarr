# Basic ExZarr Usage Examples

# Make sure to run with: mix run examples/basic_usage.exs

IO.puts("=== ExZarr Basic Usage Examples ===\n")

# Example 1: Creating a simple 2D array
IO.puts("1. Creating a 2D array with compression:")

{:ok, array} =
  ExZarr.create(
    shape: {100, 100},
    chunks: {10, 10},
    dtype: :float64,
    compressor: :zlib
  )

IO.puts("   Created array with shape: #{inspect(array.shape)}")
IO.puts("   Chunks: #{inspect(array.chunks)}")
IO.puts("   Data type: #{array.dtype}")
IO.puts("   Compressor: #{array.compressor}")
IO.puts("   Total elements: #{ExZarr.Array.size(array)}")
IO.puts("   Dimensions: #{ExZarr.Array.ndim(array)}\n")

# Example 2: Creating arrays with different data types
IO.puts("2. Creating arrays with different data types:")

dtypes = [:int8, :int32, :float32, :float64]

for dtype <- dtypes do
  {:ok, arr} = ExZarr.create(shape: {10, 10}, chunks: {5, 5}, dtype: dtype)
  IO.puts("   #{dtype}: #{ExZarr.Array.itemsize(arr)} bytes per element")
end

IO.puts("")

# Example 3: Working with groups
IO.puts("3. Creating hierarchical groups:")

{:ok, root_group} = ExZarr.Group.create("/data")
IO.puts("   Created root group at: #{root_group.path}")

{:ok, exp_group} = ExZarr.Group.create_group(root_group, "experiments")
IO.puts("   Created subgroup at: #{exp_group.path}")

{:ok, measurements} =
  ExZarr.Group.create_array(exp_group, "measurements",
    shape: {1000},
    chunks: {100},
    dtype: :float32
  )

IO.puts("   Created array in group: measurements")
IO.puts("   Array shape: #{inspect(measurements.shape)}\n")

# Example 4: Group attributes
IO.puts("4. Setting group attributes:")

updated_group = ExZarr.Group.set_attr(root_group, "description", "Scientific data collection")
updated_group = ExZarr.Group.set_attr(updated_group, "version", "1.0")
updated_group = ExZarr.Group.set_attr(updated_group, "created_by", "ExZarr")

{:ok, description} = ExZarr.Group.get_attr(updated_group, "description")
{:ok, version} = ExZarr.Group.get_attr(updated_group, "version")

IO.puts("   Description: #{description}")
IO.puts("   Version: #{version}\n")

# Example 5: Compression codecs
IO.puts("5. Testing different compression codecs:")

test_data = "This is test data for compression!" |> String.duplicate(100)
original_size = byte_size(test_data)

IO.puts("   Original size: #{original_size} bytes")

for codec <- ExZarr.Codecs.available_codecs() do
  {:ok, compressed} = ExZarr.Codecs.compress(test_data, codec)
  compressed_size = byte_size(compressed)
  ratio = Float.round(original_size / compressed_size, 2)

  IO.puts("   #{codec}: #{compressed_size} bytes (#{ratio}x compression)")
end

IO.puts("")

# Example 6: Chunk calculations
IO.puts("6. Chunk calculations:")

chunk_index = ExZarr.Chunk.index_to_chunk({150, 250}, {100, 100})
IO.puts("   Array index (150, 250) -> Chunk index: #{inspect(chunk_index)}")

{start_idx, end_idx} = ExZarr.Chunk.chunk_bounds({1, 2}, {100, 100}, {1000, 1000})
IO.puts("   Chunk (1, 2) covers: #{inspect(start_idx)} to #{inspect(end_idx)}")

strides = ExZarr.Chunk.calculate_strides({10, 20, 30})
IO.puts("   Strides for shape (10, 20, 30): #{inspect(strides)}\n")

# Example 7: Metadata information
IO.puts("7. Array metadata:")

{:ok, large_array} =
  ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    compressor: :zstd
  )

num_chunks = ExZarr.Metadata.num_chunks(large_array.metadata)
total_chunks = ExZarr.Metadata.total_chunks(large_array.metadata)
chunk_size = ExZarr.Metadata.chunk_size_bytes(large_array.metadata)

IO.puts("   Shape: #{inspect(large_array.metadata.shape)}")
IO.puts("   Chunks per dimension: #{inspect(num_chunks)}")
IO.puts("   Total chunks: #{total_chunks}")
IO.puts("   Chunk size: #{chunk_size} bytes (#{Float.round(chunk_size / 1024, 2)} KB)\n")

IO.puts("=== Examples completed successfully! ===")
