#!/bin/sh
TEST_PREFIX="[ulimit]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. ulimit display defaults"
compare_output "ulimit default shows file size" 'ulimit'
compare_output "ulimit -f same as default" 'ulimit -f'
check_exit "ulimit -a shows all limits" 'ulimit -a' "0"
check_output "ulimit -a produces output" 'ulimit -a | head -1 | grep -q . && echo yes' "yes"

section "2. ulimit resource types"
compare_output "ulimit -n open files" 'ulimit -n'
compare_output "ulimit -s stack size" 'ulimit -s'
compare_output "ulimit -u max processes" 'ulimit -u'
compare_output "ulimit -t cpu time" 'ulimit -t'
compare_output "ulimit -c core size" 'ulimit -c'
compare_output "ulimit -d data size" 'ulimit -d'
compare_output "ulimit -v virtual memory" 'ulimit -v'
compare_output "ulimit -l locked memory" 'ulimit -l'
compare_output "ulimit -m RSS" 'ulimit -m'

section "3. ulimit soft vs hard"
compare_output "ulimit -Sn soft open files" 'ulimit -Sn'
compare_output "ulimit -Hn hard open files" 'ulimit -Hn'
compare_output "ulimit -Ss soft stack" 'ulimit -Ss'
compare_output "ulimit -Hs hard stack" 'ulimit -Hs'
compare_output "ulimit -Su soft processes" 'ulimit -Su'
compare_output "ulimit -Hu hard processes" 'ulimit -Hu'

section "4. ulimit set and query"
compare_output "ulimit -n set and get" 'ulimit -n 512; ulimit -n'
compare_output "ulimit -s set and get" 'ulimit -s 8192; ulimit -s'
compare_output "ulimit -c set to 0" 'ulimit -c 0; ulimit -c'
compare_output "ulimit -c set to unlimited" 'ulimit -c unlimited; ulimit -c'

section "5. ulimit error handling"
compare_exit "ulimit invalid flag" 'ulimit -Z 2>/dev/null'
compare_exit "ulimit set above hard limit" 'ulimit -n 999999999 2>/dev/null'
compare_output "ulimit set then verify" 'OLD=$(ulimit -n); ulimit -n 256; echo $(ulimit -n); ulimit -n $OLD 2>/dev/null'

print_summary
