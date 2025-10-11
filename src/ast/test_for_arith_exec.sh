#!/bin/bash
# Test script to verify arithmetic for loop execution

echo "=== Test 1: Basic for loop ==="
for ((i=0; i<3; i++)); do echo "i=$i"; done

echo ""
echo "=== Test 2: Loop with increment by 2 ==="
for ((x=1; x<=5; x=x+2)); do echo "x=$x"; done

echo ""
echo "=== Test 3: Countdown loop ==="
for ((n=5; n>0; n--)); do echo "n=$n"; done
