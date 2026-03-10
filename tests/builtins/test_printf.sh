#!/bin/sh
TEST_PREFIX="[printf]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. printf format specifiers"
compare_output "printf %s string" 'printf "%s\n" hello'
compare_output "printf %d decimal" 'printf "%d\n" 42'
compare_output "printf %x hex lowercase" 'printf "%x\n" 255'
compare_output "printf %X hex uppercase" 'printf "%X\n" 255'
compare_output "printf %o octal" 'printf "%o\n" 8'
compare_output "printf %c character" 'printf "%c\n" A'
compare_output "printf %i integer" 'printf "%i\n" 42'

section "2. printf width and precision"
compare_output "printf left-aligned %-10s" 'printf "[%-10s]\n" hi'
compare_output "printf right-aligned %10s" 'printf "[%10s]\n" hi'
compare_output "printf precision truncate %.5s" 'printf "%.5s\n" "hello world"'
compare_output "printf zero-padded %05d" 'printf "%05d\n" 42'
compare_output "printf width with string %8s" 'printf "[%8s]\n" "abc"'
compare_output "printf negative number" 'printf "%d\n" -5'

section "3. printf escape sequences"
compare_output "printf newline in format" 'printf "a\nb\n"'
compare_output "printf tab in format" 'printf "a\tb\n"'
compare_output "printf backslash in format" 'printf "a\\\\b\n"'
compare_output "printf carriage return" 'printf "hello\rworld\n"'
compare_output "printf literal percent" 'printf "100%%\n"'

section "4. printf multiple args and %b"
compare_output "printf recycles format for multiple args" 'printf "%s\n" a b c'
compare_output "printf %b interprets escapes in arg" 'printf "%b\n" "hello\nworld"'
compare_output "printf multiple %s in format" 'printf "%s=%s\n" key val'
compare_output "printf mixed format" 'printf "%s is %d\n" age 25'

section "5. printf error handling"
compare_exit "printf missing format string" 'printf'
compare_output "printf missing arg uses default" 'printf "%s %d\n"'
compare_output "printf extra args recycle" 'printf "%s\n" a b c d'
compare_output "printf %d with non-numeric arg" 'printf "%d\n" abc 2>&1'

section "6. printf special formats"
compare_output "printf %q shell-quoted string" 'printf "%q\n" "hello world"'
compare_output "printf octal escape in format" 'printf "\101\n"'
compare_output "printf hex escape in format" 'printf "\x41\n"'

print_summary
