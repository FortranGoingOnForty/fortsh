#!/bin/sh
TEST_PREFIX="[int-subshell]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtins in subshells

section "1. variable isolation"
compare_output "assignment doesnt leak" 'X=outer; (X=inner); echo $X'
compare_output "export doesnt leak" '(export FOO=bar); echo ${FOO:-unset}'
compare_output "unset doesnt affect parent" 'X=val; (unset X); echo $X'
compare_output "declare doesnt leak" '(declare -i N=5); echo ${N:-unset}'
compare_output "readonly persists in parent" 'readonly RO=val; (echo $RO)'
compare_output "array in subshell doesnt leak" '(arr=(a b c)); echo ${arr:-unset}'
compare_output "multiple vars in subshell" '(A=1; B=2; C=3); echo ${A:-x} ${B:-y} ${C:-z}'

section "2. directory isolation"
compare_output "cd doesnt affect parent" '(cd /tmp); pwd'
compare_output "pushd doesnt affect parent" '(pushd /tmp >/dev/null 2>&1); pwd'
compare_output "multiple cd in subshell" '(cd /tmp; cd /var); pwd'
compare_output "pwd reflects subshell cd" '(cd /tmp; pwd)'
compare_output "cd and var in subshell" '(cd /tmp; X=$(pwd)); echo ${X:-unset}'

section "3. option isolation"
compare_output "set -e doesnt leak" '(set -e); echo ok'
compare_output "set in subshell only" '(set -- a b c; echo $#); echo $#'
compare_output "shopt doesnt leak" '(shopt -s nullglob 2>/dev/null); echo ok'
compare_output "set -u in subshell" '(set -u; echo ${SETVAR:-default})'

section "4. trap isolation"
compare_output "separate EXIT traps" 'trap "echo parent_bye" EXIT; (trap "echo child_bye" EXIT; echo sub_body)'
compare_output "subshell EXIT fires at end" '(trap "echo inner_bye" EXIT; echo body); echo after'
compare_output "trap in subshell independent" '(trap "echo sub_bye" EXIT; echo sub)'
compare_output "parent trap survives subshell" 'trap "echo parent_exit" EXIT; (echo sub); echo main'

section "5. nesting"
compare_output "double nested subshell" '( (echo deep) )'
compare_output "cmd sub inside subshell" '(echo $(echo nested))'
compare_output "layered scope" '(X=1; (X=2; echo $X); echo $X)'
compare_output "triple nested cmd sub" 'echo $(echo $(echo triple))'
compare_output "nested with variable" '(A=outer; (A=inner; echo $A); echo $A)'
compare_output "three level nesting" '(echo 1; (echo 2; (echo 3)))'

section "6. exit status"
compare_output "zero exit" '(exit 0); echo $?'
compare_output "non-zero exit" '(exit 42); echo $?'
compare_output "implicit exit status" '(false); echo $?'
compare_output "OR chain with subshell failure" '(exit 1) || echo recovered'
compare_output "AND chain with subshell success" '(exit 0) && echo continued'
compare_output "nested subshell exit status" '( (exit 3) ); echo $?'
compare_output "exit in nested" '(exit 0); (exit 1); echo $?'

section "7. command substitution as implicit subshell"
compare_output "cmd sub scope" 'X=outer; Y=$(X=inner; echo $X); echo $X $Y'
compare_output "cd in cmd sub" 'Y=$(cd /tmp; pwd); pwd; echo $Y'
compare_output "export in cmd sub" 'Y=$(export EV=val; echo $EV); echo ${EV:-unset} $Y'
compare_output "cmd sub exit status" 'X=$(true); echo $?'
compare_output "cmd sub false status" 'X=$(false); echo $?'
compare_output "nested cmd sub" 'echo $(echo $(echo nested))'

print_summary
