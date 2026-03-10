#!/bin/sh
# =====================================
# Shared test harness for builtin tests
# =====================================
# Source this file from individual builtin test scripts.
# Each test file must set TEST_PREFIX before sourcing.

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

# Get script directory (POSIX way)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../bin/fortsh}"

# Check if fortsh exists
if [ ! -x "$FORTSH_BIN" ]; then
    printf "${RED}ERROR${NC}: fortsh binary not found at $FORTSH_BIN\n"
    printf "Please run 'make' first or set FORTSH_BIN environment variable\n"
    exit 1
fi

# Temp directory for test files
TEST_TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TEST_TMPDIR" 2>/dev/null; }
trap cleanup EXIT INT TERM

pass() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${GREEN}✓ PASS${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    TEST_NUM=$((TEST_NUM + 1))
    TEST_ID="${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}"
    printf "${RED}✗ FAIL${NC} ${TEST_ID}: %s\n" "$1"
    FAILED_TESTS_LIST="${FAILED_TESTS_LIST}  ${TEST_ID}: $1\n"
    if [ -n "$2" ]; then printf "  expected: %s\n" "$2"; fi
    if [ -n "$3" ]; then printf "  got:      %s\n" "$3"; fi
    FAILED=$((FAILED + 1))
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${YELLOW}⊘ SKIP${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s - %s\n" "$1" "$2"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n${BLUE}==========================================\n%s\n==========================================${NC}\n" "$1"
}

# Helper: compare output against bash
compare_output() {
    test_name="$1"; command="$2"
    expected=$(bash -c "$command" 2>&1)
    actual=$("$FORTSH_BIN" -c "$command" 2>&1)
    if [ "$expected" = "$actual" ]; then pass "$test_name"
    else fail "$test_name" "$expected" "$actual"; fi
}

# Helper: compare exit code only
compare_exit() {
    test_name="$1"; command="$2"
    bash -c "$command" >/dev/null 2>&1; expected=$?
    "$FORTSH_BIN" -c "$command" >/dev/null 2>&1; actual=$?
    if [ "$expected" = "$actual" ]; then pass "$test_name"
    else fail "$test_name" "exit $expected" "exit $actual"; fi
}

# Helper: compare both output and exit code
compare_both() {
    test_name="$1"; command="$2"
    expected_out=$(bash -c "$command" 2>&1); expected_exit=$?
    actual_out=$("$FORTSH_BIN" -c "$command" 2>&1); actual_exit=$?
    if [ "$expected_out" = "$actual_out" ] && [ "$expected_exit" = "$actual_exit" ]; then
        pass "$test_name"
    else
        fail "$test_name" "out='$expected_out' exit=$expected_exit" "out='$actual_out' exit=$actual_exit"
    fi
}

# Helper: check fortsh output matches expected string
check_output() {
    test_name="$1"; command="$2"; expected="$3"
    actual=$("$FORTSH_BIN" -c "$command" 2>&1)
    if [ "$actual" = "$expected" ]; then pass "$test_name"
    else fail "$test_name" "$expected" "$actual"; fi
}

# Helper: check fortsh exit code matches expected
check_exit() {
    test_name="$1"; command="$2"; expected="$3"
    "$FORTSH_BIN" -c "$command" >/dev/null 2>&1; actual=$?
    if [ "$actual" = "$expected" ]; then pass "$test_name"
    else fail "$test_name" "exit $expected" "exit $actual"; fi
}

# Print summary — call at end of each test file
print_summary() {
    printf "\n==========================================\n"
    printf "%s TEST RESULTS\n" "$TEST_PREFIX"
    printf "==========================================\n"
    printf "Passed:  %d\n" "$PASSED"
    printf "Failed:  %d\n" "$FAILED"
    printf "Skipped: %d\n" "$SKIPPED"
    printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"
    printf "==========================================\n"

    if [ $((PASSED + FAILED)) -gt 0 ]; then
        PASS_RATE=$((PASSED * 100 / (PASSED + FAILED)))
        printf "Pass rate: %d%%\n" "$PASS_RATE"
    fi

    if [ "$FAILED" -gt 0 ]; then
        printf "\nFailed tests:\n"
        printf "%b" "$FAILED_TESTS_LIST"
        printf "==========================================\n"
    fi

    if [ "$FAILED" -eq 0 ]; then
        printf "ALL %s TESTS PASSED!\n" "$TEST_PREFIX"
        exit 0
    else
        exit 1
    fi
}
