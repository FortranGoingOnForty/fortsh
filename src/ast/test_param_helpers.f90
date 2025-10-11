program test_param_helpers
  implicit none
  integer :: test_count, pass_count

  test_count = 0
  pass_count = 0

  print *, "=== Parameter Expansion Helper Tests ==="
  print *, ""

  ! Test to_upper
  test_count = test_count + 1
  if (test_to_upper("hello", "HELLO")) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_to_upper("Hello World", "HELLO WORLD")) pass_count = pass_count + 1

  ! Test to_lower
  test_count = test_count + 1
  if (test_to_lower("HELLO", "hello")) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_to_lower("Hello World", "hello world")) pass_count = pass_count + 1

  ! Test pattern_matches
  test_count = test_count + 1
  if (test_pattern("hello", "hello", .true.)) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_pattern("hello.txt", "*.txt", .true.)) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_pattern("test", "t??t", .true.)) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_pattern("hello", "world", .false.)) pass_count = pass_count + 1

  ! Test remove_prefix
  test_count = test_count + 1
  if (test_remove_prefix("/usr/local/bin", "/*/", "local/bin", .false.)) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_remove_prefix("/usr/local/bin", "/*/", "bin", .true.)) pass_count = pass_count + 1

  ! Test remove_suffix
  test_count = test_count + 1
  if (test_remove_suffix("file.tar.gz", ".*", "file.tar", .false.)) pass_count = pass_count + 1

  test_count = test_count + 1
  if (test_remove_suffix("file.tar.gz", ".*", "file", .true.)) pass_count = pass_count + 1

  ! Print summary
  print *, ""
  print *, "=== Test Summary ==="
  print *, "Passed:", pass_count, "/", test_count
  if (pass_count == test_count) then
    print *, "✓ All tests PASSED!"
    stop 0
  else
    print *, "✗", test_count - pass_count, "tests FAILED"
    stop 1
  end if

contains

  ! Test functions
  logical function test_to_upper(input, expected)
    character(*), intent(in) :: input, expected
    character(:), allocatable :: result

    result = to_upper(input)
    test_to_upper = (trim(result) == trim(expected))

    if (test_to_upper) then
      print *, "✓ to_upper('", trim(input), "') = '", trim(result), "'"
    else
      print *, "✗ to_upper('", trim(input), "') = '", trim(result), "', expected '", trim(expected), "'"
    end if
  end function test_to_upper

  logical function test_to_lower(input, expected)
    character(*), intent(in) :: input, expected
    character(:), allocatable :: result

    result = to_lower(input)
    test_to_lower = (trim(result) == trim(expected))

    if (test_to_lower) then
      print *, "✓ to_lower('", trim(input), "') = '", trim(result), "'"
    else
      print *, "✗ to_lower('", trim(input), "') = '", trim(result), "', expected '", trim(expected), "'"
    end if
  end function test_to_lower

  logical function test_pattern(str, pattern, should_match)
    character(*), intent(in) :: str, pattern
    logical, intent(in) :: should_match
    logical :: result

    result = pattern_matches(str, pattern)
    test_pattern = (result .eqv. should_match)

    if (test_pattern) then
      if (should_match) then
        print *, "✓ pattern_matches('", trim(str), "', '", trim(pattern), "') = true"
      else
        print *, "✓ pattern_matches('", trim(str), "', '", trim(pattern), "') = false"
      end if
    else
      print *, "✗ pattern_matches('", trim(str), "', '", trim(pattern), "') failed"
    end if
  end function test_pattern

  logical function test_remove_prefix(str, pattern, expected, greedy)
    character(*), intent(in) :: str, pattern, expected
    logical, intent(in) :: greedy
    character(:), allocatable :: result

    result = remove_prefix(str, pattern, greedy)
    test_remove_prefix = (trim(result) == trim(expected))

    if (test_remove_prefix) then
      print *, "✓ remove_prefix('", trim(str), "', '", trim(pattern), "', greedy=", greedy, ") = '", trim(result), "'"
    else
      print *, "✗ remove_prefix('", trim(str), "', '", trim(pattern), "') = '", trim(result), "', expected '", trim(expected), "'"
    end if
  end function test_remove_prefix

  logical function test_remove_suffix(str, pattern, expected, greedy)
    character(*), intent(in) :: str, pattern, expected
    logical, intent(in) :: greedy
    character(:), allocatable :: result

    result = remove_suffix(str, pattern, greedy)
    test_remove_suffix = (trim(result) == trim(expected))

    if (test_remove_suffix) then
      print *, "✓ remove_suffix('", trim(str), "', '", trim(pattern), "', greedy=", greedy, ") = '", trim(result), "'"
    else
      print *, "✗ remove_suffix('", trim(str), "', '", trim(pattern), "') = '", trim(result), "', expected '", trim(expected), "'"
    end if
  end function test_remove_suffix

  ! Helper function implementations (copied from evaluator)
  function to_upper(str) result(upper)
    character(*), intent(in) :: str
    character(:), allocatable :: upper
    integer :: i, diff
    character(len(str)) :: temp

    diff = ichar('A') - ichar('a')
    temp = str
    do i = 1, len(str)
      if (str(i:i) >= 'a' .and. str(i:i) <= 'z') then
        temp(i:i) = char(ichar(str(i:i)) + diff)
      end if
    end do
    upper = temp
  end function to_upper

  function to_lower(str) result(lower)
    character(*), intent(in) :: str
    character(:), allocatable :: lower
    integer :: i, diff
    character(len(str)) :: temp

    diff = ichar('a') - ichar('A')
    temp = str
    do i = 1, len(str)
      if (str(i:i) >= 'A' .and. str(i:i) <= 'Z') then
        temp(i:i) = char(ichar(str(i:i)) + diff)
      end if
    end do
    lower = temp
  end function to_lower

  function remove_prefix(str, pattern, greedy) result(res)
    character(*), intent(in) :: str, pattern
    logical, intent(in) :: greedy
    character(:), allocatable :: res
    integer :: i

    res = str

    if (greedy) then
      do i = len_trim(str), 1, -1
        if (pattern_matches(str(1:i), pattern)) then
          if (i < len_trim(str)) then
            res = trim(str(i+1:))
          else
            res = ''
          end if
          return
        end if
      end do
    else
      do i = 1, len_trim(str)
        if (pattern_matches(str(1:i), pattern)) then
          if (i < len_trim(str)) then
            res = trim(str(i+1:))
          else
            res = ''
          end if
          return
        end if
      end do
    end if
  end function remove_prefix

  function remove_suffix(str, pattern, greedy) result(res)
    character(*), intent(in) :: str, pattern
    logical, intent(in) :: greedy
    character(:), allocatable :: res
    integer :: i, str_len

    res = str
    str_len = len_trim(str)

    if (greedy) then
      do i = 1, str_len
        if (pattern_matches(str(i:str_len), pattern)) then
          if (i > 1) then
            res = trim(str(1:i-1))
          else
            res = ''
          end if
          return
        end if
      end do
    else
      do i = str_len, 1, -1
        if (pattern_matches(str(i:str_len), pattern)) then
          if (i > 1) then
            res = trim(str(1:i-1))
          else
            res = ''
          end if
          return
        end if
      end do
    end if
  end function remove_suffix

  logical function pattern_matches(str, pattern)
    character(*), intent(in) :: str, pattern
    integer :: i, star_pos, str_len, before_len, after_len
    character(:), allocatable :: before_star, after_star

    pattern_matches = .false.
    str_len = len_trim(str)

    if (index(pattern, '*') == 0 .and. index(pattern, '?') == 0) then
      pattern_matches = (trim(str) == trim(pattern))
      return
    end if

    star_pos = index(pattern, '*')
    if (star_pos > 0) then
      before_star = pattern(1:star_pos-1)
      after_star = pattern(star_pos+1:)
      before_len = len_trim(before_star)
      after_len = len_trim(after_star)

      ! Check if string is long enough
      if (str_len < before_len + after_len) return

      ! Check prefix
      if (before_len > 0) then
        if (str(1:before_len) /= trim(before_star)) return
      end if

      ! Check suffix
      if (after_len > 0) then
        if (str(str_len-after_len+1:str_len) /= trim(after_star)) return
      end if

      pattern_matches = .true.
      return
    end if

    if (len(pattern) /= len(str)) return

    do i = 1, len(pattern)
      if (pattern(i:i) /= '?' .and. pattern(i:i) /= str(i:i)) then
        return
      end if
    end do

    pattern_matches = .true.
  end function pattern_matches

end program test_param_helpers
