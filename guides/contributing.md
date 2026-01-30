# Contributing Guide

Thank you for your interest in contributing to ExZarr! This guide will help you understand the project structure, development workflow, and how to add features safely.

## Table of Contents

- [Getting Started with Development](#getting-started-with-development)
- [Repository Layout](#repository-layout)
- [Running Tests](#running-tests)
- [Adding a New Codec](#adding-a-new-codec)
- [Adding a New Storage Backend](#adding-a-new-storage-backend)
- [Core Development Guidelines](#core-development-guidelines)
- [Documentation Standards](#documentation-standards)
- [Pull Request Process](#pull-request-process)

## Getting Started with Development

### Prerequisites

Before you begin, ensure you have:

- **Elixir 1.14+** and **Erlang/OTP 25+**
  ```bash
  elixir --version
  # Elixir 1.19.5 (compiled with Erlang/OTP 28)
  ```

- **Zig toolchain** (for codec development, optional)
  - Zigler will automatically download Zig on first compile
  - Or install manually: `brew install zig` (macOS), download from [ziglang.org](https://ziglang.org) (other platforms)

- **Git** for version control
  ```bash
  git --version
  ```

- **Code editor** with Elixir support
  - VS Code + ElixirLS extension (recommended)
  - Vim with elixir-ls
  - Emacs with alchemist
  - IntelliJ IDEA with Elixir plugin

- **Optional: Python 3.8+** for Python interoperability tests
  ```bash
  python3 --version
  pip3 install zarr numpy
  ```

### Initial Setup

Clone and set up the repository:

```bash
# Fork the repository on GitHub first, then clone your fork
git clone https://github.com/YOUR_USERNAME/ExZarr.git
cd ExZarr

# Add upstream remote
git remote add upstream https://github.com/thanos/ExZarr.git

# Install dependencies
mix deps.get

# Compile (includes Zig NIFs - may take a few minutes on first run)
mix compile

# Run tests to verify setup
mix test

# Run tests with coverage
mix coveralls

# Run static analysis
mix credo
mix dialyzer
```

**Note**: First compilation may take 5-10 minutes as Zigler downloads the Zig toolchain and compiles NIFs. Subsequent compilations are much faster.

### Development Workflow

1. **Create a feature branch** from `main`:
   ```bash
   git checkout main
   git pull upstream main
   git checkout -b feature/my-awesome-feature
   ```

2. **Make changes** with tests:
   - Write code following [Core Development Guidelines](#core-development-guidelines)
   - Add tests for new functionality
   - Update documentation

3. **Run quality checks**:
   ```bash
   # Run all tests
   mix test

   # Check code style
   mix format --check-formatted
   mix credo --strict

   # Run type checker
   mix dialyzer

   # Generate coverage report
   mix coveralls.html
   ```

4. **Commit changes**:
   ```bash
   git add .
   git commit -m "Add feature: brief description"
   ```

5. **Push to your fork**:
   ```bash
   git push origin feature/my-awesome-feature
   ```

6. **Submit pull request** on GitHub:
   - Go to your fork on GitHub
   - Click "New Pull Request"
   - Fill out the PR template
   - Wait for review from maintainers

7. **Address review feedback**:
   - Make requested changes
   - Push additional commits to the same branch
   - Changes automatically appear in the PR

**Note**: Maintainers will handle merging approved PRs. You do not need to merge.

## Repository Layout

Understanding the project structure:

```
ExZarr/
├── lib/
│   ├── ex_zarr.ex                    # Main API module - public interface
│   ├── ex_zarr/
│   │   ├── array.ex                  # Array operations (read/write/slice)
│   │   ├── group.ex                  # Group/hierarchy management
│   │   ├── metadata.ex               # Zarr v2 metadata handling
│   │   ├── metadata_v3.ex            # Zarr v3 metadata handling
│   │   ├── codecs/
│   │   │   ├── codec.ex              # Codec behavior definition
│   │   │   ├── registry.ex           # Codec discovery and registration
│   │   │   ├── zig_codecs.ex         # Zig NIF codec implementations
│   │   │   ├── pipeline_v3.ex        # v3 codec pipeline orchestration
│   │   │   └── filters/              # v3 filter implementations
│   │   ├── storage/
│   │   │   ├── backend.ex            # Storage backend behavior
│   │   │   ├── registry.ex           # Backend discovery and registration
│   │   │   └── backend/
│   │   │       ├── filesystem.ex     # Filesystem storage
│   │   │       ├── memory.ex         # In-memory storage
│   │   │       ├── s3.ex             # AWS S3 storage
│   │   │       ├── gcs.ex            # Google Cloud Storage
│   │   │       ├── azure_blob.ex     # Azure Blob Storage
│   │   │       ├── mnesia.ex         # Mnesia database storage
│   │   │       ├── mongo_gridfs.ex   # MongoDB GridFS storage
│   │   │       ├── ets.ex            # ETS table storage
│   │   │       ├── zip.ex            # ZIP archive storage
│   │   │       └── mock.ex           # Mock storage for testing
│   │   ├── chunk.ex                  # Chunk utilities (coordinates, keys)
│   │   ├── chunk_grid.ex             # Chunk grid abstraction (v2/v3)
│   │   ├── indexing.ex               # Index calculations and slicing
│   │   ├── data_type.ex              # Dtype definitions and conversions
│   │   └── application.ex            # Application supervision tree
│   └── mix/tasks/                    # Mix tasks (custom commands)
├── test/
│   ├── ex_zarr_test.exs              # Main API tests
│   ├── ex_zarr_property_test.exs     # Property-based tests (StreamData)
│   ├── ex_zarr_python_integration_test.exs  # Python interop tests
│   ├── ex_zarr_codecs_test.exs       # Codec tests
│   ├── ex_zarr_storage_test.exs      # Storage backend tests
│   ├── ex_zarr/                      # Organized test files
│   │   ├── array_test.exs
│   │   ├── codecs/
│   │   ├── storage/
│   │   └── ...
│   └── support/                      # Test helpers and fixtures
│       ├── test_helper.ex
│       ├── setup_python_tests.sh
│       └── fixtures/
├── native/                           # Zig NIFs source code
│   └── codecs/                       # Compression codec implementations
├── guides/                           # User documentation (markdown)
├── examples/                         # Example scripts (runnable .exs files)
├── benchmarks/                       # Performance benchmarks
├── docs/                             # Additional documentation
├── mix.exs                           # Project configuration
├── README.md                         # Project overview
├── CHANGELOG.md                      # Version history
└── .github/                          # GitHub configuration
    ├── workflows/
    │   └── ci.yml                    # CI/CD pipeline
    └── ISSUE_TEMPLATE/               # Issue templates
```

### Key Architectural Patterns

Understanding these patterns helps you contribute effectively:

1. **Behaviors for Extensibility**
   - `ExZarr.Codecs.Codec` - Implement to add compression codecs
   - `ExZarr.Storage.Backend` - Implement to add storage backends
   - Behaviors define contracts; implementations provide functionality

2. **GenServer Registries**
   - `ExZarr.Codecs.Registry` - Tracks available codecs
   - `ExZarr.Storage.Registry` - Tracks available backends
   - Enables dynamic discovery and lookup

3. **Metadata Structs**
   - `ExZarr.Metadata` (v2) and `ExZarr.MetadataV3` (v3)
   - Abstracts differences between Zarr versions
   - Single API works with both versions

4. **Chunk Coordinates as Tuples**
   - Always tuples: `{0, 1, 2}` not lists `[0, 1, 2]`
   - Consistent throughout codebase
   - Enables pattern matching

5. **Result Tuples**
   - Success: `{:ok, result}`
   - Failure: `{:error, reason}`
   - Never raise exceptions in library code

## Running Tests

### Full Test Suite

Run all tests:

```bash
mix test
```

Expected output:
```
Compiling 42 files (.ex)
Generated ex_zarr app
...................................

Finished in 12.5 seconds (async: 10.0s, sync: 2.5s)
487 tests, 0 failures

Randomized with seed 123456
```

### Specific Test Files

Run a single test file:

```bash
mix test test/ex_zarr_test.exs
```

Run tests in a directory:

```bash
mix test test/ex_zarr/codecs/
```

### Specific Test by Line

Run a single test:

```bash
mix test test/ex_zarr_test.exs:42
```

Where `42` is the line number of the test.

### Property-Based Tests

Run property-based tests (uses StreamData for randomized testing):

```bash
mix test test/ex_zarr_property_test.exs
```

These tests generate random inputs to verify properties hold for all cases.

### Python Integration Tests

Test Python zarr-python interoperability:

```bash
# One-time setup (installs Python dependencies)
./test/support/setup_python_tests.sh

# Run Python interop tests
mix test test/ex_zarr_python_integration_test.exs

# Or run Python tests only
mix test --only python_integration
```

**Requirements**: Python 3.8+, zarr-python, numpy.

### Coverage Reports

Generate HTML coverage report:

```bash
mix coveralls.html
```

Opens `cover/excoveralls.html` in your browser showing line-by-line coverage.

Target: >90% coverage for new code.

### Quality Checks

**Code style** (format checking):

```bash
# Check formatting
mix format --check-formatted

# Auto-format all files
mix format
```

**Static analysis** (code quality):

```bash
# Run credo (fast)
mix credo

# Run credo with strict checks
mix credo --strict
```

**Type checking** (Dialyzer):

```bash
# First run (slow, builds PLT)
mix dialyzer

# Subsequent runs (fast)
mix dialyzer
```

**All checks** (pre-commit verification):

```bash
# Run everything
mix test && mix format --check-formatted && mix credo --strict && mix dialyzer
```

## Adding a New Codec

Codecs transform chunk data (compression, filtering, checksums). Follow these steps to add a new codec.

### 1. Implement the Codec Behavior

Create a new file in `lib/ex_zarr/codecs/`:

```elixir
defmodule ExZarr.Codecs.MyCodec do
  @moduledoc """
  My Codec compresses data using the XYZ algorithm.

  This codec provides [describe benefits: fast compression, high ratio, etc.].
  Requires [list dependencies: system libraries, NIFs, etc.].

  ## Examples

      {:ok, encoded} = ExZarr.Codecs.MyCodec.encode(data, level: 5)
      {:ok, decoded} = ExZarr.Codecs.MyCodec.decode(encoded, level: 5)

  """

  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: :my_codec

  @impl true
  def codec_info do
    %{
      name: "My Codec",
      version: "1.0.0",
      type: :compression,  # or :transformation, :checksum
      description: "Fast compression using XYZ algorithm"
    }
  end

  @impl true
  def available? do
    # Check if codec dependencies are available
    # Return true if codec can be used, false otherwise
    case Code.ensure_loaded?(:my_codec_nif) do
      true -> true
      false -> false
    end
  end

  @impl true
  def encode(data, opts) when is_binary(data) do
    # Implement compression/transformation
    # opts is a keyword list with configuration options
    level = Keyword.get(opts, :level, 5)

    try do
      compressed = perform_compression(data, level)
      {:ok, compressed}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl true
  def decode(data, opts) when is_binary(data) do
    # Implement decompression/reverse transformation
    # opts should match those used in encode
    level = Keyword.get(opts, :level, 5)

    try do
      decompressed = perform_decompression(data, level)
      {:ok, decompressed}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl true
  def validate_config(opts) do
    # Validate configuration options
    # Return :ok if valid, {:error, reason} if invalid
    case Keyword.get(opts, :level) do
      nil -> :ok
      level when is_integer(level) and level >= 1 and level <= 9 -> :ok
      _invalid -> {:error, "level must be an integer between 1 and 9"}
    end
  end

  # Private helper functions
  defp perform_compression(data, level) do
    # Implementation here
    data
  end

  defp perform_decompression(data, level) do
    # Implementation here
    data
  end
end
```

### 2. Add Comprehensive Tests

Create `test/ex_zarr/codecs/my_codec_test.exs`:

```elixir
defmodule ExZarr.Codecs.MyCodecTest do
  use ExUnit.Case, async: true

  alias ExZarr.Codecs.MyCodec

  describe "encode/decode round-trip" do
    test "handles random data" do
      original = :crypto.strong_rand_bytes(1024)
      {:ok, encoded} = MyCodec.encode(original, [])
      {:ok, decoded} = MyCodec.decode(encoded, [])
      assert original == decoded
    end

    test "handles empty input" do
      assert {:ok, ""} = MyCodec.encode("", [])
      assert {:ok, ""} = MyCodec.decode("", [])
    end

    test "handles large data" do
      original = :crypto.strong_rand_bytes(10_000_000)  # 10 MB
      {:ok, encoded} = MyCodec.encode(original, [])
      {:ok, decoded} = MyCodec.decode(encoded, [])
      assert original == decoded
    end
  end

  describe "compression" do
    test "reduces size for compressible data" do
      # Repetitive data should compress well
      original = String.duplicate("a", 1024)
      {:ok, encoded} = MyCodec.encode(original, [])
      assert byte_size(encoded) < byte_size(original)
    end

    test "compression level affects size" do
      data = String.duplicate("test", 256)
      {:ok, low_level} = MyCodec.encode(data, level: 1)
      {:ok, high_level} = MyCodec.encode(data, level: 9)
      # Higher level should compress better (smaller size)
      assert byte_size(high_level) <= byte_size(low_level)
    end
  end

  describe "error handling" do
    test "handles invalid compressed data" do
      invalid_data = <<0, 1, 2, 3, 4>>
      assert {:error, _reason} = MyCodec.decode(invalid_data, [])
    end

    test "validates configuration" do
      assert :ok = MyCodec.validate_config(level: 5)
      assert {:error, _} = MyCodec.validate_config(level: 100)
      assert {:error, _} = MyCodec.validate_config(level: "invalid")
    end
  end

  describe "codec_info/0" do
    test "returns codec metadata" do
      info = MyCodec.codec_info()
      assert info.name == "My Codec"
      assert info.type == :compression
    end
  end
end
```

### 3. Register in Application

If this is a built-in codec, register it on startup:

```elixir
# lib/ex_zarr/application.ex
defmodule ExZarr.Application do
  use Application

  def start(_type, _args) do
    # Register codecs
    :ok = ExZarr.Codecs.register_codec(ExZarr.Codecs.Zlib)
    :ok = ExZarr.Codecs.register_codec(ExZarr.Codecs.MyCodec)  # Add this line
    # ... rest of start function
  end
end
```

For external codecs (in separate packages), users register them in their application.

### 4. Document the Codec

Update `guides/compression_codecs.md`:

```markdown
### My Codec

**Type**: Compression
**Availability**: Requires `libmycodec` system library
**Speed**: Fast (200-500 MB/s compression, 500-1000 MB/s decompression)
**Ratio**: Moderate (2-3× typical)

**Best for**: [Describe ideal use cases]

**Configuration**:
\`\`\`elixir
compressor: %{id: "my_codec", level: 5}
\`\`\`

**Levels**: 1-9 (1=fastest, 9=best compression)
```

### 5. Update CHANGELOG

Add entry to `CHANGELOG.md`:

```markdown
## [Unreleased]

### Added

- Added MyCodec compression support (#123)
```

## Adding a New Storage Backend

Storage backends handle reading/writing chunks to different storage systems (filesystem, S3, databases, etc.).

### 1. Implement the Backend Behavior

Create `lib/ex_zarr/storage/backend/my_backend.ex`:

```elixir
defmodule ExZarr.Storage.Backend.MyBackend do
  @moduledoc """
  Storage backend for [service/system name].

  This backend provides access to [describe storage system].

  ## Configuration

      {:ok, array} = ExZarr.create(
        storage: :my_backend,
        connection: "connection_string",
        container: "my_container",
        ...
      )

  ## Required Options

  - `:connection` - Connection string or credentials
  - `:container` - Container/bucket/namespace identifier

  ## Optional Options

  - `:timeout` - Operation timeout in milliseconds (default: 30000)
  - `:retry_count` - Number of retries on failure (default: 3)

  """

  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :my_backend

  @impl true
  def init(opts) do
    # Validate required options
    connection = Keyword.fetch!(opts, :connection)
    container = Keyword.fetch!(opts, :container)
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Initialize connection/state
    state = %{
      connection: connection,
      container: container,
      timeout: timeout
    }

    # Verify connection works
    case test_connection(state) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, "Connection failed: #{reason}"}
    end
  end

  @impl true
  def open(opts) do
    # Open existing array (same as init for most backends)
    init(opts)
  end

  @impl true
  def read_chunk(state, chunk_coords) do
    # Read chunk binary by coordinates
    # chunk_coords is a tuple: {0, 1, 2}
    chunk_key = coords_to_key(chunk_coords)

    case fetch_from_storage(state, chunk_key) do
      {:ok, binary} -> {:ok, binary}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write_chunk(state, chunk_coords, data) when is_binary(data) do
    # Write chunk binary
    chunk_key = coords_to_key(chunk_coords)

    case store_to_storage(state, chunk_key, data) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def read_metadata(state) do
    # Read array metadata (.zarray or zarr.json)
    case fetch_from_storage(state, ".zarray") do
      {:ok, json} ->
        metadata = Jason.decode!(json)
        {:ok, metadata}

      {:error, :not_found} ->
        # Try v3 metadata
        case fetch_from_storage(state, "zarr.json") do
          {:ok, json} ->
            metadata = Jason.decode!(json)
            {:ok, metadata}

          {:error, :not_found} ->
            {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def write_metadata(state, metadata, version) when version in [2, 3] do
    # Write metadata (version is 2 or 3)
    filename = if version == 2, do: ".zarray", else: "zarr.json"
    json = Jason.encode!(metadata)

    case store_to_storage(state, filename, json) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_chunks(state) do
    # Return list of chunk coordinates that exist
    case list_keys(state) do
      {:ok, keys} ->
        chunk_coords = keys
                      |> Enum.filter(&is_chunk_key?/1)
                      |> Enum.map(&key_to_coords/1)
        {:ok, chunk_coords}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_chunk(state, chunk_coords) do
    chunk_key = coords_to_key(chunk_coords)

    case delete_from_storage(state, chunk_key) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(state) do
    # Check if array exists by looking for metadata
    case read_metadata(state) do
      {:ok, _metadata} -> {:ok, true}
      {:error, :not_found} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp coords_to_key(coords) when is_tuple(coords) do
    coords
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp key_to_coords(key) do
    key
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end

  defp is_chunk_key?(key) do
    # Chunk keys are numeric coordinates: "0.1.2"
    String.match?(key, ~r/^\d+(\.\d+)*$/)
  end

  defp test_connection(_state) do
    # Verify connection works
    :ok
  end

  defp fetch_from_storage(_state, _key) do
    # Implement fetching from your storage system
    {:ok, <<>>}
  end

  defp store_to_storage(_state, _key, _data) do
    # Implement storing to your storage system
    :ok
  end

  defp list_keys(_state) do
    # Implement listing keys from your storage system
    {:ok, []}
  end

  defp delete_from_storage(_state, _key) do
    # Implement deletion from your storage system
    :ok
  end
end
```

### 2. Add Comprehensive Tests

Create `test/ex_zarr/storage/backend/my_backend_test.exs`:

```elixir
defmodule ExZarr.Storage.Backend.MyBackendTest do
  use ExUnit.Case, async: false

  alias ExZarr.Storage.Backend.MyBackend

  setup do
    # Setup test environment
    opts = [
      connection: "test_connection",
      container: "test_container"
    ]

    {:ok, state} = MyBackend.init(opts)
    {:ok, state: state}
  end

  describe "init/1" do
    test "initializes with valid options" do
      opts = [connection: "test", container: "test"]
      assert {:ok, state} = MyBackend.init(opts)
      assert state.connection == "test"
      assert state.container == "test"
    end

    test "returns error with missing options" do
      assert_raise KeyError, fn ->
        MyBackend.init([])
      end
    end
  end

  describe "read_chunk/2 and write_chunk/3" do
    test "writes and reads chunk successfully", %{state: state} do
      chunk_coords = {0, 1, 2}
      data = :crypto.strong_rand_bytes(1024)

      assert :ok = MyBackend.write_chunk(state, chunk_coords, data)
      assert {:ok, ^data} = MyBackend.read_chunk(state, chunk_coords)
    end

    test "returns error for non-existent chunk", %{state: state} do
      assert {:error, :not_found} = MyBackend.read_chunk(state, {999, 999})
    end
  end

  describe "metadata operations" do
    test "writes and reads metadata", %{state: state} do
      metadata = %{
        "shape" => [100, 100],
        "chunks" => [10, 10],
        "dtype" => "<f8"
      }

      assert :ok = MyBackend.write_metadata(state, metadata, 2)
      assert {:ok, ^metadata} = MyBackend.read_metadata(state)
    end
  end

  describe "list_chunks/1" do
    test "lists all chunk coordinates", %{state: state} do
      # Write several chunks
      coords_list = [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

      for coords <- coords_list do
        data = :crypto.strong_rand_bytes(100)
        MyBackend.write_chunk(state, coords, data)
      end

      assert {:ok, listed_coords} = MyBackend.list_chunks(state)
      assert Enum.sort(listed_coords) == Enum.sort(coords_list)
    end
  end

  describe "delete_chunk/2" do
    test "deletes chunk", %{state: state} do
      coords = {0, 0}
      data = :crypto.strong_rand_bytes(100)

      MyBackend.write_chunk(state, coords, data)
      assert {:ok, _} = MyBackend.read_chunk(state, coords)

      assert :ok = MyBackend.delete_chunk(state, coords)
      assert {:error, :not_found} = MyBackend.read_chunk(state, coords)
    end
  end

  describe "exists?/1" do
    test "returns false for non-existent array", %{state: state} do
      assert {:ok, false} = MyBackend.exists?(state)
    end

    test "returns true after metadata written", %{state: state} do
      metadata = %{"shape" => [10, 10]}
      MyBackend.write_metadata(state, metadata, 2)
      assert {:ok, true} = MyBackend.exists?(state)
    end
  end
end
```

### 3. Document Configuration

Update `guides/storage_providers.md`:

```markdown
## My Backend

**Backend ID**: `:my_backend`
**Use cases**: [Describe when to use this backend]
**Availability**: [Describe requirements/dependencies]

### Configuration

\`\`\`elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :my_backend,
  connection: "connection_string",
  container: "my_container",
  timeout: 30_000
)
\`\`\`

### Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `:connection` | Yes | - | Connection string |
| `:container` | Yes | - | Container identifier |
| `:timeout` | No | 30000 | Timeout in ms |

### Performance Characteristics

- **Latency**: [Typical latency]
- **Throughput**: [Typical throughput]
- **Best for**: [Use cases]
```

### 4. Update CHANGELOG

```markdown
## [Unreleased]

### Added

- Added MyBackend storage backend (#456)
```

## Core Development Guidelines

Follow these guidelines for all contributions.

### Code Style

- **Follow Elixir conventions**:
  - Use snake_case for variables and function names
  - Use PascalCase for module names
  - Use descriptive names

- **Format code** before committing:
  ```bash
  mix format
  ```

- **Pass static analysis**:
  ```bash
  mix credo --strict
  ```

- **Add typespecs** to public functions:
  ```elixir
  @spec create(keyword()) :: {:ok, ExZarr.Array.t()} | {:error, term()}
  def create(opts) do
    # Implementation
  end
  ```

### Error Handling

- **Return result tuples**:
  ```elixir
  # Good
  def read_chunk(coords) do
    {:ok, data} | {:error, :not_found}
  end

  # Bad (don't raise in library code)
  def read_chunk(coords) do
    raise "Chunk not found"
  end
  ```

- **Provide descriptive error atoms**:
  ```elixir
  {:error, :invalid_shape}
  {:error, :codec_not_available}
  {:error, :storage_error}
  ```

- **Handle all error cases**:
  ```elixir
  case some_operation() do
    {:ok, result} -> process(result)
    {:error, :specific_error} -> handle_specific_error()
    {:error, reason} -> handle_generic_error(reason)
  end
  ```

### Testing

- **Write tests for new features**:
  - Unit tests for individual functions
  - Integration tests for feature workflows
  - Property-based tests for data transformations

- **Test error cases**:
  ```elixir
  test "handles invalid input" do
    assert {:error, _reason} = MyModule.my_function(invalid_input)
  end
  ```

- **Test edge cases**:
  - Empty inputs
  - Very large inputs
  - Boundary conditions
  - Concurrent access

- **Maintain coverage**:
  - Target >90% for new code
  - Check with `mix coveralls.html`

### Performance

- **Profile before optimizing**:
  ```elixir
  {time, result} = :timer.tc(fn -> expensive_operation() end)
  IO.puts("Time: #{time / 1000} ms")
  ```

- **Document performance characteristics**:
  ```elixir
  @doc """
  Reads multiple chunks in parallel.

  Performance: O(n) with respect to chunk count, benefits from parallelism.
  Memory: Peak usage is max_concurrency × chunk_size.
  """
  ```

- **Consider memory usage**:
  - Large binaries live in shared heap (reference counted)
  - Avoid unnecessary copies
  - Use streaming for large data

### Compatibility

- **Ensure Zarr specification compliance**:
  - Follow Zarr v2 spec for v2 features
  - Follow Zarr v3 spec for v3 features
  - Test with zarr-python when possible

- **Test Python interoperability** for core features:
  ```bash
  mix test test/ex_zarr_python_integration_test.exs
  ```

- **Document compatibility boundaries**:
  ```elixir
  @doc """
  Creates a Zarr v2 array compatible with Python zarr-python.

  Note: Custom codecs may not be available in Python.
  """
  ```

## Documentation Standards

Good documentation helps users and future contributors.

### Module Documentation

Every module should have `@moduledoc`:

```elixir
defmodule ExZarr.MyModule do
  @moduledoc """
  Brief description of module purpose (one sentence).

  Longer description explaining what this module does,
  when to use it, and how it fits into ExZarr.

  ## Examples

      iex> ExZarr.MyModule.do_something()
      {:ok, result}

  ## Related Modules

  - `ExZarr.RelatedModule` - Related functionality

  """
end
```

### Function Documentation

Public functions need `@doc` and `@spec`:

```elixir
@doc """
Brief description of what the function does (imperative mood).

Longer description explaining behavior, algorithms, or important notes.

## Parameters

- `array` - Array struct to operate on
- `opts` - Keyword list of options:
  - `:compression` - Compression level (default: 5)
  - `:parallel` - Enable parallel processing (default: false)

## Returns

- `{:ok, result}` - Success with result
- `{:error, reason}` - Failure with reason atom

## Examples

    iex> ExZarr.MyModule.process(array, compression: 3)
    {:ok, processed_array}

    iex> ExZarr.MyModule.process(invalid_array)
    {:error, :invalid_shape}

## Performance

O(n) where n is number of chunks. Parallel processing can improve
performance for I/O-bound operations.

"""
@spec process(ExZarr.Array.t(), keyword()) :: {:ok, term()} | {:error, atom()}
def process(array, opts \\ []) do
  # Implementation
end
```

### Guide Documentation

When writing guides:

- **Use markdown** (.md files)
- **Include runnable examples**:
  ```elixir
  # This should actually work
  {:ok, array} = ExZarr.create(shape: {10, 10}, ...)
  ```
- **Organize with clear sections**
- **Link to related guides**
- **Provide context** (when to use, why it matters)

## Pull Request Process

### Before Submitting

Complete this checklist:

- [ ] All tests pass: `mix test`
- [ ] Code formatted: `mix format`
- [ ] Static analysis passes: `mix credo --strict`
- [ ] Type checking passes: `mix dialyzer`
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG.md updated with changes
- [ ] Examples added/updated (if new feature)

### PR Description Template

Use this template when creating your PR:

```markdown
## Description

[Clear description of what this PR does and why]

## Related Issues

Closes #123
Fixes #456

## Type of Change

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change
- [ ] Documentation update

## Changes Made

- [List main changes]
- [Be specific about what changed]
- [Include file/module names]

## Testing

- [ ] All existing tests pass
- [ ] Added tests for new functionality
- [ ] Tested manually:
  \`\`\`elixir
  # Example of manual testing performed
  {:ok, array} = ExZarr.create(...)
  \`\`\`

## Breaking Changes

[If breaking change, describe impact and migration path]

None / N/A
```

### Review Process

1. **Maintainer reviews** code and provides feedback
   - May request changes
   - May suggest improvements
   - May ask questions for clarification

2. **Address feedback** with additional commits:
   ```bash
   # Make requested changes
   git add .
   git commit -m "Address review feedback"
   git push origin feature-branch
   ```

3. **Once approved**, maintainer will merge:
   - You do NOT need to merge
   - Maintainer handles merge and any conflicts

4. **After merge**:
   - Maintainer handles release process
   - Your contribution will be credited in release notes
   - You'll be added to contributors list

### What You Do vs What Maintainer Does

**You (contributor)**:
- Fork repository
- Create feature branch
- Write code and tests
- Push to your fork
- Create pull request
- Respond to review feedback
- Push additional changes if requested

**Maintainer**:
- Review pull request
- Provide feedback
- Approve when ready
- Merge to main branch
- Handle releases
- Update changelog for release
- Credit contributors

## Questions or Suggestions?

- **Open an issue** for discussion before major changes
- **Ask questions** in existing issues or PRs
- **Check existing issues** to avoid duplicates

Thank you for contributing to ExZarr! Every contribution helps make the library better for the entire community.

## Additional Resources

- [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- [Writing Documentation](https://hexdocs.pm/elixir/writing-documentation.html)
- [Zarr Specification](https://zarr-specs.readthedocs.io/)
- [Zigler Documentation](https://hexdocs.pm/zigler/)

For questions, open an issue on GitHub: [https://github.com/thanos/ExZarr/issues](https://github.com/thanos/ExZarr/issues)
