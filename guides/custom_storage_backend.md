# Implementing a Custom Storage Backend

ExZarr's pluggable storage architecture allows you to extend it with custom backends for proprietary systems, specialized databases, or novel storage architectures. This guide explains the behavior contract, provides complete working examples, and covers testing and performance considerations.

## When to Implement a Custom Backend

### Good Use Cases

Implement a custom backend when:

**Internal object storage systems:**
- Ceph, MinIO, or proprietary object stores
- Network-attached storage with custom protocols
- Distributed filesystems (HDFS, GlusterFS)

**Specialized databases:**
- Cassandra (wide-column store for distributed data)
- DynamoDB (AWS NoSQL with predictable performance)
- Redis (in-memory with persistence options)
- ScyllaDB (high-performance Cassandra alternative)

**Network protocols:**
- FTP/SFTP (legacy file transfer systems)
- WebDAV (HTTP-based file storage)
- NFS/SMB (network file shares)

**Virtual filesystems:**
- Custom abstractions over multiple backends
- Tiered storage (hot/warm/cold data migration)
- Content-addressable storage

**Testing and simulation:**
- Fault injection for testing error handling
- Latency simulation for performance testing
- Quota enforcement for resource testing

### When NOT to Implement

Don't implement a custom backend if:

**Existing backend covers your use case:**
```elixir
# Don't implement HTTP storage if S3 works
# S3 backend supports any S3-compatible service
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "my-bucket",
  endpoint_url: "https://my-minio-server.com"  # Use existing S3 backend
)
```

**Simple wrapper around filesystem:**
```elixir
# Don't create a backend just to customize paths
# Use filesystem backend with path mapping
defmodule MyApp.ArrayStorage do
  def create(name) do
    path = Path.join(["/data", "arrays", Date.utc_today() |> to_string(), name])
    ExZarr.create(
      storage: :filesystem,
      path: path,
      # ... other options
    )
  end
end
```

**Prototyping or experiments:**
```elixir
# Use Memory backend for quick tests
{:ok, array} = ExZarr.create(storage: :memory, shape: {100, 100})

# Or Mock backend for error simulation
{:ok, array} = ExZarr.create(
  storage: :mock,
  simulate_errors: true,
  error_rate: 0.1
)
```

## The Storage Backend Behavior Contract

ExZarr defines the `ExZarr.Storage.Backend` behavior with 10 required callbacks.

### Required Callbacks

**1. `backend_id/0` - Unique identifier**
```elixir
@callback backend_id() :: atom()
```
Returns a unique atom identifying this backend (e.g., `:my_storage`, `:redis`, `:cassandra`).

**2. `init/1` - Initialize storage**
```elixir
@callback init(config :: keyword()) :: {:ok, state :: term()} | {:error, reason :: term()}
```
Called when creating a new array. Initialize connections, create directories/tables, allocate resources.

**3. `open/1` - Open existing storage**
```elixir
@callback open(config :: keyword()) :: {:ok, state :: term()} | {:error, term()}
```
Called when opening an existing array. Verify the location exists and set up connections.

**4. `read_chunk/2` - Read chunk data**
```elixir
@callback read_chunk(state :: term(), chunk_index :: tuple()) ::
  {:ok, binary()} | {:error, :not_found} | {:error, term()}
```
Read compressed chunk bytes by coordinate. Return `{:error, :not_found}` if chunk doesn't exist.

**5. `write_chunk/3` - Write chunk data**
```elixir
@callback write_chunk(state :: term(), chunk_index :: tuple(), data :: binary()) ::
  :ok | {:error, term()}
```
Write compressed chunk bytes to storage. Data is already compressed by ExZarr.

**6. `read_metadata/1` - Read array metadata**
```elixir
@callback read_metadata(state :: term()) ::
  {:ok, map() | binary()} | {:error, :not_found} | {:error, term()}
```
Read array metadata (shape, chunks, dtype, etc.). Can return map or JSON string.

**7. `write_metadata/3` - Write array metadata**
```elixir
@callback write_metadata(state :: term(), metadata :: map() | binary(), version :: 2 | 3) ::
  :ok | {:error, term()}
```
Write array metadata. Version parameter indicates Zarr v2 or v3 format.

**8. `list_chunks/1` - List stored chunks**
```elixir
@callback list_chunks(state :: term()) ::
  {:ok, [tuple()]} | {:error, term()}
```
Return list of all chunk coordinates stored in this array.

**9. `delete_chunk/2` - Delete a chunk**
```elixir
@callback delete_chunk(state :: term(), chunk_index :: tuple()) ::
  :ok | {:error, term()}
```
Remove a chunk from storage. May be no-op for immutable storage.

**10. `exists?/1` - Check if storage exists**
```elixir
@callback exists?(state :: term()) :: {:ok, boolean()} | {:error, term()}
```
Check whether the storage location exists (for opening existing arrays).

### State Management

**State is opaque:**
The `state` term returned by `init/1` or `open/1` is passed to all other callbacks. It can be any Elixir term:
- Map: `%{connection: conn, config: config}`
- Struct: `%MyBackend{client: client, bucket: bucket}`
- PID: `#PID<0.123.0>` (for Agent/GenServer)
- Tuple: `{conn, table_name, options}`

**State should contain:**
- Connection handles (database connections, HTTP clients)
- Configuration (paths, bucket names, credentials)
- Cached data (if safe to cache)

**State lifecycle:**
1. `init/1` or `open/1` creates state
2. State passed to all operations
3. Backend manages state cleanup (if needed)

### Return Value Conventions

**Success patterns:**
- `{:ok, result}` - Operation succeeded with result
- `:ok` - Operation succeeded with no result

**Error patterns:**
- `{:error, :not_found}` - Chunk or metadata doesn't exist (reserved error)
- `{:error, atom}` - Operation failed with error atom (`:permission_denied`, `:timeout`, etc.)
- `{:error, string}` - Operation failed with descriptive message

**Important:**
- Never raise exceptions (ExZarr catches but prefers tuples)
- Always return `{:error, :not_found}` for missing chunks (not `nil` or empty)
- Use descriptive error atoms for debugging

## Example: Minimal In-Memory Backend

A simple backend using `Agent` for storage.

```elixir
defmodule MyApp.SimpleMemory do
  @moduledoc """
  Minimal in-memory storage backend demonstrating the behavior contract.

  Stores chunks and metadata in an Agent. Data is lost when process exits.
  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :simple_memory

  @impl true
  def init(opts) do
    # Get required configuration
    array_id = Keyword.fetch!(opts, :array_id)

    # Start an Agent to hold storage state
    {:ok, agent} = Agent.start_link(fn ->
      %{
        array_id: array_id,
        chunks: %{},      # Map of chunk_index => binary_data
        metadata: nil     # Metadata map or JSON string
      }
    end)

    # Return state containing agent PID
    {:ok, %{agent: agent, array_id: array_id}}
  end

  @impl true
  def open(_opts) do
    # In-memory backend cannot be "opened" (data not persistent)
    {:error, :cannot_open_memory_storage}
  end

  @impl true
  def read_chunk(state, chunk_index) do
    Agent.get(state.agent, fn storage ->
      case Map.fetch(storage.chunks, chunk_index) do
        {:ok, data} -> {:ok, data}
        :error -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def write_chunk(state, chunk_index, data) when is_binary(data) do
    Agent.update(state.agent, fn storage ->
      put_in(storage.chunks[chunk_index], data)
    end)

    :ok
  end

  @impl true
  def read_metadata(state) do
    Agent.get(state.agent, fn storage ->
      case storage.metadata do
        nil -> {:error, :not_found}
        metadata -> {:ok, metadata}
      end
    end)
  end

  @impl true
  def write_metadata(state, metadata, _version) do
    Agent.update(state.agent, fn storage ->
      %{storage | metadata: metadata}
    end)

    :ok
  end

  @impl true
  def list_chunks(state) do
    Agent.get(state.agent, fn storage ->
      {:ok, Map.keys(storage.chunks)}
    end)
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    Agent.update(state.agent, fn storage ->
      {_, updated_chunks} = Map.pop(storage.chunks, chunk_index)
      %{storage | chunks: updated_chunks}
    end)

    :ok
  end

  @impl true
  def exists?(_state) do
    # Memory backend always exists once initialized
    {:ok, true}
  end
end
```

**Key points:**

1. **Agent for state:** Use `Agent.start_link` to create mutable storage accessible across calls
2. **Chunk coordinates as map keys:** Tuples work as map keys (e.g., `{0, 0}`, `{5, 3, 2}`)
3. **Binary data only:** Never decode chunk data in backend (already compressed)
4. **Metadata stored as-is:** ExZarr handles JSON serialization

## Example: HTTP REST API Backend

A realistic backend that stores chunks via HTTP API.

```elixir
defmodule MyApp.HttpStorage do
  @moduledoc """
  Storage backend that persists chunks via HTTP REST API.

  Demonstrates network I/O, authentication, and error handling.
  """

  @behaviour ExZarr.Storage.Backend

  require Logger

  @impl true
  def backend_id, do: :http_storage

  @impl true
  def init(opts) do
    # Required configuration
    base_url = Keyword.fetch!(opts, :base_url)
    array_id = Keyword.fetch!(opts, :array_id)

    # Optional configuration
    api_key = Keyword.get(opts, :api_key)
    timeout = Keyword.get(opts, :timeout, 30_000)

    state = %{
      base_url: String.trim_trailing(base_url, "/"),
      array_id: array_id,
      api_key: api_key,
      timeout: timeout,
      http_client: :httpc  # Use Erlang's built-in HTTP client
    }

    # Verify server is reachable
    case health_check(state) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, {:init_failed, reason}}
    end
  end

  @impl true
  def open(opts) do
    # Same as init for HTTP backend
    init(opts)
  end

  @impl true
  def read_chunk(state, chunk_index) do
    url = build_chunk_url(state, chunk_index)
    headers = build_headers(state)
    opts = [timeout: state.timeout, body_format: :binary]

    case :httpc.request(:get, {url, headers}, opts, []) do
      {:ok, {{_, 200, _}, _resp_headers, body}} ->
        {:ok, body}

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, :not_found}

      {:ok, {{_, status, _}, _, body}} ->
        Logger.error("HTTP GET failed: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) when is_binary(data) do
    url = build_chunk_url(state, chunk_index)
    headers = build_headers(state) ++ [{'content-type', 'application/octet-stream'}]
    opts = [timeout: state.timeout]

    request = {
      to_charlist(url),
      headers,
      'application/octet-stream',
      data
    }

    case :httpc.request(:put, request, opts, []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        Logger.error("HTTP PUT failed: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def read_metadata(state) do
    url = "#{state.base_url}/arrays/#{state.array_id}/metadata"
    headers = build_headers(state)
    opts = [timeout: state.timeout]

    case :httpc.request(:get, {to_charlist(url), headers}, opts, []) do
      {:ok, {{_, 200, _}, _, body}} ->
        # Return raw JSON string (ExZarr will decode)
        {:ok, to_string(body)}

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, :not_found}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def write_metadata(state, metadata, _version) do
    url = "#{state.base_url}/arrays/#{state.array_id}/metadata"
    headers = build_headers(state) ++ [{'content-type', 'application/json'}]
    opts = [timeout: state.timeout]

    # Ensure metadata is JSON string
    json_body = case metadata do
      binary when is_binary(binary) -> binary
      map when is_map(map) -> Jason.encode!(map)
    end

    request = {
      to_charlist(url),
      headers,
      'application/json',
      json_body
    }

    case :httpc.request(:put, request, opts, []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def list_chunks(state) do
    url = "#{state.base_url}/arrays/#{state.array_id}/chunks"
    headers = build_headers(state)
    opts = [timeout: state.timeout]

    case :httpc.request(:get, {to_charlist(url), headers}, opts, []) do
      {:ok, {{_, 200, _}, _, body}} ->
        # Expect JSON array of chunk indices
        # Format: [[0, 0], [0, 1], [1, 0], ...]
        indices = Jason.decode!(to_string(body))
        tuples = Enum.map(indices, &List.to_tuple/1)
        {:ok, tuples}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    url = build_chunk_url(state, chunk_index)
    headers = build_headers(state)
    opts = [timeout: state.timeout]

    case :httpc.request(:delete, {to_charlist(url), headers}, opts, []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 or code == 404 ->
        # 404 is okay (already deleted)
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def exists?(state) do
    case health_check(state) do
      :ok -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  # Private helpers

  defp build_chunk_url(state, chunk_index) do
    coords_str = chunk_index |> Tuple.to_list() |> Enum.join(",")
    "#{state.base_url}/arrays/#{state.array_id}/chunks/#{coords_str}"
  end

  defp build_headers(state) do
    case state.api_key do
      nil -> []
      key -> [{'authorization', to_charlist("Bearer #{key}")}]
    end
  end

  defp health_check(state) do
    url = "#{state.base_url}/health"
    opts = [timeout: 5_000]

    case :httpc.request(:get, {to_charlist(url), []}, opts, []) do
      {:ok, {{_, 200, _}, _, _}} -> :ok
      {:ok, {{_, status, _}, _, _}} -> {:error, {:unhealthy, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Key points:**

1. **Error handling:** Distinguish HTTP errors (404, 500) from network errors (timeout, connection refused)
2. **Authentication:** Support API key via `Authorization` header
3. **Timeouts:** Configurable timeout to prevent hanging
4. **URL construction:** Build RESTful URLs from chunk coordinates
5. **Logging:** Log errors for debugging
6. **Health check:** Verify server is reachable during init

## Backend Registration and Usage

### Register at Application Startup

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # Register custom backends before use
    :ok = ExZarr.Storage.Registry.register(MyApp.SimpleMemory)
    :ok = ExZarr.Storage.Registry.register(MyApp.HttpStorage)

    children = [
      # ... your application supervision tree
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

### Use Registered Backend

```elixir
# Use simple memory backend
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :simple_memory,  # Use backend_id
  array_id: "test_array_001"
)

# Write data
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {100, 100}
)

# Read data
{:ok, result} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)
```

```elixir
# Use HTTP storage backend
{:ok, array} = ExZarr.create(
  shape: {5000, 5000},
  chunks: {500, 500},
  dtype: :float64,
  compressor: :zstd,
  storage: :http_storage,
  base_url: "https://api.example.com",
  array_id: "experiment_#{System.system_time()}",
  api_key: System.get_env("API_KEY"),
  timeout: 60_000
)
```

### Query Registered Backends

```elixir
# List all registered backends
ExZarr.Storage.Registry.list_backends()
# => [:memory, :filesystem, :ets, :s3, :simple_memory, :http_storage]

# Get backend module for an ID
{:ok, module} = ExZarr.Storage.Registry.get(:simple_memory)
# => {:ok, MyApp.SimpleMemory}

# Check if backend is registered
ExZarr.Storage.Registry.registered?(:http_storage)
# => true
```

## Error Handling and Retries

### Backend Responsibilities

Backends should return errors, not raise exceptions:

```elixir
# Good: return error tuple
def read_chunk(state, chunk_index) do
  case fetch_from_storage(state, chunk_index) do
    {:ok, data} -> {:ok, data}
    {:error, reason} -> {:error, reason}
  end
end

# Bad: raise exception
def read_chunk(state, chunk_index) do
  fetch_from_storage!(state, chunk_index)  # Raises on error
end
```

**Error atom guidelines:**
- `:not_found` - Chunk or metadata doesn't exist (reserved)
- `:timeout` - Operation timed out
- `:permission_denied` - Access forbidden
- `:network_error` - Network issue (connection refused, DNS failure)
- `:storage_full` - Out of space
- Custom atoms for backend-specific errors

### Application-Level Retry Logic

Implement retries in your application, not in the backend:

```elixir
defmodule MyApp.RetryHelper do
  @doc """
  Retry a function up to max_attempts times with exponential backoff.
  """
  def with_retry(fun, max_attempts \\ 3, base_delay \\ 100) do
    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      case fun.() do
        {:ok, result} ->
          {:halt, {:ok, result}}

        {:error, reason} when attempt < max_attempts ->
          # Only retry on transient errors
          if retriable?(reason) do
            delay = base_delay * :math.pow(2, attempt - 1) |> round()
            Process.sleep(delay)
            {:cont, nil}
          else
            {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Determine if error is transient (retriable)
  defp retriable?(:timeout), do: true
  defp retriable?({:network_error, _}), do: true
  defp retriable?({:http_error, status}) when status >= 500, do: true
  defp retriable?(_), do: false  # Permanent errors
end
```

**Usage:**
```elixir
# Retry chunk read up to 3 times
result = MyApp.RetryHelper.with_retry(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)

case result do
  {:ok, data} -> process_data(data)
  {:error, reason} -> Logger.error("Failed after retries: #{inspect(reason)}")
end
```

### Circuit Breaker Pattern

For backends with frequent failures, implement a circuit breaker:

```elixir
defmodule MyApp.CircuitBreaker do
  use GenServer

  # State: :closed (normal), :open (failing), :half_open (testing recovery)
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def call(fun) do
    GenServer.call(__MODULE__, {:execute, fun})
  end

  def init(_opts) do
    state = %{
      status: :closed,
      failure_count: 0,
      failure_threshold: 5,
      recovery_timeout: 60_000,
      last_failure_time: nil
    }
    {:ok, state}
  end

  def handle_call({:execute, fun}, _from, %{status: :open} = state) do
    # Circuit is open, reject immediately
    {:reply, {:error, :circuit_open}, state}
  end

  def handle_call({:execute, fun}, _from, state) do
    case fun.() do
      {:ok, result} ->
        # Success, reset failure count
        {:reply, {:ok, result}, %{state | failure_count: 0}}

      {:error, reason} ->
        # Failure, increment count
        new_count = state.failure_count + 1

        new_state = if new_count >= state.failure_threshold do
          # Open circuit
          %{state | status: :open, failure_count: new_count, last_failure_time: System.monotonic_time(:millisecond)}
        else
          %{state | failure_count: new_count}
        end

        {:reply, {:error, reason}, new_state}
    end
  end
end
```

## Testing for Compliance

### Comprehensive Backend Tests

Test all behavior callbacks:

```elixir
defmodule MyApp.SimpleMemoryTest do
  use ExUnit.Case, async: true

  alias MyApp.SimpleMemory

  setup do
    {:ok, state} = SimpleMemory.init(array_id: "test_#{:rand.uniform(10000)}")
    %{state: state}
  end

  describe "chunk operations" do
    test "write and read chunk", %{state: state} do
      chunk_index = {0, 0}
      data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      assert :ok = SimpleMemory.write_chunk(state, chunk_index, data)
      assert {:ok, ^data} = SimpleMemory.read_chunk(state, chunk_index)
    end

    test "read non-existent chunk returns not_found", %{state: state} do
      assert {:error, :not_found} = SimpleMemory.read_chunk(state, {99, 99})
    end

    test "overwrite existing chunk", %{state: state} do
      chunk_index = {0, 0}
      data1 = <<1, 2, 3, 4>>
      data2 = <<5, 6, 7, 8>>

      :ok = SimpleMemory.write_chunk(state, chunk_index, data1)
      :ok = SimpleMemory.write_chunk(state, chunk_index, data2)

      assert {:ok, ^data2} = SimpleMemory.read_chunk(state, chunk_index)
    end

    test "write and read multi-dimensional chunk indices", %{state: state} do
      # 3D array chunk
      chunk_index = {2, 5, 3}
      data = :crypto.strong_rand_bytes(1000)

      :ok = SimpleMemory.write_chunk(state, chunk_index, data)
      assert {:ok, ^data} = SimpleMemory.read_chunk(state, chunk_index)
    end
  end

  describe "list_chunks/1" do
    test "returns empty list when no chunks written", %{state: state} do
      assert {:ok, []} = SimpleMemory.list_chunks(state)
    end

    test "returns all written chunk indices", %{state: state} do
      chunks = [{0, 0}, {0, 1}, {1, 0}, {2, 3}]

      Enum.each(chunks, fn idx ->
        :ok = SimpleMemory.write_chunk(state, idx, <<1, 2, 3>>)
      end)

      {:ok, listed} = SimpleMemory.list_chunks(state)

      assert length(listed) == length(chunks)
      assert Enum.all?(chunks, fn chunk -> chunk in listed end)
    end
  end

  describe "delete_chunk/2" do
    test "deletes existing chunk", %{state: state} do
      chunk_index = {0, 0}
      data = <<1, 2, 3, 4>>

      :ok = SimpleMemory.write_chunk(state, chunk_index, data)
      assert {:ok, ^data} = SimpleMemory.read_chunk(state, chunk_index)

      :ok = SimpleMemory.delete_chunk(state, chunk_index)
      assert {:error, :not_found} = SimpleMemory.read_chunk(state, chunk_index)
    end

    test "delete non-existent chunk is idempotent", %{state: state} do
      assert :ok = SimpleMemory.delete_chunk(state, {99, 99})
    end
  end

  describe "metadata operations" do
    test "write and read metadata", %{state: state} do
      metadata = %{
        "shape" => [1000, 1000],
        "chunks" => [100, 100],
        "dtype" => "float64",
        "compressor" => "zstd"
      }

      assert :ok = SimpleMemory.write_metadata(state, metadata, 2)
      assert {:ok, ^metadata} = SimpleMemory.read_metadata(state)
    end

    test "read metadata before write returns not_found", %{state: state} do
      assert {:error, :not_found} = SimpleMemory.read_metadata(state)
    end

    test "overwrite metadata", %{state: state} do
      metadata1 = %{"version" => 1}
      metadata2 = %{"version" => 2}

      :ok = SimpleMemory.write_metadata(state, metadata1, 2)
      :ok = SimpleMemory.write_metadata(state, metadata2, 2)

      assert {:ok, ^metadata2} = SimpleMemory.read_metadata(state)
    end
  end

  describe "exists?/1" do
    test "returns true after initialization", %{state: state} do
      assert {:ok, true} = SimpleMemory.exists?(state)
    end
  end
end
```

### Property-Based Testing

Use StreamData for fuzz testing:

```elixir
defmodule MyApp.SimpleMemoryPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias MyApp.SimpleMemory

  property "chunks can be written and read back unchanged" do
    check all(
      chunk_indices <- list_of(tuple({integer(0..10), integer(0..10)}), min_length: 1, max_length: 20),
      chunk_data <- list_of(binary(min_length: 1, max_length: 1000))
    ) do
      {:ok, state} = SimpleMemory.init(array_id: "prop_test")

      # Write chunks
      Enum.zip(chunk_indices, chunk_data)
      |> Enum.each(fn {idx, data} ->
        assert :ok = SimpleMemory.write_chunk(state, idx, data)
      end)

      # Read back and verify
      Enum.zip(chunk_indices, chunk_data)
      |> Enum.each(fn {idx, expected_data} ->
        assert {:ok, ^expected_data} = SimpleMemory.read_chunk(state, idx)
      end)
    end
  end
end
```

## Performance Considerations

### Minimize Overhead

Backends are called frequently (once per chunk operation). Optimize hot paths:

```elixir
# Slow: Create new HTTP client for every request
def read_chunk(state, chunk_index) do
  {:ok, client} = HTTPClient.new()  # Expensive!
  HTTPClient.get(client, build_url(chunk_index))
end

# Fast: Reuse HTTP client from state
def read_chunk(state, chunk_index) do
  HTTPClient.get(state.http_client, build_url(chunk_index))
end
```

### Connection Pooling

For network backends, use connection pools:

```elixir
defmodule MyApp.PooledHttpBackend do
  @impl true
  def init(opts) do
    # Start connection pool
    pool_opts = [
      name: {:local, :http_pool},
      worker_module: :gun,
      size: 10,
      max_overflow: 5
    ]

    {:ok, _pid} = :poolboy.start_link(pool_opts)

    {:ok, %{base_url: opts[:base_url], pool: :http_pool}}
  end

  @impl true
  def read_chunk(state, chunk_index) do
    # Check out connection from pool
    :poolboy.transaction(state.pool, fn conn ->
      # Use pooled connection
      perform_get(conn, chunk_index)
    end)
  end
end
```

### Async I/O

Use async operations where possible:

```elixir
# Sync: blocks until complete
def write_chunks(state, chunks) do
  Enum.each(chunks, fn {idx, data} ->
    write_chunk(state, idx, data)
  end)
end

# Async: fire-and-forget (if safe)
def write_chunks_async(state, chunks) do
  chunks
  |> Task.async_stream(fn {idx, data} ->
    write_chunk(state, idx, data)
  end, max_concurrency: 10)
  |> Enum.to_list()
end
```

### Caching Metadata

Metadata reads are rare but may happen multiple times. Cache safely:

```elixir
defmodule MyApp.CachedBackend do
  @impl true
  def init(opts) do
    {:ok, base_state} = MyBackend.init(opts)

    # Add cache to state
    {:ok, cache} = Agent.start_link(fn -> %{metadata: nil} end)

    {:ok, Map.put(base_state, :cache, cache)}
  end

  @impl true
  def read_metadata(state) do
    # Check cache first
    cached = Agent.get(state.cache, fn c -> c.metadata end)

    case cached do
      nil ->
        # Cache miss, read from backend
        case MyBackend.read_metadata(state) do
          {:ok, metadata} ->
            Agent.update(state.cache, fn c -> %{c | metadata: metadata} end)
            {:ok, metadata}
          error -> error
        end

      metadata ->
        # Cache hit
        {:ok, metadata}
    end
  end

  @impl true
  def write_metadata(state, metadata, version) do
    # Write to backend
    case MyBackend.write_metadata(state, metadata, version) do
      :ok ->
        # Update cache
        Agent.update(state.cache, fn c -> %{c | metadata: metadata} end)
        :ok
      error -> error
    end
  end
end
```

**Warning:** Only cache if safe (immutable data, single writer).

### Don't Re-Compress

Chunk data is already compressed by ExZarr. Don't compress again:

```elixir
# Wrong: double compression
def write_chunk(state, chunk_index, data) do
  compressed = :zlib.compress(data)  # Already compressed!
  store(state, chunk_index, compressed)
end

# Right: store as-is
def write_chunk(state, chunk_index, data) do
  store(state, chunk_index, data)  # Already compressed by ExZarr
end
```

### Benchmark Before Optimizing

Profile with realistic workloads:

```elixir
# Benchmark backend performance
defmodule MyApp.BackendBenchmark do
  def run do
    {:ok, state} = MyApp.HttpStorage.init(
      base_url: "http://localhost:8080",
      array_id: "benchmark"
    )

    data = :crypto.strong_rand_bytes(80_000)  # 80 KB chunk

    # Benchmark writes
    write_time = :timer.tc(fn ->
      Enum.each(0..99, fn i ->
        MyApp.HttpStorage.write_chunk(state, {i, 0}, data)
      end)
    end) |> elem(0)

    # Benchmark reads
    read_time = :timer.tc(fn ->
      Enum.each(0..99, fn i ->
        MyApp.HttpStorage.read_chunk(state, {i, 0})
      end)
    end) |> elem(0)

    IO.puts("Write 100 chunks: #{div(write_time, 1000)}ms")
    IO.puts("Read 100 chunks: #{div(read_time, 1000)}ms")
  end
end
```

## Summary

This guide covered implementing custom storage backends:

- **When to implement:** Internal storage, specialized databases, testing/simulation
- **When NOT to:** Existing backend covers use case, simple wrapper, prototyping
- **Behavior contract:** 10 required callbacks (backend_id, init, open, read/write chunk/metadata, list, delete, exists)
- **Examples:** Minimal in-memory backend (Agent), HTTP REST API backend (network I/O)
- **Registration:** Register at app startup, use with `storage: :backend_id`
- **Error handling:** Return tuples, not exceptions; implement retries at application level
- **Testing:** Comprehensive ExUnit tests, property-based testing with StreamData
- **Performance:** Connection pooling, async I/O, metadata caching, avoid re-compression

**Key takeaways:**
- State is opaque (any term)
- Chunk data is binary (already compressed)
- Return `{:error, :not_found}` for missing chunks
- Test all callbacks thoroughly
- Profile before optimizing

## Next Steps

Now that you can implement custom backends:

1. **Learn Compression:** Optimize codec selection in [Compression and Codecs Guide](compression_codecs.md)
2. **Python Interop:** Ensure compatibility in [Python Interoperability Guide](python_interop.md)
3. **Performance Tuning:** Benchmark your backend in [Performance Guide](performance.md)
4. **Example Applications:** See real-world patterns in [Advanced Usage Guide](advanced_usage.md)
