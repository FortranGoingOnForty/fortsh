! ==============================================================================
! Module: job_control
! Purpose: Job control management
! ==============================================================================
module job_control
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  function add_job(shell, pgid, command_line, foreground) result(job_id)
    type(shell_state_t), intent(inout) :: shell
    integer(c_pid_t), intent(in) :: pgid
    character(len=*), intent(in) :: command_line
    logical, intent(in) :: foreground
    integer :: job_id

    integer :: i

    ! Find empty slot or add new job
    job_id = 0
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == 0) then
        job_id = shell%next_job_id
        shell%next_job_id = shell%next_job_id + 1
        shell%jobs(i)%job_id = job_id
        shell%jobs(i)%pgid = pgid
        shell%jobs(i)%command_line = command_line
        shell%jobs(i)%state = JOB_RUNNING
        shell%jobs(i)%foreground = foreground
        shell%jobs(i)%notified = .false.
        allocate(shell%jobs(i)%pids(1))
        shell%jobs(i)%pids(1) = pgid
        shell%jobs(i)%num_pids = 1

        ! Update current/previous job tracking
        if (shell%current_job_id /= 0) then
          shell%previous_job_id = shell%current_job_id
        end if
        shell%current_job_id = job_id

        exit
      end if
    end do

    if (job_id > 0) shell%num_jobs = shell%num_jobs + 1
  end function

  subroutine remove_job(shell, job_id)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    integer :: i
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        if (allocated(shell%jobs(i)%pids)) deallocate(shell%jobs(i)%pids)
        shell%jobs(i)%job_id = 0
        shell%num_jobs = shell%num_jobs - 1
        exit
      end if
    end do
  end subroutine

  subroutine update_job_status(shell)
    use iso_fortran_env, only: error_unit
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j
    integer(c_int), target :: status
    integer(c_pid_t) :: pid

    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0) then
        do j = 1, shell%jobs(i)%num_pids
          pid = c_waitpid(shell%jobs(i)%pids(j), c_loc(status), WNOHANG + WUNTRACED)

          if (pid > 0) then
            if (WIFEXITED(status)) then
              shell%jobs(i)%state = JOB_DONE
              ! DON'T set last_exit_status for background jobs!
            else if (WIFSIGNALED(status)) then
              shell%jobs(i)%state = JOB_DONE
              ! DON'T set last_exit_status for background jobs!
            else if (WIFSTOPPED(status)) then
              shell%jobs(i)%state = JOB_STOPPED
            end if
          end if
        end do
      end if
    end do
  end subroutine

  subroutine notify_job_status(shell)
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0 .and. .not. shell%jobs(i)%notified) then
        if (shell%jobs(i)%state == JOB_DONE) then
          write(output_unit, '(a,i0,a,a)') '[', shell%jobs(i)%job_id, ']  Done                    ', &
                trim(shell%jobs(i)%command_line)
          shell%jobs(i)%notified = .true.
          call remove_job(shell, shell%jobs(i)%job_id)
        else if (shell%jobs(i)%state == JOB_STOPPED) then
          write(output_unit, '(a,i0,a,a)') '[', shell%jobs(i)%job_id, ']  Stopped                 ', &
                trim(shell%jobs(i)%command_line)
          shell%jobs(i)%notified = .true.
        end if
      end if
    end do
  end subroutine

  subroutine put_job_foreground(shell, job_id, cont)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    logical, intent(in) :: cont
    
    integer :: i, ret
    integer(c_int), target :: status
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        ! Give terminal to job
        ret = c_tcsetpgrp(shell%shell_terminal, shell%jobs(i)%pgid)
        
        ! Continue job if necessary
        if (cont .and. shell%jobs(i)%state == JOB_STOPPED) then
          ret = c_kill(-shell%jobs(i)%pgid, SIGCONT)
          shell%jobs(i)%state = JOB_RUNNING
        end if
        
        ! Wait for job
        shell%jobs(i)%foreground = .true.
        ret = c_waitpid(-shell%jobs(i)%pgid, c_loc(status), WUNTRACED)
        
        ! Take back terminal
        ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
        
        ! Update status
        if (WIFEXITED(status)) then
          shell%jobs(i)%state = JOB_DONE
          shell%last_exit_status = WEXITSTATUS(status)
          call remove_job(shell, job_id)
        else if (WIFSIGNALED(status)) then
          shell%jobs(i)%state = JOB_DONE
          shell%last_exit_status = 128 + WTERMSIG(status)
          call remove_job(shell, job_id)
        else if (WIFSTOPPED(status)) then
          shell%jobs(i)%state = JOB_STOPPED
          write(output_unit, '(a)') 'Stopped'
        end if
        
        exit
      end if
    end do
  end subroutine

  subroutine put_job_background(shell, job_id, cont)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    logical, intent(in) :: cont
    
    integer :: i, ret
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        shell%jobs(i)%foreground = .false.
        
        if (cont .and. shell%jobs(i)%state == JOB_STOPPED) then
          ret = c_kill(-shell%jobs(i)%pgid, SIGCONT)
          shell%jobs(i)%state = JOB_RUNNING
        end if
        
        exit
      end if
    end do
  end subroutine

  ! Enhanced job control functions
  function find_job_by_id(shell, job_id) result(job_index)
    type(shell_state_t), intent(in) :: shell
    integer, intent(in) :: job_id
    integer :: job_index
    integer :: i
    
    job_index = 0
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        job_index = i
        return
      end if
    end do
  end function

  function find_job_by_pgid(shell, pgid) result(job_index)
    type(shell_state_t), intent(in) :: shell
    integer(c_pid_t), intent(in) :: pgid
    integer :: job_index
    integer :: i
    
    job_index = 0
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%pgid == pgid .and. shell%jobs(i)%job_id > 0) then
        job_index = i
        return
      end if
    end do
  end function

  function find_job_pgid(shell, job_id) result(pgid)
    type(shell_state_t), intent(in) :: shell
    integer, intent(in) :: job_id
    integer(c_pid_t) :: pgid
    integer :: job_index
    
    job_index = find_job_by_id(shell, job_id)
    if (job_index > 0) then
      pgid = shell%jobs(job_index)%pgid
    else
      pgid = 0
    end if
  end function

  subroutine suspend_job(shell, job_id)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    integer :: job_index
    integer :: ret

    job_index = find_job_by_id(shell, job_id)
    if (job_index == 0) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' not found'
      shell%last_exit_status = 1
      return
    end if

    if (shell%jobs(job_index)%state == JOB_STOPPED) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' already stopped'
      return
    end if

    ! Send SIGTSTP to the process group
    ret = c_kill(-shell%jobs(job_index)%pgid, SIGTSTP)
    if (ret == 0) then
      shell%jobs(job_index)%state = JOB_STOPPED

      ! Update current/previous job tracking
      if (shell%current_job_id /= job_id) then
        shell%previous_job_id = shell%current_job_id
      end if
      shell%current_job_id = job_id

      write(output_unit, '(a,i15,a)') '[', job_id, '] Suspended'
    else
      write(error_unit, '(a,i15)') 'Failed to suspend job ', job_id
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine resume_job_bg(shell, job_id)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    integer :: job_index
    integer :: ret

    job_index = find_job_by_id(shell, job_id)
    if (job_index == 0) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' not found'
      shell%last_exit_status = 1
      return
    end if

    if (shell%jobs(job_index)%state /= JOB_STOPPED) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' is not stopped'
      return
    end if

    ! Send SIGCONT to the process group
    ret = c_kill(-shell%jobs(job_index)%pgid, SIGCONT)
    if (ret == 0) then
      shell%jobs(job_index)%state = JOB_RUNNING
      shell%jobs(job_index)%foreground = .false.
      shell%jobs(job_index)%notified = .false.

      ! Update current/previous job tracking
      if (shell%current_job_id /= job_id) then
        shell%previous_job_id = shell%current_job_id
      end if
      shell%current_job_id = job_id

      write(output_unit, '(a,i15,a,a)') '[', job_id, '] ', trim(shell%jobs(job_index)%command_line), ' &'
    else
      write(error_unit, '(a,i15)') 'Failed to resume job in background ', job_id
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine resume_job_fg(shell, job_id)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    integer :: job_index
    integer :: ret
    integer(c_int), target :: status

    job_index = find_job_by_id(shell, job_id)
    if (job_index == 0) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' not found'
      shell%last_exit_status = 1
      return
    end if

    if (shell%jobs(job_index)%state /= JOB_STOPPED) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' is not stopped'
      return
    end if

    ! Update current/previous job tracking before resuming
    if (shell%current_job_id /= job_id) then
      shell%previous_job_id = shell%current_job_id
    end if
    shell%current_job_id = job_id

    ! Give terminal control to job
    if (shell%is_interactive) then
      ret = c_tcsetpgrp(shell%shell_terminal, shell%jobs(job_index)%pgid)
    end if

    ! Send SIGCONT to the process group
    ret = c_kill(-shell%jobs(job_index)%pgid, SIGCONT)
    if (ret == 0) then
      shell%jobs(job_index)%state = JOB_RUNNING
      shell%jobs(job_index)%foreground = .true.
      shell%jobs(job_index)%notified = .false.
      write(output_unit, '(a)') trim(shell%jobs(job_index)%command_line)

      ! Wait for job to complete or stop
      ret = c_waitpid(-shell%jobs(job_index)%pgid, c_loc(status), WUNTRACED)

      ! Take back terminal control
      if (shell%is_interactive) then
        ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
      end if

      if (WIFEXITED(status)) then
        shell%jobs(job_index)%state = JOB_DONE
        shell%last_exit_status = WEXITSTATUS(status)
        call remove_job(shell, job_id)
      else if (WIFSIGNALED(status)) then
        shell%jobs(job_index)%state = JOB_DONE
        shell%last_exit_status = 128 + WTERMSIG(status)
        call remove_job(shell, job_id)
      else if (WIFSTOPPED(status)) then
        shell%jobs(job_index)%state = JOB_STOPPED
        shell%jobs(job_index)%foreground = .false.
        write(output_unit, '(a)') 'Stopped'
      end if
    else
      write(error_unit, '(a,i15)') 'Failed to resume job in foreground ', job_id
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine kill_job(shell, job_id, signal_num)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    integer, intent(in), optional :: signal_num
    integer :: job_index
    integer :: ret, sig
    
    job_index = find_job_by_id(shell, job_id)
    if (job_index == 0) then
      write(error_unit, '(a,i15,a)') 'Job ', job_id, ' not found'
      shell%last_exit_status = 1
      return
    end if
    
    sig = 15  ! Default signal: SIGTERM
    if (present(signal_num)) sig = signal_num
    
    ! Send signal to the process group
    ret = c_kill(-shell%jobs(job_index)%pgid, sig)
    if (ret == 0) then
      if (sig == 9 .or. sig == 15) then  ! SIGKILL or SIGTERM
        shell%jobs(job_index)%state = JOB_DONE
        call remove_job(shell, job_id)
      end if
      write(output_unit, '(a,i15,a)') '[', job_id, '] Terminated'
    else
      write(error_unit, '(a,i15)') 'Failed to kill job ', job_id
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine list_jobs(shell, show_pids)
    type(shell_state_t), intent(in) :: shell
    logical, intent(in), optional :: show_pids
    logical :: show_pid_info
    integer :: i
    character(len=16) :: state_str
    
    show_pid_info = .false.
    if (present(show_pids)) show_pid_info = show_pids
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0) then
        select case(shell%jobs(i)%state)
        case(JOB_RUNNING)
          if (shell%jobs(i)%foreground) then
            state_str = 'Running'
          else
            state_str = 'Running'
          end if
        case(JOB_STOPPED)
          state_str = 'Stopped'
        case(JOB_DONE)
          state_str = 'Done'
        end select
        
        block
          character(len=1) :: cur_mark
          character(len=256) :: cmd_display
          ! + for current job, - for previous, space otherwise
          if (shell%jobs(i)%job_id == &
              shell%current_job_id) then
            cur_mark = '+'
          else if (shell%jobs(i)%job_id == &
              shell%previous_job_id) then
            cur_mark = '-'
          else
            cur_mark = ' '
          end if
          ! Add trailing & for background running jobs
          cmd_display = trim(shell%jobs(i)%command_line)
          if (shell%jobs(i)%state == JOB_RUNNING .and. &
              .not. shell%jobs(i)%foreground) then
            cmd_display = trim(cmd_display) // ' &'
          end if
          if (show_pid_info) then
            write(output_unit, '(i0)') shell%jobs(i)%pgid
          else
            write(output_unit, '(a,i0,a,a,2x,a,a,a)') &
              '[', shell%jobs(i)%job_id, ']', cur_mark, &
              trim(state_str), &
              repeat(' ', max(1, &
                24 - len_trim(state_str))), &
              trim(cmd_display)
          end if
        end block
      end if
    end do
  end subroutine

end module job_control