! ==============================================================================
! Main Program: Fortran Shell (Fortsh)
! ==============================================================================
program fortran_shell
  use shell_types
  use system_interface
  use signal_handler
  use parser
  use executor
  use job_control
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  type(shell_state_t) :: shell
  type(pipeline_t) :: pipeline
  character(len=1024) :: input_line
  integer :: iostat, i

  ! Initialize shell state
  call initialize_shell(shell)

  ! Setup signal handlers if interactive
  if (shell%is_interactive) then
    call setup_signal_handlers()
  end if

  ! Main REPL loop
  do while (shell%running)
    ! Update job status
    if (shell%is_interactive) then
      call update_job_status(shell)
      call notify_job_status(shell)
    end if

    ! Print prompt
    write(output_unit, '(a,a,a,a,a)', advance='no') &
      trim(shell%username), '@', trim(shell%hostname), ' :: '
    flush(output_unit)

    ! Read input
    read(input_unit, '(a)', iostat=iostat) input_line

    ! Check for EOF (Ctrl-D)
    if (iostat /= 0) then
      write(output_unit, '(a)') ''
      exit
    end if

    ! Skip empty lines
    if (len_trim(input_line) == 0) cycle

    ! Parse pipeline
    call parse_pipeline(trim(input_line), pipeline)

    ! Execute pipeline
    if (pipeline%num_commands > 0) then
      call execute_pipeline(pipeline, shell, trim(input_line))
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
      end do
      deallocate(pipeline%commands)
    end if
  end do

  write(output_unit, '(a)') 'Goodbye!'

contains

  subroutine initialize_shell(shell)
    type(shell_state_t), intent(out) :: shell
    character(len=:), allocatable :: temp
    character(kind=c_char), target :: c_hostname(256)
    integer :: ret, i

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

    ! Initialize jobs array
    do i = 1, MAX_JOBS
      shell%jobs(i)%job_id = 0
    end do
  end subroutine

end program fortran_shell