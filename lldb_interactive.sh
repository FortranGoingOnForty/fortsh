#!/bin/bash
# Run fortsh under lldb and capture the segfault backtrace

lldb -o "run" -o "bt" -o "quit" ./bin/fortsh << 'EOF'
h
EOF
