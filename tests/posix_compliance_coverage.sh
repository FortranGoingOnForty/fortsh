#!/usr/bin/env bash
# POSIX Compliance Coverage Tests - Filling Identified Gaps
# These tests cover edge cases and behaviors not covered by other test suites

FORTSH_BIN="${FORTSH_BIN:-./bin/fortsh}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-coverage]"
CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

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
    printf "${YELLOW}⊘ SKIP${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s\n" "$1"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    # Extract section number from header like "200. ARITHMETIC EDGE CASES"
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Normalize output by stripping shell name prefix
normalize_output() {
    sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'
}

# Compare output between sh and fortsh
compare_posix_output() {
    test_name="$1"
    test_cmd="$2"

    posix_output=$(FORTSH_RC_FILE=/dev/null bash -c "$test_cmd" 2>&1 | normalize_output)
    posix_exit=$?

    fortsh_output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1 | normalize_output)
    fortsh_exit=$?

    if [ "$posix_output" = "$fortsh_output" ] && [ "$posix_exit" = "$fortsh_exit" ]; then
        pass "$test_name"
    else
        fail "$test_name" "$posix_output" "$fortsh_output"
    fi
}

# Normalize shell error messages by stripping shell name and "line N: " prefix
# POSIX doesn't mandate error message format, so we normalize for comparison
normalize_error() {
    echo "$1" | sed -e 's/^bash: /sh: /g' -e 's/bash: /sh: /g' -e 's/line [0-9]*: //g' -e 's/-c: //g'
}

# Compare error output, normalizing line number differences
compare_posix_error() {
    test_name="$1"
    test_cmd="$2"

    posix_output=$(FORTSH_RC_FILE=/dev/null bash -c "$test_cmd" 2>&1)
    posix_exit=$?

    fortsh_output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1)
    fortsh_exit=$?

    posix_norm=$(normalize_error "$posix_output")
    fortsh_norm=$(normalize_error "$fortsh_output")

    if [ "$posix_norm" = "$fortsh_norm" ] && [ "$posix_exit" = "$fortsh_exit" ]; then
        pass "$test_name"
    else
        fail "$test_name" "$posix_output" "$fortsh_output"
    fi
}

# Test that fortsh accepts without error
test_accepts() {
    test_name="$1"
    test_cmd="$2"

    if FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" >/dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "should succeed" "failed or not implemented"
    fi
}

# Test that command fails
test_fails() {
    test_name="$1"
    test_cmd="$2"

    if ! FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" >/dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "should fail" "succeeded unexpectedly"
    fi
}

# =====================================
# ARITHMETIC EDGE CASES
# =====================================

section "200. ARITHMETIC - OCTAL AND HEX LITERALS"

compare_posix_output "octal literal" 'echo $((010))'
compare_posix_output "hex literal lowercase" 'echo $((0xff))'
compare_posix_output "hex literal uppercase" 'echo $((0xFF))'
compare_posix_output "octal in expression" 'echo $((010 + 1))'
compare_posix_output "hex in expression" 'echo $((0x10 + 1))'
compare_posix_output "mixed bases" 'echo $((0x10 + 010 + 10))'

section "201. ARITHMETIC - NEGATIVE NUMBERS"

compare_posix_output "negative literal" 'echo $((-5))'
compare_posix_output "negative in addition" 'echo $((10 + -3))'
compare_posix_output "negative in subtraction" 'echo $((5 - -3))'
compare_posix_output "double negative" 'echo $((--5))'
compare_posix_output "negative multiplication" 'echo $((-3 * -4))'
compare_posix_output "negative division" 'echo $((-10 / 3))'
compare_posix_output "negative modulo" 'echo $((-10 % 3))'

section "202. ARITHMETIC - NESTED EXPRESSIONS"

compare_posix_output "nested arithmetic" 'echo $((1 + $((2 + 3))))'
compare_posix_output "deeply nested" 'echo $((1 + $((2 + $((3 + 4))))))'
compare_posix_output "nested with vars" 'a=5; echo $((a + $((a * 2))))'

section "203. ARITHMETIC - COMMA OPERATOR"

compare_posix_output "comma operator" 'echo $((1, 2, 3))'
compare_posix_output "comma with assignment" 'echo $((a=1, b=2, a+b))'
compare_posix_output "comma side effects" 'a=0; echo $((a=1, a=a+1, a))'

# =====================================
# WORD SPLITTING EDGE CASES
# =====================================

section "210. WORD SPLITTING - EMPTY IFS"

compare_posix_output "empty IFS no split" 'IFS=""; var="a b c"; set -- $var; echo $#'
compare_posix_output "empty IFS preserves spaces" 'IFS=""; var="a  b"; set -- $var; echo "$1"'

section "211. WORD SPLITTING - IFS VARIATIONS"

compare_posix_output "IFS whitespace only" 'IFS=" "; var="a  b"; set -- $var; echo $#'
compare_posix_output "IFS non-whitespace" 'IFS=":"; var="a:b:c"; set -- $var; echo $#'
compare_posix_output "IFS mixed" 'IFS=" :"; var="a : b"; set -- $var; echo $#'
compare_posix_output "IFS tab" 'IFS="	"; var="a	b	c"; set -- $var; echo $#'

section "212. WORD SPLITTING - $@ VS $*"

compare_posix_output "$* unquoted" 'set -- "a b" "c d"; for x in $*; do echo "[$x]"; done'
compare_posix_output "$@ unquoted" 'set -- "a b" "c d"; for x in $@; do echo "[$x]"; done'
compare_posix_output "$* quoted" 'set -- "a b" "c d"; for x in "$*"; do echo "[$x]"; done'
compare_posix_output "$@ quoted" 'set -- "a b" "c d"; for x in "$@"; do echo "[$x]"; done'
compare_posix_output "$* with IFS" 'IFS=:; set -- a b c; echo "$*"'
compare_posix_output "$@ with IFS" 'IFS=:; set -- a b c; echo "$@"'

# =====================================
# PARAMETER EXPANSION EDGE CASES
# =====================================

section "220. PARAMETER EXPANSION - EMPTY VS UNSET"

compare_posix_output ":+ empty var" 'var=""; echo "${var:+set}"'
compare_posix_output ":+ unset var" 'unset var; echo "${var:+set}"'
compare_posix_output "+ empty var" 'var=""; echo "${var+set}"'
compare_posix_output "+ unset var" 'unset var; echo "${var+set}"'
compare_posix_output ":- empty var" 'var=""; echo "${var:-default}"'
compare_posix_output "- empty var" 'var=""; echo "${var-default}"'

section "221. PARAMETER EXPANSION - ASSIGNMENT FORMS"

compare_posix_output ":= assigns when empty" 'unset var; echo "${var:=default}"; echo "$var"'
compare_posix_output "= assigns when unset" 'unset var; echo "${var=default}"; echo "$var"'
compare_posix_output ":= with empty" 'var=""; echo "${var:=default}"; echo "$var"'
compare_posix_output "= with empty" 'var=""; echo "${var=default}"; echo "$var"'

section "222. PARAMETER EXPANSION - PATTERN IN EXPANSION"

compare_posix_output "nested pattern removal" 'suffix=.txt; file=test.txt; echo "${file%$suffix}"'
compare_posix_output "var in pattern" 'pat=t; var=test; echo "${var#$pat}"'
compare_posix_output "var in suffix pattern" 'pat=st; var=test; echo "${var%$pat}"'

# =====================================
# SIGNAL AND TRAP EDGE CASES
# =====================================

section "230. TRAP - IGNORE VS RESET"

# Test trap behavior by checking patterns (bash versions may differ in exact output format)
test_trap_behavior() {
    test_name="$1"
    test_cmd="$2"
    expected_pattern="$3"

    output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1)

    if echo "$output" | grep -qE "$expected_pattern"; then
        pass "$test_name"
    else
        fail "$test_name" "expected pattern: $expected_pattern" "got: $output"
    fi
}

# trap "" INT sets ignore, trap shows it, trap - INT resets, trap shows nothing for INT
test_trap_behavior "trap ignore" 'trap "" INT; trap; trap - INT; trap' "trap.*INT"
test_trap_behavior "trap reset" 'trap "echo caught" INT; trap - INT; trap' "^$"
compare_posix_output "trap empty string" 'trap "" EXIT; echo done'

section "231. TRAP - IN SUBSHELLS"

# Non-ignored traps should show in parent but subshell inherits parent's trap display
# The EXIT trap runs when done, printing "trap"
test_trap_behavior "trap not inherited" 'trap "echo trap" EXIT; (trap); echo done' "done"
# Ignored traps ARE inherited by subshells
test_trap_behavior "ignore trap inherited" 'trap "" INT; (trap)' "trap.*INT"

section "232. TRAP - MULTIPLE SIGNALS"

compare_posix_output "trap multiple" 'trap "echo exit" EXIT; trap "echo err" ERR 2>/dev/null || true; echo done'

# =====================================
# ERROR HANDLING EDGE CASES
# =====================================

section "240. SET -e EDGE CASES"

compare_posix_output "set -e with &&" 'set -e; false && true; echo reached'
compare_posix_output "set -e with ||" 'set -e; false || true; echo reached'
compare_posix_output "set -e with !" 'set -e; ! false; echo reached'
compare_posix_output "set -e in if condition" 'set -e; if false; then echo no; fi; echo reached'
compare_posix_output "set -e in while condition" 'set -e; while false; do echo no; done; echo reached'

section "241. SET -e IN SUBSHELLS"

compare_posix_output "set -e inherited" 'set -e; (false; echo no) || echo caught'
compare_posix_output "set -e in command sub" 'set -e; x=$(false; echo yes); echo "x=$x"'

section "242. COMMAND NOT FOUND"

# Test exit status for command not found (should be 127)
test_cmd='nonexistent_command_12345 2>/dev/null; echo $?'
compare_posix_output "command not found status" "$test_cmd"

# =====================================
# FUNCTION EDGE CASES
# =====================================

section "250. FUNCTION - BUILTIN SHADOWING"

compare_posix_output "function shadows builtin" 'echo() { printf "custom: %s\n" "$1"; }; echo test; unset -f echo'
compare_posix_output "function named cd" 'cd() { echo "custom cd"; }; cd /tmp; unset -f cd'

section "251. FUNCTION - REDEFINITION"

compare_posix_output "redefine function" 'f() { echo v1; }; f; f() { echo v2; }; f'

section "252. FUNCTION - INDIRECT RECURSION"

compare_posix_output "mutual recursion" 'a() { [ $1 -le 0 ] && echo done || b $(($1-1)); }; b() { a $1; }; a 3'

section "253. FUNCTION - RETURN EDGE CASES"

compare_posix_output "return outside function" '(return 5 2>/dev/null); echo $?'
compare_posix_output "return in sourced file" 'echo "return 42" > /tmp/ret.sh; . /tmp/ret.sh; echo $?; rm /tmp/ret.sh'

# =====================================
# REDIRECTION EDGE CASES
# =====================================

section "260. REDIRECTION - CLOSED FD OPERATIONS"

compare_posix_error "write to closed fd" 'exec 3>&-; echo test >&3 2>&1 | head -1'
compare_posix_error "read from closed fd" 'exec 3<&-; cat <&3 2>&1 | head -1'

section "261. REDIRECTION - MULTIPLE HEREDOCS"

compare_posix_output "two heredocs" 'cat <<EOF1; cat <<EOF2
first
EOF1
second
EOF2'

section "262. REDIRECTION - NOCLOBBER WITH APPEND"

compare_posix_output "noclobber allows append" 'set -C; echo a > /tmp/nc_test; echo b >> /tmp/nc_test; cat /tmp/nc_test; rm /tmp/nc_test'

# =====================================
# PIPELINE EDGE CASES
# =====================================

section "270. PIPELINE - BUILTIN ONLY"

compare_posix_output "pipeline all builtins" 'echo test | { read x; echo "got: $x"; }'
compare_posix_output "pipeline with :" ': | echo piped'

section "271. PIPELINE - LONG CHAINS"

compare_posix_output "5-stage pipeline" 'echo test | cat | cat | cat | cat | cat'
compare_posix_output "pipeline with failures" 'echo ok | false | cat; echo $?'

# =====================================
# ALIAS EDGE CASES
# =====================================

section "280. ALIAS - SPECIAL CASES"

compare_posix_error "alias with quotes" "alias greet='echo hello'; greet; unalias greet"
compare_posix_error "alias with semicolon" "alias both='echo a; echo b'; both; unalias both"
compare_posix_output "alias -p format" 'alias foo=bar; alias -p | grep foo; unalias foo'

section "281. ALIAS - EXPANSION CONTEXT"

# Aliases don't expand in non-interactive mode - both bash and fortsh should fail
# Test that we get "command not found" error (exact format varies by bash version)
test_alias_behavior() {
    test_name="$1"
    test_cmd="$2"
    expected_pattern="$3"

    output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1)

    if echo "$output" | grep -qiE "$expected_pattern"; then
        pass "$test_name"
    else
        fail "$test_name" "expected pattern: $expected_pattern" "got: $output"
    fi
}

test_alias_behavior "alias in function" "alias e=echo; f() { e test; }; f; unalias e" "command not found|not found"

# =====================================
# DOT (SOURCE) EDGE CASES
# =====================================

section "290. DOT - PATH HANDLING"

compare_posix_output "dot with arguments" 'echo "echo args: \$1 \$2" > /tmp/src.sh; . /tmp/src.sh a b; rm /tmp/src.sh'
compare_posix_output "dot return value" 'echo "false" > /tmp/src.sh; . /tmp/src.sh; echo $?; rm /tmp/src.sh'
compare_posix_output "dot modifies vars" 'echo "X=modified" > /tmp/src.sh; X=original; . /tmp/src.sh; echo $X; rm /tmp/src.sh'

# =====================================
# SPECIAL BUILTIN EDGE CASES
# =====================================

section "300. SPECIAL BUILTINS - ERROR BEHAVIOR"

compare_posix_output "break outside loop" '(break 2>/dev/null); echo $?'
compare_posix_output "continue outside loop" '(continue 2>/dev/null); echo $?'
compare_posix_output "colon with redirect" ': > /tmp/colon_test; test -f /tmp/colon_test && echo exists; rm /tmp/colon_test'

# =====================================
# ENVIRONMENT EDGE CASES
# =====================================

section "310. ENVIRONMENT - PATH HANDLING"

compare_posix_output "empty PATH component" 'echo "echo found" > /tmp/pathtest; chmod +x /tmp/pathtest; PATH="/tmp:$PATH" pathtest; rm /tmp/pathtest'

section "311. ENVIRONMENT - EXPORT BEHAVIOR"

compare_posix_output "export in subshell" 'X=1; (export X=2); echo $X'
compare_posix_output "export preserves" 'export X=1; X=2; sh -c "echo \$X"'

# =====================================
# GLOB EDGE CASES
# =====================================

section "320. GLOB - SPECIAL FILENAMES"

compare_posix_output "glob with spaces" 'mkdir -p /tmp/gt; touch "/tmp/gt/a b"; echo /tmp/gt/*; rm -r /tmp/gt'
compare_posix_output "glob no match" 'echo /nonexistent/path/*.xyz 2>/dev/null'

section "321. GLOB - CHARACTER CLASSES"

compare_posix_output "glob [:alpha:]" 'mkdir -p /tmp/gc; touch /tmp/gc/a1 /tmp/gc/1a; echo /tmp/gc/[[:alpha:]]*; rm -r /tmp/gc'
compare_posix_output "glob [:digit:]" 'mkdir -p /tmp/gc; touch /tmp/gc/a1 /tmp/gc/1a; echo /tmp/gc/[[:digit:]]*; rm -r /tmp/gc'

# =====================================
# QUOTING EDGE CASES
# =====================================

section "330. QUOTING - COMPLEX NESTING"

compare_posix_output "quotes in command sub" 'echo "$(echo "inner")"'
compare_posix_output "escaped quotes" 'echo "say \"hello\""'
compare_posix_output "single in double" "echo \"it's\""
compare_posix_output "backslash in single" "echo 'back\\slash'"

section "331. QUOTING - EMPTY STRINGS"

compare_posix_output "empty preserves arg" 'set -- "" "a"; echo $#'
compare_posix_output "unquoted empty gone" 'e=""; set -- $e a; echo $#'

# =====================================
# MISCELLANEOUS EDGE CASES
# =====================================

section "340. MISC - COMPOUND COMMANDS"

compare_posix_output "if with compound cond" 'if true && true; then echo yes; fi'
compare_posix_output "while with pipeline cond" 'n=0; while echo $n | grep -q 0 && [ $n -lt 1 ]; do n=$((n+1)); done; echo $n'

section "341. MISC - COMPLEX COMBINATIONS"

compare_posix_output "redirect in loop" 'for i in 1 2 3; do echo $i; done > /tmp/loop_out; cat /tmp/loop_out; rm /tmp/loop_out'
compare_posix_output "case with patterns" 'x=abc; case $x in a*) echo match;; esac'

# =====================================
# SUMMARY
# =====================================

printf "\n==========================================\n"
printf "COVERAGE GAP TEST RESULTS ${TEST_PREFIX}\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "${YELLOW}Skipped:${NC} %d\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"
printf "==========================================\n"

if [ "$((PASSED + FAILED))" -gt 0 ]; then
    pass_rate=$((PASSED * 100 / (PASSED + FAILED)))
    printf "Pass rate: %d%%\n" "$pass_rate"
fi

if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n"
    printf "%b" "$FAILED_TESTS_LIST"
    printf "==========================================\n"
fi

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}ALL COVERAGE GAP TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
