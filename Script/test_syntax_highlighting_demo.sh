#!/bin/bash

# Syntax Highlighting Demo for FortSH
# This script will launch fortsh and you can type commands to see the syntax highlighting

echo "=========================================="
echo "  FortSH Syntax Highlighting Demo"
echo "=========================================="
echo ""
echo "Try typing these commands to see the colors:"
echo ""
echo "  ls -la          (valid command = GREEN, option = BLUE)"
echo "  invalidcmd      (invalid command = RED)"
echo "  echo 'hello'    (command = GREEN, string = YELLOW)"
echo "  echo \$HOME      (command = GREEN, variable = MAGENTA)"
echo "  cd /usr/bin     (command = GREEN, path = CYAN)"
echo "  # comment       (comment = GRAY)"
echo ""
echo "Type 'exit' when done"
echo "=========================================="
echo ""

./bin/fortsh
