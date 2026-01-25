defmodule ExZarr.Storage.BackendMoxTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExZarr.{Metadata, MetadataV3}
  alias ExZarr.Storage.Backend

  # Define mocks for storage backends
  defmock(MockStorageBackend, for: Backend)

  setup :verify_on_exit!

  describe "backend behavior with Mox" do
    test "init/1 behavior" do
      MockStorageBackend
      |> expect(:init, fn opts ->
        assert opts[:path] == "/test/path"
        {:ok, %{initialized: true, path: "/test/path"}}
      end)

      assert {:ok, %{initialized: true}} = MockStorageBackend.init(path: "/test/path")
    end

    test "read_metadata/1 behavior" do
      state = %{path: "/test"}

      MockStorageBackend
      |> expect(:read_metadata, fn ^state ->
        metadata = %Metadata{
          zarr_format: 2,
          shape: {100, 100},
          chunks: {10, 10},
          dtype: :float64,
          compressor: nil,
          fill_value: 0,
          order: "C",
          filters: nil
        }

        {:ok, metadata}
      end)

      assert {:ok, metadata} = MockStorageBackend.read_metadata(state)
      assert metadata.zarr_format == 2
    end

    test "write_metadata/3 behavior" do
      state = %{path: "/test"}

      metadata = %Metadata{
        zarr_format: 2,
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float64,
        compressor: nil,
        fill_value: 0,
        order: "C",
        filters: nil
      }

      MockStorageBackend
      |> expect(:write_metadata, fn ^state, ^metadata, _opts ->
        :ok
      end)

      assert :ok = MockStorageBackend.write_metadata(state, metadata, [])
    end

    test "read_chunk/2 behavior" do
      state = %{path: "/test"}
      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3, 4>>

      MockStorageBackend
      |> expect(:read_chunk, fn ^state, ^chunk_index ->
        {:ok, chunk_data}
      end)

      assert {:ok, ^chunk_data} = MockStorageBackend.read_chunk(state, chunk_index)
    end

    test "write_chunk/3 behavior" do
      state = %{path: "/test"}
      chunk_index = {1, 2}
      chunk_data = <<5, 6, 7, 8>>

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, ^chunk_index, ^chunk_data ->
        :ok
      end)

      assert :ok = MockStorageBackend.write_chunk(state, chunk_index, chunk_data)
    end

    test "list_chunks/1 behavior" do
      state = %{path: "/test"}
      chunks = [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      MockStorageBackend
      |> expect(:list_chunks, fn ^state ->
        {:ok, chunks}
      end)

      assert {:ok, ^chunks} = MockStorageBackend.list_chunks(state)
    end

    test "delete_chunk/2 behavior" do
      state = %{path: "/test"}
      chunk_index = {0, 0}

      MockStorageBackend
      |> expect(:delete_chunk, fn ^state, ^chunk_index ->
        :ok
      end)

      assert :ok = MockStorageBackend.delete_chunk(state, chunk_index)
    end

    test "exists?/1 behavior" do
      config = %{path: "/test"}

      MockStorageBackend
      |> expect(:exists?, fn ^config ->
        true
      end)

      assert true == MockStorageBackend.exists?(config)
    end
  end

  describe "error handling with Mox" do
    test "handles read_metadata errors" do
      state = %{path: "/nonexistent"}

      MockStorageBackend
      |> expect(:read_metadata, fn ^state ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = MockStorageBackend.read_metadata(state)
    end

    test "handles write_chunk errors" do
      state = %{path: "/readonly"}
      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3>>

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, ^chunk_index, ^chunk_data ->
        {:error, :permission_denied}
      end)

      assert {:error, :permission_denied} =
               MockStorageBackend.write_chunk(state, chunk_index, chunk_data)
    end

    test "handles read_chunk for missing chunk" do
      state = %{path: "/test"}
      chunk_index = {99, 99}

      MockStorageBackend
      |> expect(:read_chunk, fn ^state, ^chunk_index ->
        {:error, :chunk_not_found}
      end)

      assert {:error, :chunk_not_found} = MockStorageBackend.read_chunk(state, chunk_index)
    end

    test "handles list_chunks errors" do
      state = %{path: "/inaccessible"}

      MockStorageBackend
      |> expect(:list_chunks, fn ^state ->
        {:error, :access_denied}
      end)

      assert {:error, :access_denied} = MockStorageBackend.list_chunks(state)
    end
  end

  describe "multiple operations sequence with Mox" do
    test "write and read sequence" do
      state = %{path: "/test"}
      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3, 4, 5>>

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, ^chunk_index, ^chunk_data ->
        :ok
      end)
      |> expect(:read_chunk, fn ^state, ^chunk_index ->
        {:ok, chunk_data}
      end)

      # Write
      assert :ok = MockStorageBackend.write_chunk(state, chunk_index, chunk_data)

      # Read back
      assert {:ok, ^chunk_data} = MockStorageBackend.read_chunk(state, chunk_index)
    end

    test "write metadata, write chunks, list chunks" do
      state = %{path: "/test"}

      metadata = %Metadata{
        zarr_format: 2,
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float64,
        compressor: nil,
        fill_value: 0,
        order: "C",
        filters: nil
      }

      chunks = [{0, 0}, {0, 1}]

      MockStorageBackend
      |> expect(:write_metadata, fn ^state, ^metadata, _opts ->
        :ok
      end)
      |> expect(:write_chunk, 2, fn ^state, _chunk_index, _data ->
        :ok
      end)
      |> expect(:list_chunks, fn ^state ->
        {:ok, chunks}
      end)

      # Write metadata
      assert :ok = MockStorageBackend.write_metadata(state, metadata, [])

      # Write chunks
      assert :ok = MockStorageBackend.write_chunk(state, {0, 0}, <<1>>)
      assert :ok = MockStorageBackend.write_chunk(state, {0, 1}, <<2>>)

      # List chunks
      assert {:ok, ^chunks} = MockStorageBackend.list_chunks(state)
    end

    test "check existence before reading" do
      state = %{path: "/test"}
      config = %{path: "/test"}
      chunk_index = {0, 0}

      MockStorageBackend
      |> expect(:exists?, fn ^config ->
        true
      end)
      |> expect(:read_chunk, fn ^state, ^chunk_index ->
        {:ok, <<1, 2, 3>>}
      end)

      # Check if exists
      assert true == MockStorageBackend.exists?(config)

      # Then read
      assert {:ok, _data} = MockStorageBackend.read_chunk(state, chunk_index)
    end
  end

  describe "concurrent operations with Mox" do
    test "multiple concurrent reads" do
      state = %{path: "/test"}

      MockStorageBackend
      |> expect(:read_chunk, 3, fn ^state, chunk_index ->
        # Simulate reading different chunks
        {:ok, <<elem(chunk_index, 0)>>}
      end)

      # Simulate concurrent reads
      tasks =
        for i <- 0..2 do
          Task.async(fn ->
            MockStorageBackend.read_chunk(state, {i})
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, &match?({:ok, _}, &1))
      # Pattern match to verify we got exactly 3 results
      assert [_, _, _] = results
    end
  end

  describe "chunk index formats with Mox" do
    test "1D chunk indices" do
      state = %{path: "/test"}

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, {5}, _data ->
        :ok
      end)
      |> expect(:read_chunk, fn ^state, {5} ->
        {:ok, <<42>>}
      end)

      assert :ok = MockStorageBackend.write_chunk(state, {5}, <<42>>)
      assert {:ok, <<42>>} = MockStorageBackend.read_chunk(state, {5})
    end

    test "2D chunk indices" do
      state = %{path: "/test"}

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, {3, 7}, _data ->
        :ok
      end)
      |> expect(:read_chunk, fn ^state, {3, 7} ->
        {:ok, <<99>>}
      end)

      assert :ok = MockStorageBackend.write_chunk(state, {3, 7}, <<99>>)
      assert {:ok, <<99>>} = MockStorageBackend.read_chunk(state, {3, 7})
    end

    test "3D chunk indices" do
      state = %{path: "/test"}

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, {1, 2, 3}, _data ->
        :ok
      end)
      |> expect(:read_chunk, fn ^state, {1, 2, 3} ->
        {:ok, <<123>>}
      end)

      assert :ok = MockStorageBackend.write_chunk(state, {1, 2, 3}, <<123>>)
      assert {:ok, <<123>>} = MockStorageBackend.read_chunk(state, {1, 2, 3})
    end
  end

  describe "metadata handling with Mox" do
    test "v2 metadata structure" do
      state = %{path: "/test"}

      v2_metadata = %Metadata{
        zarr_format: 2,
        shape: {1000, 1000},
        chunks: {100, 100},
        dtype: :float32,
        compressor: :zstd,
        fill_value: 0,
        order: "C",
        filters: nil
      }

      MockStorageBackend
      |> expect(:write_metadata, fn ^state, ^v2_metadata, _opts ->
        :ok
      end)
      |> expect(:read_metadata, fn ^state ->
        {:ok, v2_metadata}
      end)

      assert :ok = MockStorageBackend.write_metadata(state, v2_metadata, [])
      assert {:ok, ^v2_metadata} = MockStorageBackend.read_metadata(state)
    end

    test "v3 metadata structure" do
      state = %{path: "/test"}

      v3_metadata = %MetadataV3{
        zarr_format: 3,
        node_type: :array,
        shape: {100, 100},
        data_type: "float64",
        chunk_grid: %{
          name: "regular",
          configuration: %{chunk_shape: {10, 10}}
        },
        chunk_key_encoding: %{name: "default"},
        codecs: [
          %{name: "bytes", configuration: %{}},
          %{name: "gzip", configuration: %{level: 5}}
        ],
        fill_value: 0,
        attributes: %{},
        dimension_names: nil
      }

      MockStorageBackend
      |> expect(:write_metadata, fn ^state, ^v3_metadata, _opts ->
        :ok
      end)
      |> expect(:read_metadata, fn ^state ->
        {:ok, v3_metadata}
      end)

      assert :ok = MockStorageBackend.write_metadata(state, v3_metadata, [])
      assert {:ok, ^v3_metadata} = MockStorageBackend.read_metadata(state)
    end
  end

  describe "edge cases with Mox" do
    test "empty chunk data" do
      state = %{path: "/test"}
      empty_data = <<>>

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, {0}, ^empty_data ->
        :ok
      end)
      |> expect(:read_chunk, fn ^state, {0} ->
        {:ok, empty_data}
      end)

      assert :ok = MockStorageBackend.write_chunk(state, {0}, empty_data)
      assert {:ok, ^empty_data} = MockStorageBackend.read_chunk(state, {0})
    end

    test "large chunk data" do
      state = %{path: "/test"}
      # 1MB of data
      large_data = :binary.copy(<<1>>, 1_000_000)

      MockStorageBackend
      |> expect(:write_chunk, fn ^state, {0}, ^large_data ->
        :ok
      end)
      |> expect(:read_chunk, fn ^state, {0} ->
        {:ok, large_data}
      end)

      assert :ok = MockStorageBackend.write_chunk(state, {0}, large_data)
      assert {:ok, ^large_data} = MockStorageBackend.read_chunk(state, {0})
    end

    test "empty chunk list" do
      state = %{path: "/test"}

      MockStorageBackend
      |> expect(:list_chunks, fn ^state ->
        {:ok, []}
      end)

      assert {:ok, []} = MockStorageBackend.list_chunks(state)
    end

    test "many chunks in list" do
      state = %{path: "/test"}
      many_chunks = for i <- 0..999, j <- 0..999, do: {i, j}

      MockStorageBackend
      |> expect(:list_chunks, fn ^state ->
        {:ok, many_chunks}
      end)

      assert {:ok, chunks} = MockStorageBackend.list_chunks(state)
      # Verify we got all chunks back (1 million = 1000 * 1000)
      assert chunks == many_chunks
    end
  end

  describe "delete operations with Mox" do
    test "delete existing chunk" do
      state = %{path: "/test"}
      config = %{path: "/test"}
      chunk_index = {5, 10}

      MockStorageBackend
      |> expect(:delete_chunk, fn ^state, ^chunk_index ->
        :ok
      end)
      |> expect(:exists?, fn ^config ->
        false
      end)

      assert :ok = MockStorageBackend.delete_chunk(state, chunk_index)
      assert false == MockStorageBackend.exists?(config)
    end

    test "delete non-existent chunk" do
      state = %{path: "/test"}
      chunk_index = {99, 99}

      MockStorageBackend
      |> expect(:delete_chunk, fn ^state, ^chunk_index ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = MockStorageBackend.delete_chunk(state, chunk_index)
    end
  end
end
