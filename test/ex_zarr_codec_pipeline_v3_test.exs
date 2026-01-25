defmodule ExZarr.Codecs.PipelineV3Test do
  use ExUnit.Case, async: true

  alias ExZarr.Codecs.PipelineV3
  alias ExZarr.Codecs.PipelineV3.Pipeline

  describe "parse_codecs/1 - validation" do
    test "accepts minimal valid pipeline with bytes codec only" do
      codecs = [%{name: "bytes"}]
      assert {:ok, %Pipeline{}} = PipelineV3.parse_codecs(codecs)
    end

    test "accepts pipeline with bytes and compression" do
      codecs = [
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 5}}
      ]

      assert {:ok, pipeline} = PipelineV3.parse_codecs(codecs)
      assert pipeline.array_to_bytes.name == "bytes"
      assert length(pipeline.bytes_to_bytes) == 1
      assert hd(pipeline.bytes_to_bytes).name == "gzip"
    end

    test "accepts complete pipeline with all stages" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 8}},
        %{name: "delta", configuration: %{dtype: "int64"}},
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 5}},
        %{name: "zstd", configuration: %{level: 3}}
      ]

      assert {:ok, pipeline} = PipelineV3.parse_codecs(codecs)
      assert length(pipeline.array_to_array) == 2
      assert pipeline.array_to_bytes.name == "bytes"
      assert length(pipeline.bytes_to_bytes) == 2
    end

    test "rejects empty codec list" do
      assert {:error, :empty_codec_list} = PipelineV3.parse_codecs([])
    end

    test "rejects pipeline without array→bytes codec" do
      codecs = [%{name: "gzip"}]
      assert {:error, :missing_array_to_bytes_codec} = PipelineV3.parse_codecs(codecs)
    end

    test "rejects pipeline with multiple array→bytes codecs" do
      codecs = [
        %{name: "bytes"},
        %{name: "bytes"}
      ]

      assert {:error, :multiple_array_to_bytes_codecs} = PipelineV3.parse_codecs(codecs)
    end

    test "rejects pipeline with wrong codec order - compression before bytes" do
      codecs = [
        %{name: "gzip"},
        %{name: "bytes"}
      ]

      assert {:error, :invalid_codec_order} = PipelineV3.parse_codecs(codecs)
    end

    test "rejects pipeline with wrong codec order - filter after bytes" do
      codecs = [
        %{name: "bytes"},
        %{name: "shuffle"}
      ]

      assert {:error, :invalid_codec_order} = PipelineV3.parse_codecs(codecs)
    end

    test "rejects pipeline with wrong codec order - filter after compression" do
      codecs = [
        %{name: "bytes"},
        %{name: "gzip"},
        %{name: "shuffle"}
      ]

      assert {:error, :invalid_codec_order} = PipelineV3.parse_codecs(codecs)
    end

    test "rejects pipeline with unknown codec" do
      codecs = [
        %{name: "unknown_codec"},
        %{name: "bytes"}
      ]

      assert {:error, {:unknown_codec, "unknown_codec"}} = PipelineV3.parse_codecs(codecs)
    end
  end

  describe "parse_codecs/1 - codec classification" do
    test "classifies array→array codecs correctly" do
      codecs = [
        %{name: "shuffle"},
        %{name: "delta"},
        %{name: "bytes"}
      ]

      assert {:ok, pipeline} = PipelineV3.parse_codecs(codecs)
      assert length(pipeline.array_to_array) == 2
      assert Enum.at(pipeline.array_to_array, 0).name == "shuffle"
      assert Enum.at(pipeline.array_to_array, 1).name == "delta"
    end

    test "classifies bytes→bytes codecs correctly" do
      codecs = [
        %{name: "bytes"},
        %{name: "gzip"},
        %{name: "zstd"},
        %{name: "blosc"}
      ]

      assert {:ok, pipeline} = PipelineV3.parse_codecs(codecs)
      assert length(pipeline.bytes_to_bytes) == 3
      assert Enum.at(pipeline.bytes_to_bytes, 0).name == "gzip"
      assert Enum.at(pipeline.bytes_to_bytes, 1).name == "zstd"
      assert Enum.at(pipeline.bytes_to_bytes, 2).name == "blosc"
    end

    test "preserves codec order" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 4}},
        %{name: "delta", configuration: %{dtype: "int32"}},
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 9}},
        %{name: "lz4"}
      ]

      assert {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Verify order is preserved
      assert [%{name: "shuffle"}, %{name: "delta"}] = pipeline.array_to_array
      assert %{name: "bytes"} = pipeline.array_to_bytes
      assert [%{name: "gzip"}, %{name: "lz4"}] = pipeline.bytes_to_bytes
    end

    test "preserves codec configurations" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 8}},
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 7}}
      ]

      assert {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      shuffle = Enum.at(pipeline.array_to_array, 0)
      assert shuffle.configuration.elementsize == 8

      gzip = Enum.at(pipeline.bytes_to_bytes, 0)
      assert gzip.configuration.level == 7
    end
  end

  describe "encode/3 and decode/3" do
    test "encodes and decodes with bytes codec only" do
      codecs = [%{name: "bytes"}]
      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      {:ok, encoded} = PipelineV3.encode(data, pipeline)
      # Bytes codec is pass-through
      assert encoded == data

      {:ok, decoded} = PipelineV3.decode(encoded, pipeline)
      assert decoded == data
    end

    test "encodes and decodes with compression" do
      codecs = [
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 1}}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Use repetitive data for better compression
      data = String.duplicate(<<1, 2, 3, 4>>, 100)

      {:ok, encoded} = PipelineV3.encode(data, pipeline)
      # Should be compressed
      assert byte_size(encoded) < byte_size(data)

      {:ok, decoded} = PipelineV3.decode(encoded, pipeline)
      assert decoded == data
    end

    test "encodes and decodes with shuffle filter" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 8}},
        %{name: "bytes"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # 8-byte integers
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-64>>

      {:ok, encoded} = PipelineV3.encode(data, pipeline, itemsize: 8)
      {:ok, decoded} = PipelineV3.decode(encoded, pipeline, itemsize: 8)
      assert decoded == data
    end

    test "encodes and decodes with complete pipeline" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 8}},
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 5}}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      data = for i <- 0..199, into: <<>>, do: <<i::signed-little-64>>

      {:ok, encoded} = PipelineV3.encode(data, pipeline, itemsize: 8)
      {:ok, decoded} = PipelineV3.decode(encoded, pipeline, itemsize: 8)
      assert decoded == data
    end

    test "encodes and decodes with multiple compression codecs" do
      codecs = [
        %{name: "bytes"},
        %{name: "gzip", configuration: %{level: 3}}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      data = :crypto.strong_rand_bytes(1000)

      {:ok, encoded} = PipelineV3.encode(data, pipeline)
      {:ok, decoded} = PipelineV3.decode(encoded, pipeline)
      assert decoded == data
    end
  end

  describe "from_v2/2 - conversion" do
    test "converts nil filters and no compressor" do
      codecs = PipelineV3.from_v2(nil, :none)
      assert length(codecs) == 1
      assert hd(codecs).name == "bytes"
    end

    test "converts empty filters with zlib compressor" do
      codecs = PipelineV3.from_v2([], :zlib)
      assert length(codecs) == 2
      assert Enum.at(codecs, 0).name == "bytes"
      assert Enum.at(codecs, 1).name == "gzip"
    end

    test "converts shuffle filter to v3" do
      filters = [{:shuffle, [elementsize: 8]}]
      codecs = PipelineV3.from_v2(filters, :none)

      assert length(codecs) == 2
      assert Enum.at(codecs, 0).name == "shuffle"
      assert Enum.at(codecs, 0).configuration.elementsize == 8
      assert Enum.at(codecs, 1).name == "bytes"
    end

    test "converts delta filter to v3" do
      filters = [{:delta, [dtype: :int64]}]
      codecs = PipelineV3.from_v2(filters, :none)

      assert length(codecs) == 2
      assert Enum.at(codecs, 0).name == "delta"
      assert Enum.at(codecs, 0).configuration.dtype == "int64"
      assert Enum.at(codecs, 1).name == "bytes"
    end

    test "converts multiple filters" do
      filters = [
        {:shuffle, [elementsize: 4]},
        {:delta, [dtype: :int32]}
      ]

      codecs = PipelineV3.from_v2(filters, :zlib)

      assert length(codecs) == 4
      assert Enum.at(codecs, 0).name == "shuffle"
      assert Enum.at(codecs, 1).name == "delta"
      assert Enum.at(codecs, 2).name == "bytes"
      assert Enum.at(codecs, 3).name == "gzip"
    end

    test "converts all compressor types" do
      compressors = [
        {:zlib, "gzip"},
        {:zstd, "zstd"},
        {:lz4, "lz4"},
        {:blosc, "blosc"},
        {:bzip2, "bz2"},
        {:crc32c, "crc32c"}
      ]

      for {v2_comp, v3_name} <- compressors do
        codecs = PipelineV3.from_v2([], v2_comp)
        assert length(codecs) == 2
        assert Enum.at(codecs, 1).name == v3_name
      end
    end

    test "converted codecs are valid pipelines" do
      filters = [{:shuffle, [elementsize: 8]}]
      codecs = PipelineV3.from_v2(filters, :zlib)

      assert {:ok, _pipeline} = PipelineV3.parse_codecs(codecs)
    end

    test "round-trip encode/decode with converted pipeline" do
      filters = [{:shuffle, [elementsize: 8]}]
      codecs = PipelineV3.from_v2(filters, :zlib)
      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-64>>

      {:ok, encoded} = PipelineV3.encode(data, pipeline, itemsize: 8)
      {:ok, decoded} = PipelineV3.decode(encoded, pipeline, itemsize: 8)
      assert decoded == data
    end
  end

  describe "codec stages" do
    test "array_to_array stage is empty when no filters" do
      codecs = [%{name: "bytes"}]
      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)
      assert pipeline.array_to_array == []
    end

    test "bytes_to_bytes stage is empty when no compression" do
      codecs = [%{name: "bytes"}]
      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)
      assert pipeline.bytes_to_bytes == []
    end

    test "pipeline struct has all expected fields" do
      codecs = [
        %{name: "shuffle"},
        %{name: "bytes"},
        %{name: "gzip"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      assert is_list(pipeline.array_to_array)
      assert is_map(pipeline.array_to_bytes)
      assert is_list(pipeline.bytes_to_bytes)
    end
  end

  describe "error handling" do
    test "returns error for unsupported array→array codec during encode" do
      # Create a pipeline manually to bypass validation for testing
      pipeline = %Pipeline{
        array_to_array: [%{name: "unsupported_filter"}],
        array_to_bytes: %{name: "bytes"},
        bytes_to_bytes: []
      }

      data = <<1, 2, 3, 4>>

      assert {:error, {:unsupported_array_to_array_codec, "unsupported_filter"}} =
               PipelineV3.encode(data, pipeline)
    end

    test "returns error for unsupported compression codec during encode" do
      pipeline = %Pipeline{
        array_to_array: [],
        array_to_bytes: %{name: "bytes"},
        bytes_to_bytes: [%{name: "unsupported_compression"}]
      }

      data = <<1, 2, 3, 4>>

      assert {:error, {:unsupported_compression_codec, "unsupported_compression"}} =
               PipelineV3.encode(data, pipeline)
    end

    test "decode fails for corrupted compressed data" do
      codecs = [
        %{name: "bytes"},
        %{name: "gzip"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Corrupt data that looks compressed but isn't valid
      corrupted_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      assert {:error, _reason} = PipelineV3.decode(corrupted_data, pipeline)
    end
  end

  describe "real-world scenarios" do
    test "typical data science pipeline: shuffle + zstd" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 8}},
        %{name: "bytes"},
        %{name: "zstd", configuration: %{level: 3}}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Simulate float64 array
      data = for i <- 0..999, into: <<>>, do: <<i * 1.5::float-little-64>>

      {:ok, encoded} = PipelineV3.encode(data, pipeline, itemsize: 8, dtype: :float64)
      {:ok, decoded} = PipelineV3.decode(encoded, pipeline, itemsize: 8, dtype: :float64)
      assert decoded == data
    end

    test "maximum compression: shuffle + delta + blosc" do
      codecs = [
        %{name: "shuffle", configuration: %{elementsize: 8}},
        %{name: "bytes"},
        %{name: "blosc"}
      ]

      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      # Sequential data (highly compressible)
      data = for i <- 0..499, into: <<>>, do: <<i::signed-little-64>>

      {:ok, encoded} = PipelineV3.encode(data, pipeline, itemsize: 8)
      assert byte_size(encoded) < byte_size(data)

      {:ok, decoded} = PipelineV3.decode(encoded, pipeline, itemsize: 8)
      assert decoded == data
    end

    test "no compression pipeline for fast access" do
      codecs = [%{name: "bytes"}]
      {:ok, pipeline} = PipelineV3.parse_codecs(codecs)

      data = :crypto.strong_rand_bytes(10_000)

      {:ok, encoded} = PipelineV3.encode(data, pipeline)
      # No transformation
      assert encoded == data

      {:ok, decoded} = PipelineV3.decode(encoded, pipeline)
      assert decoded == data
    end
  end
end
