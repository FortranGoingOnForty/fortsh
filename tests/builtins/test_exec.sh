#!/bin/sh
TEST_PREFIX="[exec]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. exec replaces shell"
compare_output "exec replaces shell with command" 'exec echo replaced'
compare_exit "exec replaces shell exit code true" 'exec true'
compare_exit "exec replaces shell exit code false" 'exec false'
compare_output "exec nothing after exec runs" 'exec echo hello; echo unreachable'
compare_output "exec with arguments" 'exec echo one two three'
compare_exit "exec nonexistent command fails" 'exec /nonexistent_cmd_xyz 2>/dev/null'

section "2. exec with redirections only"
compare_output "exec redirect fd to /dev/null" "exec 3>/dev/null; echo ok"
compare_output "exec redirect fd to file" "exec 3>$TEST_TMPDIR/execout; echo hello >&3; exec 3>&-; cat $TEST_TMPDIR/execout"
compare_output "exec input redirect from file" "echo data > $TEST_TMPDIR/execin; exec 3<$TEST_TMPDIR/execin; read line <&3; echo \$line"
compare_output "exec close fd" "exec 3>$TEST_TMPDIR/execout; exec 3>&-; echo ok"
compare_output "exec redirect stdout" "exec >$TEST_TMPDIR/execstdout; echo captured; exec >/dev/tty 2>/dev/null; cat $TEST_TMPDIR/execstdout"
compare_output "exec redirect stderr" "exec 2>$TEST_TMPDIR/execstderr; echo err >&2; exec 2>/dev/tty 2>/dev/null; cat $TEST_TMPDIR/execstderr"

section "3. exec in subshell"
compare_output "exec in subshell does not affect parent" '(exec echo sub); echo parent'
compare_exit "exec in subshell exit code" '(exec false)'

section "4. exec preserves environment"
compare_output "exec preserves exported vars" 'export MYVAR=hello; exec echo $MYVAR'
compare_output "exec with PATH lookup" 'exec ls /dev/null'

print_summary
