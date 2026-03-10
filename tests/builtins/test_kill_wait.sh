#!/bin/sh
TEST_PREFIX="[kill-wait]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. kill"
check_exit "kill -l lists signals" 'kill -l' "0"
compare_exit "kill nonexistent PID fails" 'kill -0 999999 2>/dev/null'

section "2. wait"
compare_output "wait for background job" 'echo start; true & wait; echo done'
compare_exit "wait returns bg exit status" 'false & wait $!'
compare_output "wait multiple background jobs" '(echo a; echo b) & wait'
compare_output "wait with no bg jobs" 'wait; echo $?'
compare_exit "wait specific PID" 'sleep 0.1 & wait $!'

print_summary
