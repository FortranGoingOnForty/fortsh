#!/bin/sh
TEST_PREFIX="[coproc]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. coproc basic launch"
compare_output "coproc sets COPROC_PID" 'coproc sleep 60; test -n "$COPROC_PID" && echo yes; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'
compare_output "coproc fd array exists" 'coproc sleep 60; test -n "${COPROC[0]}" && test -n "${COPROC[1]}" && echo yes; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'
compare_exit "coproc PID is valid process" 'coproc sleep 60; kill -0 $COPROC_PID; ret=$?; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null; exit $ret'

section "2. coproc I/O"
compare_output "coproc bidirectional cat" 'coproc cat; echo hello >&${COPROC[1]}; read line <&${COPROC[0]}; echo $line; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'
compare_output "coproc multiple writes and reads" 'coproc cat; echo one >&${COPROC[1]}; echo two >&${COPROC[1]}; read l1 <&${COPROC[0]}; read l2 <&${COPROC[0]}; echo "$l1 $l2"; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null'
compare_output "coproc with tr" 'coproc tr a-z A-Z; echo hello >&${COPROC[1]}; eval "exec ${COPROC[1]}>&-"; read line <&${COPROC[0]}; echo $line; wait 2>/dev/null'

section "3. named coproc"
# bash only supports named coprocs with compound commands; fortsh extends to simple commands
check_output "named coproc I/O" 'coproc MYPROC cat; echo test >&${MYPROC[1]}; read line <&${MYPROC[0]}; echo $line; kill $MYPROC_PID 2>/dev/null; wait 2>/dev/null' "test"
check_output "named coproc PID var" 'coproc MYPROC sleep 60; test -n "$MYPROC_PID" && echo yes; kill $MYPROC_PID 2>/dev/null; wait 2>/dev/null' "yes"

section "4. coproc cleanup"
compare_output "coproc cleanup after kill" 'coproc sleep 60; kill $COPROC_PID 2>/dev/null; wait 2>/dev/null; echo done'
compare_output "coproc wait returns exit" 'coproc true; wait $COPROC_PID; echo $?'

print_summary
