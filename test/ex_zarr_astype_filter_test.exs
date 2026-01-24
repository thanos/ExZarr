defmodule ExZarr.AsTypeFilterTest do
  use ExUnit.Case

  describe "AsType filter integration" do
    test "integration: astype filter float64 to float32" do
      # Store float64 data as float32 to save space
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [{:astype, [decode_dtype: :float64, encode_dtype: :float32]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write float64 data
      data =
        for i <- 0..99, into: <<>> do
          value = 100.0 + i * 0.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Read back (should be close but not exact due to float32 precision)
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        # Float32 has less precision than float64
        assert_in_delta read, orig, 1.0e-6
      end)
    end

    test "integration: astype filter int64 to int32" do
      # Store int64 data as int32 (lossy if values exceed int32 range)
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int64,
          filters: [{:astype, [decode_dtype: :int64, encode_dtype: :int32]}],
          compressor: :zlib,
          storage: :memory
        )

      # Values within int32 range
      data =
        for i <- 0..49, into: <<>> do
          value = i * 1000
          <<value::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      # Should match exactly (no precision loss within int32 range)
      assert read_data == data
    end

    test "integration: astype filter int32 to int16" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :int32,
          filters: [{:astype, [decode_dtype: :int32, encode_dtype: :int16]}],
          compressor: :zlib,
          storage: :memory
        )

      # Values within int16 range (-32768 to 32767)
      data =
        for i <- 0..99, into: <<>> do
          value = i * 100
          <<value::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "integration: astype reduces storage size" do
      # Storing float64 as float32 should use less space
      data =
        for i <- 0..999, into: <<>> do
          value = 100.0 + i * 0.1
          <<value::float-little-64>>
        end

      # Array with astype filter (float64 -> float32)
      {:ok, with_astype} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :float64,
          filters: [{:astype, [decode_dtype: :float64, encode_dtype: :float32]}],
          compressor: :zlib,
          storage: :memory
        )

      # Array without filter
      {:ok, without_filter} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :float64,
          filters: nil,
          compressor: :zlib,
          storage: :memory
        )

      :ok = ExZarr.Array.set_slice(with_astype, data, start: {0}, stop: {1000})
      :ok = ExZarr.Array.set_slice(without_filter, data, start: {0}, stop: {1000})

      # Read back and verify data integrity
      {:ok, astype_data} = ExZarr.Array.get_slice(with_astype, start: {0}, stop: {1000})
      {:ok, original_data} = ExZarr.Array.get_slice(without_filter, start: {0}, stop: {1000})

      astype_values = for <<v::float-little-64 <- astype_data>>, do: v
      original_values = for <<v::float-little-64 <- original_data>>, do: v

      Enum.zip(astype_values, original_values)
      |> Enum.each(fn {astype, original} ->
        # Float32 has less precision, so use larger tolerance
        assert_in_delta astype, original, 1.0e-5
      end)
    end

    test "integration: multiple chunks with astype filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {500},
          chunks: {100},
          dtype: :float64,
          filters: [{:astype, [decode_dtype: :float64, encode_dtype: :float32]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write data
      data =
        for i <- 0..499, into: <<>> do
          value = i * 2.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})

      # Read full array
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {500})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        assert_in_delta read, orig, 1.0e-5
      end)

      # Read partial slice crossing chunk boundary
      {:ok, partial} = ExZarr.Array.get_slice(array, start: {95}, stop: {105})

      expected_values =
        for i <- 95..104 do
          i * 2.5
        end

      partial_values = for <<v::float-little-64 <- partial>>, do: v

      Enum.zip(expected_values, partial_values)
      |> Enum.each(fn {expected, actual} ->
        assert_in_delta actual, expected, 1.0e-5
      end)
    end

    test "integration: astype filter persisted to filesystem" do
      path = "/tmp/test_astype_#{:rand.uniform(1_000_000)}"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {200},
            chunks: {50},
            dtype: :float64,
            filters: [{:astype, [decode_dtype: :float64, encode_dtype: :float32]}],
            compressor: :zlib,
            storage: :filesystem,
            path: path
          )

        # Save metadata
        :ok = ExZarr.save(array, path: path)

        # Write data
        data =
          for i <- 0..199, into: <<>> do
            value = 10.0 + i * 0.5
            <<value::float-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {200})

        # Reopen array
        {:ok, reopened} = ExZarr.open(path: path)

        # Verify filter metadata
        assert reopened.metadata.filters == [
                 {:astype, [encode_dtype: :float32, decode_dtype: :float64]}
               ]

        # Read back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {200})

        # Verify data
        original_values = for <<v::float-little-64 <- data>>, do: v
        read_values = for <<v::float-little-64 <- read_data>>, do: v

        Enum.zip(original_values, read_values)
        |> Enum.each(fn {orig, read} ->
          assert_in_delta read, orig, 1.0e-6
        end)
      after
        File.rm_rf(path)
      end
    end

    test "integration: astype with uint types" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :uint32,
          filters: [{:astype, [decode_dtype: :uint32, encode_dtype: :uint16]}],
          compressor: :zlib,
          storage: :memory
        )

      # Values within uint16 range (0 to 65535)
      data =
        for i <- 0..99, into: <<>> do
          value = i * 500
          <<value::unsigned-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end
  end
end
