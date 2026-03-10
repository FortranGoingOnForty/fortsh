#!/bin/sh
TEST_PREFIX="[int-job-control]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: job control, background processes, wait, kill
# TTY-dependent tests are skipped when not connected to a terminal

HAS_TTY=false
[ -t 0 ] && HAS_TTY=true

section "1. background execution"
compare_output "background and wait" 'echo bg & wait; echo done'
compare_output "background exit status via wait" 'true & wait $!; echo $?'
compare_output "background false status" 'false & wait $!; echo $?'
compare_output "multiple background wait all" 'echo a & echo b & wait; echo done'
compare_output "background dollar-bang" 'sleep 0.01 & [ -n "$!" ] && echo has_pid'
compare_output "background preserves parent" 'X=before; (X=after) & wait; echo $X'

section "2. wait"
compare_output "wait specific pid" 'sleep 0.01 & PID=$!; wait $PID; echo $?'
compare_output "wait captures exit" 'false & wait $!; echo $?'
compare_output "wait for true" 'true & wait $!; echo $?'
compare_output "wait no children" 'wait 2>/dev/null; echo $?'
compare_output "wait nonexistent pid" 'wait 99999 2>/dev/null; echo $?'
compare_output "wait all children" 'sleep 0.01 & sleep 0.01 & wait; echo $?'

section "3. kill"
compare_output "kill background process" 'sleep 10 & PID=$!; kill $PID 2>/dev/null; wait $PID 2>/dev/null; echo done'
compare_output "kill -0 checks existence" 'sleep 10 & PID=$!; kill -0 $PID 2>/dev/null && echo alive; kill $PID 2>/dev/null; wait $PID 2>/dev/null'
compare_output "kill nonexistent pid" 'kill 99999 2>/dev/null; echo $?'
compare_output "kill -l lists signals" 'kill -l | head -1 | grep -q "[A-Z]" && echo has_signals'

section "4. job control (TTY-dependent)"
if $HAS_TTY; then
    compare_output "jobs empty" 'jobs 2>/dev/null; echo $?'
else
    skip "jobs empty" "no TTY"
    skip "fg no jobs" "no TTY"
    skip "bg no jobs" "no TTY"
fi

section "5. coproc"
compare_output "basic coproc" 'coproc { cat; } 2>/dev/null; echo hello >&${COPROC[1]}; read line <&${COPROC[0]}; echo $line; kill $COPROC_PID 2>/dev/null; wait $COPROC_PID 2>/dev/null'

print_summary
