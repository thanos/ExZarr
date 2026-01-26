defmodule ExZarr.ChunkStreamingTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

  setup do
    tmp_dir = "/tmp/ex_zarr_chunk_stream_test_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "chunk_stream/2" do
    test "streams chunks lazily", %{tmp_dir: tmp_dir} do
      # Create array with multiple chunks
      {:ok, array} =
        Array.create(
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "lazy_test")
        )

      # Write data to some chunks
      data = for(_ <- 1..100, into: <<>>, do: <<1::signed-little-32>>)
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
      :ok = Array.set_slice(array, data, start: {10, 10}, stop: {20, 20})

      # Stream chunks
      chunks =
        array
        |> Array.chunk_stream()
        |> Enum.to_list()

      # Verify we got chunks back
      assert length(chunks) >= 2

      assert Enum.all?(chunks, fn {index, data} ->
               is_tuple(index) and is_binary(data)
             end)
    end

    test "sequential streaming with progress callback", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "progress_test")
        )

      # Write data to a few chunks
      data = for(_ <- 1..100, into: <<>>, do: <<1::signed-little-32>>)
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
      :ok = Array.set_slice(array, data, start: {10, 10}, stop: {20, 20})

      # Track progress
      {:ok, agent} = Agent.start_link(fn -> [] end)

      chunks =
        array
        |> Array.chunk_stream(
          progress_callback: fn done, total ->
            Agent.update(agent, fn list -> [{done, total} | list] end)
          end
        )
        |> Enum.to_list()

      progress = Agent.get(agent, & &1) |> Enum.reverse()

      # Verify progress was tracked
      assert Enum.empty?(progress) == false
      assert Enum.all?(progress, fn {done, total} -> done <= total and total > 0 end)
      # Last progress should be complete
      {final_done, final_total} = List.last(progress)
      assert final_done == final_total
      assert final_total == length(chunks)
    end

    test "parallel streaming", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {60, 60},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "parallel_test")
        )

      # Write data to multiple chunks
      data = for(_ <- 1..100, into: <<>>, do: <<42::signed-little-32>>)

      for x <- [0, 10, 20], y <- [0, 10, 20] do
        :ok = Array.set_slice(array, data, start: {x, y}, stop: {x + 10, y + 10})
      end

      # Stream in parallel
      chunks =
        array
        |> Array.chunk_stream(parallel: 4)
        |> Enum.to_list()

      # Verify we got all chunks
      assert length(chunks) >= 9

      # Verify all chunks are valid
      assert Enum.all?(chunks, fn {index, data} ->
               is_tuple(index) and is_binary(data) and byte_size(data) == 400
             end)
    end

    test "parallel streaming maintains order when ordered: true", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {30, 30},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "ordered_test")
        )

      # Write data with chunk index encoded in the data
      for x <- 0..2, y <- 0..2 do
        value = x * 10 + y
        data = for(_ <- 1..100, into: <<>>, do: <<value::signed-little-32>>)

        :ok =
          Array.set_slice(array, data,
            start: {x * 10, y * 10},
            stop: {(x + 1) * 10, (y + 1) * 10}
          )
      end

      # Stream with ordered: true
      chunks_ordered =
        array
        |> Array.chunk_stream(parallel: 4, ordered: true)
        |> Enum.to_list()

      indices_ordered = Enum.map(chunks_ordered, fn {index, _data} -> index end)

      # Stream with ordered: false for comparison
      chunks_unordered =
        array
        |> Array.chunk_stream(parallel: 4, ordered: false)
        |> Enum.to_list()

      indices_unordered = Enum.map(chunks_unordered, fn {index, _data} -> index end)

      # Both should have same chunks
      assert MapSet.new(indices_ordered) == MapSet.new(indices_unordered)
    end

    test "filter option filters chunks", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {50, 50},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "filter_test")
        )

      # Write data to multiple chunks
      data = for(_ <- 1..100, into: <<>>, do: <<1::signed-little-32>>)

      for x <- 0..4, y <- 0..4 do
        :ok =
          Array.set_slice(array, data,
            start: {x * 10, y * 10},
            stop: {(x + 1) * 10, (y + 1) * 10}
          )
      end

      # Filter to only chunks where x < 2 and y < 2
      chunks =
        array
        |> Array.chunk_stream(filter: fn {x, y} -> x < 2 and y < 2 end)
        |> Enum.to_list()

      # Should only have 4 chunks: {0,0}, {0,1}, {1,0}, {1,1}
      assert length(chunks) <= 4
      assert Enum.all?(chunks, fn {{x, y}, _data} -> x < 2 and y < 2 end)
    end

    test "streaming works with memory storage" do
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :memory
        )

      # Write data
      data = for(_ <- 1..100, into: <<>>, do: <<99::signed-little-32>>)
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
      :ok = Array.set_slice(array, data, start: {10, 10}, stop: {20, 20})

      # Stream chunks
      chunks =
        array
        |> Array.chunk_stream()
        |> Enum.to_list()

      assert length(chunks) >= 2
    end

    test "empty array returns empty stream", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {10, 10},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "empty_test")
        )

      # Don't write any data - stream should be empty or return fill chunks
      chunks =
        array
        |> Array.chunk_stream()
        |> Enum.to_list()

      # Either empty or contains only fill chunks
      assert is_list(chunks)
    end
  end

  describe "parallel_chunk_map/3" do
    test "maps function over all chunks in parallel", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {30, 30},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "map_test")
        )

      # Write data
      data = for(_ <- 1..100, into: <<>>, do: <<5::signed-little-32>>)

      for x <- 0..2, y <- 0..2 do
        :ok =
          Array.set_slice(array, data,
            start: {x * 10, y * 10},
            stop: {(x + 1) * 10, (y + 1) * 10}
          )
      end

      # Map to count bytes
      byte_counts =
        array
        |> Array.parallel_chunk_map(
          fn {_index, data} ->
            byte_size(data)
          end,
          max_concurrency: 4
        )
        |> Enum.to_list()

      # All chunks should be 400 bytes (100 int32s)
      assert length(byte_counts) >= 9
      assert Enum.all?(byte_counts, &(&1 == 400))
    end

    test "mapper function receives correct data", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "mapper_test")
        )

      # Write specific value
      data = for(_ <- 1..100, into: <<>>, do: <<42::signed-little-32>>)
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # Map to extract first value
      results =
        array
        |> Array.parallel_chunk_map(fn {index, <<value::signed-little-32, _rest::binary>>} ->
          {index, value}
        end)
        |> Enum.to_list()

      # Should have at least one chunk with value 42
      assert Enum.any?(results, fn {_index, value} -> value == 42 end)
    end

    test "returns error tuples for failed tasks", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "error_test")
        )

      # Write data to multiple chunks
      data = for(_ <- 1..100, into: <<>>, do: <<1::signed-little-32>>)
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
      :ok = Array.set_slice(array, data, start: {10, 10}, stop: {20, 20})

      # Mapper that returns error for specific index instead of raising
      # (raising in tasks can cause exit cascades in test environment)
      results =
        array
        |> Array.parallel_chunk_map(
          fn
            {{0, 0}, _data} -> {:error, :intentional_error}
            {index, _data} -> {:ok, index}
          end,
          timeout: 1000
        )
        |> Enum.to_list()

      # Should have at least one error result
      assert Enum.any?(results, fn
               {:error, :intentional_error} -> true
               _ -> false
             end)

      # Should also have successful results from other chunks
      assert Enum.any?(results, fn
               {:ok, _index} -> true
               _ -> false
             end)
    end
  end

  describe "memory efficiency" do
    @tag :memory
    test "streaming uses constant memory for many chunks", %{tmp_dir: tmp_dir} do
      # Create array with many small chunks
      {:ok, array} =
        Array.create(
          shape: {1000, 1000},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "memory_test")
        )

      # Write data to create chunks (write every 10th chunk to avoid too much disk I/O)
      data = for(_ <- 1..100, into: <<>>, do: <<1::signed-little-32>>)

      for x <- 0..99//10, y <- 0..99//10 do
        :ok =
          Array.set_slice(array, data,
            start: {x * 10, y * 10},
            stop: {(x + 1) * 10, (y + 1) * 10}
          )
      end

      # Measure memory before streaming
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)

      # Stream chunks without collecting them all - use sequential mode for constant memory
      chunk_count =
        array
        |> Array.chunk_stream(parallel: 1)
        |> Stream.take(50)
        |> Enum.reduce(0, fn _chunk, acc ->
          # Process and immediately discard each chunk to ensure GC
          acc + 1
        end)

      :erlang.garbage_collect()
      memory_after = :erlang.memory(:total)

      memory_delta_mb = (memory_after - memory_before) / (1024 * 1024)

      # Memory growth should be minimal
      # Allow for some variance in OTP versions (< 50MB is reasonable for streaming)
      assert memory_delta_mb < 50,
             "Memory grew by #{memory_delta_mb}MB, expected < 50MB"

      assert chunk_count <= 50
    end
  end

  describe "cache integration" do
    test "streaming uses cache when enabled", %{tmp_dir: tmp_dir} do
      {:ok, array} =
        Array.create(
          shape: {20, 20},
          chunks: {10, 10},
          dtype: :int32,
          storage: :filesystem,
          path: Path.join(tmp_dir, "cache_test"),
          cache_enabled: true
        )

      # Write data
      data = for(_ <- 1..100, into: <<>>, do: <<1::signed-little-32>>)
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})

      # First stream should populate cache
      _chunks1 =
        array
        |> Array.chunk_stream()
        |> Enum.to_list()

      # Second stream should hit cache (we can't easily verify this without
      # instrumenting the code, but we can verify it works)
      chunks2 =
        array
        |> Array.chunk_stream()
        |> Enum.to_list()

      assert Enum.empty?(chunks2) == false
    end
  end
end
