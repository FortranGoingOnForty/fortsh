#!/bin/sh
# =====================================
# POSIX Compliance Control Flow and Grouping Test Suite for fortsh
# =====================================
# Tests control flow, subshells, brace groups per IEEE Std 1003.1-2017
# Section: Shell Command Language - Compound Commands

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-control]"
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
section "411. SUBSHELL EXECUTION ( )"
# =====================================

result=$("$FORTSH_BIN" -c '(echo hello)' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Basic subshell execution"
else
    fail "Basic subshell execution" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=outer; (x=inner; echo $x); echo $x' 2>&1)
expected=$(printf "inner\nouter")
if [ "$result" = "$expected" ]; then
    pass "Subshell variable isolation"
else
    fail "Subshell variable isolation" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c '(cd /tmp; pwd); pwd' 2>&1)
# Should show /tmp then original dir
if echo "$result" | head -1 | grep -q "/tmp"; then
    pass "Subshell cd isolation"
else
    fail "Subshell cd isolation" "/tmp then original" "$result"
fi

result=$("$FORTSH_BIN" -c '(exit 42); echo $?' 2>&1)
if [ "$result" = "42" ]; then
    pass "Subshell exit status propagation"
else
    fail "Subshell exit status propagation" "42" "$result"
fi

result=$("$FORTSH_BIN" -c '(echo a; echo b; echo c)' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "Subshell with multiple commands"
else
    fail "Subshell with multiple commands" "$expected" "$result"
fi

# =====================================
section "412. BRACE GROUP { }"
# =====================================

result=$("$FORTSH_BIN" -c '{ echo hello; }' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Basic brace group"
else
    fail "Basic brace group" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=outer; { x=inner; echo $x; }; echo $x' 2>&1)
expected=$(printf "inner\ninner")
if [ "$result" = "$expected" ]; then
    pass "Brace group shares variable scope"
else
    fail "Brace group shares variable scope" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c '{ echo a; echo b; echo c; }' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "Brace group with multiple commands"
else
    fail "Brace group with multiple commands" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c '{ false; }; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "Brace group exit status"
else
    fail "Brace group exit status" "1" "$result"
fi

# =====================================
section "413. BREAK WITH COUNT"
# =====================================

result=$("$FORTSH_BIN" -c '
for i in 1 2 3; do
    for j in a b c; do
        if [ "$j" = "b" ]; then
            break
        fi
        echo "$i$j"
    done
done' 2>&1)
expected=$(printf "1a\n2a\n3a")
if [ "$result" = "$expected" ]; then
    pass "break exits inner loop"
else
    fail "break exits inner loop" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c '
for i in 1 2 3; do
    for j in a b c; do
        if [ "$j" = "b" ]; then
            break 2
        fi
        echo "$i$j"
    done
done' 2>&1)
if [ "$result" = "1a" ]; then
    pass "break 2 exits both loops"
else
    fail "break 2 exits both loops" "1a" "$result"
fi

result=$("$FORTSH_BIN" -c '
for i in 1 2 3; do
    break
    echo "not reached"
done
echo "done"' 2>&1)
if [ "$result" = "done" ]; then
    pass "break stops loop immediately"
else
    fail "break stops loop immediately" "done" "$result"
fi

# =====================================
section "414. CONTINUE WITH COUNT"
# =====================================

result=$("$FORTSH_BIN" -c '
for i in 1 2 3; do
    if [ "$i" = "2" ]; then
        continue
    fi
    echo $i
done' 2>&1)
expected=$(printf "1\n3")
if [ "$result" = "$expected" ]; then
    pass "continue skips iteration"
else
    fail "continue skips iteration" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c '
for i in 1 2; do
    for j in a b c; do
        if [ "$j" = "b" ]; then
            continue 2
        fi
        echo "$i$j"
    done
    echo "inner done"
done' 2>&1)
expected=$(printf "1a\n2a")
if [ "$result" = "$expected" ]; then
    pass "continue 2 continues outer loop"
else
    fail "continue 2 continues outer loop" "$expected" "$result"
fi

# =====================================
section "415. WHILE LOOP"
# =====================================

result=$("$FORTSH_BIN" -c 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done' 2>&1)
expected=$(printf "0\n1\n2")
if [ "$result" = "$expected" ]; then
    pass "Basic while loop"
else
    fail "Basic while loop" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'while false; do echo no; done; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "While with false condition"
else
    fail "While with false condition" "done" "$result"
fi

result=$("$FORTSH_BIN" -c '
i=0
while [ $i -lt 5 ]; do
    i=$((i+1))
    if [ $i -eq 3 ]; then continue; fi
    echo $i
done' 2>&1)
expected=$(printf "1\n2\n4\n5")
if [ "$result" = "$expected" ]; then
    pass "While with continue"
else
    fail "While with continue" "$expected" "$result"
fi

# =====================================
section "416. UNTIL LOOP"
# =====================================

result=$("$FORTSH_BIN" -c 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done' 2>&1)
expected=$(printf "0\n1\n2")
if [ "$result" = "$expected" ]; then
    pass "Basic until loop"
else
    fail "Basic until loop" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'until true; do echo no; done; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "Until with true condition"
else
    fail "Until with true condition" "done" "$result"
fi

# =====================================
section "417. PIPELINE EXIT STATUS"
# =====================================

result=$("$FORTSH_BIN" -c 'true | false; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "Pipeline exit status is last command"
else
    fail "Pipeline exit status is last command" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'false | true; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "Pipeline with false then true"
else
    fail "Pipeline with false then true" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo hello | cat | cat; echo $?' 2>&1)
expected=$(printf "hello\n0")
if [ "$result" = "$expected" ]; then
    pass "Multi-stage pipeline"
else
    fail "Multi-stage pipeline" "$expected" "$result"
fi

# =====================================
section "418. AND-OR LISTS"
# =====================================

result=$("$FORTSH_BIN" -c 'true && echo yes' 2>&1)
if [ "$result" = "yes" ]; then
    pass "&& executes on success"
else
    fail "&& executes on success" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'false && echo yes; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "&& skips on failure"
else
    fail "&& skips on failure" "done" "$result"
fi

result=$("$FORTSH_BIN" -c 'false || echo fallback' 2>&1)
if [ "$result" = "fallback" ]; then
    pass "|| executes on failure"
else
    fail "|| executes on failure" "fallback" "$result"
fi

result=$("$FORTSH_BIN" -c 'true || echo no; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "|| skips on success"
else
    fail "|| skips on success" "done" "$result"
fi

result=$("$FORTSH_BIN" -c 'true && echo a && echo b' 2>&1)
expected=$(printf "a\nb")
if [ "$result" = "$expected" ]; then
    pass "Chained && operators"
else
    fail "Chained && operators" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'false || false || echo third' 2>&1)
if [ "$result" = "third" ]; then
    pass "Chained || operators"
else
    fail "Chained || operators" "third" "$result"
fi

result=$("$FORTSH_BIN" -c 'false || true && echo mixed' 2>&1)
if [ "$result" = "mixed" ]; then
    pass "Mixed && and ||"
else
    fail "Mixed && and ||" "mixed" "$result"
fi

# =====================================
section "419. NEGATION WITH !"
# =====================================

result=$("$FORTSH_BIN" -c '! false; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "! false returns 0"
else
    fail "! false returns 0" "0" "$result"
fi

result=$("$FORTSH_BIN" -c '! true; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "! true returns 1"
else
    fail "! true returns 1" "1" "$result"
fi

result=$("$FORTSH_BIN" -c '! echo hello >/dev/null; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "! negates command exit status"
else
    fail "! negates command exit status" "1" "$result"
fi

# =====================================
section "420. DOT (SOURCE) COMMAND"
# =====================================

TEST_DIR="/tmp/fortsh_control_$$"
mkdir -p "$TEST_DIR"

# Create a file to source
echo 'SOURCED_VAR=hello' > "$TEST_DIR/sourceme.sh"
echo 'sourced_func() { echo "from func"; }' >> "$TEST_DIR/sourceme.sh"

result=$("$FORTSH_BIN" -c '. '"$TEST_DIR"'/sourceme.sh; echo $SOURCED_VAR' 2>&1)
if [ "$result" = "hello" ]; then
    pass ". sources file and sets variable"
else
    fail ". sources file and sets variable" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c '. '"$TEST_DIR"'/sourceme.sh; sourced_func' 2>&1)
if echo "$result" | grep -q "from func"; then
    pass ". sources file and defines function"
else
    fail ". sources file and defines function" "from func" "$result"
fi

# Test source with arguments
echo 'echo "arg1=$1 arg2=$2"' > "$TEST_DIR/withargs.sh"
result=$("$FORTSH_BIN" -c '. '"$TEST_DIR"'/withargs.sh foo bar' 2>&1)
if [ "$result" = "arg1=foo arg2=bar" ]; then
    pass ". passes arguments to sourced script"
else
    fail ". passes arguments to sourced script" "arg1=foo arg2=bar" "$result"
fi

rm -rf "$TEST_DIR"

# =====================================
section "421. EXEC BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'exec echo replaced' 2>&1)
if [ "$result" = "replaced" ]; then
    pass "exec replaces shell with command"
else
    fail "exec replaces shell with command" "replaced" "$result"
fi

# exec without command just does redirections
result=$("$FORTSH_BIN" -c 'exec 2>/dev/null; echo hello' 2>&1)
if [ "$result" = "hello" ]; then
    pass "exec without command continues shell"
else
    fail "exec without command continues shell" "hello" "$result"
fi

# =====================================
section "422. EVAL BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'cmd="echo hello"; eval $cmd' 2>&1)
if [ "$result" = "hello" ]; then
    pass "eval executes string as command"
else
    fail "eval executes string as command" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=world; eval echo "hello $x"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "eval with variable expansion"
else
    fail "eval with variable expansion" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'eval "x=5; echo \$x"' 2>&1)
if [ "$result" = "5" ]; then
    pass "eval with multiple commands"
else
    fail "eval with multiple commands" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'var=x; eval "$var=42"; echo $x' 2>&1)
if [ "$result" = "42" ]; then
    pass "eval for indirect assignment"
else
    fail "eval for indirect assignment" "42" "$result"
fi

# =====================================
section "423. RETURN FROM FUNCTION"
# =====================================

result=$("$FORTSH_BIN" -c 'f() { return 0; echo no; }; f; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "return 0 from function"
else
    fail "return 0 from function" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { return 42; }; f; echo $?' 2>&1)
if [ "$result" = "42" ]; then
    pass "return with status code"
else
    fail "return with status code" "42" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { echo before; return; echo after; }; f' 2>&1)
if [ "$result" = "before" ]; then
    pass "return without value"
else
    fail "return without value" "before" "$result"
fi

# =====================================
section "424. FUNCTION LOCAL VARIABLES"
# =====================================

result=$("$FORTSH_BIN" -c 'x=global; f() { local x=local; echo $x; }; f; echo $x' 2>&1)
expected=$(printf "local\nglobal")
if [ "$result" = "$expected" ]; then
    pass "local variable in function"
else
    fail "local variable in function" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { local x=1; g() { echo $x; }; g; }; f' 2>&1)
if [ "$result" = "1" ]; then
    pass "local visible in nested function"
else
    fail "local visible in nested function" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { local a=1 b=2; echo $a $b; }; f' 2>&1)
if [ "$result" = "1 2" ]; then
    pass "local multiple variables"
else
    fail "local multiple variables" "1 2" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { local x; x=set; echo $x; }; f' 2>&1)
if [ "$result" = "set" ]; then
    pass "local without initial value"
else
    fail "local without initial value" "set" "$result"
fi

# =====================================
section "425. FUNCTION RECURSION"
# =====================================

result=$("$FORTSH_BIN" -c '
factorial() {
    if [ $1 -le 1 ]; then
        echo 1
    else
        prev=$(factorial $(($1 - 1)))
        echo $(($1 * prev))
    fi
}
factorial 5' 2>&1)
if [ "$result" = "120" ]; then
    pass "Recursive function (factorial)"
else
    fail "Recursive function (factorial)" "120" "$result"
fi

result=$("$FORTSH_BIN" -c '
count=0
recurse() {
    count=$((count + 1))
    if [ $count -lt 5 ]; then
        recurse
    fi
    echo $count
}
recurse | tail -1' 2>&1)
if [ "$result" = "5" ]; then
    pass "Recursive function with global state"
else
    fail "Recursive function with global state" "5" "$result"
fi

# =====================================
section "426. FUNCTION ARGUMENTS"
# =====================================

result=$("$FORTSH_BIN" -c 'f() { echo $1 $2 $3; }; f a b c' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "Function positional parameters"
else
    fail "Function positional parameters" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { echo $#; }; f a b c d e' 2>&1)
if [ "$result" = "5" ]; then
    pass "Function \$# count"
else
    fail "Function \$# count" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { echo "$@"; }; f "a b" c' 2>&1)
if [ "$result" = "a b c" ]; then
    pass "Function \$@ expansion"
else
    fail "Function \$@ expansion" "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { shift; echo $1; }; f a b c' 2>&1)
if [ "$result" = "b" ]; then
    pass "shift in function"
else
    fail "shift in function" "b" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { set -- x y z; echo $1; }; f a b; echo done' 2>&1)
expected=$(printf "x\ndone")
if [ "$result" = "$expected" ]; then
    pass "set -- in function is local"
else
    fail "set -- in function is local" "$expected" "$result"
fi

# =====================================
section "427. FUNCTION OVERRIDE"
# =====================================

result=$("$FORTSH_BIN" -c 'f() { echo first; }; f() { echo second; }; f' 2>&1)
if [ "$result" = "second" ]; then
    pass "Function redefinition"
else
    fail "Function redefinition" "second" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { echo orig; }; g() { f; }; f() { echo new; }; g' 2>&1)
if [ "$result" = "new" ]; then
    pass "Function sees redefined function"
else
    fail "Function sees redefined function" "new" "$result"
fi

# =====================================
section "428. UNSET FUNCTION"
# =====================================

result=$("$FORTSH_BIN" -c 'f() { echo hi; }; unset -f f; f 2>/dev/null; echo $?' 2>&1)
if echo "$result" | grep -qE "127|1"; then
    pass "unset -f removes function"
else
    fail "unset -f removes function" "non-zero exit" "$result"
fi

# =====================================
section "429. COLON BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c ':; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass ": returns 0"
else
    fail ": returns 0" "0" "$result"
fi

result=$("$FORTSH_BIN" -c ': this is ignored; echo ok' 2>&1)
if [ "$result" = "ok" ]; then
    pass ": ignores arguments"
else
    fail ": ignores arguments" "ok" "$result"
fi

result=$("$FORTSH_BIN" -c ': ${x:=default}; echo $x' 2>&1)
if [ "$result" = "default" ]; then
    pass ": for side effects in expansion"
else
    fail ": for side effects in expansion" "default" "$result"
fi

# =====================================
section "426. TRUE AND FALSE BUILTINS"
# =====================================

result=$("$FORTSH_BIN" -c 'true; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "true returns 0"
else
    fail "true returns 0" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'false; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "false returns 1"
else
    fail "false returns 1" "1" "$result"
fi

# =====================================
section "427. EXIT BUILTIN"
# =====================================

result=$("$FORTSH_BIN" -c 'exit 0; echo no' 2>&1)
if [ -z "$result" ]; then
    pass "exit 0 terminates immediately"
else
    fail "exit 0 terminates immediately" "(empty)" "$result"
fi

result=$("$FORTSH_BIN" -c 'exit 42' 2>&1)
code=$?
if [ $code -eq 42 ]; then
    pass "exit with specific code"
else
    fail "exit with specific code" "42" "$code"
fi

result=$("$FORTSH_BIN" -c 'false; exit' 2>&1)
code=$?
if [ $code -eq 1 ]; then
    pass "exit without arg uses last status"
else
    fail "exit without arg uses last status" "1" "$code"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Control Flow and Grouping Summary\n"
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
