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
section "430. CASE STATEMENT PATTERNS"
# =====================================

# Simple exact match
result=$("$FORTSH_BIN" -c 'case "hello" in hello) echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case exact match"
else
    fail "case exact match" "yes" "$result"
fi

# Glob pattern match
result=$("$FORTSH_BIN" -c 'case "hello" in h*) echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case glob pattern"
else
    fail "case glob pattern" "yes" "$result"
fi

# Question mark match
result=$("$FORTSH_BIN" -c 'case "cat" in c?t) echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case ? pattern"
else
    fail "case ? pattern" "yes" "$result"
fi

# Bracket pattern
result=$("$FORTSH_BIN" -c 'case "b" in [abc]) echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case [abc] bracket pattern"
else
    fail "case [abc] bracket pattern" "yes" "$result"
fi

# Multiple patterns with |
result=$("$FORTSH_BIN" -c 'case "two" in one|two|three) echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case multiple patterns with |"
else
    fail "case multiple patterns with |" "yes" "$result"
fi

# Default pattern *
result=$("$FORTSH_BIN" -c 'case "xyz" in abc) echo no;; *) echo default;; esac' 2>&1)
if [ "$result" = "default" ]; then
    pass "case * default pattern"
else
    fail "case * default pattern" "default" "$result"
fi

# No match produces nothing
result=$("$FORTSH_BIN" -c 'case "x" in y) echo no;; z) echo also no;; esac; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "case no match produces empty"
else
    fail "case no match produces empty" "done" "$result"
fi

# Variable in word
result=$("$FORTSH_BIN" -c 'x=hello; case "$x" in hello) echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case with variable in word"
else
    fail "case with variable in word" "yes" "$result"
fi

# Variable in pattern
result=$("$FORTSH_BIN" -c 'pat="hel*"; case "hello" in $pat) echo yes;; *) echo no;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case with variable in pattern"
else
    fail "case with variable in pattern" "yes" "$result"
fi

# Quoted pattern (literal)
result=$("$FORTSH_BIN" -c 'case "h*" in "h*") echo yes;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "case quoted pattern is literal"
else
    fail "case quoted pattern is literal" "yes" "$result"
fi

# =====================================
section "431. NESTED CONTROL STRUCTURES"
# =====================================

# if inside for
result=$("$FORTSH_BIN" -c 'for i in 1 2 3; do if [ $i -eq 2 ]; then echo found; fi; done' 2>&1)
if [ "$result" = "found" ]; then
    pass "if inside for loop"
else
    fail "if inside for loop" "found" "$result"
fi

# case inside while
result=$("$FORTSH_BIN" -c 'i=0; while [ $i -lt 3 ]; do case $i in 1) echo one;; esac; i=$((i+1)); done' 2>&1)
if [ "$result" = "one" ]; then
    pass "case inside while loop"
else
    fail "case inside while loop" "one" "$result"
fi

# for inside if
result=$("$FORTSH_BIN" -c 'if true; then for i in a b; do echo $i; done; fi' 2>&1)
expected=$(printf "a\nb")
if [ "$result" = "$expected" ]; then
    pass "for inside if"
else
    fail "for inside if" "$expected" "$result"
fi

# Deeply nested
result=$("$FORTSH_BIN" -c '
for i in 1; do
    for j in 2; do
        for k in 3; do
            echo "$i$j$k"
        done
    done
done' 2>&1)
if [ "$result" = "123" ]; then
    pass "Triple nested for loops"
else
    fail "Triple nested for loops" "123" "$result"
fi

# =====================================
section "432. WHILE AND UNTIL LOOPS"
# =====================================

# while with counter
result=$("$FORTSH_BIN" -c 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done' 2>&1)
expected=$(printf "0\n1\n2")
if [ "$result" = "$expected" ]; then
    pass "while loop with counter"
else
    fail "while loop with counter" "$expected" "$result"
fi

# until loop
result=$("$FORTSH_BIN" -c 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done' 2>&1)
expected=$(printf "0\n1\n2")
if [ "$result" = "$expected" ]; then
    pass "until loop"
else
    fail "until loop" "$expected" "$result"
fi

# while with compound condition
result=$("$FORTSH_BIN" -c 'i=0; while [ $i -lt 5 ] && [ $i -ne 3 ]; do echo $i; i=$((i+1)); done' 2>&1)
expected=$(printf "0\n1\n2")
if [ "$result" = "$expected" ]; then
    pass "while with compound condition"
else
    fail "while with compound condition" "$expected" "$result"
fi

# Empty while body (using :)
result=$("$FORTSH_BIN" -c 'i=0; while [ $i -lt 3 ]; do : ; i=$((i+1)); done; echo $i' 2>&1)
if [ "$result" = "3" ]; then
    pass "while with empty body (colon)"
else
    fail "while with empty body (colon)" "3" "$result"
fi

# =====================================
section "433. BREAK AND CONTINUE"
# =====================================

# break in while
result=$("$FORTSH_BIN" -c 'i=0; while true; do i=$((i+1)); [ $i -ge 3 ] && break; done; echo $i' 2>&1)
if [ "$result" = "3" ]; then
    pass "break in while loop"
else
    fail "break in while loop" "3" "$result"
fi

# continue in for
result=$("$FORTSH_BIN" -c 'for i in 1 2 3 4 5; do [ $i -eq 3 ] && continue; echo $i; done' 2>&1)
expected=$(printf "1\n2\n4\n5")
if [ "$result" = "$expected" ]; then
    pass "continue in for loop"
else
    fail "continue in for loop" "$expected" "$result"
fi

# break N for nested loops
result=$("$FORTSH_BIN" -c '
for i in 1 2; do
    for j in a b; do
        echo "$i$j"
        [ "$j" = "a" ] && break 2
    done
done
echo done' 2>&1)
expected=$(printf "1a\ndone")
if [ "$result" = "$expected" ]; then
    pass "break 2 exits outer loop"
else
    fail "break 2 exits outer loop" "$expected" "$result"
fi

# continue N for nested loops
result=$("$FORTSH_BIN" -c '
for i in 1 2; do
    for j in a b; do
        [ "$i$j" = "1a" ] && continue 2
        echo "$i$j"
    done
done' 2>&1)
expected=$(printf "2a\n2b")
if [ "$result" = "$expected" ]; then
    pass "continue 2 continues outer loop"
else
    fail "continue 2 continues outer loop" "$expected" "$result"
fi

# =====================================
section "434. FOR LOOP VARIATIONS"
# =====================================

# for without in (uses positional params)
result=$("$FORTSH_BIN" -c 'set -- a b c; for x; do echo $x; done' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "for without 'in' uses \$@"
else
    fail "for without 'in' uses \$@" "$expected" "$result"
fi

# for with glob pattern
# Create temp files for glob test
result=$("$FORTSH_BIN" -c 'cd /tmp && touch _testglob_a _testglob_b && for f in _testglob_*; do echo $f; done | wc -l && rm -f _testglob_*' 2>&1 | head -1)
if [ "$result" = "2" ]; then
    pass "for with glob expansion"
else
    fail "for with glob expansion" "2" "$result"
fi

# for with command substitution
result=$("$FORTSH_BIN" -c 'for x in $(echo a b c); do echo $x; done' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "for with command substitution"
else
    fail "for with command substitution" "$expected" "$result"
fi

# for with quoted string (single iteration)
result=$("$FORTSH_BIN" -c 'for x in "a b c"; do echo "[$x]"; done' 2>&1)
if [ "$result" = "[a b c]" ]; then
    pass "for with quoted string (single iteration)"
else
    fail "for with quoted string (single iteration)" "[a b c]" "$result"
fi

# =====================================
section "435. WHILE LOOP VARIATIONS"
# =====================================

# while with pipeline
result=$("$FORTSH_BIN" -c 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done | wc -l' 2>&1)
if [ "$result" = "3" ]; then
    pass "while loop with pipeline"
else
    fail "while loop with pipeline" "3" "$result"
fi

# while with command substitution condition
result=$("$FORTSH_BIN" -c 'X=yes; while [ "$X" = "yes" ]; do echo once; X=no; done' 2>&1)
if [ "$result" = "once" ]; then
    pass "while with variable condition"
else
    fail "while with variable condition" "once" "$result"
fi

# infinite while with break
result=$("$FORTSH_BIN" -c 'i=0; while true; do i=$((i+1)); [ $i -ge 5 ] && break; done; echo $i' 2>&1)
if [ "$result" = "5" ]; then
    pass "infinite while with break"
else
    fail "infinite while with break" "5" "$result"
fi

# =====================================
section "436. UNTIL LOOP VARIATIONS"
# =====================================

# until basic
result=$("$FORTSH_BIN" -c 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done' 2>&1)
expected=$(printf "0\n1\n2")
if [ "$result" = "$expected" ]; then
    pass "until loop basic"
else
    fail "until loop basic"
fi

# until with break
result=$("$FORTSH_BIN" -c 'i=0; until false; do i=$((i+1)); [ $i -ge 3 ] && break; done; echo $i' 2>&1)
if [ "$result" = "3" ]; then
    pass "until with break"
else
    fail "until with break" "3" "$result"
fi

# =====================================
section "437. IF STATEMENT VARIATIONS"
# =====================================

# if with command
result=$("$FORTSH_BIN" -c 'if true; then echo yes; fi' 2>&1)
if [ "$result" = "yes" ]; then
    pass "if with true command"
else
    fail "if with true command" "yes" "$result"
fi

# if with test
result=$("$FORTSH_BIN" -c 'X=5; if [ $X -gt 3 ]; then echo big; fi' 2>&1)
if [ "$result" = "big" ]; then
    pass "if with test condition"
else
    fail "if with test condition" "big" "$result"
fi

# if-else
result=$("$FORTSH_BIN" -c 'if false; then echo no; else echo yes; fi' 2>&1)
if [ "$result" = "yes" ]; then
    pass "if-else statement"
else
    fail "if-else statement" "yes" "$result"
fi

# if-elif-else
result=$("$FORTSH_BIN" -c 'X=2; if [ $X -eq 1 ]; then echo one; elif [ $X -eq 2 ]; then echo two; else echo other; fi' 2>&1)
if [ "$result" = "two" ]; then
    pass "if-elif-else statement"
else
    fail "if-elif-else statement" "two" "$result"
fi

# nested if
result=$("$FORTSH_BIN" -c 'X=1; Y=2; if [ $X -eq 1 ]; then if [ $Y -eq 2 ]; then echo both; fi; fi' 2>&1)
if [ "$result" = "both" ]; then
    pass "nested if statement"
else
    fail "nested if statement" "both" "$result"
fi

# =====================================
section "438. CASE STATEMENT VARIATIONS"
# =====================================

# case with character class
result=$("$FORTSH_BIN" -c 'x=5; case $x in [0-9]) echo digit;; esac' 2>&1)
if [ "$result" = "digit" ]; then
    pass "case with character class"
else
    fail "case with character class" "digit" "$result"
fi

# case with negation
result=$("$FORTSH_BIN" -c 'x=x; case $x in [!0-9]) echo not_digit;; esac' 2>&1)
if [ "$result" = "not_digit" ]; then
    pass "case with negation"
else
    fail "case with negation" "not_digit" "$result"
fi

# case with question mark
result=$("$FORTSH_BIN" -c 'x=ab; case $x in ??) echo two_chars;; esac' 2>&1)
if [ "$result" = "two_chars" ]; then
    pass "case with question mark pattern"
else
    fail "case with question mark pattern" "two_chars" "$result"
fi

# case fall-through (first match wins)
result=$("$FORTSH_BIN" -c 'x=a; case $x in a) echo first;; a) echo second;; esac' 2>&1)
if [ "$result" = "first" ]; then
    pass "case first match wins"
else
    fail "case first match wins" "first" "$result"
fi

# =====================================
section "439. BRACE GROUP VARIATIONS"
# =====================================

# brace group in pipeline
result=$("$FORTSH_BIN" -c '{ echo a; echo b; } | wc -l' 2>&1)
if [ "$result" = "2" ]; then
    pass "brace group in pipeline"
else
    fail "brace group in pipeline" "2" "$result"
fi

# brace group with redirection
result=$("$FORTSH_BIN" -c '{ echo test; } > /tmp/brace_test_$$; cat /tmp/brace_test_$$; rm /tmp/brace_test_$$' 2>&1)
if [ "$result" = "test" ]; then
    pass "brace group with redirection"
else
    fail "brace group with redirection" "test" "$result"
fi

# brace group preserves variables
result=$("$FORTSH_BIN" -c 'X=1; { X=2; }; echo $X' 2>&1)
if [ "$result" = "2" ]; then
    pass "brace group preserves variable changes"
else
    fail "brace group preserves variable changes" "2" "$result"
fi

# =====================================
section "440. SUBSHELL VARIATIONS"
# =====================================

# subshell in pipeline
result=$("$FORTSH_BIN" -c '(echo a; echo b) | wc -l' 2>&1)
if [ "$result" = "2" ]; then
    pass "subshell in pipeline"
else
    fail "subshell in pipeline" "2" "$result"
fi

# subshell isolates variables
result=$("$FORTSH_BIN" -c 'X=1; (X=2); echo $X' 2>&1)
if [ "$result" = "1" ]; then
    pass "subshell isolates variable changes"
else
    fail "subshell isolates variable changes" "1" "$result"
fi

# Note: (( )) is arithmetic syntax in bash, not nested subshell
# Both bash and fortsh correctly treat this as arithmetic and error
"$FORTSH_BIN" -c '((echo deep))' >/dev/null 2>&1
fortsh_exit=$?
bash -c '((echo deep))' >/dev/null 2>&1
bash_exit=$?
if [ "$fortsh_exit" -eq "$bash_exit" ]; then
    pass "double paren arithmetic exit"
else
    fail "double paren arithmetic exit" "exit=$bash_exit" "exit=$fortsh_exit"
fi

# =====================================
section "441. COMPOUND LIST VARIATIONS"
# =====================================

# semicolon separated
result=$("$FORTSH_BIN" -c 'echo a; echo b; echo c' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "semicolon separated commands"
else
    fail "semicolon separated commands"
fi

# newline separated
result=$("$FORTSH_BIN" -c 'echo a
echo b
echo c' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "newline separated commands"
else
    fail "newline separated commands"
fi

# =====================================
section "442. LOGICAL OPERATORS VARIATIONS"
# =====================================

# && chain
result=$("$FORTSH_BIN" -c 'true && true && echo success' 2>&1)
if [ "$result" = "success" ]; then
    pass "&& chain all true"
else
    fail "&& chain all true" "success" "$result"
fi

# && short-circuit
result=$("$FORTSH_BIN" -c 'false && echo never' 2>&1)
if [ -z "$result" ]; then
    pass "&& short-circuits on false"
else
    fail "&& short-circuits on false" "empty" "$result"
fi

# || chain
result=$("$FORTSH_BIN" -c 'false || false || echo fallback' 2>&1)
if [ "$result" = "fallback" ]; then
    pass "|| chain with fallback"
else
    fail "|| chain with fallback" "fallback" "$result"
fi

# || short-circuit
result=$("$FORTSH_BIN" -c 'true || echo never' 2>&1)
if [ -z "$result" ]; then
    pass "|| short-circuits on true"
else
    fail "|| short-circuits on true" "empty" "$result"
fi

# mixed && and ||
result=$("$FORTSH_BIN" -c 'false && echo no || echo yes' 2>&1)
if [ "$result" = "yes" ]; then
    pass "mixed && and ||"
else
    fail "mixed && and ||" "yes" "$result"
fi

# =====================================
section "443. NEGATION WITH !"
# =====================================

# ! negates exit status
result=$("$FORTSH_BIN" -c '! false && echo success' 2>&1)
if [ "$result" = "success" ]; then
    pass "! negates false to true"
else
    fail "! negates false to true" "success" "$result"
fi

result=$("$FORTSH_BIN" -c '! true || echo failed' 2>&1)
if [ "$result" = "failed" ]; then
    pass "! negates true to false"
else
    fail "! negates true to false" "failed" "$result"
fi

# ! with pipeline
result=$("$FORTSH_BIN" -c '! echo test | grep -q nomatch && echo ok' 2>&1)
if [ "$result" = "ok" ]; then
    pass "! with pipeline"
else
    fail "! with pipeline" "ok" "$result"
fi

# =====================================
section "444. FUNCTION DEFINITIONS"
# =====================================

# function with return
result=$("$FORTSH_BIN" -c 'f() { return 42; }; f; echo $?' 2>&1)
if [ "$result" = "42" ]; then
    pass "function with return value"
else
    fail "function with return value" "42" "$result"
fi

# function with arguments
result=$("$FORTSH_BIN" -c 'greet() { echo "Hello, $1"; }; greet World' 2>&1)
if [ "$result" = "Hello, World" ]; then
    pass "function with arguments"
else
    fail "function with arguments" "Hello, World" "$result"
fi

# function calling function
result=$("$FORTSH_BIN" -c 'a() { b; }; b() { echo called; }; a' 2>&1)
if [ "$result" = "called" ]; then
    pass "function calling function"
else
    fail "function calling function" "called" "$result"
fi

# =====================================
section "445. EXIT AND RETURN"
# =====================================

# exit from subshell
result=$("$FORTSH_BIN" -c '(exit 7); echo $?' 2>&1)
if [ "$result" = "7" ]; then
    pass "exit from subshell"
else
    fail "exit from subshell" "7" "$result"
fi

# return from function
result=$("$FORTSH_BIN" -c 'f() { echo before; return; echo after; }; f' 2>&1)
if [ "$result" = "before" ]; then
    pass "return stops function execution"
else
    fail "return stops function execution" "before" "$result"
fi

# return default value
result=$("$FORTSH_BIN" -c 'f() { true; return; }; f; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "return with no value uses last exit status"
else
    fail "return with no value uses last exit status" "0" "$result"
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
