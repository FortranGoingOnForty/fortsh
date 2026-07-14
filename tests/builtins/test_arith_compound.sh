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

section "3. Nested ternary pairs : with the inner ? (EXPAND-10)"

compare_both "nested in true branch"  'echo $((1?0?2:3:4))'
compare_both "nested picks true-true" 'echo $((1?2?20:21:3))'
compare_both "nested in false branch" 'echo $((0?1:2?3:4))'
compare_both "plain ternary"          'echo $((1?2:3))'

section "4. Existing operators unaffected"

compare_both "+= still works"       'a=5; echo $((a+=2)); echo $a'
compare_both "plain = still works"  'a=2; b=4; echo $((a=b)); echo $a'
compare_both "comparisons not eaten" 'echo $((3<=4)) $((4>=4)) $((2==2)) $((2!=3))'
compare_both "plain shifts intact"  'echo $((1<<4)) $((256>>2))'

section "5. Long expressions are not truncated (QUAL-2)"

sum126=$(awk 'BEGIN{s="1";for(i=2;i<=126;i++)s=s"+1";print s}')
sum300=$(awk 'BEGIN{s="1";for(i=2;i<=300;i++)s=s"+1";print s}')
compare_both "126-term sum (old boundary)" "echo \$(($sum126))"
compare_both "300-term sum"                "echo \$(($sum300))"

section "6. Negative exponent errors like bash (EXPAND-13)"

compare_exit "2**-1 exits nonzero"  'echo $((2**-1))'
out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c 'echo $((2**-1))' 2>&1)
if printf '%s' "$out" | grep -q 'exponent less than 0'; then
    pass "diagnostic names the negative exponent"
else
    fail "diagnostic names the negative exponent" "exponent less than 0" "$out"
fi
compare_both "positive exponents fine" 'echo $((2**10)) $((3**4)) $((2**0))'

print_summary
