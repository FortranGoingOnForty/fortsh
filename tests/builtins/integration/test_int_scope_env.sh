#!/bin/sh
TEST_PREFIX="[int-scope-env]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: variable scope, export, source, environment inheritance

section "1. export inheritance"
compare_output "exported var in subshell" 'export SEX=hello; (echo $SEX)'
compare_output "non-exported not in subshell cmd" 'SEX2=hello; echo ${SEX2:-unset}'
compare_output "export from function" 'f() { export SEF=val; }; f; echo $SEF'
compare_output "export -n removes export" 'export SEN=val; export -n SEN; echo $SEN'
compare_output "export with value" 'export SEV=hello; echo $SEV'
compare_output "export existing var" 'SEE=existing; export SEE; echo $SEE'

section "2. source/dot scope"
compare_output "var from source" "echo 'SSV=sourced' > $TEST_TMPDIR/scope1.sh; source $TEST_TMPDIR/scope1.sh; echo \$SSV"
compare_output "source overwrites var" "X_SC=before; echo 'X_SC=after' > $TEST_TMPDIR/scope2.sh; source $TEST_TMPDIR/scope2.sh; echo \$X_SC"
compare_output "return from source" "echo 'return 42' > $TEST_TMPDIR/scope3.sh; source $TEST_TMPDIR/scope3.sh; echo \$?"
compare_output "cd from source" "echo 'cd /tmp' > $TEST_TMPDIR/scope4.sh; ORIG=\$(pwd); source $TEST_TMPDIR/scope4.sh; pwd; cd \"\$ORIG\""
compare_output "function def from source" "echo 'sf() { echo sourced_func; }' > $TEST_TMPDIR/scope5.sh; source $TEST_TMPDIR/scope5.sh; sf"
compare_output "multiple source" "echo 'A_SC=1' > $TEST_TMPDIR/scope6a.sh; echo 'B_SC=2' > $TEST_TMPDIR/scope6b.sh; source $TEST_TMPDIR/scope6a.sh; source $TEST_TMPDIR/scope6b.sh; echo \$A_SC \$B_SC"
compare_output "source with args" "echo 'echo \$1 \$2' > $TEST_TMPDIR/scope7.sh; source $TEST_TMPDIR/scope7.sh hello world"
compare_output "dot command same as source" "echo 'DSV=dotted' > $TEST_TMPDIR/scope8.sh; . $TEST_TMPDIR/scope8.sh; echo \$DSV"

section "3. eval scope"
compare_output "eval modifies scope" 'eval "ESV=from_eval"; echo $ESV'
compare_output "eval export" 'eval "export ESE=eval_export"; echo $ESE'
compare_output "eval readonly" 'eval "readonly ESR=eval_readonly"; echo $ESR'
compare_output "eval function def" 'eval "esf() { echo eval_func; }"; esf'
compare_output "eval preserves vars" 'X_EV=before; eval "echo \$X_EV"'
compare_output "nested eval" 'eval "eval \"echo nested_eval\""'

section "4. declare -g"
compare_output "declare -g from function" 'f() { declare -g DGV=global_val; }; f; echo $DGV'
compare_output "declare without -g stays local" 'f() { declare DLV=local_val; }; f; echo ${DLV:-unset}'
compare_output "declare -g overwrites" 'DGO=old; f() { declare -g DGO=new; }; f; echo $DGO'

section "5. IFS manipulation scope"
compare_output "IFS in function local" 'f() { local IFS=:; read A B <<< "x:y"; echo $A $B; }; f; echo "${IFS:-default}" | cat -v'
compare_output "IFS change persists" 'IFS=:; read A B <<< "x:y"; echo $A; IFS=" "'
compare_output "IFS in subshell" '(IFS=:; read A B <<< "x:y"; echo $A $B)'
compare_output "IFS reset" 'IFS=:; unset IFS; echo "a b c" | { read A B C; echo $A; }'

section "6. readonly scope"
compare_output "readonly visible in functions" 'readonly SRV=fixed; f() { echo $SRV; }; f'
compare_output "readonly visible in subshells" 'readonly SRS=fixed; (echo $SRS)'
compare_output "readonly from function persists" 'f() { readonly SRF=in_func; }; f; echo $SRF'
compare_output "readonly blocks reassignment" 'readonly SRB=fixed; { SRB=other; } 2>/dev/null; echo $SRB'
compare_output "readonly blocks unset" 'readonly SRU=fixed; unset SRU 2>/dev/null; echo $SRU'

section "7. variable cleanup"
compare_output "unset removes var" 'SUV=temp; unset SUV; echo ${SUV:-gone}'
compare_output "unset array" 'SUA=(1 2 3); unset SUA; echo ${SUA:-gone}'
compare_output "unset function" 'suf() { echo hi; }; unset -f suf; suf 2>/dev/null; echo $?'
compare_output "unset in function" 'SUF2=outer; f() { unset SUF2; }; f; echo ${SUF2:-gone}'
compare_output "unset exported var" 'export SUE=val; unset SUE; echo ${SUE:-gone}'

print_summary
