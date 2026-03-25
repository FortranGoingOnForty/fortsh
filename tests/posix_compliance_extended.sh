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

# Test identification
TEST_PREFIX="[posix-extended]"
CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

# Get script directory (POSIX way)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../bin/fortsh}"
BASH_REF="${BASH_REF:-bash}"

# Check if fortsh exists
if [ ! -x "$FORTSH_BIN" ]; then
    printf "${RED}ERROR${NC}: fortsh binary not found at $FORTSH_BIN\n"
    printf "Please run 'make' first or set FORTSH_BIN environment variable\n"
    exit 1
fi

# Test result trackers
pass() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${GREEN}✓ PASS${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    TEST_NUM=$((TEST_NUM + 1))
    TEST_ID="${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}"
    printf "${RED}✗ FAIL${NC} ${TEST_ID}: %s\n" "$1"
    FAILED_TESTS_LIST="${FAILED_TESTS_LIST}  ${TEST_ID}: $1\n"
    if [ -n "$2" ]; then
        printf "  posix:  %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  fortsh: %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${YELLOW}⊘ SKIP${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s - %s\n" "$1" "$2"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    # Extract section number from header like "26. EXTENDED TEST"
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
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
    "$BASH_REF" -c "$command" > "$posix_file" 2>&1 || true

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

    "$BASH_REF" -c "$command" > /dev/null 2>&1
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

section "51. GLOB PATTERN MATCHING"

# Create temp dir for glob tests
GLOB_DIR="/tmp/posix_glob_test_$$"
mkdir -p "$GLOB_DIR"
touch "$GLOB_DIR/file1.txt" "$GLOB_DIR/file2.txt" "$GLOB_DIR/file3.log"
touch "$GLOB_DIR/abc" "$GLOB_DIR/abd" "$GLOB_DIR/acd"

compare_posix_output "star matches multiple" 'cd '"$GLOB_DIR"' && echo file*.txt | tr " " "\n" | wc -l'
compare_posix_output "question mark single char" 'cd '"$GLOB_DIR"' && echo ab? | tr " " "\n" | wc -l'
compare_posix_output "bracket range" 'cd '"$GLOB_DIR"' && echo a[bc]d | tr " " "\n" | wc -l'
compare_posix_output "no match literal" 'cd '"$GLOB_DIR"' && echo zzz*.xyz 2>/dev/null || echo "zzz*.xyz"'

rm -rf "$GLOB_DIR"

section "52. DOTFILE HANDLING"

DOT_DIR="/tmp/posix_dot_test_$$"
mkdir -p "$DOT_DIR"
touch "$DOT_DIR/.hidden" "$DOT_DIR/visible"

compare_posix_output "star no dotfiles" 'cd '"$DOT_DIR"' && echo * | grep -c hidden || echo 0'
compare_posix_output "explicit dot matches" 'cd '"$DOT_DIR"' && ls -d .* 2>/dev/null | grep -c hidden'

rm -rf "$DOT_DIR"

section "53. QUOTING IN GLOB"

QUOTE_DIR="/tmp/posix_quote_glob_$$"
mkdir -p "$QUOTE_DIR"
touch "$QUOTE_DIR/star"

compare_posix_output "quoted star literal" 'cd '"$QUOTE_DIR"' && echo "*" | grep -c "\\*"'
compare_posix_output "single quote prevents glob" "cd '$QUOTE_DIR' && echo '*' | grep -c '\\*'"

rm -rf "$QUOTE_DIR"

section "54. EMPTY AND NULL EXPANSION"

compare_posix_output "unset var empty" 'unset X; echo "[$X]"'
compare_posix_output "null var empty" 'X=""; echo "[$X]"'
compare_posix_output "unset in arith" 'unset X; echo $((X + 1))'

section "55. SPECIAL VARIABLES READONLY"

compare_posix_output "cannot assign to ?" '(eval "?=5" 2>/dev/null); echo ok'
compare_posix_output "cannot assign to $" '(eval "\$=5" 2>/dev/null); echo ok'

section "56. COMPLEX COMMAND LISTS"

compare_posix_output "and-or chain" 'true && echo yes || echo no'
compare_posix_output "or-and chain" 'false || echo fallback && echo then'
compare_posix_output "semicolon list" 'echo a; echo b; echo c'
compare_posix_output "mixed operators" 'true && true && echo all || echo none'

section "57. NESTED SUBSHELLS"

compare_posix_output "double nesting" '( ( echo deep ) )'
compare_posix_output "triple nesting" '( ( ( echo deeper ) ) )'
compare_posix_output "nested with vars" 'X=1; ( X=2; ( X=3; echo $X ) ); echo $X'

section "58. BRACE GROUP EDGE CASES"

compare_posix_output "brace needs space" '{ echo test; }'
compare_posix_output "brace with semicolon" '{ echo a; echo b; }'
compare_posix_output "brace preserves vars" 'X=1; { X=2; }; echo $X'

section "59. ARITHMETIC BASE LITERALS"

compare_posix_output "octal 010" 'echo $((010))'
compare_posix_output "hex 0x10" 'echo $((0x10))'
compare_posix_output "hex 0xFF" 'echo $((0xFF))'
compare_posix_output "mixed bases" 'echo $((010 + 0x10 + 10))'

section "60. STRING LENGTH EDGE CASES"

compare_posix_output "length empty" 'X=""; echo ${#X}'
compare_posix_output "length one" 'X="a"; echo ${#X}'
compare_posix_output "length with spaces" 'X="a b c"; echo ${#X}'
compare_posix_output "length special chars" 'X="$@#"; echo ${#X}'

section "61. DEFAULT VALUE EDGE CASES"

compare_posix_output "default unset" 'unset X; echo ${X:-default}'
compare_posix_output "default null" 'X=""; echo ${X:-default}'
compare_posix_output "default set" 'X="value"; echo ${X:-default}'
compare_posix_output "no-colon unset" 'unset X; echo ${X-default}'
compare_posix_output "no-colon null" 'X=""; echo ${X-default}'

section "62. PATTERN REMOVAL EDGE CASES"

compare_posix_output "prefix no match" 'X="hello"; echo ${X#xyz}'
compare_posix_output "suffix no match" 'X="hello"; echo ${X%xyz}'
compare_posix_output "prefix full match" 'X="aaa"; echo ${X##a*}'
compare_posix_output "suffix full match" 'X="aaa"; echo ${X%%*a}'

section "63. POSITIONAL PARAMS EDGE CASES"

compare_posix_output "set clears all" 'set -- a b c; set --; echo $#'
compare_posix_output "set replaces" 'set -- a b; set -- x y z; echo $#'
compare_posix_output "shift all" 'set -- a b c; shift 3; echo $#'

section "64. EXIT STATUS PROPAGATION"

compare_posix_output "pipeline exit" 'true | true | false; echo $?'
compare_posix_output "subshell exit" '(exit 42); echo $?'
compare_posix_output "brace exit" '{ exit 7; }; echo $?'
compare_posix_output "command sub exit" 'X=$(exit 5); echo $?'

section "65. WORD SPLITTING IFS VARIANTS"

compare_posix_output "IFS empty no split" 'IFS=""; X="a b c"; set -- $X; echo $#'
compare_posix_output "IFS colon" 'IFS=":"; X="a:b:c"; set -- $X; echo $#'
compare_posix_output "IFS multiple" 'IFS=":;"; X="a:b;c"; set -- $X; echo $#'
compare_posix_output "IFS whitespace" 'IFS=" "; X="a  b  c"; set -- $X; echo $#'
compare_posix_output "IFS default" 'X="a   b   c"; set -- $X; echo $#'

section "66. PATHNAME EXPANSION DISABLING"

compare_posix_output "noglob off" 'touch /tmp/glob_test_a.x /tmp/glob_test_b.x 2>/dev/null; ls /tmp/glob_test_*.x 2>/dev/null | wc -l'
compare_posix_output "noglob on" 'set -f; echo /tmp/glob_test_*.x; set +f'

section "67. TILDE EXPANSION CONTEXTS"

compare_posix_output "tilde alone" 'echo ~ | grep -c "^/"'
compare_posix_output "tilde in var" 'X=~; echo $X | grep -c "^/"'
compare_posix_output "tilde quoted" 'echo "~" | grep -c "~"'
compare_posix_output "tilde in path" 'echo ~/. | grep -c "^/"'

section "68. ASSIGNMENT CONTEXTS"

compare_posix_output "simple assign" 'X=hello; echo $X'
compare_posix_output "assign with cmd sub" 'X=$(echo test); echo $X'
compare_posix_output "assign with arith" 'X=$((5+3)); echo $X'
compare_posix_output "multiple assign" 'X=1 Y=2 Z=3; echo $X $Y $Z'
compare_posix_output "assign before cmd" 'X=val sh -c "echo \$X"'

section "69. SPECIAL CHARACTER HANDLING"

compare_posix_output "escaped newline" 'echo a\
b'
compare_posix_output "escaped dollar" 'echo \$VAR'
compare_posix_output "escaped backslash" 'echo \\\\'
compare_posix_output "escaped quote" 'echo \"quoted\"'

section "70. WHILE LOOP VARIATIONS"

compare_posix_output "while with pipe" 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done | wc -l'
compare_posix_output "while false" 'while false; do echo never; done; echo done'
compare_posix_output "while break" 'i=0; while true; do i=$((i+1)); [ $i -ge 3 ] && break; done; echo $i'
compare_posix_output "while continue" 'i=0; while [ $i -lt 5 ]; do i=$((i+1)); [ $i -eq 3 ] && continue; echo $i; done'

section "71. UNTIL LOOP VARIATIONS"

compare_posix_output "until basic" 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done'
compare_posix_output "until true" 'until true; do echo never; done; echo done'
compare_posix_output "until with break" 'i=0; until false; do i=$((i+1)); [ $i -ge 3 ] && break; done; echo $i'

section "72. FOR LOOP WORD LIST"

compare_posix_output "for with glob" 'touch /tmp/for_test_1.z /tmp/for_test_2.z 2>/dev/null; for f in /tmp/for_test_*.z; do echo found; done | wc -l'
compare_posix_output "for empty" 'for x in; do echo never; done; echo done'
compare_posix_output "for with expansion" 'X="a b c"; for i in $X; do echo $i; done | wc -l'
compare_posix_output "for quoted" 'for i in "a b" "c d"; do echo "[$i]"; done'

section "73. FUNCTION ARGUMENT HANDLING"

compare_posix_output "func args count" 'f() { echo $#; }; f a b c'
compare_posix_output "func args values" 'f() { echo $1 $2 $3; }; f x y z'
compare_posix_output "func args shift" 'f() { shift; echo $1; }; f a b c'
compare_posix_output "func args all" 'f() { echo $@; }; f 1 2 3'
compare_posix_output "func nested call" 'a() { b; }; b() { echo hello; }; a'

section "74. RETURN AND EXIT"

compare_posix_output "return value" 'f() { return 42; }; f; echo $?'
compare_posix_output "return default" 'f() { true; return; }; f; echo $?'
compare_posix_output "exit in subshell" '(exit 5); echo $?'
compare_posix_output "exit from func" 'f() { exit 7; }; f; echo never'

section "75. EVAL COMPLEX"

compare_posix_output "eval variable expansion" 'X=VAR; VAR=value; eval echo \$$X'
compare_posix_output "eval multiple" 'eval "A=1; B=2"; echo $A $B'
compare_posix_output "eval with special" 'eval "echo hello world"'
compare_posix_output "eval nested" 'eval eval echo test'

section "76. EXEC REDIRECTIONS"

compare_posix_output "exec redirect stdout" 'exec >/tmp/exec_test_$$; echo test; exec >&-; cat /tmp/exec_test_$$; rm /tmp/exec_test_$$'

section "77. TRAP IN SUBSHELL"

compare_posix_output "trap inherited" '(trap "echo trapped" EXIT; exit 0) 2>/dev/null'
compare_posix_output "trap reset in subshell" 'trap "echo outer" EXIT; (trap - EXIT; echo inner) 2>/dev/null; trap - EXIT'

section "78. COLON COMMAND"

compare_posix_output "colon returns 0" ':; echo $?'
compare_posix_output "colon with args" ': arg1 arg2 arg3; echo $?'
compare_posix_output "colon with expansion" 'X=test; : $X; echo $?'
compare_posix_output "colon in if" 'if :; then echo yes; fi'

section "79. DOT SOURCE"

compare_posix_output "dot sources" 'echo "X=sourced" > /tmp/dot_test_$$; . /tmp/dot_test_$$; echo $X; rm /tmp/dot_test_$$'
compare_posix_output "dot with args" 'echo "echo \$1" > /tmp/dot_arg_$$; . /tmp/dot_arg_$$ hello; rm /tmp/dot_arg_$$'

section "80. UNSET BEHAVIOR"

compare_posix_output "unset variable" 'X=test; unset X; echo ${X:-empty}'
compare_posix_output "unset function" 'f() { echo hi; }; unset -f f; f 2>/dev/null || echo gone'
compare_posix_output "unset nonexistent" 'unset NONEXISTENT_VAR_XYZ; echo $?'

section "81. POSIX STRING OPERATIONS"

compare_posix_output "string concat" 'A=hello; B=world; echo $A$B'
compare_posix_output "string in quotes" 'A="hello world"; echo "$A"'
compare_posix_output "string length indirect" 'A=test; echo ${#A}'
compare_posix_output "empty string" 'A=""; echo "[$A]"'
compare_posix_output "string with newline" 'A="line1
line2"; echo "$A" | wc -l'

section "82. POSIX NUMERIC OPERATIONS"

compare_posix_output "add subtract" 'echo $((10 - 3 + 5))'
compare_posix_output "multiply divide" 'echo $((20 / 4 * 2))'
compare_posix_output "parentheses" 'echo $(((2 + 3) * (4 + 1)))'
compare_posix_output "comparison chain" 'echo $((5 > 3 && 3 > 1))'
compare_posix_output "ternary simulation" 'X=5; [ $X -gt 3 ] && echo big || echo small'

section "83. POSIX ARRAY SIMULATION"

compare_posix_output "positional as array" 'set -- a b c d e; echo $3'
compare_posix_output "array length" 'set -- a b c d e; echo $#'
compare_posix_output "array slice" 'set -- a b c d e; shift 2; echo $1'
compare_posix_output "array all" 'set -- a b c; echo "$@"'
compare_posix_output "array iterate" 'set -- a b c; for x in "$@"; do echo $x; done'

section "84. POSIX PATTERN MATCHING"

compare_posix_output "glob question" 'touch /tmp/pat_a /tmp/pat_b 2>/dev/null; ls /tmp/pat_? 2>/dev/null | wc -l; rm -f /tmp/pat_a /tmp/pat_b'
compare_posix_output "glob star" 'touch /tmp/patstar_1 /tmp/patstar_2 2>/dev/null; ls /tmp/patstar_* 2>/dev/null | wc -l; rm -f /tmp/patstar_*'
compare_posix_output "glob bracket" 'touch /tmp/patbr_a /tmp/patbr_b 2>/dev/null; ls /tmp/patbr_[ab] 2>/dev/null | wc -l; rm -f /tmp/patbr_*'
compare_posix_output "case pattern star" 'x=hello; case $x in h*) echo yes;; esac'
compare_posix_output "case pattern question" 'x=ab; case $x in ??) echo two;; esac'

section "85. POSIX ENVIRONMENT"

compare_posix_output "HOME exists" 'echo $HOME | grep -c "^/"'
compare_posix_output "PATH exists" 'echo $PATH | grep -c ":"'
compare_posix_output "PWD exists" 'echo $PWD | grep -c "^/"'
compare_posix_output "export visible" 'export X=val; sh -c "echo \$X"'
compare_posix_output "env assignment" 'X=test sh -c "echo \$X"'

section "86. POSIX SPECIAL EXPANSIONS"

compare_posix_output "dollar dollar" 'echo $$ | grep -E "^[0-9]+$" | wc -l'
compare_posix_output "dollar question" 'true; echo $?'
compare_posix_output "dollar bang" 'sleep 0.01 & echo $! | grep -E "^[0-9]+$" | wc -l; wait'
compare_posix_output "dollar hash" 'set -- a b c; echo $#'
compare_posix_output "dollar zero" 'echo $0 | wc -c | xargs test 0 -lt && echo yes'

section "87. POSIX ERROR HANDLING"

compare_posix_output "command not found" 'nonexistent_cmd_xyz 2>/dev/null; echo $?'
compare_posix_output "file not found" 'cat /nonexistent_file_xyz 2>/dev/null; echo $?'
compare_posix_output "permission denied sim" 'test -r /etc/shadow 2>/dev/null; echo done'
compare_posix_output "syntax error handled" 'eval "if" 2>/dev/null; echo recovered'

section "88. POSIX CONDITIONAL CHAINS"

compare_posix_output "if and" 'if true && true; then echo yes; fi'
compare_posix_output "if or" 'if false || true; then echo yes; fi'
compare_posix_output "if not" 'if ! false; then echo yes; fi'
compare_posix_output "complex condition" 'X=5; if [ $X -gt 3 ] && [ $X -lt 10 ]; then echo range; fi'
compare_posix_output "elif chain long" 'X=4; if [ $X -eq 1 ]; then echo 1; elif [ $X -eq 2 ]; then echo 2; elif [ $X -eq 3 ]; then echo 3; elif [ $X -eq 4 ]; then echo 4; fi'

section "89. POSIX INPUT PROCESSING"

compare_posix_output "read line" 'echo "hello" | { read x; echo $x; }'
compare_posix_output "read words" 'echo "a b c" | { read x y z; echo $y; }'
compare_posix_output "read with IFS" 'echo "a:b:c" | { IFS=: read x y z; echo $y; }'
compare_posix_output "cat file" 'echo "test" > /tmp/read_test_$$; cat /tmp/read_test_$$; rm /tmp/read_test_$$'

section "90. POSIX OUTPUT FORMATTING"

compare_posix_output "printf string" 'printf "%s\n" "hello"'
compare_posix_output "printf number" 'printf "%d\n" 42'
compare_posix_output "printf hex" 'printf "%x\n" 255'
compare_posix_output "printf octal" 'printf "%o\n" 64'
compare_posix_output "printf char" 'printf "%c\n" A'
compare_posix_output "echo no newline" 'printf "no newline"'

# Summary
printf "\n"
printf "==========================================\n"
printf "EXTENDED POSIX COMPLIANCE TEST RESULTS ${TEST_PREFIX}\n"
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

if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n"
    printf "%b" "$FAILED_TESTS_LIST"
    printf "==========================================\n"
fi

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}ALL EXTENDED POSIX TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
