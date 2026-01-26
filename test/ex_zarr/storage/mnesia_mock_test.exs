defmodule ExZarr.Storage.MnesiaMockTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.Mnesia

  # Mock Mnesia for testing
  defmodule MockMnesia do
    # Storage for mock data
    defmodule Storage do
      use Agent

      def start_link(_) do
        Agent.start_link(fn -> %{} end, name: __MODULE__)
      end

      def get(key) do
        Agent.get(__MODULE__, fn state -> Map.get(state, key) end)
      end

      def put(key, value) do
        Agent.update(__MODULE__, fn state -> Map.put(state, key, value) end)
      end

      def all do
        Agent.get(__MODULE__, fn state -> state end)
      end

      def delete(key) do
        Agent.update(__MODULE__, fn state -> Map.delete(state, key) end)
      end

      def clear do
        Agent.update(__MODULE__, fn _ -> %{} end)
      end
    end

    def system_info(:is_running) do
      :yes
    end

    def start do
      send(self(), {:mnesia_start})
      :ok
    end

    def create_schema(_nodes) do
      send(self(), {:mnesia_create_schema})
      :ok
    end

    def create_table(table_name, _opts) do
      send(self(), {:mnesia_create_table, table_name})
      {:atomic, :ok}
    end

    def table_info(_table_name, :size) do
      Storage.all() |> map_size()
    end

    def transaction(fun) do
      result = fun.()
      {:atomic, result}
    rescue
      e -> {:aborted, e}
    end

    def read(table_name, key) do
      case Storage.get({table_name, key}) do
        nil -> []
        data -> [{table_name, key, data}]
      end
    end

    def write({table_name, key, data}) do
      Storage.put({table_name, key}, data)
      :ok
    end

    def select(table_name, [{pattern, [], [:"$1"]}]) do
      # Extract array_id and match chunks
      {^table_name, {array_id, {:chunk, :"$1"}}, :_} = pattern

      Storage.all()
      |> Enum.filter(fn
        {{t, {a, {:chunk, _}}}, _} -> t == table_name and a == array_id
        _ -> false
      end)
      |> Enum.map(fn {{_, {_, {:chunk, idx}}}, _} -> idx end)
    end

    def delete(table_name, key, :write) do
      Storage.delete({table_name, key})
      :ok
    end
  end

  setup do
    # Start mock storage
    start_supervised!(MockMnesia.Storage)
    MockMnesia.Storage.clear()

    # Inject mock module
    Application.put_env(:ex_zarr, :mnesia_module, MockMnesia)

    on_exit(fn ->
      Application.delete_env(:ex_zarr, :mnesia_module)
    end)

    :ok
  end

  describe "backend_id/0" do
    test "returns :mnesia" do
      assert Mnesia.backend_id() == :mnesia
    end
  end

  describe "init/1" do
    test "initializes with required fields" do
      config = [
        array_id: "array1",
        table_name: :zarr_test
      ]

      assert {:ok, state} = Mnesia.init(config)
      assert state.array_id == "array1"
      assert state.table_name == :zarr_test
    end

    test "uses default table name when not specified" do
      config = [array_id: "array1"]

      assert {:ok, state} = Mnesia.init(config)
      assert state.table_name == :zarr_storage
    end

    test "creates table if it doesn't exist" do
      config = [array_id: "array1", table_name: :new_table]

      assert {:ok, state} = Mnesia.init(config)
      assert state.table_name == :new_table

      assert_receive {:mnesia_create_table, :new_table}
    end

    test "returns error for missing array_id" do
      config = [table_name: :zarr_test]
      assert {:error, :array_id_required} = Mnesia.init(config)
    end

    test "handles ram_copies option" do
      config = [array_id: "array1", ram_copies: true]

      assert {:ok, _state} = Mnesia.init(config)
    end

    test "handles disc_copies by default" do
      config = [array_id: "array1", ram_copies: false]

      assert {:ok, _state} = Mnesia.init(config)
    end
  end

  describe "open/1" do
    test "opens existing array" do
      # Initialize first to create table
      init_config = [array_id: "array1", table_name: :zarr_test]
      {:ok, _} = Mnesia.init(init_config)

      # Now open
      config = [array_id: "array2", table_name: :zarr_test]
      assert {:ok, state} = Mnesia.open(config)
      assert state.array_id == "array2"
    end
  end

  describe "read_chunk/2" do
    test "reads chunk" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write first
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1, 2, 3, 4, 5>>)

      # Then read
      assert {:ok, data} = Mnesia.read_chunk(state, {0, 0})
      assert data == <<1, 2, 3, 4, 5>>
    end

    test "returns not_found for missing chunk" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert {:error, :not_found} = Mnesia.read_chunk(state, {99, 99})
    end

    test "handles 1D chunk indices" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert :ok = Mnesia.write_chunk(state, {42}, <<1, 2, 3>>)
      assert {:ok, _data} = Mnesia.read_chunk(state, {42})
    end

    test "handles 3D chunk indices" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert :ok = Mnesia.write_chunk(state, {1, 2, 3}, <<1, 2, 3>>)
      assert {:ok, _data} = Mnesia.read_chunk(state, {1, 2, 3})
    end
  end

  describe "write_chunk/3" do
    test "writes chunk" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      chunk_data = <<10, 20, 30>>
      assert :ok = Mnesia.write_chunk(state, {0, 0}, chunk_data)

      # Verify written
      assert {:ok, ^chunk_data} = Mnesia.read_chunk(state, {0, 0})
    end

    test "overwrites existing chunk" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1, 2, 3>>)
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<4, 5, 6>>)

      assert {:ok, <<4, 5, 6>>} = Mnesia.read_chunk(state, {0, 0})
    end

    test "writes chunk with different array_id" do
      {:ok, state1} = Mnesia.init(array_id: "array1")
      {:ok, state2} = Mnesia.init(array_id: "array2")

      assert :ok = Mnesia.write_chunk(state1, {0, 0}, <<1, 2, 3>>)
      assert :ok = Mnesia.write_chunk(state2, {0, 0}, <<4, 5, 6>>)

      assert {:ok, <<1, 2, 3>>} = Mnesia.read_chunk(state1, {0, 0})
      assert {:ok, <<4, 5, 6>>} = Mnesia.read_chunk(state2, {0, 0})
    end
  end

  describe "read_metadata/1" do
    test "reads metadata" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write first
      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = Mnesia.write_metadata(state, metadata, [])

      # Then read
      assert {:ok, ^metadata} = Mnesia.read_metadata(state)
    end

    test "returns not_found for missing metadata" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert {:error, :not_found} = Mnesia.read_metadata(state)
    end
  end

  describe "write_metadata/3" do
    test "writes metadata" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = Mnesia.write_metadata(state, metadata, [])

      # Verify written
      assert {:ok, ^metadata} = Mnesia.read_metadata(state)
    end

    test "overwrites existing metadata" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      metadata1 = Jason.encode!(%{zarr_format: 2, shape: [100]})
      metadata2 = Jason.encode!(%{zarr_format: 2, shape: [200]})

      assert :ok = Mnesia.write_metadata(state, metadata1, [])
      assert :ok = Mnesia.write_metadata(state, metadata2, [])

      assert {:ok, ^metadata2} = Mnesia.read_metadata(state)
    end
  end

  describe "list_chunks/1" do
    test "lists chunks" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write some chunks
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1>>)
      assert :ok = Mnesia.write_chunk(state, {0, 1}, <<2>>)
      assert :ok = Mnesia.write_chunk(state, {1, 0}, <<3>>)

      assert {:ok, chunks} = Mnesia.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}]
    end

    test "returns empty list when no chunks" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert {:ok, []} = Mnesia.list_chunks(state)
    end

    test "does not include metadata in chunk list" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write metadata and chunks
      assert :ok = Mnesia.write_metadata(state, Jason.encode!(%{zarr_format: 2}), [])
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1>>)

      assert {:ok, chunks} = Mnesia.list_chunks(state)
      assert chunks == [{0, 0}]
    end

    test "isolates arrays by array_id" do
      {:ok, state1} = Mnesia.init(array_id: "array1")
      {:ok, state2} = Mnesia.init(array_id: "array2")

      assert :ok = Mnesia.write_chunk(state1, {0, 0}, <<1>>)
      assert :ok = Mnesia.write_chunk(state2, {0, 0}, <<2>>)

      assert {:ok, chunks1} = Mnesia.list_chunks(state1)
      assert {:ok, chunks2} = Mnesia.list_chunks(state2)

      assert chunks1 == [{0, 0}]
      assert chunks2 == [{0, 0}]
    end
  end

  describe "delete_chunk/2" do
    test "deletes chunk" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write and verify
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1, 2, 3>>)
      assert {:ok, _} = Mnesia.read_chunk(state, {0, 0})

      # Delete and verify gone
      assert :ok = Mnesia.delete_chunk(state, {0, 0})
      assert {:error, :not_found} = Mnesia.read_chunk(state, {0, 0})
    end

    test "succeeds for non-existent chunk" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      assert :ok = Mnesia.delete_chunk(state, {99, 99})
    end

    test "removes chunk from list" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write multiple chunks
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1>>)
      assert :ok = Mnesia.write_chunk(state, {0, 1}, <<2>>)
      assert :ok = Mnesia.write_chunk(state, {1, 0}, <<3>>)

      # Delete one
      assert :ok = Mnesia.delete_chunk(state, {0, 1})

      # Verify list
      assert {:ok, chunks} = Mnesia.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {1, 0}]
    end
  end

  describe "exists?/1" do
    test "returns true for existing table" do
      config = [array_id: "array1", table_name: :zarr_test]
      {:ok, _state} = Mnesia.init(config)

      assert Mnesia.exists?(config)
    end
  end

  describe "integration scenarios" do
    test "complete read/write cycle" do
      {:ok, state} = Mnesia.init(array_id: "test")

      # Write metadata
      metadata = Jason.encode!(%{zarr_format: 2})
      assert :ok = Mnesia.write_metadata(state, metadata, [])

      # Write chunks
      assert :ok = Mnesia.write_chunk(state, {0, 0}, <<1, 2, 3>>)
      assert :ok = Mnesia.write_chunk(state, {0, 1}, <<4, 5, 6>>)

      # Read chunks
      assert {:ok, <<1, 2, 3>>} = Mnesia.read_chunk(state, {0, 0})
      assert {:ok, <<4, 5, 6>>} = Mnesia.read_chunk(state, {0, 1})

      # List chunks
      assert {:ok, chunks} = Mnesia.list_chunks(state)
      assert length(chunks) == 2

      # Delete chunk
      assert :ok = Mnesia.delete_chunk(state, {0, 0})
      assert {:error, :not_found} = Mnesia.read_chunk(state, {0, 0})
    end

    test "multiple arrays in same table" do
      {:ok, state1} = Mnesia.init(array_id: "array1")
      {:ok, state2} = Mnesia.init(array_id: "array2")

      # Write to both arrays
      assert :ok = Mnesia.write_chunk(state1, {0, 0}, <<1>>)
      assert :ok = Mnesia.write_chunk(state2, {0, 0}, <<2>>)

      # Verify isolation
      assert {:ok, <<1>>} = Mnesia.read_chunk(state1, {0, 0})
      assert {:ok, <<2>>} = Mnesia.read_chunk(state2, {0, 0})
    end
  end

  describe "concurrent operations" do
    test "handles concurrent writes" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            Mnesia.write_chunk(state, {i}, <<i>>)
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :ok))

      # Verify all written
      for i <- 0..4 do
        assert {:ok, <<^i>>} = Mnesia.read_chunk(state, {i})
      end
    end

    test "handles concurrent reads" do
      {:ok, state} = Mnesia.init(array_id: "array1")

      # Write first
      for i <- 0..4 do
        assert :ok = Mnesia.write_chunk(state, {i}, <<i>>)
      end

      # Then read concurrently
      tasks =
        for i <- 0..4 do
          Task.async(fn ->
            Mnesia.read_chunk(state, {i})
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
