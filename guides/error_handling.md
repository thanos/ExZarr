# Error Handling Guide

Comprehensive guide to error handling in ExZarr for building robust applications.

## Table of Contents

- [Error Conventions](#error-conventions)
- [Error Types](#error-types)
- [Error Recovery Strategies](#error-recovery-strategies)
- [Error Handling Patterns](#error-handling-patterns)
- [Common Errors](#common-errors)
- [Debugging](#debugging)
- [Best Practices](#best-practices)

## Error Conventions

ExZarr follows Elixir conventions for error handling:

### Return Values

All public functions return tuples:

```elixir
{:ok, result}     # Success
{:error, reason}  # Failure
```

### Error Reasons

Error reasons follow a consistent pattern:

```elixir
{:error, :atom}                    # Simple error
{:error, {:atom, details}}         # Error with context
{:error, {:atom, message, meta}}   # Error with message and metadata
```

### Examples

```elixir
# Success
{:ok, array} = ExZarr.create(shape: {100, 100})

# Simple error
{:error, :invalid_shape} = ExZarr.create(shape: {-1, 100})

# Error with details
{:error, {:invalid_dtype, :unknown_type}} = ExZarr.create(dtype: :invalid)

# Error with message
{:error, {:storage_error, "Permission denied", %{path: "/tmp/array"}}}
```

## Error Types

### Configuration Errors

Errors during array creation or configuration:

#### `:invalid_shape`
```elixir
{:error, :invalid_shape}
```
**Cause**: Shape dimensions must be positive integers

**Fix**:
```elixir
# Bad
{:error, :invalid_shape} = ExZarr.create(shape: {-1, 100})

# Good
{:ok, array} = ExZarr.create(shape: {100, 100})
```

#### `:invalid_chunks`
```elixir
{:error, :invalid_chunks}
```
**Cause**: Chunk dimensions must divide evenly into shape or be valid irregular chunks

**Fix**:
```elixir
# Bad
{:error, :invalid_chunks} = ExZarr.create(
  shape: {100, 100},
  chunks: {0, 0}  # Zero not allowed
)

# Good
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10}
)
```

#### `:invalid_dtype`
```elixir
{:error, {:invalid_dtype, dtype}}
```
**Cause**: Unsupported data type

**Supported types**: `:int8`, `:int16`, `:int32`, `:int64`, `:uint8`, `:uint16`, `:uint32`, `:uint64`, `:float32`, `:float64`

**Fix**:
```elixir
# Bad
{:error, {:invalid_dtype, :complex128}} = ExZarr.create(dtype: :complex128)

# Good
{:ok, array} = ExZarr.create(dtype: :float64)
```

#### `:unsupported_codec`
```elixir
{:error, {:unsupported_codec, codec}}
```
**Cause**: Compression codec not available

**Fix**:
```elixir
# Check availability first
if ExZarr.Codecs.codec_available?(:blosc) do
  ExZarr.create(compressor: :blosc)
else
  ExZarr.create(compressor: :zlib)  # Fallback
end
```

### Storage Errors

Errors related to storage backends:

#### `:storage_not_found`
```elixir
{:error, :storage_not_found}
```
**Cause**: Cannot find array at specified path

**Fix**:
```elixir
# Check if array exists first
case ExZarr.open(path: "/path/to/array") do
  {:ok, array} -> use_array(array)
  {:error, :storage_not_found} ->
    {:ok, array} = ExZarr.create(path: "/path/to/array", shape: {100, 100})
    use_array(array)
end
```

#### `:permission_denied`
```elixir
{:error, {:permission_denied, path}}
```
**Cause**: Insufficient permissions to read/write

**Fix**:
```elixir
# Ensure proper permissions
File.chmod!("/path/to/array", 0o755)

# Or use a writable location
{:ok, array} = ExZarr.create(
  path: System.tmp_dir!() <> "/my_array",
  shape: {100, 100}
)
```

#### `:storage_backend_unavailable`
```elixir
{:error, {:storage_backend_unavailable, backend}}
```
**Cause**: Required storage backend dependencies not available

**Fix**:
```elixir
# For S3, add dependencies to mix.exs:
# {:ex_aws, "~> 2.5"},
# {:ex_aws_s3, "~> 2.5"},
# {:hackney, "~> 1.18"}

# Check backend availability
case ExZarr.Storage.Backend.available?(:s3) do
  true -> use_s3_storage()
  false -> use_filesystem_storage()  # Fallback
end
```

### I/O Errors

Errors during read/write operations:

#### `:out_of_bounds`
```elixir
{:error, {:out_of_bounds, details}}
```
**Cause**: Slice indices exceed array bounds

**Fix**:
```elixir
{:ok, array} = ExZarr.create(shape: {100, 100})

# Bad - exceeds bounds
{:error, {:out_of_bounds, _}} =
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {200, 200})

# Good - within bounds
{:ok, data} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})

# Safe - validate first
defmodule SafeRead do
  def read_slice(array, start, stop) do
    if valid_indices?(array, start, stop) do
      ExZarr.Array.get_slice(array, start: start, stop: stop)
    else
      {:error, :indices_out_of_bounds}
    end
  end

  defp valid_indices?(array, start, stop) do
    Tuple.to_list(start)
    |> Enum.zip(Tuple.to_list(stop))
    |> Enum.zip(Tuple.to_list(array.shape))
    |> Enum.all?(fn {{start_i, stop_i}, dim} ->
      start_i >= 0 and stop_i <= dim and start_i < stop_i
    end)
  end
end
```

#### `:read_failed`
```elixir
{:error, :read_failed}
```
**Cause**: Failed to read chunk data from storage

**Fix**:
```elixir
# Implement retry logic
defmodule RetryableRead do
  def read_with_retry(array, start, stop, max_attempts \\ 3) do
    read_with_retry_impl(array, start, stop, max_attempts, 0)
  end

  defp read_with_retry_impl(array, start, stop, max_attempts, attempt) do
    case ExZarr.Array.get_slice(array, start: start, stop: stop) do
      {:ok, data} ->
        {:ok, data}

      {:error, :read_failed} when attempt < max_attempts ->
        # Exponential backoff
        :timer.sleep(100 * :math.pow(2, attempt))
        read_with_retry_impl(array, start, stop, max_attempts, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

#### `:write_failed`
```elixir
{:error, :write_failed}
```
**Cause**: Failed to write chunk data to storage

**Fix**:
```elixir
# Check disk space
case File.stat(array.path) do
  {:ok, %{type: :directory}} ->
    # Directory exists, check space
    case :os.cmd('df -k #{array.path}') do
      low_space -> Logger.warn("Low disk space")
      _ -> :ok
    end
  {:error, _} ->
    # Create directory
    File.mkdir_p!(Path.dirname(array.path))
end

# Implement retry with error handling
case write_with_retry(array, data, start, stop) do
  {:ok, _} -> :ok
  {:error, :write_failed} -> handle_write_failure()
end
```

### Data Errors

Errors related to data validation:

#### `:data_size_mismatch`
```elixir
{:error, {:data_size_mismatch, expected, actual}}
```
**Cause**: Provided data size doesn't match expected size for slice

**Fix**:
```elixir
{:ok, array} = ExZarr.create(shape: {100, 100}, dtype: :float64)

# Bad - data size mismatch
small_data = <<1.0::float-64-native>>  # Only 1 element
{:error, {:data_size_mismatch, 10000, 1}} =
  ExZarr.Array.set_slice(array, small_data, start: {0, 0}, stop: {100, 100})

# Good - correct size
element_size = 8  # float64
elements = 100 * 100
data = for _ <- 1..elements, into: <<>>, do: <<1.0::float-64-native>>
{:ok, _} = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

# Helper - calculate required size
defmodule DataHelper do
  def required_size(dtype, start, stop) do
    element_size = ExZarr.DataType.size(dtype)
    element_count =
      Tuple.to_list(start)
      |> Enum.zip(Tuple.to_list(stop))
      |> Enum.map(fn {s, e} -> e - s end)
      |> Enum.reduce(1, &*/2)

    element_count * element_size
  end
end
```

#### `:invalid_data_type`
```elixir
{:error, {:invalid_data_type, expected, actual}}
```
**Cause**: Data doesn't match array's dtype

**Fix**:
```elixir
# Ensure data matches dtype
defmodule DataTypeHelper do
  def encode_data(values, :float64) do
    for value <- values, into: <<>>, do: <<value::float-64-native>>
  end

  def encode_data(values, :int32) do
    for value <- values, into: <<>>, do: <<value::signed-32-native>>
  end

  # Add more types as needed...
end
```

### Compression Errors

Errors during compression/decompression:

#### `:compression_failed`
```elixir
{:error, {:compression_failed, reason}}
```
**Cause**: Compression operation failed

**Fix**:
```elixir
# Fallback to no compression
defmodule CompressionFallback do
  def create_with_fallback(opts) do
    case ExZarr.create(opts) do
      {:ok, array} ->
        {:ok, array}

      {:error, {:compression_failed, _}} ->
        # Retry without compression
        opts_no_compression = Keyword.put(opts, :compressor, nil)
        ExZarr.create(opts_no_compression)

      error ->
        error
    end
  end
end
```

#### `:decompression_failed`
```elixir
{:error, {:decompression_failed, reason}}
```
**Cause**: Corrupted or invalid compressed data

**Fix**:
```elixir
# Data corruption - may need to restore from backup
defmodule CorruptionHandler do
  def read_with_corruption_handling(array, start, stop) do
    case ExZarr.Array.get_slice(array, start: start, stop: stop) do
      {:ok, data} ->
        {:ok, data}

      {:error, {:decompression_failed, _}} ->
        Logger.error("Corrupted chunk detected, attempting recovery")
        # Try alternative recovery strategies:
        # 1. Read fill values
        # 2. Restore from backup
        # 3. Mark as corrupted and skip
        {:error, :corrupted_data}
    end
  end
end
```

## Error Recovery Strategies

### 1. Retry with Backoff

For transient errors (network, temporary unavailability):

```elixir
defmodule RetryStrategy do
  def with_exponential_backoff(func, max_attempts \\ 3) do
    with_exponential_backoff_impl(func, max_attempts, 0, nil)
  end

  defp with_exponential_backoff_impl(func, max_attempts, attempt, _last_error)
       when attempt >= max_attempts do
    {:error, :max_retries_exceeded}
  end

  defp with_exponential_backoff_impl(func, max_attempts, attempt, _last_error) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} = error when reason in [:read_failed, :write_failed, :network_error] ->
        backoff_ms = trunc(100 * :math.pow(2, attempt))
        Logger.warn("Attempt #{attempt + 1} failed, retrying in #{backoff_ms}ms")
        :timer.sleep(backoff_ms)
        with_exponential_backoff_impl(func, max_attempts, attempt + 1, error)

      {:error, _reason} = error ->
        # Non-retryable error
        error
    end
  end
end

# Usage
RetryStrategy.with_exponential_backoff(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)
```

### 2. Graceful Degradation

Fallback to alternative approaches:

```elixir
defmodule GracefulDegradation do
  def read_with_fallback(array, start, stop) do
    # Try cached read first
    case read_cached(array, start, stop) do
      {:ok, data} -> {:ok, data}
      {:error, _} ->
        # Fallback to direct read
        case read_direct(array, start, stop) do
          {:ok, data} -> {:ok, data}
          {:error, _} ->
            # Fallback to fill values
            create_fill_data(array, start, stop)
        end
    end
  end

  defp read_cached(array, start, stop) do
    if array.cache_enabled do
      ExZarr.Array.get_slice(array, start: start, stop: stop)
    else
      {:error, :cache_disabled}
    end
  end

  defp read_direct(array, start, stop) do
    # Disable cache for this read
    %{array | cache_enabled: false}
    |> ExZarr.Array.get_slice(start: start, stop: stop)
  end

  defp create_fill_data(array, start, stop) do
    # Return fill values as last resort
    Logger.warn("Using fill values due to read failures")
    size = calculate_slice_size(array, start, stop)
    {:ok, create_fill_binary(array.dtype, size)}
  end
end
```

### 3. Circuit Breaker

Prevent cascading failures:

```elixir
defmodule CircuitBreaker do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :closed, name: __MODULE__)
  end

  def call(func) do
    case GenServer.call(__MODULE__, :check_state) do
      :closed ->
        case func.() do
          {:ok, result} ->
            GenServer.cast(__MODULE__, :success)
            {:ok, result}

          {:error, reason} = error ->
            GenServer.cast(__MODULE__, :failure)
            error
        end

      :open ->
        {:error, :circuit_breaker_open}
    end
  end

  def init(state) do
    {:ok, %{state: state, failures: 0, threshold: 5}}
  end

  def handle_call(:check_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_cast(:success, state) do
    {:noreply, %{state | state: :closed, failures: 0}}
  end

  def handle_cast(:failure, state) do
    new_failures = state.failures + 1

    new_state =
      if new_failures >= state.threshold do
        Logger.error("Circuit breaker opened after #{new_failures} failures")
        schedule_half_open()
        %{state | state: :open, failures: new_failures}
      else
        %{state | failures: new_failures}
      end

    {:noreply, new_state}
  end

  defp schedule_half_open do
    Process.send_after(self(), :try_half_open, 30_000)  # 30 seconds
  end

  def handle_info(:try_half_open, state) do
    Logger.info("Circuit breaker entering half-open state")
    {:noreply, %{state | state: :closed, failures: 0}}
  end
end
```

### 4. Validation and Sanitization

Prevent errors through input validation:

```elixir
defmodule SafeZarr do
  def safe_create(opts) do
    with :ok <- validate_shape(opts[:shape]),
         :ok <- validate_chunks(opts[:shape], opts[:chunks]),
         :ok <- validate_dtype(opts[:dtype]),
         :ok <- validate_path(opts[:path]) do
      ExZarr.create(opts)
    end
  end

  defp validate_shape(shape) when is_tuple(shape) do
    if Enum.all?(Tuple.to_list(shape), &(&1 > 0)) do
      :ok
    else
      {:error, {:validation_failed, :invalid_shape, "All dimensions must be positive"}}
    end
  end

  defp validate_shape(_), do: {:error, {:validation_failed, :invalid_shape, "Shape must be a tuple"}}

  defp validate_chunks(shape, chunks) when is_tuple(chunks) do
    if tuple_size(shape) == tuple_size(chunks) do
      :ok
    else
      {:error, {:validation_failed, :invalid_chunks, "Chunks must match shape dimensions"}}
    end
  end

  defp validate_chunks(_, _), do: {:error, {:validation_failed, :invalid_chunks, "Chunks must be a tuple"}}

  defp validate_dtype(dtype) when dtype in [:int8, :int16, :int32, :int64,
                                              :uint8, :uint16, :uint32, :uint64,
                                              :float32, :float64] do
    :ok
  end

  defp validate_dtype(dtype), do: {:error, {:validation_failed, :invalid_dtype, "Unsupported dtype: #{dtype}"}}

  defp validate_path(nil), do: :ok  # Memory storage
  defp validate_path(path) when is_binary(path) do
    # Check for path traversal
    if String.contains?(path, "..") do
      {:error, {:validation_failed, :invalid_path, "Path traversal not allowed"}}
    else
      :ok
    end
  end

  defp validate_path(_), do: {:error, {:validation_failed, :invalid_path, "Path must be a string"}}
end
```

## Error Handling Patterns

### Pattern 1: With Clause

```elixir
with {:ok, array} <- ExZarr.create(shape: {100, 100}),
     {:ok, _} <- ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100}),
     {:ok, saved} <- ExZarr.save(array, path: "/tmp/array") do
  {:ok, saved}
else
  {:error, :invalid_shape} ->
    {:error, "Invalid array dimensions"}

  {:error, {:data_size_mismatch, expected, actual}} ->
    {:error, "Data size mismatch: expected #{expected}, got #{actual}"}

  {:error, reason} ->
    {:error, "Operation failed: #{inspect(reason)}"}
end
```

### Pattern 2: Case Matching

```elixir
case ExZarr.create(shape: {100, 100}) do
  {:ok, array} ->
    handle_success(array)

  {:error, :invalid_shape} ->
    Logger.error("Invalid shape provided")
    use_default_array()

  {:error, {:unsupported_codec, codec}} ->
    Logger.warn("Codec #{codec} not available, using zlib")
    ExZarr.create(shape: {100, 100}, compressor: :zlib)

  {:error, reason} ->
    Logger.error("Array creation failed: #{inspect(reason)}")
    {:error, reason}
end
```

### Pattern 3: Bang Functions (Use with Caution)

For internal code where errors are unexpected:

```elixir
# Only use when error is truly exceptional
defmodule InternalOps do
  def create_temp_array! do
    ExZarr.create!(
      shape: {100, 100},
      storage: :memory,
      dtype: :float64
    )
  end
end

# Never use in library code or APIs!
```

### Pattern 4: Result Monad

For chaining operations:

```elixir
defmodule Result do
  def ok(value), do: {:ok, value}
  def error(reason), do: {:error, reason}

  def and_then({:ok, value}, func), do: func.(value)
  def and_then({:error, _} = error, _func), do: error

  def map({:ok, value}, func), do: {:ok, func.(value)}
  def map({:error, _} = error, _func), do: error
end

# Usage
Result.ok({100, 100})
|> Result.and_then(&ExZarr.create(shape: &1))
|> Result.and_then(&populate_array/1)
|> Result.map(&ExZarr.save(&1, path: "/tmp/array"))
```

## Common Errors

### 1. Shape/Chunk Mismatch

```elixir
# Problem
{:error, :invalid_chunks} = ExZarr.create(
  shape: {100, 100},
  chunks: {30, 30}  # Doesn't divide evenly
)

# Solution
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10}  # Divides evenly
)
```

### 2. Path Issues

```elixir
# Problem - relative path ambiguity
{:error, _} = ExZarr.create(
  shape: {100, 100},
  path: "../data/array"  # Dangerous!
)

# Solution - use absolute paths
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  path: Path.expand("./data/array")
)
```

### 3. Missing Dependencies

```elixir
# Problem
{:error, {:storage_backend_unavailable, :s3}} = ExZarr.create(
  shape: {100, 100},
  storage: :s3
)

# Solution - check availability
def create_with_s3_fallback(opts) do
  if s3_available?() do
    ExZarr.create(Keyword.put(opts, :storage, :s3))
  else
    ExZarr.create(Keyword.put(opts, :storage, :filesystem))
  end
end

defp s3_available? do
  Code.ensure_loaded?(ExAws.S3)
end
```

### 4. Data Type Confusion

```elixir
# Problem - mixing types
data = [1, 2, 3, 4, 5]  # List, not binary
{:error, _} = ExZarr.Array.set_slice(array, data, start: {0}, stop: {5})

# Solution - encode properly
data = for i <- [1, 2, 3, 4, 5], into: <<>>, do: <<i::signed-32-native>>
{:ok, _} = ExZarr.Array.set_slice(array, data, start: {0}, stop: {5})
```

## Debugging

### Enable Logging

```elixir
# In config/config.exs
config :logger, level: :debug

# Or at runtime
Logger.configure(level: :debug)
```

### Inspect Errors

```elixir
case ExZarr.create(shape: {100, 100}) do
  {:ok, array} -> array
  {:error, reason} ->
    IO.inspect(reason, label: "Error")
    IO.inspect(__STACKTRACE__, label: "Stacktrace")
    raise "Creation failed"
end
```

### Use IEx for Interactive Debugging

```elixir
# Start IEx session
iex -S mix

# Try operations interactively
iex> {:ok, array} = ExZarr.create(shape: {10, 10})
iex> ExZarr.Array.get_slice(array, start: {0, 0}, stop: {5, 5})
```

## Best Practices

1. **Always Handle Errors** - Never ignore error tuples
   ```elixir
   # Bad
   {_, array} = ExZarr.create(shape: {100, 100})

   # Good
   case ExZarr.create(shape: {100, 100}) do
     {:ok, array} -> use_array(array)
     {:error, reason} -> handle_error(reason)
   end
   ```

2. **Provide Context** - Add meaningful error messages
   ```elixir
   case ExZarr.create(opts) do
     {:ok, array} -> {:ok, array}
     {:error, reason} ->
       {:error, "Failed to create array with shape #{inspect(opts[:shape])}: #{inspect(reason)}"}
   end
   ```

3. **Validate Early** - Check inputs before operations
   ```elixir
   def safe_slice(array, start, stop) do
     with :ok <- validate_bounds(array, start, stop),
          {:ok, data} <- ExZarr.Array.get_slice(array, start: start, stop: stop) do
       {:ok, data}
     end
   end
   ```

4. **Log Appropriately** - Use appropriate log levels
   ```elixir
   case dangerous_operation() do
     {:ok, result} ->
       Logger.debug("Operation succeeded")
       {:ok, result}

     {:error, :transient} ->
       Logger.warn("Transient error, will retry")
       retry()

     {:error, reason} ->
       Logger.error("Operation failed: #{inspect(reason)}")
       {:error, reason}
   end
   ```

5. **Document Error Cases** - Document what errors functions can return
   ```elixir
   @doc """
   Creates a new Zarr array.

   ## Returns
   - `{:ok, array}` on success
   - `{:error, :invalid_shape}` if shape is invalid
   - `{:error, :invalid_dtype}` if dtype is unsupported
   - `{:error, {:storage_error, reason}}` if storage initialization fails
   """
   ```

6. **Use Types** - Add typespecsthat include error types
   ```elixir
   @type create_error :: :invalid_shape | :invalid_dtype | {:storage_error, term()}
   @spec create(keyword()) :: {:ok, t()} | {:error, create_error()}
   ```

7. **Fail Fast** - Don't silently swallow errors
   ```elixir
   # Bad
   def process(array) do
     case ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100}) do
       {:ok, data} -> transform(data)
       {:error, _} -> []  # Silent failure!
     end
   end

   # Good
   def process(array) do
     case ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100}) do
       {:ok, data} -> {:ok, transform(data)}
       {:error, reason} -> {:error, reason}  # Propagate error
     end
   end
   ```

## See Also

- [Elixir Error Handling](https://hexdocs.pm/elixir/try-catch-and-rescue.html)
- [Telemetry Guide](telemetry.md)
- [Security Guide](SECURITY.md)
- [API Documentation](https://hexdocs.pm/ex_zarr)
