defmodule ExZarr.FixedScaleOffsetFilterTest do
  use ExUnit.Case

  describe "FixedScaleOffset filter integration" do
    test "integration: fixedscaleoffset filter with float64 to int32" do
      # Store float64 temperatures as int32 using scale/offset
      # Example: temp_celsius = -50.0 to 50.0 with 0.1 degree precision
      # Stored as: (temp - (-50)) / 0.1 = integers 0 to 1000
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [
            {:fixedscaleoffset,
             [offset: -50.0, scale: 0.1, dtype: :float64, astype: :int32]}
          ],
          compressor: :zlib,
          storage: :memory
        )

      # Write temperature data
      data =
        for i <- 0..99, into: <<>> do
          temp = -50.0 + i * 1.0
          <<temp::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Read back
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      # Values should be preserved (within rounding error due to scale)
      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        # Should match within the scale precision (0.1)
        assert_in_delta read, orig, 0.1
      end)
    end

    test "integration: fixedscaleoffset filter with float32 to int16" do
      # Store small floats as int16
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float32,
          filters: [
            {:fixedscaleoffset,
             [offset: 0.0, scale: 0.01, dtype: :float32, astype: :int16]}
          ],
          compressor: :zlib,
          storage: :memory
        )

      # Values from 0 to 100 with 0.01 precision
      data =
        for i <- 0..49, into: <<>> do
          value = i * 0.5
          <<value::float-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      original_values = for <<v::float-little-32 <- data>>, do: v
      read_values = for <<v::float-little-32 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        assert_in_delta read, orig, 0.01
      end)
    end

    test "integration: fixedscaleoffset reduces storage size" do
      # Storing float64 as int16 should use much less space

      # Create test data - temperatures with limited range
      data =
        for i <- 0..999, into: <<>> do
          temp = 20.0 + i * 0.1
          <<temp::float-little-64>>
        end

      # Array with fixedscaleoffset (float64 -> int16)
      {:ok, with_filter} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :float64,
          filters: [
            {:fixedscaleoffset,
             [offset: 20.0, scale: 0.1, dtype: :float64, astype: :int16]}
          ],
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

      :ok = ExZarr.Array.set_slice(with_filter, data, start: {0}, stop: {1000})
      :ok = ExZarr.Array.set_slice(without_filter, data, start: {0}, stop: {1000})

      # Read back and verify data integrity
      {:ok, filtered_data} = ExZarr.Array.get_slice(with_filter, start: {0}, stop: {1000})
      {:ok, unfiltered_data} = ExZarr.Array.get_slice(without_filter, start: {0}, stop: {1000})

      filtered_values = for <<v::float-little-64 <- filtered_data>>, do: v
      unfiltered_values = for <<v::float-little-64 <- unfiltered_data>>, do: v

      Enum.zip(filtered_values, unfiltered_values)
      |> Enum.each(fn {filtered, unfiltered} ->
        assert_in_delta filtered, unfiltered, 0.1
      end)
    end

    test "integration: multiple chunks with fixedscaleoffset filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {500},
          chunks: {100},
          dtype: :float64,
          filters: [
            {:fixedscaleoffset,
             [offset: 100.0, scale: 0.5, dtype: :float64, astype: :int32]}
          ],
          compressor: :zlib,
          storage: :memory
        )

      # Write data
      data =
        for i <- 0..499, into: <<>> do
          value = 100.0 + i * 2.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})

      # Read full array
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {500})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        assert_in_delta read, orig, 0.5
      end)

      # Read partial slice crossing chunk boundary
      {:ok, partial} = ExZarr.Array.get_slice(array, start: {95}, stop: {105})

      expected_values =
        for i <- 95..104 do
          100.0 + i * 2.5
        end

      partial_values = for <<v::float-little-64 <- partial>>, do: v

      Enum.zip(expected_values, partial_values)
      |> Enum.each(fn {expected, actual} ->
        assert_in_delta actual, expected, 0.5
      end)
    end

    test "integration: fixedscaleoffset filter persisted to filesystem" do
      path = "/tmp/test_fixedscaleoffset_#{:rand.uniform(1000000)}"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {200},
            chunks: {50},
            dtype: :float64,
            filters: [
              {:fixedscaleoffset,
               [offset: 0.0, scale: 1.0, dtype: :float64, astype: :int32]}
            ],
            compressor: :zlib,
            storage: :filesystem,
            path: path
          )

        # Save metadata
        :ok = ExZarr.save(array, path: path)

        # Write data
        data =
          for i <- 0..199, into: <<>> do
            value = i * 10.0
            <<value::float-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {200})

        # Reopen array
        {:ok, reopened} = ExZarr.open(path: path)

        # Verify filter metadata
        assert reopened.metadata.filters == [
                 {:fixedscaleoffset,
                  [offset: 0.0, scale: 1.0, dtype: :float64, astype: :int32]}
               ]

        # Read back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {200})

        # Verify data
        original_values = for <<v::float-little-64 <- data>>, do: v
        read_values = for <<v::float-little-64 <- read_data>>, do: v

        Enum.zip(original_values, read_values)
        |> Enum.each(fn {orig, read} ->
          assert_in_delta read, orig, 1.0
        end)
      after
        File.rm_rf(path)
      end
    end

    test "integration: fixedscaleoffset with negative offset" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [
            {:fixedscaleoffset,
             [offset: -100.0, scale: 2.0, dtype: :float64, astype: :int16]}
          ],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..99, into: <<>> do
          value = -100.0 + i * 4.0
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        assert_in_delta read, orig, 2.0
      end)
    end

    test "integration: fixedscaleoffset with fractional scale" do
      # Using very small scale for high precision
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          filters: [
            {:fixedscaleoffset,
             [offset: 0.0, scale: 0.001, dtype: :float64, astype: :int32]}
          ],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 0.1
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        # Very high precision with small scale
        assert_in_delta read, orig, 0.001
      end)
    end
  end
end
