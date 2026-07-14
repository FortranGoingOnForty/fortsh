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
check_output "printf %d with non-numeric arg" 'printf "%d\n" abc 2>&1' "fortsh: printf: abc: invalid number
0"

section "6. printf special formats"
compare_output "printf %q shell-quoted string" 'printf "%q\n" "hello world"'
compare_output "printf octal escape in format" 'printf "\101\n"'
compare_output "printf hex escape in format" 'printf "\x41\n"'

section "20. Wave-5: 64-bit integers and unsigned (BUILTIN-2, BUILTIN-16)"

compare_both "%d past 2^31"          "printf '%d\n' 9999999999"
compare_both "%x of -1 is 64-bit"    "printf '%x\n' -1"
compare_both "%x past 2^32"          "printf '%x\n' 4294967296"
compare_both "%u of -1"              "printf '%u\n' -1"
compare_both "%u of -2"              "printf '%u\n' -2"
compare_both "%u positive"           "printf '%u\n' 42"
compare_both "small ints unchanged"  "printf '%d %05d %#x\n' 5 42 255"

section "21. Wave-5: %b \\c terminator and precision (BUILTIN-8)"

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "printf '%b\n' 'a\tb\c' ignored" | od -An -c | tr -s ' ')
exp=$(run_with_timeout "$TEST_TIMEOUT" "$BASH_REF" -c "printf '%b\n' 'a\tb\c' ignored" | od -An -c | tr -s ' ')
if [ "$out" = "$exp" ]; then
    pass "\\c stops output, args, and the trailing newline"
else
    fail "\\c stops output, args, and the trailing newline" "$exp" "$out"
fi
compare_both "%.2b truncates"        "printf '%.2b\n' abcdef"

section "22. Wave-5: %(fmt)T and %a (BUILTIN-9)"

out=$(TZ=UTC run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "printf '%(%Y)T\n' 0")
exp=$(TZ=UTC run_with_timeout "$TEST_TIMEOUT" "$BASH_REF" -c "printf '%(%Y)T\n' 0")
if [ "$out" = "$exp" ]; then
    pass "%(%Y)T of epoch 0 in UTC"
else
    fail "%(%Y)T of epoch 0 in UTC" "$exp" "$out"
fi
compare_both "%(%s)T round-trips"    "printf '%(%s)T\n' 1234567890"
compare_both "%a hex float"          "printf '%a\n' 1.5"
compare_both "%A hex float"          "printf '%A\n' 1.5"

section "23. Wave-5: %g trailing zeros (BUILTIN-10)"

compare_both "%g large -> short exp" "printf '%g\n' 100000000"
compare_both "%g strips zeros"       "printf '%g\n' 1.5"
compare_both "%g integral value"     "printf '%g\n' 1.0"

section "24. Wave-5: integer precision (BUILTIN-11)"

compare_both "width and precision"   "printf '%5.3d\n' 7"
compare_both "%.5x zero-pads"        "printf '%.5x\n' 255"
compare_both "%.0d of 0 is empty"    "printf '[%.0d]\n' 0"
compare_both "%.0d of 5 prints"      "printf '[%.0d]\n' 5"

section "25. Wave-5: %q of empty string (BUILTIN-17)"

compare_both "empty arg round-trips" "printf '[%q]\n' ''"
compare_both "non-empty unchanged"   "printf '%q\n' 'a b'"

print_summary
