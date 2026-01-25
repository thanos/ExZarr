# v3 Gzip Format and Codec Configuration Fix

## Issues Fixed

### Issue 1: Gzip Format Mismatch

Python v3 interoperability tests were failing with:
```
"Not a gzipped file (b'x\\x9c')"
```

**Root Cause**: ExZarr's v3 "gzip" codec was producing zlib/deflate format (magic bytes `0x78 0x9C`) instead of true gzip format (magic bytes `0x1F 0x8B`).

**Why This Matters**:
- Zlib format (RFC 1950): Uses deflate compression with a simple header
- Gzip format (RFC 1952): Uses deflate compression with a more complete header including CRC32, timestamps, etc.
- Python's zarr library expects true gzip format when using the "gzip" codec
- The two formats are incompatible - you cannot decompress gzip with a zlib decompressor

### Issue 2: Missing Codec Configuration Key

Python v3 interoperability tests were also failing with:
```
"Named configuration does not have a 'configuration' key. Got {'name': 'gzip'}."
```

**Root Cause**: ExZarr was omitting the `configuration` key from codec specs when the configuration was empty.

**Why This Matters**:
- The Zarr v3 spec requires all codec configurations to have a `configuration` field
- Even if a codec has no configuration options, the field must be present as an empty object
- Python's zarr library validates this strictly

## Fixes Applied

### Fix 1: Use True Gzip Format

**File**: `lib/ex_zarr/codecs/pipeline_v3.ex`

Added two new functions that use Erlang's `:zlib` module with `windowBits = 16 + 15` to produce/read true gzip format:

```elixir
@doc false
defp gzip_compress(data, level) when is_binary(data) do
  z = :zlib.open()
  try do
    # windowBits = 16 + 15 enables gzip format
    # 15 is the max window size, +16 adds gzip wrapper
    :ok = :zlib.deflateInit(z, level, :deflated, 16 + 15, 8, :default)
    compressed = :zlib.deflate(z, data, :finish)
    :ok = :zlib.deflateEnd(z)
    {:ok, IO.iodata_to_binary(compressed)}
  catch
    kind, reason ->
      {:error, {:gzip_compression_failed, {kind, reason}}}
  after
    :zlib.close(z)
  end
end

@doc false
defp gzip_decompress(data) when is_binary(data) do
  z = :zlib.open()
  try do
    # windowBits = 16 + 15 enables gzip format
    :ok = :zlib.inflateInit(z, 16 + 15)
    decompressed = :zlib.inflate(z, data)
    :ok = :zlib.inflateEnd(z)
    {:ok, IO.iodata_to_binary(decompressed)}
  catch
    kind, reason ->
      {:error, {:gzip_decompression_failed, {kind, reason}}}
  after
    :zlib.close(z)
  end
end
```

**Modified** lines 489-491 and 517-519 to call these functions instead of the generic `:zlib` codec.

### Fix 2: Always Include Configuration Key

**File**: `lib/ex_zarr/storage.ex`

Changed the `encode_codecs_v3` function (lines 486-497) to always include the `configuration` key:

**Before**:
```elixir
defp encode_codecs_v3(codecs) when is_list(codecs) do
  Enum.map(codecs, fn codec ->
    case Map.get(codec, :configuration, %{}) do
      config when map_size(config) == 0 ->
        %{name: codec.name}  # ← Missing configuration key!

      config ->
        %{name: codec.name, configuration: config}
    end
  end)
end
```

**After**:
```elixir
defp encode_codecs_v3(codecs) when is_list(codecs) do
  Enum.map(codecs, fn codec ->
    # zarr-python 3.x requires 'configuration' key to always be present
    config = Map.get(codec, :configuration, %{})
    %{name: codec.name, configuration: config}
  end)
end
```

## Verification

### Gzip Format Verification

Test script (`/tmp/test_v3_gzip.exs`) confirms proper gzip format:

```elixir
# Create a simple codec pipeline with gzip
codecs = [
  %{name: "bytes"},
  %{name: "gzip", configuration: %{level: 5}}
]

{:ok, pipeline} = PipelineV3.parse_codecs(codecs)
{:ok, encoded} = PipelineV3.encode(data, pipeline)

# Check gzip magic bytes
<<first, second, _rest::binary>> = encoded
if first == 0x1f and second == 0x8b do
  IO.puts("Correct gzip format (magic bytes 0x1f 0x8b)")
end
```

**Result**: Correct gzip format confirmed

### Python Interoperability Verification

All 16 Python v3 interoperability tests now pass:

```bash
$ mix test --include python_v3 test/ex_zarr_v3_python_interop_test.exs
...
16 tests, 0 failures
```

Tests verify:
- ExZarr can create v3 arrays readable by zarr-python 3.x
- Python can create v3 arrays readable by ExZarr
- Metadata format is compatible
- Codec specifications are correctly formatted
- Gzip compression/decompression works bidirectionally

### Full Test Suite

All existing tests still pass:

```bash
$ mix test
...
76 doctests, 21 properties, 466 tests, 0 failures
```

## Technical Details

### Erlang :zlib windowBits Parameter

The `windowBits` parameter in `:zlib.deflateInit/6` and `:zlib.inflateInit/2` controls the compression format:

| windowBits Value | Format | Magic Bytes | RFC |
|-----------------|--------|-------------|-----|
| `15` | Zlib/Deflate | `0x78 0x9C` | RFC 1950 |
| `16 + 15` | Gzip | `0x1F 0x8B` | RFC 1952 |
| `-15` | Raw Deflate | None | RFC 1951 |

The `+16` modifier adds the gzip wrapper (header + CRC32 trailer) to the deflate stream.

### Zarr v3 Codec Configuration Requirement

From the Zarr v3 specification:

> All named codecs MUST have a `name` field (string) and a `configuration` field (object). The `configuration` field may be an empty object if the codec requires no configuration.

This is a breaking change from earlier Zarr v3 drafts that allowed omitting the `configuration` field.

## Related Files

- `lib/ex_zarr/codecs/pipeline_v3.ex` - Gzip codec implementation
- `lib/ex_zarr/storage.ex` - Metadata encoding with codec specs
- `test/ex_zarr_v3_python_interop_test.exs` - Python compatibility tests
- `test/support/zarr_python_helper.py` - Python helper script

## Impact

These fixes enable full Python interoperability for Zarr v3 arrays:

1. **Gzip Compression**: Arrays compressed with ExZarr's gzip codec can now be read by Python's zarr library
2. **Codec Metadata**: Codec specifications written by ExZarr are now valid according to zarr-python 3.x's strict validation
3. **Bidirectional Compatibility**: ExZarr can both read and write v3 arrays that Python can process

## Testing

To test Python interoperability (requires zarr-python 3.x):

```bash
# Install zarr-python 3.x
pip install 'zarr>=3.0.0' numpy

# Run interoperability tests
mix test --include python_v3 test/ex_zarr_v3_python_interop_test.exs
```

Without zarr-python 3.x installed, these tests are automatically excluded.
