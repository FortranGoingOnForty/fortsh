#!/bin/bash
# Test tilde expansion

echo "=== Tilde Expansion Tests ==="
echo ""

# Set up test environment
export HOME="/home/testuser"
export PWD="/current/dir"
export OLDPWD="/previous/dir"

# Test 1: Simple ~
echo "Test 1: echo ~"
result=$(echo ~)
expected="$HOME"
if [ "$result" = "$expected" ]; then
    echo "✓ PASS: ~ expanded to $result"
else
    echo "✗ FAIL: expected $expected, got $result"
fi
echo ""

# Test 2: ~/path
echo "Test 2: echo ~/documents"
result=$(echo ~/documents)
expected="$HOME/documents"
if [ "$result" = "$expected" ]; then
    echo "✓ PASS: ~/documents expanded to $result"
else
    echo "✗ FAIL: expected $expected, got $result"
fi
echo ""

# Test 3: ~+ (current directory)
echo "Test 3: echo ~+"
result=$(echo ~+)
expected="$PWD"
if [ "$result" = "$expected" ]; then
    echo "✓ PASS: ~+ expanded to $result"
else
    echo "✗ FAIL: expected $expected, got $result"
fi
echo ""

# Test 4: ~- (previous directory)
echo "Test 4: echo ~-"
result=$(echo ~-)
expected="$OLDPWD"
if [ "$result" = "$expected" ]; then
    echo "✓ PASS: ~- expanded to $result"
else
    echo "✗ FAIL: expected $expected, got $result"
fi
echo ""

# Test 5: ~username (should work if user exists)
echo "Test 5: echo ~root"
result=$(echo ~root)
# Just check it doesn't still have the tilde
if [[ "$result" != "~root" ]]; then
    echo "✓ PASS: ~root expanded to $result"
else
    echo "✗ FAIL: ~root was not expanded"
fi
echo ""

# Test 6: Non-tilde word (should not be expanded)
echo "Test 6: echo notilde"
result=$(echo notilde)
expected="notilde"
if [ "$result" = "$expected" ]; then
    echo "✓ PASS: notilde remained $result"
else
    echo "✗ FAIL: expected $expected, got $result"
fi
echo ""

echo "=== Tests Complete ==="
