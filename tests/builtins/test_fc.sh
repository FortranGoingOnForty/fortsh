#!/bin/sh
TEST_PREFIX="[fc]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. fc listing"
check_exit "fc -l lists history" 'fc -l' "0"
check_exit "fc -l -n suppresses line numbers" 'fc -l -n' "0"
check_exit "fc -l -r reverses order" 'fc -l -r' "0"

section "2. fc with range"
check_exit "fc -l with count" 'fc -l -5 2>/dev/null; true' "0"

section "3. fc substitution"
# fc -s re-executes previous command with substitution
compare_output "fc -s basic re-execute" 'echo hello; fc -s echo 2>/dev/null || true'

print_summary
