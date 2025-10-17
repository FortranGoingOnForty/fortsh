#!/bin/bash

# Simple test for enhanced readline functionality
echo "Testing enhanced readline functionality..."
echo "This should fallback to line-based input in non-interactive mode."

# Send some basic commands
echo -e "echo Phase2 works!\nhelp\nexit" | ./bin/fortsh

echo "Test completed."