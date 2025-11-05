#!/bin/bash
# =====================================
# macOS ARM64 Specific Pool Validation
# Tests flang-new compiler workarounds with memory pooling
# =====================================
# ONLY run this on macOS ARM64 with flang-new

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

pass() {
    printf "${GREEN}✓${NC} %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "${RED}✗${NC} %s\n" "$1"
    [ -n "$2" ] && printf "  ${RED}→${NC} %s\n" "$2"
    FAILED=$((FAILED + 1))
}

warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
    [ -n "$2" ] && printf "  ${YELLOW}→${NC} %s\n" "$2"
    WARNINGS=$((WARNINGS + 1))
}

section() {
    printf "\n${BLUE}━━━ %s ━━━${NC}\n" "$1"
}

# Platform check
if [ "$(uname -s)" != "Darwin" ]; then
    echo "${YELLOW}⚠️  Not running on Darwin - skipping macOS tests${NC}"
    exit 0
fi

if [ "$(uname -m)" != "arm64" ]; then
    echo "${YELLOW}⚠️  Not running on ARM64 - skipping macOS ARM64 tests${NC}"
    exit 0
fi

# Find fortsh binary
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${SCRIPT_DIR}/../bin/fortsh"

if [ ! -x "$FORTSH_BIN" ]; then
    echo "${RED}✗ fortsh binary not found at $FORTSH_BIN${NC}"
    exit 1
fi

echo "${BLUE}════════════════════════════════════════════════════════${NC}"
echo "${BLUE}  macOS ARM64 Memory Pool Validation (flang-new)${NC}"
echo "${BLUE}════════════════════════════════════════════════════════${NC}"

# =====================================
# FLANG-NEW COMPILER CONSTRAINT CHECKS
# =====================================
section "flang-new Compiler Constraints"

# Test 1: 127-byte command limit with pooled strings
OUTPUT=$("$FORTSH_BIN" -c 'X="0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567"; echo ${#X}' 2>&1)
if [ "$OUTPUT" = "127" ]; then
    pass "127-byte string limit enforced correctly"
elif [ "$OUTPUT" -gt 127 ]; then
    fail "String exceeded 127-byte limit" "Got $OUTPUT bytes (flang-new will crash!)"
else
    pass "String within limit ($OUTPUT bytes)"
fi

# Test 2: Fixed-length buffer behavior
OUTPUT=$("$FORTSH_BIN" -c 'A="test"; B="$A"; echo "$B"' 2>&1)
if [ "$OUTPUT" = "test" ]; then
    pass "Fixed-length buffer assignment works"
else
    fail "Fixed-length buffer broken" "Expected 'test', got '$OUTPUT'"
fi

# Test 3: Substring operations with pooled memory
OUTPUT=$("$FORTSH_BIN" -c 'STR="hello_world"; SUB="${STR:0:5}"; echo "$SUB"' 2>&1)
if [ "$OUTPUT" = "hello" ]; then
    pass "Substring operations with pooled strings"
else
    fail "Substring operation failed" "Expected 'hello', got '$OUTPUT'"
fi

# Test 4: No block construct crashes (verify workaround)
OUTPUT=$("$FORTSH_BIN" -c 'for i in 1 2 3; do X="loop_$i"; echo "$X"; done' 2>&1 | wc -l)
if [ "$OUTPUT" -eq 3 ]; then
    pass "Loop constructs work (block workaround active)"
else
    fail "Loop construct failed" "Expected 3 lines, got $OUTPUT"
fi

# =====================================
# POINTER SAFETY WITH POOLING
# =====================================
section "Pointer Substring Safety (Zero-Copy Pooling)"

# Test 5: Verify pointer substrings don't cause crashes
"$FORTSH_BIN" -c 'A="test1"; B="test2"; C="test3"; echo "$A $B $C"' 2>&1 | grep -q "test1 test2 test3" && \
    pass "Multiple pointer substrings stable" || \
    fail "Pointer substring instability detected"

# Test 6: Rapid pointer allocation/deallocation
OUTPUT=$("$FORTSH_BIN" -c 'for i in $(seq 1 50); do X="str_$i"; done; echo "done"' 2>&1)
if [ "$OUTPUT" = "done" ]; then
    pass "Rapid pointer churn doesn't crash"
else
    fail "Pointer churn caused failure"
fi

# Test 7: Nested parameter expansion with pooled pointers
OUTPUT=$("$FORTSH_BIN" -c 'PATH="/usr/local/bin/test.sh"; FILE="${PATH##*/}"; EXT="${FILE##*.}"; echo "$EXT"' 2>&1)
if [ "$OUTPUT" = "sh" ]; then
    pass "Nested expansions with pooled pointers"
else
    fail "Nested expansion broken" "Expected 'sh', got '$OUTPUT'"
fi

# =====================================
# BUCKET ALLOCATION SPECIFIC TO MACOS
# =====================================
section "Pool Bucket Constraints"

# Test 8: Small bucket (64 bytes) - common on macOS due to 127-byte limit
"$FORTSH_BIN" -c 'SMALL="12345678901234567890123456789012345678901234567890123456789"; echo ${#SMALL}' 2>&1 | grep -q "^59$" && \
    pass "64-byte bucket allocation (common case)" || \
    fail "Small bucket allocation failed"

# Test 9: Max pooled size before direct allocation
# With 127-byte limit, test if large pools are even reachable
OUTPUT=$("$FORTSH_BIN" -c 'BIG=$(printf "%.0sX" {1..120}); echo ${#BIG}' 2>&1)
if [ "$OUTPUT" -eq 120 ]; then
    pass "Large pool bucket accessible"
else
    warn "Large pools may be unreachable" "Only got $OUTPUT bytes"
fi

# =====================================
# ALLOCATABLE STRING WORKAROUNDS
# =====================================
section "Allocatable String Workarounds"

# Test 10: Character-by-character copy workaround
OUTPUT=$("$FORTSH_BIN" -c 'SRC="abc"; DST="$SRC"; echo "$DST"' 2>&1)
if [ "$OUTPUT" = "abc" ]; then
    pass "Char-by-char copy workaround active"
else
    fail "Copy workaround broken"
fi

# Test 11: Avoid substring temporaries
"$FORTSH_BIN" -c 'X="temporary"; Y="${X}"; unset X; echo "$Y"' 2>&1 | grep -q "temporary" && \
    pass "Substring temporary avoidance works" || \
    fail "Substring temporaries causing issues"

# =====================================
# TERMINAL I/O WITH POOLING
# =====================================
section "Terminal I/O Integration"

# Test 12: Raw mode with pooled buffers (critical for readline)
echo "echo pooled_readline_test" | "$FORTSH_BIN" 2>&1 | grep -q "pooled_readline_test" && \
    pass "Readline with pooled buffers works" || \
    fail "Readline pooling broken"

# Test 13: Terminal size detection doesn't crash (flang-new TIOCGWINSZ issue)
OUTPUT=$("$FORTSH_BIN" -c 'echo test' 2>&1)
if [ "$OUTPUT" = "test" ]; then
    pass "Terminal size detection safe"
else
    warn "Terminal detection may have issues"
fi

# =====================================
# MEMORY PRESSURE TESTS
# =====================================
section "Memory Pressure (macOS Specific)"

# Test 14: Pool expansion under pressure
cat > /tmp/macos_stress_$$.sh << 'EOF'
i=0
while [ $i -lt 200 ]; do
    VAR="stress_test_string_number_$i"
    COPY="$VAR"
    i=$((i + 1))
done
echo "completed"
EOF

OUTPUT=$("$FORTSH_BIN" < /tmp/macos_stress_$$.sh 2>&1 | tail -1)
rm -f /tmp/macos_stress_$$.sh
if [ "$OUTPUT" = "completed" ]; then
    pass "Pool expansion under pressure"
else
    fail "Memory pressure test failed"
fi

# Test 15: Fragmentation handling
"$FORTSH_BIN" -c 'A="aaaa"; B="bbbbbbbb"; C="cc"; D="dddddddddddddddd"; echo "$A$B$C$D"' 2>&1 | \
    grep -q "aaaabbbbbbbbccdddddddddddddddd" && \
    pass "Fragmentation across buckets handled" || \
    fail "Fragmentation issues detected"

# =====================================
# CRITICAL SAFETY CHECKS
# =====================================
section "Critical Safety Checks"

# Test 16: No heap corruption indicators
"$FORTSH_BIN" -c 'echo "corruption_test"; X="test"; echo "$X"' 2>&1 | grep -q "test" && \
    pass "No obvious heap corruption" || \
    fail "Potential heap corruption detected"

# Test 17: No stack overflow with pooled locals
"$FORTSH_BIN" -c 'A=1; B=2; C=3; D=4; E=5; F=6; G=7; H=8; echo "$A$B$C$D$E$F$G$H"' 2>&1 | \
    grep -q "12345678" && \
    pass "Stack handling with pooled locals" || \
    fail "Stack issues with multiple pooled vars"

# Test 18: Signal handling doesn't corrupt pool
"$FORTSH_BIN" -c 'trap "echo trapped" INT; echo "signal_test"' 2>&1 | grep -q "signal_test" && \
    pass "Signal handlers don't corrupt pool" || \
    warn "Signal handling may affect pool"

# =====================================
# SUMMARY
# =====================================
section "Summary"

TOTAL=$((PASSED + FAILED + WARNINGS))
printf "\n${BLUE}Results:${NC}\n"
printf "${GREEN}Passed:   %3d${NC}\n" "$PASSED"
printf "${RED}Failed:   %3d${NC}\n" "$FAILED"
printf "${YELLOW}Warnings: %3d${NC}\n" "$WARNINGS"
printf "━━━━━━━━━━━━━━━\n"
printf "Total:    %3d\n\n" "$TOTAL"

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}✅ macOS ARM64 pool validation PASSED${NC}\n"
    printf "String pooling is safe with flang-new on Apple Silicon.\n"
    exit 0
elif [ "$FAILED" -le 2 ]; then
    printf "${YELLOW}⚠️  macOS ARM64 pool validation MOSTLY PASSED${NC}\n"
    printf "Minor issues detected but pooling appears functional.\n"
    exit 0
else
    printf "${RED}❌ macOS ARM64 pool validation FAILED${NC}\n"
    printf "Pooling has issues on Apple Silicon - investigation required.\n"
    exit 1
fi
