# Security Policy

## Supported Versions

We release security updates for the following versions of ExZarr:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| 0.7.x   | :white_check_mark: |
| 0.6.x   | :x:                |
| < 0.6   | :x:                |

For production deployments, we strongly recommend using the latest stable release to ensure you have all security patches.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in ExZarr, please report it by emailing:

**security@exzarr.dev** (or contact the maintainer directly at the email listed in mix.exs)

Please include the following information:

- Type of vulnerability
- Full paths of source file(s) related to the vulnerability
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the vulnerability, including how an attacker might exploit it

### What to Expect

- **Initial Response**: Within 48 hours, we'll acknowledge your report
- **Investigation**: We'll investigate and confirm the vulnerability within 5 business days
- **Fix Development**: We'll develop a fix and coordinate disclosure timeline with you
- **Public Disclosure**: After a fix is released, we'll publicly disclose the vulnerability (with credit to you if desired)

We appreciate responsible disclosure and will acknowledge security researchers in our CHANGELOG.md.

## Security Best Practices

### For ExZarr Users

When using ExZarr in production, follow these security guidelines:

#### 1. Input Validation

Always validate user inputs before passing them to ExZarr:

```elixir
defmodule SafeZarr do
  @doc "Safely create array with validated inputs"
  def safe_create(opts) do
    with :ok <- validate_shape(opts[:shape]),
         :ok <- validate_chunks(opts[:chunks]),
         :ok <- validate_path(opts[:path]),
         :ok <- validate_dtype(opts[:dtype]) do
      ExZarr.create(opts)
    end
  end

  defp validate_shape(shape) when is_tuple(shape) do
    if Enum.all?(Tuple.to_list(shape), &is_integer/1) and
       Enum.all?(Tuple.to_list(shape), &(&1 > 0)) do
      :ok
    else
      {:error, :invalid_shape}
    end
  end
  defp validate_shape(_), do: {:error, :invalid_shape}

  defp validate_chunks(chunks) when is_tuple(chunks) do
    if Enum.all?(Tuple.to_list(chunks), &is_integer/1) and
       Enum.all?(Tuple.to_list(chunks), &(&1 > 0)) do
      :ok
    else
      {:error, :invalid_chunks}
    end
  end
  defp validate_chunks(_), do: {:error, :invalid_chunks}

  defp validate_path(path) when is_binary(path) do
    cond do
      String.contains?(path, "..") ->
        {:error, :path_traversal_attempt}
      String.starts_with?(path, "/etc") or String.starts_with?(path, "/sys") ->
        {:error, :restricted_path}
      true ->
        :ok
    end
  end
  defp validate_path(_), do: {:error, :invalid_path}

  defp validate_dtype(dtype) when dtype in [:i1, :i2, :i4, :i8, :u1, :u2, :u4, :u8, :f4, :f8] do
    :ok
  end
  defp validate_dtype(_), do: {:error, :invalid_dtype}
end
```

#### 2. Path Traversal Prevention

Prevent directory traversal attacks by validating file paths:

```elixir
defmodule PathValidator do
  @doc "Ensure path is within allowed directory"
  def validate_path(path, base_dir) do
    absolute_path = Path.expand(path, base_dir)
    absolute_base = Path.expand(base_dir)

    if String.starts_with?(absolute_path, absolute_base) do
      {:ok, absolute_path}
    else
      {:error, :path_outside_base_directory}
    end
  end

  @doc "Sanitize user-provided path"
  def sanitize_path(path) do
    path
    |> String.replace(~r/\.\./, "")  # Remove ..
    |> String.replace(~r/\/+/, "/")   # Normalize slashes
    |> String.trim_leading("/")       # Remove leading slash
  end
end

# Usage
case PathValidator.validate_path(user_path, "/safe/base/dir") do
  {:ok, safe_path} -> ExZarr.open(storage: :filesystem, path: safe_path)
  {:error, reason} -> {:error, reason}
end
```

#### 3. Cloud Storage Authentication

**S3 Security:**

```elixir
# Use IAM roles instead of hardcoded credentials
config :ex_aws,
  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"},
  region: "us-east-1"

# Enable bucket versioning for data recovery
# Use bucket policies to restrict access
# Enable server-side encryption

{:ok, array} = ExZarr.open(
  storage: :s3,
  bucket: "my-secure-bucket",
  prefix: "arrays/production",
  # S3 will use environment credentials
)
```

**GCS Security:**

```elixir
# Use service account with minimal permissions
config :goth,
  json: {:system, "GCS_CREDENTIALS_JSON"}

# Grant only necessary IAM roles:
# - roles/storage.objectViewer (read-only)
# - roles/storage.objectCreator (write-only)
# - roles/storage.objectAdmin (full control)

{:ok, array} = ExZarr.open(
  storage: :gcs,
  bucket: "my-secure-bucket",
  prefix: "arrays/production"
)
```

**Azure Security:**

```elixir
# Use managed identity or SAS tokens
config :azurex,
  account_name: {:system, "AZURE_STORAGE_ACCOUNT"},
  account_key: {:system, "AZURE_STORAGE_KEY"}

# Enable Azure Storage encryption at rest
# Use RBAC for fine-grained access control
```

#### 4. Resource Limits

Prevent resource exhaustion attacks:

```elixir
defmodule ResourceGuard do
  @max_array_size 10 * 1024 * 1024 * 1024  # 10 GB
  @max_chunk_size 100 * 1024 * 1024        # 100 MB
  @max_dimensions 10

  def check_limits(shape, chunks, dtype) do
    element_size = dtype_size(dtype)
    total_elements = Tuple.product(shape)
    chunk_elements = Tuple.product(chunks)

    cond do
      tuple_size(shape) > @max_dimensions ->
        {:error, :too_many_dimensions}
      total_elements * element_size > @max_array_size ->
        {:error, :array_too_large}
      chunk_elements * element_size > @max_chunk_size ->
        {:error, :chunk_too_large}
      true ->
        :ok
    end
  end

  defp dtype_size(:i1), do: 1
  defp dtype_size(:i2), do: 2
  defp dtype_size(:i4), do: 4
  defp dtype_size(:i8), do: 8
  defp dtype_size(:u1), do: 1
  defp dtype_size(:u2), do: 2
  defp dtype_size(:u4), do: 4
  defp dtype_size(:u8), do: 8
  defp dtype_size(:f4), do: 4
  defp dtype_size(:f8), do: 8
end

# Usage
case ResourceGuard.check_limits(shape, chunks, dtype) do
  :ok -> ExZarr.create(shape: shape, chunks: chunks, dtype: dtype)
  {:error, reason} -> {:error, reason}
end
```

#### 5. Secure Configuration

Store sensitive configuration securely:

```elixir
# config/runtime.exs - DO NOT hardcode secrets
import Config

config :ex_zarr,
  max_cache_size: System.get_env("EXZARR_CACHE_SIZE", "1000") |> String.to_integer(),
  enable_telemetry: true

config :ex_aws,
  access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1")

# Use tools like:
# - HashiCorp Vault for secret management
# - AWS Secrets Manager
# - Google Secret Manager
# - Azure Key Vault
```

#### 6. Error Message Security

Avoid leaking sensitive information in error messages:

```elixir
# BAD - Leaks internal paths
{:error, "Failed to read /internal/secret/path/data.zarr"}

# GOOD - Generic message
{:error, :read_failed}

# For debugging, log detailed errors securely
Logger.debug("Failed to read array", path: path, reason: reason)
```

## Known Security Considerations

### 1. Compression Bomb Protection

ExZarr uses compression for efficiency, but be aware of compression bomb attacks (small compressed data that expands enormously):

```elixir
# Monitor decompression ratios
defmodule CompressionMonitor do
  def safe_decompress(compressed_data, expected_size) do
    case decompress(compressed_data) do
      {:ok, decompressed} ->
        ratio = byte_size(decompressed) / byte_size(compressed_data)

        if ratio > 1000 do
          Logger.warn("Suspicious compression ratio: #{ratio}")
          {:error, :compression_bomb_suspected}
        else
          {:ok, decompressed}
        end

      error ->
        error
    end
  end
end
```

### 2. Symlink Following (Filesystem Backend)

The filesystem backend follows symlinks by default. In multi-tenant environments:

```elixir
# Validate that paths don't escape via symlinks
defp check_symlink_safety(path, base_dir) do
  real_path = File.realpath!(path)
  real_base = File.realpath!(base_dir)

  if String.starts_with?(real_path, real_base) do
    :ok
  else
    {:error, :symlink_escape_attempt}
  end
rescue
  _ -> {:error, :invalid_path}
end
```

### 3. Concurrent Access

ExZarr provides locking mechanisms via `ArrayServer`. Ensure proper use:

```elixir
# Enable server for concurrent write protection
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  enable_server: true  # Prevents concurrent write corruption
)

# For distributed systems, use external coordination:
# - Redis locks (Redlock)
# - etcd
# - Consul
# - Database row-level locks
```

### 4. Denial of Service (DoS) Prevention

Implement rate limiting and timeouts:

```elixir
defmodule RateLimiter do
  use GenServer

  def check_rate(user_id) do
    GenServer.call(__MODULE__, {:check, user_id})
  end

  # Implementation using ETS for rate tracking
  # Limit: 100 requests per minute per user
end

# Use timeouts for all operations
{:ok, array} = ExZarr.open(storage: :s3, bucket: "data", timeout: 30_000)

# Read with timeout
case Task.await(
  Task.async(fn -> ExZarr.Array.read(array, {0, 0}, {100, 100}) end),
  30_000
) do
  {:ok, data} -> process(data)
  _ -> {:error, :timeout}
end
```

### 5. Dependency Security

ExZarr depends on several packages. Keep them updated:

```bash
# Check for known vulnerabilities
mix deps.audit

# Update dependencies regularly
mix deps.update --all

# Review dependency tree
mix deps.tree
```

**Key Dependencies:**
- `jason` - JSON parsing (ensure latest for security patches)
- `ex_aws` / `ex_aws_s3` - AWS integration
- `google_api_storage` - GCS integration
- `req` - HTTP client

## Security Features in ExZarr

### Built-in Protections

1. **Type Safety**: Dialyzer type checking prevents many runtime errors
2. **Immutable Metadata**: Zarr metadata is validated on read
3. **Chunk Integrity**: Checksums can be enabled for data integrity
4. **Memory Safety**: Erlang VM provides memory isolation
5. **Process Isolation**: Each array can run in isolated process

### Secure Defaults

- No network access by default (must explicitly configure cloud storage)
- Filesystem operations restricted to specified paths
- No code execution from metadata or data files
- Read-only mode available for safe inspection

## Security Checklist

Use this checklist before deploying ExZarr in production:

- [ ] All user inputs are validated
- [ ] File paths are sanitized and checked for traversal
- [ ] Cloud credentials use environment variables or secret managers
- [ ] Resource limits are enforced (array size, chunk size, dimensions)
- [ ] Concurrent access protection is enabled where needed
- [ ] Error messages don't leak sensitive information
- [ ] Logging is configured to exclude secrets
- [ ] Dependencies are up-to-date and audited
- [ ] Rate limiting is implemented for user-facing APIs
- [ ] Timeouts are set for all I/O operations
- [ ] Monitoring and alerting are configured
- [ ] Backup and recovery procedures are tested

## Vulnerability Disclosure Timeline

When a security vulnerability is reported and confirmed:

1. **Day 0**: Vulnerability reported
2. **Day 1-2**: Initial response and triage
3. **Day 3-7**: Investigation and fix development
4. **Day 8-10**: Testing and verification
5. **Day 11-14**: Release preparation and coordination
6. **Day 15**: Public disclosure and patch release

This timeline may be adjusted based on severity and complexity.

## Past Security Issues

No security vulnerabilities have been reported or discovered in ExZarr as of version 1.0.0.

This section will be updated with any future security issues, including:
- CVE identifier (if applicable)
- Affected versions
- Description of vulnerability
- Fix version
- Credit to reporter

## Static Analysis (Sobelow) Warnings

ExZarr is scanned with Sobelow for security vulnerabilities. The following warnings are expected and safe when used correctly:

### File Traversal Warnings (Low Confidence)

**Affected Files**: `filesystem.ex`, `consolidated_metadata.ex`, `group.ex`, `file_lock.ex`

**Reason**: ExZarr is a data storage library that intentionally reads/writes files at user-specified paths. This is core functionality, not a vulnerability.

**Safe Usage**:
```elixir
# ✓ SAFE: User controls their own filesystem
{:ok, array} = ExZarr.create(
  shape: {1000},
  storage: :filesystem,
  path: "/home/user/data/my_array"
)

# ✗ UNSAFE: Accepting untrusted path from web request
def create_array(conn, %{"path" => user_path}) do
  # DANGER: user_path could be "../../../etc/passwd"
  ExZarr.create(shape: {100}, storage: :filesystem, path: user_path)
end

# ✓ SAFE: Validate and constrain paths from external sources
def create_array(conn, %{"array_name" => name}) do
  if valid_array_name?(name) do
    safe_path = Path.join(["/var/data/arrays", sanitize_name(name)])
    ExZarr.create(shape: {100}, storage: :filesystem, path: safe_path)
  end
end
```

### String.to_atom Warnings (Low Confidence)

**Affected Files**: `storage.ex`, `codecs.ex`, `array.ex`

**Reason**: ExZarr converts codec names and data types from metadata to atoms. The set of valid values is finite and known.

**Safe Usage**:
- Codec names: `:zlib`, `:zstd`, `:lz4`, `:gzip`, `:blosc`, `:bz2` (7 values)
- Data types: `:int8`, `:int16`, `:int32`, `:int64`, `:uint8`, `:uint16`, `:uint32`, `:uint64`, `:float32`, `:float64` (10 values)

These atoms are created during metadata parsing from Zarr files. The library validates that only known codec/dtype names are converted to atoms.

**Note**: Do not parse untrusted metadata files from unknown sources. Only load Zarr arrays from trusted locations.

### Atom Interpolation in Configuration (Low Confidence)

**Affected Files**: Cloud storage backends (`s3.ex`, `gcs.ex`, `azure_blob.ex`, `mongo_gridfs.ex`, `mnesia.ex`)

**Reason**: Configuration keys like `:bucket`, `:account_name`, `:database` are converted to atoms during initialization. These are application configuration values, not user input.

**Safe Usage**:
```elixir
# ✓ SAFE: Configuration from application config
config :ex_zarr,
  storage: [
    s3: [
      bucket: "my-data-bucket",
      region: "us-west-2"
    ]
  ]

# ✗ UNSAFE: Dynamic configuration from user input
def init_storage(user_config) do
  # Don't do this with untrusted input
  ExZarr.Storage.init(storage_type: :s3, bucket: user_config["bucket"])
end
```

### HTTPS Warning (High Confidence)

**Status**: Not Applicable

ExZarr is a library for data storage, not a web application. HTTPS configuration is the responsibility of applications using ExZarr.

### Mitigation Summary

1. **File Paths**: Always validate and sanitize paths from external sources
2. **Metadata**: Only load Zarr arrays from trusted sources
3. **Configuration**: Use application config, not user input, for storage backend configuration
4. **Web Applications**: Implement proper authentication, authorization, and input validation in your application layer

For more details, see `.sobelow-conf` in the repository root.

## Additional Resources

- [Zarr Security Best Practices](https://zarr.dev/security/)
- [Elixir Security Working Group](https://erlef.org/wg/security)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CWE Top 25](https://cwe.mitre.org/top25/)
- [Sobelow Documentation](https://sobelow.io/)

## Contact

For security concerns, contact:
- Email: security@exzarr.dev (or maintainer email in mix.exs)
- GitHub: @thanos (for non-sensitive issues)

For general questions, use GitHub Discussions or Issues (public).

---

**Last Updated**: 2026-01-26
**Version**: 1.0 (for ExZarr 1.0.0+)
