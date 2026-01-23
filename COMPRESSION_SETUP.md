# Compression Codecs Setup

ExZarr includes Zig NIFs that bind to C compression libraries for high-performance compression. This guide explains how to set up and use these codecs.

## Available Codecs

- **:none** - No compression (always available)
- **:zlib** - Zlib compression via Erlang's built-in `:zlib` (always available)
- **:zstd** - Zstandard compression via libzstd (requires system library)
- **:lz4** - LZ4 compression via liblz4 (requires system library)
- **:snappy** - Snappy compression via libsnappy (requires system library)
- **:blosc** - Blosc meta-compressor via libblosc (requires system library)
- **:bzip2** - Bzip2 compression via libbz2 (requires system library)

## Installation

### macOS (Homebrew)

```bash
brew install zstd lz4 snappy c-blosc bzip2
```

### Ubuntu/Debian

```bash
sudo apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev
```

### Fedora/RHEL

```bash
sudo dnf install zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel
```

## Compilation

### First-time Setup

1. Install system libraries (see above)

2. Install Zig for zigler:
```bash
mix zig.get
```

3. Compile the project:

**macOS and Linux (Auto-detection):**
```bash
mix deps.get
mix compile
```

ExZarr automatically detects compression library paths based on your platform:
- **macOS**: Uses Homebrew paths (detects ARM vs Intel automatically)
- **Linux**: Uses standard system library paths

**Custom Installation Paths:**

If your compression libraries are installed in non-standard locations, set environment variables before compiling:

```bash
# Custom library directories (colon-separated)
export COMPRESSION_LIB_DIRS="/custom/path/lib:/another/path/lib"

# Custom Homebrew prefix (macOS only)
export HOMEBREW_PREFIX="/custom/homebrew"

# Custom bzip2 static library path
export BZIP2_STATIC_LIB="/custom/path/to/libbz2.a"

# Now compile
mix deps.get
mix compile
```

### Runtime Configuration (macOS)

The Zig NIFs need to find the compression libraries at runtime. ExZarr automatically handles this in most cases.

#### Automatic Configuration (Recommended)

The compilation process automatically adds rpaths to the compiled NIF library using `install_name_tool`. This works for most standard Homebrew installations on both ARM and Intel Macs.

Just compile and run:
```bash
mix compile
mix run
```

#### Manual Configuration (If Needed)

If you installed libraries in non-standard locations, or if automatic rpaths fail, set the library path environment variable:

**Option 1: Set for single session**
```bash
export DYLD_FALLBACK_LIBRARY_PATH="$(brew --prefix)/opt/zstd/lib:$(brew --prefix)/opt/lz4/lib:$(brew --prefix)/opt/snappy/lib:$(brew --prefix)/opt/c-blosc/lib:$(brew --prefix)/opt/bzip2/lib"
```

**Option 2: Add to shell profile**

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# For ARM Macs
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/opt/zstd/lib:/opt/homebrew/opt/lz4/lib:/opt/homebrew/opt/snappy/lib:/opt/homebrew/opt/c-blosc/lib:/opt/homebrew/opt/bzip2/lib:$DYLD_FALLBACK_LIBRARY_PATH"

# For Intel Macs
export DYLD_FALLBACK_LIBRARY_PATH="/usr/local/opt/zstd/lib:/usr/local/opt/lz4/lib:/usr/local/opt/snappy/lib:/usr/local/opt/c-blosc/lib:/usr/local/opt/bzip2/lib:$DYLD_FALLBACK_LIBRARY_PATH"
```

Then reload your shell:
```bash
source ~/.zshrc  # or ~/.bashrc
```

## Usage

### Check Available Codecs

```elixir
# Returns list of available codecs at runtime
ExZarr.Codecs.available_codecs()
# => [:none, :zlib, :zstd, :lz4, :snappy, :blosc, :bzip2]

# Check if specific codec is available
ExZarr.Codecs.codec_available?(:zstd)
# => true or false
```

### Compress and Decompress

```elixir
data = "Hello, World!"

# Basic compression (uses default level)
{:ok, compressed} = ExZarr.Codecs.compress(data, :zstd)
{:ok, decompressed} = ExZarr.Codecs.decompress(compressed, :zstd)

# With compression level
{:ok, compressed} = ExZarr.Codecs.compress(data, :zstd, level: 9)

# Different codecs
{:ok, lz4_compressed} = ExZarr.Codecs.compress(data, :lz4)
{:ok, blosc_compressed} = ExZarr.Codecs.compress(data, :blosc, level: 5)
{:ok, bzip2_compressed} = ExZarr.Codecs.compress(data, :bzip2, level: 9)
```

### Use with Zarr Arrays

```elixir
# Create array with compression
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zstd,  # Use Zstandard compression
  storage: :filesystem,
  path: "/data/my_array"
)
```

## Troubleshooting

### NIFs Not Loading

If you see errors like:
```
Failed to load NIF library: 'symbol not found in flat namespace'
```

**Solution 1:** Set the library path environment variable (see Option 1 above)

**Solution 2:** Recompile with `-Wl,-headerpad_max_install_names` (see Option 2 above)

### Codec Not Available

If `codec_available?/1` returns `false` for a codec:

1. **Check system library is installed:**
   ```bash
   # macOS
   brew list | grep -E "zstd|lz4|snappy|blosc|bzip2"

   # Linux
   ldconfig -p | grep -E "zstd|lz4|snappy|blosc|bz2"
   ```

2. **Verify library paths are set** (macOS):
   ```bash
   echo $DYLD_FALLBACK_LIBRARY_PATH
   ```

3. **Recompile** with proper LDFLAGS and CPPFLAGS

### Compression Fails

If compression returns an error:

1. **Check the codec is available:**
   ```elixir
   ExZarr.Codecs.codec_available?(:your_codec)
   ```

2. **Try a simpler codec** to isolate the issue:
   ```elixir
   # ZLIB always works
   {:ok, compressed} = ExZarr.Codecs.compress(data, :zlib)
   ```

3. **Check library loading:**
   ```bash
   # macOS - check what libraries the NIF links to
   otool -L _build/dev/lib/ex_zarr/priv/lib/Elixir.ExZarr.Codecs.ZigCodecs.so
   ```

## Performance Comparison

Typical compression ratios and speeds (on text data):

| Codec  | Compression Ratio | Speed   | Best For                  |
|--------|------------------|---------|---------------------------|
| none   | 1.0x             | Fastest | Already compressed data   |
| snappy | 2-3x             | Very Fast | Real-time compression   |
| lz4    | 2-3x             | Very Fast | Real-time compression   |
| zlib   | 3-5x             | Medium  | General purpose (default) |
| zstd   | 3-7x             | Fast    | Best ratio/speed tradeoff |
| blosc  | 2-10x            | Fast    | Numerical/scientific data |
| bzip2  | 4-8x             | Slow    | Maximum compression       |

**Recommendation:** Use `:zstd` for most cases - it provides excellent compression with good speed.

## Development Setup Script

Create a file `setup_compression.sh`:

```bash
#!/bin/bash
set -e

echo "Setting up ExZarr compression codecs..."

# Install system libraries
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Installing libraries via Homebrew..."
    brew install zstd lz4 snappy c-blosc bzip2

elif [[ -f /etc/debian_version ]]; then
    echo "Installing libraries via apt..."
    sudo apt-get update
    sudo apt-get install -y libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev

elif [[ -f /etc/redhat-release ]]; then
    echo "Installing libraries via dnf..."
    sudo dnf install -y zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel
fi

# Get Zig for zigler
echo "Installing Zig for zigler..."
mix zig.get

# Compile
echo "Compiling ExZarr with compression codecs..."
mix deps.get
mix compile

echo "✓ Setup complete!"
echo ""
echo "Test codecs with: mix run -e 'IO.inspect(ExZarr.Codecs.available_codecs())'"
```

Make it executable:
```bash
chmod +x setup_compression.sh
./setup_compression.sh
```

## Environment Variables Reference

ExZarr supports the following environment variables for customization:

| Variable | Purpose | Example |
|----------|---------|---------|
| `COMPRESSION_LIB_DIRS` | Custom library directories (colon-separated) | `/custom/lib:/another/lib` |
| `HOMEBREW_PREFIX` | Override Homebrew installation path (macOS) | `/custom/homebrew` |
| `BZIP2_STATIC_LIB` | Custom path to bzip2 static library | `/custom/libbz2.a` |
| `DYLD_FALLBACK_LIBRARY_PATH` | Runtime library search path (macOS) | See above |
| `ZIG_PATH` | Custom Zig installation path | `/custom/zig` |

**Note**: `COMPRESSION_LIB_DIRS`, `HOMEBREW_PREFIX`, and `BZIP2_STATIC_LIB` must be set **before** running `mix compile`, as they affect compilation. `DYLD_FALLBACK_LIBRARY_PATH` is only needed at runtime if automatic rpaths don't work.

## References

- [Zigler Documentation](https://hexdocs.pm/zigler/)
- [ZSTD Documentation](http://facebook.github.io/zstd/)
- [LZ4 Documentation](https://github.com/lz4/lz4)
- [Snappy Documentation](https://github.com/google/snappy)
- [Blosc Documentation](https://www.blosc.org/)
