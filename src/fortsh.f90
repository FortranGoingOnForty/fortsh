! ==============================================================================
! Main Program: Fortran Shell (Fortsh)
! ==============================================================================
program fortran_shell
  use shell_types
  use system_interface
  use signal_handler
  use signal_handling
  use parser, only: convert_backticks_to_dollar_paren
  use grammar_parser  ! New grammar-aware parser
  use ast_executor    ! AST execution for new parser
  use command_tree    ! Command tree for new parser
  use executor
  use job_control
  use readline
  use shell_config
  use aliases
  use shell_options
  use performance
  use prompt_formatting
  use command_capture_callback, only: init_command_capture  ! For command substitution
  use builtins, only: init_builtins  ! Initialize builtin function pointers
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  type(shell_state_t), allocatable :: shell
  type(pipeline_t) :: pipeline
  character(len=1024) :: input_line, proc_subst_line
  character(len=:), allocatable :: expanded_line, history_expanded
  character(len=1024) :: prompt_str  ! Fixed-length to avoid LLVM Flang heap corruption
  integer :: iostat, i, num_args
  character(len=1024) :: arg1, command_string
  logical :: execute_command_string, execute_script_file
  character(len=:), allocatable :: script_file
  ! Command duration tracking
  integer :: cmd_start_time, cmd_end_time, cmd_duration_ms, clock_rate
  real :: cmd_duration_sec
  ! New parser infrastructure
  type(command_node_t), pointer :: ast_root
  integer :: exit_code
  character(len=:), allocatable :: converted_line

  ! Initialize performance monitoring
  call init_performance_monitoring()

  ! Allocate shell to avoid large stack allocation on macOS
  allocate(shell)

  ! Initialize shell state (detects login shell from arguments)
  call initialize_shell(shell)

  ! Initialize builtin function pointers (breaks circular dependency)
  call init_builtins()

  ! Initialize control flow callbacks (breaks circular dependency)
  call init_control_flow_callbacks()

  ! Initialize command history (needed even in non-interactive mode)
  call init_history()

  ! Check for command-line arguments
  num_args = command_argument_count()
  execute_command_string = .false.
  execute_script_file = .false.

  ! Handle command-line arguments for script execution
  if (num_args > 0) then
    call get_command_argument(1, arg1)

    ! Check for -c flag (execute command string)
    if (trim(arg1) == '-c') then
      if (num_args >= 2) then
        call get_command_argument(2, command_string)
        execute_command_string = .true.
        shell%is_interactive = .false.
      else
        write(error_unit, '(a)') 'fortsh: -c: option requires an argument'
        stop 2
      end if
    ! Check if it's not a flag (assume it's a script file)
    else if (arg1(1:1) /= '-') then
      script_file = trim(arg1)
      execute_script_file = .true.
      shell%is_interactive = .false.
    end if
  end if

  ! Initialize signal handling module
  call init_signal_handling(shell)

  ! Initialize command capture callback (for command substitution)
  call init_command_capture()

  ! Setup signal handlers if interactive
  if (shell%is_interactive) then
    call setup_signal_handlers()

    ! Welcome message for interactive mode
    write(output_unit, '(a)') 'Welcome to Fortran Shell (fortsh)!'
    write(output_unit, '(a)') 'Type "help" for available commands or "exit" to quit.'
    write(output_unit, '(a)') ''

    ! Load configuration file
    call load_config_file(shell)

    ! Set HISTCONTROL for history management
    call set_histcontrol(shell%histcontrol)

    ! Load command history from file
    if (len_trim(shell%histfile) > 0) then
      call load_history_from_file(trim(shell%histfile), shell%histsize)
    end if
  end if

  ! Execute command string if -c was specified
  if (execute_command_string) then
    ! Check if string contains heredoc and pre-process it
    if (index(command_string, '<<') > 0) then
      ! Pre-process heredocs before parsing
      command_string = preprocess_heredocs_for_c(command_string, shell)
      ! write(error_unit, '(A,A)') 'DEBUG: After preprocess, command_string=', trim(command_string)
    end if

    ! Handle line continuation (backslash-newline)
    command_string = remove_line_continuations(command_string)
    call process_substitutions(shell, trim(command_string), proc_subst_line)

    ! Use new parser if feature flag is enabled
    if (shell%use_new_parser) then
      ! NEW PARSER PATH: Parse to AST and execute directly
      ! Convert backticks to $() first
      converted_line = convert_backticks_to_dollar_paren(proc_subst_line)
      ast_root => parse_command_line(converted_line)
      if (associated(ast_root)) then
        exit_code = execute_ast(ast_root, shell)
        shell%last_exit_status = exit_code
        call destroy_command_node(ast_root)
      else
        ! Parse error occurred
        shell%last_exit_status = 2
      end if
    else
      ! OLD PARSER PATH: Parse to pipeline and execute
      call parse_pipeline(proc_subst_line, pipeline)

      ! Check for syntax errors
      if (pipeline%parse_error) then
        shell%last_exit_status = 2  ! Syntax error
      else if (pipeline%num_commands > 0) then
        call execute_pipeline(pipeline, shell, trim(command_string))

        ! Check if we need to replay loop body (for loops, while, until)
        if (shell%control_depth == 0 .or. .not. shell%control_stack(shell%control_depth)%capturing_loop_body) then
          call replay_loop_if_needed(shell)
        end if

        ! Clean up pipeline
        if (allocated(pipeline%commands)) then
          do i = 1, pipeline%num_commands
            if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
            if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
            if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
            if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
            if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
            if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
            if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
          end do
          deallocate(pipeline%commands)
        end if
      end if
    end if

    ! Process any sourced files queued by the command
    if (shell%should_source) then
      call process_source_file(shell)
    end if

    ! Execute EXIT trap if one is set (before exiting)
    call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT

    ! Exit with last command's exit status
    call c_exit(shell%last_exit_status)
  end if

  ! Execute script file if specified
  if (execute_script_file) then
    shell%source_file = script_file
    shell%should_source = .true.
    call process_source_file(shell)

    ! Execute EXIT trap if one is set (before exiting)
    call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT

    ! Exit with last command's exit status (don't print Goodbye for scripts)
    if (perf_monitoring_enabled) then
      call print_performance_stats()
    end if
    call cleanup_performance_monitoring()
    call c_exit(shell%last_exit_status)
  end if

  ! Main REPL loop
  do while (shell%running)
    ! Update job status
    if (shell%is_interactive) then
      call update_job_status(shell)
      call notify_job_status(shell)
    end if

    ! Process sourced files
    if (shell%should_source) then
      call process_source_file(shell)
      cycle
    end if

    ! Read input with enhanced readline (includes prompt only if interactive)
    if (shell%is_interactive) then
      ! Use safe_expand_prompt to avoid LLVM Flang heap corruption
      call safe_expand_prompt(shell%ps1, shell, shell%ps1_len, prompt_str)
      call readline_enhanced(trim(prompt_str), input_line, iostat)
    else
      read(input_unit, '(a)', iostat=iostat) input_line
      ! Note: History will be added after expansion below
    end if

    ! Check for EOF (Ctrl-D)
    if (iostat /= 0) then
      ! Only print newline in interactive mode for clean exit
      if (shell%is_interactive) then
        write(output_unit, '(a)') ''
      end if
      exit
    end if

    ! Skip empty lines
    if (len_trim(input_line) == 0) cycle

    ! Check for unclosed quotes and continue reading lines if needed
    do while (has_unclosed_quote(input_line))
      if (shell%is_interactive) then
        ! Full readline with PS2 prompt expansion
        prompt_str = expand_prompt(shell%ps2, shell, shell%ps2_len)
        call readline_enhanced(prompt_str, proc_subst_line, iostat)
      else
        ! Non-interactive: just read next line
        read(input_unit, '(a)', iostat=iostat) proc_subst_line
      end if

      ! Check for EOF during continuation
      if (iostat /= 0) then
        ! Only print newline in interactive mode for clean exit
        if (shell%is_interactive) then
          write(output_unit, '(a)') ''
        end if
        exit
      end if

      ! Append the continuation line with a newline character
      input_line = trim(input_line) // char(10) // trim(proc_subst_line)
    end do

    ! Expand history (!!, !n, !string, etc.) if needed
    if (needs_history_expansion(input_line)) then
      history_expanded = expand_history(input_line)
      ! Print expanded command if interactive (like bash does)
      if (shell%is_interactive) then
        write(output_unit, '(a)') trim(history_expanded)
      end if
      ! Add the EXPANDED command to history (not the original !!)
      call add_to_history(history_expanded)
      ! Now expand aliases on the history-expanded line
      call expand_alias(shell, trim(history_expanded), expanded_line)
    else
      ! No history expansion needed, add original line to history
      call add_to_history(input_line)
      ! Then expand aliases
      call expand_alias(shell, trim(input_line), expanded_line)
    end if

    ! Process substitutions <() and >() before parsing
    call process_substitutions(shell, expanded_line, proc_subst_line)

    ! Parse and execute (use new parser if feature flag is enabled)
    if (shell%use_new_parser) then
      ! NEW PARSER PATH: Parse to AST and execute directly
      call system_clock(cmd_start_time, clock_rate)

      ! Convert backticks to $() first
      converted_line = convert_backticks_to_dollar_paren(proc_subst_line)
      ast_root => parse_command_line(converted_line)
      if (associated(ast_root)) then
        exit_code = execute_ast(ast_root, shell)
        shell%last_exit_status = exit_code
        call destroy_command_node(ast_root)

        ! Calculate and display duration if > 1 second
        call system_clock(cmd_end_time)
        cmd_duration_ms = (cmd_end_time - cmd_start_time) * 1000 / clock_rate
        cmd_duration_sec = real(cmd_duration_ms) / 1000.0

        if (shell%is_interactive .and. cmd_duration_sec >= 1.0) then
          write(output_unit, '(a,f0.1,a)') char(27) // '[2m' // 'Executed in ', &
                                           cmd_duration_sec, 's' // char(27) // '[0m'
        end if

        ! Increment command number for next prompt
        shell%command_number = shell%command_number + 1
        call increment_prompt_history()
      else
        ! Parse error occurred
        shell%last_exit_status = 2
      end if
    else
      ! OLD PARSER PATH: Parse to pipeline and execute
      call parse_pipeline(proc_subst_line, pipeline)

      ! Check for syntax errors
      if (pipeline%parse_error) then
        shell%last_exit_status = 2  ! Syntax error
      else if (pipeline%num_commands > 0) then
        ! Track command duration (Fish-style)
        call system_clock(cmd_start_time, clock_rate)

        call execute_pipeline(pipeline, shell, expanded_line)

      ! Exit immediately if exit command was executed
      if (.not. shell%running) then
        ! Clean up pipeline before exiting
        if (allocated(pipeline%commands)) then
          do i = 1, pipeline%num_commands
            if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
            if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
            if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
            if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
            if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
            if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
            if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
          end do
          deallocate(pipeline%commands)
        end if
        exit  ! Exit the main loop immediately
      end if

      ! Calculate and display duration if > 1 second
      call system_clock(cmd_end_time)
      cmd_duration_ms = (cmd_end_time - cmd_start_time) * 1000 / clock_rate
      cmd_duration_sec = real(cmd_duration_ms) / 1000.0

      ! Display duration if > 1 second (Fish-style)
      if (shell%is_interactive .and. cmd_duration_sec >= 1.0) then
        write(output_unit, '(a,f0.1,a)') char(27) // '[2m' // 'Executed in ', &
                                         cmd_duration_sec, 's' // char(27) // '[0m'
      end if

      ! Check if we need to replay loop body (only if NOT currently capturing)
      if (shell%control_depth == 0 .or. .not. shell%control_stack(shell%control_depth)%capturing_loop_body) then
        call replay_loop_if_needed(shell)
      end if

      ! Increment command number and history number for next prompt
      shell%command_number = shell%command_number + 1
      call increment_prompt_history()
    end if

      ! Clean up pipeline
      if (allocated(pipeline%commands)) then
        do i = 1, pipeline%num_commands
          if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
          if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
          if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
          if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
          if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
          if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
          if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
        end do

        deallocate(pipeline%commands)
      end if
    end if  ! End of old parser path
  end do

  ! Execute EXIT trap if one is set
  call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT

  ! Save command history to file (only in interactive mode)
  if (shell%is_interactive .and. len_trim(shell%histfile) > 0 .and. get_history_count() > 0) then
    call save_history_to_file(trim(shell%histfile), shell%histfilesize)
  end if

  ! Run logout scripts if this is a login shell
  if (shell%is_login_shell) then
    call run_logout_scripts(shell)
  end if

  ! Print performance statistics if monitoring was enabled
  if (perf_monitoring_enabled) then
    call print_performance_stats()
  end if

  ! Cleanup performance monitoring
  call cleanup_performance_monitoring()

  ! Only print goodbye message in interactive mode
  if (shell%is_interactive) then
    write(output_unit, '(a)') 'Goodbye!'
  end if

  ! Exit with the last command's exit status (preserves exit code from EXIT trap)
  call c_exit(shell%last_exit_status)

contains

  ! Remove backslash-newline line continuations from input
  function remove_line_continuations(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: i, j

    output = ''
    i = 1
    j = 1

    do while (i <= len_trim(input))
      ! Check for backslash followed by newline
      if (i < len_trim(input) .and. input(i:i) == char(92)) then  ! char(92) is backslash
        if (input(i+1:i+1) == char(10)) then  ! char(10) is newline
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

  ! Convert escape sequences like \n to actual characters for -c flag
  function convert_escape_sequences(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)*2) :: output  ! Worst case: all chars become newlines
    integer :: i, j

    output = ''
    i = 1
    j = 1

    do while (i <= len_trim(input))
      ! Check for backslash escape sequences
      if (i < len_trim(input) .and. input(i:i) == '\') then
        select case(input(i+1:i+1))
        case('n')
          ! Convert \n to actual newline
          output(j:j) = char(10)
          i = i + 2
          j = j + 1
        case('t')
          ! Convert \t to tab
          output(j:j) = char(9)
          i = i + 2
          j = j + 1
        case('\')
          ! Convert \\ to single backslash
          output(j:j) = '\'
          i = i + 2
          j = j + 1
        case default
          ! Keep backslash and next char as-is
          output(j:j) = input(i:i)
          j = j + 1
          i = i + 1
        end select
      else
        ! Regular character, copy as-is
        output(j:j) = input(i:i)
        i = i + 1
        j = j + 1
      end if
    end do
  end function

  ! Pre-process heredocs in -c commands
  ! Extracts heredoc content and stores it for later use
  function preprocess_heredocs_for_c(input, shell) result(output)
    use shell_types
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: input
    type(shell_state_t), intent(inout) :: shell
    character(len=len(input)*2) :: output
    integer :: i, j, heredoc_start, delim_start, delim_end
    integer :: content_start, content_end, next_cmd_start
    character(len=256) :: delimiter
    character(len=4096) :: heredoc_content
    logical :: quoted_delimiter

    ! write(error_unit, '(A,A,A)') 'DEBUG: preprocess input=|', input(1:min(200,len_trim(input))), '|'

    output = input  ! Start with original

    ! Look for heredoc marker
    i = index(input, '<<')
    if (i == 0) then
      return  ! No heredoc
    end if

    ! Skip spaces after <<
    j = i + 2
    do while (j <= len_trim(input) .and. input(j:j) == ' ')
      j = j + 1
    end do

    ! Check for quoted delimiter
    quoted_delimiter = .false.
    if (input(j:j) == "'" .or. input(j:j) == '"') then
      quoted_delimiter = .true.
      block
        character :: quote_char
        quote_char = input(j:j)
        j = j + 1
        delim_start = j
        ! Find closing quote
        delim_end = j
        do while (delim_end <= len_trim(input) .and. input(delim_end:delim_end) /= quote_char)
          delim_end = delim_end + 1
        end do
        delim_end = delim_end - 1
      end block
    else
      delim_start = j
      ! Find end of delimiter (space or newline)
      delim_end = j
      do while (delim_end <= len_trim(input) .and. &
               input(delim_end:delim_end) /= ' ' .and. &
               input(delim_end:delim_end) /= char(10))
        delim_end = delim_end + 1
      end do
      delim_end = delim_end - 1
    end if

    if (delim_end < delim_start) return  ! Invalid delimiter

    delimiter = input(delim_start:delim_end)
    ! write(error_unit, '(A,A,A)') 'DEBUG: delimiter=|', trim(delimiter), '|'

    ! Find the newline after the heredoc command
    heredoc_start = delim_end + 1
    if (quoted_delimiter) heredoc_start = heredoc_start + 1  ! Skip closing quote

    ! Skip to newline
    do while (heredoc_start <= len_trim(input) .and. input(heredoc_start:heredoc_start) /= char(10))
      heredoc_start = heredoc_start + 1
    end do
    if (heredoc_start > len_trim(input)) return  ! No content
    heredoc_start = heredoc_start + 1  ! Skip the newline

    ! Find the delimiter line
    content_start = heredoc_start
    content_end = 0
    j = heredoc_start

    do while (j <= len_trim(input))
      ! Check if we're at start of a line
      if (j == heredoc_start .or. input(j-1:j-1) == char(10)) then
        ! Debug: show what we're checking
        ! if (j + len_trim(delimiter) - 1 <= len_trim(input)) then
        !   write(error_unit, '(A,I0,A,A,A)') 'DEBUG: Checking at pos ', j, ': |', &
        !     input(j:min(j+10, len_trim(input))), '|'
        ! end if
        ! Check if this line starts with the delimiter
        if (j + len_trim(delimiter) - 1 <= len_trim(input)) then
          if (input(j:j+len_trim(delimiter)-1) == trim(delimiter)) then
            ! write(error_unit, '(A)') 'DEBUG: Found delimiter match!'
            ! Check if delimiter is alone on the line or followed by newline
            if (j + len_trim(delimiter) > len_trim(input) .or. &
                input(j+len_trim(delimiter):j+len_trim(delimiter)) == char(10)) then
              content_end = j - 1
              next_cmd_start = j + len_trim(delimiter)
              if (next_cmd_start <= len_trim(input) .and. &
                  input(next_cmd_start:next_cmd_start) == char(10)) then
                next_cmd_start = next_cmd_start + 1
              end if
              exit
            end if
          end if
        end if
      end if
      j = j + 1
    end do

    if (content_end == 0) then
      return  ! Delimiter not found
    end if

    ! Extract heredoc content
    if (content_end >= content_start) then
      heredoc_content = input(content_start:content_end)
    else
      heredoc_content = ''
    end if


    ! Store heredoc content in shell state
    shell%pending_heredoc = trim(heredoc_content)
    shell%pending_heredoc_delimiter = trim(delimiter)
    shell%pending_heredoc_quoted = quoted_delimiter
    shell%has_pending_heredoc = .true.

    ! Return the command without the heredoc content
    ! The heredoc module will handle it when the command executes
    ! Need to replace any newlines with semicolons to keep it a single command
    block
      integer :: k
      character(len=len(input)) :: cmd_part

      cmd_part = input(1:i-1)  ! Everything before <<

      ! Replace newlines with semicolons in the command part
      do k = 1, len_trim(cmd_part)
        if (cmd_part(k:k) == char(10)) then
          cmd_part(k:k) = ';'
        end if
      end do

      output = trim(cmd_part)
    end block

    ! Re-add the heredoc marker with delimiter so heredoc module can process it
    if (quoted_delimiter) then
      output = trim(output) // " << '" // trim(delimiter) // "'"
    else
      output = trim(output) // ' << ' // trim(delimiter)
    end if

    ! Add any commands after the heredoc
    if (next_cmd_start <= len_trim(input)) then
      output = trim(output) // ' ' // input(next_cmd_start:len_trim(input))
    end if

  end function

  subroutine run_logout_scripts(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: home_dir, logout_file
    logical :: file_exists

    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) return

    ! Execute ~/.fortsh_logout if it exists
    logout_file = trim(home_dir) // '/.fortsh_logout'
    inquire(file=logout_file, exist=file_exists)

    if (file_exists) then
      ! Source the logout file
      shell%source_file = logout_file
      shell%should_source = .true.
      call process_source_file(shell)
    end if
  end subroutine


  subroutine process_source_file(shell)
    use variables, only: add_function
    use grammar_parser, only: parse_command_line
    use command_tree, only: destroy_command_node, command_node_t
    use ast_executor, only: execute_ast
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: input_line, proc_subst_line, continuation_line, converted_line
    integer :: file_unit, iostat, i, brace_depth, func_line_count, exit_code
    type(pipeline_t) :: pipeline
    type(command_node_t), pointer :: ast_root
    character(len=:), allocatable :: expanded_line, history_expanded
    logical :: in_function
    character(len=256) :: func_name
    ! Reduced from 100 to 50 lines to avoid static storage
    character(len=1024) :: func_body(50)

    ! Reset the source flag first
    shell%should_source = .false.

    ! Open file for reading
    open(newunit=file_unit, file=trim(shell%source_file), status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'source: failed to open ' // trim(shell%source_file)
      shell%last_exit_status = 1
      return
    end if

    ! Initialize function capture state
    in_function = .false.
    brace_depth = 0
    func_line_count = 0
    func_name = ''

    ! Execute each line in the file
    do
      read(file_unit, '(a)', iostat=iostat) input_line
      if (iostat /= 0) exit  ! End of file or error

      ! Skip empty lines and comments (unless we're inside a function)
      if (.not. in_function) then
        if (len_trim(input_line) == 0 .or. input_line(1:1) == '#') cycle
      end if

      ! Check for unclosed quotes and continue reading lines if needed
      do while (has_unclosed_quote(input_line))
        read(file_unit, '(a)', iostat=iostat) continuation_line
        if (iostat /= 0) exit  ! End of file during continuation
        ! Append the continuation line with a newline character
        input_line = trim(input_line) // char(10) // trim(continuation_line)
      end do

      ! If EOF was reached during continuation, exit
      if (iostat /= 0) exit

      ! Check if this is the start of a function definition
      if (.not. in_function .and. is_function_definition(input_line, func_name)) then
        in_function = .true.
        brace_depth = count_braces(input_line)
        func_line_count = 0

        ! If the opening brace is on the same line, start capturing from next line
        ! Otherwise, this line might have the brace on next line
        if (index(input_line, '{') > 0) then
          ! Extract any commands after the opening brace on the same line
          call extract_first_line_body(input_line, func_body, func_line_count)
          if (brace_depth == 0) then
            ! Function complete on one line: name() { commands; }
            call add_function(shell, trim(func_name), func_body, func_line_count)
            in_function = .false.
            func_name = ''
            func_line_count = 0
          end if
        end if
        cycle
      end if

      ! If we're capturing a function, accumulate lines
      if (in_function) then
        ! Update brace depth
        brace_depth = brace_depth + count_braces(input_line)

        ! Check if this closes the function
        if (brace_depth <= 0) then
          ! Function definition complete - store it
          call add_function(shell, trim(func_name), func_body, func_line_count)
          in_function = .false.
          func_name = ''
          func_line_count = 0
          brace_depth = 0
        else
          ! Add this line to function body (skip the closing } line)
          if (func_line_count < 50 .and. trim(input_line) /= '}') then
            func_line_count = func_line_count + 1
            func_body(func_line_count) = trim(input_line)
          end if
        end if
        cycle
      end if

      ! Normal line processing (not in a function)
      ! Expand history if needed, then expand aliases
      ! NOTE: We do NOT add sourced file commands to history (only interactive commands)
      if (needs_history_expansion(input_line)) then
        history_expanded = expand_history(input_line)
        call expand_alias(shell, trim(history_expanded), expanded_line)
      else
        call expand_alias(shell, trim(input_line), expanded_line)
      end if

      ! Process substitutions <() and >() before parsing
      call process_substitutions(shell, expanded_line, proc_subst_line)

      ! Parse and execute (use new AST parser by default)
      if (shell%use_new_parser) then
        ! NEW PARSER PATH: Parse to AST and execute directly
        converted_line = convert_backticks_to_dollar_paren(proc_subst_line)
        ast_root => parse_command_line(converted_line)
        if (associated(ast_root)) then
          exit_code = execute_ast(ast_root, shell)
          shell%last_exit_status = exit_code
          call destroy_command_node(ast_root)
        else
          ! Parse error occurred
          shell%last_exit_status = 2
        end if
      else
        ! OLD PARSER PATH: Parse to pipeline and execute
        call parse_pipeline(proc_subst_line, pipeline)

        ! Check for syntax errors
        if (pipeline%parse_error) then
          shell%last_exit_status = 2  ! Syntax error
        else if (pipeline%num_commands > 0) then
          call execute_pipeline(pipeline, shell, expanded_line)

          ! Check if we need to replay loop body (only if NOT currently capturing)
          if (shell%control_depth == 0 .or. .not. shell%control_stack(shell%control_depth)%capturing_loop_body) then
            call replay_loop_if_needed(shell)
          end if

          ! Clean up pipeline
          if (allocated(pipeline%commands)) then
            do i = 1, pipeline%num_commands
              if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
              if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
              if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
              if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
              if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
              if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
              if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
            end do
            deallocate(pipeline%commands)
          end if
        end if
      end if

      ! Stop execution if exit command was encountered
      if (.not. shell%running) exit
    end do

    close(file_unit)
    shell%source_file = ''
  end subroutine

  ! Helper: Check if a line is a function definition and extract the name
  function is_function_definition(line, func_name) result(is_func)
    character(len=*), intent(in) :: line
    character(len=*), intent(out) :: func_name
    logical :: is_func
    integer :: paren_pos, brace_pos, func_pos, i
    character(len=1024) :: trimmed

    is_func = .false.
    func_name = ''
    trimmed = adjustl(line)

    ! Check for "function name" or "function name()" syntax
    if (index(trimmed, 'function ') == 1) then
      func_pos = 10  ! After "function "
      i = func_pos
      ! Extract function name
      do while (i <= len_trim(trimmed) .and. trimmed(i:i) /= ' ' .and. &
                trimmed(i:i) /= '(' .and. trimmed(i:i) /= '{')
        i = i + 1
      end do
      if (i > func_pos) then
        func_name = trimmed(func_pos:i-1)
        is_func = .true.
        return
      end if
    end if

    ! Check for "name()" syntax
    paren_pos = index(trimmed, '()')
    if (paren_pos > 1) then
      ! Extract name before ()
      i = 1
      do while (i < paren_pos .and. (is_alnum_underscore(trimmed(i:i))))
        i = i + 1
      end do
      if (i == paren_pos) then
        func_name = trimmed(1:paren_pos-1)
        is_func = .true.
        return
      end if
    end if
  end function

  ! Helper: Count net change in brace depth for a line
  function count_braces(line) result(depth_change)
    character(len=*), intent(in) :: line
    integer :: depth_change
    integer :: i

    depth_change = 0
    do i = 1, len_trim(line)
      if (line(i:i) == '{') then
        depth_change = depth_change + 1
      else if (line(i:i) == '}') then
        depth_change = depth_change - 1
      end if
    end do
  end function

  ! Helper: Check if character is alphanumeric or underscore
  function is_alnum_underscore(c) result(is_valid)
    character(len=1), intent(in) :: c
    logical :: is_valid

    is_valid = ((c >= 'a' .and. c <= 'z') .or. &
                (c >= 'A' .and. c <= 'Z') .or. &
                (c >= '0' .and. c <= '9') .or. &
                c == '_')
  end function

  ! Helper: Extract function body from first line (for one-liners)
  subroutine extract_first_line_body(line, func_body, count)
    character(len=*), intent(in) :: line
    character(len=1024), intent(inout) :: func_body(*)
    integer, intent(inout) :: count
    integer :: brace_pos, close_pos

    brace_pos = index(line, '{')
    if (brace_pos == 0) return

    close_pos = index(line(brace_pos+1:), '}')
    if (close_pos > 0) then
      ! One-liner: name() { commands }
      count = 1
      func_body(1) = trim(adjustl(line(brace_pos+1:brace_pos+close_pos-1)))
    else
      ! Multi-line but with content after {
      if (brace_pos < len_trim(line)) then
        count = 1
        func_body(1) = trim(adjustl(line(brace_pos+1:)))
      end if
    end if
  end subroutine

  subroutine initialize_shell(shell)
    type(shell_state_t), intent(out) :: shell
    character(len=:), allocatable :: temp
    character(kind=c_char), target :: c_hostname(256)
    character(len=256) :: arg
    integer :: ret, i, num_args

    ! Initialize allocatable arrays to avoid large stack allocation on macOS
    if (.not. allocated(shell%positional_params)) then
      allocate(shell%positional_params(50))
      shell%positional_params_capacity = 50
    end if
    if (.not. allocated(shell%local_vars)) then
      allocate(shell%local_vars(MAX_CONTROL_DEPTH, 20))
    end if
    if (.not. allocated(shell%local_var_counts)) then
      allocate(shell%local_var_counts(MAX_CONTROL_DEPTH))
      shell%local_var_counts = 0
    end if

    ! Detect if this is a login shell
    ! Check if argv[0] starts with '-' or if --login flag is present
    shell%is_login_shell = .false.
    num_args = command_argument_count()

    ! Check argv[0] (program name)
    if (num_args >= 0) then
      call get_command_argument(0, arg)
      ! If program name starts with '-', it's a login shell
      if (len_trim(arg) > 0 .and. arg(1:1) == '-') then
        shell%is_login_shell = .true.
      end if
    end if

    ! Check for --login flag
    do i = 1, num_args
      call get_command_argument(i, arg)
      if (trim(arg) == '--login' .or. trim(arg) == '-l') then
        shell%is_login_shell = .true.
        exit
      end if
    end do

    ! Get username
    temp = get_environment_var('USER')
    if (len(temp) > 0) then
      shell%username = temp
    else
      shell%username = 'user'
    end if

    ! Get hostname
    ret = c_gethostname(c_loc(c_hostname), 256_c_size_t)
    if (ret == 0) then
      shell%hostname = ''
      do i = 1, 256
        if (c_hostname(i) == c_null_char) exit
        shell%hostname(i:i) = c_hostname(i)
      end do
    else
      shell%hostname = 'localhost'
    end if

    ! Get current directory
    shell%cwd = get_current_directory()

    ! Check if shell is interactive
    shell%is_interactive = (c_isatty(STDIN_FD) /= 0)

    ! Setup job control if interactive
    if (shell%is_interactive) then
      shell%shell_pgid = c_getpid()
      ret = c_setpgid(shell%shell_pgid, shell%shell_pgid)
      shell%shell_terminal = STDIN_FD
      ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
    end if

    ! Initialize other fields
    shell%last_exit_status = 0
    shell%last_pid = 0
    shell%running = .true.
    shell%num_jobs = 0
    shell%next_job_id = 1

    ! Initialize history control variables
    temp = get_environment_var('HOME')
    if (len(temp) > 0) then
      shell%histfile = trim(temp) // '/.fortsh_history'
    else
      shell%histfile = ''
    end if
    shell%histsize = 1000
    shell%histfilesize = 2000
    shell%histcontrol = 'ignoredups'  ! Default: ignore duplicate consecutive commands

    ! Initialize shell options and special variables
    call initialize_shell_options(shell)

    ! Initialize special shell variables
    shell%uid = get_uid()
    shell%euid = get_euid()
    call system_clock(shell%shell_start_time)
    shell%oldpwd = ''
    shell%last_arg = ''
    shell%current_line_number = 0

    ! Initialize jobs array
    do i = 1, MAX_JOBS
      shell%jobs(i)%job_id = 0
    end do

    ! Initialize functions array
    do i = 1, size(shell%functions)
      shell%functions(i)%name = ''
      shell%functions(i)%body_lines = 0
    end do

    ! Initialize prompt string lengths (to match default values in shell_state_t)
    shell%ps1_len = len_trim(shell%ps1)  ! '\u@\h :: \w > ' = 17 chars
    shell%ps2_len = 2                    ! '> ' = 2 chars (don't trim trailing space)
    shell%ps3_len = 3                    ! '#? ' = 3 chars (don't trim trailing space)
    shell%ps4_len = 2                    ! '+ ' = 2 chars (don't trim trailing space)

    ! Check for performance monitoring environment variable
    temp = get_environment_var('FORTSH_PERF')
    if (len(temp) > 0 .and. trim(temp) == '1') then
      call set_performance_monitoring(.true.)
    end if

    ! New parser is now THE DEFAULT!
    ! Use FORTSH_USE_OLD_PARSER=1 to revert to old parser
    shell%use_new_parser = .true.

    ! Allow opt-out to old parser
    temp = get_environment_var('FORTSH_USE_OLD_PARSER')
    if (len(temp) > 0 .and. (trim(temp) == '1' .or. trim(temp) == 'true')) then
      shell%use_new_parser = .false.
      if (shell%is_interactive) then
        write(output_unit, '(a)') 'Using legacy parser (new parser is default)'
      end if
    end if
  end subroutine

  subroutine execute_trap_for_signal(shell, signum)
    use grammar_parser, only: parse_command_line
    use ast_executor, only: execute_ast_node
    use command_tree, only: command_node_t, destroy_command_node
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: signum
    character(len=4096) :: trap_command
    type(pipeline_t) :: trap_pipeline
    type(command_node_t), pointer :: trap_ast
    integer :: saved_exit_status, i, trap_exit_code

    ! Get the trap command for this signal
    trap_command = get_trap_command(shell, signum)

    if (len_trim(trap_command) == 0) return

    ! Save current exit status (trap should not affect $?)
    saved_exit_status = shell%last_exit_status

    ! Don't execute trap if we're already in one
    if (shell%executing_trap) return

    ! Don't execute EXIT trap if it was already executed by builtin_exit
    if (signum == 0 .and. shell%exit_trap_executed) return

    ! Set flag to prevent recursive trap execution
    shell%executing_trap = .true.

    ! Mark EXIT trap as executed if this is an EXIT trap
    if (signum == 0) shell%exit_trap_executed = .true.

    ! Parse the trap command (use new parser if feature flag is enabled)
    if (shell%use_new_parser) then
      ! Use AST parser for new parser mode
      trap_ast => parse_command_line(trim(trap_command))
      if (associated(trap_ast)) then
        trap_exit_code = execute_ast_node(trap_ast, shell)
        call destroy_command_node(trap_ast)
      else
        ! Parse error occurred in trap command
        shell%last_exit_status = 2
      end if
    else
      call parse_pipeline(trim(trap_command), trap_pipeline)

      ! Check for syntax errors
      if (trap_pipeline%parse_error) then
        shell%last_exit_status = 2  ! Syntax error
      else if (trap_pipeline%num_commands > 0) then
        call execute_pipeline(trap_pipeline, shell, trim(trap_command))
      end if

      ! Clean up pipeline
      if (allocated(trap_pipeline%commands)) then
        do i = 1, trap_pipeline%num_commands
          if (allocated(trap_pipeline%commands(i)%tokens)) deallocate(trap_pipeline%commands(i)%tokens)
          if (allocated(trap_pipeline%commands(i)%input_file)) deallocate(trap_pipeline%commands(i)%input_file)
          if (allocated(trap_pipeline%commands(i)%output_file)) deallocate(trap_pipeline%commands(i)%output_file)
          if (allocated(trap_pipeline%commands(i)%error_file)) deallocate(trap_pipeline%commands(i)%error_file)
          if (allocated(trap_pipeline%commands(i)%heredoc_delimiter)) deallocate(trap_pipeline%commands(i)%heredoc_delimiter)
          if (allocated(trap_pipeline%commands(i)%heredoc_content)) deallocate(trap_pipeline%commands(i)%heredoc_content)
          if (allocated(trap_pipeline%commands(i)%here_string)) deallocate(trap_pipeline%commands(i)%here_string)
        end do
        deallocate(trap_pipeline%commands)
      end if
    end if

    ! Clear flag
    shell%executing_trap = .false.

    ! Restore exit status
    shell%last_exit_status = saved_exit_status
  end subroutine

end program fortran_shell