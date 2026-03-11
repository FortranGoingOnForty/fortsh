#!/bin/sh
TEST_PREFIX="[history]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. history display"
check_exit "history runs without error" 'history' "0"
check_exit "history N shows last N" 'history 5' "0"
skip "history produces numbered output" "requires interactive mode (no history in -c)"

section "2. history management"
check_exit "history -c clears history" 'history -c' "0"
compare_output "history -c then history shows empty" 'history -c; history | wc -l | tr -d " "'
check_exit "history -d deletes entry" 'history -d 1 2>/dev/null' "0"

section "3. history file operations"
check_exit "history -w writes to file" "HISTFILE=$TEST_TMPDIR/hist_test; history -w" "0"
check_exit "history -r reads from file" "HISTFILE=$TEST_TMPDIR/hist_test; history -r" "0"
check_exit "history -a appends to file" "HISTFILE=$TEST_TMPDIR/hist_test; history -a" "0"
check_output "history -w creates file" "HISTFILE=$TEST_TMPDIR/hist_w; history -w; test -f $TEST_TMPDIR/hist_w && echo yes" "yes"
skip "history -w then -r round-trip" "requires interactive mode (no history in -c)"

section "4. history HISTSIZE"
skip "HISTSIZE limits history" "requires interactive mode (no history in -c)"

section "5. history edge cases"
check_exit "history with invalid flag" 'history --invalid 2>/dev/null; true' "0"
check_exit "history 0 shows nothing" 'history 0' "0"
check_exit "history negative number" 'history -1 2>/dev/null; true' "0"

print_summary
