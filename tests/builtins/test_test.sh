#!/bin/sh
TEST_PREFIX="[test]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. test string operators"
compare_exit "test -z empty string" 'test -z ""'
compare_exit "test -z nonempty fails" 'test -z "hello"'
compare_exit "test -n nonempty string" 'test -n "hello"'
compare_exit "test -n empty fails" 'test -n ""'
compare_exit "test string equality" 'test "abc" = "abc"'
compare_exit "test string inequality" 'test "abc" != "def"'
compare_exit "test equal strings =" 'test "same" = "same"'
compare_exit "test unequal strings !=" 'test "a" != "b"'

section "2. test numeric operators"
compare_exit "test -eq equal" 'test 5 -eq 5'
compare_exit "test -ne not equal" 'test 5 -ne 3'
compare_exit "test -lt less than" 'test 3 -lt 5'
compare_exit "test -gt greater than" 'test 5 -gt 3'
compare_exit "test -le less or equal" 'test 5 -le 5'
compare_exit "test -le strictly less" 'test 4 -le 5'
compare_exit "test -ge greater or equal" 'test 5 -ge 5'
compare_exit "test -ge strictly greater" 'test 6 -ge 5'
compare_exit "test -eq fail" 'test 5 -eq 3'
compare_exit "test -lt fail" 'test 5 -lt 3'

section "3. test file operators"
compare_exit "test -f regular file" "touch $TEST_TMPDIR/testfile; test -f $TEST_TMPDIR/testfile"
compare_exit "test -f nonexistent" "test -f $TEST_TMPDIR/no_such_file"
compare_exit "test -d directory" "test -d $TEST_TMPDIR"
compare_exit "test -d on file fails" "touch $TEST_TMPDIR/testfile; test -d $TEST_TMPDIR/testfile"
compare_exit "test -e file exists" "touch $TEST_TMPDIR/testfile; test -e $TEST_TMPDIR/testfile"
compare_exit "test -e nonexistent" "test -e $TEST_TMPDIR/no_such_file"
compare_exit "test -s nonempty file" "echo data > $TEST_TMPDIR/nonempty; test -s $TEST_TMPDIR/nonempty"
compare_exit "test -s empty file" "touch $TEST_TMPDIR/emptyfile; test -s $TEST_TMPDIR/emptyfile"
compare_exit "test -r readable file" "touch $TEST_TMPDIR/testfile; test -r $TEST_TMPDIR/testfile"
compare_exit "test -w writable file" "touch $TEST_TMPDIR/testfile; test -w $TEST_TMPDIR/testfile"
compare_exit "test -x not executable" "touch $TEST_TMPDIR/testfile; test -x $TEST_TMPDIR/testfile"
compare_exit "test -x executable" "touch $TEST_TMPDIR/exefile; chmod +x $TEST_TMPDIR/exefile; test -x $TEST_TMPDIR/exefile"

section "4. test logical operators"
compare_exit "test logical NOT true" 'test ! -z "hello"'
compare_exit "test logical NOT false" 'test ! -z ""'
compare_exit "test logical AND -a both true" 'test 1 -eq 1 -a 2 -eq 2'
compare_exit "test logical AND -a one false" 'test 1 -eq 1 -a 2 -eq 3'
compare_exit "test logical OR -o both false" 'test 1 -eq 2 -o 3 -eq 4'
compare_exit "test logical OR -o one true" 'test 1 -eq 2 -o 2 -eq 2'

section "5. [ bracket form"
compare_exit "[ string equality ]" '[ "abc" = "abc" ]'
compare_exit "[ numeric test ]" '[ 5 -gt 3 ]'
compare_exit "[ -z empty ]" '[ -z "" ]'
compare_exit "[ file exists ]" "touch $TEST_TMPDIR/testfile; [ -f $TEST_TMPDIR/testfile ]"

section "6. [[ extended test"
compare_exit "[[ pattern match glob ]]" '[[ "hello" == h* ]]'
compare_exit "[[ pattern no match ]]" '[[ "hello" == x* ]]'
compare_exit "[[ regex match =~ ]]" '[[ "hello123" =~ [0-9]+ ]]'
compare_exit "[[ regex no match ]]" '[[ "hello" =~ ^[0-9]+$ ]]'
compare_exit "[[ logical AND && ]]" '[[ 1 -eq 1 && 2 -eq 2 ]]'
compare_exit "[[ logical OR || ]]" '[[ 1 -eq 2 || 2 -eq 2 ]]'
compare_exit "[[ negation ! ]]" '[[ ! "hello" == "world" ]]'
compare_exit "[[ string comparison < ]]" '[[ "abc" < "def" ]]'
compare_exit "[[ string comparison > ]]" '[[ "def" > "abc" ]]'
compare_exit "[[ -z in extended ]]" '[[ -z "" ]]'
compare_exit "[[ -n in extended ]]" '[[ -n "hello" ]]'

print_summary
