#!/bin/sh
# Bitwise and shift compound assignments in $(( )) (EXPAND-1, EXPAND-2).
# find_rightmost_assignment knew only += -= *= /= %=: &= split at the bare
# = (storing the RHS into "a&"), and <<=/>>= were hard syntax errors.
TEST_PREFIX="[arith-compound]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Bitwise compound assignments compute and write back"

compare_both "&= computes AND"      'a=12; echo $((a&=10)); echo $a'
compare_both "|= computes OR"       'a=12; echo $((a|=1)); echo $a'
compare_both "^= computes XOR"      'a=12; echo $((a^=10)); echo $a'

section "2. Shift compound assignments"

compare_both ">>= shifts right"     'a=8; echo $((a>>=1)); echo $a'
compare_both "<<= shifts left"      'a=8; echo $((a<<=3)); echo $a'
compare_both "shift count from var" 'a=5; b=3; echo $((a<<=b)); echo $a'

section "3. Existing operators unaffected"

compare_both "+= still works"       'a=5; echo $((a+=2)); echo $a'
compare_both "plain = still works"  'a=2; b=4; echo $((a=b)); echo $a'
compare_both "comparisons not eaten" 'echo $((3<=4)) $((4>=4)) $((2==2)) $((2!=3))'
compare_both "plain shifts intact"  'echo $((1<<4)) $((256>>2))'

print_summary
