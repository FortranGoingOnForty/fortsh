#!/bin/bash
# Comprehensive test suite for BASH_REMATCH array with regex matching

echo "=== BASH_REMATCH Array Test Suite ==="
echo ""

# Test 1: Basic capture group
echo "TEST 1: Basic Capture Group"
echo "============================"
str="John Doe"
if [[ $str =~ ^([A-Z][a-z]+)\ ([A-Z][a-z]+)$ ]]; then
  echo "✓ PASS: Pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (expected: 'John Doe')"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (expected: 'John')"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (expected: 'Doe')"
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Test 2: Email address capture groups
echo "TEST 2: Email Address Capture"
echo "=============================="
email="user@example.com"
if [[ $email =~ ^([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+)\.([a-zA-Z]{2,})$ ]]; then
  echo "✓ PASS: Email pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full match)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (username)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (domain)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (TLD)"
else
  echo "✗ FAIL: Email pattern should match"
fi
echo ""

# Test 3: Phone number capture
echo "TEST 3: Phone Number Capture"
echo "============================="
phone="(555) 123-4567"
if [[ $phone =~ ^\(([0-9]{3})\)\ ([0-9]{3})-([0-9]{4})$ ]]; then
  echo "✓ PASS: Phone pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full match)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (area code)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (prefix)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (line number)"
else
  echo "✗ FAIL: Phone pattern should match"
fi
echo ""

# Test 4: Date extraction
echo "TEST 4: Date Extraction"
echo "======================="
date="2025-10-10"
if [[ $date =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
  echo "✓ PASS: Date pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full date)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (year)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (month)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (day)"
else
  echo "✗ FAIL: Date pattern should match"
fi
echo ""

# Test 5: URL parsing
echo "TEST 5: URL Parsing"
echo "==================="
url="https://example.com/path/to/file.html"
if [[ $url =~ ^(https?)://([^/]+)(/.*)?$ ]]; then
  echo "✓ PASS: URL pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full URL)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (protocol)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (domain)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (path)"
else
  echo "✗ FAIL: URL pattern should match"
fi
echo ""

# Test 6: Version string parsing
echo "TEST 6: Version String Parsing"
echo "==============================="
version="v1.2.3-beta"
if [[ $version =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-(.+))?$ ]]; then
  echo "✓ PASS: Version pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full version)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (major)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (minor)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (patch)"
  echo "  BASH_REMATCH[4]: '${BASH_REMATCH[4]}' (suffix with -)"
  echo "  BASH_REMATCH[5]: '${BASH_REMATCH[5]}' (suffix)"
else
  echo "✗ FAIL: Version pattern should match"
fi
echo ""

# Test 7: IPv4 address parsing
echo "TEST 7: IPv4 Address Parsing"
echo "============================="
ip="192.168.1.100"
if [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
  echo "✓ PASS: IPv4 pattern matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full IP)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (octet 1)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (octet 2)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (octet 3)"
  echo "  BASH_REMATCH[4]: '${BASH_REMATCH[4]}' (octet 4)"
else
  echo "✗ FAIL: IPv4 pattern should match"
fi
echo ""

# Test 8: Single capture group
echo "TEST 8: Single Capture Group"
echo "============================="
str="Error: File not found"
if [[ $str =~ ^(Error|Warning): ]]; then
  echo "✓ PASS: Single group matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full match)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (severity)"
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Test 9: No capture groups (just full match)
echo "TEST 9: No Capture Groups"
echo "========================="
str="12345"
if [[ $str =~ ^[0-9]+$ ]]; then
  echo "✓ PASS: Pattern matched (no groups)"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full match)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (should be empty)"
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Test 10: Nested groups
echo "TEST 10: Nested Groups"
echo "======================"
str="abc123def"
if [[ $str =~ ^([a-z]+)([0-9]+)([a-z]+)$ ]]; then
  echo "✓ PASS: Multiple groups matched"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}' (full match)"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}' (first letters)"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (numbers)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (last letters)"
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Test 11: Optional groups
echo "TEST 11: Optional Groups"
echo "========================"
str1="test"
str2="test-123"
if [[ $str1 =~ ^(test)(-([0-9]+))?$ ]]; then
  echo "✓ PASS (1/2): Pattern matched without optional"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}'"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}'"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (should be empty)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (should be empty)"
else
  echo "✗ FAIL (1/2): Pattern should match"
fi

if [[ $str2 =~ ^(test)(-([0-9]+))?$ ]]; then
  echo "✓ PASS (2/2): Pattern matched with optional"
  echo "  BASH_REMATCH[0]: '${BASH_REMATCH[0]}'"
  echo "  BASH_REMATCH[1]: '${BASH_REMATCH[1]}'"
  echo "  BASH_REMATCH[2]: '${BASH_REMATCH[2]}' (optional part)"
  echo "  BASH_REMATCH[3]: '${BASH_REMATCH[3]}' (number)"
else
  echo "✗ FAIL (2/2): Pattern should match"
fi
echo ""

# Test 12: Using captures in script logic
echo "TEST 12: Practical Use - File Extension Parser"
echo "==============================================="
filename="document.tar.gz"
if [[ $filename =~ ^(.+)\.([^.]+)$ ]]; then
  basename="${BASH_REMATCH[1]}"
  extension="${BASH_REMATCH[2]}"
  echo "✓ PASS: File parsed"
  echo "  Basename: '$basename'"
  echo "  Extension: '$extension'"
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Test 13: Array length check
echo "TEST 13: Array Length (Number of Captures)"
echo "==========================================="
str="abc-123-def"
if [[ $str =~ ^([a-z]+)-([0-9]+)-([a-z]+)$ ]]; then
  echo "✓ PASS: Pattern matched with 3 groups"
  echo "  Array contents:"
  echo "    [0]: '${BASH_REMATCH[0]}'"
  echo "    [1]: '${BASH_REMATCH[1]}'"
  echo "    [2]: '${BASH_REMATCH[2]}'"
  echo "    [3]: '${BASH_REMATCH[3]}'"
  echo "  Array length: ${#BASH_REMATCH[@]}"
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Test 14: Loop through captures
echo "TEST 14: Iterate Through Captures"
echo "=================================="
str="a:b:c:d"
if [[ $str =~ ^([a-z]):([a-z]):([a-z]):([a-z])$ ]]; then
  echo "✓ PASS: Pattern matched"
  echo "  Iterating through BASH_REMATCH:"
  for i in {0..4}; do
    echo "    [$i]: '${BASH_REMATCH[$i]}'"
  done
else
  echo "✗ FAIL: Pattern should match"
fi
echo ""

# Summary
echo "========================================="
echo "BASH_REMATCH Array Test Suite Complete"
echo "========================================="
echo ""
echo "Features Tested:"
echo "  ✓ Full match capture (BASH_REMATCH[0])"
echo "  ✓ Multiple capture groups"
echo "  ✓ Email, phone, date, URL parsing"
echo "  ✓ Optional groups"
echo "  ✓ Nested groups"
echo "  ✓ Array length and iteration"
echo "  ✓ Practical use cases"
echo ""
echo "Note: Run this test with both bash and fortsh to compare"
