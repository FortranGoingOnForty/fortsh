#!/bin/bash
# Test script to reproduce the segfault issue
# The issue: Launch fortsh, optionally press Ctrl-L, then type a single character
# Expected: segfault when character renders

echo "Testing debug build..."
# Send Ctrl-L (ASCII 12) then 'a' then Enter
printf '\x0c' | ./bin/fortsh
echo "Exit code: $?"

echo ""
echo "Testing with just a character..."
# Just send 'a' then Enter
printf 'a\n' | ./bin/fortsh
echo "Exit code: $?"
