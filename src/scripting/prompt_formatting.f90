! ==============================================================================
! Module: prompt_formatting
! Purpose: Prompt escape sequence expansion (PS1-PS4 with bash-style escapes)
!          Also supports zsh-style color codes: %F{color}, %f, %B, %b, etc.
! ==============================================================================
module prompt_formatting
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit
  use substitution, only: enhanced_command_substitution
  use variables, only: get_shell_variable
  implicit none

  ! History counter for prompts
  integer, save :: prompt_history_number = 1

  ! Prompt element cache — git results carry a 2-second TTL so rapid
  ! redraws (Ctrl-L, window resize, continuation prompts) don't fork
  ! git on every prompt.  invalidate_prompt_cache() is still called at
  ! the start of each expand_prompt cycle to reset the per-cycle flags.
  character(len=256), save :: cached_git_branch = ''
  character(len=64), save :: cached_git_status = ''
  character(len=64), save :: cached_git_ahead_behind = ''
  character(len=256), save :: cached_venv_name = ''
  logical, save :: cache_branch_valid = .false.
  logical, save :: cache_status_valid = .false.
  logical, save :: cache_ahead_behind_valid = .false.
  logical, save :: cache_venv_valid = .false.
  ! Time-based TTL for git data (avoid forking git on rapid redraws)
  integer, parameter :: GIT_CACHE_TTL_MS = 2000
  integer, save :: git_cache_timestamp = -1

  ! Public interface
  public :: expand_prompt, safe_expand_prompt, expand_zsh_colors
  public :: get_ansi_color_code, get_epoch_seconds, increment_prompt_history
  public :: get_git_branch, get_git_status_indicator, is_git_repo
  public :: invalidate_prompt_cache, get_git_ahead_behind, get_venv_name

contains

  ! Safe version that outputs to fixed-length buffer (no allocatable strings)
  ! Avoids LLVM Flang heap corruption bugs
  subroutine safe_expand_prompt(prompt_str, shell, stored_len, expanded)
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: prompt_str
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in), optional :: stored_len
    character(len=*), intent(out) :: expanded

    character(len=MAX_VAR_VALUE_LEN) :: result  ! Fixed-length buffer (avoid flang-new allocatable string bugs)
    character(len=MAX_VAR_VALUE_LEN) :: var_expanded  ! Buffer for variable/command expansion
    integer :: i, j, prompt_len
    integer, parameter :: RESULT_CAPACITY = 1024
    character(len=256) :: replacement  ! Fixed-length buffer (avoid flang-new allocatable string bugs)

    call invalidate_prompt_cache()

    result = ''
    j = 1
    i = 1

    ! Use stored length if provided
    if (present(stored_len) .and. stored_len > 0) then
      prompt_len = min(stored_len, len(prompt_str))
    else
      prompt_len = len_trim(prompt_str)
    end if


    do
      if (i > prompt_len .or. j > RESULT_CAPACITY) exit
      if (prompt_str(i:i) == '\' .and. i < prompt_len) then
        ! Process escape sequence
        i = i + 1
        call process_escape_sequence(prompt_str(i:i), shell, replacement)

        if (len_trim(replacement) > 0) then
          if (j + len_trim(replacement) - 1 <= RESULT_CAPACITY) then
            result(j:j+len_trim(replacement)-1) = trim(replacement)
            j = j + len_trim(replacement)
          end if
        end if
        i = i + 1
      else
        ! Regular character
        if (j <= RESULT_CAPACITY) then
          result(j:j) = prompt_str(i:i)
          j = j + 1
        end if
        i = i + 1
      end if
    end do

    ! Copy to output
    expanded = ''
    if (j > 1) then
      expanded = result(1:min(j-1, len(expanded)))
    end if

    ! Now process zsh-style color escapes (%F{color}, %f, etc.)
    if (index(expanded, '%') > 0) then
      result = ''
      call expand_zsh_colors(expanded, result, len_trim(expanded))
      expanded = result(1:min(len_trim(result), len(expanded)))
    end if

    ! Expand variables and command substitutions ($VAR, ${VAR}, $(cmd))
    if (index(expanded, '$') > 0) then
      call expand_prompt_variables(expanded, shell, var_expanded)
      expanded = var_expanded(1:min(len_trim(var_expanded), len(expanded)))
    end if
  end subroutine

  ! Main function to expand prompt string with escape sequences
  function expand_prompt(prompt_str, shell, stored_len) result(expanded)
    character(len=*), intent(in) :: prompt_str
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in), optional :: stored_len
    character(len=:), allocatable :: expanded

    ! Use allocatable to avoid stack allocation
    character(len=:), allocatable :: result
    character(len=MAX_VAR_VALUE_LEN) :: var_expanded  ! Buffer for variable/command expansion
    integer :: i, j, prompt_len, result_capacity
    character(len=:), allocatable :: replacement  ! Heap allocation to avoid stack overflow

    call invalidate_prompt_cache()

    ! Allocate replacement buffer on heap
    allocate(character(len=256) :: replacement)

    ! Start with reasonable capacity
    result_capacity = len(prompt_str) * 2 + 256
    allocate(character(len=result_capacity) :: result)
    result = ''

    j = 1
    i = 1
    ! Use stored length if provided (preserves intentional trailing spaces),
    ! otherwise fall back to len_trim for backwards compatibility
    if (present(stored_len) .and. stored_len > 0) then
      prompt_len = min(stored_len, len(prompt_str))
    else
      prompt_len = len_trim(prompt_str)
    end if

    do while (i <= prompt_len)
      if (prompt_str(i:i) == '\' .and. i < prompt_len) then
        ! Process escape sequence
        i = i + 1
        call process_escape_sequence(prompt_str(i:i), shell, replacement)

        if (len_trim(replacement) > 0) then
          ! Grow buffer if needed
          if (j + len_trim(replacement) > result_capacity) then
            call grow_string_buffer(result, result_capacity, result_capacity * 2)
          end if
          result(j:j+len_trim(replacement)-1) = trim(replacement)
          j = j + len_trim(replacement)
        end if
        i = i + 1
      else
        ! Regular character
        if (j > result_capacity) then
          call grow_string_buffer(result, result_capacity, result_capacity * 2)
        end if
        result(j:j) = prompt_str(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    ! Allocate exact length to preserve trailing spaces
    expanded = result(1:j-1)
    deallocate(result)
    if (allocated(replacement)) deallocate(replacement)

    ! Now process zsh-style color escapes (%F{color}, %f, etc.)
    if (index(expanded, '%') > 0) then
      allocate(character(len=len(expanded)*2) :: result)
      call expand_zsh_colors(expanded, result, len(expanded))
      expanded = trim(result)
      deallocate(result)
    end if

    ! Expand variables and command substitutions ($VAR, ${VAR}, $(cmd))
    if (index(expanded, '$') > 0) then
      call expand_prompt_variables(expanded, shell, var_expanded)
      expanded = trim(var_expanded)
    end if
  end function

  ! Process individual escape sequence
  subroutine process_escape_sequence(escape_char, shell, replacement)
    character(len=1), intent(in) :: escape_char
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(out) :: replacement

    character(len=:), allocatable :: temp  ! Heap allocation to avoid stack overflow
    integer :: values(8), hour
    character(len=3), dimension(7) :: day_names = &
      ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    character(len=3), dimension(12) :: month_names = &
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', &
       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    integer :: day_of_week

    ! Allocate temp buffer on heap (must come after all declarations)
    allocate(character(len=256) :: temp)

    replacement = ''

    select case (escape_char)
      ! User and host information
      case ('u')
        ! Username
        replacement = trim(shell%username)

      case ('h')
        ! Hostname (short - up to first '.')
        replacement = get_short_hostname(shell%hostname)

      case ('H')
        ! Hostname (full)
        replacement = trim(shell%hostname)

      ! Directory information
      case ('w')
        ! Current working directory (full path, with ~ for HOME). Sanitize
        ! control/escape bytes so a maliciously-named cwd can't inject ANSI
        ! sequences into the prompt.
        replacement = sanitize_for_display(get_pretty_path(shell%cwd, shell))

      case ('W')
        ! Basename of current working directory (sanitized — see \w)
        replacement = sanitize_for_display(get_basename(shell%cwd))

      ! Time and date
      case ('t')
        ! Time in 24-hour HH:MM:SS format
        call date_and_time(values=values)
        write(replacement, '(i2.2,a,i2.2,a,i2.2)') &
          values(5), ':', values(6), ':', values(7)

      case ('T')
        ! Time in 12-hour HH:MM:SS format
        call date_and_time(values=values)
        hour = values(5)
        if (hour == 0) hour = 12
        if (hour > 12) hour = hour - 12
        write(replacement, '(i2.2,a,i2.2,a,i2.2)') &
          hour, ':', values(6), ':', values(7)

      case ('@')
        ! Time in 12-hour am/pm format
        call date_and_time(values=values)
        hour = values(5)
        if (hour >= 12) then
          if (hour > 12) hour = hour - 12
          write(replacement, '(i2.2,a,i2.2,a)') hour, ':', values(6), ' pm'
        else
          if (hour == 0) hour = 12
          write(replacement, '(i2.2,a,i2.2,a)') hour, ':', values(6), ' am'
        end if

      case ('A')
        ! Time in 24-hour HH:MM format
        call date_and_time(values=values)
        write(replacement, '(i2.2,a,i2.2)') values(5), ':', values(6)

      case ('d')
        ! Date in "Day Mon DD" format
        call date_and_time(values=values)
        ! Calculate day of week (simplified - may not be exact)
        day_of_week = mod(values(3) + 2, 7) + 1  ! Rough approximation
        if (values(2) >= 1 .and. values(2) <= 12) then
          write(replacement, '(a,1x,a,1x,i2)') &
            day_names(day_of_week), month_names(values(2)), values(3)
        else
          write(replacement, '(a,1x,i2)') day_names(day_of_week), values(3)
        end if

      case ('D')
        ! Date in ISO format YYYY-MM-DD
        call date_and_time(values=values)
        write(replacement, '(i4,a,i2.2,a,i2.2)') values(1), '-', values(2), '-', values(3)

      ! Shell information
      case ('s')
        ! Shell name
        replacement = trim(shell%shell_name)

      case ('v')
        ! Shell version (short)
        replacement = '2.0'

      case ('V')
        ! Shell version + patch level
        replacement = '2.0.0'

      ! History and command numbers
      case ('!')
        ! History number
        write(replacement, '(i15)') prompt_history_number

      case ('#')
        ! Command number
        write(replacement, '(i15)') shell%command_number

      ! Special characters
      case ('$')
        ! '#' if UID=0, else '$'
        if (shell%uid == 0 .or. shell%euid == 0) then
          replacement = '#'
        else
          replacement = '$'
        end if

      case ('n')
        ! Newline - CR+LF for proper cursor positioning in terminal emulators
        replacement = char(13) // char(10)

      case ('r')
        ! Carriage return
        replacement = char(13)

      case ('\')
        ! Backslash
        replacement = '\'

      case ('[')
        ! Begin non-printing sequence (for color codes)
        replacement = ''  ! Don't print anything, just mark

      case (']')
        ! End non-printing sequence
        replacement = ''  ! Don't print anything, just mark

      case ('e')
        ! Escape character for ANSI codes
        replacement = char(27)

      case ('a')
        ! Bell/beep
        replacement = char(7)

      case ('j')
        ! Number of jobs
        write(replacement, '(i15)') shell%num_jobs

      case ('g')
        ! Git branch (if in git repo)
        replacement = get_git_branch()

      case ('G')
        ! Git status indicator (✓ clean, ✗ dirty, + staged, ± both)
        replacement = get_git_status_indicator()

      case ('p')
        ! Git ahead/behind upstream (e.g. ↑2↓1)
        replacement = get_git_ahead_behind()

      case ('P')
        ! Python virtual environment name (from VIRTUAL_ENV)
        replacement = get_venv_name()

      case ('S')
        ! Seconds since epoch (Unix timestamp)
        replacement = get_epoch_seconds()

      case default
        ! Unknown escape - just output the character
        replacement = escape_char
    end select

    ! Deallocate temp buffer
    if (allocated(temp)) deallocate(temp)
  end subroutine

  ! Get short hostname (up to first '.')
  function get_short_hostname(hostname) result(short_name)
    character(len=*), intent(in) :: hostname
    character(len=256) :: short_name
    integer :: dot_pos

    dot_pos = index(hostname, '.')
    if (dot_pos > 0) then
      short_name = hostname(:dot_pos-1)
    else
      short_name = trim(hostname)
    end if
  end function

  ! Get pretty path with ~ for home directory and intelligent shortening
  function get_pretty_path(path, shell) result(pretty)
    character(len=*), intent(in) :: path
    type(shell_state_t), intent(in) :: shell
    character(len=:), allocatable :: pretty, home_dir, temp_path
    character(len=:), allocatable :: branch, status, ab, venv
    character(len=:), allocatable :: rprompt_val
    integer :: home_len, term_rows, term_cols, max_path_len, overhead
    integer :: i, ps1_len, first_line_end, rprompt_width
    logical :: got_term_size

    home_dir = get_environment_var('HOME')

    ! Replace HOME with ~
    if (allocated(home_dir) .and. len(home_dir) > 0) then
      home_len = len(home_dir)
      if (len_trim(path) >= home_len) then
        if (path(:home_len) == home_dir(:home_len)) then
          if (len_trim(path) == home_len) then
            temp_path = '~'
          else
            temp_path = '~' // trim(path(home_len+1:))
          end if
        else
          temp_path = trim(path)
        end if
      else
        temp_path = trim(path)
      end if
    else
      temp_path = trim(path)
    end if

    ! Get terminal size to determine max path length
    got_term_size = get_terminal_size(term_rows, term_cols)
    if (got_term_size .and. term_cols > 0) then
      ps1_len = len_trim(shell%ps1)
      if (ps1_len > 0) then
        ! Find first line boundary in PS1 template
        first_line_end = 0
        do i = 1, ps1_len
          ! Check for literal newline
          if (shell%ps1(i:i) == char(10) .or. shell%ps1(i:i) == char(13)) then
            first_line_end = i - 1
            exit
          end if
          ! Check for \n escape sequence
          if (i < ps1_len .and. shell%ps1(i:i) == '\' .and. shell%ps1(i+1:i+1) == 'n') then
            first_line_end = i - 1
            exit
          end if
        end do
        if (first_line_end <= 0) first_line_end = ps1_len

        ! Count literal visible chars (non-escape, non-color chars)
        overhead = count_literal_chars(shell%ps1(1:first_line_end))

        ! Add widths of detected escape sequences (excluding \w itself)
        if (has_escape(shell%ps1(1:first_line_end), 'u')) &
          overhead = overhead + len_trim(shell%username)
        if (has_escape(shell%ps1(1:first_line_end), 'h')) &
          overhead = overhead + len_trim(get_short_hostname(shell%hostname))
        if (has_escape(shell%ps1(1:first_line_end), 'H')) &
          overhead = overhead + len_trim(shell%hostname)
        if (has_escape(shell%ps1(1:first_line_end), 'g')) then
          branch = get_git_branch()
          overhead = overhead + utf8_visual_width(branch)
        end if
        if (has_escape(shell%ps1(1:first_line_end), 'G')) then
          status = get_git_status_indicator()
          overhead = overhead + utf8_visual_width(status)
        end if
        if (has_escape(shell%ps1(1:first_line_end), 'p')) then
          ab = get_git_ahead_behind()
          overhead = overhead + utf8_visual_width(ab)
        end if
        if (has_escape(shell%ps1(1:first_line_end), 'P')) then
          venv = get_venv_name()
          overhead = overhead + utf8_visual_width(venv)
        end if
        ! Time/date escapes
        if (has_escape(shell%ps1(1:first_line_end), 't')) overhead = overhead + 8
        if (has_escape(shell%ps1(1:first_line_end), 'T')) overhead = overhead + 8
        if (has_escape(shell%ps1(1:first_line_end), 'A')) overhead = overhead + 5
        if (has_escape(shell%ps1(1:first_line_end), '@')) overhead = overhead + 8
        if (has_escape(shell%ps1(1:first_line_end), 'd')) overhead = overhead + 10
        if (has_escape(shell%ps1(1:first_line_end), 'D')) overhead = overhead + 10
        if (has_escape(shell%ps1(1:first_line_end), '$')) overhead = overhead + 1
        if (has_escape(shell%ps1(1:first_line_end), 's')) &
          overhead = overhead + len_trim(shell%shell_name)
        if (has_escape(shell%ps1(1:first_line_end), 'v')) overhead = overhead + 3
        if (has_escape(shell%ps1(1:first_line_end), 'V')) overhead = overhead + 5

        ! Account for RPROMPT width + minimum gap (readline requires 4-char gap)
        rprompt_val = get_shell_variable(shell, 'RPROMPT')
        if (len_trim(rprompt_val) > 0) then
          rprompt_width = count_literal_chars(rprompt_val)
          if (has_escape(rprompt_val, 'S')) rprompt_width = rprompt_width + 10
          if (has_escape(rprompt_val, 't')) rprompt_width = rprompt_width + 8
          if (has_escape(rprompt_val, 'T')) rprompt_width = rprompt_width + 8
          if (has_escape(rprompt_val, 'A')) rprompt_width = rprompt_width + 5
          if (has_escape(rprompt_val, 'D')) rprompt_width = rprompt_width + 10
          overhead = overhead + rprompt_width + 4  ! 4 = minimum gap
        end if

        max_path_len = term_cols - overhead
      else
        max_path_len = term_cols - 50
      end if
      if (max_path_len < 15) max_path_len = 15
    else
      max_path_len = 25
    end if

    ! Shorten path if needed
    if (len_trim(temp_path) > max_path_len) then
      pretty = shorten_path(temp_path, max_path_len)
    else
      pretty = temp_path
    end if
  end function

  ! Intelligently shorten a path by progressively abbreviating parent directories
  ! Pass 1: ~/ver/lon/pat/to/project (3-char parents)
  ! Pass 2: ~/v/l/p/t/project       (1-char parents)
  function shorten_path(path, max_length) result(shortened)
    character(len=*), intent(in) :: path
    integer, intent(in) :: max_length
    character(len=:), allocatable :: shortened
    character(len=256), allocatable :: components(:)
    integer :: num_components, i, slash_pos, comp_start, components_capacity
    character(len=:), allocatable :: result
    integer :: result_len, result_capacity, abbrev_len, use_len, comp_len

    ! If path is already short enough, return as-is
    if (len_trim(path) <= max_length) then
      shortened = trim(path)
      return
    end if

    ! Allocate initial components array
    components_capacity = 50
    allocate(components(components_capacity))

    ! Allocate result buffer
    result_capacity = 512
    allocate(character(len=result_capacity) :: result)

    ! Split path into components
    num_components = 0
    comp_start = 1

    do while (comp_start <= len_trim(path))
      slash_pos = index(path(comp_start:), '/')
      if (slash_pos > 0) then
        slash_pos = slash_pos + comp_start - 1
        if (slash_pos > comp_start) then
          num_components = num_components + 1
          if (num_components > components_capacity) then
            call grow_components_array(components, components_capacity)
          end if
          components(num_components) = path(comp_start:slash_pos-1)
        end if
        comp_start = slash_pos + 1
      else
        if (comp_start <= len_trim(path)) then
          num_components = num_components + 1
          if (num_components > components_capacity) then
            call grow_components_array(components, components_capacity)
          end if
          components(num_components) = path(comp_start:)
        end if
        exit
      end if
    end do

    ! Determine component start index (skip ~ component)
    if (len_trim(path) > 0 .and. path(1:1) == '~') then
      comp_start = 2
    else
      comp_start = 1
    end if

    ! Two-pass progressive shortening: 3-char parents, then 1-char parents
    do abbrev_len = 3, 1, -2
      result = repeat(' ', result_capacity)
      result_len = 0

      ! Write leading prefix
      if (len_trim(path) > 0 .and. path(1:1) == '~') then
        result(1:1) = '~'
        result_len = 1
      else if (len_trim(path) > 0 .and. path(1:1) == '/') then
        result(1:1) = '/'
        result_len = 1
      end if

      ! Build shortened parent components
      do i = comp_start, num_components - 1
        comp_len = len_trim(components(i))
        if (comp_len > 0) then
          if (result_len > 0 .and. result(result_len:result_len) /= '/') then
            result_len = result_len + 1
            result(result_len:result_len) = '/'
          end if
          ! Abbreviate parent to abbrev_len chars
          use_len = min(abbrev_len, comp_len)
          result(result_len+1:result_len+use_len) = components(i)(1:use_len)
          result_len = result_len + use_len
        end if
      end do

      ! Always show last component in full
      if (num_components > 0) then
        if (result_len > 0 .and. result(result_len:result_len) /= '/') then
          result_len = result_len + 1
          result(result_len:result_len) = '/'
        end if
        comp_len = len_trim(components(num_components))
        result(result_len+1:result_len+comp_len) = trim(components(num_components))
        result_len = result_len + comp_len
      end if

      ! If this pass fits or we're at minimum abbreviation, use it
      if (result_len <= max_length .or. abbrev_len == 1) then
        shortened = result(1:result_len)
        if (allocated(components)) deallocate(components)
        if (allocated(result)) deallocate(result)
        return
      end if
    end do

    ! Fallback (should not reach here)
    shortened = result(1:result_len)
    if (allocated(components)) deallocate(components)
    if (allocated(result)) deallocate(result)
  end function

  ! Get basename of path
  function get_basename(path) result(basename)
    character(len=*), intent(in) :: path
    character(len=256) :: basename
    integer :: i, last_slash

    last_slash = 0
    do i = len_trim(path), 1, -1
      if (path(i:i) == '/') then
        last_slash = i
        exit
      end if
    end do

    if (last_slash > 0 .and. last_slash < len_trim(path)) then
      basename = path(last_slash+1:)
    else if (last_slash == 0) then
      basename = trim(path)
    else
      basename = '/'
    end if
  end function

  ! Increment history number for next prompt
  subroutine increment_prompt_history()
    prompt_history_number = prompt_history_number + 1
  end subroutine

  ! Get current git branch name (returns empty string if not in git repo)
  function get_git_branch() result(branch)
    character(len=:), allocatable :: branch
    character(len=256) :: output

    if (cache_branch_valid) then
      branch = trim(cached_git_branch)
      return
    end if

    ! Try to get branch name using git command
    ! Use git symbolic-ref for speed (faster than git branch)
    output = execute_and_capture('git symbolic-ref --short HEAD 2>/dev/null')

    if (len_trim(output) > 0) then
      branch = trim(output)
    else
      ! Not in a git repo or detached HEAD
      branch = ''
    end if

    cached_git_branch = branch
    cache_branch_valid = .true.
  end function

  ! Get git status indicator with Unicode symbols
  ! Returns: '✓' if clean, '✗' if dirty (unstaged), '+' if staged, '±' if both
  ! Returns '' if not in a git repo
  function get_git_status_indicator() result(indicator)
    character(len=:), allocatable :: indicator
    character(len=4096) :: output
    logical :: has_staged, has_unstaged
    integer :: i, line_start

    if (cache_status_valid) then
      indicator = trim(cached_git_status)
      return
    end if

    ! First check if we're in a git repo
    output = execute_and_capture('git rev-parse --git-dir 2>/dev/null')
    if (len_trim(output) == 0) then
      indicator = ''
      cached_git_status = ''
      cache_status_valid = .true.
      return
    end if

    ! Check for uncommitted changes (both staged and unstaged)
    output = execute_and_capture('git status --porcelain 2>/dev/null')

    if (len_trim(output) == 0) then
      ! Clean working tree
      indicator = char(226) // char(156) // char(147)  ! ✓ (U+2713)
      cached_git_status = indicator
      cache_status_valid = .true.
      return
    end if

    ! Parse porcelain output: first column = index (staged), second = worktree
    has_staged = .false.
    has_unstaged = .false.
    line_start = 1
    do i = 1, len_trim(output)
      if (i == line_start .and. i + 1 <= len_trim(output)) then
        ! First char: staged status (non-space and non-? means staged)
        if (output(i:i) /= ' ' .and. output(i:i) /= '?') has_staged = .true.
        ! Second char: unstaged status (non-space means unstaged)
        if (output(i+1:i+1) /= ' ') has_unstaged = .true.
      end if
      if (output(i:i) == char(10)) line_start = i + 1
    end do
    ! Handle untracked files (lines starting with ??)
    if (index(output, '??') > 0) has_unstaged = .true.

    if (has_staged .and. has_unstaged) then
      indicator = char(194) // char(177)  ! ± (U+00B1)
    else if (has_staged) then
      indicator = '+'
    else
      indicator = char(226) // char(156) // char(151)  ! ✗ (U+2717)
    end if

    cached_git_status = indicator
    cache_status_valid = .true.
  end function

  ! Get git ahead/behind tracking info
  ! Returns e.g. '↑2↓1' for 2 ahead, 1 behind; '↑3' for 3 ahead; '' if up to date or no upstream
  function get_git_ahead_behind() result(info)
    character(len=:), allocatable :: info
    character(len=256) :: output
    integer :: ahead, behind, dot_pos, space_pos, iostat

    if (cache_ahead_behind_valid) then
      info = trim(cached_git_ahead_behind)
      return
    end if

    info = ''

    ! Get ahead/behind counts in one shot
    output = execute_and_capture('git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null')
    if (len_trim(output) == 0) then
      cached_git_ahead_behind = ''
      cache_ahead_behind_valid = .true.
      return
    end if

    ! Output format: "ahead\tbehind"
    ! Find the tab separator
    space_pos = 0
    do dot_pos = 1, len_trim(output)
      if (output(dot_pos:dot_pos) == char(9) .or. output(dot_pos:dot_pos) == ' ') then
        space_pos = dot_pos
        exit
      end if
    end do
    if (space_pos == 0) then
      cached_git_ahead_behind = ''
      cache_ahead_behind_valid = .true.
      return
    end if

    read(output(1:space_pos-1), *, iostat=iostat) ahead
    if (iostat /= 0) then
      cached_git_ahead_behind = ''
      cache_ahead_behind_valid = .true.
      return
    end if
    read(output(space_pos+1:), *, iostat=iostat) behind
    if (iostat /= 0) then
      cached_git_ahead_behind = ''
      cache_ahead_behind_valid = .true.
      return
    end if

    if (ahead == 0 .and. behind == 0) then
      cached_git_ahead_behind = ''
      cache_ahead_behind_valid = .true.
      return
    end if

    if (ahead > 0) then
      block
        character(len=16) :: num_str
        write(num_str, '(i0)') ahead
        ! ↑ = U+2191 = E2 86 91
        info = char(226) // char(134) // char(145) // trim(num_str)
      end block
    end if
    if (behind > 0) then
      block
        character(len=16) :: num_str
        write(num_str, '(i0)') behind
        ! ↓ = U+2193 = E2 86 93
        info = info // char(226) // char(134) // char(147) // trim(num_str)
      end block
    end if

    cached_git_ahead_behind = info
    cache_ahead_behind_valid = .true.
  end function

  ! Get Python virtual environment name from VIRTUAL_ENV
  ! Returns '(name)' if in a venv (e.g. '(.venv)'), '' if not
  function get_venv_name() result(name)
    character(len=:), allocatable :: name
    character(len=4096) :: venv_path
    integer :: i, last_sep, path_len
    character(len=:), allocatable :: basename

    if (cache_venv_valid) then
      name = trim(cached_venv_name)
      return
    end if

    call get_environment_variable('VIRTUAL_ENV', venv_path, status=i)
    if (i /= 0 .or. len_trim(venv_path) == 0) then
      name = ''
      cached_venv_name = ''
      cache_venv_valid = .true.
      return
    end if

    ! Extract basename (last component of path)
    path_len = len_trim(venv_path)
    ! Strip trailing slash if present
    if (venv_path(path_len:path_len) == '/') path_len = path_len - 1

    last_sep = 0
    do i = 1, path_len
      if (venv_path(i:i) == '/') last_sep = i
    end do

    if (last_sep > 0 .and. last_sep < path_len) then
      basename = venv_path(last_sep+1:path_len)
    else
      basename = trim(venv_path(1:path_len))
    end if

    name = '(' // basename // ')'
    cached_venv_name = name
    cache_venv_valid = .true.
  end function

  ! Check if current directory is in a git repository
  function is_git_repo() result(in_git)
    logical :: in_git
    character(len=256) :: output

    output = execute_and_capture('git rev-parse --git-dir 2>/dev/null')
    in_git = (len_trim(output) > 0)
  end function

  ! Get seconds since Unix epoch (for \S escape)
  function get_epoch_seconds() result(epoch_str)
    character(len=20) :: epoch_str
    integer(8) :: count, count_rate, count_max
    integer(8) :: epoch_seconds

    ! Get system clock count
    call system_clock(count, count_rate, count_max)

    ! Convert to seconds (this gives time since some system-defined epoch)
    ! For a proper Unix epoch, we use date_and_time to calculate
    epoch_seconds = get_unix_timestamp()
    write(epoch_str, '(i20)') epoch_seconds
    epoch_str = adjustl(epoch_str)
  end function

  ! Calculate Unix timestamp from current date/time
  function get_unix_timestamp() result(timestamp)
    integer(8) :: timestamp
    integer :: values(8)
    integer :: year, month, day, hour, minute, second
    integer :: days_since_epoch, y

    call date_and_time(values=values)
    year = values(1)
    month = values(2)
    day = values(3)
    hour = values(5)
    minute = values(6)
    second = values(7)

    ! Days from 1970 to start of current year
    days_since_epoch = 0
    do y = 1970, year - 1
      if (is_leap_year(y)) then
        days_since_epoch = days_since_epoch + 366
      else
        days_since_epoch = days_since_epoch + 365
      end if
    end do

    ! Days from start of year to start of current month
    days_since_epoch = days_since_epoch + days_before_month(month, is_leap_year(year))

    ! Add days in current month
    days_since_epoch = days_since_epoch + day - 1

    ! Convert to seconds and add time
    timestamp = int(days_since_epoch, 8) * 86400_8 + &
                int(hour, 8) * 3600_8 + int(minute, 8) * 60_8 + int(second, 8)
  end function

  ! Check if year is a leap year
  function is_leap_year(year) result(is_leap)
    integer, intent(in) :: year
    logical :: is_leap

    is_leap = (mod(year, 4) == 0 .and. mod(year, 100) /= 0) .or. (mod(year, 400) == 0)
  end function

  ! Get days before a given month (1-12)
  function days_before_month(month, leap) result(days)
    integer, intent(in) :: month
    logical, intent(in) :: leap
    integer :: days
    integer, dimension(12) :: days_in_month_normal = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    integer, dimension(12) :: days_in_month_leap = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    integer :: i

    days = 0
    if (leap) then
      do i = 1, month - 1
        days = days + days_in_month_leap(i)
      end do
    else
      do i = 1, month - 1
        days = days + days_in_month_normal(i)
      end do
    end if
  end function

  ! Convert zsh-style color name or number to ANSI escape sequence
  ! Supports: black, red, green, yellow, blue, magenta, cyan, white
  ! Also supports 256-color numbers (0-255)
  function get_ansi_color_code(color_name, is_foreground) result(ansi_code)
    character(len=*), intent(in) :: color_name
    logical, intent(in) :: is_foreground
    character(len=16) :: ansi_code
    integer :: color_num, base_code, iostat
    character(len=32) :: lower_name

    ansi_code = ''
    lower_name = to_lower(trim(color_name))

    ! Try to parse as number first
    read(color_name, *, iostat=iostat) color_num
    if (iostat == 0) then
      ! Valid number - use 256-color mode
      if (color_num >= 0 .and. color_num <= 255) then
        if (is_foreground) then
          write(ansi_code, '(a,i0,a)') char(27)//'[38;5;', color_num, 'm'
        else
          write(ansi_code, '(a,i0,a)') char(27)//'[48;5;', color_num, 'm'
        end if
      end if
      return
    end if

    ! Named colors
    base_code = 0
    select case (trim(lower_name))
      case ('black')
        base_code = 0
      case ('red')
        base_code = 1
      case ('green')
        base_code = 2
      case ('yellow')
        base_code = 3
      case ('blue')
        base_code = 4
      case ('magenta')
        base_code = 5
      case ('cyan')
        base_code = 6
      case ('white')
        base_code = 7
      case ('default')
        if (is_foreground) then
          ansi_code = char(27)//'[39m'
        else
          ansi_code = char(27)//'[49m'
        end if
        return
      case default
        return  ! Unknown color
    end select

    if (is_foreground) then
      write(ansi_code, '(a,i0,a)') char(27)//'[', 30 + base_code, 'm'
    else
      write(ansi_code, '(a,i0,a)') char(27)//'[', 40 + base_code, 'm'
    end if
  end function

  ! Convert string to lowercase
  function to_lower(str) result(lower)
    character(len=*), intent(in) :: str
    character(len=len(str)) :: lower
    integer :: i, ic

    lower = str
    do i = 1, len_trim(str)
      ic = iachar(str(i:i))
      if (ic >= iachar('A') .and. ic <= iachar('Z')) then
        lower(i:i) = achar(ic + 32)
      end if
    end do
  end function

  ! Expand zsh-style color escapes in a string
  ! Supports: %F{color}, %f, %K{color}, %k, %B, %b, %U, %u
  subroutine expand_zsh_colors(input_str, output_str, input_len)
    character(len=*), intent(in) :: input_str
    character(len=*), intent(out) :: output_str
    integer, intent(in), optional :: input_len

    integer :: i, j, k, str_len, brace_end
    character(len=32) :: color_name
    character(len=16) :: ansi_code

    output_str = ''
    j = 1
    i = 1

    if (present(input_len)) then
      str_len = input_len
    else
      str_len = len_trim(input_str)
    end if

    do while (i <= str_len .and. j <= len(output_str))
      if (input_str(i:i) == '%' .and. i < str_len) then
        select case (input_str(i+1:i+1))
          case ('F')
            ! Foreground color: %F{color}
            if (i + 2 <= str_len .and. input_str(i+2:i+2) == '{') then
              brace_end = index(input_str(i+3:), '}')
              if (brace_end > 0) then
                color_name = input_str(i+3:i+2+brace_end-1)
                ansi_code = get_ansi_color_code(trim(color_name), .true.)
                if (len_trim(ansi_code) > 0) then
                  k = len_trim(ansi_code)
                  if (j + k - 1 <= len(output_str)) then
                    output_str(j:j+k-1) = trim(ansi_code)
                    j = j + k
                  end if
                end if
                i = i + 3 + brace_end
                cycle
              end if
            end if
            ! Invalid format, output as-is
            output_str(j:j) = input_str(i:i)
            j = j + 1
            i = i + 1

          case ('f')
            ! Reset foreground color
            ansi_code = char(27)//'[39m'
            k = len_trim(ansi_code)
            if (j + k - 1 <= len(output_str)) then
              output_str(j:j+k-1) = trim(ansi_code)
              j = j + k
            end if
            i = i + 2

          case ('K')
            ! Background color: %K{color}
            if (i + 2 <= str_len .and. input_str(i+2:i+2) == '{') then
              brace_end = index(input_str(i+3:), '}')
              if (brace_end > 0) then
                color_name = input_str(i+3:i+2+brace_end-1)
                ansi_code = get_ansi_color_code(trim(color_name), .false.)
                if (len_trim(ansi_code) > 0) then
                  k = len_trim(ansi_code)
                  if (j + k - 1 <= len(output_str)) then
                    output_str(j:j+k-1) = trim(ansi_code)
                    j = j + k
                  end if
                end if
                i = i + 3 + brace_end
                cycle
              end if
            end if
            output_str(j:j) = input_str(i:i)
            j = j + 1
            i = i + 1

          case ('k')
            ! Reset background color
            ansi_code = char(27)//'[49m'
            k = len_trim(ansi_code)
            if (j + k - 1 <= len(output_str)) then
              output_str(j:j+k-1) = trim(ansi_code)
              j = j + k
            end if
            i = i + 2

          case ('B')
            ! Bold on
            ansi_code = char(27)//'[1m'
            k = len_trim(ansi_code)
            if (j + k - 1 <= len(output_str)) then
              output_str(j:j+k-1) = trim(ansi_code)
              j = j + k
            end if
            i = i + 2

          case ('b')
            ! Bold off
            ansi_code = char(27)//'[22m'
            k = len_trim(ansi_code)
            if (j + k - 1 <= len(output_str)) then
              output_str(j:j+k-1) = trim(ansi_code)
              j = j + k
            end if
            i = i + 2

          case ('U')
            ! Underline on
            ansi_code = char(27)//'[4m'
            k = len_trim(ansi_code)
            if (j + k - 1 <= len(output_str)) then
              output_str(j:j+k-1) = trim(ansi_code)
              j = j + k
            end if
            i = i + 2

          case ('u')
            ! Underline off
            ansi_code = char(27)//'[24m'
            k = len_trim(ansi_code)
            if (j + k - 1 <= len(output_str)) then
              output_str(j:j+k-1) = trim(ansi_code)
              j = j + k
            end if
            i = i + 2

          case ('%')
            ! Literal %
            output_str(j:j) = '%'
            j = j + 1
            i = i + 2

          case default
            ! Unknown escape, output as-is
            output_str(j:j) = input_str(i:i)
            j = j + 1
            i = i + 1
        end select
      else
        ! Regular character
        output_str(j:j) = input_str(i:i)
        j = j + 1
        i = i + 1
      end if
    end do
  end subroutine

  ! Helper to grow an allocatable string buffer
  subroutine grow_string_buffer(buffer, old_capacity, new_capacity)
    character(len=:), allocatable, intent(inout) :: buffer
    integer, intent(inout) :: old_capacity
    integer, intent(in) :: new_capacity
    character(len=:), allocatable :: temp

    ! Save current content
    allocate(character(len=new_capacity) :: temp)
    temp = ''
    if (allocated(buffer)) then
      temp(1:old_capacity) = buffer
      deallocate(buffer)
    end if

    ! Allocate new larger buffer
    allocate(character(len=new_capacity) :: buffer)
    buffer = temp
    old_capacity = new_capacity

    deallocate(temp)
  end subroutine

  ! Helper to grow an allocatable components array
  subroutine grow_components_array(array, current_size)
    character(len=256), allocatable, intent(inout) :: array(:)
    integer, intent(inout) :: current_size
    character(len=256), allocatable :: new_array(:)
    integer :: new_size

    new_size = current_size * 2
    allocate(new_array(new_size))

    ! Copy existing data
    new_array(1:current_size) = array(1:current_size)

    ! Swap arrays
    call move_alloc(new_array, array)
    current_size = new_size
  end subroutine

  ! Expand variable references and command substitutions in prompt strings
  ! Handles: $VAR, ${VAR}, $(command)
  subroutine expand_prompt_variables(input, shell, output)
    character(len=*), intent(in) :: input
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(out) :: output

    character(len=:), allocatable :: var_name, var_value
    character(len=4096) :: cmd_result
    integer :: i, j, start_pos, paren_count, brace_count, input_len
    character :: c

    output = ''
    j = 1
    i = 1
    input_len = len_trim(input)

    do while (i <= input_len .and. j < len(output))
      c = input(i:i)

      if (c == '$' .and. i < input_len) then
        ! Check what follows $
        if (input(i+1:i+1) == '(') then
          ! Command substitution $(...)
          start_pos = i + 2
          paren_count = 1
          i = i + 2

          ! Find matching closing parenthesis
          do while (i <= input_len .and. paren_count > 0)
            if (input(i:i) == '(') paren_count = paren_count + 1
            if (input(i:i) == ')') paren_count = paren_count - 1
            i = i + 1
          end do

          if (paren_count == 0) then
            ! Extract command and execute
            cmd_result = enhanced_command_substitution(shell, input(start_pos:i-2))
            ! Copy result to output
            if (len_trim(cmd_result) > 0) then
              if (j + len_trim(cmd_result) - 1 < len(output)) then
                output(j:j+len_trim(cmd_result)-1) = trim(cmd_result)
                j = j + len_trim(cmd_result)
              end if
            end if
          end if

        else if (input(i+1:i+1) == '{') then
          ! Brace-enclosed variable ${VAR}
          start_pos = i + 2
          brace_count = 1
          i = i + 2

          ! Find matching closing brace
          do while (i <= input_len .and. brace_count > 0)
            if (input(i:i) == '{') brace_count = brace_count + 1
            if (input(i:i) == '}') brace_count = brace_count - 1
            i = i + 1
          end do

          if (brace_count == 0) then
            var_name = input(start_pos:i-2)
            var_value = get_shell_variable(shell, trim(var_name))
            if (len_trim(var_value) > 0) then
              if (j + len_trim(var_value) - 1 < len(output)) then
                output(j:j+len_trim(var_value)-1) = trim(var_value)
                j = j + len_trim(var_value)
              end if
            end if
          end if

        else if (is_var_name_char(input(i+1:i+1))) then
          ! Simple variable $VAR
          start_pos = i + 1
          i = i + 1

          ! Read variable name (letters, digits, underscore)
          do while (i <= input_len .and. is_var_name_char(input(i:i)))
            i = i + 1
          end do

          var_name = input(start_pos:i-1)
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            if (j + len_trim(var_value) - 1 < len(output)) then
              output(j:j+len_trim(var_value)-1) = trim(var_value)
              j = j + len_trim(var_value)
            end if
          end if

        else
          ! Lone $ or unrecognized pattern - copy as-is
          output(j:j) = c
          j = j + 1
          i = i + 1
        end if

      else
        ! Regular character
        output(j:j) = c
        j = j + 1
        i = i + 1
      end if
    end do
  end subroutine

  ! Check if character is valid in a variable name
  function is_var_name_char(c) result(valid)
    character(len=1), intent(in) :: c
    logical :: valid
    integer :: ic

    ic = iachar(c)
    valid = (ic >= iachar('a') .and. ic <= iachar('z')) .or. &
            (ic >= iachar('A') .and. ic <= iachar('Z')) .or. &
            (ic >= iachar('0') .and. ic <= iachar('9')) .or. &
            c == '_'
  end function

  ! Invalidate prompt element cache (call at start of each prompt expansion)
  subroutine invalidate_prompt_cache()
    integer :: now_ms, count, count_rate

    ! Venv cache always invalidates (cheap to recompute)
    cache_venv_valid = .false.

    ! Git caches use a TTL — avoid forking git 2-3 times on every
    ! prompt when the user is just typing, resizing, or pressing Ctrl-L.
    call system_clock(count, count_rate)
    if (count_rate > 0) then
      now_ms = int(real(count) / real(count_rate) * 1000.0)
    else
      now_ms = 0
    end if

    if (git_cache_timestamp < 0 .or. &
        abs(now_ms - git_cache_timestamp) > GIT_CACHE_TTL_MS) then
      cache_branch_valid = .false.
      cache_status_valid = .false.
      cache_ahead_behind_valid = .false.
      git_cache_timestamp = now_ms
    end if
  end subroutine

  ! Check if a prompt template contains a specific escape sequence (\char)
  function has_escape(template, esc_char) result(found)
    character(len=*), intent(in) :: template
    character(len=1), intent(in) :: esc_char
    logical :: found
    integer :: i, tlen

    found = .false.
    tlen = len_trim(template)

    do i = 1, tlen - 1
      if (template(i:i) == '\' .and. template(i+1:i+1) == esc_char) then
        found = .true.
        return
      end if
    end do
  end function

  ! Count visible literal characters in a prompt template
  ! Skips: \x escape pairs, %F{...}, %K{...}, %f, %k, %B, %b, %U, %u
  function count_literal_chars(template) result(count)
    character(len=*), intent(in) :: template
    integer :: count
    integer :: i, tlen, brace_end

    count = 0
    i = 1
    tlen = len_trim(template)

    do while (i <= tlen)
      if (template(i:i) == '\' .and. i < tlen) then
        ! Skip \x escape pair (prompt escape, not a visible char)
        i = i + 2
      else if (template(i:i) == '%' .and. i < tlen) then
        ! Skip zsh-style color sequences
        select case (template(i+1:i+1))
          case ('F', 'K')
            ! %F{...} or %K{...} - skip to closing brace
            if (i + 2 <= tlen .and. template(i+2:i+2) == '{') then
              brace_end = index(template(i+3:), '}')
              if (brace_end > 0) then
                i = i + 3 + brace_end
              else
                i = i + 2
              end if
            else
              i = i + 2
            end if
          case ('f', 'k', 'B', 'b', 'U', 'u')
            ! Color/style resets - skip both chars
            i = i + 2
          case ('%')
            ! %% = literal %
            count = count + 1
            i = i + 2
          case default
            count = count + 1
            i = i + 1
        end select
      else
        count = count + 1
        i = i + 1
      end if
    end do
  end function

  ! Calculate visual width of a UTF-8 string (counts characters, not bytes)
  function utf8_visual_width(str) result(width)
    character(len=*), intent(in) :: str
    integer :: width
    integer :: i, byte_val

    width = 0
    do i = 1, len_trim(str)
      byte_val = iand(iachar(str(i:i)), 255)
      ! Skip UTF-8 continuation bytes (10xxxxxx = 128-191)
      if (byte_val < 128 .or. byte_val >= 192) then
        width = width + 1
      end if
    end do
  end function

end module prompt_formatting
