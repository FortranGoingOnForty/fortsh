#!/bin/bash
# =====================================
# Fortsh Comprehensive Test Runner
# =====================================
# Runs all test suites with categorization and detailed reporting
# Usage: ./run_all_tests.sh [OPTIONS]
#
# Options:
#   --posix-only     Run only POSIX compliance tests
#   --memory-only    Run only memory pool tests
#   --quick          Run only fast POSIX tests (skip coverage, untested)
#   --verbose        Show detailed output from each test
#   --stop-on-fail   Stop running tests after first failure
#   --help           Show this help message
#
# Exit codes:
#   0: All tests passed
#   1: Some tests failed
#   2: Invalid arguments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
VERBOSE=0
STOP_ON_FAIL=0
RUN_POSIX=1
RUN_MEMORY=0
RUN_INTERACTIVE=0
SKIP_SLOW=0

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --posix-only)
            RUN_POSIX=1
            RUN_MEMORY=0
            RUN_INTERACTIVE=0
            ;;
        --memory-only)
            RUN_POSIX=0
            RUN_MEMORY=1
            RUN_INTERACTIVE=0
            ;;
        --quick)
            SKIP_SLOW=1
            ;;
        --verbose|-v)
            VERBOSE=1
            ;;
        --stop-on-fail)
            STOP_ON_FAIL=1
            ;;
        --all)
            RUN_POSIX=1
            RUN_MEMORY=1
            RUN_INTERACTIVE=0  # Interactive tests require manual interaction
            ;;
        --help|-h)
            head -n 20 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf "${RED}Error: Unknown option: %s${NC}\n" "$arg" >&2
            printf "Use --help for usage information\n" >&2
            exit 2
            ;;
    esac
done

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Find fortsh binary
if [ -n "$FORTSH_BIN" ] && [ -x "$FORTSH_BIN" ]; then
    FORTSH_PATH="$FORTSH_BIN"
elif [ -x "$SCRIPT_DIR/../bin/fortsh" ]; then
    FORTSH_PATH="$SCRIPT_DIR/../bin/fortsh"
elif [ -x "./bin/fortsh" ]; then
    FORTSH_PATH="./bin/fortsh"
else
    printf "${RED}ERROR: fortsh binary not found!${NC}\n"
    printf "Please build fortsh first with 'make' or set FORTSH_BIN\n"
    exit 1
fi

export FORTSH_BIN="$FORTSH_PATH"

# Define test categories
POSIX_CORE_TESTS="
posix_compliance_test.sh
posix_compliance_extended.sh
posix_compliance_builtins.sh
posix_compliance_advanced.sh
posix_compliance_gaps.sh
posix_compliance_jobcontrol.sh
"

POSIX_SLOW_TESTS="
posix_compliance_coverage.sh
posix_compliance_untested.sh
"

MEMORY_TESTS="
memory_pool_test_bench.sh
memory_pool_validation.sh
macos_arm64_pool_checks.sh
"

# Counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0
TOTAL_TESTS_PASSED=0
TOTAL_TESTS_FAILED=0
TOTAL_TESTS_SKIPPED=0

# Array to store failed suite names
FAILED_SUITE_NAMES=""

# Function to run a test suite
run_test_suite() {
    local suite="$1"
    local category="$2"
    local suite_path="$SCRIPT_DIR/$suite"

    if [ ! -f "$suite_path" ]; then
        printf "${YELLOW}⊘ SKIP${NC}: %s (not found)\n" "$suite"
        SKIPPED_SUITES=$((SKIPPED_SUITES + 1))
        return 0
    fi

    if [ ! -x "$suite_path" ]; then
        printf "${YELLOW}⊘ SKIP${NC}: %s (not executable)\n" "$suite"
        SKIPPED_SUITES=$((SKIPPED_SUITES + 1))
        return 0
    fi

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    printf "${BLUE}========================================\n"
    printf "Running: ${BOLD}%s${NC}${BLUE} [%s]\n" "$suite" "$category"
    printf "========================================${NC}\n"

    # Run the test suite and capture output
    local output
    local exit_code

    if [ "$VERBOSE" -eq 1 ]; then
        "$suite_path"
        exit_code=$?
    else
        output=$("$suite_path" 2>&1)
        exit_code=$?
    fi

    # Parse test results from output if not verbose
    if [ "$VERBOSE" -eq 0 ]; then
        # Try to extract test counts from summary
        local passed=$(echo "$output" | grep -i "^Passed:" | tail -1 | awk '{print $2}')
        local failed=$(echo "$output" | grep -i "^Failed:" | tail -1 | awk '{print $2}')
        local skipped=$(echo "$output" | grep -i "^Skipped:" | tail -1 | awk '{print $2}')

        # Accumulate test counts
        if [ -n "$passed" ]; then
            TOTAL_TESTS_PASSED=$((TOTAL_TESTS_PASSED + passed))
        fi
        if [ -n "$failed" ]; then
            TOTAL_TESTS_FAILED=$((TOTAL_TESTS_FAILED + failed))
        fi
        if [ -n "$skipped" ]; then
            TOTAL_TESTS_SKIPPED=$((TOTAL_TESTS_SKIPPED + skipped))
        fi

        # Show summary line
        if [ -n "$passed" ] || [ -n "$failed" ]; then
            printf "  Tests: "
            [ -n "$passed" ] && printf "${GREEN}%d passed${NC}" "$passed"
            [ -n "$failed" ] && [ "$failed" -gt 0 ] && printf " ${RED}%d failed${NC}" "$failed"
            [ -n "$skipped" ] && [ "$skipped" -gt 0 ] && printf " ${YELLOW}%d skipped${NC}" "$skipped"
            printf "\n"
        fi
    fi

    # Check exit code
    if [ "$exit_code" -eq 0 ]; then
        printf "${GREEN}✓ PASSED${NC}: %s\n\n" "$suite"
        PASSED_SUITES=$((PASSED_SUITES + 1))
        return 0
    else
        printf "${RED}✗ FAILED${NC}: %s\n\n" "$suite"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        FAILED_SUITE_NAMES="${FAILED_SUITE_NAMES}  - ${suite}\n"

        # Show last 20 lines of output on failure if not verbose
        if [ "$VERBOSE" -eq 0 ]; then
            printf "${YELLOW}Last 20 lines of output:${NC}\n"
            echo "$output" | tail -20
            printf "\n"
        fi

        if [ "$STOP_ON_FAIL" -eq 1 ]; then
            printf "${RED}Stopping due to --stop-on-fail${NC}\n"
            exit 1
        fi
        return 1
    fi
}

# Print header
printf "${CYAN}╔════════════════════════════════════════╗\n"
printf "║   Fortsh Comprehensive Test Suite     ║\n"
printf "╚════════════════════════════════════════╝${NC}\n"
printf "fortsh binary: ${GREEN}%s${NC}\n" "$FORTSH_BIN"
printf "Test directory: %s\n" "$SCRIPT_DIR"
printf "\n"

# Run POSIX tests
if [ "$RUN_POSIX" -eq 1 ]; then
    printf "${CYAN}${BOLD}══════════════════════════════════════════\n"
    printf "POSIX COMPLIANCE TESTS\n"
    printf "══════════════════════════════════════════${NC}\n\n"

    for suite in $POSIX_CORE_TESTS; do
        run_test_suite "$suite" "POSIX"
    done

    if [ "$SKIP_SLOW" -eq 0 ]; then
        for suite in $POSIX_SLOW_TESTS; do
            run_test_suite "$suite" "POSIX-Extended"
        done
    fi
fi

# Run memory pool tests
if [ "$RUN_MEMORY" -eq 1 ]; then
    printf "${CYAN}${BOLD}══════════════════════════════════════════\n"
    printf "MEMORY POOL TESTS\n"
    printf "══════════════════════════════════════════${NC}\n\n"

    for suite in $MEMORY_TESTS; do
        run_test_suite "$suite" "Memory"
    done
fi

# Print final summary
printf "${CYAN}${BOLD}╔════════════════════════════════════════╗\n"
printf "║          FINAL TEST SUMMARY            ║\n"
printf "╚════════════════════════════════════════╝${NC}\n\n"

printf "${BOLD}Test Suites:${NC}\n"
printf "  Total:   %d\n" "$TOTAL_SUITES"
printf "  ${GREEN}Passed:  %d${NC}\n" "$PASSED_SUITES"
printf "  ${RED}Failed:  %d${NC}\n" "$FAILED_SUITES"
if [ "$SKIPPED_SUITES" -gt 0 ]; then
    printf "  ${YELLOW}Skipped: %d${NC}\n" "$SKIPPED_SUITES"
fi

printf "\n${BOLD}Individual Tests:${NC}\n"
printf "  ${GREEN}Passed:  %d${NC}\n" "$TOTAL_TESTS_PASSED"
printf "  ${RED}Failed:  %d${NC}\n" "$TOTAL_TESTS_FAILED"
if [ "$TOTAL_TESTS_SKIPPED" -gt 0 ]; then
    printf "  ${YELLOW}Skipped: %d${NC}\n" "$TOTAL_TESTS_SKIPPED"
fi

# Calculate totals
TOTAL_INDIVIDUAL=$((TOTAL_TESTS_PASSED + TOTAL_TESTS_FAILED + TOTAL_TESTS_SKIPPED))
if [ "$TOTAL_INDIVIDUAL" -gt 0 ]; then
    PASS_RATE=$((TOTAL_TESTS_PASSED * 100 / TOTAL_INDIVIDUAL))
    printf "  Pass rate: ${BOLD}%d%%${NC}\n" "$PASS_RATE"
fi

# List failed suites if any
if [ "$FAILED_SUITES" -gt 0 ]; then
    printf "\n${RED}${BOLD}Failed test suites:${NC}\n"
    printf "%b" "$FAILED_SUITE_NAMES"
fi

printf "\n${CYAN}════════════════════════════════════════${NC}\n"

# Exit with appropriate code
if [ "$FAILED_SUITES" -eq 0 ] && [ "$TOTAL_SUITES" -gt 0 ]; then
    printf "${GREEN}${BOLD}✓ ALL TEST SUITES PASSED!${NC}\n"
    exit 0
else
    printf "${RED}${BOLD}✗ SOME TEST SUITES FAILED${NC}\n"
    exit 1
fi
