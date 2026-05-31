#!/bin/sh
TEST_PREFIX="[fd-varassign]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

TEST_TMPDIR="${TMPDIR:-/tmp}/fortsh_test_va_$$"
mkdir -p "$TEST_TMPDIR"

section "1. exec {VAR}>file basics"
compare_output "open and assign fd" 'exec {fd}>/dev/null; echo $fd'
compare_output "fd is >= 10" 'exec {fd}>/dev/null; test $fd -ge 10 && echo yes'
compare_output "write through assigned fd" "exec {fd}>$TEST_TMPDIR/out.txt; echo hello >&\$fd; exec {fd}>&-; cat $TEST_TMPDIR/out.txt"
compare_output "multiple fds are unique" 'exec {a}>/dev/null; exec {b}>/dev/null; test $a -ne $b && echo yes'

section "2. exec {VAR}>>file append"
compare_output "append mode" 'f=/tmp/fortsh_va_app_$$.txt; rm -f $f; exec {fd}>>$f; echo line1 >&$fd; echo line2 >&$fd; exec {fd}>&-; cat $f; rm -f $f'

section "3. exec {VAR}<file input"
check_output "input redirect" "echo input_data > $TEST_TMPDIR/inp.txt; exec {fd}<$TEST_TMPDIR/inp.txt; read line <&\$fd; exec {fd}>&-; echo \$line" "input_data"

section "4. exec {VAR}>&- close"
compare_output "close assigned fd" "exec {fd}>$TEST_TMPDIR/cls.txt; echo before >&\$fd; exec {fd}>&-; cat $TEST_TMPDIR/cls.txt"

section "5. full lifecycle"
compare_output "open write close read" "exec {fd}>$TEST_TMPDIR/life.txt; echo lifecycle >&\$fd; exec {fd}>&-; cat $TEST_TMPDIR/life.txt"

# Cleanup
rm -rf "$TEST_TMPDIR"
print_summary
