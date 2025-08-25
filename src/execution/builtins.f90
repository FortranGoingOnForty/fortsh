! ==============================================================================
! Module: builtins (Extended with job control)
! ==============================================================================
module builtins
  use shell_types
  use system_interface
  use job_control
  use test_builtin
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  function is_builtin(cmd_name) result(is_built)
    character(len=*), intent(in) :: cmd_name
    logical :: is_built
    
    is_built = (trim(cmd_name) == 'exit' .or. &
                trim(cmd_name) == 'cd' .or. &
                trim(cmd_name) == 'pwd' .or. &
                trim(cmd_name) == 'export' .or. &
                trim(cmd_name) == 'echo' .or. &
                trim(cmd_name) == 'jobs' .or. &
                trim(cmd_name) == 'fg' .or. &
                trim(cmd_name) == 'bg' .or. &
                trim(cmd_name) == 'source' .or. &
                trim(cmd_name) == '.' .or. &
                is_test_command(cmd_name))
  end function

  subroutine execute_builtin(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    select case(trim(cmd%tokens(1)))
    case('exit')
      call builtin_exit(cmd, shell)
    case('cd')
      call builtin_cd(cmd, shell)
    case('pwd')
      call builtin_pwd(cmd, shell)
    case('export')
      call builtin_export(cmd, shell)
    case('echo')
      call builtin_echo(cmd, shell)
    case('jobs')
      call builtin_jobs(cmd, shell)
    case('fg')
      call builtin_fg(cmd, shell)
    case('bg')
      call builtin_bg(cmd, shell)
    case('source', '.')
      call builtin_source(cmd, shell)
    case('test', '[', '[[')
      call execute_test_command(cmd, shell)
    case default
      ! Should not reach here if is_builtin works correctly
      shell%last_exit_status = 1
    end select
  end subroutine

  subroutine builtin_exit(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    shell%running = .false.
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=shell%last_exit_status) shell%last_exit_status
    end if
  end subroutine

  subroutine builtin_cd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: target_dir
    
    if (cmd%num_tokens == 1) then
      target_dir = get_environment_var('HOME')
    else
      target_dir = trim(cmd%tokens(2))
    end if
    
    if (change_directory(target_dir)) then
      shell%cwd = get_current_directory()
      shell%last_exit_status = 0
    else
      write(error_unit, '(3a)') 'cd: ', trim(target_dir), ': No such file or directory'
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine builtin_pwd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    write(output_unit, '(a)') trim(shell%cwd)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_export(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'export: usage: export VAR=value'
      shell%last_exit_status = 1
      return
    end if
    
    eq_pos = index(cmd%tokens(2), '=')
    if (eq_pos > 0) then
      var_name = cmd%tokens(2)(:eq_pos-1)
      var_value = cmd%tokens(2)(eq_pos+1:)
      
      if (set_environment_var(trim(var_name), trim(var_value))) then
        shell%last_exit_status = 0
      else
        write(error_unit, '(a)') 'export: failed to set variable'
        shell%last_exit_status = 1
      end if
    else
      write(error_unit, '(a)') 'export: usage: export VAR=value'
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine builtin_echo(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    logical :: first
    
    ! Simple echo implementation
    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens < 1) then
      write(*,'(a)') ''
      shell%last_exit_status = 0
      return
    end if
    
    first = .true.
    do i = 2, cmd%num_tokens
      if (.not. first) write(*,'(a)',advance='no') ' '
      write(*,'(a)',advance='no') trim(cmd%tokens(i))
      first = .false.
    end do
    write(*,'(a)') ''
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_jobs(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    character(len=20) :: status_str
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0) then
        select case(shell%jobs(i)%state)
        case(JOB_RUNNING)
          status_str = 'Running'
        case(JOB_STOPPED)
          status_str = 'Stopped'
        case(JOB_DONE)
          status_str = 'Done'
        end select
        
        write(output_unit, '(a,i0,a,a,a,a)') '[', shell%jobs(i)%job_id, ']  ', &
              status_str, '                 ', trim(shell%jobs(i)%command_line)
      end if
    end do
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_fg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, iostat, i
    
    if (cmd%num_tokens < 2) then
      ! Bring most recent job to foreground
      job_id = 0
      do i = MAX_JOBS, 1, -1
        if (shell%jobs(i)%job_id > 0) then
          job_id = shell%jobs(i)%job_id
          exit
        end if
      end do
      
      if (job_id == 0) then
        write(error_unit, '(a)') 'fg: no current job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job number (handle %n syntax)
      if (cmd%tokens(2)(1:1) == '%') then
        read(cmd%tokens(2)(2:), *, iostat=iostat) job_id
      else
        read(cmd%tokens(2), *, iostat=iostat) job_id
      end if
      
      if (iostat /= 0) then
        write(error_unit, '(a)') 'fg: invalid job id'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    call put_job_foreground(shell, job_id, .true.)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_bg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, iostat, i
    
    if (cmd%num_tokens < 2) then
      ! Continue most recent stopped job in background
      job_id = 0
      do i = MAX_JOBS, 1, -1
        if (shell%jobs(i)%job_id > 0 .and. &
            shell%jobs(i)%state == JOB_STOPPED) then
          job_id = shell%jobs(i)%job_id
          exit
        end if
      end do
      
      if (job_id == 0) then
        write(error_unit, '(a)') 'bg: no stopped job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job number (handle %n syntax)
      if (cmd%tokens(2)(1:1) == '%') then
        read(cmd%tokens(2)(2:), *, iostat=iostat) job_id
      else
        read(cmd%tokens(2), *, iostat=iostat) job_id
      end if
      
      if (iostat /= 0) then
        write(error_unit, '(a)') 'bg: invalid job id'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    call put_job_background(shell, job_id, .true.)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_source(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    ! Simplified version - would need file reading implementation
    write(error_unit, '(a)') 'source: not yet implemented'
    shell%last_exit_status = 1
  end subroutine

end module builtins