defmodule ExZarr.MnesiaStorageTest do
  use ExUnit.Case
  alias ExZarr.Storage.Backend.Mnesia, as: MnesiaBackend
  alias ExZarr.Storage.Registry


  @moduletag :mnesia

  # These tests require Mnesia to be running
  # They are skipped by default in CI
  # To run: mix test --include mnesia

  setup_all do
    # Initialize Mnesia (only once for all tests)
    :mnesia.stop()
    :mnesia.delete_schema([node()])
    :mnesia.create_schema([node()])
    :mnesia.start()

    on_exit(fn ->
      :mnesia.stop()
    end)

    :ok
  end

  setup do
    # Register Mnesia backend
    Registry.unregister(:mnesia)
    :ok = Registry.register(MnesiaBackend)

    # Clean up test table
    table = :zarr_test
    :mnesia.delete_table(table)

    on_exit(fn ->
      Registry.unregister(:mnesia)
      :mnesia.delete_table(table)
    end)

    {:ok, table: table}
  end

  describe "Basic operations" do
    test "creates array with Mnesia storage", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "test_array_001"
        )

      assert array.storage.backend == :mnesia
    end

    test "writes and reads chunks", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          storage: :mnesia,
          table_name: table,
          array_id: "test_array_002"
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 1.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      assert read_data == data
    end

    test "handles 2D arrays", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {20, 20},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "test_array_2d"
        )

      # Write a small slice
      data =
        for _ <- 0..399, into: <<>> do
          <<42::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {20, 20})

      assert read_data == data
    end

    test "lists chunks", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "test_array_list"
        )

      # Write some data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # List chunks
      {:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
      # 100/25 = 4 chunks
      assert length(chunks) == 4
      assert Enum.sort(chunks) == [{0}, {1}, {2}, {3}]
    end

    test "deletes chunks", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "test_array_delete"
        )

      # Write data
      data = for i <- 0..49, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      # Verify chunks exist
      {:ok, chunks_before} = ExZarr.Storage.list_chunks(array.storage)
      assert length(chunks_before) == 5

      # Delete a chunk
      :ok = MnesiaBackend.delete_chunk(array.storage.state, {0})

      # Verify chunk was deleted
      {:ok, chunks_after} = ExZarr.Storage.list_chunks(array.storage)
      assert length(chunks_after) == 4
      refute {0} in chunks_after
    end
  end

  describe "Persistence" do
    test "data persists in RAM table", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {20},
          chunks: {10},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "persist_test",
          ram_copies: true
        )

      # Write data
      data = for i <- 0..19, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {20})

      # Create new array instance pointing to same data
      {:ok, reopened} =
        MnesiaBackend.open(
          array_id: "persist_test",
          table_name: table
        )

      backend_state = reopened

      # Read data through new instance
      {:ok, read_data} = MnesiaBackend.read_chunk(backend_state, {0})

      # Should be able to read the data
      assert is_binary(read_data)
    end
  end

  describe "Multiple arrays" do
    test "stores multiple arrays in same table", %{table: table} do
      {:ok, array1} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "array_1"
        )

      {:ok, array2} =
        ExZarr.create(
          shape: {30},
          chunks: {10},
          dtype: :float64,
          storage: :mnesia,
          table_name: table,
          array_id: "array_2"
        )

      # Write to both arrays
      data1 = for i <- 0..49, into: <<>>, do: <<i::signed-little-32>>
      data2 = for i <- 0..29, into: <<>>, do: <<i * 1.5::float-little-64>>

      :ok = ExZarr.Array.set_slice(array1, data1, start: {0}, stop: {50})
      :ok = ExZarr.Array.set_slice(array2, data2, start: {0}, stop: {30})

      # Read from both arrays
      {:ok, read1} = ExZarr.Array.get_slice(array1, start: {0}, stop: {50})
      {:ok, read2} = ExZarr.Array.get_slice(array2, start: {0}, stop: {30})

      assert read1 == data1
      assert read2 == data2
    end
  end

  describe "Integration with filters and compression" do
    test "works with Delta filter", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int64,
          filters: [{:delta, [dtype: :int64]}],
          compressor: :zlib,
          storage: :mnesia,
          table_name: table,
          array_id: "filter_test_delta"
        )

      data =
        for i <- 0..99, into: <<>> do
          <<i::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "works with Shuffle filter", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [{:shuffle, [elementsize: 8]}],
          compressor: :zlib,
          storage: :mnesia,
          table_name: table,
          array_id: "filter_test_shuffle"
        )

      data =
        for i <- 0..99, into: <<>> do
          value = i * 2.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end
  end

  describe "Error handling" do
    test "requires array_id" do
      result =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :mnesia,
          table_name: :test_table
        )

      assert {:error, :array_id_required} = result
    end

    test "handles missing chunks gracefully", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "missing_chunk_test"
        )

      # Try to read non-existent chunk
      result = ExZarr.Storage.Backend.Mnesia.read_chunk(array.storage.state, {99})
      assert {:error, :not_found} = result
    end
  end

  describe "Transactions" do
    test "write operations are atomic", %{table: table} do
      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :mnesia,
          table_name: table,
          array_id: "atomic_test"
        )

      data = for i <- 0..9, into: <<>>, do: <<i::signed-little-32>>

      # Multiple concurrent writes should all succeed
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &match?(:ok, &1))
    end
  end
end
