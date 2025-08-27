#!/bin/bash

echo "Debug history test..."

# Start shell and run commands with a small delay to see if history accumulates
{
  echo "echo first command"
  sleep 0.1
  echo "echo second command" 
  sleep 0.1
  echo "echo third command"
  sleep 0.1
  echo "history"
  sleep 0.1
  echo "exit"
} | ./bin/fortsh

echo "Debug test completed."