! ==============================================================================
! Module: prompt_formatting
! Purpose: Prompt escape sequence expansion (PS1-PS4 with bash-style escapes)
! ==============================================================================
module prompt_formatting
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit
  implicit none

  ! History counter for prompts
  integer, save :: prompt_history_number = 1

contains

  ! Safe version that outputs to fixed-length buffer (no allocatable strings)
  ! Avoids LLVM Flang heap corruption bugs
  subroutine safe_expand_prompt(prompt_str, shell, stored_len, expanded)
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: prompt_str
    type(shell_state_t), intent(in) :: shell
    integer, intent(in), optional :: stored_len
    character(len=*), intent(out) :: expanded

    character(len=1024) :: result  ! Fixed-length buffer (avoid flang-new allocatable string bugs)
    integer :: i, j, prompt_len
    integer, parameter :: RESULT_CAPACITY = 1024
    character(len=256) :: replacement  ! Fixed-length buffer (avoid flang-new allocatable string bugs)

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
  end subroutine

  ! Main function to expand prompt string with escape sequences
  function expand_prompt(prompt_str, shell, stored_len) result(expanded)
    character(len=*), intent(in) :: prompt_str
    type(shell_state_t), intent(in) :: shell
    integer, intent(in), optional :: stored_len
    character(len=:), allocatable :: expanded

    ! Use allocatable to avoid stack allocation
    character(len=:), allocatable :: result
    integer :: i, j, prompt_len, result_capacity
    character(len=:), allocatable :: replacement  ! Heap allocation to avoid stack overflow

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
        ! Newline
        replacement = new_line('a')

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

    ! Try to get branch name using git command
    ! Use git symbolic-ref for speed (faster than git branch)
    output = execute_and_capture('git symbolic-ref --short HEAD 2>/dev/null')

    if (len_trim(output) > 0) then
      branch = trim(output)
    else
      ! Not in a git repo or detached HEAD
      branch = ''
    end if
  end function

  ! Get git status indicator
  ! Returns: '*' if dirty, '+' if staged changes, '✓' if clean, '' if not git repo
  function get_git_status_indicator() result(indicator)
    character(len=:), allocatable :: indicator
    character(len=256) :: output

    ! First check if we're in a git repo
    output = execute_and_capture('git rev-parse --git-dir 2>/dev/null')
    if (len_trim(output) == 0) then
      indicator = ''  ! Not in a git repo
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
  end function

  ! Check if current directory is in a git repository
  function is_git_repo() result(in_git)
    logical :: in_git
    character(len=256) :: output

    output = execute_and_capture('git rev-parse --git-dir 2>/dev/null')
    in_git = (len_trim(output) > 0)
  end function

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

end module prompt_formatting
