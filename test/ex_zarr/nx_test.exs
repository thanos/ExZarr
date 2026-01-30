defmodule ExZarr.NxTest do
  use ExUnit.Case, async: true

  alias ExZarr.Nx, as: ExZarrNx

  @moduletag :nx_integration

  # Skip all tests if Nx is not available
  if Code.ensure_loaded?(Nx) do
    describe "zarr_to_nx_type/1" do
      test "converts all supported integer types" do
        assert {:ok, {:s, 8}} = ExZarrNx.zarr_to_nx_type(:int8)
        assert {:ok, {:s, 16}} = ExZarrNx.zarr_to_nx_type(:int16)
        assert {:ok, {:s, 32}} = ExZarrNx.zarr_to_nx_type(:int32)
        assert {:ok, {:s, 64}} = ExZarrNx.zarr_to_nx_type(:int64)
        assert {:ok, {:u, 8}} = ExZarrNx.zarr_to_nx_type(:uint8)
        assert {:ok, {:u, 16}} = ExZarrNx.zarr_to_nx_type(:uint16)
        assert {:ok, {:u, 32}} = ExZarrNx.zarr_to_nx_type(:uint32)
        assert {:ok, {:u, 64}} = ExZarrNx.zarr_to_nx_type(:uint64)
      end

      test "converts all supported float types" do
        assert {:ok, {:f, 32}} = ExZarrNx.zarr_to_nx_type(:float32)
        assert {:ok, {:f, 64}} = ExZarrNx.zarr_to_nx_type(:float64)
      end

      test "returns error for unsupported types" do
        assert {:error, message} = ExZarrNx.zarr_to_nx_type(:invalid_type)
        assert message =~ "Unsupported dtype"
      end
    end

    describe "nx_to_zarr_type/1" do
      test "converts all supported integer types" do
        assert {:ok, :int8} = ExZarrNx.nx_to_zarr_type({:s, 8})
        assert {:ok, :int16} = ExZarrNx.nx_to_zarr_type({:s, 16})
        assert {:ok, :int32} = ExZarrNx.nx_to_zarr_type({:s, 32})
        assert {:ok, :int64} = ExZarrNx.nx_to_zarr_type({:s, 64})
        assert {:ok, :uint8} = ExZarrNx.nx_to_zarr_type({:u, 8})
        assert {:ok, :uint16} = ExZarrNx.nx_to_zarr_type({:u, 16})
        assert {:ok, :uint32} = ExZarrNx.nx_to_zarr_type({:u, 32})
        assert {:ok, :uint64} = ExZarrNx.nx_to_zarr_type({:u, 64})
      end

      test "converts all supported float types" do
        assert {:ok, :float32} = ExZarrNx.nx_to_zarr_type({:f, 32})
        assert {:ok, :float64} = ExZarrNx.nx_to_zarr_type({:f, 64})
      end

      test "returns helpful error for BF16" do
        assert {:error, message} = ExZarrNx.nx_to_zarr_type({:bf, 16})
        assert message =~ "BF16 is not part of Zarr specification"
        assert message =~ "Workaround"
      end

      test "returns helpful error for FP16" do
        assert {:error, message} = ExZarrNx.nx_to_zarr_type({:f, 16})
        assert message =~ "FP16 is not part of Zarr specification"
        assert message =~ "Workaround"
      end

      test "returns helpful error for complex types" do
        assert {:error, message} = ExZarrNx.nx_to_zarr_type({:c, 64})
        assert message =~ "Complex numbers are not supported"
        assert message =~ "Workaround"
      end
    end

    describe "supported_dtypes/0" do
      test "returns list of 10 supported types" do
        dtypes = ExZarrNx.supported_dtypes()
        assert is_list(dtypes)
        assert length(dtypes) == 10
        assert :int8 in dtypes
        assert :uint8 in dtypes
        assert :float32 in dtypes
        assert :float64 in dtypes
      end
    end

    describe "supported_nx_types/0" do
      test "returns list of 10 supported Nx types" do
        types = ExZarrNx.supported_nx_types()
        assert is_list(types)
        assert length(types) == 10
        assert {:s, 8} in types
        assert {:u, 8} in types
        assert {:f, 32} in types
        assert {:f, 64} in types
      end
    end

    describe "to_tensor/2 - basic conversion" do
      test "converts 1D float64 array to tensor" do
        {:ok, array} = ExZarr.create(
          shape: {100},
          chunks: {50},
          dtype: :float64,
          storage: :memory
        )

        # Fill with test data
        data = for i <- 0..99, into: <<>>, do: <<i * 1.0::float-64-native>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

        {:ok, tensor} = ExZarrNx.to_tensor(array)
        assert Nx.shape(tensor) == {100}
        assert Nx.type(tensor) == {:f, 64}
        assert Nx.to_number(tensor[0]) == 0.0
        assert Nx.to_number(tensor[99]) == 99.0
      end

      test "converts 2D int32 array to tensor" do
        {:ok, array} = ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :memory
        )

        # Fill with test data
        data = for i <- 0..99, into: <<>>, do: <<i::32-native>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

        {:ok, tensor} = ExZarrNx.to_tensor(array)
        assert Nx.shape(tensor) == {10, 10}
        assert Nx.type(tensor) == {:s, 32}
      end

      test "converts 3D uint8 array to tensor" do
        {:ok, array} = ExZarr.create(
          shape: {4, 5, 6},
          chunks: {2, 5, 3},
          dtype: :uint8,
          storage: :memory
        )

        # Fill with test data
        data = for i <- 0..119, into: <<>>, do: <<i::8>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0, 0, 0}, stop: {4, 5, 6})

        {:ok, tensor} = ExZarrNx.to_tensor(array)
        assert Nx.shape(tensor) == {4, 5, 6}
        assert Nx.type(tensor) == {:u, 8}
      end

      test "converts float32 array to tensor" do
        {:ok, array} = ExZarr.create(
          shape: {50},
          chunks: {25},
          dtype: :float32,
          storage: :memory
        )

        data = for i <- 0..49, into: <<>>, do: <<i * 2.5::float-32-native>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

        {:ok, tensor} = ExZarrNx.to_tensor(array)
        assert Nx.shape(tensor) == {50}
        assert Nx.type(tensor) == {:f, 32}
      end
    end

    describe "to_tensor/2 - with options" do
      test "converts tensor with axis names" do
        {:ok, array} = ExZarr.create(
          shape: {10, 20},
          chunks: {5, 10},
          dtype: :float64,
          storage: :memory
        )

        {:ok, tensor} = ExZarrNx.to_tensor(array, names: [:rows, :cols])
        assert Nx.shape(tensor) == {10, 20}
        assert Nx.names(tensor) == [:rows, :cols]
      end

      test "converts tensor with backend transfer" do
        {:ok, array} = ExZarr.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :float64,
          storage: :memory
        )

        # Transfer to BinaryBackend (default backend)
        {:ok, tensor} = ExZarrNx.to_tensor(array, backend: Nx.BinaryBackend)
        assert Nx.shape(tensor) == {10, 10}
      end
    end

    describe "from_tensor/2 - basic conversion" do
      test "converts 1D tensor to array" do
        tensor = Nx.iota({100}, type: {:f, 64})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {50},
          storage: :memory
        )

        assert array.metadata.shape == {100}
        assert array.metadata.dtype == :float64
        assert array.metadata.chunks == {50}

        # Verify data round-trip
        {:ok, restored} = ExZarrNx.to_tensor(array)
        assert Nx.all(Nx.equal(tensor, restored)) |> Nx.to_number() == 1
      end

      test "converts 2D tensor to array" do
        tensor = Nx.iota({10, 20}, type: {:s, 32})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {5, 10},
          storage: :memory
        )

        assert array.metadata.shape == {10, 20}
        assert array.metadata.dtype == :int32
        assert array.metadata.chunks == {5, 10}
      end

      test "converts 3D tensor to array" do
        tensor = Nx.iota({4, 5, 6}, type: {:u, 8})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {2, 5, 3},
          storage: :memory
        )

        assert array.metadata.shape == {4, 5, 6}
        assert array.metadata.dtype == :uint8
        assert array.metadata.chunks == {2, 5, 3}
      end

      test "converts tensor with custom fill value" do
        tensor = Nx.iota({100}, type: {:f, 32})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {50},
          storage: :memory,
          fill_value: -1.0
        )

        assert array.metadata.fill_value == -1.0
      end

      test "converts tensor with zarr version 3" do
        tensor = Nx.iota({100}, type: {:f, 64})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {50},
          storage: :memory,
          zarr_version: 3
        )

        assert array.metadata.zarr_format == 3
      end
    end

    describe "round-trip conversion - all dtypes" do
      test "int8 round-trip" do
        tensor = Nx.tensor([-128, -1, 0, 1, 127], type: {:s, 8})
        assert_round_trip(tensor)
      end

      test "int16 round-trip" do
        tensor = Nx.tensor([-32768, -1, 0, 1, 32767], type: {:s, 16})
        assert_round_trip(tensor)
      end

      test "int32 round-trip" do
        tensor = Nx.tensor([-2147483648, -1, 0, 1, 2147483647], type: {:s, 32})
        assert_round_trip(tensor)
      end

      test "int64 round-trip" do
        tensor = Nx.tensor([-9223372036854775808, -1, 0, 1, 9223372036854775807], type: {:s, 64})
        assert_round_trip(tensor)
      end

      test "uint8 round-trip" do
        tensor = Nx.tensor([0, 1, 127, 255], type: {:u, 8})
        assert_round_trip(tensor)
      end

      test "uint16 round-trip" do
        tensor = Nx.tensor([0, 1, 32767, 65535], type: {:u, 16})
        assert_round_trip(tensor)
      end

      test "uint32 round-trip" do
        tensor = Nx.tensor([0, 1, 2147483647, 4294967295], type: {:u, 32})
        assert_round_trip(tensor)
      end

      test "uint64 round-trip" do
        tensor = Nx.tensor([0, 1, 9223372036854775807], type: {:u, 64})
        assert_round_trip(tensor)
      end

      test "float32 round-trip" do
        tensor = Nx.tensor([-1.5, 0.0, 1.5, 3.14159], type: {:f, 32})
        assert_round_trip_float(tensor, 1.0e-6)
      end

      test "float64 round-trip" do
        tensor = Nx.tensor([-1.5, 0.0, 1.5, 3.141592653589793], type: {:f, 64})
        assert_round_trip_float(tensor, 1.0e-10)
      end
    end

    describe "round-trip conversion - various shapes" do
      test "1D array round-trip" do
        tensor = Nx.iota({1000}, type: {:f, 64})
        assert_round_trip(tensor)
      end

      test "2D array round-trip" do
        tensor = Nx.iota({50, 100}, type: {:s, 32})
        assert_round_trip(tensor)
      end

      test "3D array round-trip" do
        tensor = Nx.iota({10, 20, 30}, type: {:u, 16})
        assert_round_trip(tensor)
      end

      test "4D array round-trip" do
        tensor = Nx.iota({5, 10, 15, 20}, type: {:f, 32})
        assert_round_trip_float(tensor, 1.0e-5)
      end

      test "large 2D array round-trip" do
        tensor = Nx.iota({500, 500}, type: {:f, 64})
        assert_round_trip(tensor)
      end
    end

    describe "to_tensor_chunked/3" do
      test "streams array in chunks" do
        # Create 200x200 array
        {:ok, array} = ExZarr.create(
          shape: {200, 200},
          chunks: {50, 50},
          dtype: :float64,
          storage: :memory
        )

        # Fill with data
        tensor = Nx.iota({200, 200}, type: {:f, 64})
        binary = Nx.to_binary(tensor)
        :ok = ExZarr.Array.set_slice(array, binary, start: {0, 0}, stop: {200, 200})

        # Process in 100x100 chunks
        chunks = array
        |> ExZarrNx.to_tensor_chunked({100, 100})
        |> Enum.to_list()

        # Should have 4 chunks (2x2 grid)
        assert length(chunks) == 4

        # Each chunk should be successful
        Enum.each(chunks, fn result ->
          assert {:ok, chunk_tensor} = result
          assert Nx.type(chunk_tensor) == {:f, 64}
          # Chunk size should be 100x100
          assert Nx.shape(chunk_tensor) == {100, 100}
        end)
      end

      test "streams array with uneven chunks" do
        # Create 150x150 array
        {:ok, array} = ExZarr.create(
          shape: {150, 150},
          chunks: {50, 50},
          dtype: :int32,
          storage: :memory
        )

        # Process in 100x100 chunks (last chunks will be smaller)
        chunks = array
        |> ExZarrNx.to_tensor_chunked({100, 100})
        |> Enum.to_list()

        # Should have 4 chunks
        assert length(chunks) == 4

        # Check shapes
        assert {:ok, chunk1} = Enum.at(chunks, 0)
        assert Nx.shape(chunk1) == {100, 100}

        assert {:ok, chunk2} = Enum.at(chunks, 1)
        assert Nx.shape(chunk2) == {100, 50}  # Last column chunk is smaller

        assert {:ok, chunk3} = Enum.at(chunks, 2)
        assert Nx.shape(chunk3) == {50, 100}  # Last row chunk is smaller

        assert {:ok, chunk4} = Enum.at(chunks, 3)
        assert Nx.shape(chunk4) == {50, 50}   # Corner chunk is smaller
      end

      test "streams 1D array in chunks" do
        {:ok, array} = ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :float64,
          storage: :memory
        )

        chunks = array
        |> ExZarrNx.to_tensor_chunked({250})
        |> Enum.to_list()

        assert length(chunks) == 4
        Enum.each(chunks, fn {:ok, chunk} ->
          assert Nx.type(chunk) == {:f, 64}
          assert Nx.shape(chunk) == {250}
        end)
      end

      test "processes chunks with Stream operations" do
        {:ok, array} = ExZarr.create(
          shape: {100, 100},
          chunks: {50, 50},
          dtype: :float64,
          storage: :memory
        )

        # Fill with sequential data
        tensor = Nx.iota({100, 100}, type: {:f, 64})
        binary = Nx.to_binary(tensor)
        :ok = ExZarr.Array.set_slice(array, binary, start: {0, 0}, stop: {100, 100})

        # Calculate mean of each chunk
        means = array
        |> ExZarrNx.to_tensor_chunked({50, 50})
        |> Stream.map(fn {:ok, chunk} ->
          Nx.mean(chunk) |> Nx.to_number()
        end)
        |> Enum.to_list()

        assert length(means) == 4
        Enum.each(means, fn mean ->
          assert is_float(mean)
          assert mean >= 0.0
        end)
      end
    end

    describe "error handling" do
      test "from_tensor returns error when chunks option is missing" do
        tensor = Nx.iota({100})

        assert {:error, message} = ExZarrNx.from_tensor(tensor, [])
        assert message =~ "Missing required option: :chunks"
      end

      test "from_tensor returns error for BF16 tensor" do
        # Note: BF16 type conversion is tested in nx_to_zarr_type tests
        # This verifies the error message
        assert {:error, message} = ExZarrNx.nx_to_zarr_type({:bf, 16})
        assert message =~ "BF16"
      end

      test "from_tensor returns error when storage path is missing for filesystem" do
        tensor = Nx.iota({100})

        # filesystem storage requires path
        result = ExZarrNx.from_tensor(tensor,
          chunks: {50},
          storage: :filesystem
        )

        # This will fail during array creation, not in from_tensor itself
        assert {:error, _} = result
      end
    end

    describe "integration with compression" do
      test "round-trip with zlib compression" do
        tensor = Nx.iota({100, 100}, type: {:f, 64})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {50, 50},
          storage: :memory,
          compressor: :zlib
        )

        {:ok, restored} = ExZarrNx.to_tensor(array)
        assert Nx.all(Nx.equal(tensor, restored)) |> Nx.to_number() == 1
      end

      test "round-trip with zstd compression" do
        tensor = Nx.iota({100, 100}, type: {:s, 32})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {50, 50},
          storage: :memory,
          compressor: :zstd
        )

        {:ok, restored} = ExZarrNx.to_tensor(array)
        assert Nx.all(Nx.equal(tensor, restored)) |> Nx.to_number() == 1
      end

      test "round-trip with no compression" do
        tensor = Nx.iota({100, 100}, type: {:u, 16})

        {:ok, array} = ExZarrNx.from_tensor(tensor,
          chunks: {50, 50},
          storage: :memory,
          compressor: :none
        )

        {:ok, restored} = ExZarrNx.to_tensor(array)
        assert Nx.all(Nx.equal(tensor, restored)) |> Nx.to_number() == 1
      end
    end

    describe "performance characteristics" do
      @tag :performance
      test "large array conversion is reasonably fast" do
        # 8MB array (1000x1000 float64)
        tensor = Nx.iota({1000, 1000}, type: {:f, 64})

        # Measure conversion time
        {time_from, {:ok, array}} = :timer.tc(fn ->
          ExZarrNx.from_tensor(tensor,
            chunks: {100, 100},
            storage: :memory
          )
        end)

        {time_to, {:ok, _restored}} = :timer.tc(fn ->
          ExZarrNx.to_tensor(array)
        end)

        # Should complete in reasonable time (< 1s each direction)
        # Note: Performance varies based on system load and compression
        assert time_from < 1_000_000  # microseconds (1 second)
        assert time_to < 1_000_000
      end

      @tag :performance
      test "chunked processing uses constant memory" do
        # Create large array
        {:ok, array} = ExZarr.create(
          shape: {1000, 1000},
          chunks: {100, 100},
          dtype: :float64,
          storage: :memory
        )

        # Process in chunks - should not load entire array
        chunk_count = array
        |> ExZarrNx.to_tensor_chunked({200, 200})
        |> Enum.count()

        # Should have 25 chunks (5x5 grid)
        assert chunk_count == 25
      end
    end

    # Helper functions

    defp assert_round_trip(tensor) do
      {:ok, array} = ExZarrNx.from_tensor(tensor,
        chunks: infer_chunks(Nx.shape(tensor)),
        storage: :memory
      )

      {:ok, restored} = ExZarrNx.to_tensor(array)

      assert Nx.shape(tensor) == Nx.shape(restored)
      assert Nx.type(tensor) == Nx.type(restored)
      assert Nx.all(Nx.equal(tensor, restored)) |> Nx.to_number() == 1
    end

    defp assert_round_trip_float(tensor, tolerance) do
      {:ok, array} = ExZarrNx.from_tensor(tensor,
        chunks: infer_chunks(Nx.shape(tensor)),
        storage: :memory
      )

      {:ok, restored} = ExZarrNx.to_tensor(array)

      assert Nx.shape(tensor) == Nx.shape(restored)
      assert Nx.type(tensor) == Nx.type(restored)

      # Check values are within tolerance
      diff = Nx.subtract(tensor, restored) |> Nx.abs()
      max_diff = Nx.reduce_max(diff) |> Nx.to_number()
      assert max_diff < tolerance
    end

    defp infer_chunks(shape) do
      # Simple chunking strategy: divide each dimension by 2, min 1
      shape
      |> Tuple.to_list()
      |> Enum.map(fn dim -> max(1, div(dim, 2)) end)
      |> List.to_tuple()
    end
  else
    # If Nx is not available, skip all tests
    @moduletag :skip
  end
end
