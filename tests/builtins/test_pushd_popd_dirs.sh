#!/bin/sh
TEST_PREFIX="[pushd-popd-dirs]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. pushd basic"
compare_output "pushd changes directory" 'pushd /tmp >/dev/null && pwd'
compare_output "pushd prints stack" 'pushd /tmp 2>/dev/null'
compare_output "pushd to HOME with tilde" 'pushd /tmp >/dev/null; pushd ~ >/dev/null && pwd'
compare_exit "pushd to nonexistent dir fails" 'pushd /nonexistent_xyz_12345 2>/dev/null'
compare_output "pushd swaps top two with no arg" 'pushd /tmp >/dev/null; pushd /var >/dev/null; pushd >/dev/null; pwd'
compare_output "pushd -n suppresses cd" 'cd /tmp; pushd -n /var 2>/dev/null; pwd'

section "2. popd basic"
compare_output "popd returns to previous dir" 'pushd /tmp >/dev/null; pushd /var >/dev/null; popd >/dev/null; pwd'
compare_exit "popd on empty stack fails" 'popd 2>/dev/null'
compare_output "popd -n suppresses cd" 'pushd /tmp >/dev/null; pushd /var >/dev/null; popd -n >/dev/null; pwd'
compare_output "multiple pushd then popd" 'pushd /tmp >/dev/null; pushd /var >/dev/null; pushd / >/dev/null; popd >/dev/null; popd >/dev/null; pwd'

section "3. dirs"
compare_exit "dirs shows current dir" 'dirs'
compare_output "dirs -c clears stack" 'pushd /tmp >/dev/null; dirs -c; dirs'
compare_output "dirs -p one per line" 'pushd /tmp >/dev/null; dirs -p'
compare_output "dirs -v numbered" 'pushd /tmp >/dev/null; dirs -v'
compare_output "dirs after pushd shows stack" 'pushd /tmp >/dev/null; pushd /var >/dev/null; dirs'

section "4. directory stack round-trip"
compare_output "pushd/popd preserves original" 'ORIG=$(pwd); pushd /tmp >/dev/null; pushd /var >/dev/null; popd >/dev/null; popd >/dev/null; test "$(pwd)" = "$ORIG" && echo yes'

print_summary
