#!/bin/sh
TEST_PREFIX="[help]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. help output"
check_exit "help exits successfully" 'help' "0"
check_output "help produces output" 'help | head -1 | grep -q . && echo yes' "yes"

print_summary
