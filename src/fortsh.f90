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
  character(len=1024) :: input_line
  character(len=:), allocatable :: expanded_line, prompt_str
  integer :: iostat, i

  ! Initialize performance monitoring
  call init_performance_monitoring()

  ! Initialize shell state (detects login shell from arguments)
  call initialize_shell(shell)

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
      ! Expand prompt with escape sequences
      prompt_str = expand_prompt(shell%ps1, shell)
      call readline_enhanced(prompt_str, input_line, iostat)
    else
      read(input_unit, '(a)', iostat=iostat) input_line
      ! Add to history in non-interactive mode too
      if (iostat == 0 .and. len_trim(input_line) > 0) then
        call add_to_history(input_line)
      end if
    end if

    ! Check for EOF (Ctrl-D)
    if (iostat /= 0) then
      write(output_unit, '(a)') ''
      exit
    end if

    ! Skip empty lines
    if (len_trim(input_line) == 0) cycle

    ! Expand aliases
    call expand_alias(shell, trim(input_line), expanded_line)

    ! Parse pipeline
    call parse_pipeline(expanded_line, pipeline)

    ! Execute pipeline
    if (pipeline%num_commands > 0) then
      call execute_pipeline(pipeline, shell, expanded_line)

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

  write(output_unit, '(a)') 'Goodbye!'

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
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: input_line
    integer :: file_unit, iostat, i
    type(pipeline_t) :: pipeline
    character(len=:), allocatable :: expanded_line

    ! Reset the source flag first
    shell%should_source = .false.

    ! Open file for reading
    open(newunit=file_unit, file=trim(shell%source_file), status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'source: failed to open ' // trim(shell%source_file)
      shell%last_exit_status = 1
      return
    end if

    ! Execute each line in the file
    do
      read(file_unit, '(a)', iostat=iostat) input_line
      if (iostat /= 0) exit  ! End of file or error

      ! Skip empty lines and comments
      if (len_trim(input_line) == 0 .or. input_line(1:1) == '#') cycle

      ! Add to history
      call add_to_history(input_line)

      ! Expand aliases
      call expand_alias(shell, trim(input_line), expanded_line)

      ! Parse and execute pipeline
      call parse_pipeline(expanded_line, pipeline)

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