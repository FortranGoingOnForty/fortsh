#!/bin/sh
TEST_PREFIX="[jobs-fg-bg]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. jobs display"
check_exit "jobs with no background jobs" 'jobs' "0"
compare_output "jobs shows background process" 'sleep 60 & jobs; kill %1 2>/dev/null; wait 2>/dev/null'
check_exit "jobs -p shows PIDs" 'sleep 60 & jobs -p >/dev/null; kill %1 2>/dev/null; wait 2>/dev/null' "0"
compare_output "jobs after completion" 'true & wait; jobs'
compare_output "jobs shows multiple" 'sleep 60 & sleep 60 & jobs | wc -l | tr -d " "; kill %1 %2 2>/dev/null; wait 2>/dev/null'
compare_output "jobs -p output is numeric" 'sleep 60 & jobs -p | grep -qE "^[0-9]+$" && echo yes; kill %1 2>/dev/null; wait 2>/dev/null'

section "2. fg"
compare_exit "fg with no jobs fails" 'fg 2>/dev/null'
compare_output "fg brings job to foreground" 'sleep 0.1 & fg %1 >/dev/null 2>&1; echo $?'
compare_exit "fg invalid job spec fails" 'fg %99 2>/dev/null'

section "3. bg"
compare_exit "bg with no stopped jobs fails" 'bg 2>/dev/null'
compare_exit "bg invalid job spec fails" 'bg %99 2>/dev/null'

section "4. job spec parsing"
compare_output "kill by job spec %1" 'sleep 60 & kill %1 2>/dev/null; wait 2>/dev/null; echo done'
compare_output "multiple background jobs" 'sleep 60 & sleep 60 & kill %1 %2 2>/dev/null; wait 2>/dev/null; echo done'
compare_output "job numbering sequential" 'sleep 60 & sleep 60 & sleep 60 & kill %1 %2 %3 2>/dev/null; wait 2>/dev/null; echo done'

section "5. background execution"
compare_output "command runs in background" '(echo bg_done) & wait; echo fg_done'
compare_output "background preserves exit" '(exit 42) & wait $!; echo $?'
compare_output "dollar-bang tracks PID" 'sleep 0.1 & test -n "$!" && echo yes'

print_summary
