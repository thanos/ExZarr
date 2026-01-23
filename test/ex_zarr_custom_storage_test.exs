defmodule ExZarr.CustomStorageTest do
  use ExUnit.Case
  alias ExZarr.Storage.Registry

  # Define a simple custom storage backend for testing
  defmodule TestStorageBackend do
    @behaviour ExZarr.Storage.Backend

    @impl true
    def backend_id, do: :test_storage

    @impl true
    def init(_config) do
      {:ok, agent} = Agent.start_link(fn -> %{chunks: %{}, metadata: nil} end)
      {:ok, %{agent: agent}}
    end

    @impl true
    def open(_config) do
      {:error, :cannot_open_test_storage}
    end

    @impl true
    def read_chunk(state, chunk_index) do
      Agent.get(state.agent, fn agent_state ->
        case Map.get(agent_state.chunks, chunk_index) do
          nil -> {:error, :not_found}
          data -> {:ok, data}
        end
      end)
    end

    @impl true
    def write_chunk(state, chunk_index, data) do
      Agent.update(state.agent, fn agent_state ->
        %{agent_state | chunks: Map.put(agent_state.chunks, chunk_index, data)}
      end)

      :ok
    end

    @impl true
    def read_metadata(state) do
      Agent.get(state.agent, fn agent_state ->
        case agent_state.metadata do
          nil -> {:error, :not_found}
          metadata -> {:ok, metadata}
        end
      end)
    end

    @impl true
    def write_metadata(state, metadata, _opts) do
      Agent.update(state.agent, fn agent_state ->
        %{agent_state | metadata: metadata}
      end)

      :ok
    end

    @impl true
    def list_chunks(state) do
      Agent.get(state.agent, fn agent_state ->
        {:ok, Map.keys(agent_state.chunks)}
      end)
    end

    @impl true
    def delete_chunk(state, chunk_index) do
      Agent.update(state.agent, fn agent_state ->
        %{agent_state | chunks: Map.delete(agent_state.chunks, chunk_index)}
      end)

      :ok
    end

    @impl true
    def exists?(_config), do: false

    # Optional: backend info
    def backend_info do
      %{
        id: :test_storage,
        module: __MODULE__,
        description: "Test storage backend",
        type: :custom,
        version: "1.0.0"
      }
    end
  end

  # Invalid backend (doesn't implement behavior)
  defmodule InvalidBackend do
    def backend_id, do: :invalid_backend
    # Missing required callbacks
  end

  describe "Backend behavior" do
    test "Backend.implements?/1 detects valid backends" do
      assert ExZarr.Storage.Backend.implements?(TestStorageBackend)
      assert ExZarr.Storage.Backend.implements?(ExZarr.Storage.Backend.Memory)
      assert ExZarr.Storage.Backend.implements?(ExZarr.Storage.Backend.Filesystem)
      assert ExZarr.Storage.Backend.implements?(ExZarr.Storage.Backend.Zip)
    end

    test "Backend.implements?/1 rejects invalid backends" do
      refute ExZarr.Storage.Backend.implements?(InvalidBackend)
      refute ExZarr.Storage.Backend.implements?(NonExistentModule)
    end
  end

  describe "Registry operations" do
    setup do
      # Ensure test backend is not registered at start
      Registry.unregister(:test_storage)
      :ok
    end

    test "lists built-in backends" do
      backends = Registry.list()
      assert :memory in backends
      assert :filesystem in backends
      assert :zip in backends
    end

    test "gets built-in backend modules" do
      assert {:ok, ExZarr.Storage.Backend.Memory} = Registry.get(:memory)
      assert {:ok, ExZarr.Storage.Backend.Filesystem} = Registry.get(:filesystem)
      assert {:ok, ExZarr.Storage.Backend.Zip} = Registry.get(:zip)
    end

    test "returns error for unknown backend" do
      assert {:error, :not_found} = Registry.get(:nonexistent)
    end

    test "gets backend info" do
      assert {:ok, info} = Registry.info(:memory)
      assert info.id == :memory
      assert info.description =~ "memory"
      assert info.type == :built_in

      assert {:ok, info} = Registry.info(:filesystem)
      assert info.id == :filesystem
      assert info.type == :built_in
    end

    test "registers custom backend" do
      assert :ok = Registry.register(TestStorageBackend)
      assert {:ok, TestStorageBackend} = Registry.get(:test_storage)
      assert :test_storage in Registry.list()
    end

    test "unregisters custom backend" do
      :ok = Registry.register(TestStorageBackend)
      assert :ok = Registry.unregister(:test_storage)
      assert {:error, :not_found} = Registry.get(:test_storage)
      refute :test_storage in Registry.list()
    end

    test "cannot unregister built-in backends" do
      assert {:error, :cannot_unregister_builtin} = Registry.unregister(:memory)
      assert {:error, :cannot_unregister_builtin} = Registry.unregister(:filesystem)
      assert {:error, :cannot_unregister_builtin} = Registry.unregister(:zip)
    end

    test "registers backend with force option" do
      :ok = Registry.register(TestStorageBackend)
      assert {:error, :already_registered} = Registry.register(TestStorageBackend)
      assert :ok = Registry.register(TestStorageBackend, force: true)
    end

    test "rejects invalid backend module" do
      assert {:error, :invalid_backend} = Registry.register(InvalidBackend)
    end

    test "gets custom backend info" do
      :ok = Registry.register(TestStorageBackend)
      assert {:ok, info} = Registry.info(:test_storage)
      assert info.id == :test_storage
      assert info.module == TestStorageBackend
      assert info.description == "Test storage backend"
      assert info.type == :custom
    end
  end

  describe "Using custom storage backend" do
    setup do
      Registry.unregister(:test_storage)
      :ok = Registry.register(TestStorageBackend)

      on_exit(fn ->
        Registry.unregister(:test_storage)
      end)
    end

    test "creates array with custom storage" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int32,
          storage: :test_storage
        )

      assert array.storage.backend == :test_storage
    end

    test "writes and reads data with custom storage" do
      {:ok, array} =
        ExZarr.create(
          shape: {50},
          chunks: {10},
          dtype: :float64,
          storage: :test_storage
        )

      data =
        for i <- 0..49, into: <<>> do
          value = i * 1.5
          <<value::float-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {50})

      assert read_data == data
    end

    test "works with filters and compression" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {20},
          dtype: :int64,
          filters: [{:delta, [dtype: :int64]}],
          compressor: :zlib,
          storage: :test_storage
        )

      data =
        for i <- 0..99, into: <<>> do
          <<i::signed-little-64>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
      {:ok, read_data} = ExZarr.Array.get_slice(array, start: {0}, stop: {100})

      assert read_data == data
    end

    test "handles multiple chunks" do
      {:ok, array} =
        ExZarr.create(
          shape: {500},
          chunks: {100},
          dtype: :int32,
          storage: :test_storage
        )

      data =
        for i <- 0..499, into: <<>> do
          <<i::signed-little-32>>
        end

      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})

      # Read partial slice crossing chunk boundary
      {:ok, partial} = ExZarr.Array.get_slice(array, start: {95}, stop: {105})

      expected =
        for i <- 95..104, into: <<>> do
          <<i::signed-little-32>>
        end

      assert partial == expected
    end

    test "metadata operations" do
      {:ok, array} =
        ExZarr.create(
          shape: {200, 150},
          chunks: {50, 30},
          dtype: :float32,
          storage: :test_storage
        )

      # Metadata is accessible
      assert array.metadata.shape == {200, 150}
      assert array.metadata.chunks == {50, 30}
      assert array.metadata.dtype == :float32
    end

    test "list chunks operation" do
      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {25},
          dtype: :int32,
          storage: :test_storage
        )

      # Initially no chunks
      {:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
      assert chunks == []

      # Write some data
      data = for i <- 0..99, into: <<>>, do: <<i::signed-little-32>>
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

      # Now we should have chunks
      {:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
      assert length(chunks) == 4  # 100/25 = 4 chunks
    end
  end

  describe "Error handling" do
    test "returns error for unregistered backend" do
      result = ExZarr.create(
        shape: {100},
        chunks: {10},
        storage: :nonexistent_backend
      )

      assert {:error, :invalid_storage_config} = result
    end

    test "backend errors propagate correctly" do
      Registry.unregister(:test_storage)
      :ok = Registry.register(TestStorageBackend)

      {:ok, array} =
        ExZarr.create(
          shape: {100},
          chunks: {10},
          dtype: :int32,
          storage: :test_storage
        )

      # Try to read non-existent chunk directly
      result = ExZarr.Storage.read_chunk(array.storage, {99})
      assert {:error, :not_found} = result
    end
  end
end
