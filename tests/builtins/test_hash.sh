#!/bin/sh
TEST_PREFIX="[hash]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. hash operations"
check_exit "hash with no args" 'hash' "0"
check_exit "hash -r clears cache" 'hash -r' "0"
compare_exit "hash specific command" 'hash ls'
compare_exit "hash nonexistent command fails" 'hash nonexistent_cmd_xyz_999 2>/dev/null'
compare_output "hash -r then lookup" 'hash -r; hash ls 2>/dev/null; echo $?'

print_summary
