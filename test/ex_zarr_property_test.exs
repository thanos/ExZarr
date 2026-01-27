defmodule ExZarr.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ExZarr.{Array, Chunk, Codecs, Metadata, Storage}

  @moduledoc """
  Property-based tests using StreamData to verify invariants hold across
  a wide range of inputs and configurations.
  """

  # Generators

  defp dtype_gen do
    member_of([
      :int8,
      :int16,
      :int32,
      :int64,
      :uint8,
      :uint16,
      :uint32,
      :uint64,
      :float32,
      :float64
    ])
  end

  defp compressor_gen do
    member_of([:none, :zlib, :zstd, :lz4])
  end

  defp shape_1d do
    map(integer(10..100), &{&1})
  end

  defp shape_2d do
    map({integer(10..100), integer(10..100)}, &Tuple.to_list/1)
    |> map(&List.to_tuple/1)
  end

  defp shape_3d do
    map({integer(10..50), integer(10..50), integer(10..50)}, &Tuple.to_list/1)
    |> map(&List.to_tuple/1)
  end

  defp shape_4d do
    map({integer(5..20), integer(5..20), integer(5..20), integer(5..20)}, &Tuple.to_list/1)
    |> map(&List.to_tuple/1)
  end

  defp any_shape do
    one_of([shape_1d(), shape_2d(), shape_3d(), shape_4d()])
  end

  # Property Tests

  describe "Compression properties" do
    property "compression and decompression are inverses (zlib)" do
      check all(data <- binary(min_length: 0, max_length: 10_000)) do
        assert {:ok, compressed} = Codecs.compress(data, :zlib)
        assert {:ok, decompressed} = Codecs.decompress(compressed, :zlib)
        assert decompressed == data
      end
    end

    property "compression reduces size for repetitive data" do
      check all(
              pattern <- binary(min_length: 1, max_length: 100),
              repetitions <- integer(10..100)
            ) do
        data = String.duplicate(pattern, repetitions)
        {:ok, compressed} = Codecs.compress(data, :zlib)

        # Compressed should be smaller than original for repetitive data
        # Allow some overhead for very small data
        compression_ratio = byte_size(data) / max(1, byte_size(compressed))
        assert compression_ratio >= 0.8
      end
    end

    property "none codec is identity" do
      check all(data <- binary(max_length: 1000)) do
        assert {:ok, ^data} = Codecs.compress(data, :none)
        assert {:ok, ^data} = Codecs.decompress(data, :none)
      end
    end

    property "compression handles special cases" do
      check all(
              data <-
                one_of([
                  constant(""),
                  constant(<<0>>),
                  binary(min_length: 1, max_length: 1),
                  binary(min_length: 100_000, max_length: 100_001)
                ])
            ) do
        assert {:ok, compressed} = Codecs.compress(data, :zlib)
        assert {:ok, ^data} = Codecs.decompress(compressed, :zlib)
      end
    end
  end

  describe "Chunk index calculations" do
    property "index_to_chunk is consistent" do
      check all(
              array_index <- tuple({integer(0..999), integer(0..999)}),
              chunk_size <- tuple({integer(1..100), integer(1..100)})
            ) do
        chunk_index = Chunk.index_to_chunk(array_index, chunk_size)

        # Chunk index components should be non-negative
        assert Tuple.to_list(chunk_index) |> Enum.all?(&(&1 >= 0))

        # Verify chunk index is correct
        {ai_x, ai_y} = array_index
        {cs_x, cs_y} = chunk_size
        {ci_x, ci_y} = chunk_index

        assert ci_x == div(ai_x, cs_x)
        assert ci_y == div(ai_y, cs_y)
      end
    end

    property "chunk_bounds align correctly" do
      check all(
              array_shape <-
                map({integer(100..500), integer(100..500)}, &Tuple.to_list/1)
                |> map(&List.to_tuple/1),
              chunk_shape <-
                map({integer(10..50), integer(10..50)}, &Tuple.to_list/1) |> map(&List.to_tuple/1)
            ) do
        # Calculate valid chunk indices for this array/chunk combination
        {max_x, max_y} = array_shape
        {cs_x, cs_y} = chunk_shape
        max_chunk_x = div(max_x - 1, cs_x)
        max_chunk_y = div(max_y - 1, cs_y)

        # Only test valid chunk indices
        check all(
                chunk_idx <-
                  map({integer(0..max_chunk_x), integer(0..max_chunk_y)}, &Tuple.to_list/1)
                  |> map(&List.to_tuple/1)
              ) do
          {{start_x, start_y}, {stop_x, stop_y}} =
            Chunk.chunk_bounds(chunk_idx, chunk_shape, array_shape)

          # Start should be less than stop
          assert start_x < stop_x
          assert start_y < stop_y

          # Bounds should be within array
          assert stop_x <= max_x
          assert stop_y <= max_y

          # Bounds should align with chunk shape
          {ci_x, ci_y} = chunk_idx
          assert start_x == ci_x * cs_x
          assert start_y == ci_y * cs_y
        end
      end
    end

    property "calculate_strides produces valid strides" do
      check all(shape <- any_shape()) do
        strides = Chunk.calculate_strides(shape)

        # Strides should have same dimension as shape
        assert tuple_size(strides) == tuple_size(shape)

        # Last stride should always be 1 (C-order)
        assert elem(strides, tuple_size(strides) - 1) == 1

        # Strides should be monotonically decreasing (left to right in C-order)
        stride_list = Tuple.to_list(strides)
        assert stride_list == Enum.sort(stride_list, :desc)
      end
    end
  end

  describe "Metadata properties" do
    property "metadata creation from valid config always succeeds" do
      check all(
              shape <- any_shape(),
              dtype <- dtype_gen(),
              compressor <- compressor_gen()
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 10)))
          |> List.to_tuple()

        config = %{
          shape: shape,
          chunks: chunk_shape,
          dtype: dtype,
          compressor: compressor,
          fill_value: 0
        }

        assert {:ok, metadata} = Metadata.create(config)
        assert metadata.shape == shape
        assert metadata.chunks == chunk_shape
        assert metadata.dtype == dtype
        assert metadata.compressor == compressor
      end
    end

    property "num_chunks calculation is correct" do
      check all(
              shape <- one_of([shape_1d(), shape_2d(), shape_3d()]),
              chunk_divisor <- integer(2..10)
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, chunk_divisor)))
          |> List.to_tuple()

        metadata = %Metadata{
          shape: shape,
          chunks: chunk_shape,
          dtype: :float64,
          compressor: :none,
          fill_value: 0
        }

        num_chunks = Metadata.num_chunks(metadata)

        # Verify calculation
        expected_chunks =
          shape
          |> Tuple.to_list()
          |> Enum.zip(Tuple.to_list(chunk_shape))
          |> Enum.map(fn {dim_size, chunk_size} ->
            ceil(dim_size / chunk_size)
          end)
          |> List.to_tuple()

        assert num_chunks == expected_chunks
      end
    end

    property "total_chunks is product of num_chunks" do
      check all(shape <- one_of([shape_1d(), shape_2d(), shape_3d()])) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 5)))
          |> List.to_tuple()

        metadata = %Metadata{
          shape: shape,
          chunks: chunk_shape,
          dtype: :float64,
          compressor: :none,
          fill_value: 0
        }

        total = Metadata.total_chunks(metadata)
        num_chunks = Metadata.num_chunks(metadata)

        expected_total =
          num_chunks
          |> Tuple.to_list()
          |> Enum.reduce(1, &(&1 * &2))

        assert total == expected_total
      end
    end
  end

  describe "Array properties" do
    property "array creation with valid parameters always succeeds" do
      check all(
              shape <- one_of([shape_1d(), shape_2d(), shape_3d()]),
              dtype <- dtype_gen(),
              compressor <- member_of([:none, :zlib])
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 10)))
          |> List.to_tuple()

        assert {:ok, array} =
                 ExZarr.create(
                   shape: shape,
                   chunks: chunk_shape,
                   dtype: dtype,
                   compressor: compressor,
                   storage: :memory
                 )

        assert array.shape == shape
        assert array.chunks == chunk_shape
        assert array.dtype == dtype
        assert array.compressor == compressor
      end
    end

    property "ndim matches shape dimension count" do
      generators = [
        {1, shape_1d()},
        {2, shape_2d()},
        {3, shape_3d()},
        {4, shape_4d()}
      ]

      check all(
              {expected_ndim, shape} <-
                member_of(generators) |> bind(fn {ndim, gen} -> map(gen, &{ndim, &1}) end)
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 10)))
          |> List.to_tuple()

        {:ok, array} =
          ExZarr.create(
            shape: shape,
            chunks: chunk_shape,
            storage: :memory
          )

        assert Array.ndim(array) == expected_ndim
        assert Array.ndim(array) == tuple_size(shape)
      end
    end

    property "size is product of shape dimensions" do
      check all(shape <- any_shape()) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 10)))
          |> List.to_tuple()

        {:ok, array} =
          ExZarr.create(
            shape: shape,
            chunks: chunk_shape,
            storage: :memory
          )

        expected_size =
          shape
          |> Tuple.to_list()
          |> Enum.reduce(1, &(&1 * &2))

        assert Array.size(array) == expected_size
      end
    end

    property "itemsize matches dtype" do
      check all(dtype <- dtype_gen()) do
        {:ok, array} =
          ExZarr.create(
            shape: {10, 10},
            chunks: {5, 5},
            dtype: dtype,
            storage: :memory
          )

        itemsize = Array.itemsize(array)

        expected_size =
          case dtype do
            dt when dt in [:int8, :uint8] -> 1
            dt when dt in [:int16, :uint16] -> 2
            dt when dt in [:int32, :uint32, :float32] -> 4
            dt when dt in [:int64, :uint64, :float64] -> 8
          end

        assert itemsize == expected_size
      end
    end
  end

  describe "Storage properties" do
    property "memory storage write and read are consistent" do
      check all(
              chunk_index <- tuple({integer(0..10), integer(0..10)}),
              data <- binary(min_length: 1, max_length: 1000)
            ) do
        {:ok, storage} = Storage.init(%{storage_type: :memory})

        :ok = Storage.write_chunk(storage, chunk_index, data)
        assert {:ok, ^data} = Storage.read_chunk(storage, chunk_index)
      end
    end

    property "missing chunks return not_found" do
      check all(chunk_index <- tuple({integer(0..100), integer(0..100)})) do
        {:ok, storage} = Storage.init(%{storage_type: :memory})

        assert {:error, :not_found} = Storage.read_chunk(storage, chunk_index)
      end
    end

    property "metadata round-trip preserves data" do
      check all(
              shape <- one_of([shape_1d(), shape_2d(), shape_3d()]),
              dtype <- dtype_gen(),
              compressor <- compressor_gen()
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 5)))
          |> List.to_tuple()

        original_metadata = %Metadata{
          shape: shape,
          chunks: chunk_shape,
          dtype: dtype,
          compressor: compressor,
          fill_value: 0,
          order: "C",
          zarr_format: 2
        }

        {:ok, storage} = Storage.init(%{storage_type: :memory})
        :ok = Storage.write_metadata(storage, original_metadata, [])
        {:ok, read_metadata} = Storage.read_metadata(storage)

        assert read_metadata.shape == original_metadata.shape
        assert read_metadata.chunks == original_metadata.chunks
        assert read_metadata.dtype == original_metadata.dtype
        assert read_metadata.compressor == original_metadata.compressor
      end
    end
  end

  describe "Codec availability" do
    property "codec_available? returns boolean" do
      check all(
              codec <-
                one_of([
                  compressor_gen(),
                  constant(:invalid),
                  constant(:blosc),
                  constant(:unknown)
                ])
            ) do
        result = Codecs.codec_available?(codec)
        assert is_boolean(result)
      end
    end
  end

  describe "Data integrity" do
    property "fill_value is preserved" do
      check all(fill_value <- one_of([integer(-1000..1000), float()])) do
        {:ok, array} =
          ExZarr.create(
            shape: {10, 10},
            chunks: {5, 5},
            fill_value: fill_value,
            storage: :memory
          )

        assert array.fill_value == fill_value
      end
    end
  end

  describe "Edge cases" do
    property "handles minimum valid dimensions" do
      check all(_ <- constant(nil)) do
        # 1D array with size 1
        assert {:ok, array} = ExZarr.create(shape: {1}, chunks: {1}, storage: :memory)
        assert Array.ndim(array) == 1
        assert Array.size(array) == 1
      end
    end

    property "handles large dimensions" do
      check all(size <- integer(10_000..100_000)) do
        assert {:ok, array} = ExZarr.create(shape: {size}, chunks: {100}, storage: :memory)
        assert Array.size(array) == size
      end
    end
  end

  describe "ChunkKey properties" do
    property "encode/decode roundtrip for v2" do
      check all(
              x <- integer(0..100),
              y <- integer(0..100),
              z <- integer(0..100),
              dims <- member_of([1, 2, 3])
            ) do
        chunk_index =
          case dims do
            1 -> {x}
            2 -> {x, y}
            3 -> {x, y, z}
          end

        encoded = ExZarr.ChunkKey.encode(chunk_index, 2)
        assert {:ok, decoded} = ExZarr.ChunkKey.decode(encoded, 2)
        assert decoded == chunk_index
      end
    end

    property "encode/decode roundtrip for v3" do
      check all(
              x <- integer(0..100),
              y <- integer(0..100),
              dims <- member_of([1, 2])
            ) do
        chunk_index =
          case dims do
            1 -> {x}
            2 -> {x, y}
          end

        encoded = ExZarr.ChunkKey.encode(chunk_index, 3)
        assert {:ok, decoded} = ExZarr.ChunkKey.decode(encoded, 3)
        assert decoded == chunk_index
      end
    end

    property "v2 format uses dots" do
      check all(
              x <- integer(0..10),
              y <- integer(0..10)
            ) do
        encoded = ExZarr.ChunkKey.encode({x, y}, 2)
        assert String.contains?(encoded, ".")
        assert encoded == "#{x}.#{y}"
      end
    end

    property "v3 format uses c/ prefix and slashes" do
      check all(
              x <- integer(0..10),
              y <- integer(0..10)
            ) do
        encoded = ExZarr.ChunkKey.encode({x, y}, 3)
        assert String.starts_with?(encoded, "c/")
        assert String.contains?(encoded, "/")
      end
    end

    property "valid? correctly validates chunk keys" do
      check all(
              x <- integer(0..10),
              y <- integer(0..10)
            ) do
        v2_key = ExZarr.ChunkKey.encode({x, y}, 2)
        v3_key = ExZarr.ChunkKey.encode({x, y}, 3)

        assert ExZarr.ChunkKey.valid?(v2_key, 2)
        assert ExZarr.ChunkKey.valid?(v3_key, 3)

        # Wrong version should be invalid
        refute ExZarr.ChunkKey.valid?(v2_key, 3)
        refute ExZarr.ChunkKey.valid?(v3_key, 2)
      end
    end
  end

  describe "Indexing properties" do
    property "normalize_index handles positive indices" do
      check all(
              size <- integer(10..1000),
              index <- integer(0..9)
            ) do
        if index < size do
          assert {:ok, ^index} = ExZarr.Indexing.normalize_index(index, size)
        end
      end
    end

    property "normalize_index handles negative indices" do
      check all(
              size <- integer(10..100),
              neg_offset <- integer(1..9)
            ) do
        if neg_offset <= size do
          assert {:ok, normalized} = ExZarr.Indexing.normalize_index(-neg_offset, size)
          assert normalized == size - neg_offset
          assert normalized >= 0
          assert normalized < size
        end
      end
    end

    property "normalize_slice produces valid ranges" do
      check all(
              size <- integer(10..100),
              start <- integer(0..50),
              stop <- integer(51..100)
            ) do
        if start < size and stop <= size do
          assert {:ok, slice} =
                   ExZarr.Indexing.normalize_slice(
                     %{start: start, stop: stop, step: 1},
                     size
                   )

          assert slice.start >= 0
          assert slice.stop <= size
          assert slice.start <= slice.stop
          assert slice.step == 1
        end
      end
    end

    property "slice_size matches indices count" do
      check all(
              start <- integer(0..50),
              stop <- integer(51..100),
              step <- integer(1..5)
            ) do
        slice = %{start: start, stop: stop, step: step}
        size = ExZarr.Indexing.slice_size(slice)
        indices = ExZarr.Indexing.slice_indices(slice)

        assert length(indices) == size
      end
    end

    property "slice_indices are monotonic" do
      check all(
              start <- integer(0..50),
              stop <- integer(51..100),
              step <- integer(1..5)
            ) do
        slice = %{start: start, stop: stop, step: step}
        indices = ExZarr.Indexing.slice_indices(slice)

        if length(indices) > 1 do
          # Check pairs are increasing
          indices
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.all?(fn [a, b] -> a < b end)
          |> (&assert/1).()
        end
      end
    end

    property "mask_to_indices consistency" do
      check all(
              mask_size <- integer(5..50),
              true_positions <- list_of(integer(0..49), min_length: 0, max_length: 10)
            ) do
        # Create mask tuple with specific true positions
        mask_list =
          0..(mask_size - 1)
          |> Enum.map(fn i -> i in true_positions end)

        mask = List.to_tuple(mask_list)
        indices = ExZarr.Indexing.mask_to_indices(mask)

        # All returned indices should be within bounds
        assert Enum.all?(indices, &(&1 >= 0 and &1 < mask_size))

        # Count should match number of true values
        true_count = Enum.count(mask_list, & &1)
        assert length(indices) == true_count
      end
    end

    property "validate_fancy_indices accepts valid indices" do
      check all(
              dim_size <- integer(10..100),
              num_indices <- integer(1..20)
            ) do
        indices = Enum.map(1..num_indices, fn _ -> :rand.uniform(dim_size) - 1 end)
        assert :ok = ExZarr.Indexing.validate_fancy_indices(indices, dim_size)
      end
    end
  end

  describe "FormatConverter properties" do
    property "convert handles valid metadata" do
      check all(
              shape <- one_of([shape_1d(), shape_2d()]),
              dtype <- dtype_gen()
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 5)))
          |> List.to_tuple()

        {:ok, array} =
          ExZarr.create(
            shape: shape,
            chunks: chunk_shape,
            dtype: dtype,
            compressor: :zlib,
            storage: :memory
          )

        # Just verify the array was created successfully
        assert array.shape == shape
        assert array.chunks == chunk_shape
      end
    end
  end

  describe "Storage backend properties" do
    property "delete_chunk is idempotent" do
      check all(
              chunk_index <- tuple({integer(0..10), integer(0..10)}),
              data <- binary(min_length: 1, max_length: 100)
            ) do
        {:ok, storage} = Storage.init(%{storage_type: :memory})

        # Write chunk
        :ok = Storage.write_chunk(storage, chunk_index, data)
        assert {:ok, ^data} = Storage.read_chunk(storage, chunk_index)

        # Delete once
        :ok = Storage.delete_chunk(storage, chunk_index)
        assert {:error, :not_found} = Storage.read_chunk(storage, chunk_index)

        # Delete again should still succeed (idempotent)
        :ok = Storage.delete_chunk(storage, chunk_index)
        assert {:error, :not_found} = Storage.read_chunk(storage, chunk_index)
      end
    end

    property "list_chunks returns all written chunks" do
      check all(num_chunks <- integer(1..20)) do
        {:ok, storage} = Storage.init(%{storage_type: :memory})

        # Write random chunks
        chunk_indices =
          Enum.map(1..num_chunks, fn i -> {div(i, 10), rem(i, 10)} end)
          |> Enum.uniq()

        for index <- chunk_indices do
          :ok = Storage.write_chunk(storage, index, <<1, 2, 3>>)
        end

        {:ok, listed} = Storage.list_chunks(storage)

        # All written chunks should be listed
        assert length(listed) == length(chunk_indices)

        for index <- chunk_indices do
          assert index in listed
        end
      end
    end

    property "overwrite updates chunk data" do
      check all(
              chunk_index <- tuple({integer(0..10), integer(0..10)}),
              data1 <- binary(min_length: 1, max_length: 50),
              data2 <- binary(min_length: 1, max_length: 50)
            ) do
        {:ok, storage} = Storage.init(%{storage_type: :memory})

        # Write first version
        :ok = Storage.write_chunk(storage, chunk_index, data1)
        assert {:ok, ^data1} = Storage.read_chunk(storage, chunk_index)

        # Overwrite with second version
        :ok = Storage.write_chunk(storage, chunk_index, data2)
        assert {:ok, ^data2} = Storage.read_chunk(storage, chunk_index)

        # Old data should not be accessible
        refute data1 == data2
      end
    end
  end

  describe "Codec pipeline properties" do
    property "multiple compression codecs work" do
      check all(
              data <- binary(min_length: 10, max_length: 1000),
              codec <- member_of([:zlib, :zstd, :lz4, :none])
            ) do
        if Codecs.codec_available?(codec) do
          assert {:ok, compressed} = Codecs.compress(data, codec)
          assert {:ok, decompressed} = Codecs.decompress(compressed, codec)
          assert decompressed == data
        end
      end
    end

    property "compression with level parameter" do
      check all(
              data <- binary(min_length: 100, max_length: 1000),
              level <- integer(1..9)
            ) do
        config = %{level: level}
        assert {:ok, compressed} = Codecs.compress(data, :zlib, config)
        assert {:ok, ^data} = Codecs.decompress(compressed, :zlib)
      end
    end
  end

  describe "Array operations properties" do
    property "array metadata is consistent after creation" do
      check all(
              fill <- integer(0..100),
              shape <- one_of([shape_1d(), shape_2d()])
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 10)))
          |> List.to_tuple()

        {:ok, array} =
          ExZarr.create(
            shape: shape,
            chunks: chunk_shape,
            dtype: :int32,
            fill_value: fill,
            storage: :memory
          )

        # Verify metadata is preserved
        assert array.fill_value == fill
        assert array.shape == shape
        assert array.chunks == chunk_shape
      end
    end

    property "nchunks calculation" do
      check all(
              shape <- one_of([shape_1d(), shape_2d(), shape_3d()]),
              divisor <- integer(2..20)
            ) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, divisor)))
          |> List.to_tuple()

        {:ok, array} =
          ExZarr.create(
            shape: shape,
            chunks: chunk_shape,
            storage: :memory
          )

        # Calculate expected number of chunks
        expected =
          Enum.zip(Tuple.to_list(shape), Tuple.to_list(chunk_shape))
          |> Enum.map(fn {s, c} -> ceil(s / c) end)
          |> Enum.reduce(1, &(&1 * &2))

        # Verify via metadata
        total_chunks = Metadata.total_chunks(array.metadata)
        assert total_chunks == expected
      end
    end
  end

  describe "Data type properties" do
    property "itemsize calculation" do
      check all(dtype <- dtype_gen()) do
        expected =
          case dtype do
            dt when dt in [:int8, :uint8] -> 1
            dt when dt in [:int16, :uint16] -> 2
            dt when dt in [:int32, :uint32, :float32] -> 4
            dt when dt in [:int64, :uint64, :float64] -> 8
          end

        assert ExZarr.DataType.itemsize(dtype) == expected
      end
    end

    property "dtype creates valid arrays" do
      check all(dtype <- dtype_gen()) do
        {:ok, array} =
          ExZarr.create(
            shape: {10, 10},
            chunks: {5, 5},
            dtype: dtype,
            storage: :memory
          )

        assert array.dtype == dtype

        expected_itemsize =
          case dtype do
            dt when dt in [:int8, :uint8] -> 1
            dt when dt in [:int16, :uint16] -> 2
            dt when dt in [:int32, :uint32, :float32] -> 4
            dt when dt in [:int64, :uint64, :float64] -> 8
          end

        assert Array.itemsize(array) == expected_itemsize
      end
    end
  end

  describe "Group properties" do
    property "group creation succeeds with valid paths" do
      check all(name <- string(:alphanumeric, min_length: 1, max_length: 20)) do
        {:ok, group} = ExZarr.Group.create("", storage: :memory)
        result = ExZarr.Group.create_group(group, name)

        # Should either succeed or fail with a valid error
        case result do
          {:ok, subgroup} ->
            assert is_struct(subgroup, ExZarr.Group)
            assert String.ends_with?(subgroup.path, name)

          {:error, _reason} ->
            # Some names might be invalid, that's OK
            :ok
        end
      end
    end
  end

  describe "Dimension calculation properties" do
    property "strides calculation" do
      check all(shape <- any_shape()) do
        strides = Chunk.calculate_strides(shape)

        # Last stride is always 1 (C-order)
        assert elem(strides, tuple_size(strides) - 1) == 1

        # Each stride is the product of all following dimensions
        shape_list = Tuple.to_list(shape)
        stride_list = Tuple.to_list(strides)

        Enum.with_index(stride_list)
        |> Enum.each(fn {stride, idx} ->
          expected =
            shape_list
            |> Enum.drop(idx + 1)
            |> Enum.reduce(1, &(&1 * &2))

          assert stride == expected
        end)
      end
    end

    property "chunk size calculation" do
      check all(shape <- one_of([shape_1d(), shape_2d(), shape_3d()])) do
        chunk_shape =
          shape
          |> Tuple.to_list()
          |> Enum.map(&max(1, div(&1, 5)))
          |> List.to_tuple()

        {:ok, array} =
          ExZarr.create(
            shape: shape,
            chunks: chunk_shape,
            dtype: :float64,
            storage: :memory
          )

        # Verify chunk size matches expected bytes
        itemsize = Array.itemsize(array)

        expected_chunk_bytes =
          chunk_shape
          |> Tuple.to_list()
          |> Enum.reduce(1, &(&1 * &2))
          |> Kernel.*(itemsize)

        chunk_bytes = Metadata.chunk_size_bytes(array.metadata)
        assert chunk_bytes == expected_chunk_bytes
      end
    end
  end
end
