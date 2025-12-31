#!/bin/sh
# =====================================
# POSIX Compliance Shell Options and Read Builtin Test Suite for fortsh
# =====================================
# Tests set options and read builtin per IEEE Std 1003.1-2017
# Section: Shell Command Language - set, read

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-options]"
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
section "381. SET -e (ERREXIT)"
# =====================================

result=$("$FORTSH_BIN" -c 'set -e; true; echo reached' 2>&1)
if [ "$result" = "reached" ]; then
    pass "set -e allows true command"
else
    fail "set -e allows true command" "reached" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -e; false; echo "should not reach"' 2>&1)
if [ -z "$result" ] || ! echo "$result" | grep -q "should not reach"; then
    pass "set -e exits on false"
else
    fail "set -e exits on false" "(no output)" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -e; if false; then echo no; fi; echo reached' 2>&1)
if [ "$result" = "reached" ]; then
    pass "set -e ignores false in if condition"
else
    fail "set -e ignores false in if condition" "reached" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -e; false || echo fallback' 2>&1)
if [ "$result" = "fallback" ]; then
    pass "set -e ignores false with || continuation"
else
    fail "set -e ignores false with || continuation" "fallback" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -e; ! false; echo reached' 2>&1)
if [ "$result" = "reached" ]; then
    pass "set -e ignores negated false"
else
    fail "set -e ignores negated false" "reached" "$result"
fi

# =====================================
section "382. SET -u (NOUNSET)"
# =====================================

result=$("$FORTSH_BIN" -c 'set -u; x=hello; echo $x' 2>&1)
if [ "$result" = "hello" ]; then
    pass "set -u allows set variable"
else
    fail "set -u allows set variable" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -u; echo $UNSET_VAR_12345' 2>&1)
exit_code=$?
if echo "$result" | grep -qi "unbound\|unset\|error" || [ $exit_code -ne 0 ]; then
    pass "set -u errors on unset variable"
else
    fail "set -u errors on unset variable" "error message" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -u; echo ${UNSET_VAR_12345:-default}' 2>&1)
if [ "$result" = "default" ]; then
    pass "set -u allows default expansion"
else
    fail "set -u allows default expansion" "default" "$result"
fi

# =====================================
section "383. SET -f (NOGLOB)"
# =====================================

result=$("$FORTSH_BIN" -c 'set -f; echo *' 2>&1)
if [ "$result" = "*" ]; then
    pass "set -f disables globbing"
else
    fail "set -f disables globbing" "*" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -f; echo [a-z]*' 2>&1)
if [ "$result" = "[a-z]*" ]; then
    pass "set -f disables bracket patterns"
else
    fail "set -f disables bracket patterns" "[a-z]*" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -f; set +f; cd /tmp && echo [a-z]* | head -c 20' 2>&1)
if [ "$result" != "[a-z]*" ] && [ -n "$result" ]; then
    pass "set +f re-enables globbing"
else
    fail "set +f re-enables globbing" "(expanded)" "$result"
fi

# =====================================
section "384. SET -n (NOEXEC)"
# =====================================

result=$("$FORTSH_BIN" -c 'set -n; echo hello' 2>&1)
if [ -z "$result" ]; then
    pass "set -n prevents execution"
else
    fail "set -n prevents execution" "(empty)" "$result"
fi

# =====================================
section "385. SET -x (XTRACE)"
# =====================================

result=$("$FORTSH_BIN" -c 'set -x; echo hello' 2>&1)
if echo "$result" | grep -q "echo hello\|+ echo"; then
    pass "set -x shows trace output"
else
    fail "set -x shows trace output" "trace line" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -x; x=5; echo $x' 2>&1)
if echo "$result" | grep -qE "x=5|echo 5|\+ echo"; then
    pass "set -x traces variable assignment"
else
    fail "set -x traces variable assignment" "trace lines" "$result"
fi

# =====================================
section "386. SET -v (VERBOSE)"
# =====================================

result=$("$FORTSH_BIN" -c 'set -v; echo hello' 2>&1)
if echo "$result" | grep -q "echo hello"; then
    pass "set -v shows input lines"
else
    fail "set -v shows input lines" "input echoed" "$result"
fi

# =====================================
section "387. SET -C (NOCLOBBER)"
# =====================================

TEST_DIR="/tmp/fortsh_options_$$"
mkdir -p "$TEST_DIR"

result=$("$FORTSH_BIN" -c 'set -C; echo test > '"$TEST_DIR"'/clobber1; echo test2 > '"$TEST_DIR"'/clobber1' 2>&1)
if echo "$result" | grep -qi "exist\|cannot\|error\|clobber"; then
    pass "set -C prevents clobbering existing file"
else
    # Check if file still has original content
    if [ -f "$TEST_DIR/clobber1" ]; then
        content=$(cat "$TEST_DIR/clobber1")
        if [ "$content" = "test" ]; then
            pass "set -C prevents clobbering existing file"
        else
            fail "set -C prevents clobbering existing file" "error or original content" "$result"
        fi
    else
        fail "set -C prevents clobbering existing file" "error message" "$result"
    fi
fi

rm -rf "$TEST_DIR"

# =====================================
section "388. SET -o OPTIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'set -o errexit; true; echo ok' 2>&1)
if [ "$result" = "ok" ]; then
    pass "set -o errexit (same as -e)"
else
    fail "set -o errexit (same as -e)" "ok" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -o noglob; echo *' 2>&1)
if [ "$result" = "*" ]; then
    pass "set -o noglob (same as -f)"
else
    fail "set -o noglob (same as -f)" "*" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -o nounset; x=val; echo $x' 2>&1)
if [ "$result" = "val" ]; then
    pass "set -o nounset (same as -u)"
else
    fail "set -o nounset (same as -u)" "val" "$result"
fi

# =====================================
section "389. SET -- POSITIONAL PARAMETERS"
# =====================================

result=$("$FORTSH_BIN" -c 'set -- a b c; echo $1 $2 $3' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "set -- sets positional parameters"
else
    fail "set -- sets positional parameters" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c d e; echo $#' 2>&1)
if [ "$result" = "5" ]; then
    pass "set -- updates \$#"
else
    fail "set -- updates \$#" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c; set --; echo $#' 2>&1)
if [ "$result" = "0" ]; then
    pass "set -- clears positional parameters"
else
    fail "set -- clears positional parameters" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- "a b" c; echo $1' 2>&1)
if [ "$result" = "a b" ]; then
    pass "set -- preserves quoted args"
else
    fail "set -- preserves quoted args" "a b" "$result"
fi

# =====================================
section "390. READ BUILTIN BASIC"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello" | { read x; echo $x; }' 2>&1)
if [ "$result" = "hello" ]; then
    pass "read basic input"
else
    fail "read basic input" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "one two three" | { read a b c; echo "$a|$b|$c"; }' 2>&1)
if [ "$result" = "one|two|three" ]; then
    pass "read multiple variables"
else
    fail "read multiple variables" "one|two|three" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "one two three four" | { read a b; echo "$a|$b"; }' 2>&1)
if [ "$result" = "one|two three four" ]; then
    pass "read remaining into last variable"
else
    fail "read remaining into last variable" "one|two three four" "$result"
fi

# =====================================
section "391. READ WITH IFS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "a:b:c" | { IFS=: read x y z; echo "$x|$y|$z"; }' 2>&1)
if [ "$result" = "a|b|c" ]; then
    pass "read with custom IFS"
else
    fail "read with custom IFS" "a|b|c" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "a::c" | { IFS=: read x y z; echo "$x|$y|$z"; }' 2>&1)
if [ "$result" = "a||c" ]; then
    pass "read with empty field"
else
    fail "read with empty field" "a||c" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "  a  b  " | { read x y; echo ">$x|$y<"; }' 2>&1)
if [ "$result" = ">a|b<" ]; then
    pass "read strips leading/trailing whitespace"
else
    fail "read strips leading/trailing whitespace" ">a|b<" "$result"
fi

# =====================================
section "392. READ -r (RAW MODE)"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello\\nworld" | { read -r x; echo "$x"; }' 2>&1)
if [ "$result" = 'hello\nworld' ]; then
    pass "read -r preserves backslashes"
else
    fail "read -r preserves backslashes" 'hello\nworld' "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "line\\\ncontinued\n" | { read x; echo "$x"; }' 2>&1)
if [ "$result" = "linecontinued" ]; then
    pass "read without -r joins continued lines"
else
    fail "read without -r joins continued lines" "linecontinued" "$result"
fi

# =====================================
section "393. READ EXIT STATUS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "test" | { read x; echo $?; }' 2>&1)
if [ "$result" = "0" ]; then
    pass "read returns 0 on success"
else
    fail "read returns 0 on success" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo -n "" | { read x; echo $?; }' 2>&1)
if [ "$result" = "1" ]; then
    pass "read returns non-zero on EOF"
else
    fail "read returns non-zero on EOF" "1" "$result"
fi

# =====================================
section "394. SHIFT BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'set -- a b c d; shift; echo $1 $2 $3' 2>&1)
if [ "$result" = "b c d" ]; then
    pass "shift removes first parameter"
else
    fail "shift removes first parameter" "b c d" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c d e; shift 2; echo $1 $2 $3' 2>&1)
if [ "$result" = "c d e" ]; then
    pass "shift n removes n parameters"
else
    fail "shift n removes n parameters" "c d e" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c; shift; echo $#' 2>&1)
if [ "$result" = "2" ]; then
    pass "shift updates \$#"
else
    fail "shift updates \$#" "2" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a; shift 5 2>/dev/null; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "shift beyond count returns error"
else
    fail "shift beyond count returns error" "1" "$result"
fi

# =====================================
section "395. SPECIAL PARAMETERS"
# =====================================

result=$("$FORTSH_BIN" -c 'set -- a b c; echo "$@"' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "\$@ expands all positional parameters"
else
    fail "\$@ expands all positional parameters" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c; echo "$*"' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "\$* expands all positional parameters"
else
    fail "\$* expands all positional parameters" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c; for x in "$@"; do echo "[$x]"; done' 2>&1)
expected=$(printf "[a]\n[b]\n[c]")
if [ "$result" = "$expected" ]; then
    pass "\"\$@\" preserves separate arguments"
else
    fail "\"\$@\" preserves separate arguments" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- "a b" c; for x in "$@"; do echo "[$x]"; done' 2>&1)
expected=$(printf "[a b]\n[c]")
if [ "$result" = "$expected" ]; then
    pass "\"\$@\" preserves quoted arguments"
else
    fail "\"\$@\" preserves quoted arguments" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $$' 2>&1)
if echo "$result" | grep -qE '^[0-9]+$' && [ "$result" -gt 0 ]; then
    pass "\$\$ returns PID"
else
    fail "\$\$ returns PID" "numeric PID" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "\$? returns exit status"
else
    fail "\$? returns exit status" "0" "$result"
fi

# =====================================
section "396. IFS WORD SPLITTING"
# =====================================

result=$("$FORTSH_BIN" -c 'x="a:b:c"; IFS=:; for w in $x; do echo "[$w]"; done' 2>&1)
expected=$(printf "[a]\n[b]\n[c]")
if [ "$result" = "$expected" ]; then
    pass "IFS changes word splitting"
else
    fail "IFS changes word splitting" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a::c"; IFS=:; set -- $x; echo $#' 2>&1)
if [ "$result" = "3" ]; then
    pass "IFS empty fields create arguments"
else
    fail "IFS empty fields create arguments" "3" "$result"
fi

result=$("$FORTSH_BIN" -c 'IFS=:; x="a:b:c"; echo $x' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "IFS affects echo output"
else
    fail "IFS affects echo output" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'IFS=""; x="a b c"; for w in $x; do echo "[$w]"; done' 2>&1)
if [ "$result" = "[a b c]" ]; then
    pass "Empty IFS prevents splitting"
else
    fail "Empty IFS prevents splitting" "[a b c]" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset IFS; x="a  b"; echo $x' 2>&1)
if [ "$result" = "a b" ]; then
    pass "unset IFS uses default"
else
    fail "unset IFS uses default" "a b" "$result"
fi

result=$("$FORTSH_BIN" -c 'IFS=",;"; x="a,b;c"; set -- $x; echo $1 $2 $3' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "IFS with multiple characters"
else
    fail "IFS with multiple characters" "a b c" "$result"
fi

# =====================================
section "397. ALIAS BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'alias ll="ls -la"; alias ll' 2>&1)
if echo "$result" | grep -q "ls -la\|ll="; then
    pass "alias defines and shows alias"
else
    fail "alias defines and shows alias" "ls -la" "$result"
fi

result=$("$FORTSH_BIN" -c 'alias greeting="echo hello"; greeting' 2>&1)
if [ "$result" = "hello" ]; then
    pass "alias expands in command"
else
    fail "alias expands in command" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'alias x="echo a"; alias y="echo b"; alias | wc -l' 2>&1)
if [ "$result" -ge 2 ] 2>/dev/null; then
    pass "alias lists all aliases"
else
    fail "alias lists all aliases" "at least 2" "$result"
fi

result=$("$FORTSH_BIN" -c 'alias greet="echo hi"; unalias greet; greet 2>/dev/null; echo $?' 2>&1)
if echo "$result" | grep -qE "127|1"; then
    pass "unalias removes alias"
else
    fail "unalias removes alias" "non-zero exit" "$result"
fi

result=$("$FORTSH_BIN" -c 'alias foo="echo one"; alias foo="echo two"; foo' 2>&1)
if [ "$result" = "two" ]; then
    pass "alias can be redefined"
else
    fail "alias can be redefined" "two" "$result"
fi

# =====================================
section "398. EXPORT BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'export TESTVAR=hello; echo $TESTVAR' 2>&1)
if [ "$result" = "hello" ]; then
    pass "export sets and exports variable"
else
    fail "export sets and exports variable" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'MYVAR=world; export MYVAR; echo $MYVAR' 2>&1)
if [ "$result" = "world" ]; then
    pass "export existing variable"
else
    fail "export existing variable" "world" "$result"
fi

result=$("$FORTSH_BIN" -c 'export X=1 Y=2 Z=3; echo $X $Y $Z' 2>&1)
if [ "$result" = "1 2 3" ]; then
    pass "export multiple variables"
else
    fail "export multiple variables" "1 2 3" "$result"
fi

result=$("$FORTSH_BIN" -c 'export SUBTEST=value; sh -c "echo \$SUBTEST"' 2>&1)
if [ "$result" = "value" ]; then
    pass "exported var visible in subshell"
else
    fail "exported var visible in subshell" "value" "$result"
fi

# =====================================
section "399. READONLY BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'readonly CONST=42; echo $CONST' 2>&1)
if [ "$result" = "42" ]; then
    pass "readonly sets variable"
else
    fail "readonly sets variable" "42" "$result"
fi

result=$("$FORTSH_BIN" -c 'readonly RO=1; RO=2 2>&1; echo $RO' 2>&1)
if echo "$result" | grep -q "1"; then
    pass "readonly prevents modification"
else
    fail "readonly prevents modification" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'readonly A=1 B=2; echo $A $B' 2>&1)
if [ "$result" = "1 2" ]; then
    pass "readonly multiple variables"
else
    fail "readonly multiple variables" "1 2" "$result"
fi

# =====================================
section "400. UNSET BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'x=hello; unset x; echo "${x:-unset}"' 2>&1)
if [ "$result" = "unset" ]; then
    pass "unset removes variable"
else
    fail "unset removes variable" "unset" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=1; y=2; unset x y; echo "${x:-a} ${y:-b}"' 2>&1)
if [ "$result" = "a b" ]; then
    pass "unset multiple variables"
else
    fail "unset multiple variables" "a b" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { echo hi; }; unset -f f; type f 2>/dev/null; echo $?' 2>&1)
if echo "$result" | grep -qE "1|127"; then
    pass "unset -f removes function"
else
    fail "unset -f removes function" "non-zero exit" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Shell Options and Read Summary\n"
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
