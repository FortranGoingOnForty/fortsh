#!/bin/sh
# =====================================
# POSIX Compliance Extended Test Suite for fortsh
# =====================================
# Comprehensive POSIX compliance testing based on IEEE Std 1003.1-2017
# This extends the basic test suite with additional coverage

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

# Get script directory (POSIX way)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../bin/fortsh}"

# Check if fortsh exists
if [ ! -x "$FORTSH_BIN" ]; then
    printf "${RED}ERROR${NC}: fortsh binary not found at $FORTSH_BIN\n"
    printf "Please run 'make' first or set FORTSH_BIN environment variable\n"
    exit 1
fi

# Test result trackers
pass() {
    printf "${GREEN}✓ PASS${NC}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "${RED}✗ FAIL${NC}: %s\n" "$1"
    if [ -n "$2" ]; then
        printf "  posix:  %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  fortsh: %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    printf "${YELLOW}⊘ SKIP${NC}: %s - %s\n" "$1" "$2"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    printf "\n"
    printf "${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Helper function to run command in both shells and compare
compare_posix_output() {
    test_name="$1"
    command="$2"
    posix_file="/tmp/posix_ext_$$_posix"
    fortsh_file="/tmp/posix_ext_$$_fortsh"

    # Run in POSIX shell (sh)
    sh -c "$command" > "$posix_file" 2>&1 || true

    # Run in fortsh
    "$FORTSH_BIN" -c "$command" > "$fortsh_file" 2>&1 || true

    # Compare outputs
    if diff -q "$posix_file" "$fortsh_file" > /dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "$(cat "$posix_file")" "$(cat "$fortsh_file")"
    fi

    rm -f "$posix_file" "$fortsh_file"
}

# Helper function to compare exit codes
compare_posix_exit_code() {
    test_name="$1"
    command="$2"

    sh -c "$command" > /dev/null 2>&1
    posix_exit=$?

    "$FORTSH_BIN" -c "$command" > /dev/null 2>&1
    fortsh_exit=$?

    if [ "$posix_exit" -eq "$fortsh_exit" ]; then
        pass "$test_name"
    else
        fail "$test_name" "exit=$posix_exit" "exit=$fortsh_exit"
    fi
}

# Cleanup
cleanup() {
    rm -f /tmp/posix_ext_$$_* 2>/dev/null
    rm -f /tmp/posix_test_* 2>/dev/null
    rm -rf /tmp/posix_test_dir 2>/dev/null
}
trap cleanup EXIT INT TERM

# Setup test environment
mkdir -p /tmp/posix_test_dir
cd /tmp/posix_test_dir || exit 1

section "26. EXTENDED TEST COMMAND - FILE TYPE TESTS"

# Create test files with different properties
touch /tmp/posix_test_regular
chmod 644 /tmp/posix_test_regular
echo "data" > /tmp/posix_test_nonempty
mkdir -p /tmp/posix_test_directory
mkfifo /tmp/posix_test_fifo 2>/dev/null || skip "mkfifo" "not available"
ln -sf /tmp/posix_test_regular /tmp/posix_test_symlink 2>/dev/null

compare_posix_exit_code "test -e exists" "test -e /tmp/posix_test_regular"
compare_posix_exit_code "test -e nonexistent" "! test -e /tmp/nonexistent_xyz_$$"
compare_posix_exit_code "test -f regular file" "test -f /tmp/posix_test_regular"
compare_posix_exit_code "test -d directory" "test -d /tmp/posix_test_directory"
compare_posix_exit_code "test -s non-empty" "test -s /tmp/posix_test_nonempty"
compare_posix_exit_code "test -s empty" "! test -s /tmp/posix_test_regular"

# Symlink tests (if supported)
if [ -L /tmp/posix_test_symlink ]; then
    compare_posix_exit_code "test -L symlink" "test -L /tmp/posix_test_symlink"
    compare_posix_exit_code "test -h symlink" "test -h /tmp/posix_test_symlink"
fi

# FIFO tests (if created successfully)
if [ -p /tmp/posix_test_fifo ]; then
    compare_posix_exit_code "test -p fifo" "test -p /tmp/posix_test_fifo"
fi

section "27. EXTENDED TEST COMMAND - FILE PERMISSION TESTS"

# Create files with specific permissions
touch /tmp/posix_test_readable
chmod 644 /tmp/posix_test_readable
touch /tmp/posix_test_writable
chmod 644 /tmp/posix_test_writable
touch /tmp/posix_test_executable
chmod 755 /tmp/posix_test_executable

compare_posix_exit_code "test -r readable" "test -r /tmp/posix_test_readable"
compare_posix_exit_code "test -w writable" "test -w /tmp/posix_test_writable"
compare_posix_exit_code "test -x executable" "test -x /tmp/posix_test_executable"
compare_posix_exit_code "test ! -x nonexec" "! test -x /tmp/posix_test_readable"

section "28. EXTENDED TEST COMMAND - FILE COMPARISON"

# Create files for comparison
echo "old" > /tmp/posix_test_old
sleep 1
echo "new" > /tmp/posix_test_new
ln -f /tmp/posix_test_old /tmp/posix_test_hardlink 2>/dev/null

compare_posix_exit_code "test -nt newer than" "test /tmp/posix_test_new -nt /tmp/posix_test_old"
compare_posix_exit_code "test -ot older than" "test /tmp/posix_test_old -ot /tmp/posix_test_new"

# Hard link test (if supported)
if [ -f /tmp/posix_test_hardlink ]; then
    compare_posix_exit_code "test -ef same file" "test /tmp/posix_test_old -ef /tmp/posix_test_hardlink"
fi

section "29. EXTENDED TEST COMMAND - STRING TESTS"

compare_posix_exit_code "test -n nonempty string" "test -n 'hello'"
compare_posix_exit_code "test -z empty string" "test -z ''"
compare_posix_exit_code "test string = equal" "test 'abc' = 'abc'"
compare_posix_exit_code "test string != not equal" "test 'abc' != 'xyz'"
compare_posix_exit_code "test unary string" "test 'hello'"
compare_posix_exit_code "test ! negation" "! test -z 'hello'"

section "30. EXTENDED TEST COMMAND - INTEGER COMPARISON"

compare_posix_exit_code "test -eq equal" "test 42 -eq 42"
compare_posix_exit_code "test -ne not equal" "test 42 -ne 13"
compare_posix_exit_code "test -gt greater" "test 10 -gt 5"
compare_posix_exit_code "test -ge greater or equal" "test 10 -ge 10"
compare_posix_exit_code "test -lt less" "test 5 -lt 10"
compare_posix_exit_code "test -le less or equal" "test 5 -le 5"
compare_posix_exit_code "test negative numbers" "test -5 -lt 0"

section "31. EXTENDED TEST COMMAND - LOGICAL OPERATORS"

compare_posix_exit_code "test -a and" "test 5 -gt 3 -a 10 -gt 8"
compare_posix_exit_code "test -o or" "test 5 -gt 10 -o 10 -gt 8"
compare_posix_exit_code "test ! negation" "! test 5 -gt 10"
compare_posix_exit_code "test ( ) grouping" "test \( 5 -gt 3 \) -a \( 10 -gt 8 \)"

section "32. EXTENDED PARAMETER EXPANSION - DEFAULT VALUES"

compare_posix_output "use default unset" 'unset VAR; echo "${VAR-default}"'
compare_posix_output "use default null" 'VAR=; echo "${VAR-default}"'
compare_posix_output "use default null colon" 'VAR=; echo "${VAR:-default}"'
compare_posix_output "use default set" 'VAR=value; echo "${VAR-default}"'
compare_posix_output "assign default unset" 'unset VAR; echo "${VAR=assigned}"; echo $VAR'
compare_posix_output "assign default null colon" 'VAR=; echo "${VAR:=assigned}"; echo $VAR'

section "33. EXTENDED PARAMETER EXPANSION - ERROR IF UNSET"

compare_posix_exit_code "error if unset" 'unset VAR; echo "${VAR?error}" 2>/dev/null'
compare_posix_exit_code "error if null colon" 'VAR=; echo "${VAR:?error}" 2>/dev/null'
compare_posix_output "no error if set" 'VAR=value; echo "${VAR?error}"'

section "34. EXTENDED PARAMETER EXPANSION - ALTERNATIVE VALUE"

compare_posix_output "alt unset" 'unset VAR; echo "${VAR+alternative}"'
compare_posix_output "alt null" 'VAR=; echo "${VAR+alternative}"'
compare_posix_output "alt null colon" 'VAR=; echo "${VAR:+alternative}"'
compare_posix_output "alt set" 'VAR=value; echo "${VAR+alternative}"'
compare_posix_output "alt set colon" 'VAR=value; echo "${VAR:+alternative}"'

section "35. EXTENDED PARAMETER EXPANSION - STRING LENGTH"

compare_posix_output "length empty" 'VAR=; echo "${#VAR}"'
compare_posix_output "length short" 'VAR=hi; echo "${#VAR}"'
compare_posix_output "length long" 'VAR="hello world"; echo "${#VAR}"'
compare_posix_output "length special chars" 'VAR="a b c"; echo "${#VAR}"'

section "36. EXTENDED PARAMETER EXPANSION - PATTERN REMOVAL"

# Prefix removal
compare_posix_output "prefix # simple" 'VAR=hello; echo "${VAR#hel}"'
compare_posix_output "prefix # nomatch" 'VAR=hello; echo "${VAR#xyz}"'
compare_posix_output "prefix # glob" 'VAR=foo.bar.baz; echo "${VAR#*.}"'
compare_posix_output "prefix ## glob" 'VAR=foo.bar.baz; echo "${VAR##*.}"'
compare_posix_output "prefix # star" 'VAR=/usr/local/bin; echo "${VAR#*/}"'
compare_posix_output "prefix ## star" 'VAR=/usr/local/bin; echo "${VAR##*/}"'

# Suffix removal
compare_posix_output "suffix % simple" 'VAR=hello; echo "${VAR%lo}"'
compare_posix_output "suffix % nomatch" 'VAR=hello; echo "${VAR%xyz}"'
compare_posix_output "suffix % glob" 'VAR=foo.bar.baz; echo "${VAR%.*}"'
compare_posix_output "suffix %% glob" 'VAR=foo.bar.baz; echo "${VAR%%.*}"'
compare_posix_output "suffix % extension" 'VAR=file.tar.gz; echo "${VAR%.gz}"'
compare_posix_output "suffix %% extension" 'VAR=file.tar.gz; echo "${VAR%%.*}"'

section "37. ARITHMETIC EXPANSION - BASIC OPERATIONS"

compare_posix_output "arith addition" 'echo $((5 + 3))'
compare_posix_output "arith subtraction" 'echo $((10 - 4))'
compare_posix_output "arith multiplication" 'echo $((6 * 7))'
compare_posix_output "arith division" 'echo $((20 / 4))'
compare_posix_output "arith modulo" 'echo $((17 % 5))'
compare_posix_output "arith negative" 'echo $((-5 + 10))'
compare_posix_output "arith zero" 'echo $((0 + 0))'

section "38. ARITHMETIC EXPANSION - PRECEDENCE"

compare_posix_output "arith precedence mult" 'echo $((2 + 3 * 4))'
compare_posix_output "arith precedence paren" 'echo $(((2 + 3) * 4))'
compare_posix_output "arith precedence div" 'echo $((10 - 8 / 2))'
compare_posix_output "arith precedence complex" 'echo $((2 * 3 + 4 * 5))'

section "39. ARITHMETIC EXPANSION - VARIABLES"

compare_posix_output "arith var" 'X=5; echo $((X + 3))'
compare_posix_output "arith var no dollar" 'X=10; Y=20; echo $((X + Y))'
compare_posix_output "arith var assign" 'X=5; Y=$((X * 2)); echo $Y'
compare_posix_output "arith var complex" 'A=3; B=4; echo $((A * A + B * B))'

section "40. ARITHMETIC EXPANSION - COMPARISON"

compare_posix_output "arith compare eq true" 'echo $((5 == 5))'
compare_posix_output "arith compare eq false" 'echo $((5 == 3))'
compare_posix_output "arith compare ne true" 'echo $((5 != 3))'
compare_posix_output "arith compare ne false" 'echo $((5 != 5))'
compare_posix_output "arith compare lt" 'echo $((3 < 5))'
compare_posix_output "arith compare le" 'echo $((5 <= 5))'
compare_posix_output "arith compare gt" 'echo $((7 > 5))'
compare_posix_output "arith compare ge" 'echo $((5 >= 5))'

section "41. ARITHMETIC EXPANSION - LOGICAL"

compare_posix_output "arith logical and true" 'echo $((1 && 1))'
compare_posix_output "arith logical and false" 'echo $((1 && 0))'
compare_posix_output "arith logical or true" 'echo $((0 || 1))'
compare_posix_output "arith logical or false" 'echo $((0 || 0))'
compare_posix_output "arith logical not true" 'echo $((! 0))'
compare_posix_output "arith logical not false" 'echo $((! 1))'

section "42. SPECIAL PARAMETERS"

compare_posix_output "\$\$ process id type" 'echo $$ | grep -c "^[0-9][0-9]*$"'
compare_posix_output "\$- shell flags type" 'echo $- | grep -c "^[a-z]*$"'
compare_posix_output "\$# arg count" 'set -- a b c; echo $#'
compare_posix_output "\$1 first arg" 'set -- first second; echo $1'
compare_posix_output "\$2 second arg" 'set -- first second; echo $2'
compare_posix_output "\$9 ninth arg" 'set -- a b c d e f g h i j; echo $9'
compare_posix_output "\$* all args" 'set -- a b c; echo $*'
compare_posix_output "\$@ all args" 'set -- a b c; echo $@'

section "43. ADDITIONAL POSIX BUILTINS - CD/PWD"

compare_posix_output "cd to /tmp" 'cd /tmp && pwd'
compare_posix_output "cd relative" 'cd /tmp && cd .. && pwd | grep -c "^/"'
compare_posix_output "cd $HOME" 'cd && pwd | grep -c "^/"'

section "44. ADDITIONAL POSIX BUILTINS - UNSET"

compare_posix_output "unset variable" 'VAR=test; unset VAR; echo ${VAR:-unset}'
compare_posix_output "unset nonexistent" 'unset NONEXISTENT_VAR_XYZ; echo ok'

section "45. ADDITIONAL POSIX BUILTINS - EVAL"

compare_posix_output "eval simple" 'CMD="echo hello"; eval $CMD'
compare_posix_output "eval with var" 'X=5; CMD="echo \$X"; eval $CMD'
compare_posix_output "eval complex" 'A=echo; B=test; eval $A $B'

section "46. ADDITIONAL POSIX BUILTINS - COLON"

compare_posix_output ": null command" ': ; echo ok'
compare_posix_output ": with args" ': this is ignored; echo ok'
compare_posix_exit_code ": exit status" ':'

section "47. TILDE EXPANSION"

compare_posix_output "tilde home" 'echo ~ | grep -c "^/"'
compare_posix_output "tilde in path" 'echo ~/test | grep -c "^/"'

section "48. FIELD SPLITTING - ADVANCED"

compare_posix_output "IFS multiple fields" 'IFS=:; VAR="a:b:c:d"; set -- $VAR; echo $# $1 $4'
compare_posix_output "IFS whitespace" 'IFS=" "; VAR="a b c"; set -- $VAR; echo $#'
compare_posix_output "IFS comma" 'IFS=,; VAR="x,y,z"; set -- $VAR; echo $2'

section "49. BACKGROUND JOBS"

compare_posix_exit_code "background process" 'sleep 0.1 & wait'
compare_posix_output "background exit" '(exit 0) & wait $!; echo $?'

section "50. COMMAND GROUPING"

compare_posix_output "subshell isolation" 'X=1; (X=2; echo $X); echo $X'
compare_posix_output "brace grouping" 'X=1; { X=2; echo $X; }; echo $X'
compare_posix_output "subshell exit" '(exit 5); echo $?'

# Summary
section "SUMMARY"
printf "\n"
printf "==========================================\n"
printf "EXTENDED POSIX COMPLIANCE TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "${YELLOW}Skipped:${NC} %d\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"
printf "==========================================\n"

if [ $((PASSED + FAILED)) -gt 0 ]; then
    PASS_RATE=$((PASSED * 100 / (PASSED + FAILED)))
    printf "Pass rate: %d%%\n" "$PASS_RATE"
fi

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}ALL EXTENDED POSIX TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
