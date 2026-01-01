#!/bin/sh
# =====================================
# POSIX Special Parameters Gap Tests
# =====================================
# Tests for POSIX special parameters and expansion
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-special]"
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

normalize_output() { sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'; }

compare_posix_output() {
    test_name="$1"; command="$2"
    posix_out=$(bash -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

# ============================================================================
# SPECIAL PARAMETERS
# ============================================================================

section "1. POSITIONAL PARAMETERS"
compare_posix_output "dollar at" 'set -- a b c; echo "$@"'
compare_posix_output "dollar star" 'set -- a b c; echo "$*"'
compare_posix_output "dollar hash" 'set -- a b c; echo $#'
compare_posix_output "dollar at with IFS" "IFS=:; set -- a b c; echo \"\$*\""
compare_posix_output "dollar star vs at unquoted" "set -- a b c; for x in \$*; do echo \$x; done | wc -l"
compare_posix_output "dollar at quoted iteration" "set -- 'a b' 'c d'; for x in \"\$@\"; do echo \$x; done | wc -l"
compare_posix_output "dollar hash after shift" "set -- a b c; shift; echo \$#"

section "2. SHELL STATUS PARAMETERS"
compare_posix_output "dollar question" 'true; echo $?'
compare_posix_output "dollar pid" 'echo $$ | grep -cE "^[0-9]+$"'
compare_posix_output "dollar zero" 'echo $0 | grep -c .'
compare_posix_output "dollar dash shows options" "echo \$- | grep -c '[a-z]'"
compare_posix_output "dollar dollar is numeric" "echo \$\$ | grep -c '^[0-9]*\$'"
compare_posix_output "dollar zero is set" "echo \${0:-none} | grep -c '.'"

# ============================================================================
# PARAMETER EXPANSION
# ============================================================================

section "3. DEFAULT VALUES"
compare_posix_output "pe default" 'unset x; echo ${x:-default}'
compare_posix_output "pe assign" 'unset x; echo ${x:=assigned}; echo $x'
compare_posix_output "pe error" '(unset x; echo ${x:?msg}) 2>/dev/null; echo $?'
compare_posix_output "pe alt" 'x=val; echo ${x:+alt}'
compare_posix_output "default empty" 'x=""; echo ${x:-default}'
compare_posix_output "default unset" 'unset x; echo ${x:-default}'
compare_posix_output "default set" 'x="value"; echo ${x:-default}'

section "4. STRING LENGTH"
compare_posix_output "pe length" 'x=hello; echo ${#x}'
compare_posix_output "length of empty" 'x=""; echo ${#x}'
compare_posix_output "length of one" 'x="a"; echo ${#x}'
compare_posix_output "length of special" 'x="a b c"; echo ${#x}'

section "5. PATTERN REMOVAL"
compare_posix_output "pe suffix" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "pe prefix" 'x=/path/file; echo ${x##*/}'
compare_posix_output "suffix remove" 'x="file.txt"; echo ${x%.txt}'
compare_posix_output "prefix remove" 'x="prefix_name"; echo ${x#prefix_}'
compare_posix_output "longest suffix" 'x="a.b.c"; echo ${x%%.*}'
compare_posix_output "longest prefix" 'x="a.b.c"; echo ${x##*.}'

section "6. NESTED EXPANSION"
compare_posix_output "nested default" "unset A; B=inner; echo \${A:-\${B}}"
compare_posix_output "nested length" "VAR=hello; echo \${#VAR}"
compare_posix_output "nested pattern removal" "VAR=/usr/local/bin; echo \${VAR#\${VAR%/*}}"
compare_posix_output "multiple expansions" "A=foo; B=bar; echo \${A}\${B}"
compare_posix_output "nested with quotes" "A='a b'; echo \"\${A}\""

# ============================================================================
# IFS SPLITTING
# ============================================================================

section "7. IFS SPLITTING"
compare_posix_output "ifs default" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "ifs colon" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "ifs empty" 'IFS=""; x="abc"; set -- $x; echo $#'
compare_posix_output "ifs star" 'IFS=:; set -- a b c; echo "$*"'

# ============================================================================
# COMMAND SUBSTITUTION
# ============================================================================

section "8. COMMAND SUBSTITUTION"
compare_posix_output "cmdsub basic" 'echo $(echo hello)'
compare_posix_output "cmdsub backtick" 'echo `echo hello`'
compare_posix_output "cmdsub nested" 'echo $(echo $(echo deep))'
compare_posix_output "cmdsub quoted" 'echo "$(echo hello world)"'
compare_posix_output "cmdsub multi" 'echo $(echo a; echo b)'

section "9. COMMAND SUBSTITUTION VARIANTS"
compare_posix_output "cmd sub echo" 'echo $(echo hello)'
compare_posix_output "cmd sub pwd" 'echo $(pwd | grep -c "/")'
compare_posix_output "cmd sub math" 'echo $(($(echo 5) + 3))'
compare_posix_output "cmd sub in var" 'x=$(echo test); echo $x'
compare_posix_output "backtick equiv" 'echo `echo hello`'
compare_posix_output "cmd sub whitespace" 'echo "$(echo "  spaces  ")"'
compare_posix_output "cmd sub multiline" 'echo "$(echo -e "a\nb")" | wc -l'
compare_posix_output "cmd sub exit code" '$(exit 0); echo $?'
compare_posix_output "cmd sub fail code" '$(exit 1); echo $?'

# ============================================================================
# TILDE EXPANSION
# ============================================================================

section "10. TILDE EXPANSION"
compare_posix_output "tilde in assignment" "VAR=~/test; echo \$VAR | grep -c '^/'"
compare_posix_output "tilde in middle no expand" "echo a~b | grep -c '~'"

# ============================================================================
# VARIABLE ASSIGNMENT CONTEXTS
# ============================================================================

section "11. VARIABLE ASSIGNMENT"
compare_posix_output "simple assign" 'x=5; echo $x'
compare_posix_output "multi assign" 'x=1 y=2 z=3; echo $x $y $z'
compare_posix_output "assign in subshell" '(x=inner; echo $x); echo ${x:-unset}'
compare_posix_output "assign export" 'export X=exported; printenv X 2>/dev/null || echo $X'
compare_posix_output "assign readonly" 'readonly X=constant; echo $X'
compare_posix_output "assign with cmd" 'X=$(echo value); echo $X'
compare_posix_output "assign quoted" 'X="with spaces"; echo "$X"'
compare_posix_output "assign empty" 'X=""; echo "[$X]"'
compare_posix_output "assign special" 'X="$HOME"; echo ${X:+set}'

# ============================================================================
# PIPELINES
# ============================================================================

section "12. PIPELINES"
compare_posix_output "pipe two" 'echo hello | cat'
compare_posix_output "pipe three" 'echo hello | cat | cat'
compare_posix_output "pipe with grep" 'echo hello | grep -o h'
compare_posix_output "pipe word count" 'echo "a b c" | wc -w'
compare_posix_output "pipe line count" 'printf "a\nb\nc\n" | wc -l'
compare_posix_output "pipe sort" 'printf "c\na\nb\n" | sort | head -1'
compare_posix_output "pipe uniq" 'printf "a\na\nb\n" | uniq | wc -l'
compare_posix_output "pipe head" 'printf "1\n2\n3\n4\n5\n" | head -2'
compare_posix_output "pipe tail" 'printf "1\n2\n3\n4\n5\n" | tail -2'
compare_posix_output "pipe tr" 'echo abc | tr a-z A-Z'

# ============================================================================
# COMMAND NAME RESOLUTION
# ============================================================================

section "13. COMMAND NAME RESOLUTION"
compare_posix_output "function overrides echo" "echo() { printf 'function\n'; }; echo test | grep -c function"
compare_posix_output "command -v finds function" "func() { :; }; command -v func | grep -c func"
compare_posix_output "command bypasses function" "echo() { printf 'func\n'; }; command echo test"

# Summary
printf "\n==========================================\n"
printf "SPECIAL PARAMETERS GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
