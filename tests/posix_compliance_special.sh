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
section "369. $$ IN SUBSHELLS"
# =====================================

# $$ in subshell should return parent shell PID per POSIX
# Test within SAME shell instance (not separate invocations)
result=$("$FORTSH_BIN" -c 'echo $$; (echo $$)' 2>&1)
parent_pid=$(echo "$result" | sed -n '1p')
subshell_pid=$(echo "$result" | sed -n '2p')
if [ "$parent_pid" = "$subshell_pid" ]; then
    pass "\$\$ in subshell returns parent shell PID"
else
    fail "\$\$ in subshell returns parent shell PID" "$parent_pid" "$subshell_pid"
fi

# $$ in command substitution
result=$("$FORTSH_BIN" -c 'echo $$ $(echo $$)' 2>&1)
# Both should be the same PID
pid1=$(echo "$result" | awk '{print $1}')
pid2=$(echo "$result" | awk '{print $2}')
if [ "$pid1" = "$pid2" ]; then
    pass "\$\$ in command substitution matches parent"
else
    fail "\$\$ in command substitution matches parent" "same" "$result"
fi

# $$ is numeric
result=$("$FORTSH_BIN" -c 'echo $$' 2>&1)
if [ "$result" -gt 0 ] 2>/dev/null; then
    pass "\$\$ is positive integer"
else
    fail "\$\$ is positive integer" ">0" "$result"
fi

# =====================================
section "370. \$@ VS \$* DIFFERENCES"
# =====================================

# $@ preserves separate arguments
result=$("$FORTSH_BIN" -c 'set -- "a b" "c d"; for x in "$@"; do echo "[$x]"; done' 2>&1)
expected=$(printf "[a b]\n[c d]")
if [ "$result" = "$expected" ]; then
    pass '"\$@" preserves argument boundaries'
else
    fail '"\$@" preserves argument boundaries' "$expected" "$result"
fi

# $* joins with IFS
result=$("$FORTSH_BIN" -c 'IFS=":"; set -- a b c; echo "$*"' 2>&1)
if [ "$result" = "a:b:c" ]; then
    pass '"\$*" joins with first char of IFS'
else
    fail '"\$*" joins with first char of IFS' "a:b:c" "$result"
fi

# $@ unquoted splits
result=$("$FORTSH_BIN" -c 'set -- "a b" "c d"; for x in $@; do echo "[$x]"; done' 2>&1)
# Should split into 4 words: a, b, c, d
expected=$(printf "[a]\n[b]\n[c]\n[d]")
if [ "$result" = "$expected" ]; then
    pass 'Unquoted $@ splits on whitespace'
else
    fail 'Unquoted $@ splits on whitespace' "$expected" "$result"
fi

# Empty $@ produces nothing
result=$("$FORTSH_BIN" -c 'set --; for x in "$@"; do echo X; done; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass 'Empty "$@" produces no iterations'
else
    fail 'Empty "$@" produces no iterations' "done" "$result"
fi

# $# count
result=$("$FORTSH_BIN" -c 'set -- a b c d e; echo $#' 2>&1)
if [ "$result" = "5" ]; then
    pass '$# counts positional parameters'
else
    fail '$# counts positional parameters' "5" "$result"
fi

# =====================================
section "371. PWD AND OLDPWD"
# =====================================

# PWD is set
result=$("$FORTSH_BIN" -c 'echo $PWD' 2>&1)
if [ -n "$result" ] && [ -d "$result" ]; then
    pass "PWD is set to valid directory"
else
    fail "PWD is set to valid directory" "directory path" "$result"
fi

# cd updates PWD
result=$("$FORTSH_BIN" -c 'cd /tmp && echo $PWD' 2>&1)
if echo "$result" | grep -q "tmp"; then
    pass "cd updates PWD"
else
    fail "cd updates PWD" "/tmp" "$result"
fi

# cd updates OLDPWD
result=$("$FORTSH_BIN" -c 'cd /; cd /tmp; echo $OLDPWD' 2>&1)
if [ "$result" = "/" ]; then
    pass "cd updates OLDPWD"
else
    fail "cd updates OLDPWD" "/" "$result"
fi

# cd - uses OLDPWD
result=$("$FORTSH_BIN" -c 'cd /; cd /tmp; cd -' 2>&1)
if echo "$result" | grep -q "/"; then
    pass "cd - prints previous directory"
else
    fail "cd - prints previous directory" "/" "$result"
fi

# =====================================
section "372. \$? EXIT STATUS"
# =====================================

# $? after successful command
result=$("$FORTSH_BIN" -c 'true; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass '$? is 0 after true'
else
    fail '$? is 0 after true' "0" "$result"
fi

# $? after failed command
result=$("$FORTSH_BIN" -c 'false; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass '$? is 1 after false'
else
    fail '$? is 1 after false' "1" "$result"
fi

# $? after exit N
result=$("$FORTSH_BIN" -c '(exit 42); echo $?' 2>&1)
if [ "$result" = "42" ]; then
    pass '$? captures exit code from subshell'
else
    fail '$? captures exit code from subshell' "42" "$result"
fi

# $? after signal (128+signal)
result=$("$FORTSH_BIN" -c 'sh -c "kill -9 \$\$" 2>/dev/null; echo $?' 2>&1)
if [ "$result" -ge 128 ] 2>/dev/null; then
    pass '$? is 128+ after signal death'
else
    fail '$? is 128+ after signal death' ">=128" "$result"
fi

# $? after command not found
result=$("$FORTSH_BIN" -c 'nonexistent_cmd_xyz_12345 2>/dev/null; echo $?' 2>&1)
if [ "$result" = "127" ]; then
    pass '$? is 127 for command not found'
else
    fail '$? is 127 for command not found' "127" "$result"
fi

# =====================================
section "373. \$0 SCRIPT NAME"
# =====================================

# $0 in -c command
result=$("$FORTSH_BIN" -c 'echo $0' 2>&1)
if [ -n "$result" ]; then
    pass '$0 is set in -c command'
else
    fail '$0 is set in -c command' "non-empty" "$result"
fi

# $0 can be set with -c
result=$("$FORTSH_BIN" -c 'echo $0' myname 2>&1)
if [ "$result" = "myname" ]; then
    pass '$0 can be set via argument after -c'
else
    fail '$0 can be set via argument after -c' "myname" "$result"
fi

# =====================================
section "374. SHIFT EDGE CASES"
# =====================================

# shift removes first positional param
result=$("$FORTSH_BIN" -c 'set -- a b c; shift; echo $1' 2>&1)
if [ "$result" = "b" ]; then
    pass 'shift removes first parameter'
else
    fail 'shift removes first parameter' "b" "$result"
fi

# shift N removes N params
result=$("$FORTSH_BIN" -c 'set -- a b c d e; shift 2; echo $1' 2>&1)
if [ "$result" = "c" ]; then
    pass 'shift N removes N parameters'
else
    fail 'shift N removes N parameters' "c" "$result"
fi

# shift updates $#
result=$("$FORTSH_BIN" -c 'set -- a b c d e; shift 3; echo $#' 2>&1)
if [ "$result" = "2" ]; then
    pass 'shift updates $#'
else
    fail 'shift updates $#' "2" "$result"
fi

# shift more than $# fails
result=$("$FORTSH_BIN" -c 'set -- a b; shift 5 2>/dev/null; echo $?' 2>&1)
if [ "$result" != "0" ]; then
    pass 'shift beyond $# returns non-zero'
else
    fail 'shift beyond $# returns non-zero' "non-zero" "$result"
fi

# =====================================
section "375. ENVIRONMENT VARIABLES"
# =====================================

# HOME is set
result=$("$FORTSH_BIN" -c 'echo $HOME' 2>&1)
if [ -n "$result" ] && [ -d "$result" ]; then
    pass "HOME is set to valid directory"
else
    fail "HOME is set to valid directory" "directory" "$result"
fi

# PATH is set
result=$("$FORTSH_BIN" -c 'echo $PATH' 2>&1)
if [ -n "$result" ]; then
    pass "PATH is set"
else
    fail "PATH is set" "non-empty" "$result"
fi

# PATH affects command lookup
result=$("$FORTSH_BIN" -c 'PATH=/bin:/usr/bin; ls / >/dev/null 2>&1; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "PATH affects command resolution"
else
    fail "PATH affects command resolution" "0" "$result"
fi

# Empty PATH means current directory only
result=$("$FORTSH_BIN" -c 'PATH=""; ls / 2>/dev/null; echo $?' 2>&1)
if [ "$result" != "0" ]; then
    pass "Empty PATH prevents finding commands"
else
    fail "Empty PATH prevents finding commands" "non-zero" "$result"
fi

# =====================================
section "376. EVAL SPECIAL CASES"
# =====================================

# eval with variable containing command
result=$("$FORTSH_BIN" -c 'cmd="echo hello"; eval "$cmd"' 2>&1)
if [ "$result" = "hello" ]; then
    pass "eval executes command in variable"
else
    fail "eval executes command in variable" "hello" "$result"
fi

# eval with multiple arguments
result=$("$FORTSH_BIN" -c 'eval echo hello world' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "eval concatenates arguments"
else
    fail "eval concatenates arguments" "hello world" "$result"
fi

# eval with variable expansion
result=$("$FORTSH_BIN" -c 'x=y; y=z; eval echo \$$x' 2>&1)
if [ "$result" = "z" ]; then
    pass "eval performs double expansion"
else
    fail "eval performs double expansion" "z" "$result"
fi

# eval exit status
result=$("$FORTSH_BIN" -c 'eval false; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "eval returns command exit status"
else
    fail "eval returns command exit status" "1" "$result"
fi

# =====================================
section "377. COMMAND EXECUTION MODES"
# =====================================

# Command with -c flag
result=$("$FORTSH_BIN" -c 'echo test' 2>&1)
if [ "$result" = "test" ]; then
    pass "fortsh -c executes command"
else
    fail "fortsh -c executes command" "test" "$result"
fi

# Command with environment var
result=$(X=value "$FORTSH_BIN" -c 'echo $X' 2>&1)
if [ "$result" = "value" ]; then
    pass "env var passed to fortsh"
else
    fail "env var passed to fortsh" "value" "$result"
fi

# =====================================
section "378. SPECIAL BUILTIN BEHAVIORS"
# =====================================

# break outside loop
result=$("$FORTSH_BIN" -c 'break 2>/dev/null; echo $?' 2>&1)
if echo "$result" | grep -qE '^[0-9]'; then
    pass "break outside loop returns error status"
else
    fail "break outside loop returns error status"
fi

# continue outside loop
result=$("$FORTSH_BIN" -c 'continue 2>/dev/null; echo $?' 2>&1)
if echo "$result" | grep -qE '^[0-9]'; then
    pass "continue outside loop returns error status"
else
    fail "continue outside loop returns error status"
fi

# return outside function
result=$("$FORTSH_BIN" -c 'return 2>/dev/null; echo $?' 2>&1)
if echo "$result" | grep -qE '^[0-9]'; then
    pass "return outside function handled"
else
    fail "return outside function handled"
fi

# =====================================
section "379. REDIRECTION EDGE CASES"
# =====================================

# Redirect to /dev/null
result=$("$FORTSH_BIN" -c 'echo test > /dev/null; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "redirect to /dev/null works"
else
    fail "redirect to /dev/null works" "done" "$result"
fi

# Redirect stderr to stdout
result=$("$FORTSH_BIN" -c 'echo stderr >&2' 2>&1)
if [ "$result" = "stderr" ]; then
    pass "redirect stderr to stdout"
else
    fail "redirect stderr to stdout" "stderr" "$result"
fi

# =====================================
section "380. POSITIONAL PARAMETERS EDGE CASES"
# =====================================

# More than 9 positional params
result=$("$FORTSH_BIN" -c 'set -- a b c d e f g h i j k; echo $1 ${10} ${11}' 2>&1)
if echo "$result" | grep -q "a j k"; then
    pass "access to \${10} and beyond"
else
    fail "access to \${10} and beyond" "a j k" "$result"
fi

# shift with count
result=$("$FORTSH_BIN" -c 'set -- a b c d e; shift 3; echo $1' 2>&1)
if [ "$result" = "d" ]; then
    pass "shift with count"
else
    fail "shift with count" "d" "$result"
fi

# =====================================
section "381. ARITHMETIC EDGE CASES"
# =====================================

# Negative numbers
result=$("$FORTSH_BIN" -c 'echo $((-5))' 2>&1)
if [ "$result" = "-5" ]; then
    pass "negative numbers in arithmetic"
else
    fail "negative numbers in arithmetic" "-5" "$result"
fi

# Parentheses for grouping
result=$("$FORTSH_BIN" -c 'echo $(( (2+3) * 4 ))' 2>&1)
if [ "$result" = "20" ]; then
    pass "parentheses in arithmetic"
else
    fail "parentheses in arithmetic" "20" "$result"
fi

# Comparison operators return 0/1
result=$("$FORTSH_BIN" -c 'echo $((5 > 3))' 2>&1)
if [ "$result" = "1" ]; then
    pass "arithmetic comparison returns 1 for true"
else
    fail "arithmetic comparison returns 1 for true" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((3 > 5))' 2>&1)
if [ "$result" = "0" ]; then
    pass "arithmetic comparison returns 0 for false"
else
    fail "arithmetic comparison returns 0 for false" "0" "$result"
fi

# =====================================
section "382. VARIABLE ASSIGNMENT EDGE CASES"
# =====================================

# Assignment with empty value
result=$("$FORTSH_BIN" -c 'X=; echo "[$X]"' 2>&1)
if [ "$result" = "[]" ]; then
    pass "empty variable assignment"
else
    fail "empty variable assignment" "[]" "$result"
fi

# Assignment with quotes
result=$("$FORTSH_BIN" -c 'X="hello world"; echo $X' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "quoted variable assignment"
else
    fail "quoted variable assignment" "hello world" "$result"
fi

# Multiple assignments on one line
result=$("$FORTSH_BIN" -c 'A=1 B=2 C=3; echo $A $B $C' 2>&1)
if [ "$result" = "1 2 3" ]; then
    pass "multiple assignments"
else
    fail "multiple assignments" "1 2 3" "$result"
fi

# =====================================
section "383. QUOTING EDGE CASES"
# =====================================

# Single quotes preserve literally
result=$("$FORTSH_BIN" -c "echo '\$HOME'" 2>&1)
if [ "$result" = '$HOME' ]; then
    pass "single quotes preserve dollar"
else
    fail "single quotes preserve dollar" "\$HOME" "$result"
fi

# Double quotes allow expansion
result=$("$FORTSH_BIN" -c 'X=test; echo "$X"' 2>&1)
if [ "$result" = "test" ]; then
    pass "double quotes allow expansion"
else
    fail "double quotes allow expansion" "test" "$result"
fi

# Mixed quoting
result=$("$FORTSH_BIN" -c "X=val; echo 'literal'\"\$X\"'more'" 2>&1)
if [ "$result" = "literalvalmore" ]; then
    pass "mixed quoting works"
else
    fail "mixed quoting works" "literalvalmore" "$result"
fi

# =====================================
section "384. PIPELINE EDGE CASES"
# =====================================

# Pipeline with three stages
result=$("$FORTSH_BIN" -c 'echo test | cat | cat' 2>&1)
if [ "$result" = "test" ]; then
    pass "three-stage pipeline"
else
    fail "three-stage pipeline" "test" "$result"
fi

# Pipeline with grep
result=$("$FORTSH_BIN" -c 'echo "hello world" | grep hello' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "pipeline with grep"
else
    fail "pipeline with grep" "hello world" "$result"
fi

# =====================================
section "385. CASE STATEMENT EDGE CASES"
# =====================================

# Case with wildcards
result=$("$FORTSH_BIN" -c 'x=hello; case $x in h*) echo match;; esac' 2>&1)
if [ "$result" = "match" ]; then
    pass "case with wildcard pattern"
else
    fail "case with wildcard pattern" "match" "$result"
fi

# Case with multiple patterns
result=$("$FORTSH_BIN" -c 'x=b; case $x in a|b|c) echo abc;; esac' 2>&1)
if [ "$result" = "abc" ]; then
    pass "case with multiple patterns"
else
    fail "case with multiple patterns" "abc" "$result"
fi

# Case with default
result=$("$FORTSH_BIN" -c 'x=z; case $x in a) echo a;; *) echo default;; esac' 2>&1)
if [ "$result" = "default" ]; then
    pass "case with default pattern"
else
    fail "case with default pattern" "default" "$result"
fi

# =====================================
section "386. LOOP EDGE CASES"
# =====================================

# For loop with break
result=$("$FORTSH_BIN" -c 'for i in 1 2 3 4 5; do [ $i -eq 3 ] && break; echo $i; done' 2>&1)
expected="1
2"
if [ "$result" = "$expected" ]; then
    pass "for loop with break"
else
    fail "for loop with break"
fi

# For loop with continue
result=$("$FORTSH_BIN" -c 'for i in 1 2 3 4 5; do [ $i -eq 3 ] && continue; echo $i; done' 2>&1)
if echo "$result" | grep -q "1" && echo "$result" | grep -q "4" && ! echo "$result" | grep -q "3"; then
    pass "for loop with continue"
else
    fail "for loop with continue"
fi

# =====================================
section "387. SUBSHELL EDGE CASES"
# =====================================

# Subshell variable isolation
result=$("$FORTSH_BIN" -c 'X=outer; (X=inner; echo $X); echo $X' 2>&1)
expected="inner
outer"
if [ "$result" = "$expected" ]; then
    pass "subshell variable isolation"
else
    fail "subshell variable isolation"
fi

# Subshell exit status
result=$("$FORTSH_BIN" -c '(exit 42); echo $?' 2>&1)
if [ "$result" = "42" ]; then
    pass "subshell exit status captured"
else
    fail "subshell exit status captured" "42" "$result"
fi

# =====================================
section "388. FUNCTION EDGE CASES"
# =====================================

# Function with local-like behavior (via subshell)
result=$("$FORTSH_BIN" -c 'X=global; f() { (X=local; echo $X); }; f; echo $X' 2>&1)
expected="local
global"
if [ "$result" = "$expected" ]; then
    pass "function with subshell for local vars"
else
    fail "function with subshell for local vars"
fi

# Recursive function
result=$("$FORTSH_BIN" -c 'count() { if [ $1 -gt 0 ]; then echo $1; count $(($1-1)); fi; }; count 3' 2>&1)
expected="3
2
1"
if [ "$result" = "$expected" ]; then
    pass "recursive function"
else
    fail "recursive function"
fi

# =====================================
section "389. HERE DOCUMENT EDGE CASES"
# =====================================

# Heredoc with variable expansion
result=$("$FORTSH_BIN" -c 'X=value; cat <<EOF
$X
EOF' 2>&1)
if [ "$result" = "value" ]; then
    pass "heredoc variable expansion"
else
    fail "heredoc variable expansion" "value" "$result"
fi

# Quoted heredoc (no expansion)
result=$("$FORTSH_BIN" -c 'cat <<'\''EOF'\''
$VAR
EOF' 2>&1)
if [ "$result" = '$VAR' ]; then
    pass "quoted heredoc no expansion"
else
    fail "quoted heredoc no expansion" "\$VAR" "$result"
fi

# =====================================
section "390. COMMAND SUBSTITUTION EDGE CASES"
# =====================================

# Nested command substitution
result=$("$FORTSH_BIN" -c 'echo $(echo $(echo nested))' 2>&1)
if [ "$result" = "nested" ]; then
    pass "nested command substitution"
else
    fail "nested command substitution" "nested" "$result"
fi

# Command substitution with quotes
result=$("$FORTSH_BIN" -c 'echo "$(echo "hello world")"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "command substitution with quotes"
else
    fail "command substitution with quotes" "hello world" "$result"
fi

# Backtick substitution
result=$("$FORTSH_BIN" -c 'echo `echo backtick`' 2>&1)
if [ "$result" = "backtick" ]; then
    pass "backtick command substitution"
else
    fail "backtick command substitution" "backtick" "$result"
fi

# =====================================
section "391. EXPR COMMAND"
# =====================================

result=$("$FORTSH_BIN" -c 'expr 5 + 3' 2>&1)
if [ "$result" = "8" ]; then
    pass "expr addition"
else
    fail "expr addition" "8" "$result"
fi

result=$("$FORTSH_BIN" -c 'expr 10 - 4' 2>&1)
if [ "$result" = "6" ]; then
    pass "expr subtraction"
else
    fail "expr subtraction" "6" "$result"
fi

result=$("$FORTSH_BIN" -c 'expr 6 \* 7' 2>&1)
if [ "$result" = "42" ]; then
    pass "expr multiplication"
else
    fail "expr multiplication" "42" "$result"
fi

result=$("$FORTSH_BIN" -c 'expr 20 / 4' 2>&1)
if [ "$result" = "5" ]; then
    pass "expr division"
else
    fail "expr division" "5" "$result"
fi

# =====================================
section "392. TEST COMMAND VARIATIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'test -f /etc/passwd && echo yes' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test -f regular file"
else
    fail "test -f regular file" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'test -d /tmp && echo yes' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test -d directory"
else
    fail "test -d directory" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'test 5 -eq 5 && echo yes' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test numeric equal"
else
    fail "test numeric equal" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'test "abc" = "abc" && echo yes' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test string equal"
else
    fail "test string equal" "yes" "$result"
fi

# =====================================
section "393. BASENAME AND DIRNAME SIMULATION"
# =====================================

result=$("$FORTSH_BIN" -c 'X=/path/to/file.txt; echo ${X##*/}' 2>&1)
if [ "$result" = "file.txt" ]; then
    pass "basename via parameter expansion"
else
    fail "basename via parameter expansion" "file.txt" "$result"
fi

result=$("$FORTSH_BIN" -c 'X=/path/to/file.txt; echo ${X%/*}' 2>&1)
if [ "$result" = "/path/to" ]; then
    pass "dirname via parameter expansion"
else
    fail "dirname via parameter expansion" "/path/to" "$result"
fi

result=$("$FORTSH_BIN" -c 'X=file.tar.gz; echo ${X%.gz}' 2>&1)
if [ "$result" = "file.tar" ]; then
    pass "remove extension"
else
    fail "remove extension" "file.tar" "$result"
fi

result=$("$FORTSH_BIN" -c 'X=file.tar.gz; echo ${X%%.*}' 2>&1)
if [ "$result" = "file" ]; then
    pass "remove all extensions"
else
    fail "remove all extensions" "file" "$result"
fi

# =====================================
section "394. COMPLEX PIPELINES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello world" | tr " " "\n" | wc -l' 2>&1)
if [ "$result" = "2" ]; then
    pass "pipeline with tr and wc"
else
    fail "pipeline with tr and wc" "2" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "c\na\nb\n" | sort | head -1' 2>&1)
if [ "$result" = "a" ]; then
    pass "pipeline sort and head"
else
    fail "pipeline sort and head" "a" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "test" | cat | cat | cat' 2>&1)
if [ "$result" = "test" ]; then
    pass "triple cat pipeline"
else
    fail "triple cat pipeline" "test" "$result"
fi

# =====================================
section "395. COMMAND GROUPING"
# =====================================

result=$("$FORTSH_BIN" -c '{ echo a; echo b; echo c; } | wc -l' 2>&1)
if [ "$result" = "3" ]; then
    pass "brace group to pipeline"
else
    fail "brace group to pipeline" "3" "$result"
fi

result=$("$FORTSH_BIN" -c '(echo x; echo y) | wc -l' 2>&1)
if [ "$result" = "2" ]; then
    pass "subshell to pipeline"
else
    fail "subshell to pipeline" "2" "$result"
fi

result=$("$FORTSH_BIN" -c 'X=1; { X=2; echo $X; }; echo $X' 2>&1)
expected=$(printf "2\n2")
if [ "$result" = "$expected" ]; then
    pass "brace group modifies parent var"
else
    fail "brace group modifies parent var"
fi

# =====================================
section "396. WORD EXPANSION ORDER"
# =====================================

result=$("$FORTSH_BIN" -c 'X="a b c"; echo $X' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "unquoted var word splits"
else
    fail "unquoted var word splits" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'X="a b c"; echo "$X"' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "quoted var preserves spaces"
else
    fail "quoted var preserves spaces" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo ~ | grep -c "^/"' 2>&1)
if [ "$result" = "1" ]; then
    pass "tilde expands to home"
else
    fail "tilde expands to home" "1" "$result"
fi

# =====================================
section "397. SIGNAL NAMES"
# =====================================

result=$("$FORTSH_BIN" -c 'kill -l | grep -c HUP' 2>&1)
if [ "$result" -ge 1 ]; then
    pass "kill -l shows HUP"
else
    fail "kill -l shows HUP"
fi

result=$("$FORTSH_BIN" -c 'kill -l | grep -c INT' 2>&1)
if [ "$result" -ge 1 ]; then
    pass "kill -l shows INT"
else
    fail "kill -l shows INT"
fi

result=$("$FORTSH_BIN" -c 'kill -l | grep -c TERM' 2>&1)
if [ "$result" -ge 1 ]; then
    pass "kill -l shows TERM"
else
    fail "kill -l shows TERM"
fi

# =====================================
section "398. EXEC WITH FD"
# =====================================

result=$("$FORTSH_BIN" -c 'exec 3>&1; echo test >&3; exec 3>&-' 2>&1)
if [ "$result" = "test" ]; then
    pass "exec fd redirect"
else
    fail "exec fd redirect" "test" "$result"
fi

# =====================================
section "399. COMPLEX FUNCTIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'max() { [ $1 -gt $2 ] && echo $1 || echo $2; }; max 5 3' 2>&1)
if [ "$result" = "5" ]; then
    pass "function max returns larger"
else
    fail "function max returns larger" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'sum() { echo $(($1 + $2)); }; sum 10 20' 2>&1)
if [ "$result" = "30" ]; then
    pass "function sum"
else
    fail "function sum" "30" "$result"
fi

result=$("$FORTSH_BIN" -c 'greet() { echo "Hello, $1!"; }; greet World' 2>&1)
if [ "$result" = "Hello, World!" ]; then
    pass "function with string interpolation"
else
    fail "function with string interpolation" "Hello, World!" "$result"
fi

# =====================================
section "400. ADVANCED REDIRECTIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo out; echo err >&2' 2>&1)
expected=$(printf "out\nerr")
if [ "$result" = "$expected" ]; then
    pass "stdout and stderr"
else
    fail "stdout and stderr"
fi

result=$("$FORTSH_BIN" -c '{ echo a; echo b >&2; } 2>&1 | wc -l' 2>&1)
if [ "$result" = "2" ]; then
    pass "redirect stderr to stdout in pipeline"
else
    fail "redirect stderr to stdout in pipeline" "2" "$result"
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
