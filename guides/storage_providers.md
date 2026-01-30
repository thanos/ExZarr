# Storage Providers

ExZarr provides a pluggable storage abstraction that works with local filesystem, cloud object storage, and databases. This guide shows how to configure each backend, handle credentials securely, and optimize for cloud performance.

## Built-in Storage Backends Overview

ExZarr includes 10 storage backends out of the box:

| Backend | Type | Persistence | Scalability | Latency | Primary Use Case |
|---------|------|-------------|-------------|---------|------------------|
| **Memory** | In-memory | No | Process-local | Lowest | Testing, temporary arrays |
| **ETS** | In-memory | No | Node-local | Lowest | Multi-process shared arrays |
| **Filesystem** | Disk | Yes | Single machine | Low | Local development, standard Zarr format |
| **Zip** | Archive | Yes | Single file | Low | Distribution, archival, reducing file count |
| **Mnesia** | Database | Yes | Distributed | Low-Medium | BEAM clusters, ACID transactions |
| **MongoDB GridFS** | Database | Yes | Distributed | Medium | MongoDB infrastructure, large chunks |
| **S3** | Cloud | Yes | Unlimited | Medium | AWS deployments, large datasets |
| **GCS** | Cloud | Yes | Unlimited | Medium | Google Cloud Platform |
| **Azure Blob** | Cloud | Yes | Unlimited | Medium | Microsoft Azure |
| **Mock** | Testing | No | N/A | N/A | Development, error simulation |

### Selection Criteria

**Choose based on your requirements:**

**Need persistence?**
- No → Memory, ETS
- Yes → Filesystem, Cloud, Database

**Need scalability beyond single machine?**
- No → Filesystem, Zip
- Yes → S3, GCS, Azure, MongoDB, Mnesia

**Already using cloud provider?**
- AWS → S3
- Google Cloud → GCS
- Azure → Azure Blob

**Need distributed BEAM coordination?**
- Yes → Mnesia (built-in), MongoDB (external)

**Need standard Zarr format (Python interop)?**
- Yes → Filesystem, S3, GCS, Azure (all follow Zarr spec)
- No → Memory, ETS, Mnesia (ExZarr-specific formats)

## Local Filesystem Storage

The default backend. Most compatible with other Zarr implementations.

### Basic Configuration

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  storage: :filesystem,
  path: "/data/my_array"
)
```

No additional dependencies required. Works out of the box.

### Directory Structure

**Zarr v2 format:**
```
/data/my_array/
├── .zarray          # Metadata (shape, chunks, dtype, compressor)
├── .zattrs          # Attributes (optional user metadata)
├── 0.0              # Chunk at index (0, 0)
├── 0.1              # Chunk at index (0, 1)
├── 1.0              # Chunk at index (1, 0)
└── ...
```

**Zarr v3 format:**
```
/data/my_array/
├── zarr.json        # Consolidated metadata + attributes
└── c/               # Chunks directory
    ├── 0/
    │   ├── 0        # Chunk at index (0, 0)
    │   └── 1        # Chunk at index (0, 1)
    ├── 1/
    │   └── 0        # Chunk at index (1, 0)
    └── ...
```

### Opening Existing Arrays

```elixir
# Open array created by ExZarr or Python zarr
{:ok, array} = ExZarr.open(path: "/data/my_array")

# Version detected automatically
array.metadata.zarr_format  # 2 or 3

# Read data
{:ok, data} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {100, 100}
)
```

### Best Practices

**Use absolute paths:**
```elixir
# Good: absolute path
path: "/data/arrays/experiment_001"

# Risky: relative path (depends on working directory)
path: "arrays/experiment_001"
```

**Check permissions before creation:**
```elixir
parent_dir = "/data/arrays"

unless File.exists?(parent_dir) and File.dir?(parent_dir) do
  IO.puts("Error: #{parent_dir} does not exist")
  System.halt(1)
end

# Verify write permissions
test_file = Path.join(parent_dir, ".write_test")
case File.write(test_file, "test") do
  :ok ->
    File.rm(test_file)
    # Proceed with array creation
  {:error, reason} ->
    IO.puts("Cannot write to #{parent_dir}: #{reason}")
end
```

**Consider filesystem limits:**
- **Max files per directory**: Linux ext4 has ~10 million limit
- **Large arrays**: {100000, 100000} with chunks {100, 100} = 1 million chunk files
- **Solution**: Use larger chunks or hierarchical storage (v3)

**Storage performance:**
- **Local SSD**: 200-500 MB/s read/write
- **HDD**: 50-150 MB/s read/write
- **Network mount (NFS)**: 10-100 MB/s (network-dependent)

Use local SSD for best performance.

## AWS S3 Storage

Scalable cloud object storage with high availability and durability.

### Dependencies

Add to `mix.exs`:
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},
    {:sweet_xml, "~> 0.7"}  # For XML response parsing
  ]
end
```

Run `mix deps.get` to install.

### Configuration

```elixir
# Register the S3 backend (required once per application startup)
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)

# Create array with S3 storage
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},   # Larger chunks for cloud storage
  dtype: :float64,
  compressor: :zstd,      # Better compression reduces transfer costs
  storage: :s3,
  bucket: "my-zarr-data",
  prefix: "experiments/array1",
  region: "us-west-2"
)

# Write data
:ok = ExZarr.Array.set_slice(array, data,
  start: {0, 0},
  stop: {1000, 1000}
)

# Read data
{:ok, result} = ExZarr.Array.get_slice(array,
  start: {0, 0},
  stop: {1000, 1000}
)
```

### S3 Object Keys

**Zarr v2:**
```
s3://my-zarr-data/experiments/array1/.zarray
s3://my-zarr-data/experiments/array1/0.0
s3://my-zarr-data/experiments/array1/0.1
s3://my-zarr-data/experiments/array1/1.0
```

**Zarr v3:**
```
s3://my-zarr-data/experiments/array1/zarr.json
s3://my-zarr-data/experiments/array1/c/0/0
s3://my-zarr-data/experiments/array1/c/0/1
s3://my-zarr-data/experiments/array1/c/1/0
```

### Authentication

**Method 1: Environment variables (development)**
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-west-2
```

```elixir
# Credentials loaded automatically from environment
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "my-zarr-data",
  prefix: "experiments/array1"
)
```

**Method 2: AWS credentials file (local development)**
```bash
# ~/.aws/credentials
[default]
aws_access_key_id = your_access_key
aws_secret_access_key = your_secret_key

# ~/.aws/config
[default]
region = us-west-2
```

Credentials loaded automatically via `ExAws` library.

**Method 3: IAM role (production, recommended)**

For EC2, ECS, Lambda, or EKS deployments:
```elixir
# No credentials needed - IAM role provides automatic authentication
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "my-zarr-data",
  prefix: "experiments/array1",
  region: "us-west-2"
)
```

**Advantages:**
- No credential management in code
- Automatic credential rotation
- Fine-grained IAM policies
- Audit logging via CloudTrail

### IAM Permissions

Minimum required IAM policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-zarr-data",
        "arn:aws:s3:::my-zarr-data/*"
      ]
    }
  ]
}
```

### S3-Compatible Services

ExZarr works with S3-compatible services (MinIO, LocalStack, Wasabi):

```elixir
# MinIO
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "zarr",
  prefix: "arrays",
  endpoint_url: "http://localhost:9000",
  region: "us-east-1"
)

# LocalStack (testing)
{:ok, array} = ExZarr.create(
  storage: :s3,
  bucket: "test-bucket",
  prefix: "test",
  endpoint_url: "http://localhost:4566",
  region: "us-east-1"
)
```

Set `AWS_ENDPOINT_URL` environment variable to override default S3 endpoint.

### S3 Performance Tips

**Use larger chunks:**
```elixir
# Poor: 100×100 chunks = 80 KB each (many small requests)
chunks: {100, 100}

# Good: 1000×1000 chunks = 8 MB each (fewer, larger requests)
chunks: {1000, 1000}
```

**Enable compression:**
```elixir
# Reduces transfer size and bandwidth costs
compressor: :zstd
```

**Parallelize chunk access:**
```elixir
# Read 100 chunks concurrently (amortizes S3 latency)
Task.async_stream(chunk_coords, &read_chunk/1, max_concurrency: 20)
|> Enum.to_list()
```

See [Parallel I/O Guide](parallel_io.md) for patterns.

## Google Cloud Storage (GCS)

Google's scalable object storage with strong consistency.

### Dependencies

Add to `mix.exs`:
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:goth, "~> 1.4"},      # Authentication
    {:req, "~> 0.4"}        # HTTP client
  ]
end
```

### Configuration

```elixir
# Register the GCS backend
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.GCS)

# Create array with GCS storage
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  compressor: :zstd,
  storage: :gcs,
  bucket: "my-zarr-bucket",
  prefix: "experiments/array1",
  credentials: "/path/to/service-account.json"
)
```

### GCS Object Paths

**Zarr v2:**
```
gs://my-zarr-bucket/experiments/array1/.zarray
gs://my-zarr-bucket/experiments/array1/0.0
gs://my-zarr-bucket/experiments/array1/0.1
```

**Zarr v3:**
```
gs://my-zarr-bucket/experiments/array1/zarr.json
gs://my-zarr-bucket/experiments/array1/c/0/0
gs://my-zarr-bucket/experiments/array1/c/0/1
```

### Authentication

**Method 1: Service account JSON key (recommended for production)**

Download service account key from Google Cloud Console:
```bash
# Service account JSON key file
cat /path/to/service-account.json
{
  "type": "service_account",
  "project_id": "my-project",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "client_email": "my-service@my-project.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

```elixir
{:ok, array} = ExZarr.create(
  storage: :gcs,
  bucket: "my-zarr-bucket",
  prefix: "arrays",
  credentials: "/path/to/service-account.json"
)
```

**Method 2: Application Default Credentials (GCE/GKE)**

When running on Google Compute Engine or Google Kubernetes Engine:
```elixir
# No credentials parameter needed
{:ok, array} = ExZarr.create(
  storage: :gcs,
  bucket: "my-zarr-bucket",
  prefix: "arrays"
  # credentials: auto-detected from instance metadata
)
```

**Method 3: Environment variable**
```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

```elixir
{:ok, array} = ExZarr.create(
  storage: :gcs,
  bucket: "my-zarr-bucket",
  prefix: "arrays",
  credentials: System.get_env("GOOGLE_APPLICATION_CREDENTIALS")
)
```

### Required IAM Permissions

Service account needs these roles:
- `roles/storage.objectCreator` (write objects)
- `roles/storage.objectViewer` (read objects)

Or use predefined role:
- `roles/storage.admin` (full access to buckets)

### GCS Storage Classes

Choose storage class based on access frequency:

```elixir
# Standard: frequently accessed data
storage_class: "STANDARD"

# Nearline: accessed less than once per month
storage_class: "NEARLINE"

# Coldline: accessed less than once per quarter
storage_class: "COLDLINE"

# Archive: accessed less than once per year
storage_class: "ARCHIVE"
```

Configure at bucket level (not per-array).

## Azure Blob Storage

Microsoft's cloud object storage for Azure deployments.

### Dependencies

Add to `mix.exs`:
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:azurex, "~> 1.1"}
  ]
end
```

### Configuration

```elixir
# Register the Azure Blob backend
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.AzureBlob)

# Create array with Azure Blob storage
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  compressor: :zstd,
  storage: :azure_blob,
  account_name: "mystorageaccount",
  account_key: System.get_env("AZURE_STORAGE_KEY"),
  container: "zarr-data",
  prefix: "experiments/array1"
)
```

### Azure Blob Paths

**Zarr v2:**
```
https://mystorageaccount.blob.core.windows.net/zarr-data/experiments/array1/.zarray
https://mystorageaccount.blob.core.windows.net/zarr-data/experiments/array1/0.0
https://mystorageaccount.blob.core.windows.net/zarr-data/experiments/array1/0.1
```

**Zarr v3:**
```
https://mystorageaccount.blob.core.windows.net/zarr-data/experiments/array1/zarr.json
https://mystorageaccount.blob.core.windows.net/zarr-data/experiments/array1/c/0/0
https://mystorageaccount.blob.core.windows.net/zarr-data/experiments/array1/c/0/1
```

### Authentication

**Method 1: Account key (development)**

Get account key from Azure Portal:
```bash
export AZURE_STORAGE_KEY=your_account_key_base64_string
```

```elixir
{:ok, array} = ExZarr.create(
  storage: :azure_blob,
  account_name: "mystorageaccount",
  account_key: System.get_env("AZURE_STORAGE_KEY"),
  container: "zarr-data",
  prefix: "arrays"
)
```

**Method 2: SAS token (delegated access)**

Generate SAS token with limited permissions and expiry:
```elixir
{:ok, array} = ExZarr.create(
  storage: :azure_blob,
  account_name: "mystorageaccount",
  sas_token: System.get_env("AZURE_SAS_TOKEN"),
  container: "zarr-data",
  prefix: "arrays"
)
```

**Method 3: Managed identity (Azure VMs)**

When running on Azure VMs or App Service:
```elixir
# Use managed identity (no credentials needed)
{:ok, array} = ExZarr.create(
  storage: :azure_blob,
  account_name: "mystorageaccount",
  use_managed_identity: true,
  container: "zarr-data",
  prefix: "arrays"
)
```

### Azure Access Tiers

Choose based on access frequency:
- **Hot**: Frequently accessed data (default)
- **Cool**: Infrequently accessed (at least 30 days)
- **Archive**: Rarely accessed (at least 180 days, offline)

Configure at container or blob level.

## Database Storage

### Mnesia: Distributed BEAM Database

Built-in Erlang database with ACID transactions and replication.

**No external dependencies required.** Mnesia is part of Erlang/OTP.

**Setup:**
```elixir
# Initialize Mnesia (once per node)
:mnesia.create_schema([node()])
:mnesia.start()

# Register backend
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mnesia)

# Create array
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :mnesia,
  array_id: "experiment_001",
  table_name: :zarr_storage
)
```

**Distributed setup:**
```elixir
# Create replicated table across nodes
{:ok, array} = ExZarr.create(
  storage: :mnesia,
  array_id: "shared_array",
  table_name: :zarr_arrays,
  nodes: [node(), :"worker1@host", :"worker2@host"],
  ram_copies: false  # Use disc_copies for persistence
)
```

**Use cases:**
- BEAM-native storage (no external database)
- Distributed Elixir applications
- Small to medium datasets (< 100 GB)
- ACID transaction requirements

### MongoDB GridFS: Document Database Storage

Stores large chunks in MongoDB using GridFS.

**Dependencies:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:mongodb_driver, "~> 1.4"}
  ]
end
```

**Configuration:**
```elixir
# Register backend
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.MongoGridFS)

# Create array
{:ok, array} = ExZarr.create(
  shape: {10000, 10000},
  chunks: {1000, 1000},
  dtype: :float64,
  storage: :mongo_gridfs,
  url: "mongodb://localhost:27017",
  database: "zarr_db",
  bucket: "arrays",
  array_id: "experiment_001"
)
```

**GridFS structure:**
```
Database: zarr_db
Collection: arrays.files, arrays.chunks

Files:
- {filename: "experiment_001/.zarray", ...}
- {filename: "experiment_001/0.0", ...}
- {filename: "experiment_001/0.1", ...}
```

**Use cases:**
- Existing MongoDB infrastructure
- Chunk sizes > 16 MB (MongoDB document limit)
- Distributed deployments with MongoDB sharding
- Need for MongoDB queries and aggregations

## In-Memory Storage Backends

### Memory: Process-Local Storage

Fastest storage, non-persistent.

```elixir
# No configuration needed
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :memory
)

# Data lost when process exits
```

**Use cases:**
- Unit tests (fast, isolated)
- Temporary arrays during computation
- Caching intermediate results

**Limitations:**
- Data lost on process exit
- Limited by process memory
- Not accessible from other processes

### ETS: Shared In-Memory Storage

Fast in-memory storage shared across processes.

```elixir
# Register backend
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.ETS)

# Create array with named ETS table
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :ets,
  table_name: :shared_array_data
)

# Other processes can access same table
# (via array struct or by opening)
```

**Use cases:**
- Multi-process coordination (GenServer pools)
- Shared caching across Phoenix requests
- Testing concurrent access patterns
- Node-local shared storage

**Advantages over Memory:**
- Accessible from multiple processes
- Survives owning process crash (if heir configured)
- Lower overhead than GenServer/Agent

## Credential Management

**Security principles:**

1. **Never hardcode credentials**
   ```elixir
   # BAD: credentials in source code
   account_key: "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="

   # GOOD: load from environment
   account_key: System.get_env("AZURE_STORAGE_KEY")
   ```

2. **Never commit credentials to version control**
   ```bash
   # Add to .gitignore
   .env
   config/*.secret.exs
   credentials.json
   ```

3. **Use runtime configuration**
   ```elixir
   # config/runtime.exs
   import Config

   config :my_app, :storage,
     account_name: System.get_env("AZURE_STORAGE_ACCOUNT"),
     account_key: System.get_env("AZURE_STORAGE_KEY"),
     container: System.get_env("AZURE_CONTAINER")

   # In application
   storage_config = Application.get_env(:my_app, :storage)

   {:ok, array} = ExZarr.create(
     storage: :azure_blob,
     account_name: storage_config[:account_name],
     account_key: storage_config[:account_key],
     container: storage_config[:container]
   )
   ```

4. **Use secret management services**

   **AWS Secrets Manager:**
   ```elixir
   # Fetch secret at startup
   {:ok, secret} = ExAws.SecretsManager.get_secret_value("zarr/storage/credentials")
                   |> ExAws.request()

   credentials = Jason.decode!(secret["SecretString"])

   {:ok, array} = ExZarr.create(
     storage: :s3,
     bucket: credentials["bucket"],
     # AWS credentials via IAM role
   )
   ```

   **Google Secret Manager:**
   ```elixir
   # Fetch secret
   {:ok, response} = GoogleApi.SecretManager.V1.Api.Projects.secretmanager_projects_secrets_versions_access(
     connection,
     "projects/my-project/secrets/gcs-credentials/versions/latest"
   )

   credentials = Jason.decode!(response.payload.data)
   ```

   **HashiCorp Vault:**
   ```elixir
   {:ok, response} = Vault.read("secret/data/zarr/gcs")
   credentials = response.data.data

   {:ok, array} = ExZarr.create(
     storage: :gcs,
     bucket: credentials["bucket"],
     credentials: credentials["service_account"]
   )
   ```

5. **Prefer IAM roles/managed identities**

   Best practice for production:
   - AWS: Use IAM roles (EC2, ECS, Lambda)
   - GCP: Use workload identity or service accounts
   - Azure: Use managed identity

   No credentials in code or environment variables.

### Environment Variables Pattern

For local development, use environment variables:

```bash
# .env (never commit this file)
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=us-west-2

AZURE_STORAGE_ACCOUNT=mystorageaccount
AZURE_STORAGE_KEY=your_key

GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

Load with dotenv or envy:
```elixir
# In config/runtime.exs or application.ex
System.get_env("AWS_ACCESS_KEY_ID")  # Loaded from shell environment
```

## Cloud Storage Performance Considerations

### Chunk Size Impact

Cloud storage charges per API request. Larger chunks reduce costs:

**Example: 10 GB array**
```
Small chunks (100×100, 80 KB each):
- Chunks: 125,000
- S3 PUT requests: 125,000
- Cost: 125 × $0.0004 = $0.05 per upload
- Total monthly (30 uploads): $1.50

Large chunks (1000×1000, 8 MB each):
- Chunks: 1,250
- S3 PUT requests: 1,250
- Cost: 1.25 × $0.0004 = $0.0005 per upload
- Total monthly (30 uploads): $0.015

Savings: 100× fewer requests, 100× lower cost
```

**Recommendation:** Use 1-10 MB chunks for cloud storage.

### Latency vs Throughput

**Single chunk access:**
```
S3 GET latency: 50-200ms per request
1 chunk: 100ms
10 chunks sequential: 1,000ms
```

**Parallel chunk access:**
```
10 chunks parallel (concurrency=10): ~150ms
Speedup: 6.7×
```

Parallelism amortizes cloud latency. See [Parallel I/O Guide](parallel_io.md).

### Bandwidth Costs

Cloud providers charge for data egress (download):

**AWS S3:**
- First 100 GB/month: Free
- Next 10 TB/month: $0.09/GB
- Next 40 TB/month: $0.085/GB

**Google Cloud Storage:**
- First 200 GB/month: Free (egress to worldwide destinations)
- Next 10 TB/month: $0.12/GB

**Azure Blob:**
- First 100 GB/month: Free
- Next 10 TB/month: $0.087/GB

**Reducing bandwidth costs:**
```elixir
# Use compression to reduce transfer size
compressor: :zstd  # 40-60% size reduction typical

# Example: 100 GB uncompressed data
# With zstd: ~40 GB transferred
# Bandwidth cost: 40 GB × $0.09 = $3.60 (vs $9.00 uncompressed)
# Savings: 60%
```

### Request Rate Limits

**AWS S3 (per prefix):**
- **GET/HEAD**: 5,500 requests/second
- **PUT/COPY/POST/DELETE**: 3,500 requests/second

Exceeding limits results in 503 SlowDown errors.

**Solution: Partition across prefixes**
```elixir
# Instead of single prefix:
prefix: "arrays/experiment"  # All chunks under one prefix

# Use partitioned prefixes:
prefix: "arrays/experiment/partition_#{rem(chunk_hash, 10)}"
# Distributes chunks across 10 prefixes
# Effective limit: 10 × 5,500 = 55,000 GET/s
```

**Google Cloud Storage:**
- No published hard limits
- Autoscaling (starts at 5,000 requests/second)
- Scales to 100,000+ with usage patterns

**Azure Blob:**
- 20,000 requests/second per storage account
- 60 MB/s egress per blob

### Eventual Consistency (Legacy S3 Regions)

**Modern S3 (2020+):** Strong consistency for all operations
- Read-after-write consistency for new objects
- Read-after-update consistency for overwrites
- Read-after-delete consistency

**Legacy S3 regions:** May have eventual consistency
- New objects: Read-after-write consistent
- Overwrites: Eventually consistent
- Deletes: Eventually consistent

ExZarr relies on read-after-write consistency for metadata. Use modern S3 regions to avoid issues.

### Cloud Cost Estimation

**Example workload:**
- Array size: 100 GB uncompressed
- Compression: zstd (40% reduction → 40 GB stored)
- Access pattern: Write once, read 10 times/month
- Chunk size: 8 MB (5,000 chunks)

**AWS S3 costs (us-west-2):**
```
Storage: 40 GB × $0.023/GB = $0.92/month
PUT requests: 5,000 × $0.005/1000 = $0.025
GET requests: 5,000 × 10 reads × $0.0004/1000 = $0.02
Egress: 40 GB × 10 reads × $0.09/GB = $36

Total: $36.97/month
(Dominated by egress costs)
```

**Reducing costs:**
- Use CloudFront or S3 Transfer Acceleration
- Cache frequently accessed chunks locally
- Use larger chunks (reduce request count)
- Compress aggressively (reduce egress)

## Zip Archive Storage

Single-file archive for distribution.

### Configuration

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :zip,
  path: "/data/array.zip"
)

# Write data
ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

# Archive contains all chunks and metadata
```

**Zip archive structure:**
```
array.zip
├── .zarray          # Metadata
├── 0.0              # Chunk at (0, 0)
├── 0.1              # Chunk at (0, 1)
└── ...
```

**Use cases:**
- Distributing datasets (single file to download)
- Archival storage (reduced file count)
- Email attachments (compact bundle)

**Limitations:**
- Read-only after creation (cannot update chunks in-place)
- Must load entire archive metadata
- Slower than filesystem for large arrays

## Storage Backend Comparison

### Performance Characteristics

| Backend | Read Latency | Write Latency | Throughput | Concurrency |
|---------|--------------|---------------|------------|-------------|
| Memory | 1 µs | 1 µs | GB/s | High |
| ETS | 5 µs | 5 µs | GB/s | Very High |
| Filesystem (SSD) | 100 µs | 100 µs | 500 MB/s | High |
| Filesystem (HDD) | 10 ms | 10 ms | 100 MB/s | Medium |
| S3 | 50-200 ms | 50-200 ms | 100+ MB/s | Very High |
| GCS | 50-200 ms | 50-200 ms | 100+ MB/s | Very High |
| Azure Blob | 50-200 ms | 50-200 ms | 100+ MB/s | Very High |
| Mnesia | 1-10 ms | 1-10 ms | 100+ MB/s | High |
| MongoDB GridFS | 5-20 ms | 5-20 ms | 50+ MB/s | Medium |

Values are approximate and depend on hardware, network, and configuration.

### Cost Comparison

| Backend | Storage Cost | Request Cost | Egress Cost |
|---------|--------------|--------------|-------------|
| Memory | Free (RAM) | Free | Free |
| ETS | Free (RAM) | Free | Free |
| Filesystem | Disk space | Free | Free |
| S3 | $0.023/GB/mo | $0.0004-0.005/1K | $0.09/GB |
| GCS | $0.020/GB/mo | Free (first 100K/day) | $0.12/GB |
| Azure Blob | $0.018/GB/mo | $0.0036-0.044/10K | $0.087/GB |
| Mnesia | Server cost | Free | Free |
| MongoDB | Server cost | Free | Free |

Cloud costs from 2026 pricing. Check provider websites for current rates.

## Practical Examples

### Example 1: Development to Production Progression

```elixir
# Development: use memory for fast iteration
defmodule Dev do
  def create_array do
    ExZarr.create(
      shape: {1000, 1000},
      chunks: {100, 100},
      dtype: :float64,
      storage: :memory
    )
  end
end

# Staging: use filesystem for inspection
defmodule Staging do
  def create_array do
    ExZarr.create(
      shape: {1000, 1000},
      chunks: {100, 100},
      dtype: :float64,
      storage: :filesystem,
      path: "/mnt/staging/arrays/test_array"
    )
  end
end

# Production: use S3 for scalability
defmodule Prod do
  def create_array do
    ExZarr.create(
      shape: {10000, 10000},
      chunks: {1000, 1000},  # Larger chunks for cloud
      dtype: :float64,
      compressor: :zstd,     # Compression for bandwidth
      storage: :s3,
      bucket: "prod-zarr-data",
      prefix: "arrays/#{Date.utc_today()}",
      region: "us-west-2"
    )
  end
end
```

Same API, different backends.

### Example 2: Multi-Region S3 Deployment

```elixir
defmodule MultiRegion do
  def create_regional_array(region, data_source) do
    # Create array in user's region for low latency
    {:ok, array} = ExZarr.create(
      shape: {10000, 10000},
      chunks: {1000, 1000},
      dtype: :float64,
      storage: :s3,
      bucket: "zarr-#{region}",  # Region-specific bucket
      prefix: "arrays",
      region: region
    )

    # Ingest data
    ingest_data(array, data_source)

    # Replicate to other regions (optional)
    replicate_to_regions(array, ["us-east-1", "eu-west-1", "ap-southeast-1"])
  end

  defp replicate_to_regions(source_array, regions) do
    Enum.each(regions, fn region ->
      # Copy chunks to regional bucket
      # (implementation details omitted)
    end)
  end
end
```

### Example 3: Hybrid Storage (Filesystem + S3)

```elixir
defmodule HybridStorage do
  def process_with_local_cache(s3_array_path, local_cache_path) do
    # Open S3 array
    {:ok, s3_array} = ExZarr.open(
      storage: :s3,
      bucket: "prod-data",
      prefix: s3_array_path
    )

    # Create local cache
    {:ok, cache_array} = ExZarr.create(
      shape: s3_array.shape,
      chunks: s3_array.chunks,
      dtype: s3_array.dtype,
      storage: :filesystem,
      path: local_cache_path
    )

    # Read from S3, cache locally
    {:ok, data} = ExZarr.Array.get_slice(s3_array,
      start: {0, 0},
      stop: {1000, 1000}
    )

    # Write to local cache
    ExZarr.Array.set_slice(cache_array, data,
      start: {0, 0},
      stop: {1000, 1000}
    )

    # Subsequent reads from cache (fast)
    {:ok, cached_data} = ExZarr.Array.get_slice(cache_array,
      start: {0, 0},
      stop: {1000, 1000}
    )
  end
end
```

## Troubleshooting

### S3: Access Denied Errors

```
{:error, {:http_error, 403, %{body: "AccessDenied"}}}
```

**Causes:**
- Missing IAM permissions
- Incorrect bucket name
- Wrong AWS region

**Fix:**
1. Verify IAM policy includes `s3:GetObject` and `s3:PutObject`
2. Check bucket exists: `aws s3 ls s3://my-zarr-data`
3. Verify region matches: `region: "us-west-2"`

### GCS: Authentication Failed

```
{:error, :authentication_failed}
```

**Causes:**
- Invalid service account JSON
- Missing required permissions
- Expired credentials

**Fix:**
1. Validate JSON syntax: `cat service-account.json | jq`
2. Check service account has `storage.objectAdmin` role
3. Verify credentials file path is correct

### Azure: Invalid Account Key

```
{:error, :invalid_account_key}
```

**Causes:**
- Account key truncated or corrupted
- Wrong account name

**Fix:**
1. Regenerate account key from Azure Portal
2. Copy entire base64 string (no line breaks)
3. Verify account name matches storage account

### Filesystem: Permission Denied

```
{:error, :eacces}
```

**Fix:**
```bash
# Check directory permissions
ls -la /data/

# Fix permissions
sudo chown -R $USER /data/my_array

# Or use user-writable directory
path: "/tmp/my_array"
```

## Summary

This guide covered storage backend configuration:

- **10 built-in backends**: Memory, ETS, Filesystem, Zip, S3, GCS, Azure, Mnesia, MongoDB, Mock
- **Local storage**: Filesystem (standard Zarr format), Memory/ETS (fast, non-persistent)
- **Cloud storage**: S3 (AWS), GCS (Google), Azure (Microsoft) with authentication methods
- **Database storage**: Mnesia (BEAM-native), MongoDB GridFS (external)
- **Credential management**: Environment variables, secret managers, IAM roles (preferred)
- **Cloud performance**: Chunk size optimization, parallelism, cost considerations

**Key recommendations:**
- Use IAM roles/managed identities in production
- Use 1-10 MB chunks for cloud storage
- Parallelize cloud operations (10-50 concurrent)
- Monitor cloud costs (egress dominates)
- Test with local backends before deploying to cloud

## Next Steps

Now that you understand storage backends:

1. **Implement Custom Backend**: Build your own storage in [Custom Storage Backend Guide](custom_storage_backend.md)
2. **Optimize Compression**: Reduce storage costs in [Compression and Codecs Guide](compression_codecs.md)
3. **Tune Performance**: Benchmark chunk sizes in [Performance Guide](performance.md)
4. **Python Interop**: Share cloud arrays with Python in [Python Interoperability Guide](python_interop.md)
