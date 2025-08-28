! ==============================================================================
! Module: executor (Extended with job control)
! ==============================================================================
module executor
  use shell_types
  use system_interface
  use builtins
  use parser
  use job_control
  use variables
  use control_flow
  use error_handling
  use performance
  use shell_options
  use iso_fortran_env, only: error_unit, input_unit
  use iso_c_binding
  implicit none

contains

  subroutine execute_pipeline(pipeline, shell, original_input)
    type(pipeline_t), intent(inout) :: pipeline
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    integer :: i
    logical :: should_continue
    
    should_continue = .true.
    i = 1
    
    do while (i <= pipeline%num_commands .and. should_continue)
      select case(pipeline%commands(i)%separator)
      case(SEP_PIPE)
        call execute_pipe_chain(pipeline, i, shell, original_input)
        call check_errexit(shell, shell%last_exit_status)
        do while (i <= pipeline%num_commands)
          if (pipeline%commands(i)%separator /= SEP_PIPE) exit
          i = i + 1
        end do
        
      case(SEP_SEMICOLON, SEP_NONE)
        call execute_single(pipeline%commands(i), shell, original_input)
        call check_errexit(shell, shell%last_exit_status)
        i = i + 1
        
      case(SEP_AND)
        call execute_single(pipeline%commands(i), shell, original_input)
        should_continue = (shell%last_exit_status == 0)
        call check_errexit(shell, shell%last_exit_status)
        i = i + 1
        
      case(SEP_OR)
        call execute_single(pipeline%commands(i), shell, original_input)
        should_continue = (shell%last_exit_status /= 0)
        call check_errexit(shell, shell%last_exit_status)
        i = i + 1
      end select
    end do
  end subroutine

  subroutine execute_pipe_chain(pipeline, start_idx, shell, original_input)
    type(pipeline_t), intent(inout) :: pipeline
    integer, intent(in) :: start_idx
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    integer :: i, j, pipe_count, end_idx
    integer(c_int), allocatable :: pipefd(:,:)
    integer(c_pid_t), allocatable :: pids(:)
    integer(c_pid_t) :: pgid
    integer(c_int), target :: status
    integer :: ret, job_id
    logical :: foreground
    type(c_funptr) :: old_handler
    
    ! Count pipes in chain
    pipe_count = 0
    end_idx = start_idx
    do i = start_idx, pipeline%num_commands - 1
      if (pipeline%commands(i)%separator == SEP_PIPE) then
        pipe_count = pipe_count + 1
        end_idx = i + 1
      else
        exit
      end if
    end do
    
    if (pipe_count == 0) then
      call execute_single(pipeline%commands(start_idx), shell, original_input)
      return
    end if
    
    foreground = .not. pipeline%commands(end_idx)%background
    
    allocate(pipefd(2, pipe_count))
    allocate(pids(pipe_count + 1))
    
    ! Create all pipes
    do i = 1, pipe_count
      if (.not. create_pipe(pipefd(1,i), pipefd(2,i))) then
        write(error_unit, '(a)') 'Error: Failed to create pipe'
        shell%last_exit_status = 1
        return
      end if
    end do
    
    pgid = 0
    
    ! Fork all processes
    do i = start_idx, end_idx
      pids(i - start_idx + 1) = c_fork()
      
      if (pids(i - start_idx + 1) == 0) then
        ! Child process
        
        ! Set process group
        if (pgid == 0) pgid = c_getpid()
        ret = c_setpgid(0, pgid)
        
        ! Reset signal handlers
        SIG_DFL = c_null_funptr
        old_handler = c_signal(SIGINT, SIG_DFL)
        old_handler = c_signal(SIGTSTP, SIG_DFL)
        old_handler = c_signal(SIGTTIN, SIG_DFL)
        old_handler = c_signal(SIGTTOU, SIG_DFL)
        
        ! Set up pipes
        if (i > start_idx) then
          ret = c_dup2(pipefd(1, i - start_idx), STDIN_FD)
        end if
        
        if (i < end_idx) then
          ret = c_dup2(pipefd(2, i - start_idx + 1), STDOUT_FD)
        end if
        
        ! Close all pipe FDs
        do j = 1, pipe_count
          ret = c_close(pipefd(1, j))
          ret = c_close(pipefd(2, j))
        end do
        
        ! Handle here document
        call handle_heredoc(pipeline%commands(i))
        
        ! Expand variables and execute
        call expand_tokens(pipeline%commands(i), shell)
        
        ! Expand glob patterns
        call expand_command_globs(pipeline%commands(i))
        
        if (is_builtin(pipeline%commands(i)%tokens(1))) then
          call execute_builtin(pipeline%commands(i), shell)
          call c_exit(int(shell%last_exit_status, c_int))
        else
          call setup_redirections(pipeline%commands(i))
          call exec_child(pipeline%commands(i)%tokens, pipeline%commands(i)%num_tokens)
          call c_exit(127)
        end if
      else if (pids(i - start_idx + 1) > 0) then
        ! Parent: set process group
        if (pgid == 0) pgid = pids(1)
        ret = c_setpgid(pids(i - start_idx + 1), pgid)
      end if
    end do
    
    ! Parent: close all pipes
    do i = 1, pipe_count
      ret = c_close(pipefd(1, i))
      ret = c_close(pipefd(2, i))
    end do
    
    ! Add job to job list
    if (.not. foreground) then
      job_id = add_job(shell, pgid, original_input, .false.)
      write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pgid
      shell%last_pid = pgid
    else if (shell%is_interactive) then
      ! Give terminal to job
      ret = c_tcsetpgrp(shell%shell_terminal, pgid)
    end if
    
    ! Wait for all children (if foreground)
    if (foreground) then
      call wait_for_pipeline(shell, pids, pipe_count + 1)
      
      ! Take back terminal
      if (shell%is_interactive) then
        ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
      end if
    end if
    
    deallocate(pipefd)
    deallocate(pids)
  end subroutine

  ! Wait for pipeline processes with POSIX-compliant exit status handling
  subroutine wait_for_pipeline(shell, pids, num_processes)
    type(shell_state_t), intent(inout) :: shell
    integer(c_pid_t), intent(in) :: pids(:)
    integer, intent(in) :: num_processes
    
    integer(c_int), target :: status
    integer :: i, ret, final_exit_status, first_failure
    integer, allocatable :: exit_statuses(:)
    
    allocate(exit_statuses(num_processes))
    final_exit_status = 0
    first_failure = 0
    
    ! Wait for all processes and collect their exit statuses
    do i = 1, num_processes
      ret = c_waitpid(pids(i), c_loc(status), WUNTRACED)
      if (ret > 0) then
        exit_statuses(i) = WEXITSTATUS(status)
        
        ! Track first failure for pipefail option
        if (exit_statuses(i) /= 0 .and. first_failure == 0) then
          first_failure = exit_statuses(i)
        end if
      else
        exit_statuses(i) = 1  ! Default to failure if wait failed
        if (first_failure == 0) first_failure = 1
      end if
    end do
    
    ! Set exit status according to POSIX rules
    if (shell%option_pipefail) then
      ! pipefail: return exit status of first failing command, or 0 if all succeed
      shell%last_exit_status = first_failure
    else
      ! Normal: return exit status of last (rightmost) command
      shell%last_exit_status = exit_statuses(num_processes)
    end if
    
    ! Update $! (last background PID) if this was a background pipeline
    if (num_processes > 0) then
      shell%last_bg_pid = pids(num_processes)
    end if
    
    deallocate(exit_statuses)
  end subroutine

  subroutine execute_single(cmd, shell, original_input)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    logical :: should_execute
    integer(int64) :: exec_start_time
    
    ! Start performance timing
    call start_timer('execute_single', exec_start_time)
    
    if (cmd%num_tokens == 0) return
    
    ! Check for variable assignment first (before expansion)
    if (cmd%num_tokens == 1 .and. is_assignment(cmd%tokens(1))) then
      call handle_assignment(shell, cmd%tokens(1))
      return
    end if
    
    ! Check for control flow keywords and apply control flow state
    if (allocated(cmd%tokens) .and. cmd%num_tokens > 0) then
      if (is_control_flow_keyword(cmd%tokens(1))) then
        call process_control_flow(cmd, shell, should_execute)
        if (.not. should_execute) return
      else
        ! For regular commands, check if we should execute based on control flow state
        call process_control_flow(cmd, shell, should_execute)
        if (.not. should_execute) return
      end if
    end if
    
    ! Handle here document input
    if (allocated(cmd%heredoc_delimiter)) then
      call read_heredoc(cmd%heredoc_delimiter, cmd%heredoc_content)
    end if
    
    ! Expand variables in all tokens
    call expand_tokens(cmd, shell)
    
    ! Expand glob patterns
    call expand_command_globs(cmd)
    
    ! Check if it's a user-defined function
    if (is_function(shell, cmd%tokens(1))) then
      call execute_function(cmd, shell)
    else if (is_builtin(cmd%tokens(1))) then
      call execute_builtin(cmd, shell)
    else
      call execute_external(cmd, shell, original_input)
    end if
    
    ! End performance timing
    call end_timer('execute_single', exec_start_time, total_exec_time)
  end subroutine

  subroutine expand_tokens(cmd, shell)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(in) :: shell
    integer :: i
    character(len=:), allocatable :: expanded
    
    do i = 1, cmd%num_tokens
      call expand_variables(cmd%tokens(i), expanded, shell)
      cmd%tokens(i) = expanded
    end do
  end subroutine

  subroutine execute_external(cmd, shell, original_input)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    integer(c_pid_t) :: pid, pgid
    integer(c_int), target :: wait_status
    integer :: ret, job_id
    logical :: foreground
    type(c_funptr) :: old_handler
    
    foreground = .not. cmd%background
    pid = c_fork()
    
    if (pid < 0) then
      write(error_unit, '(a)') 'Error: fork failed'
      shell%last_exit_status = 1
    else if (pid == 0) then
      ! Child process
      
      ! Set process group
      pgid = c_getpid()
      ret = c_setpgid(0, pgid)
      
      ! Reset signal handlers
      SIG_DFL = c_null_funptr
      old_handler = c_signal(SIGINT, SIG_DFL)
      old_handler = c_signal(SIGTSTP, SIG_DFL)
      old_handler = c_signal(SIGTTIN, SIG_DFL)
      old_handler = c_signal(SIGTTOU, SIG_DFL)
      
      ! Handle here document
      call handle_heredoc(cmd)
      
      ! Set up redirections
      call setup_redirections(cmd)
      
      ! Execute
      call exec_child(cmd%tokens, cmd%num_tokens)
      write(error_unit, '(a)') 'fortsh: command not found: ' // trim(cmd%tokens(1)) // &
                               '. Try "which ' // trim(cmd%tokens(1)) // '" or check your PATH.'
      call c_exit(127)
    else
      ! Parent process
      shell%last_pid = pid
      pgid = pid
      ret = c_setpgid(pid, pgid)
      
      if (foreground) then
        ! Give terminal to child
        if (shell%is_interactive) then
          ret = c_tcsetpgrp(shell%shell_terminal, pgid)
        end if
        
        ! Wait for child
        ret = c_waitpid(pid, c_loc(wait_status), WUNTRACED)
        
        ! Take back terminal
        if (shell%is_interactive) then
          ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
        end if
        
        if (WIFEXITED(wait_status)) then
          shell%last_exit_status = WEXITSTATUS(wait_status)
        else if (WIFSTOPPED(wait_status)) then
          job_id = add_job(shell, pgid, original_input, .true.)
          write(output_unit, '(a)') 'Stopped'
        end if
      else
        ! Background job
        job_id = add_job(shell, pgid, original_input, .false.)
        write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pid
      end if
    end if
  end subroutine

  subroutine handle_heredoc(cmd)
    type(command_t), intent(in) :: cmd
    integer, target :: pipefd(2)
    integer :: ret
    integer(c_size_t) :: bytes_written
    character(kind=c_char), target :: c_content(MAX_HEREDOC_LEN)
    integer :: i
    character(len=:), allocatable :: content_to_write
    
    ! Handle here-string (<<<)
    if (allocated(cmd%here_string)) then
      content_to_write = cmd%here_string // char(10)  ! Add newline
    else if (allocated(cmd%heredoc_content)) then
      content_to_write = cmd%heredoc_content
    else
      return
    end if
    
    ! Create pipe for input
    ret = c_pipe(c_loc(pipefd))
    if (ret == 0) then
      ! Convert content to C string
      do i = 1, min(len(content_to_write), MAX_HEREDOC_LEN-1)
        c_content(i) = content_to_write(i:i)
      end do
      c_content(min(len(content_to_write), MAX_HEREDOC_LEN-1)+1) = c_null_char
      
      ! Write content to pipe
      bytes_written = c_write(pipefd(2), c_loc(c_content), &
                             int(min(len(content_to_write), MAX_HEREDOC_LEN-1), c_size_t))
      
      ! Close write end and redirect stdin to read end
      ret = c_close(pipefd(2))
      ret = c_dup2(pipefd(1), STDIN_FD)
      ret = c_close(pipefd(1))
    end if
  end subroutine

  subroutine setup_redirections(cmd)
    type(command_t), intent(in) :: cmd
    integer :: fd, ret
    integer :: flags
    character(len=256), target :: c_filename
    
    ! Handle input redirection
    if (allocated(cmd%input_file)) then
      c_filename = trim(cmd%input_file)//c_null_char
      fd = c_open(c_loc(c_filename), O_RDONLY, 0)
      if (fd >= 0) then
        ret = c_dup2(fd, STDIN_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'Cannot open input file: ', trim(cmd%input_file)
        call c_exit(1)
      end if
    end if
    
    ! Handle output redirection
    if (allocated(cmd%output_file)) then
      if (cmd%append_output) then
        flags = ior(ior(O_WRONLY, O_CREAT), O_APPEND)
      else
        flags = ior(ior(O_WRONLY, O_CREAT), O_TRUNC)
      end if
      
      c_filename = trim(cmd%output_file)//c_null_char
      fd = c_open(c_loc(c_filename), flags, int(o'644', c_int))
      if (fd >= 0) then
        ret = c_dup2(fd, STDOUT_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'Cannot open output file: ', trim(cmd%output_file)
        call c_exit(1)
      end if
    end if
    
    ! Handle error redirection
    if (allocated(cmd%error_file)) then
      if (cmd%append_error) then
        flags = ior(ior(O_WRONLY, O_CREAT), O_APPEND)
      else
        flags = ior(ior(O_WRONLY, O_CREAT), O_TRUNC)
      end if
      
      c_filename = trim(cmd%error_file)//c_null_char
      fd = c_open(c_loc(c_filename), flags, int(o'644', c_int))
      if (fd >= 0) then
        ret = c_dup2(fd, STDERR_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'Cannot open error file: ', trim(cmd%error_file)
        call c_exit(1)
      end if
    end if
    
    ! Handle advanced redirections
    if (cmd%redirect_stderr_to_stdout) then
      ret = c_dup2(STDOUT_FD, STDERR_FD)
    end if
    
    if (cmd%redirect_stdout_to_stderr) then
      ret = c_dup2(STDERR_FD, STDOUT_FD)
    end if
  end subroutine

  subroutine exec_child(tokens, num_tokens)
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    
    type(c_ptr), target :: argv(num_tokens + 1)
    character(kind=c_char), target :: c_tokens(num_tokens, MAX_TOKEN_LEN+1)
    integer :: i, j
    integer :: ret
    
    ! Convert tokens to C strings
    do i = 1, num_tokens
      do j = 1, len_trim(tokens(i))
        c_tokens(i, j) = tokens(i)(j:j)
      end do
      c_tokens(i, len_trim(tokens(i)) + 1) = c_null_char
      argv(i) = c_loc(c_tokens(i, 1))
    end do
    argv(num_tokens + 1) = c_null_ptr
    
    ! Execute the command
    ret = c_execvp(argv(1), c_loc(argv))
  end subroutine

  subroutine execute_function(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=1024), allocatable :: function_body(:)
    integer :: i
    type(pipeline_t) :: pipeline
    character(len=:), allocatable :: expanded_line
    
    ! Get function body
    function_body = get_function_body(shell, cmd%tokens(1))
    
    if (allocated(function_body)) then
      ! Execute each line of the function
      do i = 1, size(function_body)
        if (len_trim(function_body(i)) > 0) then
          ! Expand aliases
          call expand_alias(shell, trim(function_body(i)), expanded_line)
          
          ! Parse and execute
          call parse_pipeline(expanded_line, pipeline)
          if (pipeline%num_commands > 0) then
            call execute_pipeline(pipeline, shell, expanded_line)
          end if
          
          ! Clean up
          if (allocated(pipeline%commands)) then
            deallocate(pipeline%commands)
          end if
          
          ! Exit early if shell stopped
          if (.not. shell%running) exit
        end if
      end do
    end if
  end subroutine

end module executor