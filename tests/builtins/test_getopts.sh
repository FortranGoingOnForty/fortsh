#!/bin/sh
TEST_PREFIX="[getopts]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. getopts basic"
compare_output "getopts basic option parsing" 'f() { while getopts "ab:c" opt; do echo "$opt"; done; }; f -a -c'
compare_output "getopts with option argument" 'f() { while getopts "a:b" opt; do echo "$opt=$OPTARG"; done; }; f -a value'
compare_output "getopts OPTIND tracks position" 'f() { OPTIND=1; while getopts "ab" opt; do :; done; echo $OPTIND; }; f -a -b'
compare_output "getopts single option" 'f() { while getopts "x" opt; do echo "$opt"; done; }; f -x'
compare_output "getopts no options given" 'f() { getopts "ab" opt; echo $?; }; f'

section "2. getopts combined and multiple"
compare_output "getopts combined flags" 'f() { while getopts "abc" opt; do echo "$opt"; done; }; f -abc'
compare_output "getopts with remaining args" 'f() { OPTIND=1; while getopts "a" opt; do echo "$opt"; done; shift $((OPTIND-1)); echo "$1"; }; f -a hello'
compare_output "getopts OPTARG for colon option" 'f() { while getopts "a:" opt; do echo "$OPTARG"; done; }; f -a myval'
compare_output "getopts multiple options with args" 'f() { while getopts "a:b:c" opt; do echo "$opt=$OPTARG"; done; }; f -a one -b two -c'
compare_output "getopts option arg attached" 'f() { while getopts "n:" opt; do echo "$OPTARG"; done; }; f -n5'

section "3. getopts error handling"
compare_output "getopts unknown option" 'f() { while getopts "ab" opt 2>/dev/null; do echo "$opt"; done; }; f -c'
compare_output "getopts silent mode unknown" 'f() { while getopts ":ab" opt; do echo "$opt"; done; }; f -c'
compare_output "getopts silent mode missing arg" 'f() { while getopts ":a:" opt; do echo "$opt=$OPTARG"; done; }; f -a'
compare_exit "getopts returns 1 when done" 'f() { set -- -a; getopts "a" opt; getopts "a" opt; echo $?; }; f'

section "4. getopts OPTIND reset"
compare_output "getopts OPTIND reset between calls" 'f() { OPTIND=1; while getopts "a" opt; do echo "$opt"; done; }; f -a; f -a'
compare_output "getopts preserves non-option args" 'f() { OPTIND=1; while getopts "v" opt; do echo "$opt"; done; shift $((OPTIND-1)); echo "$@"; }; f -v arg1 arg2'
compare_output "getopts double-dash stops parsing" 'f() { OPTIND=1; while getopts "a" opt; do echo "$opt"; done; shift $((OPTIND-1)); echo "$@"; }; f -a -- -b'

print_summary
