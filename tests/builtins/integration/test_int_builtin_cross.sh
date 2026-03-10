#!/bin/sh
TEST_PREFIX="[int-builtin-cross]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtin-to-builtin interactions

section "1. declare/export/readonly interaction"
compare_output "declare -x is export" 'declare -x BDX=exported; echo $BDX'
compare_output "declare -r is readonly" 'declare -r BDR=readonly; BDR=other 2>/dev/null; echo $BDR'
compare_output "export then readonly" 'export BER=val; readonly BER; BER=other 2>/dev/null; echo $BER'
compare_output "declare -ix integer export" 'declare -ix BDI=5; echo $BDI'
compare_output "declare -a then export" 'declare -a BDA=(1 2 3); export BDA; echo ${BDA[@]}'
compare_output "readonly then unset fails" 'readonly BRU=val; unset BRU 2>/dev/null; echo $? $BRU'
compare_output "export -p shows exported" 'export BEP=val; export -p | grep BEP | head -1'

section "2. set/shift interaction"
compare_output "set then shift" 'set -- a b c; shift; echo $@'
compare_output "set then shift 2" 'set -- a b c; shift 2; echo $@'
compare_output "set then count" 'set -- a b c; echo $#; shift; echo $#'
compare_output "set resets positional" 'set -- a b c; set -- x y; echo $@'
compare_output "set empty clears" 'set -- a b c; set --; echo $#'
compare_output "shift all" 'set -- a b c; shift 3; echo $#'

section "3. pushd/popd/dirs stack"
compare_output "round trip" 'ORIG=$(pwd); pushd /tmp >/dev/null; pushd /var >/dev/null; popd >/dev/null; popd >/dev/null; test "$(pwd)" = "$ORIG" && echo same'
compare_output "deep round trip" 'ORIG=$(pwd); pushd /tmp >/dev/null; pushd /var >/dev/null; pushd / >/dev/null; popd >/dev/null; popd >/dev/null; popd >/dev/null; test "$(pwd)" = "$ORIG" && echo same'
compare_output "dirs shows stack" 'pushd /tmp >/dev/null; pushd /var >/dev/null; dirs 2>/dev/null'
compare_output "dirs -v numbered" 'pushd /tmp >/dev/null; dirs -v 2>/dev/null'
compare_output "pushd swap top two" 'pushd /tmp >/dev/null; pushd /var >/dev/null; pushd >/dev/null 2>/dev/null; pwd'
compare_output "dirs -c clears stack" 'pushd /tmp >/dev/null; dirs -c 2>/dev/null; dirs 2>/dev/null'

section "4. alias/eval interaction"
compare_output "alias in eval" 'alias bgreet="echo hi" 2>/dev/null; eval bgreet 2>/dev/null || echo no_expand'
compare_output "alias then unalias" 'alias bua="echo test" 2>/dev/null; unalias bua 2>/dev/null; echo $?'
compare_output "alias overwrite" 'alias bao="echo old" 2>/dev/null; alias bao="echo new" 2>/dev/null; eval bao 2>/dev/null || echo no_expand'

section "5. trap/exit interaction"
compare_output "EXIT trap fires on exit" 'trap "echo bye" EXIT; exit 0'
compare_output "EXIT trap fires on implicit exit" 'trap "echo bye" EXIT; true'
compare_output "trap then trap replaces" 'trap "echo a" EXIT; trap "echo b" EXIT'
compare_output "trap then clear" 'trap "echo a" EXIT; trap - EXIT; echo done'
compare_output "EXIT trap sees last status" 'trap "echo \$?" EXIT; false'

section "6. hash/command interaction"
compare_output "hash -r then command -v" 'hash -r 2>/dev/null; command -v ls'
compare_output "command -v builtin" 'command -v echo'
compare_output "command -v not found" 'command -v nonexistent_xyz_123; echo $?'

section "7. type/command interaction"
compare_output "type echo" 'type echo 2>/dev/null | head -1'
compare_output "command -V echo" 'command -V echo 2>/dev/null | head -1'
compare_output "type external" 'type ls 2>/dev/null | head -1'
compare_output "type not found" 'type nonexistent_xyz_123 2>/dev/null; echo $?'

section "8. read/echo round-trip"
compare_output "echo pipe read" 'echo "hello world" | { read A B; echo "$A $B"; }'
compare_output "printf pipe while read" 'printf "a\nb\nc\n" | { while read line; do echo "[$line]"; done; }'
compare_output "echo to file and read back" "echo 'data here' > $TEST_TMPDIR/brt1; read VAR < $TEST_TMPDIR/brt1; echo \$VAR"
compare_output "printf format and read" 'printf "%d\n" 42 | { read N; echo "got:$N"; }'

section "9. eval/source chain"
compare_output "eval source" "echo 'BES=sourced' > $TEST_TMPDIR/bchain.sh; eval 'source $TEST_TMPDIR/bchain.sh'; echo \$BES"
compare_output "nested eval" 'eval "eval \"echo deep\""'
compare_output "eval with variable" 'CMD="echo hello"; eval "$CMD"'
compare_output "eval with special chars" 'eval "echo hello world"'

section "10. let/declare -i interaction"
compare_output "declare -i then let" 'declare -i BDL=0; let BDL+=5; echo $BDL'
compare_output "let standalone" 'let X=3+4 2>/dev/null; echo $X'
compare_output "declare -i auto-arithmetic" 'declare -i BDA2=3+4; echo $BDA2'
compare_output "let comparison" 'let "5 > 3" 2>/dev/null; echo $?'
compare_output "let false comparison" 'let "3 > 5" 2>/dev/null; echo $?'

print_summary
