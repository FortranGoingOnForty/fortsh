#!/bin/sh
TEST_PREFIX="[cd-pwd]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. cd basic"
compare_output "cd no args goes to HOME" 'cd && pwd | tail -1'
compare_output "cd to absolute /tmp" 'cd /tmp && pwd'
compare_output "cd to relative subdir" "mkdir -p $TEST_TMPDIR/sub && cd $TEST_TMPDIR && cd sub && pwd"
compare_exit "cd to nonexistent dir fails" 'cd /nonexistent_dir_xyz_12345'
compare_exit "cd to nonexistent dir exit code" 'cd /nonexistent_dir_xyz_12345 2>/dev/null'
compare_output "cd to root" 'cd / && pwd'
compare_output "cd with trailing slash" 'cd /tmp/ && pwd'

section "2. cd special"
compare_output "cd - returns to OLDPWD" 'cd /tmp && cd / && cd - 2>/dev/null && pwd'
compare_output "OLDPWD is set after cd" 'cd /tmp && cd / && echo $OLDPWD'
compare_output "cd .. parent directory" 'cd /tmp && cd .. && pwd'
compare_output "cd ../.. grandparent" 'cd /tmp && cd ../.. 2>/dev/null && pwd'
compare_output "cd . stays in same dir" 'cd /tmp && cd . && pwd'

section "3. pwd"
compare_output "pwd outputs current dir" 'pwd'
compare_exit "pwd exits 0" 'pwd'
compare_output "pwd -L logical path" 'pwd -L'
compare_output "pwd -P physical path" 'pwd -P'

section "4. cd with CDPATH"
compare_output "cd with CDPATH" "mkdir -p $TEST_TMPDIR/base/target && CDPATH=$TEST_TMPDIR/base && cd target 2>/dev/null && pwd"

print_summary
