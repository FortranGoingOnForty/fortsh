! ==============================================================================
! Module: read_builtin  
! Purpose: Interactive read built-in with options and prompts
! ==============================================================================
module read_builtin
  use shell_types
  use variables
  use iso_fortran_env, only: input_unit, output_unit, error_unit, &
    IOSTAT_EOR, IOSTAT_END
  implicit none

contains

  subroutine builtin_read(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: prompt, var_name, delimiter
    character(len=4096) :: input_line
    integer :: timeout_sec, arg_index, actual_input_len, parse_ios
    logical :: silent_mode, raw_mode, use_prompt, use_timeout, use_delimiter
    logical :: use_array, use_nchars
    integer :: nchars
    
    ! Initialize options
    prompt = ''
    var_name = 'REPLY'  ! default variable
    delimiter = char(10)  ! newline
    timeout_sec = 0
    silent_mode = .false.
    raw_mode = .false.
    use_prompt = .false.
    use_timeout = .false.
    use_delimiter = .false.
    use_array = .false.
    use_nchars = .false.
    nchars = 0
    
    ! Parse options
    arg_index = 2
    do while (arg_index <= cmd%num_tokens)
      select case (trim(cmd%tokens(arg_index)))
      case ('-p')
        ! Prompt
        if (arg_index + 1 <= cmd%num_tokens) then
          prompt = cmd%tokens(arg_index + 1)
          use_prompt = .true.
          arg_index = arg_index + 2
        else
          write(error_unit, '(a)') 'read: -p option requires an argument'
          shell%last_exit_status = 1
          return
        end if
      case ('-t')
        ! Timeout
        if (arg_index + 1 <= cmd%num_tokens) then
          read(cmd%tokens(arg_index + 1), *, iostat=parse_ios) timeout_sec
          if (parse_ios /= 0) then
            write(error_unit, '(a)') 'read: invalid timeout value'
            shell%last_exit_status = 1
            return
          end if
          use_timeout = .true.
          arg_index = arg_index + 2
        else
          write(error_unit, '(a)') 'read: -t option requires an argument'
          shell%last_exit_status = 1
          return
        end if
      case ('-s')
        ! Silent mode (no echo)
        silent_mode = .true.
        arg_index = arg_index + 1
      case ('-r')
        ! Raw mode (don't interpret backslashes)
        raw_mode = .true.
        arg_index = arg_index + 1
      case ('-d')
        ! Delimiter
        if (arg_index + 1 <= cmd%num_tokens) then
          delimiter = cmd%tokens(arg_index + 1)(1:1)
          use_delimiter = .true.
          arg_index = arg_index + 2
        else
          write(error_unit, '(a)') 'read: -d option requires an argument'
          shell%last_exit_status = 1
          return
        end if
      case ('-a')
        ! Array mode
        if (arg_index + 1 <= cmd%num_tokens) then
          var_name = cmd%tokens(arg_index + 1)
          use_array = .true.
          arg_index = arg_index + 2
        else
          write(error_unit, '(a)') 'read: -a option requires an argument'
          shell%last_exit_status = 1
          return
        end if
      case ('-n')
        ! Read n characters
        if (arg_index + 1 <= cmd%num_tokens) then
          read(cmd%tokens(arg_index + 1), *, iostat=parse_ios) nchars
          if (parse_ios /= 0) then
            write(error_unit, '(a)') 'read: invalid character count'
            shell%last_exit_status = 1
            return
          end if
          use_nchars = .true.
          arg_index = arg_index + 2
        else
          write(error_unit, '(a)') 'read: -n option requires an argument'
          shell%last_exit_status = 1
          return
        end if
      case default
        ! Variable names - don't exit, let the loop collect all of them
        if (cmd%tokens(arg_index)(1:1) /= '-') then
          ! Found first variable name, mark where variables start
          if (var_name == 'REPLY') then
            var_name = cmd%tokens(arg_index)  ! Save first var for single-var case
          end if
          exit  ! Exit to start processing variables
        else
          write(error_unit, '(a,a)') 'read: unknown option: ', trim(cmd%tokens(arg_index))
          shell%last_exit_status = 1
          return
        end if
      end select
    end do

    ! Display prompt if specified
    if (use_prompt) then
      write(output_unit, '(a)', advance='no') trim(prompt)
    end if

    ! Read input based on options
    block
      logical :: eof_reached
      eof_reached = .false.

      actual_input_len = 0
      if (use_nchars) then
        call read_n_characters(nchars, input_line)
        actual_input_len = len_trim(input_line)
      else if (use_delimiter) then
        call read_until_delimiter(delimiter, input_line)
        actual_input_len = len_trim(input_line)
      else if (use_timeout) then
        call read_with_timeout(timeout_sec, input_line, &
          shell%last_exit_status)
        actual_input_len = len_trim(input_line)
        if (shell%last_exit_status /= 0) return
      else
        call read_line_input(input_line, eof_reached, raw_mode, &
          actual_input_len)
      end if

      ! Process backslash escapes (but not continuation, which was handled above)
      if (.not. raw_mode) then
        call process_backslash_escapes(input_line)
      end if

      ! Store result in variable(s)
      if (use_array) then
        call store_array_result(shell, var_name, input_line)
      else if (arg_index < cmd%num_tokens) then
        ! Multiple variables: start from arg_index (first variable)
        call store_multiple_variables(shell, cmd%tokens, arg_index, cmd%num_tokens, input_line)
      else
        ! Single variable — strip leading and trailing IFS whitespace
        ! When IFS is explicitly set to empty, preserve all whitespace
        ! When IFS is explicitly set to empty (ifs_len==0),
        ! preserve all whitespace. ifs_len==-1 means default.
        if (shell%ifs_len == 0) then
          call set_shell_variable(shell, var_name, &
            input_line(:actual_input_len), actual_input_len)
        else
          call set_shell_variable(shell, var_name, &
            trim(adjustl(input_line)))
        end if
      end if

      ! Set exit status: 1 if EOF reached without reading any data, 0 otherwise
      if (eof_reached .and. len_trim(input_line) == 0) then
        shell%last_exit_status = 1
      else
        shell%last_exit_status = 0
      end if
    end block
  end subroutine

  subroutine read_line_input(input_line, eof_reached, raw_mode, &
      input_length)
    character(len=*), intent(out) :: input_line
    logical, intent(out), optional :: eof_reached
    logical, intent(in), optional :: raw_mode
    integer, intent(out), optional :: input_length
    integer :: iostat, line_len, nchars
    character(len=4096) :: continuation_line
    logical :: is_raw

    is_raw = .false.
    if (present(raw_mode)) is_raw = raw_mode

    ! Use non-advancing I/O to get actual character count
    input_line = ''
    nchars = 0
    read(input_unit, '(a)', iostat=iostat, advance='no', &
      size=nchars) input_line
    if (iostat == IOSTAT_EOR .or. iostat == 0) then
      if (present(eof_reached)) eof_reached = .false.
      if (present(input_length)) input_length = nchars
    else if (iostat == IOSTAT_END) then
      input_line = ''
      if (present(eof_reached)) eof_reached = .true.
      if (present(input_length)) input_length = 0
      return
    else
      input_line = ''
      if (present(eof_reached)) eof_reached = .true.
      if (present(input_length)) input_length = 0
      return
    end if

    ! POSIX: Without -r, backslash at end of line continues to next line
    if (.not. is_raw) then
      do while (.true.)
        line_len = len_trim(input_line)
        if (line_len == 0) exit
        ! Check if line ends with backslash
        if (input_line(line_len:line_len) == '\') then
          ! Remove trailing backslash
          input_line(line_len:line_len) = ' '
          ! Read next line
          read(input_unit, '(a)', iostat=iostat) continuation_line
          if (iostat /= 0) exit
          ! Append continuation line
          input_line = trim(input_line) // trim(continuation_line)
          if (present(input_length)) then
            input_length = len_trim(input_line)
          end if
        else
          exit
        end if
      end do
    end if
  end subroutine

  subroutine read_n_characters(n, input_line)
    integer, intent(in) :: n
    character(len=*), intent(out) :: input_line
    
    integer :: i, iostat
    character :: ch
    
    input_line = ''
    
    do i = 1, min(n, len(input_line))
      read(input_unit, '(a1)', iostat=iostat) ch
      if (iostat /= 0) exit
      input_line(i:i) = ch
    end do
  end subroutine

  subroutine read_until_delimiter(delimiter, input_line)
    character, intent(in) :: delimiter
    character(len=*), intent(out) :: input_line
    
    character :: ch
    integer :: pos, iostat
    
    input_line = ''
    pos = 1
    
    do while (pos <= len(input_line))
      read(input_unit, '(a1)', iostat=iostat) ch
      if (iostat /= 0) exit
      
      if (ch == delimiter) then
        exit
      end if
      
      input_line(pos:pos) = ch
      pos = pos + 1
    end do
  end subroutine

  subroutine read_with_timeout(timeout_sec, input_line, exit_status)
    use system_interface, only: input_ready_within
    integer, intent(in) :: timeout_sec
    character(len=*), intent(out) :: input_line
    integer, intent(out) :: exit_status
    integer :: iostat

    input_line = ''

    ! Wait up to timeout_sec for input via poll(); on timeout return a status
    ! greater than 128 (bash's `read -t` semantics).
    if (.not. input_ready_within(timeout_sec * 1000)) then
      exit_status = 142  ! 128 + SIGALRM, matching bash's timeout status
      return
    end if

    read(input_unit, '(a)', iostat=iostat) input_line
    if (iostat == 0) then
      exit_status = 0
    else
      exit_status = 1  ! EOF / error
    end if
  end subroutine

  subroutine process_backslash_escapes(input_line)
    character(len=*), intent(inout) :: input_line

    character(len=len(input_line)) :: processed
    integer :: i, j

    ! POSIX: Without -r, backslash removes itself and preserves the following char
    ! This is NOT like printf escapes - \n becomes literal 'n', not newline
    ! The only special case is \<newline> which is handled in read_line_input

    processed = ''
    i = 1
    j = 1

    do while (i <= len_trim(input_line))
      if (input_line(i:i) == '\' .and. i < len_trim(input_line)) then
        ! Skip the backslash, keep the next character literally
        i = i + 1
        processed(j:j) = input_line(i:i)
        j = j + 1
        i = i + 1
      else
        processed(j:j) = input_line(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    input_line = processed
  end subroutine

  subroutine store_array_result(shell, var_name, input_line)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: var_name, input_line

    character(len=256) :: words(50)
    integer :: word_count, start_pos, pos
    
    word_count = 0
    pos = 1
    start_pos = 1
    
    ! Split input into words
    do while (pos <= len_trim(input_line))
      if (input_line(pos:pos) == ' ' .or. input_line(pos:pos) == char(9)) then
        if (pos > start_pos .and. word_count < 50) then
          word_count = word_count + 1
          words(word_count) = input_line(start_pos:pos-1)
        end if
        start_pos = pos + 1
      end if
      pos = pos + 1
    end do
    
    ! Handle last word
    if (start_pos <= len_trim(input_line) .and. word_count < 50) then
      word_count = word_count + 1
      words(word_count) = input_line(start_pos:)
    end if
    
    ! Store as array
    if (word_count > 0) then
      call set_array_variable(shell, var_name, words, word_count)
    end if
  end subroutine

  subroutine store_multiple_variables(shell, tokens, start_arg, num_tokens, input_line)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: start_arg, num_tokens
    character(len=*), intent(in) :: input_line

    character(len=256) :: words(20)
    character(len=:), allocatable :: ifs_value
    integer :: word_count, var_count, i, pos, start_pos, input_len
    logical :: is_ifs_char

    ! Get IFS value (default is space, tab, newline)
    ifs_value = get_shell_variable(shell, 'IFS')
    if (len_trim(ifs_value) == 0 .or. trim(ifs_value) == ' \t\n') then
      ! Default IFS: space, tab, newline as actual characters
      ifs_value = ' ' // char(9) // char(10)
    end if

    word_count = 0
    var_count = num_tokens - start_arg + 1
    input_len = len_trim(input_line)
    pos = 1

    ! Skip leading IFS whitespace
    do while (pos <= input_len)
      if (index(ifs_value, input_line(pos:pos)) > 0) then
        pos = pos + 1
      else
        exit
      end if
    end do

    start_pos = pos

    ! Split input by IFS characters
    ! POSIX: For non-whitespace IFS chars, consecutive delimiters create empty fields
    do while (pos <= input_len .and. word_count < var_count)
      is_ifs_char = (index(ifs_value, input_line(pos:pos)) > 0)

      if (is_ifs_char) then
        ! Record the word before this IFS char (may be empty if consecutive IFS)
        if (pos > start_pos) then
          word_count = word_count + 1
          words(word_count) = input_line(start_pos:pos-1)
        else
          ! Empty field (consecutive IFS chars for non-whitespace delimiters)
          ! Only create empty field for non-whitespace IFS characters
          if (index(' ' // char(9) // char(10), input_line(pos:pos)) == 0) then
            word_count = word_count + 1
            words(word_count) = ''
          end if
        end if

        ! If we've filled all but the last variable, assign remaining input to last var
        if (word_count >= var_count - 1) then
          ! Skip current IFS char
          pos = pos + 1
          ! Skip only whitespace IFS chars before remainder
          do while (pos <= input_len)
            if (index(' ' // char(9) // char(10), input_line(pos:pos)) > 0 .and. &
                index(ifs_value, input_line(pos:pos)) > 0) then
              pos = pos + 1
            else
              exit
            end if
          end do
          if (pos <= input_len) then
            word_count = word_count + 1
            words(word_count) = input_line(pos:input_len)
          end if
          exit
        end if

        ! Skip this IFS char
        pos = pos + 1

        ! Only skip additional consecutive whitespace IFS chars
        do while (pos <= input_len)
          if (index(' ' // char(9) // char(10), input_line(pos:pos)) > 0 .and. &
              index(ifs_value, input_line(pos:pos)) > 0) then
            pos = pos + 1
          else
            exit
          end if
        end do
        start_pos = pos
        cycle
      end if

      ! Not an IFS char, keep scanning
      pos = pos + 1
    end do

    ! Handle last word if we haven't filled all variables yet
    if (word_count < var_count .and. start_pos <= input_len) then
      word_count = word_count + 1
      words(word_count) = input_line(start_pos:input_len)
    end if

    ! Assign to variables
    do i = start_arg, num_tokens
      if (i - start_arg + 1 <= word_count) then
        call set_shell_variable(shell, trim(tokens(i)), trim(words(i - start_arg + 1)))
      else
        call set_shell_variable(shell, trim(tokens(i)), '')
      end if
    end do
  end subroutine

end module read_builtin