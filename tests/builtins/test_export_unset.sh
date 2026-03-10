#!/bin/sh
TEST_PREFIX="[export-unset]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. export"
compare_output "export VAR=value" 'export MYVAR=hello; echo $MYVAR'
compare_output "export preserves in subshell" 'export MYVAR=hello; bash -c "echo \$MYVAR"'
compare_output "export without value marks for export" 'MYVAR=test; export MYVAR; bash -c "echo \$MYVAR"'
compare_output "export multiple vars" 'export A=1 B=2 C=3; echo $A $B $C'
compare_exit "export -p succeeds" 'export -p'
compare_output "export overwrites existing" 'export V=old; export V=new; echo $V'
compare_output "unexported var not in subshell" 'MYVAR=local; bash -c "echo \${MYVAR:-empty}"'
compare_output "export -n unexports variable" 'export MYVAR=hello; export -n MYVAR; bash -c "echo \${MYVAR:-gone}"'

section "2. unset"
compare_output "unset removes variable" 'MYVAR=hello; unset MYVAR; echo ">${MYVAR}<"'
compare_exit "unset nonexistent var succeeds" 'unset NONEXISTENT_VAR_XYZ_99'
compare_output "unset -v removes variable" 'MYVAR=hello; unset -v MYVAR; echo ">${MYVAR}<"'
compare_output "unset -f removes function" 'f() { echo hi; }; unset -f f; f 2>/dev/null; echo $?'
compare_output "unset multiple vars" 'A=1; B=2; C=3; unset A C; echo ">${A}< ${B} >${C}<"'
compare_output "unset array" 'arr=(a b c); unset arr; echo ">${arr[@]}<"'

section "3. printenv"
compare_output "printenv specific var" 'export MYVAR=hello; printenv MYVAR'
compare_exit "printenv nonexistent var fails" 'printenv NONEXISTENT_VAR_XYZ_99'
compare_exit "printenv with no args succeeds" 'printenv >/dev/null'

print_summary
