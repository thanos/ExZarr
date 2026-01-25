defmodule ExZarr.ChunkGridTest do
  use ExUnit.Case, async: true

  alias ExZarr.ChunkGrid
  alias ExZarr.ChunkGrid.Irregular
  alias ExZarr.ChunkGrid.Regular

  describe "Regular chunk grid" do
    test "initializes from configuration" do
      config = %{"chunk_shape" => [10, 20, 30]}

      assert {:ok, grid} = Regular.init(config)
      assert grid.chunk_shape == {10, 20, 30}
    end

    test "accepts tuple chunk shape" do
      config = %{"chunk_shape" => {10, 20}}

      assert {:ok, grid} = Regular.init(config)
      assert grid.chunk_shape == {10, 20}
    end

    test "accepts atom key" do
      config = %{chunk_shape: [15, 25]}

      assert {:ok, grid} = Regular.init(config)
      assert grid.chunk_shape == {15, 25}
    end

    test "returns chunk shape for regular chunks" do
      config = %{"chunk_shape" => [10, 20]}
      {:ok, grid} = Regular.init(config)
      grid = Regular.set_array_shape(grid, {100, 100})

      assert Regular.chunk_shape({0, 0}, grid) == {10, 20}
      assert Regular.chunk_shape({5, 3}, grid) == {10, 20}
    end

    test "returns adjusted shape for edge chunks" do
      config = %{"chunk_shape" => [10, 20]}
      {:ok, grid} = Regular.init(config)
      grid = Regular.set_array_shape(grid, {25, 55})

      # Last chunk in first dimension: 25 - 20 = 5
      assert Regular.chunk_shape({2, 0}, grid) == {5, 20}

      # Last chunk in second dimension: 55 - 40 = 15
      assert Regular.chunk_shape({0, 2}, grid) == {10, 15}

      # Edge chunk in both dimensions
      assert Regular.chunk_shape({2, 2}, grid) == {5, 15}
    end

    test "calculates chunk count" do
      config = %{"chunk_shape" => [10, 20]}
      {:ok, grid} = Regular.init(config)
      grid = Regular.set_array_shape(grid, {25, 55})

      # (25 + 9) / 10 = 3 chunks, (55 + 19) / 20 = 3 chunks
      # Total: 3 * 3 = 9
      assert Regular.chunk_count(grid) == 9
    end

    test "calculates chunk count for evenly divisible array" do
      config = %{"chunk_shape" => [10, 20]}
      {:ok, grid} = Regular.init(config)
      grid = Regular.set_array_shape(grid, {30, 40})

      # 3 * 2 = 6
      assert Regular.chunk_count(grid) == 6
    end

    test "generates all chunk indices" do
      config = %{"chunk_shape" => [10, 10]}
      {:ok, grid} = Regular.init(config)
      grid = Regular.set_array_shape(grid, {25, 15})

      indices = Regular.all_chunk_indices(grid)

      assert length(indices) == 6
      assert {0, 0} in indices
      assert {0, 1} in indices
      assert {1, 0} in indices
      assert {1, 1} in indices
      assert {2, 0} in indices
      assert {2, 1} in indices
    end

    test "validates configuration" do
      config = %{"chunk_shape" => [10, 20]}
      array_shape = {100, 100}

      assert :ok = Regular.validate(config, array_shape)
    end

    test "rejects missing chunk_shape" do
      config = %{}
      array_shape = {100, 100}

      assert {:error, {:missing_chunk_shape, _}} = Regular.validate(config, array_shape)
    end

    test "rejects dimension mismatch" do
      config = %{"chunk_shape" => [10, 20]}
      array_shape = {100, 100, 100}

      assert {:error, {:dimension_mismatch, _}} = Regular.validate(config, array_shape)
    end

    test "rejects non-positive chunk dimensions" do
      config = %{"chunk_shape" => [10, 0]}
      array_shape = {100, 100}

      assert {:error, {:invalid_chunk_shape, _}} = Regular.validate(config, array_shape)
    end
  end

  describe "Irregular chunk grid - chunk_sizes" do
    test "initializes from chunk_sizes" do
      config = %{
        "chunk_sizes" => [
          [50, 50, 25],
          [100, 50, 50]
        ]
      }

      assert {:ok, grid} = Irregular.init(config)
      assert grid.chunk_sizes == [[50, 50, 25], [100, 50, 50]]
    end

    test "returns chunk shape for specific indices" do
      config = %{
        "chunk_sizes" => [
          [50, 25],
          [100, 50]
        ]
      }

      {:ok, grid} = Irregular.init(config)
      grid = Irregular.set_array_shape(grid, {75, 150})

      assert Irregular.chunk_shape({0, 0}, grid) == {50, 100}
      assert Irregular.chunk_shape({0, 1}, grid) == {50, 50}
      assert Irregular.chunk_shape({1, 0}, grid) == {25, 100}
      assert Irregular.chunk_shape({1, 1}, grid) == {25, 50}
    end

    test "calculates chunk count from chunk_sizes" do
      config = %{
        "chunk_sizes" => [
          [50, 50, 25],
          [100, 50, 50]
        ]
      }

      {:ok, grid} = Irregular.init(config)

      # 3 * 3 = 9 chunks
      assert Irregular.chunk_count(grid) == 9
    end

    test "generates all chunk indices from chunk_sizes" do
      config = %{
        "chunk_sizes" => [
          [50, 50],
          [100, 50]
        ]
      }

      {:ok, grid} = Irregular.init(config)

      indices = Irregular.all_chunk_indices(grid)

      assert length(indices) == 4
      assert {0, 0} in indices
      assert {0, 1} in indices
      assert {1, 0} in indices
      assert {1, 1} in indices
    end

    test "validates chunk_sizes configuration" do
      config = %{
        "chunk_sizes" => [
          [50, 50],
          [100, 100]
        ]
      }

      array_shape = {100, 200}

      assert :ok = Irregular.validate(config, array_shape)
    end

    test "rejects chunk_sizes dimension mismatch" do
      config = %{
        "chunk_sizes" => [
          [50, 50]
        ]
      }

      array_shape = {100, 200}

      assert {:error, {:dimension_mismatch, _}} = Irregular.validate(config, array_shape)
    end

    test "rejects chunk_sizes that don't sum to array dimensions" do
      config = %{
        "chunk_sizes" => [
          [50, 60],
          [100, 100]
        ]
      }

      array_shape = {100, 200}

      assert {:error, {:size_mismatch, _}} = Irregular.validate(config, array_shape)
    end
  end

  describe "Irregular chunk grid - chunk_shapes" do
    test "initializes from chunk_shapes map" do
      config = %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100],
          "{0,1}" => [50, 50],
          "{1,0}" => [25, 100],
          "{1,1}" => [25, 50]
        }
      }

      assert {:ok, grid} = Irregular.init(config)
      assert is_map(grid.chunk_shapes_map)
      assert map_size(grid.chunk_shapes_map) == 4
    end

    test "returns chunk shape from map" do
      config = %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100],
          "{0,1}" => [50, 50],
          "{1,0}" => [30, 100]
        }
      }

      {:ok, grid} = Irregular.init(config)

      assert Irregular.chunk_shape({0, 0}, grid) == {50, 100}
      assert Irregular.chunk_shape({0, 1}, grid) == {50, 50}
      assert Irregular.chunk_shape({1, 0}, grid) == {30, 100}
    end

    test "calculates chunk count from map" do
      config = %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100],
          "{0,1}" => [50, 50],
          "{1,0}" => [25, 100]
        }
      }

      {:ok, grid} = Irregular.init(config)

      assert Irregular.chunk_count(grid) == 3
    end

    test "generates all chunk indices from map" do
      config = %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100],
          "{0,1}" => [50, 50],
          "{1,0}" => [25, 100]
        }
      }

      {:ok, grid} = Irregular.init(config)

      indices = Irregular.all_chunk_indices(grid)

      assert length(indices) == 3
      assert {0, 0} in indices
      assert {0, 1} in indices
      assert {1, 0} in indices
    end

    test "validates chunk_shapes configuration" do
      config = %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100],
          "{0,1}" => [50, 100]
        }
      }

      array_shape = {100, 200}

      assert :ok = Irregular.validate(config, array_shape)
    end

    test "rejects empty chunk_shapes" do
      config = %{
        "chunk_shapes" => %{}
      }

      array_shape = {100, 200}

      assert {:error, {:invalid_chunk_shapes, _}} = Irregular.validate(config, array_shape)
    end

    test "rejects chunk shape dimension mismatch" do
      config = %{
        "chunk_shapes" => %{
          "{0,0}" => [50, 100, 10]
        }
      }

      array_shape = {100, 200}

      assert {:error, {:dimension_mismatch, _}} = Irregular.validate(config, array_shape)
    end
  end

  describe "ChunkGrid.parse/1" do
    test "parses regular chunk grid" do
      config = %{
        "name" => "regular",
        "configuration" => %{"chunk_shape" => [10, 20]}
      }

      assert {:ok, {module, state}} = ChunkGrid.parse(config)
      assert module == Regular
      assert state.chunk_shape == {10, 20}
    end

    test "parses irregular chunk grid with chunk_sizes" do
      config = %{
        "name" => "irregular",
        "configuration" => %{
          "chunk_sizes" => [[50, 50], [100, 100]]
        }
      }

      assert {:ok, {module, state}} = ChunkGrid.parse(config)
      assert module == Irregular
      assert state.chunk_sizes == [[50, 50], [100, 100]]
    end

    test "parses irregular chunk grid with chunk_shapes" do
      config = %{
        "name" => "irregular",
        "configuration" => %{
          "chunk_shapes" => %{
            "{0,0}" => [50, 100]
          }
        }
      }

      assert {:ok, {module, state}} = ChunkGrid.parse(config)
      assert module == Irregular
      assert is_map(state.chunk_shapes_map)
    end

    test "rejects unknown chunk grid type" do
      config = %{
        "name" => "custom",
        "configuration" => %{}
      }

      assert {:error, {:unknown_chunk_grid, "custom"}} = ChunkGrid.parse(config)
    end

    test "rejects invalid configuration" do
      config = %{"name" => "regular"}

      assert {:error, _} = ChunkGrid.parse(config)
    end
  end

  describe "ChunkGrid.validate/2" do
    test "validates regular chunk grid" do
      config = %{
        "name" => "regular",
        "configuration" => %{"chunk_shape" => [10, 20]}
      }

      array_shape = {100, 200}

      assert :ok = ChunkGrid.validate(config, array_shape)
    end

    test "validates irregular chunk grid" do
      config = %{
        "name" => "irregular",
        "configuration" => %{
          "chunk_sizes" => [[50, 50], [100, 100]]
        }
      }

      array_shape = {100, 200}

      assert :ok = ChunkGrid.validate(config, array_shape)
    end

    test "rejects unknown chunk grid type" do
      config = %{
        "name" => "unknown",
        "configuration" => %{}
      }

      array_shape = {100, 200}

      assert {:error, {:unknown_chunk_grid, "unknown"}} =
               ChunkGrid.validate(config, array_shape)
    end
  end

  describe "real-world scenarios" do
    test "variable resolution climate data" do
      # Climate model with high resolution near surface, lower at altitude
      config = %{
        "chunk_sizes" => [
          # Time: monthly chunks
          [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
          # Latitude: uniform
          [90, 90],
          # Longitude: uniform
          [180, 180]
        ]
      }

      {:ok, grid} = Irregular.init(config)
      grid = Irregular.set_array_shape(grid, {365, 180, 360})

      # January chunk
      assert Irregular.chunk_shape({0, 0, 0}, grid) == {31, 90, 180}
      # February chunk
      assert Irregular.chunk_shape({1, 0, 0}, grid) == {28, 90, 180}
      # March chunk
      assert Irregular.chunk_shape({2, 0, 0}, grid) == {31, 90, 180}

      assert Irregular.chunk_count(grid) == 12 * 2 * 2
    end

    test "adaptive spatial resolution" do
      # Region of interest has finer chunks
      config = %{
        "chunk_shapes" => %{
          # High resolution center
          "{0,0}" => [50, 50],
          "{0,1}" => [50, 50],
          "{1,0}" => [50, 50],
          "{1,1}" => [50, 50],
          # Lower resolution edges
          "{0,2}" => [50, 200],
          "{1,2}" => [50, 200],
          "{2,0}" => [100, 50],
          "{2,1}" => [100, 50],
          "{2,2}" => [100, 200]
        }
      }

      {:ok, grid} = Irregular.init(config)

      # Center has fine resolution
      assert Irregular.chunk_shape({0, 0}, grid) == {50, 50}
      # Edge has coarse resolution
      assert Irregular.chunk_shape({2, 2}, grid) == {100, 200}

      assert Irregular.chunk_count(grid) == 9
    end
  end
end
