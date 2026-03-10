#!/bin/sh
TEST_PREFIX="[var-ops]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. default value operators"
compare_output '${var:-default} with unset var' 'unset V; echo ${V:-fallback}'
compare_output '${var:-default} with set var' 'V=real; echo ${V:-fallback}'
compare_output '${var:-default} with empty var' 'V=""; echo ${V:-fallback}'
compare_output '${var-default} with unset (no colon)' 'unset V; echo ${V-fallback}'
compare_output '${var-default} with empty (no colon)' 'V=""; echo "${V-fallback}"'
compare_output '${var:=default} assigns default' 'unset V; echo ${V:=assigned}; echo $V'
compare_output '${var:+alternate} with set var' 'V=yes; echo ${V:+alt}'
compare_output '${var:+alternate} with unset var' 'unset V; echo ${V:+alt}'
compare_output '${var:+alternate} with empty var' 'V=""; echo ${V:+alt}'
compare_exit '${var:?error} with unset var fails' 'unset V; : ${V:?oops} 2>/dev/null'
compare_output '${var:?error} with set var' 'V=ok; echo ${V:?oops}'

section "2. string length"
compare_output '${#var} string length' 'V=hello; echo ${#V}'
compare_output '${#var} empty string' 'V=""; echo ${#V}'
compare_output '${#var} with spaces' 'V="hello world"; echo ${#V}'
compare_output '${#var} unset is zero' 'unset V; echo ${#V}'

section "3. prefix removal"
compare_output '${var#pattern} shortest prefix' 'V="hello.world.txt"; echo ${V#*.}'
compare_output '${var##pattern} longest prefix' 'V="hello.world.txt"; echo ${V##*.}'
compare_output '${var#prefix} literal prefix' 'V="/usr/local/bin"; echo ${V#/usr}'
compare_output '${var##*/} basename equivalent' 'V="/path/to/file.txt"; echo ${V##*/}'

section "4. suffix removal"
compare_output '${var%pattern} shortest suffix' 'V="hello.world.txt"; echo ${V%.*}'
compare_output '${var%%pattern} longest suffix' 'V="hello.world.txt"; echo ${V%%.*}'
compare_output '${var%suffix} literal suffix' 'V="file.tar.gz"; echo ${V%.gz}'
compare_output '${var%%/*} dirname-like' 'V="path/to/file"; echo ${V%%/*}'

section "5. replacement"
compare_output '${var/pattern/repl} first match' 'V="hello world hello"; echo ${V/hello/hi}'
compare_output '${var//pattern/repl} all matches' 'V="aabaa"; echo ${V//a/X}'
compare_output '${var/pattern/} deletion' 'V="hello world"; echo ${V/world/}'
compare_output '${var/#pattern/repl} anchor start' 'V="hello world"; echo ${V/#hello/hi}'
compare_output '${var/%pattern/repl} anchor end' 'V="hello world"; echo ${V/%world/earth}'
compare_output '${var//pattern/} delete all' 'V="a1b2c3"; echo ${V//[0-9]/}'

section "6. case conversion"
compare_output '${var^} capitalize first' 'V="hello"; echo ${V^}'
compare_output '${var^^} uppercase all' 'V="hello"; echo ${V^^}'
compare_output '${var,} lowercase first' 'V="HELLO"; echo ${V,}'
compare_output '${var,,} lowercase all' 'V="HELLO"; echo ${V,,}'
compare_output '${var^^} mixed case' 'V="hElLo"; echo ${V^^}'
compare_output '${var,,} mixed case' 'V="HeLLo"; echo ${V,,}'

section "7. substring"
compare_output '${var:offset:length}' 'V="hello world"; echo ${V:6:5}'
compare_output '${var:offset} to end' 'V="hello world"; echo ${V:6}'
compare_output '${var:0:5} from start' 'V="hello world"; echo ${V:0:5}'
compare_output '${var: -3} negative offset' 'V="hello"; echo ${V: -3}'
compare_output '${var:0:0} empty substring' 'V="hello"; echo "${V:0:0}"'

print_summary
