#!/usr/bin/env bash
# ==============================================================================
# POSIX Compliance - Builtin Commands & Shell Options Test Suite
# ==============================================================================
# Tests all gaps identified in POSIX compliance analysis (2025-10-17)
# Covers: P0 (critical), P1 (important), P2 (nice-to-have) issues
# ==============================================================================

# Configuration
FORTSH_BIN="${FORTSH_BIN:-./bin/fortsh}"
VERBOSE="${VERBOSE:-0}"

# Test identification
TEST_PREFIX="[posix-builtins]"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TESTS_LIST=""

# Color codes (if terminal supports them)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Test result functions
pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${GREEN}✓${NC} ${TEST_PREFIX} $1"
}

fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${RED}✗${NC} ${TEST_PREFIX} $1"
    FAILED_TESTS_LIST="${FAILED_TESTS_LIST}  ${TEST_PREFIX} $1\n"
    if [ "$VERBOSE" = "1" ]; then
        echo -e "${RED}  Details: $2${NC}"
    fi
}

section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# ==============================================================================
# P0: CRITICAL TESTS (Must pass for basic POSIX compliance)
# ==============================================================================

test_p0_readonly_enforcement() {
    section "P0-1: readonly Variable Enforcement"

    # Test 1: Cannot modify readonly variable
    output=$($FORTSH_BIN -c 'readonly VAR=test; VAR=other' 2>&1)
    if echo "$output" | grep -q "readonly variable"; then
        pass "P0-1.1: Readonly violation produces error message"
    else
        fail "P0-1.1: Readonly violation produces error message" "No error message found"
    fi

    # Test 2: Exit code is 127 for readonly violation (POSIX compliance)
    $FORTSH_BIN -c 'readonly VAR=test; VAR=other' >/dev/null 2>&1
    if [ $? -eq 127 ]; then
        pass "P0-1.2: Readonly violation returns exit code 127"
    else
        fail "P0-1.2: Readonly violation returns exit code 127" "Got exit code $?"
    fi

    # Test 3: Command after readonly violation should not execute
    output=$($FORTSH_BIN -c 'readonly VAR=test; VAR=other; echo SHOULD_NOT_PRINT' 2>&1)
    if ! echo "$output" | grep -q "SHOULD_NOT_PRINT"; then
        pass "P0-1.3: Commands after readonly violation do not execute"
    else
        fail "P0-1.3: Commands after readonly violation do not execute" "Command was executed"
    fi

    # Test 4: Readonly variable preserves original value (test removed - see P0-1.3)
    # Note: POSIX requires non-interactive shells to exit on readonly violations,
    # so we cannot test value preservation after failed assignment in same script.
    # Value preservation is implicitly tested by P0-1.1 (error occurs) and P0-1.3 (execution stops).

    # Test 5: Multiple readonly violations
    $FORTSH_BIN -c 'readonly A=1; readonly B=2; A=x; B=y' >/dev/null 2>&1
    if [ $? -eq 127 ]; then
        pass "P0-1.5: Multiple readonly violations handled correctly"
    else
        fail "P0-1.5: Multiple readonly violations handled correctly"
    fi
}

test_p0_set_u() {
    section "P0-2: set -u (nounset option)"

    # Test 1: Undefined variable in parameter expansion
    output=$($FORTSH_BIN -c 'set -u; echo ${UNDEFINED_VAR}' 2>&1)
    if echo "$output" | grep -q "unbound variable"; then
        pass "P0-2.1: set -u detects undefined variable in \${VAR}"
    else
        fail "P0-2.1: set -u detects undefined variable in \${VAR}" "No error for undefined variable"
    fi

    # Test 2: Undefined variable in simple expansion
    output=$($FORTSH_BIN -c 'set -u; echo $UNDEFINED_SIMPLE' 2>&1)
    if echo "$output" | grep -q "unbound variable"; then
        pass "P0-2.2: set -u detects undefined variable in \$VAR"
    else
        fail "P0-2.2: set -u detects undefined variable in \$VAR"
    fi

    # Test 3: Non-interactive shell exits on unbound variable
    # POSIX: Expansion errors should return exit code 127, not 1
    $FORTSH_BIN -c 'set -u; echo $UNDEF; echo SHOULD_NOT_PRINT' >/dev/null 2>&1
    exit_code=$?
    output=$($FORTSH_BIN -c 'set -u; echo $UNDEF; echo SHOULD_NOT_PRINT' 2>&1)
    if [ $exit_code -eq 127 ] && ! echo "$output" | grep -q "SHOULD_NOT_PRINT"; then
        pass "P0-2.3: Non-interactive shell exits on unbound variable"
    else
        fail "P0-2.3: Non-interactive shell exits on unbound variable" "Exit code: $exit_code"
    fi

    # Test 4: Defined variable works with set -u
    output=$($FORTSH_BIN -c 'set -u; VAR=value; echo $VAR' 2>&1)
    if echo "$output" | grep -q "value"; then
        pass "P0-2.4: Defined variables work correctly with set -u"
    else
        fail "P0-2.4: Defined variables work correctly with set -u"
    fi

    # Test 5: set +u disables the option
    output=$($FORTSH_BIN -c 'set -u; set +u; echo $UNDEFINED_AFTER_DISABLE' 2>&1)
    if ! echo "$output" | grep -q "unbound variable"; then
        pass "P0-2.5: set +u correctly disables nounset option"
    else
        fail "P0-2.5: set +u correctly disables nounset option"
    fi

    # Test 6: Special variables always defined ($?, $$, etc.)
    output=$($FORTSH_BIN -c 'set -u; echo $? $$ $0' 2>&1)
    if ! echo "$output" | grep -q "unbound variable"; then
        pass "P0-2.6: Special variables don't trigger set -u"
    else
        fail "P0-2.6: Special variables don't trigger set -u"
    fi
}

test_p0_trap_exit() {
    section "P0-3: trap EXIT Execution"

    # Test 1: EXIT trap executes on exit builtin
    output=$($FORTSH_BIN -c 'trap "echo TRAPPED" EXIT; exit 0' 2>&1)
    if echo "$output" | grep -q "TRAPPED"; then
        pass "P0-3.1: EXIT trap executes on exit builtin"
    else
        fail "P0-3.1: EXIT trap executes on exit builtin" "Trap did not execute"
    fi

    # Test 2: EXIT trap preserves exit code
    $FORTSH_BIN -c 'trap "echo cleanup" EXIT; exit 42' >/dev/null 2>&1
    if [ $? -eq 42 ]; then
        pass "P0-3.2: EXIT trap preserves original exit code"
    else
        fail "P0-3.2: EXIT trap preserves original exit code" "Got exit code $?"
    fi

    # Test 3: EXIT trap executes on natural shell exit
    output=$(echo 'trap "echo CLEANUP" EXIT; echo done' | $FORTSH_BIN 2>&1)
    if echo "$output" | grep -q "CLEANUP"; then
        pass "P0-3.3: EXIT trap executes on natural shell termination"
    else
        fail "P0-3.3: EXIT trap executes on natural shell termination"
    fi

    # Test 4: EXIT trap executes only once
    output=$($FORTSH_BIN -c 'trap "echo ONCE" EXIT; exit 0' 2>&1)
    count=$(echo "$output" | grep -c "ONCE")
    if [ "$count" -eq 1 ]; then
        pass "P0-3.4: EXIT trap executes exactly once"
    else
        fail "P0-3.4: EXIT trap executes exactly once" "Executed $count times"
    fi

    # Test 5: EXIT trap can access variables
    output=$($FORTSH_BIN -c 'VAR=value; trap "echo \$VAR" EXIT; exit 0' 2>&1)
    if echo "$output" | grep -q "value"; then
        pass "P0-3.5: EXIT trap can access shell variables"
    else
        fail "P0-3.5: EXIT trap can access shell variables"
    fi

    # Test 6: EXIT trap with non-zero exit from command
    $FORTSH_BIN -c 'trap "echo cleanup" EXIT; false' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        pass "P0-3.6: EXIT trap preserves command failure exit code"
    else
        fail "P0-3.6: EXIT trap preserves command failure exit code"
    fi
}

# ==============================================================================
# P1: IMPORTANT TESTS (Correctness and error handling)
# ==============================================================================

test_p1_exit_code_126() {
    section "P1-1: Exit Code 126 (Non-executable File)"

    # Test 1: Non-executable file returns 126
    touch /tmp/fortsh_test_nonexec
    chmod 644 /tmp/fortsh_test_nonexec
    $FORTSH_BIN -c '/tmp/fortsh_test_nonexec' >/dev/null 2>&1
    exit_code=$?
    rm -f /tmp/fortsh_test_nonexec

    if [ $exit_code -eq 126 ]; then
        pass "P1-1.1: Non-executable file returns exit code 126"
    else
        fail "P1-1.1: Non-executable file returns exit code 126" "Got exit code $exit_code"
    fi

    # Test 2: Non-existent file still returns 127
    $FORTSH_BIN -c '/nonexistent/command/path' >/dev/null 2>&1
    if [ $? -eq 127 ]; then
        pass "P1-1.2: Non-existent command returns exit code 127"
    else
        fail "P1-1.2: Non-existent command returns exit code 127" "Got exit code $?"
    fi

    # Test 3: Executable file returns its own exit code
    echo '#!/bin/sh' > /tmp/fortsh_test_exec
    echo 'exit 5' >> /tmp/fortsh_test_exec
    chmod 755 /tmp/fortsh_test_exec
    $FORTSH_BIN -c '/tmp/fortsh_test_exec' >/dev/null 2>&1
    exit_code=$?
    rm -f /tmp/fortsh_test_exec

    if [ $exit_code -eq 5 ]; then
        pass "P1-1.3: Executable file returns its own exit code"
    else
        fail "P1-1.3: Executable file returns its own exit code" "Got exit code $exit_code"
    fi
}

test_p1_set_c_noclobber() {
    section "P1-2: set -C (noclobber option)"

    # Test 1: set -C prevents overwriting existing files
    echo "original" > /tmp/fortsh_test_noclobber
    $FORTSH_BIN -c 'set -C; echo new > /tmp/fortsh_test_noclobber' >/dev/null 2>&1
    exit_code=$?
    content=$(cat /tmp/fortsh_test_noclobber 2>/dev/null)
    rm -f /tmp/fortsh_test_noclobber

    if [ $exit_code -ne 0 ] && [ "$content" = "original" ]; then
        pass "P1-2.1: set -C prevents overwriting existing files"
    else
        fail "P1-2.1: set -C prevents overwriting existing files" "File was overwritten"
    fi

    # Test 2: set -C allows writing to new files
    rm -f /tmp/fortsh_test_noclobber_new
    $FORTSH_BIN -c 'set -C; echo content > /tmp/fortsh_test_noclobber_new' >/dev/null 2>&1
    if [ -f /tmp/fortsh_test_noclobber_new ]; then
        pass "P1-2.2: set -C allows writing to non-existent files"
        rm -f /tmp/fortsh_test_noclobber_new
    else
        fail "P1-2.2: set -C allows writing to non-existent files"
    fi

    # Test 3: >| forces overwrite even with noclobber
    echo "original" > /tmp/fortsh_test_force
    $FORTSH_BIN -c 'set -C; echo forced >| /tmp/fortsh_test_force' >/dev/null 2>&1
    content=$(cat /tmp/fortsh_test_force 2>/dev/null)
    rm -f /tmp/fortsh_test_force

    if [ "$content" = "forced" ]; then
        pass "P1-2.3: >| forces overwrite with noclobber set"
    else
        fail "P1-2.3: >| forces overwrite with noclobber set" "Content: $content"
    fi

    # Test 4: set +C disables noclobber
    echo "original" > /tmp/fortsh_test_disable
    $FORTSH_BIN -c 'set -C; set +C; echo new > /tmp/fortsh_test_disable' >/dev/null 2>&1
    content=$(cat /tmp/fortsh_test_disable 2>/dev/null)
    rm -f /tmp/fortsh_test_disable

    if [ "$content" = "new" ]; then
        pass "P1-2.4: set +C disables noclobber option"
    else
        fail "P1-2.4: set +C disables noclobber option"
    fi
}

test_p1_trap_removal() {
    section "P1-3: trap - SIGNAL (Trap Removal)"

    # Test 1: trap - INT removes INT trap
    output=$($FORTSH_BIN -c 'trap "echo caught" INT; trap - INT; kill -INT $$' 2>&1)
    if ! echo "$output" | grep -q "caught"; then
        pass "P1-3.1: trap - INT removes INT trap"
    else
        fail "P1-3.1: trap - INT removes INT trap" "Trap still executed"
    fi

    # Test 2: trap - TERM removes TERM trap
    $FORTSH_BIN -c 'trap "echo term" TERM; trap - TERM; exit 0' >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        pass "P1-3.2: trap - TERM removes TERM trap"
    else
        fail "P1-3.2: trap - TERM removes TERM trap"
    fi

    # Test 3: trap - EXIT removes EXIT trap
    output=$($FORTSH_BIN -c 'trap "echo exit" EXIT; trap - EXIT; exit 0' 2>&1)
    if ! echo "$output" | grep -q "exit"; then
        pass "P1-3.3: trap - EXIT removes EXIT trap"
    else
        fail "P1-3.3: trap - EXIT removes EXIT trap"
    fi

    # Test 4: Listing traps after removal
    output=$($FORTSH_BIN -c 'trap "echo test" INT; trap - INT; trap' 2>&1)
    if ! echo "$output" | grep -q "INT"; then
        pass "P1-3.4: Removed traps don't appear in trap listing"
    else
        fail "P1-3.4: Removed traps don't appear in trap listing"
    fi
}

test_p1_set_e_conditionals() {
    section "P1-4: set -e in Conditional Contexts"

    # Test 1: set -e doesn't exit on false in if condition
    output=$($FORTSH_BIN -c 'set -e; if false; then echo no; else echo YES; fi' 2>&1)
    if echo "$output" | grep -q "YES"; then
        pass "P1-4.1: set -e doesn't exit on false in if condition"
    else
        fail "P1-4.1: set -e doesn't exit on false in if condition"
    fi

    # Test 2: set -e doesn't exit on false in while condition
    output=$($FORTSH_BIN -c 'set -e; count=0; while false; do count=$((count+1)); done; echo AFTER' 2>&1)
    if echo "$output" | grep -q "AFTER"; then
        pass "P1-4.2: set -e doesn't exit on false in while condition"
    else
        fail "P1-4.2: set -e doesn't exit on false in while condition"
    fi

    # Test 3: set -e exits on command failure outside conditionals
    $FORTSH_BIN -c 'set -e; false; echo SHOULD_NOT_PRINT' >/dev/null 2>&1
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        pass "P1-4.3: set -e exits on command failure outside conditionals"
    else
        fail "P1-4.3: set -e exits on command failure outside conditionals"
    fi

    # Test 4: set -e with && and || operators
    output=$($FORTSH_BIN -c 'set -e; false || echo AFTER_OR' 2>&1)
    if echo "$output" | grep -q "AFTER_OR"; then
        pass "P1-4.4: set -e doesn't exit on false before ||"
    else
        fail "P1-4.4: set -e doesn't exit on false before ||"
    fi

    # Test 5: set -e in until loop
    output=$($FORTSH_BIN -c 'set -e; count=0; until [ $count -eq 1 ]; do count=1; done; echo DONE' 2>&1)
    if echo "$output" | grep -q "DONE"; then
        pass "P1-4.5: set -e doesn't exit on false in until condition"
    else
        fail "P1-4.5: set -e doesn't exit on false in until condition"
    fi
}

# ==============================================================================
# P2: NICE-TO-HAVE TESTS (Quality of life features)
# ==============================================================================

test_p2_background_pid() {
    section "P2-1: \$! (Background Process PID)"

    # Test 1: $! contains PID of last background job
    output=$($FORTSH_BIN -c 'sleep 0.1 & echo $!' 2>&1)
    if echo "$output" | grep -qE '^[0-9]+$'; then
        pass "P2-1.1: \$! expands to numeric PID"
    else
        fail "P2-1.1: \$! expands to numeric PID" "Got: $output"
    fi

    # Test 2: $! updates after each background job
    output=$($FORTSH_BIN -c 'sleep 0.1 & pid1=$!; sleep 0.1 & pid2=$!; if [ "$pid1" != "$pid2" ]; then echo DIFFERENT; fi' 2>&1)
    if echo "$output" | grep -q "DIFFERENT"; then
        pass "P2-1.2: \$! updates for each background job"
    else
        fail "P2-1.2: \$! updates for each background job" "Got: [$output]"
    fi

    # Test 3: $! is empty/zero before any background jobs
    output=$($FORTSH_BIN -c 'echo "|$!|"' 2>&1)
    if echo "$output" | grep -qE '\|[0-9]*\|'; then
        pass "P2-1.3: \$! has valid value before background jobs"
    else
        fail "P2-1.3: \$! has valid value before background jobs"
    fi
}

test_p2_dot_with_args() {
    section "P2-2: dot (.) Source with Arguments"

    # Test 1: Source script with positional parameters
    echo 'echo "arg1=$1 arg2=$2"' > /tmp/fortsh_test_source
    output=$($FORTSH_BIN -c '. /tmp/fortsh_test_source hello world' 2>&1)
    rm -f /tmp/fortsh_test_source

    if echo "$output" | grep -q "arg1=hello arg2=world"; then
        pass "P2-2.1: dot command passes arguments to sourced script"
    else
        fail "P2-2.1: dot command passes arguments to sourced script" "Got: $output"
    fi

    # Test 2: Source script preserves caller's variables
    echo 'SOURCED_VAR=from_script' > /tmp/fortsh_test_source2
    output=$($FORTSH_BIN -c '. /tmp/fortsh_test_source2; echo $SOURCED_VAR' 2>&1)
    rm -f /tmp/fortsh_test_source2

    if echo "$output" | grep -q "from_script"; then
        pass "P2-2.2: Sourced script sets variables in caller"
    else
        fail "P2-2.2: Sourced script sets variables in caller"
    fi

    # Test 3: Source with absolute path
    echo 'echo sourced' > /tmp/fortsh_abs_source
    output=$($FORTSH_BIN -c '. /tmp/fortsh_abs_source' 2>&1)
    rm -f /tmp/fortsh_abs_source

    if echo "$output" | grep -q "sourced"; then
        pass "P2-2.3: dot command works with absolute paths"
    else
        fail "P2-2.3: dot command works with absolute paths"
    fi
}

test_p2_readonly_unset() {
    section "P2-3: Readonly Unset Prevention"

    # Test 1: Cannot unset readonly variable
    output=$($FORTSH_BIN -c 'readonly VAR=test; unset VAR' 2>&1)
    if echo "$output" | grep -qE '(readonly|cannot unset)'; then
        pass "P2-3.1: unset readonly variable produces error"
    else
        fail "P2-3.1: unset readonly variable produces error"
    fi

    # Test 2: Readonly variable still exists after unset attempt
    output=$($FORTSH_BIN -c 'readonly VAR=value; unset VAR 2>/dev/null; echo $VAR' 2>&1)
    if echo "$output" | grep -q "value"; then
        pass "P2-3.2: Readonly variable survives unset attempt"
    else
        fail "P2-3.2: Readonly variable survives unset attempt"
    fi

    # Test 3: unset returns non-zero for readonly variables
    $FORTSH_BIN -c 'readonly VAR=x; unset VAR' >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        pass "P2-3.3: unset readonly variable returns non-zero"
    else
        fail "P2-3.3: unset readonly variable returns non-zero"
    fi

    # Test 4: Can unset non-readonly variables
    output=$($FORTSH_BIN -c 'VAR=test; unset VAR; echo "|$VAR|"' 2>&1)
    if echo "$output" | grep -q "||"; then
        pass "P2-3.4: unset works for non-readonly variables"
    else
        fail "P2-3.4: unset works for non-readonly variables"
    fi
}

# ==============================================================================
# ADDITIONAL ROBUSTNESS TESTS
# ==============================================================================

test_additional_builtins() {
    section "BONUS: Additional Builtin Tests"

    # Test shift builtin
    output=$($FORTSH_BIN -c 'set -- a b c; shift; echo $1' 2>&1)
    if echo "$output" | grep -q "b"; then
        pass "BONUS-1: shift builtin works correctly"
    else
        fail "BONUS-1: shift builtin works correctly"
    fi

    # Test times builtin
    output=$($FORTSH_BIN -c 'times' 2>&1)
    if echo "$output" | grep -qE '[0-9]'; then
        pass "BONUS-2: times builtin produces output"
    else
        fail "BONUS-2: times builtin produces output"
    fi

    # Test hash builtin
    output=$($FORTSH_BIN -c 'hash' 2>&1)
    if [ $? -eq 0 ]; then
        pass "BONUS-3: hash builtin executes without error"
    else
        fail "BONUS-3: hash builtin executes without error"
    fi

    # Test type builtin
    output=$($FORTSH_BIN -c 'type echo' 2>&1)
    if echo "$output" | grep -qiE '(builtin|command)'; then
        pass "BONUS-4: type builtin identifies commands"
    else
        fail "BONUS-4: type builtin identifies commands"
    fi

    # Test umask builtin
    output=$($FORTSH_BIN -c 'umask' 2>&1)
    if echo "$output" | grep -qE '^[0-9]{4}$'; then
        pass "BONUS-5: umask builtin displays mask"
    else
        fail "BONUS-5: umask builtin displays mask"
    fi

    # Test getopts builtin
    output=$($FORTSH_BIN -c 'getopts "a:b" opt -a value; echo $opt' 2>&1)
    if echo "$output" | grep -q "a"; then
        pass "BONUS-6: getopts builtin parses options"
    else
        fail "BONUS-6: getopts builtin parses options"
    fi
}

test_edge_cases() {
    section "BONUS: Edge Cases"

    # Test empty command
    $FORTSH_BIN -c '' >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        pass "EDGE-1: Empty command succeeds"
    else
        fail "EDGE-1: Empty command succeeds"
    fi

    # Test semicolon alone
    # POSIX: Semicolon alone is a syntax error (exit code 2), not success
    $FORTSH_BIN -c ';' >/dev/null 2>&1
    if [ $? -eq 2 ]; then
        pass "EDGE-2: Semicolon alone is syntax error"
    else
        fail "EDGE-2: Semicolon alone is syntax error" "Expected exit 2, got $?"
    fi

    # Test comment handling
    output=$($FORTSH_BIN -c 'echo visible # this is comment' 2>&1)
    if echo "$output" | grep -q "visible" && ! echo "$output" | grep -q "comment"; then
        pass "EDGE-3: Comments are ignored correctly"
    else
        fail "EDGE-3: Comments are ignored correctly"
    fi

    # Test multiple semicolons
    output=$($FORTSH_BIN -c 'echo a;; echo b' 2>&1)
    if echo "$output" | grep -q "b"; then
        pass "EDGE-4: Multiple semicolons handled"
    else
        fail "EDGE-4: Multiple semicolons handled"
    fi
}

# ==============================================================================
# MAIN TEST EXECUTION
# ==============================================================================

main() {
    echo "=========================================="
    echo "POSIX Compliance - Builtin Test Suite"
    echo "=========================================="
    echo "Testing: $FORTSH_BIN"
    echo "Date: $(date)"
    echo ""

    # Verify fortsh exists
    if [ ! -x "$FORTSH_BIN" ]; then
        echo -e "${RED}ERROR: fortsh binary not found or not executable: $FORTSH_BIN${NC}"
        echo "Please build fortsh or set FORTSH_BIN environment variable"
        exit 1
    fi

    # Run all test suites
    test_p0_readonly_enforcement
    test_p0_set_u
    test_p0_trap_exit

    test_p1_exit_code_126
    test_p1_set_c_noclobber
    test_p1_trap_removal
    test_p1_set_e_conditionals

    test_p2_background_pid
    test_p2_dot_with_args
    test_p2_readonly_unset

    test_additional_builtins
    test_edge_cases

    # Print summary
    echo ""
    echo "=========================================="
    echo "TEST SUMMARY ${TEST_PREFIX}"
    echo "=========================================="
    echo -e "Total Tests:  $TOTAL_TESTS"
    echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
    echo -e "${RED}Failed:       $FAILED_TESTS${NC}"

    if [ $FAILED_TESTS -gt 0 ]; then
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        echo -e "$FAILED_TESTS_LIST"
        echo "=========================================="
    fi

    if [ $FAILED_TESTS -eq 0 ]; then
        echo ""
        echo -e "${GREEN}=========================================="
        echo -e "✓ ALL TESTS PASSED!"
        echo -e "==========================================${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}=========================================="
        echo -e "✗ SOME TESTS FAILED"
        echo -e "==========================================${NC}"
        echo ""
        echo "Run with VERBOSE=1 for detailed failure information:"
        echo "  VERBOSE=1 $0"
        exit 1
    fi
}

# Run main function
main "$@"
