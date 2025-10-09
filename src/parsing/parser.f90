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
    logical :: background, in_quotes, in_param_expansion, in_for_arith
    character(len=1) :: quote_char
    integer :: paren_depth

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

    ! Strip comments (# to end of line, but not inside quotes or ${})
    working_input = input
    in_quotes = .false.
    quote_char = ' '
    in_param_expansion = .false.
    do i = 1, len_trim(working_input)
      if (in_quotes) then
        if (working_input(i:i) == quote_char) then
          in_quotes = .false.
        end if
      else
        ! Track ${...} parameter expansion
        if (i > 1 .and. working_input(i-1:i) == '${') then
          in_param_expansion = .true.
        else if (in_param_expansion .and. working_input(i:i) == '}') then
          in_param_expansion = .false.
        end if

        if (working_input(i:i) == '"' .or. working_input(i:i) == "'") then
          in_quotes = .true.
          quote_char = working_input(i:i)
        else if (working_input(i:i) == '#' .and. .not. in_param_expansion) then
          ! Only treat # as comment if not part of $# or ${...}
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
    in_for_arith = .false.
    paren_depth = 0
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
        ! Detect for (( at the beginning of command
        if (.not. in_for_arith .and. i <= len_trim(working_input)-1) then
          if (working_input(i:i+1) == '((') then
            ! Check if 'for' appears before this
            if (start <= i-1) then
              if (index(working_input(start:i-1), 'for') > 0) then
                in_for_arith = .true.
                paren_depth = 0  ! Will be counted as we process
              end if
            end if
          end if
        end if

        ! Track parentheses depth inside for (( ... ))
        if (in_for_arith) then
          if (working_input(i:i) == '(') then
            paren_depth = paren_depth + 1
          else if (working_input(i:i) == ')') then
            paren_depth = paren_depth - 1
            ! Exit for (( when we've closed all parens
            if (paren_depth == 0) then
              in_for_arith = .false.
            end if
          end if
        end if

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
          if (in_for_arith) then
          else
            ! Only split on semicolon if not inside for (( ... ))
            cmd_count = cmd_count + 1
            if (cmd_count <= MAX_PIPELINE) then
              call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
              temp_commands(cmd_count)%separator = SEP_SEMICOLON
            end if
            start = i + 1
          end if
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

    ! Skip redirection processing for arithmetic commands ((expression)) and for (( loops
    if (len_trim(working_input) >= 2 .and. working_input(1:2) == '((') then
      ! This is an arithmetic command - tokenize directly without processing redirects
      call tokenize_with_substitution(trim(working_input), cmd%tokens, cmd%num_tokens)
      return
    end if

    ! Also skip redirection processing for arithmetic for loops for((...))
    if (len_trim(working_input) >= 5 .and. working_input(1:5) == 'for((') then
      ! This is an arithmetic for loop - tokenize directly without processing redirects
      call tokenize_with_substitution(trim(working_input), cmd%tokens, cmd%num_tokens)
      return
    end if

    ! Also handle 'for ((' with space (standard bash syntax)
    if (len_trim(working_input) >= 6 .and. working_input(1:6) == 'for ((') then
      ! This is an arithmetic for loop with space - tokenize directly without processing redirects
      call tokenize_with_substitution(trim(working_input), cmd%tokens, cmd%num_tokens)
      return
    end if

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
    logical :: in_quotes, in_arith, in_array_literal
    character :: quote_char
    integer :: arith_depth, array_depth

    working_copy = adjustl(input)
    write(error_unit, '(a,a,a)') 'DEBUG tokenize: input=[', trim(input), ']'
    if (len_trim(working_copy) == 0) then
      num_tokens = 0
      return
    end if

    ! Count tokens first - must track quotes, $((  )), and array literals
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
      in_quotes = .false.
      in_arith = .false.
      arith_depth = 0
      quote_char = ' '
      in_array_literal = .false.
      array_depth = 0

      ! Skip to end of token (respecting quotes and arithmetic)
      do while (pos <= len_trim(working_copy))
        ! Check for quotes
        if (.not. in_arith) then
          if (.not. in_quotes .and. (working_copy(pos:pos) == '"' .or. working_copy(pos:pos) == "'")) then
            in_quotes = .true.
            quote_char = working_copy(pos:pos)
          else if (in_quotes .and. working_copy(pos:pos) == quote_char) then
            in_quotes = .false.
          end if
        end if

        ! Check for $((  )) arithmetic expansion and ((  )) arithmetic command
        if (.not. in_quotes) then
          ! First, check for special patterns that start arithmetic mode
          if (.not. in_arith) then
            if (pos <= len_trim(working_copy) - 2 .and. working_copy(pos:pos+2) == '$((') then
              in_arith = .true.
              arith_depth = 2
              pos = pos + 2  ! Skip the $(
            else if (pos == start .and. pos <= len_trim(working_copy) - 1 .and. &
                     working_copy(pos:pos+1) == '((') then
              ! (( at start of token - arithmetic command
              in_arith = .true.
              arith_depth = 2
              pos = pos + 1  ! Skip the first (
            else if (pos == start+3 .and. start <= len_trim(working_copy) - 4 .and. &
                     working_copy(start:start+2) == 'for' .and. &
                     working_copy(pos:pos+1) == '((') then
              ! for(( - arithmetic for loop
              in_arith = .true.
              arith_depth = 0  ! Will be counted below
            end if
          end if

          ! Then, track parentheses depth if in arithmetic mode
          if (in_arith) then
            if (working_copy(pos:pos) == '(') then
              arith_depth = arith_depth + 1
            else if (working_copy(pos:pos) == ')') then
              arith_depth = arith_depth - 1
              if (arith_depth == 0) then
                in_arith = .false.
              end if
            end if
          end if
        end if

        ! Check for array literal: var=(...)
        if (.not. in_quotes .and. .not. in_arith) then
          if (pos > 1 .and. pos <= len_trim(working_copy) - 1 .and. &
              working_copy(pos-1:pos) == '=(') then
            ! Start of array literal
            in_array_literal = .true.
            array_depth = 1
          else if (in_array_literal) then
            if (working_copy(pos:pos) == '(') then
              array_depth = array_depth + 1
            else if (working_copy(pos:pos) == ')') then
              array_depth = array_depth - 1
              if (array_depth == 0) in_array_literal = .false.
            end if
          end if
        end if

        ! Check for token boundary (space outside quotes/arithmetic/array)
        if (.not. in_quotes .and. .not. in_arith .and. .not. in_array_literal .and. &
            working_copy(pos:pos) == ' ') exit

        pos = pos + 1
      end do
    end do

    num_tokens = token_count
    if (num_tokens == 0) return

    ! Allocate temporary storage
    allocate(temp_tokens(num_tokens))

    ! Extract tokens into temporary array (same logic as counting)
    pos = 1
    token_count = 0
    do while (pos <= len_trim(working_copy) .and. token_count < num_tokens)
      ! Skip whitespace
      do while (pos <= len_trim(working_copy) .and. working_copy(pos:pos) == ' ')
        pos = pos + 1
      end do
      if (pos > len_trim(working_copy)) exit

      start = pos
      in_quotes = .false.
      in_arith = .false.
      arith_depth = 0
      quote_char = ' '
      in_array_literal = .false.
      array_depth = 0

      ! Find end of token (respecting quotes, arithmetic, and array literals)
      do while (pos <= len_trim(working_copy))
        ! Check for quotes
        if (.not. in_arith) then
          if (.not. in_quotes .and. (working_copy(pos:pos) == '"' .or. working_copy(pos:pos) == "'")) then
            in_quotes = .true.
            quote_char = working_copy(pos:pos)
          else if (in_quotes .and. working_copy(pos:pos) == quote_char) then
            in_quotes = .false.
          end if
        end if

        ! Check for $((  )) arithmetic expansion and ((  )) arithmetic command
        if (.not. in_quotes) then
          ! First, check for special patterns that start arithmetic mode
          if (.not. in_arith) then
            if (pos <= len_trim(working_copy) - 2 .and. working_copy(pos:pos+2) == '$((') then
              in_arith = .true.
              arith_depth = 2
              pos = pos + 2  ! Skip the $(
            else if (pos == start .and. pos <= len_trim(working_copy) - 1 .and. &
                     working_copy(pos:pos+1) == '((') then
              ! (( at start of token - arithmetic command
              in_arith = .true.
              arith_depth = 2
              pos = pos + 1  ! Skip the first (
            else if (pos == start+3 .and. start <= len_trim(working_copy) - 4 .and. &
                     working_copy(start:start+2) == 'for' .and. &
                     working_copy(pos:pos+1) == '((') then
              ! for(( - arithmetic for loop
              in_arith = .true.
              arith_depth = 0  ! Will be counted below
            end if
          end if

          ! Then, track parentheses depth if in arithmetic mode
          if (in_arith) then
            if (working_copy(pos:pos) == '(') then
              arith_depth = arith_depth + 1
            else if (working_copy(pos:pos) == ')') then
              arith_depth = arith_depth - 1
              if (arith_depth == 0) then
                in_arith = .false.
              end if
            end if
          end if
        end if

        ! Check for array literal: var=(...)
        if (.not. in_quotes .and. .not. in_arith) then
          if (pos > 1 .and. pos <= len_trim(working_copy) - 1 .and. &
              working_copy(pos-1:pos) == '=(') then
            ! Start of array literal
            in_array_literal = .true.
            array_depth = 1
          else if (in_array_literal) then
            if (working_copy(pos:pos) == '(') then
              array_depth = array_depth + 1
            else if (working_copy(pos:pos) == ')') then
              array_depth = array_depth - 1
              if (array_depth == 0) in_array_literal = .false.
            end if
          end if
        end if

        ! Check for token boundary (space outside quotes/arithmetic/array)
        if (.not. in_quotes .and. .not. in_arith .and. .not. in_array_literal .and. &
            working_copy(pos:pos) == ' ') exit

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
    type(shell_state_t), intent(inout) :: shell
    
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
          ! Check if it's $(( arithmetic expansion or $( command substitution
          if (i+1 <= len_trim(token) .and. token(i+1:i+1) == '(') then
            ! $((arithmetic)) expansion
            var_start = i - 1  ! Include the $ character
            i = i + 2  ! Skip both opening parens
            brace_depth = 2

            do while (i <= len_trim(token) .and. brace_depth > 0)
              if (token(i:i) == '(') then
                brace_depth = brace_depth + 1
              else if (token(i:i) == ')') then
                brace_depth = brace_depth - 1
              end if
              i = i + 1
            end do

            ! Extract full $((expr)) including delimiters
            var_name = token(var_start:i-1)

            ! Evaluate arithmetic expansion with shell context
            var_value = arithmetic_expansion_shell(trim(var_name), shell)
            if (len_trim(var_value) > 0) then
              result(j:j+len_trim(var_value)-1) = trim(var_value)
              j = j + len_trim(var_value)
            end if
          else
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

  ! Simple pattern matching for shell expansions (supports * wildcard)
  function shell_pattern_match(text, pattern) result(matches)
    character(len=*), intent(in) :: text, pattern
    logical :: matches
    integer :: t_pos, p_pos, star_pos, match_pos

    matches = .false.
    t_pos = 1
    p_pos = 1
    star_pos = 0
    match_pos = 0

    do while (t_pos <= len_trim(text))
      if (p_pos <= len_trim(pattern) .and. &
          (pattern(p_pos:p_pos) == text(t_pos:t_pos) .or. pattern(p_pos:p_pos) == '?')) then
        t_pos = t_pos + 1
        p_pos = p_pos + 1
      else if (p_pos <= len_trim(pattern) .and. pattern(p_pos:p_pos) == '*') then
        star_pos = p_pos
        match_pos = t_pos
        p_pos = p_pos + 1
      else if (star_pos > 0) then
        p_pos = star_pos + 1
        match_pos = match_pos + 1
        t_pos = match_pos
      else
        return
      end if
    end do

    do while (p_pos <= len_trim(pattern) .and. pattern(p_pos:p_pos) == '*')
      p_pos = p_pos + 1
    end do

    matches = (p_pos > len_trim(pattern))
  end function

  ! Remove shortest match from beginning
  function remove_prefix_shortest(text, pattern) result(output)
    character(len=*), intent(in) :: text, pattern
    character(len=:), allocatable :: output
    integer :: i

    ! Try matching from shortest to longest
    do i = 1, len_trim(text)
      if (shell_pattern_match(text(1:i), trim(pattern))) then
        output = text(i+1:)
        return
      end if
    end do
    output = text
  end function

  ! Remove longest match from beginning
  function remove_prefix_longest(text, pattern) result(output)
    character(len=*), intent(in) :: text, pattern
    character(len=:), allocatable :: output
    integer :: i

    ! Try matching from longest to shortest
    do i = len_trim(text), 1, -1
      if (shell_pattern_match(text(1:i), trim(pattern))) then
        output = text(i+1:)
        return
      end if
    end do
    output = text
  end function

  ! Remove shortest match from end
  function remove_suffix_shortest(text, pattern) result(output)
    character(len=*), intent(in) :: text, pattern
    character(len=:), allocatable :: output
    integer :: i, text_len

    text_len = len_trim(text)
    ! Try matching from shortest to longest
    do i = text_len, 1, -1
      if (shell_pattern_match(text(i:text_len), trim(pattern))) then
        output = text(1:i-1)
        return
      end if
    end do
    output = text
  end function

  ! Remove longest match from end
  function remove_suffix_longest(text, pattern) result(output)
    character(len=*), intent(in) :: text, pattern
    character(len=:), allocatable :: output
    integer :: i, text_len

    text_len = len_trim(text)
    ! Try matching from longest to shortest
    do i = 1, text_len
      if (shell_pattern_match(text(i:text_len), trim(pattern))) then
        output = text(1:i-1)
        return
      end if
    end do
    output = text
  end function

  ! Replace first occurrence of pattern
  function replace_first(text, pattern, replacement) result(output)
    character(len=*), intent(in) :: text, pattern, replacement
    character(len=:), allocatable :: output
    integer :: pos

    ! Simple literal search for now (not pattern matching)
    pos = index(text, trim(pattern))
    if (pos > 0) then
      output = text(:pos-1) // trim(replacement) // text(pos+len_trim(pattern):)
    else
      output = text
    end if
  end function

  ! Replace all occurrences of pattern
  function replace_all(text, pattern, replacement) result(output)
    character(len=*), intent(in) :: text, pattern, replacement
    character(len=:), allocatable :: output
    character(len=:), allocatable :: temp
    integer :: pos

    output = text
    do
      pos = index(output, trim(pattern))
      if (pos == 0) exit
      temp = output(:pos-1) // trim(replacement) // output(pos+len_trim(pattern):)
      output = temp
    end do
  end function

  ! Convert to uppercase
  function to_uppercase(text) result(output)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: output
    integer :: i, char_code

    allocate(character(len=len_trim(text)) :: output)
    do i = 1, len_trim(text)
      char_code = iachar(text(i:i))
      if (char_code >= iachar('a') .and. char_code <= iachar('z')) then
        output(i:i) = achar(char_code - 32)
      else
        output(i:i) = text(i:i)
      end if
    end do
  end function

  ! Convert to lowercase
  function to_lowercase(text) result(output)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: output
    integer :: i, char_code

    allocate(character(len=len_trim(text)) :: output)
    do i = 1, len_trim(text)
      char_code = iachar(text(i:i))
      if (char_code >= iachar('A') .and. char_code <= iachar('Z')) then
        output(i:i) = achar(char_code + 32)
      else
        output(i:i) = text(i:i)
      end if
    end do
  end function

  subroutine process_parameter_expansion(param_expr, result_value, shell)
    use variables, only: get_array_element, get_array_all_elements, get_array_size, &
                         is_associative_array, get_assoc_array_value, get_assoc_array_keys
    character(len=*), intent(in) :: param_expr
    character(len=:), allocatable, intent(out) :: result_value
    type(shell_state_t), intent(inout) :: shell

    character(len=MAX_TOKEN_LEN) :: var_name, default_value, operation, index_str
    character(len=1024) :: assoc_value, keys(100)
    character(len=256) :: offset_str, length_str_temp
    integer :: op_pos, op_len, bracket_pos, bracket_end, array_index, array_sz
    integer :: num_keys, key_idx
    integer :: colon_pos, offset, str_length, second_colon, iostat_val, char_code
    character(len=:), allocatable :: current_value
    character(len=20) :: length_str
    logical :: is_array_access, get_keys, get_all, is_length

    ! Initialize result
    result_value = ''

    ! Check for keys expansion ${!arr[@]}
    get_keys = .false.
    is_length = .false.
    var_name = param_expr

    if (param_expr(1:1) == '!') then
      get_keys = .true.
      var_name = param_expr(2:)
    else if (param_expr(1:1) == '#') then
      is_length = .true.
      var_name = param_expr(2:)
    end if

    ! Check for array syntax: var[index] or var[@] or var[*]
    bracket_pos = index(var_name, '[')
    is_array_access = (bracket_pos > 0)

    if (is_array_access) then
      bracket_end = index(var_name(bracket_pos:), ']')
      if (bracket_end > 0) then
        bracket_end = bracket_pos + bracket_end - 1
        index_str = var_name(bracket_pos+1:bracket_end-1)
        var_name = var_name(:bracket_pos-1)

        ! Check for special indices
        if (trim(index_str) == '@' .or. trim(index_str) == '*') then
          get_all = .true.

          if (is_length) then
            ! ${#arr[@]} - return array length
            array_sz = get_array_size(shell, trim(var_name))
            write(length_str, '(i0)') array_sz
            result_value = trim(length_str)
            return
          else if (get_keys) then
            ! ${!arr[@]} - return indices (for indexed) or keys (for associative)
            if (is_associative_array(shell, trim(var_name))) then
              ! Return keys for associative array
              call get_assoc_array_keys(shell, trim(var_name), keys, num_keys)
              if (num_keys == 0) then
                result_value = ''
              else
                result_value = ''
                do key_idx = 1, num_keys
                  if (key_idx > 1) result_value = result_value // ' '
                  result_value = result_value // trim(keys(key_idx))
                end do
              end if
              return
            else
              ! Return indices for indexed array
              array_sz = get_array_size(shell, trim(var_name))
              if (array_sz == 0) then
                result_value = ''
                return
              end if
              ! Build indices with proper spacing
              do array_index = 1, array_sz
                if (array_index > 1) result_value = result_value // ' '
                write(length_str, '(i0)') array_index - 1  ! 0-indexed
                result_value = result_value // trim(length_str)
              end do
              return
            end if
          else
            ! ${arr[@]} or ${map[@]} - return all elements/values
            if (is_associative_array(shell, trim(var_name))) then
              ! Return all values for associative array
              call get_assoc_array_keys(shell, trim(var_name), keys, num_keys)
              result_value = ''
              do key_idx = 1, num_keys
                if (key_idx > 1) result_value = result_value // ' '
                assoc_value = get_assoc_array_value(shell, trim(var_name), trim(keys(key_idx)))
                result_value = result_value // trim(assoc_value)
              end do
              return
            else
              ! Return all elements for indexed array
              result_value = trim(get_array_all_elements(shell, trim(var_name)))
              return
            end if
          end if
        else
          ! Check if this is an associative array
          if (is_associative_array(shell, trim(var_name))) then
            ! Associative array access: ${map[key]}
            assoc_value = get_assoc_array_value(shell, trim(var_name), trim(index_str))
            result_value = trim(assoc_value)
            return
          else
            ! Try numeric index: ${arr[0]}
            read(index_str, *, iostat=op_pos) array_index
            if (op_pos == 0) then
              ! Convert from 0-indexed to 1-indexed
              array_index = array_index + 1
              result_value = trim(get_array_element(shell, trim(var_name), array_index))
              return
            else
              ! Non-numeric index for non-associative - might be string key, treat as assoc
              assoc_value = get_assoc_array_value(shell, trim(var_name), trim(index_str))
              result_value = trim(assoc_value)
              return
            end if
          end if
        end if
      end if
    end if

    ! Not array access - fall back to original length logic
    if (is_length) then
      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if
      if (allocated(current_value)) then
        write(length_str, '(i0)') len_trim(current_value)
        result_value = trim(length_str)
      else
        result_value = '0'
      end if
      return
    end if
    
    ! Check for substring extraction ${var:offset:length}
    colon_pos = index(param_expr, ':')
    if (colon_pos > 1) then
      ! Check if this is substring (: followed by digit or -)
      if (colon_pos < len_trim(param_expr)) then
        if (param_expr(colon_pos+1:colon_pos+1) >= '0' .and. param_expr(colon_pos+1:colon_pos+1) <= '9' &
            .or. param_expr(colon_pos+1:colon_pos+1) == '-' .or. param_expr(colon_pos+1:colon_pos+1) == ' ') then
          ! This is substring extraction
          var_name = param_expr(:colon_pos-1)
          current_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(current_value) == 0) then
            current_value = get_environment_var(trim(var_name))
          end if

          ! Parse offset
          second_colon = index(param_expr(colon_pos+1:), ':')
          if (second_colon > 0) then
            second_colon = colon_pos + second_colon
            offset_str = param_expr(colon_pos+1:second_colon-1)
            length_str_temp = param_expr(second_colon+1:)
          else
            offset_str = param_expr(colon_pos+1:)
            length_str_temp = ''
          end if

          ! Convert offset to integer
          read(offset_str, *, iostat=iostat_val) offset
          if (iostat_val == 0) then
            ! Fortran uses 1-based indexing, bash uses 0-based
            offset = offset + 1
            if (offset < 1) offset = 1

            if (len_trim(length_str_temp) > 0) then
              read(length_str_temp, *, iostat=iostat_val) str_length
              if (iostat_val /= 0) str_length = len_trim(current_value)
            else
              str_length = len_trim(current_value) - offset + 1
            end if

            if (offset <= len_trim(current_value)) then
              if (offset + str_length - 1 > len_trim(current_value)) then
                str_length = len_trim(current_value) - offset + 1
              end if
              result_value = current_value(offset:offset+str_length-1)
            else
              result_value = ''
            end if
            return
          end if
        end if
      end if
    end if

    ! Check for pattern removal and replacement operations
    ! Must check before default value operators since # and % have special meaning

    ! Pattern removal from beginning: ${var#pattern} or ${var##pattern}
    if (index(param_expr, '##') > 0) then
      op_pos = index(param_expr, '##')
      var_name = param_expr(:op_pos-1)
      operation = param_expr(op_pos:op_pos+1)
      default_value = param_expr(op_pos+2:)

      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = remove_prefix_longest(current_value, trim(default_value))
      else
        result_value = ''
      end if
      return
    else if (index(param_expr, '#') > 0) then
      op_pos = index(param_expr, '#')
      ! Make sure it's not the # for length (which would be at position 1)
      if (op_pos > 1) then
        var_name = param_expr(:op_pos-1)
        operation = param_expr(op_pos:op_pos)
        default_value = param_expr(op_pos+1:)

        current_value = get_shell_variable(shell, trim(var_name))
        if (len_trim(current_value) == 0) then
          current_value = get_environment_var(trim(var_name))
        end if

        if (allocated(current_value)) then
          result_value = remove_prefix_shortest(current_value, trim(default_value))
        else
          result_value = ''
        end if
        return
      end if
    end if

    ! Pattern removal from end: ${var%pattern} or ${var%%pattern}
    if (index(param_expr, '%%') > 0) then
      op_pos = index(param_expr, '%%')
      var_name = param_expr(:op_pos-1)
      operation = param_expr(op_pos:op_pos+1)
      default_value = param_expr(op_pos+2:)

      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = remove_suffix_longest(current_value, trim(default_value))
      else
        result_value = ''
      end if
      return
    else if (index(param_expr, '%') > 0) then
      op_pos = index(param_expr, '%')
      var_name = param_expr(:op_pos-1)
      operation = param_expr(op_pos:op_pos)
      default_value = param_expr(op_pos+1:)

      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = remove_suffix_shortest(current_value, trim(default_value))
      else
        result_value = ''
      end if
      return
    end if

    ! Pattern replacement: ${var/pattern/replacement} or ${var//pattern/replacement}
    if (index(param_expr, '//') > 0) then
      op_pos = index(param_expr, '//')
      var_name = param_expr(:op_pos-1)
      ! Find the replacement (after the second /)
      if (index(param_expr(op_pos+2:), '/') > 0) then
        colon_pos = index(param_expr(op_pos+2:), '/')
        default_value = param_expr(op_pos+2:op_pos+1+colon_pos-1)  ! pattern
        operation = param_expr(op_pos+2+colon_pos:)  ! replacement
      else
        default_value = param_expr(op_pos+2:)  ! pattern
        operation = ''  ! replacement (empty = delete)
      end if

      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = replace_all(current_value, trim(default_value), trim(operation))
      else
        result_value = ''
      end if
      return
    else if (index(param_expr, '/') > 0) then
      op_pos = index(param_expr, '/')
      var_name = param_expr(:op_pos-1)
      ! Find the replacement (after the second /)
      if (index(param_expr(op_pos+1:), '/') > 0) then
        colon_pos = index(param_expr(op_pos+1:), '/')
        default_value = param_expr(op_pos+1:op_pos+colon_pos-1)  ! pattern
        operation = param_expr(op_pos+1+colon_pos:)  ! replacement
      else
        default_value = param_expr(op_pos+1:)  ! pattern
        operation = ''  ! replacement (empty = delete)
      end if

      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = replace_first(current_value, trim(default_value), trim(operation))
      else
        result_value = ''
      end if
      return
    end if

    ! Case modification
    if (index(param_expr, '^^') > 0) then
      ! All uppercase
      op_pos = index(param_expr, '^^')
      var_name = param_expr(:op_pos-1)
      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = to_uppercase(current_value)
      else
        result_value = ''
      end if
      return
    else if (index(param_expr, '^') > 0) then
      ! First char uppercase
      op_pos = index(param_expr, '^')
      var_name = param_expr(:op_pos-1)
      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value) .and. len_trim(current_value) > 0) then
        char_code = iachar(current_value(1:1))
        if (char_code >= iachar('a') .and. char_code <= iachar('z')) then
          result_value = achar(char_code - 32) // current_value(2:)
        else
          result_value = current_value
        end if
      else
        result_value = ''
      end if
      return
    else if (index(param_expr, ',,') > 0) then
      ! All lowercase
      op_pos = index(param_expr, ',,')
      var_name = param_expr(:op_pos-1)
      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value)) then
        result_value = to_lowercase(current_value)
      else
        result_value = ''
      end if
      return
    else if (index(param_expr, ',') > 0) then
      ! First char lowercase
      op_pos = index(param_expr, ',')
      var_name = param_expr(:op_pos-1)
      current_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(current_value) == 0) then
        current_value = get_environment_var(trim(var_name))
      end if

      if (allocated(current_value) .and. len_trim(current_value) > 0) then
        char_code = iachar(current_value(1:1))
        if (char_code >= iachar('A') .and. char_code <= iachar('Z')) then
          result_value = achar(char_code + 32) // current_value(2:)
        else
          result_value = current_value
        end if
      else
        result_value = ''
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