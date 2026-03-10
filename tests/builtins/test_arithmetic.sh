#!/bin/sh
TEST_PREFIX="[arithmetic]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. basic arithmetic"
compare_output "addition" 'echo $((3 + 4))'
compare_output "subtraction" 'echo $((10 - 3))'
compare_output "multiplication" 'echo $((6 * 7))'
compare_output "division" 'echo $((20 / 4))'
compare_output "modulo" 'echo $((17 % 5))'
compare_output "negative result" 'echo $((3 - 10))'
compare_output "zero division guard" 'echo $((0 / 1))'

section "2. operator precedence"
compare_output "multiply before add" 'echo $((2 + 3 * 4))'
compare_output "parentheses override" 'echo $(( (2 + 3) * 4 ))'
compare_output "nested parentheses" 'echo $(( (2 + 3) * (4 - 1) ))'
compare_output "complex expression" 'echo $(( 10 / 2 + 3 * 4 - 1 ))'

section "3. comparison and ternary"
compare_output "ternary true" 'echo $((5 > 3 ? 5 : 3))'
compare_output "ternary false" 'echo $((2 > 3 ? 2 : 3))'
compare_output "equality" 'echo $((5 == 5))'
compare_output "inequality" 'echo $((5 != 3))'
compare_output "less than" 'echo $((3 < 5))'
compare_output "greater than" 'echo $((5 > 3))'
compare_output "logical AND" 'echo $((1 && 1))'
compare_output "logical OR" 'echo $((0 || 1))'
compare_output "logical NOT" 'echo $((!0))'

section "4. increment and decrement"
compare_output "post-increment" 'x=5; echo $((x++)); echo $x'
compare_output "pre-increment" 'x=5; echo $((++x)); echo $x'
compare_output "post-decrement" 'x=5; echo $((x--)); echo $x'
compare_output "pre-decrement" 'x=5; echo $((--x)); echo $x'

section "5. bitwise operations"
compare_output "bitwise AND" 'echo $((12 & 10))'
compare_output "bitwise OR" 'echo $((12 | 10))'
compare_output "bitwise XOR" 'echo $((12 ^ 10))'
compare_output "bitwise NOT" 'echo $((~0))'
compare_output "left shift" 'echo $((1 << 4))'
compare_output "right shift" 'echo $((16 >> 2))'

section "6. compound assignment"
compare_output "+= assignment" 'x=10; echo $((x += 5))'
compare_output "-= assignment" 'x=10; echo $((x -= 3))'
compare_output "*= assignment" 'x=4; echo $((x *= 3))'
compare_output "/= assignment" 'x=20; echo $((x /= 4))'
compare_output "%= assignment" 'x=17; echo $((x %= 5))'

section "7. variables in arithmetic"
compare_output "variable reference" 'a=10; b=20; echo $((a + b))'
compare_output "unset var is zero" 'unset V; echo $((V + 5))'
compare_output "assignment in expression" 'echo $((x = 5 + 3)); echo $x'
compare_output "chained assignment" 'echo $((x = y = 5)); echo $x $y'
compare_output "comma operator" 'echo $((x=1, y=2, x+y))'

print_summary
