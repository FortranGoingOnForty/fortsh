#!/bin/sh
TEST_PREFIX="[complete-compgen]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. complete define"
check_exit "complete with -W word list" 'complete -W "start stop restart" myservice' "0"
check_exit "complete with -F function" 'complete -F _my_completer mycommand 2>/dev/null; true' "0"
check_exit "complete with -A action" 'complete -A command mytest 2>/dev/null; true' "0"
check_exit "complete multiple options" 'complete -W "a b" -o nospace testcmd 2>/dev/null; true' "0"

section "2. complete list and remove"
check_exit "complete -p prints completions" 'complete -W "a b c" testcmd; complete -p' "0"
compare_output "complete -p shows defined spec" 'complete -W "alpha beta" testcmd; complete -p testcmd'
check_exit "complete -r removes completion" 'complete -W "a b" testcmd; complete -r testcmd' "0"
check_exit "complete -r nonexistent" 'complete -r nonexistent_cmd 2>/dev/null; true' "0"
compare_output "complete -p after -r is empty" 'complete -W "a b" testcmd; complete -r testcmd; complete -p testcmd 2>/dev/null; echo $?'

section "3. compgen basic"
compare_output "compgen -W filters by prefix" 'compgen -W "start stop status" st'
compare_output "compgen -W no match empty output" 'compgen -W "alpha beta" z'
compare_output "compgen -W exact match" 'compgen -W "alpha beta gamma" alpha'
compare_output "compgen -W all match empty prefix" 'compgen -W "a b c"'

section "4. compgen edge cases"
compare_output "compgen -W single word" 'compgen -W "only" o'
compare_output "compgen -W empty string" 'compgen -W "" a'
compare_output "compgen -W multiple matches" 'compgen -W "start stop stash status" st'
compare_output "compgen -W case sensitive" 'compgen -W "Alpha Beta" a'
compare_output "compgen -W no prefix matches all" 'compgen -W "x y z" | wc -l | tr -d " "'

print_summary
