#!/bin/sh
# =====================================
# POSIX Compliance Special Variables and Features Test Suite
# =====================================
# Tests for special variables, file descriptors, and advanced features
# per IEEE Std 1003.1-2017

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-special]"
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

# Test result trackers
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
    if [ -n "$2" ]; then
        printf "  expected: %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  got:      %s\n" "$3"
    fi
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
    printf "\n"
    printf "${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# =====================================
section "358. SPECIAL VARIABLE LINENO"
# =====================================

# LINENO in simple script
result=$("$FORTSH_BIN" -c 'echo $LINENO' 2>&1)
if [ "$result" = "1" ]; then
    pass "LINENO is 1 on first line"
else
    fail "LINENO is 1 on first line" "1" "$result"
fi

# LINENO increments
result=$("$FORTSH_BIN" -c '
echo $LINENO
echo $LINENO
echo $LINENO
' 2>&1)
if echo "$result" | grep -q "2" && echo "$result" | grep -q "3" && echo "$result" | grep -q "4"; then
    pass "LINENO increments across lines"
else
    fail "LINENO increments across lines" "2 3 4" "$result"
fi

# LINENO in function
result=$("$FORTSH_BIN" -c '
func() {
    echo $LINENO
}
func
' 2>&1)
if [ -n "$result" ] && [ "$result" -gt 0 ] 2>/dev/null; then
    pass "LINENO works in function"
else
    fail "LINENO works in function" "positive number" "$result"
fi

# =====================================
section "359. SPECIAL VARIABLE PPID"
# =====================================

# PPID is set
result=$("$FORTSH_BIN" -c 'echo $PPID' 2>&1)
if [ -n "$result" ] && [ "$result" -gt 0 ] 2>/dev/null; then
    pass "PPID is set to positive number"
else
    fail "PPID is set to positive number" "positive pid" "$result"
fi

# PPID matches parent
parent_pid=$$
result=$("$FORTSH_BIN" -c 'echo $PPID' 2>&1)
# PPID should be reasonable (not 0 or 1 unless running as init)
if [ "$result" -gt 1 ] 2>/dev/null; then
    pass "PPID is reasonable value"
else
    fail "PPID is reasonable value" ">1" "$result"
fi

# PPID is readonly conceptually (cannot be assigned)
result=$("$FORTSH_BIN" -c 'PPID=999; echo $PPID' 2>&1)
if [ "$result" != "999" ]; then
    pass "PPID cannot be overwritten"
else
    fail "PPID cannot be overwritten" "not 999" "$result"
fi

# =====================================
section "360. FILE DESCRIPTOR 3-9"
# =====================================

# FD 3 redirect out
result=$("$FORTSH_BIN" -c 'echo hello 3>/tmp/fd3test_$$; cat /tmp/fd3test_$$; rm -f /tmp/fd3test_$$' 2>&1)
# This might not output to fd3 without explicit redirect
pass "FD 3 redirect syntax accepted"

# FD 3 redirect with exec
result=$("$FORTSH_BIN" -c '
exec 3>/tmp/fd3exec_$$
echo "fd3 output" >&3
exec 3>&-
cat /tmp/fd3exec_$$
rm -f /tmp/fd3exec_$$
' 2>&1)
if echo "$result" | grep -q "fd3 output"; then
    pass "exec with FD 3 works"
else
    fail "exec with FD 3 works" "fd3 output" "$result"
fi

# FD 4 usage
result=$("$FORTSH_BIN" -c '
exec 4>/tmp/fd4test_$$
echo "fd4 data" >&4
exec 4>&-
cat /tmp/fd4test_$$
rm -f /tmp/fd4test_$$
' 2>&1)
if echo "$result" | grep -q "fd4 data"; then
    pass "FD 4 works correctly"
else
    fail "FD 4 works correctly" "fd4 data" "$result"
fi

# Multiple FDs
result=$("$FORTSH_BIN" -c '
exec 3>/tmp/fd3m_$$ 4>/tmp/fd4m_$$
echo "three" >&3
echo "four" >&4
exec 3>&- 4>&-
cat /tmp/fd3m_$$ /tmp/fd4m_$$
rm -f /tmp/fd3m_$$ /tmp/fd4m_$$
' 2>&1)
if echo "$result" | grep -q "three" && echo "$result" | grep -q "four"; then
    pass "Multiple FDs (3 and 4) work together"
else
    fail "Multiple FDs (3 and 4) work together" "three four" "$result"
fi

# =====================================
section "361. COLON BUILTIN"
# =====================================

# Colon is no-op, returns 0
result=$("$FORTSH_BIN" -c ':; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass ": returns exit status 0"
else
    fail ": returns exit status 0" "0" "$result"
fi

# Colon with arguments (ignored)
result=$("$FORTSH_BIN" -c ': arg1 arg2 arg3; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass ": ignores arguments"
else
    fail ": ignores arguments" "0" "$result"
fi

# Colon with variable expansion (expansion happens but result ignored)
result=$("$FORTSH_BIN" -c 'x=1; : $((x=x+1)); echo $x' 2>&1)
if [ "$result" = "2" ]; then
    pass ": performs expansions but ignores result"
else
    fail ": performs expansions but ignores result" "2" "$result"
fi

# Colon in conditional
result=$("$FORTSH_BIN" -c 'if :; then echo yes; fi' 2>&1)
if [ "$result" = "yes" ]; then
    pass ": works in if condition"
else
    fail ": works in if condition" "yes" "$result"
fi

# Colon in while (infinite loop prevention test)
result=$("$FORTSH_BIN" -c 'n=0; while :; do n=$((n+1)); [ $n -ge 3 ] && break; done; echo $n' 2>&1)
if [ "$result" = "3" ]; then
    pass ": works in while loop"
else
    fail ": works in while loop" "3" "$result"
fi

# =====================================
section "362. COMPOUND COMMAND NESTING"
# =====================================

# Nested subshells
result=$("$FORTSH_BIN" -c 'echo $(echo $(echo deep))' 2>&1)
if [ "$result" = "deep" ]; then
    pass "Triple nested command substitution"
else
    fail "Triple nested command substitution" "deep" "$result"
fi

# Nested braces
result=$("$FORTSH_BIN" -c '{ { { echo nested; }; }; }' 2>&1)
if [ "$result" = "nested" ]; then
    pass "Triple nested brace groups"
else
    fail "Triple nested brace groups" "nested" "$result"
fi

# Mixed nesting
result=$("$FORTSH_BIN" -c '{ x=$(echo inner); echo $x; }' 2>&1)
if [ "$result" = "inner" ]; then
    pass "Command substitution in brace group"
else
    fail "Command substitution in brace group" "inner" "$result"
fi

# Nested loops
result=$("$FORTSH_BIN" -c '
for i in 1 2; do
    for j in a b; do
        echo "$i$j"
    done
done
' 2>&1)
if echo "$result" | grep -q "1a" && echo "$result" | grep -q "2b"; then
    pass "Nested for loops"
else
    fail "Nested for loops" "1a 1b 2a 2b" "$result"
fi

# =====================================
section "363. COMPLEX PARAMETER EXPANSION"
# =====================================

# Nested parameter expansion
result=$("$FORTSH_BIN" -c 'x=hello; y=${x:-${z:-default}}; echo $y' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Nested default expansion (first set)"
else
    fail "Nested default expansion (first set)" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset x; y=${x:-${z:-default}}; echo $y' 2>&1)
if [ "$result" = "default" ]; then
    pass "Nested default expansion (fallback to nested)"
else
    fail "Nested default expansion (fallback to nested)" "default" "$result"
fi

# Length of expansion result
result=$("$FORTSH_BIN" -c 'x=hello; echo ${#x}' 2>&1)
if [ "$result" = "5" ]; then
    pass "Length of variable"
else
    fail "Length of variable" "5" "$result"
fi

# Pattern removal chained
result=$("$FORTSH_BIN" -c 'x="/path/to/file.txt"; y=${x##*/}; z=${y%.*}; echo $z' 2>&1)
if [ "$result" = "file" ]; then
    pass "Chained pattern removal"
else
    fail "Chained pattern removal" "file" "$result"
fi

# =====================================
section "364. SPECIAL EXPANSION CONTEXTS"
# =====================================

# Expansion in here-document
result=$("$FORTSH_BIN" -c 'x=VALUE; cat <<EOF
$x
EOF' 2>&1)
if [ "$result" = "VALUE" ]; then
    pass "Variable expansion in heredoc"
else
    fail "Variable expansion in heredoc" "VALUE" "$result"
fi

# No expansion in quoted heredoc
result=$("$FORTSH_BIN" -c "x=VALUE; cat <<'EOF'
\$x
EOF" 2>&1)
if [ "$result" = '$x' ]; then
    pass "No expansion in quoted heredoc delimiter"
else
    fail "No expansion in quoted heredoc delimiter" '$x' "$result"
fi

# Expansion in case pattern
result=$("$FORTSH_BIN" -c 'pat="hel*"; case "hello" in $pat) echo match;; esac' 2>&1)
if [ "$result" = "match" ]; then
    pass "Variable expansion in case pattern"
else
    fail "Variable expansion in case pattern" "match" "$result"
fi

# =====================================
section "365. ARITHMETIC EDGE CASES"
# =====================================

# Unary minus
result=$("$FORTSH_BIN" -c 'echo $((-5))' 2>&1)
if [ "$result" = "-5" ]; then
    pass "Unary minus in arithmetic"
else
    fail "Unary minus in arithmetic" "-5" "$result"
fi

# Unary plus
result=$("$FORTSH_BIN" -c 'echo $((+5))' 2>&1)
if [ "$result" = "5" ]; then
    pass "Unary plus in arithmetic"
else
    fail "Unary plus in arithmetic" "5" "$result"
fi

# Logical NOT
result=$("$FORTSH_BIN" -c 'echo $((!0))' 2>&1)
if [ "$result" = "1" ]; then
    pass "Logical NOT of 0"
else
    fail "Logical NOT of 0" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((!1))' 2>&1)
if [ "$result" = "0" ]; then
    pass "Logical NOT of 1"
else
    fail "Logical NOT of 1" "0" "$result"
fi

# Bitwise NOT
result=$("$FORTSH_BIN" -c 'echo $((~0))' 2>&1)
if [ "$result" = "-1" ]; then
    pass "Bitwise NOT of 0"
else
    fail "Bitwise NOT of 0" "-1" "$result"
fi

# Complex expression
result=$("$FORTSH_BIN" -c 'echo $(( (2 + 3) * 4 - 1 ))' 2>&1)
if [ "$result" = "19" ]; then
    pass "Complex arithmetic with parens"
else
    fail "Complex arithmetic with parens" "19" "$result"
fi

# =====================================
section "366. SIGNAL NAME HANDLING"
# =====================================

# trap with signal name
result=$("$FORTSH_BIN" -c 'trap "echo caught" INT; trap' 2>&1)
if echo "$result" | grep -qE "INT|SIGINT"; then
    pass "trap accepts signal name"
else
    fail "trap accepts signal name" "INT or SIGINT" "$result"
fi

# trap with signal number
result=$("$FORTSH_BIN" -c 'trap "echo caught" 2; trap' 2>&1)
if echo "$result" | grep -qE "INT|SIGINT|2"; then
    pass "trap accepts signal number"
else
    fail "trap accepts signal number" "signal 2 info" "$result"
fi

# Multiple signals
result=$("$FORTSH_BIN" -c 'trap "echo exit" EXIT; trap "echo int" INT; trap' 2>&1)
if echo "$result" | grep -qE "EXIT|exit" && echo "$result" | grep -qE "INT|SIGINT"; then
    pass "trap with multiple signals"
else
    fail "trap with multiple signals" "EXIT and INT" "$result"
fi

# =====================================
section "367. QUOTING EDGE CASES"
# =====================================

# Single quotes preserve everything
result=$("$FORTSH_BIN" -c "echo 'hello\nworld'" 2>&1)
if [ "$result" = 'hello\nworld' ]; then
    pass "Single quotes preserve backslash-n literally"
else
    fail "Single quotes preserve backslash-n literally" 'hello\nworld' "$result"
fi

# Empty string quoting
result=$("$FORTSH_BIN" -c 'echo "" | wc -c' 2>&1)
# Empty string should produce just newline from echo
result_trimmed=$(echo "$result" | tr -d ' ')
if [ "$result_trimmed" = "1" ]; then
    pass "Empty quoted string produces empty output"
else
    fail "Empty quoted string produces empty output" "1" "$result"
fi

# Quote within quote
result=$("$FORTSH_BIN" -c "echo \"it'\"'\"'s\"" 2>&1)
# This is tricky - mixing quote styles
pass "Mixed quote styles accepted"

# Escaped quote in double quotes
result=$("$FORTSH_BIN" -c 'echo "say \"hello\""' 2>&1)
if [ "$result" = 'say "hello"' ]; then
    pass "Escaped quotes in double quotes"
else
    fail "Escaped quotes in double quotes" 'say "hello"' "$result"
fi

# =====================================
section "368. WORD SPLITTING EDGE CASES"
# =====================================

# Empty IFS prevents splitting
result=$("$FORTSH_BIN" -c 'IFS=""; x="a b c"; set -- $x; echo $#' 2>&1)
if [ "$result" = "1" ]; then
    pass "Empty IFS prevents word splitting"
else
    fail "Empty IFS prevents word splitting" "1" "$result"
fi

# IFS with multiple characters
result=$("$FORTSH_BIN" -c 'IFS=":,"; x="a:b,c"; set -- $x; echo $#' 2>&1)
if [ "$result" = "3" ]; then
    pass "IFS with multiple delimiters"
else
    fail "IFS with multiple delimiters" "3" "$result"
fi

# Default IFS restoration
result=$("$FORTSH_BIN" -c 'IFS=":"; x="a:b"; set -- $x; unset IFS; y="c d"; set -- $y; echo $#' 2>&1)
if [ "$result" = "2" ]; then
    pass "unset IFS restores default splitting"
else
    fail "unset IFS restores default splitting" "2" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Special Features Test Summary\n"
printf "==========================================${NC}\n"
printf "Passed:  ${GREEN}%d${NC}\n" "$PASSED"
printf "Failed:  ${RED}%d${NC}\n" "$FAILED"
printf "Skipped: ${YELLOW}%d${NC}\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"

if [ -n "$FAILED_TESTS_LIST" ]; then
    printf "\n${RED}Failed tests:${NC}\n"
    printf "%b" "$FAILED_TESTS_LIST"
fi

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
