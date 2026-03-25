#!/bin/sh
# =====================================
# POSIX Redirection Gap Tests
# =====================================
# Tests for POSIX redirection operators
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-redirect]"
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
# BASIC REDIRECTIONS
# ============================================================================

section "1. OUTPUT REDIRECTION"
compare_posix_output "redir out" 'echo test > /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir in" 'echo test > /tmp/r$$; cat < /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir append" 'echo a > /tmp/r$$; echo b >> /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir stderr" 'ls /nonexistent$$ 2>/dev/null; echo done'

section "2. READ/WRITE REDIRECTION"
compare_posix_exit_code "redirect <> creates file" "echo test <> /tmp/posix_gaps_rw_$$; test -f /tmp/posix_gaps_rw_$$; rm -f /tmp/posix_gaps_rw_$$"
compare_posix_exit_code "redirect <> opens existing" "echo data > /tmp/posix_gaps_rw2_$$; cat <> /tmp/posix_gaps_rw2_$$ 2>/dev/null; rm -f /tmp/posix_gaps_rw2_$$"

# ============================================================================
# ADVANCED REDIRECTIONS
# ============================================================================

section "3. FD REDIRECTION"
compare_posix_output "redirect order matters" "echo test 2>&1 >/dev/null | wc -l"
compare_posix_output "redirect to same fd" "echo test >&1 2>&1"
compare_posix_output "redirect append" "echo a > /tmp/posix_gaps_redir_$$; echo b >> /tmp/posix_gaps_redir_$$; wc -l < /tmp/posix_gaps_redir_$$; rm -f /tmp/posix_gaps_redir_$$"

section "4. HERE DOCUMENTS IN REDIRECT"
compare_posix_output "redirect here-string alternative" "cat <<EOF
test
EOF"
compare_posix_output "redirect duplicate stdin" "cat <&0 <<EOF
input
EOF"

section "5. LOOP REDIRECTIONS"
compare_posix_output "redirect in loop" 'for i in 1 2 3; do echo $i; done > /tmp/redir_test_$$; cat /tmp/redir_test_$$; rm /tmp/redir_test_$$'
compare_posix_output "append multiple" 'echo a >> /tmp/app_test_$$; echo b >> /tmp/app_test_$$; cat /tmp/app_test_$$; rm /tmp/app_test_$$'
compare_posix_output "stderr to file" 'ls /nonexistent 2>/tmp/err_test_$$ || cat /tmp/err_test_$$ | wc -l; rm -f /tmp/err_test_$$'

# ============================================================================
# IFS FIELD SPLITTING
# ============================================================================

section "6. IFS FIELD SPLITTING"
compare_posix_output "IFS mixed ws and non-ws" "IFS=': \t'; VAR='a:b c:d'; set -- \$VAR; echo \$# \$1 \$2 \$3 \$4"
compare_posix_output "IFS multiple delimiters" "IFS=',:'; VAR='a,b:c,d'; set -- \$VAR; echo \$#"
compare_posix_output "IFS trailing delimiters" "IFS=:; VAR='a:b:c:'; set -- \$VAR; echo \$#"
compare_posix_output "IFS leading and trailing" "IFS=:; VAR=':a:b:'; set -- \$VAR; echo \$# \$1 \$2"
compare_posix_output "IFS consecutive delimiters" "IFS=:; VAR='a::b'; set -- \$VAR; echo \$# \$1 \$2 \$3"
compare_posix_output "IFS whitespace collapsing" "IFS=' '; VAR='a  b   c'; set -- \$VAR; echo \$#"

# ============================================================================
# COMMENTS
# ============================================================================

section "7. COMMENTS"
compare_posix_output "comment inline" 'echo yes # comment'
compare_posix_output "comment in dquote" 'echo "not # comment"'
compare_posix_output "comment in squote" "echo 'not # comment'"

# ============================================================================
# EXIT CODES
# ============================================================================

section "8. EXIT CODES"
compare_posix_exit_code "true exits 0" "true"
compare_posix_exit_code "false exits 1" "false"
compare_posix_exit_code "exit 0" "(exit 0)"
compare_posix_output "exit code chain" "true; echo \$?"
compare_posix_output "backtick vs dollar-paren" "a=\`echo test\`; b=\$(echo test); test \"\$a\" = \"\$b\" && echo same"

# Summary
printf "\n==========================================\n"
printf "REDIRECTION GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
