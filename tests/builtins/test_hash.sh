#!/bin/sh
TEST_PREFIX="[hash]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. hash basic"
check_exit "hash with no args" 'hash' "0"
check_exit "hash -r clears cache" 'hash -r' "0"
compare_exit "hash specific command" 'hash ls'
compare_exit "hash nonexistent command fails" 'hash nonexistent_cmd_xyz_999 2>/dev/null'
compare_output "hash -r then lookup" 'hash -r; hash ls 2>/dev/null; echo $?'

section "2. hash caching behavior"
compare_output "hash caches after use" 'ls >/dev/null; hash -t ls 2>/dev/null || hash ls 2>/dev/null; echo $?'
compare_output "hash -r clears then miss" 'ls >/dev/null; hash -r; hash -t ls 2>/dev/null; echo $?'
compare_output "hash multiple commands" 'ls >/dev/null; cat /dev/null; hash ls cat 2>/dev/null; echo $?'

section "3. hash error handling"
compare_exit "hash nonexistent gives error" 'hash no_such_cmd_xyz 2>/dev/null'
compare_output "hash after PATH change" 'hash ls 2>/dev/null; PATH=""; hash -t ls 2>/dev/null; echo $?'

print_summary
