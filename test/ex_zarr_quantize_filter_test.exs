defmodule ExZarr.QuantizeFilterTest do
  use ExUnit.Case

  describe "Quantize filter integration" do
    test "integration: quantize filter with float64 data" do
      # Create array with quantize filter (2 decimal digits)
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [{:quantize, [dtype: :float64, digits: 2]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write data with varying precision
      data =
        for i <- 0..99, into: <<>> do
          value = 100.0 + i * 0.123456789
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Read back
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      # Values should be quantized to 2 decimal places
      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        # Quantized value should match original rounded to 2 decimal places
        expected = Float.round(orig, 2)
        assert_in_delta read, expected, 0.01
      end)
    end

    test "integration: quantize filter with float32 data" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float32,
          filters: [{:quantize, [dtype: :float32, digits: 1]}],
          compressor: :zlib,
          storage: :memory
        )

      # Data with high precision
      data =
        for i <- 0..49, into: <<>> do
          value = 50.0 + i * 0.987654
          <<value::float-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      # Check quantization to 1 decimal place
      original_values = for <<v::float-little-32 <- data>>, do: v
      read_values = for <<v::float-little-32 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        expected = Float.round(orig, 1)
        assert_in_delta read, expected, 0.1
      end)
    end

    test "integration: quantize filter improves compression" do
      # High-precision data should compress better when quantized

      # Array with quantize filter
      {:ok, with_quantize} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :float64,
          filters: [{:quantize, [dtype: :float64, digits: 2]}],
          compressor: :zlib,
          storage: :memory
        )

      # Array without quantize
      {:ok, without_quantize} =
        ExZarr.create(
          shape: {1000},
          chunks: {1000},
          dtype: :float64,
          filters: nil,
          compressor: :zlib,
          storage: :memory
        )

      # Generate data with high precision (lots of decimal places)
      data =
        for i <- 0..999, into: <<>> do
          value = 100.0 + i * 0.123456789
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(with_quantize, data, start: {0}, stop: {1000})
      :ok = ExZarr.Array.set_slice(without_quantize, data, start: {0}, stop: {1000})

      # Read back quantized data
      {:ok, quantized_data} = ExZarr.Array.get_slice(with_quantize, start: {0}, stop: {1000})
      {:ok, original_data} = ExZarr.Array.get_slice(without_quantize, start: {0}, stop: {1000})

      # Verify quantization preserves approximate values
      quantized_values = for <<v::float-little-64 <- quantized_data>>, do: v
      original_values = for <<v::float-little-64 <- original_data>>, do: v

      Enum.zip(quantized_values, original_values)
      |> Enum.each(fn {quant, orig} ->
        # Should be close but not exact due to quantization
        assert_in_delta quant, orig, 0.01
      end)
    end

    test "integration: multiple chunks with quantize filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {500},
          chunks: {100},
          dtype: :float64,
          filters: [{:quantize, [dtype: :float64, digits: 3]}],
          compressor: :zlib,
          storage: :memory
        )

      # Write data
      data =
        for i <- 0..499, into: <<>> do
          value = i * 1.23456789
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})

      # Read full array
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {500})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        expected = Float.round(orig, 3)
        assert_in_delta read, expected, 0.001
      end)

      # Read partial slice crossing chunk boundary
      {:ok, partial} = ExZarr.Array.get_slice(array, start: {95}, stop: {105})

      expected_values =
        for i <- 95..104 do
          Float.round(i * 1.23456789, 3)
        end

      partial_values = for <<v::float-little-64 <- partial>>, do: v

      Enum.zip(expected_values, partial_values)
      |> Enum.each(fn {expected, actual} ->
        assert_in_delta actual, expected, 0.001
      end)
    end

    test "integration: quantize filter persisted to filesystem" do
      path = "/tmp/test_quantize_#{:rand.uniform(1_000_000)}"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {200},
            chunks: {50},
            dtype: :float64,
            filters: [{:quantize, [dtype: :float64, digits: 2]}],
            compressor: :zlib,
            storage: :filesystem,
            path: path
          )

        # Save metadata
        :ok = ExZarr.save(array, path: path)

        # Write data
        data =
          for i <- 0..199, into: <<>> do
            value = 10.0 + i * 0.123456
            <<value::float-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {200})

        # Reopen array
        {:ok, reopened} = ExZarr.open(path: path)

        # Verify filter metadata
        assert reopened.metadata.filters == [{:quantize, [digits: 2, dtype: :float64]}]

        # Read back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {200})

        # Verify quantization
        original_values = for <<v::float-little-64 <- data>>, do: v
        read_values = for <<v::float-little-64 <- read_data>>, do: v

        Enum.zip(original_values, read_values)
        |> Enum.each(fn {orig, read} ->
          expected = Float.round(orig, 2)
          assert_in_delta read, expected, 0.01
        end)
      after
        File.rm_rf(path)
      end
    end

    test "integration: quantize filter with high digits preserves precision" do
      # With high digits, quantization should have minimal effect
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {100},
          dtype: :float64,
          filters: [{:quantize, [dtype: :float64, digits: 10]}],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..99, into: <<>> do
          value = i * 1.23456789
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        # With 10 digits, should be very close
        assert_in_delta read, orig, 1.0e-9
      end)
    end

    test "integration: quantize filter with zero digits rounds to integers" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          filters: [{:quantize, [dtype: :float64, digits: 0]}],
          compressor: :zlib,
          storage: :memory
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 1.7 + 0.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      original_values = for <<v::float-little-64 <- data>>, do: v
      read_values = for <<v::float-little-64 <- read_data>>, do: v

      Enum.zip(original_values, read_values)
      |> Enum.each(fn {orig, read} ->
        # Should be rounded to nearest integer
        expected = Float.round(orig, 0)
        assert_in_delta read, expected, 0.5
      end)
    end
  end
end
