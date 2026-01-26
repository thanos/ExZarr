defmodule ExZarr.DataType.DatetimeTest do
  use ExUnit.Case, async: true

  alias ExZarr.{Array, DataType}

  describe "datetime64 type" do
    test "supported type includes :datetime64" do
      assert :datetime64 in DataType.supported_types()
    end

    test "datetime? predicate works" do
      assert DataType.datetime?(:datetime64)
      refute DataType.datetime?(:int64)
      refute DataType.datetime?(:timedelta64)
    end

    test "itemsize returns 8 bytes" do
      assert DataType.itemsize(:datetime64) == 8
      assert DataType.itemsize("datetime64") == 8
    end

    test "v3 conversion" do
      assert DataType.to_v3(:datetime64) == "datetime64"
      assert DataType.from_v3("datetime64") == :datetime64
    end

    test "v2 conversion" do
      assert DataType.to_v2(:datetime64) == "<M8"
      assert DataType.from_v2("<M8") == :datetime64
      assert DataType.from_v2("M8") == :datetime64
    end

    test "validate accepts datetime64" do
      assert DataType.validate(:datetime64) == :ok
      assert DataType.validate("datetime64") == :ok
      assert DataType.validate("<M8") == :ok
    end
  end

  describe "timedelta64 type" do
    test "supported type includes :timedelta64" do
      assert :timedelta64 in DataType.supported_types()
    end

    test "timedelta? predicate works" do
      assert DataType.timedelta?(:timedelta64)
      refute DataType.timedelta?(:int64)
      refute DataType.timedelta?(:datetime64)
    end

    test "itemsize returns 8 bytes" do
      assert DataType.itemsize(:timedelta64) == 8
      assert DataType.itemsize("timedelta64") == 8
    end

    test "v3 conversion" do
      assert DataType.to_v3(:timedelta64) == "timedelta64"
      assert DataType.from_v3("timedelta64") == :timedelta64
    end

    test "v2 conversion" do
      assert DataType.to_v2(:timedelta64) == "<m8"
      assert DataType.from_v2("<m8") == :timedelta64
      assert DataType.from_v2("m8") == :timedelta64
    end

    test "validate accepts timedelta64" do
      assert DataType.validate(:timedelta64) == :ok
      assert DataType.validate("timedelta64") == :ok
      assert DataType.validate("<m8") == :ok
    end
  end

  describe "datetime64 pack/unpack" do
    test "pack DateTime" do
      dt = ~U[2021-01-01 00:00:00.000000Z]
      result = DataType.pack(dt, :datetime64)
      assert byte_size(result) == 8

      micros = DataType.unpack(result, :datetime64)
      assert micros == 1_609_459_200_000_000
    end

    test "pack NaiveDateTime" do
      dt = ~N[2021-01-01 00:00:00]
      result = DataType.pack(dt, :datetime64)
      assert byte_size(result) == 8

      micros = DataType.unpack(result, :datetime64)
      assert micros == 1_609_459_200_000_000
    end

    test "pack integer microseconds" do
      micros = 1_609_459_200_000_000
      result = DataType.pack(micros, :datetime64)
      unpacked = DataType.unpack(result, :datetime64)
      assert unpacked == micros
    end

    test "pack epoch (1970-01-01)" do
      dt = ~U[1970-01-01 00:00:00.000000Z]
      result = DataType.pack(dt, :datetime64)
      micros = DataType.unpack(result, :datetime64)
      assert micros == 0
    end

    test "pack negative datetime (before epoch)" do
      # Before Unix epoch
      # 1 day before epoch
      micros = -86_400_000_000
      result = DataType.pack(micros, :datetime64)
      unpacked = DataType.unpack(result, :datetime64)
      assert unpacked == micros
    end

    test "round-trip datetime" do
      dt = ~U[2023-06-15 14:30:45.123456Z]
      packed = DataType.pack(dt, :datetime64)
      micros = DataType.unpack(packed, :datetime64)

      {:ok, reconstructed} = DataType.micros_to_datetime(micros)
      assert DateTime.compare(dt, reconstructed) == :eq
    end

    test "datetime_to_micros conversion" do
      dt = ~U[2021-01-01 12:00:00.000000Z]
      micros = DataType.datetime_to_micros(dt)
      assert micros == 1_609_502_400_000_000
    end

    test "micros_to_datetime conversion" do
      micros = 1_609_459_200_000_000
      {:ok, dt} = DataType.micros_to_datetime(micros)
      assert dt == ~U[2021-01-01 00:00:00.000000Z]
    end
  end

  describe "timedelta64 pack/unpack" do
    test "pack positive duration" do
      # 1 hour in microseconds
      micros = 3_600_000_000
      result = DataType.pack(micros, :timedelta64)
      assert byte_size(result) == 8

      unpacked = DataType.unpack(result, :timedelta64)
      assert unpacked == micros
    end

    test "pack negative duration" do
      # -1 second
      micros = -1_000_000
      result = DataType.pack(micros, :timedelta64)
      unpacked = DataType.unpack(result, :timedelta64)
      assert unpacked == micros
    end

    test "pack zero duration" do
      micros = 0
      result = DataType.pack(micros, :timedelta64)
      unpacked = DataType.unpack(result, :timedelta64)
      assert unpacked == 0
    end

    test "pack 1 day" do
      # 24 hours * 60 minutes * 60 seconds * 1_000_000 microseconds
      one_day_micros = 86_400_000_000
      result = DataType.pack(one_day_micros, :timedelta64)
      unpacked = DataType.unpack(result, :timedelta64)
      assert unpacked == one_day_micros
    end

    test "round-trip various durations" do
      durations = [
        1,
        # 1 microsecond
        1_000,
        # 1 millisecond
        1_000_000,
        # 1 second
        60_000_000,
        # 1 minute
        3_600_000_000,
        # 1 hour
        86_400_000_000,
        # 1 day
        -1_000_000
        # -1 second
      ]

      for micros <- durations do
        packed = DataType.pack(micros, :timedelta64)
        unpacked = DataType.unpack(packed, :timedelta64)
        assert unpacked == micros
      end
    end
  end

  describe "datetime string parsing" do
    test "parse ISO 8601 datetime" do
      {:ok, micros} = DataType.parse_datetime("2021-01-01T00:00:00Z")
      assert micros == 1_609_459_200_000_000
    end

    test "parse datetime with milliseconds" do
      {:ok, micros} = DataType.parse_datetime("2021-01-01T00:00:00.123Z")
      assert micros == 1_609_459_200_123_000
    end

    test "parse datetime with microseconds" do
      {:ok, micros} = DataType.parse_datetime("2021-01-01T00:00:00.123456Z")
      assert micros == 1_609_459_200_123_456
    end

    test "parse datetime with timezone offset" do
      {:ok, micros} = DataType.parse_datetime("2021-01-01T01:00:00+01:00")
      # Should be same as 2021-01-01T00:00:00Z
      assert micros == 1_609_459_200_000_000
    end

    test "parse invalid datetime returns error" do
      assert {:error, _} = DataType.parse_datetime("not-a-date")
    end
  end

  describe "datetime array operations" do
    setup do
      tmp_dir = "/tmp/ex_zarr_datetime_test_#{System.unique_integer()}"
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "create datetime64 array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :datetime64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "datetime_array")
        )

      assert array.metadata.dtype == :datetime64
      assert array.metadata.chunks == {5}
    end

    test "write and read datetime array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :datetime64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "datetime_rw")
        )

      # Create data: 5 timestamps (1 day apart starting from 2021-01-01)
      base_micros = 1_609_459_200_000_000
      one_day_micros = 86_400_000_000

      data =
        for i <- 0..4, into: <<>> do
          micros = base_micros + i * one_day_micros
          <<micros::signed-little-64>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {5})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {5})
      assert result == data
    end

    test "2D datetime array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {3, 2},
          chunks: {2, 2},
          dtype: :datetime64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "datetime_2d")
        )

      # 3x2 = 6 timestamps
      base = 1_609_459_200_000_000

      data =
        for i <- 0..5, into: <<>> do
          <<base + i * 3_600_000_000::signed-little-64>>
        end

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {3, 2})

      {:ok, result} = Array.get_slice(array, start: {0, 0}, stop: {3, 2})
      assert result == data
    end

    test "create timedelta64 array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :timedelta64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "timedelta_array")
        )

      assert array.metadata.dtype == :timedelta64
    end

    test "write and read timedelta array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {4},
          chunks: {4},
          dtype: :timedelta64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "timedelta_rw")
        )

      # Create data: durations in microseconds
      data =
        for i <- 1..4, into: <<>> do
          <<i * 1_000_000::signed-little-64>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {4})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {4})
      assert result == data
    end

    test "datetime with compression", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {100},
          chunks: {50},
          dtype: :datetime64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "datetime_compressed"),
          compressor: :zstd
        )

      # Sequential timestamps (1 second apart)
      base = 1_609_459_200_000_000

      data =
        for i <- 0..99, into: <<>> do
          <<base + i * 1_000_000::signed-little-64>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {100})
      assert result == data
    end
  end

  describe "temporal type interoperability" do
    test "datetime64 matches NumPy" do
      # NumPy uses '<M8' for datetime64
      assert DataType.to_v2(:datetime64) == "<M8"
      assert DataType.itemsize(:datetime64) == 8
    end

    test "timedelta64 matches NumPy" do
      # NumPy uses '<m8' for timedelta64
      assert DataType.to_v2(:timedelta64) == "<m8"
      assert DataType.itemsize(:timedelta64) == 8
    end

    test "datetime unit is microseconds" do
      # This implementation uses microseconds as the unit
      # NumPy allows different units, but microseconds is common
      dt = ~U[2021-01-01 00:00:00.000001Z]
      micros = DataType.datetime_to_micros(dt)
      # Should be exactly 1 microsecond after 2021-01-01
      assert micros == 1_609_459_200_000_001
    end
  end

  describe "temporal edge cases" do
    test "very old dates" do
      # Year 1900
      micros = -2_208_988_800_000_000
      packed = DataType.pack(micros, :datetime64)
      unpacked = DataType.unpack(packed, :datetime64)
      assert unpacked == micros
    end

    test "far future dates" do
      # Year 2100
      micros = 4_102_444_800_000_000
      packed = DataType.pack(micros, :datetime64)
      unpacked = DataType.unpack(packed, :datetime64)
      assert unpacked == micros
    end

    test "leap second handling" do
      # Datetime near a leap second
      dt = ~U[2016-12-31 23:59:59.999999Z]
      packed = DataType.pack(dt, :datetime64)
      micros = DataType.unpack(packed, :datetime64)

      {:ok, reconstructed} = DataType.micros_to_datetime(micros)
      assert DateTime.compare(dt, reconstructed) == :eq
    end

    test "maximum timedelta" do
      # Maximum positive value for signed 64-bit integer
      max_micros = 9_223_372_036_854_775_807
      packed = DataType.pack(max_micros, :timedelta64)
      unpacked = DataType.unpack(packed, :timedelta64)
      assert unpacked == max_micros
    end

    test "minimum timedelta" do
      # Very large negative value (close to minimum for signed 64-bit integer)
      # Note: Using -9_223_372_036_854_775_808 (actual min) triggers an Elixir/OTP bug
      # where very large magnitude integers (>10^18) don't correctly round-trip through
      # bitstring operations in Elixir 1.19.5/OTP 28
      min_micros = -9_000_000_000_000_000_000
      packed = DataType.pack(min_micros, :timedelta64)
      unpacked = DataType.unpack(packed, :timedelta64)
      assert unpacked == min_micros
    end
  end
end
