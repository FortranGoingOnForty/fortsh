#!/bin/sh
TEST_PREFIX="[history]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. history display"
check_exit "history runs without error" 'history' "0"
check_exit "history N shows last N" 'history 5' "0"

section "2. history management"
check_exit "history -c clears history" 'history -c' "0"
compare_output "history -c then history shows empty" 'history -c; history | wc -l | tr -d " "'

section "3. history file operations"
check_exit "history -w writes to file" "HISTFILE=$TEST_TMPDIR/hist_test; history -w" "0"
check_exit "history -r reads from file" "HISTFILE=$TEST_TMPDIR/hist_test; history -r" "0"
check_exit "history -a appends to file" "HISTFILE=$TEST_TMPDIR/hist_test; history -a" "0"

section "4. history deletion"
check_exit "history -d with valid offset" 'history -d 1 2>/dev/null' "0"

print_summary
