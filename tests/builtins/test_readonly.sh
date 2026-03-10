#!/bin/sh
TEST_PREFIX="[readonly]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. readonly basic"
compare_output "readonly VAR=value preserves value" 'readonly MYRO=hello; echo $MYRO'
compare_output "readonly existing var" 'MYVAR=test; readonly MYVAR; echo $MYVAR'
compare_output "readonly with empty value" 'readonly MYRO=""; echo ">${MYRO}<"'
compare_output "readonly multiple vars" 'readonly A=1 B=2; echo $A $B'

section "2. readonly enforcement"
compare_exit "modify readonly var fails" 'readonly MYRO=hello; MYRO=world 2>/dev/null'
compare_exit "unset readonly var fails" 'readonly MYRO=hello; unset MYRO 2>/dev/null'
compare_output "readonly var in subshell" 'readonly MYRO=hello; echo $MYRO'
compare_exit "export readonly var succeeds" 'readonly MYRO=hello; export MYRO 2>/dev/null'

section "3. readonly listing"
check_exit "readonly -p lists vars" 'readonly -p' "0"
compare_output "readonly -p shows declared vars" 'readonly TESTRO=abc; readonly -p | grep TESTRO'

print_summary
