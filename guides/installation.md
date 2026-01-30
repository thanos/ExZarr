# Installation and Build Toolchain

This guide covers installing ExZarr, setting up the Zig toolchain for high-performance codecs, and troubleshooting common build issues. Follow these steps to get ExZarr running reliably on macOS, Linux, or in CI environments.

## Prerequisites

### Required Software

**Elixir and Erlang/OTP:**
- Elixir 1.14 or later
- Erlang/OTP 25 or later

Check your versions:
```bash
elixir --version
# Erlang/OTP 25 [erts-13.0] [source] [64-bit] [smp:8:8] [ds:8:8:10]
# Elixir 1.14.0 (compiled with Erlang/OTP 25)
```

These versions are required because ExZarr uses modern Elixir features and requires OTP 25+ for certain BEAM capabilities.

**Operating System Support:**
- macOS (Intel and Apple Silicon)
- Linux (Ubuntu/Debian, Fedora/RHEL, Arch)
- Windows (not officially tested, may work with WSL2)

### Optional Dependencies

**Zig Toolchain:**
Required only if you want high-performance codecs (zstd, lz4, snappy, blosc, bzip2). If you skip this, ExZarr will use Erlang's built-in zlib codec, which is reliable and works everywhere.

**System Libraries for Codecs:**
Required for Zig NIFs to compile. See [Zig Toolchain Setup](#zig-toolchain-setup) section below.

## Mix Dependency Installation

### Basic Installation

Add ExZarr to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"}
  ]
end
```

Then fetch dependencies:
```bash
mix deps.get
```

This installs ExZarr with all required dependencies (Jason for JSON, Zigler for Zig compilation).

### Optional Dependencies

For cloud storage backends, add the appropriate libraries:

**AWS S3:**
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

**Google Cloud Storage:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:goth, "~> 1.4"},      # Authentication
    {:req, "~> 0.4"}        # HTTP client
  ]
end
```

**Azure Blob Storage:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:azurex, "~> 1.1"}
  ]
end
```

**MongoDB GridFS:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.0"},
    {:mongodb_driver, "~> 1.4"}
  ]
end
```

These dependencies are marked as `optional: true` in ExZarr's `mix.exs`, so they're only included when you explicitly add them.

### Compilation

Compile the project:
```bash
mix compile
```

First compilation will:
1. Download Zigler (if not cached)
2. Download Zig compiler (if not cached, ~200MB)
3. Compile Zig NIFs (if system libraries present)
4. Compile Elixir modules

This can take 2-5 minutes on first run. Subsequent compilations are much faster (seconds).

## Zig Toolchain Setup

Zig is used for high-performance compression codecs. If you skip this section, ExZarr will work fine using Erlang's built-in zlib codec.

### Automatic Setup (Recommended)

Zigler automatically downloads the Zig compiler when you run `mix compile`. No manual installation needed.

The Zig compiler (~200MB) is cached in `~/.cache/zigler/` for reuse across projects.

### Manual Zig Installation (Optional)

You can pre-install Zig manually to avoid automatic downloads:

**macOS:**
```bash
brew install zig
```

**Linux (from official binaries):**
```bash
# Download Zig 0.13.0 (or later)
wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
tar xf zig-linux-x86_64-0.13.0.tar.xz
sudo mv zig-linux-x86_64-0.13.0 /usr/local/zig
export PATH=/usr/local/zig:$PATH

# Verify
zig version
```

**Ubuntu/Debian (from apt):**
```bash
# Note: apt version may be older than required
sudo apt install zig
```

### System Libraries for Codecs

For Zig NIFs to compile and link properly, install compression libraries:

**macOS:**
```bash
brew install zstd lz4 snappy c-blosc bzip2
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
  libzstd-dev \
  liblz4-dev \
  libsnappy-dev \
  libblosc-dev \
  libbz2-dev
```

**Fedora/RHEL/Rocky Linux:**
```bash
sudo dnf install -y \
  zstd-devel \
  lz4-devel \
  snappy-devel \
  blosc-devel \
  bzip2-devel
```

**Arch Linux:**
```bash
sudo pacman -S zstd lz4 snappy blosc bzip2
```

### Verifying Codec Availability

After compilation, check which codecs are available:

```elixir
# Start IEx
iex -S mix

# Check available codecs
iex> ExZarr.Codecs.available_codecs()
[:zlib, :gzip, :zstd, :lz4, :snappy, :blosc, :bzip2, :crc32c]

# If Zig NIFs didn't compile, you'll see:
[:zlib, :gzip]  # Only Erlang built-in codecs
```

If you see only `:zlib` and `:gzip`, the Zig NIFs didn't compile. This is fine for basic usage, but you won't have access to faster compression algorithms. See [Build Troubleshooting](#build-troubleshooting) below.

## Verifying Installation

### Quick Verification Test

Run this in IEx to verify ExZarr is working:

```elixir
# Start IEx
iex -S mix

# Create a small in-memory array
iex> {:ok, array} = ExZarr.create(
  shape: {10, 10},
  chunks: {5, 5},
  dtype: :float64,
  storage: :memory
)
{:ok, %ExZarr.Array{...}}

# Write some data
iex> data = Tuple.duplicate(Tuple.duplicate(1.0, 10), 10)
iex> :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
:ok

# Read it back
iex> {:ok, retrieved} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10, 10})
{:ok, {{1.0, 1.0, ...}, ...}}

# Verify data matches
iex> data == retrieved
true
```

If this works, ExZarr is installed correctly.

### Comprehensive Verification

Run the test suite:

```bash
# Run all tests
mix test

# Should see output like:
# ..................................................
# Finished in 2.3 seconds (0.1s async, 2.2s sync)
# 466 tests, 0 failures
```

If tests pass, your installation is complete and working correctly.

### Check Installed Version

```elixir
iex> Application.spec(:ex_zarr, :vsn) |> to_string()
"1.0.0"
```

## Build Troubleshooting

### Issue: Zig Compilation Fails

**Symptom:**
```
** (Mix) Could not compile dependency :ex_zarr
...
error: unable to find library -lzstd
```

**Cause:** Missing system libraries for compression codecs.

**Fix:**
Install the required libraries for your platform (see [System Libraries for Codecs](#system-libraries-for-codecs) above).

After installing libraries:
```bash
# Clean and recompile
mix deps.clean ex_zarr --build
mix deps.get
mix compile
```

**Workaround:**
If you can't install system libraries, ExZarr will work with Erlang's built-in zlib:

```elixir
# Just use zlib - always available
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib  # No Zig NIFs required
)
```

### Issue: Mix Hangs During Compilation

**Symptom:**
`mix compile` appears to hang with no output for several minutes.

**Cause:**
Zigler is downloading the Zig compiler (~200MB) on first compilation. On slow networks, this takes time.

**Diagnosis:**
Check if download is happening:
```bash
# In another terminal
ls -lh ~/.cache/zigler/

# Watch for growing files
watch -n 1 "du -sh ~/.cache/zigler/"
```

**Fix:**
Wait patiently. The download happens only once and is cached.

**Alternative:**
Pre-install Zig manually (see [Manual Zig Installation](#manual-zig-installation-optional)) to avoid automatic download.

### Issue: Compilation Timeout in CI

**Symptom:**
CI build times out during `mix deps.compile`.

**Cause:**
First compilation is slow (downloading Zig, compiling NIFs). Default CI timeouts may be too short.

**Fix:**
Increase timeout in CI configuration:

```yaml
# GitHub Actions
- name: Compile dependencies
  run: mix deps.compile
  timeout-minutes: 15  # Increase from default 5
```

**Better solution - Cache Zigler:**
```yaml
# GitHub Actions
- name: Cache Zigler
  uses: actions/cache@v3
  with:
    path: ~/.cache/zigler
    key: ${{ runner.os }}-zigler-${{ hashFiles('**/mix.lock') }}

- name: Cache build
  uses: actions/cache@v3
  with:
    path: _build
    key: ${{ runner.os }}-build-${{ hashFiles('**/mix.lock') }}
```

After caching, subsequent builds are fast (30-60 seconds).

### Issue: Architecture Mismatch (Apple Silicon)

**Symptom on M1/M2 Mac:**
```
dyld: Symbol not found: _lz4_compress
Architecture error
```

**Cause:**
System libraries installed for wrong architecture (x86_64 instead of ARM64).

**Diagnosis:**
```bash
# Check your architecture
uname -m
# Should output: arm64

# Check library architecture
file /opt/homebrew/lib/liblz4.dylib
# Should contain: arm64
```

**Fix:**
Reinstall libraries for ARM64:
```bash
# Ensure using ARM64 Homebrew
which brew
# Should be: /opt/homebrew/bin/brew (not /usr/local/bin/brew)

# Reinstall libraries
brew reinstall zstd lz4 snappy c-blosc bzip2

# Clean and recompile
mix deps.clean ex_zarr --build
mix compile
```

### Issue: ExZarr Compiles But Codec Not Available

**Symptom:**
Compilation succeeds, but codec returns unavailable at runtime:

```elixir
iex> ExZarr.Codecs.available_codecs()
[:zlib, :gzip]  # Missing zstd, lz4, etc.
```

**Cause:**
NIF compiled but failed to load at runtime due to missing runtime libraries.

**Diagnosis:**
```bash
# Check if NIF file exists
ls -la _build/dev/lib/ex_zarr/priv/*.so

# Check NIF dependencies (Linux)
ldd _build/dev/lib/ex_zarr/priv/zig_codecs.so

# Check NIF dependencies (macOS)
otool -L _build/dev/lib/ex_zarr/priv/zig_codecs.so
```

**Fix (Linux):**
```bash
# Ensure library path includes codec libraries
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Or install libraries system-wide
sudo ldconfig
```

**Fix (macOS):**
```bash
# Usually Homebrew handles this, but if needed:
export DYLD_LIBRARY_PATH=/opt/homebrew/lib:$DYLD_LIBRARY_PATH
```

### Issue: Permission Denied Errors

**Symptom:**
```
** (File.Error) could not write to file "priv/zig_codecs.so": permission denied
```

**Cause:**
Build directory has incorrect permissions, often from running `sudo mix` previously.

**Fix:**
```bash
# Fix ownership
sudo chown -R $USER _build deps

# Clean and rebuild
mix deps.clean --all
mix deps.get
mix compile
```

**Prevention:**
Never run `mix` commands with `sudo`. If you need system-wide installation, use proper Elixir version management (asdf, mise).

## CI/CD Configuration

### GitHub Actions Example

Complete workflow for testing ExZarr in CI:

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.14', '1.15', '1.16']
        otp: ['25', '26', '27']

    steps:
    - uses: actions/checkout@v3

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}

    - name: Install system dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y \
          libzstd-dev \
          liblz4-dev \
          libsnappy-dev \
          libblosc-dev \
          libbz2-dev

    - name: Cache deps
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

    - name: Cache Zigler
      uses: actions/cache@v3
      with:
        path: ~/.cache/zigler
        key: ${{ runner.os }}-zigler-${{ hashFiles('**/mix.lock') }}

    - name: Cache build
      uses: actions/cache@v3
      with:
        path: _build
        key: ${{ runner.os }}-build-${{ matrix.otp }}-${{ matrix.elixir }}-${{ hashFiles('**/mix.lock') }}

    - name: Install dependencies
      run: mix deps.get

    - name: Compile
      run: mix compile --warnings-as-errors

    - name: Run tests
      run: mix test

    - name: Check formatting
      run: mix format --check-formatted

    - name: Run Credo
      run: mix credo --strict
```

### Docker Example

Dockerfile for ExZarr application:

```dockerfile
FROM elixir:1.16-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    zstd-dev \
    lz4-dev \
    snappy-dev \
    bzip2-dev

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy source
COPY . .

# Compile (includes Zig NIFs)
RUN mix deps.compile
RUN MIX_ENV=prod mix compile

# Runtime stage
FROM elixir:1.16-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    zstd \
    lz4-libs \
    snappy \
    bzip2

WORKDIR /app

# Copy compiled artifacts
COPY --from=builder /app/_build/prod /app/_build/prod
COPY --from=builder /app/deps /app/deps

CMD ["iex", "-S", "mix"]
```

### GitLab CI Example

```yaml
image: elixir:1.16

cache:
  paths:
    - deps/
    - _build/
    - ~/.cache/zigler/

before_script:
  - apt-get update
  - apt-get install -y libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev
  - mix local.hex --force
  - mix local.rebar --force
  - mix deps.get

test:
  script:
    - mix compile --warnings-as-errors
    - mix test
    - mix credo --strict
```

### Caching Best Practices

**Always cache:**
- `deps/` - Mix dependencies
- `_build/` - Compiled artifacts
- `~/.cache/zigler/` - Zig compiler download

**Cache keys should include:**
- OS/platform
- Elixir/OTP versions
- `mix.lock` hash (invalidate on dependency changes)

**Typical cache savings:**
- Without cache: 5-10 minutes (downloading Zig, compiling NIFs)
- With cache: 30-90 seconds (only recompile changed files)

## Next Steps

Now that ExZarr is installed:

1. **Try the Quickstart**: See [Quickstart Guide](quickstart.md) for a 5-minute working example
2. **Learn Core Concepts**: Understand chunking and codecs in [Core Concepts Guide](core_concepts.md)
3. **Configure Storage**: Set up S3 or other backends in [Storage Providers Guide](storage_providers.md)
4. **Optimize Performance**: Tune chunk sizes and compression in [Performance Guide](performance.md)

## Getting Help

If you encounter issues not covered here:

1. Check [Troubleshooting Guide](troubleshooting.md) for more solutions
2. Verify your environment matches [Prerequisites](#prerequisites)
3. Search [GitHub Issues](https://github.com/thanos/ExZarr/issues)
4. Open a new issue with your environment details and error messages

Include in bug reports:
```bash
# Gather environment info
elixir --version
mix --version
uname -a
ls -la _build/dev/lib/ex_zarr/priv/  # Check for .so files
```
