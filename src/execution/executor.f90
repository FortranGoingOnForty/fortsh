! ==============================================================================
! Module: executor (Extended with job control)
! ==============================================================================
module executor
  use shell_types
  use system_interface
  use builtins
  use parser
  use job_control
  use variables, only: var_set_shell_variable => set_shell_variable, set_array_variable, set_array_element
  use control_flow
  use error_handling
  use performance
  use shell_options
  use signal_handling, only: execute_trap, TRAP_DEBUG, TRAP_ERR
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
        ! Skip the last command in the pipeline (it has non-PIPE separator)
        i = i + 1
        
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

        ! Reset signal handlers to default
        old_handler = c_signal(SIGINT, c_null_funptr)
        old_handler = c_signal(SIGTSTP, c_null_funptr)
        old_handler = c_signal(SIGTTIN, c_null_funptr)
        old_handler = c_signal(SIGTTOU, c_null_funptr)
        
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

        ! Handle eval builtin directly (to avoid circular dependency)
        if (trim(pipeline%commands(i)%tokens(1)) == 'eval') then
          call execute_eval_builtin(pipeline%commands(i), shell)
          call c_exit(int(shell%last_exit_status, c_int))
        else if (is_builtin(pipeline%commands(i)%tokens(1))) then
          ! Builtins in pipes need redirections applied
          call setup_redirections(pipeline%commands(i))
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
      ! Set $! to last process in background pipeline
      shell%last_bg_pid = pids(pipe_count + 1)
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

    deallocate(exit_statuses)
  end subroutine

  subroutine execute_single(cmd, shell, original_input)
    use control_flow, only: capture_loop_command, is_control_flow_keyword
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    logical :: should_execute, trap_executed
    integer(int64) :: exec_start_time
    character(len=2048) :: reconstructed_cmd

    ! Start performance timing
    call start_timer('execute_single', exec_start_time)

    if (cmd%num_tokens == 0) return

    ! Capture command if we're inside a loop body (before executing control flow)
    if (shell%control_depth > 0) then
      if (shell%control_stack(shell%control_depth)%capturing_loop_body) then
        if (allocated(cmd%tokens) .and. cmd%num_tokens > 0) then
          ! Reconstruct the command from tokens (don't use original_input which may contain the whole line)
          call reconstruct_command_from_tokens(cmd, reconstructed_cmd)

          ! Track nested depth for proper 'done' matching
          if (trim(cmd%tokens(1)) == 'for' .or. trim(cmd%tokens(1)) == 'while' .or. &
              (len_trim(cmd%tokens(1)) >= 5 .and. cmd%tokens(1)(1:5) == 'for((')) then
            ! Starting a nested loop - increment nesting depth
            shell%control_stack(shell%control_depth)%capture_nesting_depth = &
              shell%control_stack(shell%control_depth)%capture_nesting_depth + 1
            call capture_loop_command(shell, trim(reconstructed_cmd))
            return
          else if (trim(cmd%tokens(1)) == 'do') then
            ! 'do' for nested loop - just capture it
            if (shell%control_stack(shell%control_depth)%capture_nesting_depth > 0) then
              call capture_loop_command(shell, trim(reconstructed_cmd))
              return
            end if
            ! If nesting depth is 0, this 'do' is an error - let it be processed
          else if (trim(cmd%tokens(1)) == 'done') then
            ! Check nesting depth
            if (shell%control_stack(shell%control_depth)%capture_nesting_depth > 0) then
              ! This 'done' ends a nested loop
              shell%control_stack(shell%control_depth)%capture_nesting_depth = &
                shell%control_stack(shell%control_depth)%capture_nesting_depth - 1
              call capture_loop_command(shell, trim(reconstructed_cmd))
              return
            else
              ! This 'done' ends the current capturing loop - process normally
            end if
          else
            ! Everything else gets captured
            call capture_loop_command(shell, trim(reconstructed_cmd))
            return
          end if
        end if
      end if
    end if

    ! Check for control flow keywords and apply control flow state
    if (allocated(cmd%tokens) .and. cmd%num_tokens > 0) then
      if (is_control_flow_keyword(cmd%tokens(1))) then
        call process_control_flow(cmd, shell, should_execute)
        if (.not. should_execute) return

        ! Special handling for single-line if statements: if condition; then command; fi
        ! After processing "then", check if there are extra tokens to execute
        if (trim(cmd%tokens(1)) == 'then' .and. cmd%num_tokens > 1) then
          call execute_inline_then_commands(cmd, shell)
          return
        end if
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

    ! Expand variables in all tokens (except for defun, which needs raw body)
    ! Do this BEFORE checking for assignment so ${var##pattern} gets expanded
    if (trim(cmd%tokens(1)) /= 'defun') then
      call expand_tokens(cmd, shell)
    end if

    ! Check for variable assignment (after expansion so ${...} is processed)
    if (cmd%num_tokens == 1 .and. is_assignment(cmd%tokens(1))) then
      call handle_assignment(shell, cmd%tokens(1))
      return
    end if

    ! Expand glob patterns (except for defun)
    if (trim(cmd%tokens(1)) /= 'defun') then
      call expand_command_globs(cmd)
    end if

    ! === DEBUGGING & TRACING HOOKS ===
    ! Execute DEBUG trap if set (before command execution)
    trap_executed = execute_trap(shell, TRAP_DEBUG)

    ! If a trap command was queued, execute it now
    if (len_trim(shell%pending_trap_command) > 0) then
      call execute_pending_trap(shell)
    end if

    ! Trace command if xtrace is enabled (set -x)
    if (shell%option_xtrace .and. cmd%num_tokens > 0) then
      ! Reconstruct command for tracing
      call reconstruct_command_from_tokens(cmd, reconstructed_cmd)
      call trace_command(shell, trim(reconstructed_cmd))
    end if
    ! === END DEBUGGING & TRACING HOOKS ===

    ! Check for variable assignment: var=value or arr=(...)
    if (index(cmd%tokens(1), '=') > 0 .and. index(cmd%tokens(1), '=') > 1) then
      call execute_assignment(cmd, shell)
    ! Check for ((expression)) arithmetic evaluation command
    else if (len_trim(cmd%tokens(1)) >= 4 .and. &
        cmd%tokens(1)(1:2) == '((' .and. &
        cmd%tokens(1)(len_trim(cmd%tokens(1))-1:len_trim(cmd%tokens(1))) == '))') then
      call execute_arithmetic_command(cmd, shell)
    ! Check if it's a user-defined function
    else if (is_function(shell, cmd%tokens(1))) then
      call execute_function(cmd, shell)
    ! Handle eval builtin directly (to avoid circular dependency with builtins)
    else if (trim(cmd%tokens(1)) == 'eval') then
      call execute_eval_builtin(cmd, shell)
    else if (is_builtin(cmd%tokens(1))) then
      call execute_builtin_with_redirects(cmd, shell)
    else
      call execute_external(cmd, shell, original_input)
    end if

    ! === ERROR TRAP HOOK ===
    ! Execute ERR trap if command failed (after command execution)
    if (shell%last_exit_status /= 0) then
      trap_executed = execute_trap(shell, TRAP_ERR, shell%last_exit_status)

      ! If a trap command was queued, execute it now
      if (len_trim(shell%pending_trap_command) > 0) then
        call execute_pending_trap(shell)
      end if
    end if
    ! === END ERROR TRAP HOOK ===

    ! End performance timing
    call end_timer('execute_single', exec_start_time, total_exec_time)
  end subroutine

  ! Execute builtin with redirection support
  subroutine execute_builtin_with_redirects(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    integer :: saved_stdout, saved_stdin, saved_stderr
    integer :: fd, ret, flags
    character(len=256), target :: c_filename
    logical :: has_redirects

    ! Check if we have any redirections
    has_redirects = allocated(cmd%output_file) .or. allocated(cmd%input_file) .or. &
                    allocated(cmd%error_file) .or. cmd%redirect_stderr_to_stdout .or. &
                    cmd%redirect_stdout_to_stderr

    if (.not. has_redirects) then
      ! No redirections, just execute the builtin normally
      call execute_builtin(cmd, shell)
      return
    end if

    ! Save current file descriptors
    saved_stdout = c_dup(STDOUT_FD)
    saved_stdin = c_dup(STDIN_FD)
    saved_stderr = c_dup(STDERR_FD)

    ! Handle input redirection
    if (allocated(cmd%input_file)) then
      c_filename = trim(cmd%input_file)//c_null_char
      fd = c_open(c_loc(c_filename), O_RDONLY, 0)
      if (fd >= 0) then
        ret = c_dup2(fd, STDIN_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'fortsh: cannot open input file: ', trim(cmd%input_file)
        shell%last_exit_status = 1
        return
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
        write(error_unit, '(3a)') 'fortsh: cannot open output file: ', trim(cmd%output_file)
        shell%last_exit_status = 1
        ! Restore stdin before returning
        ret = c_dup2(saved_stdin, STDIN_FD)
        ret = c_close(saved_stdin)
        return
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
        write(error_unit, '(3a)') 'fortsh: cannot open error file: ', trim(cmd%error_file)
        shell%last_exit_status = 1
        ! Restore fds before returning
        ret = c_dup2(saved_stdin, STDIN_FD)
        ret = c_dup2(saved_stdout, STDOUT_FD)
        ret = c_close(saved_stdin)
        ret = c_close(saved_stdout)
        return
      end if
    end if

    ! Handle advanced redirections
    if (cmd%redirect_stderr_to_stdout) then
      ret = c_dup2(STDOUT_FD, STDERR_FD)
    end if

    if (cmd%redirect_stdout_to_stderr) then
      ret = c_dup2(STDERR_FD, STDOUT_FD)
    end if

    ! Execute the builtin
    call execute_builtin(cmd, shell)

    ! Restore original file descriptors
    ret = c_dup2(saved_stdout, STDOUT_FD)
    ret = c_dup2(saved_stdin, STDIN_FD)
    ret = c_dup2(saved_stderr, STDERR_FD)
    ret = c_close(saved_stdout)
    ret = c_close(saved_stdin)
    ret = c_close(saved_stderr)
  end subroutine

  ! Execute ((expression)) arithmetic evaluation command
  ! Sets exit status to 0 if expression is non-zero, 1 if zero
  subroutine execute_arithmetic_command(cmd, shell)
    use expansion, only: arithmetic_expansion_shell
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: expr, result_str
    character(len=:), allocatable :: arith_expr
    integer(kind=8) :: result_val
    integer :: iostat

    ! Build full expression from all tokens
    expr = trim(cmd%tokens(1))

    ! Convert ((expr)) to $((expr)) for arithmetic_expansion_shell
    arith_expr = '$' // trim(expr)

    ! Evaluate arithmetic expression
    result_str = arithmetic_expansion_shell(trim(arith_expr), shell)

    ! Convert result to integer
    read(result_str, *, iostat=iostat) result_val
    if (iostat /= 0) result_val = 0

    ! Set exit status: 0 if non-zero, 1 if zero
    if (result_val /= 0) then
      shell%last_exit_status = 0
    else
      shell%last_exit_status = 1
    end if
  end subroutine

  ! Execute variable assignment: var=value, arr=(a b c), or arr[0]=value
  subroutine execute_assignment(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=MAX_TOKEN_LEN) :: var_name, var_value, token
    character(len=MAX_TOKEN_LEN) :: array_elements(100)
    character(len=100) :: index_str
    character(len=:), allocatable :: expanded_value
    integer :: eq_pos, paren_start, paren_end, num_elements, bracket_pos
    integer :: bracket_end, array_index, read_status, actual_value_len, i
    logical :: is_indexed_assignment
    character(len=1) :: quote_char_temp

    token = trim(cmd%tokens(1))
    eq_pos = index(token, '=')
    if (eq_pos == 0) return

    ! Check for array index assignment: arr[index]=value
    bracket_pos = index(token, '[')
    is_indexed_assignment = (bracket_pos > 0 .and. bracket_pos < eq_pos)

    if (is_indexed_assignment) then
      ! arr[index]=value
      var_name = token(:bracket_pos-1)
      bracket_end = index(token(bracket_pos:), ']')
      if (bracket_end > 0) then
        bracket_end = bracket_pos + bracket_end - 1
        index_str = token(bracket_pos+1:bracket_end-1)
        var_value = token(eq_pos+1:)

        ! Parse the index (bash uses 0-indexed, convert to 1-indexed)
        read(index_str, *, iostat=read_status) array_index
        if (read_status == 0) then
          array_index = array_index + 1  ! Convert to 1-indexed
          call set_array_element(shell, trim(var_name), array_index, trim(var_value))
          shell%last_exit_status = 0
        else
          write(error_unit, '(a)') 'Error: invalid array index'
          shell%last_exit_status = 1
        end if
      else
        write(error_unit, '(a)') 'Error: unclosed bracket in array assignment'
        shell%last_exit_status = 1
      end if
      return
    end if

    ! Get variable name (before =)
    var_name = token(:eq_pos-1)

    ! Check if it's an array literal: arr=(...)
    paren_start = eq_pos + 1
    if (paren_start <= len_trim(token) .and. token(paren_start:paren_start) == '(') then
      ! Array literal
      paren_end = index(token(paren_start+1:), ')')
      if (paren_end > 0) then
        paren_end = paren_start + paren_end
        ! Extract elements between parentheses
        var_value = token(paren_start+1:paren_end-1)

        ! Split by spaces to get array elements
        num_elements = 0
        call split_array_elements(var_value, array_elements, num_elements)

        ! Set as array variable
        call set_array_variable(shell, trim(var_name), array_elements, num_elements)
        shell%last_exit_status = 0
      else
        write(error_unit, '(a)') 'Error: unclosed array literal'
        shell%last_exit_status = 1
      end if
    else
      ! Simple assignment: var=value
      var_value = token(eq_pos+1:)

      ! Calculate actual content length BEFORE stripping quotes (to preserve trailing spaces)
      actual_value_len = len_trim(var_value)
      if (actual_value_len >= 2) then
        if (var_value(1:1) == "'" .or. var_value(1:1) == '"') then
          ! Find closing quote position by searching backwards
          quote_char_temp = var_value(1:1)
          do i = actual_value_len, 2, -1
            if (var_value(i:i) == quote_char_temp) then
              ! Content length is closing_quote_pos - 2
              actual_value_len = i - 2
              exit
            end if
          end do
        else
          ! No quotes, use len_trim
          actual_value_len = len_trim(var_value)
        end if
      else
        actual_value_len = len_trim(var_value)
      end if

      ! Strip surrounding quotes from value (single or double quotes)
      call strip_quotes_local(var_value)

      ! Expand variables in the value (including parameter expansions like ${var##pattern})
      if (index(var_value, '$') > 0 .or. index(var_value, '~') > 0) then
        call expand_variables(var_value, expanded_value, shell)
        if (allocated(expanded_value)) then
          ! For expanded values, use the allocated length
          call var_set_shell_variable(shell, trim(var_name), expanded_value, len(expanded_value))
        else
          call var_set_shell_variable(shell, trim(var_name), '', 0)
        end if
      else
        call var_set_shell_variable(shell, trim(var_name), var_value, actual_value_len)
      end if
      shell%last_exit_status = 0
    end if
  end subroutine

  ! Split array elements by spaces (respecting quotes)
  subroutine split_array_elements(input, elements, count)
    character(len=*), intent(in) :: input
    character(len=MAX_TOKEN_LEN), intent(out) :: elements(:)
    integer, intent(out) :: count
    integer :: i, start, len_input
    logical :: in_quotes
    character :: quote_char

    count = 0
    i = 1
    len_input = len_trim(input)

    do while (i <= len_input)
      ! Skip leading spaces
      do while (i <= len_input .and. input(i:i) == ' ')
        i = i + 1
      end do
      if (i > len_input) exit

      ! Start of element
      count = count + 1
      if (count > size(elements)) exit
      start = i
      in_quotes = .false.
      quote_char = ' '

      ! Find end of element
      do while (i <= len_input)
        if (.not. in_quotes .and. (input(i:i) == '"' .or. input(i:i) == "'")) then
          in_quotes = .true.
          quote_char = input(i:i)
        else if (in_quotes .and. input(i:i) == quote_char) then
          in_quotes = .false.
        else if (.not. in_quotes .and. input(i:i) == ' ') then
          exit
        end if
        i = i + 1
      end do

      ! Extract element (and remove quotes if present)
      elements(count) = input(start:i-1)
      if (len_trim(elements(count)) >= 2) then
        if ((elements(count)(1:1) == '"' .and. elements(count)(len_trim(elements(count)):len_trim(elements(count))) == '"') .or. &
            (elements(count)(1:1) == "'" .and. elements(count)(len_trim(elements(count)):len_trim(elements(count))) == "'")) then
          elements(count) = elements(count)(2:len_trim(elements(count))-1)
        end if
      end if
    end do
  end subroutine

  subroutine expand_tokens(cmd, shell)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
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

      ! Reset signal handlers to default
      old_handler = c_signal(SIGINT, c_null_funptr)
      old_handler = c_signal(SIGTSTP, c_null_funptr)
      old_handler = c_signal(SIGTTIN, c_null_funptr)
      old_handler = c_signal(SIGTTOU, c_null_funptr)
      
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
        ! Set $! to the background job PID
        shell%last_bg_pid = pid
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
    type(shell_state_t), pointer :: shell_ptr

    ! Note: We need shell state for variable expansion in FD redirections
    ! In child process context, we don't have direct access to shell state
    ! So for now we'll handle literal FDs and environment variables

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

    ! Handle FD duplications from redirections array
    call apply_fd_redirections(cmd)
  end subroutine

  ! Apply file descriptor redirections (including variable FD duplications)
  subroutine apply_fd_redirections(cmd)
    use expansion, only: get_environment_var
    type(command_t), intent(in) :: cmd
    character(len=:), allocatable :: expanded_value
    character(len=256) :: target_fd_str, var_name
    integer :: i, target_fd, ret, iostat, bracket_pos

    do i = 1, cmd%num_redirections
      select case(cmd%redirections(i)%type)
      case(REDIR_DUP_OUT)  ! >&n
        if (allocated(cmd%redirections(i)%target_fd_expr)) then
          ! Variable FD expression - need to expand
          target_fd_str = cmd%redirections(i)%target_fd_expr

          ! Extract variable name from ${var} or ${var[index]} pattern
          if (len_trim(target_fd_str) > 3) then
            if (target_fd_str(1:2) == '${' .and. &
                target_fd_str(len_trim(target_fd_str):len_trim(target_fd_str)) == '}') then
              var_name = target_fd_str(3:len_trim(target_fd_str)-1)

              ! Check for array syntax [index]
              bracket_pos = index(var_name, '[')
              if (bracket_pos > 0) then
                ! For COPROC[1] style, try environment variable with underscore
                ! e.g., COPROC_1 for COPROC[1]
                var_name = var_name(:bracket_pos-1) // '_' // &
                          var_name(bracket_pos+1:index(var_name,']')-1)
              end if

              ! Get value from environment
              expanded_value = get_environment_var(trim(var_name))
              if (allocated(expanded_value)) then
                read(expanded_value, *, iostat=iostat) target_fd
                if (iostat == 0 .and. target_fd >= 0) then
                  ret = c_dup2(target_fd, cmd%redirections(i)%fd)
                end if
              end if
            end if
          end if
        else if (cmd%redirections(i)%target_fd >= 0) then
          ! Literal FD
          ret = c_dup2(cmd%redirections(i)%target_fd, cmd%redirections(i)%fd)
        end if

      case(REDIR_DUP_IN)  ! <&n
        if (allocated(cmd%redirections(i)%target_fd_expr)) then
          ! Variable FD expression - need to expand
          target_fd_str = cmd%redirections(i)%target_fd_expr

          ! Extract variable name from ${var} pattern
          if (len_trim(target_fd_str) > 3) then
            if (target_fd_str(1:2) == '${' .and. &
                target_fd_str(len_trim(target_fd_str):len_trim(target_fd_str)) == '}') then
              var_name = target_fd_str(3:len_trim(target_fd_str)-1)

              ! Check for array syntax [index]
              bracket_pos = index(var_name, '[')
              if (bracket_pos > 0) then
                ! For COPROC[0] style, try environment variable with underscore
                var_name = var_name(:bracket_pos-1) // '_' // &
                          var_name(bracket_pos+1:index(var_name,']')-1)
              end if

              ! Get value from environment
              expanded_value = get_environment_var(trim(var_name))
              if (allocated(expanded_value)) then
                read(expanded_value, *, iostat=iostat) target_fd
                if (iostat == 0 .and. target_fd >= 0) then
                  ret = c_dup2(target_fd, cmd%redirections(i)%fd)
                end if
              end if
            end if
          end if
        else if (cmd%redirections(i)%target_fd >= 0) then
          ! Literal FD
          ret = c_dup2(cmd%redirections(i)%target_fd, cmd%redirections(i)%fd)
        end if
      end select
    end do
  end subroutine

  subroutine exec_child(tokens, num_tokens)
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens

    type(c_ptr), target :: argv(num_tokens + 1)
    character(kind=c_char), target :: c_tokens(MAX_TOKEN_LEN+1, num_tokens)
    integer :: i, j
    integer :: ret

    ! Convert tokens to C strings
    do i = 1, num_tokens
      do j = 1, len_trim(tokens(i))
        c_tokens(j, i) = tokens(i)(j:j)
      end do
      c_tokens(len_trim(tokens(i)) + 1, i) = c_null_char
      argv(i) = c_loc(c_tokens(1, i))
    end do
    argv(num_tokens + 1) = c_null_ptr

    ! Execute the command
    ret = c_execvp(argv(1), c_loc(argv))

    ! If we reach here, exec failed
    write(error_unit, '(a)') 'fortsh: command not found: ' // trim(tokens(1)) // &
                             '. Try "which ' // trim(tokens(1)) // '" or check your PATH.'
  end subroutine

  subroutine execute_function(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=1024), allocatable :: function_body(:)
    character(len=1024) :: saved_positional_params(50)
    integer :: saved_num_positional
    integer :: i, saved_exit_status
    type(pipeline_t) :: pipeline
    character(len=:), allocatable :: expanded_line
    logical :: function_returned

    ! Save current positional parameters (caller's $1, $2, etc.)
    saved_positional_params = shell%positional_params
    saved_num_positional = shell%num_positional

    ! Enter function scope
    shell%function_depth = shell%function_depth + 1

    ! Initialize local variable count for this function scope
    if (shell%function_depth <= size(shell%local_var_counts)) then
      shell%local_var_counts(shell%function_depth) = 0
    end if

    ! Set positional parameters from function arguments
    ! cmd%tokens(1) is function name, cmd%tokens(2:) are arguments
    shell%num_positional = cmd%num_tokens - 1
    do i = 1, shell%num_positional
      shell%positional_params(i) = cmd%tokens(i + 1)
    end do

    ! Get function body
    function_body = get_function_body(shell, cmd%tokens(1))

    function_returned = .false.

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

            ! Check if we need to replay loop body (only if NOT currently capturing)
            if (shell%control_depth == 0 .or. .not. shell%control_stack(shell%control_depth)%capturing_loop_body) then
              call replay_loop_if_needed(shell)
            end if
          end if

          ! Clean up
          if (allocated(pipeline%commands)) then
            deallocate(pipeline%commands)
          end if

          ! Check if function returned early (via return builtin)
          ! We'll use a special flag in shell state for this
          if (shell%function_return_pending) then
            shell%function_return_pending = .false.
            function_returned = .true.
            exit
          end if

          ! Exit early if shell stopped
          if (.not. shell%running) exit
        end if
      end do
    end if

    ! Clean up local variables for this function scope
    if (shell%function_depth > 0 .and. shell%function_depth <= size(shell%local_var_counts)) then
      shell%local_var_counts(shell%function_depth) = 0
    end if

    ! Exit function scope
    shell%function_depth = shell%function_depth - 1

    ! Restore caller's positional parameters
    shell%positional_params = saved_positional_params
    shell%num_positional = saved_num_positional
  end subroutine

  ! Execute eval builtin (moved here to avoid circular dependency with builtins module)
  subroutine execute_eval_builtin(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=4096) :: eval_command
    integer :: i
    type(pipeline_t) :: pipeline

    ! If no arguments, just return success
    if (cmd%num_tokens < 2) then
      shell%last_exit_status = 0
      return
    end if

    ! Concatenate all arguments into a single command string
    eval_command = trim(cmd%tokens(2))
    do i = 3, cmd%num_tokens
      eval_command = trim(eval_command) // ' ' // trim(cmd%tokens(i))
    end do

    ! Parse the concatenated string as a pipeline
    call parse_pipeline(trim(eval_command), pipeline)

    ! Execute the parsed pipeline in the current shell context
    if (pipeline%num_commands > 0) then
      call execute_pipeline(pipeline, shell, trim(eval_command))

      ! Clean up pipeline allocations
      do i = 1, pipeline%num_commands
        if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
        if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
        if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
        if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
        if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
        if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
        if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
      end do

      if (allocated(pipeline%commands)) deallocate(pipeline%commands)
    else
      ! Empty command - success
      shell%last_exit_status = 0
    end if
  end subroutine

  ! Replay loop body if needed
  subroutine replay_loop_if_needed(shell)
    use parser, only: parse_pipeline
    use control_flow, only: process_control_flow
    type(shell_state_t), intent(inout) :: shell
    type(pipeline_t) :: pipeline, done_pipeline
    type(command_t) :: done_cmd
    integer :: i, iteration_count
    logical :: should_execute
    character(len=4) :: done_str

    ! Check if we should replay
    if (shell%control_depth == 0) return
    if (shell%control_stack(shell%control_depth)%loop_body_count == 0) return

    iteration_count = 0
    done_str = 'done'

    ! Keep replaying until loop condition is false
    do while (shell%control_depth > 0 .and. shell%control_stack(shell%control_depth)%loop_body_count > 0)
      iteration_count = iteration_count + 1
      if (iteration_count > 1000) then
        write(error_unit, '(a)') 'Loop limit reached (1000 iterations)'
        exit
      end if

      ! Temporarily stop capturing to avoid re-capturing during replay
      shell%control_stack(shell%control_depth)%capturing_loop_body = .false.

      do i = 1, shell%control_stack(shell%control_depth)%loop_body_count
        ! Check if break was requested
        if (shell%control_stack(shell%control_depth)%break_requested) then
          ! Clear the break flag
          shell%control_stack(shell%control_depth)%break_requested = .false.
          shell%control_stack(shell%control_depth)%break_level = 0
          ! Exit the loop immediately
          shell%control_stack(shell%control_depth)%loop_body_count = 0  ! Signal loop end
          exit
        end if

        ! Check if continue was requested
        if (shell%control_stack(shell%control_depth)%continue_requested) then
          ! Clear the continue flag
          shell%control_stack(shell%control_depth)%continue_requested = .false.
          shell%control_stack(shell%control_depth)%continue_level = 0
          ! Skip the rest of the iteration
          exit
        end if

        call parse_pipeline(shell%control_stack(shell%control_depth)%loop_body(i), pipeline)
        if (pipeline%num_commands > 0) then
          call execute_pipeline(pipeline, shell, shell%control_stack(shell%control_depth)%loop_body(i))
        end if
      end do

      ! Re-enable capturing for next iteration
      shell%control_stack(shell%control_depth)%capturing_loop_body = .true.

      ! Check if loop_body_count is 0 (break was called)
      if (shell%control_stack(shell%control_depth)%loop_body_count == 0) then
        ! Break was called, exit the loop
        exit
      end if

      ! Simulate 'done' to check loop condition and update state
      call parse_pipeline(done_str, done_pipeline)
      if (done_pipeline%num_commands > 0) then
        done_cmd = done_pipeline%commands(1)
        call process_control_flow(done_cmd, shell, should_execute)
        ! If control_depth decreased to 0, loop ended
        if (shell%control_depth == 0) then
          exit
        end if
        ! Also exit if loop_body_count became 0 (shouldn't happen but safety check)
        if (shell%control_stack(shell%control_depth)%loop_body_count == 0) then
          exit
        end if
      else
        exit  ! Couldn't parse done, exit
      end if
    end do
  end subroutine

  ! Reconstruct command line from command tokens
  subroutine reconstruct_command_from_tokens(cmd, result)
    type(command_t), intent(in) :: cmd
    character(len=*), intent(out) :: result
    integer :: i

    result = ''
    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens == 0) return

    ! Join tokens with spaces
    do i = 1, cmd%num_tokens
      if (i == 1) then
        result = trim(cmd%tokens(i))
      else
        result = trim(result) // ' ' // trim(cmd%tokens(i))
      end if
    end do
  end subroutine

  ! Strip surrounding quotes (single or double) from a string
  ! Preserves trailing spaces within quotes
  subroutine strip_quotes_local(str)
    character(len=*), intent(inout) :: str
    integer :: i, len_str, closing_quote_pos
    character(len=len(str)) :: temp
    character(len=1) :: quote_char

    len_str = len_trim(str)
    if (len_str < 2) return

    ! Check if string starts with a quote
    if (str(1:1) /= "'" .and. str(1:1) /= '"') return

    quote_char = str(1:1)

    ! Search for matching closing quote (search backwards from end)
    closing_quote_pos = 0
    do i = len_str, 2, -1
      if (str(i:i) == quote_char) then
        closing_quote_pos = i
        exit
      end if
    end do

    ! If we found a matching closing quote, extract the content (preserving all characters including trailing spaces)
    if (closing_quote_pos > 1) then
      ! Save the original string first
      temp = str
      ! Clear the output string
      str = repeat(' ', len(str))
      ! Copy character by character from positions 2 to closing_quote_pos-1
      do i = 2, closing_quote_pos - 1
        str(i-1:i-1) = temp(i:i)
      end do
    end if
  end subroutine

  ! Execute a pending trap command (set by signal_handling module)
  subroutine execute_pending_trap(shell)
    type(shell_state_t), intent(inout) :: shell
    type(pipeline_t) :: trap_pipeline
    integer :: i, saved_status

    ! Save the trap command and signal before clearing
    character(len=1024) :: trap_cmd
    trap_cmd = shell%pending_trap_command

    ! Save current exit status (traps don't affect $?)
    saved_status = shell%last_exit_status

    ! Clear the pending trap
    shell%pending_trap_command = ''
    shell%pending_trap_signal = 0

    ! Set flag to prevent recursive trap execution
    shell%executing_trap = .true.

    ! Parse the trap command
    call parse_pipeline(trim(trap_cmd), trap_pipeline)

    ! Execute it in current shell context
    if (trap_pipeline%num_commands > 0) then
      call execute_pipeline(trap_pipeline, shell, trim(trap_cmd))

      ! Clean up pipeline allocations
      do i = 1, trap_pipeline%num_commands
        if (allocated(trap_pipeline%commands(i)%tokens)) deallocate(trap_pipeline%commands(i)%tokens)
        if (allocated(trap_pipeline%commands(i)%input_file)) deallocate(trap_pipeline%commands(i)%input_file)
        if (allocated(trap_pipeline%commands(i)%output_file)) deallocate(trap_pipeline%commands(i)%output_file)
        if (allocated(trap_pipeline%commands(i)%error_file)) deallocate(trap_pipeline%commands(i)%error_file)
        if (allocated(trap_pipeline%commands(i)%heredoc_delimiter)) deallocate(trap_pipeline%commands(i)%heredoc_delimiter)
        if (allocated(trap_pipeline%commands(i)%heredoc_content)) deallocate(trap_pipeline%commands(i)%heredoc_content)
        if (allocated(trap_pipeline%commands(i)%here_string)) deallocate(trap_pipeline%commands(i)%here_string)
      end do

      if (allocated(trap_pipeline%commands)) deallocate(trap_pipeline%commands)
    end if

    ! Clear flag to allow future trap execution
    shell%executing_trap = .false.

    ! Restore original exit status (traps don't affect $?)
    shell%last_exit_status = saved_status
  end subroutine

  ! Execute inline commands after "then" in single-line if statements
  ! Example: if [ 1 -eq 1 ]; then echo "test"; fi
  ! After parsing, the "then echo 'test'" becomes a single command with tokens ["then", "echo", "test"]
  subroutine execute_inline_then_commands(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: remainder_cmd
    type(pipeline_t) :: inline_pipeline
    integer :: i

    ! Only execute if we're in a truthy if block
    ! The control flow state has already been updated by process_control_flow
    if (shell%control_depth == 0) return
    if (.not. shell%control_stack(shell%control_depth)%should_execute) return

    ! Build command string from tokens 2 onwards
    remainder_cmd = ''
    do i = 2, cmd%num_tokens
      if (len_trim(remainder_cmd) > 0) then
        remainder_cmd = trim(remainder_cmd) // ' ' // trim(cmd%tokens(i))
      else
        remainder_cmd = trim(cmd%tokens(i))
      end if
    end do

    ! Parse and execute the inline commands
    if (len_trim(remainder_cmd) > 0) then
      call parse_pipeline(trim(remainder_cmd), inline_pipeline)
      if (inline_pipeline%num_commands > 0) then
        call execute_pipeline(inline_pipeline, shell, trim(remainder_cmd))

        ! Clean up pipeline allocations
        do i = 1, inline_pipeline%num_commands
          if (allocated(inline_pipeline%commands(i)%tokens)) deallocate(inline_pipeline%commands(i)%tokens)
          if (allocated(inline_pipeline%commands(i)%input_file)) deallocate(inline_pipeline%commands(i)%input_file)
          if (allocated(inline_pipeline%commands(i)%output_file)) deallocate(inline_pipeline%commands(i)%output_file)
          if (allocated(inline_pipeline%commands(i)%error_file)) deallocate(inline_pipeline%commands(i)%error_file)
          if (allocated(inline_pipeline%commands(i)%heredoc_delimiter)) deallocate(inline_pipeline%commands(i)%heredoc_delimiter)
          if (allocated(inline_pipeline%commands(i)%heredoc_content)) deallocate(inline_pipeline%commands(i)%heredoc_content)
          if (allocated(inline_pipeline%commands(i)%here_string)) deallocate(inline_pipeline%commands(i)%here_string)
        end do

        if (allocated(inline_pipeline%commands)) deallocate(inline_pipeline%commands)
      end if
    end if
  end subroutine

  ! Initialize control_flow's evaluate_condition procedure pointer
  ! This breaks the circular dependency by setting the pointer at runtime
  subroutine init_control_flow_callbacks()
    use control_flow
    evaluate_condition => evaluate_condition_impl
  end subroutine

  ! Evaluate a condition for control flow (if/while statements)
  subroutine evaluate_condition_impl(condition_cmd, shell, result)
    use test_builtin, only: execute_test_command
    use parser, only: parse_pipeline
    character(len=*), intent(in) :: condition_cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: result

    type(command_t) :: cmd
    type(pipeline_t) :: pipeline
    character(len=256) :: tokens(50)
    integer :: num_tokens, i

    ! Check if it's a test command (starts with [ or test)
    if (index(trim(condition_cmd), '[') == 1 .or. &
        index(trim(condition_cmd), 'test ') == 1) then
      call execute_test_condition_impl(condition_cmd, shell, result)
    else
      ! For any other command, parse and execute it to get exit status
      call parse_pipeline(trim(condition_cmd), pipeline)

      if (pipeline%num_commands > 0) then
        call execute_pipeline(pipeline, shell, trim(condition_cmd))

        ! Clean up allocations
        do i = 1, pipeline%num_commands
          if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
          if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
          if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
          if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
          if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
          if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
          if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
        end do

        if (allocated(pipeline%commands)) deallocate(pipeline%commands)

        result = (shell%last_exit_status == 0)
      else
        result = .false.
      end if
    end if
  end subroutine

  ! Simple tokenization by spaces
  subroutine tokenize_line(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    character(len=256), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens
    integer :: i, start_pos

    num_tokens = 0
    i = 1

    do while (i <= len_trim(input))
      ! Skip spaces
      do while (i <= len_trim(input) .and. input(i:i) == ' ')
        i = i + 1
      end do

      if (i > len_trim(input)) exit

      ! Start of token
      start_pos = i
      do while (i <= len_trim(input) .and. input(i:i) /= ' ')
        i = i + 1
      end do

      ! Store token
      num_tokens = num_tokens + 1
      if (num_tokens <= size(tokens)) then
        tokens(num_tokens) = input(start_pos:i-1)
      end if
    end do
  end subroutine

  ! Helper for evaluating test conditions
  subroutine execute_test_condition_impl(condition_cmd, shell, result)
    use test_builtin, only: execute_test_command
    use control_flow, only: simple_variable_expand
    character(len=*), intent(in) :: condition_cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: result

    type(command_t) :: cmd
    character(len=256) :: tokens(50), expanded_token
    character(len=:), allocatable :: expanded_result
    integer :: num_tokens, i

    ! Tokenize the condition command
    num_tokens = 0
    call tokenize_line(trim(condition_cmd), tokens, num_tokens)

    ! Allocate and set command tokens with variable expansion
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)
    allocate(character(len=256) :: cmd%tokens(num_tokens))
    cmd%num_tokens = num_tokens
    do i = 1, num_tokens
      expanded_token = tokens(i)

      ! Expand variables in the token (e.g., $count becomes the value of count)
      if (index(expanded_token, '$') > 0) then
        call simple_variable_expand(expanded_token, expanded_result, shell)
        if (allocated(expanded_result)) then
          cmd%tokens(i) = expanded_result
        else
          cmd%tokens(i) = expanded_token
        end if
      else
        cmd%tokens(i) = expanded_token
      end if
    end do

    ! Execute the test command
    call execute_test_command(cmd, shell)

    ! Clean up
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)

    result = (shell%last_exit_status == 0)
  end subroutine

end module executor