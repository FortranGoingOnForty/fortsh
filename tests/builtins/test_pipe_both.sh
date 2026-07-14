#!/bin/sh
# |& pipes stdout+stderr (bash shorthand for 2>&1 |). Before PARSE-4 the
# lexer split it into | plus a dangling &, which the parser rejected as a
# syntax error.
TEST_PREFIX="[pipe-both]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. |& routes stderr through the pipe"

compare_both "stderr reaches the consumer" \
    'ls /nonexistent-fortsh-test |& wc -l'
compare_both "stdout still flows too" \
    'echo visible |& cat'
compare_both "merged streams stay ordered per stage" \
    '{ echo out; ls /nonexistent-fortsh-test; } |& sort | head -2'

section "2. Chaining and mixing with |"

compare_both "chained |&" \
    'echo a |& cat |& cat'
compare_both "| then |&" \
    'echo x | cat |& cat'
compare_both "|& then |" \
    'ls /nonexistent-fortsh-test |& cat | wc -l'

section "3. Exit status comes from the last stage"

compare_both "last stage failure" \
    'true |& false; echo rc=$?'
compare_both "last stage success" \
    'ls /nonexistent-fortsh-test |& true; echo rc=$?'

section "4. Bare | must not leak stderr into the pipe"

compare_both "stderr bypasses a plain pipe" \
    'ls /nonexistent-fortsh-test 2>/dev/null | wc -l'
compare_both "explicit 2>&1 | equals |&" \
    'ls /nonexistent-fortsh-test 2>&1 | wc -l'

print_summary
