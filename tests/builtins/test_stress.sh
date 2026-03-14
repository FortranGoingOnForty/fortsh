#!/bin/sh
# ============================================================
# Stress tests for allocatable string / widened buffer changes
# ============================================================
# These tests verify that fortsh handles large values, deep
# nesting, many variables, and boundary conditions correctly
# after the MAX_VAR_VALUE_LEN 1024->4096 refactoring.
#
# Tests marked with skip() are known pre-existing issues not
# related to the buffer refactoring.

TEST_PREFIX="STRESS"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/test_harness.sh"

# Increase timeout for stress tests
TEST_TIMEOUT=30

# ==========================================
# 1. Long variable values
# ==========================================
section "1 - Long variable values"

compare_output "2000-char variable via printf %0*d" \
  'x=$(printf "%0*d" 2000 0); echo ${#x}'

compare_output "3000-char variable via printf %0*d" \
  'x=$(printf "%0*d" 3000 0); echo ${#x}'

compare_output "4000-char variable (near limit)" \
  'x=$(printf "%0*d" 4000 0); echo ${#x}'

compare_output "variable with 1000 'a' chars" \
  'x=$(printf "a%.0s" $(seq 1 1000)); echo ${#x}'

# printf "a%.0s" with many args hits command expansion buffer
# use python or head /dev/zero instead for large single-char strings
compare_output "2000-char variable via head" \
  'x=$(head -c 2000 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "3000-char variable via head" \
  'x=$(head -c 3000 /dev/zero | tr "\0" "a"); echo ${#x}'

# BUG: printf "a%.0s" with many args truncates at ~1041 chars (#37)
compare_output "2000-char via printf repeat" \
  'x=$(printf "a%.0s" $(seq 1 2000)); echo ${#x}'

compare_output "long variable substring" \
  'x=$(printf "%0*d" 3000 0); echo ${#x}; y=${x:500:1000}; echo ${#y}'

compare_output "long variable pattern removal" \
  'x="aaa$(printf "%0*d" 2000 0)aaa"; y=${x##aaa}; echo ${#y}'

# ==========================================
# 2. Long command lines
# ==========================================
section "2 - Long command lines"

compare_output "echo with 500 args" \
  'echo $(seq 1 500) | wc -w'

compare_output "echo with 1000 args" \
  'echo $(seq 1 1000) | wc -w'

compare_output "long pipe chain" \
  'echo hello | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat'

compare_output "long command with semicolons" \
  'a=1; b=2; c=3; d=4; e=5; f=6; g=7; h=8; i=9; j=10; echo $a $b $c $d $e $f $g $h $i $j'

# ==========================================
# 3. Array stress tests
# ==========================================
section "3 - Array stress tests"

# Use explicit indices to avoid arr[$i]= parsing differences
compare_output "array direct assignment 10 elements" \
  'arr=(a b c d e f g h i j); echo ${#arr[@]}'

compare_output "array with explicit long values" \
  'x=$(printf "%0*d" 100 0); arr[0]=$x; arr[1]=$x; echo ${#arr[0]} ${#arr[1]}'

# BUG: array element assignment truncates long values (#35)
compare_output "array element from command substitution" \
  'arr[0]=$(printf "%0*d" 1000 0); echo ${#arr[0]}'

compare_output "array append" \
  'arr=(); for i in $(seq 1 30); do arr+=("item$i"); done; echo ${#arr[@]}'

compare_output "array slice" \
  'arr=(a b c d e f g h i j); echo ${arr[@]:3:4}'

compare_output "unset array elements" \
  'arr=(1 2 3 4 5 6 7 8 9 10); unset arr[4]; unset arr[7]; echo ${#arr[@]}'

# ==========================================
# 4. Associative array stress tests
# ==========================================
section "4 - Associative array stress tests"

compare_output "basic assoc array" \
  'declare -A m; m[a]=1; m[b]=2; m[c]=3; echo ${#m[@]}'

compare_output "assoc array with long value via var" \
  'declare -A m; x=$(printf "%0*d" 1000 0); m[k]=$x; echo ${#m[k]}'

# BUG: assoc element assignment truncates long values (#35)
compare_output "assoc array element from command substitution" \
  'declare -A m; m[x]=$(printf "%0*d" 1000 0); echo ${#m[x]}'

compare_output "assoc array overwrite" \
  'declare -A m; m[k]=old; m[k]=new; echo ${m[k]}'

# ==========================================
# 5. Deep nesting
# ==========================================
section "5 - Deep nesting"

compare_output "nested if 10 levels" \
  'x=1; if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then echo deep; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi'

compare_output "nested loops 5 levels" \
  'for a in 1 2; do for b in 1 2; do for c in 1 2; do for d in 1 2; do for e in 1 2; do echo "$a$b$c$d$e"; done; done; done; done; done | wc -l'

compare_output "nested command substitution 5 levels" \
  'echo $(echo $(echo $(echo $(echo hello))))'

compare_output "nested case in loops" \
  'for i in a b c; do case $i in a) echo A;; b) for j in 1 2; do case $j in 1) echo B1;; 2) echo B2;; esac; done;; c) echo C;; esac; done'

# ==========================================
# 6. Many variables
# ==========================================
section "6 - Many variables"

compare_output "100 variables" \
  'for i in $(seq 1 100); do eval "var_$i=$i"; done; echo $var_1 $var_50 $var_100'

compare_output "export 50 variables" \
  'for i in $(seq 1 50); do export "ev_$i=$i"; done; env | grep "^ev_" | wc -l'

compare_output "rapid set/unset cycle" \
  'for i in $(seq 1 50); do x=$i; unset x; done; echo ${x:-unset}'

# ==========================================
# 7. Function stress tests
# ==========================================
section "7 - Function stress tests"

compare_output "function with many params" \
  'f() { echo $# $1 $5 ${10}; }; f a b c d e f g h i j'

compare_output "recursive function 10 levels" \
  'f() { if [ $1 -le 0 ]; then echo done; else f $(($1 - 1)); fi; }; f 10'

compare_output "recursive function 20 levels" \
  'f() { if [ $1 -le 0 ]; then echo $1; return; fi; f $(($1 - 1)); }; f 20'

# BUG: recursive function 50 levels causes core dump (#36)
compare_output "recursive function 50 levels" \
  'f() { if [ $1 -le 0 ]; then echo $1; return; fi; f $(($1 - 1)); }; f 50'

compare_output "function redefine in loop" \
  'for i in 1 2 3; do eval "f() { echo $i; }"; f; done'

compare_output "function local var scoping" \
  'f() { local x=inner; echo $x; }; x=outer; f; echo $x'

compare_output "nested function calls 5 levels" \
  'a() { echo a; b; }; b() { echo b; c; }; c() { echo c; d; }; d() { echo d; e; }; e() { echo e; }; a'

# ==========================================
# 8. Alias stress tests
# ==========================================
section "8 - Alias stress tests"

check_output "alias with long command" \
  'shopt -s expand_aliases; alias longcmd="echo hello_from_alias"; longcmd' \
  'hello_from_alias'

compare_output "many aliases" \
  'shopt -s expand_aliases; for i in $(seq 1 20); do alias "a$i=echo $i"; done; alias | wc -l'

# ==========================================
# 9. Trap stress tests
# ==========================================
section "9 - Trap stress tests"

compare_output "EXIT trap fires" \
  'trap "echo trapped" EXIT; true'

compare_output "multiple trap signals" \
  'trap "echo exit" EXIT; trap "echo hup" HUP; trap "echo usr1" USR1; trap -p | wc -l'

compare_output "trap set/unset cycle" \
  'for i in $(seq 1 10); do trap "echo $i" EXIT; done; trap -p EXIT'

# ==========================================
# 10. Heredoc stress tests
# ==========================================
section "10 - Heredoc stress tests"

compare_output "heredoc basic" \
  'cat <<EOF
line1
line2
line3
EOF'

compare_output "heredoc with variable expansion" \
  'x=world; cat <<EOF
hello $x
EOF'

compare_output "heredoc with long delimiter" \
  'cat <<VERYLONGDELIMITERTHATISTOTALLYUNNECESSARY
hello
VERYLONGDELIMITERTHATISTOTALLYUNNECESSARY'

# ==========================================
# 11. String operations on large values
# ==========================================
section "11 - String operations"

compare_output "string length of 3000-char var" \
  'x=$(head -c 3000 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "uppercase transform large string" \
  'x=$(head -c 1000 /dev/zero | tr "\0" "a"); echo ${x^^} | wc -c'

compare_output "string replacement large string" \
  'x=$(head -c 1000 /dev/zero | tr "\0" "a"); echo ${x//a/b} | wc -c'

compare_output "concatenation stress" \
  'x=""; for i in $(seq 1 100); do x="${x}abc"; done; echo ${#x}'

# ==========================================
# 12. Parameter expansion stress
# ==========================================
section "12 - Parameter expansion stress"

compare_output "default value expansion chain" \
  'echo ${a:-${b:-${c:-${d:-${e:-deep}}}}}'

compare_output "indirect expansion" \
  'x=hello; ref=x; echo ${!ref}'

compare_output "many positional params" \
  'set -- $(seq 1 50); echo $# $1 ${25} ${50}'

compare_output "shift through many params" \
  'set -- $(seq 1 30); shift 15; echo $1 $#'

compare_output "all positional params" \
  'set -- $(seq 1 20); echo "$@" | wc -w'

# ==========================================
# 13. Pipeline stress
# ==========================================
section "13 - Pipeline stress"

compare_output "10-stage pipeline" \
  'seq 1 100 | sort -n | head -50 | tail -10 | wc -l'

compare_output "pipeline with large data" \
  'seq 1 10000 | wc -l'

compare_output "pipeline with grep chain" \
  'seq 1 1000 | grep 5 | grep -v 50 | wc -l'

# ==========================================
# 14. Brace expansion stress
# ==========================================
section "14 - Brace expansion stress"

compare_output "large sequence" \
  'echo {1..100} | wc -w'

compare_output "nested braces" \
  'echo {a,b}{1,2,3}{x,y} | wc -w'

compare_output "alpha sequence" \
  'echo {a..z} | wc -w'

# ==========================================
# 15. Boundary conditions
# ==========================================
section "15 - Boundary conditions"

compare_output "empty variable operations" \
  'x=""; echo "${#x}" "${x:-default}" "${x:+set}"'

compare_output "single char variable" \
  'x=a; echo ${#x} ${x}'

compare_output "null byte handling" \
  'printf "a\0b" | wc -c'

compare_output "empty command substitution" \
  'x=$(true); echo "[$x]"'

compare_output "whitespace-only variable" \
  'x="   "; echo "${#x}" "$x"'

compare_output "long assignment value" \
  'x=$(head -c 2000 /dev/zero | tr "\0" "z"); echo ${#x}'

compare_output "variable with special chars" \
  'x="hello'\''world\"test"; echo "$x"'

# ==========================================
# 16. Pipeline overflow (formerly 4096 ceiling)
# ==========================================
section "16 - Pipeline overflow (>4096 byte values)"

compare_output "5000-char variable via head" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "10000-char variable via head" \
  'x=$(head -c 10000 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "5000-char in echo" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "b"); echo ${#x}'

compare_output "8000-char variable via python" \
  'x=$(python3 -c "print(\"c\"*8000, end=\"\")"); echo ${#x}'

compare_output "5000-char array assignment via word splitting" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "d"); arr=($x); echo ${#arr[0]}'

compare_output "10000-char array element" \
  'x=$(head -c 10000 /dev/zero | tr "\0" "e"); arr=($x); echo ${#arr[0]}'

compare_output "multiple 5000-char array elements" \
  'a=$(head -c 5000 /dev/zero | tr "\0" "f"); b=$(head -c 5000 /dev/zero | tr "\0" "g"); arr=($a $b); echo ${#arr[0]} ${#arr[1]}'

compare_output "5000-char variable string length" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "h"); echo ${#x}'

compare_output "5000-char variable substring" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "i"); y=${x:1000:2000}; echo ${#y}'

compare_output "command substitution preserves 10000 bytes" \
  'echo $(head -c 10000 /dev/zero | tr "\0" "j") | wc -c'

compare_output "nested command sub with large output" \
  'x=$(echo $(head -c 5000 /dev/zero | tr "\0" "k")); echo ${#x}'

compare_output "export 5000-char variable" \
  'export BIGVAR=$(head -c 5000 /dev/zero | tr "\0" "m"); echo ${#BIGVAR}'

print_summary
