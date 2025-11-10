#!/bin/bash
# Get detailed crash information

# Kill any existing lldb processes
pkill -9 lldb 2>/dev/null

# Run with lldb, type 'h', capture the crash
(
  sleep 1
  printf 'h'
  sleep 2
) | lldb -o "run" -o "register read" -o "bt 20" -o "disassemble -c 10" -o "quit" ./bin/fortsh 2>&1 | tee crash_info.txt

echo ""
echo "=== Crash info saved to crash_info.txt ==="
echo ""
grep -A 20 "signal SIGSEGV" crash_info.txt || echo "No segfault captured"
