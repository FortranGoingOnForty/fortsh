#!/bin/sh
# fc must not leave its mkstemp temp file behind (RES-3). unlink_file was a
# no-op — it reused the newunit= return (a negative unit number) as the iostat,
# so the >= 0 guard was always false and close(status='delete') never ran — so
# every fc edit leaked one fortsh_fc_XXXXXX file in TMPDIR.
TEST_PREFIX="[fc-tempfile]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

# Count fortsh_fc_* files left in a private TMPDIR after running an fc command.
leftover_after() {
    d=$(mktemp -d)
    TMPDIR="$d" run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "$1" >/dev/null 2>&1
    n=$(find "$d" -maxdepth 1 -name 'fortsh_fc_*' 2>/dev/null | wc -l)
    rm -rf "$d"
    echo "$n"
}

section "1. Success path leaves no temp file"
# fc -e true: a no-op editor, so the edited history lines are re-executed and
# the temp file must be cleaned up afterward.
n=$(leftover_after 'echo one; echo two; fc -e true 1 2')
if [ "$n" -eq 0 ]; then pass "fc -e true removes its temp file"
else fail "fc -e true removes its temp file" "0 leftover" "$n leftover"; fi

section "2. Failing editor still cleans up"
# An editor that exits non-zero: fc should still not leak the temp file.
n=$(leftover_after 'echo x; fc -e false 1 1')
if [ "$n" -eq 0 ]; then pass "fc -e false removes its temp file"
else fail "fc -e false removes its temp file" "0 leftover" "$n leftover"; fi

section "3. Repeated fc does not accumulate"
n=$(leftover_after 'echo a; echo b; fc -e true 1 1; fc -e true 2 2; fc -e true 1 2')
if [ "$n" -eq 0 ]; then pass "three fc edits leave nothing behind"
else fail "three fc edits leave nothing behind" "0 leftover" "$n leftover"; fi

print_summary
