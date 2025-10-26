#!/bin/bash
# Simple performance test for memory pooling

echo "=== Simple Memory Pool Performance Test ==="
echo ""

# Create test input that exercises syntax highlighting heavily
cat > /tmp/fortsh_perf_test.txt << 'EOF'
echo "Testing syntax highlighting with many tokens"
ls -la | grep pattern | sort | head -n 10
cd /usr/local/bin && pwd && ls
export VAR1="value1" VAR2="value2" VAR3="value3"
if [ -f /etc/passwd ]; then echo "File exists"; else echo "Not found"; fi
for i in 1 2 3 4 5; do echo "Number: $i"; done
function test() { echo "Function $1 $2 $3"; }
test arg1 arg2 arg3
# This is a comment with $VARIABLES and /paths/to/files
echo "String with \"quotes\" and 'single quotes' mixed"
VAR=$((10 + 20 * 3))
echo "Result: $VAR"
[ 5 -gt 3 ] && echo "Greater" || echo "Lesser"
find /tmp -name "*.txt" -exec echo {} \;
grep -E "pattern[0-9]+" file.txt | sed 's/old/new/g'
EOF

# Repeat the input to stress test
for i in {1..20}; do
    cat /tmp/fortsh_perf_test.txt >> /tmp/fortsh_perf_full.txt
done

echo "Test input size: $(wc -l /tmp/fortsh_perf_full.txt | awk '{print $1}') lines"
echo ""

# Build and test WITHOUT memory pool
echo "1. Building WITHOUT memory pool..."
make clean >/dev/null 2>&1
make MEMPOOL=0 >/dev/null 2>&1

echo "   Running performance test..."
START=$(date +%s%N)
./bin/fortsh < /tmp/fortsh_perf_full.txt > /dev/null 2>&1
END=$(date +%s%N)
TIME_NO_POOL=$((($END - $START) / 1000000))
echo "   Time: ${TIME_NO_POOL}ms"

# Get memory stats if possible
if command -v /usr/bin/time >/dev/null 2>&1; then
    MEMSTATS=$(/usr/bin/time -f "   Memory: %MKB peak" ./bin/fortsh < /tmp/fortsh_perf_full.txt 2>&1 >/dev/null | grep Memory)
    echo "$MEMSTATS"
fi

echo ""

# Build and test WITH memory pool
echo "2. Building WITH memory pool..."
make clean >/dev/null 2>&1
make MEMPOOL=1 >/dev/null 2>&1

echo "   Running performance test..."
START=$(date +%s%N)
./bin/fortsh < /tmp/fortsh_perf_full.txt > /dev/null 2>&1
END=$(date +%s%N)
TIME_WITH_POOL=$((($END - $START) / 1000000))
echo "   Time: ${TIME_WITH_POOL}ms"

# Get memory stats if possible
if command -v /usr/bin/time >/dev/null 2>&1; then
    MEMSTATS=$(/usr/bin/time -f "   Memory: %MKB peak" ./bin/fortsh < /tmp/fortsh_perf_full.txt 2>&1 >/dev/null | grep Memory)
    echo "$MEMSTATS"
fi

echo ""
echo "=== Summary ==="
echo "Without pool: ${TIME_NO_POOL}ms"
echo "With pool:    ${TIME_WITH_POOL}ms"

if [ $TIME_WITH_POOL -lt $TIME_NO_POOL ]; then
    IMPROVEMENT=$(( ($TIME_NO_POOL - $TIME_WITH_POOL) * 100 / $TIME_NO_POOL ))
    echo "Improvement:  ${IMPROVEMENT}% faster with pooling"
else
    DEGRADATION=$(( ($TIME_WITH_POOL - $TIME_NO_POOL) * 100 / $TIME_NO_POOL ))
    echo "Degradation:  ${DEGRADATION}% slower with pooling"
fi

# Cleanup
rm -f /tmp/fortsh_perf_test.txt /tmp/fortsh_perf_full.txt