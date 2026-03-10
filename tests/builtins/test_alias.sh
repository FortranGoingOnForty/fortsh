#!/bin/sh
TEST_PREFIX="[alias]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. alias basic"
compare_output "alias define and use via eval" 'shopt -s expand_aliases 2>/dev/null; alias greet="echo hello"; eval greet'
compare_exit "alias lists all without error" 'alias >/dev/null 2>&1'
compare_exit "alias nonexistent fails" 'alias nonexistent_alias_xyz 2>/dev/null'
compare_output "alias with arguments" 'shopt -s expand_aliases 2>/dev/null; alias say="echo"; eval "say hello"'

section "2. unalias"
compare_exit "unalias removes alias" 'alias greet="echo hello"; unalias greet; alias greet 2>/dev/null'
compare_exit "unalias -a removes all" 'alias a1="echo 1"; alias a2="echo 2"; unalias -a; alias a1 2>/dev/null'
compare_exit "unalias nonexistent fails" 'unalias nonexistent_alias_xyz 2>/dev/null'

section "3. alias edge cases"
compare_output "alias with equals in value" 'shopt -s expand_aliases 2>/dev/null; alias myvar="echo x=1"; eval myvar'
compare_output "alias with semicolon" 'shopt -s expand_aliases 2>/dev/null; alias both="echo a; echo b"; eval both'
compare_output "alias preserves original after unalias" 'alias echo="printf ALIAS"; unalias echo; echo hello'

print_summary
