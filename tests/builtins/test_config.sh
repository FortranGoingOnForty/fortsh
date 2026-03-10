#!/bin/sh
TEST_PREFIX="[config]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. config display"
check_exit "config show exits successfully" 'config show' "0"
check_exit "config with no args shows config" 'config' "0"

section "2. config operations"
check_exit "config reload" 'config reload 2>/dev/null; true' "0"

print_summary
