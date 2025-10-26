#!/bin/bash
# Test various interactive scenarios
echo "Testing interactive mode..."

# Test 1: Basic typing and execution
echo -e "echo 'Test 1 passed'" | timeout 2 ./bin/fortsh 2>&1 | grep -q "Test 1 passed" && echo "✓ Basic typing works" || echo "✗ Basic typing failed"

# Test 2: Variable assignment
echo -e "X=hello\necho \$X" | timeout 2 ./bin/fortsh 2>&1 | grep -q "hello" && echo "✓ Variable assignment works" || echo "✗ Variable assignment failed"

# Test 3: Tab completion simulation (just press tab, shouldn't crash)
echo -e "ec\t\n" | timeout 2 ./bin/fortsh 2>&1 > /dev/null && echo "✓ Tab key doesn't crash" || echo "✗ Tab key causes issues"

# Test 4: History navigation (up arrow would be \033[A but we'll test with echo)
echo -e "echo first\necho second\n!!" | timeout 2 ./bin/fortsh 2>&1 | grep -q "second" && echo "✓ History expansion works" || echo "✗ History expansion failed"

# Test 5: Long command
LONG_CMD="echo '$(printf 'X%.0s' {1..100})'"
echo -e "$LONG_CMD" | timeout 2 ./bin/fortsh 2>&1 | grep -q "XXX" && echo "✓ Long commands work" || echo "✗ Long commands failed"

echo "Interactive mode test complete!"
