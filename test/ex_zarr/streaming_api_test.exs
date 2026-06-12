defmodule ExZarr.StreamingApiTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

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

  describe "ExZarr.Telemetry" do
    test "emits stream events", %{tmp_dir: tmp_dir} do
      {:ok, array} = create_array(tmp_dir, "telemetry_test")
      :ok = Array.set_slice(array, chunk_data(), start: {0, 0}, stop: {10, 10})

      test_pid = self()

      :ok =
        :telemetry.attach(
          "stream-start-test",
          [:ex_zarr, :stream, :start],
          fn _event, _measurements, _metadata, pid ->
            send(pid, :stream_started)
          end,
          test_pid
        )

      :ok =
        :telemetry.attach(
          "stream-stop-test",
          [:ex_zarr, :stream, :stop],
          fn _event, _measurements, _metadata, pid ->
            send(pid, :stream_stopped)
          end,
          test_pid
        )

      array |> Array.stream_chunks() |> Enum.to_list()

      assert_receive :stream_started
      assert_receive :stream_stopped

      :telemetry.detach("stream-start-test")
      :telemetry.detach("stream-stop-test")
    end
  end
end
