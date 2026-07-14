#!/bin/sh
# Process substitution must not leak a file descriptor or a zombie per <(…)/>(…)
# (RES-1, RES-2). Before the fix a loop of substitutions grew /proc/$$/fd
# monotonically and left one <defunct> child each. These checks run fortsh
# directly (not against bash) because they assert fortsh's own fd/zombie
# bookkeeping; a Linux /proc is required, so they skip elsewhere.
TEST_PREFIX="[proc-subst-leaks]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

if [ ! -d /proc/self/fd ]; then
    section "0. Environment"
    skip "process substitution leak checks" "no /proc (Linux only)"
    print_summary
    exit 0
fi

# Assert a fortsh -c snippet prints "OK".
expect_ok() {
    name="$1"; snippet="$2"
    out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "$snippet" 2>&1)
    if [ "$out" = "OK" ]; then pass "$name"; else fail "$name" "OK" "$out"; fi
}

section "1. Input <(…) does not leak fds"
# Compare the fd count before and after 30 substitutions in the same shell.
expect_ok "30x <(echo) holds fd count flat" \
    'b=$(ls /proc/$$/fd | wc -l); for i in $(seq 1 30); do cat <(echo x) >/dev/null; done; a=$(ls /proc/$$/fd | wc -l); [ "$a" -le "$b" ] && echo OK || echo "leaked $b->$a"'

section "2. Input <(…) leaves no zombies"
expect_ok "30x <(echo) reaps every child" \
    'for i in $(seq 1 30); do cat <(echo x) >/dev/null; done; z=$(ps --ppid $$ -o stat= 2>/dev/null | grep -c Z); [ "$z" -eq 0 ] && echo OK || echo "$z zombies"'

section "3. Output >(…) does not leak or hang"
expect_ok "10x >(cat) holds fd count flat" \
    'b=$(ls /proc/$$/fd | wc -l); for i in $(seq 1 10); do echo hi > >(cat >/dev/null); done; a=$(ls /proc/$$/fd | wc -l); [ "$a" -le "$b" ] && echo OK || echo "leaked $b->$a"'

section "4. Substitution still delivers data (no regression)"
compare_output "cat <(echo) contents" 'cat <(echo hello world)'
compare_output "diff <(a) <(b)" 'diff <(printf "a\nb\n") <(printf "a\nc\n")'
compare_output "while read < <(cmd)" 'while read l; do echo "got:$l"; done < <(printf "x\ny\n")'

section "4b. while/until loop re-reads a <(…) redirect every run (DISC-1)"
# A while/until node reading from a process substitution used to work only on
# its first execution: the old buffered `read` over-consumed the fd, so an
# enclosing loop or a second such statement saw an empty stream. The byte-level
# read (BUILTIN-1/15) reads exactly one byte at a time and no longer corrupts
# re-reads of the same fd.
compare_output "for-loop re-runs while < <(cmd)" \
    'for i in 1 2 3; do while read x; do echo "$i:$x"; done < <(echo v$i); done'
compare_output "two while < <(cmd) statements" \
    'while read x; do echo "a:$x"; done < <(echo p); while read x; do echo "b:$x"; done < <(echo q)'
compare_output "for-loop re-runs until < <(cmd)" \
    'for i in 1 2; do until ! read x; do echo "$i:$x"; done < <(printf "%s\n" a b); done'
# Controls that always worked (simple command / brace group consumer).
compare_output "for-loop simple cmd < <(cmd)" \
    'for i in 1 2 3; do cat < <(echo v$i); done'
compare_output "for-loop brace group < <(cmd)" \
    'for i in 1 2 3; do { read x; echo "$i:$x"; } < <(echo v$i); done'

section "5. No predictable /tmp FIFO files (SEC-3 dead path removed)"
# The live path uses pipe + /dev/fd; the old predictable /tmp/fortsh_fifo_*
# helpers were deleted. Nothing should ever create such a file.
fifo_dir=$(mktemp -d)
TMPDIR="$fifo_dir" run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c \
    'for i in $(seq 1 10); do cat <(echo x) >/dev/null; done' >/dev/null 2>&1
n=$(find /tmp "$fifo_dir" -maxdepth 1 -name 'fortsh_fifo_*' 2>/dev/null | wc -l)
rm -rf "$fifo_dir"
if [ "$n" -eq 0 ]; then pass "no fortsh_fifo_* temp files created"
else fail "no fortsh_fifo_* temp files created" "0" "$n"; fi

print_summary
