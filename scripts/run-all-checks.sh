#!/usr/bin/env bash
#
# Run all CI checks locally without GitHub Actions
# This script mimics the CI pipeline defined in .github/workflows/ci.yml
#
# Usage:
#   ./scripts/run-all-checks.sh           # Run all checks
#   ./scripts/run-all-checks.sh --fast    # Skip slow checks (dialyzer, coverage)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Options
FAST_MODE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --fast)
            FAST_MODE=true
            shift
            ;;
        *)
            ;;
    esac
done

# Function to run a check
run_check() {
    local name="$1"
    local command="$2"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Running: ${name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if eval "$command"; then
        echo -e "${GREEN}✓ ${name} passed${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ ${name} failed${NC}"
        ((FAILED++))
        return 1
    fi
}

# Function to skip a check
skip_check() {
    local name="$1"
    local reason="$2"

    echo ""
    echo -e "${CYAN}⊘ ${name} skipped${NC}"
    if [ -n "$reason" ]; then
        echo -e "${CYAN}  Reason: ${reason}${NC}"
    fi
    ((SKIPPED++))
}

# Print header
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║                                                        ║"
echo "║            ExZarr CI Checks - Local Run               ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Change to project root
cd "$(dirname "$0")/.."

echo -e "${YELLOW}Project: ExZarr${NC}"
echo -e "${YELLOW}Location: $(pwd)${NC}"
echo -e "${YELLOW}Mode: $([ "$FAST_MODE" = true ] && echo "Fast (skipping slow checks)" || echo "Full")${NC}"
echo ""

# Check for required system libraries
echo -e "${CYAN}Checking system dependencies...${NC}"
missing_deps=()

if ! command -v pkg-config &> /dev/null; then
    echo -e "${YELLOW}Warning: pkg-config not found${NC}"
fi

for lib in zstd lz4 snappy blosc bz2; do
    case "$OSTYPE" in
        darwin*)
            # macOS - check homebrew
            if [ "$lib" = "blosc" ]; then
                lib_path="/opt/homebrew/opt/c-blosc"
            elif [ "$lib" = "bz2" ]; then
                lib_path="/opt/homebrew/opt/bzip2"
            else
                lib_path="/opt/homebrew/opt/$lib"
            fi

            if [ ! -d "$lib_path" ]; then
                missing_deps+=("$lib")
            fi
            ;;
        linux*)
            # Linux - check pkg-config
            if command -v pkg-config &> /dev/null; then
                pkg_name="$lib"
                [ "$lib" = "blosc" ] && pkg_name="libblosc"
                [ "$lib" = "bz2" ] && pkg_name="bzip2"

                if ! pkg-config --exists "$pkg_name" 2>/dev/null; then
                    missing_deps+=("$lib")
                fi
            fi
            ;;
    esac
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "${RED}Missing system libraries: ${missing_deps[*]}${NC}"
    echo ""
    case "$OSTYPE" in
        darwin*)
            echo -e "${YELLOW}Install with: brew install zstd lz4 snappy c-blosc bzip2${NC}"
            ;;
        linux*)
            echo -e "${YELLOW}Install with: sudo apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev${NC}"
            ;;
    esac
    echo ""
    exit 1
fi

echo -e "${GREEN}All system dependencies found${NC}"
echo ""

# Install dependencies if needed
if [ ! -d "deps" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    mix deps.get
fi

# Compile dependencies
echo -e "${YELLOW}Compiling dependencies...${NC}"
mix deps.compile

# Test Job Checks
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           TEST JOB CHECKS                             ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"

# 1. Format check
run_check "Format check" \
    "mix format --check-formatted"

# 2. Compilation with warnings as errors
run_check "Compile (warnings as errors)" \
    "MIX_ENV=test mix compile --warnings-as-errors --force"

# 3. Tests
run_check "Unit tests" \
    "mix test --trace"

# 4. Coverage (skip in fast mode)
if [ "$FAST_MODE" = true ]; then
    skip_check "Test coverage" "fast mode enabled"
else
    if command -v mix coveralls &> /dev/null || mix help coveralls &> /dev/null 2>&1; then
        run_check "Test coverage" \
            "mix coveralls.html"
    else
        skip_check "Test coverage" "excoveralls not installed"
    fi
fi

# Quality Job Checks
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           QUALITY JOB CHECKS                          ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"

# 5. Credo
if command -v mix credo &> /dev/null || mix help credo &> /dev/null 2>&1; then
    run_check "Credo (code quality)" \
        "mix credo --strict"
else
    skip_check "Credo" "not installed"
fi

# 6. Dialyzer (skip in fast mode or if PLT doesn't exist)
if [ "$FAST_MODE" = true ]; then
    skip_check "Dialyzer (type checking)" "fast mode enabled"
elif [ -f "priv/plts/dialyzer.plt" ] || [ -f "_build/dev/*.plt" ]; then
    run_check "Dialyzer (type checking)" \
        "mix dialyzer --format github"
else
    skip_check "Dialyzer" "PLT not built. Run: mix dialyzer --plt"
fi

# Documentation Job Checks
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           DOCUMENTATION JOB CHECKS                    ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"

# 7. Documentation generation
run_check "Generate documentation" \
    "MIX_ENV=dev mix docs"

# 8. Documentation coverage
run_check "Documentation warnings check" \
    "MIX_ENV=dev mix docs --warnings-as-errors"

# Print summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SUMMARY                            ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Passed:  ${PASSED}${NC}"
echo -e "${RED}Failed:  ${FAILED}${NC}"
echo -e "${CYAN}Skipped: ${SKIPPED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║                 ALL CHECKS PASSED!                     ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                        ║${NC}"
    echo -e "${RED}║              SOME CHECKS FAILED!                       ║${NC}"
    echo -e "${RED}║                                                        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
