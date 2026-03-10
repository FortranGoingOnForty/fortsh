#!/bin/sh
TEST_PREFIX="[jobs-fg-bg]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. jobs"
check_exit "jobs with no background jobs" 'jobs' "0"
compare_output "jobs shows background process" 'sleep 60 & jobs; kill %1 2>/dev/null; wait 2>/dev/null'
check_exit "jobs -p shows PIDs" 'sleep 60 & jobs -p >/dev/null; kill %1 2>/dev/null; wait 2>/dev/null' "0"
compare_output "jobs after completion" 'true & wait; jobs'

section "2. fg"
compare_exit "fg with no jobs fails" 'fg 2>/dev/null'
compare_output "fg brings job to foreground" 'sleep 0.1 & fg %1 >/dev/null 2>&1; echo $?'

section "3. bg"
compare_exit "bg with no stopped jobs fails" 'bg 2>/dev/null'

section "4. job spec parsing"
compare_output "kill by job spec %1" 'sleep 60 & kill %1 2>/dev/null; wait 2>/dev/null; echo done'
compare_output "multiple background jobs" 'sleep 60 & sleep 60 & kill %1 %2 2>/dev/null; wait 2>/dev/null; echo done'

print_summary
