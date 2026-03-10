#!/bin/sh
TEST_PREFIX="[memory]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. memory commands"
check_exit "memory with no args" 'memory' "0"
check_exit "memory stats" 'memory stats' "0"
check_exit "memory optimize" 'memory optimize' "0"

print_summary
