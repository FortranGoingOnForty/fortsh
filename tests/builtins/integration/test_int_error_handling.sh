#!/bin/sh
TEST_PREFIX="[int-error-handling]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: error handling with set -e, pipefail, and error propagation

section "1. set -e (errexit) basics"
compare_output "no error continues" 'set -e; true; echo reached'
compare_exit "error exits" 'set -e; false; echo unreachable'
compare_output "OR suppresses errexit" 'set -e; false || true; echo reached'
compare_output "if condition doesnt trigger" 'set -e; if false; then :; fi; echo reached'
compare_output "while condition doesnt trigger" 'set -e; while false; do :; done; echo reached'
compare_output "negation doesnt trigger" 'set -e; ! false; echo reached'
compare_output "AND left fail doesnt exit alone" 'set -e; false && true; echo reached'
compare_output "set +e disables" 'set -e; set +e; false; echo reached'
compare_output "errexit with command sub" 'set -e; echo $(true); echo reached'

section "2. set -e in subshells"
compare_output "subshell error exits subshell" 'set -e; (false) || echo recovered'
compare_exit "errexit in subshell" '(set -e; false; echo unreachable)'
compare_output "errexit subshell status" '(set -e; false; echo unreachable); echo $?'
compare_output "parent errexit child fails" 'set -e; (false) || true; echo reached'

section "3. set -e in functions"
compare_exit "errexit function fails" 'set -e; f() { false; echo unreachable; }; f; echo after'
compare_exit "errexit inside function" 'f() { set -e; false; echo unreachable; }; f'
compare_output "errexit function in conditional" 'set -e; f() { false; }; if f; then echo yes; else echo no; fi; echo after'
compare_output "errexit with return" 'set -e; f() { return 1; }; f || echo caught; echo after'

section "4. pipefail"
compare_output "pipefail first fails" 'set -o pipefail; false | true; echo $?'
compare_output "pipefail middle fails" 'set -o pipefail; true | false | true; echo $?'
compare_output "pipefail all succeed" 'set -o pipefail; true | true; echo $?'
compare_output "pipefail all fail" 'set -o pipefail; false | false; echo $?'
compare_exit "errexit plus pipefail" 'set -eo pipefail; false | true; echo unreachable'
compare_output "pipefail disabled by default" 'false | true; echo $?'
compare_output "pipefail with echo" 'set -o pipefail; echo hello | true; echo $?'

section "5. error propagation"
compare_output "function return status" 'f() { return 1; }; f; echo $?'
compare_output "subshell exit status" '(exit 2); echo $?'
compare_output "eval preserves status" 'eval "false"; echo $?'
compare_output "eval true status" 'eval "true"; echo $?'
compare_output "source preserves status" "echo 'false' > $TEST_TMPDIR/efalse.sh; source $TEST_TMPDIR/efalse.sh; echo \$?"
compare_output "cmd sub status" 'X=$(false); echo $?'
compare_output "cmd sub true status" 'X=$(true); echo $?'
compare_output "last in pipeline" 'true | false; echo $?'
compare_output "negated status" '! true; echo $?'
compare_output "negated false status" '! false; echo $?'

section "6. builtin error handling"
compare_output "cd failure" 'cd /nonexistent_xyz 2>/dev/null; echo $?'
compare_output "source failure" 'source /nonexistent_file.sh 2>/dev/null; echo $?'
compare_exit "readonly violation" 'readonly ERX=1; ERX=2 2>/dev/null'
compare_output "unset readonly" 'readonly ERY=1; unset ERY 2>/dev/null; echo $?'
compare_output "command not found" 'nonexistent_cmd_xyz 2>/dev/null; echo $?'
compare_output "read with no input" 'read VAR < /dev/null; echo $?'
compare_output "test failure" 'test 1 -eq 2; echo $?'
compare_output "false builtin" 'false; echo $?'
compare_output "true builtin" 'true; echo $?'

section "7. set -e with conditionals (should NOT exit)"
compare_output "set -e if false" 'set -e; if false; then echo yes; fi; echo reached'
compare_output "set -e while false" 'set -e; while false; do echo no; done; echo reached'
compare_output "set -e until true" 'set -e; until true; do echo no; done; echo reached'
compare_output "set -e test in if" 'set -e; if test 1 -eq 2; then echo no; fi; echo reached'
compare_output "set -e bracket in if" 'set -e; if [ 1 -eq 2 ]; then echo no; fi; echo reached'
compare_output "set -e negation" 'set -e; ! false; echo reached'

print_summary
