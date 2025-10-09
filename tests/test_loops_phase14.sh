#!/bin/bash
# Phase 14 Loop Tests - Variable Scoping & Expansion Fixes
# Run with: cat tests/test_loops_phase14.sh | ./bin/fortsh

echo "========================================="
echo "Phase 14 Test Suite: Loop Execution"
echo "========================================="
echo ""

echo "Test 1: Basic for loop"
echo "-----------------------"
for fruit in apple banana cherry
do
  echo "  Fruit: $fruit"
done
echo ""

echo "Test 2: Arithmetic for loop (no space)"
echo "---------------------------------------"
for((i=0;i<5;i++))
do
  echo "  Count: $i"
done
echo ""

echo "Test 3: Arithmetic for loop with increment"
echo "--------------------------------------------"
for((i=2;i<=10;i+=2))
do
  echo "  Even: $i"
done
echo ""

echo "Test 4: Sequential loops (different variables)"
echo "------------------------------------------------"
for letter in A B C
do
  echo "  Letter: $letter"
done
for((n=1;n<=3;n++))
do
  echo "  Number: $n"
done
echo ""

echo "Test 5: Variable expansion in loops"
echo "-------------------------------------"
prefix="Item"
for x in first second third
do
  echo "  $prefix: $x"
done
echo ""

echo "Test 6: Loop with command substitution"
echo "----------------------------------------"
for word in one two three
do
  echo "  Word has ${#word} letters"
done
echo ""

echo "========================================="
echo "Known Limitations:"
echo "========================================="
echo "1. Nested loops do not work correctly"
echo "2. Requires for(( syntax without space"
echo "3. Loop variables persist after loop ends"
echo ""

echo "========================================="
echo "Test Complete"
echo "========================================="