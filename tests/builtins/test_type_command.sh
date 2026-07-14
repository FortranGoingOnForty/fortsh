#!/bin/sh
TEST_PREFIX="[type-command]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. type builtin"
compare_exit "type recognizes builtin" 'type echo >/dev/null 2>&1'
compare_exit "type recognizes external command" 'type ls >/dev/null 2>&1'
compare_exit "type nonexistent command fails" 'type nonexistent_cmd_xyz_999 2>/dev/null'
compare_output "type -t builtin" 'type -t echo'
compare_output "type -t external" 'type -t ls'
compare_output "type -t function" 'f() { :; }; type -t f'
compare_output "type -t alias" 'alias myalias="echo hi" 2>/dev/null; type -t myalias'
compare_output "type -t keyword" 'type -t if'

section "2. command builtin"
compare_exit "command -v finds builtin" 'command -v echo >/dev/null'
compare_exit "command -v finds external" 'command -v ls >/dev/null'
compare_exit "command -v nonexistent fails" 'command -v nonexistent_cmd_xyz_999'
compare_output "command bypasses function" 'echo() { printf "FUNC\n"; }; command echo hello'
compare_exit "command -V describes command" 'command -V echo >/dev/null'

section "3. which"
compare_exit "which finds external command" 'which ls >/dev/null 2>&1'
compare_exit "which nonexistent fails" 'which nonexistent_cmd_xyz_999 2>/dev/null'

section "9. Wave-6: resolution table covers all live builtins (DOC-12)"

compare_both "type : names a builtin"  'type :'
compare_both "command -v :"            'command -v :; echo rc=$?'
for b in config memory perf disown rawtest; do
    out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "command -v $b")
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "$b" ]; then
        pass "command -v $b resolves"
    else
        fail "command -v $b resolves" "$b (rc 0)" "rc=$rc out=$out"
    fi
done

print_summary
