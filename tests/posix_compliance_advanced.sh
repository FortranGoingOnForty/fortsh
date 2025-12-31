#!/bin/sh
# =====================================
# POSIX Compliance Advanced Test Suite for fortsh
# =====================================
# Additional coverage based on OpenGroup POSIX.1-2017 specification
# Fills gaps not covered in basic, extended, and builtins test suites
#
# Coverage areas:
# - Advanced control flow (break/continue with levels)
# - Additional special built-ins (exec, command)
# - Extended set options (-f, -x, -v, -a)
# - File descriptor operations
# - Advanced arithmetic operators
# - Signal handling extensions
# - Pathname expansion edge cases
# - IFS edge cases
# - Function recursion and advanced usage

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-advanced]"
CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

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
    # Extract section number from header like "51. BREAK CONTINUE"
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n"
    printf "${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Normalize shell error messages by stripping shell name and "line N: " prefix
normalize_output() {
    sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'
}

# Helper function to run command in both shells and compare
compare_posix_output() {
    test_name="$1"
    command="$2"
    posix_file="/tmp/posix_adv_$$_posix"
    fortsh_file="/tmp/posix_adv_$$_fortsh"

    # Run in POSIX shell (sh)
    bash -c "$command" 2>&1 | normalize_output > "$posix_file" || true

    # Run in fortsh
    "$FORTSH_BIN" -c "$command" 2>&1 | normalize_output > "$fortsh_file" || true

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

    bash -c "$command" > /dev/null 2>&1
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
    rm -f /tmp/posix_adv_$$_* 2>/dev/null
    rm -rf /tmp/posix_advanced_test_* 2>/dev/null
}
trap cleanup EXIT INT TERM

section "51. BREAK AND CONTINUE IN LOOPS"

compare_posix_output "break in for loop" 'for i in 1 2 3 4 5; do echo $i; if [ $i -eq 3 ]; then break; fi; done'
compare_posix_output "continue in for loop" 'for i in 1 2 3 4 5; do if [ $i -eq 3 ]; then continue; fi; echo $i; done'
compare_posix_output "break in while loop" 'i=0; while [ $i -lt 5 ]; do i=$((i+1)); echo $i; if [ $i -eq 3 ]; then break; fi; done'
compare_posix_output "continue in while loop" 'i=0; while [ $i -lt 5 ]; do i=$((i+1)); if [ $i -eq 3 ]; then continue; fi; echo $i; done'
compare_posix_output "break in until loop" 'i=0; until [ $i -ge 5 ]; do i=$((i+1)); echo $i; if [ $i -eq 3 ]; then break; fi; done'

section "52. NESTED LOOPS WITH BREAK/CONTINUE"

compare_posix_output "break inner loop" 'for i in 1 2; do for j in a b c; do echo $i$j; if [ $j = b ]; then break; fi; done; done'
compare_posix_output "break with level" 'for i in 1 2; do for j in a b; do echo $i$j; if [ $j = b ]; then break 2; fi; done; done'
compare_posix_output "continue outer loop" 'for i in 1 2 3; do for j in a b; do echo $i$j; if [ $j = a ]; then continue 2; fi; done; done'

section "53. EXEC BUILTIN"

compare_posix_output "exec with redirect" 'exec 3>&1; echo test >&3; exec 3>&-; echo done'
compare_posix_exit_code "exec replace shell" '(exec true); echo $?'
compare_posix_output "exec without command" 'exec 2>&1; pwd >/dev/null'

section "54. COMMAND BUILTIN"

compare_posix_output "command -v test" 'command -v test | grep -c test'
compare_posix_output "command -v echo" 'command -v echo | grep -c echo'
compare_posix_exit_code "command -v nonexistent" '! command -v nonexistent_cmd_xyz'

section "55. READ BUILTIN - THOROUGH TESTING"

compare_posix_output "read single var" 'echo hello | read VAR 2>/dev/null || VAR=hello; echo $VAR'
compare_posix_output "read multiple vars" 'echo one two three | { read A B C; echo $A $B $C; }'
compare_posix_output "read with IFS" 'IFS=:; echo a:b:c | { read X Y Z; echo $X $Y $Z; }'
compare_posix_output "read remaining to last" 'echo a b c d e | { read X Y Z; echo "$Z"; }'

section "56. FILE DESCRIPTOR DUPLICATION"

compare_posix_output "dup stdout to fd3" 'exec 3>&1; echo test >&3'
compare_posix_output "dup stdin from fd" 'exec 3</dev/null; cat <&3; exec 3<&-; echo ok'
compare_posix_exit_code "close stdout" '(exec 1>&-; echo test 2>/dev/null); echo $?'

section "57. SET -F (NOGLOB)"

compare_posix_output "noglob disables expansion" 'set -f; echo /tmp/*.xyz; set +f'
compare_posix_output "noglob with literal star" 'set -f; VAR="a * b"; echo $VAR; set +f'
compare_posix_output "glob after set +f" 'set -f; set +f; echo /tmp 2>/dev/null | grep -c tmp'

section "58. SET -X (XTRACE)"

compare_posix_output "xtrace shows commands" 'set -x; echo test 2>&1 | grep -c echo; set +x'
compare_posix_output "xtrace in function" 'f() { set -x; echo inner 2>&1; set +x; }; f | grep -c echo'

section "59. SET -V (VERBOSE)"

compare_posix_output "verbose shows input" 'set -v; : test 2>&1 | grep -c test; set +v'

section "60. SET -A (ALLEXPORT)"

compare_posix_output "allexport exports vars" 'set -a; TEST_VAR=value; sh -c "echo \$TEST_VAR"'
compare_posix_output "allexport off" 'set +a; TEST2=val; sh -c "echo \${TEST2:-empty}"'

section "61. TRAP WITH SIGNALS"

compare_posix_output "trap INT signal" 'trap "echo caught" INT; trap | grep INT'
compare_posix_output "trap TERM signal" 'trap "echo term" TERM; trap | grep TERM'
compare_posix_output "trap HUP signal" 'trap "echo hup" HUP; trap | grep HUP'
compare_posix_output "trap with number" 'trap "echo sig15" 15; trap | grep -c 15'

section "62. TRAP INHERITANCE IN SUBSHELLS"

compare_posix_output "trap not inherited" 'trap "echo parent" EXIT; (trap | grep -c EXIT || echo 0)'
compare_posix_output "subshell can set trap" '(trap "echo sub" EXIT; exit 0)'

section "63. PARAMETER EXPANSION :? ERROR"

compare_posix_exit_code "error if unset" 'unset VAR; echo ${VAR:?error} 2>/dev/null'
compare_posix_exit_code "error if null" 'VAR=; echo ${VAR:?null} 2>/dev/null'
compare_posix_output "no error if set" 'VAR=test; echo ${VAR:?error}'

section "64. PARAMETER EXPANSION WITH SPECIAL PARAMS"

compare_posix_output "length of positional params" 'set -- a b c; echo ${#@}'
compare_posix_output "length of $*" 'set -- x y; echo ${#*}'
compare_posix_output "length of $1" 'set -- hello; echo ${#1}'

section "65. WAIT WITH ARGUMENTS"

compare_posix_output "wait specific PID" 'sleep 0.1 & pid=$!; wait $pid; echo $?'
compare_posix_output "wait all background" '(sleep 0.1 &); wait; echo ok'
compare_posix_exit_code "wait nonexistent PID" 'wait 999999'

section "66. IFS EDGE CASES"

compare_posix_output "empty IFS" 'IFS=; VAR="a b c"; set -- $VAR; echo $#'
compare_posix_output "IFS whitespace only" 'IFS=" \t\n"; VAR="a  b"; set -- $VAR; echo $# $1 $2'
compare_posix_output "IFS custom delimiter" 'IFS=,; VAR="a,b,c"; set -- $VAR; echo $2'
compare_posix_output "IFS leading delimiters" 'IFS=:; VAR=":a:b"; set -- $VAR; echo $#'

section "67. ARITHMETIC BITWISE OPERATORS"

compare_posix_output "bitwise AND" 'echo $((12 & 10))'
compare_posix_output "bitwise OR" 'echo $((12 | 10))'
compare_posix_output "bitwise XOR" 'echo $((12 ^ 10))'
compare_posix_output "bitwise NOT" 'echo $((~5))'
compare_posix_output "left shift" 'echo $((3 << 2))'
compare_posix_output "right shift" 'echo $((12 >> 2))'

section "68. ARITHMETIC ASSIGNMENT OPERATORS"

compare_posix_output "add assign" 'X=5; echo $((X += 3)); echo $X'
compare_posix_output "subtract assign" 'X=10; echo $((X -= 3)); echo $X'
compare_posix_output "multiply assign" 'X=4; echo $((X *= 2)); echo $X'
compare_posix_output "divide assign" 'X=20; echo $((X /= 4)); echo $X'
compare_posix_output "modulo assign" 'X=17; echo $((X %= 5)); echo $X'

section "69. ARITHMETIC INCREMENT/DECREMENT"

compare_posix_output "post increment" 'X=5; echo $((X++)); echo $X'
compare_posix_output "pre increment" 'X=5; echo $((++X)); echo $X'
compare_posix_output "post decrement" 'X=5; echo $((X--)); echo $X'
compare_posix_output "pre decrement" 'X=5; echo $((--X)); echo $X'

section "70. ARITHMETIC TERNARY OPERATOR"

compare_posix_output "ternary true" 'echo $((5 > 3 ? 10 : 20))'
compare_posix_output "ternary false" 'echo $((5 < 3 ? 10 : 20))'
compare_posix_output "ternary nested" 'echo $((1 ? 2 : 3 ? 4 : 5))'

section "71. PIPELINE NEGATION"

compare_posix_exit_code "negate true" '! true'
compare_posix_exit_code "negate false" '! false'
compare_posix_output "negate pipeline" '! echo test | grep -q xyz; echo $?'
compare_posix_exit_code "negate compound" '! (exit 0)'

section "72. THREE-STAGE PIPELINES"

compare_posix_output "three stage pipe" 'echo abc | tr a A | tr b B'
compare_posix_output "four stage pipe" 'echo test | cat | cat | wc -l'
compare_posix_exit_code "multi-stage exit" 'true | true | true'

section "73. CDPATH VARIABLE"

compare_posix_output "CDPATH usage" 'mkdir -p /tmp/posix_cdpath_test/subdir; CDPATH=/tmp/posix_cdpath_test; (cd subdir 2>/dev/null && pwd) | grep -c subdir; rm -rf /tmp/posix_cdpath_test'

section "74. OLDPWD VARIABLE"

compare_posix_output "OLDPWD set" 'OLD=/tmp; cd /tmp >/dev/null; cd / >/dev/null; echo $OLDPWD | grep -c tmp'
compare_posix_output "cd - uses OLDPWD" 'cd /tmp >/dev/null; cd / >/dev/null; cd - >/dev/null; pwd | grep -c tmp'

section "75. PATHNAME EXPANSION - BRACKET EXPRESSIONS"

mkdir -p /tmp/posix_advanced_test_bracket
touch /tmp/posix_advanced_test_bracket/a1.txt /tmp/posix_advanced_test_bracket/a2.txt
touch /tmp/posix_advanced_test_bracket/b1.txt /tmp/posix_advanced_test_bracket/b2.txt
touch /tmp/posix_advanced_test_bracket/c1.txt

compare_posix_output "bracket range" 'ls /tmp/posix_advanced_test_bracket/[a-b]1.txt 2>/dev/null | wc -l'
compare_posix_output "bracket negation" 'ls /tmp/posix_advanced_test_bracket/[!a]*.txt 2>/dev/null | wc -l'
compare_posix_output "bracket char class" 'ls /tmp/posix_advanced_test_bracket/[[:lower:]]1.txt 2>/dev/null | wc -l'

rm -rf /tmp/posix_advanced_test_bracket

section "76. PATHNAME EXPANSION - DOTFILE MATCHING"

mkdir -p /tmp/posix_advanced_test_dotfile
touch /tmp/posix_advanced_test_dotfile/.hidden
touch /tmp/posix_advanced_test_dotfile/visible

compare_posix_output "star no dotfiles" 'ls /tmp/posix_advanced_test_dotfile/* 2>/dev/null | wc -l'
compare_posix_output "explicit dot match" 'ls /tmp/posix_advanced_test_dotfile/.* 2>/dev/null | grep -c hidden'

rm -rf /tmp/posix_advanced_test_dotfile

section "77. FOR LOOP VARIATIONS"

compare_posix_output "for with glob" 'touch /tmp/posix_for_1.txt /tmp/posix_for_2.txt /tmp/posix_for_3.txt; for f in /tmp/posix_for_*.txt; do echo $f; done | wc -l; rm /tmp/posix_for_*.txt'
compare_posix_output "for with no items" 'for x in; do echo $x; done; echo empty'
compare_posix_output "for with quoted items" 'for i in "a b" "c d"; do echo $i; done | wc -l'

section "78. CASE PATTERN MATCHING"

compare_posix_output "case multiple pattern" 'x=b; case $x in a|b|c) echo match;; *) echo no;; esac'
compare_posix_output "case glob pattern" 'x=hello; case $x in h*) echo prefix;; esac'
compare_posix_output "case question mark" 'x=ab; case $x in ??) echo two;; esac'
compare_posix_output "case bracket" 'x=a; case $x in [abc]) echo bracket;; esac'

section "79. FUNCTION VARIATIONS"

compare_posix_output "function recursion" 'fact() { if [ $1 -le 1 ]; then echo 1; else echo $(($1 * $(fact $(($1 - 1))))); fi; }; fact 5'
compare_posix_output "function unset" 'f() { echo test; }; f; unset -f f; command -v f >/dev/null 2>&1; echo $?'
compare_posix_output "nested return" 'a() { b; echo $?; }; b() { return 42; }; a'

section "80. EXPANSION IN DIFFERENT CONTEXTS"

compare_posix_output "tilde in assignment" 'VAR=~; echo $VAR | grep -c ^/'
compare_posix_output "expansion in case" 'VAR=test; case $VAR in test) echo match;; esac'
compare_posix_output "no expansion in quotes" 'echo "~" | grep -c "~"'

section "81. REDIRECTION ORDER AND PRECEDENCE"

compare_posix_output "multiple redirects" 'echo test >/tmp/redir1 2>&1 >/tmp/redir2; cat /tmp/redir1 /tmp/redir2 2>/dev/null | wc -l; rm -f /tmp/redir1 /tmp/redir2'
compare_posix_output "redirect compound cmd" '{ echo a; echo b; } >/tmp/redir_compound; wc -l < /tmp/redir_compound; rm -f /tmp/redir_compound'

section "82. ERROR HANDLING IN EXPANSIONS"

compare_posix_exit_code "division by zero" 'echo $((5 / 0)) 2>/dev/null'
compare_posix_exit_code "expansion error" 'set -u; echo $UNDEFINED_VAR_XYZ 2>/dev/null'

section "83. SPECIAL PARAMETERS - ADDITIONAL"

compare_posix_output "PPID is numeric" 'echo $PPID | grep -c "^[0-9]*$"'
compare_posix_output "LINENO exists" 'echo $LINENO | grep -c "^[0-9]*$"'

section "84. ALIAS AND UNALIAS"

compare_posix_output "alias definition" 'alias ll="ls -l"; alias ll | grep -c "ls -l"'
compare_posix_output "unalias removes" 'alias test_alias=echo; unalias test_alias; alias test_alias 2>&1 | grep -c "not found"'

section "85. HASH BUILTIN OPERATIONS"

compare_posix_output "hash -r clears" 'hash -r; echo $?'
compare_posix_exit_code "hash command" 'hash echo 2>/dev/null'

section "86. MULTIPLE SEMICOLONS AND EDGE CASES"

compare_posix_output "multiple semicolons" 'echo a;; echo b'
compare_posix_output "semicolon at start" '; echo test'
compare_posix_exit_code "empty command" ''

section "87. BACKSLASH LINE CONTINUATION"

compare_posix_output "backslash continuation" 'echo hel\
lo'
compare_posix_output "backslash in command" 'ec\
ho test'

section "88. COMMENT HANDLING"

compare_posix_output "comment after command" 'echo visible # this is comment'
compare_posix_output "comment alone" '# comment
echo after'

section "89. QUOTING EDGE CASES"

compare_posix_output "empty string quotes" 'echo "" | wc -l'
compare_posix_output "adjacent quotes" 'echo "a"b"c"'
compare_posix_output "quote within quote" "echo \"it's\" | grep -c \"'\""

section "90. COMPOUND COMMAND REDIRECTION"

compare_posix_output "subshell with redirect" '(echo a; echo b) | wc -l'
compare_posix_output "brace group redirect" '{ echo x; echo y; } | wc -l'
compare_posix_output "if statement redirect" 'if true; then echo yes; fi | cat'

section "91. POSIX PARAMETER LENGTH"

compare_posix_output "length of empty" 'X=""; echo ${#X}'
compare_posix_output "length with spaces" 'X="a b c"; echo ${#X}'
compare_posix_output "length special chars" 'X="$@#!"; echo ${#X}'
compare_posix_output "length unicode" 'X="abc"; echo ${#X}'

section "92. POSIX DEFAULT VALUES VARIANTS"

compare_posix_output ":-colon vs dash" 'X=""; echo "${X:-default}" "${X-default}"'
compare_posix_output ":=colon vs equals" 'unset Y; echo "${Y:=def}"; echo $Y'
compare_posix_output ":+colon vs plus" 'X=val; echo "${X:+alt}" "${X+alt}"'
compare_posix_output ":?colon vs question" 'X=val; echo "${X:?err}" 2>/dev/null'

section "93. POSIX PATTERN REMOVAL EDGE CASES"

compare_posix_output "remove empty pattern" 'X=test; echo "${X#}"'
compare_posix_output "remove star pattern" 'X=test; echo "${X#*}"'
compare_posix_output "remove all with ##" 'X=test; echo "${X##*}"'
compare_posix_output "suffix empty" 'X=test; echo "${X%}"'
compare_posix_output "suffix star" 'X=test; echo "${X%*}"'
compare_posix_output "suffix all" 'X=test; echo "${X%%*}"'

section "94. POSIX ARITHMETIC OPERATORS"

compare_posix_output "arithmetic modulo" 'echo $((17 % 5))'
compare_posix_output "arithmetic negative" 'echo $((-5 + 3))'
compare_posix_output "arithmetic parens" 'echo $(((2 + 3) * 4))'
compare_posix_output "arithmetic bitwise and" 'echo $((12 & 10))'
compare_posix_output "arithmetic bitwise or" 'echo $((12 | 10))'
compare_posix_output "arithmetic bitwise xor" 'echo $((12 ^ 10))'
compare_posix_output "arithmetic shift left" 'echo $((1 << 4))'
compare_posix_output "arithmetic shift right" 'echo $((16 >> 2))'

section "95. POSIX ARITHMETIC COMPARISONS"

compare_posix_output "arith less than" 'echo $((3 < 5))'
compare_posix_output "arith greater than" 'echo $((5 > 3))'
compare_posix_output "arith less equal" 'echo $((3 <= 3))'
compare_posix_output "arith greater equal" 'echo $((3 >= 3))'
compare_posix_output "arith equal" 'echo $((5 == 5))'
compare_posix_output "arith not equal" 'echo $((5 != 3))'
compare_posix_output "arith logical and" 'echo $((1 && 1))'
compare_posix_output "arith logical or" 'echo $((0 || 1))'

section "96. POSIX COMMAND SUBSTITUTION EDGE CASES"

compare_posix_output "cmd sub with quotes" 'echo $(echo "hello world")'
compare_posix_output "cmd sub trailing newlines" 'echo "$(printf "a\n\n\n")"b'
compare_posix_output "cmd sub with pipe" 'echo $(echo test | tr t T)'
compare_posix_output "cmd sub with redirect" 'echo $(cat </dev/null)'
compare_posix_output "backtick with quotes" 'echo `echo "hello"`'

section "97. POSIX SUBSHELL VARIABLE ISOLATION"

compare_posix_output "subshell no export" 'X=1; (X=2; echo $X); echo $X'
compare_posix_output "subshell unset" 'X=1; (unset X; echo ${X:-empty}); echo $X'
compare_posix_output "nested subshell" '(( echo nested ))'
compare_posix_output "subshell exit" '(exit 5); echo $?'

section "98. POSIX BRACE GROUP VS SUBSHELL"

compare_posix_output "brace group modifies" 'X=1; { X=2; }; echo $X'
compare_posix_output "subshell isolates" 'X=1; (X=2); echo $X'
compare_posix_output "brace with semicolon" '{ echo a; echo b; }'
compare_posix_output "brace in pipeline" '{ echo test; } | cat'

section "99. POSIX HERE-STRING ALTERNATIVES"

compare_posix_output "echo pipe vs redirect" 'echo test | cat'
compare_posix_output "printf to stdin" 'printf "test\n" | read X; echo $X'

section "100. POSIX PIPELINE EXIT STATUS"

compare_posix_output "pipe success" 'true | true; echo $?'
compare_posix_output "pipe last fails" 'true | false; echo $?'
compare_posix_output "pipe first fails" 'false | true; echo $?'
compare_posix_output "long pipeline" 'echo a | cat | cat | cat; echo $?'

section "101. POSIX PROCESS SUBSTITUTION ALTERNATIVES"

compare_posix_output "temp file pattern" 'echo test > /tmp/psub$$; cat /tmp/psub$$; rm /tmp/psub$$'
compare_posix_output "named pipe simulation" 'mkfifo /tmp/pfifo$$ 2>/dev/null || true; rm -f /tmp/pfifo$$; echo ok'

section "102. POSIX TEST BRACKETS"

compare_posix_output "test vs bracket" 'test 1 -eq 1 && [ 1 -eq 1 ] && echo ok'
compare_posix_output "bracket spacing" '[ "a" = "a" ] && echo match'
compare_posix_output "empty bracket test" '[ "" ] || echo empty'
compare_posix_output "nonempty test" '[ "x" ] && echo nonempty'

section "103. POSIX GETOPTS ADVANCED"

compare_posix_output "getopts multiple" 'while getopts "ab:c" opt 2>/dev/null; do echo $opt; done <<< "-a -b val -c"'
compare_posix_output "getopts OPTARG" 'getopts "a:" opt <<< "-a value" 2>/dev/null; echo $OPTARG'
compare_posix_output "getopts OPTIND" 'OPTIND=1; getopts "a" opt <<< "-a" 2>/dev/null; echo $OPTIND'

section "104. POSIX READ BUILTIN"

compare_posix_output "read single var" 'echo "hello" | { read X; echo $X; }'
compare_posix_output "read multiple vars" 'echo "a b c" | { read X Y Z; echo "$X:$Y:$Z"; }'
compare_posix_output "read with IFS" 'echo "a:b:c" | { IFS=: read X Y Z; echo "$X $Y $Z"; }'
compare_posix_output "read extra words" 'echo "a b c d" | { read X Y; echo "$X:$Y"; }'

section "105. POSIX PRINTF FORMATTING"

compare_posix_output "printf string" 'printf "%s\n" "test"'
compare_posix_output "printf integer" 'printf "%d\n" 42'
compare_posix_output "printf width" 'printf "%10s\n" "hi"'
compare_posix_output "printf left align" 'printf "%-10s|\n" "hi"'
compare_posix_output "printf zero pad" 'printf "%05d\n" 42'
compare_posix_output "printf multiple" 'printf "%s %d\n" "val" 123'

# Summary
printf "\n"
printf "==========================================\n"
printf "ADVANCED POSIX COMPLIANCE TEST RESULTS ${TEST_PREFIX}\n"
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
    printf "${GREEN}ALL ADVANCED POSIX TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
