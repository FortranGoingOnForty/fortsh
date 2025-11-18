! ==============================================================================
! Module: parser
! Purpose: Command line parsing and tokenization
! ==============================================================================
module parser
  use shell_types
  use system_interface
  use variables  ! includes check_nounset
  use glob
  use error_handling
  use performance
  use iso_fortran_env, only: error_unit, input_unit
  implicit none

  ! Export backtick conversion for new parser
  public :: convert_backticks_to_dollar_paren

contains

  subroutine parse_pipeline(input, pipeline)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline

    character(len=len(input)) :: working_input, proc_subst_input
    integer :: pos, start, cmd_count
    integer :: i, comment_pos, newline_pos
    type(command_t), allocatable :: temp_commands(:)
    logical :: background, in_quotes, in_param_expansion, in_for_arith, after_case_in
    character(len=1) :: quote_char
    integer :: paren_depth, brace_depth, case_depth

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
          ! Found comment - remove from # to end of line (but keep newline and rest)
          ! Find the next newline
          newline_pos = index(working_input(i:), char(10))
          if (newline_pos > 0) then
            ! There's a newline - remove comment but keep newline and everything after
            working_input = working_input(:i-1) // working_input(i+newline_pos-1:)
          else
            ! No newline - truncate to end
            working_input = working_input(:i-1)
          end if
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

    ! Convert backticks to $() format BEFORE tokenization
    ! This ensures complete backtick expressions are converted together
    working_input = convert_backticks_to_dollar_paren(working_input)

    ! Parse commands and separators (track quotes to avoid splitting inside them)
    i = 1
    in_quotes = .false.
    quote_char = ' '
    in_for_arith = .false.
    paren_depth = 0
    brace_depth = 0
    case_depth = 0
    after_case_in = .false.
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

        ! Track parentheses depth (for subshells and for ((..)))
        ! Skip tracking for $( which is command substitution
        if (working_input(i:i) == '(') then
          ! Check if this is $( command substitution - if so, skip tracking
          if (i == 1 .or. working_input(i-1:i-1) /= '$') then
            paren_depth = paren_depth + 1
          end if
        else if (working_input(i:i) == ')') then
          if (paren_depth > 0) then
            paren_depth = paren_depth - 1
            ! Exit for (( when we've closed all parens
            if (in_for_arith .and. paren_depth == 0) then
              in_for_arith = .false.
            end if
          end if
        end if

        ! Track brace depth for function definitions
        if (working_input(i:i) == '{') then
          brace_depth = brace_depth + 1
        else if (working_input(i:i) == '}') then
          brace_depth = brace_depth - 1
        end if

        ! Track case statement depth (case...esac)
        ! Check for 'case' keyword at word boundary
        if (i <= len_trim(working_input) - 3) then
          if (working_input(i:i+3) == 'case') then
            ! Verify it's a word boundary (space or start of command before it)
            if (i == 1 .or. working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';') then
              ! Verify word boundary after (space or special char)
              if (i+4 > len_trim(working_input) .or. working_input(i+4:i+4) == ' ' .or. &
                  working_input(i+4:i+4) == ';') then
                case_depth = case_depth + 1
                after_case_in = .false.  ! Reset when we see 'case'
              end if
            end if
          end if
        end if

        ! Check for ' in ' keyword inside case statement (split after it)
        if (case_depth > 0 .and. .not. after_case_in) then
          if (i <= len_trim(working_input) - 2) then
            if (working_input(i:i+1) == 'in') then
              ! Verify word boundary before (space)
              if (i > 1 .and. working_input(i-1:i-1) == ' ') then
                ! Verify word boundary after (space or end)
                if (i+2 > len_trim(working_input) .or. working_input(i+2:i+2) == ' ') then
                  ! Split after ' in '
                  ! Find the end of 'in' plus any trailing space
                  if (i+2 <= len_trim(working_input) .and. working_input(i+2:i+2) == ' ') then
                    cmd_count = cmd_count + 1
                    if (cmd_count <= MAX_PIPELINE) then
                      call parse_single_command(working_input(start:i+1), temp_commands(cmd_count))
                      temp_commands(cmd_count)%separator = SEP_SEMICOLON
                    end if
                    start = i + 3  ! Skip 'in '
                    after_case_in = .true.
                  else
                    cmd_count = cmd_count + 1
                    if (cmd_count <= MAX_PIPELINE) then
                      call parse_single_command(working_input(start:i+1), temp_commands(cmd_count))
                      temp_commands(cmd_count)%separator = SEP_SEMICOLON
                    end if
                    start = i + 2  ! Skip 'in'
                    after_case_in = .true.
                  end if
                  i = start - 1  ! Will be incremented at end of loop
                  cycle
                end if
              end if
            end if
          end if
        end if

        ! Check for 'esac' keyword at word boundary
        if (i <= len_trim(working_input) - 3) then
          if (working_input(i:i+3) == 'esac') then
            ! Verify it's a word boundary (space or start before it)
            if (i == 1 .or. working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';') then
              ! Verify word boundary after (space, semicolon, or end)
              if (i+4 > len_trim(working_input) .or. working_input(i+4:i+4) == ' ' .or. &
                  working_input(i+4:i+4) == ';') then
                case_depth = case_depth - 1
                if (case_depth < 0) case_depth = 0  ! Prevent negative
                after_case_in = .false.  ! Reset after esac
              end if
            end if
          end if
        end if

        ! Check for operators (but skip if inside parentheses/subshell)
        if (i <= len_trim(working_input) - 1 .and. paren_depth == 0) then
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
            (i == 1 .or. working_input(i-1:i-1) /= '>') .and. &
            (i == len_trim(working_input) .or. working_input(i+1:i+1) /= '|')) then
          ! Don't split on | if we're in a case pattern (after 'case...in') or inside parentheses (subshell)
          if (.not. after_case_in .and. paren_depth == 0) then
            cmd_count = cmd_count + 1
            if (cmd_count <= MAX_PIPELINE) then
              call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
              temp_commands(cmd_count)%separator = SEP_PIPE
            end if
            start = i + 1
          end if
        else if (working_input(i:i) == '&') then
          ! Check it's not part of && (which is already handled above)
          ! Also check it's not part of >& or <& (FD redirection)
          if ((i == 1 .or. (working_input(i-1:i-1) /= '&' .and. &
                           working_input(i-1:i-1) /= '>' .and. &
                           working_input(i-1:i-1) /= '<')) .and. &
              (i == len_trim(working_input) .or. working_input(i+1:i+1) /= '&')) then
            ! Single & - mark current command as background and split
            cmd_count = cmd_count + 1
            if (cmd_count <= MAX_PIPELINE) then
              call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
              temp_commands(cmd_count)%separator = SEP_SEMICOLON  ! Execute like semicolon
              temp_commands(cmd_count)%background = .true.  ! But run in background
            end if
            start = i + 1
          end if
        else if (working_input(i:i) == ';') then
          ! Check for ;; (double semicolon) which is used in case statements
          if (i < len_trim(working_input) .and. working_input(i+1:i+1) == ';') then
            ! This is ;; - only valid inside case statements
            if (case_depth == 0) then
              ! Syntax error: ;; outside case statement
              call parser_error(102, 'Syntax error: ";;" is only valid in case statements', 'parse_pipeline')
              pipeline%num_commands = 0
              pipeline%parse_error = .true.
              return
            end if
            cmd_count = cmd_count + 1
            if (cmd_count <= MAX_PIPELINE) then
              call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
              temp_commands(cmd_count)%separator = SEP_SEMICOLON
            end if
            start = i + 2  ! Skip both semicolons
            i = i + 1  ! Will be incremented again at end of loop
            after_case_in = .false.  ! Reset after ;;, ready for next pattern
          ! Only split on single semicolon if not inside for (( ... )), function braces, subshells, or case statement
          else if (in_for_arith .or. brace_depth > 0 .or. paren_depth > 0 .or. case_depth > 0) then
            ! Skip - we're inside for (( ... )), function { ... }, subshell ( ... ), or case...esac
          else
            ! Check if semicolon is at the start (syntax error)
            if (i == start) then
              call parser_error(103, 'Syntax error: unexpected ";"', 'parse_pipeline')
              pipeline%num_commands = 0
              pipeline%parse_error = .true.
              return
            end if
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
        pipeline%commands(i)%force_clobber = temp_commands(i)%force_clobber
        pipeline%commands(i)%redirect_stderr_to_stdout = temp_commands(i)%redirect_stderr_to_stdout
        pipeline%commands(i)%redirect_stdout_to_stderr = temp_commands(i)%redirect_stdout_to_stderr
        pipeline%commands(i)%redirect_both_to_file = temp_commands(i)%redirect_both_to_file
        pipeline%commands(i)%background = temp_commands(i)%background
        pipeline%commands(i)%separator = temp_commands(i)%separator
        pipeline%commands(i)%is_command_group = temp_commands(i)%is_command_group
        pipeline%commands(i)%is_subshell = temp_commands(i)%is_subshell

        ! Copy redirection array
        pipeline%commands(i)%num_redirections = temp_commands(i)%num_redirections
        pipeline%commands(i)%redirections = temp_commands(i)%redirections

        ! Copy prefix assignments (VAR=value command)
        pipeline%commands(i)%num_prefix_assignments = temp_commands(i)%num_prefix_assignments
        pipeline%commands(i)%prefix_assignments = temp_commands(i)%prefix_assignments

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
        ! Copy heredoc quoted flag
        pipeline%commands(i)%heredoc_quoted = temp_commands(i)%heredoc_quoted

        if (allocated(temp_commands(i)%here_string)) then
          pipeline%commands(i)%here_string = temp_commands(i)%here_string
        end if
        if (allocated(temp_commands(i)%group_content)) then
          pipeline%commands(i)%group_content = temp_commands(i)%group_content
        end if
        if (allocated(temp_commands(i)%subshell_content)) then
          pipeline%commands(i)%subshell_content = temp_commands(i)%subshell_content
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
    integer :: pos, end_pos, source_fd
    character(len=MAX_TOKEN_LEN) :: temp_str


    working_input = adjustl(input)
    ! write(error_unit, '(a,a)') 'DEBUG parse_single_command input: ', trim(working_input)

    ! Handle subshell grouping ( ... )
    ! Check if input starts with ( and ends with )
    if (len_trim(working_input) >= 3) then
      if (working_input(1:1) == '(') then
        ! Find the position of the closing )
        pos = len_trim(working_input)
        if (working_input(pos:pos) == ')') then
          ! This is a subshell - mark it and store the inner content
          cmd%is_subshell = .true.
          cmd%subshell_content = adjustl(working_input(2:pos-1))
          ! Don't tokenize the content - it will be re-parsed during execution
          cmd%num_tokens = 0
          return
        end if
      end if
    end if

    ! Handle command grouping { ... }
    ! Check if input starts with { and ends with }
    if (len_trim(working_input) >= 3) then
      if (working_input(1:1) == '{') then
        ! Find the position of the closing }
        pos = len_trim(working_input)
        if (working_input(pos:pos) == '}') then
          ! This is a command group - mark it and store the inner content
          cmd%is_command_group = .true.
          cmd%group_content = adjustl(working_input(2:pos-1))
          ! Don't tokenize the content - it will be re-parsed during execution
          cmd%num_tokens = 0
          return
        end if
      end if
    end if

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
    pos = find_outside_quotes(working_input, '<<<')
    if (pos > 0) then
      call extract_filename(working_input(pos+3:), temp_str)
      cmd%here_string = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for here document (<<)
      pos = find_outside_quotes(working_input, '<<')
      if (pos > 0) then
        call extract_word(working_input(pos+2:), temp_str)
        ! Strip quotes from delimiter if present and track if it was quoted
        cmd%heredoc_delimiter = trim(temp_str)
        cmd%heredoc_quoted = strip_heredoc_delimiter_quotes(cmd%heredoc_delimiter)
        ! Try to extract heredoc content from input if it contains newlines
        call extract_heredoc_from_input(input, trim(cmd%heredoc_delimiter), cmd%heredoc_content)
        working_input = working_input(:pos-1)
      end if
    end if
    
    ! Check for specific 2>&1 redirection (stderr to stdout) - keep this as it's common
    ! and is best handled specially
    pos = find_outside_quotes(working_input, '2>&1')
    if (pos > 0) then
      cmd%redirect_stderr_to_stdout = .true.
      working_input = working_input(:pos-1) // ' ' // working_input(pos+4:)
    end if

    ! Note: >&2, 1>&2, and other FD redirections are now handled by the general
    ! FD duplication code below

    ! Check for variable FD redirections >&${var} and <&${var}
    pos = find_outside_quotes(working_input, '>&$')
    if (pos > 0 .and. pos + 3 <= len_trim(working_input)) then
      if (working_input(pos+3:pos+3) == '{') then
        ! Found >&${...} pattern
        end_pos = index(working_input(pos+4:), '}')
        if (end_pos > 0) then
          end_pos = pos + 3 + end_pos  ! Adjust for full string position
          ! Store variable expression and add redirection
          if (cmd%num_redirections < 10) then
            cmd%num_redirections = cmd%num_redirections + 1
            cmd%redirections(cmd%num_redirections)%type = REDIR_DUP_OUT
            cmd%redirections(cmd%num_redirections)%fd = 1  ! Default stdout
            cmd%redirections(cmd%num_redirections)%target_fd = -1  ! Will be resolved at runtime
            cmd%redirections(cmd%num_redirections)%target_fd_expr = working_input(pos+2:end_pos)  ! Include ${...}
            ! Remove from working input
            working_input = working_input(:pos-1) // ' ' // working_input(end_pos+1:)
          end if
        end if
      end if
    end if

    pos = find_outside_quotes(working_input, '<&$')
    if (pos > 0 .and. pos + 3 <= len_trim(working_input)) then
      if (working_input(pos+3:pos+3) == '{') then
        ! Found <&${...} pattern
        end_pos = index(working_input(pos+4:), '}')
        if (end_pos > 0) then
          end_pos = pos + 3 + end_pos  ! Adjust for full string position
          ! Store variable expression and add redirection
          if (cmd%num_redirections < 10) then
            cmd%num_redirections = cmd%num_redirections + 1
            cmd%redirections(cmd%num_redirections)%type = REDIR_DUP_IN
            cmd%redirections(cmd%num_redirections)%fd = 0  ! Default stdin
            cmd%redirections(cmd%num_redirections)%target_fd = -1  ! Will be resolved at runtime
            cmd%redirections(cmd%num_redirections)%target_fd_expr = working_input(pos+2:end_pos)  ! Include ${...}
            ! Remove from working input
            working_input = working_input(:pos-1) // ' ' // working_input(end_pos+1:)
          end if
        end if
      end if
    end if

    ! Check for general FD duplication >&n FIRST (must come before file redirections)
    ! Use find_outside_quotes and iterate to find all patterns
    pos = find_outside_quotes(working_input, '>&')
    do while (pos > 0)
      ! Debug output
      ! write(error_unit, '(a,i15,a,a)') 'DEBUG: Found >& at pos ', pos, ' in: ', trim(working_input)

      ! Check what follows >&
      if (pos+2 <= len_trim(working_input)) then
        ! write(error_unit, '(a,a)') 'DEBUG: Character after >& is: ', working_input(pos+2:pos+2)

        if (working_input(pos+2:pos+2) >= '0' .and. working_input(pos+2:pos+2) <= '9') then
          ! Found >&n pattern - literal FD duplication
          read(working_input(pos+2:pos+2), *) end_pos
          ! write(error_unit, '(a,i15)') 'DEBUG: Processing >&n where n=', end_pos

          ! Check if there's a source FD before >&
          source_fd = 1  ! Default to stdout
          if (pos > 1 .and. working_input(pos-1:pos-1) >= '0' .and. working_input(pos-1:pos-1) <= '9') then
            read(working_input(pos-1:pos-1), *) source_fd
            ! write(error_unit, '(a,i15,a,i15)') 'DEBUG: Found source FD=', source_fd, ' redirecting to target FD=', end_pos
          end if

          if (cmd%num_redirections < 10) then
            cmd%num_redirections = cmd%num_redirections + 1
            cmd%redirections(cmd%num_redirections)%type = REDIR_DUP_OUT
            cmd%redirections(cmd%num_redirections)%fd = source_fd
            cmd%redirections(cmd%num_redirections)%target_fd = end_pos
          end if
          ! Remove from working input - also remove source FD if present
          if (pos > 1 .and. working_input(pos-1:pos-1) >= '0' .and. working_input(pos-1:pos-1) <= '9') then
            working_input = working_input(:pos-2) // ' ' // working_input(pos+3:)
          else
            working_input = working_input(:pos-1) // ' ' // working_input(pos+3:)
          end if
          ! write(error_unit, '(a,a)') 'DEBUG: After removal: ', trim(working_input)
          ! Search again from beginning since we modified the string
          pos = find_outside_quotes(working_input, '>&')
        else
          ! Not a digit after >&, skip this occurrence and find next
          ! write(error_unit, '(a)') 'DEBUG: Not a digit after >&, exiting FD dup handler'
          ! For now, just exit - we'll let the general > handler deal with it
          exit
        end if
      else
        ! write(error_unit, '(a)') 'DEBUG: No character after >&, exiting'
        exit
      end if
    end do

    ! if (pos == 0) then
    !   write(error_unit, '(a)') 'DEBUG: No >& patterns found'
    ! end if

    ! Check for <&n patterns
    pos = find_outside_quotes(working_input, '<&')
    do while (pos > 0)
      ! Check what follows <&
      if (pos+2 <= len_trim(working_input)) then
        if (working_input(pos+2:pos+2) >= '0' .and. working_input(pos+2:pos+2) <= '9') then
          ! Found <&n pattern - literal FD duplication
          read(working_input(pos+2:pos+2), *) end_pos
          if (cmd%num_redirections < 10) then
            cmd%num_redirections = cmd%num_redirections + 1
            cmd%redirections(cmd%num_redirections)%type = REDIR_DUP_IN
            cmd%redirections(cmd%num_redirections)%fd = 0  ! Default stdin
            cmd%redirections(cmd%num_redirections)%target_fd = end_pos
          end if
          ! Remove from working input
          working_input = working_input(:pos-1) // ' ' // working_input(pos+3:)
          ! Search again from beginning since we modified the string
          pos = find_outside_quotes(working_input, '<&')
        else
          ! Not a digit after <&, skip this occurrence and find next
          ! For now, just exit - we'll let other handlers deal with it
          exit
        end if
      else
        exit
      end if
    end do

    ! Now continue with other redirections
    if (.not. (cmd%redirect_stderr_to_stdout)) then
      ! Check for &>file or &>>file (both stdout and stderr to file)
      pos = find_outside_quotes(working_input, '&>>')
      if (pos > 0) then
        cmd%redirect_both_to_file = .true.
        cmd%append_output = .true.
        cmd%append_error = .true.
        call extract_filename(working_input(pos+3:), temp_str)
        cmd%output_file = trim(temp_str)
        cmd%error_file = trim(temp_str)
        working_input = working_input(:pos-1)
      else
        pos = find_outside_quotes(working_input, '&>')
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
    pos = find_outside_quotes(working_input, '2>>')
    if (pos > 0) then
      cmd%append_error = .true.
      call extract_filename(working_input(pos+3:), temp_str)
      cmd%error_file = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for error redirection (2>)
      pos = find_outside_quotes(working_input, '2>')
      if (pos > 0) then
        cmd%append_error = .false.
        call extract_filename(working_input(pos+2:), temp_str)
        cmd%error_file = trim(temp_str)
        working_input = working_input(:pos-1)
      end if
    end if

    ! Check for force clobber FIRST (>|) before append (>>)
    ! This prevents ">|" from matching ">>"
    pos = find_outside_quotes(working_input, '>|')
    if (pos > 0) then
      cmd%append_output = .false.
      cmd%force_clobber = .true.
      call extract_filename(working_input(pos+2:), temp_str)
      cmd%output_file = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for output redirection (>>)
      pos = find_outside_quotes(working_input, '>>')
      if (pos > 0) then
        cmd%append_output = .true.
        call extract_filename(working_input(pos+2:), temp_str)
        cmd%output_file = trim(temp_str)
        working_input = working_input(:pos-1)
      else
        ! Check for output redirection (>)
        pos = find_outside_quotes(working_input, '>')
        if (pos > 0) then
          cmd%append_output = .false.
          call extract_filename(working_input(pos+1:), temp_str)
          cmd%output_file = trim(temp_str)
          working_input = working_input(:pos-1)
        end if
      end if
    end if

    ! Check for input redirection (<)
    pos = find_outside_quotes(working_input, '<')
    if (pos > 0) then
      call extract_filename(working_input(pos+1:), temp_str)
      cmd%input_file = trim(temp_str)
      working_input = working_input(:pos-1)
    end if
    
    ! Tokenize the remaining command
    call tokenize_with_substitution(trim(working_input), cmd%tokens, cmd%num_tokens)

    ! Extract prefix assignments (VAR=value command)
    call extract_prefix_assignments(cmd)

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
      if (word(i:i) == ' ' .or. word(i:i) == char(9) .or. word(i:i) == char(10) .or. &
          word(i:i) == '<' .or. word(i:i) == '>' .or. &
          word(i:i) == '|' .or. word(i:i) == '&' .or. &
          word(i:i) == ';') then
        word = word(:i-1)
        exit
      end if
    end do
  end subroutine

  ! Strip quotes from heredoc delimiter ('EOF' -> EOF, "EOF" -> EOF)
  ! Returns .true. if quotes were found and removed
  function strip_heredoc_delimiter_quotes(delimiter) result(was_quoted)
    character(len=*), intent(inout) :: delimiter
    logical :: was_quoted
    integer :: len_delim
    character(len=1) :: first_char, last_char

    was_quoted = .false.
    len_delim = len_trim(delimiter)
    if (len_delim < 2) return

    first_char = delimiter(1:1)
    last_char = delimiter(len_delim:len_delim)

    ! Check if surrounded by matching quotes
    if ((first_char == "'" .and. last_char == "'") .or. &
        (first_char == '"' .and. last_char == '"')) then
      ! Remove surrounding quotes
      delimiter = delimiter(2:len_delim-1)
      was_quoted = .true.
    end if
  end function

  ! Find position of character outside quotes
  function find_outside_quotes(str, char) result(pos)
    character(len=*), intent(in) :: str, char
    integer :: pos
    integer :: i
    logical :: in_quotes, in_arith
    character(len=1) :: quote_char
    integer :: arith_depth

    pos = 0
    in_quotes = .false.
    in_arith = .false.
    quote_char = ' '
    arith_depth = 0

    do i = 1, len_trim(str)
      ! Check for arithmetic expansion start: $((
      if (.not. in_quotes .and. i <= len_trim(str) - 2) then
        if (str(i:i+2) == '$((') then
          in_arith = .true.
          arith_depth = arith_depth + 2
          cycle
        end if
      end if

      ! Track parentheses inside arithmetic expressions
      if (in_arith .and. .not. in_quotes) then
        if (str(i:i) == '(') then
          arith_depth = arith_depth + 1
        else if (str(i:i) == ')') then
          arith_depth = arith_depth - 1
          if (arith_depth == 0) then
            in_arith = .false.
          end if
        end if
      end if

      if (.not. in_quotes .and. .not. in_arith) then
        if (str(i:i) == '"' .or. str(i:i) == "'") then
          in_quotes = .true.
          quote_char = str(i:i)
        else if (str(i:min(i+len(char)-1, len_trim(str))) == char) then
          pos = i
          return
        end if
      else if (in_quotes) then
        if (str(i:i) == quote_char) then
          in_quotes = .false.
        end if
      end if
    end do
  end function

  subroutine tokenize_with_substitution(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens

    character(len=len(input)) :: working_copy
    integer :: pos, start, token_count, i, token_len
    character(len=MAX_TOKEN_LEN), allocatable :: temp_tokens(:)
    logical :: in_quotes, in_arith, in_array_literal, in_cmd_subst, escaped
    character :: quote_char
    integer :: arith_depth, array_depth, cmd_depth

    working_copy = adjustl(input)
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
      start = pos  ! Initialize start to beginning of token
      token_count = token_count + 1
      in_quotes = .false.
      in_arith = .false.
      arith_depth = 0
      quote_char = ' '
      in_array_literal = .false.
      array_depth = 0
      in_cmd_subst = .false.
      cmd_depth = 0
      escaped = .false.

      ! Skip to end of token (respecting quotes and arithmetic)
      ! Continue past len_trim when inside quotes to preserve trailing spaces
      do while (pos <= len_trim(working_copy) .or. (in_quotes .and. pos <= len(working_copy)))
        ! Handle backslash escaping outside quotes
        if (.not. in_quotes .and. .not. escaped .and. working_copy(pos:pos) == '\') then
          escaped = .true.
          pos = pos + 1
          cycle
        end if

        ! Check for quotes (unless escaped)
        if (.not. in_arith .and. .not. escaped) then
          if (.not. in_quotes .and. (working_copy(pos:pos) == '"' .or. working_copy(pos:pos) == "'")) then
            in_quotes = .true.
            quote_char = working_copy(pos:pos)
          else if (in_quotes .and. working_copy(pos:pos) == quote_char) then
            in_quotes = .false.
          end if
        end if

        ! Check for $((  )) arithmetic expansion and ((  )) arithmetic command
        if (.not. in_quotes .and. .not. escaped) then
          ! First, check for special patterns that start arithmetic mode
          if (.not. in_arith .and. .not. in_cmd_subst) then
            if (pos <= len_trim(working_copy) - 2 .and. working_copy(pos:pos+2) == '$((') then
              in_arith = .true.
              arith_depth = 2
              pos = pos + 2  ! Skip the $(
            else if (pos <= len_trim(working_copy) - 1 .and. working_copy(pos:pos+1) == '$(') then
              ! $( command substitution - but NOT $((
              in_cmd_subst = .true.
              cmd_depth = 1
              pos = pos + 1  ! Skip the $(
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

          ! Track parentheses depth if in command substitution mode
          if (in_cmd_subst) then
            if (working_copy(pos:pos) == '(') then
              cmd_depth = cmd_depth + 1
            else if (working_copy(pos:pos) == ')') then
              cmd_depth = cmd_depth - 1
              if (cmd_depth == 0) then
                in_cmd_subst = .false.
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

        ! Check for token boundary (space outside quotes/arithmetic/array/command-subst, and not escaped)
        if (.not. in_quotes .and. .not. in_arith .and. .not. in_array_literal .and. &
            .not. in_cmd_subst .and. .not. escaped .and. working_copy(pos:pos) == ' ') exit

        ! Clear escaped flag after processing the escaped character
        if (escaped) escaped = .false.

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
      in_cmd_subst = .false.
      cmd_depth = 0
      escaped = .false.

      ! Find end of token (respecting quotes, arithmetic, and array literals)
      ! Continue past len_trim when inside quotes to preserve trailing spaces
      do while (pos <= len_trim(working_copy) .or. (in_quotes .and. pos <= len(working_copy)))
        ! Handle backslash escaping outside quotes
        if (.not. in_quotes .and. .not. escaped .and. working_copy(pos:pos) == '\') then
          escaped = .true.
          pos = pos + 1
          cycle
        end if

        ! Check for quotes (unless escaped)
        if (.not. in_arith .and. .not. escaped) then
          if (.not. in_quotes .and. (working_copy(pos:pos) == '"' .or. working_copy(pos:pos) == "'")) then
            in_quotes = .true.
            quote_char = working_copy(pos:pos)
          else if (in_quotes .and. working_copy(pos:pos) == quote_char) then
            in_quotes = .false.
          end if
        end if

        ! Check for $((  )) arithmetic expansion and ((  )) arithmetic command
        if (.not. in_quotes .and. .not. escaped) then
          ! First, check for special patterns that start arithmetic mode
          if (.not. in_arith .and. .not. in_cmd_subst) then
            if (pos <= len_trim(working_copy) - 2 .and. working_copy(pos:pos+2) == '$((') then
              in_arith = .true.
              arith_depth = 2
              pos = pos + 2  ! Skip the $(
            else if (pos <= len_trim(working_copy) - 1 .and. working_copy(pos:pos+1) == '$(') then
              ! $( command substitution - but NOT $((
              in_cmd_subst = .true.
              cmd_depth = 1
              pos = pos + 1  ! Skip the $(
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

          ! Track parentheses depth if in command substitution mode
          if (in_cmd_subst) then
            if (working_copy(pos:pos) == '(') then
              cmd_depth = cmd_depth + 1
            else if (working_copy(pos:pos) == ')') then
              cmd_depth = cmd_depth - 1
              if (cmd_depth == 0) then
                in_cmd_subst = .false.
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

        ! Check for token boundary (space outside quotes/arithmetic/array/command-subst, and not escaped)
        if (.not. in_quotes .and. .not. in_arith .and. .not. in_array_literal .and. &
            .not. in_cmd_subst .and. .not. escaped .and. working_copy(pos:pos) == ' ') exit

        ! Clear escaped flag after processing the escaped character
        if (escaped) escaped = .false.

        pos = pos + 1
      end do

      ! Store token (DON'T strip quotes yet - expand_variables needs to see them)
      ! DON'T process backslash escapes yet - glob expansion needs to see them
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

  ! Helper function to strip outer quotes from a token
  function strip_outer_quotes(token) result(stripped)
    character(len=*), intent(in) :: token
    character(len=len(token)) :: stripped
    integer :: token_len

    stripped = token
    token_len = len_trim(token)

    ! Check if token has matching outer quotes
    if (token_len >= 2) then
      ! Check for double quotes
      if (token(1:1) == '"' .and. token(token_len:token_len) == '"') then
        stripped = token(2:token_len-1)
        return
      end if
      ! Check for single quotes
      if (token(1:1) == "'" .and. token(token_len:token_len) == "'") then
        stripped = token(2:token_len-1)
        return
      end if
    end if
  end function

  ! Helper function to strip ALL quotes from a token (for adjacent quotes like "a"b"c")
  function strip_all_quotes(token) result(stripped)
    character(len=*), intent(in) :: token
    character(len=len(token)) :: stripped
    integer :: i, j, token_len
    logical :: in_single_quote, in_double_quote

    stripped = ''
    j = 1
    token_len = len_trim(token)
    in_single_quote = .false.
    in_double_quote = .false.

    do i = 1, token_len
      if (token(i:i) == "'" .and. .not. in_double_quote) then
        ! Toggle single quote mode
        in_single_quote = .not. in_single_quote
        ! Don't include the quote character itself
      else if (token(i:i) == '"' .and. .not. in_single_quote) then
        ! Toggle double quote mode
        in_double_quote = .not. in_double_quote
        ! Don't include the quote character itself
      else
        ! Regular character - include it
        stripped(j:j) = token(i:i)
        j = j + 1
      end if
    end do
  end function

  ! Helper function to process backslash escape sequences outside quotes
  function process_escapes(token) result(processed)
    character(len=*), intent(in) :: token
    character(len=len(token)) :: processed
    integer :: i, j, token_len
    logical :: in_quotes
    character :: quote_char

    processed = ''
    i = 1
    j = 1
    token_len = len_trim(token)
    in_quotes = .false.
    quote_char = ' '

    do while (i <= token_len)
      ! Track quotes
      if (.not. in_quotes .and. (token(i:i) == '"' .or. token(i:i) == "'")) then
        in_quotes = .true.
        quote_char = token(i:i)
        processed(j:j) = token(i:i)
        j = j + 1
        i = i + 1
      else if (in_quotes .and. token(i:i) == quote_char) then
        in_quotes = .false.
        processed(j:j) = token(i:i)
        j = j + 1
        i = i + 1
      else if (.not. in_quotes .and. token(i:i) == '\' .and. i < token_len) then
        ! Backslash escape outside quotes - skip the backslash, keep the next char
        i = i + 1
        processed(j:j) = token(i:i)
        j = j + 1
        i = i + 1
      else
        ! Regular character
        processed(j:j) = token(i:i)
        j = j + 1
        i = i + 1
      end if
    end do
  end function

  subroutine expand_variables(token, expanded, shell, was_quoted_in)
    use expansion, only: expand_braces, arithmetic_expansion_shell
    character(len=*), intent(in) :: token
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(inout) :: shell
    logical, intent(in), optional :: was_quoted_in

    character(len=MAX_TOKEN_LEN) :: result, working_token
    integer :: i, j, var_start, brace_depth, end_pos
    character(len=MAX_TOKEN_LEN) :: var_name
    character(len=:), allocatable :: var_value, brace_expanded
    character(len=20) :: pid_str
    logical :: is_quoted, is_single_quoted

    ! Check if token was originally quoted (from lexer metadata or token inspection)
    is_quoted = .false.
    is_single_quoted = .false.

    ! Use the passed parameter if provided, otherwise fall back to checking the token
    if (present(was_quoted_in)) then
      is_quoted = was_quoted_in
      ! We don't track single vs double quotes in metadata, assume double if quoted
      is_single_quoted = .false.
    else
      ! Legacy: check if token still has quotes (for backward compatibility)
      if (len_trim(token) >= 2) then
        if (token(1:1) == '"' .and. token(len_trim(token):len_trim(token)) == '"') then
          is_quoted = .true.
        else if (token(1:1) == "'" .and. token(len_trim(token):len_trim(token)) == "'") then
          is_quoted = .true.
          is_single_quoted = .true.
        end if
      end if
    end if
    ! Single quotes preserve everything literally - no expansion at all
    if (is_single_quoted) then
      ! Return the token with outer quotes stripped
      expanded = strip_outer_quotes(token)
      return
    end if

    ! For double-quoted tokens that are all whitespace (no special chars),
    ! return a single space to preserve the whitespace argument
    ! This handles cases like " " where len_trim would be 0
    ! We can't determine exact whitespace count, so return at least one space
    if (is_quoted .and. len_trim(token) == 0 .and. len(token) > 0) then
      ! Token is all whitespace - return a single space
      ! (This preserves the argument while avoiding the len_trim=0 issue in exec_child)
      expanded = ' '
      return
    end if

    ! Apply brace expansion ONLY if token is not quoted
    if (.not. is_quoted) then
      brace_expanded = expand_braces(token)
      working_token = brace_expanded
    else
      working_token = token
    end if

    result = ''
    i = 1
    j = 1
    end_pos = len_trim(working_token)

    do while (i <= end_pos)
      ! Check for backslash escape
      ! Handle \$ even outside quotes since lexer may have already removed quotes
      if (working_token(i:i) == '\' .and. i < end_pos) then
        if (working_token(i+1:i+1) == '$') then
          ! \$ -> literal $
          i = i + 1  ! Skip backslash
          result(j:j) = '$'
          i = i + 1
          j = j + 1
          cycle
        else if (is_quoted .and. .not. is_single_quoted) then
          ! In double quotes, backslash also escapes: ` " \ and newline
          if (working_token(i+1:i+1) == '`' .or. &
              working_token(i+1:i+1) == '"' .or. working_token(i+1:i+1) == '\') then
            ! Skip the backslash and add the escaped character
            i = i + 1
            result(j:j) = working_token(i:i)
            i = i + 1
            j = j + 1
            cycle
          end if
        end if
        ! Otherwise, keep the backslash (it's not escaping anything special)
      end if

      if (working_token(i:i) == '~' .and. (i == 1 .or. working_token(i-1:i-1) == ' ')) then
        ! Tilde expansion
        call process_tilde_expansion(working_token, i, result, j, shell)
      else if (working_token(i:i) == '$' .and. i < len_trim(working_token)) then
        i = i + 1
        
        ! Check for special variables
        if (working_token(i:i) == '?') then
          write(pid_str, '(i15)') shell%last_exit_status
          pid_str = adjustl(pid_str)  ! Left-justify to remove leading spaces
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (working_token(i:i) == '$') then
          write(pid_str, '(i15)') c_getpid()
          pid_str = adjustl(pid_str)  ! Left-justify to remove leading spaces
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (working_token(i:i) == '\' .and. i < len_trim(working_token) .and. working_token(i+1:i+1) == '!') then
          ! Handle bash-escaped $\! (bash adds backslash before ! in some contexts)
          i = i + 1  ! Skip the backslash
          write(pid_str, '(i15)') shell%last_bg_pid
          pid_str = adjustl(pid_str)  ! Left-justify to remove leading spaces
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (working_token(i:i) == '!') then
          write(pid_str, '(i15)') shell%last_bg_pid
          pid_str = adjustl(pid_str)  ! Left-justify to remove leading spaces
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (working_token(i:i) == '@') then
          ! $@ - all positional parameters
          var_value = get_shell_variable(shell, '@')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '#') then
          ! $# - number of positional parameters
          var_value = get_shell_variable(shell, '#')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '*') then
          ! $* - all positional parameters as single word
          var_value = get_shell_variable(shell, '*')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '-') then
          ! $- - current shell option flags
          var_value = get_shell_variable(shell, '-')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '_') then
          ! $_ - last argument of previous command
          var_value = get_shell_variable(shell, '_')
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) >= '0' .and. working_token(i:i) <= '9') then
          ! $0, $1, $2, ... - positional parameters
          var_name = working_token(i:i)
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '(') then
          ! Check if it's $(( arithmetic expansion or $( command substitution
          if (i+1 <= len_trim(working_token) .and. working_token(i+1:i+1) == '(') then
            ! $((arithmetic)) expansion
            var_start = i - 1  ! Include the $ character
            i = i + 2  ! Skip both opening parens
            brace_depth = 2

            do while (i <= len_trim(working_token) .and. brace_depth > 0)
              if (working_token(i:i) == '(') then
                brace_depth = brace_depth + 1
              else if (working_token(i:i) == ')') then
                brace_depth = brace_depth - 1
              end if
              i = i + 1
            end do

            ! Extract full $((expr)) including delimiters
            var_name = working_token(var_start:i-1)

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

            do while (i <= len_trim(working_token) .and. brace_depth > 0)
              if (working_token(i:i) == '(') then
                brace_depth = brace_depth + 1
              else if (working_token(i:i) == ')') then
                brace_depth = brace_depth - 1
              end if
              i = i + 1
            end do

            var_name = working_token(var_start:i-2)  ! This is actually the command

            ! Execute command substitution
            call execute_command_substitution(trim(var_name), var_value, shell)
            if (allocated(var_value) .and. len(var_value) > 0) then
              result(j:j+len(var_value)-1) = var_value
              j = j + len(var_value)
            end if
          end if
        else if (working_token(i:i) == '{') then
          ! ${VAR} or ${VAR:operation} parameter expansion
          i = i + 1
          var_start = i
          brace_depth = 1

          do while (i <= len_trim(working_token) .and. brace_depth > 0)
            ! Check for nested ${ pattern (not standalone {)
            if (i > 1 .and. i < len_trim(working_token)) then
              if (working_token(i-1:i) == '${') then
                brace_depth = brace_depth + 1
                i = i + 1  ! Skip the { part of ${
              end if
            end if
            if (working_token(i:i) == '}') then
              brace_depth = brace_depth - 1
            end if
            i = i + 1
          end do

          var_name = working_token(var_start:i-2)

          ! Process parameter expansion
          call process_parameter_expansion(var_name, var_value, shell)
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
        else
          ! Simple $VAR syntax
          var_start = i
          do while (i <= len_trim(working_token))
            if (.not. (is_alnum(working_token(i:i)) .or. working_token(i:i) == '_')) exit
            i = i + 1
          end do

          var_name = working_token(var_start:i-1)

          ! If no valid variable name was found, treat $ as literal
          if (len_trim(var_name) == 0) then
            result(j:j) = '$'
            j = j + 1
          else
            ! Check shell variables first
            ! Check if variable is set before expanding
            if (is_shell_variable_set(shell, trim(var_name))) then
              var_value = get_shell_variable(shell, trim(var_name))
              ! Use get_shell_variable_length to preserve ALL characters including whitespace
              ! This is crucial for variables like IFS=' ' where the space must be preserved
              brace_depth = get_shell_variable_length(shell, trim(var_name))
              if (brace_depth > 0) then
                result(j:j+brace_depth-1) = var_value(1:brace_depth)
                j = j + brace_depth
              end if
            else
              ! Fall back to environment variables
              var_value = get_environment_var(trim(var_name))
              if (allocated(var_value) .and. len(var_value) > 0) then
                result(j:j+len(var_value)-1) = var_value
                j = j + len(var_value)
              else
                ! Variable is not set - check if set -u is enabled
                if (check_nounset(shell, trim(var_name))) then
                  shell%last_exit_status = 127  ! POSIX: expansion errors return 127
                  shell%fatal_expansion_error = .true.
                  shell%running = .false.  ! Stop shell execution
                  expanded = ''
                  return
                end if
              end if
            end if
          end if
        end if
      else if (working_token(i:i) == '`') then
        ! Backtick command substitution
        i = i + 1
        var_start = i
        
        ! Find closing backtick
        do while (i <= len_trim(working_token) .and. working_token(i:i) /= '`')
          i = i + 1
        end do
        
        if (i <= len_trim(working_token) .and. working_token(i:i) == '`') then
          var_name = working_token(var_start:i-1)  ! This is the command
          i = i + 1  ! Skip closing backtick
          
          ! Execute command substitution
          call execute_command_substitution(trim(var_name), var_value, shell)
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
        else
          ! Unmatched backtick, treat as literal
          result(j:j) = '`'
          j = j + 1
        end if
      else
        result(j:j) = working_token(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    ! POSIX: Quote removal does NOT apply to the results of parameter expansion
    ! Only apply quote removal to quotes that were literally in the command, not in variable values
    ! So we do NOT call strip_outer_quotes here - that would incorrectly remove quotes from values like $VAR where VAR='"test"'
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

  subroutine read_heredoc(delimiter, content, shell, strip_tabs)
    use shell_types, only: shell_state_t
    use variables, only: get_shell_variable
    character(len=*), intent(in) :: delimiter
    character(len=:), allocatable, intent(out) :: content
    type(shell_state_t), intent(inout) :: shell
    logical, intent(in), optional :: strip_tabs

    character(len=MAX_TOKEN_LEN) :: line
    character(len=MAX_HEREDOC_LEN) :: buffer
    integer :: iostat, pos, tab_pos
    logical :: should_expand, do_strip_tabs

    ! Determine if we should strip tabs
    do_strip_tabs = .false.
    if (present(strip_tabs)) do_strip_tabs = strip_tabs

    ! Check if we have pending heredoc content from -c flag
    if (shell%has_pending_heredoc .and. &
        trim(shell%pending_heredoc_delimiter) == trim(delimiter)) then
      ! Use the pre-stored content (tabs already stripped by preprocess_heredocs_for_c if needed)
      buffer = trim(shell%pending_heredoc)

      ! Check if we should expand variables
      should_expand = .not. shell%pending_heredoc_quoted

      ! Expand variables if needed
      if (should_expand) then
        buffer = expand_heredoc_variables(buffer, shell)
      end if

      allocate(character(len=len_trim(buffer)) :: content)
      content = trim(buffer)

      ! Clear the pending heredoc
      shell%has_pending_heredoc = .false.
      shell%pending_heredoc = ''
      shell%pending_heredoc_delimiter = ''
      shell%pending_heredoc_quoted = .false.
      shell%pending_heredoc_strip_tabs = .false.
      return
    end if

    ! Fall back to reading from stdin
    buffer = ''
    pos = 1

    write(*, '(a)', advance='no') '> '

    do
      read(*, '(a)', iostat=iostat) line
      if (iostat /= 0) exit

      if (trim(line) == trim(delimiter)) exit

      ! Strip leading tabs if requested
      if (do_strip_tabs) then
        tab_pos = 1
        do while (tab_pos <= len_trim(line) .and. line(tab_pos:tab_pos) == char(9))
          tab_pos = tab_pos + 1
        end do
        line = line(tab_pos:)
      end if

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

  ! Expand variables in heredoc content
  function expand_heredoc_variables(input, shell) result(output)
    use shell_types, only: shell_state_t
    use variables, only: get_shell_variable
    character(len=*), intent(in) :: input
    type(shell_state_t), intent(in) :: shell
    character(len=MAX_HEREDOC_LEN) :: output

    integer :: i, j, var_start, var_end
    character(len=256) :: var_name, var_value

    output = ''
    i = 1
    j = 1

    do while (i <= len_trim(input))
      if (input(i:i) == '$' .and. i < len_trim(input)) then
        ! Found potential variable
        var_start = i + 1

        ! Check for ${var} format
        if (input(var_start:var_start) == '{') then
          var_start = var_start + 1
          var_end = var_start
          do while (var_end <= len_trim(input) .and. input(var_end:var_end) /= '}')
            var_end = var_end + 1
          end do
          if (var_end <= len_trim(input)) then
            var_name = input(var_start:var_end-1)
            var_value = get_shell_variable(shell, trim(var_name))
            output(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
            i = var_end + 1
          else
            output(j:j) = '$'
            j = j + 1
            i = i + 1
          end if
        else
          ! Check for $var format
          var_end = var_start
          do while (var_end <= len_trim(input) .and. &
                   ((input(var_end:var_end) >= 'A' .and. input(var_end:var_end) <= 'Z') .or. &
                    (input(var_end:var_end) >= 'a' .and. input(var_end:var_end) <= 'z') .or. &
                    (input(var_end:var_end) >= '0' .and. input(var_end:var_end) <= '9') .or. &
                    input(var_end:var_end) == '_'))
            var_end = var_end + 1
          end do
          if (var_end > var_start) then
            var_name = input(var_start:var_end-1)
            var_value = get_shell_variable(shell, trim(var_name))
            output(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
            i = var_end
          else
            output(j:j) = '$'
            j = j + 1
            i = i + 1
          end if
        end if
      else
        output(j:j) = input(i:i)
        j = j + 1
        i = i + 1
      end if
    end do
  end function

  ! Strip leading tabs from each line in heredoc content
  function strip_leading_tabs(input) result(output)
    character(len=*), intent(in) :: input
    character(len=MAX_HEREDOC_LEN) :: output
    integer :: i, j, line_start
    logical :: at_line_start

    output = ''
    i = 1
    j = 1
    at_line_start = .true.

    do while (i <= len_trim(input))
      if (at_line_start .and. input(i:i) == char(9)) then
        ! Skip leading tab
        i = i + 1
      else
        ! Copy character
        at_line_start = .false.
        output(j:j) = input(i:i)
        if (input(i:i) == char(10)) then
          at_line_start = .true.
        end if
        j = j + 1
        i = i + 1
      end if
    end do
  end function

  ! Extract heredoc content from input string (for -c mode)
  subroutine extract_heredoc_from_input(input, delimiter, content)
    character(len=*), intent(in) :: input, delimiter
    character(len=:), allocatable, intent(out) :: content

    integer :: i, line_start, line_end, content_start
    integer :: newline_pos, delim_line_start
    character(len=len(input)) :: current_line
    character(len=MAX_HEREDOC_LEN) :: buffer
    integer :: buffer_pos
    logical :: found_start, found_end

    ! Check if input contains newlines (heredoc marker)
    newline_pos = index(input, char(10))
    if (newline_pos == 0) then
      ! No newlines, can't extract heredoc content
      return
    end if

    ! Find where heredoc content starts (after first newline following <<DELIM)
    content_start = 0
    do i = 1, len(input)
      if (input(i:i) == '<' .and. i < len(input) - 1) then
        if (input(i+1:i+1) == '<') then
          ! Found <<, look for newline after delimiter
          do newline_pos = i+2, len(input)
            if (input(newline_pos:newline_pos) == char(10)) then
              content_start = newline_pos + 1
              exit
            end if
          end do
          if (content_start > 0) exit
        end if
      end if
    end do

    if (content_start == 0 .or. content_start > len(input)) then
      ! No content after heredoc marker
      return
    end if

    ! Extract lines until we find the delimiter
    buffer = ''
    buffer_pos = 1
    line_start = content_start
    found_end = .false.

    do while (line_start <= len(input) .and. .not. found_end)
      ! Find end of current line (newline or end of string)
      line_end = line_start
      do while (line_end <= len(input) .and. input(line_end:line_end) /= char(10))
        line_end = line_end + 1
      end do

      ! Extract current line (handle case where line_end went past end of input)
      if (line_end > len(input)) then
        ! No newline found, extract to end of input
        if (line_start <= len(input)) then
          current_line = input(line_start:len(input))
        else
          current_line = ''
        end if
      else if (line_end > line_start) then
        ! Newline found, extract up to (but not including) the newline
        current_line = input(line_start:line_end-1)
      else
        current_line = ''
      end if

      ! Check if this line matches the delimiter
      if (trim(current_line) == trim(delimiter)) then
        found_end = .true.
        exit
      end if

      ! Add line to buffer
      if (buffer_pos > 1) then
        ! Add newline before this line
        buffer(buffer_pos:buffer_pos) = char(10)
        buffer_pos = buffer_pos + 1
      end if

      if (len_trim(current_line) > 0) then
        buffer(buffer_pos:buffer_pos+len_trim(current_line)-1) = trim(current_line)
        buffer_pos = buffer_pos + len_trim(current_line)
      end if

      ! Move to next line
      line_start = line_end + 1
    end do

    ! Allocate and return content (with trailing newline to match POSIX)
    if (buffer_pos > 1) then
      ! Add trailing newline
      buffer(buffer_pos:buffer_pos) = char(10)
      buffer_pos = buffer_pos + 1
      allocate(character(len=buffer_pos-1) :: content)
      content = buffer(:buffer_pos-1)
    end if
  end subroutine

  ! Expand glob patterns in command tokens
  subroutine expand_command_globs(cmd, shell)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(in) :: shell

    character(len=MAX_TOKEN_LEN), allocatable :: expanded_tokens(:)
    character(len=MAX_TOKEN_LEN), allocatable :: original_tokens(:)
    character(len=MAX_TOKEN_LEN), allocatable :: filtered_tokens(:)
    integer :: expanded_count, i, filtered_count
    logical :: has_expandable

    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens == 0) return

    ! Skip glob expansion if noglob option is enabled (set -f)
    if (shell%option_noglob) return

    ! Save original tokens
    allocate(original_tokens(cmd%num_tokens))
    do i = 1, cmd%num_tokens
      original_tokens(i) = cmd%tokens(i)
    end do

    ! Don't glob expand tokens that were escaped or have backslashes
    ! Check metadata if available, otherwise fall back to checking for backslash
    has_expandable = .false.
    do i = 1, cmd%num_tokens
      ! Skip if token was escaped (metadata available) or has backslash (fallback)
      if (allocated(cmd%token_escaped)) then
        ! Use metadata if available
        if (i <= size(cmd%token_escaped) .and. cmd%token_escaped(i)) then
          cycle  ! Skip this token - it was escaped
        end if
      else if (index(cmd%tokens(i), '\') > 0) then
        ! Fallback: check for backslash in token
        cycle  ! Skip this token - it has a backslash
      end if

      ! Check if token has glob characters
      if (index(cmd%tokens(i), '*') > 0 .or. &
          index(cmd%tokens(i), '?') > 0 .or. &
          index(cmd%tokens(i), '[') > 0) then
        has_expandable = .true.
        exit
      end if
    end do

    if (.not. has_expandable) then
      ! No tokens need glob expansion
      if (allocated(original_tokens)) deallocate(original_tokens)
      return
    end if

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

  ! Convert backtick command substitution to $() format
  function convert_backticks_to_dollar_paren(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    character(len=len(input)*2) :: temp_result
    integer :: i, j, backtick_start
    logical :: in_backticks, in_single_quote, in_double_quote
    character(len=1) :: backslash

    backslash = char(92)
    temp_result = ''
    i = 1
    j = 1
    in_backticks = .false.
    in_single_quote = .false.
    in_double_quote = .false.
    backtick_start = 0

    do while (i <= len_trim(input))
      ! Track quote state (but not inside backticks)
      if (.not. in_backticks) then
        if (input(i:i) == "'" .and. (i == 1 .or. input(i-1:i-1) /= backslash)) then
          in_single_quote = .not. in_single_quote
        else if (input(i:i) == '"' .and. (i == 1 .or. input(i-1:i-1) /= backslash)) then
          in_double_quote = .not. in_double_quote
        end if
      end if

      ! Process backticks (not inside single quotes)
      if (input(i:i) == '`' .and. .not. in_single_quote .and. &
          (i == 1 .or. input(i-1:i-1) /= backslash)) then
        if (.not. in_backticks) then
          ! Start of backtick command substitution
          in_backticks = .true.
          backtick_start = i
          temp_result(j:j+1) = '$('
          j = j + 2
        else
          ! End of backtick command substitution
          in_backticks = .false.
          temp_result(j:j) = ')'
          j = j + 1
        end if
        i = i + 1
      else
        ! Regular character
        temp_result(j:j) = input(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    allocate(character(len=j-1) :: output)
    output = temp_result(1:j-1)
  end function

  subroutine execute_command_substitution(command, output, shell)
    use command_capture, only: execute_command_and_capture
    character(len=*), intent(in) :: command
    character(len=:), allocatable, intent(out) :: output
    type(shell_state_t), intent(inout) :: shell

    character(len=4096) :: temp_output

    ! Execute in current shell context to preserve functions, variables, etc.
    call execute_command_and_capture(shell, command, temp_output)

    ! Allocate and copy result
    output = trim(temp_output)

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
                         is_associative_array, get_assoc_array_value, get_assoc_array_keys, &
                         set_shell_variable, is_shell_variable_set, check_nounset
    character(len=*), intent(in) :: param_expr
    character(len=:), allocatable, intent(out) :: result_value
    type(shell_state_t), intent(inout) :: shell

    character(len=MAX_TOKEN_LEN) :: var_name, default_value, operation, index_str
    character(len=1024) :: assoc_value
    character(len=256) :: keys(100), offset_str, length_str_temp
    integer :: op_pos, op_len, bracket_pos, bracket_end, array_index, array_sz
    integer :: num_keys, key_idx
    integer :: colon_pos, offset, str_length, second_colon, iostat_val, char_code
    character(len=:), allocatable :: current_value
    character(len=20) :: length_str
    logical :: is_array_access, get_keys, get_all, is_length, var_is_set

    ! Initialize result
    result_value = ''

    ! Check for @ transformations first: ${var@U}, ${var@L}, ${var@u}, ${var@Q}, ${var@E}
    op_pos = index(param_expr, '@')
    if (op_pos > 1 .and. op_pos < len_trim(param_expr)) then
      ! Extract variable name and transformation operator
      var_name = param_expr(:op_pos-1)
      operation = param_expr(op_pos+1:op_pos+1)
      current_value = get_shell_variable(shell, trim(var_name))

      select case (trim(operation))
      case ('U')
        ! ${var@U} - convert to uppercase
        result_value = to_uppercase(trim(current_value))
        return
      case ('L')
        ! ${var@L} - convert to lowercase
        result_value = to_lowercase(trim(current_value))
        return
      case ('u')
        ! ${var@u} - capitalize first character
        if (len_trim(current_value) > 0) then
          char_code = iachar(current_value(1:1))
          if (char_code >= iachar('a') .and. char_code <= iachar('z')) then
            result_value = achar(char_code - 32) // current_value(2:)
          else
            result_value = current_value
          end if
        end if
        return
      case ('l')
        ! ${var@l} - lowercase first character
        if (len_trim(current_value) > 0) then
          char_code = iachar(current_value(1:1))
          if (char_code >= iachar('A') .and. char_code <= iachar('Z')) then
            result_value = achar(char_code + 32) // current_value(2:)
          else
            result_value = current_value
          end if
        end if
        return
      case ('Q')
        ! ${var@Q} - shell-quote value (wrap in single quotes, escape embedded quotes)
        if (len_trim(current_value) > 0) then
          ! Use buffer to build the quoted string
          var_name = "'"  ! Start with opening quote
          op_pos = 2
          do key_idx = 1, len_trim(current_value)
            if (current_value(key_idx:key_idx) == "'") then
              ! Escape embedded single quote as '\''
              var_name(op_pos:op_pos+3) = "'\'''"
              op_pos = op_pos + 4
            else
              var_name(op_pos:op_pos) = current_value(key_idx:key_idx)
              op_pos = op_pos + 1
            end if
          end do
          var_name(op_pos:op_pos) = "'"  ! Add closing quote
          result_value = var_name(1:op_pos)
        else
          result_value = "''"
        end if
        return
      case ('E')
        ! ${var@E} - expand escape sequences
        ! Use buffer to build the expanded string
        var_name = ''
        op_pos = 1
        key_idx = 1
        do while (key_idx <= len_trim(current_value))
          if (current_value(key_idx:key_idx) == '\' .and. key_idx < len_trim(current_value)) then
            key_idx = key_idx + 1
            select case (current_value(key_idx:key_idx))
            case ('n')
              var_name(op_pos:op_pos) = char(10)
              op_pos = op_pos + 1
            case ('t')
              var_name(op_pos:op_pos) = char(9)
              op_pos = op_pos + 1
            case ('r')
              var_name(op_pos:op_pos) = char(13)
              op_pos = op_pos + 1
            case ('\')
              var_name(op_pos:op_pos) = '\'
              op_pos = op_pos + 1
            case default
              var_name(op_pos:op_pos) = '\'
              var_name(op_pos+1:op_pos+1) = current_value(key_idx:key_idx)
              op_pos = op_pos + 2
            end select
          else
            var_name(op_pos:op_pos) = current_value(key_idx:key_idx)
            op_pos = op_pos + 1
          end if
          key_idx = key_idx + 1
        end do
        result_value = var_name(1:op_pos-1)
        return
      end select
    end if

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
            if (is_associative_array(shell, trim(var_name))) then
              ! For associative arrays, count the keys
              call get_assoc_array_keys(shell, trim(var_name), keys, num_keys)
              write(length_str, '(I0)') num_keys
              result_value = trim(length_str)
            else
              ! For indexed arrays, use get_array_size
              array_sz = get_array_size(shell, trim(var_name))
              write(length_str, '(I0)') array_sz
              result_value = trim(length_str)
            end if
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
                write(length_str, '(i15)') array_index - 1  ! 0-indexed
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
      ! Special handling for @ and * parameters, or empty (just ${#}) - return count, not string length
      if (trim(var_name) == '@' .or. trim(var_name) == '*' .or. len_trim(var_name) == 0) then
        write(length_str, '(I0)') shell%num_positional
        result_value = trim(length_str)
        return
      end if

      ! Get actual stored length from variable
      call get_variable_length(shell, trim(var_name), str_length)
      if (str_length >= 0) then
        write(length_str, '(I0)') str_length
        result_value = trim(length_str)
      else
        ! Variable not found or is environment variable - use len_trim
        current_value = get_shell_variable(shell, trim(var_name))
        if (len_trim(current_value) == 0) then
          current_value = get_environment_var(trim(var_name))
        end if
        if (allocated(current_value)) then
          write(length_str, '(I0)') len_trim(current_value)
          result_value = trim(length_str)
        else
          result_value = '0'
        end if
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

      ! Expand variable references in pattern (both ${VAR} and $VAR style)
      if (index(default_value, '$') > 0) then
        block
          character(len=:), allocatable :: expanded_pattern
          call expand_variables(trim(default_value), expanded_pattern, shell)
          default_value = expanded_pattern
          deallocate(expanded_pattern)
        end block
      end if

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

        ! Expand variable references in pattern (both ${VAR} and $VAR style)
        if (index(default_value, '$') > 0) then
          block
            character(len=:), allocatable :: expanded_pattern
            call expand_variables(trim(default_value), expanded_pattern, shell)
            default_value = expanded_pattern
            deallocate(expanded_pattern)
          end block
        end if

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

      ! Expand variable references in pattern (both ${VAR} and $VAR style)
      if (index(default_value, '$') > 0) then
        block
          character(len=:), allocatable :: expanded_pattern
          call expand_variables(trim(default_value), expanded_pattern, shell)
          default_value = expanded_pattern
          deallocate(expanded_pattern)
        end block
      end if

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

      ! Expand variable references in pattern (both ${VAR} and $VAR style)
      if (index(default_value, '$') > 0) then
        block
          character(len=:), allocatable :: expanded_pattern
          call expand_variables(trim(default_value), expanded_pattern, shell)
          default_value = expanded_pattern
          deallocate(expanded_pattern)
        end block
      end if

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

    ! Look for parameter expansion operators (:-, :=, :+, :?, -, =, +, ?)
    op_pos = 0
    op_len = 0

    ! Check for :- (default value if unset or null)
    op_pos = index(param_expr, ':-')
    if (op_pos > 0) then
      op_len = 2
      operation = ':-'
    else
      ! Check for := (assign default if unset or null)
      op_pos = index(param_expr, ':=')
      if (op_pos > 0) then
        op_len = 2
        operation = ':='
      else
        ! Check for :+ (alternate value if set and not null)
        op_pos = index(param_expr, ':+')
        if (op_pos > 0) then
          op_len = 2
          operation = ':+'
        else
          ! Check for :? (error if unset or null)
          op_pos = index(param_expr, ':?')
          if (op_pos > 0) then
            op_len = 2
            operation = ':?'
          else
            ! Check for - (default value if unset only)
            op_pos = index(param_expr, '-')
            if (op_pos > 0) then
              op_len = 1
              operation = '-'
            else
              ! Check for = (assign default if unset only)
              op_pos = index(param_expr, '=')
              if (op_pos > 0) then
                op_len = 1
                operation = '='
              else
                ! Check for + (alternate value if set)
                op_pos = index(param_expr, '+')
                if (op_pos > 0) then
                  op_len = 1
                  operation = '+'
                else
                  ! Check for ? (error if unset)
                  op_pos = index(param_expr, '?')
                  if (op_pos > 0) then
                    op_len = 1
                    operation = '?'
                  end if
                end if
              end if
            end if
          end if
        end if
      end if
    end if
    
    if (op_pos > 0) then
      ! Extract variable name and default value
      var_name = param_expr(:op_pos-1)
      default_value = param_expr(op_pos+op_len:)

      ! Expand nested parameter expansions in default_value (e.g., ${B} in ${A:-${B}})
      if (index(default_value, '${') > 0) then
        block
          character(len=:), allocatable :: expanded_default
          call expand_variables(trim(default_value), expanded_default, shell)
          default_value = expanded_default
          deallocate(expanded_default)
        end block
      end if
    else
      ! Simple ${VAR} expansion
      var_name = param_expr
      default_value = ''
    end if

    ! Get current variable value and check if set
    var_is_set = is_shell_variable_set(shell, trim(var_name))
    current_value = get_shell_variable(shell, trim(var_name))
    if (len_trim(current_value) == 0) then
      current_value = get_environment_var(trim(var_name))
      if (allocated(current_value) .and. len_trim(current_value) > 0) then
        var_is_set = .true.
      end if
    end if

    ! Apply parameter expansion logic
    if (op_pos == 0) then
      ! Simple expansion ${VAR}
      ! Check if variable is unset and set -u is enabled
      if (.not. var_is_set) then
        if (check_nounset(shell, trim(var_name))) then
          shell%last_exit_status = 127  ! POSIX: expansion errors return 127
          shell%fatal_expansion_error = .true.
          shell%running = .false.  ! Stop shell execution
          result_value = ''
          return
        end if
      end if

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
    else if (trim(operation) == '-') then
      ! Use default value if variable is unset (but not if just empty)
      if (var_is_set) then
        if (allocated(current_value)) then
          result_value = current_value
        else
          result_value = ''
        end if
      else
        result_value = trim(default_value)
      end if
    else if (trim(operation) == ':=') then
      ! Assign default if variable is unset or empty
      if (allocated(current_value) .and. len(current_value) > 0) then
        result_value = current_value
      else
        result_value = trim(default_value)
        ! Set the variable to the default value
        call set_shell_variable(shell, trim(var_name), trim(default_value))
      end if
    else if (trim(operation) == '=') then
      ! Assign default if variable is unset (but not if just empty)
      if (var_is_set) then
        if (allocated(current_value)) then
          result_value = current_value
        else
          result_value = ''
        end if
      else
        result_value = trim(default_value)
        call set_shell_variable(shell, trim(var_name), trim(default_value))
      end if
    else if (trim(operation) == ':+') then
      ! Use alternate value if variable is set and not empty
      if (allocated(current_value) .and. len(current_value) > 0) then
        result_value = trim(default_value)
      else
        result_value = ''
      end if
    else if (trim(operation) == '+') then
      ! Use alternate value if variable is set (even if empty)
      if (var_is_set) then
        result_value = trim(default_value)
      else
        result_value = ''
      end if
    else if (trim(operation) == ':?') then
      ! Error if variable is unset or empty
      if (.not. allocated(current_value) .or. len(current_value) == 0) then
        write(error_unit, '(A,A,A,A,A)') 'fortsh: ', trim(var_name), ': ', &
              trim(default_value), ' (parameter null or not set)'
        result_value = ''
        shell%last_exit_status = 127
        shell%fatal_expansion_error = .true.  ! Signal to abort execution
        return
      else
        result_value = current_value
      end if
    else if (trim(operation) == '?') then
      ! Error if variable is unset
      if (.not. var_is_set) then
        if (len_trim(default_value) > 0) then
          write(error_unit, '(A,A,A,A)') 'fortsh: ', trim(var_name), ': ', trim(default_value)
        else
          write(error_unit, '(A,A,A)') 'fortsh: ', trim(var_name), ': parameter not set'
        end if
        result_value = ''
        shell%last_exit_status = 127
        shell%fatal_expansion_error = .true.  ! Signal to abort execution
        return
      else
        if (allocated(current_value)) then
          result_value = current_value
        else
          result_value = ''
        end if
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

  ! Detect and replace process substitution <(...) and >(...) with FIFO paths
  subroutine process_substitutions(shell, input, output)
    use substitution, only: create_fifo_for_subst, set_fifo_pid
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: output

    integer :: i, start_pos, paren_depth, out_pos, fifo_len
    character(len=MAX_PATH_LEN) :: fifo_path, command
    logical :: is_input_subst
    integer(c_pid_t) :: pid
    character(len=1) :: subst_type

    output = ''
    out_pos = 1
    i = 1

    do while (i <= len_trim(input))
      ! Check for <( or >(
      ! IMPORTANT: Must check i+1 doesn't exceed string bounds
      if (i+1 <= len_trim(input) .and. &
          (input(i:i+1) == '<(' .or. input(i:i+1) == '>(')) then

        subst_type = input(i:i)
        is_input_subst = (subst_type == '<')

        ! Find matching closing parenthesis
        start_pos = i + 2
        paren_depth = 1
        i = start_pos

        do while (i <= len_trim(input) .and. paren_depth > 0)
          if (input(i:i) == '(') then
            paren_depth = paren_depth + 1
          else if (input(i:i) == ')') then
            paren_depth = paren_depth - 1
          end if
          i = i + 1
        end do

        if (paren_depth == 0) then
          ! Extract the command
          command = input(start_pos:i-2)

          ! Create FIFO
          fifo_path = create_fifo_for_subst(shell, is_input_subst)

          if (len_trim(fifo_path) > 0) then
            ! Fork background process to execute command with proper redirection
            pid = c_fork()

            if (pid == 0) then
              ! Child process
              call execute_proc_subst_command(trim(command), trim(fifo_path), is_input_subst)
              call c_exit(0)
            else
              ! Parent process - track the PID
              call set_fifo_pid(shell, fifo_path, pid)

              ! Replace <(command) or >(command) with FIFO path
              fifo_len = len_trim(fifo_path)
              if (out_pos + fifo_len - 1 <= len(output)) then
                output(out_pos:out_pos+fifo_len-1) = trim(fifo_path)
                out_pos = out_pos + fifo_len
              end if
            end if
          else
            write(error_unit, '(A)') 'fortsh: failed to create process substitution'
            ! Keep original if failed - but this is a rare error case
          end if
        end if
      else
        ! Regular character - copy without trimming
        if (out_pos <= len(output)) then
          output(out_pos:out_pos) = input(i:i)
          out_pos = out_pos + 1
        end if
        i = i + 1
      end if
    end do
  end subroutine

  ! Execute a process substitution command with proper redirection
  subroutine execute_proc_subst_command(command, fifo_path, is_input)
    character(len=*), intent(in) :: command, fifo_path
    logical, intent(in) :: is_input
    character(len=512) :: full_command
    character(len=256), target :: shell_cmd, command_c
    character(len=16), target :: shell_flag
    type(c_ptr), target :: argv(4)
    integer :: result

    ! Build redirected command using shell
    if (is_input) then
      ! <(command) - redirect command's stdout to FIFO
      write(full_command, '(A,A,A,A)') trim(command), ' > ', trim(fifo_path), c_null_char
    else
      ! >(command) - redirect FIFO to command's stdin
      write(full_command, '(A,A,A,A)') trim(command), ' < ', trim(fifo_path), c_null_char
    end if

    ! Execute via /bin/sh -c
    shell_cmd = '/bin/sh'//c_null_char
    shell_flag = '-c'//c_null_char
    command_c = trim(full_command)

    argv(1) = c_loc(shell_cmd)
    argv(2) = c_loc(shell_flag)
    argv(3) = c_loc(command_c)
    argv(4) = c_null_ptr

    result = c_execvp(c_loc(shell_cmd), c_loc(argv))
    if (result < 0) then
      write(error_unit, '(A)') 'fortsh: failed to execute process substitution command'
      call c_exit(1)
    end if
  end subroutine

  ! Execute a command via system shell (for process substitution)
  subroutine execute_command_via_shell(command)
    character(len=*), intent(in) :: command
    character(len=256), target :: shell_cmd, command_c
    character(len=16), target :: shell_flag
    type(c_ptr), target :: argv(4)
    integer :: result

    ! Build command: /bin/sh -c "command"
    shell_cmd = '/bin/sh'//c_null_char
    shell_flag = '-c'//c_null_char
    command_c = trim(command)//c_null_char

    argv(1) = c_loc(shell_cmd)
    argv(2) = c_loc(shell_flag)
    argv(3) = c_loc(command_c)
    argv(4) = c_null_ptr

    ! Execute /bin/sh -c "command"
    result = c_execvp(c_loc(shell_cmd), c_loc(argv))
    if (result < 0) then
      write(error_unit, '(A)') 'fortsh: failed to execute process substitution command'
      call c_exit(1)
    end if
  end subroutine

  ! Extract prefix assignments (VAR=value command) from tokenized command
  ! Moves VAR=value pairs to cmd%prefix_assignments and removes them from tokens
  subroutine extract_prefix_assignments(cmd)
    type(command_t), intent(inout) :: cmd
    integer :: i, eq_pos, first_cmd_token
    character(len=256) :: token
    logical :: is_assignment
    character(len=:), allocatable :: new_tokens(:)
    integer :: new_token_count

    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens == 0) return

    cmd%num_prefix_assignments = 0
    first_cmd_token = 0

    ! Scan tokens from the beginning to find prefix assignments
    do i = 1, cmd%num_tokens
      token = trim(cmd%tokens(i))

      ! Check if token is a valid assignment (VAR=value)
      is_assignment = .false.
      eq_pos = index(token, '=')

      if (eq_pos > 1) then
        ! Has '=' and something before it
        ! Check if everything before '=' is a valid variable name
        ! (letters, numbers, underscore, but must start with letter or underscore)
        is_assignment = is_valid_var_name(token(:eq_pos-1))
      end if

      if (is_assignment) then
        ! This is a prefix assignment
        if (cmd%num_prefix_assignments < 10) then
          cmd%num_prefix_assignments = cmd%num_prefix_assignments + 1
          cmd%prefix_assignments(cmd%num_prefix_assignments) = trim(token)
        end if
      else
        ! First non-assignment token - this is where the command starts
        first_cmd_token = i
        exit
      end if
    end do

    ! If we found prefix assignments, remove them from tokens
    if (cmd%num_prefix_assignments > 0 .and. first_cmd_token > 0) then
      new_token_count = cmd%num_tokens - cmd%num_prefix_assignments

      if (new_token_count > 0) then
        ! Allocate new token array with remaining tokens
        allocate(character(len=len(cmd%tokens)) :: new_tokens(new_token_count))

        ! Copy remaining tokens
        do i = 1, new_token_count
          new_tokens(i) = cmd%tokens(first_cmd_token + i - 1)
        end do

        ! Replace tokens array
        deallocate(cmd%tokens)
        cmd%tokens = new_tokens
        cmd%num_tokens = new_token_count
      else
        ! All tokens were assignments, no actual command
        deallocate(cmd%tokens)
        cmd%num_tokens = 0
      end if
    end if
  end subroutine

  ! Check if a string is a valid shell variable name
  function is_valid_var_name(name) result(is_valid)
    character(len=*), intent(in) :: name
    logical :: is_valid
    integer :: i
    character :: ch

    is_valid = .false.
    if (len_trim(name) == 0) return

    ! First character must be letter or underscore
    ch = name(1:1)
    if (.not. ((ch >= 'A' .and. ch <= 'Z') .or. &
               (ch >= 'a' .and. ch <= 'z') .or. &
               ch == '_')) then
      return
    end if

    ! Remaining characters can be letters, digits, or underscores
    do i = 2, len_trim(name)
      ch = name(i:i)
      if (.not. ((ch >= 'A' .and. ch <= 'Z') .or. &
                 (ch >= 'a' .and. ch <= 'z') .or. &
                 (ch >= '0' .and. ch <= '9') .or. &
                 ch == '_')) then
        return
      end if
    end do

    is_valid = .true.
  end function

  ! Check if a line has unclosed quotes (needs continuation)
  function has_unclosed_quote(line) result(has_unclosed)
    character(len=*), intent(in) :: line
    logical :: has_unclosed
    integer :: i
    logical :: in_single_quote, in_double_quote
    character :: prev_char

    has_unclosed = .false.
    in_single_quote = .false.
    in_double_quote = .false.
    prev_char = ' '

    do i = 1, len_trim(line)
      ! Check for escape character
      if (prev_char == '\') then
        ! Skip this character as it's escaped
        prev_char = ' '  ! Reset escape
        cycle
      end if

      ! Track quote state
      if (line(i:i) == "'" .and. .not. in_double_quote) then
        in_single_quote = .not. in_single_quote
      else if (line(i:i) == '"' .and. .not. in_single_quote) then
        in_double_quote = .not. in_double_quote
      end if

      prev_char = line(i:i)
    end do

    ! If either quote type is unclosed, we need continuation
    has_unclosed = in_single_quote .or. in_double_quote
  end function

end module parser