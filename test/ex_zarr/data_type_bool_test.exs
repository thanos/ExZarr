defmodule ExZarr.DataType.BoolTest do
  use ExUnit.Case, async: true

  alias ExZarr.{Array, DataType}

  doctest ExZarr.DataType

  describe "bool type" do
    test "supported type includes :bool" do
      assert :bool in DataType.supported_types()
    end

    test "bool? predicate works" do
      assert DataType.bool?(:bool)
      refute DataType.bool?(:int32)
      refute DataType.bool?(:float64)
      refute DataType.bool?(:complex64)
    end

    test "itemsize returns 1 byte" do
      assert DataType.itemsize(:bool) == 1
      assert DataType.itemsize("bool") == 1
    end

    test "v3 conversion" do
      assert DataType.to_v3(:bool) == "bool"
      assert DataType.from_v3("bool") == :bool
    end

    test "v2 conversion" do
      assert DataType.to_v2(:bool) == "|b1"
      assert DataType.from_v2("|b1") == :bool
      assert DataType.from_v2("b1") == :bool
    end

    test "validate accepts bool" do
      assert DataType.validate(:bool) == :ok
      assert DataType.validate("bool") == :ok
      assert DataType.validate("|b1") == :ok
    end
  end

  describe "bool pack/unpack" do
    test "pack true to 1" do
      assert DataType.pack(true, :bool) == <<1>>
    end

    test "pack false to 0" do
      assert DataType.pack(false, :bool) == <<0>>
    end

    test "pack 0 to 0" do
      assert DataType.pack(0, :bool) == <<0>>
    end

    test "pack non-zero to 1" do
      assert DataType.pack(1, :bool) == <<1>>
      assert DataType.pack(42, :bool) == <<1>>
      assert DataType.pack(-1, :bool) == <<1>>
    end

    test "unpack 0 to false" do
      assert DataType.unpack(<<0>>, :bool) == false
    end

    test "unpack non-zero to true" do
      assert DataType.unpack(<<1>>, :bool) == true
      assert DataType.unpack(<<255>>, :bool) == true
      assert DataType.unpack(<<42>>, :bool) == true
    end

    test "round-trip true" do
      packed = DataType.pack(true, :bool)
      assert DataType.unpack(packed, :bool) == true
    end

    test "round-trip false" do
      packed = DataType.pack(false, :bool)
      assert DataType.unpack(packed, :bool) == false
    end
  end

  describe "bool array operations" do
    setup do
      tmp_dir = "/tmp/ex_zarr_bool_test_#{System.unique_integer()}"
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "create bool array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_array")
        )

      assert array.metadata.dtype == :bool
      assert array.metadata.chunks == {5}
    end

    test "write and read bool array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_rw")
        )

      # Write boolean data
      data = <<1, 0, 1, 1, 0, 0, 1, 0, 1, 0>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {10})

      # Read back
      {:ok, result} = Array.get_slice(array, start: {0}, stop: {10})
      assert result == data
    end

    test "write and read 2D bool array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {3, 4},
          chunks: {2, 2},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_2d")
        )

      # 3x4 = 12 booleans
      data = <<1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 0, 0>>
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {3, 4})

      {:ok, result} = Array.get_slice(array, start: {0, 0}, stop: {3, 4})
      assert result == data
    end

    test "bool array with fill value", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {5},
          chunks: {5},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_fill"),
          fill_value: 0
        )

      # Read before writing - should get fill value
      {:ok, result} = Array.get_slice(array, start: {0}, stop: {5})

      # All should be 0 (false)
      assert result == <<0, 0, 0, 0, 0>>
    end

    test "partial write to bool array", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10},
          chunks: {5},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_partial"),
          fill_value: 0
        )

      # Write to middle
      data = <<1, 1, 1>>
      :ok = Array.set_slice(array, data, start: {3}, stop: {6})

      # Read full array
      {:ok, result} = Array.get_slice(array, start: {0}, stop: {10})

      # Should be: 0,0,0,1,1,1,0,0,0,0
      assert result == <<0, 0, 0, 1, 1, 1, 0, 0, 0, 0>>
    end
  end

  describe "bool type interoperability" do
    test "bool type name matches Python zarr" do
      # Python zarr uses 'bool' as the type name
      assert DataType.to_v3(:bool) == "bool"
    end

    test "bool numpy dtype matches Python" do
      # NumPy uses '|b1' for bool (1 byte, byte order not applicable)
      assert DataType.to_v2(:bool) == "|b1"
    end

    test "bool size matches NumPy" do
      # NumPy bool is 1 byte
      assert DataType.itemsize(:bool) == 1
    end
  end

  describe "bool edge cases" do
    test "bool with compression", %{} do
      tmp_dir = "/tmp/ex_zarr_bool_compress_#{System.unique_integer()}"
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, array} =
        Array.create(
          shape: {100},
          chunks: {50},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_compressed"),
          compressor: :zstd
        )

      # Create pattern: alternating true/false
      data = for i <- 0..99, into: <<>>, do: <<rem(i, 2)>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {100})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {100})
      assert result == data
    end

    test "bool array all true" do
      tmp_dir = "/tmp/ex_zarr_bool_all_true_#{System.unique_integer()}"
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, array} =
        Array.create(
          shape: {20},
          chunks: {10},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_all_true")
        )

      data = for _ <- 1..20, into: <<>>, do: <<1>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {20})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {20})
      assert result == data
    end

    test "bool array all false" do
      tmp_dir = "/tmp/ex_zarr_bool_all_false_#{System.unique_integer()}"
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, array} =
        Array.create(
          shape: {20},
          chunks: {10},
          dtype: :bool,
          storage: :filesystem,
          path: Path.join(tmp_dir, "bool_all_false")
        )

      data = for _ <- 1..20, into: <<>>, do: <<0>>
      :ok = Array.set_slice(array, data, start: {0}, stop: {20})

      {:ok, result} = Array.get_slice(array, start: {0}, stop: {20})
      assert result == data
    end
  end
end
