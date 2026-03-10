#!/bin/sh
TEST_PREFIX="[let]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. let arithmetic"
compare_output "let addition" 'let "x=5+3"; echo $x'
compare_output "let subtraction" 'let "x=10-3"; echo $x'
compare_output "let multiplication" 'let "x=4*3"; echo $x'
compare_output "let division" 'let "x=20/4"; echo $x'
compare_output "let modulo" 'let "x=17%5"; echo $x'

section "2. let compound assignment"
compare_output "let increment" 'x=10; let "x++"; echo $x'
compare_output "let decrement" 'x=10; let "x--"; echo $x'
compare_output "let multiply assign" 'x=4; let "x*=3"; echo $x'
compare_output "let add assign" 'x=10; let "x+=5"; echo $x'
compare_output "let subtract assign" 'x=10; let "x-=3"; echo $x'

section "3. let exit codes"
compare_exit "let nonzero result exits 0" 'let "1+1"'
compare_exit "let zero result exits 1" 'let "0"'
compare_exit "let comparison true" 'let "5 > 3"'
compare_exit "let comparison false" 'let "3 > 5"'

section "4. let multiple expressions"
compare_output "let multiple args" 'let "x=5" "y=10" "z=x+y"; echo $z'
compare_output "let with variables" 'a=3; b=4; let "c=a*b"; echo $c'

print_summary
