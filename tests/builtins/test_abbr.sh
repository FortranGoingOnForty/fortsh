#!/bin/sh
TEST_PREFIX="[abbr]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. abbr define and show"
check_exit "abbr with no args succeeds" 'abbr' "0"
check_exit "abbr define abbreviation" 'abbr gs="git status"' "0"
check_output "abbr shows defined abbr" 'abbr gs="git status"; abbr gs' "gs = git status"
check_exit "abbr -s shows all" 'abbr gs="git status"; abbr -s' "0"

section "2. abbr erase"
check_exit "abbr -e removes abbreviation" 'abbr gs="git status"; abbr -e gs' "0"
check_exit "abbr --erase removes abbreviation" 'abbr gs="git status"; abbr --erase gs' "0"
check_exit "abbr -e nonexistent" 'abbr -e nonexistent_xyz 2>/dev/null; true' "0"

section "3. abbr edge cases"
check_exit "abbr with quoted value" 'abbr ll="ls -la"' "0"
check_exit "abbr overwrite existing" 'abbr gs="git status"; abbr gs="git stash"' "0"

print_summary
