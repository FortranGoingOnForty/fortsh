! ==============================================================================
! Test: suggestions module
! Unit tests for autosuggestion selection logic (path and history).
! ==============================================================================
program test_suggestions
  use suggestions
  implicit none

  integer :: passed, failed, total
  passed = 0
  failed = 0
  total = 0

  write(*, '(a)') '=========================================='
  write(*, '(a)') 'Testing Suggestions Module'
  write(*, '(a)') '=========================================='

  ! --- Path suggestion tests ---
  call test_path_single_prefix()
  call test_path_exact_match_no_suggestion()
  call test_path_non_prefix_rejected()
  call test_path_empty_input()
  call test_path_no_completions()
  call test_path_multiple_common_prefix()
  call test_path_multiple_no_common_extension()
  call test_path_multiple_non_prefix_rejected()

  ! --- History suggestion tests ---
  call test_history_basic_match()
  call test_history_no_match()
  call test_history_empty_input()
  call test_history_newline_truncation()
  call test_history_newline_first_char_skipped()
  call test_history_most_recent_wins()
  call test_history_exact_match_no_suggestion()

  write(*, '(a)') ''
  write(*, '(a)') '=========================================='
  write(*, '(a,i0,a,i0,a,i0,a)') 'Results: ', passed, ' passed, ', failed, ' failed (', total, ' total)'
  write(*, '(a)') '=========================================='

  if (failed > 0) then
    write(*, '(a)') 'SOME TESTS FAILED!'
    error stop 1
  else
    write(*, '(a)') 'All tests passed!'
  end if

contains

  subroutine assert_eq_int(test_name, expected, actual)
    character(len=*), intent(in) :: test_name
    integer, intent(in) :: expected, actual
    total = total + 1
    if (expected == actual) then
      passed = passed + 1
      write(*, '(a,a,a)') '  PASS: ', test_name, ''
    else
      failed = failed + 1
      write(*, '(a,a,a,i0,a,i0)') '  FAIL: ', test_name, ' (expected=', expected, ', got=', actual, ')'
    end if
  end subroutine

  subroutine assert_eq_str(test_name, expected, actual, length)
    character(len=*), intent(in) :: test_name, expected, actual
    integer, intent(in) :: length
    total = total + 1
    if (actual(1:max(1,length)) == expected(1:max(1,len_trim(expected)))) then
      passed = passed + 1
      write(*, '(a,a,a)') '  PASS: ', test_name, ''
    else
      failed = failed + 1
      write(*, '(a,a,a,a,a,a,a)') '  FAIL: ', test_name, &
        ' (expected="', trim(expected), '", got="', actual(1:length), '")'
    end if
  end subroutine

  ! ======================== Path suggestion tests ========================

  subroutine test_path_single_prefix()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'scratch.txt'
    res = compute_path_suggestion('scr', 3, comps, 1)

    call assert_eq_int('path/single_prefix: length', 8, res%length)
    call assert_eq_str('path/single_prefix: text', 'atch.txt', res%text, res%length)
    call assert_eq_int('path/single_prefix: source', SUGGEST_PATH, res%source)
  end subroutine

  subroutine test_path_exact_match_no_suggestion()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'scratch.txt'
    res = compute_path_suggestion('scratch.txt', 11, comps, 1)

    call assert_eq_int('path/exact_match: length=0', 0, res%length)
    call assert_eq_int('path/exact_match: source=NONE', SUGGEST_NONE, res%source)
  end subroutine

  subroutine test_path_non_prefix_rejected()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'foo_scratch'
    res = compute_path_suggestion('scr', 3, comps, 1)

    call assert_eq_int('path/non_prefix: length=0', 0, res%length)
    call assert_eq_int('path/non_prefix: source=NONE', SUGGEST_NONE, res%source)
  end subroutine

  subroutine test_path_empty_input()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'file.txt'
    res = compute_path_suggestion('', 0, comps, 1)

    call assert_eq_int('path/empty_input: length=0', 0, res%length)
  end subroutine

  subroutine test_path_no_completions()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    res = compute_path_suggestion('abc', 3, comps, 0)

    call assert_eq_int('path/no_completions: length=0', 0, res%length)
  end subroutine

  subroutine test_path_multiple_common_prefix()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'src/io/readline.f90'
    comps(2) = 'src/io/suggestions.f90'
    res = compute_path_suggestion('src/i', 5, comps, 2)

    ! Common prefix is 'src/io/' (7 chars), last_word is 5, so suggestion = 'o/'
    call assert_eq_int('path/multi_common: length', 2, res%length)
    call assert_eq_str('path/multi_common: text', 'o/', res%text, res%length)
    call assert_eq_int('path/multi_common: source', SUGGEST_PATH, res%source)
  end subroutine

  subroutine test_path_multiple_no_common_extension()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'abc'
    comps(2) = 'abd'
    res = compute_path_suggestion('ab', 2, comps, 2)

    ! Common prefix is 'ab' (2 chars) = same as last_word, no extension
    call assert_eq_int('path/multi_no_ext: length=0', 0, res%length)
  end subroutine

  subroutine test_path_multiple_non_prefix_rejected()
    character(len=SUGGEST_BUF_LEN) :: comps(MAX_SUGGEST_COMPLETIONS)
    type(suggestion_result_t) :: res

    comps(1) = 'xyz_abc'
    comps(2) = 'xyz_abd'
    res = compute_path_suggestion('ab', 2, comps, 2)

    ! Common prefix 'xyz_ab' doesn't start with 'ab'
    call assert_eq_int('path/multi_non_prefix: length=0', 0, res%length)
  end subroutine

  ! ======================== History suggestion tests ========================

  subroutine test_history_basic_match()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    hist(1) = 'ls -la /usr/bin'
    hist(2) = 'cd /tmp'
    res = compute_history_suggestion('ls -', 4, hist, 2)

    call assert_eq_int('hist/basic: length', 11, res%length)
    call assert_eq_str('hist/basic: text', 'la /usr/bin', res%text, res%length)
    call assert_eq_int('hist/basic: source', SUGGEST_HISTORY, res%source)
  end subroutine

  subroutine test_history_no_match()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    hist(1) = 'echo hello'
    hist(2) = 'cd /tmp'
    res = compute_history_suggestion('git ', 4, hist, 2)

    call assert_eq_int('hist/no_match: length=0', 0, res%length)
    call assert_eq_int('hist/no_match: source=NONE', SUGGEST_NONE, res%source)
  end subroutine

  subroutine test_history_empty_input()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    hist(1) = 'echo hello'
    res = compute_history_suggestion('', 0, hist, 1)

    call assert_eq_int('hist/empty: length=0', 0, res%length)
  end subroutine

  subroutine test_history_newline_truncation()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    hist(1) = 'echo hello' // char(10) // 'echo world'
    res = compute_history_suggestion('echo ', 5, hist, 1)

    call assert_eq_int('hist/newline: length', 5, res%length)
    call assert_eq_str('hist/newline: text', 'hello', res%text, res%length)
  end subroutine

  subroutine test_history_newline_first_char_skipped()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    ! History entry where remainder starts with newline — should be skipped
    hist(1) = 'echo' // char(10) // 'world'
    hist(2) = 'echo hello'
    res = compute_history_suggestion('echo', 4, hist, 2)

    ! Should skip hist(1) (newline first char) and find hist(2)
    call assert_eq_int('hist/nl_first: length', 6, res%length)
    call assert_eq_str('hist/nl_first: text', ' hello', res%text, res%length)
    call assert_eq_int('hist/nl_first: source', SUGGEST_HISTORY, res%source)
  end subroutine

  subroutine test_history_most_recent_wins()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    hist(1) = 'ls /old'
    hist(2) = 'ls /new'
    hist(3) = 'ls /newest'
    res = compute_history_suggestion('ls ', 3, hist, 3)

    ! Most recent (highest index) should win
    call assert_eq_int('hist/recent: length', 7, res%length)
    call assert_eq_str('hist/recent: text', '/newest', res%text, res%length)
  end subroutine

  subroutine test_history_exact_match_no_suggestion()
    character(len=SUGGEST_BUF_LEN) :: hist(10)
    type(suggestion_result_t) :: res

    hist(1) = 'ls -la'
    res = compute_history_suggestion('ls -la', 6, hist, 1)

    ! Exact match — hist_len == input_len, so no suggestion
    call assert_eq_int('hist/exact: length=0', 0, res%length)
  end subroutine

end program test_suggestions
