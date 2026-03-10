#!/bin/sh
TEST_PREFIX="[kill-wait]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. kill signals"
check_exit "kill -l lists signals" 'kill -l' "0"
compare_exit "kill nonexistent PID fails" 'kill -0 999999 2>/dev/null'
compare_output "kill -l output has TERM" 'kill -l | grep -q TERM && echo yes'
compare_output "kill -0 checks process exists" 'sleep 60 & pid=$!; kill -0 $pid && echo alive; kill $pid; wait $pid 2>/dev/null'
compare_output "kill sends TERM by default" 'sleep 60 & pid=$!; kill $pid; wait $pid 2>/dev/null; echo done'
compare_output "kill -9 sends SIGKILL" 'sleep 60 & pid=$!; kill -9 $pid; wait $pid 2>/dev/null; echo done'
compare_output "kill -s TERM sends TERM" 'sleep 60 & pid=$!; kill -s TERM $pid; wait $pid 2>/dev/null; echo done'
compare_exit "kill with invalid signal" 'kill -INVALID 1 2>/dev/null'

section "2. wait basic"
compare_output "wait for background job" 'echo start; true & wait; echo done'
compare_exit "wait returns bg exit status 0" 'true & wait $!'
compare_exit "wait returns bg exit status 1" 'false & wait $!'
compare_output "wait with no bg jobs succeeds" 'wait; echo $?'
compare_exit "wait specific PID" 'sleep 0.1 & wait $!'

section "3. wait multiple"
compare_output "wait all background jobs" 'true & true & wait; echo done'
compare_output "wait specific among multiple" 'sleep 0.1 & p1=$!; sleep 0.1 & p2=$!; wait $p1; echo "p1=$?"; wait $p2; echo "p2=$?"'
compare_exit "wait for already-exited process" 'true & pid=$!; sleep 0.1; wait $pid'

section "4. wait exit status"
compare_output "wait captures exit 42" '(exit 42) & wait $!; echo $?'
compare_output "wait captures exit 0" '(exit 0) & wait $!; echo $?'
compare_output "dollar-bang is last bg PID" 'sleep 0.1 & echo $! | grep -qE "^[0-9]+$" && echo valid'

print_summary
