#!/bin/sh
# Case-modification expansion (EXPAND-3): pattern arguments (${v^^[hl]})
# and ~/~~ toggles. The old dispatch keyed on the LAST character being
# ^ or , so pattern forms ending in ] fell through to empty, and ~ had
# no handler at all.
TEST_PREFIX="[case-mod]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Pattern arguments"

compare_both "^^ with char class"       'v=hello; echo "[${v^^[hl]}]"'
compare_both ",, with char class"       'v=HELLO; echo "[${v,,[HL]}]"'
compare_both "^ first char no match"    'v=hello; echo ${v^[xl]}'
compare_both "^ first char match"       'v=hello; echo ${v^[xh]}'

section "2. Toggle operators"

compare_both "~~ toggles all"           'v=hello; echo "[${v~~}]"'
compare_both "~~ mixed case"            'v=HeLLo; echo "[${v~~}]"'
compare_both "~ toggles first"          'v=Hello; echo "[${v~}]"'

section "3. Plain forms unchanged"

compare_both "^^ all"                   'v=hello; echo ${v^^}'
compare_both "^ first"                  'v=hello; echo ${v^}'
compare_both ",, all"                   'v=HELLO; echo ${v,,}'
compare_both ", first"                  'v=HELLO; echo ${v,}'

section "4. Operators in operands or replacements untouched"

compare_both "comma in default operand" 'echo ${u:-b,c}'
compare_both "comma as replacement"     'v=a.b; echo ${v/./,}'
compare_both "caret in operand"         'echo ${u:-a^b}'

print_summary
