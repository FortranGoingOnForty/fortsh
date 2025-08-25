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
              shell%last_exit_status = WEXITSTATUS(status)
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

end module job_control