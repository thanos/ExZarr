defmodule ExZarr.DataTypeTest do
  use ExUnit.Case, async: true

  doctest ExZarr.DataType

  describe "to_v3/1" do
    test "converts integer types" do
      assert "int8" = ExZarr.DataType.to_v3(:int8)
      assert "int16" = ExZarr.DataType.to_v3(:int16)
      assert "int32" = ExZarr.DataType.to_v3(:int32)
      assert "int64" = ExZarr.DataType.to_v3(:int64)
    end

    test "converts unsigned integer types" do
      assert "uint8" = ExZarr.DataType.to_v3(:uint8)
      assert "uint16" = ExZarr.DataType.to_v3(:uint16)
      assert "uint32" = ExZarr.DataType.to_v3(:uint32)
      assert "uint64" = ExZarr.DataType.to_v3(:uint64)
    end

    test "converts float types" do
      assert "float32" = ExZarr.DataType.to_v3(:float32)
      assert "float64" = ExZarr.DataType.to_v3(:float64)
    end

    test "raises for unknown types" do
      assert_raise ArgumentError, ~r/Unknown dtype atom/, fn ->
        ExZarr.DataType.to_v3(:unknown)
      end
    end
  end

  describe "from_v3/1" do
    test "converts integer types" do
      assert :int8 = ExZarr.DataType.from_v3("int8")
      assert :int16 = ExZarr.DataType.from_v3("int16")
      assert :int32 = ExZarr.DataType.from_v3("int32")
      assert :int64 = ExZarr.DataType.from_v3("int64")
    end

    test "converts unsigned integer types" do
      assert :uint8 = ExZarr.DataType.from_v3("uint8")
      assert :uint16 = ExZarr.DataType.from_v3("uint16")
      assert :uint32 = ExZarr.DataType.from_v3("uint32")
      assert :uint64 = ExZarr.DataType.from_v3("uint64")
    end

    test "converts float types" do
      assert :float32 = ExZarr.DataType.from_v3("float32")
      assert :float64 = ExZarr.DataType.from_v3("float64")
    end

    test "raises for unknown types" do
      assert_raise ArgumentError, ~r/Unknown v3 data type/, fn ->
        ExZarr.DataType.from_v3("unknown")
      end
    end
  end

  describe "to_v2/1" do
    test "converts integer types to NumPy format" do
      assert "<i1" = ExZarr.DataType.to_v2(:int8)
      assert "<i2" = ExZarr.DataType.to_v2(:int16)
      assert "<i4" = ExZarr.DataType.to_v2(:int32)
      assert "<i8" = ExZarr.DataType.to_v2(:int64)
    end

    test "converts unsigned integer types to NumPy format" do
      assert "<u1" = ExZarr.DataType.to_v2(:uint8)
      assert "<u2" = ExZarr.DataType.to_v2(:uint16)
      assert "<u4" = ExZarr.DataType.to_v2(:uint32)
      assert "<u8" = ExZarr.DataType.to_v2(:uint64)
    end

    test "converts float types to NumPy format" do
      assert "<f4" = ExZarr.DataType.to_v2(:float32)
      assert "<f8" = ExZarr.DataType.to_v2(:float64)
    end

    test "raises for unknown types" do
      assert_raise ArgumentError, ~r/Unknown dtype atom/, fn ->
        ExZarr.DataType.to_v2(:unknown)
      end
    end
  end

  describe "from_v2/1" do
    test "converts integer types from NumPy format" do
      assert :int8 = ExZarr.DataType.from_v2("<i1")
      assert :int16 = ExZarr.DataType.from_v2("<i2")
      assert :int32 = ExZarr.DataType.from_v2("<i4")
      assert :int64 = ExZarr.DataType.from_v2("<i8")
    end

    test "converts unsigned integer types from NumPy format" do
      assert :uint8 = ExZarr.DataType.from_v2("<u1")
      assert :uint16 = ExZarr.DataType.from_v2("<u2")
      assert :uint32 = ExZarr.DataType.from_v2("<u4")
      assert :uint64 = ExZarr.DataType.from_v2("<u8")
    end

    test "converts float types from NumPy format" do
      assert :float32 = ExZarr.DataType.from_v2("<f4")
      assert :float64 = ExZarr.DataType.from_v2("<f8")
    end

    test "handles big-endian byte order" do
      assert :int32 = ExZarr.DataType.from_v2(">i4")
      assert :float64 = ExZarr.DataType.from_v2(">f8")
    end

    test "handles not-applicable byte order" do
      assert :uint8 = ExZarr.DataType.from_v2("|u1")
      assert :int8 = ExZarr.DataType.from_v2("|i1")
    end

    test "raises for unknown types" do
      assert_raise ArgumentError, ~r/Unknown v2 dtype string/, fn ->
        ExZarr.DataType.from_v2("<unknown")
      end

      assert_raise ArgumentError, ~r/Unknown v2 dtype string/, fn ->
        ExZarr.DataType.from_v2("|x9")
      end
    end
  end

  describe "bidirectional conversion" do
    test "v3 round-trip" do
      types = [
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
      ]

      for dtype <- types do
        v3_str = ExZarr.DataType.to_v3(dtype)
        assert ^dtype = ExZarr.DataType.from_v3(v3_str)
      end
    end

    test "v2 round-trip" do
      types = [
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
      ]

      for dtype <- types do
        v2_str = ExZarr.DataType.to_v2(dtype)
        assert ^dtype = ExZarr.DataType.from_v2(v2_str)
      end
    end

    test "v2 to v3 conversion" do
      assert "int32" = ExZarr.DataType.to_v3(ExZarr.DataType.from_v2("<i4"))
      assert "float64" = ExZarr.DataType.to_v3(ExZarr.DataType.from_v2("<f8"))
      assert "uint16" = ExZarr.DataType.to_v3(ExZarr.DataType.from_v2("<u2"))
    end

    test "v3 to v2 conversion" do
      assert "<i4" = ExZarr.DataType.to_v2(ExZarr.DataType.from_v3("int32"))
      assert "<f8" = ExZarr.DataType.to_v2(ExZarr.DataType.from_v3("float64"))
      assert "<u2" = ExZarr.DataType.to_v2(ExZarr.DataType.from_v3("uint16"))
    end
  end

  describe "itemsize/1" do
    test "returns correct size for integer types" do
      assert 1 = ExZarr.DataType.itemsize(:int8)
      assert 2 = ExZarr.DataType.itemsize(:int16)
      assert 4 = ExZarr.DataType.itemsize(:int32)
      assert 8 = ExZarr.DataType.itemsize(:int64)
    end

    test "returns correct size for unsigned integer types" do
      assert 1 = ExZarr.DataType.itemsize(:uint8)
      assert 2 = ExZarr.DataType.itemsize(:uint16)
      assert 4 = ExZarr.DataType.itemsize(:uint32)
      assert 8 = ExZarr.DataType.itemsize(:uint64)
    end

    test "returns correct size for float types" do
      assert 4 = ExZarr.DataType.itemsize(:float32)
      assert 8 = ExZarr.DataType.itemsize(:float64)
    end

    test "accepts v3 strings" do
      assert 4 = ExZarr.DataType.itemsize("int32")
      assert 8 = ExZarr.DataType.itemsize("float64")
      assert 2 = ExZarr.DataType.itemsize("uint16")
    end

    test "raises for unknown types" do
      assert_raise ArgumentError, fn ->
        ExZarr.DataType.itemsize(:unknown)
      end
    end
  end

  describe "type predicates" do
    test "signed?/1" do
      assert ExZarr.DataType.signed?(:int8)
      assert ExZarr.DataType.signed?(:int16)
      assert ExZarr.DataType.signed?(:int32)
      assert ExZarr.DataType.signed?(:int64)

      refute ExZarr.DataType.signed?(:uint8)
      refute ExZarr.DataType.signed?(:uint32)
      refute ExZarr.DataType.signed?(:float32)
      refute ExZarr.DataType.signed?(:float64)
    end

    test "unsigned?/1" do
      assert ExZarr.DataType.unsigned?(:uint8)
      assert ExZarr.DataType.unsigned?(:uint16)
      assert ExZarr.DataType.unsigned?(:uint32)
      assert ExZarr.DataType.unsigned?(:uint64)

      refute ExZarr.DataType.unsigned?(:int8)
      refute ExZarr.DataType.unsigned?(:int32)
      refute ExZarr.DataType.unsigned?(:float32)
      refute ExZarr.DataType.unsigned?(:float64)
    end

    test "float?/1" do
      assert ExZarr.DataType.float?(:float32)
      assert ExZarr.DataType.float?(:float64)

      refute ExZarr.DataType.float?(:int8)
      refute ExZarr.DataType.float?(:int32)
      refute ExZarr.DataType.float?(:uint8)
      refute ExZarr.DataType.float?(:uint32)
    end
  end

  describe "supported_types/0" do
    test "returns list of all supported types" do
      types = ExZarr.DataType.supported_types()
      assert length(types) == 10
      assert :int32 in types
      assert :float64 in types
      assert :uint8 in types
    end
  end

  describe "validate/1" do
    test "validates atoms" do
      assert :ok = ExZarr.DataType.validate(:int32)
      assert :ok = ExZarr.DataType.validate(:float64)
      assert :ok = ExZarr.DataType.validate(:uint8)
    end

    test "validates v3 strings" do
      assert :ok = ExZarr.DataType.validate("int32")
      assert :ok = ExZarr.DataType.validate("float64")
      assert :ok = ExZarr.DataType.validate("uint8")
    end

    test "validates v2 strings" do
      assert :ok = ExZarr.DataType.validate("<i4")
      assert :ok = ExZarr.DataType.validate("<f8")
      assert :ok = ExZarr.DataType.validate("|u1")
    end

    test "rejects invalid types" do
      assert {:error, :unsupported_dtype} = ExZarr.DataType.validate(:unknown)
      assert {:error, :unsupported_dtype} = ExZarr.DataType.validate("unknown")
      assert {:error, :unsupported_dtype} = ExZarr.DataType.validate("<x9")
    end
  end
end
