#!/bin/sh
TEST_PREFIX="[set-shopt]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. set options"
compare_exit "set -e exits on error" 'set -e; false'
compare_output "set -e does not exit on conditional" 'set -e; if false; then echo no; fi; echo ok'
compare_output "set -u errors on unset var" 'set -u; echo ${NONEXISTENT_XYZ_999} 2>&1 || true'
compare_exit "set -u triggers failure for unset" 'set -u; echo $NONEXISTENT_XYZ_999 2>/dev/null'
compare_exit "set -o pipefail catches pipe failure" 'set -o pipefail; false | true'
compare_output "set -o pipefail success" 'set -o pipefail; true | true; echo $?'

section "2. set positional parameters"
compare_output "set -- sets positional params" 'set -- a b c; echo $1 $2 $3'
compare_output "set -- count" 'set -- x y z; echo $#'
compare_output "set -- overwrites previous" 'set -- a b; set -- x y z; echo $1 $#'
compare_output "set -- empty clears params" 'set -- a b c; set --; echo $#'
compare_output "set -- with special chars" 'set -- "hello world" foo; echo "$1"'
compare_output "dollar-at expansion" 'set -- a b c; for x in "$@"; do echo $x; done'
compare_output "dollar-star expansion" 'set -- a b c; echo "$*"'

section "3. dollar-dash options string"
compare_output "dollar-dash shows options" 'set -u; case $- in *u*) echo yes;; *) echo no;; esac'

section "4. shopt"
check_exit "shopt -s extglob" 'shopt -s extglob 2>/dev/null; echo done' "0"
compare_exit "shopt -q queries option" 'shopt -q login_shell 2>/dev/null; true'
compare_exit "shopt -u unsets option" 'shopt -s extglob 2>/dev/null; shopt -u extglob 2>/dev/null; true'

print_summary
