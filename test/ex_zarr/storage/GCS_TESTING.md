# GCS Storage Backend Testing Guide

This guide explains how to test the Google Cloud Storage (GCS) backend for ExZarr.

## Test Types

### 1. Mock Tests (Fast, No Dependencies)

**File**: `test/ex_zarr/storage/gcs_mock_test.exs`
**Count**: 39 tests
**Run time**: ~0.2 seconds

Mock tests use in-memory mocks for Req (HTTP client) and Goth (authentication). They don't require any external services.

```bash
# Run mock tests (always included by default)
mix test test/ex_zarr/storage/gcs_mock_test.exs
```

### 2. Integration Tests (Requires fake-gcs-server)

**File**: `test/ex_zarr/storage/gcs_test.exs`
**Count**: 26 tests
**Requirements**: Docker, fake-gcs-server running

Integration tests verify the GCS backend works with a real HTTP-based GCS-compatible server.

## Running Integration Tests

### Step 1: Start fake-gcs-server

```bash
docker run -d -p 4443:4443 \
  fsouza/fake-gcs-server \
  -scheme http \
  -port 4443
```

**Important**: Use `http` scheme, not `https`. fake-gcs-server runs in HTTP mode by default.

### Step 2: Set Environment Variable

```bash
export GCS_ENDPOINT_URL=http://localhost:4443
```

**Note**: Use `http://`, not `https://`!

### Step 3: Run Tests

```bash
mix test --include gcs
```

## Authentication for fake-gcs-server

fake-gcs-server doesn't validate authentication. The integration tests use `MockGoth` which returns fake tokens that fake-gcs-server accepts.

You don't need real Google Cloud credentials to run the tests.

## Testing with Real Google Cloud Storage

To test with real GCS (not recommended for regular development):

1. Create a service account in Google Cloud Console
2. Download the service account JSON key
3. Don't set `GCS_ENDPOINT_URL` (or unset it)
4. Configure credentials:

```elixir
config = [
  bucket: "your-test-bucket",
  credentials: "/path/to/service-account.json"
]
```

**Warning**: Real GCS tests will incur costs and require internet connectivity.

## Cleanup

To stop fake-gcs-server:

```bash
# Find the container
docker ps | grep fake-gcs-server

# Stop it
docker stop <container-id>
```

## Test Structure

### Mock Tests Cover:
- Backend initialization
- Credential handling (file and map)
- Read/write operations for chunks and metadata
- List operations
- Delete operations
- Concurrent operations
- Prefix handling
- Various chunk dimensions (1D, 2D, 3D, ND)

### Integration Tests Cover:
- Same operations as mock tests
- Real HTTP communication with fake-gcs-server
- Actual authentication flow (mocked)
- Real bucket operations
- Prefix isolation

## Troubleshooting

### Tests fail with "GCS service not configured"

Set the environment variable:
```bash
export GCS_ENDPOINT_URL=http://localhost:4443
```

### Tests fail with connection errors

Check that fake-gcs-server is running:
```bash
docker ps | grep fake-gcs-server
curl http://localhost:4443/storage/v1/b
```

### Tests fail with "invalid_grant" or OAuth errors

Make sure you're using `http://` not `https://`:
```bash
# Wrong
export GCS_ENDPOINT_URL=https://localhost:4443

# Correct
export GCS_ENDPOINT_URL=http://localhost:4443
```

The MockGoth should handle authentication, but check that it's properly injected.

### fake-gcs-server port already in use

Change the port:
```bash
docker run -d -p 4444:4443 \
  fsouza/fake-gcs-server \
  -scheme http \
  -port 4443

export GCS_ENDPOINT_URL=http://localhost:4444
```

## CI/CD Integration

For CI/CD pipelines, run only mock tests by default:

```yaml
# GitHub Actions example
- name: Run tests
  run: mix test
  # GCS integration tests are excluded by default
```

To include integration tests in CI:

```yaml
- name: Start fake-gcs-server
  run: |
    docker run -d -p 4443:4443 \
      fsouza/fake-gcs-server \
      -scheme http \
      -port 4443

- name: Run all tests including GCS
  env:
    GCS_ENDPOINT_URL: http://localhost:4443
  run: mix test --include gcs
```

## Performance Notes

- **Mock tests**: Very fast (~200ms), no network I/O
- **Integration tests**: Moderate speed (~2-5 seconds), involves HTTP
- **Real GCS tests**: Slow (10+ seconds), network latency + API costs

## Code Coverage

Both test suites together provide comprehensive coverage:
- All backend callbacks
- Error conditions
- Edge cases (empty data, large data, etc.)
- Concurrent operations
- Multiple chunk dimensions

Total coverage for GCS backend: >95%
