! ==============================================================================
! Module: parser
! Purpose: Command line parsing and tokenization
! ==============================================================================
module parser
  use shell_types
  use system_interface
  use variables
  use expansion
  use glob
  use error_handling
  use performance
  use iso_fortran_env, only: error_unit, input_unit
  implicit none

contains

  subroutine parse_pipeline(input, pipeline)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline

    character(len=len(input)) :: working_input
    integer :: pos, start, cmd_count
    integer :: i, comment_pos
    type(command_t), allocatable :: temp_commands(:)
    logical :: background, in_quotes
    character(len=1) :: quote_char

    integer(int64) :: parse_start_time

    ! Start performance timing
    call start_timer('parse_pipeline', parse_start_time)

    ! Validate input
    if (.not. validate_command(input)) then
      call parser_error(101, 'Invalid command input', 'parse_pipeline')
      pipeline%num_commands = 0
      return
    end if

    call debug_log('Parsing pipeline: ' // trim(input), 'parse_pipeline')

    allocate(temp_commands(MAX_PIPELINE))
    call track_allocation(MAX_PIPELINE * 1024, 'temp_commands')

    ! Strip comments (# to end of line, but not inside quotes)
    working_input = input
    in_quotes = .false.
    quote_char = ' '
    do i = 1, len_trim(working_input)
      if (in_quotes) then
        if (working_input(i:i) == quote_char) then
          in_quotes = .false.
        end if
      else
        if (working_input(i:i) == '"' .or. working_input(i:i) == "'") then
          in_quotes = .true.
          quote_char = working_input(i:i)
        else if (working_input(i:i) == '#') then
          ! Only treat # as comment if not part of $# and not in middle of word
          if (i > 1 .and. working_input(i-1:i-1) == '$') then
            ! This is $#, not a comment
            cycle
          end if
          ! Found comment, truncate here
          working_input = working_input(:i-1)
          exit
        end if
      end if
    end do
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
    
    ! Parse commands and separators (track quotes to avoid splitting inside them)
    i = 1
    in_quotes = .false.
    quote_char = ' '
    do while (i <= len_trim(working_input))
      ! Track quote state
      if (.not. in_quotes) then
        if (working_input(i:i) == '"' .or. working_input(i:i) == "'") then
          in_quotes = .true.
          quote_char = working_input(i:i)
        end if
      else
        if (working_input(i:i) == quote_char) then
          in_quotes = .false.
        end if
      end if

      ! Only check for operators outside quotes
      if (.not. in_quotes) then
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
        pipeline%commands(i)%redirect_stdout_to_stderr = temp_commands(i)%redirect_stdout_to_stderr
        pipeline%commands(i)%redirect_both_to_file = temp_commands(i)%redirect_both_to_file
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
        
        if (allocated(temp_commands(i)%here_string)) then
          pipeline%commands(i)%here_string = temp_commands(i)%here_string
        end if
      end do
    end if
    
    deallocate(temp_commands)
    call track_deallocation(MAX_PIPELINE * 1024, 'temp_commands')
    
    ! End performance timing
    call end_timer('parse_pipeline', parse_start_time, total_parse_time)
    total_commands = total_commands + 1
    
    ! Trigger auto memory optimization periodically
    if (mod(total_commands, 50_int64) == 0) then
      call auto_optimize_memory()
    end if
  end subroutine

  subroutine parse_single_command(input, cmd)
    character(len=*), intent(in) :: input
    type(command_t), intent(out) :: cmd
    
    character(len=len(input)) :: working_input
    integer :: pos, end_pos
    character(len=MAX_TOKEN_LEN) :: temp_str
    
    working_input = adjustl(input)
    
    ! Check for here-string (<<<) - must come before here document
    pos = index(working_input, '<<<')
    if (pos > 0) then
      call extract_filename(working_input(pos+3:), temp_str)
      cmd%here_string = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for here document (<<)
      pos = index(working_input, '<<')
      if (pos > 0) then
        call extract_word(working_input(pos+2:), temp_str)
        cmd%heredoc_delimiter = trim(temp_str)
        working_input = working_input(:pos-1)
      end if
    end if
    
    ! Check for advanced redirections first (must come before simpler ones)
    
    ! Check for 1>&2 (stdout to stderr)
    pos = index(working_input, '1>&2')
    if (pos > 0) then
      cmd%redirect_stdout_to_stderr = .true.
      working_input = working_input(:pos-1) // ' ' // working_input(pos+5:)
    else
      ! Check for >&2 (stdout to stderr shorthand)
      pos = index(working_input, '>&2')
      if (pos > 0) then
        cmd%redirect_stdout_to_stderr = .true.
        working_input = working_input(:pos-1) // ' ' // working_input(pos+4:)
      end if
    end if
    
    ! Check for 2>&1 (stderr to stdout)  
    pos = index(working_input, '2>&1')
    if (pos > 0) then
      cmd%redirect_stderr_to_stdout = .true.
      working_input = working_input(:pos-1) // ' ' // working_input(pos+4:)
    else
      ! Check for &>file or &>>file (both stdout and stderr to file)
      pos = index(working_input, '&>>')
      if (pos > 0) then
        cmd%redirect_both_to_file = .true.
        cmd%append_output = .true.
        cmd%append_error = .true.
        call extract_filename(working_input(pos+3:), temp_str)
        cmd%output_file = trim(temp_str)
        cmd%error_file = trim(temp_str)
        working_input = working_input(:pos-1)
      else
        pos = index(working_input, '&>')
        if (pos > 0) then
          cmd%redirect_both_to_file = .true.
          cmd%append_output = .false.
          cmd%append_error = .false.
          call extract_filename(working_input(pos+2:), temp_str)
          cmd%output_file = trim(temp_str)
          cmd%error_file = trim(temp_str)
          working_input = working_input(:pos-1)
        end if
      end if
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
      if (token(i:i) == '~' .and. (i == 1 .or. token(i-1:i-1) == ' ')) then
        ! Tilde expansion
        call process_tilde_expansion(token, i, result, j, shell)
      else if (token(i:i) == '$' .and. i < len_trim(token)) then
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
        else if (token(i:i) == '@') then
          ! $@ - all positional parameters
          var_value = get_shell_variable(shell, '@')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (token(i:i) == '#') then
          ! $# - number of positional parameters
          var_value = get_shell_variable(shell, '#')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (token(i:i) == '*') then
          ! $* - all positional parameters as single word
          var_value = get_shell_variable(shell, '*')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (token(i:i) >= '0' .and. token(i:i) <= '9') then
          ! $0, $1, $2, ... - positional parameters
          var_name = token(i:i)
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (token(i:i) == '(') then
          ! $(command) command substitution
          i = i + 1
          var_start = i
          brace_depth = 1
          
          do while (i <= len_trim(token) .and. brace_depth > 0)
            if (token(i:i) == '(') then
              brace_depth = brace_depth + 1
            else if (token(i:i) == ')') then
              brace_depth = brace_depth - 1
            end if
            i = i + 1
          end do
          
          var_name = token(var_start:i-2)  ! This is actually the command
          
          ! Execute command substitution
          call execute_command_substitution(trim(var_name), var_value, shell)
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len(var_value)-1) = var_value
            j = j + len(var_value)
          end if
        else if (token(i:i) == '{') then
          ! ${VAR} or ${VAR:operation} parameter expansion
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
          
          ! Process parameter expansion
          call process_parameter_expansion(var_name, var_value, shell)
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len(var_value)-1) = var_value
            j = j + len(var_value)
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
      else if (token(i:i) == '`') then
        ! Backtick command substitution
        i = i + 1
        var_start = i
        
        ! Find closing backtick
        do while (i <= len_trim(token) .and. token(i:i) /= '`')
          i = i + 1
        end do
        
        if (i <= len_trim(token) .and. token(i:i) == '`') then
          var_name = token(var_start:i-1)  ! This is the command
          i = i + 1  ! Skip closing backtick
          
          ! Execute command substitution
          call execute_command_substitution(trim(var_name), var_value, shell)
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len(var_value)-1) = var_value
            j = j + len(var_value)
          end if
        else
          ! Unmatched backtick, treat as literal
          result(j:j) = '`'
          j = j + 1
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

  ! Expand glob patterns in command tokens
  subroutine expand_command_globs(cmd)
    type(command_t), intent(inout) :: cmd
    
    character(len=MAX_TOKEN_LEN), allocatable :: expanded_tokens(:)
    character(len=MAX_TOKEN_LEN), allocatable :: original_tokens(:)
    integer :: expanded_count, i
    
    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens == 0) return
    
    ! Save original tokens
    allocate(original_tokens(cmd%num_tokens))
    do i = 1, cmd%num_tokens
      original_tokens(i) = cmd%tokens(i)
    end do
    
    ! Expand glob patterns
    call expand_glob_patterns(original_tokens, cmd%num_tokens, expanded_tokens, expanded_count)
    
    ! Replace command tokens with expanded ones
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)
    
    if (expanded_count > 0) then
      allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(expanded_count))
      do i = 1, expanded_count
        cmd%tokens(i) = expanded_tokens(i)
      end do
      cmd%num_tokens = expanded_count
    else
      ! No expansion occurred - restore original
      allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(cmd%num_tokens))
      do i = 1, cmd%num_tokens
        cmd%tokens(i) = original_tokens(i)
      end do
    end if
    
    ! Cleanup
    if (allocated(expanded_tokens)) deallocate(expanded_tokens)
    if (allocated(original_tokens)) deallocate(original_tokens)
  end subroutine

  subroutine execute_command_substitution(command, output, shell)
    character(len=*), intent(in) :: command
    character(len=:), allocatable, intent(out) :: output
    type(shell_state_t), intent(in) :: shell
    
    ! Use the existing execute_and_capture function
    output = execute_and_capture(command)
    
    ! Remove trailing newline for single-line output (bash behavior)
    do while (len(output) > 0 .and. output(len(output):len(output)) == char(10))
      output = output(:len(output)-1)
    end do
  end subroutine

  subroutine process_parameter_expansion(param_expr, result_value, shell)
    character(len=*), intent(in) :: param_expr
    character(len=:), allocatable, intent(out) :: result_value
    type(shell_state_t), intent(in) :: shell
    
    character(len=MAX_TOKEN_LEN) :: var_name, default_value, operation
    integer :: op_pos, op_len
    character(len=:), allocatable :: current_value
    character(len=20) :: length_str
    
    ! Initialize result
    result_value = ''
    
    ! Check for length expansion ${#var}
    if (param_expr(1:1) == '#') then
      var_name = param_expr(2:)
      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if
      if (allocated(current_value)) then
        write(length_str, '(i0)') len(current_value)
        result_value = trim(length_str)
      else
        result_value = '0'
      end if
      return
    end if
    
    ! Look for parameter expansion operators (:-, :=, :+)
    op_pos = 0
    op_len = 0
    
    ! Check for :- (default value)
    op_pos = index(param_expr, ':-')
    if (op_pos > 0) then
      op_len = 2
      operation = ':-'
    else
      ! Check for := (assign default)
      op_pos = index(param_expr, ':=')
      if (op_pos > 0) then
        op_len = 2
        operation = ':='
      else
        ! Check for :+ (alternate value)
        op_pos = index(param_expr, ':+')
        if (op_pos > 0) then
          op_len = 2
          operation = ':+'
        end if
      end if
    end if
    
    if (op_pos > 0) then
      ! Extract variable name and default value
      var_name = param_expr(:op_pos-1)
      default_value = param_expr(op_pos+op_len:)
    else
      ! Simple ${VAR} expansion
      var_name = param_expr
      default_value = ''
    end if
    
    ! Get current variable value
    current_value = get_shell_variable(shell, trim(var_name))
    if (len_trim(current_value) == 0) then
      current_value = get_environment_var(trim(var_name))
    end if
    
    ! Apply parameter expansion logic
    if (op_pos == 0) then
      ! Simple expansion ${VAR}
      if (allocated(current_value)) then
        result_value = current_value
      else
        result_value = ''
      end if
    else if (trim(operation) == ':-') then
      ! Use default value if variable is unset or empty
      if (allocated(current_value) .and. len(current_value) > 0) then
        result_value = current_value
      else
        result_value = trim(default_value)
      end if
    else if (trim(operation) == ':=') then
      ! Assign default if variable is unset or empty
      if (allocated(current_value) .and. len(current_value) > 0) then
        result_value = current_value
      else
        result_value = trim(default_value)
        ! Note: In a full implementation, we'd also set the variable here
      end if
    else if (trim(operation) == ':+') then
      ! Use alternate value if variable is set
      if (allocated(current_value) .and. len(current_value) > 0) then
        result_value = trim(default_value)
      else
        result_value = ''
      end if
    end if
  end subroutine

  subroutine process_tilde_expansion(token, pos, result, result_pos, shell)
    character(len=*), intent(in) :: token
    integer, intent(inout) :: pos, result_pos
    character(len=*), intent(inout) :: result
    type(shell_state_t), intent(in) :: shell
    
    character(len=MAX_TOKEN_LEN) :: username, home_path
    character(len=:), allocatable :: home_dir
    integer :: start_pos
    
    ! Skip the tilde
    pos = pos + 1
    
    if (pos > len_trim(token) .or. token(pos:pos) == '/' .or. token(pos:pos) == ' ') then
      ! Simple ~ expansion - use HOME environment variable
      home_dir = get_environment_var('HOME')
      if (allocated(home_dir) .and. len(home_dir) > 0) then
        result(result_pos:result_pos+len(home_dir)-1) = home_dir
        result_pos = result_pos + len(home_dir)
      else
        ! Fallback to /home/user if HOME not set
        home_dir = get_environment_var('USER')
        if (allocated(home_dir) .and. len(home_dir) > 0) then
          home_path = '/home/' // home_dir
          result(result_pos:result_pos+len_trim(home_path)-1) = trim(home_path)
          result_pos = result_pos + len_trim(home_path)
        else
          ! Last resort fallback
          result(result_pos:result_pos+5) = '/home/'
          result_pos = result_pos + 6
        end if
      end if
    else
      ! ~username expansion
      start_pos = pos
      do while (pos <= len_trim(token) .and. token(pos:pos) /= '/' .and. token(pos:pos) /= ' ')
        pos = pos + 1
      end do
      
      if (pos > start_pos) then
        username = token(start_pos:pos-1)
      else
        username = ''
      end if
      
      ! Simple implementation: assume user home is in /home/username
      ! In a full implementation, you'd use getpwnam() system call
      home_path = '/home/' // trim(username)
      result(result_pos:result_pos+len_trim(home_path)-1) = trim(home_path)
      result_pos = result_pos + len_trim(home_path)
      
      ! Don't increment pos here as it's already at the next character
      pos = pos - 1  ! Adjust because main loop will increment
    end if
  end subroutine

end module parser