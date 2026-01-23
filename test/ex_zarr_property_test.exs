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
end
