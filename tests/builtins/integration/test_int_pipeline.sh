#!/bin/sh
TEST_PREFIX="[int-pipeline]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtins interacting with pipelines

section "1. builtins as pipeline source"
compare_output "echo into pipeline" 'echo hello world | tr a-z A-Z'
compare_output "printf into pipeline" 'printf "%s\n" a b c | sort -r'
compare_output "echo pipe to wc" 'echo "one two three" | wc -w | tr -d " "'
compare_output "pwd in pipeline" 'pwd | grep -q / && echo yes'
compare_output "type in pipeline" 'type echo | head -1'
compare_output "printf format in pipeline" 'printf "%d\n" 3 1 2 | sort -n'
compare_output "set outputs to pipeline" 'X=hello; set | grep "^X=" | head -1'
compare_output "declare -p in pipeline" 'X=42; declare -p X 2>/dev/null | head -1'
compare_output "export -p in pipeline" 'export EX=val; export -p | grep EX | head -1'
compare_output "alias in pipeline" 'alias myalias="echo test" 2>/dev/null; alias | grep myalias | head -1; unalias myalias 2>/dev/null'

section "2. builtins as pipeline sink"
compare_output "read from pipeline" 'echo hello | read VAR; echo $VAR'
compare_output "read line from pipeline" 'printf "a\nb\nc\n" | while read line; do echo "got:$line"; done'
compare_output "read multiple vars from pipeline" 'echo "one two three" | { read A B C; echo "$A $B $C"; }'
compare_output "read in while from seq" 'seq 3 | while read n; do echo "num:$n"; done'
compare_output "multi-stage to read" 'printf "c\na\nb\n" | sort | while read x; do echo "sorted:$x"; done'
compare_output "read with IFS from pipeline" 'echo "a:b:c" | { IFS=: read A B C; echo "$A $B $C"; }'

section "3. builtins mid-pipeline"
compare_output "builtin mid-pipeline sort head" 'echo -e "b\na\nc" | sort | head -1'
compare_output "echo tr wc chain" 'echo "hello world" | tr a-z A-Z | wc -c | tr -d " "'
compare_output "printf sort tail chain" 'printf "%d\n" 5 1 3 2 4 | sort -n | tail -1'
compare_output "command substitution in pipeline" 'echo $(echo hello) | tr a-z A-Z'

section "4. pipeline exit status"
compare_output "last cmd status true" 'false | true; echo $?'
compare_output "last cmd status false" 'true | false; echo $?'
compare_output "pipefail first fails" 'set -o pipefail; false | true; echo $?'
compare_output "pipefail middle fails" 'set -o pipefail; true | false | true; echo $?'
compare_output "pipefail all succeed" 'set -o pipefail; true | true; echo $?'
compare_output "negated pipeline" '! true; echo $?'
compare_output "negated pipeline false" '! false; echo $?'
compare_output "PIPESTATUS basic" 'true | false | true; echo ${PIPESTATUS[0]} ${PIPESTATUS[1]} ${PIPESTATUS[2]}'
compare_output "PIPESTATUS all zero" 'true | true | true; echo ${PIPESTATUS[@]}'

section "5. pipeline subshell semantics"
compare_output "var set in pipeline doesnt leak" 'X=before; echo y | read X; echo $X'
compare_output "cd in pipeline doesnt affect parent" 'cd /tmp | cat; pwd'
compare_output "export in pipeline segment" 'echo test | { export PVAR=pipe; echo $PVAR; }; echo ${PVAR:-unset}'
compare_output "cmd sub in pipeline" 'echo "$(echo hello)" | tr h H'
compare_output "subshell in pipeline" '(echo from_sub) | tr a-z A-Z'

section "6. pipeline edge cases"
compare_output "empty pipeline source" 'echo -n "" | wc -c | tr -d " "'
compare_output "large data through pipeline" 'printf "%0100s\n" | wc -c | tr -d " "'
compare_output "multiple echo into pipeline" '{ echo a; echo b; echo c; } | sort -r'
compare_output "pipeline with command group" '{ echo 1; echo 2; } | { while read n; do echo "got:$n"; done; }'
compare_output "pipeline preserves whitespace" 'echo "  hello  " | cat'
compare_output "pipeline with exit in subshell" '(echo before; exit 0; echo after) | cat'

print_summary
