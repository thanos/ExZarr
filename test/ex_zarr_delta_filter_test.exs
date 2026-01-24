defmodule ExZarr.DeltaFilterTest do
  use ExUnit.Case

  describe "Delta filter integration" do
    test "integration: delta filter with compression and int64 sequential data" do
      # Create array with sequential data and delta filter
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int64,
          filters: [{:delta, [dtype: :int64]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write sequential data
      data =
        for i <- 0..99, into: <<>> do
          <<i::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Read back
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "integration: multiple chunks with delta filter" do
      # Create array spanning multiple chunks
      {:ok, array} =
        ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :int32,
          filters: [{:delta, [dtype: :int32]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write sequential data
      data =
        for i <- 0..999, into: <<>> do
          <<i::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {1000})

      # Read back full array
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {1000})
      assert read_data == data

      # Read partial slice crossing chunk boundary
      {:ok, partial} = ExZarr.Array.get_slice(array, start: {90}, stop: {110})

      expected =
        for i <- 90..109, into: <<>> do
          <<i::signed-little-32>>
        end

      assert partial == expected
    end

    test "integration: delta filter with float64 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          filters: [{:delta, [dtype: :float64]}],
          compressor: :zlib,
          storage: :memory
        )

      # Slowly varying floating point data
      data =
        for i <- 0..49, into: <<>> do
          value = 100.0 + i * 0.1
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      # Float comparison with tolerance
      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        assert_in_delta orig, read, 0.0001
      end)
    end

    test "integration: delta filter with uint32 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {200},
          chunks: {50},
          dtype: :uint32,
          filters: [{:delta, [dtype: :uint32]}],
          compressor: :none,
          storage: :memory
        )

      # Sequential unsigned data
      data =
        for i <- 1000..1199, into: <<>> do
          <<i::unsigned-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {200})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {200})

      assert read_data == data
    end

    test "integration: delta filter persisted to filesystem" do
      path = "/tmp/test_delta_#{:rand.uniform(1_000_000)}"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {500},
            chunks: {100},
            dtype: :int64,
            filters: [{:delta, [dtype: :int64]}],
            compressor: :zlib,
            storage: :filesystem,
            path: path
          )

        # Save metadata to filesystem
        :ok = ExZarr.save(array, path: path)

        # Write data
        data =
          for i <- 0..499, into: <<>> do
            <<i::signed-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})

        # Reopen array
        {:ok, reopened} = ExZarr.open(path: path)

        # Read back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {500})

        assert read_data == data

        # Verify metadata contains filter
        assert reopened.metadata.filters == [{:delta, [dtype: :int64, astype: :int64]}]
      after
        File.rm_rf(path)
      end
    end

    test "integration: delta filter with compression maintains data integrity" do
      # Create two arrays: one with delta, one without
      {:ok, with_delta} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :int64,
          filters: [{:delta, [dtype: :int64]}],
          compressor: :zlib,
          storage: :memory
        )

      {:ok, without_delta} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :int64,
          filters: nil,
          compressor: :zlib,
          storage: :memory
        )

      # Write same sequential data to both
      data =
        for i <- 0..999, into: <<>> do
          <<i::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(with_delta, data, start: {0}, stop: {1000})
      :ok = ExZarr.Array.set_slice(without_delta, data, start: {0}, stop: {1000})

      # Verify both decompress correctly - delta filter should not affect data integrity
      {:ok, read_with_delta} = ExZarr.Array.get_slice(with_delta, start: {0}, stop: {1000})
      {:ok, read_without_delta} = ExZarr.Array.get_slice(without_delta, start: {0}, stop: {1000})

      assert read_with_delta == data
      assert read_without_delta == data

      # Both should produce identical output despite different compression pipelines
      assert read_with_delta == read_without_delta
    end

    test "integration: empty array with delta filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          filters: [{:delta, [dtype: :int32]}],
          compressor: :zlib,
          storage: :memory
        )

      # Read from uninitialized array (should return fill values)
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {10})

      # Should be 10 int32 zeros (fill value)
      expected =
        for _i <- 0..9, into: <<>> do
          <<0::signed-little-32>>
        end

      assert read_data == expected
    end
  end
end
