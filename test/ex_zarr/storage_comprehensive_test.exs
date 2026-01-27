defmodule ExZarr.StorageComprehensiveTest do
  use ExUnit.Case, async: true

  alias ExZarr.Metadata
  alias ExZarr.Storage

  setup do
    # Ensure mock backend is registered (ignore if already registered)
    case ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mock) do
      :ok -> :ok
      {:error, :already_registered} -> :ok
    end

    :ok
  end

  describe "Storage.init/1" do
    test "initializes memory storage" do
      config = %{storage_type: :memory, path: "test_array"}
      assert {:ok, storage} = Storage.init(config)
      assert storage.backend == :memory
      assert is_map(storage.state)
    end

    test "initializes mock storage" do
      config = %{storage_type: :mock}
      assert {:ok, storage} = Storage.init(config)
      assert storage.backend == :mock
      assert is_map(storage.state)
    end

    test "initializes mock storage with options" do
      config = %{storage_type: :mock, pid: self(), delay: 10}
      assert {:ok, storage} = Storage.init(config)
      assert storage.state.pid == self()
      assert storage.state.delay == 10
    end

    test "returns error for invalid storage config" do
      assert {:error, :invalid_storage_config} = Storage.init(%{invalid: :config})
    end

    test "returns error for missing storage_type" do
      assert {:error, :invalid_storage_config} = Storage.init(%{path: "test"})
    end

    test "returns error for unknown backend" do
      config = %{storage_type: :nonexistent_backend}
      assert {:error, _} = Storage.init(config)
    end
  end

  describe "Storage.write_chunk/3 and read_chunk/2" do
    test "writes and reads chunk with memory storage" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_data = <<1, 2, 3, 4, 5, 6, 7, 8>>
      chunk_index = {0, 0}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)
    end

    test "writes and reads chunk with mock storage" do
      {:ok, storage} = Storage.init(%{storage_type: :mock})

      chunk_data = <<1, 2, 3, 4, 5, 6, 7, 8>>
      chunk_index = {0, 0}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)
    end

    test "reads nonexistent chunk returns error" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      assert {:error, :not_found} = Storage.read_chunk(storage, {0, 0})
    end

    test "writes and reads multiple chunks" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunks = [
        {{0, 0}, <<1, 2, 3, 4>>},
        {{0, 1}, <<5, 6, 7, 8>>},
        {{1, 0}, <<9, 10, 11, 12>>}
      ]

      for {index, data} <- chunks do
        assert :ok = Storage.write_chunk(storage, index, data)
      end

      for {index, expected_data} <- chunks do
        assert {:ok, ^expected_data} = Storage.read_chunk(storage, index)
      end
    end

    test "overwrites existing chunk" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_index = {0, 0}
      original_data = <<1, 2, 3, 4>>
      new_data = <<5, 6, 7, 8>>

      assert :ok = Storage.write_chunk(storage, chunk_index, original_data)
      assert {:ok, ^original_data} = Storage.read_chunk(storage, chunk_index)

      assert :ok = Storage.write_chunk(storage, chunk_index, new_data)
      assert {:ok, ^new_data} = Storage.read_chunk(storage, chunk_index)
    end

    test "handles 1D chunk indices" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_data = <<1, 2, 3, 4>>
      chunk_index = {5}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)
    end

    test "handles 3D chunk indices" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_data = <<1, 2, 3, 4>>
      chunk_index = {1, 2, 3}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)
    end

    test "handles large chunk data" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      # 1MB of data
      chunk_data = :binary.copy(<<42>>, 1_000_000)
      chunk_index = {0}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)
    end

    test "handles empty chunk data" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_data = <<>>
      chunk_index = {0}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)
    end
  end

  describe "Storage.delete_chunk/2" do
    test "deletes existing chunk" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_data = <<1, 2, 3, 4>>
      chunk_index = {0, 0}

      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)
      assert {:ok, ^chunk_data} = Storage.read_chunk(storage, chunk_index)

      assert :ok = Storage.delete_chunk(storage, chunk_index)
      assert {:error, :not_found} = Storage.read_chunk(storage, chunk_index)
    end

    test "delete nonexistent chunk returns ok" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      # Deleting non-existent chunk should succeed (idempotent)
      assert :ok = Storage.delete_chunk(storage, {0, 0})
    end

    test "deletes multiple chunks" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunks = [{{0, 0}, <<1>>}, {{0, 1}, <<2>>}, {{1, 0}, <<3>>}]

      for {index, data} <- chunks do
        assert :ok = Storage.write_chunk(storage, index, data)
      end

      for {index, _} <- chunks do
        assert :ok = Storage.delete_chunk(storage, index)
        assert {:error, :not_found} = Storage.read_chunk(storage, index)
      end
    end
  end

  describe "Storage.write_metadata/3 and read_metadata/1" do
    test "writes and reads metadata" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      metadata = %Metadata{
        shape: {100, 100},
        chunks: {10, 10},
        dtype: :float64,
        compressor: :zlib,
        fill_value: 0.0,
        order: "C",
        zarr_format: 2
      }

      assert :ok = Storage.write_metadata(storage, metadata, zarr_version: 2)
      assert {:ok, read_metadata} = Storage.read_metadata(storage)

      assert read_metadata.shape == metadata.shape
      assert read_metadata.chunks == metadata.chunks
      assert read_metadata.dtype == metadata.dtype
    end

    test "reads nonexistent metadata returns error" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      assert {:error, _} = Storage.read_metadata(storage)
    end

    test "overwrites existing metadata" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      metadata1 = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float32,
        compressor: :zlib,
        zarr_format: 2
      }

      metadata2 = %Metadata{
        shape: {200},
        chunks: {20},
        dtype: :int32,
        compressor: :gzip,
        zarr_format: 2
      }

      assert :ok = Storage.write_metadata(storage, metadata1, zarr_version: 2)
      assert {:ok, read1} = Storage.read_metadata(storage)
      assert read1.shape == {100}

      assert :ok = Storage.write_metadata(storage, metadata2, zarr_version: 2)
      assert {:ok, read2} = Storage.read_metadata(storage)
      assert read2.shape == {200}
      assert read2.dtype == :int32
    end

    test "writes metadata with different compressors" do
      for compressor <- [:zlib, :gzip, :zstd, nil] do
        {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test_#{compressor}"})

        metadata = %Metadata{
          shape: {100},
          chunks: {10},
          dtype: :float64,
          compressor: compressor,
          zarr_format: 2
        }

        assert :ok = Storage.write_metadata(storage, metadata, zarr_version: 2)
        assert {:ok, read_metadata} = Storage.read_metadata(storage)
        assert read_metadata.compressor == compressor
      end
    end

    test "writes metadata with filters" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :int32,
        compressor: :zlib,
        filters: [{:delta, [dtype: :int32]}],
        zarr_format: 2
      }

      assert :ok = Storage.write_metadata(storage, metadata, zarr_version: 2)
      assert {:ok, read_metadata} = Storage.read_metadata(storage)
      # Delta filter encoding includes both dtype and astype
      assert read_metadata.filters == [{:delta, [dtype: :int32, astype: :int32]}]
    end
  end

  describe "Storage.list_chunks/1" do
    test "lists no chunks when empty" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      assert {:ok, []} = Storage.list_chunks(storage)
    end

    test "lists single chunk" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      chunk_index = {0, 0}
      assert :ok = Storage.write_chunk(storage, chunk_index, <<1, 2, 3>>)

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert chunk_index in chunks
      assert length(chunks) == 1
    end

    test "lists multiple chunks" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      indices = [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      for index <- indices do
        assert :ok = Storage.write_chunk(storage, index, <<1, 2, 3>>)
      end

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert length(chunks) == 4

      for index <- indices do
        assert index in chunks
      end
    end

    test "list does not include deleted chunks" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      indices = [{0, 0}, {0, 1}, {1, 0}]

      for index <- indices do
        assert :ok = Storage.write_chunk(storage, index, <<1>>)
      end

      assert :ok = Storage.delete_chunk(storage, {0, 1})

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert length(chunks) == 2
      assert {0, 0} in chunks
      assert {1, 0} in chunks
      refute {0, 1} in chunks
    end

    test "lists 1D chunks" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      for i <- 0..5 do
        assert :ok = Storage.write_chunk(storage, {i}, <<i>>)
      end

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert length(chunks) == 6
    end

    test "lists 3D chunks" do
      {:ok, storage} = Storage.init(%{storage_type: :memory, path: "test"})

      indices = [{0, 0, 0}, {0, 0, 1}, {1, 1, 1}]

      for index <- indices do
        assert :ok = Storage.write_chunk(storage, index, <<1>>)
      end

      assert {:ok, chunks} = Storage.list_chunks(storage)
      assert length(chunks) == 3

      for index <- indices do
        assert index in chunks
      end
    end
  end

  describe "Mock backend error simulation" do
    test "simulates read errors" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          fail_on: [:read_chunk]
        })

      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3, 4>>

      # Write should succeed
      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)

      # Read should fail
      assert {:error, _} = Storage.read_chunk(storage, chunk_index)
    end

    test "simulates write errors" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          fail_on: [:write_chunk]
        })

      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3, 4>>

      # Write should fail
      assert {:error, _} = Storage.write_chunk(storage, chunk_index, chunk_data)
    end

    test "simulates metadata read errors" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          fail_on: [:read_metadata]
        })

      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        zarr_format: 2
      }

      # Write should succeed
      assert :ok = Storage.write_metadata(storage, metadata, zarr_version: 2)

      # Read should fail
      assert {:error, _} = Storage.read_metadata(storage)
    end

    test "simulates metadata write errors" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          fail_on: [:write_metadata]
        })

      metadata = %Metadata{
        shape: {100},
        chunks: {10},
        dtype: :float64,
        compressor: :zlib,
        zarr_format: 2
      }

      # Write should fail
      assert {:error, _} = Storage.write_metadata(storage, metadata, zarr_version: 2)
    end

    test "simulates list chunks errors" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          fail_on: [:list_chunks]
        })

      # List should fail
      assert {:error, _} = Storage.list_chunks(storage)
    end

    test "simulates delete errors" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          fail_on: [:delete_chunk]
        })

      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3, 4>>

      # Write should succeed
      assert :ok = Storage.write_chunk(storage, chunk_index, chunk_data)

      # Delete should fail
      assert {:error, _} = Storage.delete_chunk(storage, chunk_index)
    end

    test "sends messages when pid is configured" do
      {:ok, storage} =
        Storage.init(%{
          storage_type: :mock,
          pid: self()
        })

      chunk_index = {0, 0}
      chunk_data = <<1, 2, 3, 4>>

      Storage.write_chunk(storage, chunk_index, chunk_data)
      assert_received {:mock_storage, :write_chunk, _}

      Storage.read_chunk(storage, chunk_index)
      assert_received {:mock_storage, :read_chunk, _}

      Storage.list_chunks(storage)
      assert_received {:mock_storage, :list_chunks, _}

      Storage.delete_chunk(storage, chunk_index)
      assert_received {:mock_storage, :delete_chunk, _}
    end
  end

  describe "Storage.open/1" do
    test "returns error when opening memory storage (not supported)" do
      # Memory storage is ephemeral and doesn't support opening existing storage
      result =
        Storage.open(
          storage: :memory,
          path: "test_open"
        )

      assert {:error, :cannot_open_memory_storage} = result
    end

    test "returns error when opening nonexistent storage" do
      result =
        Storage.open(
          storage: :memory,
          path: "nonexistent"
        )

      assert {:error, _} = result
    end

    test "initializes mock storage on open" do
      # Mock backend creates new storage on open (for testing purposes)
      result = Storage.open(storage: :mock)

      # Mock backend should return ok result
      assert {:ok, _storage} = result
    end
  end
end
