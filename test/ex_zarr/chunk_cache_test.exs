defmodule ExZarr.ChunkCacheTest do
  use ExUnit.Case, async: true

  alias ExZarr.ChunkCache

  setup do
    # Start a cache for this test
    {:ok, cache} = ChunkCache.start_link(max_size: 5, name: :"cache_#{System.unique_integer()}")
    {:ok, cache: cache}
  end

  describe "basic operations" do
    test "stores and retrieves chunks", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      data = <<1, 2, 3, 4>>

      :ok = ChunkCache.put(key, data, cache)
      assert {:ok, ^data} = ChunkCache.get(key, cache)
    end

    test "returns :not_found for missing chunks", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      assert :not_found = ChunkCache.get(key, cache)
    end

    test "updates existing chunks", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      data1 = <<1, 2, 3, 4>>
      data2 = <<5, 6, 7, 8>>

      :ok = ChunkCache.put(key, data1, cache)
      assert {:ok, ^data1} = ChunkCache.get(key, cache)

      :ok = ChunkCache.put(key, data2, cache)
      assert {:ok, ^data2} = ChunkCache.get(key, cache)
    end

    test "invalidates cached chunks", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      data = <<1, 2, 3, 4>>

      :ok = ChunkCache.put(key, data, cache)
      assert {:ok, ^data} = ChunkCache.get(key, cache)

      :ok = ChunkCache.invalidate(key, cache)
      assert :not_found = ChunkCache.get(key, cache)
    end

    test "clears entire cache", %{cache: cache} do
      key1 = {"/tmp/array1", {0, 0}}
      key2 = {"/tmp/array1", {0, 1}}
      data = <<1, 2, 3, 4>>

      :ok = ChunkCache.put(key1, data, cache)
      :ok = ChunkCache.put(key2, data, cache)

      :ok = ChunkCache.clear(cache)

      assert :not_found = ChunkCache.get(key1, cache)
      assert :not_found = ChunkCache.get(key2, cache)
    end
  end

  describe "LRU eviction" do
    test "evicts least recently used when full", %{cache: cache} do
      # Cache has max_size: 5, fill it up
      keys = for i <- 0..4, do: {"/tmp/array1", {i, 0}}

      Enum.each(keys, fn key ->
        ChunkCache.put(key, <<1, 2, 3>>, cache)
      end)

      # Access all but the first to update LRU order
      Enum.each(Enum.drop(keys, 1), fn key ->
        ChunkCache.get(key, cache)
      end)

      # Add one more - should evict keys[0] (least recently used)
      new_key = {"/tmp/array1", {5, 0}}
      ChunkCache.put(new_key, <<9, 9, 9>>, cache)

      # First key should be evicted
      assert :not_found = ChunkCache.get(Enum.at(keys, 0), cache)

      # New key should be present
      assert {:ok, <<9, 9, 9>>} = ChunkCache.get(new_key, cache)

      # Other keys should still be present
      Enum.each(Enum.drop(keys, 1), fn key ->
        assert {:ok, _} = ChunkCache.get(key, cache)
      end)
    end

    test "updates LRU order on access", %{cache: cache} do
      # Fill cache with keys and corresponding data
      for i <- 0..4 do
        key = {"/tmp/array1", {i, 0}}
        ChunkCache.put(key, <<i::32>>, cache)
      end

      keys = for i <- 0..4, do: {"/tmp/array1", {i, 0}}

      # Access first key to move it to front
      ChunkCache.get(Enum.at(keys, 0), cache)

      # Add new key - should evict keys[1] (now LRU)
      new_key = {"/tmp/array1", {5, 0}}
      ChunkCache.put(new_key, <<99::32>>, cache)

      # keys[0] should still be present (we just accessed it)
      assert {:ok, _} = ChunkCache.get(Enum.at(keys, 0), cache)

      # keys[1] should be evicted
      assert :not_found = ChunkCache.get(Enum.at(keys, 1), cache)
    end
  end

  describe "statistics" do
    test "tracks hits and misses", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      data = <<1, 2, 3, 4>>

      # Initial stats
      stats = ChunkCache.stats(cache)
      assert stats.size == 0
      assert stats.hits == 0
      assert stats.misses == 0

      # Miss
      ChunkCache.get(key, cache)
      stats = ChunkCache.stats(cache)
      assert stats.misses == 1

      # Put and hit
      ChunkCache.put(key, data, cache)
      ChunkCache.get(key, cache)
      stats = ChunkCache.stats(cache)
      assert stats.hits == 1
      assert stats.misses == 1
      assert stats.size == 1
    end

    test "calculates hit rate", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      data = <<1, 2, 3, 4>>

      ChunkCache.put(key, data, cache)

      # 3 hits, 1 miss = 75% hit rate
      ChunkCache.get(key, cache)
      ChunkCache.get(key, cache)
      ChunkCache.get(key, cache)
      # miss
      ChunkCache.get({"/tmp/array1", {1, 1}}, cache)

      stats = ChunkCache.stats(cache)
      assert stats.hits == 3
      assert stats.misses == 1
      assert_in_delta stats.hit_rate, 75.0, 0.1
    end
  end

  describe "concurrent access" do
    test "handles concurrent reads", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      data = <<1, 2, 3, 4>>

      ChunkCache.put(key, data, cache)

      # Spawn multiple readers
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            ChunkCache.get(key, cache)
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn result -> result == {:ok, data} end)
    end

    test "handles concurrent writes", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}

      # Spawn multiple writers
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            ChunkCache.put(key, <<i::32>>, cache)
            :ok
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn result -> result == :ok end)

      # Final value should be one of the written values
      assert {:ok, <<value::32>>} = ChunkCache.get(key, cache)
      assert value >= 1 and value <= 50
    end

    test "handles concurrent reads and writes", %{cache: cache} do
      key = {"/tmp/array1", {0, 0}}
      initial_data = <<0::32>>

      ChunkCache.put(key, initial_data, cache)

      # Mix of readers and writers
      tasks =
        for i <- 1..100 do
          if rem(i, 2) == 0 do
            Task.async(fn -> ChunkCache.get(key, cache) end)
          else
            Task.async(fn ->
              ChunkCache.put(key, <<i::32>>, cache)
              :ok
            end)
          end
        end

      results = Task.await_many(tasks)

      # All operations should complete
      assert length(results) == 100
    end
  end

  describe "multiple arrays" do
    test "caches chunks from different arrays", %{cache: cache} do
      key1 = {"/tmp/array1", {0, 0}}
      key2 = {"/tmp/array2", {0, 0}}
      data1 = <<1, 2, 3, 4>>
      data2 = <<5, 6, 7, 8>>

      ChunkCache.put(key1, data1, cache)
      ChunkCache.put(key2, data2, cache)

      assert {:ok, ^data1} = ChunkCache.get(key1, cache)
      assert {:ok, ^data2} = ChunkCache.get(key2, cache)
    end

    test "eviction considers all arrays", %{cache: cache} do
      # Fill with chunks from different arrays
      keys = [
        {"/tmp/array1", {0, 0}},
        {"/tmp/array2", {0, 0}},
        {"/tmp/array3", {0, 0}},
        {"/tmp/array4", {0, 0}},
        {"/tmp/array5", {0, 0}}
      ]

      Enum.each(keys, fn key ->
        ChunkCache.put(key, <<1, 2, 3>>, cache)
      end)

      # Add one more - should evict the oldest
      new_key = {"/tmp/array6", {0, 0}}
      ChunkCache.put(new_key, <<9, 9, 9>>, cache)

      # First key should be evicted
      assert :not_found = ChunkCache.get(Enum.at(keys, 0), cache)

      # New key should be present
      assert {:ok, <<9, 9, 9>>} = ChunkCache.get(new_key, cache)
    end
  end
end
