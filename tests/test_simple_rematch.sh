#!/bin/bash

echo "Simple BASH_REMATCH test"
str="John Doe"
echo "String: $str"

if [[ $str =~ ^([A-Z][a-z]+)\ ([A-Z][a-z]+)$ ]]; then
  echo "Match SUCCESS"
  echo "BASH_REMATCH[0]: '${BASH_REMATCH[0]}'"
  echo "BASH_REMATCH[1]: '${BASH_REMATCH[1]}'"
  echo "BASH_REMATCH[2]: '${BASH_REMATCH[2]}'"
else
  echo "Match FAILED"
fi
