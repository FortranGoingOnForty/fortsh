#!/bin/bash
# =====================================
# Integration Test Script for fortsh
# =====================================

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTSH_DIR="$(dirname "$SCRIPT_DIR")"
FORTSH_BIN="$FORTSH_DIR/bin/fortsh"

echo "======================================"
echo "Fortsh Integration Test Suite"
echo "======================================"
echo ""

# Check if fortsh binary exists
if [[ ! -x "$FORTSH_BIN" ]]; then
    echo "❌ fortsh binary not found at $FORTSH_BIN"
    echo "Please run 'make' in the main directory first"
    exit 1
fi

echo "✅ Found fortsh binary at $FORTSH_BIN"
echo ""

# Test 1: Basic command execution
echo "Test 1: Basic command execution"
echo "-------------------------------"
result=$(echo "echo hello world" | "$FORTSH_BIN" 2>/dev/null | grep "hello world")
if [[ "$result" == "hello world" ]]; then
    echo "✅ Basic echo command works"
else
    echo "❌ Basic echo command failed"
    echo "Expected: 'hello world', Got: '$result'"
fi

# Test 2: Variable expansion
echo ""
echo "Test 2: Variable expansion"
echo "-------------------------"
result=$(echo -e "TEST=fortsh\necho \$TEST" | "$FORTSH_BIN" 2>/dev/null | tail -1)
if [[ "$result" == "fortsh" ]]; then
    echo "✅ Variable expansion works"
else
    echo "❌ Variable expansion failed"
    echo "Expected: 'fortsh', Got: '$result'"
fi

# Test 3: Glob pattern matching
echo ""
echo "Test 3: Glob pattern matching"
echo "-----------------------------"
result=$(echo "echo *.txt" | "$FORTSH_BIN" 2>/dev/null | grep -c "txt")
if [[ "$result" -gt 0 ]]; then
    echo "✅ Glob pattern matching works"
else
    echo "❌ Glob pattern matching failed"
fi

# Test 4: Here-string redirection
echo ""
echo "Test 4: Here-string redirection"
echo "-------------------------------"
result=$(echo "cat <<< hello" | "$FORTSH_BIN" 2>/dev/null)
if [[ "$result" == "hello" ]]; then
    echo "✅ Here-string redirection works"
else
    echo "❌ Here-string redirection failed"
    echo "Expected: 'hello', Got: '$result'"
fi

# Test 5: For loop basic functionality
echo ""
echo "Test 5: For loop functionality"
echo "------------------------------"
result=$(echo -e "for i in a b c\ndo\necho item-\$i\ndone" | "$FORTSH_BIN" 2>/dev/null | head -1)
if [[ "$result" == "item-a" ]]; then
    echo "✅ For loop basic functionality works"
else
    echo "❌ For loop functionality failed"
    echo "Expected: 'item-a', Got: '$result'"
fi

# Test 6: Built-in commands
echo ""
echo "Test 6: Built-in commands"
echo "-------------------------"
result=$(echo "pwd" | "$FORTSH_BIN" 2>/dev/null)
if [[ -n "$result" ]]; then
    echo "✅ Built-in commands work (pwd returned: $result)"
else
    echo "❌ Built-in commands failed"
fi

# Test 7: Alias functionality
echo ""
echo "Test 7: Alias functionality"
echo "---------------------------"
result=$(echo -e "alias ll='echo long-list'\nll" | "$FORTSH_BIN" 2>/dev/null | tail -1)
if [[ "$result" == "long-list" ]]; then
    echo "✅ Alias functionality works"
else
    echo "❌ Alias functionality failed"
    echo "Expected: 'long-list', Got: '$result'"
fi

# Test 8: Error handling
echo ""
echo "Test 8: Error handling"
echo "----------------------"
result=$(echo "nonexistent_command_xyz123" | "$FORTSH_BIN" 2>&1 | grep -c "command not found")
if [[ "$result" -gt 0 ]]; then
    echo "✅ Error handling works"
else
    echo "❌ Error handling failed"
fi

echo ""
echo "======================================"
echo "Integration tests completed!"
echo "======================================"