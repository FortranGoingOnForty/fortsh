#!/bin/bash

echo "Test John Doe pattern"
str="John Doe"
echo "String: $str"

# Test with regular space (no backslash)
if [[ $str =~ ^([A-Z][a-z]+)\ ([A-Z][a-z]+)$ ]]; then
  echo "Match with backslash-space: YES"
  echo "BASH_REMATCH[0]='${BASH_REMATCH[0]}'"
  echo "BASH_REMATCH[1]='${BASH_REMATCH[1]}'"
  echo "BASH_REMATCH[2]='${BASH_REMATCH[2]}'"
else
  echo "Match with backslash-space: NO"
fi

# Test with just space
if [[ $str =~ ^([A-Z][a-z]+) ([A-Z][a-z]+)$ ]]; then
  echo "Match with plain space: YES"
  echo "BASH_REMATCH[0]='${BASH_REMATCH[0]}'"
  echo "BASH_REMATCH[1]='${BASH_REMATCH[1]}'"
  echo "BASH_REMATCH[2]='${BASH_REMATCH[2]}'"
else
  echo "Match with plain space: NO"
fi
