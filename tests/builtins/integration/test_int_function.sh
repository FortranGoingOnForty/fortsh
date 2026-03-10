#!/bin/sh
TEST_PREFIX="[int-function]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtins in/with functions

section "1. scope interaction"
compare_output "local variable scope" 'x=global; f() { local x=local; echo $x; }; f; echo $x'
compare_output "declare scope in function" 'f() { declare -i n=3+4; echo $n; }; f; echo ${n:-unset}'
compare_output "export from function persists" 'f() { export FE=val; }; f; echo $FE'
compare_output "local array scope" 'f() { local -a arr=(1 2 3); echo ${arr[@]}; }; f; echo ${arr:-unset}'
compare_output "readonly from function persists" 'f() { readonly FR=frozen; }; f; echo $FR'
compare_output "declare -g in function" 'f() { declare -g GV=global_val; }; f; echo $GV'
compare_output "local doesnt affect global" 'X=outer; f() { local X=inner; }; f; echo $X'
compare_output "unset local reveals global" 'X=global; f() { local X=local; unset X; echo ${X:-gone}; }; f; echo $X'
compare_output "multiple locals" 'f() { local A=1 B=2 C=3; echo $A $B $C; }; f; echo ${A:-x} ${B:-y} ${C:-z}'

section "2. return and exit status"
compare_output "return 0" 'f() { return 0; }; f; echo $?'
compare_output "return 42" 'f() { return 42; }; f; echo $?'
compare_output "early return" 'f() { echo before; return; echo after; }; f'
compare_output "implicit return status" 'f() { false; }; f; echo $?'
compare_output "return in conditional" 'f() { return 0; }; f && echo yes'
compare_output "return from nested if" 'f() { if true; then return 5; fi; echo unreachable; }; f; echo $?'
compare_output "return preserves value" 'f() { true; return; }; f; echo $?'

section "3. nested functions"
compare_output "simple nested call" 'a() { echo a; }; b() { a; echo b; }; b'
compare_output "inner function def" 'outer() { inner() { echo inner; }; inner; }; outer'
compare_output "scope in nested" 'f() { local x=1; g() { echo $x; }; g; }; f'
compare_output "chain of three" 'a() { echo 1; }; b() { a; echo 2; }; c() { b; echo 3; }; c'
compare_output "mutual call" 'a() { echo a; }; b() { echo b; a; }; b'
compare_output "function overwrite" 'f() { echo old; }; f; f() { echo new; }; f'

section "4. recursion"
compare_output "countdown" 'countdown() { [ $1 -le 0 ] && return; echo $1; countdown $(($1 - 1)); }; countdown 5'
compare_output "recursive sum" 'sum() { [ $1 -le 0 ] && echo 0 && return; echo $(( $1 + $(sum $(($1 - 1))) )); }; sum 5'
compare_output "fibonacci" 'fib() { [ $1 -le 1 ] && echo $1 && return; echo $(( $(fib $(($1 - 1))) + $(fib $(($1 - 2))) )); }; fib 6'

section "5. positional parameters"
compare_output "dollar-hash dollar-1 dollar-2" 'f() { echo $# $1 $2; }; f a b c'
compare_output "shift in function" 'f() { echo $1; shift; echo $1; }; f first second'
compare_output "set in function" 'f() { set -- x y z; echo $@; }; f a b c'
compare_output "set doesnt leak" 'set -- a b; f() { set -- x y z; echo $@; }; f; echo $@'
compare_output "dollar-at quoted" 'f() { for arg in "$@"; do echo "arg:$arg"; done; }; f "hello world" foo'
compare_output "dollar-star" 'f() { echo $*; }; f a b c'

section "6. trap in functions"
compare_output "RETURN trap" 'f() { trap "echo cleaned" RETURN; echo body; }; f'
compare_output "ERR trap in function" 'f() { trap "echo err" ERR; false; }; f 2>/dev/null'
compare_output "function as trap handler" 'cleanup() { echo bye; }; trap cleanup EXIT; echo main'
compare_output "trap reset in function" 'f() { trap "echo trap1" RETURN; trap - RETURN; echo body; }; f'

section "7. functions with builtins"
compare_output "cd in function affects caller" 'ORIG=$(pwd); f() { cd /tmp && pwd; }; f; cd "$ORIG"'
compare_output "eval in function" 'f() { eval "echo hello"; }; f'
compare_output "source in function" "echo 'echo sourced' > $TEST_TMPDIR/fsrc.sh; f() { source $TEST_TMPDIR/fsrc.sh; }; f"
compare_output "hash in function" 'f() { hash -r 2>/dev/null; echo ok; }; f'
compare_output "type in function" 'f() { type echo 2>/dev/null | head -1; }; f'
compare_output "printf in function" 'f() { printf "%d %d %d\n" 1 2 3; }; f'
compare_output "test in function" 'f() { test 5 -gt 3 && echo yes; }; f'

section "8. getopts in functions"
compare_output "getopts basic in function" 'f() { OPTIND=1; while getopts "ab:" opt; do echo "$opt $OPTARG"; done; }; f -a -b val'
compare_output "getopts called twice" 'f() { OPTIND=1; while getopts "x" opt; do echo $opt; done; }; f -x; f -x'
compare_output "getopts with args after" 'f() { OPTIND=1; while getopts "a" opt; do echo $opt; done; shift $((OPTIND-1)); echo $1; }; f -a rest'

print_summary
