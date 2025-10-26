#!/bin/bash
# Performance test for memory pooling feature

echo "=== Memory Pool Performance Test ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test command that exercises syntax highlighting
TEST_CMD='ls -la | grep ".f90" | head -5 ; echo "test $VAR" ; cd /tmp && pwd'

# Function to measure performance
measure_performance() {
    local binary=$1
    local label=$2

    echo -e "${YELLOW}Testing: $label${NC}"

    # Measure memory usage and timing
    echo "1. Memory test (100 iterations of syntax highlighting):"

    # Create a test script that exercises the highlighting
    cat > /tmp/fortsh_test.sh << 'EOF'
for i in {1..100}; do
    echo 'ls -la /usr/bin | grep "^-" | wc -l'
    echo 'echo "Testing variable $HOME and path /etc/passwd"'
    echo 'if [ -f /etc/passwd ]; then echo "found"; fi'
done
EOF

    # Time the execution
    TIME_OUTPUT=$(/usr/bin/time -v $binary < /tmp/fortsh_test.sh 2>&1 | grep -E "(User time|System time|Maximum resident|wall clock)")

    echo "$TIME_OUTPUT"

    # Interactive test with valgrind (if available)
    if command -v valgrind > /dev/null 2>&1; then
        echo ""
        echo "2. Memory leak check (quick test):"
        echo "$TEST_CMD" | valgrind --leak-check=summary --track-origins=yes $binary 2>&1 | grep -E "(definitely lost|indirectly lost|possibly lost|LEAK SUMMARY)" | head -10
    fi

    echo ""
}

# Build without memory pool
echo -e "${GREEN}Building WITHOUT memory pooling...${NC}"
make clean > /dev/null 2>&1
make MEMPOOL=0 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed without memory pool${NC}"
    exit 1
fi

cp bin/fortsh bin/fortsh_no_pool
measure_performance "bin/fortsh_no_pool" "WITHOUT Memory Pool"

# Build with memory pool
echo -e "${GREEN}Building WITH memory pooling...${NC}"
make clean > /dev/null 2>&1
make MEMPOOL=1 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed with memory pool${NC}"
    exit 1
fi

cp bin/fortsh bin/fortsh_with_pool
measure_performance "bin/fortsh_with_pool" "WITH Memory Pool"

# Quick interactive test
echo -e "${YELLOW}=== Quick Interactive Comparison ===${NC}"
echo "Testing command completion and highlighting..."

echo ""
echo "WITHOUT pool - Typing test:"
echo "$TEST_CMD" | bin/fortsh_no_pool 2>/dev/null | head -5

echo ""
echo "WITH pool - Typing test:"
echo "$TEST_CMD" | bin/fortsh_with_pool 2>/dev/null | head -5

# Run the memory pool test if it exists
if [ -f tests/test_memory_pool ]; then
    echo ""
    echo -e "${YELLOW}=== Memory Pool Unit Tests ===${NC}"
    ./tests/test_memory_pool
fi

echo ""
echo -e "${GREEN}=== Performance Test Complete ===${NC}"
echo "Compare the 'Maximum resident set size' and timing values above."
echo "Lower memory usage and faster times indicate improvement."