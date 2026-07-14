#!/bin/sh
# Empty-subshell () syntax error format (PARSE-7). The non-interactive
# prefix is deliberately "sh: -c: line 1:" (grammar_parser.f90 prefix
# policy) so these cases assert the message shape, not bash's shell name:
# both lines carry the full prefix including the line number, and the
# second line echoes the offending input.
TEST_PREFIX="[empty-subshell-err]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Error format matches bash's shape"

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c '()' 2>&1)
rc=$?
line1=$(printf '%s\n' "$out" | sed -n 1p)
line2=$(printf '%s\n' "$out" | sed -n 2p)
if [ "$rc" -eq 2 ] && \
   printf '%s' "$line1" | grep -q "line 1: syntax error near unexpected token \`)'" && \
   printf '%s' "$line2" | grep -q "line 1: \`()'"; then
    pass "() prints two fully-prefixed lines and exits 2"
else
    fail "() prints two fully-prefixed lines and exits 2" \
         "line 1: on both lines, rc=2" "rc=$rc out=$out"
fi

compare_exit "exit status matches bash" '()'

section "2. Non-empty subshell still parses"

compare_both "simple subshell" '(echo ok)'
compare_both "subshell exit status" '(exit 3); echo rc=$?'

print_summary
