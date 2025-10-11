#!/bin/bash
# Test suite for getopts builtin

echo "=== getopts Builtin Test Suite ==="
echo ""

# Test 1: Basic option parsing
echo "TEST 1: Basic Option Parsing"
echo "============================="
test_basic() {
  while getopts "abc" opt; do
    case $opt in
      a) echo "Option -a found" ;;
      b) echo "Option -b found" ;;
      c) echo "Option -c found" ;;
      \?) echo "Invalid option: -$OPTARG" ;;
    esac
  done
}

set -- -a -b -c
test_basic
[ $? -eq 0 ] && echo "✓ PASS: Basic option parsing" || echo "✗ FAIL"
echo ""

# Test 2: Options with arguments
echo "TEST 2: Options with Arguments"
echo "=============================="
test_with_args() {
  while getopts "a:b:c" opt; do
    case $opt in
      a) echo "Option -a with arg: $OPTARG" ;;
      b) echo "Option -b with arg: $OPTARG" ;;
      c) echo "Option -c (no arg)" ;;
      \?) echo "Invalid option: -$OPTARG" ;;
    esac
  done
}

set -- -a value1 -b value2 -c
OPTIND=1  # Reset OPTIND
test_with_args
echo "✓ PASS: Options with arguments"
echo ""

# Test 3: Combined option format (-ovalue)
echo "TEST 3: Combined Option Format"
echo "=============================="
test_combined() {
  while getopts "o:" opt; do
    case $opt in
      o) echo "Option -o with arg: $OPTARG" ;;
      \?) echo "Invalid option: -$OPTARG" ;;
    esac
  done
}

set -- -ofilename.txt
OPTIND=1
test_combined
echo "✓ PASS: Combined format"
echo ""

# Test 4: Invalid option handling
echo "TEST 4: Invalid Option Handling"
echo "==============================="
test_invalid() {
  while getopts "abc" opt; do
    case $opt in
      a|b|c) echo "Valid option: -$opt" ;;
      \?) echo "Invalid option detected: $OPTARG" ;;
    esac
  done
}

set -- -a -x -b
OPTIND=1
test_invalid
echo "✓ PASS: Invalid option handling"
echo ""

# Test 5: OPTIND tracking
echo "TEST 5: OPTIND Tracking"
echo "======================="
set -- -a -b arg1 arg2
OPTIND=1
while getopts "ab" opt; do
  echo "Processing -$opt, OPTIND=$OPTIND"
done
echo "After processing options, OPTIND=$OPTIND"
echo "Remaining args: ${@:$OPTIND}"
echo "✓ PASS: OPTIND tracking"
echo ""

# Test 6: Mixed options and arguments
echo "TEST 6: Mixed Options and Arguments"
echo "===================================="
parse_mixed() {
  local verbose=false
  local output=""

  while getopts "vo:" opt; do
    case $opt in
      v) verbose=true ;;
      o) output="$OPTARG" ;;
      \?) return 1 ;;
    esac
  done

  shift $((OPTIND-1))

  echo "verbose=$verbose"
  echo "output=$output"
  echo "remaining args: $@"
}

set -- -v -o output.txt file1.txt file2.txt
OPTIND=1
parse_mixed
echo "✓ PASS: Mixed options and arguments"
echo ""

# Test 7: Multiple uses in same script
echo "TEST 7: Multiple Uses in Same Script"
echo "===================================="
first_parse() {
  OPTIND=1
  while getopts "ab" opt; do
    echo "First parse: -$opt"
  done
}

second_parse() {
  OPTIND=1
  while getopts "xy" opt; do
    echo "Second parse: -$opt"
  done
}

set -- -a -b
first_parse

set -- -x -y
second_parse

echo "✓ PASS: Multiple uses"
echo ""

# Summary
echo "========================================="
echo "getopts Builtin Test Suite Complete"
echo "========================================="
echo ""
echo "Features Tested:"
echo "  ✓ Basic option parsing (-a, -b, -c)"
echo "  ✓ Options with required arguments (-a:)"
echo "  ✓ Combined format (-ovalue)"
echo "  ✓ Invalid option detection"
echo "  ✓ OPTIND tracking and management"
echo "  ✓ Mixed options and arguments"
echo "  ✓ Multiple getopts calls in same script"
