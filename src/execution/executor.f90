! ==============================================================================
! Module: executor (Extended with job control)
! ==============================================================================
module executor
  use shell_types
  use system_interface
  use builtin_interface
  use parser
  use job_control
  use pipeline_helpers, only: expand_tokens, expand_command_globs, process_command_escapes
  use variables, only: var_set_shell_variable => set_shell_variable, set_array_variable, set_array_element, &
                       get_shell_variable
  use control_flow
  use error_handling
  use performance
  use aliases, only: expand_alias, is_alias, get_alias
  use shell_options
  use signal_handling, only: execute_trap, TRAP_DEBUG, TRAP_ERR
  use better_errors
  use completion, only: register_completion_executor, completion_func_executor_t
  use iso_fortran_env, only: error_unit, input_unit
  use iso_c_binding
  implicit none

  public :: init_completion_executor

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

  ! DEPRECATED: Legacy pipeline execution path, only used by FORTSH_USE_OLD_PARSER=1.
  ! The AST executor (ast_executor.f90::execute_pipeline_node) is the primary pipeline
  ! implementation with full feature parity. This subroutine will be removed when the
  ! legacy parser path is retired.
  subroutine execute_pipe_chain(pipeline, start_idx, shell, original_input)
    type(pipeline_t), intent(inout) :: pipeline
    integer, intent(in) :: start_idx
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input

    integer :: i, j, pipe_count, end_idx
    integer(c_int), allocatable :: pipefd(:,:)
    integer(c_pid_t), allocatable :: pids(:)
    integer(c_pid_t) :: pgid
    integer :: ret, job_id
    logical :: foreground
    type(c_funptr) :: old_handler
    type(pipeline_t) :: group_pipeline
    integer :: k
    character(len=2048) :: reconstructed_cmd

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

    ! Trace all pipeline commands BEFORE forking (so order is deterministic)
    if (shell%option_xtrace) then
      do i = start_idx, end_idx
        if (pipeline%commands(i)%num_tokens > 0) then
          call reconstruct_command_from_tokens(pipeline%commands(i), reconstructed_cmd)
          call trace_command(shell, trim(reconstructed_cmd))
        end if
      end do
    end if

    ! Flush all output before forking to prevent buffer duplication
    flush(output_unit)
    flush(error_unit)

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
        old_handler = c_signal(SIGPIPE, c_null_funptr)
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

        ! Expand variables and execute (unless pre-expanded in pipeline)
        if (.not. pipeline%commands(i)%skip_expansion) then
          call expand_tokens(pipeline%commands(i), shell)
        end if

        ! Expand glob patterns
        call expand_command_globs(pipeline%commands(i), shell)

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
      ! Only print job notification in interactive mode
      if (shell%is_interactive) then
        write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pgid
      end if
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
    integer :: i, ret
    integer, allocatable :: exit_statuses(:)

    allocate(exit_statuses(num_processes))

    ! Wait for all processes and collect their exit statuses
    do i = 1, num_processes
      ret = c_waitpid(pids(i), c_loc(status), WUNTRACED)
      if (ret > 0) then
        if (WIFEXITED(status)) then
          exit_statuses(i) = WEXITSTATUS(status)
        else if (WIFSIGNALED(status)) then
          exit_statuses(i) = 128 + WTERMSIG(status)
        else
          exit_statuses(i) = 1
        end if
      else
        exit_statuses(i) = 1
      end if
    end do

    ! Set exit status according to POSIX/bash rules
    if (shell%option_pipefail) then
      ! pipefail: return rightmost non-zero exit status (bash-correct semantics)
      shell%last_exit_status = 0
      do i = num_processes, 1, -1
        if (exit_statuses(i) /= 0) then
          shell%last_exit_status = exit_statuses(i)
          exit
        end if
      end do
    else
      ! Normal: return exit status of last (rightmost) command
      shell%last_exit_status = exit_statuses(num_processes)
    end if

    deallocate(exit_statuses)
  end subroutine

  recursive subroutine execute_single(cmd, shell, original_input)
    use control_flow, only: capture_loop_command, is_control_flow_keyword
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    logical :: should_execute, trap_executed, negate_exit_status
    integer(int64) :: exec_start_time
    integer :: i
    character(len=256) :: reconstructed_cmd
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

    ! Check for empty command (e.g., from empty command substitution result)
    if (len_trim(cmd%tokens(1)) == 0) then
      ! Empty command - nothing to execute
      ! Note: exit status from command substitution is preserved
      return
    end if

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
      call read_heredoc(cmd%heredoc_delimiter, cmd%heredoc_content, shell, cmd%heredoc_strip_tabs)
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
    ! Also skip if already pre-expanded in pipeline
    if (.not. cmd%skip_expansion .and. &
        trim(cmd%tokens(1)) /= 'defun' .and. &
        .not. (index(cmd%tokens(1), '=') > 0 .and. index(cmd%tokens(1), '=') > 1)) then
      ! Initialize token metadata if not set (for old parser path)
      call init_token_metadata(cmd)
      call expand_tokens(cmd, shell)
    end if

    ! All tokens removed by expansion (e.g., unquoted $(exit 5) expands to nothing)
    ! Preserve exit status from command substitution and return
    if (cmd%num_tokens == 0) then
      call end_timer('execute_single', exec_start_time, total_exec_time)
      return
    end if

    ! Check if parameter expansion error occurred (${VAR?error})
    if (shell%fatal_expansion_error) then
      ! NOTE: Don't reset flag here - let it propagate to subshell handler
      ! The subshell code uses this flag to convert exit code 127 to 1 (bash behavior)
      ! End performance timing
      call end_timer('execute_single', exec_start_time, total_exec_time)
      ! POSIX: In non-interactive shells, exit the shell entirely
      if (.not. shell%is_interactive) then
        shell%running = .false.
      end if
      return  ! Abort command execution
    end if

    ! Check if arithmetic expansion error occurred
    if (shell%arithmetic_error) then
      shell%arithmetic_error = .false.  ! Reset flag
      ! End performance timing
      call end_timer('execute_single', exec_start_time, total_exec_time)
      return  ! Abort command execution
    end if

    ! Check for empty command after expansion (e.g., $(exit 0) returns empty)
    if (cmd%num_tokens > 0 .and. len_trim(cmd%tokens(1)) == 0) then
      ! Empty command after expansion - nothing to execute
      ! Note: exit status from command substitution is preserved
      call end_timer('execute_single', exec_start_time, total_exec_time)
      return
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
      call expand_command_globs(cmd, shell)
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
    ! Only recognize as assignment if name before = is valid (no $, `, etc.)
    ! POSIX: Words containing $ before = are not assignments, they're commands
    if (index(cmd%tokens(1), '=') > 0 .and. index(cmd%tokens(1), '=') > 1 .and. &
        index(cmd%tokens(1)(1:index(cmd%tokens(1), '=')-1), '$') == 0) then
      call execute_assignment(cmd, shell)
    ! Check for ((expression)) arithmetic evaluation command
    else if (len_trim(cmd%tokens(1)) >= 4 .and. &
        cmd%tokens(1)(1:2) == '((' .and. &
        cmd%tokens(1)(len_trim(cmd%tokens(1))-1:len_trim(cmd%tokens(1))) == '))') then
      call execute_arithmetic_command(cmd, shell)
    ! Check if it's a user-defined function (unless bypass_functions is set)
    else if (.not. shell%bypass_functions .and. is_function(shell, cmd%tokens(1))) then
      call execute_function(cmd, shell)
    ! Eval is now handled as a regular builtin (no special case needed)
    ! Check for cd-less navigation: if single token is a directory, treat as 'cd'
    else if (cmd%num_tokens == 1 .and. file_is_directory(trim(cmd%tokens(1)))) then
      ! Create synthetic cd command by properly reallocating tokens array
      block
        character(len=:), allocatable :: dir_path
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
    ! Check for alias expansion (unless bypass_aliases is set by 'command' builtin)
    ! POSIX: Aliases are only expanded in interactive shells
    else if (shell%is_interactive .and. .not. shell%bypass_aliases .and. is_alias(shell, cmd%tokens(1))) then
      block
        character(len=:), allocatable :: alias_command, expanded_command
        character(len=4096) :: rest_of_command
        integer :: j
        type(pipeline_t) :: alias_pipeline

        ! Get the alias command
        alias_command = get_alias(shell, cmd%tokens(1))

        ! Build the rest of the command (arguments after the aliased command)
        rest_of_command = ''
        do j = 2, cmd%num_tokens
          if (j > 2) rest_of_command = trim(rest_of_command) // ' '
          rest_of_command = trim(rest_of_command) // trim(cmd%tokens(j))
        end do

        ! Combine alias expansion with rest of arguments
        if (len_trim(rest_of_command) > 0) then
          expanded_command = trim(alias_command) // ' ' // trim(rest_of_command)
        else
          expanded_command = trim(alias_command)
        end if

        ! Parse the expanded command
        call parse_pipeline(expanded_command, alias_pipeline)

        if (alias_pipeline%num_commands > 0) then
          ! Execute the expanded command
          if (alias_pipeline%num_commands == 1) then
            ! Single command - execute it directly with current redirections
            ! Copy over any redirections from the original command
            if (allocated(cmd%input_file)) then
              alias_pipeline%commands(1)%input_file = cmd%input_file
            end if
            if (allocated(cmd%output_file)) then
              alias_pipeline%commands(1)%output_file = cmd%output_file
              alias_pipeline%commands(1)%append_output = cmd%append_output
              alias_pipeline%commands(1)%force_clobber = cmd%force_clobber
            end if
            if (allocated(cmd%error_file)) then
              alias_pipeline%commands(1)%error_file = cmd%error_file
              alias_pipeline%commands(1)%append_error = cmd%append_error
            end if
            ! Copy other redirection flags
            alias_pipeline%commands(1)%redirect_stderr_to_stdout = cmd%redirect_stderr_to_stdout
            alias_pipeline%commands(1)%redirect_stdout_to_stderr = cmd%redirect_stdout_to_stderr
            alias_pipeline%commands(1)%redirect_both_to_file = cmd%redirect_both_to_file
            if (allocated(cmd%here_string)) then
              alias_pipeline%commands(1)%here_string = cmd%here_string
            end if
            if (allocated(cmd%heredoc_delimiter)) then
              alias_pipeline%commands(1)%heredoc_delimiter = cmd%heredoc_delimiter
              alias_pipeline%commands(1)%heredoc_content = cmd%heredoc_content
              alias_pipeline%commands(1)%heredoc_quoted = cmd%heredoc_quoted
            end if

            ! Execute the single command recursively
            call execute_single(alias_pipeline%commands(1), shell, expanded_command)
          else
            ! Multiple commands - execute as pipeline
            call execute_pipeline(alias_pipeline, shell, expanded_command)
          end if

          ! Clean up
          do j = 1, alias_pipeline%num_commands
            if (allocated(alias_pipeline%commands(j)%tokens)) deallocate(alias_pipeline%commands(j)%tokens)
            if (allocated(alias_pipeline%commands(j)%input_file)) deallocate(alias_pipeline%commands(j)%input_file)
            if (allocated(alias_pipeline%commands(j)%output_file)) deallocate(alias_pipeline%commands(j)%output_file)
            if (allocated(alias_pipeline%commands(j)%error_file)) deallocate(alias_pipeline%commands(j)%error_file)
            if (allocated(alias_pipeline%commands(j)%heredoc_delimiter)) deallocate(alias_pipeline%commands(j)%heredoc_delimiter)
            if (allocated(alias_pipeline%commands(j)%heredoc_content)) deallocate(alias_pipeline%commands(j)%heredoc_content)
            if (allocated(alias_pipeline%commands(j)%here_string)) deallocate(alias_pipeline%commands(j)%here_string)
            if (allocated(alias_pipeline%commands(j)%group_content)) deallocate(alias_pipeline%commands(j)%group_content)
          end do
          if (allocated(alias_pipeline%commands)) deallocate(alias_pipeline%commands)
        end if
      end block
    else if (is_builtin(cmd%tokens(1))) then
      call execute_builtin_with_redirects(cmd, shell)
    else
      ! Check for command_not_found_handle before executing external
      if (.not. shell%bypass_functions .and. &
          is_function(shell, 'command_not_found_handle') .and. &
          index(trim(cmd%tokens(1)), '/') == 0) then
        block
          logical :: cmd_found
          integer :: ii
          character(len=4096) :: path_var, candidate
          character(len=:), allocatable :: path_dir
          integer :: spos, cpos

          ! Inline PATH search to avoid command_builtin dependency
          cmd_found = .false.
          path_var = get_shell_variable(shell, 'PATH')
          if (len_trim(path_var) == 0) path_var = '/usr/bin:/bin'
          spos = 1
          do while (spos <= len_trim(path_var) .and. .not. cmd_found)
            cpos = index(path_var(spos:), ':')
            if (cpos == 0) then
              path_dir = path_var(spos:len_trim(path_var))
              spos = len_trim(path_var) + 1
            else
              path_dir = path_var(spos:spos + cpos - 2)
              spos = spos + cpos
            end if
            if (len_trim(path_dir) == 0) path_dir = '.'
            write(candidate, '(a,a,a)') trim(path_dir), '/', trim(cmd%tokens(1))
            cmd_found = file_exists(trim(candidate))
          end do

          if (.not. cmd_found) then
            ! Build handler call string and dispatch via AST pipeline
            ! (command_not_found_handle is an AST-cached function from eval)
            block
              use trap_dispatch, only: eval_trap_string
              character(len=4096) :: handler_str
              integer :: handler_exit

              handler_str = 'command_not_found_handle'
              do ii = 1, cmd%num_tokens
                handler_str = trim(handler_str) // ' ' // trim(cmd%tokens(ii))
              end do
              call eval_trap_string(trim(handler_str), shell, handler_exit)
            end block
          else
            call execute_external(cmd, shell, original_input)
          end if
        end block
      else
        call execute_external(cmd, shell, original_input)
      end if
    end if

    ! === ERROR TRAP HOOK ===
    ! Execute ERR trap if command failed (after command execution)
    ! POSIX: ERR trap suppressed in same contexts as errexit:
    ! - || / && lists, if/while/until conditions, negation (!)
    if (shell%last_exit_status /= 0 .and. &
        .not. shell%evaluating_condition .and. &
        .not. shell%in_and_or_list .and. &
        .not. shell%in_negation) then
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
    integer :: fd, ret, flags, i
    integer, target :: pipefd(2)
    integer(c_size_t) :: bytes_written
    character(len=256), target :: c_filename
    character(kind=c_char), target :: c_content(MAX_HEREDOC_LEN)
    character(len=:), allocatable :: content_to_write, expanded_content
    logical :: has_redirects, has_heredoc
    ! Prefix assignment handling
    character(len=MAX_TOKEN_LEN), allocatable :: saved_var_names(:), saved_var_values(:)
    integer :: num_saved_vars, eq_pos, j
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    logical, allocatable :: var_was_set(:)

    ! Apply prefix assignments to shell variables (save old values first)
    num_saved_vars = 0
    if (allocated(cmd%prefix_assignments)) then
    allocate(saved_var_names(cmd%num_prefix_assignments))
    allocate(saved_var_values(cmd%num_prefix_assignments))
    allocate(var_was_set(cmd%num_prefix_assignments))
    do j = 1, cmd%num_prefix_assignments
      eq_pos = index(cmd%prefix_assignments(j), '=')
      if (eq_pos > 1) then
        num_saved_vars = num_saved_vars + 1
        var_name = cmd%prefix_assignments(j)(:eq_pos-1)
        var_value = cmd%prefix_assignments(j)(eq_pos+1:)
        saved_var_names(num_saved_vars) = trim(var_name)
        ! Save old value (empty string if not set)
        saved_var_values(num_saved_vars) = get_shell_variable(shell, trim(var_name))
        var_was_set(num_saved_vars) = (len_trim(saved_var_values(num_saved_vars)) > 0)
        ! Set new value
        call var_set_shell_variable(shell, trim(var_name), trim(var_value))
      end if
    end do
    end if  ! allocated(prefix_assignments)

    ! Check if we have any redirections
    has_redirects = allocated(cmd%output_file) .or. allocated(cmd%input_file) .or. &
                    allocated(cmd%error_file) .or. cmd%redirect_stderr_to_stdout .or. &
                    cmd%redirect_stdout_to_stderr
    has_heredoc = allocated(cmd%heredoc_content) .or. allocated(cmd%here_string)

    if (.not. has_redirects .and. .not. has_heredoc) then
      ! No redirections, just execute the builtin normally
      call execute_builtin(cmd, shell)
      ! Restore prefix assignment variables
      do j = 1, num_saved_vars
        if (var_was_set(j)) then
          call var_set_shell_variable(shell, trim(saved_var_names(j)), trim(saved_var_values(j)))
        else
          ! Variable wasn't set before, we should unset it
          ! For now, just set to empty (proper unset would need more work)
          call var_set_shell_variable(shell, trim(saved_var_names(j)), '')
        end if
      end do
      return
    end if

    ! Save current file descriptors
    saved_stdout = c_dup(STDOUT_FD)
    saved_stdin = c_dup(STDIN_FD)
    saved_stderr = c_dup(STDERR_FD)

    ! Handle heredoc/here-string input (redirects stdin)
    if (has_heredoc) then
      ! Prepare content to write
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
      end if

      ! Create pipe and redirect stdin
      if (allocated(content_to_write)) then
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
      end if
    end if

    ! Handle input redirection (file)
    if (allocated(cmd%input_file)) then
      c_filename = trim(cmd%input_file)//c_null_char
      fd = c_open(c_loc(c_filename), O_RDONLY, 0)
      if (fd >= 0) then
        ret = c_dup2(fd, STDIN_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'fortsh: cannot open input file: ', trim(cmd%input_file)
        shell%last_exit_status = 1
        ! Restore prefix assignment variables before returning
        do j = 1, num_saved_vars
          if (var_was_set(j)) then
            call var_set_shell_variable(shell, trim(saved_var_names(j)), trim(saved_var_values(j)))
          else
            call var_set_shell_variable(shell, trim(saved_var_names(j)), '')
          end if
        end do
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
          ! Restore prefix assignment variables before returning
          do j = 1, num_saved_vars
            if (var_was_set(j)) then
              call var_set_shell_variable(shell, trim(saved_var_names(j)), trim(saved_var_values(j)))
            else
              call var_set_shell_variable(shell, trim(saved_var_names(j)), '')
            end if
          end do
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
        ! Restore prefix assignment variables before returning
        do j = 1, num_saved_vars
          if (var_was_set(j)) then
            call var_set_shell_variable(shell, trim(saved_var_names(j)), trim(saved_var_values(j)))
          else
            call var_set_shell_variable(shell, trim(saved_var_names(j)), '')
          end if
        end do
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
        ! Restore prefix assignment variables before returning
        do j = 1, num_saved_vars
          if (var_was_set(j)) then
            call var_set_shell_variable(shell, trim(saved_var_names(j)), trim(saved_var_values(j)))
          else
            call var_set_shell_variable(shell, trim(saved_var_names(j)), '')
          end if
        end do
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

    ! Restore prefix assignment variables
    do j = 1, num_saved_vars
      if (var_was_set(j)) then
        call var_set_shell_variable(shell, trim(saved_var_names(j)), trim(saved_var_values(j)))
      else
        ! Variable wasn't set before, set to empty
        call var_set_shell_variable(shell, trim(saved_var_names(j)), '')
      end if
    end do
  end subroutine

  ! Execute ((expression)) arithmetic evaluation command
  ! Sets exit status to 0 if expression is non-zero, 1 if zero
  subroutine execute_arithmetic_command(cmd, shell)
    use expansion, only: arithmetic_expansion_shell
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: expr, result_str
    character(len=:), allocatable :: arith_expr
    integer(kind=8) :: result_val
    integer :: iostat

    ! Build full expression from all tokens
    expr = trim(cmd%tokens(1))

    ! Convert ((expr)) to $((expr)) for arithmetic_expansion_shell
    arith_expr = '$' // trim(expr)

    ! Evaluate arithmetic expression
    result_str = arithmetic_expansion_shell(trim(arith_expr), shell)

    ! Check if there was an error (empty result indicates error)
    if (len_trim(result_str) == 0) then
      ! There was an arithmetic error, exit status already set by arithmetic_expansion_shell
      ! Just return without changing it
      return
    end if

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
    ! Heap-allocated to avoid static storage in recursive context
    character(len=MAX_TOKEN_LEN), allocatable :: array_elements(:)
    character(len=100) :: index_str
    character(len=:), allocatable :: expanded_value
    integer :: eq_pos, paren_start, paren_end, num_elements, bracket_pos
    integer :: bracket_end, array_index, read_status, actual_value_len, i, token_len
    logical :: is_indexed_assignment
    character(len=1) :: quote_char_temp

    allocate(array_elements(30))

    ! For quoted tokens, preserve whitespace by not trimming
    ! For unquoted tokens, trim is safe
    ! NOTE: Check allocation first to avoid accessing unallocated arrays
    if (allocated(cmd%token_quoted) .and. allocated(cmd%token_lengths)) then
      if (size(cmd%token_quoted) >= 1 .and. cmd%token_quoted(1)) then
        ! Quoted token - preserve whitespace, track actual length
        ! Use token_lengths array if available, otherwise fall back to len()
        if (size(cmd%token_lengths) >= 1) then
          token_len = cmd%token_lengths(1)
        else
          token_len = len(cmd%tokens(1))
        end if
        token = cmd%tokens(1)
      else
        ! Token arrays allocated but this token not quoted - use standard processing
        token = cmd%tokens(1)
        token_len = len_trim(token)
      end if
    else
      ! Old parser: token may contain quotes with whitespace inside
      ! We need to find the actual token end, not use len_trim which strips whitespace
      token = cmd%tokens(1)

      ! Find the = sign to check if value is quoted
      eq_pos = index(token, '=')
      if (eq_pos > 0 .and. eq_pos < len(token)) then
        ! Check if value starts with a quote
        if (token(eq_pos+1:eq_pos+1) == '"' .or. token(eq_pos+1:eq_pos+1) == "'") then
          quote_char_temp = token(eq_pos+1:eq_pos+1)
          ! Find the closing quote to determine actual length
          do i = eq_pos + 2, len(token)
            if (token(i:i) == quote_char_temp) then
              token_len = i
              exit
            end if
          end do
          ! If no closing quote found, fall back to len_trim
          if (i > len(token)) then
            token_len = len_trim(token)
          end if
        else
          ! Unquoted value - trim is safe
          token_len = len_trim(token)
        end if
      else
        token_len = len_trim(token)
      end if
    end if
    eq_pos = index(token, '=')
    if (eq_pos == 0) return

    ! Check for array index assignment: arr[index]=value
    bracket_pos = index(token, '[')
    is_indexed_assignment = (bracket_pos > 0 .and. bracket_pos < eq_pos)

    if (is_indexed_assignment) then
      ! arr[index]=value
      var_name = token(:bracket_pos-1)
      bracket_end = index(token(bracket_pos:token_len), ']')
      if (bracket_end > 0) then
        bracket_end = bracket_pos + bracket_end - 1
        index_str = token(bracket_pos+1:bracket_end-1)
        var_value = token(eq_pos+1:token_len)

        ! Strip quotes and lexer sentinel chars from array subscript
        block
          use variables, only: strip_quotes
          character(len=100) :: clean_key
          integer :: ci, co
          call strip_quotes(index_str)
          ! Remove sentinel chars (char(1), char(2), char(3))
          co = 0
          clean_key = ''
          do ci = 1, len_trim(index_str)
            if (ichar(index_str(ci:ci)) > 3) then
              co = co + 1
              clean_key(co:co) = index_str(ci:ci)
            end if
          end do
          index_str = clean_key
        end block

        ! Expand variables/command substitutions in value
        if (index(var_value, '$') > 0 .or. index(var_value, '~') > 0) then
          block
            use parser, only: expand_variables
            call expand_variables(var_value, expanded_value, shell)
            if (allocated(expanded_value)) then
              var_value = expanded_value
            end if
          end block
        end if

        ! Check associative array first (numeric keys are valid)
        block
          use variables, only: is_associative_array, set_assoc_array_value
          if (is_associative_array(shell, trim(var_name))) then
            call set_assoc_array_value(shell, trim(var_name), &
              trim(index_str), trim(var_value))
            shell%last_exit_status = 0
          else
            ! Parse as numeric index (0-indexed → 1-indexed)
            read(index_str, *, iostat=read_status) array_index
            if (read_status == 0) then
              array_index = array_index + 1
              call set_array_element(shell, trim(var_name), &
                array_index, trim(var_value))
              shell%last_exit_status = 0
            else
              write(error_unit, '(a)') &
                'Error: invalid array index'
              shell%last_exit_status = 1
            end if
          end if
        end block
      else
        write(error_unit, '(a)') 'Error: unclosed bracket in array assignment'
        shell%last_exit_status = 1
      end if
      return
    end if

    ! Get variable name (before =)
    var_name = token(:eq_pos-1)

    ! Check for += append syntax: arr+=(...)
    block
      logical :: is_append
      is_append = .false.
      if (eq_pos >= 2 .and. token(eq_pos-1:eq_pos-1) == '+') then
        is_append = .true.
        var_name = token(:eq_pos-2)
      end if

    ! Check if it's an array literal: arr=(...) or arr+=(...)
    paren_start = eq_pos + 1
    if (paren_start <= token_len .and. token(paren_start:paren_start) == '(') then
      ! Array literal
      paren_end = index(token(paren_start+1:token_len), ')')
      if (paren_end > 0) then
        paren_end = paren_start + paren_end
        ! Extract elements between parentheses
        var_value = token(paren_start+1:paren_end-1)

        ! Expand command substitutions and variables
        if (index(trim(var_value), '$') > 0 .or. &
            index(trim(var_value), '`') > 0) then
          block
            use parser, only: expand_variables
            character(len=:), allocatable :: arr_exp
            call expand_variables(trim(var_value), &
              arr_exp, shell)
            if (allocated(arr_exp)) then
              var_value = arr_exp
            end if
          end block
        end if

        ! Split by spaces to get array elements
        num_elements = 0
        call split_array_elements(var_value, array_elements, num_elements)

        if (is_append) then
          ! Append to existing array
          block
            integer :: existing_size, k
            existing_size = get_array_size(shell, trim(var_name))
            do k = 1, num_elements
              call set_array_element(shell, trim(var_name), &
                existing_size + k, trim(array_elements(k)))
            end do
          end block
        else
          ! Set as array variable
          call set_array_variable(shell, trim(var_name), &
            array_elements, num_elements)
        end if
        shell%last_exit_status = 0
      else
        write(error_unit, '(a)') 'Error: unclosed array literal'
        shell%last_exit_status = 1
      end if
    else
      ! Simple assignment: var=value
      ! Use token_len to avoid including padding for quoted tokens
      var_value = token(eq_pos+1:token_len)

      ! Expand variables in the value (including parameter expansions like ${var##pattern})
      ! IMPORTANT: Call expand_variables BEFORE stripping quotes, so it can apply
      ! correct backslash escape handling for double-quoted strings
      ! expand_variables will strip outer quotes automatically
      if (index(var_value, '$') > 0 .or. index(var_value, '~') > 0) then
        call expand_variables(var_value, expanded_value, shell)

        ! Check if arithmetic expansion error occurred
        if (shell%arithmetic_error) then
          shell%arithmetic_error = .false.  ! Reset flag
          shell%last_exit_status = 127  ! POSIX sh returns 127 for arithmetic errors
          return  ! Abort assignment
        end if

        ! POSIX: Exit status of assignment with command substitution is from last substitution
        ! Don't overwrite the exit status that was set by execute_command_and_capture

        if (allocated(expanded_value)) then
          ! For expanded values, use the allocated length
          call var_set_shell_variable(shell, trim(var_name), expanded_value, len(expanded_value))
        else
          call var_set_shell_variable(shell, trim(var_name), '', 0)
        end if
      else
        ! No variable expansion needed
        ! Calculate actual length from token positions (NOT len_trim, to preserve whitespace)
        actual_value_len = token_len - eq_pos

        ! Strip outer quotes if present (old parser keeps quotes in tokens)
        if (actual_value_len >= 2) then
          if ((var_value(1:1) == '"' .and. &
               var_value(actual_value_len:actual_value_len) == '"') &
              .or. (var_value(1:1) == "'" .and. &
               var_value(actual_value_len:actual_value_len) == "'")) &
              then
            ! Remove quotes and adjust length
            var_value = var_value(2:actual_value_len-1)
            actual_value_len = actual_value_len - 2
          end if
        end if

        ! Check for integer attribute: evaluate as arithmetic
        block
          logical :: is_int_var
          is_int_var = .false.
          do i = 1, shell%num_variables
            if (trim(shell%variables(i)%name) == &
                trim(var_name)) then
              is_int_var = shell%variables(i)%is_integer
              exit
            end if
          end do
          if (is_int_var .and. actual_value_len > 0) then
            block
              use expansion, only: arithmetic_expansion_shell
              character(len=:), allocatable :: arith_expr, arith_result
              arith_expr = '$((' // &
                var_value(:actual_value_len) // '))'
              arith_result = &
                arithmetic_expansion_shell( &
                  trim(arith_expr), shell)
              var_value = arith_result
              actual_value_len = len_trim(var_value)
            end block
          end if
        end block

        call var_set_shell_variable(shell, trim(var_name), &
          var_value, actual_value_len)
        ! Set exit status to 0 for simple assignments without expansions
        ! But don't overwrite error status from readonly violation
        if (shell%last_exit_status /= 127) then
          shell%last_exit_status = 0
        end if
      end if

      ! If allexport is enabled (set -a), automatically export the variable
      if (shell%option_allexport) then
        do i = 1, shell%num_variables
          if (trim(shell%variables(i)%name) == trim(var_name)) then
            shell%variables(i)%exported = .true.
            ! Also set in environment
            if (.not. set_environment_var(trim(var_name), trim(shell%variables(i)%value))) then
              ! Silently ignore export errors (POSIX behavior)
            end if
            exit
          end if
        end do
      end if

      ! POSIX: Exit status of assignment is from last command substitution
      ! Only set to 0 if no expansion was performed (i.e., no command substitution)
      ! Don't overwrite exit status when there was a command substitution
    end if
    end block
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

  subroutine execute_external(cmd, shell, original_input)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input

    integer(c_pid_t) :: pid, pgid, ret
    integer(c_int), target :: wait_status
    integer(c_int) :: pgid_ret
    integer :: job_id
    logical :: foreground
    type(c_funptr) :: old_handler

    foreground = .not. cmd%background

    ! Check for empty command before forking (e.g., from empty command substitution)
    ! This preserves the exit status from the command substitution
    if (cmd%num_tokens < 1 .or. len_trim(cmd%tokens(1)) == 0) then
      ! Empty command - nothing to execute, preserve current exit status
      return
    end if

    ! CRITICAL: Re-ensure SIGCHLD is SIG_DFL before forking
    ! Something in interactive mode might be resetting it
    pid = c_fork()

    if (pid < 0) then
      write(error_unit, '(a)') 'Error: fork failed'
      shell%last_exit_status = 1
    else if (pid == 0) then
      ! Child process
      if (.not. shell%in_pipeline_child) then
        ! Only set up own process group when NOT in a pipeline child.
        ! Pipeline children inherit their process group from the AST
        ! pipeline executor which manages groups at the pipeline level.
        pgid = c_getpid()
        ret = c_setpgid(0, pgid)
      end if

      ! Reset signal handlers to default
      old_handler = c_signal(SIGINT, c_null_funptr)
      old_handler = c_signal(SIGPIPE, c_null_funptr)
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

      ! Auto-populate hash table (hashall)
      if (shell%option_hashall .and. &
          index(trim(cmd%tokens(1)), '/') == 0) then
        call cache_command_path(shell, trim(cmd%tokens(1)))
      end if

      if (.not. shell%in_pipeline_child) then
        ! Only manage process groups and terminal when NOT in a pipeline
        ! child. The AST pipeline executor handles these at pipeline level.
        pgid = pid
        ret = c_setpgid(pid, pgid)

        if (foreground) then
          ! Give terminal to child
          if (shell%is_interactive) then
            pgid_ret = c_tcsetpgrp(shell%shell_terminal, pgid)
          end if

          ! Wait for child
          ret = c_waitpid(pid, c_loc(wait_status), WUNTRACED)

          ! Take back terminal
          if (shell%is_interactive) then
            pgid_ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
          end if

          if (ret == pid) then
            if (WIFEXITED(wait_status)) then
              shell%last_exit_status = WEXITSTATUS(wait_status)
            else if (WIFSIGNALED(wait_status)) then
              ! Process was killed by a signal - exit status is 128 + signal_number
              shell%last_exit_status = 128 + WTERMSIG(wait_status)
            else if (WIFSTOPPED(wait_status)) then
              job_id = add_job(shell, pgid, original_input, .true.)
              ! Set state to stopped (add_job defaults to RUNNING)
              block
                integer :: ji
                do ji = 1, MAX_JOBS
                  if (shell%jobs(ji)%job_id == job_id) then
                    shell%jobs(ji)%state = JOB_STOPPED
                    exit
                  end if
                end do
              end block
              write(output_unit, '(a)') 'Stopped'
            end if
          end if
        else
          ! Background job
          job_id = add_job(shell, pgid, original_input, .false.)
          ! Only print job notification in interactive mode
          if (shell%is_interactive) then
            write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pid
          end if
          ! Set $! to the background job PID
          shell%last_bg_pid = pid
        end if
      else
        ! In pipeline child: just wait for the grandchild, no terminal/pgroup mgmt
        ret = c_waitpid(pid, c_loc(wait_status), int(0, c_int))
        if (ret == pid) then
          if (WIFEXITED(wait_status)) then
            shell%last_exit_status = WEXITSTATUS(wait_status)
          else if (WIFSIGNALED(wait_status)) then
            shell%last_exit_status = 128 + WTERMSIG(wait_status)
          end if
        end if
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

      case(REDIR_FD_OUT, REDIR_FD_APPEND)  ! n> file or n>> file
        if (allocated(cmd%redirections(i)%filename)) then
          block
            character(len=256), target :: c_filename
            integer :: fd, flags

            c_filename = trim(cmd%redirections(i)%filename) // c_null_char

            if (cmd%redirections(i)%type == REDIR_FD_APPEND) then
              flags = ior(ior(O_WRONLY, O_CREAT), O_APPEND)
            else
              flags = ior(ior(O_WRONLY, O_CREAT), O_TRUNC)
            end if

            fd = c_open(c_loc(c_filename), flags, int(o'644', c_int))
            if (fd >= 0) then
              ret = c_dup2(fd, cmd%redirections(i)%fd)
              ret = c_close(fd)
            end if
          end block
        end if

      case(REDIR_CLOSE)  ! n>&-
        ret = c_close(cmd%redirections(i)%fd)

      end select
    end do
  end subroutine

  subroutine exec_child(tokens, num_tokens)
    use system_interface, only: file_exists, file_is_executable
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens

    type(c_ptr), target :: argv(num_tokens + 1)
    integer :: c_tok_len
    character(kind=c_char), allocatable, target :: c_tokens(:,:)
    integer :: i, j, k
    integer :: ret
    logical :: is_path_command


    ! Allocate C token buffer based on actual token character length
    c_tok_len = len(tokens(1)) + 1
    allocate(c_tokens(c_tok_len, num_tokens))

    ! Convert tokens to C strings
    do i = 1, num_tokens
      ! Use len_trim, but if it's 0 and token starts with whitespace, use 1
      ! This preserves whitespace-only arguments like " "
      j = len_trim(tokens(i))
      if (j == 0 .and. len(tokens(i)) > 0) then
        if (tokens(i)(1:1) == ' ' .or. tokens(i)(1:1) == char(9)) then
          j = 1  ! Keep at least one whitespace character
        end if
      end if
      do k = 1, j
        c_tokens(k, i) = tokens(i)(k:k)
      end do
      c_tokens(j + 1, i) = c_null_char
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

    type(string_t), allocatable :: function_body(:)
    type(string_t), allocatable :: saved_positional_params(:)
    integer :: saved_num_positional
    integer :: i
    type(pipeline_t) :: pipeline
    character(len=:), allocatable :: expanded_line
    logical :: function_returned

    ! Save current positional parameters (caller's $1, $2, etc.)
    if (allocated(shell%positional_params)) then
      allocate(saved_positional_params(size(shell%positional_params)))
      do i = 1, size(shell%positional_params)
        saved_positional_params(i)%str = shell%positional_params(i)%str
      end do
    end if
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
      shell%positional_params(i)%str = cmd%tokens(i + 1)
    end do

    ! Get function body (allocate empty first to silence -Wmaybe-uninitialized)
    allocate(function_body(0))
    function_body = get_function_body(shell, cmd%tokens(1))

    function_returned = .false.

    if (allocated(function_body)) then
      ! For defun-style functions (body has no $), append call args
      if (size(function_body) == 1 .and. cmd%num_tokens > 1 .and. &
          allocated(function_body(1)%str) .and. &
          index(function_body(1)%str, '$') == 0) then
        block
          integer :: j
          do j = 2, cmd%num_tokens
            function_body(1)%str = trim(function_body(1)%str) // &
                               ' ' // trim(cmd%tokens(j))
          end do
        end block
      end if

      ! Execute each line of the function
      do i = 1, size(function_body)
        if (allocated(function_body(i)%str) .and. len_trim(function_body(i)%str) > 0) then
          ! Expand aliases
          call expand_alias(shell, trim(function_body(i)%str), expanded_line)

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
    if (allocated(saved_positional_params)) then
      do i = 1, size(saved_positional_params)
        shell%positional_params(i)%str = saved_positional_params(i)%str
      end do
      deallocate(saved_positional_params)
    end if
    shell%num_positional = saved_num_positional
  end subroutine

  ! ===========================================================================
  ! COMPLETION FUNCTION EXECUTOR
  ! Called by completion module to execute -F completion functions
  ! ===========================================================================
  subroutine execute_completion_function(shell, func_name, command, word, prev_word)
    use variables, only: set_shell_variable, get_function_body, is_function
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: func_name
    character(len=*), intent(in) :: command
    character(len=*), intent(in) :: word
    character(len=*), intent(in) :: prev_word

    type(command_t) :: cmd

    ! Check if function exists
    if (.not. is_function(shell, func_name)) then
      return
    end if

    ! Set up COMP_* variables for the completion function
    ! COMP_LINE - the full command line (simplified)
    call set_shell_variable(shell, 'COMP_LINE', trim(command) // ' ' // trim(word))
    ! COMP_POINT - cursor position
    call set_shell_variable(shell, 'COMP_POINT', '0')
    ! COMP_CWORD - index of word containing cursor (0-based)
    call set_shell_variable(shell, 'COMP_CWORD', '1')

    ! Build command structure to execute the function
    ! The function receives: command word prev_word
    allocate(character(len=256) :: cmd%tokens(4))
    cmd%num_tokens = 4
    cmd%tokens(1) = trim(func_name)
    cmd%tokens(2) = trim(command)
    cmd%tokens(3) = trim(word)
    cmd%tokens(4) = trim(prev_word)

    ! Execute the function
    call execute_function(cmd, shell)

    ! Clean up
    deallocate(cmd%tokens)
  end subroutine execute_completion_function

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

        call parse_pipeline(shell%control_stack(loop_depth)%loop_body(i)%str, pipeline)
        if (pipeline%num_commands > 0) then
          call execute_pipeline(pipeline, shell, shell%control_stack(loop_depth)%loop_body(i)%str)
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
    integer :: i, j, len_str, closing_quote_pos
    character(len=len(str)) :: temp
    character(len=1) :: quote_char
    logical :: is_double_quote

    len_str = len_trim(str)
    if (len_str < 2) return

    ! Check if string starts with a quote
    if (str(1:1) /= "'" .and. str(1:1) /= '"') return

    quote_char = str(1:1)
    is_double_quote = (quote_char == '"')

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

      ! If double quotes, process escape sequences while copying
      if (is_double_quote) then
        i = 2
        j = 1
        do while (i < closing_quote_pos)
          if (temp(i:i) == '\' .and. i+1 < closing_quote_pos) then
            ! Check if this backslash escapes a special character
            if (temp(i+1:i+1) == '"' .or. temp(i+1:i+1) == '\' .or. &
                temp(i+1:i+1) == '$' .or. temp(i+1:i+1) == '`') then
              ! Skip backslash, keep the escaped character
              i = i + 1
              str(j:j) = temp(i:i)
              i = i + 1
              j = j + 1
            else
              ! Backslash doesn't escape anything special - keep both
              str(j:j) = temp(i:i)
              i = i + 1
              j = j + 1
            end if
          else
            ! Regular character
            str(j:j) = temp(i:i)
            i = i + 1
            j = j + 1
          end if
        end do
      else
        ! Single quotes - copy literally without escape processing
        do i = 2, closing_quote_pos - 1
          str(i-1:i-1) = temp(i:i)
        end do
      end if
    end if
  end subroutine

  ! Execute a pending trap command (set by signal_handling module)
  subroutine execute_pending_trap(shell)
    use trap_dispatch, only: eval_trap_string
    type(shell_state_t), intent(inout) :: shell
    integer :: saved_status, exit_code
    logical :: saved_bypass

    ! Save the trap command and signal before clearing
    character(len=:), allocatable :: trap_cmd
    trap_cmd = trim(shell%pending_trap_command)

    ! Save current exit status (traps don't affect $?)
    saved_status = shell%last_exit_status

    ! Save and clear bypass_functions — trap handlers should see all functions
    ! even when fired inside 'command' builtin context
    saved_bypass = shell%bypass_functions
    shell%bypass_functions = .false.

    ! Clear the pending trap
    shell%pending_trap_command = ''
    shell%pending_trap_signal = 0

    ! Set flag to prevent recursive trap execution
    shell%executing_trap = .true.

    ! Execute via trap_dispatch (registered by ast_executor at startup)
    call eval_trap_string(trim(trap_cmd), shell, exit_code)

    ! Clear flag to allow future trap execution
    shell%executing_trap = .false.

    ! Restore bypass_functions and exit status
    shell%bypass_functions = saved_bypass
    shell%last_exit_status = saved_status
  end subroutine

  ! Execute inline commands after "then" in single-line if statements
  ! Example: if [ 1 -eq 1 ]; then echo "test"; fi
  ! After parsing, the "then echo 'test'" becomes a single command with tokens ["then", "echo", "test"]
  subroutine execute_inline_then_commands(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: remainder_cmd
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

    type(pipeline_t) :: pipeline
    integer :: saved_depth, i

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
    character(len=:), allocatable :: func_body_line
    integer :: body_count, brace_start, brace_end, paren_pos

    is_func_def = .false.

    ! Check if we have enough tokens
    if (cmd%num_tokens < 1) return

    ! IMPORTANT: Don't treat quoted strings as function definitions
    ! If the first token is quoted, it cannot be a function definition
    if (allocated(cmd%token_quoted) .and. size(cmd%token_quoted) >= 1) then
      if (cmd%token_quoted(1)) return
    end if

    ! Reconstruct the full command to analyze it
    call reconstruct_command_from_tokens(cmd, reconstructed)

    ! Check for pattern: name() { body }
    ! Look for () followed by {
    paren_pos = index(reconstructed, '()')
    if (paren_pos == 0) return

    ! Extract function name (everything before ())
    func_name = adjustl(reconstructed(1:paren_pos-1))
    if (len_trim(func_name) == 0) return

    ! IMPORTANT: Function names cannot contain spaces
    ! This prevents "echo 'a() { }'" from being treated as a function definition
    ! (it would reconstruct to "echo a() { }" with func_name="echo a")
    if (index(func_name, ' ') > 0) return

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
      func_body_line = trim(adjustl(reconstructed(brace_start+1:brace_end-1)))
    else
      body_count = 0
      func_body_line = ''
    end if

    ! Register the function
    call add_function(shell, trim(func_name), [func_body_line], body_count)

    is_func_def = .true.
  end function

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

    if (.false.) print *, original_input  ! Silence unused warning

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
      else if (WIFSIGNALED(wait_status)) then
        shell%last_exit_status = 128 + WTERMSIG(wait_status)
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
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    character(len=MAX_TOKEN_LEN), target :: c_var_name, c_var_value

    ! Iterate through all prefix assignments
    if (.not. allocated(cmd%prefix_assignments)) return
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
    character(len=16384) :: input_line
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

  ! ===========================================================================
  ! COMPLETION EXECUTOR INITIALIZATION
  ! Registers the executor's completion function handler with the completion module
  ! ===========================================================================
  subroutine init_completion_executor()
    ! Register our execute_completion_function as the callback
    call register_completion_executor(execute_completion_function)
  end subroutine init_completion_executor

  ! Initialize token metadata arrays if not already set
  ! This is needed for commands parsed by the old parser path which doesn't
  ! populate these arrays. Inspects tokens to determine quote type and length.
  subroutine init_token_metadata(cmd)
    type(command_t), intent(inout) :: cmd
    integer :: i, token_len
    character(len=1) :: first_char, last_char

    if (cmd%num_tokens == 0) return

    ! Initialize token_quoted if not allocated
    if (.not. allocated(cmd%token_quoted)) then
      allocate(cmd%token_quoted(cmd%num_tokens))
      cmd%token_quoted = .false.
    end if

    ! Initialize token_escaped if not allocated
    if (.not. allocated(cmd%token_escaped)) then
      allocate(cmd%token_escaped(cmd%num_tokens))
      cmd%token_escaped = .false.
    end if

    ! Initialize token_quote_type if not allocated
    if (.not. allocated(cmd%token_quote_type)) then
      allocate(cmd%token_quote_type(cmd%num_tokens))
      cmd%token_quote_type = QUOTE_NONE
    end if

    ! Initialize token_lengths if not allocated
    if (.not. allocated(cmd%token_lengths)) then
      allocate(cmd%token_lengths(cmd%num_tokens))
      cmd%token_lengths = 0
    end if

    ! Inspect each token to determine quote type and length
    do i = 1, cmd%num_tokens
      token_len = len_trim(cmd%tokens(i))

      ! If quote info isn't set, try to detect from token content
      if (cmd%token_quote_type(i) == QUOTE_NONE .and. token_len >= 2) then
        first_char = cmd%tokens(i)(1:1)
        last_char = cmd%tokens(i)(token_len:token_len)

        ! Check for single-quoted token (may have sentinel markers char(2)/char(3))
        ! IMPORTANT: Don't treat as syntactic quotes if token was escaped (e.g., \'a\')
        if (first_char == "'" .and. last_char == "'" .and. .not. cmd%token_escaped(i)) then
          cmd%token_quoted(i) = .true.
          cmd%token_quote_type(i) = QUOTE_SINGLE
          ! For single quotes, preserve trailing whitespace by not using len_trim
          ! Find actual content length between quotes
          cmd%token_lengths(i) = token_len
        else if (first_char == char(2)) then
          ! Single-quote sentinel marker - this token was single-quoted
          cmd%token_quoted(i) = .true.
          cmd%token_quote_type(i) = QUOTE_SINGLE
          cmd%token_lengths(i) = token_len
        ! Check for double-quoted token
        ! IMPORTANT: Don't treat as syntactic quotes if token was escaped (e.g., \"a\")
        else if (first_char == '"' .and. last_char == '"' .and. .not. cmd%token_escaped(i)) then
          cmd%token_quoted(i) = .true.
          cmd%token_quote_type(i) = QUOTE_DOUBLE
          ! For double-quoted, find actual length including trailing whitespace
          ! The content is between the quotes: token(2:token_len-1)
          ! We need to preserve the full quoted token including any trailing space inside
          cmd%token_lengths(i) = token_len
        else if (first_char == char(1)) then
          ! Double-quote sentinel marker
          cmd%token_quoted(i) = .true.
          cmd%token_quote_type(i) = QUOTE_DOUBLE
          cmd%token_lengths(i) = token_len
        else
          ! Unquoted token
          cmd%token_lengths(i) = token_len
        end if
      else if (cmd%token_lengths(i) == 0) then
        cmd%token_lengths(i) = token_len
      end if
    end do
  end subroutine init_token_metadata

  subroutine cache_command_path(shell, cmd_name)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: cmd_name
    character(len=MAX_PATH_LEN) :: full_path
    integer :: j

    ! Inline PATH search to avoid circular dependency with command_builtin
    block
      character(len=:), allocatable :: path_alloc
      character(len=4096) :: path_var
      character(len=:), allocatable :: path_comp, candidate
      integer :: spos, epos, cpos
      character(kind=c_char), target :: c_path(1025)
      integer :: ci, acc_status
      interface
        function cache_access(pathname, mode) bind(C, name="access")
          import :: c_char, c_int
          character(kind=c_char), intent(in) :: pathname(*)
          integer(c_int), value :: mode
          integer(c_int) :: cache_access
        end function
      end interface

      full_path = ''
      if (index(cmd_name, '/') > 0) return

      path_alloc = get_environment_var('PATH')
      if (allocated(path_alloc) .and. len_trim(path_alloc) > 0) then
        path_var = path_alloc
      else
        path_var = '/usr/bin:/bin'
      end if

      spos = 1
      do while (spos <= len_trim(path_var))
        cpos = index(path_var(spos:), ':')
        if (cpos == 0) then
          epos = len_trim(path_var)
        else
          epos = spos + cpos - 2
        end if
        path_comp = path_var(spos:epos)
        if (len_trim(path_comp) == 0) path_comp = '.'

        ! Build the candidate via allocatable concat — a fixed-buffer write here
        ! aborted with "End of record" when path+name exceeded the buffer.
        candidate = trim(path_comp) // '/' // trim(cmd_name)

        ! Only probe candidates that fit the C path buffer; anything longer
        ! cannot name a real executable (bash likewise reports "not found").
        if (len_trim(candidate) + 1 <= size(c_path)) then
          ! Check executable via C access()
          do ci = 1, len_trim(candidate)
            c_path(ci) = candidate(ci:ci)
          end do
          c_path(len_trim(candidate) + 1) = c_null_char
          acc_status = cache_access(c_path, int(1, c_int))  ! X_OK = 1
          if (acc_status == 0) then
            full_path = trim(candidate)
            exit
          end if
        end if

        if (cpos == 0) exit
        spos = spos + cpos
      end do
    end block
    if (len_trim(full_path) == 0) return

    ! Check if already in hash table — update hits
    do j = 1, shell%num_hashed_commands
      if (trim(shell%command_hash(j)%command_name) == &
          cmd_name) then
        shell%command_hash(j)%hits = &
          shell%command_hash(j)%hits + 1
        return
      end if
    end do

    ! Add new entry
    if (shell%num_hashed_commands < &
        size(shell%command_hash)) then
      shell%num_hashed_commands = &
        shell%num_hashed_commands + 1
      shell%command_hash(shell%num_hashed_commands) &
        %command_name = cmd_name
      shell%command_hash(shell%num_hashed_commands) &
        %full_path = full_path
      shell%command_hash(shell%num_hashed_commands) &
        %hits = 1
    end if
  end subroutine cache_command_path

end module executor