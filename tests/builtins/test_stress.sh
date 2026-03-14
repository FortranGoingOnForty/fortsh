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

# ==========================================
# 17. Indirect expansion edge cases
# ==========================================
section "17 - Indirect expansion edge cases"

compare_output "indirect to unset variable" \
  'ref=nosuchvar; echo "${!ref}"'

compare_output "indirect with default value" \
  'x=hello; ref=x; echo ${!ref:-fallback}'

compare_output "indirect chain (not recursive)" \
  'a=hello; b=a; echo ${!b}'

compare_output "indirect to empty variable" \
  'x=""; ref=x; echo "[${!ref}]"'

compare_output "indirect to integer variable" \
  'x=42; ref=x; echo ${!ref}'

compare_output "indirect to PATH" \
  'ref=PATH; val=${!ref}; echo "${val:0:1}"'

compare_output "indirect with nounset on valid ref" \
  'set -u; x=hello; ref=x; echo ${!ref}; set +u'

# ==========================================
# 18. Hardcoded limit boundary tests
# ==========================================
section "18 - Hardcoded limit boundaries"

# Case statement patterns (grammar_parser patterns(10) limit)
# NOTE: increasing case limits causes stack frame overflow in nested parsing.
# Keeping limits at patterns(10)/items(20) to avoid stack corruption.
# Issue tracked for future heap-allocation refactor.
compare_output "case with 9 patterns" \
  'x=9; case $x in 1) echo a;; 2) echo b;; 3) echo c;; 4) echo d;; 5) echo e;; 6) echo f;; 7) echo g;; 8) echo h;; 9) echo i;; esac'

compare_output "case with 10 patterns" \
  'x=10; case $x in 1) echo a;; 2) echo b;; 3) echo c;; 4) echo d;; 5) echo e;; 6) echo f;; 7) echo g;; 8) echo h;; 9) echo i;; 10) echo j;; esac'

compare_output "case with 18 items" \
  'x=18; case $x in 1) echo a;; 2) echo b;; 3) echo c;; 4) echo d;; 5) echo e;; 6) echo f;; 7) echo g;; 8) echo h;; 9) echo i;; 10) echo j;; 11) echo k;; 12) echo l;; 13) echo m;; 14) echo n;; 15) echo o;; 16) echo p;; 17) echo q;; 18) echo r;; esac'

# Many function definitions (function_ast_cache(20) limit)
compare_output "25 function definitions" \
  'for i in $(seq 1 25); do eval "f_$i() { echo $i; }"; done; f_1; f_13; f_25'

compare_output "30 function definitions" \
  'for i in $(seq 1 30); do eval "f_$i() { echo $i; }"; done; f_1; f_15; f_30'

# Many prefix assignments (saved_var_names(10) limit)
compare_output "5 prefix assignments" \
  'A=1 B=2 C=3 D=4 E=5 env | grep -c "^[ABCDE]="'

compare_output "12 prefix assignments" \
  'A=1 B=2 C=3 D=4 E=5 F=6 G=7 H=8 I=9 J=10 K=11 L=12 env | grep -c "^[A-L]="'

# Many shell variables (MAX_SHELL_VARS=512)
compare_output "200 variables" \
  'for i in $(seq 1 200); do eval "var_$i=$i"; done; echo $var_1 $var_100 $var_200'

compare_output "400 variables" \
  'i=1; while [ $i -le 400 ]; do eval "var_$i=$i"; i=$((i+1)); done; echo $var_1 $var_200 $var_400'

# Control flow nesting depth (MAX_CONTROL_DEPTH=20)
compare_output "nested if 15 levels" \
  'x=1; if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then if [ $x -eq 1 ]; then echo deep15; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi; fi'

# Long variable names (MAX_VAR_NAME_LEN=256)
compare_output "100-char variable name" \
  'eval "$(printf "a%.0s" $(seq 1 100))=hello"; eval "echo \$$(printf "a%.0s" $(seq 1 100))"'

compare_output "200-char variable name" \
  'eval "$(printf "a%.0s" $(seq 1 200))=world"; eval "echo \$$(printf "a%.0s" $(seq 1 200))"'

# ==========================================
# 19. Recursion & stack pressure
# ==========================================
section "19 - Recursion and stack pressure"

compare_output "recursive function 75 levels" \
  'f() { if [ $1 -le 0 ]; then echo $1; return; fi; f $(($1 - 1)); }; f 75'

compare_output "recursive function 100 levels" \
  'f() { if [ $1 -le 0 ]; then echo $1; return; fi; f $(($1 - 1)); }; f 100'

compare_output "mutual recursion 20 levels" \
  'a() { if [ $1 -le 0 ]; then echo done; return; fi; b $(($1-1)); }; b() { a "$1"; }; a 20'

compare_output "nested subshells 10 levels" \
  '(echo 1; (echo 2; (echo 3; (echo 4; (echo 5; (echo 6; (echo 7; (echo 8; (echo 9; (echo 10))))))))))'

compare_output "nested command substitution 10 levels" \
  'echo $(echo $(echo $(echo $(echo $(echo $(echo $(echo $(echo $(echo hello)))))))))'

compare_output "nested arithmetic 20 levels" \
  'echo $(( ((((((((((((((((((((1+1)))))))))))))))))))) ))'

# ==========================================
# 20. Memory & buffer boundary tests
# ==========================================
section "20 - Buffer boundaries"

# Command substitution at exact power-of-2 boundaries
compare_output "cmd sub exactly 4096 bytes" \
  'x=$(head -c 4096 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "cmd sub exactly 4097 bytes" \
  'x=$(head -c 4097 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "cmd sub exactly 8192 bytes" \
  'x=$(head -c 8192 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "cmd sub exactly 8193 bytes" \
  'x=$(head -c 8193 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "cmd sub exactly 16384 bytes" \
  'x=$(head -c 16384 /dev/zero | tr "\0" "a"); echo ${#x}'

compare_output "cmd sub exactly 65536 bytes" \
  'x=$(head -c 65536 /dev/zero | tr "\0" "a"); echo ${#x}'

# Pattern matching on large strings
compare_output "pattern removal on 5000-char string" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "a"); y=${x#aaa}; echo ${#y}'

compare_output "pattern replace on 5000-char string" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "a"); echo ${x//a/b} | wc -c'

# Sparse array
compare_output "sparse array index 10000" \
  'arr[10000]=hello; echo ${arr[10000]}'

compare_output "sparse array index 99999" \
  'arr[99999]=world; echo ${arr[99999]}'

# Arithmetic integer boundaries
compare_output "arithmetic max int" \
  'echo $((9223372036854775807))'

compare_output "arithmetic large multiplication" \
  'echo $((1000000 * 1000000))'

compare_output "arithmetic negative" \
  'echo $((-2147483648))'

# Substring at boundary offsets
compare_output "substring negative offset" \
  'x=hello_world; echo ${x: -5}'

compare_output "substring offset beyond length" \
  'x=hi; echo "[${x:100:5}]"'

compare_output "substring zero length" \
  'x=hello; echo "[${x:2:0}]"'

# ==========================================
# 21. Tokenization limits
# ==========================================
section "21 - Tokenization limits"

compare_output "echo with 200 arguments" \
  'echo $(seq 1 200) | wc -w'

compare_output "echo with 400 arguments" \
  'echo $(seq 1 400) | wc -w'

compare_output "many semicolons 30 commands" \
  'a=0; a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); a=$((a+1)); echo $a'

# ==========================================
# 22. FD & redirection stress
# ==========================================
section "22 - FD and redirection stress"

compare_output "rapid redirect cycling 100 iterations" \
  'i=1; while [ $i -le 100 ]; do echo $i > /tmp/fortsh_test_fd_$$; i=$((i+1)); done; cat /tmp/fortsh_test_fd_$$; rm -f /tmp/fortsh_test_fd_$$'

compare_output "append redirect 200 lines" \
  'rm -f /tmp/fortsh_test_append_$$; i=1; while [ $i -le 200 ]; do echo $i >> /tmp/fortsh_test_append_$$; i=$((i+1)); done; wc -l < /tmp/fortsh_test_append_$$; rm -f /tmp/fortsh_test_append_$$'

compare_output "stderr redirect in loop" \
  'for i in 1 2 3 4 5; do echo "err$i" >&2; done 2>&1 | wc -l'

compare_output "output and error merge" \
  '{ echo stdout; echo stderr >&2; } 2>&1 | sort'

compare_output "dev null redirect in loop" \
  'i=1; while [ $i -le 100 ]; do echo $i > /dev/null; i=$((i+1)); done; echo done'

# ==========================================
# 23. Pipeline & fork stress
# ==========================================
section "23 - Pipeline and fork stress"

compare_output "15-stage pipeline" \
  'echo hello | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat'

compare_output "20-stage pipeline" \
  'echo hello | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat | cat'

compare_output "pipeline with 100000 lines" \
  'seq 1 100000 | wc -l'

compare_output "pipeline with sort 10000 lines" \
  'seq 1 10000 | sort -rn | head -1'

compare_output "background job wait cycling" \
  'i=1; while [ $i -le 50 ]; do true & i=$((i+1)); done; wait; echo done'

compare_output "100 background jobs then wait" \
  'i=1; while [ $i -le 100 ]; do true & i=$((i+1)); done; wait; echo done'

compare_output "subshell pipeline isolation" \
  'x=outer; echo $x | (read y; echo $y) | cat'

# ==========================================
# 24. Array scaling
# ==========================================
section "24 - Array scaling"

# BUG: arr[$i]=$i doesn't expand $i in subscript — use eval workaround
compare_output "indexed array 100 elements" \
  'i=0; while [ $i -lt 100 ]; do eval "arr[$i]=$i"; i=$((i+1)); done; echo ${#arr[@]} ${arr[0]} ${arr[50]} ${arr[99]}'

compare_output "indexed array 500 elements" \
  'i=0; while [ $i -lt 500 ]; do eval "arr[$i]=$i"; i=$((i+1)); done; echo ${#arr[@]} ${arr[0]} ${arr[250]} ${arr[499]}'

# BUG: arr=($(cmd)) doesn't word-split command substitution into elements
compare_output "indexed array via init list 20" \
  'arr=(a b c d e f g h i j k l m n o p q r s t); echo ${#arr[@]} ${arr[0]} ${arr[19]}'

compare_output "array append 500 times" \
  'arr=(); i=0; while [ $i -lt 500 ]; do arr+=("$i"); i=$((i+1)); done; echo ${#arr[@]}'

# BUG: m["key$i"] doesn't expand $i in subscript — use eval workaround
compare_output "assoc array 100 keys" \
  'declare -A m; i=1; while [ $i -le 100 ]; do eval "m[key$i]=$i"; i=$((i+1)); done; echo ${#m[@]} ${m[key1]} ${m[key50]} ${m[key100]}'

compare_output "assoc array 200 keys" \
  'declare -A m; i=1; while [ $i -le 200 ]; do eval "m[key$i]=$i"; i=$((i+1)); done; echo ${#m[@]}'

compare_output "assoc array overwrite cycle" \
  'declare -A m; i=1; while [ $i -le 100 ]; do m[k]=$i; i=$((i+1)); done; echo ${m[k]}'

compare_output "array element 10000-char value" \
  'x=$(head -c 10000 /dev/zero | tr "\0" "a"); arr[0]=$x; echo ${#arr[0]}'

# ==========================================
# 25. Control flow edge cases
# ==========================================
section "25 - Control flow edge cases"

compare_output "mixed loop nesting for-while-until" \
  'for i in 1 2; do j=0; while [ $j -lt 2 ]; do k=5; until [ $k -le 3 ]; do k=$((k-1)); done; echo "$i $j $k"; j=$((j+1)); done; done'

compare_output "break 2 from inner loop" \
  'for i in 1 2 3; do for j in a b c; do if [ "$j" = "b" ]; then break 2; fi; echo "$i$j"; done; done; echo end'

compare_output "break 3 from triple nested" \
  'for i in 1 2; do for j in a b; do for k in x y; do if [ "$k" = "y" ]; then break 3; fi; echo "$i$j$k"; done; done; done; echo end'

compare_output "continue 2 from inner loop" \
  'for i in 1 2 3; do for j in a b c; do if [ "$j" = "b" ]; then continue 2; fi; echo "$i$j"; done; done'

compare_output "loop 5000 iterations" \
  'x=0; i=0; while [ $i -lt 5000 ]; do x=$((x+1)); i=$((i+1)); done; echo $x'

# 10000 iterations takes ~45s in fortsh — increase timeout
TEST_TIMEOUT=60
compare_output "loop 10000 iterations" \
  'x=0; i=0; while [ $i -lt 10000 ]; do x=$((x+1)); i=$((i+1)); done; echo $x'
TEST_TIMEOUT=30

compare_output "while with complex condition" \
  'i=0; while [ $i -lt 10 ] && [ $((i % 2)) -eq 0 -o $i -lt 5 ]; do echo $i; i=$((i+1)); done'

compare_output "nested case in loop" \
  'for i in $(seq 1 20); do case $((i % 4)) in 0) echo "a$i";; 1) echo "b$i";; 2) echo "c$i";; 3) echo "d$i";; esac; done | wc -l'

# ==========================================
# 26. Trap & signal stress
# ==========================================
section "26 - Trap and signal stress"

compare_output "set traps on 10 signals" \
  'trap "echo 1" HUP; trap "echo 2" INT; trap "echo 3" QUIT; trap "echo 4" TERM; trap "echo 5" USR1; trap "echo 6" USR2; trap "echo 7" PIPE; trap "echo 8" ALRM; trap "echo 9" CONT; trap "echo exit" EXIT; trap -p | wc -l'

compare_output "trap reset cycling 50 times" \
  'i=1; while [ $i -le 50 ]; do trap "echo $i" EXIT; i=$((i+1)); done; trap -p EXIT'

compare_output "trap with long handler" \
  'handler=""; i=1; while [ $i -le 100 ]; do handler="${handler}echo $i;"; i=$((i+1)); done; trap "$handler" EXIT; echo before'

compare_output "modify trap inside trap" \
  'trap '\''trap "echo inner" EXIT; echo outer'\'' EXIT; exit 0'

compare_output "trap unset then reset" \
  'trap "echo first" EXIT; trap - EXIT; trap "echo second" EXIT; exit 0'

# ==========================================
# 27. String & expansion stress
# ==========================================
section "27 - String and expansion stress"

compare_output "uppercase 5000-char variable" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "a"); echo ${x^^} | wc -c'

compare_output "lowercase 5000-char variable" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "A"); echo ${x,,} | wc -c'

compare_output "global replace 5000-char variable" \
  'x=$(head -c 5000 /dev/zero | tr "\0" "a"); echo ${x//a/b} | wc -c'

compare_output "concatenation loop 5000 chars" \
  'x=""; for i in $(seq 1 1000); do x="${x}abcde"; done; echo ${#x}'

compare_output "prefix removal on 10000-char string" \
  'x=$(head -c 10000 /dev/zero | tr "\0" "a"); y=${x#aaaa}; echo ${#y}'

compare_output "suffix removal on 10000-char string" \
  'x=$(head -c 10000 /dev/zero | tr "\0" "a"); y=${x%aaaa}; echo ${#y}'

compare_output "default expansion chain 8 deep" \
  'echo ${a:-${b:-${c:-${d:-${e:-${f:-${g:-${h:-deep8}}}}}}}}'

compare_output "assign-default expansion" \
  'unset x; echo ${x:=hello}; echo $x'

compare_output "error-if-unset expansion" \
  'x=set; echo ${x:?should not error}'

# ==========================================
# 28. Heredoc scaling
# ==========================================
section "28 - Heredoc scaling"

compare_output "heredoc 50 lines" \
  "seq 1 50 | while read line; do echo \"\$line\"; done | cat <<EOF
$(seq 1 50)
EOF
wc -l"

compare_output "heredoc with 20 variable expansions" \
  'a=1; b=2; c=3; d=4; e=5; f=6; g=7; h=8; i=9; j=10; cat <<EOF
$a $b $c $d $e $f $g $h $i $j $a $b $c $d $e $f $g $h $i $j
EOF'

compare_output "heredoc with command substitution" \
  'cat <<EOF
$(echo hello) $(echo world) $(echo from) $(echo heredoc)
EOF'

compare_output "heredoc quoted delimiter no expansion" \
  'x=should_not_expand; cat <<'\''EOF'\''
$x $(echo nope)
EOF'

compare_output "multiple heredocs sequential" \
  'cat <<A; cat <<B; cat <<C
line_a
A
line_b
B
line_c
C'

# ==========================================
# 29. Glob expansion stress
# ==========================================
section "29 - Glob expansion"

compare_output "glob with many matches" \
  'mkdir -p /tmp/fortsh_glob_$$; i=1; while [ $i -le 200 ]; do touch /tmp/fortsh_glob_$$/f$i.txt; i=$((i+1)); done; ls /tmp/fortsh_glob_$$/*.txt | wc -l; rm -rf /tmp/fortsh_glob_$$'

# Use check_output for glob no-match since $$ differs between bash and fortsh
check_output "glob with no matches nullglob off" \
  'echo /tmp/no_such_dir_xyz/*.abc' \
  '/tmp/no_such_dir_xyz/*.abc'

compare_output "glob bracket expression" \
  'mkdir -p /tmp/fortsh_glob2_$$; touch /tmp/fortsh_glob2_$$/a1 /tmp/fortsh_glob2_$$/b2 /tmp/fortsh_glob2_$$/c3; ls /tmp/fortsh_glob2_$$/[abc][0-9] | wc -l; rm -rf /tmp/fortsh_glob2_$$'

compare_output "glob question mark" \
  'mkdir -p /tmp/fortsh_glob3_$$; touch /tmp/fortsh_glob3_$$/ax /tmp/fortsh_glob3_$$/bx /tmp/fortsh_glob3_$$/cx; echo /tmp/fortsh_glob3_$$/?x | wc -w; rm -rf /tmp/fortsh_glob3_$$'

# ==========================================
# 30. Eval & dynamic execution stress
# ==========================================
section "30 - Eval and dynamic execution"

compare_output "eval with nested quoting" \
  'x="echo hello"; eval "$x"'

compare_output "eval defining 50 variables" \
  'for i in $(seq 1 50); do eval "v$i=$((i*2))"; done; echo $v1 $v25 $v50'

compare_output "eval redefining function 20 times" \
  'for i in $(seq 1 20); do eval "f() { echo $i; }"; done; f'

compare_output "eval with command substitution" \
  'x="echo \$(echo nested)"; eval "$x"'

compare_output "eval chain 5 deep" \
  'eval "eval \"eval \\\"eval \\\\\\\"echo deep\\\\\\\"\\\"\""'

# ==========================================
# 31. Rapid set/unset & variable churn
# ==========================================
section "31 - Variable churn"

compare_output "set/unset 500 cycle" \
  'i=0; while [ $i -lt 500 ]; do x=$i; unset x; i=$((i+1)); done; echo ${x:-done}'

compare_output "rapid export/unexport" \
  'i=0; while [ $i -lt 100 ]; do export v=$i; unset v; i=$((i+1)); done; echo ${v:-done}'

compare_output "overwrite same variable 1000 times" \
  'i=0; while [ $i -lt 1000 ]; do x=$i; i=$((i+1)); done; echo $x'

compare_output "local variable scoping 10 deep" \
  'f() { local x=$1; if [ $1 -le 0 ]; then echo $x; return; fi; f $(($1-1)); echo $x; }; f 10 | head -1'

compare_output "local var does not leak" \
  'f() { local inner=secret; }; f; echo "${inner:-not_leaked}"'

# ==========================================
# 32. Quoting & escaping edge cases
# ==========================================
section "32 - Quoting edge cases"

compare_output "single quotes preserve specials" \
  'echo '\''$HOME $(echo no) `echo no`'\'''

compare_output "double quotes allow expansion" \
  'x=works; echo "it $x"'

compare_output "mixed quote concatenation" \
  "echo 'hello'\"world\"'more'"

compare_output "backslash in double quotes" \
  'echo "a\\b" "c\"d" "e\$f"'

# dollar-single-quote ($'...') ANSI-C quoting
compare_output "dollar-single-quote escapes" \
  "echo \$'hello\\tworld'"

compare_output "empty string arguments preserved" \
  'f() { echo $#; }; f "" "" ""'

compare_output "IFS splitting edge case" \
  'IFS=:; x="a:b::d"; for w in $x; do echo "[$w]"; done'

# ==========================================
# 33. Process substitution & subshell stress
# ==========================================
section "33 - Subshell isolation"

compare_output "subshell variable isolation" \
  'x=outer; (x=inner; echo $x); echo $x'

compare_output "subshell exit code" \
  '(exit 42); echo $?'

compare_output "nested subshell variable" \
  'x=1; (x=2; (x=3; echo $x); echo $x); echo $x'

compare_output "subshell with loop" \
  '(for i in 1 2 3; do echo $i; done) | wc -l'

compare_output "subshell does not affect parent vars" \
  'x=before; (x=after; export x); echo $x'

# ==========================================
# 34. Compound command stress
# ==========================================
section "34 - Compound commands"

compare_output "brace group with many commands" \
  '{ echo a; echo b; echo c; echo d; echo e; echo f; echo g; echo h; echo i; echo j; } | wc -l'

compare_output "brace group pipeline" \
  '{ echo hello; echo world; } | sort'

compare_output "brace group with redirect" \
  '{ echo line1; echo line2; echo line3; } > /tmp/fortsh_brace_$$; wc -l < /tmp/fortsh_brace_$$; rm -f /tmp/fortsh_brace_$$'

compare_output "nested brace groups" \
  '{ { { echo deep; }; }; }'

compare_output "command list with mixed operators" \
  'true && echo a; false || echo b; true && false || echo c'

compare_output "long AND chain" \
  'true && true && true && true && true && true && true && true && true && true && echo all_true'

compare_output "long OR chain" \
  'false || false || false || false || false || false || false || false || false || false || echo found'

compare_output "mixed AND/OR chain" \
  'true && false || true && echo result'

print_summary
