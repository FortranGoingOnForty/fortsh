#!/bin/sh
TEST_PREFIX="[exec]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. exec basic"
compare_output "exec replaces shell with command" 'exec echo replaced'
compare_exit "exec replaces shell exit code" 'exec true'
compare_exit "exec with false" 'exec false'

section "2. exec with redirections"
compare_output "exec redirect only" "exec 3>/dev/null; echo ok"
compare_output "exec redirect fd to file" "exec 3>$TEST_TMPDIR/execout; echo hello >&3; exec 3>&-; cat $TEST_TMPDIR/execout"
compare_output "exec input redirect" "echo data > $TEST_TMPDIR/execin; exec 3<$TEST_TMPDIR/execin; read line <&3; echo \$line"

print_summary
