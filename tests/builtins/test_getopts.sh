#!/bin/sh
TEST_PREFIX="[getopts]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. getopts basic"
compare_output "getopts basic option parsing" 'f() { while getopts "ab:c" opt; do echo "$opt"; done; }; f -a -c'
compare_output "getopts with option argument" 'f() { while getopts "a:b" opt; do echo "$opt=$OPTARG"; done; }; f -a value'
compare_output "getopts OPTIND tracks position" 'f() { OPTIND=1; while getopts "ab" opt; do :; done; echo $OPTIND; }; f -a -b'

section "2. getopts advanced"
compare_output "getopts combined flags" 'f() { while getopts "abc" opt; do echo "$opt"; done; }; f -abc'
compare_output "getopts unknown option" 'f() { while getopts "ab" opt 2>/dev/null; do echo "$opt"; done; }; f -c'
compare_output "getopts with remaining args" 'f() { OPTIND=1; while getopts "a" opt; do echo "$opt"; done; shift $((OPTIND-1)); echo "$1"; }; f -a hello'
compare_output "getopts OPTARG for colon option" 'f() { while getopts "a:" opt; do echo "$OPTARG"; done; }; f -a myval'

print_summary
