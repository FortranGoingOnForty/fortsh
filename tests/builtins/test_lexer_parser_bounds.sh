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
# A pad at the cap either fits (rc 0) or is rejected with the MEM-5/PARSE-5
# "word too long" diagnostic (rc 2). Either way it must not crash — under
# -fcheck=bounds the original bug aborts with a Fortran runtime error.
for padlen in 4093 4094 4095 4096; do
    pad=$(awk -v n="$padlen" 'BEGIN{while(i++<n)printf "a"}')
    scr="$TEST_TMPDIR/mem1_$padlen.sh"
    printf "printf '%%s' \$'%s\\\\q'\n" "$pad" > "$scr"
    out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$scr" 2>&1)
    rc=$?
    if printf '%s' "$out" | grep -qi 'runtime error'; then
        fail "standalone \$'...' pad=$padlen at the cap does not crash" \
             "clean rc 0 or word-too-long rc 2" "runtime error: $(printf '%s' "$out" | head -c 80)"
    elif [ "$rc" -eq 0 ] || { [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'word too long'; }; then
        pass "standalone \$'...' pad=$padlen at the cap does not crash"
    else
        fail "standalone \$'...' pad=$padlen at the cap does not crash" \
             "rc 0, or rc 2 + word-too-long" "rc=$rc out=$(printf '%s' "$out" | head -c 60)"
    fi
done

pad=$(awk 'BEGIN{while(i++<4095)printf "a"}')
scr="$TEST_TMPDIR/mem1_midword.sh"
printf "x=\$'%s\\\\q'\nprintf '%%s' \"\$x\" | wc -c\n" "$pad" > "$scr"
out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$scr" 2>&1)
rc=$?
if ! printf '%s' "$out" | grep -qi 'runtime error' && \
   { [ "$rc" -eq 0 ] || { [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'word too long'; }; }; then
    pass "mid-word x=\$'...' pad=4095 at the cap does not crash"
else
    fail "mid-word x=\$'...' pad=4095 at the cap does not crash" \
         "rc 0, or rc 2 + word-too-long" "rc=$rc out=$(printf '%s' "$out" | head -c 60)"
fi

print_summary
