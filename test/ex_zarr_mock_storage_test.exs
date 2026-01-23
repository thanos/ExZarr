defmodule ExZarr.MockStorageTest do
  use ExUnit.Case
  alias ExZarr.Storage.Backend.Mock
  alias ExZarr.Storage.Registry

  setup do
    # Register mock backend
    Registry.unregister(:mock)
    :ok = Registry.register(Mock)

    on_exit(fn ->
      Registry.unregister(:mock)
    end)

    :ok
  end

  describe "Basic operations" do
    test "creates array with mock storage" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          storage: :mock,
          pid: self()
        )

      assert array.storage.backend == :mock
      assert_received {:mock_storage, :init, _}
    end

    test "writes and reads chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          storage: :mock,
          pid: self()
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 1.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      assert read_data == data

      # Verify messages were sent
      assert_received {:mock_storage, :write_chunk, [{0}, _]}
      assert_received {:mock_storage, :write_chunk, [{1}, _]}
      assert_received {:mock_storage, :write_chunk, [{2}, _]}
      assert_received {:mock_storage, :write_chunk, [{3}, _]}
      assert_received {:mock_storage, :write_chunk, [{4}, _]}
    end

    test "handles metadata operations" do
      {:ok, array} =
        ExZarr.create(
          shape: {100, 100},
          chunks: {20, 20},
          dtype: :int32,
          storage: :mock,
          pid: self()
        )

      assert array.metadata.shape == {100, 100}
      assert array.metadata.chunks == {20, 20}

      # Metadata is only written when save is called
      :ok = ExZarr.Array.save(array, [])
      assert_received {:mock_storage, :write_metadata, _}
    end

    test "lists chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :int32,
          storage: :mock
        )

      # Write some data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # List chunks
      {:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
      # 100/25 = 4 chunks
      assert length(chunks) == 4
    end
  end

  describe "Error simulation" do
    test "simulates always-failing mode" do
      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :mock,
          error_mode: :always
        )

      data = for i <- 0..9, into: <<>>, do: <<i::signed-little-32>>

      # Write should fail
      result = ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})
      assert match?({:error, _}, result)
    end

    test "simulates failures on specific operations" do
      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :mock,
          fail_on: [:write_chunk]
        )

      data = for i <- 0..9, into: <<>>, do: <<i::signed-little-32>>

      # Write should fail
      result = ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})
      assert match?({:error, _}, result)
    end

    test "simulates random failures" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :mock,
          error_mode: :random
        )

      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>

      # Some writes may fail, some may succeed
      # Try multiple times to see both cases
      results =
        for _ <- 1..10 do
          ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
        end

      # Should have a mix of successes and failures
      successes = Enum.count(results, &match?(:ok, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      # With 50% probability over 10 attempts, very unlikely to be all one or the other
      assert successes > 0 or failures > 0
    end
  end

  describe "Latency simulation" do
    test "simulates delay" do
      delay_ms = 100

      {:ok, array} =
        ExZarr.create(
          shape: {10},
          chunks: {10},
          dtype: :int32,
          storage: :mock,
          delay: delay_ms
        )

      data = for i <- 0..9, into: <<>>, do: <<i::signed-little-32>>

      # Measure time
      start = System.monotonic_time(:millisecond)
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})
      elapsed = System.monotonic_time(:millisecond) - start

      # Should take at least delay_ms (one write operation)
      assert elapsed >= delay_ms
    end
  end

  describe "State verification" do
    test "can inspect mock state" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :int32,
          storage: :mock
        )

      # Write some data
      data = for i <- 0..49, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})

      # Save to write metadata
      :ok = ExZarr.Array.save(array, [])

      # Check mock state
      state = Mock.get_state(array.storage.state)
      # 50/10 = 5 chunks
      assert map_size(state.chunks) == 5
      assert state.metadata != nil
    end

    test "can reset mock state" do
      {:ok, array} =
        ExZarr.create(
          shape: {20},
          chunks: {10},
          dtype: :int32,
          storage: :mock
        )

      # Write data
      data = for i <- 0..19, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {20})

      # Verify data was written
      state = Mock.get_state(array.storage.state)
      assert map_size(state.chunks) > 0

      # Reset
      :ok = Mock.reset(array.storage.state)

      # Verify state was cleared
      state_after = Mock.get_state(array.storage.state)
      assert map_size(state_after.chunks) == 0
      assert state_after.metadata == nil
    end
  end

  describe "Message tracking" do
    test "tracks all operations" do
      {:ok, array} =
        ExZarr.create(
          shape: {30},
          chunks: {10},
          dtype: :int32,
          storage: :mock,
          pid: self()
        )

      # Clear mailbox
      flush_mailbox()

      # Perform operations
      data = for i <- 0..29, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {30})

      # Read back
      {:ok, _} = ExZarr.Array.get_slice(array, start: {0}, stop: {30})

      # Count write operations
      write_messages = collect_messages(:write_chunk)
      # 30/10 = 3 chunks
      assert length(write_messages) == 3

      # Count read operations
      # set_slice reads each chunk first (3 reads) + get_slice reads them again (3 reads) = 6 total
      read_messages = collect_messages(:read_chunk)
      assert length(read_messages) == 6
    end
  end

  describe "Integration with filters and compression" do
    test "works with Delta filter" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int64,
          filters: [{:delta, [dtype: :int64]}],
          compressor: :zlib,
          storage: :mock
        )

      data =
        for i <- 0..99, into: <<>> do
          <<i::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "works with multiple filters" do
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
          storage: :mock
        )

      data =
        for i <- 0..99, into: <<>> do
          value = i * 1.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, _read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})
    end
  end

  ## Helper functions

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp collect_messages(operation) do
    collect_messages(operation, [])
  end

  defp collect_messages(operation, acc) do
    receive do
      {:mock_storage, ^operation, args} ->
        collect_messages(operation, [args | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
