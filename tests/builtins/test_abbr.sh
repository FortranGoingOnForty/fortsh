#!/bin/sh
TEST_PREFIX="[abbr]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. abbr define"
check_exit "abbr with no args succeeds" 'abbr' "0"
check_exit "abbr define abbreviation" 'abbr gs="git status"' "0"
check_exit "abbr define with spaces in value" 'abbr ll="ls -la --color"' "0"
check_exit "abbr define single char" 'abbr g="git"' "0"
check_exit "abbr define with path" 'abbr vi="/usr/bin/vim"' "0"

section "2. abbr show"
check_output "abbr shows defined abbr" 'abbr gs="git status"; abbr gs' "gs = git status"
check_exit "abbr -s shows all" 'abbr gs="git status"; abbr -s' "0"
check_exit "abbr --show shows all" 'abbr gs="git status"; abbr --show' "0"
check_exit "abbr show nonexistent" 'abbr nonexistent_xyz 2>/dev/null; true' "0"
check_output "abbr shows multiple" 'abbr a1="echo 1"; abbr a2="echo 2"; abbr -s | wc -l | tr -d " "' "2"

section "3. abbr erase"
check_exit "abbr -e removes abbreviation" 'abbr gs="git status"; abbr -e gs' "0"
check_exit "abbr --erase removes abbreviation" 'abbr gs="git status"; abbr --erase gs' "0"
check_exit "abbr -e nonexistent" 'abbr -e nonexistent_xyz 2>/dev/null; true' "0"
check_output "abbr -e then show is gone" 'abbr gs="git status"; abbr -e gs; abbr gs 2>/dev/null; echo $?' "1"

section "4. abbr overwrite and edge cases"
check_exit "abbr overwrite existing" 'abbr gs="git status"; abbr gs="git stash"' "0"
check_output "abbr overwrite changes value" 'abbr gs="git status"; abbr gs="git stash"; abbr gs' "gs = git stash"
check_exit "abbr with quoted value double" 'abbr ll="ls -la"' "0"
check_exit "abbr with quoted value single" "abbr ll='ls -la'" "0"
check_exit "abbr with equals in value" 'abbr myvar="export FOO=bar"' "0"

print_summary
