#!/bin/sh
TEST_PREFIX="[trap]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. trap EXIT"
compare_output "trap EXIT runs on exit" 'trap "echo bye" EXIT; echo hello'
compare_output "trap EXIT runs after commands" 'trap "echo last" EXIT; echo first; echo second'
compare_output "trap EXIT with explicit exit" 'trap "echo cleanup" EXIT; echo running; exit 0'
compare_output "trap EXIT order" 'trap "echo bye" EXIT; echo a; echo b'

section "2. trap management"
compare_output "trap reset with dash" 'trap "echo caught" EXIT; trap - EXIT; echo done'
compare_output "trap empty string ignores" 'trap "" INT; echo ok'
check_exit "trap -l lists signals" 'trap -l' "0"
check_exit "trap -p prints current traps" 'trap -p' "0"
compare_output "trap -p shows set trap" 'trap "echo bye" EXIT; trap -p EXIT'

section "3. trap with signals"
compare_output "trap ERR on command failure" 'trap "echo error" ERR; false; true'
compare_output "trap multiple signals" 'trap "echo sig" EXIT; echo running'
compare_output "trap replaces previous" 'trap "echo first" EXIT; trap "echo second" EXIT; true'

section "4. trap in subshell"
compare_output "trap not inherited in subshell" 'trap "echo parent" EXIT; (echo child); echo back'
compare_output "trap in subshell independent" '(trap "echo sub_exit" EXIT; echo in_sub)'

print_summary
