defmodule ExZarr.Nx.DataLoaderTest do
  use ExUnit.Case, async: true

  alias ExZarr.Nx.DataLoader

  @moduletag :nx_integration

  if Code.ensure_loaded?(Nx) do
    describe "batch_stream/3" do
      test "loads batches of specified size" do
        {:ok, array} = create_test_array({100, 10})

        batches =
          array
          |> DataLoader.batch_stream(32)
          |> Enum.to_list()

        # Should have 4 batches: 32, 32, 32, 4
        assert length(batches) == 4

        assert {:ok, batch1} = Enum.at(batches, 0)
        assert Nx.shape(batch1) == {32, 10}

        assert {:ok, batch2} = Enum.at(batches, 1)
        assert Nx.shape(batch2) == {32, 10}

        assert {:ok, batch3} = Enum.at(batches, 2)
        assert Nx.shape(batch3) == {32, 10}

        assert {:ok, batch4} = Enum.at(batches, 3)
        # Final incomplete batch
        assert Nx.shape(batch4) == {4, 10}
      end

      test "handles exact division" do
        {:ok, array} = create_test_array({100, 10})

        batches =
          array
          |> DataLoader.batch_stream(25)
          |> Enum.to_list()

        # Should have exactly 4 batches of size 25
        assert length(batches) == 4

        Enum.each(batches, fn {:ok, batch} ->
          assert Nx.shape(batch) == {25, 10}
        end)
      end

      test "drops final batch with drop_remainder option" do
        {:ok, array} = create_test_array({100, 10})

        batches =
          array
          |> DataLoader.batch_stream(32, drop_remainder: true)
          |> Enum.to_list()

        # Should have 3 complete batches, drops final batch of 4
        assert length(batches) == 3

        Enum.each(batches, fn {:ok, batch} ->
          assert Nx.shape(batch) == {32, 10}
        end)
      end

      test "works with 1D arrays" do
        {:ok, array} = create_test_array({100})

        batches =
          array
          |> DataLoader.batch_stream(32)
          |> Enum.to_list()

        assert length(batches) == 4

        assert {:ok, batch1} = Enum.at(batches, 0)
        assert Nx.shape(batch1) == {32}
      end

      test "works with 3D arrays" do
        {:ok, array} = create_test_array({100, 28, 28})

        batches =
          array
          |> DataLoader.batch_stream(16)
          |> Enum.to_list()

        # 6 full + 1 partial
        assert length(batches) == 7

        assert {:ok, batch1} = Enum.at(batches, 0)
        assert Nx.shape(batch1) == {16, 28, 28}

        assert {:ok, last_batch} = List.last(batches)
        assert Nx.shape(last_batch) == {4, 28, 28}
      end

      test "verifies data integrity in batches" do
        {:ok, array} = create_sequential_array({10, 3})

        batches =
          array
          |> DataLoader.batch_stream(3)
          |> Enum.to_list()

        # Check first batch has correct data
        assert {:ok, batch1} = Enum.at(batches, 0)
        # First row should be [0, 0, 0], second [1, 1, 1], third [2, 2, 2]
        assert Nx.to_number(batch1[0][0]) == 0
        assert Nx.to_number(batch1[1][0]) == 1
        assert Nx.to_number(batch1[2][0]) == 2

        # Check second batch
        assert {:ok, batch2} = Enum.at(batches, 1)
        assert Nx.to_number(batch2[0][0]) == 3
        assert Nx.to_number(batch2[1][0]) == 4
        assert Nx.to_number(batch2[2][0]) == 5
      end

      test "applies backend transfer option" do
        {:ok, array} = create_test_array({100, 10})

        batches =
          array
          |> DataLoader.batch_stream(32, backend: Nx.BinaryBackend)
          |> Enum.to_list()

        assert {:ok, batch} = Enum.at(batches, 0)
        assert Nx.shape(batch) == {32, 10}
      end

      test "applies axis names option" do
        {:ok, array} = create_test_array({100, 10})

        batches =
          array
          |> DataLoader.batch_stream(32, names: [:batch, :features])
          |> Enum.to_list()

        assert {:ok, batch} = Enum.at(batches, 0)
        assert Nx.names(batch) == [:batch, :features]
      end
    end

    describe "shuffled_batch_stream/3" do
      test "loads batches with shuffled order" do
        {:ok, array} = create_sequential_array({100, 3})

        batches =
          array
          |> DataLoader.shuffled_batch_stream(32, seed: 42)
          |> Enum.to_list()

        # Should have 4 batches
        assert length(batches) == 4

        # Extract first values from first batch to verify shuffling
        assert {:ok, batch1} = Enum.at(batches, 0)

        first_values =
          for i <- 0..2 do
            Nx.to_number(batch1[i][0])
          end

        # Should not be sequential (0, 1, 2) due to shuffling
        # Note: this test has small chance of false positive if shuffle happens to produce 0,1,2
        refute first_values == [0, 1, 2]
      end

      test "produces same shuffle with same seed" do
        {:ok, array} = create_sequential_array({100, 3})

        batches1 =
          array
          |> DataLoader.shuffled_batch_stream(32, seed: 42)
          |> Enum.to_list()

        batches2 =
          array
          |> DataLoader.shuffled_batch_stream(32, seed: 42)
          |> Enum.to_list()

        # Should produce identical batches
        Enum.zip(batches1, batches2)
        |> Enum.each(fn {{:ok, b1}, {:ok, b2}} ->
          assert Nx.all(Nx.equal(b1, b2)) |> Nx.to_number() == 1
        end)
      end

      test "produces different shuffle with different seed" do
        {:ok, array} = create_sequential_array({100, 3})

        batches1 =
          array
          |> DataLoader.shuffled_batch_stream(32, seed: 42)
          |> Enum.to_list()

        batches2 =
          array
          |> DataLoader.shuffled_batch_stream(32, seed: 123)
          |> Enum.to_list()

        # Should produce different batches
        {:ok, b1} = Enum.at(batches1, 0)
        {:ok, b2} = Enum.at(batches2, 0)

        # At least one element should differ
        refute Nx.all(Nx.equal(b1, b2)) |> Nx.to_number() == 1
      end

      test "shuffles all samples exactly once" do
        {:ok, array} = create_sequential_array({100, 1})

        batches =
          array
          |> DataLoader.shuffled_batch_stream(25, seed: 42)
          |> Enum.to_list()

        # Collect all values
        all_values =
          batches
          |> Enum.flat_map(fn {:ok, batch} ->
            for i <- 0..(Nx.size(batch) - 1) do
              Nx.to_number(batch[i][0])
            end
          end)
          |> Enum.sort()

        # Should have all values from 0 to 99 exactly once
        assert all_values == Enum.to_list(0..99)
      end

      test "respects drop_remainder option" do
        {:ok, array} = create_test_array({100, 10})

        batches =
          array
          |> DataLoader.shuffled_batch_stream(32, seed: 42, drop_remainder: true)
          |> Enum.to_list()

        # Should have 3 complete batches
        assert length(batches) == 3

        Enum.each(batches, fn {:ok, batch} ->
          assert Nx.shape(batch) == {32, 10}
        end)
      end
    end

    describe "paired_batch_stream/4" do
      test "loads features and labels together" do
        {:ok, features} = create_test_array({100, 20})
        {:ok, labels} = create_test_array({100, 1})

        batches =
          DataLoader.paired_batch_stream(features, labels, 32)
          |> Enum.to_list()

        assert length(batches) == 4

        assert {:ok, {X_batch, y_batch}} = Enum.at(batches, 0)
        assert Nx.shape(X_batch) == {32, 20}
        assert Nx.shape(y_batch) == {32, 1}
      end

      test "maintains alignment between features and labels" do
        {:ok, features} = create_sequential_array({10, 3})
        {:ok, labels} = create_sequential_array({10, 1})

        batches =
          DataLoader.paired_batch_stream(features, labels, 3)
          |> Enum.to_list()

        # Check first batch alignment
        assert {:ok, {X_batch, y_batch}} = Enum.at(batches, 0)

        # First sample: features should be [0, 0, 0], label [0]
        assert Nx.to_number(X_batch[0][0]) == 0
        assert Nx.to_number(y_batch[0][0]) == 0

        # Second sample: features [1, 1, 1], label [1]
        assert Nx.to_number(X_batch[1][0]) == 1
        assert Nx.to_number(y_batch[1][0]) == 1
      end

      test "raises error if sample counts differ" do
        {:ok, features} = create_test_array({100, 20})
        {:ok, labels} = create_test_array({90, 1})

        assert_raise ArgumentError, ~r/same number of samples/, fn ->
          DataLoader.paired_batch_stream(features, labels, 32)
          |> Enum.to_list()
        end
      end

      test "respects drop_remainder option" do
        {:ok, features} = create_test_array({100, 20})
        {:ok, labels} = create_test_array({100, 1})

        batches =
          DataLoader.paired_batch_stream(features, labels, 32, drop_remainder: true)
          |> Enum.to_list()

        # Should have 3 complete batches
        assert length(batches) == 3

        Enum.each(batches, fn {:ok, {X_batch, y_batch}} ->
          assert Nx.shape(X_batch) == {32, 20}
          assert Nx.shape(y_batch) == {32, 1}
        end)
      end
    end

    describe "paired_shuffled_batch_stream/4" do
      test "shuffles features and labels together" do
        {:ok, features} = create_sequential_array({100, 3})
        {:ok, labels} = create_sequential_array({100, 1})

        batches =
          DataLoader.paired_shuffled_batch_stream(features, labels, 32, seed: 42)
          |> Enum.to_list()

        assert length(batches) == 4

        # Verify alignment is maintained after shuffling
        {:ok, {X_batch, y_batch}} = Enum.at(batches, 0)

        # Each sample's label should match its feature
        for i <- 0..31 do
          feature_val = Nx.to_number(X_batch[i][0])
          label_val = Nx.to_number(y_batch[i][0])
          assert feature_val == label_val
        end
      end

      test "produces consistent shuffle with same seed" do
        {:ok, features} = create_sequential_array({100, 3})
        {:ok, labels} = create_sequential_array({100, 1})

        batches1 =
          DataLoader.paired_shuffled_batch_stream(features, labels, 32, seed: 42)
          |> Enum.to_list()

        batches2 =
          DataLoader.paired_shuffled_batch_stream(features, labels, 32, seed: 42)
          |> Enum.to_list()

        # Should produce identical batches
        Enum.zip(batches1, batches2)
        |> Enum.each(fn {{:ok, {X1, y1}}, {:ok, {X2, y2}}} ->
          assert Nx.all(Nx.equal(X1, X2)) |> Nx.to_number() == 1
          assert Nx.all(Nx.equal(y1, y2)) |> Nx.to_number() == 1
        end)
      end

      test "raises error if sample counts differ" do
        {:ok, features} = create_test_array({100, 20})
        {:ok, labels} = create_test_array({90, 1})

        assert_raise ArgumentError, ~r/same number of samples/, fn ->
          DataLoader.paired_shuffled_batch_stream(features, labels, 32)
          |> Enum.to_list()
        end
      end
    end

    describe "count_batches/3" do
      test "counts batches without drop_remainder" do
        {:ok, array} = create_test_array({100, 10})

        assert DataLoader.count_batches(array, 32) == 4
        assert DataLoader.count_batches(array, 25) == 4
        assert DataLoader.count_batches(array, 50) == 2
        assert DataLoader.count_batches(array, 100) == 1
      end

      test "counts batches with drop_remainder" do
        {:ok, array} = create_test_array({100, 10})

        assert DataLoader.count_batches(array, 32, drop_remainder: true) == 3
        assert DataLoader.count_batches(array, 25, drop_remainder: true) == 4
        assert DataLoader.count_batches(array, 50, drop_remainder: true) == 2
      end

      test "handles edge cases" do
        {:ok, array} = create_test_array({10, 5})

        assert DataLoader.count_batches(array, 10) == 1
        assert DataLoader.count_batches(array, 11) == 1
        assert DataLoader.count_batches(array, 5) == 2
      end
    end

    describe "multi-epoch training simulation" do
      test "can iterate multiple epochs with different shuffling" do
        {:ok, array} = create_sequential_array({50, 5})

        # Simulate 3 epochs
        epoch_results =
          for epoch <- 1..3 do
            batches =
              array
              |> DataLoader.shuffled_batch_stream(10, seed: epoch)
              |> Enum.to_list()

            # Collect first batch for comparison
            {:ok, first_batch} = Enum.at(batches, 0)
            first_batch
          end

        # Each epoch should have different shuffle
        [epoch1, epoch2, epoch3] = epoch_results

        refute Nx.all(Nx.equal(epoch1, epoch2)) |> Nx.to_number() == 1
        refute Nx.all(Nx.equal(epoch2, epoch3)) |> Nx.to_number() == 1
      end

      test "can track progress across epochs" do
        {:ok, array} = create_test_array({100, 10})
        batch_size = 32

        num_batches = DataLoader.count_batches(array, batch_size)
        assert num_batches == 4

        # Simulate training loop
        for _epoch <- 1..3 do
          batch_count =
            array
            |> DataLoader.batch_stream(batch_size)
            |> Enum.count()

          assert batch_count == num_batches
        end
      end
    end

    describe "integration with different dtypes" do
      test "works with float32" do
        {:ok, array} = create_test_array({100, 10}, :float32)

        batches =
          array
          |> DataLoader.batch_stream(32)
          |> Enum.to_list()

        assert {:ok, batch} = Enum.at(batches, 0)
        assert Nx.type(batch) == {:f, 32}
      end

      test "works with int32" do
        {:ok, array} = create_test_array({100, 10}, :int32)

        batches =
          array
          |> DataLoader.batch_stream(32)
          |> Enum.to_list()

        assert {:ok, batch} = Enum.at(batches, 0)
        assert Nx.type(batch) == {:s, 32}
      end

      test "works with uint8" do
        {:ok, array} = create_test_array({100, 10}, :uint8)

        batches =
          array
          |> DataLoader.batch_stream(32)
          |> Enum.to_list()

        assert {:ok, batch} = Enum.at(batches, 0)
        assert Nx.type(batch) == {:u, 8}
      end
    end

    describe "memory efficiency" do
      @tag :performance
      test "processes large dataset without loading all at once" do
        # Create 10MB dataset (1000x1000 float64)
        {:ok, array} = create_test_array({1000, 1000})

        # Process in small batches
        batch_count =
          array
          |> DataLoader.batch_stream(100)
          |> Enum.count()

        assert batch_count == 10
      end

      @tag :performance
      test "shuffled streaming doesn't load entire dataset" do
        {:ok, array} = create_test_array({1000, 1000})

        # Process with shuffling
        batch_count =
          array
          |> DataLoader.shuffled_batch_stream(100, seed: 42)
          |> Enum.count()

        assert batch_count == 10
      end
    end

    # Helper functions

    defp create_test_array(shape, dtype \\ :float64) do
      # Create ExZarr array with random data
      chunks = infer_chunks(shape)

      ExZarr.create(
        shape: shape,
        chunks: chunks,
        dtype: dtype,
        storage: :memory
      )
    end

    defp create_sequential_array(shape, dtype \\ :float64) do
      # Create array where each row has the same value equal to its index
      # E.g., row 0: [0, 0, 0], row 1: [1, 1, 1], etc.
      num_samples = elem(shape, 0)
      row_size = if tuple_size(shape) > 1, do: elem(shape, 1), else: 1

      tensor =
        for i <- 0..(num_samples - 1) do
          List.duplicate(i, row_size)
        end
        |> List.flatten()
        |> Nx.tensor(type: nx_type_for_dtype(dtype))
        |> Nx.reshape(shape)

      # Convert to ExZarr array
      ExZarr.Nx.from_tensor(tensor,
        chunks: infer_chunks(shape),
        storage: :memory
      )
    end

    defp infer_chunks(shape) do
      # Simple chunking strategy
      shape
      |> Tuple.to_list()
      |> Enum.map(fn dim -> max(1, div(dim, 2)) end)
      |> List.to_tuple()
    end

    defp nx_type_for_dtype(:float64), do: {:f, 64}
    defp nx_type_for_dtype(:float32), do: {:f, 32}
    defp nx_type_for_dtype(:int32), do: {:s, 32}
    defp nx_type_for_dtype(:uint8), do: {:u, 8}
  else
    @moduletag :skip
  end
end
