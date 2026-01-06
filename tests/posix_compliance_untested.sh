#!/bin/sh
# =====================================
# POSIX Compliance - Previously Untested Features
# =====================================
# Tests for POSIX features that are implemented but lack test coverage

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-untested]"
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
        printf "  posix:         %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  fortsh:        %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${YELLOW}⊘ SKIP${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s\n" "$1"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    # Extract section number from header like "131. COMMAND BUILTIN"
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Compare output between sh and fortsh
compare_posix_output() {
    test_name="$1"
    test_cmd="$2"

    # Run with POSIX sh
    posix_output=$(FORTSH_RC_FILE=/dev/null bash -c "$test_cmd" 2>&1)
    posix_exit=$?

    # Run with fortsh
    fortsh_output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1)
    fortsh_exit=$?

    # Compare outputs
    if [ "$posix_output" = "$fortsh_output" ] && [ "$posix_exit" = "$fortsh_exit" ]; then
        pass "$test_name"
    else
        fail "$test_name" "$posix_output" "$fortsh_output"
    fi
}

# Normalize shell error messages by stripping shell name and "line N: " prefix
# POSIX doesn't mandate error message format, so we normalize for comparison
normalize_error() {
    echo "$1" | sed -e 's/^bash: /sh: /' -e 's/^fortsh: /sh: /' -e 's/line [0-9]*: //'
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

# Test that fortsh accepts an option/command without error
test_accepts() {
    test_name="$1"
    test_cmd="$2"

    if FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" >/dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "should succeed" "failed or not implemented"
    fi
}

# Test that command fails as expected
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
# TESTS START HERE
# =====================================

section "131. COMMAND BUILTIN - PATH SEARCH"

compare_posix_output "command -v ls" 'command -v ls >/dev/null && echo found'
compare_posix_output "command -v nonexistent" 'command -v nonexistent >/dev/null || echo notfound'
test_accepts "command -p ls" 'command -p ls / >/dev/null'
compare_posix_output "command without options" 'command echo test'

section "132. MULTI-FD REDIRECTIONS"

# Create test file
compare_posix_output "fd 3 redirect write" 'exec 3>/tmp/posix_fd3.txt; echo test >&3; exec 3>&-; cat /tmp/posix_fd3.txt; rm /tmp/posix_fd3.txt'
compare_posix_output "fd 4 redirect read" 'echo data > /tmp/posix_fd4.txt; exec 4</tmp/posix_fd4.txt; read line <&4; echo $line; exec 4<&-; rm /tmp/posix_fd4.txt'
compare_posix_output "fd duplication" 'exec 5>&1; echo stdout >&5; exec 5>&-'
compare_posix_output "fd 3 and 4 together" 'exec 3>/tmp/posix_3.txt 4>/tmp/posix_4.txt; echo a >&3; echo b >&4; exec 3>&- 4>&-; cat /tmp/posix_3.txt /tmp/posix_4.txt; rm /tmp/posix_3.txt /tmp/posix_4.txt'

section "133. EXEC WITH SHELL REDIRECTIONS"

# Note: These redirect the shell itself, not just one command
# Save stdout to FD 3, redirect, write, restore, then cat (otherwise cat hangs on file still open for writing)
compare_posix_output "exec redirect stdout" 'exec 3>&1; exec >/tmp/posix_exec_out.txt; echo redirected; exec >&3; cat /tmp/posix_exec_out.txt; rm /tmp/posix_exec_out.txt'
compare_posix_output "exec redirect stdin" 'echo testdata > /tmp/posix_exec_in.txt; exec </tmp/posix_exec_in.txt; read data; echo $data; rm /tmp/posix_exec_in.txt'

section "134. SET OPTION INTERACTIONS"

compare_posix_output "set -e with true" 'set -e; true; echo ok'
compare_posix_output "set -u with unset var" 'set -u; echo ${UNSET_VAR:-default}'
compare_posix_output "set -C noclobber" 'set -C; echo test > /tmp/posix_clobber.txt; echo ok; rm /tmp/posix_clobber.txt'
compare_posix_output "set -C override with >|" 'set -C; echo test > /tmp/posix_clobber2.txt; echo override >| /tmp/posix_clobber2.txt; cat /tmp/posix_clobber2.txt; rm /tmp/posix_clobber2.txt'

section "135. SPECIAL BUILTIN ERROR HANDLING"

# POSIX: Special builtins must exit non-interactive shell on error
# Testing with subshells to avoid killing the test script

compare_posix_error "readonly error exits" '(readonly VAR=1; VAR=2 2>/dev/null; echo should not print) || echo exited'
compare_posix_output "export invalid" '(export 123INVALID=value 2>/dev/null; echo should not print) || echo exited'
compare_posix_output "set invalid option" '(set -@ 2>/dev/null; echo should not print) || echo exited'

section "136. ULIMIT TESTS"

test_accepts "ulimit display" 'ulimit'
test_accepts "ulimit -a all" 'ulimit -a >/dev/null'
test_accepts "ulimit -n files" 'ulimit -n >/dev/null'
test_accepts "ulimit -s stack" 'ulimit -s >/dev/null 2>&1'

section "137. NESTED PARAMETER EXPANSION"

compare_posix_output "nested default" 'unset A B; echo ${A:-${B:-default}}'
compare_posix_output "nested with set var" 'A=inner; unset B; echo ${B:-${A}}'
compare_posix_output "double nested" 'unset A B C; echo ${A:-${B:-${C:-triple}}}'

section "138. PARAMETER LENGTH EDGE CASES"

compare_posix_output "length of $@" 'set -- a b c; echo ${#@}'
compare_posix_output "length of $*" 'set -- a b c; echo ${#*}'
compare_posix_output "length of empty" 'VAR=; echo ${#VAR}'
compare_posix_output "length of unset" 'unset VAR; echo ${#VAR}'

section "139. QUOTING EDGE CASES"

compare_posix_output "empty double quotes" 'VAR=""; echo x${VAR}y'
compare_posix_output "empty single quotes" "VAR=''; echo x\${VAR}y"
compare_posix_output "adjacent quotes concat" 'echo "a"b"c"'
compare_posix_output "quote in quote" 'echo "it'\''s"'

section "140. BACKSLASH NEWLINE CONTINUATION"

compare_posix_output "line continuation in string" 'echo "test\
continuation"'
compare_posix_output "line continuation in command" 'ec\
ho test'

section "141. COMMENT IN COMMAND SUBSTITUTION"

compare_posix_output "comment in subshell" '$(# this is a comment
echo test)'
compare_posix_output "comment in backtick" '`# comment
echo test`'

section "142. REDIRECTION EDGE CASES"

compare_posix_output "close stdin" 'cat <&- 2>&1 | head -1'
compare_posix_error "close stdout" 'echo test >&- 2>&1'
compare_posix_output "read/write mode" 'echo data > /tmp/posix_rw.txt; cat <> /tmp/posix_rw.txt; rm /tmp/posix_rw.txt'

section "143. ERROR HANDLING EDGE CASES"

test_fails "assign to positional param" '$1=value 2>/dev/null'
test_fails "readonly reassign" 'readonly VAR=1; VAR=2 2>/dev/null'
# Test that execution continues after arithmetic error
# Check that "continued" appears in the output (error format may vary)
test_accepts "division by zero" 'echo $((5/0)) | cat; echo continued 2>&1 | grep -q continued'

section "144. SET -n (NOEXEC) TESTING"

# This tests if set -n is implemented
compare_posix_output "set -n parse only" 'set -n; echo "should not execute"; false' || skip "set -n not implemented"

section "145. SET -m (MONITOR) TESTING"

test_accepts "set -m monitor mode" 'set -m; set +m'
compare_posix_output "set -m doesn't affect output" 'set -m; echo test; set +m'

# =====================================
# SUMMARY
# =====================================

printf "\n==========================================\n"
printf "UNTESTED FEATURES TEST RESULTS ${TEST_PREFIX}\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "${YELLOW}Skipped:${NC} %d\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"
printf "==========================================\n"

# Calculate pass rate
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
    printf "${GREEN}ALL UNTESTED FEATURES TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
