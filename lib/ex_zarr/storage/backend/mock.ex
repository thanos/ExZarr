defmodule ExZarr.Storage.Backend.Mock do
  @moduledoc """
  Mock storage backend for testing.

  Provides a controllable storage backend that can simulate various
  scenarios including errors, delays, and state verification. Useful
  for testing error handling and edge cases without external dependencies.

  ## Configuration

  Optional configuration:
  - `:pid` - PID to receive operation messages (optional)
  - `:error_mode` - Simulate errors (`:always`, `:random`, or `nil`)
  - `:delay` - Simulate latency in milliseconds (optional)
  - `:fail_on` - List of operations to fail on (optional)

  ## Example

  ```elixir
  # Register the mock backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mock)

  # Create array with mock storage
  {:ok, array} = ExZarr.create(
    shape: {100},
    chunks: {10},
    dtype: :int32,
    storage: :mock,
    pid: self()
  )

  # Operations will send messages to the test process
  :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})

  # Verify operation was called
  assert_received {:mock_storage, :write_chunk, [{0}, _data]}
  ```

  ## Error Simulation

  ```elixir
  # Always fail
  {:ok, array} = ExZarr.create(
    storage: :mock,
    error_mode: :always
  )

  # Fail specific operations
  {:ok, array} = ExZarr.create(
    storage: :mock,
    fail_on: [:write_chunk, :read_metadata]
  )

  # Random failures (50% chance)
  {:ok, array} = ExZarr.create(
    storage: :mock,
    error_mode: :random
  )
  ```

  ## Latency Simulation

  ```elixir
  # Simulate 100ms delay on all operations
  {:ok, array} = ExZarr.create(
    storage: :mock,
    delay: 100
  )
  ```

  ## Testing Patterns

  The mock backend is useful for:
  - Testing error handling without external services
  - Simulating network latency
  - Verifying operation sequences
  - Testing concurrent access patterns
  - Integration testing without dependencies
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :mock

  @impl true
  def init(config) do
    {:ok, agent} = Agent.start_link(fn -> %{chunks: %{}, metadata: nil} end)

    state = %{
      agent: agent,
      pid: Keyword.get(config, :pid),
      error_mode: Keyword.get(config, :error_mode),
      delay: Keyword.get(config, :delay),
      fail_on: Keyword.get(config, :fail_on, []),
      call_count: %{}
    }

    send_message(state, :init, [config])
    {:ok, state}
  end

  @impl true
  def open(config) do
    pid = Keyword.get(config, :pid)
    send_message(%{pid: pid}, :open, [config])

    # Mock always succeeds on open
    init(config)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    maybe_delay(state)
    send_message(state, :read_chunk, [chunk_index])

    with :ok <- maybe_error(state, :read_chunk) do
      Agent.get(state.agent, fn agent_state ->
        case Map.get(agent_state.chunks, chunk_index) do
          nil -> {:error, :not_found}
          data -> {:ok, data}
        end
      end)
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    maybe_delay(state)
    send_message(state, :write_chunk, [chunk_index, data])

    case maybe_error(state, :write_chunk) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        Agent.update(state.agent, fn agent_state ->
          %{agent_state | chunks: Map.put(agent_state.chunks, chunk_index, data)}
        end)

        :ok
    end
  end

  @impl true
  def read_metadata(state) do
    maybe_delay(state)
    send_message(state, :read_metadata, [])

    with :ok <- maybe_error(state, :read_metadata) do
      Agent.get(state.agent, fn agent_state ->
        case agent_state.metadata do
          nil -> {:error, :not_found}
          metadata -> {:ok, metadata}
        end
      end)
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    maybe_delay(state)
    send_message(state, :write_metadata, [metadata])

    case maybe_error(state, :write_metadata) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        Agent.update(state.agent, fn agent_state ->
          %{agent_state | metadata: metadata}
        end)

        :ok
    end
  end

  @impl true
  def list_chunks(state) do
    maybe_delay(state)
    send_message(state, :list_chunks, [])

    case maybe_error(state, :list_chunks) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        Agent.get(state.agent, fn agent_state ->
          {:ok, Map.keys(agent_state.chunks)}
        end)
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    maybe_delay(state)
    send_message(state, :delete_chunk, [chunk_index])

    case maybe_error(state, :delete_chunk) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        Agent.update(state.agent, fn agent_state ->
          %{agent_state | chunks: Map.delete(agent_state.chunks, chunk_index)}
        end)

        :ok
    end
  end

  @impl true
  def exists?(_config) do
    # Mock always reports as existing
    true
  end

  ## Helper Functions

  @doc """
  Get the current state of a mock storage backend for verification.

  ## Example

      state = ExZarr.Storage.Backend.Mock.get_state(array.storage.state)
      assert map_size(state.chunks) == 5
  """
  def get_state(state) do
    Agent.get(state.agent, & &1)
  end

  @doc """
  Reset the mock storage state.

  ## Example

      :ok = ExZarr.Storage.Backend.Mock.reset(array.storage.state)
  """
  def reset(state) do
    Agent.update(state.agent, fn _ ->
      %{chunks: %{}, metadata: nil}
    end)
  end

  @doc """
  Get call count for operations.

  ## Example

      count = ExZarr.Storage.Backend.Mock.call_count(array.storage.state, :write_chunk)
      assert count == 10
  """
  def call_count(state, operation) do
    Map.get(state.call_count, operation, 0)
  end

  ## Private Helpers

  defp send_message(%{pid: pid}, operation, args) when is_pid(pid) do
    send(pid, {:mock_storage, operation, args})
  end

  defp send_message(_, _, _), do: :ok

  defp maybe_delay(%{delay: delay}) when is_integer(delay) and delay > 0 do
    Process.sleep(delay)
  end

  defp maybe_delay(_), do: :ok

  defp maybe_error(%{error_mode: :always}, _operation) do
    {:error, :mock_error}
  end

  defp maybe_error(%{error_mode: :random}, _operation) do
    if :rand.uniform() < 0.5 do
      {:error, :mock_random_error}
    else
      :ok
    end
  end

  defp maybe_error(%{fail_on: fail_list}, operation) when is_list(fail_list) do
    if operation in fail_list do
      {:error, {:mock_fail_on, operation}}
    else
      :ok
    end
  end

  defp maybe_error(_, _), do: :ok
end
