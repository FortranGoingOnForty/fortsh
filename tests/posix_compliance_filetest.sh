#!/bin/sh
# =====================================
# POSIX Compliance File Test Operators Suite for fortsh
# =====================================
# Tests test/[ builtin file and string operators per IEEE Std 1003.1-2017
# Section: Shell Command Language - Conditional Expressions

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-filetest]"
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
        printf "  expected: %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  got:      %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${YELLOW}⊘ SKIP${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s - %s\n" "$1" "$2"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n"
    printf "${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Create test directory with test files
setup_test_files() {
    TEST_DIR="/tmp/fortsh_filetest_$$"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR" || exit 1

    # Create various test files
    echo "content" > regular_file
    mkdir test_dir
    touch empty_file
    chmod 755 executable_file 2>/dev/null || touch executable_file
    chmod +x executable_file 2>/dev/null
    chmod 000 unreadable_file 2>/dev/null || touch unreadable_file
    ln -s regular_file symlink_file 2>/dev/null
    ln -s nonexistent broken_link 2>/dev/null
    mkfifo named_pipe 2>/dev/null || true
}

cleanup_test_files() {
    cd /
    chmod 644 "$TEST_DIR/unreadable_file" 2>/dev/null
    rm -rf "$TEST_DIR"
}

# Trap to ensure cleanup
trap cleanup_test_files EXIT

setup_test_files

# =====================================
section "369. FILE EXISTENCE AND TYPE TESTS"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -e regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -e file ] exists test (regular file)"
else
    fail "[ -e file ] exists test (regular file)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -e test_dir ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -e dir ] exists test (directory)"
else
    fail "[ -e dir ] exists test (directory)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -e nonexistent ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -e nonexistent ] returns false"
else
    fail "[ -e nonexistent ] returns false" "no" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -f regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -f file ] regular file test"
else
    fail "[ -f file ] regular file test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -f test_dir ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -f dir ] returns false for directory"
else
    fail "[ -f dir ] returns false for directory" "no" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -d test_dir ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -d dir ] directory test"
else
    fail "[ -d dir ] directory test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -d regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -d file ] returns false for file"
else
    fail "[ -d file ] returns false for file" "no" "$result"
fi

# =====================================
section "370. SYMBOLIC LINK TESTS"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -L symlink_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -L symlink ] symbolic link test"
else
    fail "[ -L symlink ] symbolic link test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -h symlink_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -h symlink ] symbolic link test (alias)"
else
    fail "[ -h symlink ] symbolic link test (alias)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -L regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -L regular ] returns false for non-symlink"
else
    fail "[ -L regular ] returns false for non-symlink" "no" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -L broken_link ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -L broken_link ] true for broken symlink"
else
    fail "[ -L broken_link ] true for broken symlink" "yes" "$result"
fi

# =====================================
section "371. FILE PERMISSION TESTS"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -r regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -r file ] readable test"
else
    fail "[ -r file ] readable test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -w regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -w file ] writable test"
else
    fail "[ -w file ] writable test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -x executable_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -x file ] executable test"
else
    fail "[ -x file ] executable test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -x regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -x non-exec ] returns false"
else
    fail "[ -x non-exec ] returns false" "no" "$result"
fi

# =====================================
section "372. FILE SIZE TESTS"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -s regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -s file ] size greater than zero"
else
    fail "[ -s file ] size greater than zero" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -s empty_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -s empty ] returns false for empty file"
else
    fail "[ -s empty ] returns false for empty file" "no" "$result"
fi

# =====================================
section "373. STRING TESTS"
# =====================================

result=$("$FORTSH_BIN" -c '[ -z "" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -z \"\" ] zero length string"
else
    fail "[ -z \"\" ] zero length string" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -z "hello" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -z str ] returns false for non-empty"
else
    fail "[ -z str ] returns false for non-empty" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -n "hello" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -n str ] non-zero length string"
else
    fail "[ -n str ] non-zero length string" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -n "" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -n \"\" ] returns false for empty"
else
    fail "[ -n \"\" ] returns false for empty" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "hello" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ string ] implicit non-empty test"
else
    fail "[ string ] implicit non-empty test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ \"\" ] empty string is false"
else
    fail "[ \"\" ] empty string is false" "no" "$result"
fi

# =====================================
section "374. STRING COMPARISON TESTS"
# =====================================

result=$("$FORTSH_BIN" -c '[ "abc" = "abc" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ str = str ] string equality"
else
    fail "[ str = str ] string equality" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "abc" = "xyz" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ str1 = str2 ] returns false for different"
else
    fail "[ str1 = str2 ] returns false for different" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "abc" != "xyz" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ str1 != str2 ] string inequality"
else
    fail "[ str1 != str2 ] string inequality" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "abc" != "abc" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ str != str ] returns false for same"
else
    fail "[ str != str ] returns false for same" "no" "$result"
fi

# =====================================
section "375. NUMERIC COMPARISON TESTS"
# =====================================

result=$("$FORTSH_BIN" -c '[ 5 -eq 5 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n -eq n ] numeric equality"
else
    fail "[ n -eq n ] numeric equality" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -eq 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ n1 -eq n2 ] returns false for different"
else
    fail "[ n1 -eq n2 ] returns false for different" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -ne 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n1 -ne n2 ] numeric inequality"
else
    fail "[ n1 -ne n2 ] numeric inequality" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -gt 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n1 -gt n2 ] greater than"
else
    fail "[ n1 -gt n2 ] greater than" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 3 -gt 5 ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ n1 -gt n2 ] returns false when not greater"
else
    fail "[ n1 -gt n2 ] returns false when not greater" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -ge 5 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n -ge n ] greater or equal (equal)"
else
    fail "[ n -ge n ] greater or equal (equal)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -ge 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n1 -ge n2 ] greater or equal (greater)"
else
    fail "[ n1 -ge n2 ] greater or equal (greater)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 3 -lt 5 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n1 -lt n2 ] less than"
else
    fail "[ n1 -lt n2 ] less than" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -lt 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ n1 -lt n2 ] returns false when not less"
else
    fail "[ n1 -lt n2 ] returns false when not less" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 5 -le 5 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n -le n ] less or equal (equal)"
else
    fail "[ n -le n ] less or equal (equal)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 3 -le 5 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ n1 -le n2 ] less or equal (less)"
else
    fail "[ n1 -le n2 ] less or equal (less)" "yes" "$result"
fi

# =====================================
section "376. LOGICAL OPERATORS"
# =====================================

result=$("$FORTSH_BIN" -c '[ ! -e /nonexistent ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ ! expr ] negation"
else
    fail "[ ! expr ] negation" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ ! -d /tmp ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ ! expr ] negation of true"
else
    fail "[ ! expr ] negation of true" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -d /tmp -a -e /tmp ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ expr -a expr ] logical AND (both true)"
else
    fail "[ expr -a expr ] logical AND (both true)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -d /tmp -a -e /nonexistent ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ expr -a expr ] logical AND (one false)"
else
    fail "[ expr -a expr ] logical AND (one false)" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -e /nonexistent -o -d /tmp ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ expr -o expr ] logical OR (one true)"
else
    fail "[ expr -o expr ] logical OR (one true)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -e /nonexistent -o -e /alsononexistent ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ expr -o expr ] logical OR (both false)"
else
    fail "[ expr -o expr ] logical OR (both false)" "no" "$result"
fi

# =====================================
section "377. FILE COMPARISON TESTS"
# =====================================

# Create files with different timestamps
touch "$TEST_DIR/older_file"
sleep 1
touch "$TEST_DIR/newer_file"

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ newer_file -nt older_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ f1 -nt f2 ] newer than test"
else
    fail "[ f1 -nt f2 ] newer than test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ older_file -ot newer_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ f1 -ot f2 ] older than test"
else
    fail "[ f1 -ot f2 ] older than test" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ regular_file -ef regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ f -ef f ] same file test"
else
    fail "[ f -ef f ] same file test" "yes" "$result"
fi

# =====================================
section "378. TEST COMMAND FORM"
# =====================================

result=$("$FORTSH_BIN" -c 'test -d /tmp && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test -d dir (test command form)"
else
    fail "test -d dir (test command form)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'test "hello" = "hello" && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test str = str (test command form)"
else
    fail "test str = str (test command form)" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'test 5 -gt 3 && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "test n1 -gt n2 (test command form)"
else
    fail "test n1 -gt n2 (test command form)" "yes" "$result"
fi

# =====================================
section "379. SPECIAL FILE TYPES"
# =====================================

# Named pipe test (if created successfully)
if [ -p "$TEST_DIR/named_pipe" ]; then
    result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -p named_pipe ] && echo yes || echo no' 2>&1)
    if [ "$result" = "yes" ]; then
        pass "[ -p fifo ] named pipe test"
    else
        fail "[ -p fifo ] named pipe test" "yes" "$result"
    fi
else
    skip "[ -p fifo ] named pipe test" "mkfifo not available"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && [ -p regular_file ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -p regular ] returns false for non-pipe"
else
    fail "[ -p regular ] returns false for non-pipe" "no" "$result"
fi

# Terminal test
result=$("$FORTSH_BIN" -c '[ -t 0 ] && echo yes || echo no' 2>&1)
# Since we're running non-interactively, stdin is not a terminal
if [ "$result" = "no" ]; then
    pass "[ -t 0 ] non-terminal stdin"
else
    fail "[ -t 0 ] non-terminal stdin" "no" "$result"
fi

# =====================================
section "380. EDGE CASES"
# =====================================

result=$("$FORTSH_BIN" -c '[ ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ ] empty test returns false"
else
    fail "[ ] empty test returns false" "no" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; [ -n "$x" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -n \"\$empty\" ] with empty variable"
else
    fail "[ -n \"\$empty\" ] with empty variable" "no" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="hello"; [ -n "$x" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -n \"\$var\" ] with non-empty variable"
else
    fail "[ -n \"\$var\" ] with non-empty variable" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "=" = "=" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ \"=\" = \"=\" ] equals sign as string"
else
    fail "[ \"=\" = \"=\" ] equals sign as string" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "-n" = "-n" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ \"-n\" = \"-n\" ] operator as string"
else
    fail "[ \"-n\" = \"-n\" ] operator as string" "yes" "$result"
fi

# =====================================
section "381. COMPLEX TEST EXPRESSIONS"
# =====================================

result=$("$FORTSH_BIN" -c '[ 1 -eq 1 -a 2 -eq 2 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ a -a b ] both true"
else
    fail "[ a -a b ] both true" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 1 -eq 1 -a 2 -eq 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ a -a b ] second false"
else
    fail "[ a -a b ] second false" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 1 -eq 2 -o 2 -eq 2 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ a -o b ] second true"
else
    fail "[ a -o b ] second true" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 1 -eq 2 -o 3 -eq 4 ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ a -o b ] both false"
else
    fail "[ a -o b ] both false" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ ! 1 -eq 2 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ ! expr ] negates false"
else
    fail "[ ! expr ] negates false" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ ! 1 -eq 1 ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ ! expr ] negates true"
else
    fail "[ ! expr ] negates true" "no" "$result"
fi

# =====================================
section "382. PARENTHESES IN TEST"
# =====================================

result=$("$FORTSH_BIN" -c '[ \( 1 -eq 1 \) ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ \\( expr \\) ] parentheses"
else
    fail "[ \\( expr \\) ] parentheses" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ \( 1 -eq 1 -o 2 -eq 3 \) -a 3 -eq 3 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ \\( a -o b \\) -a c ] complex grouping"
else
    fail "[ \\( a -o b \\) -a c ] complex grouping" "yes" "$result"
fi

# =====================================
section "383. STRING LENGTH COMPARISONS"
# =====================================

result=$("$FORTSH_BIN" -c '[ -z "" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -z \"\" ] empty string is zero length"
else
    fail "[ -z \"\" ] empty string is zero length" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -z "x" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -z \"x\" ] non-empty has length"
else
    fail "[ -z \"x\" ] non-empty has length" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -n "" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -n \"\" ] empty has no length"
else
    fail "[ -n \"\" ] empty has no length" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -n "abc" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -n \"abc\" ] string has length"
else
    fail "[ -n \"abc\" ] string has length" "yes" "$result"
fi

# =====================================
section "384. NUMERIC EDGE CASES"
# =====================================

result=$("$FORTSH_BIN" -c '[ 0 -eq 0 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ 0 -eq 0 ] zero equals zero"
else
    fail "[ 0 -eq 0 ] zero equals zero" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -5 -lt 0 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -5 -lt 0 ] negative less than zero"
else
    fail "[ -5 -lt 0 ] negative less than zero" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ -10 -gt -20 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -10 -gt -20 ] negative comparisons"
else
    fail "[ -10 -gt -20 ] negative comparisons" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 999999 -gt 1 ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ large -gt 1 ] large numbers"
else
    fail "[ large -gt 1 ] large numbers" "yes" "$result"
fi

# =====================================
section "385. STRING VS NUMERIC"
# =====================================

result=$("$FORTSH_BIN" -c '[ "10" = "10" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ \"10\" = \"10\" ] string comparison"
else
    fail "[ \"10\" = \"10\" ] string comparison" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c '[ "10" = "010" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ \"10\" = \"010\" ] string differs from numeric"
else
    fail "[ \"10\" = \"010\" ] string differs from numeric" "no" "$result"
fi

result=$("$FORTSH_BIN" -c '[ 10 -eq 010 ] && echo yes || echo no' 2>&1)
# Numeric comparison - may or may not treat 010 as octal
if [ "$result" = "yes" ] || [ "$result" = "no" ]; then
    pass "[ 10 -eq 010 ] numeric comparison"
else
    fail "[ 10 -eq 010 ] numeric comparison" "yes or no" "$result"
fi

# =====================================
section "386. FILE TEST WITH VARIABLES"
# =====================================

result=$("$FORTSH_BIN" -c 'f='"$TEST_DIR"'/regular_file; [ -f "$f" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -f \"\$var\" ] variable as filename"
else
    fail "[ -f \"\$var\" ] variable as filename" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'd='"$TEST_DIR"'; [ -d "$d" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -d \"\$var\" ] variable as dirname"
else
    fail "[ -d \"\$var\" ] variable as dirname" "yes" "$result"
fi

# =====================================
section "387. EMPTY OPERAND HANDLING"
# =====================================

result=$("$FORTSH_BIN" -c 'unset x; [ -n "$x" ] && echo yes || echo no' 2>&1)
if [ "$result" = "no" ]; then
    pass "[ -n \"\$unset\" ] unset variable"
else
    fail "[ -n \"\$unset\" ] unset variable" "no" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset x; [ -z "$x" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ -z \"\$unset\" ] unset is zero length"
else
    fail "[ -z \"\$unset\" ] unset is zero length" "yes" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset x; [ "$x" = "" ] && echo yes || echo no' 2>&1)
if [ "$result" = "yes" ]; then
    pass "[ \"\$unset\" = \"\" ] unset equals empty"
else
    fail "[ \"\$unset\" = \"\" ] unset equals empty" "yes" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX File Test Operators Summary\n"
printf "==========================================${NC}\n"
printf "Passed:  ${GREEN}%d${NC}\n" "$PASSED"
printf "Failed:  ${RED}%d${NC}\n" "$FAILED"
printf "Skipped: ${YELLOW}%d${NC}\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"

if [ -n "$FAILED_TESTS_LIST" ]; then
    printf "\n${RED}Failed tests:${NC}\n"
    printf "%b" "$FAILED_TESTS_LIST"
fi

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
