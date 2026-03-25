#!/bin/sh
# =====================================
# POSIX Control Flow Gap Tests
# =====================================
# Tests for POSIX control flow constructs
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-control]"
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

normalize_output() { sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'; }

compare_posix_output() {
    test_name="$1"; command="$2"
    posix_out=$("$BASH_REF" -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

# ============================================================================
# IF STATEMENTS
# ============================================================================

section "1. IF BASIC"
compare_posix_output "if true" 'if true; then echo yes; fi'
compare_posix_output "if false" 'if false; then echo yes; fi; echo done'
compare_posix_output "if else" 'if false; then echo no; else echo yes; fi'
compare_posix_output "if elif" 'if false; then echo 1; elif true; then echo 2; fi'
compare_posix_output "if elif else" 'if false; then echo 1; elif false; then echo 2; else echo 3; fi'
compare_posix_output "if nested" 'if true; then if true; then echo deep; fi; fi'

section "2. IF CONDITIONS"
compare_posix_output "if and" 'if true && true; then echo yes; fi'
compare_posix_output "if or" 'if false || true; then echo yes; fi'
compare_posix_output "if not" 'if ! false; then echo yes; fi'

# ============================================================================
# FOR LOOPS
# ============================================================================

section "3. FOR BASIC"
compare_posix_output "for simple" 'for i in a b c; do echo $i; done'
compare_posix_output "for numbers" 'for i in 1 2 3; do echo $i; done | wc -l'
compare_posix_output "for empty" 'for i in; do echo $i; done; echo done'
compare_posix_output "for single" "for i in one; do echo \$i; done"

section "4. FOR EDGE CASES"
compare_posix_output "for with break" 'for i in 1 2 3; do echo $i; break; done'
compare_posix_output "for with continue" 'for i in 1 2 3; do if [ $i = 2 ]; then continue; fi; echo $i; done'
# Inline test with debug output for CI diagnosis
_glob_cmd="touch /tmp/posix_gaps_for1_$$.txt /tmp/posix_gaps_for2_$$.txt /tmp/posix_gaps_for3_$$.txt 2>/dev/null; for f in /tmp/posix_gaps_for*_$$.txt; do test -f \$f && echo yes; done | head -1; rm -f /tmp/posix_gaps_for*_$$.txt"
_glob_posix=$("$BASH_REF" -c "$_glob_cmd" 2>&1)
_glob_fortsh=$("$FORTSH_BIN" -c "$_glob_cmd" 2>&1)
_glob_debug="[DEBUG glob] posix_hex=[$(printf '%s' "$_glob_posix" | od -A n -t x1 | tr -d '\n')] fortsh_hex=[$(printf '%s' "$_glob_fortsh" | od -A n -t x1 | tr -d '\n')] posix_raw=[$_glob_posix] fortsh_raw=[$_glob_fortsh]"
_glob_posix_n=$(printf '%s' "$_glob_posix" | normalize_output)
_glob_fortsh_n=$(printf '%s' "$_glob_fortsh" | normalize_output)
if [ "$_glob_posix_n" = "$_glob_fortsh_n" ]; then pass "for glob expansion"
else fail "for glob expansion" "$_glob_posix_n" "$_glob_fortsh_n"; fi
compare_posix_output "for preserves IFS" "IFS=:; for i in a b c; do echo \$i; done; echo \$IFS | od -A n -t x1 | grep -c 3a"

# ============================================================================
# WHILE LOOPS
# ============================================================================

section "5. WHILE BASIC"
compare_posix_output "while basic" 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done'
compare_posix_output "while false" 'while false; do echo no; done; echo done'
compare_posix_output "while break" 'while true; do echo once; break; done'
compare_posix_output "while count" 'n=3; while [ $n -gt 0 ]; do n=$((n-1)); done; echo $n'

section "6. WHILE EDGE CASES"
compare_posix_output "while true with break" "i=0; while true; do i=\$((i+1)); test \$i -eq 3 && break; done; echo \$i"
compare_posix_output "while with exit status" "i=5; while [ \$i -gt 0 ]; do i=\$((i-1)); done; echo \$?"

# ============================================================================
# UNTIL LOOPS
# ============================================================================

section "7. UNTIL BASIC"
compare_posix_output "until basic" 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done'
compare_posix_output "until true" 'until true; do echo no; done; echo done'
compare_posix_output "until count" 'n=0; until [ $n -eq 3 ]; do n=$((n+1)); done; echo $n'

section "8. UNTIL EDGE CASES"
compare_posix_output "until false with break" "i=0; until false; do i=\$((i+1)); test \$i -eq 3 && break; done; echo \$i"
compare_posix_output "until complex condition" "i=0; until [ \$i -gt 3 ] && [ \$i -lt 10 ]; do i=\$((i+1)); done; echo \$i"

# ============================================================================
# CASE STATEMENTS
# ============================================================================

section "9. CASE BASIC"
compare_posix_output "case single" 'case x in x) echo yes;; esac'
compare_posix_output "case default" 'case y in x) echo no;; *) echo yes;; esac'
compare_posix_output "case multi" 'case b in a|b|c) echo abc;; esac'
compare_posix_output "case glob" 'case abc in a*) echo yes;; esac'
compare_posix_output "case nested" 'case x in x) case y in y) echo deep;; esac;; esac'

section "10. CASE PATTERNS"
compare_posix_output "case glob star" 'case abc in a*) echo star;; esac'
compare_posix_output "case glob question" 'case abc in a?c) echo match;; esac'
compare_posix_output "case glob bracket" 'case abc in [a-z]*) echo match;; esac'
compare_posix_output "case no match" 'case x in y) echo no;; esac; echo done'
compare_posix_output "case empty" 'case "" in "") echo empty;; esac'
compare_posix_output "case with var" 'x=test; case $x in test) echo yes;; esac'
compare_posix_output "case quoted" 'case "a b" in "a b") echo space;; esac'

section "11. CASE EDGE CASES"
compare_posix_output "case empty pattern" "x=''; case \$x in '') echo empty;; esac"
compare_posix_output "case with quotes" "x='a b'; case \$x in 'a b') echo match;; esac"
compare_posix_output "case glob vs literal" "x='*'; case \$x in '*') echo literal;; esac"
compare_posix_output "case bracket range" "x=b; case \$x in [a-c]) echo range;; esac"
compare_posix_output "case multiple patterns order" "x=a; case \$x in a|b) echo first;; a) echo second;; esac"
compare_posix_output "case with variable pattern" "P='a*'; x=abc; case \$x in \$P) echo var_pattern;; esac"

# ============================================================================
# BREAK AND CONTINUE
# ============================================================================

section "12. BREAK"
compare_posix_output "break simple" 'for i in 1 2 3; do echo $i; break; done'
compare_posix_output "break nested" 'for i in 1 2; do for j in a b; do echo $i$j; break; done; done'
compare_posix_output "break 2" 'for i in 1 2; do for j in a b; do echo $i$j; break 2; done; done'

section "13. CONTINUE"
compare_posix_output "continue simple" 'for i in 1 2 3; do if [ $i = 2 ]; then continue; fi; echo $i; done'
compare_posix_output "continue 2" 'for i in 1 2; do for j in a b; do if [ $j = a ]; then continue 2; fi; echo $i$j; done; done'

section "14. BREAK/CONTINUE EDGE CASES"
compare_posix_output "break with level 0" "for i in 1 2; do break 0 2>/dev/null || break; echo \$i; done || echo ok"
compare_posix_output "break level too high" "for i in 1 2; do break 10 2>/dev/null || break; echo \$i; done || echo done"
compare_posix_output "continue with level" "for i in 1 2; do for j in a b; do continue 2 2>/dev/null || continue; echo \$i\$j; done; done || echo ok"
compare_posix_output "break outside loop" "break 2>/dev/null || echo ok"
compare_posix_output "continue outside loop" "continue 2>/dev/null || echo ok"

# ============================================================================
# FUNCTIONS
# ============================================================================

section "15. FUNCTION DEFINITION"
compare_posix_output "func basic" 'f() { echo hello; }; f'
compare_posix_output "func args" 'f() { echo $1 $2; }; f a b'
compare_posix_output "func return" 'f() { return 5; }; f; echo $?'
compare_posix_output "func positional" 'f() { echo $# $@; }; f a b c'

section "16. RETURN AND EXIT"
compare_posix_output "return basic" 'f() { return; }; f; echo $?'
compare_posix_output "return code" 'f() { return 5; }; f; echo $?'
compare_posix_output "exit subshell" '(exit 5); echo $?'
compare_posix_output "exit code" '(exit 42); echo $?'

# ============================================================================
# SUBSHELL AND BRACE GROUPS
# ============================================================================

section "17. SUBSHELL"
compare_posix_output "subshell basic" '(echo hello)'
compare_posix_output "subshell var" 'x=1; (x=2); echo $x'
compare_posix_output "subshell exit" '(exit 5); echo $?'

section "18. SUBSHELL VARIABLE ISOLATION"
compare_posix_output "subshell doesnt modify parent" "(X=inner); echo \${X:-unset}"
compare_posix_output "subshell inherits variables" "X=outer; (echo \$X)"
compare_posix_output "nested subshells" "X=1; (X=2; (X=3; echo \$X); echo \$X); echo \$X"
compare_posix_output "subshell with exports" "export X=exp; (X=inner; echo \$X); echo \$X"

section "19. BRACE GROUPS"
compare_posix_output "brace basic" '{ echo hello; }'
compare_posix_output "brace var" 'x=1; { x=2; }; echo $x'
compare_posix_output "brace redir" '{ echo a; echo b; } > /tmp/b$$; wc -l < /tmp/b$$; rm /tmp/b$$'
compare_posix_output "brace group modifies parent" "X=1; { X=2; }; echo \$X"
compare_posix_output "brace group with redirects" "{ echo a; echo b; } | wc -l"
compare_posix_output "nested brace groups" "X=1; { { X=2; }; echo \$X; }; echo \$X"

# ============================================================================
# LOGICAL OPERATORS
# ============================================================================

section "20. LOGICAL OPERATORS"
compare_posix_output "and both true" 'true && echo yes'
compare_posix_output "and first false" 'false && echo no; echo done'
compare_posix_output "or first true" 'true || echo no; echo done'
compare_posix_output "or first false" 'false || echo yes'
compare_posix_output "not true" '! true; echo $?'
compare_posix_output "not false" '! false; echo $?'

# ============================================================================
# NESTED LOOPS
# ============================================================================

section "21. NESTED LOOPS"
compare_posix_output "nested for" 'for i in 1 2; do for j in a b; do echo $i$j; done; done | wc -l'
compare_posix_output "loop with pipe" 'for i in 1 2 3; do echo $i; done | head -2'

# Summary
printf "\n==========================================\n"
if [ -n "$_glob_debug" ]; then printf "%s\n" "$_glob_debug"; fi
printf "CONTROL FLOW GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
