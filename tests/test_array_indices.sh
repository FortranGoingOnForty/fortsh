#!/bin/bash
# Test array indices expansion ${!array[@]}

echo "=== Array Indices Expansion Tests ==="

# Test 1: Get indices from simple array
echo ""
echo "Test 1: Simple array indices"
declare -a myarray
myarray[0]=apple
myarray[1]=banana
myarray[2]=cherry
indices="${!myarray[@]}"
echo "Array: ${myarray[@]}"
echo "Indices: $indices"
if [ "$indices" = "0 1 2" ]; then
  echo "Simple array indices: PASS"
else
  echo "Simple array indices: FAIL (expected '0 1 2', got '$indices')"
fi

# Test 2: Get indices from sparse array
echo ""
echo "Test 2: Sparse array indices"
declare -a sparse
sparse[0]=first
sparse[5]=sixth
sparse[10]=eleventh
sparse_indices="${!sparse[@]}"
echo "Sparse array: ${sparse[@]}"
echo "Sparse indices: $sparse_indices"
if [ "$sparse_indices" = "0 5 10" ]; then
  echo "Sparse array indices: PASS"
else
  echo "Sparse array indices: FAIL (expected '0 5 10', got '$sparse_indices')"
fi

# Test 3: Get count of array indices
echo ""
echo "Test 3: Count of array indices"
declare -a counted
counted[1]=one
counted[2]=two
counted[3]=three
count_indices="${!counted[@]}"
num_indices=$(echo $count_indices | wc -w)
echo "Array indices: $count_indices"
echo "Number of indices: $num_indices"
if [ "$num_indices" = "3" ]; then
  echo "Count of indices: PASS"
else
  echo "Count of indices: FAIL (expected 3, got $num_indices)"
fi

# Test 4: Iteration over array indices
echo ""
echo "Test 4: Iterate over array indices"
declare -a items
items[10]=ten
items[20]=twenty
items[30]=thirty
echo "Iterating over indices:"
for idx in ${!items[@]}; do
  echo "  Index $idx: ${items[$idx]}"
done

echo ""
echo "=== Array Indices Tests Complete ==="
