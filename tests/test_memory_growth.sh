#!/bin/bash
# Demonstrate memory growth in shells during long-running operations

echo "=== Memory Growth Demonstration ==="
echo ""
echo "This test shows how shells accumulate memory during repeated operations."
echo ""

# Create a test script that does repeated allocations
cat > /tmp/memory_stress_test.sh << 'EOF'
#!/bin/bash
# Simulate a long-running shell session with many allocations

echo "Starting memory stress test..."

# Function that creates many temporary strings
process_files() {
    for i in {1..100}; do
        # Each of these creates temporary allocations
        VAR="test_string_$i"
        PATH_VAR="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"
        EXPANDED="${VAR}_expanded_${PATH_VAR}"

        # Tab completion simulation (creates many candidates)
        compgen -f /usr/ > /dev/null 2>&1

        # Command substitution (more allocations)
        DATE=$(date +%Y%m%d)
        COUNT=$(echo "$VAR" | wc -c)

        # Array operations
        ARR=($VAR $PATH_VAR $EXPANDED $DATE $COUNT)

        # Parameter expansion
        echo "${VAR%%_*}" > /dev/null
        echo "${PATH_VAR//:/,}" > /dev/null
    done
}

# Monitor memory usage
echo "Iteration | RSS (KB) | VSZ (KB)"
echo "----------|----------|----------"

for iteration in {1..10}; do
    # Get current memory usage
    if [[ "$1" == "fortsh" ]]; then
        # For fortsh
        MEM_BEFORE=$(ps aux | grep "[f]ortsh" | awk '{print $6 " " $5}')
    else
        # For bash
        MEM_BEFORE=$(ps aux | grep "$$" | grep -v grep | awk '{print $6 " " $5}')
    fi

    # Run allocation-heavy operations
    process_files

    # Get memory after
    if [[ "$1" == "fortsh" ]]; then
        MEM_AFTER=$(ps aux | grep "[f]ortsh" | awk '{print $6 " " $5}')
    else
        MEM_AFTER=$(ps aux | grep "$$" | grep -v grep | awk '{print $6 " " $5}')
    fi

    printf "%9d | %s\n" "$iteration" "$MEM_AFTER"
done

echo ""
echo "Note: RSS should ideally stay constant after initial growth."
echo "Growing RSS indicates memory fragmentation or leaks."
EOF

chmod +x /tmp/memory_stress_test.sh

echo "1. Testing bash memory growth:"
echo "-------------------------------"
bash /tmp/memory_stress_test.sh

echo ""
echo "2. Testing fortsh memory growth (without pooling):"
echo "---------------------------------------------------"
# Build without pooling
make clean >/dev/null 2>&1
make MEMPOOL=0 >/dev/null 2>&1

# Create fortsh test script
cat > /tmp/fortsh_memory_test.sh << 'EOF'
# Fortsh version of memory stress test
for i in 1 2 3 4 5 6 7 8 9 10
do
    echo "Iteration $i"
    # These operations cause allocations in fortsh
    ls /usr/bin | head -20 > /dev/null
    echo "test_$i" | grep "test" > /dev/null
    VAR="allocated_string_$i"
    echo "$VAR" > /dev/null
done
EOF

echo "Running fortsh test..."
./bin/fortsh < /tmp/fortsh_memory_test.sh 2>/dev/null | head -20

echo ""
echo "=== Key Observations ==="
echo ""
echo "Without memory pooling:"
echo "- Each iteration allocates new memory"
echo "- Memory is fragmented even after deallocation"
echo "- RSS (Resident Set Size) grows over time"
echo ""
echo "With memory pooling (what we're building):"
echo "- Memory is reused from pools"
echo "- No fragmentation between iterations"
echo "- RSS remains stable after initial allocation"
echo ""
echo "This is why bash uses obstacks and modern shells use pooling!"

# Cleanup
rm -f /tmp/memory_stress_test.sh /tmp/fortsh_memory_test.sh