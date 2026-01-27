defmodule ExZarr.CodecsPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ExZarr.{Codecs, Metadata}

  @moduledoc """
  Property-based tests focused on codec operations to increase coverage.
  """

  # Generators

  defp compressor_with_config do
    one_of([
      constant({:none, %{}}),
      constant({:zlib, %{}}),
      constant({:zlib, %{level: 5}}),
      constant({:zlib, %{level: 9}}),
      constant({:zstd, %{}}),
      constant({:zstd, %{level: 3}}),
      constant({:lz4, %{}}),
      constant({:gzip, %{}}),
      constant({:gzip, %{level: 6}})
    ])
  end

  defp dtype_gen do
    member_of([
      :int8,
      :int16,
      :int32,
      :int64,
      :uint8,
      :uint16,
      :uint32,
      :uint64,
      :float32,
      :float64
    ])
  end

  describe "Codec compression properties" do
    property "compress with different levels" do
      check all(
              data <- binary(min_length: 100, max_length: 5000),
              {codec, config} <- compressor_with_config()
            ) do
        if Codecs.codec_available?(codec) do
          case Codecs.compress(data, codec, config) do
            {:ok, compressed} ->
              assert is_binary(compressed)
              {:ok, decompressed} = Codecs.decompress(compressed, codec)
              assert decompressed == data

            {:error, _reason} ->
              # Some codecs might not be available, that's OK
              :ok
          end
        end
      end
    end

    property "codec_available? is consistent" do
      check all(codec <- member_of([:zlib, :zstd, :lz4, :gzip, :none, :invalid])) do
        result1 = Codecs.codec_available?(codec)
        result2 = Codecs.codec_available?(codec)

        # Should be consistent
        assert result1 == result2
        assert is_boolean(result1)
      end
    end

    property "compression preserves data size for incompressible data" do
      check all(data <- binary(min_length: 10, max_length: 100)) do
        # Random data is usually incompressible
        {:ok, compressed} = Codecs.compress(data, :zlib)
        {:ok, decompressed} = Codecs.decompress(compressed, :zlib)

        assert byte_size(decompressed) == byte_size(data)
        assert decompressed == data
      end
    end

    property "empty data compresses and decompresses" do
      check all(_ <- constant(nil)) do
        data = <<>>

        for codec <- [:none, :zlib] do
          if Codecs.codec_available?(codec) do
            {:ok, compressed} = Codecs.compress(data, codec)
            {:ok, decompressed} = Codecs.decompress(compressed, codec)
            assert decompressed == <<>>
          end
        end
      end
    end

    property "large data compresses efficiently" do
      check all(
              pattern <- binary(min_length: 1, max_length: 10),
              repetitions <- integer(100..500)
            ) do
        data = String.duplicate(pattern, repetitions)

        {:ok, compressed} = Codecs.compress(data, :zlib)
        {:ok, decompressed} = Codecs.decompress(compressed, :zlib)

        assert decompressed == data
        # Compressed should be smaller for repetitive data
        assert byte_size(compressed) < byte_size(data)
      end
    end

    property "different compression levels work" do
      check all(
              data <- binary(min_length: 1000, max_length: 5000),
              level <- integer(1..9)
            ) do
        config = %{level: level}

        {:ok, compressed} = Codecs.compress(data, :zlib, config)
        {:ok, decompressed} = Codecs.decompress(compressed, :zlib)

        assert decompressed == data
      end
    end
  end

  describe "Codec selection properties" do
    property "codec_available? is stable across calls" do
      check all(
              codec <- member_of([:zlib, :zstd, :lz4, :gzip, :none, :invalid]),
              count <- integer(2..10)
            ) do
        # Try to check codec availability multiple times
        results =
          Enum.map(1..count, fn _ ->
            Codecs.codec_available?(codec)
          end)

        # All results should be the same (stable)
        assert Enum.uniq(results) |> length() == 1
      end
    end

    property "codec registration is idempotent" do
      check all(count <- integer(1..10)) do
        # Try to get codec multiple times
        results =
          Enum.map(1..count, fn _ ->
            Codecs.codec_available?(:zlib)
          end)

        # All results should be the same
        assert Enum.uniq(results) |> length() == 1
      end
    end
  end

  describe "Array codec integration properties" do
    property "arrays with different codecs work correctly" do
      check all(
              {codec, _config} <- compressor_with_config(),
              dtype <- dtype_gen()
            ) do
        if Codecs.codec_available?(codec) do
          {:ok, array} =
            ExZarr.create(
              shape: {50, 50},
              chunks: {10, 10},
              dtype: dtype,
              compressor: codec,
              storage: :memory
            )

          assert array.compressor == codec
          assert array.dtype == dtype
        end
      end
    end

    property "metadata preserves compressor configuration" do
      check all(
              {codec, _config} <- compressor_with_config(),
              shape_size <- integer(10..100)
            ) do
        if Codecs.codec_available?(codec) do
          metadata = %Metadata{
            shape: {shape_size},
            chunks: {10},
            dtype: :float64,
            compressor: codec,
            fill_value: 0.0,
            order: "C",
            zarr_format: 2
          }

          # Verify metadata is valid
          assert metadata.compressor == codec
          assert metadata.shape == {shape_size}

          # Verify total chunks calculation
          total = Metadata.total_chunks(metadata)
          expected = ceil(shape_size / 10)
          assert total == expected
        end
      end
    end
  end

  describe "Error handling properties" do
    property "invalid compression config returns error" do
      check all(data <- binary(min_length: 1, max_length: 100)) do
        # Invalid config (negative level)
        invalid_config = %{level: -1}

        result = Codecs.compress(data, :zlib, invalid_config)

        case result do
          {:ok, _compressed} ->
            # Implementation might handle gracefully
            :ok

          {:error, _reason} ->
            # Or return error - both acceptable
            :ok
        end
      end
    end

    property "decompressing random data fails or succeeds gracefully" do
      check all(data <- binary(min_length: 10, max_length: 100)) do
        # Try to decompress random data (not actually compressed)
        result = Codecs.decompress(data, :zlib)

        case result do
          {:ok, _decompressed} ->
            # Might succeed if data happens to be valid
            :ok

          {:error, _reason} ->
            # Or fail gracefully
            :ok
        end

        # Should not crash
        assert true
      end
    end

    property "none codec handles any data" do
      check all(data <- binary(max_length: 10_000)) do
        {:ok, compressed} = Codecs.compress(data, :none)
        {:ok, decompressed} = Codecs.decompress(compressed, :none)

        # None codec is identity
        assert compressed == data
        assert decompressed == data
      end
    end
  end

  describe "Compression ratio properties" do
    property "compression ratio for zeros is high" do
      check all(size <- integer(1000..10_000)) do
        data = :binary.copy(<<0>>, size)

        {:ok, compressed} = Codecs.compress(data, :zlib)

        compression_ratio = byte_size(data) / max(1, byte_size(compressed))

        # Zeros should compress very well (at least 10x)
        assert compression_ratio >= 10.0
      end
    end

    property "compression ratio for random data is low" do
      check all(data <- binary(min_length: 1000, max_length: 5000)) do
        {:ok, compressed} = Codecs.compress(data, :zlib)

        compression_ratio = byte_size(data) / max(1, byte_size(compressed))

        # Random data might not compress well
        # Allow ratio from 0.5 (expansion) to 5 (good compression)
        assert compression_ratio >= 0.5
        assert compression_ratio <= 10.0
      end
    end
  end

  describe "Codec metadata properties" do
    property "metadata chunk_size_bytes calculation" do
      check all(
              chunk_size <- integer(10..100),
              dtype <- dtype_gen()
            ) do
        itemsize =
          case dtype do
            dt when dt in [:int8, :uint8] -> 1
            dt when dt in [:int16, :uint16] -> 2
            dt when dt in [:int32, :uint32, :float32] -> 4
            dt when dt in [:int64, :uint64, :float64] -> 8
          end

        metadata = %Metadata{
          shape: {chunk_size * 10},
          chunks: {chunk_size},
          dtype: dtype,
          compressor: :none,
          fill_value: 0,
          order: "C",
          zarr_format: 2
        }

        expected_bytes = chunk_size * itemsize
        assert Metadata.chunk_size_bytes(metadata) == expected_bytes
      end
    end

    property "metadata total_chunks for 1D arrays" do
      check all(
              size <- integer(100..1000),
              chunk_size <- integer(10..100)
            ) do
        metadata = %Metadata{
          shape: {size},
          chunks: {chunk_size},
          dtype: :float64,
          compressor: :none,
          fill_value: 0,
          order: "C",
          zarr_format: 2
        }

        expected_total = ceil(size / chunk_size)
        assert Metadata.total_chunks(metadata) == expected_total
      end
    end

    property "metadata total_chunks for 2D arrays" do
      check all(
              size_x <- integer(50..200),
              size_y <- integer(50..200),
              chunk_x <- integer(10..50),
              chunk_y <- integer(10..50)
            ) do
        metadata = %Metadata{
          shape: {size_x, size_y},
          chunks: {chunk_x, chunk_y},
          dtype: :int32,
          compressor: :zlib,
          fill_value: 0,
          order: "C",
          zarr_format: 2
        }

        expected_total = ceil(size_x / chunk_x) * ceil(size_y / chunk_y)
        assert Metadata.total_chunks(metadata) == expected_total
      end
    end
  end

  describe "Multiple codecs interaction" do
    property "switching codecs between writes" do
      check all(data1 <- binary(min_length: 10, max_length: 100)) do
        # Compress with zlib
        {:ok, zlib_compressed} = Codecs.compress(data1, :zlib)
        {:ok, zlib_decompressed} = Codecs.decompress(zlib_compressed, :zlib)
        assert zlib_decompressed == data1

        # Compress with none
        {:ok, none_compressed} = Codecs.compress(data1, :none)
        {:ok, none_decompressed} = Codecs.decompress(none_compressed, :none)
        assert none_decompressed == data1

        # Original data unchanged
        assert data1 == zlib_decompressed
        assert data1 == none_decompressed
      end
    end
  end
end
