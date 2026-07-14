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

section "2. Two-byte \$'...' unknown-escape append at the buffer cap (MEM-1)"

# The LEX_DOLLAR_SINGLE unknown-escape default writes two bytes; with only
# a one-byte guard, a 4095-char pad put the second byte one past the 4096
# buffer. Scripts are generated files because the -c buffer itself caps at
# 4096 (PARSE-5). Word must START with $' — mid-word uses the other handler.
for padlen in 4094 4095 4096; do
    pad=$(awk -v n="$padlen" 'BEGIN{while(i++<n)printf "a"}')
    scr="$TEST_TMPDIR/mem1_$padlen.sh"
    printf "printf '%%s' \$'%s\\\\q'\n" "$pad" > "$scr"
    out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$scr" 2>&1)
    rc=$?
    len=$(printf '%s' "$out" | wc -c)
    if [ "$rc" -eq 0 ] && [ "$len" -le 4097 ] && \
       ! printf '%s' "$out" | grep -qi 'runtime error'; then
        pass "standalone \$'...' pad=$padlen survives \\q at the cap"
    else
        fail "standalone \$'...' pad=$padlen survives \\q at the cap" \
             "rc=0, len<=4097, no runtime error" "rc=$rc len=$len"
    fi
done

pad=$(awk 'BEGIN{while(i++<4095)printf "a"}')
scr="$TEST_TMPDIR/mem1_midword.sh"
printf "x=\$'%s\\\\q'\nprintf '%%s' \"\$x\" | wc -c\n" "$pad" > "$scr"
out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$scr" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qi 'runtime error'; then
    pass "mid-word x=\$'...' pad=4095 survives \\q at the cap"
else
    fail "mid-word x=\$'...' pad=4095 survives \\q at the cap" \
         "rc=0, no runtime error" "rc=$rc out=$(printf '%s' "$out" | head -c 60)"
fi

print_summary
