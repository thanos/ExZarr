defmodule ExZarr.ETSStorageTest do
  use ExUnit.Case
  alias ExZarr.Storage.Backend.ETS, as: ETSBackend
  alias ExZarr.Storage.Registry

  setup do
    # Register ETS backend
    Registry.unregister(:ets)
    :ok = Registry.register(ETSBackend)

    on_exit(fn ->
      Registry.unregister(:ets)
    end)

    :ok
  end

  describe "Basic operations" do
    test "creates array with ETS storage" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          storage: :ets,
          table_name: :test_array_basic
        )

      assert array.storage.backend == :ets

      # Cleanup
      ETSBackend.delete_table(:test_array_basic)
    end

    test "creates array with auto-generated table name" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          storage: :ets
        )

      assert array.storage.backend == :ets
      # Table name should be auto-generated
      table_name = array.storage.state.table_name
      assert is_atom(table_name)

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "writes and reads chunks" do
      table_name = :test_array_rw

      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          storage: :ets,
          table_name: table_name
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 1.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      assert read_data == data

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "handles 2D arrays" do
      table_name = :test_array_2d

      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {20, 20},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Write a small slice
      data =
        for _ <- 0..399, into: <<>> do
          <<42::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {20, 20})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {20, 20})

      assert read_data == data

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "lists chunks" do
      table_name = :test_array_list

      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Write some data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # List chunks
      {:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
      # 100/25 = 4 chunks
      assert length(chunks) == 4
      assert Enum.sort(chunks) == [{0}, {1}, {2}, {3}]

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "deletes chunks" do
      table_name = :test_array_delete

      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Write data
      data = for i <- 0..49, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      # Verify chunks exist
      {:ok, chunks_before} = ExZarr.Storage.list_chunks(array.storage)
      assert length(chunks_before) == 5

      # Delete a chunk
      :ok = ETSBackend.delete_chunk(array.storage.state, {0})

      # Verify chunk was deleted
      {:ok, chunks_after} = ExZarr.Storage.list_chunks(array.storage)
      assert length(chunks_after) == 4
      refute {0} in chunks_after

      # Cleanup
      ETSBackend.delete_table(table_name)
    end
  end

  describe "Table types and access" do
    test "creates public table" do
      table_name = :test_public

      {:ok, _array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          access: :public
        )

      # Verify table is public
      info = ETSBackend.table_info(table_name)
      assert info.protection == :public

      # Another process should be able to read
      task =
        Task.async(fn ->
          :ets.lookup(table_name, :metadata)
        end)

      result = Task.await(task)
      assert is_list(result)

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "creates protected table" do
      table_name = :test_protected

      {:ok, _array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          access: :protected
        )

      # Verify table is protected
      info = ETSBackend.table_info(table_name)
      assert info.protection == :protected

      # Another process can read but not write
      task =
        Task.async(fn ->
          # Read should work
          read_result = :ets.lookup(table_name, :metadata)

          # Write should fail
          write_result =
            try do
              :ets.insert(table_name, {:test, "data"})
              :ok
            catch
              :error, :badarg -> :error
            end

          {read_result, write_result}
        end)

      {read_result, write_result} = Task.await(task)
      assert is_list(read_result)
      assert write_result == :error

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "creates ordered_set table" do
      table_name = :test_ordered

      {:ok, _array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          table_type: :ordered_set
        )

      # Verify table type
      info = ETSBackend.table_info(table_name)
      assert info.type == :ordered_set

      # Cleanup
      ETSBackend.delete_table(table_name)
    end
  end

  describe "Named tables" do
    test "creates named table accessible from other processes" do
      table_name = :test_shared

      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          named_table: true,
          access: :public
        )

      # Write data
      data = for i <- 0..49, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      # Access from another process using table name
      task =
        Task.async(fn ->
          case :ets.lookup(table_name, {:chunk, {0}}) do
            [{{:chunk, {0}}, chunk_data}] -> byte_size(chunk_data)
            [] -> 0
          end
        end)

      chunk_size = Task.await(task)
      assert chunk_size > 0

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "can open existing named table" do
      table_name = :test_reopen

      # Create array
      {:ok, array1} =
        ExZarr.create(
          shape: {20},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          named_table: true
        )

      # Write data
      data = for i <- 0..19, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array1, data, start: {0}, stop: {20})

      # Open same table from different context
      {:ok, backend_state} =
        ETSBackend.open(
          table_name: table_name,
          named_table: true
        )

      # Should be able to read existing data
      {:ok, read_chunk} = ETSBackend.read_chunk(backend_state, {0})
      assert is_binary(read_chunk)

      # Cleanup
      ETSBackend.delete_table(table_name)
    end
  end

  describe "Multi-process access" do
    test "concurrent reads from multiple processes" do
      table_name = :test_concurrent

      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          access: :public
        )

      # Write data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Spawn multiple readers
      tasks =
        for i <- 0..9 do
          Task.async(fn ->
            {:ok, chunk_data} = ETSBackend.read_chunk(array.storage.state, {i})
            byte_size(chunk_data)
          end)
        end

      # All reads should succeed
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 > 0))

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "survives process termination with heir" do
      table_name = :test_heir
      test_pid = self()

      # Create array in separate process with heir
      creator_pid =
        spawn(fn ->
          {:ok, array} =
            ExZarr.create(
              shape: {20},
              chunks: {10},
              dtype: :int32,
              storage: :ets,
              table_name: table_name,
              heir: test_pid
            )

          # Write data
          data = for i <- 0..19, into: <<>>, do: <<i::signed-little-32>>
          :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {20})

          send(test_pid, :done)

          # Wait for termination signal
          receive do
            :terminate -> :ok
          end
        end)

      # Wait for data to be written
      assert_receive :done, 1000

      # Verify table exists before termination
      assert ETSBackend.table_exists?(table_name)

      # Terminate creator process
      send(creator_pid, :terminate)
      Process.sleep(100)

      # Table should still exist due to heir
      assert ETSBackend.table_exists?(table_name)

      # Should be able to read data
      state = ETSBackend.get_state(table_name)
      assert map_size(state.chunks) == 2

      # Cleanup
      ETSBackend.delete_table(table_name)
    end
  end

  describe "Helper functions" do
    test "table_info returns metadata" do
      table_name = :test_info

      {:ok, _array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      info = ETSBackend.table_info(table_name)

      assert info.name == table_name
      assert is_integer(info.size)
      assert is_integer(info.memory)
      assert info.type in [:set, :ordered_set, :bag, :duplicate_bag]
      assert info.protection in [:public, :protected, :private]
      assert is_pid(info.owner)

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "get_state retrieves all data" do
      table_name = :test_state

      {:ok, array} =
        ExZarr.create(
          shape: {30},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Write data
      data = for i <- 0..29, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {30})

      # Save to write metadata
      :ok = ExZarr.Array.save(array, [])

      # Get state
      state = ETSBackend.get_state(table_name)

      assert map_size(state.chunks) == 3
      assert state.metadata != nil

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "clear_table removes all data" do
      table_name = :test_clear

      {:ok, array} =
        ExZarr.create(
          shape: {20},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Write data
      data = for i <- 0..19, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {20})

      # Verify data exists
      state_before = ETSBackend.get_state(table_name)
      assert map_size(state_before.chunks) > 0

      # Clear table
      :ok = ETSBackend.clear_table(table_name)

      # Verify data is gone
      state_after = ETSBackend.get_state(table_name)
      assert map_size(state_after.chunks) == 0
      assert state_after.metadata == nil

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "delete_table removes table" do
      table_name = :test_delete

      {:ok, _array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Verify table exists
      assert ETSBackend.table_exists?(table_name)

      # Delete table
      :ok = ETSBackend.delete_table(table_name)

      # Verify table is gone
      refute ETSBackend.table_exists?(table_name)

      # Trying to delete again should return error
      assert {:error, :table_not_found} = ETSBackend.delete_table(table_name)
    end
  end

  describe "Integration with filters and compression" do
    test "works with Delta filter" do
      table_name = :test_delta

      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int64,
          filters: [{:delta, [dtype: :int64]}],
          compressor: :zlib,
          storage: :ets,
          table_name: table_name
        )

      data =
        for i <- 0..99, into: <<>> do
          <<i::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "works with Shuffle filter" do
      table_name = :test_shuffle

      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [{:shuffle, [elementsize: 8]}],
          compressor: :zlib,
          storage: :ets,
          table_name: table_name
        )

      data =
        for i <- 0..99, into: <<>> do
          value = i * 2.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "works with multiple filters" do
      table_name = :test_multi_filter

      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :float64,
          filters: [
            {:quantize, [digits: 2, dtype: :float64]},
            {:shuffle, [elementsize: 8]}
          ],
          compressor: :zlib,
          storage: :ets,
          table_name: table_name
        )

      data =
        for i <- 0..99, into: <<>> do
          value = i * 1.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, _read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      # Cleanup
      ETSBackend.delete_table(table_name)
    end
  end

  describe "Error handling" do
    test "handles missing chunks gracefully" do
      table_name = :test_missing

      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Try to read non-existent chunk
      result = ETSBackend.read_chunk(array.storage.state, {99})
      assert {:error, :not_found} = result

      # Cleanup
      ETSBackend.delete_table(table_name)
    end

    test "returns error for deleted table" do
      table_name = :test_deleted

      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :ets,
          table_name: table_name
        )

      # Delete table
      ETSBackend.delete_table(table_name)

      # Operations should fail
      result = ETSBackend.read_chunk(array.storage.state, {0})
      assert {:error, :table_not_found} = result
    end

    test "cannot open non-existent named table" do
      result = ETSBackend.open(table_name: :nonexistent, named_table: true)
      assert {:error, :table_not_found} = result
    end

    test "requires table_name for open" do
      result = ETSBackend.open(named_table: true)
      assert {:error, :table_name_required} = result
    end
  end

  describe "Performance comparison" do
    @tag :performance
    test "ETS is faster than Agent for concurrent reads" do
      table_name = :perf_test

      # Create ETS-based array
      {:ok, ets_array} =
        ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :int32,
          storage: :ets,
          table_name: table_name,
          access: :public
        )

      # Write data
      data = for i <- 0..999, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(ets_array, data, start: {0}, stop: {1000})

      # Create Memory-based array with same data
      {:ok, mem_array} =
        ExZarr.create(
          shape: {1000},
          chunks: {100},
          dtype: :int32,
          storage: :memory
        )

      :ok = ExZarr.Array.set_slice(mem_array, data, start: {0}, stop: {1000})

      # Benchmark concurrent reads
      num_readers = 10
      num_reads = 10

      ets_time =
        :timer.tc(fn ->
          tasks =
            for _ <- 1..num_readers do
              Task.async(fn ->
                for i <- 0..num_reads do
                  chunk_idx = rem(i, 10)
                  ETSBackend.read_chunk(ets_array.storage.state, {chunk_idx})
                end
              end)
            end

          Task.await_many(tasks, 5000)
        end)
        |> elem(0)

      mem_time =
        :timer.tc(fn ->
          tasks =
            for _ <- 1..num_readers do
              Task.async(fn ->
                for i <- 0..num_reads do
                  chunk_idx = rem(i, 10)
                  ExZarr.Storage.read_chunk(mem_array.storage, {chunk_idx})
                end
              end)
            end

          Task.await_many(tasks, 5000)
        end)
        |> elem(0)

      # ETS should be faster for concurrent reads
      # This is informational - actual speedup depends on system
      IO.puts(
        "\nPerformance comparison (#{num_readers} concurrent readers, #{num_reads} reads each):"
      )

      IO.puts("  ETS:    #{ets_time} μs")
      IO.puts("  Memory: #{mem_time} μs")
      IO.puts("  Speedup: #{Float.round(mem_time / ets_time, 2)}x")

      # Cleanup
      ETSBackend.delete_table(table_name)
    end
  end
end
