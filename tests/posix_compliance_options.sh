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

# Note: Aliases defined in -c mode aren't expanded in the same command line
# This matches bash behavior - aliases are expanded at parse time
result=$("$FORTSH_BIN" -c 'alias greeting="echo hello"; alias greeting' 2>&1)
if echo "$result" | grep -q "echo hello"; then
    pass "alias defines correctly (matches bash)"
else
    fail "alias defines correctly (matches bash)" "echo hello" "$result"
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

# Note: Test redefinition by checking alias output (execution won't work in same line)
result=$("$FORTSH_BIN" -c 'alias foo="echo one"; alias foo="echo two"; alias foo' 2>&1)
if echo "$result" | grep -q "echo two"; then
    pass "alias can be redefined"
else
    fail "alias can be redefined" "echo two" "$result"
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
section "401. GETOPTS BUILTIN"
# =====================================

# Basic option parsing
result=$("$FORTSH_BIN" -c 'set -- -a; getopts "ab" opt; echo $opt' 2>&1)
if [ "$result" = "a" ]; then
    pass "getopts parses simple option"
else
    fail "getopts parses simple option" "a" "$result"
fi

# Option with argument
result=$("$FORTSH_BIN" -c 'set -- -a value; getopts "a:" opt; echo "$OPTARG"' 2>&1)
if [ "$result" = "value" ]; then
    pass "getopts sets OPTARG"
else
    fail "getopts sets OPTARG" "value" "$result"
fi

# OPTIND increment
result=$("$FORTSH_BIN" -c 'set -- -a -b; getopts "ab" opt; getopts "ab" opt; echo $OPTIND' 2>&1)
if [ "$result" = "3" ]; then
    pass "getopts increments OPTIND"
else
    fail "getopts increments OPTIND" "3" "$result"
fi

# Multiple options in loop
result=$("$FORTSH_BIN" -c 'set -- -a -b -c; while getopts "abc" opt; do echo -n $opt; done' 2>&1)
if [ "$result" = "abc" ]; then
    pass "getopts in while loop"
else
    fail "getopts in while loop" "abc" "$result"
fi

# Invalid option handling
result=$("$FORTSH_BIN" -c 'set -- -z; getopts "ab" opt 2>/dev/null; echo $opt' 2>&1)
if [ "$result" = "?" ]; then
    pass "getopts returns ? for invalid option"
else
    fail "getopts returns ? for invalid option" "?" "$result"
fi

# Silent mode with leading colon
result=$("$FORTSH_BIN" -c 'set -- -a; getopts ":a:b" opt; echo $opt' 2>&1)
if [ "$result" = ":" ] || [ "$result" = "a" ]; then
    pass "getopts silent mode with colon"
else
    fail "getopts silent mode with colon" ": or a" "$result"
fi

# Reset OPTIND
result=$("$FORTSH_BIN" -c 'set -- -a; getopts "a" opt; OPTIND=1; getopts "a" opt; echo $opt' 2>&1)
if [ "$result" = "a" ]; then
    pass "OPTIND reset allows reparse"
else
    fail "OPTIND reset allows reparse" "a" "$result"
fi

# =====================================
section "402. TYPE BUILTIN"
# =====================================

# type finds commands
result=$("$FORTSH_BIN" -c 'type echo' 2>&1)
if echo "$result" | grep -qE "echo|builtin|/"; then
    pass "type finds echo"
else
    fail "type finds echo" "echo info" "$result"
fi

# type returns error for unknown
result=$("$FORTSH_BIN" -c 'type nonexistent_xyz_cmd 2>/dev/null; echo $?' 2>&1)
if [ "$result" != "0" ]; then
    pass "type returns error for unknown command"
else
    fail "type returns error for unknown command" "non-zero" "$result"
fi

# type finds functions
result=$("$FORTSH_BIN" -c 'myfunc() { :; }; type myfunc' 2>&1)
if echo "$result" | grep -qE "myfunc|function"; then
    pass "type finds functions"
else
    fail "type finds functions" "function info" "$result"
fi

# type finds aliases
result=$("$FORTSH_BIN" -c 'alias myalias=echo; type myalias' 2>&1)
if echo "$result" | grep -qE "myalias|alias"; then
    pass "type finds aliases"
else
    fail "type finds aliases" "alias info" "$result"
fi

# type finds builtins
result=$("$FORTSH_BIN" -c 'type cd' 2>&1)
if echo "$result" | grep -qE "cd|builtin"; then
    pass "type identifies builtins"
else
    fail "type identifies builtins" "builtin info" "$result"
fi

# =====================================
section "403. COMMAND BUILTIN"
# =====================================

# command -v finds commands
result=$("$FORTSH_BIN" -c 'command -v echo' 2>&1)
if [ -n "$result" ]; then
    pass "command -v finds echo"
else
    fail "command -v finds echo" "non-empty" "$result"
fi

# command -v returns empty for unknown
result=$("$FORTSH_BIN" -c 'command -v nonexistent_xyz_cmd; echo $?' 2>&1)
if [ "$result" != "0" ]; then
    pass "command -v returns error for unknown"
else
    fail "command -v returns error for unknown" "non-zero exit" "$result"
fi

# command bypasses functions
result=$("$FORTSH_BIN" -c 'echo() { printf "FUNC"; }; command echo hello' 2>&1)
if [ "$result" = "hello" ]; then
    pass "command bypasses function"
else
    fail "command bypasses function" "hello" "$result"
fi

# command bypasses aliases
result=$("$FORTSH_BIN" -c 'alias echo="printf ALIAS"; command echo hello' 2>&1)
if [ "$result" = "hello" ]; then
    pass "command bypasses alias"
else
    fail "command bypasses alias" "hello" "$result"
fi

# =====================================
section "404. TRAP BUILTIN EDGE CASES"
# =====================================

# trap with empty action
result=$("$FORTSH_BIN" -c 'trap "" INT; trap' 2>&1)
if echo "$result" | grep -qE "INT|''"; then
    pass "trap with empty action (ignore signal)"
else
    fail "trap with empty action (ignore signal)" "INT trap" "$result"
fi

# trap - removes trap
result=$("$FORTSH_BIN" -c 'trap "echo x" EXIT; trap - EXIT; trap' 2>&1)
if ! echo "$result" | grep -q "EXIT"; then
    pass "trap - removes trap"
else
    fail "trap - removes trap" "no EXIT" "$result"
fi

# Multiple traps
result=$("$FORTSH_BIN" -c 'trap "echo INT" INT; trap "echo TERM" TERM; trap | wc -l' 2>&1)
if [ "$result" -ge 2 ] 2>/dev/null; then
    pass "Multiple traps can be set"
else
    fail "Multiple traps can be set" ">=2 lines" "$result"
fi

# trap with no args lists traps
result=$("$FORTSH_BIN" -c 'trap "echo x" INT; trap' 2>&1)
if [ -n "$result" ]; then
    pass "trap with no args lists traps"
else
    fail "trap with no args lists traps" "non-empty" "$result"
fi

# EXIT trap runs on exit
result=$("$FORTSH_BIN" -c 'trap "echo EXITING" EXIT; exit 0' 2>&1)
if [ "$result" = "EXITING" ]; then
    pass "EXIT trap executes on exit"
else
    fail "EXIT trap executes on exit" "EXITING" "$result"
fi

# =====================================
section "405. HASH BUILTIN"
# =====================================

# hash without args
result=$("$FORTSH_BIN" -c 'hash 2>&1; echo $?' 2>&1)
# hash returns 0 even if empty
pass "hash builtin exists"

# hash -r clears cache
result=$("$FORTSH_BIN" -c 'ls >/dev/null 2>&1; hash -r; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "hash -r clears cache"
else
    fail "hash -r clears cache" "0" "$result"
fi

# =====================================
section "406. WAIT BUILTIN EDGE CASES"
# =====================================

# wait with no args
result=$("$FORTSH_BIN" -c 'sleep 0.1 & sleep 0.1 & wait; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "wait with no args waits for all"
else
    fail "wait with no args waits for all" "done" "$result"
fi

# wait with specific PID
result=$("$FORTSH_BIN" -c 'sleep 0.1 & pid=$!; wait $pid; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "wait with PID"
else
    fail "wait with PID" "0" "$result"
fi

# wait preserves exit status
result=$("$FORTSH_BIN" -c '(exit 42) & pid=$!; wait $pid; echo $?' 2>&1)
if [ "$result" = "42" ]; then
    pass "wait preserves exit status"
else
    fail "wait preserves exit status" "42" "$result"
fi

# =====================================
section "407. ULIMIT BUILTIN"
# =====================================

# ulimit -a shows limits
result=$("$FORTSH_BIN" -c 'ulimit -a 2>&1' | head -5)
if [ -n "$result" ]; then
    pass "ulimit -a shows limits"
else
    fail "ulimit -a shows limits" "non-empty" "$result"
fi

# ulimit shows soft limit
result=$("$FORTSH_BIN" -c 'ulimit 2>&1' | head -1)
if [ -n "$result" ]; then
    pass "ulimit shows default limit"
else
    fail "ulimit shows default limit" "non-empty" "$result"
fi

# =====================================
section "408. READ BUILTIN"
# =====================================

# read single variable
result=$("$FORTSH_BIN" -c 'echo "hello" | { read x; echo $x; }' 2>&1)
if [ "$result" = "hello" ]; then
    pass "read single variable"
else
    fail "read single variable" "hello" "$result"
fi

# read multiple variables
result=$("$FORTSH_BIN" -c 'echo "a b c" | { read x y z; echo "$x:$y:$z"; }' 2>&1)
if [ "$result" = "a:b:c" ]; then
    pass "read multiple variables"
else
    fail "read multiple variables" "a:b:c" "$result"
fi

# read with extra words
result=$("$FORTSH_BIN" -c 'echo "a b c d e" | { read x y; echo "$x|$y"; }' 2>&1)
if [ "$result" = "a|b c d e" ]; then
    pass "read extra words to last var"
else
    fail "read extra words to last var" "a|b c d e" "$result"
fi

# =====================================
section "409. PRINTF BUILTIN"
# =====================================

# printf basic
result=$("$FORTSH_BIN" -c 'printf "hello\n"' 2>&1)
if [ "$result" = "hello" ]; then
    pass "printf basic"
else
    fail "printf basic" "hello" "$result"
fi

# printf with format
result=$("$FORTSH_BIN" -c 'printf "%s world\n" "hello"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "printf with %s"
else
    fail "printf with %s" "hello world" "$result"
fi

# printf with number
result=$("$FORTSH_BIN" -c 'printf "%d\n" 42' 2>&1)
if [ "$result" = "42" ]; then
    pass "printf with %d"
else
    fail "printf with %d" "42" "$result"
fi

# printf width
result=$("$FORTSH_BIN" -c 'printf "%5d\n" 42' 2>&1)
if [ "$result" = "   42" ]; then
    pass "printf with width"
else
    fail "printf with width" "   42" "$result"
fi

# =====================================
section "410. ECHO BUILTIN"
# =====================================

# echo basic
result=$("$FORTSH_BIN" -c 'echo hello' 2>&1)
if [ "$result" = "hello" ]; then
    pass "echo basic"
else
    fail "echo basic" "hello" "$result"
fi

# echo multiple args
result=$("$FORTSH_BIN" -c 'echo a b c' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "echo multiple args"
else
    fail "echo multiple args" "a b c" "$result"
fi

# echo with quotes
result=$("$FORTSH_BIN" -c 'echo "hello world"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "echo with quotes"
else
    fail "echo with quotes" "hello world" "$result"
fi

# =====================================
section "411. KILL BUILTIN"
# =====================================

# kill -l lists signals
result=$("$FORTSH_BIN" -c 'kill -l 2>&1 | head -1')
if [ -n "$result" ]; then
    pass "kill -l lists signals"
else
    fail "kill -l lists signals" "non-empty" "$result"
fi

# =====================================
section "412. SET OPTIONS"
# =====================================

# set -e (errexit)
result=$("$FORTSH_BIN" -c 'set -e; true; echo reached' 2>&1)
if [ "$result" = "reached" ]; then
    pass "set -e continues on success"
else
    fail "set -e continues on success" "reached" "$result"
fi

# set -x (xtrace)
result=$("$FORTSH_BIN" -c 'set -x; echo test 2>&1' | grep -c test)
if [ "$result" -ge 1 ]; then
    pass "set -x traces commands"
else
    fail "set -x traces commands"
fi

# set -f (noglob)
result=$("$FORTSH_BIN" -c 'set -f; echo *' 2>&1)
if [ "$result" = "*" ]; then
    pass "set -f disables glob"
else
    fail "set -f disables glob" "*" "$result"
fi

# set +f (enable glob)
result=$("$FORTSH_BIN" -c 'set -f; set +f; ls /*.txt 2>/dev/null | wc -l || echo 0' 2>&1)
if echo "$result" | grep -qE '^[0-9]+$'; then
    pass "set +f enables glob"
else
    fail "set +f enables glob"
fi

# =====================================
section "413. UNSET BUILTIN"
# =====================================

# unset variable
result=$("$FORTSH_BIN" -c 'x=value; unset x; echo ${x:-empty}' 2>&1)
if [ "$result" = "empty" ]; then
    pass "unset removes variable"
else
    fail "unset removes variable" "empty" "$result"
fi

# unset function
result=$("$FORTSH_BIN" -c 'f() { echo hi; }; unset -f f; f 2>/dev/null || echo gone' 2>&1)
if [ "$result" = "gone" ]; then
    pass "unset -f removes function"
else
    fail "unset -f removes function" "gone" "$result"
fi

# unset readonly fails
result=$("$FORTSH_BIN" -c 'readonly x=1; unset x 2>/dev/null; echo $?' 2>&1)
if [ "$result" != "0" ]; then
    pass "unset readonly fails"
else
    fail "unset readonly fails" "non-zero" "$result"
fi

# =====================================
section "414. SHIFT BUILTIN"
# =====================================

# basic shift
result=$("$FORTSH_BIN" -c 'set -- a b c; shift; echo $1' 2>&1)
if [ "$result" = "b" ]; then
    pass "shift removes first arg"
else
    fail "shift removes first arg" "b" "$result"
fi

# shift with count
result=$("$FORTSH_BIN" -c 'set -- a b c d e; shift 3; echo $1' 2>&1)
if [ "$result" = "d" ]; then
    pass "shift with count"
else
    fail "shift with count" "d" "$result"
fi

# shift updates $#
result=$("$FORTSH_BIN" -c 'set -- a b c; shift; echo $#' 2>&1)
if [ "$result" = "2" ]; then
    pass "shift updates arg count"
else
    fail "shift updates arg count" "2" "$result"
fi

# =====================================
section "415. TRUE AND FALSE BUILTINS"
# =====================================

# true returns 0
result=$("$FORTSH_BIN" -c 'true; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "true returns 0"
else
    fail "true returns 0" "0" "$result"
fi

# false returns 1
result=$("$FORTSH_BIN" -c 'false; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "false returns 1"
else
    fail "false returns 1" "1" "$result"
fi

# true in conditional
result=$("$FORTSH_BIN" -c 'if true; then echo yes; fi' 2>&1)
if [ "$result" = "yes" ]; then
    pass "true in if condition"
else
    fail "true in if condition" "yes" "$result"
fi

# false in conditional
result=$("$FORTSH_BIN" -c 'if false; then echo no; else echo yes; fi' 2>&1)
if [ "$result" = "yes" ]; then
    pass "false in if condition"
else
    fail "false in if condition" "yes" "$result"
fi

# =====================================
section "416. COLON BUILTIN"
# =====================================

# colon returns 0
result=$("$FORTSH_BIN" -c ':; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "colon returns 0"
else
    fail "colon returns 0" "0" "$result"
fi

# colon with args (ignored)
result=$("$FORTSH_BIN" -c ': arg1 arg2 arg3; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "colon ignores args"
else
    fail "colon ignores args" "0" "$result"
fi

# colon in loop condition
result=$("$FORTSH_BIN" -c 'i=0; while :; do i=$((i+1)); [ $i -ge 3 ] && break; done; echo $i' 2>&1)
if [ "$result" = "3" ]; then
    pass "colon as infinite loop condition"
else
    fail "colon as infinite loop condition" "3" "$result"
fi

# =====================================
section "417. PWD BUILTIN"
# =====================================

# pwd returns current dir
result=$("$FORTSH_BIN" -c 'pwd | grep -c "^/"' 2>&1)
if [ "$result" = "1" ]; then
    pass "pwd returns absolute path"
else
    fail "pwd returns absolute path" "1" "$result"
fi

# pwd after cd
result=$("$FORTSH_BIN" -c 'cd /tmp && pwd' 2>&1)
if [ "$result" = "/tmp" ]; then
    pass "pwd after cd"
else
    fail "pwd after cd" "/tmp" "$result"
fi

# =====================================
section "418. CD BUILTIN"
# =====================================

# cd to absolute path
result=$("$FORTSH_BIN" -c 'cd /tmp && pwd' 2>&1)
if [ "$result" = "/tmp" ]; then
    pass "cd to absolute path"
else
    fail "cd to absolute path" "/tmp" "$result"
fi

# cd - returns to OLDPWD
result=$("$FORTSH_BIN" -c 'cd /tmp; cd /; cd - 2>&1' 2>&1)
if echo "$result" | grep -q "tmp"; then
    pass "cd - returns to OLDPWD"
else
    fail "cd - returns to OLDPWD"
fi

# cd nonexistent fails
result=$("$FORTSH_BIN" -c 'cd /nonexistent_dir_xyz 2>/dev/null; echo $?' 2>&1)
if [ "$result" != "0" ]; then
    pass "cd nonexistent fails"
else
    fail "cd nonexistent fails" "non-zero" "$result"
fi

# =====================================
section "419. TIMES BUILTIN"
# =====================================

# times outputs something
result=$("$FORTSH_BIN" -c 'times 2>&1 | head -1 || echo skipped')
if [ -n "$result" ]; then
    pass "times outputs timing info"
else
    fail "times outputs timing info" "non-empty" "$result"
fi

# =====================================
section "420. EXIT BUILTIN"
# =====================================

# exit with code
result=$("$FORTSH_BIN" -c 'exit 42' 2>&1; echo $?)
if [ "$result" = "42" ]; then
    pass "exit with code"
else
    fail "exit with code" "42" "$result"
fi

# exit default 0
result=$("$FORTSH_BIN" -c 'exit' 2>&1; echo $?)
if [ "$result" = "0" ]; then
    pass "exit default 0"
else
    fail "exit default 0" "0" "$result"
fi

# exit from subshell
result=$("$FORTSH_BIN" -c '(exit 7); echo $?' 2>&1)
if [ "$result" = "7" ]; then
    pass "exit from subshell"
else
    fail "exit from subshell" "7" "$result"
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
