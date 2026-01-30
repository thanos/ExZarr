# Troubleshooting Guide

This guide helps diagnose and fix common ExZarr issues. Problems are organized by symptom to help you quickly find solutions.

## Table of Contents

- [Build and Installation Issues](#build-and-installation-issues)
- [Runtime Errors (Codec/Storage)](#runtime-errors-codecstorage)
- [Memory Issues](#memory-issues)
- [Cloud Storage Problems (S3/GCS/Azure)](#cloud-storage-problems-s3gcsazure)
- [Data Integrity Issues](#data-integrity-issues)
- [Performance Problems](#performance-problems)
- [Python Interoperability Issues](#python-interoperability-issues)
- [Common Gotchas Checklist](#common-gotchas-checklist)
- [Getting Help](#getting-help)

## Build and Installation Issues

### Issue: Zig compilation fails during `mix compile`

**Symptom**: Error messages mentioning "zig", "NIF", or "zigler" during compilation.

**Cause**: Missing system libraries for optional codecs (zstd, lz4, snappy, blosc, bzip2).

**Diagnosis**:

```bash
# macOS: Check installed libraries
brew list | grep -E "zstd|lz4|snappy|blosc|bzip2"

# Ubuntu/Debian: Check installed packages
dpkg -l | grep -E "zstd|lz4|snappy|blosc|bzip2"

# Arch Linux
pacman -Q | grep -E "zstd|lz4|snappy|blosc|bzip2"
```

**Fix**:

```bash
# macOS
brew install zstd lz4 snappy c-blosc bzip2

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev

# Arch Linux
sudo pacman -S zstd lz4 snappy blosc bzip2

# Fedora/RHEL
sudo dnf install zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel

# After installing libraries, recompile
mix deps.clean ex_zarr --build
mix deps.get
mix compile
```

**Workaround**: If you can't install these libraries, ExZarr will still work with zlib-only compression (always available, no dependencies):

```elixir
# Use zlib or gzip (no Zig NIFs needed)
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib  # Always available
)
```

---

### Issue: Mix hangs during compilation

**Symptom**: `mix compile` stalls with no output for several minutes.

**Cause**: Zigler is downloading the Zig toolchain (first-time only). This can take 5-10 minutes on slow connections.

**Diagnosis**:

```bash
# Check if Zig is being downloaded
ls -lh ~/.cache/zigler/

# Monitor network activity (macOS)
nettop -m tcp

# Monitor network activity (Linux)
iftop
```

**Fix**: Wait patiently. The download happens once and is cached.

**Alternative**: Pre-install Zig manually to skip automatic download:

```bash
# macOS
brew install zig

# Ubuntu (download from ziglang.org)
wget https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz
tar xf zig-linux-x86_64-0.11.0.tar.xz
sudo mv zig-linux-x86_64-0.11.0 /usr/local/zig
export PATH=$PATH:/usr/local/zig
```

---

### Issue: Architecture mismatch on Apple Silicon (M1/M2/M3)

**Symptom**: Errors like "Architecture not supported", "dyld: Library not loaded", or "wrong architecture".

**Cause**: System libraries installed for wrong architecture (x86_64 instead of ARM64).

**Diagnosis**:

```bash
# Check current architecture
uname -m  # Should show "arm64"

# Check library architecture
file /opt/homebrew/lib/libzstd.dylib  # Should show "arm64"

# If using Rosetta accidentally
arch  # Should show "arm64", not "i386"
```

**Fix**:

```bash
# Ensure using native Homebrew (not Rosetta)
which brew  # Should be /opt/homebrew/bin/brew

# Reinstall libraries for ARM64
brew reinstall zstd lz4 snappy c-blosc bzip2

# Clean and recompile
mix deps.clean ex_zarr --build
mix compile
```

---

### Issue: ExZarr compiles but codec not available at runtime

**Symptom**: `{:error, :codec_not_available}` when creating array, even after successful compilation.

**Diagnosis**:

```elixir
# Check which codecs are available
ExZarr.Codecs.available_codecs()
# Expected: [:zlib, :gzip, :zstd, :lz4, :snappy, :blosc, :bzip2, :crc32c]
# If missing codecs, NIF failed to load

# Check NIF load status
:code.which(ExZarr.Codecs.ZigCodecs)
# Should return path to .beam file, not :non_existing
```

**Cause**: Runtime library paths not configured correctly.

**Fix**:

```bash
# Linux: Check LD_LIBRARY_PATH
echo $LD_LIBRARY_PATH
# Should include /usr/lib, /usr/local/lib

export LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH

# macOS: Check DYLD_LIBRARY_PATH (rarely needed)
# Homebrew libraries are usually found automatically

# Verify libraries are loadable
ldd /path/to/_build/dev/lib/ex_zarr/priv/zig_codecs.so  # Linux
otool -L /path/to/_build/dev/lib/ex_zarr/priv/zig_codecs.so  # macOS
```

---

### Issue: Compilation fails with "zigler not found"

**Symptom**: Error message "Could not find zigler" during compilation.

**Cause**: Zigler dependency not installed.

**Fix**:

```bash
# Ensure dependencies are fetched
mix deps.get

# If problem persists, clean and retry
mix deps.clean --all
mix deps.get
mix compile
```

## Runtime Errors (Codec/Storage)

### Issue: `{:error, :not_found}` when reading array

**Symptom**: ExZarr.open/1 or ExZarr.Array.get_slice/3 returns `{:error, :not_found}`.

**Diagnosis**:

```bash
# Check directory exists
ls -la /path/to/array

# Check for metadata file
ls -la /path/to/array/.zarray      # Zarr v2
ls -la /path/to/array/zarr.json    # Zarr v3

# Check file permissions
stat /path/to/array/.zarray
```

**Cause**: Path incorrect, array not created, or permissions issue.

**Fix**:

1. Verify path is correct:
   ```elixir
   # Use absolute path
   {:ok, array} = ExZarr.open(path: "/absolute/path/to/array")

   # Not relative path
   {:ok, array} = ExZarr.open(path: "relative/path")  # May fail
   ```

2. Check array was saved:
   ```elixir
   # After creating array, ensure it's saved
   {:ok, array} = ExZarr.create(...)
   :ok = ExZarr.Array.save(array)  # Don't forget this!
   ```

3. Fix permissions:
   ```bash
   # Make readable
   chmod -R 755 /path/to/array
   ```

---

### Issue: `{:error, :decompression_failed}`

**Symptom**: Reading chunk fails with decompression error.

**Diagnosis**:

```elixir
# Check which codec was used
{:ok, array} = ExZarr.open(path: "/path/to/array")
IO.inspect(array.metadata.compressor, label: "Compressor")

# Check if codec is available
ExZarr.Codecs.available_codecs()
|> Enum.member?(:zstd)  # Or whatever codec is used
```

**Cause 1**: Codec not available on reading system.

**Fix**: Install required codec library (see [Build and Installation Issues](#build-and-installation-issues)).

**Cause 2**: Corrupted chunk data.

**Diagnosis**:

```elixir
# Try reading other chunks to see if corruption is localized
{:ok, chunk1} = ExZarr.Array.read_chunk(array, {0, 0})  # May fail
{:ok, chunk2} = ExZarr.Array.read_chunk(array, {0, 1})  # May succeed
```

**Fix**: Re-write corrupted chunk or restore from backup.

**Cause 3**: Codec version mismatch (rare).

**Fix**: Ensure same codec library versions on read/write systems:

```bash
# Check version
dpkg -l | grep libzstd  # Debian/Ubuntu
brew list --versions zstd  # macOS
```

---

### Issue: `{:error, :invalid_shape}` or `{:error, :dimension_mismatch}`

**Symptom**: `set_slice/3` fails with shape error.

**Diagnosis**:

```elixir
# Check data shape matches slice dimensions
data = {{1.0, 2.0}, {3.0, 4.0}}  # 2×2 data

# Calculate expected shape from start/stop
start = {0, 0}
stop = {2, 2}
expected_shape = {elem(stop, 0) - elem(start, 0), elem(stop, 1) - elem(start, 1)}
# Result: {2, 2}

# Verify data matches
IO.inspect(data, label: "Data")
IO.inspect(expected_shape, label: "Expected shape")
```

**Cause**: Data dimensions don't match start/stop coordinates.

**Fix**:

```elixir
# Correct: Data shape matches slice
data = {{1.0, 2.0, 3.0}, {4.0, 5.0, 6.0}}  # 2×3
ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {2, 3}  # 2×3 slice
)

# Wrong: Mismatch
data = {{1.0, 2.0}, {3.0, 4.0}}  # 2×2
ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {2, 3}  # ERROR: 2×3 slice but 2×2 data
)
```

---

### Issue: `{:error, :storage_error}` with filesystem storage

**Symptom**: Read/write operations fail with storage error.

**Diagnosis**:

```bash
# Check disk space
df -h /path/to/array

# Check inode usage (can run out even with free space)
df -i /path/to/array

# Check write permissions
touch /path/to/array/test_file && rm /path/to/array/test_file
```

**Cause**: Disk full, out of inodes, or permission denied.

**Fix**:

```bash
# Free up space
rm -rf /path/to/unnecessary/files

# Fix permissions
chmod -R u+w /path/to/array

# Move to different filesystem if out of inodes
```

---

### Issue: `{:error, :invalid_metadata}`

**Symptom**: Cannot open array, metadata parsing fails.

**Diagnosis**:

```bash
# Check metadata file is valid JSON
cat /path/to/array/.zarray | python3 -m json.tool
# Or use jq
cat /path/to/array/.zarray | jq .
```

**Cause**: Corrupted or manually edited metadata file.

**Fix**:

1. Restore from backup if available
2. Manually fix JSON syntax errors
3. Recreate array if no backup available

## Memory Issues

### Issue: Process crashes with "Out of memory" error

**Symptom**: Elixir process exits, system runs out of RAM, or VM terminates.

**Diagnosis**:

```elixir
# Monitor memory before operation
before = :erlang.memory(:total) |> div(1024 * 1024)
IO.puts("Memory before: #{before} MB")

# Run operation
ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10000, 10000})

# Check memory after
after_mem = :erlang.memory(:total) |> div(1024 * 1024)
IO.puts("Memory after: #{after_mem} MB")
IO.puts("Memory used: #{after_mem - before} MB")

# Check process memory specifically
Process.info(self(), :memory) |> elem(1) |> div(1024 * 1024)
```

**Cause**: Loading too many chunks concurrently, or chunks too large.

**Fix**:

1. **Reduce chunk size**:
   ```elixir
   # Large chunks (10 MB each)
   chunks: {1000, 1000}  # For float64: 1000 * 1000 * 8 = 8 MB

   # Smaller chunks (2.5 MB each)
   chunks: {500, 500}  # 500 * 500 * 8 = 2 MB
   ```

2. **Decrease parallelism**:
   ```elixir
   # High concurrency (uses more memory)
   Task.async_stream(chunks, &process/1, max_concurrency: 16)

   # Lower concurrency (uses less memory)
   Task.async_stream(chunks, &process/1, max_concurrency: 4)
   ```

3. **Use streaming**:
   ```elixir
   # Load entire array (high memory)
   {:ok, data} = ExZarr.Array.get_slice(array,
     start: {0, 0},
     stop: {10000, 10000}
   )

   # Stream chunks (constant memory)
   array
   |> ExZarr.Array.chunk_stream(parallel: 1)
   |> Stream.each(&process_chunk/1)
   |> Stream.run()
   ```

4. **Increase system RAM** (if application genuinely needs it).

---

### Issue: Memory usage grows over time (memory leak)

**Symptom**: Memory steadily increases with each operation, not reclaimed by garbage collection.

**Diagnosis**:

```elixir
# Monitor memory over multiple operations
for i <- 1..10 do
  before = :erlang.memory(:total)

  # Perform operation
  perform_operation()

  # Force GC
  :erlang.garbage_collect()
  Process.sleep(100)

  after_mem = :erlang.memory(:total)
  leaked = (after_mem - before) |> div(1024 * 1024)

  IO.puts("Iteration #{i}: Leaked #{leaked} MB")
end
```

**Cause**: Holding references to large binaries in process state (e.g., Agent, GenServer).

**Fix**:

```elixir
# Bad: Accumulating data in process state
defmodule LeakyProcessor do
  use GenServer

  def handle_call(:process, _from, state) do
    data = load_large_array()
    # Problem: Adding to state grows unbounded
    {:reply, :ok, Map.put(state, :data, data)}
  end
end

# Good: Process and discard
defmodule CleanProcessor do
  use GenServer

  def handle_call(:process, _from, state) do
    data = load_large_array()
    result = process(data)
    # Data discarded after function returns
    {:reply, result, state}
  end
end
```

---

### Issue: "Binary too large" error

**Symptom**: Error when creating array or writing large chunk: `ArgumentError: binary too large`.

**Cause**: Chunk size exceeds BEAM binary size limit (theoretical limit ~2 GB per binary, practical limit varies).

**Fix**: Use smaller chunks.

```elixir
# Too large (may fail)
chunks: {10000, 10000}  # 10000 * 10000 * 8 = 800 MB per chunk

# Better (recommended)
chunks: {1000, 1000}  # 1000 * 1000 * 8 = 8 MB per chunk

# General guideline: Keep chunks < 100 MB
```

## Cloud Storage Problems (S3/GCS/Azure)

### Issue: S3 authentication fails

**Symptom**: `{:error, :access_denied}`, `{:error, :unauthorized}`, or AWS signature errors.

**Diagnosis**:

```bash
# Check environment variables
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY
echo $AWS_REGION
echo $AWS_DEFAULT_REGION

# Test S3 access with AWS CLI
aws s3 ls s3://your-bucket/
aws s3 ls s3://your-bucket/path/to/array/

# Check IAM permissions
aws iam get-user
```

**Cause**: Invalid credentials, missing IAM permissions, or wrong region.

**Fix**:

1. **Verify credentials**:
   ```bash
   # Set environment variables
   export AWS_ACCESS_KEY_ID="your_access_key"
   export AWS_SECRET_ACCESS_KEY="your_secret_key"
   export AWS_REGION="us-east-1"
   ```

2. **Check IAM policy**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:ListBucket",
           "s3:DeleteObject"
         ],
         "Resource": [
           "arn:aws:s3:::your-bucket",
           "arn:aws:s3:::your-bucket/*"
         ]
       }
     ]
   }
   ```

3. **Verify bucket and region**:
   ```elixir
   # Check bucket exists in correct region
   {:ok, array} = ExZarr.create(
     storage: :s3,
     bucket: "your-bucket",
     prefix: "arrays/my_array",
     region: "us-east-1",  # Must match bucket region
     ...
   )
   ```

---

### Issue: S3 operations very slow

**Symptom**: Each chunk read takes 1+ seconds, total operation takes minutes.

**Diagnosis**:

```elixir
# Time individual chunk reads
{time, _result} = :timer.tc(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)

IO.puts("Time: #{time / 1000} ms")
# If > 500ms per chunk, investigate
```

**Cause 1**: Chunks too small (too many API calls).

**Fix**: Increase chunk size:

```elixir
# Small chunks (bad for S3)
chunks: {10, 10}  # 100 API calls for 100×100 region

# Larger chunks (good for S3)
chunks: {100, 100}  # 1 API call for 100×100 region

# Recommended: 5-50 MB per chunk for S3
```

**Cause 2**: Wrong region (cross-region latency).

**Diagnosis**:

```bash
# Check bucket region
aws s3api get-bucket-location --bucket your-bucket

# Check compute region
curl -s http://169.254.169.254/latest/meta-data/placement/region  # EC2
```

**Fix**: Use bucket in same region as compute, or use S3 Transfer Acceleration:

```elixir
# Enable Transfer Acceleration
config :ex_aws, :s3,
  scheme: "https://",
  host: "your-bucket.s3-accelerate.amazonaws.com"
```

**Cause 3**: No parallelism.

**Fix**: Use parallel reads:

```elixir
# Sequential (slow)
for chunk <- chunks do
  ExZarr.Array.read_chunk(array, chunk)
end

# Parallel (fast)
Task.async_stream(chunks, fn chunk ->
  ExZarr.Array.read_chunk(array, chunk)
end, max_concurrency: 8)
|> Enum.to_list()
```

---

### Issue: GCS "Invalid JWT signature" error

**Symptom**: Google Cloud Storage authentication fails with JWT-related error.

**Cause**: Service account JSON file corrupted, incomplete, or has wrong permissions.

**Diagnosis**:

```bash
# Check service account file is valid JSON
cat service-account.json | python3 -m json.tool

# Verify file contains required fields
cat service-account.json | jq '.private_key, .client_email'
```

**Fix**:

1. Re-download service account key from GCP Console:
   - Go to IAM & Admin → Service Accounts
   - Select service account → Keys → Add Key → Create new key
   - Download JSON file

2. Verify permissions:
   ```bash
   # Service account needs Storage Object Admin or equivalent
   gcloud projects get-iam-policy PROJECT_ID \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:YOUR_EMAIL"
   ```

3. Set environment variable:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
   ```

---

### Issue: Azure "AuthenticationFailed" error

**Symptom**: Cannot access Azure Blob Storage, 403 Forbidden errors.

**Diagnosis**:

```bash
# Check account key format (long base64 string)
echo $AZURE_STORAGE_ACCOUNT_KEY | wc -c
# Should be 88+ characters

# Test with Azure CLI
az storage blob list --account-name myaccount --container-name mycontainer
```

**Cause**: Invalid account key, wrong account name, or corrupted key (truncated, whitespace).

**Fix**:

1. Regenerate account key from Azure Portal:
   - Storage Account → Access keys → Regenerate

2. Ensure no whitespace:
   ```bash
   # Remove any whitespace/newlines
   export AZURE_STORAGE_ACCOUNT_KEY="$(echo $AZURE_STORAGE_ACCOUNT_KEY | tr -d '[:space:]')"
   ```

3. Verify account name is correct:
   ```elixir
   {:ok, array} = ExZarr.create(
     storage: :azure_blob,
     account_name: "mystorageaccount",  # Must match exactly
     container_name: "mycontainer",
     ...
   )
   ```

---

### Issue: Cloud storage rate limiting

**Symptom**: Intermittent errors like "SlowDown" (S3) or 429 status codes.

**Cause**: Exceeding cloud provider rate limits.

**S3 rate limits**:
- 5,500 GET requests/second per prefix
- 3,500 PUT requests/second per prefix

**Fix**:

1. **Partition across multiple prefixes**:
   ```elixir
   # Use different prefixes to get 10× throughput
   prefix = "arrays/partition_#{rem(array_id, 10)}/my_array"
   # Now you get 55,000 GET/s and 35,000 PUT/s total
   ```

2. **Reduce parallelism**:
   ```elixir
   # Lower concurrency to stay under limits
   max_concurrency: 4  # Instead of 16
   ```

3. **Implement exponential backoff**:
   ```elixir
   defmodule RetryHelper do
     def with_retry(func, max_attempts \\ 3) do
       retry(func, max_attempts, 0)
     end

     defp retry(func, max_attempts, attempt) do
       case func.() do
         {:ok, result} -> {:ok, result}
         {:error, :rate_limit} when attempt < max_attempts ->
           wait_time = :math.pow(2, attempt) * 100  # Exponential backoff
           Process.sleep(round(wait_time))
           retry(func, max_attempts, attempt + 1)
         error -> error
       end
     end
   end
   ```

## Data Integrity Issues

### Issue: Data read back doesn't match what was written

**Symptom**: Values differ after write → read cycle.

**Diagnosis**:

```elixir
# Write known test data
test_data = {{1.0, 2.0}, {3.0, 4.0}}
:ok = ExZarr.Array.set_slice(array, test_data,
  start: {0, 0},
  stop: {2, 2}
)

# Read back immediately
{:ok, read_data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {2, 2}
)

# Compare
if test_data == read_data do
  IO.puts("Data matches")
else
  IO.puts("Data mismatch!")
  IO.inspect(test_data, label: "Written")
  IO.inspect(read_data, label: "Read")
end
```

**Cause 1**: Dtype mismatch (e.g., writing floats to int array causes truncation).

**Fix**:

```elixir
# Check array dtype
IO.inspect(array.metadata.dtype)

# Ensure data type matches
# Writing float data:
{:ok, array} = ExZarr.create(dtype: :float64, ...)  # Use float64

# Writing integer data:
{:ok, array} = ExZarr.create(dtype: :int32, ...)  # Use int32
```

**Cause 2**: Concurrent writes to same chunk (race condition).

**Diagnosis**: Check if multiple processes writing to overlapping regions.

**Fix**: Coordinate writes to avoid overlaps:

```elixir
# Bad: Concurrent writes to same chunk
Task.async(fn -> write_region(array, {0, 0}, {100, 100}) end)
Task.async(fn -> write_region(array, {50, 50}, {150, 150}) end)  # Overlaps!

# Good: Non-overlapping writes
Task.async(fn -> write_region(array, {0, 0}, {100, 100}) end)
Task.async(fn -> write_region(array, {100, 100}, {200, 200}) end)  # No overlap
```

**Cause 3**: Not saving array (filesystem storage).

**Fix**:

```elixir
# Don't forget to save!
{:ok, array} = ExZarr.create(storage: :filesystem, ...)
ExZarr.Array.set_slice(array, data, ...)
:ok = ExZarr.Array.save(array)  # Important!
```

---

### Issue: Chunks missing or incomplete

**Symptom**: Some regions return `fill_value` instead of written data.

**Diagnosis**:

```elixir
# Check which chunks exist
{:ok, chunk_indices} = list_stored_chunks(array)
IO.inspect(chunk_indices, label: "Stored chunks")

# Expected chunks
expected = generate_expected_chunks(array)
missing = expected -- chunk_indices
IO.inspect(missing, label: "Missing chunks")
```

**Cause**: Write operation failed silently or was interrupted.

**Fix**:

1. **Always check write return values**:
   ```elixir
   # Check for errors
   case ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100}) do
     :ok -> IO.puts("Write successful")
     {:error, reason} -> IO.puts("Write failed: #{inspect(reason)}")
   end
   ```

2. **Use transactions for critical writes** (database backends):
   ```elixir
   # Wrap in transaction
   Mnesia.transaction(fn ->
     ExZarr.Array.set_slice(array, data, ...)
   end)
   ```

3. **Implement checksums** for data integrity:
   ```elixir
   # Use CRC32C codec
   {:ok, array} = ExZarr.create(
     codecs: [
       %{name: "crc32c"},  # Checksum validation
       %{name: "zstd", level: 3}
     ],
     ...
   )
   ```

---

### Issue: Checksum validation fails

**Symptom**: `{:error, :checksum_mismatch}` when reading with CRC32C codec.

**Cause**: Data corrupted during storage/transmission, or codec bug.

**Diagnosis**:

```elixir
# Try reading with checksum disabled
{:ok, array_no_checksum} = ExZarr.open(
  path: array.storage.path,
  skip_checksum: true  # If supported
)

{:ok, data} = ExZarr.Array.get_slice(array_no_checksum, ...)
# If this succeeds, data is present but checksum mismatches
```

**Fix**:

1. **Re-write affected chunks**:
   ```elixir
   # Identify corrupted chunks, rewrite from source
   source_data = load_from_backup()
   ExZarr.Array.set_slice(array, source_data, ...)
   ```

2. **Check storage backend integrity**:
   - Filesystem: Run `fsck` to check disk errors
   - Cloud: Verify data with provider's integrity checking tools

## Performance Problems

### Issue: Reads much slower than expected

**Symptom**: Multi-second latency for small reads.

**Diagnosis**:

```elixir
# Profile read operation
{time, _result} = :timer.tc(fn ->
  ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
end)

IO.puts("Read time: #{time / 1000} ms")

# Break down by component
{io_time, raw_data} = :timer.tc(fn -> storage_read(...) end)
{decompress_time, data} = :timer.tc(fn -> decompress(raw_data) end)

IO.puts("I/O: #{io_time / 1000} ms")
IO.puts("Decompression: #{decompress_time / 1000} ms")
```

**Possible causes and fixes**:

**1. Chunks too large** (loading unnecessary data):

```elixir
# Problem: 100 MB chunks, reading 1 MB region loads 100 MB
chunks: {10000, 10000}

# Fix: Reduce chunk size
chunks: {1000, 1000}
```

**2. Compression too slow**:

```elixir
# Problem: High compression level
compressor: %{id: "zstd", level: 19}  # Very slow

# Fix: Use faster compression
compressor: %{id: "zstd", level: 3}  # Faster
# Or even faster:
compressor: %{id: "lz4", level: 1}
```

**3. No parallelism**:

```elixir
# Sequential reads (slow)
for i <- 0..9 do
  ExZarr.Array.get_slice(array, start: {i * 100, 0}, stop: {(i + 1) * 100, 1000})
end

# Parallel reads (fast)
0..9
|> Task.async_stream(fn i ->
  ExZarr.Array.get_slice(array, start: {i * 100, 0}, stop: {(i + 1) * 100, 1000})
end, max_concurrency: 8)
|> Enum.to_list()
```

**4. Storage backend bottleneck**:

```bash
# Test disk speed
dd if=/dev/zero of=/tmp/test bs=1M count=1000
# Should be > 100 MB/s for SSD

# Test S3 latency
time aws s3 cp s3://bucket/key /tmp/test
```

For detailed performance tuning, see the [Performance Guide](performance.md).

---

### Issue: Writes much slower than expected

**Symptom**: Minutes to write small array.

**Diagnosis**:

```elixir
# Profile write operation
{time, _} = :timer.tc(fn ->
  ExZarr.Array.set_slice(array, large_data, start: {0, 0}, stop: {1000, 1000})
end)

IO.puts("Write time: #{time / 1000} ms")

# Break down compression
data_size = calculate_data_size(large_data)
throughput = data_size / (time / 1_000_000)  # bytes/sec
IO.puts("Throughput: #{throughput / 1_048_576} MB/s")
```

**Possible causes and fixes**:

**1. Compression level too high**:

```elixir
# Slow: Maximum compression
compressor: %{id: "zstd", level: 19}  # ~10 MB/s

# Faster: Moderate compression
compressor: %{id: "zstd", level: 3}   # ~100 MB/s

# Fastest: Light compression
compressor: %{id: "lz4", level: 1}    # ~500 MB/s
```

**2. Chunks too small** (compression overhead):

```elixir
# Problem: Tiny chunks, high overhead
chunks: {10, 10}  # Compress 400 bytes × 10,000 times

# Fix: Larger chunks
chunks: {100, 100}  # Compress 40 KB × 100 times
```

**3. Sequential writes**:

```elixir
# Use parallel writes when writing multiple chunks
Task.async_stream(chunk_data, fn {coords, data} ->
  ExZarr.Array.write_chunk(array, coords, data)
end, max_concurrency: 4)
|> Enum.to_list()
```

## Python Interoperability Issues

### Issue: Python zarr can't open ExZarr-created array

**Symptom**: Python error "Not a valid Zarr array" or "KeyError: .zarray".

**Diagnosis**:

```bash
# Check metadata file exists and is valid JSON
ls -la /path/to/array/.zarray
cat /path/to/array/.zarray | python3 -m json.tool

# Test in Python
python3 -c "import zarr; z = zarr.open('/path/to/array', mode='r'); print(z.info)"
```

**Cause**: Invalid JSON, unsupported codec, or wrong Zarr version.

**Fix**:

1. **Use Zarr v2 for compatibility**:
   ```elixir
   {:ok, array} = ExZarr.create(
     zarr_version: 2,  # Widely supported
     compressor: :zlib,  # Universally compatible
     ...
   )
   ```

2. **Verify JSON is valid**:
   ```bash
   cat /path/to/array/.zarray | python3 -m json.tool
   # Should output formatted JSON without errors
   ```

3. **Use standard codecs**:
   ```elixir
   # Python zarr always supports zlib/gzip
   compressor: :zlib
   # Or
   compressor: :gzip
   ```

---

### Issue: Data values don't match between Python and Elixir

**Symptom**: Same array shows different values in each language.

**Diagnosis**:

```python
# Python
import zarr
import numpy as np

z = zarr.open('/path/to/array', mode='r')
print(f"Shape: {z.shape}")
print(f"Dtype: {z.dtype}")
print(f"First element: {z[0, 0]}")
```

```elixir
# Elixir
{:ok, array} = ExZarr.open(path: "/path/to/array")
IO.inspect(array.metadata.shape)
IO.inspect(array.metadata.dtype)

{:ok, first_elem} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {1, 1})
IO.inspect(first_elem)
```

**Cause**: Dtype interpretation difference.

**Fix**: Ensure both use same dtype (see [Python Interop Guide](python_interop.md) compatibility matrix):

```elixir
# Compatible types
:int32, :int64, :float32, :float64, :uint8, etc.

# Incompatible (don't use for interop)
:bool, complex numbers, datetime
```

---

### Issue: Python can't decompress ExZarr chunks

**Symptom**: Python zarr opens array but fails when reading data.

**Cause**: Codec not available in Python environment.

**Fix**:

```bash
# Install required Python packages
pip install zarr
pip install zstd  # For zstd compression
pip install lz4   # For lz4 compression

# Verify installation
python3 -c "import zarr; print(zarr.codec_registry)"
```

For comprehensive Python interop guidance, see the [Python Interoperability Guide](python_interop.md).

## Common Gotchas Checklist

Avoid these common mistakes:

- [ ] **Forgetting to save array after writing** (filesystem storage)
  ```elixir
  ExZarr.Array.set_slice(array, data, ...)
  :ok = ExZarr.Array.save(array)  # Don't forget!
  ```

- [ ] **Using string path without storage option**
  ```elixir
  # Wrong
  {:ok, array} = ExZarr.create(path: "/data/array")

  # Right
  {:ok, array} = ExZarr.create(storage: :filesystem, path: "/data/array")
  ```

- [ ] **Chunk size too small** (< 100 KB) causing performance issues

- [ ] **Chunk size too large** (> 100 MB) causing memory issues

- [ ] **Writing to same chunk from multiple processes** (race condition)
  - Fix: Coordinate writes to non-overlapping regions

- [ ] **Assuming parallel operations when using `Enum`**
  ```elixir
  # Sequential (no parallelism)
  Enum.map(chunks, &process/1)

  # Parallel
  Task.async_stream(chunks, &process/1, max_concurrency: 8)
  ```

- [ ] **Not handling `{:error, reason}` returns**
  ```elixir
  # Bad: Pattern match assumes success
  {:ok, data} = ExZarr.Array.get_slice(...)

  # Good: Handle both cases
  case ExZarr.Array.get_slice(...) do
    {:ok, data} -> process(data)
    {:error, reason} -> handle_error(reason)
  end
  ```

- [ ] **Mixing Zarr v2 and v3 configuration syntax**
  - v2 uses `compressor: :zlib`
  - v3 uses `codecs: [%{name: "zlib"}]`
  - Don't mix them!

- [ ] **Using custom codec without registering it first**
  ```elixir
  # Register before use
  ExZarr.Codecs.register_codec(MyCustomCodec)
  ```

- [ ] **Hardcoding credentials in source code** (security issue)
  ```elixir
  # Bad
  aws_access_key_id: "AKIAIOSFODNN7EXAMPLE"

  # Good
  aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID")
  ```

- [ ] **Not installing Zig codecs then wondering why they're unavailable**
  - Check: `ExZarr.Codecs.available_codecs()`

- [ ] **Expecting Python NumPy arrays when ExZarr returns nested tuples**
  - ExZarr uses tuples, Python uses NumPy arrays
  - Convert: `Nx.tensor()` for numerical computing

- [ ] **Forgetting that uninitialized chunks return `fill_value`, not error**
  ```elixir
  # Reading unwritten chunk returns fill_value (default: 0)
  {:ok, data} = ExZarr.Array.get_slice(array, start: {100, 100}, stop: {200, 200})
  # data will be all zeros if never written
  ```

## Getting Help

### Check Documentation First

Before reporting issues, check existing resources:

- **API Documentation**: [https://hexdocs.pm/ex_zarr](https://hexdocs.pm/ex_zarr)
- **Guides**: Comprehensive guides covering most scenarios
  - [Installation Guide](../README.md#installation)
  - [Quickstart Guide](quickstart.md)
  - [Performance Guide](performance.md)
  - [Compression Guide](compression_codecs.md)
  - [Python Interop Guide](python_interop.md)
- **Examples**: Working code in `/examples` directory
  ```bash
  ls examples/
  # Run examples
  elixir examples/basic_usage.exs
  ```

### Verify Your Setup

Collect diagnostic information:

```elixir
# Check ExZarr version
{:ok, vsn} = :application.get_key(:ex_zarr, :vsn)
IO.puts("ExZarr version: #{vsn}")

# Check available codecs
codecs = ExZarr.Codecs.available_codecs()
IO.inspect(codecs, label: "Available codecs")

# Check Elixir/Erlang versions
IO.puts("Elixir: #{System.version()}")
IO.puts("Erlang/OTP: #{:erlang.system_info(:otp_release)}")

# Check OS
IO.puts("OS: #{:os.type() |> elem(0)}")
IO.puts("Architecture: #{:erlang.system_info(:system_architecture)}")
```

### Create Minimal Reproduction

When reporting issues:

1. **Simplify to smallest code that shows problem**:
   ```elixir
   # Minimal reproduction
   {:ok, array} = ExZarr.create(shape: {10, 10}, chunks: {5, 5}, dtype: :float64)
   # Problem occurs here:
   ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
   ```

2. **Remove dependencies on external data/services**:
   - Use `:memory` storage instead of S3
   - Generate test data instead of loading files

3. **Include full error message and stacktrace**:
   ```elixir
   try do
     problematic_operation()
   rescue
     e -> IO.puts(Exception.format(:error, e, __STACKTRACE__))
   end
   ```

### Report Issues

GitHub Issues: [https://github.com/thanos/ExZarr/issues](https://github.com/thanos/ExZarr/issues)

**Include in your report**:
- ExZarr version: `Mix.Project.config()[:version]`
- Elixir version: `System.version()`
- Erlang/OTP version: `:erlang.system_info(:otp_release)`
- Operating system: `uname -a` output
- Full error message
- Minimal code to reproduce
- Expected behavior vs actual behavior

**Good issue template**:

```markdown
## Environment
- ExZarr version: 1.0.0
- Elixir version: 1.19.5
- Erlang/OTP version: 28.1
- OS: macOS 15.2 (arm64)

## Problem
Reading chunks fails with decompression error.

## Reproduction
\`\`\`elixir
{:ok, array} = ExZarr.create(
  shape: {100, 100},
  chunks: {10, 10},
  dtype: :float64,
  compressor: :zstd
)
{:ok, _} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10, 10})
# Error: {:error, :decompression_failed}
\`\`\`

## Expected
Read should succeed.

## Actual
Returns {:error, :decompression_failed}

## Additional Context
Available codecs: [:zlib, :gzip]
(Note: :zstd missing)
```

### Community Resources

- **Elixir Forum**: [https://elixirforum.com](https://elixirforum.com)
  - Tag posts with "exzarr" or "zarr"
- **Elixir Slack**: [https://elixir-slackin.herokuapp.com](https://elixir-slackin.herokuapp.com)
  - Join #scientific-computing channel
- **Discord**: Elixir community server
  - Ask in #help or #data-science channels

### Related Resources

- **Zarr Specification**: [https://zarr-specs.readthedocs.io](https://zarr-specs.readthedocs.io)
- **Python zarr Documentation**: [https://zarr.readthedocs.io](https://zarr.readthedocs.io)
- **Elixir Documentation**: [https://elixir-lang.org/docs.html](https://elixir-lang.org/docs.html)

## Summary

Most issues fall into these categories:

1. **Build/Installation**: Install system libraries for codecs
2. **Runtime Errors**: Check paths, permissions, codec availability
3. **Memory**: Reduce chunk size or parallelism, use streaming
4. **Cloud Storage**: Verify credentials, check regions, increase chunk size
5. **Data Integrity**: Check dtypes, avoid concurrent writes, use checksums
6. **Performance**: Optimize chunk size, compression, parallelism
7. **Python Interop**: Use Zarr v2, standard codecs, compatible dtypes

**Quick diagnostic flow**:
1. Check error message → search this guide
2. Verify setup with diagnostic commands
3. Try simplest workaround first
4. If issue persists, create minimal reproduction
5. Report issue with full diagnostic info

For workload-specific optimization, see the [Performance Guide](performance.md).
