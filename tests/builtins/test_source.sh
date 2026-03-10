#!/bin/sh
TEST_PREFIX="[source]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

# Create test files
printf 'SOURCED_VAR=hello\n' > "$TEST_TMPDIR/source_var.sh"
printf 'greet() { echo "hi $1"; }\n' > "$TEST_TMPDIR/source_func.sh"
printf 'echo "arg1=$1 arg2=$2"\n' > "$TEST_TMPDIR/source_args.sh"
printf 'X=10\nY=20\necho $((X + Y))\n' > "$TEST_TMPDIR/source_multi.sh"
printf 'return 42\n' > "$TEST_TMPDIR/source_return.sh"

section "1. source basic"
compare_output "source file sets variable" "source $TEST_TMPDIR/source_var.sh; echo \$SOURCED_VAR"
compare_output "source file defines function" "source $TEST_TMPDIR/source_func.sh; greet world"
compare_exit "source nonexistent file fails" "source $TEST_TMPDIR/no_such_file.sh 2>/dev/null"
compare_output "source with arguments" "source $TEST_TMPDIR/source_args.sh foo bar"
compare_output "source multiple assignments" "source $TEST_TMPDIR/source_multi.sh"

section "2. dot command"
compare_output "dot command works like source" ". $TEST_TMPDIR/source_var.sh; echo \$SOURCED_VAR"
compare_output "dot with function def" ". $TEST_TMPDIR/source_func.sh; greet user"
compare_exit "dot nonexistent file fails" ". $TEST_TMPDIR/no_such_file.sh 2>/dev/null"

section "3. source edge cases"
compare_exit "source file with return" "source $TEST_TMPDIR/source_return.sh"
compare_output "source preserves env" "A=before; printf 'A=after\n' > $TEST_TMPDIR/s.sh; source $TEST_TMPDIR/s.sh; echo \$A"
compare_output "source in function" "f() { source $TEST_TMPDIR/source_var.sh; echo \$SOURCED_VAR; }; f"

print_summary
