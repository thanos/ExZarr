defmodule ExZarr.CodecsExtendedTest do
  use ExUnit.Case
  import Bitwise
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
    test "returns error for invalid codec" do
      assert {:error, {:unsupported_codec, :invalid}} = Codecs.compress("data", :invalid)
      assert {:error, {:unsupported_codec, :invalid}} = Codecs.decompress("data", :invalid)
    end
  end

  describe "ZSTD codec" do
    test "zstd compression and decompression" do
      data = "test data for zstd"
      assert {:ok, compressed} = Codecs.compress(data, :zstd)
      assert {:ok, ^data} = Codecs.decompress(compressed, :zstd)
      # Should compress the data
      assert byte_size(compressed) < byte_size(data) * 2
    end
  end

  describe "LZ4 codec" do
    test "lz4 compression and decompression" do
      data = "test data for lz4"
      assert {:ok, compressed} = Codecs.compress(data, :lz4)
      assert {:ok, ^data} = Codecs.decompress(compressed, :lz4)
      # Should compress the data
      assert byte_size(compressed) < byte_size(data) * 2
    end
  end

  describe "Snappy codec" do
    test "snappy compression and decompression" do
      data = "test data for snappy"
      assert {:ok, compressed} = Codecs.compress(data, :snappy)
      assert {:ok, ^data} = Codecs.decompress(compressed, :snappy)
      # Should compress the data
      assert byte_size(compressed) < byte_size(data) * 2
    end
  end

  describe "Blosc codec" do
    test "blosc compression and decompression" do
      data = "test data for blosc"
      assert {:ok, compressed} = Codecs.compress(data, :blosc)
      assert {:ok, ^data} = Codecs.decompress(compressed, :blosc)
      # Should compress the data
      assert byte_size(compressed) < byte_size(data) * 2
    end
  end

  describe "Bzip2 codec" do
    test "bzip2 compression and decompression" do
      data = "test data for bzip2"
      assert {:ok, compressed} = Codecs.compress(data, :bzip2)
      assert {:ok, ^data} = Codecs.decompress(compressed, :bzip2)
      # Compression may make small data larger due to overhead, so just verify round-trip works
      assert is_binary(compressed)
    end
  end

  describe "CRC32C codec" do
    test "crc32c encoding and validation" do
      data = "Hello, World!"
      assert {:ok, encoded} = Codecs.compress(data, :crc32c)
      # Should add 4-byte checksum
      assert byte_size(encoded) == byte_size(data) + 4
      assert {:ok, ^data} = Codecs.decompress(encoded, :crc32c)
    end

    test "crc32c detects corruption" do
      data = "Hello, World!"
      {:ok, encoded} = Codecs.compress(data, :crc32c)

      # Corrupt the checksum
      <<prefix::binary-size(byte_size(data)), _checksum::binary>> = encoded
      corrupted = prefix <> <<0, 0, 0, 0>>

      assert {:error, {:checksum_validation_failed, :crc32c_checksum_mismatch}} =
        Codecs.decompress(corrupted, :crc32c)
    end

    test "crc32c detects data corruption" do
      data = "Hello, World!"
      {:ok, encoded} = Codecs.compress(data, :crc32c)

      # Corrupt the data (flip a bit)
      <<first_byte, rest::binary>> = encoded
      corrupted = <<bxor(first_byte, 1), rest::binary>>

      assert {:error, {:checksum_validation_failed, :crc32c_checksum_mismatch}} =
        Codecs.decompress(corrupted, :crc32c)
    end

    test "crc32c with empty data" do
      data = ""
      assert {:ok, encoded} = Codecs.compress(data, :crc32c)
      assert byte_size(encoded) == 4  # Just the checksum
      assert {:ok, ^data} = Codecs.decompress(encoded, :crc32c)
    end

    test "crc32c with large data" do
      data = String.duplicate("ExZarr is awesome! ", 10000)
      assert {:ok, encoded} = Codecs.compress(data, :crc32c)
      assert byte_size(encoded) == byte_size(data) + 4
      assert {:ok, ^data} = Codecs.decompress(encoded, :crc32c)
    end

    test "crc32c with binary data" do
      data = :crypto.strong_rand_bytes(1000)
      assert {:ok, encoded} = Codecs.compress(data, :crc32c)
      assert byte_size(encoded) == 1004
      assert {:ok, ^data} = Codecs.decompress(encoded, :crc32c)
    end

    test "crc32c rejects too-short data" do
      # Data must be at least 4 bytes (for checksum)
      short_data = <<1, 2, 3>>
      assert {:error, {:checksum_validation_failed, :crc32c_invalid_data}} =
        Codecs.decompress(short_data, :crc32c)
    end

    test "crc32c is deterministic" do
      data = "Same input, same checksum!"
      {:ok, encoded1} = Codecs.compress(data, :crc32c)
      {:ok, encoded2} = Codecs.compress(data, :crc32c)
      assert encoded1 == encoded2
    end

    test "crc32c different data produces different checksums" do
      {:ok, encoded1} = Codecs.compress("Data A", :crc32c)
      {:ok, encoded2} = Codecs.compress("Data B", :crc32c)

      # Extract checksums
      checksum1 = binary_part(encoded1, byte_size("Data A"), 4)
      checksum2 = binary_part(encoded2, byte_size("Data B"), 4)

      assert checksum1 != checksum2
    end
  end

  describe "Codec availability checking" do
    test "reports zlib as available" do
      assert Codecs.codec_available?(:zlib) == true
    end

    test "reports none as available" do
      assert Codecs.codec_available?(:none) == true
    end

    test "reports zstd as available" do
      assert Codecs.codec_available?(:zstd) == true
    end

    test "reports lz4 as available" do
      assert Codecs.codec_available?(:lz4) == true
    end

    test "reports snappy as available" do
      assert Codecs.codec_available?(:snappy) == true
    end

    test "reports blosc as available" do
      assert Codecs.codec_available?(:blosc) == true
    end

    test "reports bzip2 as available" do
      assert Codecs.codec_available?(:bzip2) == true
    end

    test "reports crc32c as available" do
      assert Codecs.codec_available?(:crc32c) == true
    end

    test "reports unknown codec as unavailable" do
      assert Codecs.codec_available?(:unknown) == false
      assert Codecs.codec_available?(:random) == false
    end
  end

  describe "Codec list completeness" do
    test "available_codecs returns non-empty list" do
      codecs = Codecs.available_codecs()
      refute Enum.empty?(codecs)
    end

    test "available_codecs includes none and zlib" do
      codecs = Codecs.available_codecs()
      assert :none in codecs
      assert :zlib in codecs
    end

    test "available_codecs returns expected codecs" do
      codecs = Codecs.available_codecs()
      assert codecs == [:none, :zlib, :crc32c, :zstd, :lz4, :snappy, :blosc, :bzip2]
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
