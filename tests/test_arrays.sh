#!/bin/bash
# Test array functionality

echo "=== Array Tests ==="

# Test 1: Array declaration
echo "Test 1: Array declaration"
declare -a myarray
echo "Array declared: PASS"

# Test 2: Array assignment
echo ""
echo "Test 2: Array assignment"
myarray[0]=apple
myarray[1]=banana
myarray[2]=cherry
echo "Array elements assigned: PASS"

# Test 3: Array element access
echo ""
echo "Test 3: Array element access"
echo "myarray[0] = ${myarray[0]}"
echo "myarray[1] = ${myarray[1]}"
echo "myarray[2] = ${myarray[2]}"
if [ "${myarray[0]}" = "apple" ]; then
  echo "Element access: PASS"
else
  echo "Element access: FAIL"
fi

# Test 4: Array length
echo ""
echo "Test 4: Array length"
length=${#myarray[@]}
echo "Array length = $length"
if [ "$length" = "3" ]; then
  echo "Array length: PASS"
else
  echo "Array length: FAIL (expected 3, got $length)"
fi

# Test 5: All elements expansion
echo ""
echo "Test 5: All elements expansion"
echo "All elements: ${myarray[@]}"
all="${myarray[@]}"
if [ "$all" = "apple banana cherry" ]; then
  echo "All elements: PASS"
else
  echo "All elements: FAIL (got: $all)"
fi

# Test 6: Sparse array
echo ""
echo "Test 6: Sparse array"
declare -a sparse
sparse[0]=first
sparse[5]=sixth
sparse[10]=eleventh
echo "sparse[0] = ${sparse[0]}"
echo "sparse[5] = ${sparse[5]}"
echo "sparse[10] = ${sparse[10]}"
echo "Sparse array length: ${#sparse[@]}"

# Test 7: Mixed assignment and access
echo ""
echo "Test 7: Mixed operations"
declare -a mixed
mixed[0]=one
mixed[1]=two
mixed[2]=three
echo "Initial: ${mixed[@]}"
mixed[1]=TWO
echo "After modification: ${mixed[@]}"
if [ "${mixed[1]}" = "TWO" ]; then
  echo "Mixed operations: PASS"
else
  echo "Mixed operations: FAIL"
fi

echo ""
echo "=== Array Tests Complete ==="
