defmodule ExZarr.MetadataCacheTest do
  use ExUnit.Case, async: true

  alias ExZarr.MetadataCache

  setup do
    # Start a cache with unique name for each test
    cache_name = :"cache_#{System.unique_integer()}"
    {:ok, pid} = MetadataCache.start_link(name: cache_name, ttl: 1000, max_size: 10)

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    {:ok, cache: cache_name, pid: pid}
  end

  describe "put/get" do
    test "stores and retrieves metadata", %{cache: cache} do
      metadata = %{shape: [100, 100], dtype: "int32", chunks: [10, 10]}
      path = "/path/to/array1"

      :ok = MetadataCache.put(path, metadata, cache)

      assert {:ok, ^metadata} = MetadataCache.get(path, cache)
    end

    test "returns not_found for missing entries", %{cache: cache} do
      assert {:error, :not_found} = MetadataCache.get("/nonexistent/path", cache)
    end

    test "handles multiple different paths", %{cache: cache} do
      metadata1 = %{shape: [100, 100], dtype: "int32"}
      metadata2 = %{shape: [200, 200], dtype: "float64"}

      :ok = MetadataCache.put("/array1", metadata1, cache)
      :ok = MetadataCache.put("/array2", metadata2, cache)

      assert {:ok, ^metadata1} = MetadataCache.get("/array1", cache)
      assert {:ok, ^metadata2} = MetadataCache.get("/array2", cache)
    end

    test "overwrites existing entries", %{cache: cache} do
      path = "/path/to/array"
      metadata1 = %{version: 1}
      metadata2 = %{version: 2}

      :ok = MetadataCache.put(path, metadata1, cache)
      assert {:ok, ^metadata1} = MetadataCache.get(path, cache)

      :ok = MetadataCache.put(path, metadata2, cache)
      assert {:ok, ^metadata2} = MetadataCache.get(path, cache)
    end
  end

  describe "invalidate" do
    test "removes entry from cache", %{cache: cache} do
      metadata = %{shape: [100, 100]}
      path = "/path/to/array"

      :ok = MetadataCache.put(path, metadata, cache)
      assert {:ok, ^metadata} = MetadataCache.get(path, cache)

      :ok = MetadataCache.invalidate(path, cache)
      assert {:error, :not_found} = MetadataCache.get(path, cache)
    end

    test "succeeds for non-existent entries", %{cache: cache} do
      :ok = MetadataCache.invalidate("/nonexistent", cache)
    end

    test "only invalidates specified path", %{cache: cache} do
      metadata1 = %{id: 1}
      metadata2 = %{id: 2}

      :ok = MetadataCache.put("/array1", metadata1, cache)
      :ok = MetadataCache.put("/array2", metadata2, cache)

      :ok = MetadataCache.invalidate("/array1", cache)

      assert {:error, :not_found} = MetadataCache.get("/array1", cache)
      assert {:ok, ^metadata2} = MetadataCache.get("/array2", cache)
    end
  end

  describe "clear" do
    test "removes all entries", %{cache: cache} do
      :ok = MetadataCache.put("/array1", %{id: 1}, cache)
      :ok = MetadataCache.put("/array2", %{id: 2}, cache)
      :ok = MetadataCache.put("/array3", %{id: 3}, cache)

      :ok = MetadataCache.clear(cache)

      assert {:error, :not_found} = MetadataCache.get("/array1", cache)
      assert {:error, :not_found} = MetadataCache.get("/array2", cache)
      assert {:error, :not_found} = MetadataCache.get("/array3", cache)
    end

    test "resets statistics", %{cache: cache} do
      # Generate some hits and misses
      :ok = MetadataCache.put("/array1", %{}, cache)
      {:ok, _} = MetadataCache.get("/array1", cache)
      {:error, :not_found} = MetadataCache.get("/nonexistent", cache)

      stats_before = MetadataCache.stats(cache)
      assert stats_before.hits > 0
      assert stats_before.misses > 0

      :ok = MetadataCache.clear(cache)

      stats_after = MetadataCache.stats(cache)
      assert stats_after.hits == 0
      assert stats_after.misses == 0
    end
  end

  describe "stats" do
    test "tracks cache hits", %{cache: cache} do
      metadata = %{shape: [100, 100]}
      :ok = MetadataCache.put("/array", metadata, cache)

      # Generate 3 hits
      {:ok, _} = MetadataCache.get("/array", cache)
      {:ok, _} = MetadataCache.get("/array", cache)
      {:ok, _} = MetadataCache.get("/array", cache)

      stats = MetadataCache.stats(cache)
      assert stats.hits == 3
    end

    test "tracks cache misses", %{cache: cache} do
      # Generate 2 misses
      {:error, :not_found} = MetadataCache.get("/nonexistent1", cache)
      {:error, :not_found} = MetadataCache.get("/nonexistent2", cache)

      stats = MetadataCache.stats(cache)
      assert stats.misses == 2
    end

    test "calculates hit rate correctly", %{cache: cache} do
      :ok = MetadataCache.put("/array", %{}, cache)

      # 3 hits
      {:ok, _} = MetadataCache.get("/array", cache)
      {:ok, _} = MetadataCache.get("/array", cache)
      {:ok, _} = MetadataCache.get("/array", cache)

      # 1 miss
      {:error, :not_found} = MetadataCache.get("/nonexistent", cache)

      stats = MetadataCache.stats(cache)
      assert stats.hits == 3
      assert stats.misses == 1
      # 3 / 4
      assert stats.hit_rate == 0.75
    end

    test "returns zero hit rate when no requests", %{cache: cache} do
      stats = MetadataCache.stats(cache)
      assert stats.hit_rate == 0.0
    end

    test "tracks number of entries", %{cache: cache} do
      stats_before = MetadataCache.stats(cache)
      assert stats_before.entries == 0

      :ok = MetadataCache.put("/array1", %{}, cache)
      :ok = MetadataCache.put("/array2", %{}, cache)
      :ok = MetadataCache.put("/array3", %{}, cache)

      stats_after = MetadataCache.stats(cache)
      assert stats_after.entries == 3
    end
  end

  describe "TTL expiration" do
    test "expires entries after TTL", %{cache: cache} do
      metadata = %{shape: [100, 100]}
      :ok = MetadataCache.put("/array", metadata, cache)

      # Should be cached immediately
      assert {:ok, ^metadata} = MetadataCache.get("/array", cache)

      # Wait for TTL to expire (TTL is 1000ms in setup)
      Process.sleep(1100)

      # Should now be expired
      assert {:error, :not_found} = MetadataCache.get("/array", cache)
    end

    test "expired entries count as misses", %{cache: cache} do
      :ok = MetadataCache.put("/array", %{}, cache)
      {:ok, _} = MetadataCache.get("/array", cache)

      stats_before = MetadataCache.stats(cache)
      assert stats_before.hits == 1
      assert stats_before.misses == 0

      # Wait for expiration
      Process.sleep(1100)

      {:error, :not_found} = MetadataCache.get("/array", cache)

      stats_after = MetadataCache.stats(cache)
      assert stats_after.hits == 1
      assert stats_after.misses == 1
    end
  end

  describe "max_size limit" do
    test "evicts oldest entry when max_size exceeded", %{cache: cache} do
      # Cache has max_size: 10 from setup
      # Fill cache to max
      for i <- 1..10 do
        :ok = MetadataCache.put("/array#{i}", %{id: i}, cache)
      end

      stats = MetadataCache.stats(cache)
      assert stats.entries == 10

      # Add one more - should evict oldest
      :ok = MetadataCache.put("/array11", %{id: 11}, cache)

      # Still at max size
      stats = MetadataCache.stats(cache)
      assert stats.entries == 10

      # Newest entry should exist
      assert {:ok, %{id: 11}} = MetadataCache.get("/array11", cache)
    end

    test "accepts max_size configuration", %{} do
      cache_name = :"cache_max_size_#{System.unique_integer()}"
      {:ok, pid} = MetadataCache.start_link(name: cache_name, max_size: 3)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      # Fill beyond max_size
      :ok = MetadataCache.put("/array1", %{}, cache_name)
      :ok = MetadataCache.put("/array2", %{}, cache_name)
      :ok = MetadataCache.put("/array3", %{}, cache_name)
      :ok = MetadataCache.put("/array4", %{}, cache_name)

      stats = MetadataCache.stats(cache_name)
      assert stats.entries == 3
    end
  end

  describe "concurrent access" do
    test "handles concurrent puts and gets", %{cache: cache} do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            path = "/array#{rem(i, 10)}"
            metadata = %{id: i}

            :ok = MetadataCache.put(path, metadata, cache)
            Process.sleep(:rand.uniform(10))

            case MetadataCache.get(path, cache) do
              {:ok, _meta} -> :ok
              {:error, :not_found} -> :miss
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All operations should complete
      assert length(results) == 50
    end

    test "concurrent gets don't corrupt cache", %{cache: cache} do
      metadata = %{shape: [100, 100], dtype: "int32"}
      :ok = MetadataCache.put("/shared_array", metadata, cache)

      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            MetadataCache.get("/shared_array", cache)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All reads should succeed with correct metadata
      assert Enum.all?(results, fn result ->
               match?({:ok, ^metadata}, result)
             end)
    end
  end

  describe "integration scenarios" do
    test "typical workflow: cache miss, then hit", %{cache: cache} do
      path = "/data/array"

      # First access - cache miss
      assert {:error, :not_found} = MetadataCache.get(path, cache)

      stats1 = MetadataCache.stats(cache)
      assert stats1.misses == 1

      # Simulate loading from storage and caching
      metadata = %{shape: [100, 100], dtype: "float64"}
      :ok = MetadataCache.put(path, metadata, cache)

      # Second access - cache hit
      assert {:ok, ^metadata} = MetadataCache.get(path, cache)

      stats2 = MetadataCache.stats(cache)
      assert stats2.hits == 1
    end

    test "invalidation after write", %{cache: cache} do
      path = "/data/array"
      original_metadata = %{shape: [100, 100]}
      updated_metadata = %{shape: [200, 200]}

      # Initial cache
      :ok = MetadataCache.put(path, original_metadata, cache)
      assert {:ok, ^original_metadata} = MetadataCache.get(path, cache)

      # Simulate write operation - invalidate cache
      :ok = MetadataCache.invalidate(path, cache)

      # After write, need to reload
      assert {:error, :not_found} = MetadataCache.get(path, cache)

      # Cache new metadata
      :ok = MetadataCache.put(path, updated_metadata, cache)
      assert {:ok, ^updated_metadata} = MetadataCache.get(path, cache)
    end
  end

  describe "cleanup process" do
    test "periodically cleans up expired entries", %{} do
      # Start cache with very short TTL
      cache_name = :"cache_cleanup_#{System.unique_integer()}"
      {:ok, pid} = MetadataCache.start_link(name: cache_name, ttl: 100)

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      # Add entries
      for i <- 1..5 do
        :ok = MetadataCache.put("/array#{i}", %{id: i}, cache_name)
      end

      stats_before = MetadataCache.stats(cache_name)
      assert stats_before.entries == 5

      # Wait for TTL expiration and cleanup
      Process.sleep(200)

      # Entries should still be in ETS until cleanup runs
      # But they will return :not_found on get due to expiration check

      # Trigger some gets to verify expiration
      for i <- 1..5 do
        assert {:error, :not_found} = MetadataCache.get("/array#{i}", cache_name)
      end
    end
  end

  describe "performance characteristics" do
    test "achieves high hit rate with repeated accesses", %{cache: cache} do
      # Simulate typical usage pattern
      paths = for i <- 1..10, do: "/array#{i}"

      # Initial population (all misses)
      for path <- paths do
        {:error, :not_found} = MetadataCache.get(path, cache)
        :ok = MetadataCache.put(path, %{path: path}, cache)
      end

      # Repeated accesses (should be hits)
      for _ <- 1..10 do
        for path <- paths do
          {:ok, _} = MetadataCache.get(path, cache)
        end
      end

      stats = MetadataCache.stats(cache)

      # 10 initial misses, then 100 hits
      assert stats.misses == 10
      assert stats.hits == 100
      # >90% hit rate
      assert stats.hit_rate > 0.9
    end
  end
end
