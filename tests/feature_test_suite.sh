#!/bin/bash
# Comprehensive Fortsh Feature Test Suite
# Tests all major shell operators and features

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
SKIPPED=0

# Test result tracker
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Error: $2"
    ((FAILED++))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    ((SKIPPED++))
}

section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Cleanup function
cleanup() {
    rm -f /tmp/fortsh_test_* 2>/dev/null
}

# Setup
cleanup
trap cleanup EXIT

section "1. BASIC OUTPUT & ECHO"

# Test 1.1: Simple echo
if echo "hello" > /tmp/fortsh_test_1 2>&1 && [ -f /tmp/fortsh_test_1 ]; then
    pass "Simple echo"
else
    fail "Simple echo" "Command failed"
fi

# Test 1.2: Echo with variables
VAR="world"
if echo "$VAR" | grep -q "world"; then
    pass "Echo with variables"
else
    fail "Echo with variables" "Variable not expanded"
fi

section "2. BASIC REDIRECTION"

# Test 2.1: Output redirection (>)
if echo "test" > /tmp/fortsh_test_2 && grep -q "test" /tmp/fortsh_test_2; then
    pass "Output redirection (>)"
else
    fail "Output redirection (>)" "File not created or content wrong"
fi

# Test 2.2: Append redirection (>>)
echo "line1" > /tmp/fortsh_test_3
if echo "line2" >> /tmp/fortsh_test_3 && [ $(wc -l < /tmp/fortsh_test_3) -eq 2 ]; then
    pass "Append redirection (>>)"
else
    fail "Append redirection (>>)" "Append failed"
fi

# Test 2.3: Input redirection (<)
echo "input" > /tmp/fortsh_test_4
if cat < /tmp/fortsh_test_4 | grep -q "input"; then
    pass "Input redirection (<)"
else
    fail "Input redirection (<)" "Input not read"
fi

# Test 2.4: Error redirection (2>)
if ls /nonexistent 2> /tmp/fortsh_test_5 && [ -s /tmp/fortsh_test_5 ]; then
    pass "Error redirection (2>)"
else
    fail "Error redirection (2>)" "stderr not captured"
fi

# Test 2.5: Redirect both stdout and stderr (2>&1)
if ls /nonexistent 2>&1 | grep -q "cannot access\|No such"; then
    pass "Redirect stderr to stdout (2>&1)"
else
    fail "Redirect stderr to stdout (2>&1)" "Combined output failed"
fi

section "3. PIPES"

# Test 3.1: Simple pipe
if echo "hello" | cat | grep -q "hello"; then
    pass "Simple pipe (echo | cat)"
else
    fail "Simple pipe" "Pipe failed"
fi

# Test 3.2: Two-stage pipe
if echo "test" | cat | grep "test" > /dev/null; then
    pass "Two-stage pipe"
else
    fail "Two-stage pipe" "Multi-stage pipe failed"
fi

# Test 3.3: Pipe with grep
if ls / | grep -q "bin"; then
    pass "Pipe with grep"
else
    fail "Pipe with grep" "Pipe to grep failed"
fi

# Test 3.4: Pipe with wc
COUNT=$(echo -e "a\nb\nc" | wc -l)
if [ "$COUNT" -eq 3 ]; then
    pass "Pipe with wc"
else
    fail "Pipe with wc" "Expected 3, got $COUNT"
fi

# Test 3.5: Three-stage pipe
if echo "HELLO" | tr '[:upper:]' '[:lower:]' | grep -q "hello"; then
    pass "Three-stage pipe"
else
    fail "Three-stage pipe" "Complex pipe failed"
fi

section "4. COMMAND SUBSTITUTION"

# Test 4.1: Backticks
if [ "$(echo test)" = "test" ]; then
    pass "Command substitution with $()"
else
    fail "Command substitution with $()" "Substitution failed"
fi

# Test 4.2: Nested substitution
if [ "$(echo $(echo nested))" = "nested" ]; then
    pass "Nested command substitution"
else
    fail "Nested command substitution" "Nested substitution failed"
fi

# Test 4.3: Substitution in echo
OUTPUT=$(echo "Result: $(echo success)")
if echo "$OUTPUT" | grep -q "Result: success"; then
    pass "Command substitution in echo"
else
    fail "Command substitution in echo" "Got: $OUTPUT"
fi

section "5. VARIABLES"

# Test 5.1: Simple variable assignment
VAR1="value"
if [ "$VAR1" = "value" ]; then
    pass "Simple variable assignment"
else
    fail "Simple variable assignment" "Variable not set"
fi

# Test 5.2: Variable in command
FILE="/tmp/fortsh_test_var"
if echo "data" > "$FILE" && [ -f "$FILE" ]; then
    pass "Variable in command"
else
    fail "Variable in command" "File not created"
fi

# Test 5.3: Command substitution to variable
LINES=$(echo -e "a\nb" | wc -l)
if [ "$LINES" -eq 2 ]; then
    pass "Command substitution to variable"
else
    fail "Command substitution to variable" "Expected 2, got $LINES"
fi

section "6. PARAMETER EXPANSION"

# Test 6.1: Default value
UNSET_VAR=""
if [ "${UNSET_VAR:-default}" = "default" ]; then
    pass "Parameter expansion with default (:-)"
else
    fail "Parameter expansion with default" "Default not used"
fi

# Test 6.2: String length
STR="hello"
if [ "${#STR}" -eq 5 ]; then
    pass "String length expansion (${#var})"
else
    fail "String length expansion" "Expected 5, got ${#STR}"
fi

# Test 6.3: Substring removal
PATH_VAR="path/to/file.txt"
if [ "${PATH_VAR##*/}" = "file.txt" ]; then
    pass "Remove prefix (##)"
else
    fail "Remove prefix (##)" "Got: ${PATH_VAR##*/}"
fi

section "7. BRACE EXPANSION"

# Test 7.1: Numeric range
RESULT=$(echo {1..3})
if [ "$RESULT" = "1 2 3" ]; then
    pass "Brace expansion numeric range {1..3}"
else
    fail "Brace expansion numeric range" "Got: $RESULT"
fi

# Test 7.2: String list
RESULT=$(echo {a,b,c})
if echo "$RESULT" | grep -q "a b c"; then
    pass "Brace expansion string list {a,b,c}"
else
    fail "Brace expansion string list" "Got: $RESULT"
fi

section "8. GLOB PATTERNS"

# Setup test files
touch /tmp/fortsh_test_a.txt /tmp/fortsh_test_b.txt /tmp/fortsh_test_c.dat

# Test 8.1: Wildcard *
COUNT=$(ls /tmp/fortsh_test_*.txt 2>/dev/null | wc -l)
if [ "$COUNT" -eq 2 ]; then
    pass "Glob wildcard (*)"
else
    fail "Glob wildcard (*)" "Expected 2 files, got $COUNT"
fi

# Test 8.2: Single char ?
if ls /tmp/fortsh_test_?.txt 2>/dev/null | grep -q "fortsh_test_a"; then
    pass "Glob single char (?)"
else
    fail "Glob single char (?)" "Pattern didn't match"
fi

section "9. ARITHMETIC"

# Test 9.1: Basic arithmetic
if [ $((5 + 3)) -eq 8 ]; then
    pass "Arithmetic expansion (( ))"
else
    fail "Arithmetic expansion" "5 + 3 != 8"
fi

# Test 9.2: Multiplication
if [ $((4 * 3)) -eq 12 ]; then
    pass "Arithmetic multiplication"
else
    fail "Arithmetic multiplication" "4 * 3 != 12"
fi

# Test 9.3: Variables in arithmetic
NUM=10
if [ $((NUM + 5)) -eq 15 ]; then
    pass "Variables in arithmetic"
else
    fail "Variables in arithmetic" "NUM + 5 != 15"
fi

section "10. CONTROL FLOW"

# Test 10.1: If statement
if true; then
    pass "If statement (true)"
else
    fail "If statement" "If didn't execute"
fi

# Test 10.2: If-else
if false; then
    fail "If-else statement" "False branch executed"
else
    pass "If-else statement"
fi

# Test 10.3: For loop
COUNT=0
for i in 1 2 3; do
    COUNT=$((COUNT + 1))
done
if [ "$COUNT" -eq 3 ]; then
    pass "For loop"
else
    fail "For loop" "Expected 3 iterations, got $COUNT"
fi

# Test 10.4: While loop
COUNT=0
NUM=3
while [ $NUM -gt 0 ]; do
    COUNT=$((COUNT + 1))
    NUM=$((NUM - 1))
done
if [ "$COUNT" -eq 3 ]; then
    pass "While loop"
else
    fail "While loop" "Expected 3 iterations, got $COUNT"
fi

section "11. TEST OPERATORS"

# Test 11.1: File exists
touch /tmp/fortsh_test_exists
if [ -f /tmp/fortsh_test_exists ]; then
    pass "Test file exists (-f)"
else
    fail "Test file exists" "File not detected"
fi

# Test 11.2: Directory exists
if [ -d /tmp ]; then
    pass "Test directory exists (-d)"
else
    fail "Test directory exists" "Directory not detected"
fi

# Test 11.3: String equality
if [ "abc" = "abc" ]; then
    pass "String equality (=)"
else
    fail "String equality" "Strings don't match"
fi

# Test 11.4: Numeric comparison
if [ 5 -gt 3 ]; then
    pass "Numeric comparison (-gt)"
else
    fail "Numeric comparison" "5 not greater than 3"
fi

# Test 11.5: Advanced test [[]]
if [[ "hello" == "hello" ]]; then
    pass "Advanced test [[ ]]"
else
    fail "Advanced test [[ ]]" "Test failed"
fi

section "12. HERE DOCUMENTS"

# Test 12.1: Simple here doc
OUTPUT=$(cat <<EOF
line1
line2
EOF
)
if echo "$OUTPUT" | grep -q "line1"; then
    pass "Here document (<<EOF)"
else
    fail "Here document" "Content not captured"
fi

# Test 12.2: Here doc with variables
NAME="fortsh"
OUTPUT=$(cat <<EOF
Hello $NAME
EOF
)
if echo "$OUTPUT" | grep -q "Hello fortsh"; then
    pass "Here document with variable expansion"
else
    fail "Here document with variable expansion" "Variable not expanded"
fi

section "13. BACKGROUND JOBS"

# Test 13.1: Background execution
(sleep 0.1 && echo "done" > /tmp/fortsh_test_bg) &
BG_PID=$!
sleep 0.2
if [ -f /tmp/fortsh_test_bg ]; then
    pass "Background job execution (&)"
else
    fail "Background job execution" "Background job didn't complete"
fi

# Test 13.2: $! captures PID
(sleep 0.1) &
LAST_PID=$!
if [ -n "$LAST_PID" ] && [ "$LAST_PID" -gt 0 ]; then
    pass "Background job PID (\$!)"
else
    fail "Background job PID" "PID not captured: $LAST_PID"
fi

section "14. SPECIAL VARIABLES"

# Test 14.1: $? exit status
true
if [ $? -eq 0 ]; then
    pass "Exit status (\$?)"
else
    fail "Exit status" "Expected 0, got $?"
fi

# Test 14.2: $$ PID
if [ -n "$$" ] && [ "$$" -gt 0 ]; then
    pass "Current PID (\$\$)"
else
    fail "Current PID" "PID not set: $$"
fi

section "15. FUNCTIONS"

# Test 15.1: Simple function
test_func() {
    echo "success"
}
if [ "$(test_func)" = "success" ]; then
    pass "Function definition and call"
else
    fail "Function definition and call" "Function didn't execute"
fi

# Test 15.2: Function with parameters
test_params() {
    echo "$1-$2"
}
if [ "$(test_params a b)" = "a-b" ]; then
    pass "Function with parameters"
else
    fail "Function with parameters" "Parameters not passed"
fi

# Test 15.3: Function return value
test_return() {
    return 42
}
test_return
if [ $? -eq 42 ]; then
    pass "Function return value"
else
    fail "Function return value" "Expected 42, got $?"
fi

section "16. ARRAYS"

# Test 16.1: Indexed array
arr=(one two three)
if [ "${arr[0]}" = "one" ]; then
    pass "Indexed array access"
else
    fail "Indexed array access" "Element 0: ${arr[0]}"
fi

# Test 16.2: Array length
if [ "${#arr[@]}" -eq 3 ]; then
    pass "Array length (${#arr[@]})"
else
    fail "Array length" "Expected 3, got ${#arr[@]}"
fi

# Test 16.3: Array iteration
COUNT=0
for item in "${arr[@]}"; do
    COUNT=$((COUNT + 1))
done
if [ "$COUNT" -eq 3 ]; then
    pass "Array iteration"
else
    fail "Array iteration" "Expected 3, got $COUNT"
fi

section "17. QUOTING"

# Test 17.1: Double quotes preserve variables
VAR="world"
if [ "$(echo "hello $VAR")" = "hello world" ]; then
    pass "Double quotes with variables"
else
    fail "Double quotes with variables" "Variable not expanded"
fi

# Test 17.2: Single quotes literal
if [ '$(echo test)' = '$(echo test)' ]; then
    pass "Single quotes literal"
else
    fail "Single quotes literal" "Command was executed"
fi

section "18. COMPLEX COMBINATIONS"

# Test 18.1: Pipe + redirection
if echo "test" | cat > /tmp/fortsh_test_combo1 && grep -q "test" /tmp/fortsh_test_combo1; then
    pass "Pipe + redirection"
else
    fail "Pipe + redirection" "Combination failed"
fi

# Test 18.2: Command substitution + pipe
if echo "$(echo hello | tr '[:lower:]' '[:upper:]')" | grep -q "HELLO"; then
    pass "Command substitution + pipe"
else
    fail "Command substitution + pipe" "Combination failed"
fi

# Test 18.3: Multiple redirections
if { echo "out"; echo "err" >&2; } >>/tmp/fortsh_test_out 2>>/tmp/fortsh_test_err; then
    pass "Multiple redirections"
else
    fail "Multiple redirections" "Complex redirection failed"
fi

section "SUMMARY"
echo ""
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${RED}Failed:${NC}  $FAILED"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
echo "Total:   $((PASSED + FAILED + SKIPPED))"
echo "=========================================="

PASS_RATE=$((PASSED * 100 / (PASSED + FAILED)))
echo "Pass rate: ${PASS_RATE}%"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}ALL TESTS PASSED!${NC} ✓"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC} ✗"
    exit 1
fi
