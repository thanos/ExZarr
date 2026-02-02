defmodule ExZarr.NewAPITest do
  use ExUnit.Case, async: true

  describe "ExZarr.metadata/1" do
    test "returns array metadata" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {25, 25},
          dtype: :float64,
          storage: :memory
        )

      metadata = ExZarr.metadata(array)

      assert metadata.shape == {100, 100}
      assert metadata.chunks == {25, 25}
      assert metadata.dtype == :float64
    end
  end

  describe "ExZarr.slice/2" do
    test "reads slice and returns Nx tensor" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {50, 50},
          dtype: :int32,
          storage: :memory
        )

      # Write data
      tensor = Nx.iota({100, 100}, type: {:s, 32})
      :ok = ExZarr.Nx.to_zarr(tensor, array)

      # Read slice
      {:ok, slice} = ExZarr.slice(array, {0..9, 0..9})

      assert Nx.shape(slice) == {10, 10}
      assert Nx.type(slice) == {:s, 32}

      # Verify data matches
      expected = Nx.slice(tensor, [0, 0], [10, 10])
      assert Nx.all(Nx.equal(slice, expected)) |> Nx.to_number() == 1
    end

    test "reads single row" do
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {25, 25},
          dtype: :float64,
          storage: :memory
        )

      tensor = Nx.iota({50, 50}, type: {:f, 64})
      :ok = ExZarr.Nx.to_zarr(tensor, array)

      {:ok, row} = ExZarr.slice(array, {0..0, 0..49})

      assert Nx.shape(row) == {1, 50}
    end

    test "reads square region" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {25, 25},
          dtype: :float64,
          storage: :memory
        )

      tensor = Nx.iota({100, 100}, type: {:f, 64})
      :ok = ExZarr.Nx.to_zarr(tensor, array)

      {:ok, square} = ExZarr.slice(array, {10..19, 10..19})

      assert Nx.shape(square) == {10, 10}
    end
  end

  describe "ExZarr.Nx.to_zarr/2" do
    test "writes tensor to array" do
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {25, 25},
          dtype: :float64,
          storage: :memory
        )

      tensor = Nx.iota({50, 50}, type: {:f, 64})
      assert :ok = ExZarr.Nx.to_zarr(tensor, array)

      # Verify by reading back
      {:ok, read_tensor} = ExZarr.Nx.to_tensor(array)
      assert Nx.all(Nx.equal(tensor, read_tensor)) |> Nx.to_number() == 1
    end

    test "returns error for shape mismatch" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {25, 25},
          dtype: :int32,
          storage: :memory
        )

      bad_tensor = Nx.iota({50, 50}, type: {:s, 32})

      assert {:error, msg} = ExZarr.Nx.to_zarr(bad_tensor, array)
      assert msg =~ "Shape mismatch"
    end

    test "returns error for dtype mismatch" do
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {25, 25},
          dtype: :int32,
          storage: :memory
        )

      wrong_dtype_tensor = Nx.iota({50, 50}, type: {:f, 64})

      assert {:error, msg} = ExZarr.Nx.to_zarr(wrong_dtype_tensor, array)
      assert msg =~ "Dtype mismatch"
    end
  end
end
