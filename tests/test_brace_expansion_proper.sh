#!/bin/bash
# Proper brace expansion tests (unquoted, as used in real shells)

echo "=== Proper Brace Expansion Tests ==="
echo ""

# Test 1: List expansion with echo
echo "TEST 1: echo {a,b,c}"
echo "===================="
echo {a,b,c}
echo "Expected: a b c (or: a b c on separate line)"
echo "✓ PASS (if you see: a b c above)"
echo ""

# Test 2: Numeric range
echo "TEST 2: echo {1..5}"
echo "==================="
echo {1..5}
echo "Expected: 1 2 3 4 5"
echo "✓ PASS (if correct above)"
echo ""

# Test 3: Descending numeric range
echo "TEST 3: echo {5..1}"
echo "==================="
echo {5..1}
echo "Expected: 5 4 3 2 1"
echo "✓ PASS (if correct above)"
echo ""

# Test 4: Alphabetic range
echo "TEST 4: echo {a..e}"
echo "==================="
echo {a..e}
echo "Expected: a b c d e"
echo "✓ PASS (if correct above)"
echo ""

# Test 5: Step expansion
echo "TEST 5: echo {1..10..2}"
echo "======================="
echo {1..10..2}
echo "Expected: 1 3 5 7 9"
echo "✓ PASS (if correct above)"
echo ""

# Test 6: Alphabetic with step
echo "TEST 6: echo {a..z..5}"
echo "======================"
echo {a..z..5}
echo "Expected: a f k p u z"
echo "✓ PASS (if correct above)"
echo ""

# Test 7: Mixed items
echo "TEST 7: echo {red,green,blue}"
echo "=============================="
echo {red,green,blue}
echo "Expected: red green blue"
echo "✓ PASS (if correct above)"
echo ""

# Test 8: Single item (no expansion)
echo "TEST 8: echo {single}"
echo "====================="
echo {single}
echo "Expected: {single} (no expansion)"
echo "✓ PASS (if correct above)"
echo ""

# Test 9: No braces
echo "TEST 9: echo normal"
echo "==================="
echo normal
echo "Expected: normal"
echo "✓ PASS (if correct above)"
echo ""

# Test 10: Range with for loop
echo "TEST 10: for loop with {1..3}"
echo "=============================="
for i in {1..3}; do
  echo "  Iteration $i"
done
echo "Expected: Iteration 1, 2, 3"
echo "✓ PASS (if correct above)"
echo ""

# Test 11: Multiple braces in one command
echo "TEST 11: echo {a,b} {1,2}"
echo "========================="
echo {a,b} {1,2}
echo "Expected: a b 1 2"
echo "✓ PASS (if correct above)"
echo ""

# Test 12: Descending with step
echo "TEST 12: echo {10..1..2}"
echo "========================"
echo {10..1..2}
echo "Expected: 10 8 6 4 2"
echo "✓ PASS (if correct above)"
echo ""

# Summary
echo "========================================="
echo "Brace Expansion Test Complete"
echo "========================================="
echo ""
echo "Manual verification required."
echo "Compare actual output with expected output above."
echo ""
echo "Features tested:"
echo "  - List expansion: {a,b,c}"
echo "  - Numeric ranges: {1..10}"
echo "  - Alphabetic ranges: {a..z}"
echo "  - Step expansion: {1..10..2}"
echo "  - Descending ranges"
echo "  - Multiple brace groups"
echo "  - For loop integration"
