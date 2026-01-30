# Zarr v3 Support Status

## TL;DR

**ExZarr provides full, production-ready support for Zarr v3.**

Both Zarr v2 and v3 are first-class citizens in ExZarr with complete implementations and automatic version detection.

## Production Status

| Feature | Status | Notes |
|---------|--------|-------|
| **Zarr v3 Core Specification** | Production-ready | Full implementation |
| **Unified Codec Pipeline** | Production-ready | Complete support |
| **v3 Metadata Format** | Production-ready | `zarr.json` with embedded attributes |
| **Hierarchical Chunk Storage** | Production-ready | `c/` directory with slash-separated keys |
| **Automatic Version Detection** | Production-ready | Transparent v2/v3 interoperability |
| **Python Interoperability** | Production-ready | Compatible with zarr-python 3.x |
| **Dimension Names** | Production-ready | Full support |
| **Custom Chunk Grids** | Production-ready | Regular and irregular grids |
| **Sharding Extension** | Supported | Optional v3 extension |

## What This Means

### For New Projects
**Recommended:** Use Zarr v3 as the default for new projects.

```elixir
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/data/my_array"
)
```

### For Existing Projects
- v2 arrays continue to work perfectly
- v3 arrays are fully supported
- Automatic version detection handles both formats
- Gradual migration is straightforward

### For Python Interoperability
- **zarr-python 3.x:** Full interoperability with v3 arrays
- **zarr-python 2.x:** Use v2 format for compatibility
- Both versions are production-ready in ExZarr

## Features Comparison

### Zarr v3 Advantages
- Unified codec pipeline (explicit, configurable)
- Improved metadata format (single `zarr.json` file)
- Better extensibility (built-in extension support)
- Dimension names (semantic axis labels)
- Hierarchical chunk storage (cleaner organization)
- Sharding support (reduce object count in cloud storage)

### Zarr v2 Advantages
- Broader ecosystem compatibility (older tools)
- Maximum compatibility with zarr-python 2.x
- Widely deployed in existing systems

## Implementation Details

### What's Fully Implemented (v3)
- [x] Core v3 specification
- [x] Unified codec pipeline
- [x] v3 metadata format (`zarr.json`)
- [x] Hierarchical chunk keys (`c/0/1/2`)
- [x] Automatic version detection
- [x] Dimension names
- [x] Custom chunk grids
- [x] Array-to-array codecs
- [x] Array-to-bytes codecs
- [x] Bytes-to-bytes codecs
- [x] Groups with v3 format
- [x] Attributes in metadata
- [x] Python zarr-python 3.x interoperability

### Extension Features
- [x] Sharding (optional extension)
- [ ] Variable chunking (future extension)
- [ ] Custom extension support (extensible architecture)

## Version Selection Guide

### Choose Zarr v3 When:
- Starting a new project (recommended default)
- Working with modern Python tools (zarr-python 3.x)
- Need improved metadata organization
- Want unified codec pipeline flexibility
- Require dimension names
- Cloud-native workflows benefiting from sharding

### Choose Zarr v2 When:
- Maximum compatibility with legacy tools required
- Working with older Python codebases (zarr-python 2.x)
- Sharing data with users on older platforms
- Legacy tool compatibility more important than modern features

## Testing and Validation

ExZarr's v3 implementation is validated through:
- **Specification compliance:** Implements zarr-specs v3 specification
- **Python interoperability tests:** Round-trip testing with zarr-python 3.x
- **Property-based tests:** Randomized validation of v3 features
- **Integration tests:** Real-world v3 workflows
- **Compatibility tests:** v2 and v3 coexistence

## Migration Path

v2 to v3 migration is straightforward:

```elixir
# Open existing v2 array
{:ok, v2_array} = ExZarr.open(path: "/data/v2_array")

# Create new v3 array with same data
{:ok, v3_array} = ExZarr.create(
  shape: v2_array.shape,
  chunks: v2_array.chunks,
  dtype: v2_array.dtype,
  codecs: [
    %{name: "bytes"},
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/data/v3_array"
)

# Copy data
{:ok, data} = ExZarr.fetch_all(v2_array)
:ok = ExZarr.store_all(v3_array, data)
```

See [docs/V2_TO_V3_MIGRATION.md](docs/V2_TO_V3_MIGRATION.md) for detailed guidance.

## Frequently Asked Questions

### Is v3 stable enough for production?
**Yes.** ExZarr's v3 implementation is production-ready with comprehensive testing and validation.

### Should I use v3 for new projects?
**Yes.** v3 is the modern standard and recommended for new projects.

### Can I mix v2 and v3 arrays?
**Yes.** ExZarr handles both formats transparently with automatic version detection.

### What about Python compatibility?
**Full compatibility** with zarr-python 3.x for v3 arrays, and zarr-python 2.x for v2 arrays.

### Is v3 faster than v2?
Performance is similar for core operations. v3's sharding extension can significantly reduce cloud storage API calls.

### When will v3 be the default?
v3 is fully supported now. We recommend it for new projects. The default will shift to v3 in a future release once ecosystem adoption increases.

## Resources

- [Zarr v3 Specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/v3.0.html)
- [V2 to V3 Migration Guide](docs/V2_TO_V3_MIGRATION.md)
- [Python Interoperability Guide](guides/python_interop.md)
- [Core Concepts Guide](guides/core_concepts.md)

## Questions or Issues?

If you encounter any v3-related issues or have questions:
- Open an issue: https://github.com/thanos/ExZarr/issues
- Check documentation: https://hexdocs.pm/ex_zarr
- Review examples: `examples/` directory

## Summary

ExZarr's Zarr v3 support is **complete, tested, and production-ready**. Both v2 and v3 are first-class formats with full feature parity and automatic version detection. Use v3 for new projects and enjoy modern Zarr features with confidence.
