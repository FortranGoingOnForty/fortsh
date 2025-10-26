#!/bin/bash
echo "=== Comprehensive Interactive Mode Test ==="

# Test 1: Basic typing
echo -e "echo 'Test 1'" | timeout 2 ./bin/fortsh 2>&1 | grep -q "Test 1" && echo "✓ Basic typing" || echo "✗ Basic typing"

# Test 2: cd with space (previously caused segfault)
echo -e "cd \npwd" | timeout 2 ./bin/fortsh 2>&1 > /dev/null && echo "✓ cd with space" || echo "✗ cd with space"

# Test 3: Multiple spaces
echo -e "echo    'spaces'" | timeout 2 ./bin/fortsh 2>&1 | grep -q "spaces" && echo "✓ Multiple spaces" || echo "✗ Multiple spaces"

# Test 4: Tab after command
echo -e "echo\t'tab'" | timeout 2 ./bin/fortsh 2>&1 | grep -q "tab" && echo "✓ Tab after command" || echo "✗ Tab after command"

# Test 5: Variable with spaces
echo -e "X='hello world'\necho \$X" | timeout 2 ./bin/fortsh 2>&1 | grep -q "hello world" && echo "✓ Variable with spaces" || echo "✗ Variable with spaces"

# Test 6: Command with multiple arguments
echo -e "echo one two three" | timeout 2 ./bin/fortsh 2>&1 | grep -q "one two three" && echo "✓ Multiple arguments" || echo "✗ Multiple arguments"

# Test 7: Empty command (just Enter)
echo -e "\necho 'after empty'" | timeout 2 ./bin/fortsh 2>&1 | grep -q "after empty" && echo "✓ Empty command" || echo "✗ Empty command"

# Test 8: History expansion
echo -e "echo first\necho second\n!!" | timeout 2 ./bin/fortsh 2>&1 | grep -q "second" && echo "✓ History expansion" || echo "✗ History expansion"

# Test 9: cd followed by typing (previously caused segfault with buffer_ref)
echo -e "cd ../\necho test" | timeout 2 ./bin/fortsh 2>&1 | grep -q "test" && echo "✓ cd then typing" || echo "✗ cd then typing"

echo "=== Test Complete ==="
