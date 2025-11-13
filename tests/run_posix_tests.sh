#!/bin/sh
# =====================================
# POSIX Compliance Test Runner
# =====================================
# Runs all POSIX compliance test suites for fortsh
# Automatically detects fortsh binary location

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Find fortsh binary - check multiple locations
if [ -n "$FORTSH_BIN" ] && [ -x "$FORTSH_BIN" ]; then
    # Use environment variable if set
    FORTSH_PATH="$FORTSH_BIN"
elif [ -x "$SCRIPT_DIR/../bin/fortsh" ]; then
    # Look in ../bin/fortsh (relative to tests/)
    FORTSH_PATH="$SCRIPT_DIR/../bin/fortsh"
elif [ -x "./bin/fortsh" ]; then
    # Look in ./bin/fortsh (from project root)
    FORTSH_PATH="./bin/fortsh"
elif [ -x "$(pwd)/bin/fortsh" ]; then
    # Look in current working directory
    FORTSH_PATH="$(pwd)/bin/fortsh"
else
    printf "${RED}ERROR: fortsh binary not found!${NC}\n"
    printf "Searched locations:\n"
    printf "  - FORTSH_BIN environment variable\n"
    printf "  - %s/bin/fortsh\n" "$SCRIPT_DIR/.."
    printf "  - ./bin/fortsh\n"
    printf "  - $(pwd)/bin/fortsh\n"
    printf "\nPlease build fortsh first with 'make' or set FORTSH_BIN\n"
    exit 1
fi

export FORTSH_BIN="$FORTSH_PATH"

# Test suite files
TEST_SUITES="
posix_compliance_test.sh
posix_compliance_extended.sh
posix_compliance_builtins.sh
posix_compliance_advanced.sh
posix_compliance_gaps.sh
"

# Print header
printf "${CYAN}========================================\n"
printf "POSIX Compliance Test Suite Runner\n"
printf "========================================${NC}\n"
printf "fortsh binary: ${GREEN}%s${NC}\n" "$FORTSH_BIN"
printf "Test directory: %s\n" "$SCRIPT_DIR"
printf "\n"

# Counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
TOTAL_TESTS=0

# Run each test suite
for suite in $TEST_SUITES; do
    suite_path="$SCRIPT_DIR/$suite"

    if [ ! -f "$suite_path" ]; then
        printf "${YELLOW}⊘ SKIP${NC}: %s (not found)\n" "$suite"
        continue
    fi

    if [ ! -x "$suite_path" ]; then
        printf "${YELLOW}⊘ SKIP${NC}: %s (not executable)\n" "$suite"
        continue
    fi

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    printf "${BLUE}========================================\n"
    printf "Running: %s\n" "$suite"
    printf "========================================${NC}\n"

    # Run the test suite
    if "$suite_path"; then
        printf "${GREEN}✓ PASSED${NC}: %s\n\n" "$suite"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        printf "${RED}✗ FAILED${NC}: %s\n\n" "$suite"
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
done

# Print summary
printf "${CYAN}========================================\n"
printf "OVERALL SUMMARY\n"
printf "========================================${NC}\n"
printf "Total test suites: %d\n" "$TOTAL_SUITES"
printf "${GREEN}Passed suites:     %d${NC}\n" "$PASSED_SUITES"
printf "${RED}Failed suites:     %d${NC}\n" "$FAILED_SUITES"
printf "${CYAN}========================================${NC}\n"

if [ "$FAILED_SUITES" -eq 0 ] && [ "$TOTAL_SUITES" -gt 0 ]; then
    printf "${GREEN}\n✓ ALL TEST SUITES PASSED!\n${NC}"
    exit 0
else
    printf "${RED}\n✗ SOME TEST SUITES FAILED\n${NC}"
    exit 1
fi
