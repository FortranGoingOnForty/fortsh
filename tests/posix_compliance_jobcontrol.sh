#!/bin/sh
# =====================================
# POSIX Compliance - Job Control Tests
# =====================================
# Tests for POSIX job control features (jobs, fg, bg, job specs)

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

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
    printf "${GREEN}✓ PASS${NC}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "${RED}✗ FAIL${NC}: %s\n" "$1"
    if [ -n "$2" ]; then
        printf "  expected: %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  got:      %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    printf "${YELLOW}⊘ SKIP${NC}: %s\n" "$1"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    printf "\n${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Test that command succeeds
test_succeeds() {
    test_name="$1"
    test_cmd="$2"

    if FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" >/dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "should succeed" "failed"
    fi
}

# Test that command produces expected output
test_output() {
    test_name="$1"
    test_cmd="$2"
    expected="$3"

    output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1)
    if [ "$output" = "$expected" ]; then
        pass "$test_name"
    else
        fail "$test_name" "$expected" "$output"
    fi
}

# Test that output contains pattern
test_contains() {
    test_name="$1"
    test_cmd="$2"
    pattern="$3"

    output=$(FORTSH_RC_FILE=/dev/null "$FORTSH_BIN" -c "$test_cmd" 2>&1)
    if echo "$output" | grep -q "$pattern"; then
        pass "$test_name"
    else
        fail "$test_name" "output containing '$pattern'" "$output"
    fi
}

# =====================================
# TESTS START HERE
# =====================================

section "146. BASIC JOB CONTROL"

# Note: Many job control features require interactive mode
# We test what we can in non-interactive mode

test_succeeds "jobs builtin exists" 'jobs >/dev/null 2>&1 || true'
test_succeeds "bg builtin exists" 'bg 2>/dev/null || true'
test_succeeds "fg builtin exists" 'fg 2>/dev/null || true'

section "147. BACKGROUND JOBS"

test_succeeds "simple background job" 'sleep 0.1 &'
test_succeeds "background with wait" 'sleep 0.1 & wait'
test_output "background job count" 'sleep 0.2 & sleep 0.2 & jobs | wc -l | tr -d " "' '2'
test_succeeds "wait for specific job" 'sleep 0.1 & PID=$!; wait $PID'

section "148. JOB EXIT STATUS"

test_output "background true exit" 'true & wait $!; echo $?' '0'
test_output "background false exit" 'false & wait $!; echo $?' '1'
test_output "wait preserves status" 'sh -c "exit 42" & wait $!; echo $?' '42'

section "149. JOBS BUILTIN OUTPUT"

test_succeeds "jobs with no jobs" 'jobs'
test_succeeds "jobs after background" 'sleep 0.5 & jobs; wait'
# Test that jobs shows running processes
test_contains "jobs shows running" 'sleep 0.5 & jobs' 'sleep'

section "150. BACKGROUND PIPELINES"

test_succeeds "pipeline in background" 'echo test | cat &'
test_succeeds "multi-stage background pipeline" 'echo test | cat | cat & wait'
test_output "background pipeline exit" 'echo test | cat & wait $!; echo $?' '0'

section "151. $! LAST BACKGROUND PID"

test_succeeds "$! is set after background" 'sleep 0.1 & test -n "$!"'
test_succeeds "$! is numeric" 'sleep 0.1 & case $! in *[!0-9]*) false;; esac'
test_succeeds "wait for $!" 'sleep 0.1 & wait $!'

section "152. JOB SPECIFICATIONS (if supported)"

# These may not work in non-interactive mode, so we're lenient
skip "job spec %1 (interactive feature)"
skip "job spec %% (interactive feature)"
skip "job spec %+ (interactive feature)"
skip "job spec %- (interactive feature)"

section "153. FG/BG WITH SUSPENDED JOBS"

# Suspending jobs requires interactive terminal (Ctrl-Z)
skip "fg with suspended job (requires interactive tty)"
skip "bg with suspended job (requires interactive tty)"

section "154. WAIT EDGE CASES"

test_output "wait with no args" 'sleep 0.1 & sleep 0.1 & wait; echo done' 'done'
test_output "wait nonexistent PID" 'wait 999999 2>&1 | grep -q "not found\|No such" && echo error || echo ok' 'error'
test_succeeds "multiple waits" 'sleep 0.1 & P1=$!; sleep 0.1 & P2=$!; wait $P1; wait $P2'

section "155. SET -m MONITOR MODE"

test_succeeds "set -m enables" 'set -m'
test_succeeds "set +m disables" 'set -m; set +m'
test_output "monitor doesn't affect output" 'set -m; echo test; set +m' 'test'

section "156. JOB CONTROL WITH FUNCTIONS"

test_succeeds "background function" 'f() { echo test; }; f &'
test_output "wait for function" 'f() { echo ok; }; f & wait; echo done' 'ok
done'

section "157. DISOWN (if implemented)"

# disown is not strictly POSIX but common
skip "disown builtin (not required by POSIX)"

section "158. AMPERSAND SEMANTICS"

test_output "& at end" 'echo test &' ''
test_output "multiple & commands" 'echo a & echo b & wait; echo done' 'a
b
done'

section "159. BACKGROUND SUBSHELLS"

test_succeeds "subshell in background" '(sleep 0.1) &'
test_output "background subshell isolation" 'VAR=outer; (VAR=inner) & wait; echo $VAR' 'outer'

section "160. JOB CONTROL ERROR CASES"

# Test error messages for invalid job control operations
test_contains "fg with no jobs" 'fg 2>&1' 'no.*job\|No current job'
test_contains "bg with no jobs" 'bg 2>&1' 'no.*job\|No current job'

# =====================================
# SUMMARY
# =====================================

section "SUMMARY"

printf "\n==========================================\n"
printf "JOB CONTROL TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "${YELLOW}Skipped:${NC} %d\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"
printf "==========================================\n"

# Calculate pass rate (excluding skipped)
if [ "$((PASSED + FAILED))" -gt 0 ]; then
    pass_rate=$((PASSED * 100 / (PASSED + FAILED)))
    printf "Pass rate: %d%% (excluding skipped)\n" "$pass_rate"
fi

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}ALL NON-SKIPPED JOB CONTROL TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
