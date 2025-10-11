#!/bin/bash

echo "Debug BASH_REMATCH Test"
str="abc123"
echo "String: $str"

if [[ $str =~ ^([a-z]+)([0-9]+)$ ]]; then
  echo "Match succeeded"
  echo "Immediately: BASH_REMATCH[0]='${BASH_REMATCH[0]}'"
  echo "Immediately: BASH_REMATCH[1]='${BASH_REMATCH[1]}'"
  echo "Immediately: BASH_REMATCH[2]='${BASH_REMATCH[2]}'"
else
  echo "Match failed"
fi

echo "After if: BASH_REMATCH[0]='${BASH_REMATCH[0]}'"
echo "After if: BASH_REMATCH[1]='${BASH_REMATCH[1]}'"
