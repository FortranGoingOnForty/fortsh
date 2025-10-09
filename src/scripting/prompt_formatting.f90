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

  ! Main function to expand prompt string with escape sequences
  function expand_prompt(prompt_str, shell) result(expanded)
    character(len=*), intent(in) :: prompt_str
    type(shell_state_t), intent(in) :: shell
    character(len=:), allocatable :: expanded

    character(len=4096) :: result
    integer :: i, j, prompt_len
    character(len=256) :: replacement

    result = ''
    j = 1
    i = 1
    prompt_len = len_trim(prompt_str)

    do while (i <= prompt_len)
      if (prompt_str(i:i) == '\' .and. i < prompt_len) then
        ! Process escape sequence
        i = i + 1
        call process_escape_sequence(prompt_str(i:i), shell, replacement)

        if (len_trim(replacement) > 0) then
          result(j:j+len_trim(replacement)-1) = trim(replacement)
          j = j + len_trim(replacement)
        end if
        i = i + 1
      else
        ! Regular character
        result(j:j) = prompt_str(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    expanded = trim(result)
  end function

  ! Process individual escape sequence
  subroutine process_escape_sequence(escape_char, shell, replacement)
    character(len=1), intent(in) :: escape_char
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(out) :: replacement

    character(len=256) :: temp
    integer :: values(8), year, month, day, hour, minute, second
    character(len=3), dimension(7) :: day_names = &
      ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    character(len=3), dimension(12) :: month_names = &
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', &
       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    integer :: day_of_week

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
        write(replacement, '(i0)') prompt_history_number

      case ('#')
        ! Command number
        write(replacement, '(i0)') shell%command_number

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
        write(replacement, '(i0)') shell%num_jobs

      case default
        ! Unknown escape - just output the character
        replacement = escape_char
    end select
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

  ! Get pretty path with ~ for home directory
  function get_pretty_path(path) result(pretty)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: pretty, home_dir
    integer :: home_len

    home_dir = get_environment_var('HOME')

    if (allocated(home_dir) .and. len(home_dir) > 0) then
      home_len = len(home_dir)
      if (len_trim(path) >= home_len) then
        if (path(:home_len) == home_dir(:home_len)) then
          if (len_trim(path) == home_len) then
            pretty = '~'
          else
            pretty = '~' // trim(path(home_len+1:))
          end if
          return
        end if
      end if
    end if

    pretty = trim(path)
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

end module prompt_formatting
