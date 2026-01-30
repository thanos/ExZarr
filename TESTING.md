# Testing Strategy

ExZarr uses a comprehensive testing strategy that separates self-contained tests from integration tests requiring external services.

## Test Categories

### Self-Contained Tests (Run in CI)

These tests run without external dependencies and are executed in CI:

**Storage Backends**:
- **Memory** - In-memory ETS-based storage
- **ETS** - Erlang Term Storage (in-memory)
- **Mock** - Testing backend with error simulation
- **Filesystem** - Local file system storage
- **Zip** - Single-file archive storage

**Other Tests**:
- Core array operations
- Compression codecs (zlib, zstd, lz4, snappy, blosc, bzip2, crc32c)
- Filter pipelines (Delta, Quantize, Shuffle, etc.)
- Metadata serialization
- Property-based tests
- Custom codec/storage plugins

**Total**: 324 tests

### Integration Tests (Excluded from CI)

These tests require external services and are excluded by default:

**Cloud Storage**:
- **S3** - AWS S3 (10 tests) - requires AWS credentials
- **GCS** - Google Cloud Storage (13 tests) - requires GCS credentials
- **Azure** - Azure Blob Storage (12 tests) - requires Azure credentials
- **MongoDB** - MongoDB GridFS (17 tests) - requires MongoDB running
- **Mnesia** - BEAM distributed database (12 tests) - requires Mnesia setup

**Python Interoperability**:
- **Python Integration** - (14 tests) - requires Python 3 + zarr + numpy

**Total**: 78 tests (excluded)

## Running Tests

### Standard Test Run (CI Mode)

```bash
# Run all self-contained tests
mix test

# Results:
# 324 tests passing
# 78 tests excluded
# 0 failures
```

### Integration Tests (Local)

#### Prerequisites

1. **Install optional dependencies** in `mix.exs`:

```elixir
defp deps do
  [
    # ... standard deps ...

    # For AWS S3 tests
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},
    {:hackney, "~> 1.20"},

    # For Google Cloud Storage tests
    {:goth, "~> 1.4"},
    {:req, "~> 0.5"},

    # For Azure Blob Storage tests
    {:azurex, "~> 0.3"},
    {:httpoison, "~> 2.2"},

    # For MongoDB GridFS tests
    {:mongodb_driver, "~> 1.4"}
  ]
end
```

2. **Set up credentials**:

```bash
# AWS S3
export AWS_ACCESS_KEY_ID="your_key"
export AWS_SECRET_ACCESS_KEY="your_secret"
export AWS_REGION="us-west-2"
export TEST_S3_BUCKET="your-test-bucket"

# Google Cloud Storage
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
export TEST_GCS_BUCKET="your-test-bucket"
export TEST_GCS_PROJECT="your-project-id"

# Azure Blob Storage
export AZURE_STORAGE_CONNECTION_STRING="your_connection_string"
export TEST_AZURE_CONTAINER="your-test-container"

# MongoDB (start local instance)
docker run -d -p 27017:27017 mongo:5.0

# Python Integration Tests
pip3 install 'zarr>=2.10.0,<3.0.0' numpy
```

3. **Mnesia Setup** (no external service needed, but requires initialization)

#### Run Specific Integration Tests

```bash
# Run S3 tests
mix test --include s3

# Run GCS tests
mix test --include gcs

# Run Azure tests
mix test --include azure

# Run MongoDB tests
mix test --include mongo

# Run Mnesia tests
mix test --include mnesia

# Run Python integration tests
mix test --include python

# Run all integration tests
mix test --include s3 --include gcs --include azure --include mongo --include mnesia --include python
```

## CI Configuration

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs only self-contained tests:

```yaml
- name: Run tests
  # CI runs only self-contained storage backends:
  # ✓ Memory, ETS, Mock, Filesystem, Zip
  #
  # Excluded (require external services):
  # ✗ S3, GCS, Azure, MongoDB, Mnesia, Python Integration
  run: mix test --trace
```

Integration tests are excluded via the configuration in `test/test_helper.exs`, which excludes the tags `:s3`, `:gcs`, `:azure`, `:mongo`, `:mnesia`, and `:python` by default.

### Why This Strategy?

1. **Fast Feedback**: CI completes in ~7 seconds without network calls
2. **No Credentials**: No need to manage cloud credentials in CI
3. **Reliable**: No flaky tests due to network issues or service availability
4. **Cost Effective**: No charges for cloud storage API calls in CI
5. **Local Control**: Developers can test integrations with proper setup

## Test Coverage

Despite excluding 64 integration tests, coverage remains high because:

1. **Mock Backend**: Simulates all storage backend operations
2. **Filesystem Backend**: Tests actual file I/O patterns
3. **Comprehensive Unit Tests**: All codecs, filters, and operations tested
4. **Property Tests**: Validates correctness across many input variations

## Adding New Tests

### For Self-Contained Features

Just add tests normally - they'll run in CI:

```elixir
defmodule ExZarr.NewFeatureTest do
  use ExUnit.Case

  test "new feature works" do
    # Test implementation
  end
end
```

### For External Service Integration

Tag the module to exclude from CI:

```elixir
defmodule ExZarr.NewCloudBackendTest do
  use ExUnit.Case

  @moduletag :new_cloud_backend

  # These tests require external service
  # To run: mix test --include new_cloud_backend

  test "connects to service" do
    # Integration test
  end
end
```

Update `test/test_helper.exs` to exclude the new tag:

```elixir
ExUnit.configure(exclude: [:s3, :gcs, :azure, :mongo, :mnesia, :python, :new_cloud_backend])
```

## Troubleshooting

### Tests Failing in CI

1. Check if test is self-contained (no external dependencies)
2. Verify test doesn't require credentials or services
3. Consider adding appropriate `@moduletag` to exclude from CI

### Integration Tests Failing Locally

1. Verify external service is running (MongoDB, etc.)
2. Check credentials are properly set via environment variables
3. Ensure optional dependencies are installed
4. Test network connectivity to cloud services

## Test Metrics

**Current Status**:
- Total tests: 402
- CI tests: 324 (81%)
- Integration tests: 78 (19%)
- Pass rate: 100% (324/324 in CI)

**Coverage by Category**:
- Storage backends: 5 self-contained, 5 integration
- Codecs: 8 codecs fully tested
- Filters: 6 filters fully tested
- Core operations: Comprehensive coverage
- Property tests: 21 properties validating correctness
- Python interoperability: 14 integration tests (requires Python setup)

## Future Improvements

1. **Mock Cloud Services**: Implement mocked versions of cloud storage APIs for CI
2. **Integration Test Suite**: Separate workflow for nightly integration tests
3. **Performance Benchmarks**: Add benchmark suite for codec and storage performance
4. **Compatibility Tests**: Add tests for Python zarr-python interoperability
