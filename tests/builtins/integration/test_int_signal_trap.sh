#!/bin/sh
TEST_PREFIX="[int-signal-trap]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: traps and signal handling

section "1. EXIT trap"
compare_output "basic EXIT trap" 'trap "echo bye" EXIT; echo main'
compare_output "EXIT with explicit exit" 'trap "echo bye" EXIT; exit 0'
compare_output "function as EXIT handler" 'f() { echo cleaned; }; trap f EXIT; echo main'
compare_output "subshell has own EXIT" 'trap "echo outer" EXIT; (trap "echo inner" EXIT; echo sub)'
compare_output "EXIT trap sees exit status" 'trap "echo status=$?" EXIT; exit 42'
compare_output "EXIT trap on implicit exit" 'trap "echo bye" EXIT; true'
compare_output "EXIT trap with multiple commands" 'trap "echo a; echo b" EXIT; echo main'

section "2. ERR trap"
compare_output "ERR on false" 'trap "echo error" ERR; false; echo after'
compare_output "ERR not in OR chain" 'trap "echo error" ERR; false || true; echo ok'
compare_output "ERR not in if condition" 'trap "echo error" ERR; if false; then echo no; fi; echo ok'
compare_output "ERR not in while condition" 'trap "echo error" ERR; while false; do :; done; echo ok'
compare_output "ERR not with negation" 'trap "echo error" ERR; ! false; echo ok'
compare_output "ERR on command failure" 'trap "echo err" ERR; /nonexistent_xyz 2>/dev/null; echo after'

section "3. RETURN trap"
compare_output "RETURN in function" 'f() { trap "echo returned" RETURN; echo body; }; f'
compare_output "RETURN fires on return" 'f() { trap "echo returned" RETURN; echo body; return 0; }; f'
compare_output "RETURN on source" "echo 'echo sourced' > $TEST_TMPDIR/trap_src.sh; trap 'echo returned' RETURN; source $TEST_TMPDIR/trap_src.sh"
compare_output "RETURN multiple calls" 'f() { trap "echo ret" RETURN; echo body; }; f; f; f'

section "4. signal traps"
compare_output "trap USR1" 'trap "echo caught" USR1; kill -USR1 $$; echo after'
compare_output "ignore signal" 'trap "" TERM; kill -TERM $$ 2>/dev/null; echo survived'
compare_output "trap INT" 'trap "echo interrupted" INT; kill -INT $$; echo after'
compare_output "trap HUP" 'trap "echo hangup" HUP; kill -HUP $$; echo after'

section "5. trap management"
compare_output "overwrite trap" 'trap "echo a" EXIT; trap "echo b" EXIT'
compare_output "clear trap" 'trap "echo a" EXIT; trap - EXIT; echo done'
compare_output "display trap" 'trap "echo hello" EXIT; trap -p EXIT'
compare_output "trap multiple signals" 'trap "echo caught" USR1 USR2; kill -USR1 $$; kill -USR2 $$; echo done'
compare_output "trap -p shows all" 'trap "echo a" USR1; trap "echo b" USR2; trap -p | grep -cE "USR[12]" | tr -d " "'
compare_output "trap list signals" 'trap -l >/dev/null 2>&1; echo $?'

section "6. trap interaction with builtins"
compare_output "trap doesnt change exit status" 'trap "echo bye" EXIT; false; echo $?'
compare_output "trap with eval" 'trap "echo bye" EXIT; eval "echo evaled"'
compare_output "trap in subshell" '(trap "echo sub_bye" EXIT; echo sub)'
compare_output "trap preserved across commands" 'trap "echo bye" EXIT; echo a; echo b; echo c'
compare_output "nested trap scopes" 'trap "echo outer_bye" EXIT; (trap "echo inner_bye" EXIT; echo inner); echo between'

print_summary
