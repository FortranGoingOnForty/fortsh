#!/bin/bash
# Test script to verify fortsh keyboard bindings
# This will be run by the user interactively

echo "=== Testing fortsh keyboard bindings ==="
echo ""
echo "Please test the following in the fortsh prompt:"
echo "1. Press Ctrl-L (should clear the screen)"
echo "2. Press Ctrl-C (should cancel the current line, not show ^C)"
echo "3. Press Tab twice (should show command completion)"
echo "4. Press Ctrl-R (should enter reverse-i-search)"
echo "5. Type 'echo test' and press Enter"
echo "6. Press Up arrow (should show 'echo test' from history)"
echo ""
echo "Starting fortsh..."
echo ""

./bin/fortsh
