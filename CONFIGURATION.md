# ExZarr Configuration Guide

This guide explains how to configure ExZarr's compression libraries and other configurable options.

## Overview

ExZarr automatically detects compression library paths based on your platform, but also supports environment variable overrides for custom installations.

## Compression Library Configuration

### Automatic Detection

By default, ExZarr automatically detects where compression libraries are installed:

- **macOS**: Detects Homebrew installation automatically
  - ARM Macs (Apple Silicon): `/opt/homebrew`
  - Intel Macs: `/usr/local`
  - Falls back to `brew --prefix` command if available

- **Linux**: Uses standard system library paths
  - `/usr/lib`
  - `/usr/local/lib`
  - `/usr/lib/x86_64-linux-gnu` (Debian/Ubuntu x64)
  - `/usr/lib/aarch64-linux-gnu` (Debian/Ubuntu ARM)

### Environment Variables

You can override automatic detection using these environment variables:

#### `COMPRESSION_LIB_DIRS`

Specifies custom library directories as a colon-separated list.

**When to use**: When compression libraries are installed in non-standard locations.

**Example**:
```bash
export COMPRESSION_LIB_DIRS="/opt/custom/lib:/usr/local/custom/lib"
rm -rf _build
mix compile
```

**Important**: Must be set **before** compilation, as paths are embedded in the compiled NIF.

#### `HOMEBREW_PREFIX`

Overrides the Homebrew installation prefix (macOS only).

**When to use**: When using a custom Homebrew installation location.

**Example**:
```bash
export HOMEBREW_PREFIX="/custom/homebrew"
rm -rf _build
mix compile
```

#### `BZIP2_STATIC_LIB`

Specifies the full path to the bzip2 static library file.

**When to use**: When bzip2's static library is in a non-standard location.

**Example**:
```bash
export BZIP2_STATIC_LIB="/custom/path/to/libbz2.a"
rm -rf _build
mix compile
```

#### `DYLD_FALLBACK_LIBRARY_PATH` (macOS Runtime)

macOS-specific environment variable for runtime library loading.

**When to use**: Only needed if automatic rpaths don't work (rare).

**Example**:
```bash
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/opt/zstd/lib:/opt/homebrew/opt/lz4/lib:/opt/homebrew/opt/snappy/lib:/opt/homebrew/opt/c-blosc/lib:/opt/homebrew/opt/bzip2/lib"
```

**Note**: This is a runtime variable, not a compile-time variable.

## Zig Configuration

#### `ZIG_PATH`

Specifies a custom Zig installation path for zigler.

**When to use**: When using a custom Zig installation instead of the cached version.

**Example**:
```bash
export ZIG_PATH="/custom/zig/installation/bin/zig"
mix compile
```

## Configuration Check

To verify your configuration, run:

```bash
mix run -e "ExZarr.Codecs.CompressionConfig.library_dirs() |> IO.inspect(label: \"Library dirs\")"
```

This will show the detected library paths.

## Common Scenarios

### Scenario 1: Standard Homebrew Installation (macOS)

No configuration needed! Just install libraries and compile:

```bash
brew install zstd lz4 snappy c-blosc bzip2
mix compile
```

### Scenario 2: Custom Library Location (Any Platform)

```bash
# Set custom paths
export COMPRESSION_LIB_DIRS="/my/custom/libs:/another/path"

# Clean and recompile
rm -rf _build
mix compile
```

### Scenario 3: Docker/Container with Custom Paths

```dockerfile
FROM elixir:1.19

# Install libraries to custom location
RUN mkdir -p /opt/compression-libs
# ... install libraries to /opt/compression-libs ...

# Set environment variable
ENV COMPRESSION_LIB_DIRS=/opt/compression-libs/lib

# Compile application
WORKDIR /app
COPY . .
RUN mix deps.get && mix compile
```

### Scenario 4: Multiple Homebrew Installations (macOS)

```bash
# Use specific Homebrew installation
export HOMEBREW_PREFIX="/opt/homebrew-custom"

# Clean and recompile
rm -rf _build
mix compile
```

### Scenario 5: Intel Mac (x86_64)

ExZarr automatically detects Intel Macs and uses `/usr/local` instead of `/opt/homebrew`.

To verify:
```bash
mix run -e "ExZarr.Codecs.CompressionConfig.homebrew_prefix() |> IO.inspect()"
```

### Scenario 6: Linux Package Managers

Standard package manager installations work automatically:

**Ubuntu/Debian**:
```bash
sudo apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev
mix compile
```

**Fedora/RHEL**:
```bash
sudo dnf install zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel
mix compile
```

**Arch Linux**:
```bash
sudo pacman -S zstd lz4 snappy blosc bzip2
mix compile
```

## Troubleshooting

### Libraries Not Found at Compile Time

**Symptom**: Compilation fails with "library not found" errors.

**Solution**: Set `COMPRESSION_LIB_DIRS` to the correct paths:
```bash
# Find where libraries are installed
find /usr /opt -name "libzstd.*" 2>/dev/null

# Set the directory (without the filename)
export COMPRESSION_LIB_DIRS="/path/to/lib"
rm -rf _build && mix compile
```

### Libraries Not Found at Runtime (macOS)

**Symptom**: Application crashes with "symbol not found" or "library not loaded" errors.

**Solution**: Set runtime library path:
```bash
export DYLD_FALLBACK_LIBRARY_PATH="$(brew --prefix)/opt/zstd/lib:$(brew --prefix)/opt/lz4/lib:$(brew --prefix)/opt/snappy/lib:$(brew --prefix)/opt/c-blosc/lib:$(brew --prefix)/opt/bzip2/lib"
```

Or add to your shell profile (`~/.zshrc` or `~/.bashrc`).

### Codec Shows as Unavailable

**Symptom**: `ExZarr.Codecs.codec_available?(:codec_name)` returns `false`.

**Steps to debug**:

1. Check if library is installed:
   ```bash
   # macOS
   brew list | grep codec_name

   # Linux
   ldconfig -p | grep codec_name
   ```

2. Check if library can be loaded:
   ```bash
   otool -L _build/dev/lib/ex_zarr/priv/lib/Elixir.ExZarr.Codecs.ZigCodecs.so  # macOS
   ldd _build/dev/lib/ex_zarr/priv/lib/Elixir.ExZarr.Codecs.ZigCodecs.so      # Linux
   ```

3. Recompile with correct paths:
   ```bash
   export COMPRESSION_LIB_DIRS="/correct/path"
   rm -rf _build
   mix compile
   ```

## Configuration Module API

The `ExZarr.Codecs.CompressionConfig` module provides functions to inspect configuration:

```elixir
# Get library directories for compilation
ExZarr.Codecs.CompressionConfig.library_dirs()
# => ["/opt/homebrew/opt/zstd/lib", ...]

# Get rpath directories (includes both ARM and Intel paths on macOS)
ExZarr.Codecs.CompressionConfig.rpath_dirs()
# => ["/opt/homebrew/opt/zstd/lib", ..., "/usr/local/opt/zstd/lib", ...]

# Get Homebrew prefix
ExZarr.Codecs.CompressionConfig.homebrew_prefix()
# => "/opt/homebrew"

# Get bzip2 static library path
ExZarr.Codecs.CompressionConfig.bzip2_static_lib()
# => "/opt/homebrew/opt/bzip2/lib/libbz2.a"
```

## Files Involved

The configuration system consists of:

- `lib/ex_zarr/codecs/compression_config.ex` - Configuration detection and management
- `lib/ex_zarr/codecs/zig_codecs.ex` - Uses configuration at compile time
- `lib/mix/tasks/fix_nif_rpaths.ex` - Uses configuration to add rpaths
- `config/config.exs` - Documents environment variables

## See Also

- [COMPRESSION_SETUP.md](COMPRESSION_SETUP.md) - Installation and setup guide
- [README.md](README.md) - General usage documentation
