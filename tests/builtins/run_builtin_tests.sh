#!/bin/sh
# =====================================
# Fortsh Builtin Test Runner
# =====================================
# Runs all individual builtin test suites and aggregates results.
# Can be called standalone or from the main run_all_tests.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../bin/fortsh}"
export FORTSH_BIN

if [ ! -x "$FORTSH_BIN" ]; then
    printf "${RED}ERROR${NC}: fortsh binary not found at %s\n" "$FORTSH_BIN"
    printf "Please run 'make' first or set FORTSH_BIN environment variable\n"
    exit 1
fi

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
SUITES_PASSED=0
SUITES_FAILED=0
FAILED_SUITES=""

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [ ! -x "$test_file" ] && continue
    suite_name=$(basename "$test_file")
    # Skip the shared harness
    [ "$suite_name" = "test_harness.sh" ] && continue

    if [ "$VERBOSE" -eq 1 ]; then
        printf "\n${CYAN}── %s ──${NC}\n" "$suite_name"
        output=$(timeout 120 "$test_file" 2>&1)
        exit_code=$?
        echo "$output"
    else
        output=$(timeout 120 "$test_file" 2>&1)
        exit_code=$?
    fi

    # Strip ANSI codes for parsing
    clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
    passed=$(echo "$clean" | grep -i "^Passed:" | tail -1 | awk '{print $2}')
    failed=$(echo "$clean" | grep -i "^Failed:" | tail -1 | awk '{print $2}')
    skipped=$(echo "$clean" | grep -i "^Skipped:" | tail -1 | awk '{print $2}')

    passed=${passed:-0}
    failed=${failed:-0}
    skipped=${skipped:-0}

    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))

    if [ "$exit_code" -eq 0 ]; then
        printf "${GREEN}✓${NC} %-30s  ${GREEN}%d passed${NC}" "$suite_name" "$passed"
        [ "$skipped" -gt 0 ] && printf "  ${YELLOW}%d skipped${NC}" "$skipped"
        printf "\n"
        SUITES_PASSED=$((SUITES_PASSED + 1))
    else
        printf "${RED}✗${NC} %-30s  ${GREEN}%d passed${NC}  ${RED}%d failed${NC}" "$suite_name" "$passed" "$failed"
        [ "$skipped" -gt 0 ] && printf "  ${YELLOW}%d skipped${NC}" "$skipped"
        printf "\n"
        SUITES_FAILED=$((SUITES_FAILED + 1))
        FAILED_SUITES="${FAILED_SUITES}  - ${suite_name}\n"
    fi
done

printf "\n==========================================\n"
printf "BUILTIN TEST RESULTS\n"
printf "==========================================\n"
printf "Passed:  %d\n" "$TOTAL_PASSED"
printf "Failed:  %d\n" "$TOTAL_FAILED"
printf "Skipped: %d\n" "$TOTAL_SKIPPED"
printf "Total:   %d\n" "$((TOTAL_PASSED + TOTAL_FAILED + TOTAL_SKIPPED))"
printf "==========================================\n"

if [ $((TOTAL_PASSED + TOTAL_FAILED)) -gt 0 ]; then
    PASS_RATE=$((TOTAL_PASSED * 100 / (TOTAL_PASSED + TOTAL_FAILED)))
    printf "Pass rate: %d%%\n" "$PASS_RATE"
fi

if [ "$SUITES_FAILED" -gt 0 ]; then
    printf "\n${RED}Failed suites:${NC}\n"
    printf "%b" "$FAILED_SUITES"
    printf "==========================================\n"
fi

if [ "$TOTAL_FAILED" -eq 0 ]; then
    printf "ALL BUILTIN TESTS PASSED!\n"
    exit 0
else
    exit 1
fi
