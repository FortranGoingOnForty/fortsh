#!/bin/sh
TEST_PREFIX="[declare]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. declare basic flags"
compare_output "declare -i integer arithmetic" 'declare -i num=5+3; echo $num'
compare_output "declare -r is readonly" 'declare -r RO=hello; echo $RO'
compare_exit "declare -r prevents modification" 'declare -r RO=hello; RO=world 2>/dev/null'
compare_output "declare -x exports variable" 'declare -x MYEXP=exported; '"$BASH_REF"' -c "echo \$MYEXP"'
compare_output "declare plain variable" 'declare V=hello; echo $V'

section "2. declare arrays"
compare_output "declare -a indexed array" 'declare -a arr=(a b c); echo ${arr[1]}'
compare_output "declare -a empty array" 'declare -a arr; arr[0]=x; echo ${arr[0]}'
compare_output "declare -A associative array" 'declare -A map; map[key]=val; echo ${map[key]}'
compare_output "declare -A multiple keys" 'declare -A m; m[a]=1; m[b]=2; echo ${m[a]} ${m[b]}'
compare_output "declare -A overwrite key" 'declare -A m; m[k]=old; m[k]=new; echo ${m[k]}'

section "3. declare listing"
check_exit "declare -p prints attributes" 'declare -p >/dev/null' "0"
compare_output "declare without args succeeds" 'declare >/dev/null; echo $?'
compare_output "declare -p specific var" 'declare -i NUM=42; declare -p NUM'

section "4. declare integer behavior"
compare_output "declare -i assignment evaluates arithmetic" 'declare -i x; x=2+3; echo $x'
compare_output "declare -i multiplication" 'declare -i x=3*4; echo $x'
compare_output "declare -i with variable reference" 'y=10; declare -i x=y+5; echo $x'
compare_output "declare -i string assigns zero" 'declare -i x=notanumber; echo $x'

section "5. declare combined flags"
compare_output "declare -ix integer and export" 'declare -ix INTEXP=42; echo $INTEXP'
compare_output "declare -ri readonly integer" 'declare -ri RINT=42; echo $RINT'
compare_exit "declare -ri prevents modification" 'declare -ri RINT=42; RINT=99 2>/dev/null'

print_summary
