defmodule ExZarr.ArrayServerTest do
  use ExUnit.Case, async: true

  alias ExZarr.ArrayServer

  setup do
    {:ok, server} =
      ArrayServer.start_link(
        array_id: "test_array_#{System.unique_integer()}",
        name: :"server_#{System.unique_integer()}"
      )

    {:ok, server: server}
  end

  describe "basic locking" do
    test "acquires and releases read lock", %{server: server} do
      chunk = {0, 0}

      assert :ok = ArrayServer.lock_chunk(server, chunk, :read)
      assert :ok = ArrayServer.unlock_chunk(server, chunk)
    end

    test "acquires and releases write lock", %{server: server} do
      chunk = {0, 0}

      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)
      assert :ok = ArrayServer.unlock_chunk(server, chunk)
    end

    test "multiple processes can hold read locks", %{server: server} do
      chunk = {0, 0}

      # First process acquires read lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :read)

      # Second process can also acquire read lock
      task =
        Task.async(fn ->
          ArrayServer.lock_chunk(server, chunk, :read, 1000)
        end)

      assert :ok = Task.await(task)

      # Both should be able to release
      assert :ok = ArrayServer.unlock_chunk(server, chunk)

      Task.async(fn ->
        ArrayServer.unlock_chunk(server, chunk)
      end)
      |> Task.await()
    end

    @tag :skip
    test "write lock blocks other locks", %{server: server} do
      chunk = {0, 0}

      # Acquire write lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)

      # Another process trying to acquire any lock should timeout
      task =
        Task.async(fn ->
          try do
            ArrayServer.lock_chunk(server, chunk, :read, 100)
          catch
            :exit, {:timeout, _} -> {:error, :timeout}
          end
        end)

      assert {:error, :timeout} = Task.await(task)

      # Give time for queue cleanup
      Process.sleep(50)

      # Release the write lock
      assert :ok = ArrayServer.unlock_chunk(server, chunk)

      # Give time for queue processing
      Process.sleep(50)

      # Now the read lock should succeed immediately (no blocking process)
      assert :ok = ArrayServer.lock_chunk(server, chunk, :read)
    end

    @tag :skip
    test "read lock blocks write lock", %{server: server} do
      chunk = {0, 0}

      # Acquire read lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :read)

      # Another process trying to acquire write lock should timeout
      task =
        Task.async(fn ->
          try do
            ArrayServer.lock_chunk(server, chunk, :write, 100)
          catch
            :exit, {:timeout, _} -> {:error, :timeout}
          end
        end)

      assert {:error, :timeout} = Task.await(task)

      # Release the read lock
      assert :ok = ArrayServer.unlock_chunk(server, chunk)

      # Now the write lock should succeed immediately (no blocking process)
      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)
    end
  end

  describe "try_lock" do
    test "returns immediately if lock available", %{server: server} do
      chunk = {0, 0}

      assert :ok = ArrayServer.try_lock_chunk(server, chunk, :read)
      assert :ok = ArrayServer.unlock_chunk(server, chunk)
    end

    test "returns error if lock unavailable", %{server: server} do
      chunk = {0, 0}

      # Acquire write lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)

      # try_lock should fail immediately
      task =
        Task.async(fn ->
          ArrayServer.try_lock_chunk(server, chunk, :read)
        end)

      assert {:error, :locked} = Task.await(task)
    end
  end

  describe "lock queue" do
    test "queues requests when lock unavailable", %{server: server} do
      chunk = {0, 0}

      # Process 1 acquires write lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)

      # Process 2 requests lock (will be queued)
      task2 =
        Task.async(fn ->
          result = ArrayServer.lock_chunk(server, chunk, :read, 5000)
          acquire_time = System.monotonic_time(:millisecond)
          {result, acquire_time}
        end)

      # Give task2 time to queue
      Process.sleep(50)

      # Process 1 releases lock
      release_time = System.monotonic_time(:millisecond)
      assert :ok = ArrayServer.unlock_chunk(server, chunk)

      # Process 2 should now acquire lock
      {:ok, acquire_time} = Task.await(task2)

      # Verify process 2 acquired after process 1 released
      assert acquire_time >= release_time
    end

    test "processes queue in FIFO order", %{server: server} do
      chunk = {0, 0}

      # Acquire write lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)

      # Spawn multiple queued requests
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            :ok = ArrayServer.lock_chunk(server, chunk, :write, 10_000)
            {i, System.monotonic_time(:millisecond)}
          end)
        end

      # Give tasks time to queue
      Process.sleep(100)

      # Release lock and measure order
      ArrayServer.unlock_chunk(server, chunk)

      results = Task.await_many(tasks, 15_000)

      # Extract completion order
      completion_times = Enum.map(results, fn {_i, time} -> time end)

      # Times should be monotonically increasing (FIFO order)
      assert completion_times == Enum.sort(completion_times)
    end
  end

  describe "automatic cleanup" do
    test "releases locks when process dies", %{server: server} do
      chunk = {0, 0}

      # Spawn process that acquires lock then dies
      {:ok, pid} =
        Task.start(fn ->
          ArrayServer.lock_chunk(server, chunk, :write, 5000)
          Process.sleep(100)
          # Process exits without releasing lock
        end)

      # Wait for lock acquisition
      Process.sleep(50)

      # Wait for process to die
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5000

      # Give GenServer time to process the DOWN message
      Process.sleep(100)

      # Should now be able to acquire lock
      assert :ok = ArrayServer.try_lock_chunk(server, chunk, :write)
    end

    test "processes queued requests after lock holder dies", %{server: server} do
      chunk = {0, 0}

      # Spawn process that holds lock
      holder_pid =
        spawn(fn ->
          ArrayServer.lock_chunk(server, chunk, :write, 5000)

          receive do
            :release -> ArrayServer.unlock_chunk(server, chunk)
          end
        end)

      # Wait for lock
      Process.sleep(50)

      # Spawn queued waiter
      waiter_task =
        Task.async(fn ->
          ArrayServer.lock_chunk(server, chunk, :read, 10_000)
        end)

      # Give waiter time to queue
      Process.sleep(50)

      # Kill holder
      Process.exit(holder_pid, :kill)

      # Wait for holder death
      Process.sleep(100)

      # Waiter should acquire lock
      assert :ok = Task.await(waiter_task, 5000)
    end
  end

  describe "multiple chunks" do
    test "locks on different chunks don't interfere", %{server: server} do
      chunk1 = {0, 0}
      chunk2 = {1, 1}

      # Acquire locks on different chunks
      assert :ok = ArrayServer.lock_chunk(server, chunk1, :write)
      assert :ok = ArrayServer.lock_chunk(server, chunk2, :write)

      # Should be able to access both
      assert :ok = ArrayServer.unlock_chunk(server, chunk1)
      assert :ok = ArrayServer.unlock_chunk(server, chunk2)
    end

    test "can hold locks on multiple chunks simultaneously", %{server: server} do
      chunks = [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      # Acquire locks on all chunks
      Enum.each(chunks, fn chunk ->
        assert :ok = ArrayServer.lock_chunk(server, chunk, :read)
      end)

      # Release all
      Enum.each(chunks, fn chunk ->
        assert :ok = ArrayServer.unlock_chunk(server, chunk)
      end)
    end
  end

  describe "release_all_locks" do
    test "releases all locks held by process", %{server: server} do
      chunks = [{0, 0}, {0, 1}, {1, 0}]

      # Acquire locks on multiple chunks
      Enum.each(chunks, fn chunk ->
        assert :ok = ArrayServer.lock_chunk(server, chunk, :write)
      end)

      # Release all at once
      assert :ok = ArrayServer.release_all_locks(server)

      # All should be available
      Enum.each(chunks, fn chunk ->
        assert :ok = ArrayServer.try_lock_chunk(server, chunk, :write)
      end)
    end
  end

  describe "get_locks" do
    test "returns lock information", %{server: server} do
      chunk1 = {0, 0}
      chunk2 = {1, 1}

      # Initially empty
      assert %{} = ArrayServer.get_locks(server)

      # Acquire some locks
      assert :ok = ArrayServer.lock_chunk(server, chunk1, :write)
      assert :ok = ArrayServer.lock_chunk(server, chunk2, :read)

      locks = ArrayServer.get_locks(server)

      assert Map.has_key?(locks, chunk1)
      assert Map.has_key?(locks, chunk2)
      assert locks[chunk1].type == :write
      assert locks[chunk2].type == :read
    end
  end

  describe "concurrent stress test" do
    test "handles 50 concurrent readers", %{server: server} do
      chunk = {0, 0}

      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            :ok = ArrayServer.lock_chunk(server, chunk, :read, 10_000)
            Process.sleep(:rand.uniform(10))
            :ok = ArrayServer.unlock_chunk(server, chunk)
            i
          end)
        end

      results = Task.await_many(tasks, 30_000)

      # All should succeed
      assert length(results) == 50
      assert Enum.sort(results) == Enum.to_list(1..50)
    end

    test "handles mixed read/write workload", %{server: server} do
      chunk = {0, 0}

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            lock_type = if rem(i, 3) == 0, do: :write, else: :read
            :ok = ArrayServer.lock_chunk(server, chunk, lock_type, 30_000)
            Process.sleep(:rand.uniform(5))
            :ok = ArrayServer.unlock_chunk(server, chunk)
            {i, lock_type}
          end)
        end

      results = Task.await_many(tasks, 60_000)

      # All should complete
      assert length(results) == 100
    end

    test "handles multiple chunks with contention", %{server: server} do
      chunks = for i <- 0..4, j <- 0..4, do: {i, j}

      tasks =
        for i <- 1..200 do
          Task.async(fn ->
            chunk = Enum.random(chunks)
            lock_type = if rem(i, 5) == 0, do: :write, else: :read

            :ok = ArrayServer.lock_chunk(server, chunk, lock_type, 30_000)
            Process.sleep(:rand.uniform(3))
            :ok = ArrayServer.unlock_chunk(server, chunk)

            i
          end)
        end

      results = Task.await_many(tasks, 60_000)

      # All should complete
      assert length(results) == 200
    end
  end

  describe "error handling" do
    test "returns error when unlocking non-held lock", %{server: server} do
      chunk = {0, 0}

      # Try to unlock without holding lock
      assert {:error, :not_locked} = ArrayServer.unlock_chunk(server, chunk)
    end

    test "returns error when different process tries to unlock", %{server: server} do
      chunk = {0, 0}

      # This process acquires lock
      assert :ok = ArrayServer.lock_chunk(server, chunk, :write)

      # Different process tries to unlock
      task =
        Task.async(fn ->
          ArrayServer.unlock_chunk(server, chunk)
        end)

      assert {:error, :not_holder} = Task.await(task)
    end
  end
end
