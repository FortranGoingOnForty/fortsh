#!/bin/sh
TEST_PREFIX="[ulimit]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. ulimit display"
compare_output "ulimit default shows file size" 'ulimit'
check_exit "ulimit -a shows all limits" 'ulimit -a' "0"
compare_output "ulimit -n open files" 'ulimit -n'
compare_output "ulimit -s stack size" 'ulimit -s'
compare_output "ulimit -u max processes" 'ulimit -u'
compare_output "ulimit -t cpu time" 'ulimit -t'

section "2. ulimit soft vs hard"
compare_output "ulimit -S soft limit" 'ulimit -Sn'
compare_output "ulimit -H hard limit" 'ulimit -Hn'

section "3. ulimit resource types"
compare_output "ulimit -c core size" 'ulimit -c'
compare_output "ulimit -d data size" 'ulimit -d'
compare_output "ulimit -f file size" 'ulimit -f'
compare_output "ulimit -v virtual memory" 'ulimit -v'

section "4. ulimit -a format"
check_output "ulimit -a produces output" 'ulimit -a | head -1 | grep -q . && echo yes' "yes"

print_summary
