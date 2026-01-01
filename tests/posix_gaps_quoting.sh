#!/bin/sh
# =====================================
# POSIX Quoting Gap Tests
# =====================================
# Tests for POSIX quoting mechanisms
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-quoting]"
CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

# Get script directory (POSIX way)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../bin/fortsh}"

# Check if fortsh exists
if [ ! -x "$FORTSH_BIN" ]; then
    printf "${RED}ERROR${NC}: fortsh binary not found at $FORTSH_BIN\n"
    printf "Please run 'make' first or set FORTSH_BIN environment variable\n"
    exit 1
fi

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
    if [ -n "$2" ]; then printf "  posix:  %s\n" "$2"; fi
    if [ -n "$3" ]; then printf "  fortsh: %s\n" "$3"; fi
    FAILED=$((FAILED + 1))
}

section() {
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n${BLUE}==========================================\n%s\n==========================================${NC}\n" "$1"
}

normalize_output() { sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'; }

compare_posix_output() {
    test_name="$1"; command="$2"
    posix_out=$(bash -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

# ============================================================================
# QUOTING TESTS
# ============================================================================

section "1. SINGLE QUOTING"
compare_posix_output "simple" "echo 'hello'"
compare_posix_output "with space" "echo 'hello world'"
compare_posix_output "dollar literal" "echo '\$x'"
compare_posix_output "backtick literal" "echo '\`cmd\`'"
compare_posix_output "backslash literal" "echo '\\'"

section "2. DOUBLE QUOTING"
compare_posix_output "simple" 'echo "hello"'
compare_posix_output "with space" 'echo "hello world"'
compare_posix_output "var expand" 'x=val; echo "$x"'
compare_posix_output "escaped dollar" 'echo "\$x"'
compare_posix_output "escaped quote" 'echo "hello\"world"'

section "3. BACKSLASH ESCAPING"
compare_posix_output "escape space" 'echo hello\ world'
compare_posix_output "escape dollar" 'echo \$x'
compare_posix_output "escape newline" 'echo hello\
world'
compare_posix_output "escape backslash" 'echo \\\\'

section "4. MIXED QUOTING"
compare_posix_output "single in double" 'echo "'"'"'"'
compare_posix_output "double in single" "echo '\"'"
compare_posix_output "concat quotes" "echo 'a'b'c'"
compare_posix_output "quote switching" 'echo "a'"'"'b"'

section "5. EMPTY QUOTES"
compare_posix_output "empty single" "echo ''"
compare_posix_output "empty double" 'echo ""'
compare_posix_output "empty in string" 'echo a""b'
compare_posix_output "empty as arg" 'set -- ""; echo $#'

section "6. COMPLEX ESCAPING"
compare_posix_output "backslash in dquotes" 'echo "test\\nword"'
compare_posix_output "dollar in dquotes" 'echo "cost: \$5"'
compare_posix_output "backtick in dquotes" 'echo "date: \`date +%Y\`" | grep -c date'
compare_posix_output "mixed quoting" "echo 'single'\"double\"'single'"
compare_posix_output "empty concat" "echo ''test''"
compare_posix_output "quote removal" 'VAR="\"test\""; echo $VAR'
compare_posix_output "backslash newline" "echo 'line1\
line2' | wc -l"

# Summary
printf "\n==========================================\n"
printf "QUOTING GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
