#!/bin/sh
# Command/arithmetic substitution inside ${...} operand words (EXPAND-7).
# expand_word_operand knew only $VAR and ${...}; $(...), backticks, and
# $((...)) in a default/assign/alternate word came out as mangled literals.
TEST_PREFIX="[param-operand]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Substitutions in operand words"

compare_both "command subst in :-"        'echo ${u:-$(echo Y)}'
compare_both "backtick in :-"             'echo ${u:-`echo BT`}'
compare_both "arithmetic in :-"           'echo ${u:-$((1+1))}'
compare_both "command subst in :+"        'v=set; echo ${v:+$(echo alt)}'
compare_both "quoted ) inside operand"    'echo ${u:-$(echo "a)b")}'
compare_both "multi-line capture joins"   'echo ${u:-$(echo one; echo two)}'

section "2. Operand not evaluated when branch not taken"

compare_both "set var skips default"      'v=x; echo ${v:-$(echo no)}'

section "3. Mixed operand forms still work"

compare_both "nested brace in operand"    'a=A; echo ${u:-pre${a}post}'
compare_both "plain var in operand"       'a=A; echo ${u:-$a}'
compare_both "adjacent expansions"        'echo $(echo out)${u:-D}'

print_summary
