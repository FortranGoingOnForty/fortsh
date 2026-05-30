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
#ifdef USE_C_STRINGS
  use iso_c_binding, only: c_char, c_int, c_ptr, c_size_t, c_f_pointer
#endif
  implicit none

  ! Export backtick conversion for new parser
  public :: convert_backticks_to_dollar_paren
  public :: needs_compound_continuation
  public :: remove_line_continuations

contains

  subroutine parse_pipeline(input, pipeline)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline

    character(len=len(input)) :: working_input
    integer :: start, cmd_count
    integer :: i, newline_pos
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
        if (i > 1 .and. working_input(i:i) == '{') then
          if (working_input(i-1:i-1) == '$') in_param_expansion = .true.
        else if (in_param_expansion .and. working_input(i:i) == '}') then
          in_param_expansion = .false.
        end if

        if (working_input(i:i) == '"' .or. working_input(i:i) == "'") then
          in_quotes = .true.
          quote_char = working_input(i:i)
        else if (working_input(i:i) == '#' .and. .not. in_param_expansion) then
          ! Only treat # as comment if not part of $# or ${...}
          if (i > 1) then; if (working_input(i-1:i-1) == '$') then
            ! This is $#, not a comment
            cycle
          end if; end if
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
          if (i == 1) then
            paren_depth = paren_depth + 1
          else if (working_input(i-1:i-1) /= '$') then
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
            block
              logical :: at_word_boundary
              if (i == 1) then
                at_word_boundary = .true.
              else
                at_word_boundary = (working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';')
              end if
              if (at_word_boundary) then
                ! Verify word boundary after (space or special char)
                if (i+4 > len_trim(working_input) .or. working_input(i+4:i+4) == ' ' .or. &
                    working_input(i+4:i+4) == ';') then
                  case_depth = case_depth + 1
                  after_case_in = .false.  ! Reset when we see 'case'
                end if
              end if
            end block
          end if
        end if

        ! Check for ' in ' keyword inside case statement (split after it)
        if (case_depth > 0 .and. .not. after_case_in) then
          if (i <= len_trim(working_input) - 2) then
            if (working_input(i:i+1) == 'in') then
              ! Verify word boundary before (space)
              if (i > 1) then; if (working_input(i-1:i-1) == ' ') then
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
              end if; end if  ! i > 1 guard
            end if
          end if
        end if

        ! Check for 'esac' keyword at word boundary
        if (i <= len_trim(working_input) - 3) then
          if (working_input(i:i+3) == 'esac') then
            ! Verify it's a word boundary (space or start before it)
            block
              logical :: esac_word_boundary
              if (i == 1) then
                esac_word_boundary = .true.
              else
                esac_word_boundary = (working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';')
              end if
              if (esac_word_boundary) then
                ! Verify word boundary after (space, semicolon, or end)
                if (i+4 > len_trim(working_input) .or. working_input(i+4:i+4) == ' ' .or. &
                    working_input(i+4:i+4) == ';') then
                  case_depth = case_depth - 1
                  if (case_depth < 0) case_depth = 0  ! Prevent negative
                  after_case_in = .false.  ! Reset after esac
                end if
              end if
            end block
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

        block
          logical :: pipe_not_after_pipe, pipe_not_after_gt, pipe_not_before_pipe
          if (i == 1) then
            pipe_not_after_pipe = .true.
            pipe_not_after_gt = .true.
          else
            pipe_not_after_pipe = (working_input(i-1:i-1) /= '|')
            pipe_not_after_gt = (working_input(i-1:i-1) /= '>')
          end if
          if (i == len_trim(working_input)) then
            pipe_not_before_pipe = .true.
          else
            pipe_not_before_pipe = (working_input(i+1:i+1) /= '|')
          end if
        if (working_input(i:i) == '|' .and. pipe_not_after_pipe .and. &
            pipe_not_after_gt .and. pipe_not_before_pipe) then
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
          block
            logical :: amp_not_after_special, amp_not_before_amp
            if (i == 1) then
              amp_not_after_special = .true.
            else
              amp_not_after_special = (working_input(i-1:i-1) /= '&' .and. &
                                      working_input(i-1:i-1) /= '>' .and. &
                                      working_input(i-1:i-1) /= '<')
            end if
            if (i == len_trim(working_input)) then
              amp_not_before_amp = .true.
            else
              amp_not_before_amp = (working_input(i+1:i+1) /= '&')
            end if
          if (amp_not_after_special .and. amp_not_before_amp) then
            ! Single & - mark current command as background and split
            cmd_count = cmd_count + 1
            if (cmd_count <= MAX_PIPELINE) then
              call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
              temp_commands(cmd_count)%separator = SEP_SEMICOLON  ! Execute like semicolon
              temp_commands(cmd_count)%background = .true.  ! But run in background
            end if
            start = i + 1
          end if
          end block  ! amp_not_after_special bounds-safe check
        else if (working_input(i:i) == ';') then
          ! Check for ;; (double semicolon) which is used in case statements
          if (i < len_trim(working_input) .and. working_input(i+1:i+1) == ';') then
            ! This is ;; - inside case statements it's a pattern terminator
            if (case_depth > 0) then
              cmd_count = cmd_count + 1
              if (cmd_count <= MAX_PIPELINE) then
                call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
                temp_commands(cmd_count)%separator = SEP_SEMICOLON
              end if
              start = i + 2  ! Skip both semicolons
              i = i + 1  ! Will be incremented again at end of loop
              after_case_in = .false.  ! Reset after ;;, ready for next pattern
            else
              ! POSIX: ;; outside case is treated as two semicolons (null command + separator)
              ! Parse command before first semicolon (if any)
              if (i > start) then
                cmd_count = cmd_count + 1
                if (cmd_count <= MAX_PIPELINE) then
                  call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
                  temp_commands(cmd_count)%separator = SEP_SEMICOLON
                end if
              end if
              start = i + 2  ! Skip both semicolons
              i = i + 1  ! Will be incremented again at end of loop
            end if
          ! Only split on single semicolon if not inside for (( ... )), function braces, subshells, or case statement
          else if (in_for_arith .or. brace_depth > 0 .or. paren_depth > 0 .or. case_depth > 0) then
            ! Skip - we're inside for (( ... )), function { ... }, subshell ( ... ), or case...esac
          else
            ! POSIX: semicolon at start is a null command - just skip it
            if (i == start) then
              start = i + 1
            else
              cmd_count = cmd_count + 1
              if (cmd_count <= MAX_PIPELINE) then
                call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
                temp_commands(cmd_count)%separator = SEP_SEMICOLON
              end if
              start = i + 1
            end if
          end if
        end if
        end block  ! pipe_not_after_pipe bounds-safe check
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
        if (allocated(temp_commands(i)%prefix_assignments) .and. &
            temp_commands(i)%num_prefix_assignments > 0) then
          pipeline%commands(i)%prefix_assignments = temp_commands(i)%prefix_assignments
        end if

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
    integer :: pos, start, token_count, i
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
    use expansion, only: expand_braces, arithmetic_expansion_shell, process_param_expansion
    character(len=*), intent(in) :: token
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(inout) :: shell
    logical, intent(in), optional :: was_quoted_in

    character(len=:), allocatable :: result, working_token
    integer :: i, j, var_start, brace_depth, end_pos
    integer :: result_cap
    character(len=256) :: var_name  ! Variable names are short; was MAX_TOKEN_LEN (4096)
    character(len=:), allocatable :: var_value, brace_expanded
    character(len=20) :: pid_str
    logical :: is_quoted, is_single_quoted
    logical :: escapes_already_processed  ! True if lexer already processed escapes

    ! Initialize growing result buffer
    result_cap = max(len(token) * 4, 16384)
    allocate(character(len=result_cap) :: result)

    ! Check if token was originally quoted (from lexer metadata or token inspection)
    is_quoted = .false.
    is_single_quoted = .false.
    escapes_already_processed = .false.

    ! Use the passed parameter if provided, otherwise fall back to checking the token
    if (present(was_quoted_in)) then
      is_quoted = was_quoted_in
      ! We don't track single vs double quotes in metadata, assume double if quoted
      is_single_quoted = .false.
      ! If was_quoted_in=true but token doesn't have outer quotes, the new lexer
      ! already stripped quotes and processed escapes - don't re-process them
      if (is_quoted .and. len_trim(token) >= 2) then
        if (.not. (token(1:1) == '"' .and. token(len_trim(token):len_trim(token)) == '"')) then
          escapes_already_processed = .true.
        end if
      else if (is_quoted .and. len_trim(token) < 2) then
        ! Short quoted token without surrounding quotes - escapes were processed
        escapes_already_processed = .true.
      end if
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
    ! return the whitespace to preserve the argument
    ! This handles cases like " " or "   " where len_trim would be 0
    ! Now that executor passes correct token length, we preserve exact whitespace count
    if (is_quoted .and. len_trim(token) == 0 .and. len(token) > 0) then
      ! Check if this is truly a whitespace token vs a token with quotes at boundaries
      block
        ! If token has quotes at boundaries, don't count them as content - let normal processing handle it
        if (len(token) >= 2) then
          if ((token(1:1) == '"' .and. token(len(token):len(token)) == '"') .or. &
              (token(1:1) == "'" .and. token(len(token):len(token)) == "'")) then
            ! Token is just quotes with possibly empty content - let normal processing handle it
          else
            ! Token is all whitespace (no quotes) - return the whitespace exactly as-is
            expanded = token
            return
          end if
        else
          ! Short token that's all whitespace - return it as-is
          expanded = token
          return
        end if
      end block
    end if

    ! Apply brace expansion ONLY if token is not quoted
    if (.not. is_quoted) then
      brace_expanded = expand_braces(token)
      working_token = brace_expanded
    else
      working_token = token
    end if

    i = 1
    j = 1
    ! For quoted tokens, use len(token) to preserve trailing whitespace
    ! For unquoted tokens, use len_trim() to skip padding
    if (is_quoted) then
      end_pos = len(token)  ! Use actual passed token length, not buffer size
      ! If token has actual quote characters (not sentinels), skip them
      ! This handles tokens from the old parser path which don't use sentinels
      if (end_pos >= 2) then
        if (working_token(1:1) == '"' .and. working_token(end_pos:end_pos) == '"') then
          i = 2  ! Skip opening quote
          end_pos = end_pos - 1  ! Skip closing quote
        end if
      end if
    else
      end_pos = len_trim(working_token)
    end if

    ! Track if we're inside single-quoted literal region (between char(2) markers)
    block
    logical :: in_single_quote_literal
    in_single_quote_literal = .false.

    do while (i <= end_pos)
      ! Grow result buffer if needed (headroom for single-char writes)
      call ensure_result_cap(j + 256)
      ! Check for single-quote literal START sentinel (char(2))
      if (working_token(i:i) == char(2)) then
        in_single_quote_literal = .true.
        i = i + 1
        cycle
      end if

      ! Check for single-quote literal END sentinel (char(3))
      if (working_token(i:i) == char(3)) then
        in_single_quote_literal = .false.
        i = i + 1
        cycle
      end if

      ! In single-quoted literal region, copy everything literally (no expansion)
      if (in_single_quote_literal) then
        result(j:j) = working_token(i:i)
        i = i + 1
        j = j + 1
        cycle
      end if

      ! Check for double-quote boundary sentinel (char(1)) - skip it
      if (working_token(i:i) == char(1)) then
        i = i + 1
        cycle
      end if

      ! Check for backslash escape
      ! Handle \$ and \` even outside quotes since lexer keeps both chars for these
      if (working_token(i:i) == '\' .and. i < end_pos) then
        if (working_token(i+1:i+1) == '$') then
          ! \$ -> literal $ (lexer keeps both chars, we process here)
          i = i + 1  ! Skip backslash
          result(j:j) = '$'
          i = i + 1
          j = j + 1
          cycle
        else if (working_token(i+1:i+1) == '`') then
          ! \` -> literal ` (lexer keeps both chars, we process here)
          i = i + 1  ! Skip backslash
          result(j:j) = '`'
          i = i + 1
          j = j + 1
          cycle
        else if (is_quoted .and. .not. is_single_quoted .and. .not. escapes_already_processed) then
          ! In double quotes, backslash also escapes: " \ and newline
          ! BUT skip this if lexer already processed escapes (new lexer path)
          ! Note: \$ and \` are handled above because lexer keeps both chars for them
          if (working_token(i+1:i+1) == '"' .or. working_token(i+1:i+1) == '\') then
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

      ! POSIX: Tilde expansion is NOT performed inside double quotes
      block
        logical :: tilde_at_word_start
        if (i == 1) then
          tilde_at_word_start = .true.
        else
          tilde_at_word_start = (working_token(i-1:i-1) == ' ')
        end if
      if (working_token(i:i) == '~' .and. tilde_at_word_start &
          .and. .not. is_quoted) then
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
          ! Use shell%shell_pid (set at startup) so $$ returns same value in subshells
          write(pid_str, '(i0)') shell%shell_pid
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
            call ensure_result_cap(j + len_trim(var_value))
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '#') then
          ! $# - number of positional parameters
          var_value = get_shell_variable(shell, '#')
          if (len_trim(var_value) > 0) then
            call ensure_result_cap(j + len_trim(var_value))
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '*') then
          ! $* - all positional parameters as single word
          var_value = get_shell_variable(shell, '*')
          if (len_trim(var_value) > 0) then
            call ensure_result_cap(j + len_trim(var_value))
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '-') then
          ! $- - current shell option flags
          var_value = get_shell_variable(shell, '-')
          if (len_trim(var_value) > 0) then
            call ensure_result_cap(j + len_trim(var_value))
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
          i = i + 1
        else if (working_token(i:i) == '_') then
          ! Check if this is $_ alone or $_varname
          if (i+1 <= len_trim(working_token) .and. &
              (is_alnum(working_token(i+1:i+1)) .or. working_token(i+1:i+1) == '_')) then
            ! $_varname - underscore-prefixed variable name
            var_start = i
            do while (i <= len_trim(working_token) .and. &
                      (is_alnum(working_token(i:i)) .or. working_token(i:i) == '_'))
              i = i + 1
            end do
            var_name = working_token(var_start:i-1)
            var_value = get_shell_variable(shell, trim(var_name))
            if (len_trim(var_value) > 0) then
              call ensure_result_cap(j + len_trim(var_value))
              result(j:j+len_trim(var_value)-1) = trim(var_value)
              j = j + len_trim(var_value)
            end if
          else
            ! $_ - last argument of previous command
            var_value = get_shell_variable(shell, '_')
            if (len_trim(var_value) > 0) then
              call ensure_result_cap(j + len_trim(var_value))
              result(j:j+len_trim(var_value)-1) = trim(var_value)
              j = j + len_trim(var_value)
            end if
            i = i + 1
          end if
        else if (working_token(i:i) >= '0' .and. working_token(i:i) <= '9') then
          ! $0, $1, $2, ... - positional parameters
          var_name = working_token(i:i)
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            call ensure_result_cap(j + len_trim(var_value))
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
              call ensure_result_cap(j + len_trim(var_value))
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
              call ensure_result_cap(j + len(var_value))
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

          ! Process parameter expansion (delegated to expansion module — issue #12)
          call process_param_expansion(var_name, var_value, shell)
          if (allocated(var_value) .and. len(var_value) > 0) then
            call ensure_result_cap(j + len_trim(var_value))
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
                call ensure_result_cap(j + brace_depth)
                result(j:j+brace_depth-1) = var_value(1:brace_depth)
                j = j + brace_depth
              end if
            else
              ! Fall back to environment variables
              var_value = get_environment_var(trim(var_name))
              if (allocated(var_value) .and. len(var_value) > 0) then
                call ensure_result_cap(j + len(var_value))
                result(j:j+len(var_value)-1) = var_value
                j = j + len(var_value)
              else
                ! Variable is not set - check if set -u is enabled
                if (check_nounset(shell, trim(var_name))) then
                  shell%last_exit_status = 127  ! bash uses 127 for direct expansion errors
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
            call ensure_result_cap(j + len_trim(var_value))
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
        else
          ! Unmatched backtick, treat as literal
          result(j:j) = '`'
          j = j + 1
        end if
      else if (working_token(i:i) == char(1)) then
        ! Skip sentinel character (marks quote boundary from lexer)
        i = i + 1
      else if ((working_token(i:i) == '<' .or. working_token(i:i) == '>') .and. &
               i + 1 <= len_trim(working_token) .and. working_token(i+1:i+1) == '(' .and. &
               .not. is_quoted) then
        ! Process substitution <(cmd) / >(cmd) — bash model:
        ! create pipe, fork child, use /dev/fd/N as the filename.
        ! No FIFOs, no temp files, no leaks.
        block
          use trap_dispatch, only: eval_trap_string
          use io_helpers, only: write_stderr
          character(len=MAX_PATH_LEN) :: ps_command
          character(len=32) :: devfd_path
          logical :: ps_is_input, pipe_ok
          integer :: ps_start, ps_depth, ps_exit
          integer(c_pid_t) :: ps_pid
          integer(c_int) :: read_fd, write_fd, parent_fd, child_fd, ret

          ps_is_input = (working_token(i:i) == '<')
          ps_start = i + 2
          ps_depth = 1
          i = ps_start

          do while (i <= len_trim(working_token) .and. ps_depth > 0)
            if (working_token(i:i) == '(') ps_depth = ps_depth + 1
            if (working_token(i:i) == ')') ps_depth = ps_depth - 1
            if (ps_depth > 0) i = i + 1
          end do

          if (ps_depth == 0) then
            ps_command = working_token(ps_start:i-1)
            i = i + 1

            pipe_ok = create_pipe(read_fd, write_fd)
            if (pipe_ok) then
              if (ps_is_input) then
                parent_fd = read_fd
                child_fd = write_fd
              else
                parent_fd = write_fd
                child_fd = read_fd
              end if

              ps_pid = c_fork()
              if (ps_pid == 0) then
                ! Child: close parent's end, redirect child's end
                ret = c_close(parent_fd)
                if (ps_is_input) then
                  ret = c_dup2(child_fd, STDOUT_FD)
                else
                  ret = c_dup2(child_fd, STDIN_FD)
                end if
                ret = c_close(child_fd)
                shell%is_interactive = .false.
                call eval_trap_string(trim(ps_command), shell, ps_exit)
                call c_exit(ps_exit)
              else if (ps_pid > 0) then
                ! Parent: close child's end, build /dev/fd/N path
                ret = c_close(child_fd)
                write(devfd_path, '(a,i0)') '/dev/fd/', parent_fd
                call ensure_result_cap(j + len_trim(devfd_path))
                result(j:j+len_trim(devfd_path)-1) = trim(devfd_path)
                j = j + len_trim(devfd_path)
              end if
            end if
          else
            result(j:j) = working_token(i:i)
            j = j + 1
          end if
        end block
      else
        result(j:j) = working_token(i:i)
        i = i + 1
        j = j + 1
      end if
      end block  ! tilde_at_word_start bounds-safe check
    end do
    end block  ! End of in_single_quote_literal block

    ! POSIX: Quote removal does NOT apply to the results of parameter expansion
    ! Only apply quote removal to quotes that were literally in the command, not in variable values
    ! So we do NOT call strip_outer_quotes here - that would incorrectly remove quotes from values like $VAR where VAR='"test"'
    ! Don't use trim() - preserve trailing whitespace from variable values
    if (j > 1) then
      expanded = result(1:j-1)
    else
      expanded = ''
    end if

  contains

    subroutine ensure_result_cap(needed)
      integer, intent(in) :: needed
      character(len=:), allocatable :: tmp
      integer :: new_cap
      if (needed <= result_cap) return
      new_cap = max(result_cap * 2, needed + 4096)
      allocate(character(len=new_cap) :: tmp)
      if (j > 1) tmp(1:j-1) = result(1:j-1)
      call move_alloc(tmp, result)
      result_cap = new_cap
    end subroutine

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

    ! Check if we have pending heredocs from -c flag (new array-based approach)
    if (shell%num_pending_heredocs > 0 .and. &
        shell%next_pending_heredoc <= shell%num_pending_heredocs) then
      ! Get the next pending heredoc
      buffer = trim(shell%pending_heredocs(shell%next_pending_heredoc)%content)

      ! Check if we should expand variables
      should_expand = .not. shell%pending_heredocs(shell%next_pending_heredoc)%quoted

      ! Expand variables if needed
      if (should_expand) then
        buffer = expand_heredoc_variables(buffer, shell)
      end if

      allocate(character(len=len_trim(buffer)) :: content)
      content = trim(buffer)

      ! Advance to next pending heredoc
      shell%next_pending_heredoc = shell%next_pending_heredoc + 1

      ! Clear pending heredocs when all consumed
      if (shell%next_pending_heredoc > shell%num_pending_heredocs) then
        shell%num_pending_heredocs = 0
        shell%next_pending_heredoc = 1
        ! Also clear legacy single heredoc
        shell%has_pending_heredoc = .false.
        shell%pending_heredoc = ''
        shell%pending_heredoc_delimiter = ''
        shell%pending_heredoc_quoted = .false.
        shell%pending_heredoc_strip_tabs = .false.
      end if
      return
    end if

    ! Legacy: Check single pending heredoc (backward compatibility)
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

      ! Strip leading tabs BEFORE delimiter comparison (<<- strips tabs)
      if (do_strip_tabs) then
        tab_pos = 1
        do while (tab_pos <= len_trim(line) .and. line(tab_pos:tab_pos) == char(9))
          tab_pos = tab_pos + 1
        end do
        line = line(tab_pos:)
      end if

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

  ! Expand variables in heredoc content
  function expand_heredoc_variables(input, shell) result(output)
    use shell_types, only: shell_state_t
    use variables, only: get_shell_variable
    character(len=*), intent(in) :: input
    type(shell_state_t), intent(in) :: shell
    character(len=MAX_HEREDOC_LEN) :: output

    integer :: i, j, var_start, var_end
    character(len=256) :: var_name
    character(len=:), allocatable :: var_value

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
    integer :: i, j
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
    integer :: newline_pos
    character(len=len(input)) :: current_line
    character(len=MAX_HEREDOC_LEN) :: buffer
    integer :: buffer_pos
    logical :: found_end

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
        ! Fortran .or. does NOT short-circuit, so check i > 1 separately
        ! to avoid input(0:0) out-of-bounds access
        block
          logical :: not_escaped
          if (i == 1) then
            not_escaped = .true.
          else
            not_escaped = (input(i-1:i-1) /= backslash)
          end if
          if (input(i:i) == "'" .and. not_escaped) then
            in_single_quote = .not. in_single_quote
          else if (input(i:i) == '"' .and. not_escaped) then
            in_double_quote = .not. in_double_quote
          end if
        end block
      end if

      ! Inside backticks: handle escaped backticks as nested substitution delimiters
      ! POSIX: \` inside backticks means start/end of nested command substitution
      if (in_backticks .and. input(i:i) == backslash .and. i < len_trim(input)) then
        if (input(i+1:i+1) == '`') then
          ! Escaped backtick inside backticks = nested command substitution
          ! Convert to $() for the nested level
          temp_result(j:j+1) = '$('
          j = j + 2
          i = i + 2
          ! Find the matching closing \` and convert it too
          block
            integer :: k, nest_level
            nest_level = 1
            k = i
            do while (k <= len_trim(input) .and. nest_level > 0)
              if (input(k:k) == backslash .and. k < len_trim(input) .and. input(k+1:k+1) == '`') then
                nest_level = nest_level - 1
                if (nest_level == 0) then
                  ! Copy everything up to here, then add closing )
                  do while (i < k)
                    temp_result(j:j) = input(i:i)
                    j = j + 1
                    i = i + 1
                  end do
                  temp_result(j:j) = ')'
                  j = j + 1
                  i = k + 2  ! Skip the \`
                  exit
                else
                  k = k + 2
                end if
              else
                k = k + 1
              end if
            end do
          end block
          cycle
        else if (input(i+1:i+1) == '$' .or. input(i+1:i+1) == backslash .or. &
                 input(i+1:i+1) == char(10)) then
          ! Other escapes: consume backslash, copy the character
          temp_result(j:j) = input(i+1:i+1)
          j = j + 1
          i = i + 2
          cycle
        end if
      end if

      ! Process backticks (not inside single quotes)
      ! Fortran .or. does NOT short-circuit, so check i > 1 separately
      block
        logical :: backtick_not_escaped
        if (i == 1) then
          backtick_not_escaped = .true.
        else
          backtick_not_escaped = (input(i-1:i-1) /= backslash)
        end if
      if (input(i:i) == '`' .and. .not. in_single_quote .and. backtick_not_escaped) then
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
      end block  ! backtick_not_escaped
    end do

    allocate(character(len=j-1) :: output)
    output = temp_result(1:j-1)
  end function

  subroutine execute_command_substitution(command, output, shell)
    use command_capture, only: execute_command_and_capture
    character(len=*), intent(in) :: command
    character(len=:), allocatable, intent(out) :: output
    type(shell_state_t), intent(inout) :: shell

    ! POSIX: errexit should not trigger in command substitution
    shell%in_command_substitution = .true.

    ! Execute in current shell context to preserve functions, variables, etc.
    call execute_command_and_capture(shell, command, output)

    shell%in_command_substitution = .false.

    if (.not. allocated(output)) output = ''

    ! Remove trailing newlines (but NOT other whitespace like spaces)
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


  subroutine process_tilde_expansion(token, pos, result, result_pos, shell)
    character(len=*), intent(in) :: token
    integer, intent(inout) :: pos, result_pos
    character(len=*), intent(inout) :: result
    type(shell_state_t), intent(in) :: shell

    character(len=MAX_TOKEN_LEN) :: username, home_path
    character(len=:), allocatable :: home_dir, shell_var
    integer :: start_pos

    ! Skip the tilde
    pos = pos + 1

    ! POSIX: ~+ expands to PWD, ~- expands to OLDPWD
    if (pos <= len_trim(token) .and. token(pos:pos) == '+') then
      ! ~+ - expand to PWD (check shell variable first, then environment)
      shell_var = get_shell_variable(shell, 'PWD')
      if (len_trim(shell_var) > 0) then
        result(result_pos:result_pos+len_trim(shell_var)-1) = trim(shell_var)
        result_pos = result_pos + len_trim(shell_var)
      else
        home_dir = get_environment_var('PWD')
        if (allocated(home_dir) .and. len(home_dir) > 0) then
          result(result_pos:result_pos+len(home_dir)-1) = home_dir
          result_pos = result_pos + len(home_dir)
        else
          ! Fallback: return ~+ literally
          result(result_pos:result_pos+1) = '~+'
          result_pos = result_pos + 2
        end if
      end if
      pos = pos + 1  ! Skip the +
      return
    else if (pos <= len_trim(token) .and. token(pos:pos) == '-') then
      ! ~- - expand to OLDPWD (check shell variable first, then environment)
      shell_var = get_shell_variable(shell, 'OLDPWD')
      if (len_trim(shell_var) > 0) then
        result(result_pos:result_pos+len_trim(shell_var)-1) = trim(shell_var)
        result_pos = result_pos + len_trim(shell_var)
      else
        home_dir = get_environment_var('OLDPWD')
        if (allocated(home_dir) .and. len(home_dir) > 0) then
          result(result_pos:result_pos+len(home_dir)-1) = home_dir
          result_pos = result_pos + len(home_dir)
        else
          ! Fallback: return ~- literally
          result(result_pos:result_pos+1) = '~-'
          result_pos = result_pos + 2
        end if
      end if
      pos = pos + 1  ! Skip the -
      return
    else if (pos > len_trim(token) .or. token(pos:pos) == '/' .or. token(pos:pos) == ' ') then
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
      ! ~username expansion — resolve the real home via getpwnam.
      start_pos = pos
      do while (pos <= len_trim(token) .and. token(pos:pos) /= '/' .and. token(pos:pos) /= ' ')
        pos = pos + 1
      end do

      if (pos > start_pos) then
        username = token(start_pos:pos-1)
      else
        username = ''
      end if

      block
        character(len=:), allocatable :: user_home
        user_home = get_user_home(trim(username))
        if (len(user_home) > 0) then
          result(result_pos:result_pos+len(user_home)-1) = user_home
          result_pos = result_pos + len(user_home)
        else
          ! Unknown user: leave "~username" literal (matches bash).
          result(result_pos:result_pos) = '~'
          result_pos = result_pos + 1
          if (len_trim(username) > 0) then
            result(result_pos:result_pos+len_trim(username)-1) = trim(username)
            result_pos = result_pos + len_trim(username)
          end if
        end if
      end block

      ! pos already points at the terminator ('/'/space) or just past the end,
      ! exactly like the bare-~ branch above — do NOT step back (that re-copied
      ! the username's last char, e.g. ~root -> /home/roott).
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
      ! IMPORTANT: Fortran .and. does NOT short-circuit, so we must use
      ! a nested if to avoid substring out-of-bounds access
      if (i+1 <= len(input) .and. i+1 <= len_trim(input)) then
        if (input(i:i+1) == '<(' .or. input(i:i+1) == '>(') then

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
                ! Child process — run command natively through the AST
                ! executor with stdout/stdin redirected to the FIFO.
                call execute_proc_subst_native(trim(command), trim(fifo_path), is_input_subst, shell)
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
      else
        ! Last character or beyond trim - copy as regular character
        if (out_pos <= len(output)) then
          output(out_pos:out_pos) = input(i:i)
          out_pos = out_pos + 1
        end if
        i = i + 1
      end if
    end do
  end subroutine

  ! Execute a process substitution command natively through the AST
  ! executor with stdout/stdin redirected to the FIFO.
  subroutine execute_proc_subst_native(command, fifo_path, is_input, shell)
    use trap_dispatch, only: eval_trap_string
    use io_helpers, only: write_stderr
    character(len=*), intent(in) :: command, fifo_path
    logical, intent(in) :: is_input
    type(shell_state_t), intent(inout) :: shell
    integer(c_int) :: fifo_fd, ret
    integer :: exit_status
    character(len=MAX_PATH_LEN), target :: c_path

    c_path = trim(fifo_path) // c_null_char

    if (is_input) then
      ! <(cmd): command writes to FIFO → redirect stdout to FIFO
      fifo_fd = c_open(c_loc(c_path), O_WRONLY, 0)
      if (fifo_fd < 0) then
        call write_stderr('fortsh: process substitution: cannot open FIFO for writing')
        call c_exit(1)
      end if
      ret = c_dup2(fifo_fd, STDOUT_FD)
    else
      ! >(cmd): command reads from FIFO → redirect stdin from FIFO
      fifo_fd = c_open(c_loc(c_path), O_RDONLY, 0)
      if (fifo_fd < 0) then
        call write_stderr('fortsh: process substitution: cannot open FIFO for reading')
        call c_exit(1)
      end if
      ret = c_dup2(fifo_fd, STDIN_FD)
    end if
    ret = c_close(fifo_fd)

    shell%is_interactive = .false.
    call eval_trap_string(trim(command), shell, exit_status)
    call c_exit(exit_status)
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
    character(len=MAX_TOKEN_LEN), allocatable :: new_tokens(:)
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
        if (cmd%num_prefix_assignments < MAX_PREFIX_ASSIGNMENTS) then
          if (.not. allocated(cmd%prefix_assignments)) then
            allocate(character(len=MAX_TOKEN_LEN) :: cmd%prefix_assignments(MAX_PREFIX_ASSIGNMENTS))
          end if
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
        allocate(new_tokens(new_token_count))

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
    integer :: i, check_len, bracket_pos
    character :: ch

    is_valid = .false.
    check_len = len_trim(name)
    if (check_len == 0) return

    ! Accept array subscript names: var[subscript]
    bracket_pos = index(name(1:check_len), '[')
    if (bracket_pos > 0) then
      check_len = bracket_pos - 1
      if (check_len == 0) return
    end if

    ! First character must be letter or underscore
    ch = name(1:1)
    if (.not. ((ch >= 'A' .and. ch <= 'Z') .or. &
               (ch >= 'a' .and. ch <= 'z') .or. &
               ch == '_')) then
      return
    end if

    ! Remaining characters can be letters, digits, or underscores
    do i = 2, check_len
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

  function ends_with_continuation_backslash(line) result(needs_continuation)
    character(len=*), intent(in) :: line
    logical :: needs_continuation
    integer :: i, line_len
    logical :: in_single_quote, in_double_quote
    character :: prev_char

    needs_continuation = .false.
    line_len = len_trim(line)

    ! Empty line doesn't need continuation
    if (line_len == 0) return

    ! Quick check: if line doesn't end with backslash, no continuation needed
    if (line(line_len:line_len) /= '\') return

    ! Now we need to check if the trailing backslash is inside quotes
    in_single_quote = .false.
    in_double_quote = .false.
    prev_char = ' '

    do i = 1, line_len
      ! Check for escape character (in double quotes or unquoted)
      if (prev_char == '\' .and. .not. in_single_quote) then
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

    ! If we're not inside quotes and line ends with backslash, need continuation
    ! (prev_char is backslash at this point since it's the last char)
    needs_continuation = .not. in_single_quote .and. .not. in_double_quote
  end function

  ! Detect if a command line has a heredoc operator (<<) whose content hasn't been provided.
  ! Returns the delimiter string if found, empty if no heredoc pending.
  function get_heredoc_delimiter(line) result(delimiter)
    character(len=*), intent(in) :: line
    character(len=256) :: delimiter
    integer :: i, dstart, dend, line_len
    logical :: in_sq, in_dq, strip_tabs, delim_quoted

    delimiter = ''
    line_len = len_trim(line)
    in_sq = .false.; in_dq = .false.
    i = 1

    do while (i < line_len)
      ! Track quotes
      if (line(i:i) == "'" .and. .not. in_dq) then
        in_sq = .not. in_sq
        i = i + 1; cycle
      end if
      if (line(i:i) == '"' .and. .not. in_sq) then
        in_dq = .not. in_dq
        i = i + 1; cycle
      end if
      if (in_sq .or. in_dq) then
        i = i + 1; cycle
      end if

      ! Look for << not inside quotes (but NOT <<< which is here-string)
      if (line(i:i) == '<' .and. i + 1 <= line_len .and. line(i+1:i+1) == '<') then
        ! Skip <<< (here-string, not heredoc)
        if (i + 2 <= line_len .and. line(i+2:i+2) == '<') then
          i = i + 3
          cycle
        end if
        i = i + 2
        ! Skip <<- (strip tabs variant)
        strip_tabs = .false.
        if (i <= line_len .and. line(i:i) == '-') then
          strip_tabs = .true.
          i = i + 1
        end if
        ! Skip whitespace
        do while (i <= line_len .and. (line(i:i) == ' ' .or. line(i:i) == char(9)))
          i = i + 1
        end do
        if (i > line_len) return

        ! Extract delimiter — may be quoted
        delim_quoted = .false.
        if (line(i:i) == "'" .or. line(i:i) == '"') then
          delim_quoted = .true.
          dstart = i + 1
          dend = index(line(dstart:line_len), line(i:i))
          if (dend > 0) then
            dend = dstart + dend - 2
          else
            dend = line_len  ! unclosed quote
          end if
        else
          dstart = i
          dend = i
          do while (dend + 1 <= line_len .and. line(dend+1:dend+1) /= ' ' .and. &
                    line(dend+1:dend+1) /= char(9) .and. line(dend+1:dend+1) /= ';')
            dend = dend + 1
          end do
        end if

        if (dend >= dstart) then
          delimiter = line(dstart:dend)
          return
        end if
      end if
      i = i + 1
    end do
  end function

  function needs_compound_continuation(input) result(needs_more)
    use lexer, only: tokenize
    character(len=*), intent(in) :: input
    logical :: needs_more
    type(token_t), allocatable :: tokens(:)
    integer :: num_tokens, i
    integer :: if_depth, do_depth, case_depth, brace_depth

    needs_more = .false.

    ! Tokenize the input using the lexer
    allocate(tokens(MAX_TOKENS))
    call tokenize(input, tokens, num_tokens)

    if_depth = 0
    do_depth = 0
    case_depth = 0
    brace_depth = 0

    do i = 1, num_tokens
      if (tokens(i)%token_type /= TOKEN_KEYWORD) cycle
      select case (trim(tokens(i)%value))
      case ('if')
        if_depth = if_depth + 1
      case ('fi')
        if_depth = if_depth - 1
      case ('do')
        do_depth = do_depth + 1
      case ('done')
        do_depth = do_depth - 1
      case ('case')
        case_depth = case_depth + 1
      case ('esac')
        case_depth = case_depth - 1
      case ('{')
        brace_depth = brace_depth + 1
      case ('}')
        brace_depth = brace_depth - 1
      end select
    end do

    needs_more = (if_depth > 0 .or. do_depth > 0 .or. case_depth > 0 .or. brace_depth > 0)
  end function

  function remove_line_continuations(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: i, j

    output = ''
    i = 1
    j = 1

    do while (i <= len_trim(input))
      ! Check for backslash followed by newline
      if (i < len_trim(input) .and. input(i:i) == char(92)) then
        if (input(i+1:i+1) == char(10)) then
          ! Skip both the backslash and newline
          i = i + 2
          cycle
        end if
      end if

      ! Copy character to output
      output(j:j) = input(i:i)
      i = i + 1
      j = j + 1
    end do
  end function

end module parser