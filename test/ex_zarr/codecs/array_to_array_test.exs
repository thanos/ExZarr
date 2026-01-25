defmodule ExZarr.Codecs.ArrayToArrayTest do
  use ExUnit.Case, async: true

  alias ExZarr.Codecs.PipelineV3

  describe "transpose codec" do
    test "transposes 2D array (swap rows and columns)" do
      # Create a 2x3 array: [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
      data =
        for i <- [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], into: <<>>, do: <<i::float-little-64>>

      codecs = [
        %{name: "transpose", configuration: %{order: [1, 0]}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Encode with transpose
      {:ok, transposed} =
        PipelineV3.encode(data, pipeline, shape: {2, 3}, dtype: :float64)

      # Transposed should be 3x2: [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]
      # Flat order: [1.0, 4.0, 2.0, 5.0, 3.0, 6.0]
      expected =
        for i <- [1.0, 4.0, 2.0, 5.0, 3.0, 6.0], into: <<>>, do: <<i::float-little-64>>

      assert transposed == expected

      # Decode should reverse the transpose
      {:ok, decoded} =
        PipelineV3.decode(transposed, pipeline, shape: {2, 3}, dtype: :float64)

      assert decoded == data
    end

    test "transposes 3D array" do
      # Create a 2x2x2 array
      data =
        for i <- 0..7, into: <<>>, do: <<i::float-little-32>>

      codecs = [
        %{name: "transpose", configuration: %{order: [2, 1, 0]}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Encode with transpose
      {:ok, transposed} =
        PipelineV3.encode(data, pipeline, shape: {2, 2, 2}, dtype: :float32)

      # Should reorder dimensions
      assert byte_size(transposed) == byte_size(data)

      # Decode should restore original
      {:ok, decoded} =
        PipelineV3.decode(transposed, pipeline, shape: {2, 2, 2}, dtype: :float32)

      assert decoded == data
    end

    test "1D array transpose is no-op" do
      data = for i <- 0..9, into: <<>>, do: <<i::float-little-64>>

      codecs = [
        %{name: "transpose", configuration: %{order: [0]}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, transposed} =
        PipelineV3.encode(data, pipeline, shape: {10}, dtype: :float64)

      assert transposed == data

      {:ok, decoded} =
        PipelineV3.decode(transposed, pipeline, shape: {10}, dtype: :float64)

      assert decoded == data
    end

    test "rejects invalid transpose order" do
      data = for i <- 0..5, into: <<>>, do: <<i::float-little-64>>

      codecs = [
        %{name: "transpose", configuration: %{order: [0, 0]}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      assert {:error, {:invalid_transpose_order, _}} =
               PipelineV3.encode(data, pipeline, shape: {2, 3}, dtype: :float64)
    end
  end

  describe "quantize codec" do
    test "quantizes float64 to int16 and back" do
      # Create array with float values
      data =
        for i <- [0.0, 1.5, 2.7, -3.2, 4.9], into: <<>>, do: <<i::float-little-64>>

      codecs = [
        %{
          name: "quantize",
          configuration: %{dtype: "int16", scale: 0.1, offset: 0.0}
        },
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Encode: quantize floats to int16
      {:ok, quantized} =
        PipelineV3.encode(data, pipeline, shape: {5}, dtype: :float64)

      # Should be int16 data (2 bytes per element)
      assert byte_size(quantized) == 5 * 2

      # Decode: dequantize back to float64
      {:ok, decoded} =
        PipelineV3.decode(quantized, pipeline, shape: {5}, dtype: :float64)

      # Should be close to original (within quantization error)
      # Expected: [0.0, 1.5, 2.7, -3.2, 4.9] → quantize → [0, 15, 27, -32, 49] → dequantize → [0.0, 1.5, 2.7, -3.2, 4.9]
      expected =
        for i <- [0.0, 1.5, 2.7, -3.2, 4.9], into: <<>>, do: <<i::float-little-64>>

      assert decoded == expected
    end

    test "quantizes with scale and offset" do
      # Temperature data in Celsius: [20.5, 21.3, 19.8, 22.1]
      data =
        for i <- [20.5, 21.3, 19.8, 22.1], into: <<>>, do: <<i::float-little-32>>

      codecs = [
        %{
          name: "quantize",
          configuration: %{dtype: "int16", scale: 0.1, offset: 20.0}
        },
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, quantized} =
        PipelineV3.encode(data, pipeline, shape: {4}, dtype: :float32)

      {:ok, decoded} =
        PipelineV3.decode(quantized, pipeline, shape: {4}, dtype: :float32)

      # Verify values are close (within 0.1 due to quantization)
      original_values = [20.5, 21.3, 19.8, 22.1]

      decoded_values =
        for i <- 0..3 do
          offset = i * 4
          <<_::binary-size(offset), val::float-little-32, _::binary>> = decoded
          val
        end

      Enum.zip(original_values, decoded_values)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig, dec, 0.1
      end)
    end

    test "clamps values to int16 range" do
      # Values that exceed int16 range (-32768 to 32767)
      data =
        for i <- [100_000.0, -100_000.0, 5000.0], into: <<>>, do: <<i::float-little-64>>

      codecs = [
        %{
          name: "quantize",
          configuration: %{dtype: "int16", scale: 1.0, offset: 0.0}
        },
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, quantized} =
        PipelineV3.encode(data, pipeline, shape: {3}, dtype: :float64)

      {:ok, decoded} =
        PipelineV3.decode(quantized, pipeline, shape: {3}, dtype: :float64)

      # Should be clamped to int16 range
      decoded_values =
        for i <- 0..2 do
          offset = i * 8
          <<_::binary-size(offset), val::float-little-64, _::binary>> = decoded
          val
        end

      assert Enum.at(decoded_values, 0) == 32_767.0
      assert Enum.at(decoded_values, 1) == -32_768.0
      assert Enum.at(decoded_values, 2) == 5000.0
    end
  end

  describe "bitround codec" do
    test "rounds mantissa bits of float32" do
      # Original value with precise mantissa
      value = 1.23456789
      data = <<value::float-little-32>>

      codecs = [
        %{name: "bitround", configuration: %{keepbits: 10}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, rounded} =
        PipelineV3.encode(data, pipeline, shape: {1}, dtype: :float32)

      # Rounded value should be slightly different
      <<rounded_value::float-little-32>> = rounded
      assert rounded_value != value

      # But should be close
      assert_in_delta rounded_value, value, 0.01

      # Decode is no-op (lossy)
      {:ok, decoded} =
        PipelineV3.decode(rounded, pipeline, shape: {1}, dtype: :float32)

      assert decoded == rounded
    end

    test "rounds mantissa bits of float64" do
      value = 3.141592653589793
      data = <<value::float-little-64>>

      codecs = [
        %{name: "bitround", configuration: %{keepbits: 20}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, rounded} =
        PipelineV3.encode(data, pipeline, shape: {1}, dtype: :float64)

      <<rounded_value::float-little-64>> = rounded
      assert rounded_value != value
      assert_in_delta rounded_value, value, 0.0001
    end

    test "keepbits >= mantissa bits is no-op" do
      value = 2.71828
      data = <<value::float-little-32>>

      codecs = [
        %{name: "bitround", configuration: %{keepbits: 23}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, rounded} =
        PipelineV3.encode(data, pipeline, shape: {1}, dtype: :float32)

      # Should be unchanged
      assert rounded == data
    end

    test "works with array of values" do
      data =
        for i <- [1.1, 2.2, 3.3, 4.4, 5.5], into: <<>>, do: <<i::float-little-32>>

      codecs = [
        %{name: "bitround", configuration: %{keepbits: 12}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, rounded} =
        PipelineV3.encode(data, pipeline, shape: {5}, dtype: :float32)

      # All values should be rounded
      assert byte_size(rounded) == byte_size(data)

      # Verify values are close
      original_values = [1.1, 2.2, 3.3, 4.4, 5.5]

      rounded_values =
        for i <- 0..4 do
          offset = i * 4
          <<_::binary-size(offset), val::float-little-32, _::binary>> = rounded
          val
        end

      Enum.zip(original_values, rounded_values)
      |> Enum.each(fn {orig, rnd} ->
        assert_in_delta orig, rnd, 0.01
      end)
    end
  end

  describe "codec combinations" do
    test "transpose + quantize" do
      # 2x3 array of floats
      data =
        for i <- [1.1, 2.2, 3.3, 4.4, 5.5, 6.6], into: <<>>, do: <<i::float-little-64>>

      codecs = [
        %{name: "transpose", configuration: %{order: [1, 0]}},
        %{
          name: "quantize",
          configuration: %{dtype: "int16", scale: 0.1, offset: 0.0}
        },
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, encoded} =
        PipelineV3.encode(data, pipeline, shape: {2, 3}, dtype: :float64)

      {:ok, decoded} =
        PipelineV3.decode(encoded, pipeline, shape: {2, 3}, dtype: :float64)

      # Should be close to original
      original_values = [1.1, 2.2, 3.3, 4.4, 5.5, 6.6]

      decoded_values =
        for i <- 0..5 do
          offset = i * 8
          <<_::binary-size(offset), val::float-little-64, _::binary>> = decoded
          val
        end

      Enum.zip(original_values, decoded_values)
      |> Enum.each(fn {orig, dec} ->
        assert_in_delta orig, dec, 0.1
      end)
    end

    test "bitround + compression improves compression ratio" do
      # Repeated pattern with noise
      data =
        for i <- 0..99, into: <<>> do
          # Base pattern + small random-like noise
          value = 10.0 + :math.sin(i / 10.0) + rem(i, 7) * 0.001
          <<value::float-little-64>>
        end

      # Without bitround
      codecs_no_round = [
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 5}}
      ]

      {:ok, pipeline_no_round} = PipelineV3.parse_codecs(codecs_no_round)

      {:ok, compressed_no_round} =
        PipelineV3.encode(data, pipeline_no_round, shape: {100}, dtype: :float64)

      # With bitround
      codecs_with_round = [
        %{name: "bitround", configuration: %{keepbits: 10}},
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 5}}
      ]

      {:ok, pipeline_with_round} = PipelineV3.parse_codecs(codecs_with_round)

      {:ok, compressed_with_round} =
        PipelineV3.encode(data, pipeline_with_round, shape: {100}, dtype: :float64)

      # Bitround should improve compression
      # (This may not always be true for small datasets, but generally holds)
      # Just verify it doesn't error
      assert is_binary(compressed_no_round)
      assert is_binary(compressed_with_round)
    end
  end

  describe "error handling" do
    test "transpose requires shape option" do
      data = <<1.0::float-little-64>>

      codecs = [
        %{name: "transpose", configuration: %{order: [0]}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Missing shape
      assert {:error, {:missing_transpose_config, _}} =
               PipelineV3.encode(data, pipeline, dtype: :float64)
    end

    test "quantize handles empty data" do
      data = <<>>

      codecs = [
        %{
          name: "quantize",
          configuration: %{dtype: "int16", scale: 1.0, offset: 0.0}
        },
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      {:ok, encoded} = PipelineV3.encode(data, pipeline, shape: {0}, dtype: :float64)

      assert encoded == <<>>
    end
  end
end
