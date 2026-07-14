#!/bin/sh
# PARSE-5 / MEM-5: no silent truncation at the lexer/parser capacity limits.
# Token arrays and parser word lists grow past the initial 2000 entries; the
# -c string is read at its full length; a single word over the fixed
# 4096-byte token buffer is a loud syntax error (exit 2), never a silent clip.
TEST_PREFIX="[token-limits]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Token and word counts grow past 2000"

many=$(seq 1 2100 | tr '\n' ' ')
compare_both "2100-token pipeline keeps its final stage" \
    "echo $many | wc -w"
compare_both "3000-word for-loop list is complete" \
    "for i in $(seq 1 3000 | tr '\n' ' '); do :; done; echo \$i"

section "2. -c strings longer than 4096 bytes run in full"

words=$(seq -f 'w%g' 1 900 | tr '\n' ' ')
scr_cmd="echo $words>/dev/null; echo tail-ran"
out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "$scr_cmd" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "tail-ran" ]; then
    pass "-c string of ${#scr_cmd} bytes executes its trailing command"
else
    fail "-c string of ${#scr_cmd} bytes executes its trailing command" \
         "tail-ran (rc 0)" "rc=$rc out=$(printf '%s' "$out" | head -c 60)"
fi

section "3. Per-word 4096 cap: exact fit works, overflow is loud"

w4096=$(awk 'BEGIN{while(i++<4096)printf "C"}')
compare_both "4096-byte word passes byte-for-byte" \
    "echo $w4096 | wc -c"

w4097=$(awk 'BEGIN{while(i++<4097)printf "D"}')
out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "echo $w4097" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'word too long'; then
    pass "4097-byte word is rejected with a diagnostic, exit 2"
else
    fail "4097-byte word is rejected with a diagnostic, exit 2" \
         "rc=2 + word too long" "rc=$rc out=$(printf '%s' "$out" | head -c 60)"
fi

out=$(printf 'echo %s\n' "$w4097" | run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'word too long'; then
    pass "over-long word via stdin is rejected too"
else
    fail "over-long word via stdin is rejected too" \
         "rc=2 + word too long" "rc=$rc out=$(printf '%s' "$out" | head -c 60)"
fi

section "4. Ordinary input is unaffected"

compare_both "small pipeline" 'echo hi | wc -w'
compare_both "small for loop" 'for i in a b c; do echo $i; done'
compare_both "4000-byte word round-trips" \
    "echo $(awk 'BEGIN{while(i++<4000)printf "B"}') | wc -c"

print_summary
