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
  use better_errors
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
        ! Check if shell should exit (e.g., due to ${VAR?error})
        if (.not. shell%running) exit
        do while (i <= pipeline%num_commands)
          if (pipeline%commands(i)%separator /= SEP_PIPE) exit
          i = i + 1
        end do
        ! Skip the last command in the pipeline (it has non-PIPE separator)
        i = i + 1

      case(SEP_SEMICOLON, SEP_NONE)
        call execute_single(pipeline%commands(i), shell, original_input)
        ! NOTE: Sourcing is now handled at the AST level (in execute_ast) or by the caller
        ! We don't process sourced files inline here to avoid double-processing
        call check_errexit(shell, shell%last_exit_status)
        ! Check if shell should exit (e.g., due to ${VAR?error})
        if (.not. shell%running) exit
        i = i + 1

      case(SEP_AND)
        call execute_single(pipeline%commands(i), shell, original_input)
        should_continue = (shell%last_exit_status == 0)
        ! POSIX: errexit should be ignored in AND-OR lists
        ! Check if shell should exit (e.g., due to ${VAR?error})
        if (.not. shell%running) exit
        i = i + 1

      case(SEP_OR)
        call execute_single(pipeline%commands(i), shell, original_input)
        should_continue = (shell%last_exit_status /= 0)
        ! POSIX: errexit should be ignored in AND-OR lists
        ! Check if shell should exit (e.g., due to ${VAR?error})
        if (.not. shell%running) exit
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
    type(pipeline_t) :: group_pipeline
    integer :: k
    
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
        call handle_heredoc(pipeline%commands(i), shell)

        ! Handle command groups { cmd1; cmd2; }
        if (pipeline%commands(i)%is_command_group .and. allocated(pipeline%commands(i)%group_content)) then
          ! Parse the group content as a pipeline and execute it
          call parse_pipeline(pipeline%commands(i)%group_content, group_pipeline)
          if (group_pipeline%num_commands > 0) then
            call execute_pipeline(group_pipeline, shell, pipeline%commands(i)%group_content)
            ! Clean up
            do k = 1, group_pipeline%num_commands
              if (allocated(group_pipeline%commands(k)%tokens)) deallocate(group_pipeline%commands(k)%tokens)
              if (allocated(group_pipeline%commands(k)%input_file)) deallocate(group_pipeline%commands(k)%input_file)
              if (allocated(group_pipeline%commands(k)%output_file)) deallocate(group_pipeline%commands(k)%output_file)
              if (allocated(group_pipeline%commands(k)%error_file)) deallocate(group_pipeline%commands(k)%error_file)
              if (allocated(group_pipeline%commands(k)%heredoc_delimiter)) deallocate(group_pipeline%commands(k)%heredoc_delimiter)
              if (allocated(group_pipeline%commands(k)%heredoc_content)) deallocate(group_pipeline%commands(k)%heredoc_content)
              if (allocated(group_pipeline%commands(k)%here_string)) deallocate(group_pipeline%commands(k)%here_string)
              if (allocated(group_pipeline%commands(k)%group_content)) deallocate(group_pipeline%commands(k)%group_content)
            end do
            if (allocated(group_pipeline%commands)) deallocate(group_pipeline%commands)
          end if
          call c_exit(int(shell%last_exit_status, c_int))
        end if

        ! Handle subshells ( cmd1; cmd2 )
        if (pipeline%commands(i)%is_subshell .and. allocated(pipeline%commands(i)%subshell_content)) then
          ! Parse the subshell content as a pipeline and execute it
          call parse_pipeline(pipeline%commands(i)%subshell_content, group_pipeline)
          if (group_pipeline%num_commands > 0) then
            call execute_pipeline(group_pipeline, shell, pipeline%commands(i)%subshell_content)
            ! Clean up
            do k = 1, group_pipeline%num_commands
              if (allocated(group_pipeline%commands(k)%tokens)) deallocate(group_pipeline%commands(k)%tokens)
              if (allocated(group_pipeline%commands(k)%input_file)) deallocate(group_pipeline%commands(k)%input_file)
              if (allocated(group_pipeline%commands(k)%output_file)) deallocate(group_pipeline%commands(k)%output_file)
              if (allocated(group_pipeline%commands(k)%error_file)) deallocate(group_pipeline%commands(k)%error_file)
              if (allocated(group_pipeline%commands(k)%heredoc_delimiter)) deallocate(group_pipeline%commands(k)%heredoc_delimiter)
              if (allocated(group_pipeline%commands(k)%heredoc_content)) deallocate(group_pipeline%commands(k)%heredoc_content)
              if (allocated(group_pipeline%commands(k)%here_string)) deallocate(group_pipeline%commands(k)%here_string)
              if (allocated(group_pipeline%commands(k)%group_content)) deallocate(group_pipeline%commands(k)%group_content)
              if (allocated(group_pipeline%commands(k)%subshell_content)) deallocate(group_pipeline%commands(k)%subshell_content)
            end do
            if (allocated(group_pipeline%commands)) deallocate(group_pipeline%commands)
          end if
          call c_exit(int(shell%last_exit_status, c_int))
        end if

        ! Check if we have tokens to process
        if (pipeline%commands(i)%num_tokens == 0) then
          ! No tokens (shouldn't happen after command group handling)
          write(error_unit, '(a)') 'Error: command has no tokens'
          call c_exit(1)
        end if

        ! Expand variables and execute
        call expand_tokens(pipeline%commands(i), shell)

        ! Expand glob patterns
        call expand_command_globs(pipeline%commands(i))

        ! Process backslash escapes AFTER glob expansion
        call process_command_escapes(pipeline%commands(i))

        ! Handle eval builtin directly (to avoid circular dependency)
        ! Removed special handling for eval - it's now a regular builtin
        if (is_builtin(pipeline%commands(i)%tokens(1))) then
          ! Builtins in pipes need redirections applied
          call setup_redirections(pipeline%commands(i), shell)
          call execute_builtin(pipeline%commands(i), shell)
          call c_exit(int(shell%last_exit_status, c_int))
        else
          call setup_redirections(pipeline%commands(i), shell)
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
      write(output_unit, '(a,i15,a,i0)') '[', job_id, '] ', pgid
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
    logical :: should_execute, trap_executed, negate_exit_status
    integer(int64) :: exec_start_time
    integer :: i
    character(len=2048) :: reconstructed_cmd
    character(len=MAX_TOKEN_LEN), allocatable :: temp_tokens(:)
    type(pipeline_t) :: pipeline

    ! Start performance timing
    call start_timer('execute_single', exec_start_time)

    ! Handle subshells ( cmd1; cmd2 )
    if (cmd%is_subshell .and. allocated(cmd%subshell_content)) then
      ! Fork a subshell and execute commands in it
      call execute_subshell(cmd%subshell_content, shell, original_input)
      ! End performance timing
      call end_timer('execute_single', exec_start_time, total_exec_time)
      return
    end if

    ! Handle command groups { cmd1; cmd2; }
    if (cmd%is_command_group .and. allocated(cmd%group_content)) then
      ! Parse the group content as a pipeline and execute it
      call parse_pipeline(cmd%group_content, pipeline)
      if (pipeline%num_commands > 0) then
        call execute_pipeline(pipeline, shell, cmd%group_content)
        ! Clean up
        do i = 1, pipeline%num_commands
          if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
          if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
          if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
          if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
          if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
          if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
          if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
          if (allocated(pipeline%commands(i)%group_content)) deallocate(pipeline%commands(i)%group_content)
        end do
        if (allocated(pipeline%commands)) deallocate(pipeline%commands)
      end if
      ! End performance timing
      call end_timer('execute_single', exec_start_time, total_exec_time)
      return
    end if

    if (cmd%num_tokens == 0) return

    ! Handle negation operator (!)
    negate_exit_status = .false.

    ! Check if first token is the negation operator
    if (trim(cmd%tokens(1)) == '!') then
      negate_exit_status = .true.

      ! Remove the ! from tokens and shift everything left
      if (cmd%num_tokens > 1) then
        allocate(temp_tokens(cmd%num_tokens - 1))
        do i = 2, cmd%num_tokens
          temp_tokens(i - 1) = cmd%tokens(i)
        end do

        ! Replace cmd%tokens with shifted tokens
        deallocate(cmd%tokens)
        allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(cmd%num_tokens - 1))
        cmd%tokens = temp_tokens
        cmd%num_tokens = cmd%num_tokens - 1
        deallocate(temp_tokens)
      else
        ! Just "!" with no command - that's an error
        write(error_unit, '(a)') '!: command not found'
        shell%last_exit_status = 127
        return
      end if
    end if

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
        ! Special handling for single-line if statements: if condition; then command; fi
        ! Check BEFORE processing control flow, because process_control_flow will set should_execute=false for "then"/"else"
        if (trim(cmd%tokens(1)) == 'then' .and. cmd%num_tokens > 1) then
          call process_control_flow(cmd, shell, should_execute)
          call execute_inline_then_commands(cmd, shell)
          return
        end if

        ! Special handling for single-line else: else echo command
        if (trim(cmd%tokens(1)) == 'else' .and. cmd%num_tokens > 1) then
          call process_control_flow(cmd, shell, should_execute)
          call execute_inline_then_commands(cmd, shell)  ! Reuse same function since logic is identical
          return
        end if

        ! Special handling for single-line elif: elif condition; then echo command
        if (trim(cmd%tokens(1)) == 'elif') then
          call process_control_flow(cmd, shell, should_execute)
          ! If the elif condition was true and we should execute, wait for the "then" keyword
          ! The inline command will be handled when we see "then"
          return
        end if

        call process_control_flow(cmd, shell, should_execute)

        ! If we just processed a 'done' keyword, execute the loop body immediately
        ! This ensures loops execute inline, not deferred until after the pipeline
        if (trim(cmd%tokens(1)) == 'done') then
          call replay_loop_if_needed(shell)
        end if

        if (.not. should_execute) return
      else
        ! For regular commands, check if we should execute based on control flow state
        call process_control_flow(cmd, shell, should_execute)
        if (.not. should_execute) return
      end if
    end if

    ! Handle case pattern: skip first token if flag is set
    if (shell%case_pattern_skip_first_token .and. cmd%num_tokens > 1) then
      ! Shift tokens left to skip the pattern token
      allocate(temp_tokens(cmd%num_tokens - 1))
      do i = 2, cmd%num_tokens
        temp_tokens(i - 1) = cmd%tokens(i)
      end do
      deallocate(cmd%tokens)
      allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(cmd%num_tokens - 1))
      cmd%tokens = temp_tokens
      cmd%num_tokens = cmd%num_tokens - 1
      deallocate(temp_tokens)
      ! Reset the flag
      shell%case_pattern_skip_first_token = .false.
    end if

    ! Handle here document input
    ! Only read from stdin if content wasn't already extracted from input string
    if (allocated(cmd%heredoc_delimiter) .and. .not. allocated(cmd%heredoc_content)) then
      call read_heredoc(cmd%heredoc_delimiter, cmd%heredoc_content, shell)
    end if

    ! Check if this is a function definition BEFORE expanding variables
    ! (so $1, $2, etc. remain literal in the function body)
    if (is_function_definition_command(cmd, shell)) then
      ! Function was registered, don't execute anything
      shell%last_exit_status = 0
      return
    end if

    ! Expand variables in all tokens (except for defun and assignments)
    ! Skip expansion for assignments because execute_assignment needs to handle
    ! quote-aware expansion properly (e.g., CMD="echo \$X" should store "echo $X")
    if (trim(cmd%tokens(1)) /= 'defun' .and. &
        .not. (index(cmd%tokens(1), '=') > 0 .and. index(cmd%tokens(1), '=') > 1)) then
      call expand_tokens(cmd, shell)
    end if

    ! Check if parameter expansion error occurred (${VAR?error})
    if (shell%fatal_expansion_error) then
      shell%fatal_expansion_error = .false.  ! Reset flag
      ! End performance timing
      call end_timer('execute_single', exec_start_time, total_exec_time)
      ! POSIX: In non-interactive shells, exit the shell entirely
      if (.not. shell%is_interactive) then
        shell%running = .false.
      end if
      return  ! Abort command execution
    end if

    ! Check for variable assignment (after expansion so ${...} is processed)
    ! DISABLED: Now that we skip expand_tokens for assignments (line 503-506),
    ! all assignments should go through execute_assignment which properly handles
    ! backslash escapes in double-quoted strings.
    ! if (cmd%num_tokens == 1 .and. is_assignment(cmd%tokens(1))) then
    !   call handle_assignment(shell, cmd%tokens(1))
    !   return
    ! end if

    ! Expand glob patterns (except for defun)
    if (trim(cmd%tokens(1)) /= 'defun') then
      call expand_command_globs(cmd)
    end if

    ! Process backslash escapes AFTER glob expansion
    if (trim(cmd%tokens(1)) /= 'defun') then
      call process_command_escapes(cmd)
    end if

    ! === DEBUGGING & TRACING HOOKS ===
    ! Execute DEBUG trap if set (before command execution)
    trap_executed = execute_trap(shell, TRAP_DEBUG)

    ! If a trap command was queued, execute it now
    ! Check executing_trap to prevent recursion
    ! Don't execute EXIT trap here - it should only execute when shell is exiting
    if (len_trim(shell%pending_trap_command) > 0 .and. .not. shell%executing_trap .and. shell%pending_trap_signal /= 0) then
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
    ! Eval is now handled as a regular builtin (no special case needed)
    ! Check for cd-less navigation: if single token is a directory, treat as 'cd'
    else if (cmd%num_tokens == 1 .and. file_is_directory(trim(cmd%tokens(1)))) then
      ! Create synthetic cd command by properly reallocating tokens array
      block
        character(len=:), allocatable :: dir_path, old_tokens(:)
        integer :: token_len
        ! Save the directory path
        dir_path = trim(cmd%tokens(1))
        token_len = len(cmd%tokens)
        ! Deallocate old tokens and allocate new array with size 2
        deallocate(cmd%tokens)
        allocate(character(len=token_len) :: cmd%tokens(2))
        cmd%tokens(1) = 'cd'
        cmd%tokens(2) = dir_path
        cmd%num_tokens = 2
      end block
      call execute_builtin_with_redirects(cmd, shell)
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
      ! Check executing_trap to prevent recursion
      ! Don't execute EXIT trap here - it should only execute when shell is exiting
      if (len_trim(shell%pending_trap_command) > 0 .and. .not. shell%executing_trap .and. shell%pending_trap_signal /= 0) then
        call execute_pending_trap(shell)
      end if
    end if
    ! === END ERROR TRAP HOOK ===

    ! Handle exit status negation
    if (negate_exit_status) then
      if (shell%last_exit_status == 0) then
        shell%last_exit_status = 1
      else
        shell%last_exit_status = 0
      end if
    end if

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
      ! Check noclobber protection
      if (shell%option_noclobber .and. .not. cmd%force_clobber .and. .not. cmd%append_output) then
        ! Check if file exists
        if (file_exists(trim(cmd%output_file))) then
          write(error_unit, '(3a)') 'fortsh: ', trim(cmd%output_file), ': cannot overwrite existing file'
          shell%last_exit_status = 1
          ! Restore stdin before returning
          ret = c_dup2(saved_stdin, STDIN_FD)
          ret = c_close(saved_stdin)
          return
        end if
      end if

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
    ! Reduced from 100 to 30 elements
    character(len=MAX_TOKEN_LEN) :: array_elements(30)
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

      ! Expand variables in the value (including parameter expansions like ${var##pattern})
      ! IMPORTANT: Call expand_variables BEFORE stripping quotes, so it can apply
      ! correct backslash escape handling for double-quoted strings
      ! expand_variables will strip outer quotes automatically
      if (index(var_value, '$') > 0 .or. index(var_value, '~') > 0) then
        call expand_variables(var_value, expanded_value, shell)
        if (allocated(expanded_value)) then
          ! For expanded values, use the allocated length
          call var_set_shell_variable(shell, trim(var_name), expanded_value, len(expanded_value))
        else
          call var_set_shell_variable(shell, trim(var_name), '', 0)
        end if
      else
        ! No variable expansion needed
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
        call var_set_shell_variable(shell, trim(var_name), var_value, actual_value_len)
      end if
      ! Set exit status to 0 for successful assignments
      ! Don't overwrite error codes like 127 (readonly violation)
      if (shell%last_exit_status /= 127) then
        shell%last_exit_status = 0
      end if
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

  ! Check if a string contains escaped spaces (backslash before space)
  function has_escaped_spaces(str) result(has_escaped)
    character(len=*), intent(in) :: str
    logical :: has_escaped
    integer :: i, len_str
    character(len=1) :: backslash

    has_escaped = .false.
    len_str = len_trim(str)
    backslash = char(92)  ! ASCII code for backslash

    do i = 1, len_str - 1
      if (str(i:i) == backslash .and. str(i+1:i+1) == ' ') then
        has_escaped = .true.
        return
      end if
    end do
  end function

  ! Interpret escape sequences in IFS string (\t -> tab, \n -> newline)
  subroutine interpret_ifs_escapes(input, output)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: output
    integer :: i, j, input_len
    character(len=1) :: backslash

    backslash = char(92)  ! ASCII code for backslash
    input_len = len_trim(input)
    j = 1
    i = 1
    output = ''

    do while (i <= input_len)
      if (input(i:i) == backslash .and. i < input_len) then
        ! Check for escape sequences
        if (input(i+1:i+1) == 't') then
          ! \t -> tab
          output(j:j) = char(9)
          j = j + 1
          i = i + 2
        else if (input(i+1:i+1) == 'n') then
          ! \n -> newline
          output(j:j) = char(10)
          j = j + 1
          i = i + 2
        else if (input(i+1:i+1) == backslash) then
          ! \\ -> backslash
          output(j:j) = backslash
          j = j + 1
          i = i + 2
        else
          ! Unknown escape, keep backslash and next char
          output(j:j) = input(i:i)
          j = j + 1
          i = i + 1
        end if
      else
        ! Regular character
        output(j:j) = input(i:i)
        j = j + 1
        i = i + 1
      end if
    end do
  end subroutine

  subroutine expand_tokens(cmd, shell)
    use expansion, only: field_split
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j, num_words, total_tokens
    character(len=:), allocatable :: expanded
    character(len=1024), allocatable :: temp_tokens(:)  ! Increased to match split_words length
    logical :: is_format_string
    ! Reduced from 100 to 30 to avoid static storage (102KB -> 30KB)
    character(len=1024) :: split_words(30)
    character(len=MAX_TOKEN_LEN) :: word
    character(len=256) :: ifs_to_use
    integer :: word_count, start_pos, pos, k
    logical :: should_split, has_quotes, has_equals, has_escaped, has_ifs_char

    ! Allocate temporary storage for expanded tokens
    allocate(temp_tokens(cmd%num_tokens * 10))  ! Allocate extra space for brace expansion
    total_tokens = 0

    ! Determine IFS characters to use
    ! Interpret escape sequences in IFS (\t -> tab, \n -> newline)
    if (len_trim(shell%ifs) > 0) then
      call interpret_ifs_escapes(trim(shell%ifs), ifs_to_use)
    else
      ifs_to_use = ' '//char(9)//char(10)  ! space, tab, newline (default IFS)
    end if

    do i = 1, cmd%num_tokens
      ! Check if this token was single-quoted (no expansion)
      if (allocated(cmd%token_quote_type) .and. &
          i <= size(cmd%token_quote_type) .and. &
          cmd%token_quote_type(i) == QUOTE_SINGLE) then
        ! Single quotes - no expansion, use literal value
        expanded = cmd%tokens(i)
      else
        ! No quotes or double quotes - perform expansion
        call expand_variables(cmd%tokens(i), expanded, shell)
      end if

      ! Determine if we should split this token on IFS characters
      ! Only split if:
      ! 1. Contains IFS characters
      ! 2. NOT quoted (doesn't contain quote characters)
      ! 3. NOT an assignment (doesn't contain =, like alias ll='...' or var=value)
      ! 4. NOT escaped (doesn't contain escaped IFS chars)
      should_split = .false.

      ! Check if expanded string contains any IFS character
      has_ifs_char = .false.
      do k = 1, len(expanded)
        if (index(ifs_to_use, expanded(k:k)) > 0) then
          has_ifs_char = .true.
          exit
        end if
      end do

      if (has_ifs_char) then
        ! Check if ORIGINAL token was quoted (using metadata, not looking for quotes in string)
        if (allocated(cmd%token_quoted) .and. i <= size(cmd%token_quoted)) then
          has_quotes = cmd%token_quoted(i)
        else
          ! Fallback: Check if ORIGINAL token had quotes (not expanded, since expand_variables strips them)
          has_quotes = (index(cmd%tokens(i), '"') > 0 .or. index(cmd%tokens(i), "'") > 0)
        end if
        ! Check if it's an assignment (contains =)
        has_equals = (index(expanded, '=') > 0)
        ! Check if spaces are escaped with backslash in ORIGINAL token
        has_escaped = has_escaped_spaces(cmd%tokens(i))
        ! PARSER FIX: Check if token starts with % (printf format string)
        is_format_string = (len_trim(expanded) > 0 .and. expanded(1:1) == '%')

        ! Only split if no quotes, no equals sign, no escaped spaces, and not a format string
        should_split = (.not. has_quotes .and. .not. has_equals .and. .not. has_escaped .and. .not. is_format_string)
      end if

      if (should_split) then
        ! Split the expanded string using IFS characters
        word_count = 0
        call field_split(expanded, trim(ifs_to_use), split_words, word_count)

        ! Add all split words as separate tokens
        do j = 1, word_count
          total_tokens = total_tokens + 1
          if (total_tokens <= size(temp_tokens)) then
            temp_tokens(total_tokens) = split_words(j)
          end if
        end do
      else
        ! No IFS chars or shouldn't split, just add as single token
        total_tokens = total_tokens + 1
        if (total_tokens <= size(temp_tokens)) then
          temp_tokens(total_tokens) = expanded
        end if
      end if
    end do

    ! Replace command tokens with expanded ones
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)
    allocate(character(len=1024) :: cmd%tokens(total_tokens))  ! Match temp_tokens length
    do i = 1, total_tokens
      cmd%tokens(i) = temp_tokens(i)
    end do
    cmd%num_tokens = total_tokens

    deallocate(temp_tokens)
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
      call handle_heredoc(cmd, shell)

      ! Apply prefix assignments to environment (VAR=value command)
      call apply_prefix_assignments(cmd)

      ! Set up redirections
      call setup_redirections(cmd, shell)

      ! Execute
      call exec_child(cmd%tokens, cmd%num_tokens)
      ! Error message is printed by exec_child if command not found
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
        write(output_unit, '(a,i15,a,i15)') '[', job_id, '] ', pid
        ! Set $! to the background job PID
        shell%last_bg_pid = pid
      end if
    end if
  end subroutine

  subroutine handle_heredoc(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer, target :: pipefd(2)
    integer :: ret
    integer(c_size_t) :: bytes_written
    character(kind=c_char), target :: c_content(MAX_HEREDOC_LEN)
    integer :: i
    character(len=:), allocatable :: content_to_write
    character(len=:), allocatable :: expanded_content

    ! Handle here-string (<<<)
    if (allocated(cmd%here_string)) then
      content_to_write = cmd%here_string // char(10)  ! Add newline
    else if (allocated(cmd%heredoc_content)) then
      ! Check if we should expand variables (unquoted delimiter)
      if (.not. cmd%heredoc_quoted) then
        ! Expand variables in heredoc content
        call expand_variables(cmd%heredoc_content, expanded_content, shell)
        if (allocated(expanded_content)) then
          content_to_write = expanded_content
        else
          content_to_write = cmd%heredoc_content
        end if
      else
        ! Quoted delimiter - use content as-is
        content_to_write = cmd%heredoc_content
      end if
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

  subroutine setup_redirections(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(in) :: shell
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
      ! Check noclobber protection
      if (shell%option_noclobber .and. .not. cmd%force_clobber .and. .not. cmd%append_output) then
        ! Check if file exists
        if (file_exists(trim(cmd%output_file))) then
          write(error_unit, '(3a)') 'fortsh: ', trim(cmd%output_file), ': cannot overwrite existing file'
          call c_exit(1)
        end if
      end if

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
    use system_interface, only: file_exists, file_is_executable
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens

    type(c_ptr), target :: argv(num_tokens + 1)
    character(kind=c_char), target :: c_tokens(MAX_TOKEN_LEN+1, num_tokens)
    integer :: i, j
    integer :: ret
    logical :: is_path_command


    ! Convert tokens to C strings
    do i = 1, num_tokens
      do j = 1, len_trim(tokens(i))
        c_tokens(j, i) = tokens(i)(j:j)
      end do
      c_tokens(len_trim(tokens(i)) + 1, i) = c_null_char
      argv(i) = c_loc(c_tokens(1, i))
    end do
    argv(num_tokens + 1) = c_null_ptr

    ! Check if command is a path (contains /) before calling exec
    ! This allows us to distinguish between "file not found" (127) and "permission denied" (126)
    is_path_command = (index(trim(tokens(1)), '/') > 0)

    if (is_path_command) then
      ! For path-based commands, check if file exists and is executable
      if (file_exists(trim(tokens(1)))) then
        if (.not. file_is_executable(trim(tokens(1)))) then
          ! File exists but is not executable -> exit 126
          write(error_unit, '(a)') 'fortsh: ' // trim(tokens(1)) // ': Permission denied'
          call c_exit(126)
        end if
      end if
      ! If file doesn't exist, execvp will fail with ENOENT (exit 127 below)
    end if

    ! Execute the command
    ret = c_execvp(argv(1), c_loc(argv))

    ! If we reach here, exec failed
    call show_command_not_found_error(trim(tokens(1)))
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

            ! NOTE: Loop replay now happens inline when 'done' is processed (see line ~470)
            ! Deferred replay is no longer needed for normal loop execution
            ! This fallback might still be needed for edge cases, so leaving it commented:
            ! if (shell%control_depth == 0 .or. .not. shell%control_stack(shell%control_depth)%capturing_loop_body) then
            !   call replay_loop_if_needed(shell)
            ! end if
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
    integer :: i, iteration_count, loop_depth
    logical :: should_execute
    character(len=4) :: done_str

    ! Check if we should replay
    if (shell%control_depth == 0) return
    if (shell%control_stack(shell%control_depth)%loop_body_count == 0) return

    ! Save the loop's control depth - this won't change even if nested control structures are executed
    loop_depth = shell%control_depth
    iteration_count = 0
    done_str = 'done'

    ! Keep replaying until loop condition is false
    ! Use loop_depth instead of shell%control_depth since depth can change during loop body execution
    do while (shell%control_depth >= loop_depth .and. shell%control_stack(loop_depth)%loop_body_count > 0)
      iteration_count = iteration_count + 1
      if (iteration_count > 1000) then
        write(error_unit, '(a)') 'Loop limit reached (1000 iterations)'
        exit
      end if

      ! Temporarily stop capturing to avoid re-capturing during replay
      shell%control_stack(loop_depth)%capturing_loop_body = .false.

      do i = 1, shell%control_stack(loop_depth)%loop_body_count
        ! Check if break was requested
        if (shell%control_stack(loop_depth)%break_requested) then
          if (shell%control_stack(loop_depth)%break_level > 1) then
            ! Multi-level break: propagate to parent loop
            if (loop_depth > 1) then
              shell%control_stack(loop_depth - 1)%break_requested = .true.
              shell%control_stack(loop_depth - 1)%break_level = &
                shell%control_stack(loop_depth)%break_level - 1
            end if
          end if
          ! Clear the break flag for this level
          shell%control_stack(loop_depth)%break_requested = .false.
          shell%control_stack(loop_depth)%break_level = 0
          ! Exit the loop immediately
          shell%control_stack(loop_depth)%loop_body_count = 0  ! Signal loop end
          exit
        end if

        ! Check if continue was requested
        if (shell%control_stack(loop_depth)%continue_requested) then
          if (shell%control_stack(loop_depth)%continue_level > 1) then
            ! Multi-level continue: propagate to parent loop
            if (loop_depth > 1) then
              shell%control_stack(loop_depth - 1)%continue_requested = .true.
              shell%control_stack(loop_depth - 1)%continue_level = &
                shell%control_stack(loop_depth)%continue_level - 1
            end if
          end if
          ! Clear the continue flag for this level
          shell%control_stack(loop_depth)%continue_requested = .false.
          shell%control_stack(loop_depth)%continue_level = 0
          ! Skip the rest of the iteration
          exit
        end if

        call parse_pipeline(shell%control_stack(loop_depth)%loop_body(i), pipeline)
        if (pipeline%num_commands > 0) then
          call execute_pipeline(pipeline, shell, shell%control_stack(loop_depth)%loop_body(i))
        end if
      end do

      ! Re-enable capturing for next iteration
      shell%control_stack(loop_depth)%capturing_loop_body = .true.

      ! Check if loop_body_count is 0 (break was called)
      if (shell%control_stack(loop_depth)%loop_body_count == 0) then
        ! Break was called, exit the loop
        exit
      end if

      ! Simulate 'done' to check loop condition and update state
      call parse_pipeline(done_str, done_pipeline)
      if (done_pipeline%num_commands > 0) then
        done_cmd = done_pipeline%commands(1)
        call process_control_flow(done_cmd, shell, should_execute)
        ! If control_depth decreased below loop_depth, loop ended
        if (shell%control_depth < loop_depth) then
          exit
        end if
        ! Also exit if loop_body_count became 0 (break was called)
        if (shell%control_stack(loop_depth)%loop_body_count == 0) then
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
    integer :: num_tokens, i, saved_depth

    ! POSIX: Suppress errexit during condition evaluation (if/while/until test expressions)
    shell%evaluating_condition = .true.

    ! Save control depth and temporarily reset to 0 so condition executes unconditionally
    ! This prevents should_execute_command() from blocking condition evaluation
    saved_depth = shell%control_depth
    shell%control_depth = 0

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

    ! Restore control depth
    shell%control_depth = saved_depth

    ! Re-enable errexit checking
    shell%evaluating_condition = .false.
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

  ! Check if command is a function definition and register it
  function is_function_definition_command(cmd, shell) result(is_func_def)
    use variables, only: add_function
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical :: is_func_def

    character(len=256) :: func_name
    character(len=2048) :: reconstructed
    ! Reduced from 100 to 50 lines to avoid static storage
    character(len=1024) :: func_body(50)
    integer :: body_count, brace_start, brace_end, paren_pos

    is_func_def = .false.

    ! Check if we have enough tokens
    if (cmd%num_tokens < 1) return

    ! Reconstruct the full command to analyze it
    call reconstruct_command_from_tokens(cmd, reconstructed)

    ! Check for pattern: name() { body }
    ! Look for () followed by {
    paren_pos = index(reconstructed, '()')
    if (paren_pos == 0) return

    ! Extract function name (everything before ())
    func_name = adjustl(reconstructed(1:paren_pos-1))
    if (len_trim(func_name) == 0) return

    ! Check if there's a { after the ()
    brace_start = index(reconstructed(paren_pos:), '{')
    if (brace_start == 0) return
    brace_start = paren_pos + brace_start - 1

    ! Find matching }
    brace_end = index(reconstructed(brace_start:), '}')
    if (brace_end == 0) return
    brace_end = brace_start + brace_end - 1

    ! Extract function body (between { and })
    if (brace_end > brace_start + 1) then
      body_count = 1
      func_body(1) = trim(adjustl(reconstructed(brace_start+1:brace_end-1)))
    else
      body_count = 0
    end if

    ! Register the function
    call add_function(shell, trim(func_name), func_body, body_count)

    is_func_def = .true.
  end function

  ! Process backslash escapes in all command tokens
  ! This should be called AFTER glob expansion
  subroutine process_command_escapes(cmd)
    type(command_t), intent(inout) :: cmd
    integer :: i, j, k, token_len
    character(len=MAX_TOKEN_LEN) :: result
    logical :: in_quotes
    character(len=1) :: quote_char, backslash

    backslash = char(92)  ! ASCII for backslash

    do i = 1, cmd%num_tokens
      token_len = len_trim(cmd%tokens(i))
      result = ''
      k = 0  ! Count of characters written to result
      j = 1
      in_quotes = .false.
      quote_char = ' '

      do while (j <= token_len)
        ! Track quote state
        if (.not. in_quotes .and. (cmd%tokens(i)(j:j) == '"' .or. cmd%tokens(i)(j:j) == "'")) then
          in_quotes = .true.
          quote_char = cmd%tokens(i)(j:j)
          k = k + 1
          result(k:k) = cmd%tokens(i)(j:j)
          j = j + 1
        else if (in_quotes .and. cmd%tokens(i)(j:j) == quote_char) then
          in_quotes = .false.
          k = k + 1
          result(k:k) = cmd%tokens(i)(j:j)
          j = j + 1
        else if (.not. in_quotes .and. cmd%tokens(i)(j:j) == backslash .and. j < token_len) then
          ! Check what character follows the backslash
          ! Only process structural escapes (space, glob characters)
          if (cmd%tokens(i)(j+1:j+1) == ' ' .or. &
              cmd%tokens(i)(j+1:j+1) == '*' .or. &
              cmd%tokens(i)(j+1:j+1) == '?' .or. &
              cmd%tokens(i)(j+1:j+1) == '[') then
            ! Structural escape - skip backslash, keep next char
            j = j + 1
            k = k + 1
            result(k:k) = cmd%tokens(i)(j:j)
            j = j + 1
          else
            ! Non-structural escape (like \n, \t) - keep both backslash and next char
            k = k + 1
            result(k:k) = backslash
            j = j + 1
            if (j <= token_len) then
              k = k + 1
              result(k:k) = cmd%tokens(i)(j:j)
              j = j + 1
            end if
          end if
        else
          ! Regular character
          k = k + 1
          result(k:k) = cmd%tokens(i)(j:j)
          j = j + 1
        end if
      end do

      ! Only copy the actual content (k characters)
      if (k > 0) then
        cmd%tokens(i) = result(1:k)
      else
        cmd%tokens(i) = ''
      end if
    end do
  end subroutine

  ! Execute subshell ( cmd1; cmd2 )
  ! Forks a child process and executes commands in isolated environment
  subroutine execute_subshell(content, shell, original_input)
    character(len=*), intent(in) :: content
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input

    integer(c_pid_t) :: pid
    integer(c_int), target :: wait_status
    integer :: ret
    type(pipeline_t) :: subshell_pipeline
    integer :: i

    pid = c_fork()

    if (pid < 0) then
      write(error_unit, '(a)') 'Error: fork failed for subshell'
      shell%last_exit_status = 1
    else if (pid == 0) then
      ! Child process (subshell)
      ! Parse and execute the subshell content
      call parse_pipeline(content, subshell_pipeline)
      if (subshell_pipeline%num_commands > 0) then
        call execute_pipeline(subshell_pipeline, shell, content)
      end if
      ! Exit with the last command's exit status
      call c_exit(int(shell%last_exit_status, c_int))
    else
      ! Parent process - wait for subshell
      shell%last_pid = pid
      ret = c_waitpid(pid, c_loc(wait_status), 0)

      if (WIFEXITED(wait_status)) then
        shell%last_exit_status = WEXITSTATUS(wait_status)
      else
        shell%last_exit_status = 1
      end if
    end if
  end subroutine

  ! Apply prefix assignments to environment (VAR=value command)
  ! Called in child process before exec to set environment variables
  ! scoped to the command execution
  subroutine apply_prefix_assignments(cmd)
    type(command_t), intent(in) :: cmd
    integer :: i, eq_pos, ret
    character(len=256) :: var_name, var_value
    character(len=256), target :: c_var_name, c_var_value

    ! Iterate through all prefix assignments
    do i = 1, cmd%num_prefix_assignments
      ! Find the '=' separator
      eq_pos = index(cmd%prefix_assignments(i), '=')

      if (eq_pos > 1) then
        ! Extract variable name and value
        var_name = cmd%prefix_assignments(i)(:eq_pos-1)
        var_value = cmd%prefix_assignments(i)(eq_pos+1:)

        ! Convert to C strings with null terminator
        c_var_name = trim(var_name)//c_null_char
        c_var_value = trim(var_value)//c_null_char

        ! Set environment variable (overwrite=1 to replace existing values)
        ret = c_setenv(c_loc(c_var_name), c_loc(c_var_value), 1_c_int)
        ! Note: We ignore the return value here since we're in a child process
        ! and any errors will be reflected in the command's execution
      end if
    end do
  end subroutine

  ! Process sourced files inline (for dot command in non-interactive mode)
  subroutine process_source_inline(shell)
    use variables, only: set_shell_variable
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

      ! Expand aliases (simple version - just use the line as-is)
      expanded_line = trim(input_line)

      ! Parse and execute pipeline
      call parse_pipeline(expanded_line, pipeline)

      if (pipeline%num_commands > 0) then
        call execute_pipeline(pipeline, shell, expanded_line)

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
  end subroutine process_source_inline

end module executor