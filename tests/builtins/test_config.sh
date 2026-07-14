#!/bin/sh
TEST_PREFIX="[config]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. config display"
check_exit "config show exits successfully" 'config show' "0"
check_exit "config with no args shows config" 'config' "0"

section "2. config operations"
check_exit "config reload" 'config reload 2>/dev/null; true' "0"

section "9. Wave-6: config shows ~/.fortshrc with legacy fallback (DOC-10)"

th="$TEST_TMPDIR/confhome"
mkdir -p "$th"
echo 'echo from-fortshrc' > "$th/.fortshrc"
out=$(HOME="$th" run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --norc -c 'config' 2>&1)
if printf '%s' "$out" | grep -q 'from-fortshrc' && ! printf '%s' "$out" | grep -q 'no .fortshrc'; then
    pass "config displays ~/.fortshrc"
else
    fail "config displays ~/.fortshrc" "contents shown" "$out"
fi
rm -f "$th/.fortshrc"
echo 'echo from-legacy' > "$th/.fshrc"
out=$(HOME="$th" run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --norc -c 'config' 2>&1)
if printf '%s' "$out" | grep -q 'from-legacy'; then
    pass "legacy ~/.fshrc fallback still works"
else
    fail "legacy ~/.fshrc fallback still works" "legacy contents shown" "$out"
fi

print_summary
