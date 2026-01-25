# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-23

### Added

#### Core Functionality
- **Complete array slicing implementation** with `get_slice` and `set_slice` functions
- **Chunked storage system** for efficient I/O and memory usage
- **N-dimensional array support** (1D to N-D) with optimized implementations for 1D and 2D
- **10 data types**: int8, int16, int32, int64, uint8, uint16, uint32, uint64, float32, float64
- **Compression support**: zlib (fully working), with graceful fallbacks for zstd and lz4
- **Two storage backends**:
  - Memory storage (using Agent for persistent state)
  - Filesystem storage (Zarr v2 directory structure)

#### Validation and Safety
- **Comprehensive index validation** for all slicing operations
- **Bounds checking** to prevent out-of-bounds access
- **Data size validation** ensuring data matches slice dimensions
- **Type validation** for indices and data
- **Clear error messages** with actionable feedback

#### Interoperability
- **Full Zarr v2 specification compliance**
- **Bidirectional compatibility with zarr-python**
- **14 integration tests** verifying Python ↔ Elixir compatibility
- **All data types work across implementations**
- **Metadata format compatibility**

#### Documentation
- Comprehensive module documentation with examples
- `INTEROPERABILITY.md` guide for multi-language workflows
- Interactive demo script (`examples/python_interop_demo.exs`)
- Integration test documentation (`test/support/README.md`)
- Python helper scripts for testing

#### Testing
- **196 tests** covering all functionality
- **21 property-based tests** using StreamData
- **35 validation tests** for bounds checking and error handling
- **19 slicing tests** for read/write operations
- **14 Python integration tests** for cross-language compatibility
- **100% passing** test suite with zero failures

#### Code Quality
- Passes all Credo checks (strict mode)
- Well-documented functions and modules
- Type specifications for public APIs
- Consistent error handling patterns

### Technical Details

#### Array Operations
- Row-major (C-order) data layout
- Lazy chunk loading (only loads needed chunks)
- Efficient slice extraction across chunk boundaries
- Partial chunk updates (read-modify-write)
- Fill value support for uninitialized regions

#### Performance Optimizations
- Dimension-specific implementations (1D, 2D, ND)
- Minimal data copying during operations
- Efficient binary pattern matching
- Agent-based memory storage for fast writes

#### Metadata
- Zarr v2 JSON metadata format
- Shape, chunks, dtype, compressor configuration
- Fill value preservation
- Automatic metadata generation

### Breaking Changes
None (initial release)

### Deprecated
None

### Fixed
- Memory storage now correctly persists writes using Agent
- Chunk boundary calculations work correctly for all dimensions
- Data size validation accounts for element size
- Index validation prevents invalid operations before I/O

### Security
- Input validation prevents buffer overflows
- Bounds checking prevents out-of-bounds access
- Type checking ensures data integrity

## [0.3.0] - 2026-01-24

### Added

#### Compression Codecs - Complete Implementation

**All Major Codecs via Zig NIFs**:
- **zstd** - Zstandard compression (native implementation via Zig NIF + libzstd)
- **lz4** - LZ4 fast compression (native implementation via Zig NIF + liblz4)
- **snappy** - Snappy compression (native implementation via Zig NIF + libsnappy)
- **blosc** - Blosc meta-compressor (native implementation via Zig NIF + libblosc)
- **bzip2** - Bzip2 compression (native implementation via Zig NIF + libbz2)
- **crc32c** - CRC32C checksum codec (pure Zig implementation, RFC 3720 compliant)
- **zlib** - Standard zlib compression (via Erlang `:zlib`, already present in v0.1.0)
- **none** - No compression option

**Codec Features**:
- High-performance native implementations using Zig NIFs
- Full compatibility with Python zarr's compression formats
- CRC32C uses Castagnoli polynomial (0x1EDC6F41) matching RFC 3720 specification
- Corruption detection and validation for CRC32C
- All codecs tested for Python interoperability

#### Custom Codec Plugin System

**Extensible Architecture**:
- **`ExZarr.Codecs.Codec` behavior** - Contract defining codec interface
  - `codec_id/0` - Unique atom identifier
  - `codec_info/0` - Metadata (name, version, type, description)
  - `available?/0` - Runtime availability check
  - `encode/2` - Compression/transformation function
  - `decode/2` - Decompression/inverse transformation
  - `validate_config/1` - Configuration validation

- **`ExZarr.Codecs.Registry` GenServer** - Dynamic codec management
  - Runtime registration: `ExZarr.Codecs.register_codec/2`
  - Runtime unregistration: `ExZarr.Codecs.unregister_codec/1`
  - Codec queries: `list_codecs/0`, `available_codecs/0`, `codec_info/1`
  - Force registration option for codec replacement
  - Protection against unregistering built-in codecs

- **Application supervision tree** - `ExZarr.Application` with supervised registry
  - Fault-tolerant codec registry under supervision
  - Automatic recovery on crashes
  - OTP-compliant architecture

**Plugin Capabilities**:
- Create compression codecs (like zlib, zstd)
- Create transformation codecs (like transpose, shuffle)
- Create checksum codecs (like crc32c)
- Register at runtime without recompiling ExZarr
- Seamless integration with built-in codecs
- Can be chained with other codecs

#### Examples and Documentation

**Example Codecs** (`examples/custom_codec_example.exs`):
- `UppercaseCodec` - Simple transformation codec demonstrating API
- `RleCodec` - Run-length encoding compression codec
- Complete usage demonstration with:
  - Codec registration/unregistration
  - Encoding and decoding operations
  - Querying codec information
  - Chaining custom and built-in codecs

**Documentation Updates**:
- Updated README with "Custom Codecs" section
- Code examples for creating custom codecs
- Usage patterns and best practices
- Updated compression codec list with all implementations
- Updated roadmap to reflect completed features

#### Testing

**Comprehensive Test Coverage**:
- **10 CRC32C tests** - Encoding, decoding, corruption detection, edge cases
- **29 custom codec tests** - Full plugin system coverage including:
  - Behavior validation (`Codec.implements?/1`)
  - Registry operations (register, unregister, list, info)
  - Custom codec compression/decompression
  - Availability checks
  - Integration with built-in codecs
  - Error handling for failing codecs
  - Protection against invalid operations

**Total Test Suite**:
- **238 tests** (up from 196 in v0.1.0)
- **21 property-based tests** with 2,100+ generated test cases
- **100% passing** with 72.5% code coverage
- All codecs verified for Python zarr compatibility

### Changed

**Codec Module Refactoring**:
- Refactored `ExZarr.Codecs` to route through registry
- Split built-in codec logic into `compress_builtin/3` and `decompress_builtin/2`
- Updated `available_codecs/0` to dynamically query registry
- Updated `codec_available?/1` to check registry and call custom codec's `available?/0`
- Changed `@type codec` from fixed atom list to `atom()` for extensibility

**Mix Configuration**:
- Updated `mix.exs` to start `ExZarr.Application` with supervision tree
- Added application module configuration for codec registry initialization

**Documentation**:
- Updated `GAP_ANALYSIS.md` to reflect codec completion (v1.0 → v1.1)
- Updated compression performance comparison
- Updated test statistics
- Updated feature implementation status

### Technical Details

#### CRC32C Implementation
- Pure Zig implementation with 256-entry lookup table
- Castagnoli polynomial: 0x1EDC6F41 (RFC 3720)
- 4-byte overhead in little-endian format
- Compatible with Python zarr's `google-crc32c` library
- Validates data integrity on decode
- Returns error on checksum mismatch

#### Zig NIF Integration
- Uses Zigler 0.13 for seamless Zig-to-Elixir integration
- Automatic memory management via beam.allocator
- Proper error handling with Elixir result tuples `{:ok, data} | {:error, reason}`
- Platform-specific library linking (macOS, Linux)
- Post-compile RPATH fixing for library loading

#### Custom Codec Architecture
- GenServer-based registry pattern following OTP best practices
- ETS table for O(1) codec lookup performance
- Behavior contract ensures consistent codec API
- Support for both `:compression` and `:transformation` codec types
- Validation prevents registering invalid codecs
- Protection prevents unregistering built-in codecs

### Breaking Changes
None - Full backward compatibility maintained

### Deprecated
None

### Fixed
- Removed codec fallbacks - all codecs now have native implementations
- Fixed `available_codecs/0` to return dynamically registered codecs
- Fixed `codec_available?/1` to properly check custom codecs

### Performance
- Native Zig implementations provide significant performance improvements over fallbacks
- CRC32C table-driven algorithm for fast checksum computation
- GenServer registry with ETS backend for fast codec lookups
- Zero-copy binary operations where possible

### Security
- CRC32C detects data corruption and tampering
- Codec validation prevents malformed codec registration
- Input validation on all encode/decode operations
- Protection against unregistering critical built-in codecs

## [0.4.0] - 2026-01-25

### Added

#### Zarr v3 Specification Support
- **Complete Zarr v3 implementation** with full specification compliance
- **Python zarr 3.x interoperability** - bidirectional compatibility verified
- **16 Python v3 integration tests** covering all v3 features
- **Unified codec pipeline** - array→array, array→bytes, bytes→bytes stages
- **v3 metadata format** - `zarr.json` with `node_type`, `data_type`, unified `codecs`
- **v3 chunk key encoding** - slash-separated paths (`c/0/1/2`) with configurable encoding
- **Automatic version detection** - seamlessly works with both v2 and v3 arrays
- **Version-aware array operations** - smart routing based on zarr_format field
- **Group metadata support** - explicit group nodes with v3 format
- **Data type conversion utilities** - automatic mapping between v2 and v3 type systems

#### Python v3 Interoperability Testing
- **Comprehensive test suite** (`test/ex_zarr_v3_python_interop_test.exs`):
  - 7 tests: Python 3.x → ExZarr v3 compatibility
  - 6 tests: ExZarr v3 → Python 3.x compatibility
  - 3 tests: v3 metadata compatibility
  - 2 tests: v3 codec compatibility
- **Enhanced Python helper script** (`test/support/zarr_python_helper.py`):
  - `check_zarr_version()` - Detects zarr-python version
  - `create_v3_array()` - Creates v3 arrays
  - `read_v3_array()` - Reads v3 arrays
  - `verify_v3_array()` - Validates v3 arrays
- **Automatic test exclusion** - Tests tagged with `:python_v3` excluded when zarr-python 3.x not available

#### Documentation
- **`docs/V3_PYTHON_INTEROP.md`** - Comprehensive Python v3 testing guide
- **`docs/V3_PYTHON_INTEROP_FIX.md`** - Metadata save pattern documentation
- **`docs/V3_GZIP_AND_CODEC_CONFIG_FIX.md`** - Gzip format and codec configuration fixes
- **Migration guide** - v2 to v3 conversion patterns (in plan documentation)

### Changed

#### Gzip Codec Implementation
- **Fixed gzip format** - Now produces true gzip format (RFC 1952) with magic bytes `0x1F 0x8B`
- **Previous issue**: Was producing zlib/deflate format (RFC 1950) with magic bytes `0x78 0x9C`
- **New implementation** (`lib/ex_zarr/codecs/pipeline_v3.ex`):
  - `gzip_compress/2` - Uses `:zlib.deflateInit/6` with `windowBits = 16 + 15`
  - `gzip_decompress/1` - Uses `:zlib.inflateInit/2` with `windowBits = 16 + 15`
- **Python compatibility** - Gzip-compressed arrays now readable by zarr-python 3.x

#### Codec Configuration Serialization
- **Always include `configuration` key** in v3 codec specs (required by Zarr v3 spec)
- **Previous issue**: Was omitting `configuration` when empty, causing zarr-python validation errors
- **Fixed in** `lib/ex_zarr/storage.ex` - `encode_codecs_v3/1` function
- **Compliance**: Matches Zarr v3 specification requirement for codec metadata

#### Type Specifications
- **Fixed 12 dialyzer warnings** - Narrowed type specs to match success typing
- **Files updated**:
  - `lib/ex_zarr/codecs/pipeline_v3.ex` - More specific error types
  - `lib/ex_zarr/metadata_v3.ex` - Precise validation error tuples
  - `lib/ex_zarr/data_type.ex` - Specific return types (`1 | 2 | 4 | 8` instead of `pos_integer()`)
  - `lib/ex_zarr/version.ex` - Non-empty list indicators
- **Result**: Zero dialyzer errors

### Fixed

#### Python Interoperability Issues
- **Issue #101**: Python v3 interoperability testing implementation
- **Gzip format mismatch**: Fixed codec to produce RFC 1952 gzip format instead of RFC 1950 zlib
- **Missing configuration key**: Fixed codec metadata to always include `configuration` field
- **Metadata persistence**: Documented requirement for `ExZarr.save/2` after `ExZarr.create/1` for v3 arrays

#### Type System
- **Dialyzer compliance**: All type specifications now match inferred success types
- **More precise error types**: Better error reporting with specific error tuple shapes
- **Better tooling support**: IDE autocomplete and static analysis work correctly

### Technical Details

#### Zarr v3 Architecture
- **Version abstraction layer** (`lib/ex_zarr/version.ex`):
  - `detect_version/1` - Automatic v2/v3 detection from metadata
  - `default_version/0` - Configurable default (v3 by default)
  - `supported_versions/0` - Lists supported versions

- **v3 metadata module** (`lib/ex_zarr/metadata_v3.ex`):
  - Complete v3 metadata struct with validation
  - `node_type` field for array vs group distinction
  - `data_type` string format (e.g., "int32", "float64")
  - `codecs` array with three-stage pipeline
  - `chunk_grid` and `chunk_key_encoding` extensions

- **Chunk key encoding** (`lib/ex_zarr/chunk_key.ex`):
  - v2: dot-separated (e.g., "0.1.2")
  - v3: slash-separated with prefix (e.g., "c/0/1/2")
  - `encode/2` and `decode/2` for version-aware conversion

- **Codec pipeline** (`lib/ex_zarr/codecs/pipeline_v3.ex`):
  - Three-stage pipeline validation and execution
  - Array→array codecs (filters/transforms)
  - Array→bytes codec (required serializer)
  - Bytes→bytes codecs (compression)
  - Strict ordering enforcement per v3 spec

#### Gzip Format Details
- **windowBits parameter** in Erlang's `:zlib`:
  - `15` = Zlib/Deflate format (RFC 1950)
  - `16 + 15` = Gzip format (RFC 1952)
  - `+16` modifier adds gzip wrapper (header + CRC32 trailer)
- **Magic bytes**:
  - Zlib: `0x78 0x9C`
  - Gzip: `0x1F 0x8B`
- **Compatibility**: Gzip format required by zarr-python 3.x

#### Testing
- **Total test count**: **482 tests** (up from 238 in v0.2.0)
- **New v3 tests**: 16 Python interoperability tests
- **Test exclusions**: Python tests automatically excluded without zarr-python 3.x
- **Success rate**: 100% passing (0 failures)
- **Dialyzer**: Zero type errors

### Breaking Changes
None - Full backward compatibility maintained with v2 arrays

### Planned Features
- S3 storage backend
- Parallel chunk operations
- Advanced indexing (fancy indexing, boolean indexing)
- Filter pipeline support (delta, quantize, shuffle)
- Additional codecs (lzma)
- v3 sharding extension
- v3 storage transformers

---

[0.4.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.4.0
[0.3.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.3.0
[0.1.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.1.0
