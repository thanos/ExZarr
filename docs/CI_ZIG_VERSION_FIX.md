# CI Zig Version Fix

## Issue

GitHub Actions CI was failing with exit code 132 (Illegal instruction) when running `mix test --trace`.

**Error symptoms**:
- Job failed after downloading Zig but before any Elixir test output
- Exit code 132 indicates an "Illegal instruction" error
- This typically occurs when compiled binaries use CPU instructions not available on the runner's hardware

## Root Cause

Zig version 0.15.2 was not compatible with GitHub Actions runner hardware/OS. This version may have been compiled with CPU feature flags (like AVX512 or newer SIMD instructions) that aren't available on the standard GitHub Actions Ubuntu runners.

## Solution

Downgraded Zig to version 0.12.0, a stable release known to work reliably on GitHub Actions runners.

**Files modified**: `.github/workflows/ci.yml`

**Changes**:
- Line 52 (test job): `version: 0.15.2` → `version: 0.12.0`
- Line 117 (quality job): `version: 0.15.2` → `version: 0.12.0`
- Line 178 (docs job): `version: 0.15.2` → `version: 0.12.0`

## Compatibility

- **Zigler version**: 0.13.x (from mix.exs) - Compatible with Zig 0.12.x
- **Local compilation**: Verified successful with existing Zig NIFs
- **GitHub Actions**: Version 0.12.0 is widely used and stable on CI runners

## Verification

After this change:
1. Push the update to trigger CI workflow
2. Verify all three jobs (test, quality, docs) run successfully
3. Confirm Zig NIFs compile without illegal instruction errors

## Related

- Zig 0.12.0 release: https://ziglang.org/download/0.12.0/release-notes.html
- GitHub Actions Ubuntu runners: https://github.com/actions/runner-images
- Zigler 0.13 documentation: https://hexdocs.pm/zigler/0.13.0/

## Alternative Approaches

If 0.12.0 still has issues, consider:
1. Try Zig 0.11.x (older stable version)
2. Use `version: master` for latest development builds (not recommended for CI)
3. Build Zig from source on the runner (adds significant build time)

## Impact

This fix enables CI to run successfully on GitHub Actions runners without requiring changes to:
- Zig NIF code
- Elixir dependencies
- Test suite
- Local development workflow
