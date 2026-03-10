#!/bin/sh
TEST_PREFIX="[times]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. times output"
check_exit "times exits successfully" 'times' "0"
check_exit "times produces output" 'times >/dev/null' "0"

print_summary
