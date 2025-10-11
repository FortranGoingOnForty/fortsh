#!/bin/bash
# Test array slicing ${array[@]:offset:length}

echo "=== Array Slicing Tests ==="

# Test 1: Basic array slicing with offset and length
echo ""
echo "Test 1: Basic array slicing"
declare -a fruits
fruits=(apple banana cherry date elderberry fig grape)
echo "Full array: ${fruits[@]}"
slice1="${fruits[@]:1:3}"
echo "Slice [1:3]: $slice1"
if [ "$slice1" = "banana cherry date" ]; then
  echo "Basic slicing: PASS"
else
  echo "Basic slicing: FAIL (expected 'banana cherry date', got '$slice1')"
fi

# Test 2: Slice from offset to end (no length)
echo ""
echo "Test 2: Slice from offset to end"
declare -a numbers
numbers=(one two three four five)
echo "Full array: ${numbers[@]}"
slice2="${numbers[@]:2}"
echo "Slice [2:]: $slice2"
if [ "$slice2" = "three four five" ]; then
  echo "Slice to end: PASS"
else
  echo "Slice to end: FAIL (expected 'three four five', got '$slice2')"
fi

# Test 3: Slice with length exceeding array size
echo ""
echo "Test 3: Slice with excessive length"
declare -a colors
colors=(red green blue)
echo "Full array: ${colors[@]}"
slice3="${colors[@]:1:10}"
echo "Slice [1:10]: $slice3"
if [ "$slice3" = "green blue" ]; then
  echo "Excessive length: PASS"
else
  echo "Excessive length: FAIL (expected 'green blue', got '$slice3')"
fi

# Test 4: Slice from start
echo ""
echo "Test 4: Slice from start"
declare -a letters
letters=(a b c d e f)
echo "Full array: ${letters[@]}"
slice4="${letters[@]:0:3}"
echo "Slice [0:3]: $slice4"
if [ "$slice4" = "a b c" ]; then
  echo "Slice from start: PASS"
else
  echo "Slice from start: FAIL (expected 'a b c', got '$slice4')"
fi

# Test 5: Single element slice
echo ""
echo "Test 5: Single element slice"
declare -a words
words=(hello world foo bar)
echo "Full array: ${words[@]}"
slice5="${words[@]:2:1}"
echo "Slice [2:1]: $slice5"
if [ "$slice5" = "foo" ]; then
  echo "Single element: PASS"
else
  echo "Single element: FAIL (expected 'foo', got '$slice5')"
fi

# Test 6: Iteration over sliced array
echo ""
echo "Test 6: Iterate over sliced array"
declare -a data
data=(item1 item2 item3 item4 item5)
echo "Full array: ${data[@]}"
echo "Iterating over slice [1:2]:"
for item in ${data[@]:1:2}; do
  echo "  - $item"
done

echo ""
echo "=== Array Slicing Tests Complete ==="
