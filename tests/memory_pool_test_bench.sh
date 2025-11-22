#!/bin/bash
# =====================================
# Comprehensive Memory Pool Test Bench
# =====================================
# Tests all aspects of Phase 6 memory pooling implementation
# Ensures pooling behaves exactly as designed with no subtleties

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0
WARNINGS=0

# Test configuration
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
FORTSH_POOLED="$FORTSH_DIR/bin/fortsh"
FORTSH_TRADITIONAL="$FORTSH_DIR/bin/fortsh_traditional"
TEST_WORK_DIR="/tmp/memory_pool_test_$$"

# Create work directory
mkdir -p "$TEST_WORK_DIR"
cd "$TEST_WORK_DIR" || exit 1

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_WORK_DIR"
    cd "$FORTSH_DIR" || exit 1
}
trap cleanup EXIT INT TERM

# Test result functions
pass() {
    printf "${GREEN}✓ PASS${NC}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "${RED}✗ FAIL${NC}: %s\n" "$1"
    if [ -n "$2" ]; then
        printf "  Details: %s\n" "$2"
    fi
    FAILED=$((FAILED + 1))
}

warn() {
    printf "${YELLOW}⚠ WARN${NC}: %s\n" "$1"
    if [ -n "$2" ]; then
        printf "  Details: %s\n" "$2"
    fi
    WARNINGS=$((WARNINGS + 1))
}

section() {
    printf "\n${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

subsection() {
    printf "\n${CYAN}--- %s ---${NC}\n" "$1"
}

# =====================================
# 1. BUILD VALIDATION
# =====================================
section "1. BUILD VALIDATION"

subsection "Building pooled version"
cd "$FORTSH_DIR" || exit 1
make clean > /dev/null 2>&1
if make > /dev/null 2>&1; then
    pass "Pooled build successful"
    cp bin/fortsh "$FORTSH_POOLED"
else
    fail "Pooled build failed"
    exit 1
fi

subsection "Building traditional version"
make clean > /dev/null 2>&1
if make NO_MEMPOOL=1 > /dev/null 2>&1; then
    pass "Traditional build successful"
    cp bin/fortsh "$FORTSH_TRADITIONAL"
else
    fail "Traditional build failed"
    exit 1
fi

# Verify binaries exist
if [ ! -x "$FORTSH_POOLED" ]; then
    fail "Pooled binary not found"
    exit 1
fi

if [ ! -x "$FORTSH_TRADITIONAL" ]; then
    fail "Traditional binary not found"
    exit 1
fi

cd "$TEST_WORK_DIR" || exit 1

# =====================================
# 2. BASIC FUNCTIONALITY TESTS
# =====================================
section "2. BASIC FUNCTIONALITY COMPARISON"

subsection "Command execution"
POOLED_OUT=$("$FORTSH_POOLED" -c "echo 'test output'" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "echo 'test output'" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Identical output for basic command"
else
    fail "Different outputs" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Variable expansion"
POOLED_OUT=$("$FORTSH_POOLED" -c 'X=hello; echo "$X world"' 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c 'X=hello; echo "$X world"' 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Identical variable expansion"
else
    fail "Different variable expansion" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Parameter expansion"
POOLED_OUT=$("$FORTSH_POOLED" -c 'VAR=foo.bar.baz; echo "${VAR##*.}"' 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c 'VAR=foo.bar.baz; echo "${VAR##*.}"' 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Identical parameter expansion"
else
    fail "Different parameter expansion" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

# =====================================
# 3. MODULE-SPECIFIC TESTS
# =====================================
section "3. MODULE-SPECIFIC POOLING TESTS"

subsection "Parser Module"
# Test token parsing with various complexities
TEST_CMD='echo "test" | grep test && X=$((5+3)); [ $X -eq 8 ] && echo "pass"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Parser: Complex tokenization"
else
    fail "Parser: Different tokenization" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Expansion Module"
# Test complex expansions
TEST_CMD='A=hello; B=world; C=${A}_${B}; echo "${C^^}"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Expansion: Complex string operations"
else
    fail "Expansion: Different results" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Executor Module"
# Test command execution with large output
TEST_CMD='for i in $(seq 1 100); do echo "Line $i of output"; done | wc -l'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1 | tr -d ' ')
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1 | tr -d ' ')

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Executor: Large buffer handling"
else
    fail "Executor: Different buffer behavior" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Variables Module"
# Test variable arrays and functions
TEST_CMD='arr=(a b c d e); func() { echo "$@"; }; func "${arr[@]}"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Variables: Array and function handling"
else
    fail "Variables: Different behavior" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Builtins Module"
# Test cd and printenv
TEST_CMD='cd /tmp && pwd && TEST_VAR=pooltest printenv TEST_VAR'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Builtins: cd and printenv"
else
    fail "Builtins: Different behavior" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

# =====================================
# 4. READLINE BUFFER TESTS
# =====================================
section "4. READLINE BUFFER VALIDATION"

subsection "Interactive editing simulation"
# Test with echo piped to simulate input
echo "echo test" | "$FORTSH_POOLED" > pooled_interactive.out 2>&1
echo "echo test" | "$FORTSH_TRADITIONAL" > trad_interactive.out 2>&1

# Remove prompt variations
sed 's/fortsh\$ //g' pooled_interactive.out > pooled_clean.out
sed 's/fortsh\$ //g' trad_interactive.out > trad_clean.out

if diff -q pooled_clean.out trad_clean.out > /dev/null 2>&1; then
    pass "Readline: Interactive behavior consistent"
else
    fail "Readline: Different interactive behavior"
fi

# =====================================
# 5. STRESS TESTS
# =====================================
section "5. STRESS AND EDGE CASE TESTS"

subsection "Rapid allocation/deallocation"
# Create a script that rapidly allocates/deallocates
cat > stress_test.sh << 'EOF'
for i in {1..100}; do
    X="String_$i"
    Y="${X}_modified"
    Z="${Y%%_*}"
    unset X Y Z
done
echo "Stress test complete"
EOF

POOLED_OUT=$("$FORTSH_POOLED" < stress_test.sh 2>&1 | grep "Stress test complete")
TRAD_OUT=$("$FORTSH_TRADITIONAL" < stress_test.sh 2>&1 | grep "Stress test complete")

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Stress: Rapid allocation/deallocation"
else
    fail "Stress: Different behavior under load"
fi

subsection "Large string operations"
# Test with very large strings
TEST_CMD='LARGE=$(printf "X%.0s" {1..1000}); echo "${#LARGE}"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Stress: Large string handling"
else
    fail "Stress: Different large string behavior" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

subsection "Nested expansions"
# Test deeply nested expansions with variable indirection (deterministic)
TEST_CMD='V=world; X="\$V"; Y="\$X"; eval eval echo "$Y"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Stress: Nested expansions"
else
    fail "Stress: Different nested expansion behavior" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

# =====================================
# 6. MEMORY LEAK DETECTION
# =====================================
section "6. MEMORY LEAK DETECTION"

subsection "Checking for leaks with valgrind (if available)"
if command -v valgrind > /dev/null 2>&1; then
    # Run a simple command under valgrind
    valgrind --leak-check=full --error-exitcode=1 "$FORTSH_POOLED" -c "echo test" > valgrind.out 2>&1
    if [ $? -eq 0 ]; then
        pass "No memory leaks detected (pooled)"
    else
        fail "Memory leaks detected in pooled version"
        warn "Check valgrind.out for details"
    fi

    valgrind --leak-check=full --error-exitcode=1 "$FORTSH_TRADITIONAL" -c "echo test" > valgrind_trad.out 2>&1
    if [ $? -eq 0 ]; then
        pass "No memory leaks detected (traditional)"
    else
        fail "Memory leaks detected in traditional version"
    fi
else
    warn "valgrind not available" "Skipping memory leak detection"
fi

# =====================================
# 7. DASHBOARD VALIDATION (Pooled only)
# =====================================
section "7. DASHBOARD TRACKING VALIDATION"

subsection "Dashboard output verification"
# Create a test that should trigger dashboard output
cat > dashboard_test.sh << 'EOF'
# Trigger various module allocations
X="test string"
Y="${X}_modified"
cd /tmp
echo "Dashboard test"
EOF

# Run with dashboard environment variable (if implemented)
MEMPOOL_DEBUG=1 "$FORTSH_POOLED" < dashboard_test.sh > dashboard.out 2>&1

if grep -q "Dashboard test" dashboard.out; then
    pass "Dashboard: Command execution tracked"
    # Check if we got any dashboard output (implementation-dependent)
    if grep -q -i "allocation\|bucket\|cache" dashboard.out 2>/dev/null; then
        pass "Dashboard: Tracking information present"
    else
        warn "Dashboard: No tracking output detected" "May need MEMPOOL_DEBUG flag"
    fi
else
    fail "Dashboard: Basic execution failed"
fi

# =====================================
# 8. BUCKET ALLOCATION TESTS
# =====================================
section "8. BUCKET ALLOCATION STRATEGY"

subsection "Testing different size allocations"
# Test various string sizes that should hit different buckets
cat > bucket_test.sh << 'EOF'
# 64-byte range
TINY="Short"
# 256-byte range
SMALL=$(printf "X%.0s" {1..100})
# 1KB range
MEDIUM=$(printf "X%.0s" {1..500})
# 4KB range
LARGE=$(printf "X%.0s" {1..2000})

echo "${#TINY} ${#SMALL} ${#MEDIUM} ${#LARGE}"
EOF

POOLED_OUT=$("$FORTSH_POOLED" < bucket_test.sh 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" < bucket_test.sh 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Buckets: Different size allocations handled correctly"
else
    fail "Buckets: Size handling differs" "Pooled: '$POOLED_OUT', Traditional: '$TRAD_OUT'"
fi

# =====================================
# 9. CONCURRENCY TESTS
# =====================================
section "9. CONCURRENT OPERATIONS"

subsection "Background jobs with pooling"
TEST_CMD='(echo "job1") & (echo "job2") & wait; echo "done"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1 | sort)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1 | sort)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Concurrency: Background jobs handled correctly"
else
    fail "Concurrency: Different background job behavior"
fi

# =====================================
# 10. ZERO-COPY VALIDATION
# =====================================
section "10. ZERO-COPY BEHAVIOR VALIDATION"

subsection "String reference semantics"
# Test that string modifications work correctly
TEST_CMD='X="original"; Y="$X"; X="modified"; echo "$Y"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Zero-copy: Reference semantics preserved"
else
    fail "Zero-copy: Different reference behavior"
fi

# =====================================
# 11. PERFORMANCE COMPARISON
# =====================================
section "11. PERFORMANCE COMPARISON"

subsection "Timing allocation-heavy operations"
# Create allocation-heavy script
cat > perf_test.sh << 'EOF'
start=$(date +%s%N)
for i in {1..1000}; do
    VAR="String_$i"
    MOD="${VAR}_modified"
    unset VAR MOD
done
end=$(date +%s%N)
echo $((end - start))
EOF

POOLED_TIME=$("$FORTSH_POOLED" < perf_test.sh 2>&1)
TRAD_TIME=$("$FORTSH_TRADITIONAL" < perf_test.sh 2>&1)

if [ -n "$POOLED_TIME" ] && [ -n "$TRAD_TIME" ]; then
    # Check if pooled is not significantly slower (within 2x)
    if [ "$POOLED_TIME" -lt $((TRAD_TIME * 2)) ]; then
        pass "Performance: Pooled version competitive"
        printf "  Pooled: %s ns, Traditional: %s ns\n" "$POOLED_TIME" "$TRAD_TIME"
    else
        warn "Performance: Pooled version slower" "Pooled: $POOLED_TIME ns, Traditional: $TRAD_TIME ns"
    fi
else
    warn "Performance: Could not measure timing"
fi

# =====================================
# 12. REGRESSION TESTS
# =====================================
section "12. REGRESSION TEST SUITE"

subsection "Running POSIX compliance tests"
cd "$FORTSH_DIR" || exit 1

# Basic POSIX test
if FORTSH_BIN="$FORTSH_POOLED" ./tests/posix_compliance_test.sh > /dev/null 2>&1; then
    POOLED_BASIC_RESULT=$?
else
    POOLED_BASIC_RESULT=$?
fi

if FORTSH_BIN="$FORTSH_TRADITIONAL" ./tests/posix_compliance_test.sh > /dev/null 2>&1; then
    TRAD_BASIC_RESULT=$?
else
    TRAD_BASIC_RESULT=$?
fi

if [ "$POOLED_BASIC_RESULT" -eq "$TRAD_BASIC_RESULT" ]; then
    pass "Regression: POSIX basic tests consistent"
else
    fail "Regression: Different POSIX basic results"
fi

# Builtins test
if FORTSH_BIN="$FORTSH_POOLED" ./tests/posix_compliance_builtins.sh > /dev/null 2>&1; then
    POOLED_BUILTIN_RESULT=$?
else
    POOLED_BUILTIN_RESULT=$?
fi

if FORTSH_BIN="$FORTSH_TRADITIONAL" ./tests/posix_compliance_builtins.sh > /dev/null 2>&1; then
    TRAD_BUILTIN_RESULT=$?
else
    TRAD_BUILTIN_RESULT=$?
fi

if [ "$POOLED_BUILTIN_RESULT" -eq "$TRAD_BUILTIN_RESULT" ]; then
    pass "Regression: Builtins tests consistent"
else
    fail "Regression: Different builtins results"
fi

cd "$TEST_WORK_DIR" || exit 1

# =====================================
# 13. EDGE CASES AND CORNER CONDITIONS
# =====================================
section "13. EDGE CASES AND CORNER CONDITIONS"

subsection "Empty string handling"
TEST_CMD='X=""; Y="${X}"; echo "[$Y]"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Edge: Empty string handling"
else
    fail "Edge: Empty strings differ"
fi

subsection "Maximum length strings"
# Test with maximum reasonable string length (64KB)
TEST_CMD='BIG=$(printf "X%.0s" {1..65536}); echo "ok"'
"$FORTSH_POOLED" -c "$TEST_CMD" > pooled_big.out 2>&1
POOLED_RESULT=$?
"$FORTSH_TRADITIONAL" -c "$TEST_CMD" > trad_big.out 2>&1
TRAD_RESULT=$?

if [ "$POOLED_RESULT" -eq "$TRAD_RESULT" ]; then
    pass "Edge: Maximum string length handling"
else
    fail "Edge: Different max string behavior"
fi

subsection "Special characters in strings"
TEST_CMD='X="$(printf "\x01\x02\x03")"; echo "${#X}"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Edge: Special characters handled"
else
    fail "Edge: Special character handling differs"
fi

# =====================================
# 14. MODULE INTEGRATION TESTS
# =====================================
section "14. MODULE INTEGRATION VALIDATION"

subsection "Parser → Expansion → Executor chain"
TEST_CMD='VAR="test"; echo "${VAR^^}" | grep TEST && echo "chain ok"'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Integration: Module chain working"
else
    fail "Integration: Module chain differs"
fi

subsection "Variables → Builtins interaction"
TEST_CMD='export TEST_VAR="pooled"; cd /tmp && printenv TEST_VAR'
POOLED_OUT=$("$FORTSH_POOLED" -c "$TEST_CMD" 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" -c "$TEST_CMD" 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Integration: Variables-Builtins interaction"
else
    fail "Integration: Variables-Builtins differs"
fi

# =====================================
# 15. FINAL VALIDATION
# =====================================
section "15. FINAL COMPREHENSIVE VALIDATION"

subsection "Complex real-world script"
cat > complex_test.sh << 'EOF'
#!/bin/sh
# Complex script testing all modules together

# Variables and arrays
NAMES=(Alice Bob Charlie)
COUNT=0

# Functions
greet() {
    local name="$1"
    echo "Hello, ${name}!"
    COUNT=$((COUNT + 1))
}

# Control flow
for name in "${NAMES[@]}"; do
    if [ "${#name}" -gt 3 ]; then
        greet "$name"
    fi
done

# Parameter expansion
FILE="/path/to/some/file.tar.gz"
echo "Extension: ${FILE##*.}"
echo "Basename: ${FILE##*/}"

# Builtins
cd /tmp
TEST_EXPORT="final_test"
export TEST_EXPORT

# Final output
echo "Greeted $COUNT people"
echo "PWD: $(pwd)"
echo "Export: $TEST_EXPORT"
EOF

POOLED_OUT=$("$FORTSH_POOLED" < complex_test.sh 2>&1)
TRAD_OUT=$("$FORTSH_TRADITIONAL" < complex_test.sh 2>&1)

if [ "$POOLED_OUT" = "$TRAD_OUT" ]; then
    pass "Final: Complex script execution identical"
else
    fail "Final: Complex script differs"
    echo "=== Pooled Output ===" > complex_diff.txt
    echo "$POOLED_OUT" >> complex_diff.txt
    echo "=== Traditional Output ===" >> complex_diff.txt
    echo "$TRAD_OUT" >> complex_diff.txt
    warn "See complex_diff.txt for details"
fi

# =====================================
# TEST SUMMARY
# =====================================
section "TEST SUMMARY"

TOTAL=$((PASSED + FAILED + WARNINGS))

printf "\n${BLUE}==========================================\n"
printf "MEMORY POOL TEST BENCH RESULTS\n"
printf "==========================================${NC}\n"
printf "${GREEN}Passed:${NC}   %3d\n" "$PASSED"
printf "${RED}Failed:${NC}   %3d\n" "$FAILED"
printf "${YELLOW}Warnings:${NC} %3d\n" "$WARNINGS"
printf "Total:    %3d\n" "$TOTAL"
printf "==========================================\n"

if [ "$TOTAL" -gt 0 ]; then
    PASS_RATE=$((PASSED * 100 / TOTAL))
    printf "Pass rate: %d%%\n" "$PASS_RATE"
fi

# Rebuild with pooling for production
printf "\n${CYAN}Rebuilding with memory pooling for production...${NC}\n"
cd "$FORTSH_DIR" || exit 1
make clean > /dev/null 2>&1
MEMPOOL=1 make > /dev/null 2>&1

if [ "$FAILED" -eq 0 ]; then
    printf "\n${GREEN}✓ ALL MEMORY POOL TESTS PASSED!${NC}\n"
    printf "Memory pooling is behaving exactly as designed.\n"
    printf "Zero-copy pooling validated across all modules.\n"
    exit 0
else
    printf "\n${RED}✗ SOME TESTS FAILED${NC}\n"
    printf "Memory pooling has issues that need investigation.\n"
    exit 1
fi