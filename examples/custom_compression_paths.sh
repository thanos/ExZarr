#!/bin/bash
# Example: Using custom compression library paths
#
# This script demonstrates how to compile ExZarr with custom
# compression library paths using environment variables.

echo "=== Custom Compression Library Paths Example ==="
echo ""

# Example 1: Custom library directories
echo "Example 1: Setting custom library directories"
echo "export COMPRESSION_LIB_DIRS=\"/custom/lib:/another/lib\""
export COMPRESSION_LIB_DIRS="/custom/lib:/another/lib"
mix run -e "IO.inspect(ExZarr.Codecs.CompressionConfig.library_dirs())"
echo ""

# Example 2: Custom Homebrew prefix
unset COMPRESSION_LIB_DIRS
echo "Example 2: Setting custom Homebrew prefix"
echo "export HOMEBREW_PREFIX=\"/custom/homebrew\""
export HOMEBREW_PREFIX="/custom/homebrew"
mix run -e "IO.inspect(ExZarr.Codecs.CompressionConfig.homebrew_prefix())"
echo ""

# Example 3: Custom bzip2 static library
unset HOMEBREW_PREFIX
echo "Example 3: Setting custom bzip2 static library"
echo "export BZIP2_STATIC_LIB=\"/custom/path/libbz2.a\""
export BZIP2_STATIC_LIB="/custom/path/libbz2.a"
mix run -e "IO.inspect(ExZarr.Codecs.CompressionConfig.bzip2_static_lib())"
echo ""

# Reset
unset BZIP2_STATIC_LIB
echo "Example 4: Auto-detection (no environment variables)"
mix run -e "IO.inspect(ExZarr.Codecs.CompressionConfig.library_dirs())"
echo ""

echo "=== To use custom paths for compilation ==="
echo "1. Set environment variables BEFORE running 'mix compile'"
echo "2. Clean and recompile: rm -rf _build && mix compile"
echo "3. The new paths will be embedded in the compiled NIF"
