#!/bin/sh
# Quote-aware closing-paren scan for $(...) command substitution.
# Before PARSE-2 the unquoted-word paren scan (and the expansion engine's
# matching scan) counted every ')' including ones inside quotes, so
# $(echo "a)b") ended at the quoted paren and the rest of the line was
# re-lexed as word content — y=$(echo "p)q") assigned an empty value.
TEST_PREFIX="[cmdsubst-quotes]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Quoted ) inside unquoted \$()"

compare_both "double-quoted ) survives" \
    'echo $(echo "a)b")'
compare_both "multiple quoted ) survive" \
    'echo $(printf "%s" "1)2)3")'
compare_both "single-quoted ) survives" \
    "echo \$(echo 'a)b')"
compare_both "quoted ( does not open a nesting level" \
    'echo $(echo "unbalanced ( paren")'

section "2. Assignment form (was silent data loss)"

compare_both "assignment captures quoted )" \
    'y=$(echo "p)q"); echo "[$y]"'
compare_both "assignment captures single-quoted )" \
    "y=\$(echo 'p)q'); echo \"[\$y]\""

section "3. \$() inside double quotes agrees with unquoted form"

compare_both "in-dquote substitution keeps quoted )" \
    'echo "$(echo "a)b")"'
compare_both "surrounding text preserved around quoted )" \
    'echo "x$(echo "y)z")w"'

section "4. Word continues after the substitution"

compare_both "text after \$() stays in the same word" \
    'echo pre$(echo "a)b")post'
compare_both "two substitutions in one word" \
    'echo $(echo "a)b")-$(echo "c)d")'

section "5. Unaffected neighbors"

compare_both "plain substitution" \
    'echo $(echo hi)'
compare_both "nested substitution without quotes" \
    'echo $(echo $(echo deep))'
compare_both "arithmetic expansion untouched" \
    'echo $((1+2))'
compare_both "backslash escape inside quoted span" \
    'echo $(echo "a\)b")'

# Known limit (matches the pre-existing in-double-quote path): a nested $( )
# whose own double-quoted content contains ')' — e.g.
#   echo $(echo "nested $(echo "x)y") ok")
# needs recursive re-lexing of the inner substitution's quoting context.
# Both scan paths now share one span-skipper, so they at least agree.

print_summary
