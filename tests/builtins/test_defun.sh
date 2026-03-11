#!/bin/sh
TEST_PREFIX="[defun]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

# defun is a fortsh-specific alternate syntax for function definitions

section "1. defun basic"
check_exit "defun defines a function" 'defun greet echo hello; greet' "0"
check_output "defun function produces output" 'defun greet echo hello; greet' "hello"
check_exit "defun with no args shows usage" 'defun 2>/dev/null; true' "0"

section "2. defun with arguments"
check_output "defun function receives args" 'defun say echo; say hello world' "hello world"
check_output "defun function uses dollar-1" 'defun greet echo "hi $1"; greet alice' "hi alice"

section "3. defun overwrite and unset"
check_output "defun overwrites existing function" 'defun f echo old; defun f echo new; f' "new"
check_output "unset -f removes defun function" 'defun f echo test; unset -f f; f 2>/dev/null; echo $?' "127"
check_output "type shows defun as function" 'defun myfunc echo hi; type myfunc 2>/dev/null | head -1' "myfunc is a function"

section "4. defun edge cases"
check_output "defun with special chars in body" 'defun f echo "hello world"; f' "hello world"
check_output "defun called multiple times" 'defun f echo ok; f; f; f' "ok
ok
ok"

print_summary
