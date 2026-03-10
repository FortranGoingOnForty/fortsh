#!/bin/sh
TEST_PREFIX="[eval]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. eval basic"
compare_output "eval basic echo" "eval 'echo hello'"
compare_output "eval with variable expansion" 'X=world; eval "echo hello $X"'
compare_output "eval constructs command from parts" 'CMD="echo"; ARG="hello"; eval "$CMD $ARG"'
compare_output "eval with multiple statements" 'eval "echo one; echo two"'

section "2. eval exit codes"
compare_exit "eval preserves exit code 0" "eval 'true'"
compare_exit "eval preserves exit code 1" "eval 'false'"
compare_exit "eval exit with specific code" "eval 'exit 42'"
compare_output "eval captures $?" 'eval "true"; echo $?'

section "3. eval compound commands"
compare_output "eval for loop" "eval 'for i in a b c; do echo \$i; done'"
compare_output "eval if statement" 'eval "if true; then echo yes; fi"'
compare_output "eval pipeline" 'eval "echo hello | tr h H"'

section "4. eval edge cases"
compare_output "eval empty string" 'eval ""; echo $?'
compare_output "eval variable indirection" 'name=VAR; VAR=hello; eval "echo \$$name"'
compare_output "eval with quoting layers" "eval 'echo '\"'\"'hello'\"'\"''"
compare_output "eval nested" 'eval eval "echo hello"'

print_summary
