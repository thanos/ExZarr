defmodule ExZarr.StreamingPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ExZarr.Array

  defp shape_gen do
    map({integer(12..48), integer(12..48)}, fn {w, h} -> {w, h} end)
  end

  defp chunks_gen do
    map({integer(4..16), integer(4..16)}, fn {w, h} -> {w, h} end)
  end

  defp expected_chunk_count(shape, chunks) do
    shape
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(chunks))
    |> Enum.map(fn {array_dim, chunk_dim} ->
      div(array_dim + chunk_dim - 1, chunk_dim)
    end)
    |> Enum.reduce(1, &*/2)
  end

  defp chunk_binary(value \\ 1) do
    for(_ <- 1..100, into: <<>>, do: <<value::signed-little-32>>)
  end

  describe "streaming properties" do
    property "include_missing chunk count matches grid math" do
      check all(shape <- shape_gen(), chunks <- chunks_gen()) do
        tmp_dir = "/tmp/ex_zarr_stream_prop_#{System.unique_integer()}"
        File.mkdir_p!(tmp_dir)

        try do
          {:ok, array} =
            Array.create(
              shape: shape,
              chunks: chunks,
              dtype: :int32,
              storage: :filesystem,
              path: Path.join(tmp_dir, "count_test")
            )

          expected = expected_chunk_count(shape, chunks)

          actual =
            array
            |> Array.stream_chunks(include_missing: true)
            |> Enum.count()

          assert actual == expected
        after
          File.rm_rf(tmp_dir)
        end
      end
    end

    property "write_stream then stream_chunks roundtrip preserves bytes" do
      check all(value <- integer(1..255)) do
        tmp_dir = "/tmp/ex_zarr_stream_prop_#{System.unique_integer()}"
        File.mkdir_p!(tmp_dir)

        try do
          {:ok, array} =
            Array.create(
              shape: {10, 10},
              chunks: {10, 10},
              dtype: :int32,
              storage: :filesystem,
              path: Path.join(tmp_dir, "roundtrip_test")
            )

          data = chunk_binary(value)

          assert {:ok, %{written: 1}} =
                   Array.write_stream(array, [{{0, 0}, data}], validate: false)

          [{_index, read_data}] = array |> Array.stream_chunks() |> Enum.take(1)
          assert read_data == data
        after
          File.rm_rf(tmp_dir)
        end
      end
    end
  end
end
