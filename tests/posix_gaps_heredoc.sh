#!/bin/sh
# =====================================
# POSIX Here-Document Gap Tests
# =====================================
# Tests for POSIX here-document functionality
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-heredoc]"
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

compare_posix_exit_code() {
    test_name="$1"; command="$2"
    "$BASH_REF" -c "$command" >/dev/null 2>&1; posix_code=$?
    "$FORTSH_BIN" -c "$command" >/dev/null 2>&1; fortsh_code=$?
    if [ "$posix_code" = "$fortsh_code" ]; then pass "$test_name"
    else fail "$test_name" "exit $posix_code" "exit $fortsh_code"; fi
}

# ============================================================================
# HEREDOC TESTS
# ============================================================================

section "1. BASIC HEREDOC"
compare_posix_output "simple" 'cat <<EOF
hello
EOF'
compare_posix_output "multiline" 'cat <<EOF
line1
line2
EOF'
compare_posix_output "empty" 'cat <<EOF
EOF'

section "2. VARIABLE EXPANSION"
compare_posix_output "var expansion" 'x=value; cat <<EOF
$x
EOF'
compare_posix_output "var with text" 'X=world; cat <<EOF
hello $X
EOF'

section "3. COMMAND SUBSTITUTION"
compare_posix_output "cmd sub" 'cat <<EOF
$(echo hello)
EOF'

section "4. ARITHMETIC EXPANSION"
compare_posix_output "arith" 'cat <<EOF
$((1+2))
EOF'

section "5. QUOTED DELIMITER"
compare_posix_output "single quoted" "cat <<'EOF'
\$x \$(cmd)
EOF"
compare_posix_output "double quoted" 'cat <<"EOF"
$x $(cmd)
EOF'
compare_posix_output "quoted no expand" "cat <<'EOF'
\$notvar
EOF"

section "6. TAB STRIPPING (<<-)"
compare_posix_output "dash strips tabs" "cat <<-EOF
	line1
		line2
	line3
EOF"
compare_posix_output "dash mixed" "cat <<-EOF
	tab_line
    space_line
EOF"
compare_posix_output "dash with vars" "VAR=test; cat <<-EOF
	value=\$VAR
	end
EOF"
compare_posix_output "dash quoted" "cat <<-'EOF'
	\$VAR
	literal
EOF"
compare_posix_output "dash simple" 'cat <<-EOF
	tabbed
	EOF'

section "7. MULTIPLE HEREDOCS"
compare_posix_output "double heredoc" 'cat <<EOF1; cat <<EOF2
first
EOF1
second
EOF2'

# Summary
printf "\n==========================================\n"
printf "HEREDOC GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
