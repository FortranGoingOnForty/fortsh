#!/bin/sh
TEST_PREFIX="[int-control-flow]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtins in loops, conditionals, and control flow

section "1. builtins as loop conditions"
compare_output "while read as condition" 'printf "a\nb\nc\n" | while read line; do echo "got:$line"; done'
compare_output "while test as condition" 'i=0; while test $i -lt 3; do echo $i; i=$((i+1)); done'
compare_output "while bracket as condition" 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done'
compare_output "until test as condition" 'i=0; until test $i -ge 3; do echo $i; i=$((i+1)); done'
compare_output "until bracket as condition" 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done'
compare_output "while true with break" 'i=0; while true; do i=$((i+1)); [ $i -ge 3 ] && break; echo $i; done'
compare_output "while command as condition" 'echo -e "a\nb" > /tmp/test_cf_$$; while read line; do echo $line; done < /tmp/test_cf_$$; rm -f /tmp/test_cf_$$'

section "2. break and continue"
compare_output "basic break" 'for i in 1 2 3 4 5; do echo $i; test $i -eq 3 && break; done'
compare_output "basic continue" 'for i in 1 2 3 4 5; do test $i -eq 3 && continue; echo $i; done'
compare_output "break in nested for - inner" 'for i in 1 2; do for j in a b c; do [ $j = b ] && break; echo $i$j; done; done'
compare_output "continue in nested for" 'for i in 1 2; do for j in a b c; do [ $j = b ] && continue; echo $i$j; done; done'
compare_output "break 2 exits both loops" 'for i in 1 2; do for j in a b; do [ $i = 2 ] && break 2; echo $i$j; done; done'
compare_output "continue 2 skips outer" 'for i in 1 2 3; do for j in a b; do [ $i = 2 ] && continue 2; echo $i$j; done; done'
compare_output "break in while" 'i=0; while true; do i=$((i+1)); [ $i -gt 3 ] && break; echo $i; done'
compare_output "continue in while" 'i=0; while [ $i -lt 5 ]; do i=$((i+1)); [ $i -eq 3 ] && continue; echo $i; done'

section "3. if/elif with builtins"
compare_output "if test gt" 'if test 5 -gt 3; then echo yes; fi'
compare_output "if bracket dir" 'if [ -d /tmp ]; then echo dir; fi'
compare_output "if double bracket glob" 'if [[ "hello" == h* ]]; then echo match; fi'
compare_output "if command -v" 'if command -v ls >/dev/null; then echo found; fi'
compare_output "elif chain" 'X=2; if [ $X -eq 1 ]; then echo one; elif [ $X -eq 2 ]; then echo two; else echo other; fi'
compare_output "triple elif" 'X=3; if [ $X -eq 1 ]; then echo one; elif [ $X -eq 2 ]; then echo two; elif [ $X -eq 3 ]; then echo three; else echo other; fi'
compare_output "if false elif false else" 'if false; then echo no; elif false; then echo no2; else echo default; fi'
compare_output "if type builtin" 'if type echo >/dev/null 2>&1; then echo builtin; fi'
compare_output "if with negation" 'if ! false; then echo negated; fi'

section "4. case with builtins"
compare_output "case with echo result" 'X=hello; case $X in h*) echo starts_h;; *) echo other;; esac'
compare_output "case with cmd sub" 'case $(echo hello) in h*) echo match;; esac'
compare_output "case on exit status" 'true; case $? in 0) echo ok;; *) echo fail;; esac'
compare_output "case multiple patterns" 'X=banana; case $X in apple|pear) echo fruit1;; banana|grape) echo fruit2;; esac'
compare_output "case with variable" 'PAT=hello; case $PAT in hello) echo matched;; esac'
compare_output "case fallthrough default" 'X=unknown; case $X in a) echo a;; b) echo b;; *) echo default;; esac'

section "5. compound conditions"
compare_output "and chain both true" 'test -d /tmp && test -d /var && echo both'
compare_output "or chain first false" 'false || echo fallback'
compare_output "and-or chain" 'true && false || echo recovered'
compare_output "negation" '! false && echo negated'
compare_output "double negation" '! ! true; echo $?'
compare_output "complex condition" '[ -d /tmp ] && [ -d /var ] || echo missing'
compare_output "grouped conditions" '{ true && true; } && echo both'

section "6. builtins in loops"
compare_output "for in list" 'for i in 1 2 3; do echo $i; done'
compare_output "for with cmd sub in list" 'for f in $(echo a b c); do echo $f; done'
# TODO: c-style for loop syntax not yet supported (issue #27)
skip "c-style for" "issue #27"
compare_output "echo in while loop" 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done'
compare_output "variable survives non-pipeline loop" 'i=0; while [ $i -lt 3 ]; do i=$((i+1)); done; echo $i'
compare_output "read loop from heredoc" 'while read line; do echo "got:$line"; done <<EOF
x
y
z
EOF'
compare_output "for with brace expansion" 'for i in {1..5}; do echo $i; done'
compare_output "for with glob" "touch $TEST_TMPDIR/cf_a.txt $TEST_TMPDIR/cf_b.txt; for f in $TEST_TMPDIR/cf_*.txt; do basename \$f; done | sort"

section "7. loop exit status"
compare_output "exit status from loop body" 'for cmd in true false true; do $cmd; echo $?; done'
compare_output "while false never runs" 'while false; do echo never; done; echo $?'
compare_output "for loop exit status" 'for i in 1; do true; done; echo $?'
compare_output "for loop last cmd status" 'for i in 1; do false; done; echo $?'

section "8. nested control flow"
compare_output "if inside for" 'for i in 1 2 3; do if [ $i -eq 2 ]; then echo even; else echo odd; fi; done'
compare_output "for inside if" 'if true; then for i in 1 2; do echo $i; done; fi'
compare_output "while inside for" 'for i in 1 2; do j=0; while [ $j -lt 2 ]; do echo "$i.$j"; j=$((j+1)); done; done'
compare_output "case inside for" 'for x in a b c; do case $x in a) echo first;; b) echo second;; *) echo other;; esac; done'

print_summary
