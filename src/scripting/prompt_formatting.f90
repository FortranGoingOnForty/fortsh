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

  ! Prompt element cache (valid for one prompt expansion cycle)
  character(len=256), save :: cached_git_branch = ''
  character(len=64), save :: cached_git_status = ''
  character(len=64), save :: cached_git_ahead_behind = ''
  character(len=256), save :: cached_venv_name = ''
  logical, save :: cache_branch_valid = .false.
  logical, save :: cache_status_valid = .false.
  logical, save :: cache_ahead_behind_valid = .false.
  logical, save :: cache_venv_valid = .false.

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

    character(len=1024) :: result  ! Fixed-length buffer (avoid flang-new allocatable string bugs)
    character(len=1024) :: var_expanded  ! Buffer for variable/command expansion
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
    character(len=1024) :: var_expanded  ! Buffer for variable/command expansion
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
        ! Current working directory (full path, with ~ for HOME)
        replacement = get_pretty_path(shell%cwd)

      case ('W')
        ! Basename of current working directory
        replacement = get_basename(shell%cwd)

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
        ! Git status indicator (* if dirty, + if staged, clean otherwise)
        replacement = get_git_status_indicator()

      case ('p')
        ! Git ahead/behind indicator
        temp = get_git_ahead_behind()
        replacement = trim(temp)

      case ('P')
        ! Virtual environment name
        temp = get_venv_name()
        replacement = trim(temp)

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
  function get_pretty_path(path) result(pretty)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: pretty, home_dir, temp_path
    integer :: home_len, term_rows, term_cols, max_path_len
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
      ! Reserve space for prompt elements (username, hostname, etc)
      ! Calculate based on actual prompt format: user@host :: path [branch] >
      ! Assume ~50 chars for username, hostname, decorators, git branch
      max_path_len = term_cols - 50  ! Be conservative to ensure readability
      if (max_path_len < 15) max_path_len = 15  ! Minimum 15 chars for path
    else
      ! Fallback if terminal size unavailable - assume narrow terminal
      max_path_len = 25  ! More aggressive default shortening
    end if

    ! Shorten path if needed
    if (len_trim(temp_path) > max_path_len) then
      pretty = shorten_path(temp_path, max_path_len)
    else
      pretty = temp_path
    end if
  end function

  ! Intelligently shorten a path by abbreviating parent directories
  ! Example: ~/very/long/path/to/project -> ~/v/l/p/t/project
  function shorten_path(path, max_length) result(shortened)
    character(len=*), intent(in) :: path
    integer, intent(in) :: max_length
    character(len=:), allocatable :: shortened
    character(len=256), allocatable :: components(:)
    integer :: num_components, i, slash_pos, start_pos, components_capacity
    character(len=:), allocatable :: result
    integer :: result_len, result_capacity

    ! If path is already short enough, return as-is
    if (len_trim(path) <= max_length) then
      shortened = trim(path)
      return
    end if

    ! Allocate initial components array
    components_capacity = 50
    allocate(components(components_capacity))

    ! Allocate result buffer - initialize with spaces
    result_capacity = 512
    allocate(character(len=result_capacity) :: result)
    result = repeat(' ', result_capacity)  ! Initialize properly

    ! Split path into components
    num_components = 0
    start_pos = 1

    do while (start_pos <= len_trim(path))
      slash_pos = index(path(start_pos:), '/')
      if (slash_pos > 0) then
        slash_pos = slash_pos + start_pos - 1
        if (slash_pos > start_pos) then
          num_components = num_components + 1
          ! Grow array if needed
          if (num_components > components_capacity) then
            call grow_components_array(components, components_capacity)
          end if
          components(num_components) = path(start_pos:slash_pos-1)
        end if
        start_pos = slash_pos + 1
      else
        ! Last component
        if (start_pos <= len_trim(path)) then
          num_components = num_components + 1
          ! Grow array if needed
          if (num_components > components_capacity) then
            call grow_components_array(components, components_capacity)
          end if
          components(num_components) = path(start_pos:)
        end if
        exit
      end if
    end do

    ! Build shortened path
    result_len = 0

    ! Handle leading ~ or /
    if (len_trim(path) > 0 .and. path(1:1) == '~') then
      result(1:1) = '~'
      result_len = 1
      start_pos = 2  ! Skip the ~ component
    else if (len_trim(path) > 0 .and. path(1:1) == '/') then
      result(1:1) = '/'
      result_len = 1
      start_pos = 1
    else
      start_pos = 1
    end if

    ! Shorten all components except the last one
    do i = start_pos, num_components - 1
      if (len_trim(components(i)) > 0) then
        if (result_len > 0 .and. result(result_len:result_len) /= '/') then
          result_len = result_len + 1
          if (result_len > result_capacity) then
            call grow_string_buffer(result, result_capacity, result_capacity * 2)
          end if
          result(result_len:result_len) = '/'
        end if
        ! Use first character of each parent directory
        result_len = result_len + 1
        if (result_len > result_capacity) then
          call grow_string_buffer(result, result_capacity, result_capacity * 2)
        end if
        result(result_len:result_len) = components(i)(1:1)
      end if
    end do

    ! Always show the last component in full (the current directory name)
    if (num_components > 0) then
      if (result_len > 0 .and. result(result_len:result_len) /= '/') then
        result_len = result_len + 1
        if (result_len > result_capacity) then
          call grow_string_buffer(result, result_capacity, result_capacity * 2)
        end if
        result(result_len:result_len) = '/'
      end if
      if (result_len + len_trim(components(num_components)) > result_capacity) then
        call grow_string_buffer(result, result_capacity, result_len + len_trim(components(num_components)) + 256)
      end if
      result(result_len+1:result_len+len_trim(components(num_components))) = &
        trim(components(num_components))
      result_len = result_len + len_trim(components(num_components))
    end if

    shortened = result(1:result_len)

    ! Clean up
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

  ! Get git status indicator
  ! Returns: '*' if dirty, '+' if staged changes, '✓' if clean, '' if not git repo
  function get_git_status_indicator() result(indicator)
    character(len=:), allocatable :: indicator
    character(len=256) :: output

    if (cache_status_valid) then
      indicator = trim(cached_git_status)
      return
    end if

    ! First check if we're in a git repo
    output = execute_and_capture('git rev-parse --git-dir 2>/dev/null')
    if (len_trim(output) == 0) then
      indicator = ''  ! Not in a git repo
      cached_git_status = ''
      cache_status_valid = .true.
      return
    end if

    ! Check for uncommitted changes (both staged and unstaged)
    ! Using git status --porcelain for machine-readable output
    output = execute_and_capture('git status --porcelain 2>/dev/null')

    if (len_trim(output) > 0) then
      ! There are changes
      ! Check if any are staged (lines starting with A, M, D, R, C in first column)
      if (index(output, 'A ') > 0 .or. index(output, 'M ') > 0 .or. &
          index(output, 'D ') > 0 .or. index(output, 'R ') > 0) then
        indicator = '+'  ! Staged changes
      else
        indicator = '*'  ! Unstaged changes
      end if
    else
      ! Clean working tree
      indicator = ''  ! Clean (or use '✓' if you want to show clean status)
    end if

    cached_git_status = indicator
    cache_status_valid = .true.
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
    cache_branch_valid = .false.
    cache_status_valid = .false.
    cache_ahead_behind_valid = .false.
    cache_venv_valid = .false.
  end subroutine

  ! Get git ahead/behind counts relative to upstream
  ! Returns: '↑N↓M', '↑N', '↓M', or '' if no upstream or not in git repo
  function get_git_ahead_behind() result(ab)
    character(len=:), allocatable :: ab
    character(len=256) :: output
    integer :: ahead, behind, iostat

    if (cache_ahead_behind_valid) then
      ab = trim(cached_git_ahead_behind)
      return
    end if

    ! Get ahead/behind counts
    output = execute_and_capture( &
      'git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null')

    if (len_trim(output) > 0) then
      ! Parse "behind<tab>ahead" format
      read(output, *, iostat=iostat) behind, ahead
      if (iostat == 0) then
        if (ahead > 0 .and. behind > 0) then
          write(output, '(a,i0,a,i0)') char(226)//char(134)//char(145), ahead, &
            char(226)//char(134)//char(147), behind
          ab = trim(output)
        else if (ahead > 0) then
          write(output, '(a,i0)') char(226)//char(134)//char(145), ahead
          ab = trim(output)
        else if (behind > 0) then
          write(output, '(a,i0)') char(226)//char(134)//char(147), behind
          ab = trim(output)
        else
          ab = ''
        end if
      else
        ab = ''
      end if
    else
      ab = ''
    end if

    cached_git_ahead_behind = ab
    cache_ahead_behind_valid = .true.
  end function

  ! Get virtual environment name from VIRTUAL_ENV
  ! Returns: '(name)' or '' if no venv active
  function get_venv_name() result(venv)
    character(len=:), allocatable :: venv, virtual_env
    integer :: i, last_slash

    if (cache_venv_valid) then
      venv = trim(cached_venv_name)
      return
    end if

    virtual_env = get_environment_var('VIRTUAL_ENV')

    if (allocated(virtual_env) .and. len_trim(virtual_env) > 0) then
      ! Extract the last path component (venv directory name)
      last_slash = 0
      do i = len_trim(virtual_env), 1, -1
        if (virtual_env(i:i) == '/') then
          last_slash = i
          exit
        end if
      end do
      if (last_slash > 0 .and. last_slash < len_trim(virtual_env)) then
        venv = '(' // trim(virtual_env(last_slash+1:)) // ')'
      else
        venv = '(' // trim(virtual_env) // ')'
      end if
    else
      venv = ''
    end if

    cached_venv_name = venv
    cache_venv_valid = .true.
  end function

end module prompt_formatting
