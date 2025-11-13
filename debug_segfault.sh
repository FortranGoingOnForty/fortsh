#!/bin/bash
# Script to debug the segfault with lldb

# Create lldb command file
cat > /tmp/lldb_commands.txt << 'EOF'
run
bt
quit
EOF

# Run lldb with the command file, sending 'h' as input
echo "h" | lldb -s /tmp/lldb_commands.txt ./bin/fortsh 2>&1

# Cleanup
rm -f /tmp/lldb_commands.txt
