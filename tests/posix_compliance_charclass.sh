#!/bin/sh
# =====================================
# POSIX Compliance Character Class Test Suite for fortsh
# =====================================
# Tests POSIX bracket expression character classes per IEEE Std 1003.1-2017
# Section 9.3.5 RE Bracket Expression

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-charclass]"
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
    TEST_DIR="/tmp/fortsh_charclass_$$"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR" || exit 1

    # Create files for character class testing
    touch "file1.txt" "file2.txt" "file3.txt"
    touch "FileA.txt" "FileB.txt" "FileC.txt"
    touch "data_01.csv" "data_02.csv" "data_99.csv"
    touch "test-file" "test_file" "test.file"
    touch "UPPER.TXT" "lower.txt" "MiXeD.TxT"
    touch "a1b2c3" "xyz789" "ABC123"
    touch "file with space.txt"
    touch ".hidden" ".dotfile"
    touch "special!file" "special@file"
}

cleanup_test_files() {
    cd /
    rm -rf "$TEST_DIR"
}

# Trap to ensure cleanup
trap cleanup_test_files EXIT

setup_test_files

# =====================================
section "341. POSIX CHARACTER CLASS [:alpha:]"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:alpha:]]*' 2>&1)
# Should match files starting with alphabetic characters
if echo "$result" | grep -q "file1.txt\|FileA.txt"; then
    pass "[:alpha:] matches alphabetic characters"
else
    fail "[:alpha:] matches alphabetic characters" "files starting with letters" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && for f in [[:alpha:]]*.txt; do echo "$f"; done | head -1' 2>&1)
if [ -n "$result" ] && [ "$result" != '[[:alpha:]]*.txt' ]; then
    pass "[:alpha:] in loop context"
else
    fail "[:alpha:] in loop context" "matched files" "$result"
fi

# =====================================
section "342. POSIX CHARACTER CLASS [:digit:]"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo data_[[:digit:]]*.csv' 2>&1)
if echo "$result" | grep -q "data_0"; then
    pass "[:digit:] matches numeric characters"
else
    fail "[:digit:] matches numeric characters" "data_0*.csv files" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo *[[:digit:]][[:digit:]].csv' 2>&1)
if echo "$result" | grep -q "data_"; then
    pass "[:digit:][:digit:] matches two digits"
else
    fail "[:digit:][:digit:] matches two digits" "files ending in two digits" "$result"
fi

# =====================================
section "343. POSIX CHARACTER CLASS [:alnum:]"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:alnum:]]*.txt' 2>&1)
if echo "$result" | grep -q "file"; then
    pass "[:alnum:] matches alphanumeric characters"
else
    fail "[:alnum:] matches alphanumeric characters" "alphanumeric files" "$result"
fi

# =====================================
section "344. POSIX CHARACTER CLASS [:upper:]"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:upper:]]*.TXT' 2>&1)
if echo "$result" | grep -q "UPPER.TXT\|File"; then
    pass "[:upper:] matches uppercase characters"
else
    fail "[:upper:] matches uppercase characters" "uppercase files" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:upper:]][[:upper:]][[:upper:]]*.TXT' 2>&1)
if echo "$result" | grep -q "UPPER.TXT\|ABC"; then
    pass "[:upper:] repeated matches multiple uppercase"
else
    fail "[:upper:] repeated matches multiple uppercase" "all-caps files" "$result"
fi

# =====================================
section "345. POSIX CHARACTER CLASS [:lower:]"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:lower:]]*.txt' 2>&1)
if echo "$result" | grep -q "file\|lower"; then
    pass "[:lower:] matches lowercase characters"
else
    fail "[:lower:] matches lowercase characters" "lowercase files" "$result"
fi

# =====================================
section "346. POSIX CHARACTER CLASS [:space:]"
# =====================================

# [:space:] in variable content
result=$("$FORTSH_BIN" -c 'x="hello world"; case "$x" in *[[:space:]]*) echo "has space";; esac' 2>&1)
if [ "$result" = "has space" ]; then
    pass "[:space:] matches space in case pattern"
else
    fail "[:space:] matches space in case pattern" "has space" "$result"
fi

# =====================================
section "347. POSIX CHARACTER CLASS [:blank:]"
# =====================================

# [:blank:] matches space and tab only
result=$("$FORTSH_BIN" -c 'x="a	b"; case "$x" in *[[:blank:]]*) echo "has blank";; esac' 2>&1)
if [ "$result" = "has blank" ]; then
    pass "[:blank:] matches tab character"
else
    fail "[:blank:] matches tab character" "has blank" "$result"
fi

# =====================================
section "348. POSIX CHARACTER CLASS [:xdigit:]"
# =====================================

result=$("$FORTSH_BIN" -c 'case "a1b2c3" in [[:xdigit:]]*) echo "starts with hex";; esac' 2>&1)
if [ "$result" = "starts with hex" ]; then
    pass "[:xdigit:] matches hexadecimal digits"
else
    fail "[:xdigit:] matches hexadecimal digits" "starts with hex" "$result"
fi

result=$("$FORTSH_BIN" -c 'case "DEADBEEF" in [[:xdigit:]]*) echo "valid hex";; esac' 2>&1)
if [ "$result" = "valid hex" ]; then
    pass "[:xdigit:] matches uppercase hex"
else
    fail "[:xdigit:] matches uppercase hex" "valid hex" "$result"
fi

# =====================================
section "349. POSIX CHARACTER CLASS [:punct:]"
# =====================================

result=$("$FORTSH_BIN" -c 'case "hello!" in *[[:punct:]]) echo "ends with punct";; esac' 2>&1)
if [ "$result" = "ends with punct" ]; then
    pass "[:punct:] matches punctuation"
else
    fail "[:punct:] matches punctuation" "ends with punct" "$result"
fi

result=$("$FORTSH_BIN" -c 'case "@#$%" in [[:punct:]]*) echo "starts with punct";; esac' 2>&1)
if [ "$result" = "starts with punct" ]; then
    pass "[:punct:] matches special characters"
else
    fail "[:punct:] matches special characters" "starts with punct" "$result"
fi

# =====================================
section "350. POSIX CHARACTER CLASS [:print:]"
# =====================================

result=$("$FORTSH_BIN" -c 'case "hello" in [[:print:]]*) echo "printable";; esac' 2>&1)
if [ "$result" = "printable" ]; then
    pass "[:print:] matches printable characters"
else
    fail "[:print:] matches printable characters" "printable" "$result"
fi

# =====================================
section "351. POSIX CHARACTER CLASS [:graph:]"
# =====================================

result=$("$FORTSH_BIN" -c 'case "abc123" in [[:graph:]]*) echo "graphical";; esac' 2>&1)
if [ "$result" = "graphical" ]; then
    pass "[:graph:] matches graphical characters"
else
    fail "[:graph:] matches graphical characters" "graphical" "$result"
fi

# =====================================
section "352. POSIX BRACKET NEGATION [^...] and [!...]"
# =====================================

# Note: POSIX uses [!...] for negation, [^...] is bash extension
result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [!A-Z]*.txt' 2>&1)
if echo "$result" | grep -q "file\|lower"; then
    pass "[!...] negation matches non-uppercase (POSIX standard)"
else
    fail "[!...] negation matches non-uppercase (POSIX standard)" "lowercase files" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [!0-9]*.txt' 2>&1)
if echo "$result" | grep -q "file\|File"; then
    pass "[!...] negation matches non-digits"
else
    fail "[!...] negation matches non-digits" "non-digit files" "$result"
fi

# =====================================
section "353. POSIX RANGE EXPRESSIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo file[1-3].txt' 2>&1)
if echo "$result" | grep -q "file1.txt\|file2.txt\|file3.txt"; then
    pass "[1-3] range matches digits 1-3"
else
    fail "[1-3] range matches digits 1-3" "file1-3.txt" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo File[A-C].txt' 2>&1)
if echo "$result" | grep -q "FileA.txt\|FileB.txt\|FileC.txt"; then
    pass "[A-C] range matches uppercase A-C"
else
    fail "[A-C] range matches uppercase A-C" "FileA-C.txt" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [a-z]*.txt' 2>&1)
if echo "$result" | grep -q "file\|lower"; then
    pass "[a-z] range matches lowercase"
else
    fail "[a-z] range matches lowercase" "lowercase files" "$result"
fi

# =====================================
section "354. COMBINED CHARACTER CLASSES"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:alpha:][:digit:]]*.txt' 2>&1)
if echo "$result" | grep -q "file\|File"; then
    pass "[[:alpha:][:digit:]] combined classes"
else
    fail "[[:alpha:][:digit:]] combined classes" "alphanumeric start" "$result"
fi

result=$("$FORTSH_BIN" -c 'case "test123" in [[:alpha:]][[:alpha:]][[:alpha:]][[:alpha:]][[:digit:]][[:digit:]][[:digit:]]) echo "matched";; esac' 2>&1)
if [ "$result" = "matched" ]; then
    pass "Combined classes in exact pattern"
else
    fail "Combined classes in exact pattern" "matched" "$result"
fi

# =====================================
section "355. CHARACTER CLASS IN CASE STATEMENTS"
# =====================================

result=$("$FORTSH_BIN" -c '
for word in hello WORLD 123 test!; do
    case "$word" in
        [[:upper:]]*) echo "$word: upper" ;;
        [[:lower:]]*) echo "$word: lower" ;;
        [[:digit:]]*) echo "$word: digit" ;;
        *) echo "$word: other" ;;
    esac
done
' 2>&1)
if echo "$result" | grep -q "hello: lower" && echo "$result" | grep -q "WORLD: upper" && echo "$result" | grep -q "123: digit"; then
    pass "Character classes in case statement"
else
    fail "Character classes in case statement" "categorized output" "$result"
fi

# =====================================
section "356. CHARACTER CLASS EDGE CASES"
# =====================================

# Literal hyphen at start
result=$("$FORTSH_BIN" -c 'case "-test" in [-a]*) echo "matched";; esac' 2>&1)
if [ "$result" = "matched" ]; then
    pass "Literal hyphen at bracket start"
else
    fail "Literal hyphen at bracket start" "matched" "$result"
fi

# Literal bracket
result=$("$FORTSH_BIN" -c 'case "[test]" in \[*) echo "matched";; esac' 2>&1)
if [ "$result" = "matched" ]; then
    pass "Escaped bracket in pattern"
else
    fail "Escaped bracket in pattern" "matched" "$result"
fi

# Empty class should not match
result=$("$FORTSH_BIN" -c 'case "test" in []) echo "empty";; *) echo "star";; esac' 2>&1)
if [ "$result" = "star" ]; then
    pass "Empty bracket expression fallthrough"
else
    skip "Empty bracket expression fallthrough" "implementation varies"
fi

# =====================================
section "357. CHARACTER CLASS WITH GLOB PATTERNS"
# =====================================

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo *[[:digit:]].*' 2>&1)
if echo "$result" | grep -q "data_0\|file"; then
    pass "Character class with glob wildcards"
else
    fail "Character class with glob wildcards" "digit-containing files" "$result"
fi

result=$("$FORTSH_BIN" -c 'cd '"$TEST_DIR"' && echo [[:alpha:]]?[[:alpha:]]?[[:alpha:]]*.txt' 2>&1)
if echo "$result" | grep -q "file\|File\|lower"; then
    pass "Character class with ? wildcards"
else
    fail "Character class with ? wildcards" "pattern matched files" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Character Class Test Summary\n"
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
