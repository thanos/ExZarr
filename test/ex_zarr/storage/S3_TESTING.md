# S3 Storage Backend Testing Guide

## Overview

The ExZarr S3 storage backend supports both AWS S3 and S3-compatible services like localstack and minio for testing.

## Prerequisites

### 1. Add Dependencies

Ensure these dependencies are in your `mix.exs`:

```elixir
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},
{:sweet_xml, "~> 0.7"}  # Required for XML parsing
```

### 2. Start Localstack (Recommended for Testing)

```bash
# Using Docker
docker run -d -p 4566:4566 localstack/localstack

# Or using Docker Compose
# Add to docker-compose.yml:
# services:
#   localstack:
#     image: localstack/localstack
#     ports:
#       - "4566:4566"
```

### 3. Alternative: Start Minio

```bash
docker run -d -p 9000:9000 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data
```

## Running S3 Integration Tests

### With Localstack

```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566

# Run S3 tests
mix test --include s3 test/ex_zarr/storage/s3_test.exs

# Or in one line:
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_ENDPOINT_URL=http://localhost:4566 \
  mix test --include s3
```

### With Minio

```bash
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_ENDPOINT_URL=http://localhost:9000

mix test --include s3
```

### With Real AWS S3

```bash
# Use your AWS credentials (from ~/.aws/credentials or environment)
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
# Don't set AWS_ENDPOINT_URL for real AWS

mix test --include s3
```

## Test Coverage

The S3 integration tests include:

- **Backend Registration**: Verify S3 backend is properly registered
- **Initialization**: Test bucket and configuration validation
- **Metadata Operations**: Read/write .zarray metadata files
- **Chunk Operations**: Read/write/delete/list chunks
- **Concurrent Operations**: Parallel reads and writes
- **Prefix Isolation**: Multiple arrays in same bucket
- **Error Handling**: Missing chunks, invalid buckets, network errors

## Mock Tests

For fast CI/CD testing without requiring localstack:

```bash
# Mock tests don't require AWS or localstack
mix test test/ex_zarr/storage/s3_mock_test.exs
```

The mock tests use Mox to simulate ExAws behavior, testing all S3 backend functionality without network calls.

## Configuration Details

### Endpoint URL Format

The S3 backend automatically parses `AWS_ENDPOINT_URL` and converts it to ExAws format:

```elixir
# Input: AWS_ENDPOINT_URL=http://localhost:4566
# Becomes:
[
  region: "us-east-1",
  scheme: "http://",
  host: "localhost",
  port: 4566,
  access_key_id: "test",
  secret_access_key: "test"
]
```

### Backend Configuration

When creating arrays, you can optionally specify endpoint_url:

```elixir
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "my-bucket",
  prefix: "arrays/data",
  endpoint_url: "http://localhost:4566",  # Optional for localstack
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64
)
```

Or rely on environment variable:

```elixir
# If AWS_ENDPOINT_URL is set, it will be used automatically
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "my-bucket",
  prefix: "arrays/data",
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64
)
```

## Troubleshooting

### Tests Skip

If tests are skipped:
```
⚠️  S3 tests require AWS credentials and endpoint configuration.
```

**Solution**: Set `AWS_ENDPOINT_URL` environment variable before running tests.

### Connection Refused

```
{:error, %HTTPoison.Error{reason: :econnrefused}}
```

**Solution**: Ensure localstack is running:
```bash
curl http://localhost:4566/_localstack/health
```

### Missing XML Parser

```
** (ExAws.Error) Missing XML parser. Please see docs
```

**Solution**: Add `{:sweet_xml, "~> 0.7"}` to dependencies and run `mix deps.get`.

### Invalid Credentials

```
{:error, {:http_error, 403, "InvalidAccessKeyId"}}
```

**Solution**: Set proper credentials for your environment:
- Localstack: `AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test`
- Minio: Use minio root credentials
- AWS: Use valid AWS credentials

## CI/CD Integration

### GitHub Actions

```yaml
name: Test S3 Backend

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      localstack:
        image: localstack/localstack
        ports:
          - 4566:4566
        env:
          SERVICES: s3

    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '26.0'
          elixir-version: '1.15.0'

      - name: Install dependencies
        run: mix deps.get

      - name: Run S3 tests
        env:
          AWS_ACCESS_KEY_ID: test
          AWS_SECRET_ACCESS_KEY: test
          AWS_ENDPOINT_URL: http://localhost:4566
        run: mix test --include s3
```

## Performance Notes

- **Localstack**: ~0.5 seconds for 31 tests (fast, suitable for CI/CD)
- **Real AWS S3**: Slower due to network latency
- **Mock tests**: ~0.2 seconds for 45 tests (fastest, no network)

## Example Usage

See `examples/s3_storage.exs` for a comprehensive example demonstrating:
- Array creation in S3
- Reading and writing data
- Chunk operations
- Multiple arrays with prefixes
- Error handling
- Performance tips

```bash
./examples/s3_storage.exs
```
