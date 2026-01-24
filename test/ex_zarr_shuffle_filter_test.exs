defmodule ExZarr.ShuffleFilterTest do
  use ExUnit.Case

  describe "Shuffle filter integration" do
    test "integration: shuffle filter with int32 data" do
      # Shuffle improves compression on numeric data
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          filters: [{:shuffle, [elementsize: 4]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write sequential data
      data =
        for i <- 0..99, into: <<>> do
          <<i::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Read back - should be identical
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "integration: shuffle filter with int64 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int64,
          filters: [{:shuffle, [elementsize: 8]}],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 1000
          <<value::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      assert read_data == data
    end

    test "integration: shuffle filter with float64 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :float64,
          filters: [{:shuffle, [elementsize: 8]}],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..99, into: <<>> do
          value = 100.0 + i * 0.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "integration: shuffle improves compression on sequential data" do
      # Sequential numeric data should compress better with shuffle

      # Create identical data for both arrays
      data =
        for i <- 0..999, into: <<>> do
          <<i::signed-little-32>>
        end

      # Array with shuffle filter
      {:ok, with_shuffle} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :int32,
          filters: [{:shuffle, [elementsize: 4]}],
          compressor: :zlib,
          storage: :memory
        )

      # Array without shuffle
      {:ok, without_shuffle} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :int32,
          filters: nil,
          compressor: :zlib,
          storage: :memory
        )

      :ok = ExZarr.Array.set_slice(with_shuffle, data, start: {0}, stop: {1000})
      :ok = ExZarr.Array.set_slice(without_shuffle, data, start: {0}, stop: {1000})

      # Read back and verify data integrity
      {:ok, shuffled_data} = ExZarr.Array.get_slice(with_shuffle, start: {0}, stop: {1000})
      {:ok, unshuffled_data} = ExZarr.Array.get_slice(without_shuffle, start: {0}, stop: {1000})

      # Both should produce identical output
      assert shuffled_data == data
      assert unshuffled_data == data
      assert shuffled_data == unshuffled_data
    end

    test "integration: multiple chunks with shuffle filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {500},
          chunks: {100},
          dtype: :int32,
          filters: [{:shuffle, [elementsize: 4]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write data
      data =
        for i <- 0..499, into: <<>> do
          <<i::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})

      # Read full array
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {500})
      assert read_data == data

      # Read partial slice crossing chunk boundary
      {:ok, partial} = ExZarr.Array.get_slice(array, start: {95}, stop: {105})

      expected =
        for i <- 95..104, into: <<>> do
          <<i::signed-little-32>>
        end

      assert partial == expected
    end

    test "integration: shuffle filter persisted to filesystem" do
      path = "/tmp/test_shuffle_#{:rand.uniform(1_000_000)}"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {200},
            chunks: {50},
            dtype: :int64,
            filters: [{:shuffle, [elementsize: 8]}],
            compressor: :zlib,
            storage: :filesystem,
            path: path
          )

        # Save metadata
        :ok = ExZarr.save(array, path: path)

        # Write data
        data =
          for i <- 0..199, into: <<>> do
            <<i::signed-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {200})

        # Reopen array
        {:ok, reopened} = ExZarr.open(path: path)

        # Verify filter metadata
        assert reopened.metadata.filters == [{:shuffle, [elementsize: 8]}]

        # Read back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {200})

        assert read_data == data
      after
        File.rm_rf(path)
      end
    end

    test "integration: shuffle filter with int16 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int16,
          filters: [{:shuffle, [elementsize: 2]}],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..99, into: <<>> do
          value = i * 100
          <<value::signed-little-16>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "integration: shuffle filter with uint32 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :uint32,
          filters: [{:shuffle, [elementsize: 4]}],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 1000..1099, into: <<>> do
          <<i::unsigned-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end
  end
end
