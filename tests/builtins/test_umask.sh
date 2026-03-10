#!/bin/sh
TEST_PREFIX="[umask]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. umask display"
compare_output "umask shows current mask" 'umask'
compare_output "umask -S symbolic form" 'umask -S'

section "2. umask set"
compare_output "umask set 0022 and verify" 'umask 0022; umask'
compare_output "umask set 0077 and symbolic" 'umask 0077; umask -S'
compare_output "umask set then restore" 'OLD=$(umask); umask 0077; umask $OLD; umask'
compare_exit "umask invalid value" 'umask 9999 2>/dev/null'

print_summary
