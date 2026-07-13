#!/bin/sh
# Invocation option handling (DOC-5): unknown options are rejected with exit 2,
# --norc is accepted, and options may precede -c. These call $FORTSH_BIN with
# raw argv rather than through the compare_* helpers, which all wrap -c.
TEST_PREFIX="[cli-options]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. Unknown options are errors"

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --badopt -c 'echo hi' </dev/null 2>&1); rc=$?
if [ "$rc" = "2" ]; then pass "--badopt exits 2"; else fail "--badopt exits 2" "exit 2" "exit $rc"; fi
case "$out" in
    *"invalid option"*) pass "--badopt prints invalid-option diagnostic" ;;
    *) fail "--badopt prints invalid-option diagnostic" "invalid option" "$out" ;;
esac
case "$out" in
    *hi*) fail "--badopt does not run the -c command" "no output" "$out" ;;
    *) pass "--badopt does not run the -c command" ;;
esac

"$BASH_REF" --badopt -c 'echo hi' >/dev/null 2>&1
if [ "$?" = "2" ]; then pass "bash agrees: unknown option exits 2"; else skip "bash agrees: unknown option exits 2" "reference bash differs"; fi

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c </dev/null 2>&1); rc=$?
if [ "$rc" = "2" ]; then pass "-c without argument exits 2"; else fail "-c without argument exits 2" "exit 2" "exit $rc"; fi
case "$out" in
    *"option requires an argument"*) pass "-c without argument prints diagnostic" ;;
    *) fail "-c without argument prints diagnostic" "option requires an argument" "$out" ;;
esac

section "2. --norc"

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --norc -c 'echo hi' </dev/null 2>&1); rc=$?
if [ "$out" = "hi" ] && [ "$rc" = "0" ]; then pass "--norc -c 'echo hi' prints hi, exit 0"
else fail "--norc -c 'echo hi' prints hi, exit 0" "out='hi' exit=0" "out='$out' exit=$rc"; fi

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --help </dev/null 2>&1)
case "$out" in
    *--norc*) pass "--help documents --norc" ;;
    *) fail "--help documents --norc" "--norc in help text" "$out" ;;
esac

section "3. Options before -c keep positional parameters"

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --norc -c 'echo $0 $1 $2' zero one two </dev/null 2>&1)
if [ "$out" = "zero one two" ]; then pass "--norc -c cmd arg0 arg1 arg2 sets \$0 \$1 \$2"
else fail "--norc -c cmd arg0 arg1 arg2 sets \$0 \$1 \$2" "zero one two" "$out"; fi

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c 'echo $0 $1 $2' zero one two </dev/null 2>&1)
expected=$("$BASH_REF" -c 'echo $0 $1 $2' zero one two 2>&1)
if [ "$out" = "$expected" ]; then pass "-c positional params match bash"
else fail "-c positional params match bash" "$expected" "$out"; fi

section "4. Script invocation still works"

printf 'echo from_script\n' > "$TEST_TMPDIR/cli_script.sh"
out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$TEST_TMPDIR/cli_script.sh" </dev/null 2>&1); rc=$?
if [ "$out" = "from_script" ] && [ "$rc" = "0" ]; then pass "script file executes"
else fail "script file executes" "out='from_script' exit=0" "out='$out' exit=$rc"; fi

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --norc "$TEST_TMPDIR/cli_script.sh" </dev/null 2>&1); rc=$?
if [ "$out" = "from_script" ] && [ "$rc" = "0" ]; then pass "--norc before script file"
else fail "--norc before script file" "out='from_script' exit=0" "out='$out' exit=$rc"; fi

out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -- "$TEST_TMPDIR/cli_script.sh" </dev/null 2>&1); rc=$?
if [ "$out" = "from_script" ] && [ "$rc" = "0" ]; then pass "-- ends option parsing before script file"
else fail "-- ends option parsing before script file" "out='from_script' exit=0" "out='$out' exit=$rc"; fi

section "5. Version and help exit 0"

run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --version >/dev/null 2>&1
if [ "$?" = "0" ]; then pass "--version exits 0"; else fail "--version exits 0" "exit 0" "exit $?"; fi
run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" --help >/dev/null 2>&1
if [ "$?" = "0" ]; then pass "--help exits 0"; else fail "--help exits 0" "exit 0" "exit $?"; fi

print_summary
