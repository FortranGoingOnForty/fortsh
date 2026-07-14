#!/bin/sh
# Bounds-safety cases for the lexer/parser. Run against a `make debug`
# build (-fcheck=bounds) these abort on any out-of-bounds substring access;
# CI builds debug and runs this suite so a reintroduced OOB re-aborts.
# On a release build they still assert behavior (exit codes, output).
TEST_PREFIX="[lexer-parser-bounds]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Redirect scan reads past end of exact-length token (DISC-2)"

# expand_variables scanned working_token(i+1:i+1) unguarded while looking
# for <( / >( — .and. does not short-circuit, so every redirect whose
# filename filled its buffer aborted under -fcheck=bounds.
compare_both "output redirect" \
    'echo hi >/dev/null && echo ok'
compare_both "input redirect" \
    'cat </dev/null && echo ok'
compare_both "append redirect" \
    'echo hi >>/dev/null && echo ok'
compare_both "process substitution still recognized" \
    'cat < <(echo procsubst)'
compare_both "word ending in bare > is literal in quotes" \
    'echo "a>" "b<"'

print_summary
