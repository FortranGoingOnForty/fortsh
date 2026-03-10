#!/bin/sh
TEST_PREFIX="[flow-control]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. exit"
compare_exit "exit 0" 'exit 0'
compare_exit "exit 1" 'exit 1'
compare_exit "exit 42" 'exit 42'
compare_exit "exit no arg uses last status" 'false; exit'
compare_exit "exit 255 wraps" 'exit 255'

section "2. return"
compare_output "return from function" 'f() { echo before; return; echo after; }; f'
compare_exit "return with code" 'f() { return 5; }; f'
compare_output "return preserves code" 'f() { return 3; }; f; echo $?'
compare_output "return only affects function" 'f() { return 0; }; f; echo after'
compare_exit "return outside function fails" 'return 0 2>/dev/null'

section "3. break"
compare_output "break exits loop" 'for i in 1 2 3 4 5; do if [ $i -eq 3 ]; then break; fi; echo $i; done'
compare_output "break in while loop" 'i=0; while true; do i=$((i+1)); if [ $i -eq 3 ]; then break; fi; echo $i; done'
compare_output "break N exits nested loops" 'for i in 1 2; do for j in a b; do if [ "$j" = "b" ]; then break 2; fi; echo "$i$j"; done; done'
compare_output "break 1 same as break" 'for i in 1 2 3; do if [ $i -eq 2 ]; then break 1; fi; echo $i; done'
compare_output "break from inner loop only" 'for i in 1 2; do for j in a b c; do if [ "$j" = "b" ]; then break; fi; echo "$i$j"; done; echo "outer$i"; done'

section "4. continue"
compare_output "continue skips iteration" 'for i in 1 2 3 4 5; do if [ $i -eq 3 ]; then continue; fi; echo $i; done'
compare_output "continue in while loop" 'i=0; while [ $i -lt 5 ]; do i=$((i+1)); if [ $i -eq 3 ]; then continue; fi; echo $i; done'
compare_output "continue N in nested loops" 'for i in 1 2; do for j in a b c; do if [ "$j" = "b" ]; then continue 2; fi; echo "$i$j"; done; done'
compare_output "continue 1 same as continue" 'for i in 1 2 3; do if [ $i -eq 2 ]; then continue 1; fi; echo $i; done'

section "5. colon and true/false"
compare_exit ": is no-op with exit 0" ':'
compare_exit "true exits 0" 'true'
compare_exit "false exits 1" 'false'
compare_exit ": with arguments still exits 0" ': some args here'
compare_output ": does not produce output" ': hello; echo $?'

print_summary
