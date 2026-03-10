#!/bin/sh
TEST_PREFIX="[perf]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. perf commands"
check_exit "perf with no args" 'perf' "0"
check_exit "perf on enables monitoring" 'perf on' "0"
check_exit "perf off disables monitoring" 'perf off' "0"
check_exit "perf stats shows statistics" 'perf stats' "0"
check_exit "perf reset clears counters" 'perf reset' "0"

print_summary
