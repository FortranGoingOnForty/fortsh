#!/bin/sh
TEST_PREFIX="[local]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. local scope"
compare_output "local restricts scope to function" 'f() { local x=inner; echo $x; }; f; echo ">${x}<"'
compare_output "local with initial value" 'f() { local msg=hello; echo $msg; }; f'
compare_output "local does not leak outside" 'f() { local secret=42; }; f; echo ">${secret}<"'
compare_output "local shadows outer variable" 'x=outer; f() { local x=inner; echo $x; }; f; echo $x'
compare_exit "local outside function fails" 'local x=5 2>/dev/null'

section "2. local advanced"
compare_output "local without value" 'f() { local x; echo ">${x}<"; }; f'
compare_output "local multiple vars" 'f() { local a=1 b=2; echo $a $b; }; f'
compare_output "local preserves outer after return" 'x=outer; f() { local x=inner; return; }; f; echo $x'
compare_output "nested function locals" 'g() { local x=inner2; echo $x; }; f() { local x=inner1; g; echo $x; }; f'
compare_output "local in nested calls" 'x=global; f() { local x=f_val; g; echo $x; }; g() { echo $x; }; f; echo $x'

section "3. local with types"
compare_output "local -i integer" 'f() { local -i n=5+3; echo $n; }; f'
compare_output "local -a array" 'f() { local -a arr=(a b c); echo ${arr[@]}; }; f'
compare_output "local -r readonly" 'f() { local -r x=fixed; echo $x; }; f'

print_summary
