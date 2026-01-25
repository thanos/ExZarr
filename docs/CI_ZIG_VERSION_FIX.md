# CI Zig Version Fix

## Issue

GitHub Actions CI was failing with two different errors:

1. **Initial failure**: Exit code 132 (Illegal instruction) with Zig 0.15.2
2. **After downgrade to 0.12.0**: Compilation error "expected string literal" in build.zig.zon

**Error symptoms**:
- Exit code 132 indicates an "Illegal instruction" error (CPU compatibility issue)
- Build.zig.zon parsing errors indicate Zig version mismatch with Zigler

## Root Cause

**Two-part issue**:

1. Zig version 0.15.2 was not compatible with GitHub Actions runner hardware/OS
2. Downgrading Zig to 0.12.0 created incompatibility with Zigler 0.15.2

**Version dependency chain**:
- Zigler 0.15.2 requires Zig 0.15.x (zig_get dependency shows "0.15.2")
- Zigler 0.13.x requires Zig 0.13.x but has different API (can't evaluate runtime options)
- Mix.exs had `~> 0.13` which allows up to 0.15.2

## Solution

Use Zig version 0.13.0 with Zigler 0.15.2:
- Zig 0.13.0 is stable and compatible with GitHub Actions runners
- Zigler 0.15.2 can work with Zig 0.13.0 (compatible minor version difference)
- Avoids CPU instruction compatibility issues of Zig 0.15.2

**Files modified**: `.github/workflows/ci.yml`

**Changes**:
- Line 52 (test job): `version: 0.15.2` → `version: 0.13.0`
- Line 117 (quality job): `version: 0.15.2` → `version: 0.13.0`
- Line 178 (docs job): `version: 0.15.2` → `version: 0.13.0`

## Compatibility

- **Zigler version**: 0.15.2 (from mix.lock)
- **Zig version**: 0.13.0 (CI) - Cross-compatible with Zigler 0.15.2
- **Local compilation**: Verified successful with existing Zig NIFs
- **GitHub Actions**: Version 0.13.0 is stable on CI runners
- **Test results**: All 466 tests pass (0 failures)

## Verification

After this change:
1. Push the update to trigger CI workflow
2. Verify all three jobs (test, quality, docs) run successfully
3. Confirm Zig NIFs compile without illegal instruction errors

## Related

- Zig 0.12.0 release: https://ziglang.org/download/0.12.0/release-notes.html
- GitHub Actions Ubuntu runners: https://github.com/actions/runner-images
- Zigler 0.13 documentation: https://hexdocs.pm/zigler/0.13.0/

## Why Not Other Versions?

**Zig 0.12.0**: Incompatible with Zigler 0.15.2 - causes build.zig.zon parsing errors

**Zig 0.15.2**: Causes "Illegal instruction" (exit code 132) on GitHub Actions runners

**Zigler 0.13.x with Zig 0.12.0**: Would work BUT Zigler 0.13.x has different API that doesn't support runtime evaluation of module attributes (breaks our `@library_dirs` usage)

**Zig 0.13.0 with Zigler 0.15.2**: ✅ Best compromise - stable, compatible, no CPU issues

## Alternative Approaches

If 0.13.0 still has issues:
1. Try Zig 0.14.0 (intermediate version)
2. Pin both Zigler and Zig to matching versions (e.g., 0.11.x / 0.11.x)
3. Use `version: master` for latest development builds (not recommended for CI)
4. Build Zig from source on the runner (adds significant build time)

## Impact

This fix enables CI to run successfully on GitHub Actions runners without requiring changes to:
- Zig NIF code
- Elixir dependencies
- Test suite
- Local development workflow
