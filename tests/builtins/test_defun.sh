#!/bin/sh
TEST_PREFIX="[defun]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

# defun is a fortsh-specific alternate syntax for function definitions

section "1. defun basic"
check_exit "defun defines a function" 'defun greet echo hello; greet' "0"
check_output "defun function runs" 'defun greet echo hello; greet' "hello"
check_exit "defun with no args shows usage" 'defun 2>/dev/null; true' "0"

print_summary
