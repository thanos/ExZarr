defmodule ExZarr.Storage.FileLock do
  @moduledoc """
  File locking utilities for cross-process coordination on filesystem storage.

  Provides advisory file locking to prevent concurrent modifications to the same
  chunk file by different processes or even different BEAM instances.

  ## Features

  - Advisory locking via `:file.open` with `:exclusive` mode
  - Automatic lock release on process termination
  - Timeout support for lock acquisition
  - Compatible with NFS and other network filesystems (best-effort)

  ## Lock Types

  - **Write locks**: Use `:exclusive` mode, prevents all other access
  - **Read locks**: Advisory only, multiple readers can open simultaneously

  ## Limitations

  - Advisory locks only (not enforced by OS)
  - Network filesystem compatibility varies
  - Lock files may persist if process crashes before cleanup

  ## Usage

      # Acquire write lock
      {:ok, lock} = ExZarr.Storage.FileLock.acquire_write("/path/to/chunk", timeout: 5000)

      # Write data...

      # Release lock
      :ok = ExZarr.Storage.FileLock.release(lock)

      # Or use with_lock for automatic cleanup
      ExZarr.Storage.FileLock.with_write_lock("/path/to/file", fn ->
        # Write operations here
        :ok
      end)
  """

  require Logger

  @type lock :: %{
          path: String.t(),
          lock_file: String.t(),
          fd: :file.fd() | nil,
          type: :read | :write
        }

  @type lock_error :: :timeout | :eexist | :eacces | term()

  @default_timeout 5_000
  @lock_suffix ".lock"

  @doc """
  Acquires an exclusive write lock on a file.

  Creates a lock file with `.lock` extension. The lock is automatically
  released when the process terminates or when explicitly released.

  ## Options

  - `:timeout` - Maximum time to wait for lock in milliseconds (default: 5000)
  - `:retries` - Number of retry attempts (default: based on timeout)

  ## Returns

  - `{:ok, lock}` if lock acquired
  - `{:error, :timeout}` if lock couldn't be acquired
  - `{:error, reason}` for other errors
  """
  @spec acquire_write(String.t(), keyword()) :: {:ok, lock()} | {:error, lock_error()}
  def acquire_write(path, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    lock_file = path <> @lock_suffix

    acquire_with_retry(lock_file, :write, timeout)
  end

  @doc """
  Acquires a read lock on a file.

  For read locks, we use a less restrictive approach since multiple readers
  are allowed. This is advisory only.

  ## Options

  - `:timeout` - Maximum time to wait for lock in milliseconds (default: 5000)

  ## Returns

  - `{:ok, lock}` if lock acquired
  - `{:error, reason}` for errors
  """
  @spec acquire_read(String.t(), keyword()) :: {:ok, lock()} | {:error, lock_error()}
  def acquire_read(path, _opts \\ []) do
    lock_file = path <> @lock_suffix <> ".read"

    # Ensure the parent directory exists for the lock file
    lock_dir = Path.dirname(lock_file)
    _ = File.mkdir_p(lock_dir)

    # For read locks, we just open the file without exclusive mode
    case :file.open(lock_file, [:read, :write, :binary]) do
      {:ok, fd} ->
        lock = %{
          path: path,
          lock_file: lock_file,
          fd: fd,
          type: :read
        }

        {:ok, lock}

      {:error, :enoent} ->
        # File doesn't exist, create it
        case :file.open(lock_file, [:read, :write, :binary, :raw]) do
          {:ok, fd} ->
            lock = %{
              path: path,
              lock_file: lock_file,
              fd: fd,
              type: :read
            }

            {:ok, lock}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Releases a lock.

  Closes the lock file handle and removes the lock file if it's a write lock.
  """
  @spec release(lock()) :: :ok
  def release(%{fd: fd, lock_file: lock_file, type: type} = _lock) do
    # Close file handle
    _ =
      if fd != nil do
        :file.close(fd)
      end

    # Remove lock file for write locks
    _ =
      if type == :write do
        File.rm(lock_file)
      end

    :ok
  end

  @doc """
  Executes a function while holding a write lock.

  Automatically acquires the lock before executing and releases it after.
  Ensures cleanup even if the function raises an error.

  ## Example

      ExZarr.Storage.FileLock.with_write_lock("/path/to/file", timeout: 10_000, fn ->
        # Write operations here
        File.write!("/path/to/file", data)
      end)
  """
  @spec with_write_lock(String.t(), keyword(), (-> result)) ::
          {:ok, result} | {:error, lock_error()}
        when result: term()
  def with_write_lock(path, opts \\ [], fun) do
    case acquire_write(path, opts) do
      {:ok, lock} ->
        try do
          result = fun.()
          {:ok, result}
        after
          release(lock)
        end

      error ->
        error
    end
  end

  @doc """
  Executes a function while holding a read lock.

  Similar to `with_write_lock/3` but for read operations.
  """
  @spec with_read_lock(String.t(), keyword(), (-> result)) ::
          {:ok, result} | {:error, lock_error()}
        when result: term()
  def with_read_lock(path, opts \\ [], fun) do
    case acquire_read(path, opts) do
      {:ok, lock} ->
        try do
          result = fun.()
          {:ok, result}
        after
          release(lock)
        end

      error ->
        error
    end
  end

  @doc """
  Checks if a write lock exists for a file.

  Returns `true` if a lock file exists, `false` otherwise.
  Note: This is a best-effort check and subject to race conditions.
  """
  @spec locked?(String.t()) :: boolean()
  def locked?(path) do
    lock_file = path <> @lock_suffix
    File.exists?(lock_file)
  end

  @doc """
  Removes a stale lock file.

  Use with caution - only call this if you're certain the lock is stale
  (e.g., from a crashed process).
  """
  @spec remove_stale_lock(String.t()) :: :ok | {:error, atom()}
  def remove_stale_lock(path) do
    lock_file = path <> @lock_suffix
    File.rm(lock_file)
  end

  ## Private Helpers

  defp acquire_with_retry(lock_file, type, timeout) do
    start_time = System.monotonic_time(:millisecond)
    # 50ms between retries
    retry_interval = 50

    do_acquire_with_retry(lock_file, type, start_time, timeout, retry_interval)
  end

  defp do_acquire_with_retry(lock_file, type, start_time, timeout, retry_interval) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      {:error, :timeout}
    else
      case try_acquire(lock_file, type) do
        {:ok, lock} ->
          {:ok, lock}

        {:error, :eexist} ->
          # Lock file exists, wait and retry
          Process.sleep(retry_interval)
          do_acquire_with_retry(lock_file, type, start_time, timeout, retry_interval)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp try_acquire(lock_file, type) do
    # Ensure the parent directory exists for the lock file
    lock_dir = Path.dirname(lock_file)
    _ = File.mkdir_p(lock_dir)

    # Try to create and open the lock file exclusively
    # The :exclusive flag ensures the file is created atomically
    # and fails if it already exists
    case :file.open(lock_file, [:write, :binary, :exclusive, :raw]) do
      {:ok, fd} ->
        # Write PID to lock file for debugging
        pid_info = "#{inspect(self())}\n"
        _ = :file.write(fd, pid_info)

        lock = %{
          path: String.replace_suffix(lock_file, @lock_suffix, ""),
          lock_file: lock_file,
          fd: fd,
          type: type
        }

        {:ok, lock}

      {:error, :eexist} ->
        # Lock already exists
        {:error, :eexist}

      {:error, reason} ->
        Logger.warning("Failed to acquire lock on #{lock_file}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
