#!/bin/sh
TEST_PREFIX="[complete-compgen]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. complete"
check_exit "complete with -W word list" 'complete -W "start stop restart" myservice' "0"
check_exit "complete -p prints completions" 'complete -W "a b c" testcmd; complete -p' "0"
check_exit "complete -r removes completion" 'complete -W "a b" testcmd; complete -r testcmd' "0"
compare_output "complete -p shows defined spec" 'complete -W "alpha beta" testcmd; complete -p testcmd'

section "2. compgen"
compare_output "compgen -W filters by prefix" 'compgen -W "start stop status" st'
compare_output "compgen -W no match" 'compgen -W "alpha beta" z'
compare_output "compgen -W exact match" 'compgen -W "alpha beta gamma" alpha'
compare_output "compgen -W all match empty prefix" 'compgen -W "a b c"'

print_summary
