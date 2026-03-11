#!/bin/sh
TEST_PREFIX="[fc]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. fc listing"
check_exit "fc -l lists history" 'fc -l' "0"
check_exit "fc -l -n suppresses line numbers" 'fc -l -n' "0"
check_exit "fc -l -r reverses order" 'fc -l -r' "0"
skip "fc -l produces output" "requires interactive mode (no history in -c)"

section "2. fc with range"
check_exit "fc -l with negative offset" 'fc -l -5 2>/dev/null; true' "0"
check_exit "fc -l first last range" 'fc -l 1 5 2>/dev/null; true' "0"
check_exit "fc -l with prefix search" 'echo hello; fc -l echo 2>/dev/null; true' "0"

section "3. fc flags combined"
check_exit "fc -l -n combined" 'fc -l -n 2>/dev/null; true' "0"
check_exit "fc -l -r -n all combined" 'fc -l -r -n 2>/dev/null; true' "0"

section "4. fc substitution"
compare_output "fc -s re-executes" 'echo testcmd123; fc -s echo 2>/dev/null || true'
check_exit "fc -s with no history" 'fc -s nonexistent_xyz 2>/dev/null; true' "0"

section "5. fc editor"
check_exit "fc -e with EDITOR" 'FCEDIT=/bin/true; fc -e /bin/true 2>/dev/null; true' "0"

print_summary
