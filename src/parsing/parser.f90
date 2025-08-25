! ==============================================================================
! Module: parser
! Purpose: Command line parsing and tokenization
! ==============================================================================
module parser
  use shell_types
  use system_interface
  use variables
  use iso_fortran_env, only: error_unit, input_unit
  implicit none

contains

  subroutine parse_pipeline(input, pipeline)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline
    
    character(len=len(input)) :: working_input
    integer :: pos, start, cmd_count
    integer :: i
    type(command_t), allocatable :: temp_commands(:)
    logical :: background
    
    allocate(temp_commands(MAX_PIPELINE))
    working_input = input
    cmd_count = 0
    start = 1
    background = .false.
    
    ! Check for background execution (&)
    if (len_trim(working_input) > 0) then
      if (working_input(len_trim(working_input):len_trim(working_input)) == '&') then
        background = .true.
        working_input = working_input(:len_trim(working_input)-1)
      end if
    end if
    
    ! Parse commands and separators
    i = 1
    do while (i <= len_trim(working_input))
      ! Check for operators
      if (i <= len_trim(working_input) - 1) then
        if (working_input(i:i+1) == '&&') then
          cmd_count = cmd_count + 1
          if (cmd_count <= MAX_PIPELINE) then
            call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
            temp_commands(cmd_count)%separator = SEP_AND
          end if
          start = i + 2
          i = i + 2
          cycle
        else if (working_input(i:i+1) == '||') then
          cmd_count = cmd_count + 1
          if (cmd_count <= MAX_PIPELINE) then
            call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
            temp_commands(cmd_count)%separator = SEP_OR
          end if
          start = i + 2
          i = i + 2
          cycle
        end if
      end if
      
      if (working_input(i:i) == '|' .and. &
          (i == 1 .or. working_input(i-1:i-1) /= '|') .and. &
          (i == len_trim(working_input) .or. working_input(i+1:i+1) /= '|')) then
        cmd_count = cmd_count + 1
        if (cmd_count <= MAX_PIPELINE) then
          call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
          temp_commands(cmd_count)%separator = SEP_PIPE
        end if
        start = i + 1
      else if (working_input(i:i) == ';') then
        cmd_count = cmd_count + 1
        if (cmd_count <= MAX_PIPELINE) then
          call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
          temp_commands(cmd_count)%separator = SEP_SEMICOLON
        end if
        start = i + 1
      end if
      
      i = i + 1
    end do
    
    ! Don't forget the last command
    if (start <= len_trim(working_input)) then
      cmd_count = cmd_count + 1
      if (cmd_count <= MAX_PIPELINE) then
        call parse_single_command(working_input(start:), temp_commands(cmd_count))
        temp_commands(cmd_count)%separator = SEP_NONE
      end if
    end if
    
    ! Set background flag for last command
    if (cmd_count > 0 .and. background) then
      temp_commands(cmd_count)%background = .true.
    end if
    
    ! Copy to pipeline with explicit token copying
    pipeline%num_commands = cmd_count
    if (cmd_count > 0) then
      allocate(pipeline%commands(cmd_count))
      do i = 1, cmd_count
        ! Copy non-allocatable components
        pipeline%commands(i)%num_tokens = temp_commands(i)%num_tokens
        pipeline%commands(i)%append_output = temp_commands(i)%append_output
        pipeline%commands(i)%append_error = temp_commands(i)%append_error
        pipeline%commands(i)%redirect_stderr_to_stdout = temp_commands(i)%redirect_stderr_to_stdout
        pipeline%commands(i)%background = temp_commands(i)%background
        pipeline%commands(i)%separator = temp_commands(i)%separator
        
        ! Copy allocatable components explicitly
        if (allocated(temp_commands(i)%tokens)) then
          allocate(character(len=MAX_TOKEN_LEN) :: pipeline%commands(i)%tokens(temp_commands(i)%num_tokens))
          pipeline%commands(i)%tokens = temp_commands(i)%tokens
        end if
        
        if (allocated(temp_commands(i)%input_file)) then
          pipeline%commands(i)%input_file = temp_commands(i)%input_file
        end if
        if (allocated(temp_commands(i)%output_file)) then
          pipeline%commands(i)%output_file = temp_commands(i)%output_file
        end if
        if (allocated(temp_commands(i)%error_file)) then
          pipeline%commands(i)%error_file = temp_commands(i)%error_file
        end if
        if (allocated(temp_commands(i)%heredoc_delimiter)) then
          pipeline%commands(i)%heredoc_delimiter = temp_commands(i)%heredoc_delimiter
        end if
        if (allocated(temp_commands(i)%heredoc_content)) then
          pipeline%commands(i)%heredoc_content = temp_commands(i)%heredoc_content
        end if
      end do
    end if
    
    deallocate(temp_commands)
  end subroutine

  subroutine parse_single_command(input, cmd)
    character(len=*), intent(in) :: input
    type(command_t), intent(out) :: cmd
    
    character(len=len(input)) :: working_input
    integer :: pos, end_pos
    character(len=MAX_TOKEN_LEN) :: temp_str
    
    working_input = adjustl(input)
    
    ! Check for here document (<<)
    pos = index(working_input, '<<')
    if (pos > 0) then
      call extract_word(working_input(pos+2:), temp_str)
      cmd%heredoc_delimiter = trim(temp_str)
      working_input = working_input(:pos-1)
    end if
    
    ! Check for 2>&1 (must come before other redirections)
    pos = index(working_input, '2>&1')
    if (pos > 0) then
      cmd%redirect_stderr_to_stdout = .true.
      working_input = working_input(:pos-1) // ' ' // working_input(pos+4:)
    end if
    
    ! Check for error redirection (2>>)
    pos = index(working_input, '2>>')
    if (pos > 0) then
      cmd%append_error = .true.
      call extract_filename(working_input(pos+3:), temp_str)
      cmd%error_file = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for error redirection (2>)
      pos = index(working_input, '2>')
      if (pos > 0) then
        cmd%append_error = .false.
        call extract_filename(working_input(pos+2:), temp_str)
        cmd%error_file = trim(temp_str)
        working_input = working_input(:pos-1)
      end if
    end if
    
    ! Check for output redirection (>>)
    pos = index(working_input, '>>')
    if (pos > 0) then
      cmd%append_output = .true.
      call extract_filename(working_input(pos+2:), temp_str)
      cmd%output_file = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for output redirection (>)
      pos = index(working_input, '>')
      if (pos > 0) then
        cmd%append_output = .false.
        call extract_filename(working_input(pos+1:), temp_str)
        cmd%output_file = trim(temp_str)
        working_input = working_input(:pos-1)
      end if
    end if
    
    ! Check for input redirection (<)
    pos = index(working_input, '<')
    if (pos > 0) then
      call extract_filename(working_input(pos+1:), temp_str)
      cmd%input_file = trim(temp_str)
      working_input = working_input(:pos-1)
    end if
    
    ! Tokenize the remaining command
    call tokenize_with_substitution(trim(working_input), cmd%tokens, cmd%num_tokens)
    
  end subroutine

  subroutine extract_filename(input, filename)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: filename
    integer :: i
    
    filename = adjustl(input)
    
    do i = 1, len_trim(filename)
      if (filename(i:i) == ' ' .or. filename(i:i) == char(9)) then
        filename = filename(:i-1)
        exit
      end if
    end do
  end subroutine

  subroutine extract_word(input, word)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: word
    integer :: i
    
    word = adjustl(input)
    
    do i = 1, len_trim(word)
      if (word(i:i) == ' ' .or. word(i:i) == char(9) .or. &
          word(i:i) == '<' .or. word(i:i) == '>' .or. &
          word(i:i) == '|' .or. word(i:i) == '&' .or. &
          word(i:i) == ';') then
        word = word(:i-1)
        exit
      end if
    end do
  end subroutine

  subroutine tokenize_with_substitution(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens
    
    character(len=len(input)) :: working_copy
    integer :: pos, start, token_count, i, token_len
    character(len=MAX_TOKEN_LEN), allocatable :: temp_tokens(:)
    
    working_copy = adjustl(input)
    if (len_trim(working_copy) == 0) then
      num_tokens = 0
      return
    end if
    
    ! Count tokens first
    token_count = 0
    pos = 1
    do while (pos <= len_trim(working_copy))
      ! Skip whitespace
      do while (pos <= len_trim(working_copy) .and. working_copy(pos:pos) == ' ')
        pos = pos + 1
      end do
      if (pos > len_trim(working_copy)) exit
      
      ! Found start of token
      token_count = token_count + 1
      
      ! Skip to end of token
      do while (pos <= len_trim(working_copy) .and. working_copy(pos:pos) /= ' ')
        pos = pos + 1
      end do
    end do
    
    num_tokens = token_count
    if (num_tokens == 0) return
    
    ! Allocate temporary storage
    allocate(temp_tokens(num_tokens))
    
    ! Extract tokens into temporary array
    pos = 1
    token_count = 0
    do while (pos <= len_trim(working_copy) .and. token_count < num_tokens)
      ! Skip whitespace
      do while (pos <= len_trim(working_copy) .and. working_copy(pos:pos) == ' ')
        pos = pos + 1
      end do
      if (pos > len_trim(working_copy)) exit
      
      start = pos
      
      ! Find end of token
      do while (pos <= len_trim(working_copy) .and. working_copy(pos:pos) /= ' ')
        pos = pos + 1
      end do
      
      ! Store token
      token_count = token_count + 1
      temp_tokens(token_count) = working_copy(start:pos-1)
    end do
    
    ! Now allocate the final deferred-length character array
    ! We'll use MAX_TOKEN_LEN as a uniform length for now
    allocate(character(len=MAX_TOKEN_LEN) :: tokens(num_tokens))
    do i = 1, num_tokens
      tokens(i) = temp_tokens(i)
    end do
    
    deallocate(temp_tokens)
  end subroutine

  subroutine expand_variables(token, expanded, shell)
    character(len=*), intent(in) :: token
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(in) :: shell
    
    character(len=MAX_TOKEN_LEN) :: result
    integer :: i, j, var_start, brace_depth
    character(len=MAX_TOKEN_LEN) :: var_name
    character(len=:), allocatable :: var_value
    character(len=20) :: pid_str
    
    result = ''
    i = 1
    j = 1
    
    do while (i <= len_trim(token))
      if (token(i:i) == '$' .and. i < len_trim(token)) then
        i = i + 1
        
        ! Check for special variables
        if (token(i:i) == '?') then
          write(result(j:), '(i0)') shell%last_exit_status
          j = j + len_trim(result(j:))
          i = i + 1
        else if (token(i:i) == '$') then
          write(pid_str, '(i0)') c_getpid()
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (token(i:i) == '!') then
          write(pid_str, '(i0)') shell%last_pid
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (token(i:i) == '{') then
          ! ${VAR} syntax
          i = i + 1
          var_start = i
          brace_depth = 1
          
          do while (i <= len_trim(token) .and. brace_depth > 0)
            if (token(i:i) == '{') then
              brace_depth = brace_depth + 1
            else if (token(i:i) == '}') then
              brace_depth = brace_depth - 1
            end if
            i = i + 1
          end do
          
          var_name = token(var_start:i-2)
          
          ! Check shell variables first
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          else
            ! Fall back to environment variables
            var_value = get_environment_var(trim(var_name))
            if (allocated(var_value) .and. len(var_value) > 0) then
              result(j:j+len(var_value)-1) = var_value
              j = j + len(var_value)
            end if
          end if
        else
          ! Simple $VAR syntax
          var_start = i
          do while (i <= len_trim(token))
            if (.not. (is_alnum(token(i:i)) .or. token(i:i) == '_')) exit
            i = i + 1
          end do
          
          var_name = token(var_start:i-1)
          
          ! Check shell variables first
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          else
            ! Fall back to environment variables
            var_value = get_environment_var(trim(var_name))
            if (allocated(var_value) .and. len(var_value) > 0) then
              result(j:j+len(var_value)-1) = var_value
              j = j + len(var_value)
            end if
          end if
        end if
      else
        result(j:j) = token(i:i)
        i = i + 1
        j = j + 1
      end if
    end do
    
    expanded = trim(result)
    
  contains
    
    function is_alnum(ch) result(res)
      character, intent(in) :: ch
      logical :: res
      res = (ch >= 'a' .and. ch <= 'z') .or. &
            (ch >= 'A' .and. ch <= 'Z') .or. &
            (ch >= '0' .and. ch <= '9')
    end function
    
  end subroutine

  subroutine read_heredoc(delimiter, content)
    character(len=*), intent(in) :: delimiter
    character(len=:), allocatable, intent(out) :: content
    
    character(len=MAX_TOKEN_LEN) :: line
    character(len=MAX_HEREDOC_LEN) :: buffer
    integer :: iostat, pos
    
    buffer = ''
    pos = 1
    
    write(*, '(a)', advance='no') '> '
    
    do
      read(*, '(a)', iostat=iostat) line
      if (iostat /= 0) exit
      
      if (trim(line) == trim(delimiter)) exit
      
      if (pos > 1) then
        buffer(pos:pos) = char(10)  ! newline
        pos = pos + 1
      end if
      
      buffer(pos:pos+len_trim(line)-1) = trim(line)
      pos = pos + len_trim(line)
      
      write(*, '(a)', advance='no') '> '
    end do
    
    allocate(character(len=pos-1) :: content)
    content = buffer(:pos-1)
  end subroutine

end module parser