defmodule ExZarr.CodecsExtendedTest do
  use ExUnit.Case
  alias ExZarr.Codecs

  describe "Compression edge cases" do
    test "compresses empty data" do
      assert {:ok, compressed} = Codecs.compress("", :zlib)
      assert {:ok, ""} = Codecs.decompress(compressed, :zlib)
    end

    test "compresses very small data" do
      data = "a"
      assert {:ok, compressed} = Codecs.compress(data, :zlib)
      assert {:ok, ^data} = Codecs.decompress(compressed, :zlib)
    end

    test "compresses large repetitive data" do
      data = String.duplicate("A", 100_000)
      assert {:ok, compressed} = Codecs.compress(data, :zlib)
      # Should compress well
      assert byte_size(compressed) < byte_size(data) / 10
      assert {:ok, ^data} = Codecs.decompress(compressed, :zlib)
    end

    test "compresses binary data" do
      data = :crypto.strong_rand_bytes(1000)
      assert {:ok, compressed} = Codecs.compress(data, :zlib)
      assert {:ok, ^data} = Codecs.decompress(compressed, :zlib)
    end

    test "compresses data with special characters" do
      data = "Hello\n\t\r\0World! 🚀"
      assert {:ok, compressed} = Codecs.compress(data, :zlib)
      assert {:ok, ^data} = Codecs.decompress(compressed, :zlib)
    end
  end

  describe "Unsupported codecs" do
    test "returns error for unsupported compression codec" do
      assert {:error, {:unsupported_codec, :blosc}} = Codecs.compress("data", :blosc)
    end

    test "returns error for unsupported decompression codec" do
      assert {:error, {:unsupported_codec, :blosc}} = Codecs.decompress("data", :blosc)
    end

    test "returns error for invalid codec" do
      assert {:error, {:unsupported_codec, :invalid}} = Codecs.compress("data", :invalid)
      assert {:error, {:unsupported_codec, :invalid}} = Codecs.decompress("data", :invalid)
    end
  end

  describe "ZSTD fallback" do
    test "zstd returns unsupported error" do
      # Note: zstd/lz4 show as available but return error when used
      assert {:error, {:unsupported_codec, :zstd}} = Codecs.compress("data", :zstd)
      assert {:error, {:unsupported_codec, :zstd}} = Codecs.decompress("data", :zstd)
    end
  end

  describe "LZ4 fallback" do
    test "lz4 returns unsupported error" do
      # Note: zstd/lz4 show as available but return error when used
      assert {:error, {:unsupported_codec, :lz4}} = Codecs.compress("data", :lz4)
      assert {:error, {:unsupported_codec, :lz4}} = Codecs.decompress("data", :lz4)
    end
  end

  describe "Codec availability checking" do
    test "reports zlib as available" do
      assert Codecs.codec_available?(:zlib) == true
    end

    test "reports none as available" do
      assert Codecs.codec_available?(:none) == true
    end

    test "reports zstd as listed (but not implemented)" do
      # zstd is in the list but not actually functional
      assert Codecs.codec_available?(:zstd) == true
    end

    test "reports lz4 as listed (but not implemented)" do
      # lz4 is in the list but not actually functional
      assert Codecs.codec_available?(:lz4) == true
    end

    test "reports blosc as unavailable" do
      assert Codecs.codec_available?(:blosc) == false
    end

    test "reports unknown codec as unavailable" do
      assert Codecs.codec_available?(:unknown) == false
      assert Codecs.codec_available?(:random) == false
    end
  end

  describe "Codec list completeness" do
    test "available_codecs returns non-empty list" do
      codecs = Codecs.available_codecs()
      assert length(codecs) > 0
    end

    test "available_codecs includes none and zlib" do
      codecs = Codecs.available_codecs()
      assert :none in codecs
      assert :zlib in codecs
    end

    test "available_codecs has expected length" do
      codecs = Codecs.available_codecs()
      assert length(codecs) == 4
    end
  end

  describe "Compression ratio tests" do
    test "zlib achieves good compression on repetitive data" do
      data = String.duplicate("ExZarr is awesome! ", 1000)
      {:ok, compressed} = Codecs.compress(data, :zlib)

      compression_ratio = byte_size(data) / byte_size(compressed)
      assert compression_ratio > 10
    end

    test "zlib handles incompressible data gracefully" do
      data = :crypto.strong_rand_bytes(1000)
      {:ok, compressed} = Codecs.compress(data, :zlib)

      # Random data doesn't compress well
      assert byte_size(compressed) >= byte_size(data) * 0.9
    end
  end

  describe "None codec passthrough" do
    test "none codec preserves exact data" do
      data = :crypto.strong_rand_bytes(500)
      {:ok, result} = Codecs.compress(data, :none)
      assert result == data
    end

    test "none codec identity for compress and decompress" do
      data = "Test data 123"
      {:ok, compressed} = Codecs.compress(data, :none)
      {:ok, decompressed} = Codecs.decompress(compressed, :none)
      assert data == compressed
      assert compressed == decompressed
    end
  end

  describe "ZigCodecs module" do
    alias ExZarr.Codecs.ZigCodecs

    test "zlib_compress works directly" do
      data = "Direct zlib test"
      assert {:ok, compressed} = ZigCodecs.zlib_compress(data)
      assert byte_size(compressed) > 0
    end

    test "zlib_decompress works directly" do
      data = "Direct zlib test"
      {:ok, compressed} = ZigCodecs.zlib_compress(data)
      assert {:ok, ^data} = ZigCodecs.zlib_decompress(compressed)
    end

    test "handles compression errors gracefully" do
      # zlib_decompress with invalid data should handle errors
      result = ZigCodecs.zlib_decompress("invalid compressed data")
      assert match?({:error, _}, result)
    end
  end
end
