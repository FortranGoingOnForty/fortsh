#!/bin/sh
# =====================================
# POSIX Compliance Here-Document and Expansion Test Suite for fortsh
# =====================================
# Tests here-documents and parameter expansion per IEEE Std 1003.1-2017
# Section: Shell Command Language - Here-Documents, Parameter Expansion

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-heredoc]"
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
section "396. BASIC HERE-DOCUMENT"
# =====================================

result=$("$FORTSH_BIN" -c 'cat <<EOF
hello world
EOF' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Basic here-document"
else
    fail "Basic here-document" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'cat <<END
line one
line two
END' 2>&1)
expected=$(printf "line one\nline two")
if [ "$result" = "$expected" ]; then
    pass "Here-document multiple lines"
else
    fail "Here-document multiple lines" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=world; cat <<EOF
hello $x
EOF' 2>&1)
if [ "$result" = "hello world" ]; then
    pass "Here-document with variable expansion"
else
    fail "Here-document with variable expansion" "hello world" "$result"
fi

result=$("$FORTSH_BIN" -c 'cat <<EOF
result: $(echo test)
EOF' 2>&1)
if [ "$result" = "result: test" ]; then
    pass "Here-document with command substitution"
else
    fail "Here-document with command substitution" "result: test" "$result"
fi

# =====================================
section "397. QUOTED HERE-DOCUMENT DELIMITER"
# =====================================

result=$("$FORTSH_BIN" -c 'x=world; cat <<"EOF"
hello $x
EOF' 2>&1)
if [ "$result" = 'hello $x' ]; then
    pass "Quoted delimiter prevents expansion"
else
    fail "Quoted delimiter prevents expansion" 'hello $x' "$result"
fi

result=$("$FORTSH_BIN" -c "cat <<'END'
test \$(echo foo)
END" 2>&1)
if [ "$result" = 'test $(echo foo)' ]; then
    pass "Single-quoted delimiter prevents command sub"
else
    fail "Single-quoted delimiter prevents command sub" 'test $(echo foo)' "$result"
fi

# =====================================
section "398. HERE-DOCUMENT WITH TAB STRIPPING (<<-)"
# =====================================

result=$("$FORTSH_BIN" -c '	cat <<-EOF
	hello
	world
	EOF' 2>&1)
expected=$(printf "hello\nworld")
if [ "$result" = "$expected" ]; then
    pass "<<- strips leading tabs"
else
    fail "<<- strips leading tabs" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'cat <<-END
		indented
	END' 2>&1)
if [ "$result" = "indented" ]; then
    pass "<<- strips multiple tabs"
else
    fail "<<- strips multiple tabs" "indented" "$result"
fi

# =====================================
section "399. HERE-DOCUMENT TO DIFFERENT COMMANDS"
# =====================================

result=$("$FORTSH_BIN" -c 'wc -l <<EOF
one
two
three
EOF' 2>&1)
if echo "$result" | grep -q "3"; then
    pass "Here-document to wc -l"
else
    fail "Here-document to wc -l" "3" "$result"
fi

# Note: read with heredoc can hang if not implemented - use timeout
result=$(timeout 2 "$FORTSH_BIN" -c 'read x <<EOF
test input
EOF
echo "$x"' 2>&1)
exit_code=$?
if [ "$result" = "test input" ]; then
    pass "Here-document to read"
elif [ $exit_code -eq 124 ]; then
    fail "Here-document to read" "test input" "(timeout - hangs)"
else
    fail "Here-document to read" "test input" "$result"
fi

# =====================================
section "400. PARAMETER EXPANSION ${var:-default}"
# =====================================

result=$("$FORTSH_BIN" -c 'unset x; echo ${x:-default}' 2>&1)
if [ "$result" = "default" ]; then
    pass "\${var:-default} for unset variable"
else
    fail "\${var:-default} for unset variable" "default" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo ${x:-default}' 2>&1)
if [ "$result" = "default" ]; then
    pass "\${var:-default} for empty variable"
else
    fail "\${var:-default} for empty variable" "default" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=value; echo ${x:-default}' 2>&1)
if [ "$result" = "value" ]; then
    pass "\${var:-default} for set variable"
else
    fail "\${var:-default} for set variable" "value" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset x; echo ${x-default}' 2>&1)
if [ "$result" = "default" ]; then
    pass "\${var-default} for unset (no colon)"
else
    fail "\${var-default} for unset (no colon)" "default" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo ${x-default}' 2>&1)
if [ "$result" = "" ]; then
    pass "\${var-default} for empty (no colon)"
else
    fail "\${var-default} for empty (no colon)" "(empty)" "$result"
fi

# =====================================
section "401. PARAMETER EXPANSION ${var:+alternate}"
# =====================================

result=$("$FORTSH_BIN" -c 'x=value; echo ${x:+alternate}' 2>&1)
if [ "$result" = "alternate" ]; then
    pass "\${var:+alternate} for set variable"
else
    fail "\${var:+alternate} for set variable" "alternate" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset x; echo ${x:+alternate}' 2>&1)
if [ "$result" = "" ]; then
    pass "\${var:+alternate} for unset variable"
else
    fail "\${var:+alternate} for unset variable" "(empty)" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo ${x:+alternate}' 2>&1)
if [ "$result" = "" ]; then
    pass "\${var:+alternate} for empty variable"
else
    fail "\${var:+alternate} for empty variable" "(empty)" "$result"
fi

# =====================================
section "402. PARAMETER EXPANSION ${var:=assign}"
# =====================================

result=$("$FORTSH_BIN" -c 'unset x; echo ${x:=assigned}; echo $x' 2>&1)
expected=$(printf "assigned\nassigned")
if [ "$result" = "$expected" ]; then
    pass "\${var:=value} assigns when unset"
else
    fail "\${var:=value} assigns when unset" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo ${x:=assigned}; echo $x' 2>&1)
expected=$(printf "assigned\nassigned")
if [ "$result" = "$expected" ]; then
    pass "\${var:=value} assigns when empty"
else
    fail "\${var:=value} assigns when empty" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=original; echo ${x:=assigned}; echo $x' 2>&1)
expected=$(printf "original\noriginal")
if [ "$result" = "$expected" ]; then
    pass "\${var:=value} keeps original when set"
else
    fail "\${var:=value} keeps original when set" "$expected" "$result"
fi

# =====================================
section "403. PARAMETER EXPANSION ${var:?error}"
# =====================================

result=$("$FORTSH_BIN" -c 'x=value; echo ${x:?error message}' 2>&1)
if [ "$result" = "value" ]; then
    pass "\${var:?error} returns value when set"
else
    fail "\${var:?error} returns value when set" "value" "$result"
fi

result=$("$FORTSH_BIN" -c 'unset x; echo ${x:?custom error}' 2>&1)
if echo "$result" | grep -qi "error\|custom"; then
    pass "\${var:?error} shows error when unset"
else
    fail "\${var:?error} shows error when unset" "error message" "$result"
fi

# =====================================
section "404. PARAMETER EXPANSION ${#var}"
# =====================================

result=$("$FORTSH_BIN" -c 'x=hello; echo ${#x}' 2>&1)
if [ "$result" = "5" ]; then
    pass "\${#var} string length"
else
    fail "\${#var} string length" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=""; echo ${#x}' 2>&1)
if [ "$result" = "0" ]; then
    pass "\${#var} empty string length"
else
    fail "\${#var} empty string length" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="hello world"; echo ${#x}' 2>&1)
if [ "$result" = "11" ]; then
    pass "\${#var} string with space"
else
    fail "\${#var} string with space" "11" "$result"
fi

# =====================================
section "405. PARAMETER EXPANSION ${var%pattern}"
# =====================================

result=$("$FORTSH_BIN" -c 'x="file.txt"; echo ${x%.txt}' 2>&1)
if [ "$result" = "file" ]; then
    pass "\${var%pattern} removes shortest suffix"
else
    fail "\${var%pattern} removes shortest suffix" "file" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="file.tar.gz"; echo ${x%.*}' 2>&1)
if [ "$result" = "file.tar" ]; then
    pass "\${var%.*} removes extension"
else
    fail "\${var%.*} removes extension" "file.tar" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="file.tar.gz"; echo ${x%%.*}' 2>&1)
if [ "$result" = "file" ]; then
    pass "\${var%%.*} removes all extensions"
else
    fail "\${var%%.*} removes all extensions" "file" "$result"
fi

# =====================================
section "406. PARAMETER EXPANSION ${var#pattern}"
# =====================================

result=$("$FORTSH_BIN" -c 'x="/path/to/file"; echo ${x#*/}' 2>&1)
if [ "$result" = "path/to/file" ]; then
    pass "\${var#*/} removes shortest prefix"
else
    fail "\${var#*/} removes shortest prefix" "path/to/file" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="/path/to/file"; echo ${x##*/}' 2>&1)
if [ "$result" = "file" ]; then
    pass "\${var##*/} basename extraction"
else
    fail "\${var##*/} basename extraction" "file" "$result"
fi

result=$("$FORTSH_BIN" -c 'x="prefix_name"; echo ${x#prefix_}' 2>&1)
if [ "$result" = "name" ]; then
    pass "\${var#prefix} removes literal prefix"
else
    fail "\${var#prefix} removes literal prefix" "name" "$result"
fi

# =====================================
section "407. BACKTICK COMMAND SUBSTITUTION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo `echo hello`' 2>&1)
if [ "$result" = "hello" ]; then
    pass "Basic backtick substitution"
else
    fail "Basic backtick substitution" "hello" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=`expr 2 + 3`; echo $x' 2>&1)
if [ "$result" = "5" ]; then
    pass "Backtick with expr"
else
    fail "Backtick with expr" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo `echo \`echo nested\``' 2>&1)
if [ "$result" = "nested" ]; then
    pass "Nested backtick substitution"
else
    fail "Nested backtick substitution" "nested" "$result"
fi

# =====================================
section "408. COMMAND SUBSTITUTION EDGE CASES"
# =====================================

result=$("$FORTSH_BIN" -c 'echo "$(echo "inner quotes")"' 2>&1)
if [ "$result" = "inner quotes" ]; then
    pass "\$(...) with inner quotes"
else
    fail "\$(...) with inner quotes" "inner quotes" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $(echo $(echo nested))' 2>&1)
if [ "$result" = "nested" ]; then
    pass "Nested \$(...) substitution"
else
    fail "Nested \$(...) substitution" "nested" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=$(cat <<EOF
multi
line
EOF
); echo "$x"' 2>&1)
expected=$(printf "multi\nline")
if [ "$result" = "$expected" ]; then
    pass "\$(...) with here-document inside"
else
    fail "\$(...) with here-document inside" "$expected" "$result"
fi

# =====================================
section "409. ARITHMETIC EXPANSION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo $((2 + 3))' 2>&1)
if [ "$result" = "5" ]; then
    pass "\$((...)) addition"
else
    fail "\$((...)) addition" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((10 - 3))' 2>&1)
if [ "$result" = "7" ]; then
    pass "\$((...)) subtraction"
else
    fail "\$((...)) subtraction" "7" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((4 * 5))' 2>&1)
if [ "$result" = "20" ]; then
    pass "\$((...)) multiplication"
else
    fail "\$((...)) multiplication" "20" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((20 / 4))' 2>&1)
if [ "$result" = "5" ]; then
    pass "\$((...)) division"
else
    fail "\$((...)) division" "5" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((17 % 5))' 2>&1)
if [ "$result" = "2" ]; then
    pass "\$((...)) modulo"
else
    fail "\$((...)) modulo" "2" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((x * 2))' 2>&1)
if [ "$result" = "10" ]; then
    pass "\$((...)) with variable (no \$)"
else
    fail "\$((...)) with variable (no \$)" "10" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $(($x * 2))' 2>&1)
if [ "$result" = "10" ]; then
    pass "\$((...)) with \$variable"
else
    fail "\$((...)) with \$variable" "10" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $(( (2 + 3) * 4 ))' 2>&1)
if [ "$result" = "20" ]; then
    pass "\$((...)) with parentheses"
else
    fail "\$((...)) with parentheses" "20" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((-5 + 3))' 2>&1)
if [ "$result" = "-2" ]; then
    pass "\$((...)) negative numbers"
else
    fail "\$((...)) negative numbers" "-2" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 > 3))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) greater than comparison"
else
    fail "\$((...)) greater than comparison" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((3 > 5))' 2>&1)
if [ "$result" = "0" ]; then
    pass "\$((...)) greater than false"
else
    fail "\$((...)) greater than false" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 < 10))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) less than comparison"
else
    fail "\$((...)) less than comparison" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 == 5))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) equality"
else
    fail "\$((...)) equality" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 != 3))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) inequality"
else
    fail "\$((...)) inequality" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 >= 5))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) greater or equal"
else
    fail "\$((...)) greater or equal" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((3 <= 5))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) less or equal"
else
    fail "\$((...)) less or equal" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((1 && 1))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) logical AND"
else
    fail "\$((...)) logical AND" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((1 && 0))' 2>&1)
if [ "$result" = "0" ]; then
    pass "\$((...)) logical AND false"
else
    fail "\$((...)) logical AND false" "0" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((0 || 1))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) logical OR"
else
    fail "\$((...)) logical OR" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((!0))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) logical NOT"
else
    fail "\$((...)) logical NOT" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 & 3))' 2>&1)
if [ "$result" = "1" ]; then
    pass "\$((...)) bitwise AND"
else
    fail "\$((...)) bitwise AND" "1" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 | 3))' 2>&1)
if [ "$result" = "7" ]; then
    pass "\$((...)) bitwise OR"
else
    fail "\$((...)) bitwise OR" "7" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 ^ 3))' 2>&1)
if [ "$result" = "6" ]; then
    pass "\$((...)) bitwise XOR"
else
    fail "\$((...)) bitwise XOR" "6" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((1 << 4))' 2>&1)
if [ "$result" = "16" ]; then
    pass "\$((...)) left shift"
else
    fail "\$((...)) left shift" "16" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((16 >> 2))' 2>&1)
if [ "$result" = "4" ]; then
    pass "\$((...)) right shift"
else
    fail "\$((...)) right shift" "4" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 > 3 ? 10 : 20))' 2>&1)
if [ "$result" = "10" ]; then
    pass "\$((...)) ternary true"
else
    fail "\$((...)) ternary true" "10" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $((5 < 3 ? 10 : 20))' 2>&1)
if [ "$result" = "20" ]; then
    pass "\$((...)) ternary false"
else
    fail "\$((...)) ternary false" "20" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((x += 3)); echo $x' 2>&1)
expected=$(printf "8\n8")
if [ "$result" = "$expected" ]; then
    pass "\$((...)) += assignment"
else
    fail "\$((...)) += assignment" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=10; echo $((x -= 3)); echo $x' 2>&1)
expected=$(printf "7\n7")
if [ "$result" = "$expected" ]; then
    pass "\$((...)) -= assignment"
else
    fail "\$((...)) -= assignment" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((x *= 3))' 2>&1)
if [ "$result" = "15" ]; then
    pass "\$((...)) *= assignment"
else
    fail "\$((...)) *= assignment" "15" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((++x)); echo $x' 2>&1)
expected=$(printf "6\n6")
if [ "$result" = "$expected" ]; then
    pass "\$((...)) pre-increment"
else
    fail "\$((...)) pre-increment" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((x++)); echo $x' 2>&1)
expected=$(printf "5\n6")
if [ "$result" = "$expected" ]; then
    pass "\$((...)) post-increment"
else
    fail "\$((...)) post-increment" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((--x)); echo $x' 2>&1)
expected=$(printf "4\n4")
if [ "$result" = "$expected" ]; then
    pass "\$((...)) pre-decrement"
else
    fail "\$((...)) pre-decrement" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=5; echo $((x--)); echo $x' 2>&1)
expected=$(printf "5\n4")
if [ "$result" = "$expected" ]; then
    pass "\$((...)) post-decrement"
else
    fail "\$((...)) post-decrement" "$expected" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo $(( 2 + 3 * 4 ))' 2>&1)
if [ "$result" = "14" ]; then
    pass "\$((...)) operator precedence"
else
    fail "\$((...)) operator precedence" "14" "$result"
fi

result=$("$FORTSH_BIN" -c 'a=2; b=3; echo $(( a * b + a ))' 2>&1)
if [ "$result" = "8" ]; then
    pass "\$((...)) multiple variables"
else
    fail "\$((...)) multiple variables" "8" "$result"
fi

# =====================================
section "410. TILDE EXPANSION"
# =====================================

result=$("$FORTSH_BIN" -c 'echo ~' 2>&1)
if [ "$result" = "$HOME" ]; then
    pass "~ expands to \$HOME"
else
    fail "~ expands to \$HOME" "$HOME" "$result"
fi

result=$("$FORTSH_BIN" -c 'echo ~/test' 2>&1)
if [ "$result" = "$HOME/test" ]; then
    pass "~/path expands correctly"
else
    fail "~/path expands correctly" "$HOME/test" "$result"
fi

result=$("$FORTSH_BIN" -c 'x=~; echo $x' 2>&1)
if [ "$result" = "$HOME" ]; then
    pass "~ in assignment expands"
else
    fail "~ in assignment expands" "$HOME" "$result"
fi

# =====================================
# Summary
# =====================================
printf "\n"
printf "${BLUE}==========================================\n"
printf "POSIX Here-Document and Expansion Summary\n"
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
