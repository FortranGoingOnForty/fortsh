#!/bin/bash
# Comprehensive test suite for regex matching with =~ operator

echo "=== Regex Matching Test Suite ==="
echo ""

# Test 1: Basic regex match - digits
echo "TEST 1: Basic Digit Pattern"
echo "============================"
str="12345"
if [[ $str =~ ^[0-9]+$ ]]; then
  echo "✓ PASS: '$str' matches digit pattern"
else
  echo "✗ FAIL: '$str' should match digit pattern"
fi
echo ""

# Test 2: Regex match with letters
echo "TEST 2: Letter Pattern"
echo "======================"
str="hello"
if [[ $str =~ ^[a-z]+$ ]]; then
  echo "✓ PASS: '$str' matches lowercase letters"
else
  echo "✗ FAIL: '$str' should match lowercase letters"
fi
echo ""

# Test 3: Regex no match
echo "TEST 3: No Match"
echo "================"
str="hello123"
if [[ $str =~ ^[a-z]+$ ]]; then
  echo "✗ FAIL: '$str' should NOT match letters-only pattern"
else
  echo "✓ PASS: '$str' correctly does not match"
fi
echo ""

# Test 4: Email pattern
echo "TEST 4: Email Pattern"
echo "====================="
email="user@example.com"
if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "✓ PASS: '$email' matches email pattern"
else
  echo "✗ FAIL: '$email' should match email pattern"
fi
echo ""

# Test 5: IP address pattern
echo "TEST 5: IP Address Pattern"
echo "=========================="
ip="192.168.1.1"
if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "✓ PASS: '$ip' matches IP pattern"
else
  echo "✗ FAIL: '$ip' should match IP pattern"
fi
echo ""

# Test 6: URL pattern
echo "TEST 6: URL Pattern"
echo "==================="
url="https://example.com/path"
if [[ $url =~ ^https?:// ]]; then
  echo "✓ PASS: '$url' starts with http(s)://"
else
  echo "✗ FAIL: '$url' should match URL pattern"
fi
echo ""

# Test 7: Word boundary
echo "TEST 7: Word Pattern"
echo "===================="
text="The quick brown fox"
if [[ $text =~ quick ]]; then
  echo "✓ PASS: Found 'quick' in text"
else
  echo "✗ FAIL: Should find 'quick' in text"
fi
echo ""

# Test 8: Case sensitive matching
echo "TEST 8: Case Sensitive"
echo "======================"
str="Hello"
if [[ $str =~ ^hello$ ]]; then
  echo "✗ FAIL: Should be case sensitive (Hello != hello)"
else
  echo "✓ PASS: Correctly case sensitive"
fi
echo ""

# Test 9: Anchor patterns
echo "TEST 9: Anchor Patterns"
echo "======================="
str="test123"
if [[ $str =~ ^test ]]; then
  echo "✓ PASS (1/3): Matches start anchor ^test"
else
  echo "✗ FAIL (1/3): Should match start anchor"
fi

if [[ $str =~ 123$ ]]; then
  echo "✓ PASS (2/3): Matches end anchor 123$"
else
  echo "✗ FAIL (2/3): Should match end anchor"
fi

if [[ $str =~ ^test123$ ]]; then
  echo "✓ PASS (3/3): Matches full string ^test123$"
else
  echo "✗ FAIL (3/3): Should match full string"
fi
echo ""

# Test 10: Character classes
echo "TEST 10: Character Classes"
echo "=========================="
str1="abc123"
str2="xyz789"

if [[ $str1 =~ [0-9]+ ]]; then
  echo "✓ PASS (1/2): '$str1' contains digits"
else
  echo "✗ FAIL (1/2): Should contain digits"
fi

if [[ $str2 =~ [a-z]+ ]]; then
  echo "✓ PASS (2/2): '$str2' contains letters"
else
  echo "✗ FAIL (2/2): Should contain letters"
fi
echo ""

# Test 11: Repetition quantifiers
echo "TEST 11: Repetition Quantifiers"
echo "================================"
str="aaaa"
if [[ $str =~ ^a{4}$ ]]; then
  echo "✓ PASS (1/4): Matches exactly 4 a's"
else
  echo "✗ FAIL (1/4): Should match exactly 4 a's"
fi

str="aaa"
if [[ $str =~ ^a{2,5}$ ]]; then
  echo "✓ PASS (2/4): Matches 2-5 a's"
else
  echo "✗ FAIL (2/4): Should match 2-5 a's"
fi

str="aaa"
if [[ $str =~ ^a+$ ]]; then
  echo "✓ PASS (3/4): Matches a+ (one or more)"
else
  echo "✗ FAIL (3/4): Should match a+"
fi

str=""
if [[ $str =~ ^a*$ ]]; then
  echo "✓ PASS (4/4): Matches a* (zero or more)"
else
  echo "✗ FAIL (4/4): Should match a*"
fi
echo ""

# Test 12: Alternation
echo "TEST 12: Alternation (OR)"
echo "========================="
str="cat"
if [[ $str =~ ^(cat|dog)$ ]]; then
  echo "✓ PASS (1/2): Matches 'cat' or 'dog'"
else
  echo "✗ FAIL (1/2): Should match alternation"
fi

str="dog"
if [[ $str =~ ^(cat|dog)$ ]]; then
  echo "✓ PASS (2/2): Matches 'cat' or 'dog'"
else
  echo "✗ FAIL (2/2): Should match alternation"
fi
echo ""

# Test 13: Optional character
echo "TEST 13: Optional Character"
echo "==========================="
str1="color"
str2="colour"
if [[ $str1 =~ ^colou?r$ ]] && [[ $str2 =~ ^colou?r$ ]]; then
  echo "✓ PASS: Both 'color' and 'colour' match colou?r"
else
  echo "✗ FAIL: Should match optional 'u'"
fi
echo ""

# Test 14: Empty string
echo "TEST 14: Empty String"
echo "====================="
str=""
if [[ $str =~ ^$ ]]; then
  echo "✓ PASS: Empty string matches ^$"
else
  echo "✗ FAIL: Empty string should match ^$"
fi
echo ""

# Test 15: Special characters (escaped)
echo "TEST 15: Special Characters"
echo "==========================="
str="file.txt"
if [[ $str =~ \.txt$ ]]; then
  echo "✓ PASS: Matches escaped dot \\.txt"
else
  echo "✗ FAIL: Should match \\.txt"
fi
echo ""

# Test 16: Negation with !
echo "TEST 16: Negation with !"
echo "========================"
str="abc"
if [[ ! $str =~ ^[0-9]+$ ]]; then
  echo "✓ PASS: Correctly negated - not digits"
else
  echo "✗ FAIL: Should not match digits"
fi
echo ""

# Summary
echo "========================================="
echo "Regex Matching Test Suite Complete"
echo "========================================="
echo ""
echo "Features Tested:"
echo "  ✓ Basic patterns (digits, letters)"
echo "  ✓ Complex patterns (email, IP, URL)"
echo "  ✓ Anchors (^, $)"
echo "  ✓ Character classes ([a-z], [0-9])"
echo "  ✓ Quantifiers (+, *, ?, {n}, {m,n})"
echo "  ✓ Alternation (|)"
echo "  ✓ Case sensitivity"
echo "  ✓ Special characters (escaping)"
echo "  ✓ Negation with !"
echo ""
echo "Note: BASH_REMATCH array capture groups not yet implemented"
