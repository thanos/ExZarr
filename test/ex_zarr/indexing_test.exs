defmodule ExZarr.IndexingTest do
  use ExUnit.Case, async: true

  alias ExZarr.Indexing

  describe "normalize_index/2" do
    test "normalizes positive index within bounds" do
      assert {:ok, 0} = Indexing.normalize_index(0, 10)
      assert {:ok, 5} = Indexing.normalize_index(5, 10)
      assert {:ok, 9} = Indexing.normalize_index(9, 10)
    end

    test "normalizes negative index" do
      assert {:ok, 9} = Indexing.normalize_index(-1, 10)
      assert {:ok, 5} = Indexing.normalize_index(-5, 10)
      assert {:ok, 0} = Indexing.normalize_index(-10, 10)
    end

    test "returns error for out of bounds positive index" do
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(10, 10)
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(15, 10)
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(100, 10)
    end

    test "returns error for out of bounds negative index" do
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(-11, 10)
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(-20, 10)
    end

    test "handles size 1 array" do
      assert {:ok, 0} = Indexing.normalize_index(0, 1)
      assert {:ok, 0} = Indexing.normalize_index(-1, 1)
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(1, 1)
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(-2, 1)
    end

    test "handles large array sizes" do
      size = 1_000_000
      assert {:ok, 999_999} = Indexing.normalize_index(-1, size)
      assert {:ok, 0} = Indexing.normalize_index(-size, size)
      assert {:error, :index_out_of_bounds} = Indexing.normalize_index(size, size)
    end
  end

  describe "normalize_slice/2" do
    test "normalizes basic slice with explicit values" do
      assert {:ok, %{start: 0, stop: 10, step: 1}} =
               Indexing.normalize_slice(%{start: 0, stop: 10, step: 1}, 20)
    end

    test "fills in default start and stop for positive step" do
      assert {:ok, %{start: 0, stop: 20, step: 1}} =
               Indexing.normalize_slice(%{start: nil, stop: nil, step: 1}, 20)
    end

    test "fills in default start and stop for negative step" do
      assert {:ok, %{start: 19, stop: -1, step: -1}} =
               Indexing.normalize_slice(%{start: nil, stop: nil, step: -1}, 20)
    end

    test "normalizes negative start index" do
      assert {:ok, %{start: 15, stop: 20, step: 1}} =
               Indexing.normalize_slice(%{start: -5, stop: nil, step: 1}, 20)
    end

    test "normalizes negative stop index" do
      assert {:ok, %{start: 0, stop: 15, step: 1}} =
               Indexing.normalize_slice(%{start: nil, stop: -5, step: 1}, 20)
    end

    test "normalizes both negative start and stop" do
      assert {:ok, %{start: 10, stop: 15, step: 1}} =
               Indexing.normalize_slice(%{start: -10, stop: -5, step: 1}, 20)
    end

    test "handles step of 2" do
      assert {:ok, %{start: 0, stop: 10, step: 2}} =
               Indexing.normalize_slice(%{start: 0, stop: 10, step: 2}, 20)
    end

    test "handles negative step with explicit bounds" do
      assert {:ok, %{start: 10, stop: 0, step: -1}} =
               Indexing.normalize_slice(%{start: 10, stop: 0, step: -1}, 20)
    end

    test "handles reverse slice with negative step" do
      assert {:ok, %{start: 19, stop: -1, step: -2}} =
               Indexing.normalize_slice(%{start: nil, stop: nil, step: -2}, 20)
    end

    test "handles empty slice (start >= stop with positive step)" do
      # This should still normalize successfully - the slice will just be empty
      assert {:ok, %{start: 10, stop: 5, step: 1}} =
               Indexing.normalize_slice(%{start: 10, stop: 5, step: 1}, 20)
    end

    test "returns error for zero step" do
      assert {:error, _} = Indexing.normalize_slice(%{start: 0, stop: 10, step: 0}, 20)
    end

    test "handles default step of 1" do
      assert {:ok, %{start: 0, stop: 10, step: 1}} =
               Indexing.normalize_slice(%{start: 0, stop: 10}, 20)
    end

    test "normalizes slice on size 1 array" do
      assert {:ok, %{start: 0, stop: 1, step: 1}} =
               Indexing.normalize_slice(%{start: nil, stop: nil, step: 1}, 1)
    end
  end

  describe "slice_indices/1" do
    test "generates indices for basic slice" do
      slice = %{start: 0, stop: 5, step: 1}
      indices = Indexing.slice_indices(slice)
      assert indices == [0, 1, 2, 3, 4]
    end

    test "generates indices with step > 1" do
      slice = %{start: 0, stop: 10, step: 2}
      indices = Indexing.slice_indices(slice)
      assert indices == [0, 2, 4, 6, 8]
    end

    test "generates indices with negative step" do
      slice = %{start: 5, stop: 0, step: -1}
      indices = Indexing.slice_indices(slice)
      assert indices == [5, 4, 3, 2, 1]
    end

    test "generates empty list for empty slice" do
      slice = %{start: 5, stop: 5, step: 1}
      indices = Indexing.slice_indices(slice)
      assert indices == []
    end

    test "handles large step" do
      slice = %{start: 0, stop: 100, step: 25}
      indices = Indexing.slice_indices(slice)
      assert indices == [0, 25, 50, 75]
    end

    test "handles single element" do
      slice = %{start: 5, stop: 6, step: 1}
      indices = Indexing.slice_indices(slice)
      assert indices == [5]
    end

    test "handles negative step with large range" do
      slice = %{start: 100, stop: 0, step: -10}
      indices = Indexing.slice_indices(slice)
      assert length(indices) == 10
      assert hd(indices) == 100
      assert List.last(indices) == 10
    end
  end

  describe "slice_size/1" do
    test "computes size for basic slice" do
      slice = %{start: 0, stop: 10, step: 1}
      assert Indexing.slice_size(slice) == 10
    end

    test "computes size for slice with step > 1" do
      slice = %{start: 0, stop: 10, step: 2}
      assert Indexing.slice_size(slice) == 5
    end

    test "computes size for slice with step = 3" do
      slice = %{start: 0, stop: 10, step: 3}
      assert Indexing.slice_size(slice) == 4
    end

    test "computes size for negative step" do
      slice = %{start: 10, stop: 0, step: -1}
      assert Indexing.slice_size(slice) == 10
    end

    test "computes size for negative step with custom range" do
      slice = %{start: 20, stop: 10, step: -2}
      assert Indexing.slice_size(slice) == 5
    end

    test "returns 0 for empty slice (start >= stop with positive step)" do
      slice = %{start: 10, stop: 10, step: 1}
      assert Indexing.slice_size(slice) == 0

      slice = %{start: 15, stop: 10, step: 1}
      assert Indexing.slice_size(slice) == 0
    end

    test "returns 0 for empty slice (start <= stop with negative step)" do
      slice = %{start: 10, stop: 10, step: -1}
      assert Indexing.slice_size(slice) == 0

      slice = %{start: 10, stop: 15, step: -1}
      assert Indexing.slice_size(slice) == 0
    end

    test "handles large ranges" do
      slice = %{start: 0, stop: 1_000_000, step: 1}
      assert Indexing.slice_size(slice) == 1_000_000
    end

    test "handles single element slice" do
      slice = %{start: 5, stop: 6, step: 1}
      assert Indexing.slice_size(slice) == 1
    end

    test "handles step = 10" do
      slice = %{start: 0, stop: 100, step: 10}
      assert Indexing.slice_size(slice) == 10
    end
  end

  describe "parse_slice_spec/2" do
    test "parses list of ranges for 2D array" do
      specs = [0..9, 5..15]
      shape = {20, 20}

      assert {:ok, result} = Indexing.parse_slice_spec(specs, shape)
      assert is_tuple(result)
    end

    test "parses integer indices" do
      specs = [5, 10]
      shape = {20, 20}

      assert {:ok, result} = Indexing.parse_slice_spec(specs, shape)
      assert is_tuple(result)
    end

    test "handles 1D array" do
      specs = [0..10]
      shape = {100}

      assert {:ok, result} = Indexing.parse_slice_spec(specs, shape)
      assert is_tuple(result)
    end

    test "handles 3D array" do
      specs = [0..5, 10..20, 15..25]
      shape = {30, 30, 30}

      assert {:ok, result} = Indexing.parse_slice_spec(specs, shape)
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end
  end

  describe "validate_fancy_indices/2" do
    test "validates indices within bounds" do
      indices = [0, 5, 9]
      assert :ok = Indexing.validate_fancy_indices(indices, 10)
    end

    test "validates negative indices" do
      indices = [-1, -5, -10]
      assert :ok = Indexing.validate_fancy_indices(indices, 10)
    end

    test "validates mixed positive and negative indices" do
      indices = [0, -1, 5, -5]
      assert :ok = Indexing.validate_fancy_indices(indices, 10)
    end

    test "returns error for index out of bounds" do
      indices = [0, 5, 10]
      assert {:error, _} = Indexing.validate_fancy_indices(indices, 10)
    end

    test "returns error for negative index out of bounds" do
      indices = [0, -11, 5]
      assert {:error, _} = Indexing.validate_fancy_indices(indices, 10)
    end

    test "validates empty list" do
      assert :ok = Indexing.validate_fancy_indices([], 10)
    end

    test "validates single element" do
      assert :ok = Indexing.validate_fancy_indices([5], 10)
      assert {:error, _} = Indexing.validate_fancy_indices([10], 10)
    end

    test "handles large dimension size" do
      indices = [0, 500_000, 999_999]
      assert :ok = Indexing.validate_fancy_indices(indices, 1_000_000)
    end
  end

  describe "validate_boolean_mask/2" do
    test "validates mask with correct size" do
      mask = {true, false, true, false, true}
      assert :ok = Indexing.validate_boolean_mask(mask, 5)
    end

    test "validates all true mask" do
      mask = {true, true, true}
      assert :ok = Indexing.validate_boolean_mask(mask, 3)
    end

    test "validates all false mask" do
      mask = {false, false, false}
      assert :ok = Indexing.validate_boolean_mask(mask, 3)
    end

    test "returns error for size mismatch" do
      mask = {true, false, true}
      assert {:error, :mask_size_mismatch} = Indexing.validate_boolean_mask(mask, 5)
    end

    test "validates empty mask" do
      mask = {}
      assert :ok = Indexing.validate_boolean_mask(mask, 0)
    end

    test "returns error for empty mask with non-zero dimension" do
      mask = {}
      assert {:error, :mask_size_mismatch} = Indexing.validate_boolean_mask(mask, 5)
    end

    test "handles large masks" do
      mask = List.duplicate(true, 10_000) |> List.to_tuple()
      assert :ok = Indexing.validate_boolean_mask(mask, 10_000)
    end
  end

  describe "mask_to_indices/1" do
    test "converts simple boolean mask" do
      mask = {true, false, true, false, true}
      assert Indexing.mask_to_indices(mask) == [0, 2, 4]
    end

    test "converts all true mask" do
      mask = {true, true, true}
      assert Indexing.mask_to_indices(mask) == [0, 1, 2]
    end

    test "converts all false mask" do
      mask = {false, false, false}
      assert Indexing.mask_to_indices(mask) == []
    end

    test "converts mask with single true" do
      mask = {false, false, true, false}
      assert Indexing.mask_to_indices(mask) == [2]
    end

    test "converts empty mask" do
      mask = {}
      assert Indexing.mask_to_indices(mask) == []
    end

    test "converts large mask" do
      mask_list = for i <- 0..99, do: rem(i, 2) == 0
      mask = List.to_tuple(mask_list)

      indices = Indexing.mask_to_indices(mask)
      assert length(indices) == 50
      assert Enum.all?(indices, fn i -> rem(i, 2) == 0 end)
    end

    test "handles mask with first and last true" do
      mask = {true, false, false, false, true}
      assert Indexing.mask_to_indices(mask) == [0, 4]
    end

    test "handles alternating pattern" do
      mask = {true, false, true, false, true, false}
      assert Indexing.mask_to_indices(mask) == [0, 2, 4]
    end
  end

  describe "compute_block_indices/3" do
    test "computes blocks for evenly divisible range" do
      blocks = Indexing.compute_block_indices(0, 30, 10)
      assert blocks == [{0, 10}, {10, 20}, {20, 30}]
    end

    test "computes blocks with remainder" do
      blocks = Indexing.compute_block_indices(5, 25, 10)
      assert is_list(blocks)
      assert blocks != []
    end

    test "computes single block for small range" do
      blocks = Indexing.compute_block_indices(0, 5, 10)
      assert blocks == [{0, 5}]
    end

    test "handles start != 0" do
      blocks = Indexing.compute_block_indices(10, 40, 10)
      assert is_list(blocks)
      {first_start, _} = hd(blocks)
      {_, last_stop} = List.last(blocks)
      assert first_start >= 10
      assert last_stop <= 40
    end

    test "handles block size larger than range" do
      blocks = Indexing.compute_block_indices(0, 5, 100)
      assert blocks == [{0, 5}]
    end

    test "handles various ranges" do
      blocks = Indexing.compute_block_indices(0, 100, 25)
      assert is_list(blocks)
      assert length(blocks) == 4
    end
  end
end
