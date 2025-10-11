#!/bin/bash

str="12345"
echo "Test 1: Simple digit pattern"
if [[ $str =~ ^[0-9]+$ ]]; then
  echo "PASS: digits matched"
  echo "BASH_REMATCH[0]: '${BASH_REMATCH[0]}'"
else
  echo "FAIL: digits should match"
fi

str2="hello"
echo "Test 2: Simple letter pattern"
if [[ $str2 =~ ^[a-z]+$ ]]; then
  echo "PASS: letters matched"
  echo "BASH_REMATCH[0]: '${BASH_REMATCH[0]}'"
else
  echo "FAIL: letters should match"
fi

str3="abc123"
echo "Test 3: Pattern with capture group"
if [[ $str3 =~ ^([a-z]+)([0-9]+)$ ]]; then
  echo "PASS: pattern matched"
  echo "BASH_REMATCH[0]: '${BASH_REMATCH[0]}'"
  echo "BASH_REMATCH[1]: '${BASH_REMATCH[1]}'"
  echo "BASH_REMATCH[2]: '${BASH_REMATCH[2]}'"
else
  echo "FAIL: pattern should match"
fi
