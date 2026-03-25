#!/bin/sh
# =====================================
# POSIX Arithmetic Gap Tests
# =====================================
# Tests for POSIX arithmetic expansion
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-arithmetic]"
CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

# Get script directory (POSIX way)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../bin/fortsh}"
BASH_REF="${BASH_REF:-bash}"

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
    posix_out=$("$BASH_REF" -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

compare_posix_exit_code() {
    test_name="$1"; command="$2"
    "$BASH_REF" -c "$command" >/dev/null 2>&1; posix_code=$?
    "$FORTSH_BIN" -c "$command" >/dev/null 2>&1; fortsh_code=$?
    if [ "$posix_code" = "$fortsh_code" ]; then pass "$test_name"
    else fail "$test_name" "exit $posix_code" "exit $fortsh_code"; fi
}

# ============================================================================
# ARITHMETIC TESTS
# ============================================================================

section "1. BASIC OPERATORS"
compare_posix_output "add" 'echo $((5+3))'
compare_posix_output "sub" 'echo $((5-3))'
compare_posix_output "mul" 'echo $((5*3))'
compare_posix_output "div" 'echo $((15/3))'
compare_posix_output "mod" 'echo $((17%5))'
compare_posix_output "neg" 'echo $((-5))'

section "2. SPACING"
compare_posix_output "with spaces" 'echo $(( 1 + 2 ))'
compare_posix_output "mixed spacing" 'echo $(( 5 +3 ))'

section "3. COMPARISONS"
compare_posix_output "lt" 'echo $((3<5))'
compare_posix_output "gt" 'echo $((5>3))'
compare_posix_output "le" 'echo $((5<=5))'
compare_posix_output "ge" 'echo $((5>=5))'
compare_posix_output "eq" 'echo $((5==5))'
compare_posix_output "ne" 'echo $((5!=3))'

section "4. LOGICAL"
compare_posix_output "and" 'echo $((1&&1))'
compare_posix_output "or" 'echo $((0||1))'
compare_posix_output "not" 'echo $((!0))'

section "5. BITWISE"
compare_posix_output "band" 'echo $((12&10))'
compare_posix_output "bor" 'echo $((12|10))'
compare_posix_output "bxor" 'echo $((12^10))'
compare_posix_output "lshift" 'echo $((1<<4))'
compare_posix_output "rshift" 'echo $((16>>2))'

section "6. TERNARY"
compare_posix_output "ternary t" 'echo $((1?10:20))'
compare_posix_output "ternary f" 'echo $((0?10:20))'
compare_posix_output "ternary expr" 'echo $((5>3?1:0))'

section "7. ASSIGNMENT OPS"
compare_posix_output "pluseq" 'x=5; echo $((x+=3))'
compare_posix_output "minuseq" 'x=5; echo $((x-=3))'
compare_posix_output "muleq" 'x=5; echo $((x*=3))'
compare_posix_output "diveq" 'x=15; echo $((x/=3))'

section "8. PRECEDENCE"
compare_posix_output "mul before add" 'echo $((2+3*4))'
compare_posix_output "parens override" 'echo $(((2+3)*4))'
compare_posix_output "div add" 'echo $((10/2+3))'
compare_posix_output "nested parens" 'echo $(((2 + 3) * (4 + 5)))'

section "9. VARIABLES"
compare_posix_output "var simple" 'x=5; echo $((x))'
compare_posix_output "var expr" 'a=3; b=4; echo $((a*a+b*b))'
compare_posix_output "var unset" 'unset z; echo $((z))'
compare_posix_output "var ref" 'X=10; echo $((X + 5))'

section "10. NUMBER BASES"
compare_posix_output "octal" 'echo $((010))'
compare_posix_output "hex" 'echo $((0x10))'
compare_posix_output "hex lowercase" 'echo $((0xa))'

section "11. INCREMENT/DECREMENT"
compare_posix_output "preinc" 'x=5; echo $((++x))'
compare_posix_output "predec" 'x=5; echo $((--x))'
compare_posix_output "postinc" 'x=5; echo $((x++))'
compare_posix_output "postdec" 'x=5; echo $((x--))'

section "12. EDGE CASES"
compare_posix_output "negative numbers" "echo \$((-5 * -3))"
compare_posix_output "large numbers" "echo \$((999999 + 1))"
compare_posix_output "modulo negative" "echo \$((-17 % 5))"
compare_posix_output "comparison chain" "echo \$((5 > 3 && 10 > 8))"
compare_posix_output "unary minus" "X=5; echo \$((-X))"
compare_posix_output "unary plus" "X=5; echo \$((+X))"
compare_posix_output "zero" 'echo $((0))'
compare_posix_output "nested arith" 'echo $(($((1 + 2)) + 3))'
compare_posix_exit_code "division by zero" "echo \$((5 / 0)) 2>/dev/null"

# Summary
printf "\n==========================================\n"
printf "ARITHMETIC GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
