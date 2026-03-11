! ==============================================================================
! Module: suggestions
! Pure suggestion selection logic for autosuggestions (shadow text).
! Separated from readline for testability — no I/O, no terminal ops.
! ==============================================================================
module suggestions
  implicit none
  private

  ! Buffer size — matches readline's MAX_LINE_LEN on Linux/gfortran
  integer, parameter, public :: SUGGEST_BUF_LEN = 1024
  integer, parameter, public :: MAX_SUGGEST_COMPLETIONS = 40

  ! Suggestion source identifiers
  integer, parameter, public :: SUGGEST_NONE = 0
  integer, parameter, public :: SUGGEST_PATH = 1
  integer, parameter, public :: SUGGEST_HISTORY = 2

  type, public :: suggestion_result_t
    character(len=SUGGEST_BUF_LEN) :: text = ''
    integer :: length = 0
    integer :: source = 0  ! SUGGEST_NONE, SUGGEST_PATH, SUGGEST_HISTORY
  end type suggestion_result_t

  public :: compute_path_suggestion, compute_history_suggestion

contains

  ! --------------------------------------------------------------------------
  ! Compute a path-based suggestion from completion results.
  !
  ! Given the last word the user typed and an array of completions returned
  ! by the file scanner, returns the remaining suffix to suggest. Only
  ! completions that are genuine prefix extensions of last_word are accepted.
  ! --------------------------------------------------------------------------
  function compute_path_suggestion(last_word, last_word_len, &
      completions, num_completions) result(res)
    character(len=*), intent(in) :: last_word
    integer, intent(in) :: last_word_len
    character(len=*), intent(in) :: completions(:)
    integer, intent(in) :: num_completions
    type(suggestion_result_t) :: res

    integer :: i, j, common_prefix_len, comp_len
    logical :: is_prefix

    res%text = ''
    res%length = 0
    res%source = SUGGEST_NONE

    if (last_word_len == 0 .or. num_completions == 0) return

    if (num_completions == 1) then
      ! Single completion — suggest the remainder if it's a prefix extension
      comp_len = len_trim(completions(1))
      if (comp_len > last_word_len) then
        ! Verify prefix match character-by-character
        is_prefix = .true.
        do i = 1, last_word_len
          if (completions(1)(i:i) /= last_word(i:i)) then
            is_prefix = .false.
            exit
          end if
        end do
        if (is_prefix) then
          res%length = min(comp_len - last_word_len, SUGGEST_BUF_LEN)
          do i = 1, res%length
            res%text(i:i) = completions(1)(last_word_len + i : last_word_len + i)
          end do
          res%source = SUGGEST_PATH
        end if
      end if
    else
      ! Multiple completions — find common prefix, then suggest the difference
      common_prefix_len = len_trim(completions(1))

      do i = 2, num_completions
        comp_len = len_trim(completions(i))
        do j = 1, min(common_prefix_len, comp_len)
          if (completions(1)(j:j) /= completions(i)(j:j)) then
            common_prefix_len = j - 1
            exit
          end if
        end do
        if (common_prefix_len == 0) exit
      end do

      if (common_prefix_len > last_word_len) then
        ! Verify the common prefix starts with last_word
        is_prefix = .true.
        do i = 1, last_word_len
          if (completions(1)(i:i) /= last_word(i:i)) then
            is_prefix = .false.
            exit
          end if
        end do
        if (is_prefix) then
          res%length = min(common_prefix_len - last_word_len, SUGGEST_BUF_LEN)
          do i = 1, res%length
            res%text(i:i) = completions(1)(last_word_len + i : last_word_len + i)
          end do
          res%source = SUGGEST_PATH
        end if
      end if
    end if
  end function compute_path_suggestion

  ! --------------------------------------------------------------------------
  ! Compute a history-based suggestion.
  !
  ! Searches history_lines backwards for the first entry that starts with
  ! current_input. Returns the remaining suffix (truncated at newlines).
  ! --------------------------------------------------------------------------
  function compute_history_suggestion(current_input, input_len, &
      history_lines, history_count) result(res)
    character(len=*), intent(in) :: current_input
    integer, intent(in) :: input_len
    character(len=*), intent(in) :: history_lines(:)
    integer, intent(in) :: history_count
    type(suggestion_result_t) :: res

    integer :: i, j, hist_len, remainder_len, newline_pos
    logical :: matches

    res%text = ''
    res%length = 0
    res%source = SUGGEST_NONE

    if (input_len == 0 .or. history_count == 0) return

    do i = history_count, 1, -1
      hist_len = len_trim(history_lines(i))
      if (hist_len > input_len) then
        ! Check prefix match character-by-character
        matches = .true.
        do j = 1, input_len
          if (history_lines(i)(j:j) /= current_input(j:j)) then
            matches = .false.
            exit
          end if
        end do

        if (matches) then
          ! Extract remainder
          remainder_len = min(hist_len - input_len, SUGGEST_BUF_LEN)

          ! Find first newline in remainder
          newline_pos = 0
          do j = 1, remainder_len
            if (history_lines(i)(input_len + j : input_len + j) == char(10) .or. &
                history_lines(i)(input_len + j : input_len + j) == char(13)) then
              newline_pos = j
              exit
            end if
          end do

          if (newline_pos == 1) then
            ! Newline is first char of remainder — no useful suggestion
            cycle
          end if

          ! Truncate at newline if found
          if (newline_pos > 1) then
            remainder_len = newline_pos - 1
          end if

          ! Copy remainder character-by-character
          res%text = ''
          do j = 1, remainder_len
            res%text(j:j) = history_lines(i)(input_len + j : input_len + j)
          end do
          res%length = remainder_len
          res%source = SUGGEST_HISTORY
          return
        end if
      end if
    end do
  end function compute_history_suggestion

end module suggestions
