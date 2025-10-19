! ==============================================================================
! Main Program: Fortran Shell (Fortsh)
! ==============================================================================
program fortran_shell
  use shell_types
  use system_interface
  use signal_handler
  use signal_handling
  use parser
  use executor
  use job_control
  use readline
  use shell_config
  use aliases
  use shell_options
  use performance
  use prompt_formatting
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  type(shell_state_t) :: shell
  type(pipeline_t) :: pipeline
  character(len=1024) :: input_line, proc_subst_line
  character(len=:), allocatable :: expanded_line, prompt_str, history_expanded
  integer :: iostat, i, num_args
  character(len=1024) :: arg1, command_string
  logical :: execute_command_string, execute_script_file
  character(len=:), allocatable :: script_file
  ! Command duration tracking
  integer :: cmd_start_time, cmd_end_time, cmd_duration_ms, clock_rate
  real :: cmd_duration_sec

  ! Initialize performance monitoring
  call init_performance_monitoring()

  ! Initialize shell state (detects login shell from arguments)
  call initialize_shell(shell)

  ! Initialize control flow callbacks (breaks circular dependency)
  call init_control_flow_callbacks()

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
    call process_substitutions(shell, trim(command_string), proc_subst_line)
    call parse_pipeline(proc_subst_line, pipeline)

    if (pipeline%num_commands > 0) then
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
#ifdef __APPLE__
      ! WORKAROUND: On macOS ARM64, gfortran has a bug with large stack-allocated
      ! derived types that causes segfaults. Until this is fixed, we bypass
      ! readline_enhanced and expand_prompt, using simple prompts instead.
      ! This means no command history, line editing, or tab completion on macOS.
      prompt_str = '$ '
      write(output_unit, '(a)', advance='no') prompt_str
      flush(output_unit)
      read(input_unit, '(a)', iostat=iostat) input_line
#else
      ! Full readline with prompt expansion on other platforms
      prompt_str = expand_prompt(shell%ps1, shell, shell%ps1_len)
      call readline_enhanced(prompt_str, input_line, iostat)
#endif
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
#ifdef __APPLE__
        ! WORKAROUND: Simple PS2 prompt for macOS (see main loop for details)
        prompt_str = '> '
        write(output_unit, '(a)', advance='no') prompt_str
        flush(output_unit)
        read(input_unit, '(a)', iostat=iostat) proc_subst_line
#else
        ! Full readline with PS2 prompt expansion
        prompt_str = expand_prompt(shell%ps2, shell, shell%ps2_len)
        call readline_enhanced(prompt_str, proc_subst_line, iostat)
#endif
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

    ! Parse pipeline
    call parse_pipeline(proc_subst_line, pipeline)

    ! Execute pipeline
    if (pipeline%num_commands > 0) then
      ! Track command duration (Fish-style)
      call system_clock(cmd_start_time, clock_rate)

      call execute_pipeline(pipeline, shell, expanded_line)

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
  end do

  ! Execute EXIT trap if one is set
  call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT

  ! Save command history to file (if histfile is set)
  if (len_trim(shell%histfile) > 0 .and. get_history_count() > 0) then
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

contains

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
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: input_line, proc_subst_line, continuation_line
    integer :: file_unit, iostat, i, brace_depth, func_line_count
    type(pipeline_t) :: pipeline
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
      if (needs_history_expansion(input_line)) then
        history_expanded = expand_history(input_line)
        call add_to_history(history_expanded)
        call expand_alias(shell, trim(history_expanded), expanded_line)
      else
        call add_to_history(input_line)
        call expand_alias(shell, trim(input_line), expanded_line)
      end if

      ! Process substitutions <() and >() before parsing
      call process_substitutions(shell, expanded_line, proc_subst_line)

      ! Parse and execute pipeline
      call parse_pipeline(proc_subst_line, pipeline)

      if (pipeline%num_commands > 0) then
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
    shell%ps2_len = len_trim(shell%ps2)  ! '> ' = 2 chars
    shell%ps3_len = len_trim(shell%ps3)  ! '#? ' = 3 chars
    shell%ps4_len = len_trim(shell%ps4)  ! '+ ' = 2 chars

    ! Check for performance monitoring environment variable
    temp = get_environment_var('FORTSH_PERF')
    if (len(temp) > 0 .and. trim(temp) == '1') then
      call set_performance_monitoring(.true.)
    end if
  end subroutine

  subroutine execute_trap_for_signal(shell, signum)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: signum
    character(len=4096) :: trap_command
    type(pipeline_t) :: trap_pipeline
    integer :: saved_exit_status, i

    ! Get the trap command for this signal
    trap_command = get_trap_command(shell, signum)

    if (len_trim(trap_command) == 0) return

    ! Save current exit status (trap should not affect $?)
    saved_exit_status = shell%last_exit_status

    ! Parse the trap command
    call parse_pipeline(trim(trap_command), trap_pipeline)

    ! Execute the trap command if parsing succeeded
    if (trap_pipeline%num_commands > 0) then
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

    ! Restore exit status
    shell%last_exit_status = saved_exit_status
  end subroutine

end program fortran_shell