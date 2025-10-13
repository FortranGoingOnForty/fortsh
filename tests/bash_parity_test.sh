#!/bin/bash
# =====================================
# Bash Parity Test Suite for fortsh
# =====================================
# This test compares fortsh output with bash output to ensure compatibility

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
SKIPPED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../bin/fortsh}"

# Check if fortsh exists
if [[ ! -x "$FORTSH_BIN" ]]; then
    echo -e "${RED}ERROR${NC}: fortsh binary not found at $FORTSH_BIN"
    echo "Please run 'make' first or set FORTSH_BIN environment variable"
    exit 1
fi

# Test result trackers
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    if [[ -n "$2" ]]; then
        echo "  bash:   $2"
    fi
    if [[ -n "$3" ]]; then
        echo "  fortsh: $3"
    fi
    ((FAILED++))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1 - $2"
    ((SKIPPED++))
}

section() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "$1"
    echo -e "==========================================${NC}"
}

# Helper function to run command in both shells and compare
compare_output() {
    local test_name="$1"
    local command="$2"
    local bash_file="/tmp/bash_parity_$$_bash"
    local fortsh_file="/tmp/bash_parity_$$_fortsh"

    # Run in bash
    bash -c "$command" > "$bash_file" 2>&1 || true

    # Run in fortsh
    "$FORTSH_BIN" -c "$command" > "$fortsh_file" 2>&1 || true

    # Compare outputs
    if diff -q "$bash_file" "$fortsh_file" > /dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "$(cat "$bash_file")" "$(cat "$fortsh_file")"
    fi

    rm -f "$bash_file" "$fortsh_file"
}

# Helper function to compare exit codes
compare_exit_code() {
    local test_name="$1"
    local command="$2"

    bash -c "$command" > /dev/null 2>&1
    local bash_exit=$?

    "$FORTSH_BIN" -c "$command" > /dev/null 2>&1
    local fortsh_exit=$?

    if [[ $bash_exit -eq $fortsh_exit ]]; then
        pass "$test_name"
    else
        fail "$test_name" "exit=$bash_exit" "exit=$fortsh_exit"
    fi
}

# Cleanup
cleanup() {
    rm -f /tmp/bash_parity_$$_* 2>/dev/null
    rm -f /tmp/fortsh_parity_test_* 2>/dev/null
}
trap cleanup EXIT

section "1. BASIC ECHO AND OUTPUT"

compare_output "echo simple string" "echo hello world"
compare_output "echo with single quotes" "echo 'hello world'"
compare_output "echo with double quotes" 'echo "hello world"'
compare_output "echo with special chars" "echo 'hello\$world'"
compare_output "echo multiple args" "echo a b c d e"

section "2. VARIABLE EXPANSION"

compare_output "simple variable" "VAR=test; echo \$VAR"
compare_output "variable in string" 'VAR=world; echo "hello $VAR"'
compare_output "multiple variables" "A=hello; B=world; echo \$A \$B"
compare_output "undefined variable" "echo \$UNDEFINED_VAR_XYZ"
compare_output "variable with braces" "VAR=test; echo \${VAR}"

section "3. PARAMETER EXPANSION"

compare_output "default value :-" 'echo "${UNSET:-default}"'
compare_output "string length" 'STR=hello; echo "${#STR}"'
compare_output "remove prefix #" 'VAR=prefix_value; echo "${VAR#prefix_}"'
compare_output "remove prefix ##" 'VAR=path/to/file.txt; echo "${VAR##*/}"'
compare_output "remove suffix %" 'VAR=file.txt; echo "${VAR%.txt}"'
compare_output "remove suffix %%" 'VAR=file.tar.gz; echo "${VAR%%.*}"'
compare_output "uppercase first" 'VAR=hello; echo "${VAR^}"'
compare_output "uppercase all" 'VAR=hello; echo "${VAR^^}"'
compare_output "lowercase first" 'VAR=HELLO; echo "${VAR,}"'
compare_output "lowercase all" 'VAR=HELLO; echo "${VAR,,}"'

section "4. COMMAND SUBSTITUTION"

compare_output "command substitution \$()" "echo \$(echo nested)"
compare_output "backtick substitution" 'echo `echo backtick`'
compare_output "nested substitution" "echo \$(echo \$(echo deep))"
compare_output "substitution in string" 'echo "result: $(echo success)"'

section "5. ARITHMETIC EXPANSION"

compare_output "simple addition" "echo \$((5 + 3))"
compare_output "subtraction" "echo \$((10 - 7))"
compare_output "multiplication" "echo \$((4 * 3))"
compare_output "division" "echo \$((15 / 3))"
compare_output "modulo" "echo \$((10 % 3))"
compare_output "arithmetic with vars" "A=5; B=3; echo \$((A + B))"
compare_output "complex expression" "echo \$((5 * 3 + 2))"

section "6. BRACE EXPANSION"

compare_output "numeric range" "echo {1..5}"
compare_output "reverse range" "echo {5..1}"
compare_output "char range" "echo {a..e}"
compare_output "list expansion" "echo {foo,bar,baz}"
compare_output "nested braces" "echo {a,b}{1,2}"

section "7. GLOB PATTERNS"

# Setup test files
mkdir -p /tmp/fortsh_parity_test_dir
touch /tmp/fortsh_parity_test_dir/{a,b,c}.txt
touch /tmp/fortsh_parity_test_dir/test{1,2,3}.dat

compare_output "glob wildcard *" "ls /tmp/fortsh_parity_test_dir/*.txt 2>/dev/null | wc -l"
compare_output "glob single char ?" "ls /tmp/fortsh_parity_test_dir/?.txt 2>/dev/null | wc -l"
compare_output "glob bracket" "ls /tmp/fortsh_parity_test_dir/[ab].txt 2>/dev/null | wc -l"

section "8. REDIRECTION"

compare_output "output redirect" "echo test > /tmp/fortsh_parity_test_out && cat /tmp/fortsh_parity_test_out"
compare_output "append redirect" "echo line1 > /tmp/fortsh_parity_test_app && echo line2 >> /tmp/fortsh_parity_test_app && wc -l < /tmp/fortsh_parity_test_app"
compare_output "here string" "cat <<< hello"
compare_output "stderr redirect" "ls /nonexistent 2>&1 | grep -c 'cannot access\\|No such'"

section "9. PIPELINES"

compare_output "simple pipe" "echo hello | cat"
compare_output "two-stage pipe" "echo test | cat | tr t T"
compare_output "three-stage pipe" "echo HELLO | tr '[:upper:]' '[:lower:]' | tr l x"

section "10. CONDITIONALS"

compare_exit_code "true command" "true"
compare_exit_code "false command" "false"
compare_output "if true" "if true; then echo yes; fi"
compare_output "if false" "if false; then echo no; else echo yes; fi"
compare_output "if-elif-else" "X=2; if [ \$X -eq 1 ]; then echo one; elif [ \$X -eq 2 ]; then echo two; else echo other; fi"

section "11. LOOPS"

compare_output "for loop list" "for i in a b c; do echo \$i; done"
compare_output "for loop range" "for i in {1..3}; do echo \$i; done"
compare_output "for loop glob" "for f in /tmp/fortsh_parity_test_dir/*.txt; do basename \$f; done | wc -l"
compare_output "while loop" "i=3; while [ \$i -gt 0 ]; do echo \$i; i=\$((i-1)); done"
compare_output "until loop" "i=1; until [ \$i -gt 3 ]; do echo \$i; i=\$((i+1)); done"

section "12. TEST OPERATORS"

compare_exit_code "test -f file" "touch /tmp/fortsh_parity_test_file && test -f /tmp/fortsh_parity_test_file"
compare_exit_code "test -d dir" "test -d /tmp"
compare_exit_code "test -n string" "test -n 'hello'"
compare_exit_code "test -z empty" "test -z ''"
compare_exit_code "test string =" "test 'hello' = 'hello'"
compare_exit_code "test number -eq" "test 5 -eq 5"
compare_exit_code "test number -gt" "test 5 -gt 3"
compare_exit_code "test number -lt" "test 3 -lt 5"

section "13. LOGICAL OPERATORS"

compare_exit_code "true && true" "true && true"
compare_exit_code "true && false" "true && false"
compare_exit_code "false || true" "false || true"
compare_exit_code "false || false" "false || false"
compare_output "command && echo" "true && echo success"
compare_output "command || echo" "false || echo fallback"

section "14. SPECIAL VARIABLES"

compare_output "\$? exit status" "true; echo \$?"
compare_output "\$? after failure" "false; echo \$?"
compare_output "\$\$ PID exists" "test -n \$\$ && echo ok"

section "15. FUNCTIONS"

compare_output "simple function" "func() { echo hello; }; func"
compare_output "function with args" "func() { echo \$1 \$2; }; func foo bar"
compare_output "function return" "func() { return 42; }; func; echo \$?"
compare_output "local variables" "func() { local x=10; echo \$x; }; func"

section "16. ARRAYS"

compare_output "array declaration" "arr=(a b c); echo \${arr[0]}"
compare_output "array length" "arr=(a b c); echo \${#arr[@]}"
compare_output "array all elements" "arr=(a b c); echo \${arr[@]}"
compare_output "array indices" "arr=(a b c); echo \${!arr[@]}"

section "17. QUOTING AND ESCAPING"

compare_output "single quote literal" "echo '\$VAR'"
compare_output "double quote expand" 'VAR=test; echo "$VAR"'
compare_output "escape in double" 'echo "hello\$world"'
compare_output "escape newline" "echo 'line1\nline2'"

section "18. SUBSHELLS"

compare_output "subshell var isolation" "(VAR=inner; echo \$VAR); echo \$VAR"
compare_output "subshell cd isolation" "(cd /tmp; pwd); pwd"

section "19. CASE STATEMENT"

compare_output "case match" "x=2; case \$x in 1) echo one;; 2) echo two;; esac"
compare_output "case wildcard" "x=hello; case \$x in h*) echo starts_h;; esac"
compare_output "case default" "x=z; case \$x in a) echo a;; *) echo default;; esac"

section "20. MULTI-LINE STRINGS"

compare_output "double quote multiline" 'echo "line1
line2"'
compare_output "single quote multiline" "echo 'line1
line2'"

# Summary
section "SUMMARY"
echo ""
echo "=========================================="
echo "BASH PARITY TEST RESULTS"
echo "=========================================="
echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${RED}Failed:${NC}  $FAILED"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
echo "Total:   $((PASSED + FAILED + SKIPPED))"
echo "=========================================="

if [[ $((PASSED + FAILED)) -gt 0 ]]; then
    PASS_RATE=$((PASSED * 100 / (PASSED + FAILED)))
    echo "Pass rate: ${PASS_RATE}%"
fi

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}ALL BASH PARITY TESTS PASSED!${NC} ✓"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC} ✗"
    exit 1
fi
