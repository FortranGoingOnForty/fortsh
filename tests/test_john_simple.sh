#!/bin/bash

str="John Doe"
if [[ $str =~ ^([A-Z][a-z]+)\ ([A-Z][a-z]+)$ ]]; then
  echo "PASS"
  echo "0: '${BASH_REMATCH[0]}'"
  echo "1: '${BASH_REMATCH[1]}'"
  echo "2: '${BASH_REMATCH[2]}'"
else
  echo "FAIL"
fi
