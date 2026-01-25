defmodule ExZarr.ChunkGridIntegrationTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array
  alias ExZarr.ChunkGrid.{Irregular, Regular}

  describe "Array with Regular chunk grid" do
    test "creates array with regular grid" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Should create with regular chunks
      assert array.chunks == {10, 20}

      # Chunk grid not explicitly set for backward compatibility
      assert is_nil(array.chunk_grid_module)
      assert is_nil(array.chunk_grid_state)
    end

    test "get_chunk_shape returns regular chunk shape" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # All chunks should return the same shape
      assert Array.get_chunk_shape(array, {0, 0}) == {10, 20}
      assert Array.get_chunk_shape(array, {5, 5}) == {10, 20}
      assert Array.get_chunk_shape(array, {9, 9}) == {10, 20}
    end

    test "get_chunk_bounds calculates correct bounds" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # First chunk
      assert Array.get_chunk_bounds(array, {0, 0}) == {{0, 0}, {10, 20}}

      # Middle chunk
      assert Array.get_chunk_bounds(array, {5, 5}) == {{50, 100}, {60, 120}}

      # Edge chunk
      assert Array.get_chunk_bounds(array, {9, 9}) == {{90, 180}, {100, 200}}
    end

    test "reads and writes data correctly" do
      {:ok, array} =
        ExZarr.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Write data
      data = for i <- 0..24, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {5, 5})

      # Read back
      assert {:ok, read_data} = Array.get_slice(array, start: {0, 0}, stop: {5, 5})
      assert read_data == data
    end
  end

  describe "Array with explicit Regular chunk grid" do
    test "creates array with explicit regular grid module" do
      # Create array and set chunk grid explicitly
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Set up regular grid explicitly
      {:ok, grid_state} = Regular.init(%{"chunk_shape" => [10, 20]})
      grid_state = Regular.set_array_shape(grid_state, {100, 200})

      array = %{
        array
        | chunk_grid_module: Regular,
          chunk_grid_state: grid_state
      }

      # Should use chunk grid
      assert array.chunk_grid_module == Regular
      assert Array.get_chunk_shape(array, {0, 0}) == {10, 20}
    end

    test "get_chunk_shape returns correct shapes for edge chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {95, 185},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Set up regular grid
      {:ok, grid_state} = Regular.init(%{"chunk_shape" => [10, 20]})
      grid_state = Regular.set_array_shape(grid_state, {95, 185})

      array = %{
        array
        | chunk_grid_module: Regular,
          chunk_grid_state: grid_state
      }

      # Regular chunk
      assert Array.get_chunk_shape(array, {0, 0}) == {10, 20}

      # Edge chunk in first dimension: 95 - 90 = 5
      assert Array.get_chunk_shape(array, {9, 0}) == {5, 20}

      # Edge chunk in second dimension: 185 - 180 = 5
      assert Array.get_chunk_shape(array, {0, 9}) == {10, 5}

      # Edge chunk in both dimensions
      assert Array.get_chunk_shape(array, {9, 9}) == {5, 5}
    end
  end

  describe "Array with Irregular chunk grid" do
    test "creates array with irregular grid using chunk_sizes" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Set up irregular grid
      {:ok, grid_state} =
        Irregular.init(%{
          "chunk_sizes" => [
            [50, 50],
            [100, 100]
          ]
        })

      grid_state = Irregular.set_array_shape(grid_state, {100, 200})

      array = %{
        array
        | chunk_grid_module: Irregular,
          chunk_grid_state: grid_state
      }

      # Should use irregular chunk sizes
      assert Array.get_chunk_shape(array, {0, 0}) == {50, 100}
      assert Array.get_chunk_shape(array, {0, 1}) == {50, 100}
      assert Array.get_chunk_shape(array, {1, 0}) == {50, 100}
      assert Array.get_chunk_shape(array, {1, 1}) == {50, 100}
    end

    test "get_chunk_bounds calculates correct bounds for irregular chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 200},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Set up irregular grid
      {:ok, grid_state} =
        Irregular.init(%{
          "chunk_sizes" => [
            [50, 50],
            [100, 100]
          ]
        })

      grid_state = Irregular.set_array_shape(grid_state, {100, 200})

      array = %{
        array
        | chunk_grid_module: Irregular,
          chunk_grid_state: grid_state
      }

      # First chunk: starts at {0, 0}, size is {50, 100}
      assert Array.get_chunk_bounds(array, {0, 0}) == {{0, 0}, {50, 100}}

      # Second chunk in first dimension: starts at {50, 0}, size is {50, 100}
      assert Array.get_chunk_bounds(array, {1, 0}) == {{50, 0}, {100, 100}}

      # Second chunk in second dimension: starts at {0, 100}, size is {50, 100}
      assert Array.get_chunk_bounds(array, {0, 1}) == {{0, 100}, {50, 200}}
    end

    test "creates array with irregular grid using chunk_shapes map" do
      {:ok, array} =
        ExZarr.create(
          shape: {75, 150},
          chunks: {10, 20},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # Set up irregular grid with explicit shapes
      {:ok, grid_state} =
        Irregular.init(%{
          "chunk_shapes" => %{
            "{0,0}" => [50, 100],
            "{0,1}" => [50, 50],
            "{1,0}" => [25, 100],
            "{1,1}" => [25, 50]
          }
        })

      grid_state = Irregular.set_array_shape(grid_state, {75, 150})

      array = %{
        array
        | chunk_grid_module: Irregular,
          chunk_grid_state: grid_state
      }

      # Should use explicit chunk shapes
      assert Array.get_chunk_shape(array, {0, 0}) == {50, 100}
      assert Array.get_chunk_shape(array, {0, 1}) == {50, 50}
      assert Array.get_chunk_shape(array, {1, 0}) == {25, 100}
      assert Array.get_chunk_shape(array, {1, 1}) == {25, 50}
    end
  end

  describe "Real-world scenarios with irregular grids" do
    test "climate data with monthly time chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {365, 180, 360},
          chunks: {30, 90, 180},
          dtype: :float32,
          zarr_version: 3,
          storage: :memory
        )

      # Set up irregular grid for monthly chunks
      {:ok, grid_state} =
        Irregular.init(%{
          "chunk_sizes" => [
            # Days per month
            [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
            # Latitude (2 chunks)
            [90, 90],
            # Longitude (2 chunks)
            [180, 180]
          ]
        })

      grid_state = Irregular.set_array_shape(grid_state, {365, 180, 360})

      array = %{
        array
        | chunk_grid_module: Irregular,
          chunk_grid_state: grid_state
      }

      # January: 31 days
      assert Array.get_chunk_shape(array, {0, 0, 0}) == {31, 90, 180}

      # February: 28 days
      assert Array.get_chunk_shape(array, {1, 0, 0}) == {28, 90, 180}

      # March: 31 days
      assert Array.get_chunk_shape(array, {2, 0, 0}) == {31, 90, 180}

      # Verify bounds for February
      assert Array.get_chunk_bounds(array, {1, 0, 0}) == {{31, 0, 0}, {59, 90, 180}}
    end

    test "adaptive resolution spatial data" do
      {:ok, array} =
        ExZarr.create(
          shape: {200, 300},
          chunks: {50, 100},
          dtype: :float64,
          zarr_version: 3,
          storage: :memory
        )

      # Set up adaptive resolution grid
      {:ok, grid_state} =
        Irregular.init(%{
          "chunk_shapes" => %{
            # High resolution center (fine grid)
            "{0,0}" => [50, 50],
            "{0,1}" => [50, 50],
            "{0,2}" => [50, 50],
            "{0,3}" => [50, 50],
            # Medium resolution
            "{1,0}" => [50, 100],
            "{1,1}" => [50, 100],
            "{1,2}" => [50, 100],
            # Coarse resolution edges
            "{2,0}" => [50, 150],
            "{2,1}" => [50, 150],
            # Very coarse corner
            "{3,0}" => [50, 300]
          }
        })

      grid_state = Irregular.set_array_shape(grid_state, {200, 300})

      array = %{
        array
        | chunk_grid_module: Irregular,
          chunk_grid_state: grid_state
      }

      # Center region: high resolution
      assert Array.get_chunk_shape(array, {0, 0}) == {50, 50}
      assert Array.get_chunk_shape(array, {0, 1}) == {50, 50}

      # Middle region: medium resolution
      assert Array.get_chunk_shape(array, {1, 0}) == {50, 100}

      # Edge region: coarse resolution
      assert Array.get_chunk_shape(array, {2, 0}) == {50, 150}

      # Corner: very coarse
      assert Array.get_chunk_shape(array, {3, 0}) == {50, 300}
    end
  end

  describe "Backward compatibility" do
    test "existing code works without chunk grids" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        )

      # No chunk grid set
      assert is_nil(array.chunk_grid_module)
      assert is_nil(array.chunk_grid_state)

      # All existing operations work
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      assert :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
      assert {:ok, ^data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})

      # Chunk operations work
      assert Array.get_chunk_shape(array, {0, 0}) == {10, 10}
      assert Array.get_chunk_bounds(array, {0, 0}) == {{0, 0}, {10, 10}}
    end
  end
end
