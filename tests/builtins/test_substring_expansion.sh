#!/bin/sh
# ${var:offset:length} — offset and length are arithmetic expressions
# (EXPAND-5) and a negative length counts back from the end (EXPAND-4).
# Before the fix both were list-directed integer reads: variable names and
# expressions silently became 0, and negative lengths produced empty.
TEST_PREFIX="[substring]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Bounds are arithmetic expressions"

compare_both "variable offset and length"  'v=hello; i=1; n=3; echo ${v:i:n}'
compare_both "expression offset"           'v=hello; echo ${v:1+1:2}'
compare_both "variable offset only"        'v=hello; o=1; echo ${v:o}'
compare_both "expression in length"        'v=hello; n=1; echo ${v:1:n+1}'

section "2. Negative length trims from the end"

compare_both "drop last char"              'v=hello; echo ${v:0:-1}'
compare_both "slice both ends"             'v=0123456789; echo ${v:2:-2}'

section "3. Existing forms unchanged"

compare_both "literal offset:length"       'v=hello; echo ${v:1:3}'
compare_both "offset only"                 'v=hello; echo ${v:2}'
compare_both "negative offset needs space" 'v=hello; echo ${v: -3:2}'
compare_both "length past end clamps"      'v=hello; echo ${v:0:99}'
compare_both "zero length is empty"        'v=hello; echo ${v:0:0}x'
compare_both "default op not substring"    'u=fb; echo ${x:-$u}'

print_summary
