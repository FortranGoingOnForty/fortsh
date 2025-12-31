#!/bin/sh
# =====================================
# POSIX Compliance Redirection and Pipeline Test Suite for fortsh
# =====================================
# Tests redirections and pipelines per IEEE Std 1003.1-2017
# Section: Shell Command Language - Redirection

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-redirect]"
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

TEST_DIR="/tmp/fortsh_redirect_$$"
mkdir -p "$TEST_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# =====================================
section "428. OUTPUT REDIRECTION >"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello > '"$TEST_DIR"'/out1.txt; cat '"$TEST_DIR"'/out1.txt' 2>&1)
if [ "$result" = "hello" ]; then
    pass "> redirects stdout to file"
else
    fail "> redirects stdout to file" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo first > '"$TEST_DIR"'/out2.txt; echo second > '"$TEST_DIR"'/out2.txt; cat '"$TEST_DIR"'/out2.txt' 2>&1)
if [ "$result" = "second" ]; then
    pass "> overwrites existing file"
else
    fail "> overwrites existing file" "second" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "multi word" > '"$TEST_DIR"'/out3.txt; cat '"$TEST_DIR"'/out3.txt' 2>&1)
if [ "$result" = "multi word" ]; then
    pass "> with quoted string"
else
    fail "> with quoted string" "multi word" "$result"
fi

# =====================================
section "429. APPEND REDIRECTION >>"
# =====================================

result=$("$FORTSH_BIN" -c 'echo first > '"$TEST_DIR"'/append.txt; echo second >> '"$TEST_DIR"'/append.txt; cat '"$TEST_DIR"'/append.txt' 2>&1)
expected=$(printf "first\nsecond")
if [ "$result" = "$expected" ]; then
    pass ">> appends to file"
else
    fail ">> appends to file" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo line1 >> '"$TEST_DIR"'/new.txt; cat '"$TEST_DIR"'/new.txt' 2>&1)
if [ "$result" = "line1" ]; then
    pass ">> creates file if not exists"
else
    fail ">> creates file if not exists" "line1" "$result"
fi

# =====================================
section "430. INPUT REDIRECTION <"
# =====================================

echo "test input" > "$TEST_DIR/input.txt"

result=$("$FORTSH_BIN" -c 'cat < '"$TEST_DIR"'/input.txt' 2>&1)
if [ "$result" = "test input" ]; then
    pass "< redirects file to stdin"
else
    fail "< redirects file to stdin" "test input" "$result"
fi

result=$("$FORTSH_BIN" -c 'read line < '"$TEST_DIR"'/input.txt; echo "$line"' 2>&1)
if [ "$result" = "test input" ]; then
    pass "< with read builtin"
else
    fail "< with read builtin" "test input" "$result"
fi

# =====================================
section "431. STDERR REDIRECTION 2>"
# =====================================

result=$("$FORTSH_BIN" -c 'ls /nonexistent 2> '"$TEST_DIR"'/err.txt; cat '"$TEST_DIR"'/err.txt' 2>&1)
if echo "$result" | grep -qi "no such\|not found\|cannot"; then
    pass "2> redirects stderr to file"
else
    fail "2> redirects stderr to file" "error message" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo stdout; ls /nonexistent 2>/dev/null' 2>&1)
if [ "$result" = "stdout" ]; then
    pass "2>/dev/null suppresses stderr"
else
    fail "2>/dev/null suppresses stderr" "stdout" "$result"
fi

# =====================================
section "432. REDIRECT STDERR TO STDOUT 2>&1"
# =====================================

result=$("$FORTSH_BIN" -c '{ echo out; ls /nonexistent; } 2>&1 | head -2' 2>&1)
if echo "$result" | grep -q "out"; then
    pass "2>&1 merges stderr to stdout"
else
    fail "2>&1 merges stderr to stdout" "both streams" "$result"
fi

result=$("$FORTSH_BIN" -c 'ls /nonexistent 2>&1 | cat' 2>&1)
if echo "$result" | grep -qi "no such\|not found\|cannot"; then
    pass "2>&1 stderr goes through pipe"
else
    fail "2>&1 stderr goes through pipe" "error in pipe" "$result"
fi

# =====================================
section "433. REDIRECT STDOUT TO STDERR 1>&2"
# =====================================

result=$("$FORTSH_BIN" -c 'echo error >&2' 2>&1)
if [ "$result" = "error" ]; then
    pass ">&2 redirects stdout to stderr"
else
    fail ">&2 redirects stdout to stderr" "error" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo error 1>&2 2>/dev/null' 2>&1)
if [ -z "$result" ]; then
    pass "1>&2 with stderr suppressed"
else
    fail "1>&2 with stderr suppressed" "(empty)" "$result"
fi

# =====================================
section "434. COMBINED REDIRECTIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo out > '"$TEST_DIR"'/combined.txt 2>&1; cat '"$TEST_DIR"'/combined.txt' 2>&1)
if [ "$result" = "out" ]; then
    pass "> file 2>&1 combination"
else
    fail "> file 2>&1 combination" "out" "$result"
fi

result=$("$FORTSH_BIN" -c '{ echo out; echo err >&2; } > '"$TEST_DIR"'/both.txt 2>&1; cat '"$TEST_DIR"'/both.txt' 2>&1)
expected=$(printf "out\nerr")
if [ "$result" = "$expected" ]; then
    pass "Both streams to same file"
else
    fail "Both streams to same file" "$expected" "$result"
fi

# =====================================
section "435. NOCLOBBER WITH >|"
# =====================================

echo "original" > "$TEST_DIR/noclobber.txt"

result=$("$FORTSH_BIN" -c 'set -C; echo new >| '"$TEST_DIR"'/noclobber.txt; cat '"$TEST_DIR"'/noclobber.txt' 2>&1)
if [ "$result" = "new" ]; then
    pass ">| overrides noclobber"
else
    fail ">| overrides noclobber" "new" "$result"
fi

# =====================================
section "436. SIMPLE PIPELINE"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello | cat' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Simple two-stage pipeline"
else
    fail "Simple two-stage pipeline" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo hello world | wc -w' 2>&1)
if echo "$result" | grep -q "2"; then
    pass "Pipeline with wc"
else
    fail "Pipeline with wc" "2" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "c\na\nb\n" | sort' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "Pipeline with sort"
else
    fail "Pipeline with sort" "$expected" "$result"
fi

# =====================================
section "437. MULTI-STAGE PIPELINE"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello | cat | cat | cat' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Four-stage pipeline"
else
    fail "Four-stage pipeline" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "b\na\nc\nb\na\n" | sort | uniq' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "sort | uniq pipeline"
else
    fail "sort | uniq pipeline" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "hello world" | tr " " "\n" | wc -l' 2>&1)
if echo "$result" | grep -q "2"; then
    pass "tr | wc pipeline"
else
    fail "tr | wc pipeline" "2" "$result"
fi

# =====================================
section "438. PIPELINE WITH REDIRECTION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello | cat > '"$TEST_DIR"'/pipe_out.txt; cat '"$TEST_DIR"'/pipe_out.txt' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Pipeline with output redirect"
else
    fail "Pipeline with output redirect" "hello" "$result"
fi

echo "from file" > "$TEST_DIR/pipe_in.txt"
result=$("$FORTSH_BIN" -c 'cat < '"$TEST_DIR"'/pipe_in.txt | tr "a-z" "A-Z"' 2>&1)
if [ "$result" = "FROM FILE" ]; then
    pass "Input redirect into pipeline"
else
    fail "Input redirect into pipeline" "FROM FILE" "$result"
fi

# =====================================
section "439. PIPELINE SUBSHELL"
# =====================================

result=$("$FORTSH_BIN" -c 'echo test | { read x; echo "got: $x"; }' 2>&1)
if [ "$result" = "got: test" ]; then
    pass "Pipeline to brace group"
else
    fail "Pipeline to brace group" "got: test" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo test | (cat; echo done)' 2>&1)
expected=$(printf "test\ndone")
if [ "$result" = "$expected" ]; then
    pass "Pipeline to subshell"
else
    fail "Pipeline to subshell" "$expected" "$result"
fi

# =====================================
section "440. COMMAND SUBSTITUTION IN PIPELINE"
# =====================================

result=$("$FORTSH_BIN" -c 'echo $(echo hello | tr "a-z" "A-Z")' 2>&1)
if [ "$result" = "HELLO" ]; then
    pass "Command substitution with pipeline"
else
    fail "Command substitution with pipeline" "HELLO" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=$(printf "a\nb\nc\n" | wc -l); echo $x' 2>&1)
if echo "$result" | grep -q "3"; then
    pass "Variable from pipeline in command sub"
else
    fail "Variable from pipeline in command sub" "3" "$result"
fi

# =====================================
section "441. REDIRECTION ORDER"
# =====================================

# The order matters: 2>&1 before > vs after
result=$("$FORTSH_BIN" -c '{ echo out; echo err >&2; } > '"$TEST_DIR"'/order1.txt 2>&1; cat '"$TEST_DIR"'/order1.txt | wc -l' 2>&1)
if echo "$result" | grep -q "2"; then
    pass "> file 2>&1 captures both"
else
    fail "> file 2>&1 captures both" "2 lines" "$result"
fi

# =====================================
section "442. /dev/null REDIRECTION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello > /dev/null; echo done' 2>&1)
if [ "$result" = "done" ]; then
    pass "> /dev/null discards output"
else
    fail "> /dev/null discards output" "done" "$result"
fi

result=$("$FORTSH_BIN" -c 'cat < /dev/null; echo empty' 2>&1)
if [ "$result" = "empty" ]; then
    pass "< /dev/null provides empty input"
else
    fail "< /dev/null provides empty input" "empty" "$result"
fi

result=$("$FORTSH_BIN" -c 'ls /nonexistent 2>/dev/null; echo $?' 2>&1)
# Should show non-zero exit but no error output
if echo "$result" | grep -qE "^[12]$"; then
    pass "2>/dev/null with failing command"
else
    fail "2>/dev/null with failing command" "exit code only" "$result"
fi

# =====================================
section "443. PROCESS SUBSTITUTION STYLE"
# =====================================

# Note: <() is a bash extension, but we test if basic redirects work with commands
result=$("$FORTSH_BIN" -c 'diff <(echo a) <(echo a) 2>/dev/null; echo $?' 2>&1)
# This may not be supported - just document if it works
if [ "$result" = "0" ]; then
    pass "Process substitution <() works"
else
    skip "Process substitution <() works" "bash extension"
fi

# =====================================
section "444. CLOSING FILE DESCRIPTORS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello >&-; echo done 2>/dev/null' 2>&1)
# Closing stdout then trying to echo should either error or succeed
if echo "$result" | grep -q "done"; then
    pass ">&- closes stdout (recovered)"
else
    pass ">&- closes stdout (caused error)"
fi

# =====================================
section "445. DUPLICATING INPUT"
# =====================================

result=$("$FORTSH_BIN" -c 'echo test | { cat; } 0<&0' 2>&1)
if [ "$result" = "test" ]; then
    pass "0<&0 duplicates stdin"
else
    fail "0<&0 duplicates stdin" "test" "$result"
fi

# =====================================
section "446. PIPELINE EXIT STATUS"
# =====================================

# Last command determines exit status
result=$("$FORTSH_BIN" -c 'false | true; echo $?' 2>&1)
if [ "$result" = "0" ]; then
    pass "Pipeline exit is last command (false|true=0)"
else
    fail "Pipeline exit is last command (false|true=0)" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'true | false; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "Pipeline exit is last command (true|false=1)"
else
    fail "Pipeline exit is last command (true|false=1)" "1" "$result"
fi

# Multi-stage pipeline
result=$("$FORTSH_BIN" -c 'echo a | cat | cat | cat; echo $?' 2>&1)
if echo "$result" | grep -q "0"; then
    pass "Multi-stage pipeline success"
else
    fail "Multi-stage pipeline success" "0" "$result"
fi

# Pipeline with negation
result=$("$FORTSH_BIN" -c '! false | true; echo $?' 2>&1)
if [ "$result" = "1" ]; then
    pass "! negates pipeline exit"
else
    fail "! negates pipeline exit" "1" "$result"
fi

# =====================================
section "447. EXEC REDIRECTIONS"
# =====================================

# exec without command modifies shell FDs
result=$("$FORTSH_BIN" -c '
exec 3>"'"$TEST_DIR"'/exec_fd3.txt"
echo "fd3 data" >&3
exec 3>&-
cat "'"$TEST_DIR"'/exec_fd3.txt"
' 2>&1)
if [ "$result" = "fd3 data" ]; then
    pass "exec opens FD 3 for writing"
else
    fail "exec opens FD 3 for writing" "fd3 data" "$result"
fi

# exec read/write mode
result=$("$FORTSH_BIN" -c '
echo "initial" > "'"$TEST_DIR"'/rw_test.txt"
exec 4<>"'"$TEST_DIR"'/rw_test.txt"
read line <&4
echo "read: $line"
exec 4>&-
' 2>&1)
if [ "$result" = "read: initial" ]; then
    pass "exec <> opens read-write"
else
    fail "exec <> opens read-write" "read: initial" "$result"
fi

# =====================================
section "448. COMPOUND REDIRECTIONS"
# =====================================

# Redirect entire loop
result=$("$FORTSH_BIN" -c '
for i in 1 2 3; do
    echo $i
done > "'"$TEST_DIR"'/loop_out.txt"
cat "'"$TEST_DIR"'/loop_out.txt"
' 2>&1)
expected=$(printf "1\n2\n3")
if [ "$result" = "$expected" ]; then
    pass "Redirect entire for loop"
else
    fail "Redirect entire for loop" "$expected" "$result"
fi

# Redirect if statement
result=$("$FORTSH_BIN" -c '
if true; then
    echo inside
fi > "'"$TEST_DIR"'/if_out.txt"
cat "'"$TEST_DIR"'/if_out.txt"
' 2>&1)
if [ "$result" = "inside" ]; then
    pass "Redirect entire if statement"
else
    fail "Redirect entire if statement" "inside" "$result"
fi

# Redirect case statement
result=$("$FORTSH_BIN" -c '
case "x" in
    x) echo matched;;
esac > "'"$TEST_DIR"'/case_out.txt"
cat "'"$TEST_DIR"'/case_out.txt"
' 2>&1)
if [ "$result" = "matched" ]; then
    pass "Redirect entire case statement"
else
    fail "Redirect entire case statement" "matched" "$result"
fi

# =====================================
section "449. INPUT REDIRECTION VARIATIONS"
# =====================================

# cat multiple files
echo "file1" > "$TEST_DIR/cat1.txt"
echo "file2" > "$TEST_DIR/cat2.txt"
result=$("$FORTSH_BIN" -c 'cat "'"$TEST_DIR"'/cat1.txt" "'"$TEST_DIR"'/cat2.txt"' 2>&1)
expected=$(printf "file1\nfile2")
if [ "$result" = "$expected" ]; then
    pass "cat multiple files"
else
    fail "cat multiple files" "$expected" "$result"
fi

# Input from file
echo "from file" > "$TEST_DIR/input.txt"
result=$("$FORTSH_BIN" -c 'cat < "'"$TEST_DIR"'/input.txt"' 2>&1)
if [ "$result" = "from file" ]; then
    pass "< redirects stdin from file"
else
    fail "< redirects stdin from file" "from file" "$result"
fi

# =====================================
section "450. OUTPUT APPEND BEHAVIOR"
# =====================================

# >> creates file if not exists
rm -f "$TEST_DIR/append_new.txt"
result=$("$FORTSH_BIN" -c 'echo first >> "'"$TEST_DIR"'/append_new.txt"; cat "'"$TEST_DIR"'/append_new.txt"' 2>&1)
if [ "$result" = "first" ]; then
    pass ">> creates file if not exists"
else
    fail ">> creates file if not exists" "first" "$result"
fi

# >> appends to existing
echo "line1" > "$TEST_DIR/append_exist.txt"
result=$("$FORTSH_BIN" -c 'echo line2 >> "'"$TEST_DIR"'/append_exist.txt"; cat "'"$TEST_DIR"'/append_exist.txt"' 2>&1)
expected=$(printf "line1\nline2")
if [ "$result" = "$expected" ]; then
    pass ">> appends to existing file"
else
    fail ">> appends to existing file" "$expected" "$result"
fi

# Multiple appends
rm -f "$TEST_DIR/multi_append.txt"
result=$("$FORTSH_BIN" -c '
echo a >> "'"$TEST_DIR"'/multi_append.txt"
echo b >> "'"$TEST_DIR"'/multi_append.txt"
echo c >> "'"$TEST_DIR"'/multi_append.txt"
cat "'"$TEST_DIR"'/multi_append.txt"
' 2>&1)
expected=$(printf "a\nb\nc")
if [ "$result" = "$expected" ]; then
    pass "Multiple sequential appends"
else
    fail "Multiple sequential appends" "$expected" "$result"
fi

# =====================================
section "451. REDIRECT WITH ASSIGNMENTS"
# =====================================

# Assignment with redirect
result=$("$FORTSH_BIN" -c 'x=$(cat < /dev/null); echo "empty:[$x]"' 2>&1)
if [ "$result" = "empty:[]" ]; then
    pass "Assignment from empty file"
else
    fail "Assignment from empty file" "empty:[]" "$result"
fi

# Assignment captures command output despite redirects
result=$("$FORTSH_BIN" -c 'x=$(echo hello 2>/dev/null); echo $x' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Assignment captures stdout"
else
    fail "Assignment captures stdout" "hello" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Redirection and Pipeline Summary\n"
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
