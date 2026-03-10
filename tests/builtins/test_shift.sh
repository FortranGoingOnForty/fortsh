#!/bin/sh
TEST_PREFIX="[shift]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. shift basic"
compare_output "shift removes first param" 'set -- a b c; shift; echo $1'
compare_output "shift updates count" 'set -- a b c; shift; echo $#'
compare_output "shift N removes N params" 'set -- a b c d e; shift 2; echo $1'
compare_output "shift all params" 'set -- a b c; shift 3; echo $#'
compare_output "shift preserves remaining" 'set -- a b c d; shift 2; echo "$@"'

section "2. shift edge cases"
compare_exit "shift past available params fails" 'set -- a; shift 5 2>/dev/null'
compare_output "shift 0 is no-op" 'set -- a b c; shift 0; echo $1'
compare_output "shift in loop" 'set -- a b c; while [ $# -gt 0 ]; do echo $1; shift; done'
compare_output "shift with no params" 'set --; shift 2>/dev/null; echo $#'
compare_output "multiple shifts" 'set -- a b c d e; shift; shift; echo $1 $#'

print_summary
