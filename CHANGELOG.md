# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-27

### First Stable Release!

ExZarr 1.0.0 marks the first production-ready release with comprehensive testing, security hardening, and extensive documentation.

### Added

#### Testing & Quality Assurance
- **Comprehensive Test Suite**: 1,713 total tests (146 doctests + 65 properties + 1,502 unit tests)
  - Zero test failures across all test suites
  - 4 tests intentionally skipped for environment-specific features
  - 151 tests excluded (cloud storage backends requiring credentials)
- **Property-Based Testing**: Expanded from 21 to 65 properties
  - New `test/ex_zarr_codecs_property_test.exs` with 19 codec-focused properties
  - Enhanced `test/ex_zarr_property_test.exs` with 25 additional properties
  - Comprehensive coverage of compression, indexing, storage, and metadata operations
- **Backend Test Coverage**: New comprehensive test files
  - `test/ex_zarr/storage_comprehensive_test.exs` - 39 tests for storage operations
  - `test/ex_zarr/storage/backend/filesystem_test.exs` - 41 tests (82% coverage)
  - `test/ex_zarr/storage/backend/zip_test.exs` - 40 tests (95.2% coverage)
  - `test/mix/tasks/fix_nif_rpaths_test.exs` - 14 tests for Mix task
- **Core Module Coverage**: Significantly improved test coverage
  - `format_converter.ex`: 20% → 80% (+60 percentage points, 36 tests)
  - `indexing.ex`: 12.1% → 85.1% (+73pp, 69 tests)
  - `metadata.ex`: 59.1% → 79.5% (+20pp, 56 tests)
  - `storage.ex`: ~29% → 68.1% (+39pp, 39 tests)
  - `filesystem.ex`: 0% → 82% (+82pp, 41 tests)
  - `zip.ex`: 66.6% → 95.2% (+29pp, 40 tests)
- **Overall Coverage**: 80.3% (up from 76.3%), with 100% coverage on 6 critical modules

#### Security & Documentation
- **Security Policy**: Comprehensive `SECURITY.md` with 550+ lines
  - Vulnerability reporting process and timelines
  - Input validation best practices with code examples
  - Cloud authentication security patterns
  - Path traversal prevention guidelines
  - Resource limit recommendations
  - Security checklist for production deployments
- **Sobelow Integration**: Static security analysis configured
  - `.sobelow-conf` configuration file with documented exceptions
  - All high/medium confidence warnings resolved
  - 45 low-confidence warnings documented as expected behavior
  - Detailed explanation of file traversal, String.to_atom, and configuration warnings
- **Enhanced Error Handling Guide**: `guides/error_handling.md`
  - Comprehensive error handling patterns
  - Recovery strategies for common failures
  - Circuit breaker and retry patterns
  - Logging and debugging recommendations
- **Telemetry Guide**: `guides/telemetry.md`
  - Complete instrumentation documentation
  - Integration examples for monitoring systems
  - Performance metrics and event tracking

#### Code Quality
- **Zero Compilation Warnings**: Clean compilation across all environments
- **Credo Grade A+**: Strict mode with 0 issues (1,396 mods/funs analyzed)
- **Dialyzer Passing**: All type specs validated, 14 known issues properly suppressed
- **Documentation Coverage**:
  - Zero `mix docs` warnings
  - All public functions have `@doc` annotations
  - All modules have `@moduledoc` annotations
  - Comprehensive guides in `guides/` directory

### Changed

#### API Stability
- **Semantic Versioning Commitment**: v1.0.0 marks API stability
  - No breaking changes planned for 1.x series
  - Deprecation warnings will be added for any future API changes
  - At least one minor version deprecation period before removal
- **Dependency Versions**: Updated to stable releases
  - `:telemetry` added for observability support
  - All dependencies pinned to stable versions

### Fixed

#### Test Stability
- Fixed metadata tests to include required `fill_value` field
- Fixed storage tests to handle mock backend registration idempotency
- Fixed property tests to only test public API functions
- Corrected filter metadata encoding to include both `dtype` and `astype` fields

#### Documentation
- Fixed all relative path references in guides
- Corrected README.md installation instructions
- Updated all version references to 1.0.0

### Testing Metrics

**Test Suite Performance**
- Total execution time: ~5.8 seconds
- Async tests: 3.4 seconds
- Sync tests: 2.4 seconds
- All tests: 100% passing rate

**Code Coverage by Module**
- 100% coverage: `ex_zarr.ex`, `application.ex`, `chunk_cache.ex`, `version.ex`, `storage/backend.ex`, `codecs/codec.ex`
- >90% coverage: `chunk_key.ex` (96%), `storage/backend/zip.ex` (95.2%), `codecs/sharding_indexed.ex` (93.9%), `array_server.ex` (93%), `memory.ex` (90.9%)
- >80% coverage: 15 additional modules
- Overall project: 80.3%

### Security

**Vulnerability Status**: No security vulnerabilities reported or discovered

**Security Hardening**
- Comprehensive path validation examples
- Safe usage patterns for all file operations
- Secure cloud storage authentication patterns
- Input sanitization guidelines
- Resource limit recommendations
- Documented DoS prevention strategies

**Static Analysis Results** (Sobelow)
- 0 high confidence warnings
- 0 medium confidence warnings
- 45 low confidence warnings (all documented as expected for data storage library)

### Breaking Changes

None. This is the first stable release, establishing the baseline API.

### Deprecations

None.

### Migration Guide

For users upgrading from v0.7.0:
1. Update dependency in `mix.exs`: `{:ex_zarr, "~> 1.0"}`
2. Run `mix deps.get`
3. No code changes required - full backward compatibility maintained

### Contributors

Special thanks to all contributors who made v1.0.0 possible through testing, feedback, and code contributions.

### Looking Forward

Planned for v1.1.0:
- Additional cloud storage backend optimizations
- Enhanced v3 format support
- Performance improvements for large arrays
- Additional convenience functions for common patterns

---

## [0.7.0] - 2026-01-26

### Added

#### Chunk Streaming and Parallel Processing
- `Array.chunk_stream/2` - Stream chunks lazily with constant memory usage
  - Sequential mode using `Stream.resource` for truly lazy evaluation
  - Parallel mode with configurable concurrency (max 10 workers)
  - Progress callback support for monitoring long operations
  - Filter option to process subset of chunks
  - Ordered and unordered streaming modes
- `Array.parallel_chunk_map/3` - Process chunks in parallel with custom mapper function
  - Configurable concurrency and timeout
  - Automatic error handling for failed tasks
  - Integration with existing chunk cache and locking mechanisms

#### Custom Chunk Key Encoding
- `ChunkKey.Encoder` behavior - Define custom chunk naming schemes
  - `encode/2` callback - Convert chunk index to string key
  - `decode/2` callback - Parse string key back to chunk index
  - `pattern/1` callback - Provide regex for key validation
- `ChunkKey.V2Encoder` and `ChunkKey.V3Encoder` - Default encoder implementations
- `ChunkKey.Registry` - Runtime encoder registration with Agent
- `ChunkKey.register_encoder/2` - Register custom encoders by name
- `ChunkKey.encode_with/3` and `decode_with/3` - Use registered encoders
- Centralized chunk key logic in S3 and GCS backends

#### Group Convenience Features
- Access behavior implementation - Use bracket notation for path-based access
  - `group["experiments/exp1/results"]` syntax support
  - Automatic intermediate group creation on write
  - Works with `get_in`, `put_in`, `update_in` functions
- `Group.get_item/2` - Lazy load arrays and groups from storage
  - Path-based access with forward slash separator
  - Caches loaded items in memory
  - Tracks checked paths to avoid redundant storage queries
- `Group.put_item/3` - Add items with auto-creation of parent groups
- `Group.remove_item/2` - Remove items from in-memory structure
- `Group.require_group/2` - Create group hierarchy like mkdir -p
  - Returns existing group if present
  - Creates all intermediate groups
  - Returns error if path conflicts with array
- `Group.tree/2` - ASCII tree visualization of group hierarchy
  - Box-drawing characters for structure (├── └──)
  - Array [A] and group [G] markers
  - Optional depth limiting
  - Optional shape display
- `Group.batch_create/2` - Create multiple groups/arrays in parallel
  - Concurrent metadata writes for cloud storage efficiency
  - Mixed group and array creation support
  - Up to 10 concurrent operations

### Fixed

#### Type Safety
- Fixed unmatched return value in `Array.chunk_stream` lock acquisition
- Fixed `ChunkCache.put` argument order in streaming code
- All dialyzer warnings resolved

#### Test Stability
- Memory efficiency test now uses sequential streaming for consistent results
  - Changed from parallel to sequential mode
  - Increased threshold to account for OTP version variance
  - Uses `Enum.reduce` for truly lazy processing
- ArrayServer FIFO queue test uses staggered delays to ensure reliable ordering
  - Added task-specific delays to guarantee queue order
  - Uses Agent to track actual acquisition order
  - Prevents race conditions in CI environments

#### Path Handling
- Fixed `Group.create_group/3` to use correct storage path
- Fixed `Group.create_array/3` to properly join storage path with array path
- Corrected filesystem metadata file locations

### Changed

#### Storage Backend Refactoring
- S3 and GCS backends now use centralized `ChunkKey.encode` function
- Eliminated duplicate chunk key encoding logic
- Simplified pattern matching with `ChunkKey.chunk_key_pattern`

#### Group Structure
- Added `_loaded` field to Group struct for lazy loading cache
- Type specification updated to include MapSet for loaded paths

### Testing

**Test Coverage**
- Total tests: 1246 (up from 794 in v0.5.0)
- New chunk streaming tests: 12 tests
- New chunk key encoding tests: 32 tests
- New group convenience tests: 37 tests
- Success rate: 100% passing (0 failures, 6 skipped)
- Quality checks: All passing (dialyzer, format checks)

**Test Files**
- `test/ex_zarr/chunk_streaming_test.exs` - Chunk iteration and parallel processing
- `test/ex_zarr/chunk_key_encoding_test.exs` - Custom encoder behavior and registry
- `test/ex_zarr/group_convenience_test.exs` - Group access and convenience features

## [0.5.0] - 2026-01-25

### Added

#### Metadata Serialization and Deserialization
- **Complete JSON encoding/decoding for Zarr v3 metadata**
  - `MetadataV3.to_json/1` - Serialize metadata structures to JSON strings
  - `MetadataV3.from_json/1` - Parse JSON to MetadataV3 structures
  - Full support for chunk grids (regular and irregular)
  - Full support for codec pipeline encoding (nested configurations)
  - Full support for dimension names and storage transformers
  - 54 new tests covering JSON serialization and zarr-python 3.x file compatibility

#### Format Conversion
- **Bidirectional conversion between Zarr v2 and v3 formats**
  - `MetadataV3.from_v2/1` - Convert v2 metadata to v3 format
  - `MetadataV3.to_v2/1` - Convert v3 metadata to v2 format (with validation)
  - `ExZarr.FormatConverter` module - Convert entire arrays between formats
  - `FormatConverter.convert/1` - Copy arrays with proper chunk key encoding
  - `FormatConverter.check_v2_compatibility/1` - Pre-validate v3→v2 conversion
  - Automatic handling of codec pipeline differences
  - Clear error messages for incompatible features (sharding, irregular grids)
  - 18 conversion tests including round-trip verification

#### S3 Storage Backend Enhancements
- **Localstack and minio support for local testing**
  - Custom endpoint URL configuration
  - Automatic parsing of `AWS_ENDPOINT_URL` environment variable
  - ExAws configuration for S3-compatible services (scheme, host, port)
  - 45 mock tests using Mox for fast CI/CD testing without AWS
  - 31 integration tests with full localstack support
  - Comprehensive testing guide (`test/ex_zarr/storage/S3_TESTING.md`)
  - Example usage script (`examples/s3_storage.exs`)

#### Dependencies
- **sweet_xml ~> 0.7** - Required for ExAws.S3 XML parsing

### Fixed

#### Type Specifications
- **MetadataV3.from_v2/1 return type** - Removed unreachable `{:error, term()}` case
  - Function always succeeds with v2 metadata input
  - Updated spec to match success typing: `{:ok, t()}`

#### S3 Backend Configuration
- **ExAws configuration for S3-compatible services**
  - Fixed endpoint URL parsing from single string to ExAws format
  - Corrected credential handling for localstack/minio
  - Fixed `build_ex_aws_config/2` to parse URI components properly
  - Resolved test setup issues with ExUnit callback return values

### Changed

#### Test Organization
- **S3 integration tests** now properly skip when `AWS_ENDPOINT_URL` not configured
- **setup_all callback** returns proper values for ExUnit compatibility
- **Mock tests** run independently without requiring AWS services

#### Documentation
- **Updated S3 backend moduledoc** with localstack/minio configuration
- **Created S3_TESTING.md** with complete setup and troubleshooting guide
- **Updated examples** with S3 endpoint URL usage patterns

### Testing

**Test Coverage**
- **Total tests**: 794 (up from 482 in v0.4.0)
- **S3 mock tests**: 45 tests
- **S3 integration tests**: 31 tests
- **Format conversion tests**: 18 tests
- **JSON serialization tests**: 54 tests
- **Success rate**: 100% passing (0 failures, 3 skipped)
- **Quality checks**: All passing (format, credo strict, dialyzer)

### Technical Details

#### Format Conversion Limitations
- **v3 → v2 conversion** has known limitations detected by validation:
  - Sharding codec not supported in v2 (rejected with clear error)
  - Dimension names lost in conversion (documented)
  - Irregular chunk grids not supported in v2 (rejected with clear error)
  - Array→array codecs (transpose, quantize, bitround) dropped
- **v2 → v3 conversion** fully supported without limitations

#### S3 Configuration
- **Endpoint URL parsing** converts HTTP URL to ExAws format:
  - `http://localhost:4566` → `scheme: "http://", host: "localhost", port: 4566`
  - Credentials from environment: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
  - Region configuration: default `us-east-1` or specified
- **Backward compatible** - works with real AWS S3 when endpoint not specified

### Breaking Changes
None - Full backward compatibility maintained with v0.1.0, v0.3.0, and v0.4.0

---

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

[0.5.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.5.0
[0.4.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.4.0
[0.3.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.3.0
[0.1.0]: https://github.com/thanos/ex_zarr/releases/tag/v0.1.0
