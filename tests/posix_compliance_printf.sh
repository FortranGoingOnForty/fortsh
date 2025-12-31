#!/bin/sh
# =====================================
# POSIX Compliance printf Builtin Test Suite for fortsh
# =====================================
# Tests the printf builtin command per IEEE Std 1003.1-2017
# Section: Shell & Utilities - printf

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-printf]"
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

# =====================================
section "358. PRINTF BASIC STRING FORMAT %s"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%s\n" "hello"' 2>&1)
if [ "$result" = "hello" ]; then
    pass "printf %s basic string"
else
    fail "printf %s basic string" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%s %s\n" "hello" "world"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "printf %s multiple arguments"
else
    fail "printf %s multiple arguments" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%s" ""' 2>&1)
if [ "$result" = "" ]; then
    pass "printf %s empty string"
else
    fail "printf %s empty string" "(empty)" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%.3s\n" "hello"' 2>&1)
if [ "$result" = "hel" ]; then
    pass "printf %.3s precision truncates"
else
    fail "printf %.3s precision truncates" "hel" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%10s\n" "hi"' 2>&1)
if [ "$result" = "        hi" ]; then
    pass "printf %10s width right-align"
else
    fail "printf %10s width right-align" "        hi" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%-10s|\n" "hi"' 2>&1)
if [ "$result" = "hi        |" ]; then
    pass "printf %-10s width left-align"
else
    fail "printf %-10s width left-align" "hi        |" "$result"
fi

# =====================================
section "359. PRINTF INTEGER FORMATS %d %i"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%d\n" 42' 2>&1)
if [ "$result" = "42" ]; then
    pass "printf %d basic decimal"
else
    fail "printf %d basic decimal" "42" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%i\n" 42' 2>&1)
if [ "$result" = "42" ]; then
    pass "printf %i basic integer"
else
    fail "printf %i basic integer" "42" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%d\n" -42' 2>&1)
if [ "$result" = "-42" ]; then
    pass "printf %d negative number"
else
    fail "printf %d negative number" "-42" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%5d\n" 42' 2>&1)
if [ "$result" = "   42" ]; then
    pass "printf %5d width padding"
else
    fail "printf %5d width padding" "   42" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%05d\n" 42' 2>&1)
if [ "$result" = "00042" ]; then
    pass "printf %05d zero padding"
else
    fail "printf %05d zero padding" "00042" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%-5d|\n" 42' 2>&1)
if [ "$result" = "42   |" ]; then
    pass "printf %-5d left-align"
else
    fail "printf %-5d left-align" "42   |" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%+d\n" 42' 2>&1)
if [ "$result" = "+42" ]; then
    pass "printf %+d explicit plus sign"
else
    fail "printf %+d explicit plus sign" "+42" "$result"
fi

# =====================================
section "360. PRINTF OCTAL AND HEX FORMATS %o %x %X"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%o\n" 8' 2>&1)
if [ "$result" = "10" ]; then
    pass "printf %o octal format"
else
    fail "printf %o octal format" "10" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%x\n" 255' 2>&1)
if [ "$result" = "ff" ]; then
    pass "printf %x lowercase hex"
else
    fail "printf %x lowercase hex" "ff" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%X\n" 255' 2>&1)
if [ "$result" = "FF" ]; then
    pass "printf %X uppercase hex"
else
    fail "printf %X uppercase hex" "FF" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%#x\n" 255' 2>&1)
if [ "$result" = "0xff" ]; then
    pass "printf %#x alternate form"
else
    fail "printf %#x alternate form" "0xff" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%#o\n" 8' 2>&1)
if [ "$result" = "010" ]; then
    pass "printf %#o alternate octal form"
else
    fail "printf %#o alternate octal form" "010" "$result"
fi

# =====================================
section "361. PRINTF CHARACTER FORMAT %c"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%c\n" A' 2>&1)
if [ "$result" = "A" ]; then
    pass "printf %c single character"
else
    fail "printf %c single character" "A" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%c\n" "hello"' 2>&1)
if [ "$result" = "h" ]; then
    pass "printf %c first char of string"
else
    fail "printf %c first char of string" "h" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%c%c%c\n" a b c' 2>&1)
if [ "$result" = "abc" ]; then
    pass "printf %c multiple chars"
else
    fail "printf %c multiple chars" "abc" "$result"
fi

# =====================================
section "362. PRINTF ESCAPE SEQUENCES"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "hello\nworld\n"' 2>&1)
expected=$(printf "hello\nworld")
if [ "$result" = "$expected" ]; then
    pass "printf \\n newline"
else
    fail "printf \\n newline" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "a\tb\n"' 2>&1)
expected=$(printf "a\tb")
if [ "$result" = "$expected" ]; then
    pass "printf \\t tab"
else
    fail "printf \\t tab" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "back\\\\slash\n"' 2>&1)
if [ "$result" = 'back\slash' ]; then
    pass "printf \\\\ literal backslash"
else
    fail "printf \\\\ literal backslash" 'back\slash' "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "100%%\n"' 2>&1)
if [ "$result" = "100%" ]; then
    pass "printf %% literal percent"
else
    fail "printf %% literal percent" "100%" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "\101\n"' 2>&1)
if [ "$result" = "A" ]; then
    pass "printf \\NNN octal escape"
else
    fail "printf \\NNN octal escape" "A" "$result"
fi

# =====================================
section "363. PRINTF %b ESCAPE INTERPRETATION"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%b\n" "hello\nworld"' 2>&1)
expected=$(printf "hello\nworld")
if [ "$result" = "$expected" ]; then
    pass "printf %b interprets backslash escapes"
else
    fail "printf %b interprets backslash escapes" "(newline)" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%b\n" "tab\there"' 2>&1)
expected=$(printf "tab\there")
if [ "$result" = "$expected" ]; then
    pass "printf %b interprets \\t"
else
    fail "printf %b interprets \\t" "(tab)" "$result"
fi

# =====================================
section "364. PRINTF FORMAT REUSE"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%s\n" one two three' 2>&1)
expected=$(printf "one\ntwo\nthree")
if [ "$result" = "$expected" ]; then
    pass "printf format reused for extra args"
else
    fail "printf format reused for extra args" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%d " 1 2 3 4 5; printf "\n"' 2>&1)
if [ "$result" = "1 2 3 4 5 " ]; then
    pass "printf %d reused for multiple integers"
else
    fail "printf %d reused for multiple integers" "1 2 3 4 5 " "$result"
fi

# =====================================
section "365. PRINTF WITH VARIABLES"
# =====================================

result=$("$FORTSH_BIN" -c 'x="hello"; printf "%s\n" "$x"' 2>&1)
if [ "$result" = "hello" ]; then
    pass "printf with variable argument"
else
    fail "printf with variable argument" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'n=42; printf "Value: %d\n" "$n"' 2>&1)
if [ "$result" = "Value: 42" ]; then
    pass "printf integer from variable"
else
    fail "printf integer from variable" "Value: 42" "$result"
fi

result=$("$FORTSH_BIN" -c 'fmt="%s: %d\n"; printf "$fmt" name 42' 2>&1)
if [ "$result" = "name: 42" ]; then
    pass "printf format from variable"
else
    fail "printf format from variable" "name: 42" "$result"
fi

# =====================================
section "366. PRINTF DYNAMIC WIDTH AND PRECISION"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%*s\n" 10 hi' 2>&1)
if [ "$result" = "        hi" ]; then
    pass "printf %*s dynamic width"
else
    fail "printf %*s dynamic width" "        hi" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%.*s\n" 3 hello' 2>&1)
if [ "$result" = "hel" ]; then
    pass "printf %.*s dynamic precision"
else
    fail "printf %.*s dynamic precision" "hel" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%*.*s\n" 10 3 hello' 2>&1)
if [ "$result" = "       hel" ]; then
    pass "printf %*.*s dynamic width and precision"
else
    fail "printf %*.*s dynamic width and precision" "       hel" "$result"
fi

# =====================================
section "367. PRINTF RETURN VALUE"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%s" "test"; echo $?' 2>&1)
if echo "$result" | grep -q "0"; then
    pass "printf returns 0 on success"
else
    fail "printf returns 0 on success" "0" "$result"
fi

# =====================================
section "368. PRINTF EDGE CASES"
# =====================================

result=$("$FORTSH_BIN" -c 'printf "%d\n" 0' 2>&1)
if [ "$result" = "0" ]; then
    pass "printf %d zero"
else
    fail "printf %d zero" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "%s\n" ""' 2>&1)
if [ "$result" = "" ]; then
    pass "printf empty argument"
else
    fail "printf empty argument" "(empty)" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf "no format"' 2>&1)
if [ "$result" = "no format" ]; then
    pass "printf literal string no format"
else
    fail "printf literal string no format" "no format" "$result"
fi

result=$("$FORTSH_BIN" -c 'printf ""' 2>&1)
if [ "$result" = "" ]; then
    pass "printf empty format string"
else
    fail "printf empty format string" "(empty)" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX printf Builtin Test Summary\n"
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
