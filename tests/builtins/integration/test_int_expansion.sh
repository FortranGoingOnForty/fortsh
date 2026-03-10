#!/bin/sh
TEST_PREFIX="[int-expansion]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtins with parameter, arithmetic, and command substitution

section "1. parameter expansion with builtins"
compare_output "default value" 'X=hello; echo ${X:-default}'
compare_output "unset default" 'echo ${UNSET_VAR_XYZ:-fallback}'
compare_output "alternate value set" 'X=hello; echo ${X:+alternate}'
compare_output "alternate value unset" 'echo ${UNSET_VAR_XYZ:+alternate}'
compare_output "prefix strip" 'X=hello; echo ${X#h}'
compare_output "prefix strip greedy" 'X=hello; echo ${X##*l}'
compare_output "suffix strip" 'X=hello; echo ${X%o}'
compare_output "suffix strip greedy" 'X=hello; echo ${X%%l*}'
compare_output "substitution" 'X=hello_world; echo ${X/world/earth}'
compare_output "substitution global" 'X=ababa; echo ${X//a/x}'
compare_output "string length" 'X=hello; echo ${#X}'
compare_output "assign default" 'unset ADEF; echo ${ADEF:=assigned}; echo $ADEF'
compare_output "substring" 'X=hello; echo ${X:1:3}'
compare_output "uppercase" 'X=hello; echo ${X^^}'
compare_output "lowercase" 'X=HELLO; echo ${X,,}'
compare_output "first char upper" 'X=hello; echo ${X^}'
compare_output "first char lower" 'X=HELLO; echo ${X,}'

section "2. array expansion with builtins"
compare_output "all elements" 'arr=(a b c); echo ${arr[@]}'
compare_output "element count" 'arr=(a b c); echo ${#arr[@]}'
compare_output "index access" 'arr=(a b c); echo ${arr[1]}'
compare_output "first element" 'arr=(a b c); echo ${arr[0]}'
compare_output "last element" 'arr=(a b c); echo ${arr[-1]}'
compare_output "array slice" 'arr=(a b c d e); echo ${arr[@]:1:3}'
compare_output "iterate array" 'arr=(a b c); for x in "${arr[@]}"; do echo $x; done'
compare_output "array length of element" 'arr=(hello world); echo ${#arr[0]}'
compare_output "assoc array access" 'declare -A map; map[key]=value; echo ${map[key]}'
compare_output "assoc array keys" 'declare -A m; m[a]=1; m[b]=2; echo ${!m[@]} | tr " " "\n" | sort | tr "\n" " "; echo'
compare_output "array append" 'arr=(a b); arr+=(c); echo ${arr[@]}'
compare_output "array unset element" 'arr=(a b c); unset arr[1]; echo ${arr[@]}'

section "3. arithmetic expansion"
compare_output "basic add" 'echo $((3 + 4))'
compare_output "variable in arithmetic" 'X=5; echo $((X * 2))'
compare_output "exponent" 'echo $((2 ** 10))'
compare_output "grouping" 'echo $(( (3 + 4) * 2 ))'
compare_output "modulo" 'echo $((17 % 5))'
compare_output "division" 'echo $((10 / 3))'
compare_output "comparison in arithmetic" 'echo $((5 > 3))'
compare_output "ternary" 'X=5; echo $(( X > 3 ? 1 : 0 ))'
compare_output "increment" 'X=5; echo $((++X)); echo $X'
compare_output "decrement" 'X=5; echo $((--X)); echo $X'
compare_output "compound assignment" 'X=10; echo $((X += 5)); echo $X'
compare_output "bitwise and" 'echo $((12 & 10))'
compare_output "bitwise or" 'echo $((12 | 10))'
compare_output "left shift" 'echo $((1 << 4))'

section "4. command substitution"
compare_output "basic cmd sub" 'echo "$(echo hello)"'
compare_output "nested cmd sub" 'echo "$(echo $(echo nested))"'
compare_output "cd in cmd sub" 'X=$(cd /tmp && pwd); echo $X'
compare_output "exit status from cmd sub" 'X=$(true); echo $?'
compare_output "false status from cmd sub" 'X=$(false); echo $?'
compare_output "backtick form" 'echo `echo backtick`'
compare_output "cmd sub preserves newlines in var" 'X=$(printf "a\nb"); echo "$X"'
compare_output "cmd sub strips trailing newline" 'X=$(echo hello); echo $X'
compare_output "cmd sub in arithmetic" 'echo $(( $(echo 3) + $(echo 4) ))'
compare_output "nested cmd sub with processing" 'echo $(echo $(echo hello) | tr a-z A-Z)'

section "5. tilde expansion"
compare_output "tilde expands to HOME" 'echo ~ | grep -q / && echo yes'
compare_output "tilde with path" 'echo ~/subdir | grep -q / && echo yes'
compare_output "cd with tilde" 'cd ~ && echo $? || echo failed'

section "6. word splitting and IFS"
compare_output "IFS colon split" 'IFS=:; read A B C <<< "one:two:three"; echo "$A $B $C"'
compare_output "custom IFS in for" 'IFS=,; for x in $(echo "a,b,c"); do echo $x; done'
compare_output "word splitting with set" 'X="a  b  c"; set -- $X; echo $#'
compare_output "IFS default splitting" 'X="a b c"; set -- $X; echo $1 $2 $3'
compare_output "IFS empty no splitting" 'IFS=""; X="a b c"; set -- $X; echo $#'

section "7. brace expansion"
compare_output "comma brace" 'echo {a,b,c}'
compare_output "range brace" 'echo {1..5}'
compare_output "range with step" 'echo {1..10..2}'
compare_output "brace with prefix" 'echo file.{txt,md,sh}'
compare_output "nested brace" 'echo {a,b}{1,2}'

section "8. quoting interaction"
compare_output "double quotes preserve" 'X="hello world"; echo "$X"'
compare_output "single quotes literal" 'X="hello world"; echo '"'"'$X'"'"''
compare_output "nested quoting in cmd sub" 'echo "$(echo "nested quotes")"'
compare_output "escaped dollar" 'echo \$HOME'
compare_output "escaped backtick" 'echo \`echo hi\`'
compare_output "mixed quoting" "echo 'single' \"double\" plain"
compare_output "quote in variable" 'X="it'"'"'s"; echo "$X"'

print_summary
