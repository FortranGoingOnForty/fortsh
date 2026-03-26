#!/bin/sh
# =====================================
# POSIX Builtin Gap Tests
# =====================================
# Tests for POSIX shell builtins
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-builtins]"
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
    if [ -n "$2" ]; then printf "  posix:  %s\n" "$2"; fi
    if [ -n "$3" ]; then printf "  fortsh: %s\n" "$3"; fi
    FAILED=$((FAILED + 1))
}

section() {
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n${BLUE}==========================================\n%s\n==========================================${NC}\n" "$1"
}

normalize_output() { sed -e 's|^[^ ]*bash: |sh: |' -e 's|^[^ ]*fortsh: |sh: |' -e 's/line [0-9]*: //'; }

compare_posix_output() {
    test_name="$1"; command="$2"
    posix_out=$("$BASH_REF" -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

compare_posix_exit_code() {
    test_name="$1"; command="$2"
    "$BASH_REF" -c "$command" >/dev/null 2>&1; posix_code=$?
    "$FORTSH_BIN" -c "$command" >/dev/null 2>&1; fortsh_code=$?
    if [ "$posix_code" = "$fortsh_code" ]; then pass "$test_name"
    else fail "$test_name" "exit $posix_code" "exit $fortsh_code"; fi
}

compare_posix_error() {
    test_name="$1"; command="$2"
    posix_out=$("$BASH_REF" -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

# ============================================================================
# CD BUILTIN
# ============================================================================

section "1. CD BUILTIN"
compare_posix_output "cd tmp" 'cd /tmp; pwd'
compare_posix_output "cd home" 'cd ~; pwd | grep -c /'
compare_posix_output "cd dash" 'cd /tmp; cd /; cd -'
compare_posix_output "cd dotdot" 'cd /tmp; cd ..; pwd'

# ============================================================================
# PWD BUILTIN
# ============================================================================

section "2. PWD BUILTIN"
compare_posix_output "pwd basic" 'pwd | grep -c /'
compare_posix_output "pwd P" 'pwd -P | grep -c /'
compare_posix_output "pwd L" 'pwd -L | grep -c /'

# ============================================================================
# ECHO BUILTIN
# ============================================================================

section "3. ECHO BUILTIN"
compare_posix_output "echo basic" 'echo hello'
compare_posix_output "echo multi" 'echo hello world'
compare_posix_output "echo empty" 'echo ""'
compare_posix_output "echo n" 'echo -n hello; echo world'
compare_posix_output "echo special" 'echo "a\tb"'

# ============================================================================
# PRINTF BUILTIN
# ============================================================================

section "4. PRINTF BUILTIN"
compare_posix_output "printf s" 'printf "%s\n" hello'
compare_posix_output "printf d" 'printf "%d\n" 42'
compare_posix_output "printf x" 'printf "%x\n" 255'
compare_posix_output "printf o" 'printf "%o\n" 8'
compare_posix_output "printf width" 'printf "%5d\n" 42'
compare_posix_output "printf left" 'printf "%-5d|\n" 42'
compare_posix_output "printf zero" 'printf "%05d\n" 42'

# ============================================================================
# TEST BUILTIN
# ============================================================================

section "5. TEST NUMERIC OPERATORS"
compare_posix_output "test eq" '[ 5 -eq 5 ]; echo $?'
compare_posix_output "test ne" '[ 5 -ne 3 ]; echo $?'
compare_posix_output "test lt" '[ 3 -lt 5 ]; echo $?'
compare_posix_output "test gt" '[ 5 -gt 3 ]; echo $?'
compare_posix_output "test le" '[ 5 -le 5 ]; echo $?'
compare_posix_output "test ge" '[ 5 -ge 5 ]; echo $?'

section "6. TEST STRING OPERATORS"
compare_posix_output "test z empty" '[ -z "" ]; echo $?'
compare_posix_output "test z nonempty" '[ -z "x" ]; echo $?'
compare_posix_output "test n empty" '[ -n "" ]; echo $?'
compare_posix_output "test n nonempty" '[ -n "x" ]; echo $?'
compare_posix_output "test str eq" '[ "a" = "a" ]; echo $?'
compare_posix_output "test str ne" '[ "a" != "b" ]; echo $?'

section "7. TEST FILE OPERATORS"
compare_posix_output "test f" '[ -f /etc/passwd ]; echo $?'
compare_posix_output "test d" '[ -d /tmp ]; echo $?'
compare_posix_output "test e" '[ -e /tmp ]; echo $?'
compare_posix_output "test r" '[ -r /etc/passwd ]; echo $?'
compare_posix_output "test x" '[ -x /bin/sh ]; echo $?'
compare_posix_output "test s" 'echo x > /tmp/ts$$; [ -s /tmp/ts$$ ]; echo $?; rm /tmp/ts$$'

section "8. TEST COMPOUND"
compare_posix_output "test and" '[ -d /tmp -a -f /etc/passwd ]; echo $?'
compare_posix_output "test or" '[ -d /nonexistent -o -f /etc/passwd ]; echo $?'
compare_posix_output "test not" '[ ! -d /nonexistent ]; echo $?'
compare_posix_output "test paren" '[ \( -d /tmp \) ]; echo $?'

# ============================================================================
# TYPE AND COMMAND BUILTINS
# ============================================================================

section "9. TYPE BUILTIN"
compare_posix_output "type builtin" "type echo | grep -ci 'builtin\\|built-in\\|shell builtin'"
compare_posix_output "type function" "f() { :; }; type f | grep -c function"
compare_posix_output "type external" "type cat | grep -c '/'"
compare_posix_exit_code "type nonexistent" "type nonexistent_$$ 2>/dev/null"

section "10. COMMAND BUILTIN"
compare_posix_output "command v" 'command -v echo | grep -c echo'
compare_posix_output "command V" 'command -V echo 2>/dev/null | grep -c echo'
compare_posix_output "command p" 'command -p echo test'

# ============================================================================
# SET BUILTIN
# ============================================================================

section "11. SET BUILTIN"
compare_posix_output "set -- clears positionals" "set -- a b; set --; echo \$#"
compare_posix_error "set -- with empty" "set -- ''; echo \$# |\$1|"
compare_posix_output "set -- with spaces" "set -- 'a b' 'c d'; echo \$1"
compare_posix_output "set without args shows vars" "X=1; set | grep -c '^X='"
compare_posix_output "set -o lists options" "set -o 2>&1 | wc -l"
compare_posix_output "set args" 'set -- a b c; echo $1 $2 $3'
compare_posix_output "set count" 'set -- a b c d e; echo $#'
compare_posix_output "set all" 'set -- x y z; echo "$@"'
compare_posix_output "set star" 'set -- x y z; echo "$*"'

# ============================================================================
# SHIFT BUILTIN
# ============================================================================

section "12. SHIFT BUILTIN"
compare_posix_output "shift basic" 'set -- a b c; shift; echo $1'
compare_posix_output "shift count" 'set -- a b c; shift; echo $#'
compare_posix_output "shift 2" 'set -- a b c d; shift 2; echo $1'
compare_posix_output "shift with count" "set -- a b c d e; shift 3; echo \$1"
compare_posix_exit_code "shift too many" "set -- a b; shift 5 2>/dev/null"
compare_posix_output "shift zero" "set -- a b c; shift 0; echo \$#"
compare_posix_output "shift all" "set -- a b c; shift 3; echo \$#"
compare_posix_exit_code "shift with no args" "set --; shift 2>/dev/null"

# ============================================================================
# EVAL BUILTIN
# ============================================================================

section "13. EVAL BUILTIN"
compare_posix_output "eval with semicolons" "eval 'echo a; echo b' | wc -l"
compare_posix_output "eval with pipes" "eval 'echo test | cat'"
compare_posix_output "eval with redirects" "eval 'echo test > /tmp/posix_gaps_eval_$$'; cat /tmp/posix_gaps_eval_$$; rm -f /tmp/posix_gaps_eval_$$"
compare_posix_output "eval double expansion" "VAR='echo \$HOME'; eval \$VAR | grep -c /"
compare_posix_output "eval empty string" "eval ''; echo ok"
compare_posix_output "nested eval" "eval eval echo nested"

# ============================================================================
# READONLY AND UNSET
# ============================================================================

section "14. READONLY"
compare_posix_exit_code "readonly then unset fails" "readonly X=1; unset X 2>/dev/null"
compare_posix_exit_code "export readonly" "readonly X=1; export X; sh -c 'echo \$X' | grep -c 1"
compare_posix_output "readonly in subshell" "(readonly Y=2; echo \$Y); readonly | grep -c Y || echo 0"
compare_posix_output "readonly basic" 'readonly Y=5; echo $Y'
compare_posix_output "readonly list" 'readonly | grep -c .'

section "15. UNSET"
compare_posix_output "unset var" 'x=5; unset x; echo ${x:-unset}'
compare_posix_output "unset func" 'f() { echo f; }; unset -f f; f 2>/dev/null || echo unset'
compare_posix_output "unset v flag" 'x=5; unset -v x; echo ${x:-unset}'

# ============================================================================
# EXPORT
# ============================================================================

section "16. EXPORT"
compare_posix_output "export basic" 'export X=5; sh -c "echo \$X"'
compare_posix_output "export list" 'export | grep -c ='

# ============================================================================
# RETURN AND DOT
# ============================================================================

section "17. RETURN BUILTIN"
compare_posix_output "return without function" "return 2>/dev/null || echo ok"
compare_posix_output "return value preserved" "f() { return 42; }; f; echo \$?"
compare_posix_output "return in sourced script" "echo 'return 7' > /tmp/posix_gaps_source_$$; . /tmp/posix_gaps_source_$$ 2>/dev/null || echo \$?; rm -f /tmp/posix_gaps_source_$$"

section "18. DOT BUILTIN"
compare_posix_output "source with PATH search" "echo 'echo sourced' > /tmp/posix_gaps_dot_$$; PATH=/tmp:\$PATH; . posix_gaps_dot_$$ 2>/dev/null || echo 'not found'; rm -f /tmp/posix_gaps_dot_$$"
compare_posix_exit_code "source nonexistent" ". /tmp/posix_gaps_nonexistent_$$ 2>/dev/null"
compare_posix_output "source preserves variables" "echo 'A=from_source' > /tmp/posix_gaps_dot2_$$; . /tmp/posix_gaps_dot2_$$; echo \$A; rm -f /tmp/posix_gaps_dot2_$$"

# ============================================================================
# GETOPTS
# ============================================================================

section "19. GETOPTS"
compare_posix_output "getopts basic" "set -- -a test; getopts 'a:' opt; echo \$opt"
compare_posix_output "getopts OPTARG" "set -- -a value; getopts 'a:' opt; echo \$OPTARG"
compare_posix_output "getopts OPTIND" "set -- -a -b; getopts 'ab' opt; echo \$OPTIND"
compare_posix_output "getopts invalid option" "set -- -z; getopts 'ab' opt 2>/dev/null; echo \$opt | grep -c '?'"

# ============================================================================
# UMASK
# ============================================================================

section "20. UMASK"
compare_posix_output "umask get" "umask | grep -c '^[0-9]*\$'"
compare_posix_output "umask set and get" "old=\$(umask); umask 022; umask; umask \$old | head -1"

# ============================================================================
# HASH
# ============================================================================

section "21. HASH"
compare_posix_exit_code "hash command" "hash echo 2>/dev/null"
compare_posix_exit_code "hash -r clears" "hash -r"
compare_posix_exit_code "hash nonexistent" "hash nonexistent_cmd_$$ 2>/dev/null"

# ============================================================================
# TIMES
# ============================================================================

section "22. TIMES"
compare_posix_output "times output format" "times | wc -l"
compare_posix_exit_code "times exit status" "times >/dev/null"

# ============================================================================
# TRAP
# ============================================================================

section "23. TRAP"
compare_posix_output "trap with signal number" "trap 'echo sig' 15; trap | grep -c 15"
compare_posix_output "trap with multiple signals" "trap 'echo multi' INT TERM; trap | grep -c 'echo multi'"
compare_posix_output "trap ignore signal" "trap '' INT; trap | grep INT | grep -c ''"

# ============================================================================
# EXIT
# ============================================================================

section "24. EXIT"
compare_posix_exit_code "exit with status" "sh -c 'exit 42'"
compare_posix_exit_code "exit in subshell" "(exit 7); echo \$?"

# ============================================================================
# VARIABLE OPERATIONS
# ============================================================================

section "25. VARIABLE ASSIGNMENT"
compare_posix_output "var simple" 'x=5; echo $x'
compare_posix_output "var empty" 'x=; echo "[$x]"'
compare_posix_output "var quoted" 'x="a b"; echo "$x"'
compare_posix_output "var concat" 'x=hel; y=lo; echo $x$y'
compare_posix_output "var braces" 'x=val; echo ${x}'

section "26. FUNCTION SCOPE"
compare_posix_output "func global" 'x=global; f() { x=func; }; f; echo $x'
compare_posix_output "func params" 'f() { echo $# $1 $2; }; f a b c'
compare_posix_output "func shift" 'f() { shift; echo $1; }; f a b c'

# ============================================================================
# MISCELLANEOUS
# ============================================================================

section "27. MISCELLANEOUS EDGE CASES"
compare_posix_output "empty command in list" ": ; echo ok"
compare_posix_output "whitespace only" "   ; echo ok"
compare_posix_output "multiple empty commands" ": ; : ; echo ok"
compare_posix_output "empty string as command" "'' 2>/dev/null || echo ok"

section "28. PIPELINES"
compare_posix_output "five stage pipeline" "echo test | cat | cat | cat | cat"
compare_posix_exit_code "pipeline with negation" "! false | false"
compare_posix_output "pipeline with subshell" "(echo a; echo b) | wc -l"
compare_posix_output "pipeline with brace group" "{ echo x; echo y; } | wc -l"

# Summary
printf "\n==========================================\n"
printf "BUILTINS GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
