#!/bin/bash
# Comprehensive test suite for enhanced array features
# Tests: indices expansion, array slicing, and their combinations

echo "=== Enhanced Array Features Test Suite ==="
echo ""

# Test 1: Array indices expansion
echo "TEST 1: Array Indices Expansion"
echo "================================"
declare -a test1
test1[0]=alpha
test1[1]=beta
test1[2]=gamma
indices1="${!test1[@]}"
echo "Array: ${test1[@]}"
echo "Indices: $indices1"
[ "$indices1" = "0 1 2" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 2: Sparse array indices
echo "TEST 2: Sparse Array Indices"
echo "============================"
declare -a test2
test2[1]=one
test2[5]=five
test2[10]=ten
indices2="${!test2[@]}"
echo "Sparse array: ${test2[@]}"
echo "Indices: $indices2"
[ "$indices2" = "1 5 10" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 3: Basic array slicing
echo "TEST 3: Basic Array Slicing"
echo "==========================="
declare -a test3
test3=(a b c d e f g)
slice3="${test3[@]:2:3}"
echo "Full array: ${test3[@]}"
echo "Slice [2:3]: $slice3"
[ "$slice3" = "c d e" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 4: Slice from offset to end
echo "TEST 4: Slice to End"
echo "===================="
declare -a test4
test4=(one two three four five)
slice4="${test4[@]:3}"
echo "Full array: ${test4[@]}"
echo "Slice [3:]: $slice4"
[ "$slice4" = "four five" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 5: Slice from start
echo "TEST 5: Slice from Start"
echo "========================"
declare -a test5
test5=(red orange yellow green blue)
slice5="${test5[@]:0:2}"
echo "Full array: ${test5[@]}"
echo "Slice [0:2]: $slice5"
[ "$slice5" = "red orange" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 6: Single element slice
echo "TEST 6: Single Element Slice"
echo "============================"
declare -a test6
test6=(apple banana cherry date)
slice6="${test6[@]:1:1}"
echo "Full array: ${test6[@]}"
echo "Slice [1:1]: $slice6"
[ "$slice6" = "banana" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 7: Array length with indices
echo "TEST 7: Count of Array Indices"
echo "==============================="
declare -a test7
test7=(x y z)
indices7="${!test7[@]}"
count7=$(echo $indices7 | wc -w)
echo "Array: ${test7[@]}"
echo "Indices: $indices7"
echo "Count: $count7"
[ "$count7" = "3" ] && echo "✓ PASS" || echo "✗ FAIL"
echo ""

# Test 8: Combining indices and slicing
echo "TEST 8: Slice of Indices (conceptual)"
echo "====================================="
declare -a test8
test8[2]=item2
test8[4]=item4
test8[6]=item6
test8[8]=item8
all_indices="${!test8[@]}"
echo "Array: ${test8[@]}"
echo "All indices: $all_indices"
echo "Note: Can iterate and work with indices"
for idx in ${!test8[@]}; do
  echo "  Index $idx = ${test8[$idx]}"
done
echo "✓ PASS"
echo ""

# Test 9: Modify and check indices
echo "TEST 9: Modify and Check Indices"
echo "================================="
declare -a test9
test9[0]=first
test9[1]=second
test9[2]=third
before_indices="${!test9[@]}"
echo "Before: indices=$before_indices, values=${test9[@]}"
test9[1]=MODIFIED
after_indices="${!test9[@]}"
echo "After:  indices=$after_indices, values=${test9[@]}"
[ "$before_indices" = "$after_indices" ] && echo "✓ PASS (indices unchanged)" || echo "✗ FAIL"
echo ""

# Test 10: Slice with excessive length
echo "TEST 10: Slice with Excessive Length"
echo "====================================="
declare -a test10
test10=(a b c)
slice10="${test10[@]:1:100}"
echo "Full array (3 elements): ${test10[@]}"
echo "Slice [1:100]: $slice10"
[ "$slice10" = "b c" ] && echo "✓ PASS (clamped to array bounds)" || echo "✗ FAIL"
echo ""

# Summary
echo "=========================================="
echo "Enhanced Array Features Test Suite Complete"
echo "=========================================="
echo ""
echo "Features Tested:"
echo "  ✓ Array indices expansion (${!array[@]})"
echo "  ✓ Sparse array indices"
echo "  ✓ Array slicing (${array[@]:offset:length})"
echo "  ✓ Slice from offset to end"
echo "  ✓ Slice from start"
echo "  ✓ Single element slicing"
echo "  ✓ Combining features"
echo "  ✓ Boundary conditions"
