#!/bin/sh
# Brace expansion in for-loop word lists and array literals (DOC-1).
# The for-loop split was gated on len(expanded) > len(source), so {1..3}
# (expands to "1 2 3", 5 chars vs 6) collapsed into one iteration; {1..5}
# happened to pass. Array literals never brace-expanded at all.
TEST_PREFIX="[brace-words]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. For-loop word lists"

compare_both "{1..3} iterates three times (dodged the old gate)" \
    'for i in {1..3}; do echo "i=$i"; done'
compare_both "{1..5} still iterates five times" \
    'for i in {1..5}; do echo -n "$i "; done; echo'
compare_both "comma list with suffix" \
    'for w in {a,b}c; do echo $w; done'
compare_both "reverse range" \
    'for i in {5..1}; do echo -n $i; done; echo'
compare_both "non-expanding brace stays literal" \
    'for w in {abc}; do echo $w; done'
compare_both "plain words unaffected" \
    'for w in a b; do echo $w; done'

section "2. Array literals"

compare_both "range literal yields elements" \
    'arr=({1..10}); echo "${arr[0]} ${arr[9]} n=${#arr[@]}"'
compare_both "brace mixed with plain word" \
    'arr=({1..3} x); echo "n=${#arr[@]} last=${arr[3]}"'
compare_both "quoted brace does not expand" \
    'arr=("{1..3}"); echo "n=${#arr[@]} [${arr[0]}]"'
compare_both "plain array unaffected" \
    'arr=(one two); echo "${arr[1]} n=${#arr[@]}"'

print_summary
