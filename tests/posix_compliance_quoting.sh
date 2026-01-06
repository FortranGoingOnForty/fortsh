#!/bin/sh
# =====================================
# POSIX Compliance Quoting Test Suite for fortsh
# =====================================
# Tests quoting and escaping per IEEE Std 1003.1-2017
# Section: Shell Command Language - Quoting

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-quoting]"
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
section "446. SINGLE QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c "echo 'hello world'" 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Single quotes preserve spaces"
else
    fail "Single quotes preserve spaces" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c "x=test; echo '\$x'" 2>&1)
if [ "$result" = '$x' ]; then
    pass "Single quotes prevent variable expansion"
else
    fail "Single quotes prevent variable expansion" '$x' "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'back\\slash'" 2>&1)
if [ "$result" = 'back\slash' ]; then
    pass "Single quotes preserve backslash"
else
    fail "Single quotes preserve backslash" 'back\slash' "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'has \"double\" quotes'" 2>&1)
if [ "$result" = 'has "double" quotes' ]; then
    pass "Single quotes preserve double quotes"
else
    fail "Single quotes preserve double quotes" 'has "double" quotes' "$result"
fi

result=$("$FORTSH_BIN" -c "echo '\$(echo no)'" 2>&1)
if [ "$result" = '$(echo no)' ]; then
    pass "Single quotes prevent command substitution"
else
    fail "Single quotes prevent command substitution" '$(echo no)' "$result"
fi

# =====================================
section "447. DOUBLE QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello world"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Double quotes preserve spaces"
else
    fail "Double quotes preserve spaces" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=test; echo "$x"' 2>&1)
if [ "$result" = "test" ]; then
    pass "Double quotes allow variable expansion"
else
    fail "Double quotes allow variable expansion" "test" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "$(echo hello)"' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Double quotes allow command substitution"
else
    fail "Double quotes allow command substitution" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "has '\''single'\'' quotes"' 2>&1)
if [ "$result" = "has 'single' quotes" ]; then
    pass "Double quotes preserve single quotes"
else
    fail "Double quotes preserve single quotes" "has 'single' quotes" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "escaped \"quote\""' 2>&1)
if [ "$result" = 'escaped "quote"' ]; then
    pass "Double quotes with escaped quotes"
else
    fail "Double quotes with escaped quotes" 'escaped "quote"' "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "back\\slash"' 2>&1)
if [ "$result" = 'back\slash' ]; then
    pass "Double quotes with escaped backslash"
else
    fail "Double quotes with escaped backslash" 'back\slash' "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "dollar\$sign"' 2>&1)
if [ "$result" = 'dollar$sign' ]; then
    pass "Double quotes with escaped dollar"
else
    fail "Double quotes with escaped dollar" 'dollar$sign' "$result"
fi

# =====================================
section "448. BACKSLASH ESCAPING"
# =====================================

result=$("$FORTSH_BIN" -c 'echo hello\ world' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Backslash escapes space"
else
    fail "Backslash escapes space" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=test; echo \$x' 2>&1)
if [ "$result" = '$x' ]; then
    pass "Backslash escapes dollar sign"
else
    fail "Backslash escapes dollar sign" '$x' "$result"
fi

result=$("$FORTSH_BIN" -c 'echo back\\slash' 2>&1)
if [ "$result" = 'back\slash' ]; then
    pass "Backslash escapes backslash"
else
    fail "Backslash escapes backslash" 'back\slash' "$result"
fi

result=$("$FORTSH_BIN" -c 'echo hello\
world' 2>&1)
if [ "$result" = "helloworld" ]; then
    pass "Backslash-newline line continuation"
else
    fail "Backslash-newline line continuation" "helloworld" "$result"
fi

# =====================================
section "449. MIXED QUOTING"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello"'\''world'\''' 2>&1)
# Adjacent quoted strings concatenate: "hello" + 'world' = helloworld
if [ "$result" = "helloworld" ]; then
    pass "Adjacent double and single quotes"
else
    fail "Adjacent double and single quotes" "helloworld" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=val; echo "$x"'\''$x'\''' 2>&1)
if [ "$result" = 'val$x' ]; then
    pass "Mixed expansion and literal"
else
    fail "Mixed expansion and literal" 'val$x' "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'don'\\''t'" 2>&1)
if [ "$result" = "don't" ]; then
    pass "Single quote in single quoted string"
else
    fail "Single quote in single quoted string" "don't" "$result"
fi

# =====================================
section "450. QUOTING SPECIAL CHARACTERS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "semi;colon"' 2>&1)
if [ "$result" = "semi;colon" ]; then
    pass "Semicolon in double quotes"
else
    fail "Semicolon in double quotes" "semi;colon" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'pipe|char'" 2>&1)
if [ "$result" = "pipe|char" ]; then
    pass "Pipe in single quotes"
else
    fail "Pipe in single quotes" "pipe|char" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "ampersand&here"' 2>&1)
if [ "$result" = "ampersand&here" ]; then
    pass "Ampersand in double quotes"
else
    fail "Ampersand in double quotes" "ampersand&here" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'less<greater>'" 2>&1)
if [ "$result" = "less<greater>" ]; then
    pass "Angle brackets in single quotes"
else
    fail "Angle brackets in single quotes" "less<greater>" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "paren(here)"' 2>&1)
if [ "$result" = "paren(here)" ]; then
    pass "Parentheses in double quotes"
else
    fail "Parentheses in double quotes" "paren(here)" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'star*glob?'" 2>&1)
if [ "$result" = "star*glob?" ]; then
    pass "Glob chars in single quotes"
else
    fail "Glob chars in single quotes" "star*glob?" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "hash#comment"' 2>&1)
if [ "$result" = "hash#comment" ]; then
    pass "Hash in double quotes"
else
    fail "Hash in double quotes" "hash#comment" "$result"
fi

# =====================================
section "451. EMPTY STRINGS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo ""' 2>&1)
if [ "$result" = "" ]; then
    pass "Empty double-quoted string"
else
    fail "Empty double-quoted string" "(empty)" "$result"
fi

result=$("$FORTSH_BIN" -c "echo ''" 2>&1)
if [ "$result" = "" ]; then
    pass "Empty single-quoted string"
else
    fail "Empty single-quoted string" "(empty)" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo "[$x]"' 2>&1)
if [ "$result" = "[]" ]; then
    pass "Empty variable in quotes"
else
    fail "Empty variable in quotes" "[]" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo a "" b' 2>&1)
if [ "$result" = "a  b" ]; then
    pass "Empty string preserves word"
else
    fail "Empty string preserves word" "a  b" "$result"
fi

# =====================================
section "452. WORD SPLITTING"
# =====================================

result=$("$FORTSH_BIN" -c 'x="a b c"; for w in $x; do echo "[$w]"; done' 2>&1)
expected=$(printf "[a]\n[b]\n[c]")
if [ "$result" = "$expected" ]; then
    pass "Unquoted variable splits on whitespace"
else
    fail "Unquoted variable splits on whitespace" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a b c"; for w in "$x"; do echo "[$w]"; done' 2>&1)
if [ "$result" = "[a b c]" ]; then
    pass "Quoted variable prevents splitting"
else
    fail "Quoted variable prevents splitting" "[a b c]" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a  b"; echo $x' 2>&1)
if [ "$result" = "a b" ]; then
    pass "Word splitting collapses spaces"
else
    fail "Word splitting collapses spaces" "a b" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a  b"; echo "$x"' 2>&1)
if [ "$result" = "a  b" ]; then
    pass "Quoting preserves multiple spaces"
else
    fail "Quoting preserves multiple spaces" "a  b" "$result"
fi

# =====================================
section "453. GLOB PREVENTION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "*"' 2>&1)
if [ "$result" = "*" ]; then
    pass "Double quotes prevent glob expansion"
else
    fail "Double quotes prevent glob expansion" "*" "$result"
fi

result=$("$FORTSH_BIN" -c "echo '[a-z]*'" 2>&1)
if [ "$result" = "[a-z]*" ]; then
    pass "Single quotes prevent bracket expansion"
else
    fail "Single quotes prevent bracket expansion" "[a-z]*" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "?"' 2>&1)
if [ "$result" = "?" ]; then
    pass "Double quotes prevent ? expansion"
else
    fail "Double quotes prevent ? expansion" "?" "$result"
fi

# =====================================
section "454. QUOTE IN VARIABLE"
# =====================================

result=$("$FORTSH_BIN" -c "x=\"has 'quotes'\"; echo \"\$x\"" 2>&1)
if [ "$result" = "has 'quotes'" ]; then
    pass "Single quotes inside double-quoted variable"
else
    fail "Single quotes inside double-quoted variable" "has 'quotes'" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="has \"quotes\""; echo "$x"' 2>&1)
if [ "$result" = 'has "quotes"' ]; then
    pass "Double quotes inside variable"
else
    fail "Double quotes inside variable" 'has "quotes"' "$result"
fi

# =====================================
section "455. QUOTING IN ASSIGNMENTS"
# =====================================

result=$("$FORTSH_BIN" -c 'x="hello world"; echo $x' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Quoted assignment with spaces"
else
    fail "Quoted assignment with spaces" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c "x='no \$expansion'; echo \"\$x\"" 2>&1)
if [ "$result" = 'no $expansion' ]; then
    pass "Single-quoted assignment"
else
    fail "Single-quoted assignment" 'no $expansion' "$result"
fi

result=$("$FORTSH_BIN" -c 'y=value; x="with $y"; echo "$x"' 2>&1)
if [ "$result" = "with value" ]; then
    pass "Variable expansion in assignment"
else
    fail "Variable expansion in assignment" "with value" "$result"
fi

# =====================================
section "456. QUOTING IN COMMAND SUBSTITUTION"
# =====================================

result=$("$FORTSH_BIN" -c 'x=$(echo "hello world"); echo "$x"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Quotes inside command substitution"
else
    fail "Quotes inside command substitution" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="$(echo "nested quotes")"; echo "$x"' 2>&1)
if [ "$result" = "nested quotes" ]; then
    pass "Nested quotes in command substitution"
else
    fail "Nested quotes in command substitution" "nested quotes" "$result"
fi

# =====================================
section "457. BACKSLASH IN DOUBLE QUOTES"
# =====================================

# POSIX: In double quotes, \\\\ (4 backslashes) becomes \\ (2 backslashes)
# Each pair of \\ in double quotes produces one literal backslash
result=$("$FORTSH_BIN" -c 'echo "back\\\\slash"' 2>&1)
if [ "$result" = 'back\\slash' ]; then
    pass "Backslash-backslash in double quotes"
else
    fail "Backslash-backslash in double quotes" 'back\\slash' "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "newline\\n"' 2>&1)
if [ "$result" = 'newline\n' ]; then
    pass "Backslash-n in double quotes (literal)"
else
    fail "Backslash-n in double quotes (literal)" 'newline\n' "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "tab\\t"' 2>&1)
if [ "$result" = 'tab\t' ]; then
    pass "Backslash-t in double quotes (literal)"
else
    fail "Backslash-t in double quotes (literal)" 'tab\t' "$result"
fi

# =====================================
section "458. DOLLAR IN QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "cost: \$5"' 2>&1)
if [ "$result" = 'cost: $5' ]; then
    pass "Escaped dollar in double quotes"
else
    fail "Escaped dollar in double quotes" 'cost: $5' "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'cost: \$5'" 2>&1)
if [ "$result" = 'cost: $5' ]; then
    pass "Dollar in single quotes (literal)"
else
    fail "Dollar in single quotes (literal)" 'cost: $5' "$result"
fi

# =====================================
section "459. NEWLINE IN QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "line1
line2"' 2>&1)
expected=$(printf "line1\nline2")
if [ "$result" = "$expected" ]; then
    pass "Literal newline in double quotes"
else
    fail "Literal newline in double quotes" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'line1
line2'" 2>&1)
expected=$(printf "line1\nline2")
if [ "$result" = "$expected" ]; then
    pass "Literal newline in single quotes"
else
    fail "Literal newline in single quotes" "$expected" "$result"
fi

# =====================================
section "460. TAB AND SPACE IN QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "	tab"' 2>&1)
if printf "%s" "$result" | grep -q "	"; then
    pass "Literal tab in double quotes"
else
    fail "Literal tab in double quotes" "string with tab" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "  spaces  "' 2>&1)
if [ "$result" = "  spaces  " ]; then
    pass "Multiple spaces in double quotes"
else
    fail "Multiple spaces in double quotes" "  spaces  " "$result"
fi

# =====================================
section "461. QUOTING IN FOR LOOP"
# =====================================

result=$("$FORTSH_BIN" -c 'for x in "a b" c; do echo "[$x]"; done' 2>&1)
expected=$(printf "[a b]\n[c]")
if [ "$result" = "$expected" ]; then
    pass "Quoted string in for list"
else
    fail "Quoted string in for list" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'list="a b c"; for x in $list; do echo "[$x]"; done' 2>&1)
expected=$(printf "[a]\n[b]\n[c]")
if [ "$result" = "$expected" ]; then
    pass "Unquoted var splits in for"
else
    fail "Unquoted var splits in for" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'list="a b c"; for x in "$list"; do echo "[$x]"; done' 2>&1)
if [ "$result" = "[a b c]" ]; then
    pass "Quoted var no split in for"
else
    fail "Quoted var no split in for" "[a b c]" "$result"
fi

# =====================================
section "462. QUOTING IN CASE STATEMENT"
# =====================================

result=$("$FORTSH_BIN" -c 'x="hello world"; case "$x" in "hello world") echo match;; esac' 2>&1)
if [ "$result" = "match" ]; then
    pass "Quoted string in case word"
else
    fail "Quoted string in case word" "match" "$result"
fi

result=$("$FORTSH_BIN" -c 'case "a b" in "a b") echo yes;; *) echo no;; esac' 2>&1)
if [ "$result" = "yes" ]; then
    pass "Quoted pattern in case"
else
    fail "Quoted pattern in case" "yes" "$result"
fi

# =====================================
section "463. QUOTING SPECIAL SHELL CHARS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello; world"' 2>&1)
if [ "$result" = "hello; world" ]; then
    pass "Semicolon in double quotes"
else
    fail "Semicolon in double quotes" "hello; world" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'a && b'" 2>&1)
if [ "$result" = "a && b" ]; then
    pass "Double ampersand in single quotes"
else
    fail "Double ampersand in single quotes" "a && b" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "a || b"' 2>&1)
if [ "$result" = "a || b" ]; then
    pass "Double pipe in double quotes"
else
    fail "Double pipe in double quotes" "a || b" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'back\`tick'" 2>&1)
if [ "$result" = 'back`tick' ]; then
    pass "Backtick in single quotes"
else
    fail "Backtick in single quotes" 'back`tick' "$result"
fi

# =====================================
section "464. QUOTING IN ARITHMETIC"
# =====================================

result=$("$FORTSH_BIN" -c 'x=5; echo $((x + 3))' 2>&1)
if [ "$result" = "8" ]; then
    pass "Unquoted var in arithmetic"
else
    fail "Unquoted var in arithmetic" "8" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="5"; echo $((x + 3))' 2>&1)
if [ "$result" = "8" ]; then
    pass "Quoted assignment used in arithmetic"
else
    fail "Quoted assignment used in arithmetic" "8" "$result"
fi

# =====================================
section "465. ESCAPE SEQUENCES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "hello\tworld"' 2>&1)
if echo "$result" | grep -q "hello"; then
    pass "Backslash-t in double quotes"
else
    fail "Backslash-t in double quotes"
fi

# Use $'...' to pass literal backslash-n to the shell
result=$("$FORTSH_BIN" -c $'echo \'hello\\nworld\'' 2>&1)
if echo "$result" | grep -q 'hello\\nworld'; then
    pass "Backslash-n literal in single quotes"
else
    fail "Backslash-n literal in single quotes"
fi

# =====================================
section "466. QUOTING AND WORD SPLITTING"
# =====================================

result=$("$FORTSH_BIN" -c 'x="a b c"; set -- $x; echo $#' 2>&1)
if [ "$result" = "3" ]; then
    pass "Unquoted var splits on spaces"
else
    fail "Unquoted var splits on spaces" "3" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a b c"; set -- "$x"; echo $#' 2>&1)
if [ "$result" = "1" ]; then
    pass "Quoted var prevents splitting"
else
    fail "Quoted var prevents splitting" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; set -- $x; echo $#' 2>&1)
if [ "$result" = "0" ]; then
    pass "Empty unquoted var produces no args"
else
    fail "Empty unquoted var produces no args" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; set -- "$x"; echo $#' 2>&1)
if [ "$result" = "1" ]; then
    pass "Empty quoted var produces one empty arg"
else
    fail "Empty quoted var produces one empty arg" "1" "$result"
fi

# =====================================
section "467. QUOTING SPECIAL PARAMETERS"
# =====================================

result=$("$FORTSH_BIN" -c 'set -- a b c; echo "$@" | wc -w' 2>&1)
if [ "$result" = "3" ]; then
    pass 'Quoted $@ preserves args'
else
    fail 'Quoted $@ preserves args' "3" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a b c; echo "$*"' 2>&1)
if [ "$result" = "a b c" ]; then
    pass 'Quoted $* joins args'
else
    fail 'Quoted $* joins args' "a b c" "$result"
fi

result=$("$FORTSH_BIN" -c 'set -- a "b c" d; for x in "$@"; do echo "[$x]"; done' 2>&1)
expected=$(printf "[a]\n[b c]\n[d]")
if [ "$result" = "$expected" ]; then
    pass 'Quoted $@ preserves quoting in original args'
else
    fail 'Quoted $@ preserves quoting in original args'
fi

# =====================================
section "468. NESTED QUOTING"
# =====================================

result=$("$FORTSH_BIN" -c "echo 'single \"with\" double'" 2>&1)
if [ "$result" = 'single "with" double' ]; then
    pass "Double quotes inside single quotes"
else
    fail "Double quotes inside single quotes"
fi

result=$("$FORTSH_BIN" -c 'echo "double '\''with'\'' single"' 2>&1)
if [ "$result" = "double 'with' single" ]; then
    pass "Single quotes inside double quotes (escaped)"
else
    fail "Single quotes inside double quotes (escaped)"
fi

# =====================================
section "469. QUOTING IN ASSIGNMENTS"
# =====================================

result=$("$FORTSH_BIN" -c 'x="hello world"; echo $x' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Quoted assignment with spaces"
else
    fail "Quoted assignment with spaces" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c "x='hello world'; echo \$x" 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Single-quoted assignment with spaces"
else
    fail "Single-quoted assignment with spaces" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=hello\ world; echo $x' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Escaped space in assignment"
else
    fail "Escaped space in assignment" "hello world" "$result"
fi

# =====================================
section "470. QUOTING IN COMMAND SUBSTITUTION"
# =====================================

result=$("$FORTSH_BIN" -c 'x=$(echo "hello world"); echo "$x"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Quoted string in command substitution"
else
    fail "Quoted string in command substitution" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=`echo "hello world"`; echo "$x"' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Quoted string in backtick substitution"
else
    fail "Quoted string in backtick substitution" "hello world" "$result"
fi

# =====================================
section "471. QUOTING AND GLOB PREVENTION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "*"' 2>&1)
if [ "$result" = "*" ]; then
    pass "Quoted asterisk is literal"
else
    fail "Quoted asterisk is literal" "*" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "?"' 2>&1)
if [ "$result" = "?" ]; then
    pass "Quoted question mark is literal"
else
    fail "Quoted question mark is literal" "?" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "[abc]"' 2>&1)
if [ "$result" = "[abc]" ]; then
    pass "Quoted brackets are literal"
else
    fail "Quoted brackets are literal" "[abc]" "$result"
fi

# =====================================
section "472. QUOTING IN TESTS"
# =====================================

result=$("$FORTSH_BIN" -c 'x=""; [ -z "$x" ] && echo empty' 2>&1)
if [ "$result" = "empty" ]; then
    pass "Quoted empty var in test -z"
else
    fail "Quoted empty var in test -z" "empty" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="hello"; [ -n "$x" ] && echo nonempty' 2>&1)
if [ "$result" = "nonempty" ]; then
    pass "Quoted var in test -n"
else
    fail "Quoted var in test -n" "nonempty" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a b"; [ "$x" = "a b" ] && echo match' 2>&1)
if [ "$result" = "match" ]; then
    pass "Quoted var with spaces in test ="
else
    fail "Quoted var with spaces in test =" "match" "$result"
fi

# =====================================
section "473. QUOTING IN CASE PATTERNS"
# =====================================

result=$("$FORTSH_BIN" -c 'x="*"; case "$x" in "*") echo literal;; esac' 2>&1)
if [ "$result" = "literal" ]; then
    pass "Quoted asterisk matches literally in case"
else
    fail "Quoted asterisk matches literally in case" "literal" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="a b"; case "$x" in "a b") echo match;; esac' 2>&1)
if [ "$result" = "match" ]; then
    pass "Quoted pattern with space in case"
else
    fail "Quoted pattern with space in case" "match" "$result"
fi

# =====================================
section "474. QUOTING IN FUNCTION ARGS"
# =====================================

result=$("$FORTSH_BIN" -c 'f() { echo "[$1]"; }; f "hello world"' 2>&1)
if [ "$result" = "[hello world]" ]; then
    pass "Quoted arg to function"
else
    fail "Quoted arg to function" "[hello world]" "$result"
fi

result=$("$FORTSH_BIN" -c 'f() { echo $#; }; f "a b" "c d"' 2>&1)
if [ "$result" = "2" ]; then
    pass "Quoted args count in function"
else
    fail "Quoted args count in function" "2" "$result"
fi

# =====================================
section "475. DOLLAR IN QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "\$HOME"' 2>&1)
if [ "$result" = '$HOME' ]; then
    pass "Escaped dollar in double quotes"
else
    fail "Escaped dollar in double quotes" "\$HOME" "$result"
fi

result=$("$FORTSH_BIN" -c "echo '\$HOME'" 2>&1)
if [ "$result" = '$HOME' ]; then
    pass "Dollar in single quotes"
else
    fail "Dollar in single quotes" "\$HOME" "$result"
fi

# =====================================
section "476. BACKSLASH IN QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "\\"' 2>&1)
if [ "$result" = '\' ]; then
    pass "Escaped backslash in double quotes"
else
    fail "Escaped backslash in double quotes" "\\" "$result"
fi

result=$("$FORTSH_BIN" -c "echo '\\'" 2>&1)
if [ "$result" = '\' ]; then
    pass "Backslash in single quotes"
else
    fail "Backslash in single quotes" "\\" "$result"
fi

# =====================================
section "477. QUOTE REMOVAL"
# =====================================

result=$("$FORTSH_BIN" -c 'echo ""hello""' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Empty quotes around word"
else
    fail "Empty quotes around word" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo "a""b""c"' 2>&1)
if [ "$result" = "abc" ]; then
    pass "Adjacent quoted strings concatenate"
else
    fail "Adjacent quoted strings concatenate" "abc" "$result"
fi

# =====================================
section "478. MIXED QUOTE STYLES"
# =====================================

result=$("$FORTSH_BIN" -c "x=val; echo 'a'\"\$x\"'b'" 2>&1)
if [ "$result" = "avalb" ]; then
    pass "Mixed single and double quotes"
else
    fail "Mixed single and double quotes" "avalb" "$result"
fi

result=$("$FORTSH_BIN" -c "echo 'single'\"double\"'single'" 2>&1)
if [ "$result" = "singledoublesingle" ]; then
    pass "Alternating quote styles"
else
    fail "Alternating quote styles" "singledoublesingle" "$result"
fi

# =====================================
section "479. QUOTING IN REDIRECTIONS"
# =====================================

result=$("$FORTSH_BIN" -c 'echo test > "/tmp/quote space test.txt"; cat "/tmp/quote space test.txt"; rm "/tmp/quote space test.txt"' 2>&1)
if [ "$result" = "test" ]; then
    pass "Quoted filename with space in redirect"
else
    fail "Quoted filename with space in redirect" "test" "$result"
fi

# =====================================
section "480. EMPTY QUOTES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo ""' 2>&1)
if [ -z "$result" ]; then
    pass "Empty double quotes produce empty output"
else
    fail "Empty double quotes produce empty output" "empty" "$result"
fi

result=$("$FORTSH_BIN" -c "echo ''" 2>&1)
if [ -z "$result" ]; then
    pass "Empty single quotes produce empty output"
else
    fail "Empty single quotes produce empty output" "empty" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo "[$x]"' 2>&1)
if [ "$result" = "[]" ]; then
    pass "Empty var in quotes"
else
    fail "Empty var in quotes" "[]" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Quoting Test Summary\n"
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
