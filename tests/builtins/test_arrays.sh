#!/bin/sh
TEST_PREFIX="[arrays]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. indexed array basics"
compare_output "array literal assignment" 'arr=(a b c); echo ${arr[0]}'
compare_output "array second element" 'arr=(a b c); echo ${arr[1]}'
compare_output "array third element" 'arr=(a b c); echo ${arr[2]}'
compare_output "array all elements @" 'arr=(a b c); echo ${arr[@]}'
compare_output "array all elements *" 'arr=(a b c); echo ${arr[*]}'
compare_output "array length" 'arr=(a b c); echo ${#arr[@]}'
compare_output "array single element assignment" 'arr[0]=hello; echo ${arr[0]}'

section "2. indexed array operations"
compare_output "array sparse assignment" 'arr=(); arr[0]=x; arr[5]=y; echo ${arr[5]}'
compare_output "array indices with !" 'arr=(a b c); arr[5]=d; echo ${!arr[@]}'
compare_output "array append +=" 'arr=(a b); arr+=(c d); echo ${arr[@]}'
compare_output "array slice" 'arr=(a b c d e); echo ${arr[@]:1:2}'
compare_output "array slice to end" 'arr=(a b c d e); echo ${arr[@]:2}'
compare_output "array unset element" 'arr=(a b c); unset arr[1]; echo ${arr[@]}'
compare_output "array unset preserves indices" 'arr=(a b c d); unset arr[1]; echo ${!arr[@]}'
compare_output "array element length" 'arr=(hello world); echo ${#arr[0]}'

section "3. indexed array advanced"
compare_output "array in for loop" 'arr=(a b c); for x in "${arr[@]}"; do echo $x; done'
compare_output "array with spaces in elements" 'arr=("hello world" "foo bar"); echo ${arr[0]}'
compare_output "array reassignment" 'arr=(a b c); arr=(x y); echo ${arr[@]}'
compare_output "array from command substitution" 'arr=($(echo a b c)); echo ${arr[1]}'
compare_output "array element modification" 'arr=(a b c); arr[1]=B; echo ${arr[@]}'

section "4. associative array basics"
compare_output "assoc array set and get" 'declare -A m; m[name]=alice; echo ${m[name]}'
compare_output "assoc array multiple keys" 'declare -A m; m[a]=1; m[b]=2; m[c]=3; echo ${m[a]} ${m[b]} ${m[c]}'
compare_output "assoc array count" 'declare -A m; m[a]=1; m[b]=2; m[c]=3; echo ${#m[@]}'
compare_output "assoc array overwrite key" 'declare -A m; m[k]=old; m[k]=new; echo ${m[k]}'
compare_output "assoc array unset key" 'declare -A m; m[a]=1; m[b]=2; unset m[a]; echo ${#m[@]}'

section "5. associative array advanced"
compare_output "assoc array key list sorted" 'declare -A m; m[x]=1; m[y]=2; for k in "${!m[@]}"; do echo "$k"; done | sort'
compare_output "assoc array value with spaces" 'declare -A m; m[key]="hello world"; echo ${m[key]}'
compare_output "assoc array numeric keys" 'declare -A m; m[1]=one; m[2]=two; echo ${m[1]} ${m[2]}'
compare_output "assoc array empty value" 'declare -A m; m[k]=""; echo ">${m[k]}<"'
compare_output "assoc array in loop" 'declare -A m; m[a]=1; m[b]=2; for v in "${m[@]}"; do echo $v; done | sort'
compare_output "assoc array quoted key" 'declare -A m; m["my key"]="value"; echo ${m["my key"]}'

print_summary
