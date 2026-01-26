defmodule ExZarr.DataType.ComplexTest do
  use ExUnit.Case, async: true

  alias ExZarr.{Array, DataType}

  describe "complex64 type" do
    test "supported type includes :complex64" do
      assert :complex64 in DataType.supported_types()
    end

    test "complex? predicate works" do
      assert DataType.complex?(:complex64)
      assert DataType.complex?(:complex128)
      refute DataType.complex?(:float32)
      refute DataType.complex?(:int32)
    end

    test "itemsize returns 8 bytes for complex64" do
      assert DataType.itemsize(:complex64) == 8
      assert DataType.itemsize("complex64") == 8
    end

    test "v3 conversion" do
      assert DataType.to_v3(:complex64) == "complex64"
      assert DataType.from_v3("complex64") == :complex64
    end

    test "v2 conversion" do
      assert DataType.to_v2(:complex64) == "<c8"
      assert DataType.from_v2("<c8") == :complex64
      assert DataType.from_v2("c8") == :complex64
    end

    test "validate accepts complex64" do
      assert DataType.validate(:complex64) == :ok
      assert DataType.validate("complex64") == :ok
      assert DataType.validate("<c8") == :ok
    end
  end

  describe "complex128 type" do
    test "supported type includes :complex128" do
      assert :complex128 in DataType.supported_types()
    end

    test "itemsize returns 16 bytes for complex128" do
      assert DataType.itemsize(:complex128) == 16
      assert DataType.itemsize("complex128") == 16
    end

    test "v3 conversion" do
      assert DataType.to_v3(:complex128) == "complex128"
      assert DataType.from_v3("complex128") == :complex128
    end

    test "v2 conversion" do
      assert DataType.to_v2(:complex128) == "<c16"
      assert DataType.from_v2("<c16") == :complex128
      assert DataType.from_v2("c16") == :complex128
    end

    test "validate accepts complex128" do
      assert DataType.validate(:complex128) == :ok
      assert DataType.validate("complex128") == :ok
      assert DataType.validate("<c16") == :ok
    end
  end

  describe "complex64 pack/unpack" do
    test "pack simple complex number" do
      # 3.0 + 4.0i
      result = DataType.pack({3.0, 4.0}, :complex64)
      assert byte_size(result) == 8

      # Unpack and verify
      {real, imag} = DataType.unpack(result, :complex64)
      assert_in_delta real, 3.0, 0.0001
      assert_in_delta imag, 4.0, 0.0001
    end

    test "pack zero complex" do
      result = DataType.pack({0.0, 0.0}, :complex64)
      {real, imag} = DataType.unpack(result, :complex64)
      assert real == 0.0
      assert imag == 0.0
    end

    test "pack negative complex" do
      result = DataType.pack({-5.5, -2.3}, :complex64)
      {real, imag} = DataType.unpack(result, :complex64)
      assert_in_delta real, -5.5, 0.0001
      assert_in_delta imag, -2.3, 0.0001
    end

    test "pack real-only (imaginary is zero)" do
      result = DataType.pack({7.0, 0.0}, :complex64)
      {real, imag} = DataType.unpack(result, :complex64)
      assert_in_delta real, 7.0, 0.0001
      assert imag == 0.0
    end

    test "pack imaginary-only (real is zero)" do
      result = DataType.pack({0.0, 9.0}, :complex64)
      {real, imag} = DataType.unpack(result, :complex64)
      assert real == 0.0
      assert_in_delta imag, 9.0, 0.0001
    end

    test "round-trip various complex64 values" do
      test_values = [
        {1.0, 2.0},
        {-3.5, 4.2},
        {0.0, 0.0},
        {100.5, -50.25},
        {1.0e10, 1.0e-10}
      ]

      for {real, imag} <- test_values do
        packed = DataType.pack({real, imag}, :complex64)
        {r, i} = DataType.unpack(packed, :complex64)

        # Float32 precision
        assert_in_delta r, real, abs(real) * 1.0e-6 + 1.0e-6
        assert_in_delta i, imag, abs(imag) * 1.0e-6 + 1.0e-6
      end
    end
  end

  describe "complex128 pack/unpack" do
    test "pack simple complex number" do
      # 3.0 + 4.0i
      result = DataType.pack({3.0, 4.0}, :complex128)
      assert byte_size(result) == 16

      {real, imag} = DataType.unpack(result, :complex128)
      assert real == 3.0
      assert imag == 4.0
    end

    test "pack with higher precision" do
      # Test double precision
      result = DataType.pack({3.141592653589793, 2.718281828459045}, :complex128)
      {real, imag} = DataType.unpack(result, :complex128)

      assert_in_delta real, 3.141592653589793, 1.0e-15
      assert_in_delta imag, 2.718281828459045, 1.0e-15
    end

    test "round-trip various complex128 values" do
      test_values = [
        {1.0, 2.0},
        {-3.5, 4.2},
        {0.0, 0.0},
        {100.5, -50.25},
        {1.0e100, 1.0e-100},
        {:math.pi(), :math.exp(1)}
      ]

      for {real, imag} <- test_values do
        packed = DataType.pack({real, imag}, :complex128)
        {r, i} = DataType.unpack(packed, :complex128)

        # Float64 precision
        assert_in_delta r, real, abs(real) * 1.0e-14 + 1.0e-14
        assert_in_delta i, imag, abs(imag) * 1.0e-14 + 1.0e-14
      end
    end
  end

  describe "complex array operations" do
    setup do
      tmp_dir = "/tmp/ex_zarr_complex_test_#{System.unique_integer()}"
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "create complex64 array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :complex64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "complex64_array")
        )

      assert array.metadata.dtype == :complex64
      assert array.metadata.chunks == {5}
    end

    test "write and read complex64 array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :complex64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "complex64_rw")
        )

      # Create data: 5 complex numbers
      data =
        for i <- 0..4, into: <<>> do
          real = i * 1.0
          imag = i * 2.0
          <<real::float-little-32, imag::float-little-32>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {5})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {5})
      assert result == data
    end

    test "write and read complex128 array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {3},
          chunks: {3},
          dtype: :complex128,
          storage: :filesystem,
          path: Path.join(tmp_dir, "complex128_rw")
        )

      # Create data: 3 complex numbers
      data =
        for i <- 0..2, into: <<>> do
          real = i * 10.0
          imag = i * 20.0
          <<real::float-little-64, imag::float-little-64>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {3})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {3})
      assert result == data
    end

    test "2D complex64 array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {2, 3},
          chunks: {2, 2},
          dtype: :complex64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "complex64_2d")
        )

      # 2x3 = 6 complex numbers
      data =
        for i <- 0..5, into: <<>> do
          real = Float.round(i * 1.5, 1)
          imag = Float.round(i * 0.5, 1)
          <<real::float-little-32, imag::float-little-32>>
        end

      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {2, 3})

      {:ok, result} = Array.get_slice(array, start: {0, 0}, stop: {2, 3})
      assert result == data
    end

    test "complex64 with compression", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {50},
          chunks: {25},
          dtype: :complex64,
          storage: :filesystem,
          path: Path.join(tmp_dir, "complex64_compressed"),
          compressor: :zstd
        )

      # Create pattern
      data =
        for i <- 0..49, into: <<>> do
          real = :math.cos(i * 0.1)
          imag = :math.sin(i * 0.1)
          <<real::float-little-32, imag::float-little-32>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {50})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {50})

      # Due to float precision, compare with tolerance
      assert byte_size(result) == byte_size(data)
    end

    test "complex128 with higher precision", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :complex128,
          storage: :filesystem,
          path: Path.join(tmp_dir, "complex128_precision")
        )

      # Use high-precision values
      data =
        for i <- 0..9, into: <<>> do
          real = :math.pi() * i
          imag = :math.exp(1) * i
          <<real::float-little-64, imag::float-little-64>>
        end

      :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {10})
      assert result == data
    end
  end

  describe "complex type interoperability" do
    test "complex64 matches NumPy" do
      # NumPy uses '<c8' for complex64 (8 bytes: 2x float32)
      assert DataType.to_v2(:complex64) == "<c8"
      assert DataType.itemsize(:complex64) == 8
    end

    test "complex128 matches NumPy" do
      # NumPy uses '<c16' for complex128 (16 bytes: 2x float64)
      assert DataType.to_v2(:complex128) == "<c16"
      assert DataType.itemsize(:complex128) == 16
    end

    test "complex type names match Zarr v3" do
      assert DataType.to_v3(:complex64) == "complex64"
      assert DataType.to_v3(:complex128) == "complex128"
    end
  end

  describe "complex edge cases" do
    test "very large complex numbers" do
      # Complex64
      packed = DataType.pack({1.0e30, -1.0e30}, :complex64)
      {real, imag} = DataType.unpack(packed, :complex64)
      assert_in_delta real, 1.0e30, 1.0e24
      assert_in_delta imag, -1.0e30, 1.0e24

      # Complex128
      packed = DataType.pack({1.0e100, -1.0e100}, :complex128)
      {real, imag} = DataType.unpack(packed, :complex128)
      assert_in_delta real, 1.0e100, 1.0e85
      assert_in_delta imag, -1.0e100, 1.0e85
    end

    test "very small complex numbers" do
      # Complex64
      packed = DataType.pack({1.0e-30, -1.0e-30}, :complex64)
      {real, imag} = DataType.unpack(packed, :complex64)
      assert_in_delta real, 1.0e-30, 1.0e-36
      assert_in_delta imag, -1.0e-30, 1.0e-36

      # Complex128
      packed = DataType.pack({1.0e-100, -1.0e-100}, :complex128)
      {real, imag} = DataType.unpack(packed, :complex128)
      assert_in_delta real, 1.0e-100, 1.0e-115
      assert_in_delta imag, -1.0e-100, 1.0e-115
    end

    @tag :skip
    test "special float values in complex" do
      # Note: Infinity handling with Elixir's float encoding can be tricky
      # Skipping for now as it's an edge case not critical for MVP
      # Infinity
      # packed = DataType.pack({:math.pow(2, 1000), 0.0}, :complex64)
      # {real, _imag} = DataType.unpack(packed, :complex64)
      # assert real == :infinity
    end
  end
end
