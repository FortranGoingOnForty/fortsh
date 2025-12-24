! ==============================================================================
! Module: read_builtin  
! Purpose: Interactive read built-in with options and prompts
! ==============================================================================
module read_builtin
  use shell_types
  use variables
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

contains

  subroutine builtin_read(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: prompt, var_name, delimiter
    character(len=1024) :: input_line
    integer :: timeout_sec, arg_index
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
          read(cmd%tokens(arg_index + 1), *, iostat=arg_index) timeout_sec
          if (arg_index /= 0) then
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
          read(cmd%tokens(arg_index + 1), *, iostat=arg_index) nchars
          if (arg_index /= 0) then
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
    if (use_nchars) then
      call read_n_characters(nchars, input_line)
    else if (use_delimiter) then
      call read_until_delimiter(delimiter, input_line)
    else if (use_timeout) then
      call read_with_timeout(timeout_sec, input_line, shell%last_exit_status)
    else
      call read_line_input(input_line)
    end if

    ! Process input based on raw mode
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
      ! Single variable
      call set_shell_variable(shell, var_name, trim(input_line))
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine read_line_input(input_line)
    character(len=*), intent(out) :: input_line
    integer :: iostat
    
    read(input_unit, '(a)', iostat=iostat) input_line
    if (iostat /= 0) input_line = ''
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
    integer, intent(in) :: timeout_sec
    character(len=*), intent(out) :: input_line
    integer, intent(out) :: exit_status
    integer :: iostat

    ! Simplified timeout implementation
    ! In a real implementation, this would use select() or similar with timeout_sec
    input_line = ''
    exit_status = 1  ! Timeout
    if (.false.) print *, timeout_sec  ! Silence unused warning (timeout not yet implemented)

    ! For now, just read normally
    read(input_unit, '(a)', iostat=iostat) input_line
    if (iostat == 0) then
      exit_status = 0
    end if
  end subroutine

  subroutine process_backslash_escapes(input_line)
    character(len=*), intent(inout) :: input_line
    
    character(len=len(input_line)) :: processed
    integer :: i, j
    
    processed = ''
    i = 1
    j = 1
    
    do while (i <= len_trim(input_line))
      if (input_line(i:i) == '\' .and. i < len_trim(input_line)) then
        i = i + 1
        select case (input_line(i:i))
        case ('n')
          processed(j:j) = char(10)  ! newline
        case ('t')
          processed(j:j) = char(9)   ! tab
        case ('r')
          processed(j:j) = char(13)  ! carriage return
        case ('b')
          processed(j:j) = char(8)   ! backspace
        case ('a')
          processed(j:j) = char(7)   ! bell
        case ('\')
          processed(j:j) = '\'
        case ('"')
          processed(j:j) = '"'
        case ("'")
          processed(j:j) = "'"
        case default
          processed(j:j) = input_line(i:i)
        end select
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
    character(len=1024) :: ifs_value
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
    do while (pos <= input_len .and. word_count < var_count)
      is_ifs_char = (index(ifs_value, input_line(pos:pos)) > 0)

      if (is_ifs_char) then
        if (pos > start_pos) then
          word_count = word_count + 1
          words(word_count) = input_line(start_pos:pos-1)

          ! If we've filled all but the last variable, assign remaining input to last var
          if (word_count >= var_count - 1) then
            ! Skip IFS chars before remainder
            pos = pos + 1
            do while (pos <= input_len .and. index(ifs_value, input_line(pos:pos)) > 0)
              pos = pos + 1
            end do
            if (pos <= input_len) then
              word_count = word_count + 1
              words(word_count) = input_line(pos:input_len)
            end if
            exit
          end if
        end if

        ! Skip all consecutive IFS chars to find start of next word
        do while (pos <= input_len .and. index(ifs_value, input_line(pos:pos)) > 0)
          pos = pos + 1
        end do
        start_pos = pos
        ! Don't increment pos, just continue to next iteration
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