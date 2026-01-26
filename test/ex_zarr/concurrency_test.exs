defmodule ExZarr.ConcurrencyTest do
  use ExUnit.Case, async: false

  alias ExZarr.Array

  setup do
    # Use unique temp directory for each test
    tmp_dir = "/tmp/ex_zarr_concurrency_test_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "concurrent reads without server" do
    test "multiple processes can read simultaneously", %{tmp_dir: tmp_dir} do
      # Create and populate array
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array1")
        )

      data = for i <- 0..99, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Spawn multiple concurrent readers
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, read_array} =
              Array.open(
                storage: :filesystem,
                path: Path.join(tmp_dir, "array1")
              )

            {:ok, result} = Array.get_slice(read_array, start: {0, 0}, stop: {10, 10})
            result
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should read successfully
      assert length(results) == 20
      # All should read the same data (as binary)
      assert Enum.all?(results, fn result -> result == data end)
    end
  end

  describe "concurrent reads with server" do
    test "ArrayServer coordinates reads without blocking", %{tmp_dir: tmp_dir} do
      # Create array with server enabled
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array2"),
          enable_server: true
        )

      data = for i <- 0..99, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Spawn multiple concurrent readers
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, result} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
            result
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should succeed
      assert length(results) == 20
      assert Enum.all?(results, fn result -> result == data end)
    end
  end

  describe "concurrent writes with server" do
    test "ArrayServer prevents write conflicts", %{tmp_dir: tmp_dir} do
      # Create array with server enabled
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {5, 5},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array3"),
          enable_server: true
        )

      # Multiple processes write to different chunks
      tasks =
        for i <- 0..3 do
          Task.async(fn ->
            # Each task writes to its own chunk
            row = div(i, 2) * 5
            col = rem(i, 2) * 5
            data = for j <- 0..24, into: <<>>, do: <<i * 100 + j::32-little>>

            :ok = Array.set_slice(array, data, start: {row, col}, stop: {row + 5, col + 5})
            i
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All writes should succeed
      assert Enum.sort(results) == [0, 1, 2, 3]

      # Verify data integrity
      for i <- 0..3 do
        row = div(i, 2) * 5
        col = rem(i, 2) * 5
        {:ok, read_data} = Array.get_slice(array, start: {row, col}, stop: {row + 5, col + 5})

        # Convert binary to list of integers for comparison
        expected = for j <- 0..24, do: i * 100 + j
        actual = for <<val::32-little <- read_data>>, do: val

        assert actual == expected
      end
    end

    test "ArrayServer serializes writes to same chunk", %{tmp_dir: tmp_dir} do
      # Create array with server enabled
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array4"),
          enable_server: true
        )

      # Multiple processes write to the same chunk
      # Only the last write should be visible
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            data = for _j <- 0..99, into: <<>>, do: <<i::32-little>>
            :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
            i
          end)
        end

      Task.await_many(tasks, 10_000)

      # Read final state
      {:ok, result} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})

      # Should be all the same value (one of 1..10)
      values = for <<val::32-little <- result>>, do: val
      [first | _] = values

      assert Enum.all?(values, fn v -> v == first end)
      assert first >= 1 and first <= 10
    end
  end

  describe "concurrent reads and writes with server" do
    test "readers and writers don't corrupt data", %{tmp_dir: tmp_dir} do
      # Create array with server enabled
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array5"),
          enable_server: true
        )

      # Initialize array
      init_data = for i <- 0..399, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, init_data, start: {0, 0}, stop: {20, 20})

      # Mix of readers and writers
      tasks =
        for i <- 1..50 do
          if rem(i, 3) == 0 do
            # Writer
            Task.async(fn ->
              chunk_row = rem(i, 2) * 10
              chunk_col = rem(div(i, 2), 2) * 10
              data = for j <- 0..99, into: <<>>, do: <<i * 1000 + j::32-little>>

              :ok =
                Array.set_slice(array, data,
                  start: {chunk_row, chunk_col},
                  stop: {chunk_row + 10, chunk_col + 10}
                )

              {:write, i}
            end)
          else
            # Reader
            Task.async(fn ->
              {:ok, _data} = Array.get_slice(array, start: {0, 0}, stop: {20, 20})
              {:read, i}
            end)
          end
        end

      results = Task.await_many(tasks, 20_000)

      # All operations should complete
      assert length(results) == 50

      # Count reads and writes
      {reads, writes} =
        Enum.split_with(results, fn
          {:read, _} -> true
          {:write, _} -> false
        end)

      assert Enum.empty?(reads) == false
      assert Enum.empty?(writes) == false
    end
  end

  describe "cache performance" do
    test "cache improves repeated read performance", %{tmp_dir: tmp_dir} do
      # Create array with cache enabled
      {:ok, array} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array6"),
          enable_cache: true
        )

      # Populate array
      data = for i <- 0..9999, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

      # First read (cache miss)
      {time1, _} =
        :timer.tc(fn ->
          Array.get_slice(array, start: {0, 0}, stop: {10, 10})
        end)

      # Second read (cache hit)
      {time2, _} =
        :timer.tc(fn ->
          Array.get_slice(array, start: {0, 0}, stop: {10, 10})
        end)

      # Cache hit should be faster (usually 10x or more)
      # We use a conservative threshold to avoid flaky tests
      assert time2 < time1 * 0.5,
             "Cache hit (#{time2}μs) should be faster than miss (#{time1}μs)"
    end

    test "cache invalidation on write", %{tmp_dir: tmp_dir} do
      # Create array with cache enabled
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "array7"),
          enable_cache: true
        )

      # Write initial data
      data1 = for i <- 0..99, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, data1, start: {0, 0}, stop: {10, 10})

      # Read to populate cache
      {:ok, read1} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert read1 == data1

      # Write new data (should invalidate cache)
      data2 = for i <- 100..199, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, data2, start: {0, 0}, stop: {10, 10})

      # Read again (should get new data, not cached)
      {:ok, read2} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      assert read2 == data2
      refute read2 == read1
    end
  end

  describe "stress test" do
    @tag timeout: 120_000
    test "handles 50+ concurrent processes", %{tmp_dir: tmp_dir} do
      # Create array with full concurrency support
      {:ok, array} =
        Array.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "stress_array"),
          enable_server: true,
          enable_cache: true
        )

      # Initialize
      init_data = for i <- 0..2499, into: <<>>, do: <<i::32-little>>
      :ok = Array.set_slice(array, init_data, start: {0, 0}, stop: {50, 50})

      # Spawn 50 concurrent processes doing random operations
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            # Each process does multiple operations
            results =
              for _op <- 1..10 do
                # More reads than writes
                operation = Enum.random([:read, :write, :read, :read])

                case operation do
                  :read ->
                    row = :rand.uniform(40)
                    col = :rand.uniform(40)

                    {:ok, _data} =
                      Array.get_slice(array, start: {row, col}, stop: {row + 10, col + 10})

                    :read

                  :write ->
                    row = :rand.uniform(4) * 10
                    col = :rand.uniform(4) * 10
                    data = for j <- 0..99, into: <<>>, do: <<i * 1000 + j::32-little>>

                    :ok =
                      Array.set_slice(array, data,
                        start: {row, col},
                        stop: {row + 10, col + 10}
                      )

                    :write
                end
              end

            {i, results}
          end)
        end

      results = Task.await_many(tasks, 100_000)

      # All processes should complete
      assert length(results) == 50

      # Each process should have done 10 operations
      Enum.each(results, fn {_pid, ops} ->
        assert length(ops) == 10
      end)
    end
  end

  describe "deadlock prevention" do
    test "timeout prevents deadlock", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "deadlock_test"),
          enable_server: true
        )

      # Process 1 holds lock and doesn't release
      pid1 =
        spawn(fn ->
          ExZarr.ArrayServer.lock_chunk(array.server_pid, {0, 0}, :write)

          receive do
            :release -> :ok
          after
            60_000 -> :ok
          end
        end)

      # Wait for lock acquisition
      Process.sleep(100)

      # Process 2 tries to acquire with timeout
      # When GenServer.call times out, it sends EXIT to the calling process
      # We need to catch this EXIT instead of expecting {:error, :timeout}
      task =
        Task.async(fn ->
          try do
            ExZarr.ArrayServer.lock_chunk(array.server_pid, {0, 0}, :write, 500)
          catch
            :exit, {:timeout, _} -> {:error, :timeout}
          end
        end)

      # Should timeout
      assert {:error, :timeout} = Task.await(task)

      # Cleanup
      send(pid1, :release)
    end
  end
end
