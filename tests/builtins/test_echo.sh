#!/bin/sh
TEST_PREFIX="[echo]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. echo basic"
compare_output "echo basic string" 'echo hello world'
compare_output "echo with no arguments" 'echo'
compare_output "echo with multiple spaced args" 'echo a   b    c'
compare_output "echo single arg" 'echo hello'
compare_output "echo preserves quotes in args" 'echo "hello world"'
compare_output "echo multiple quoted args" 'echo "hello" "world"'
compare_output "echo with special characters" 'echo "hello*world"'
compare_output "echo empty string" 'echo ""'

section "2. echo flags"
compare_output "echo -n suppresses newline" 'echo -n hello'
compare_output "echo -n with multiple args" 'echo -n hello world'
compare_output "echo -e interprets backslash-n" 'echo -e "hello\nworld"'
compare_output "echo -e interprets backslash-t" 'echo -e "hello\tworld"'
compare_output "echo -e interprets double backslash" 'echo -e "back\\\\slash"'
compare_output "echo -e interprets backslash-a and backslash-b" 'echo -e "x\b\ay"'
compare_output "echo -E disables escape interpretation" 'echo -E "hello\nworld"'
compare_output "echo -en combines flags" 'echo -en "hello\nworld"'
compare_output "echo -ne combines flags reversed" 'echo -ne "hello\tworld"'

section "3. echo edge cases"
compare_output "echo dash-dash is literal" 'echo -- hello'
compare_output "echo treats unknown flag as text" 'echo -z hello'
compare_output "echo -e with \\c truncates" 'echo -e "hello\cworld"'
compare_output "echo -e with \\0NNN octal" 'echo -e "\0101"'
compare_output "echo -e with \\xNN hex" 'echo -e "\x41"'
compare_output "echo preserves trailing spaces in quotes" 'echo "hello   "'

print_summary
