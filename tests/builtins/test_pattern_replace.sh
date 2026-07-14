#!/bin/sh
# ${var/pat/repl} operand expansion (EXPAND-6): the replace branch passed
# pattern and replacement to pattern_replace verbatim, so $p / $r / $(cmd)
# were matched and inserted literally.
TEST_PREFIX="[pattern-replace]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Variables in pattern and replacement"

compare_both "var pattern, replace-all"   'v=aXbXc; p=X; echo ${v//$p/_}'
compare_both "var replacement"            'v=ab; r=Z; echo ${v/b/$r}'
compare_both "braced var pattern"         'v=aXb; p=X; echo ${v/${p}/_}'
compare_both "braced var replacement"     'v=ab; r=Z; echo ${v/b/${r}}'
compare_both "command subst replacement"  'v=ab; echo ${v/b/$(echo CS)}'

section "2. Literal forms unchanged"

compare_both "single replace"             'v=hello; echo ${v/l/L}'
compare_both "replace all"                'v=hello; echo ${v//l/L}'
compare_both "anchored start"             'v=path; echo ${v/#pa/PA}'
compare_both "anchored end"               'v=path; echo ${v/%th/TH}'
compare_both "delete shortest"            'v=aXb; echo ${v/X}'
compare_both "delete all"                 'v=abcabc; echo ${v//abc/}x'

print_summary
