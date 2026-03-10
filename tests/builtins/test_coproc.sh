#!/bin/sh
TEST_PREFIX="[coproc]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. coproc basic"
compare_output "coproc runs command" 'coproc cat; echo hello >&${COPROC[1]}; read line <&${COPROC[0]}; echo $line; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'
compare_output "coproc sets COPROC_PID" 'coproc sleep 60; test -n "$COPROC_PID" && echo yes; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'
compare_output "coproc fd array" 'coproc sleep 60; test -n "${COPROC[0]}" && test -n "${COPROC[1]}" && echo yes; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'

section "2. named coproc"
compare_output "named coproc" 'coproc MYPROC cat; echo test >&${MYPROC[1]}; read line <&${MYPROC[0]}; echo $line; kill $MYPROC_PID 2>/dev/null; wait 2>/dev/null'

print_summary
