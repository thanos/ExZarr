defmodule ExZarr.StreamingApiTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array
  alias ExZarr.Broadway.ChunkProducer

  setup do
    tmp_dir = "/tmp/ex_zarr_streaming_api_#{System.unique_integer()}"
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  defp create_array(tmp_dir, name, shape \\ {50, 50}, chunks \\ {10, 10}) do
    Array.create(
      shape: shape,
      chunks: chunks,
      dtype: :int32,
      storage: :filesystem,
      path: Path.join(tmp_dir, name)
    )
  end

  defp chunk_data(value \\ 1) do
    for(_ <- 1..100, into: <<>>, do: <<value::signed-little-32>>)
  end

  # GenStage producers stop with :normal after exhaustion; GenStage.stream/1
  # re-raises that exit during cleanup. Collect events in an Agent first.
  defp collect_gen_stage_messages(producer, opts \\ []) do
    max_demand = Keyword.get(opts, :max_demand, 1)
    {:ok, agent} = Agent.start_link(fn -> [] end)

    try do
      [{producer, max_demand: max_demand}]
      |> GenStage.stream()
      |> Stream.each(fn event -> Agent.update(agent, &[event | &1]) end)
      |> Stream.run()
    catch
      :exit, {:normal, {GenStage, :close_stream, _}} -> :ok
    end

    messages = Agent.get(agent, &Enum.reverse/1)
    Agent.stop(agent)
    messages
  end

  describe "stream_chunks/2" do
    test "is an alias for chunk_stream/2", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "alias_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      chunk_stream = array |> Array.chunk_stream() |> Enum.to_list()
      stream_chunks = array |> Array.stream_chunks() |> Enum.to_list()

      assert stream_chunks == chunk_stream
    end

    test "supports concurrency option", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "concurrency_test")

      for x <- [0, 10, 20], y <- [0, 10, 20] do
        :ok = Array.set_slice(array, chunk_data(7), start: {x, y}, stop: {x + 10, y + 10})
      end

      chunks =
        array
        |> Array.stream_chunks(concurrency: 4, ordered: false)
        |> Enum.to_list()

      assert length(chunks) >= 9
    end

    test "returns metadata when requested", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "metadata_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      [event | _] = array |> Array.stream_chunks(metadata: true) |> Enum.take(1)

      assert %{index: index, data: data, metadata: meta} = event
      assert is_tuple(index)
      assert is_binary(data)
      assert %{bounds: _, shape: _, bytes: _} = meta
    end

    test "include_missing streams all logical chunk indices", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "missing_test", {30, 30}, {10, 10})
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      stored =
        array
        |> Array.stream_chunks()
        |> Enum.count()

      all =
        array
        |> Array.stream_chunks(include_missing: true)
        |> Enum.count()

      assert all == 9
      assert stored < all
    end
  end

  describe "stream_slices/3" do
    test "streams unit slices along a dimension", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "slice_test", {20, 10}, {20, 10})

      for row <- 0..19 do
        data = for(_ <- 1..10, into: <<>>, do: <<row::signed-little-32>>)
        :ok = Array.set_slice(array, data, start: {row, 0}, stop: {row + 1, 10})
      end

      rows =
        array
        |> Array.stream_slices(0)
        |> Enum.map(fn {_start, data} ->
          <<value::signed-little-32, _rest::binary>> = data
          value
        end)

      assert rows == Enum.to_list(0..19)
    end

    test "returns no slices for empty region", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "empty_region_test", {20, 10}, {20, 10})

      for row <- 0..19 do
        data = for(_ <- 1..10, into: <<>>, do: <<row::signed-little-32>>)
        :ok = Array.set_slice(array, data, start: {row, 0}, stop: {row + 1, 10})
      end

      assert [] =
               array
               |> Array.stream_slices(0, start: {5, 0}, stop: {5, 10})
               |> Enum.to_list()
    end

    test "supports step option", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "step_test", {20, 10}, {20, 10})

      for row <- 0..19 do
        data = for(_ <- 1..10, into: <<>>, do: <<row::signed-little-32>>)
        :ok = Array.set_slice(array, data, start: {row, 0}, stop: {row + 1, 10})
      end

      rows =
        array
        |> Array.stream_slices(0, start: {0, 0}, stop: {10, 10}, step: 2)
        |> Enum.map(fn {start, _data} -> elem(start, 0) end)

      assert rows == [0, 2, 4, 6, 8]
    end

    test "supports bounded region", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "region_test", {30, 10}, {30, 10})

      for row <- 0..29 do
        data = for(_ <- 1..10, into: <<>>, do: <<row::signed-little-32>>)
        :ok = Array.set_slice(array, data, start: {row, 0}, stop: {row + 1, 10})
      end

      count =
        array
        |> Array.stream_slices(0, start: {5, 0}, stop: {15, 10})
        |> Enum.count()

      assert count == 10
    end
  end

  describe "write_stream/3" do
    test "writes chunks from a stream", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "write_test")

      stream =
        Stream.map([{0, 0}, {0, 1}, {1, 0}], fn index ->
          {index, chunk_data(99)}
        end)

      assert {:ok, %{written: 3}} = Array.write_stream(array, stream)

      {:ok, data} = Array.get_slice(array, start: {0, 0}, stop: {10, 10})
      <<value::signed-little-32, _rest::binary>> = data
      assert value == 99
    end

    test "validates chunk sizes by default", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "validate_test")

      stream = Stream.map([{{0, 0}, <<1, 2, 3>>}], & &1)

      assert {:error, {:invalid_chunk_size, _details}} = Array.write_stream(array, stream)
    end

    test "supports checkpoint callbacks", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "checkpoint_test")
      {:ok, agent} = Agent.start_link(fn -> [] end)

      stream = Stream.map([{{0, 0}, chunk_data()}], & &1)

      assert {:ok, %{written: 1}} =
               Array.write_stream(array, stream,
                 checkpoint: fn stats -> Agent.update(agent, &[stats | &1]) end
               )

      checkpoints = Agent.get(agent, & &1)
      assert Enum.any?(checkpoints, &(&1.written == 1))
    end

    test "skips invalid entries when on_error is :skip", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "invalid_entry_test")

      assert {:ok, %{written: 0, failed: 1}} =
               Array.write_stream(array, [:bad_entry], on_error: :skip)
    end

    test "batch_size > 1 invokes checkpoint across batches", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "batch_test")
      {:ok, agent} = Agent.start_link(fn -> [] end)

      stream =
        Stream.map(
          [
            {{0, 0}, chunk_data(1)},
            {{0, 1}, chunk_data(2)},
            {{1, 0}, chunk_data(3)}
          ],
          & &1
        )

      assert {:ok, %{written: 3}} =
               Array.write_stream(array, stream,
                 batch_size: 2,
                 checkpoint: fn stats -> Agent.update(agent, &[stats.written | &1]) end
               )

      checkpoints = Agent.get(agent, &Enum.reverse/1)
      assert checkpoints == [2, 3]
    end

    test "on_error callback receives failing index", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "callback_test")
      {:ok, agent} = Agent.start_link(fn -> [] end)

      stream =
        Stream.map(
          [
            {{0, 0}, chunk_data(1)},
            {{0, 0}, <<1, 2, 3>>}
          ],
          & &1
        )

      on_error = fn index, _reason -> Agent.update(agent, &[index | &1]) end

      assert {:ok, %{written: 1, failed: 1}} =
               Array.write_stream(array, stream, on_error: on_error)

      assert Agent.get(agent, & &1) == [{0, 0}]
    end

    test "on_error :halt stops on invalid entry", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "halt_write_test")

      assert {:error, {:invalid_entry, :bad_entry}} =
               Array.write_stream(array, [:bad_entry], on_error: :halt)
    end

    test "skips errors when on_error is :skip", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "skip_test")

      stream =
        Stream.map(
          [
            {{0, 0}, chunk_data(1)},
            {{0, 0}, <<1, 2, 3>>},
            {{0, 1}, chunk_data(2)}
          ],
          & &1
        )

      assert {:ok, %{written: 2, failed: 1}} =
               Array.write_stream(array, stream, on_error: :skip)
    end
  end

  describe "stream error handling" do
    test "on_error :halt raises StreamError on read failure", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "halt_read_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      failing_read = fn _array, _index -> {:error, :corrupt} end

      assert_raise ExZarr.StreamError, fn ->
        ExZarr.Streaming.stream_chunks(array, [on_error: :halt], failing_read)
        |> Enum.take(1)
      end
    end

    test "skips slow chunks on timeout with on_error :skip", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "timeout_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      slow_read = fn _array, _index ->
        Process.sleep(50)
        {:ok, chunk_data()}
      end

      result =
        ExZarr.Streaming.stream_chunks(
          array,
          [concurrency: 2, timeout: 1, on_error: :skip],
          slow_read
        )
        |> Enum.to_list()

      assert is_list(result)
    end
  end

  describe "ExZarr.Telemetry" do
    setup do
      test_id = "telemetry-#{System.unique_integer()}"

      on_exit(fn ->
        :telemetry.detach("#{test_id}-chunk-stop")
        :telemetry.detach("#{test_id}-stream-stop")
      end)

      {:ok, test_id: test_id}
    end

    test "events/0 includes span stop events", _context do
      events = ExZarr.Telemetry.events()

      assert [:ex_zarr, :chunk, :read, :stop] in events
      assert [:ex_zarr, :chunk, :write, :stop] in events
      assert [:ex_zarr, :stream, :start] in events
      assert [:ex_zarr, :stream, :stop] in events
    end

    test "emits stream and chunk events with measurements", %{tmp_dir: tmp_dir, test_id: test_id} do
      {:ok, array} = create_array(tmp_dir, "telemetry_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})
      array_ref = {array.shape, array.chunks, array.dtype}
      test_pid = self()

      :ok =
        :telemetry.attach(
          "#{test_id}-chunk-stop",
          [:ex_zarr, :chunk, :read, :stop],
          fn _event, measurements, metadata, pid ->
            send(pid, {:chunk_stop, measurements, metadata})
          end,
          test_pid
        )

      :ok =
        :telemetry.attach(
          "#{test_id}-stream-stop",
          [:ex_zarr, :stream, :stop],
          fn _event, measurements, metadata, pid ->
            send(pid, {:stream_stop, measurements, metadata})
          end,
          test_pid
        )

      array |> Array.stream_chunks() |> Enum.take(1)

      assert_receive {:chunk_stop, measurements, metadata}
                     when is_map(measurements) and is_map(metadata)

      assert is_integer(measurements.duration)

      assert_receive {:stream_stop, %{duration: stream_duration, count: count},
                      %{array: ^array_ref, type: :chunks}}
                     when is_integer(stream_duration) and count >= 1
    end
  end

  describe "pipeline integrations" do
    test "GenStage chunk producer stops after exhaustion", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "genstage_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      {:ok, producer} = ExZarr.GenStage.start_chunk_producer(array)

      events = collect_gen_stage_messages(producer)

      assert length(events) == 1
      Process.sleep(10)
      refute Process.alive?(producer)
    end

    test "GenStage accepts flat stream options", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "genstage_flat_opts")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      {:ok, producer} = ExZarr.GenStage.start_chunk_producer(array, metadata: true)

      [event | _] =
        [{producer, max_demand: 1}]
        |> GenStage.stream()
        |> Enum.take(1)

      assert %{index: _, data: _, metadata: _} = event
    end

    @tag :broadway
    test "Broadway producer does not duplicate successful chunks", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "broadway_dup_test", {20, 10}, {10, 10})

      for row <- 0..19 do
        data = for(_ <- 1..10, into: <<>>, do: <<row::signed-little-32>>)
        :ok = Array.set_slice(array, data, start: {row, 0}, stop: {row + 1, 10})
      end

      {:ok, producer} =
        ChunkProducer.start_link(
          array: array,
          stream_opts: [include_missing: true]
        )

      messages = collect_gen_stage_messages(producer, max_demand: 2)

      indices =
        messages
        |> Enum.map(fn %Broadway.Message{data: {index, _data}} -> index end)

      assert indices == Enum.uniq(indices)
      refute Process.alive?(producer)
    end

    test "Flow chunk_flow yields all stored chunks", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "flow_test")

      for x <- [0, 10], y <- [0, 10] do
        :ok = Array.set_slice(array, chunk_data(3), start: {x, y}, stop: {x + 10, y + 10})
      end

      count =
        array
        |> ExZarr.Flow.chunk_flow(stages: 2)
        |> Flow.map(fn {_index, data} -> byte_size(data) end)
        |> Enum.count()

      assert count >= 4
    end
  end
end
