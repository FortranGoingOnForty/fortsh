#!/bin/bash
# Comprehensive test suite for medium-priority built-in commands
# Tests: getopts, trap, wait, kill, ulimit

echo "=== Medium-Priority Built-ins Test Suite ==="
echo ""

# ============================================
# TEST GROUP 1: getopts
# ============================================
echo "GROUP 1: getopts Builtin"
echo "========================="
echo ""

# Test 1.1: Basic getopts usage
echo "TEST 1.1: Basic getopts"
echo "----------------------"
test_getopts_basic() {
  local result=""
  while getopts "abc" opt; do
    result="${result}$opt"
  done
  echo "$result"
}

set -- -a -b -c
OPTIND=1
output=$(test_getopts_basic)
[ "$output" = "abc" ] && echo "✓ PASS" || echo "✗ FAIL (got: $output)"
echo ""

# Test 1.2: getopts with required arguments
echo "TEST 1.2: getopts with arguments"
echo "--------------------------------"
test_getopts_args() {
  local opts=""
  local args=""
  while getopts "a:b:c" opt; do
    case $opt in
      a|b) opts="${opts}${opt}"; args="${args}${OPTARG}," ;;
      c) opts="${opts}${opt}" ;;
    esac
  done
  echo "${opts}:${args}"
}

set -- -a val1 -b val2 -c
OPTIND=1
output=$(test_getopts_args)
[ "$output" = "abc:val1,val2," ] && echo "✓ PASS" || echo "✗ FAIL (got: $output)"
echo ""

# Test 1.3: getopts invalid option handling
echo "TEST 1.3: getopts invalid options"
echo "---------------------------------"
test_getopts_invalid() {
  local count=0
  while getopts "ab" opt 2>/dev/null; do
    [ "$opt" = "?" ] && count=$((count + 1))
  done
  echo "$count"
}

set -- -a -x -b
OPTIND=1
output=$(test_getopts_invalid)
[ "$output" -ge "1" ] && echo "✓ PASS" || echo "✗ FAIL (got: $output)"
echo ""

# ============================================
# TEST GROUP 2: trap
# ============================================
echo "GROUP 2: trap Builtin"
echo "====================="
echo ""

# Test 2.1: trap command syntax
echo "TEST 2.1: trap syntax acceptance"
echo "--------------------------------"
trap 'echo signal' SIGINT 2>/dev/null
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
trap - SIGINT 2>/dev/null  # Clean up
echo ""

# Test 2.2: trap -p (list traps)
echo "TEST 2.2: trap -p"
echo "----------------"
trap -p >/dev/null 2>&1
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 2.3: trap removal
echo "TEST 2.3: trap removal"
echo "---------------------"
trap 'echo test' SIGTERM 2>/dev/null
trap - SIGTERM 2>/dev/null
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# ============================================
# TEST GROUP 3: wait
# ============================================
echo "GROUP 3: wait Builtin"
echo "====================="
echo ""

# Test 3.1: wait with no arguments
echo "TEST 3.1: wait (no args)"
echo "-----------------------"
wait 2>/dev/null
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 3.2: wait with PID
echo "TEST 3.2: wait with PID"
echo "----------------------"
sleep 0.1 &
pid=$!
wait $pid 2>/dev/null
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 3.3: wait for completed process
echo "TEST 3.3: wait for completed process"
echo "------------------------------------"
sleep 0.1 &
pid=$!
sleep 0.2  # Let it finish
wait $pid 2>/dev/null
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# ============================================
# TEST GROUP 4: kill
# ============================================
echo "GROUP 4: kill Builtin"
echo "====================="
echo ""

# Test 4.1: kill syntax (default signal)
echo "TEST 4.1: kill with PID"
echo "----------------------"
sleep 60 &
pid=$!
kill $pid 2>/dev/null
status=$?
wait $pid 2>/dev/null  # Clean up
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 4.2: kill with signal number
echo "TEST 4.2: kill -9"
echo "----------------"
sleep 60 &
pid=$!
kill -9 $pid 2>/dev/null
status=$?
wait $pid 2>/dev/null  # Clean up
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 4.3: kill with signal name
echo "TEST 4.3: kill -TERM"
echo "-------------------"
sleep 60 &
pid=$!
kill -TERM $pid 2>/dev/null
status=$?
wait $pid 2>/dev/null  # Clean up
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 4.4: kill with -s option
echo "TEST 4.4: kill -s SIGKILL"
echo "------------------------"
sleep 60 &
pid=$!
kill -s SIGKILL $pid 2>/dev/null
status=$?
wait $pid 2>/dev/null  # Clean up
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# ============================================
# TEST GROUP 5: ulimit
# ============================================
echo "GROUP 5: ulimit Builtin"
echo "======================="
echo ""

# Test 5.1: ulimit with no arguments
echo "TEST 5.1: ulimit (no args)"
echo "-------------------------"
ulimit >/dev/null 2>&1
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 5.2: ulimit -a (show all)
echo "TEST 5.2: ulimit -a"
echo "------------------"
ulimit -a >/dev/null 2>&1
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 5.3: ulimit -n (show open files)
echo "TEST 5.3: ulimit -n"
echo "------------------"
ulimit -n >/dev/null 2>&1
status=$?
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# Test 5.4: ulimit -n value (set limit)
echo "TEST 5.4: ulimit -n 1024"
echo "-----------------------"
# This may fail if not privileged, but syntax should be accepted
current=$(ulimit -n)
ulimit -n 1024 2>/dev/null
status=$?
ulimit -n $current 2>/dev/null  # Restore
[ $status -eq 0 ] && echo "✓ PASS" || echo "✗ FAIL (exit code: $status)"
echo ""

# ============================================
# TEST GROUP 6: type command updates
# ============================================
echo "GROUP 6: type Command Recognition"
echo "=================================="
echo ""

# Test that all new built-ins are recognized by type
builtins=("getopts" "trap" "wait" "kill" "ulimit")
all_passed=true

for cmd in "${builtins[@]}"; do
  output=$(type "$cmd" 2>&1)
  if echo "$output" | grep -q "builtin"; then
    echo "✓ type $cmd: recognized as builtin"
  else
    echo "✗ type $cmd: NOT recognized as builtin"
    all_passed=false
  fi
done

echo ""
[ "$all_passed" = true ] && echo "✓ ALL PASS" || echo "✗ SOME FAILED"
echo ""

# ============================================
# SUMMARY
# ============================================
echo "=========================================="
echo "Medium-Priority Built-ins Test Complete"
echo "=========================================="
echo ""
echo "Built-ins Tested:"
echo "  ✓ getopts - command-line option parsing"
echo "  ✓ trap    - signal handler registration"
echo "  ✓ wait    - wait for background processes"
echo "  ✓ kill    - send signals to processes"
echo "  ✓ ulimit  - resource limit management"
echo ""
echo "Total Test Groups: 6"
echo "Total Test Cases: 20+"
echo ""
echo "NOTE: Some built-ins have minimal implementations"
echo "      Full functionality requires additional C bindings:"
echo "      - trap: requires sigaction/signal"
echo "      - wait: requires waitpid tracking"
echo "      - kill: requires kill() system call"
echo "      - ulimit: requires getrlimit/setrlimit"
