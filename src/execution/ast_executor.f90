! =====================================
! AST Executor Module - Execute parsed command trees
! =====================================
! Executes commands from the AST produced by the grammar parser
! Part of the parser rewrite project
!
! Status: PHASE 4 - AST execution implementation
! Author: Parser Rewrite Team
! Created: 2025-11-06

module ast_executor
  use iso_fortran_env
  use iso_c_binding
  use shell_types
  use command_tree
  use system_interface
  use glob, only: pattern_matches_no_dotfile_check
  implicit none
  private

  ! Public interface
  public :: execute_ast
  public :: execute_ast_node
  public :: unset_ast_function
  public :: is_ast_function

  ! C bindings for process control
  interface
    function close(fd) bind(c, name='close')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: close
    end function close
  end interface

  ! Global function AST cache (maps function name to AST body)
  type :: function_ast_entry_t
    character(len=256) :: name
    type(command_node_t), pointer :: body => null()
  end type function_ast_entry_t

  type(function_ast_entry_t), save :: function_ast_cache(20)
  integer, save :: num_cached_functions = 0

contains

  ! =====================================
  ! Main Entry Point
  ! =====================================

  ! Execute an AST and return exit status
  function execute_ast(root, shell) result(exit_status)
    type(command_node_t), pointer, intent(in) :: root
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status

    if (.not. associated(root)) then
      exit_status = 0
      return
    end if

    exit_status = execute_ast_node(root, shell)
  end function execute_ast

  ! =====================================
  ! Node Execution Functions
  ! =====================================

  recursive function execute_ast_node(node, shell) result(exit_status)
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status

    if (.not. associated(node)) then
      exit_status = 0
      return
    end if

    select case(node%node_type)
    case(CMD_SIMPLE)
      exit_status = execute_simple_command(node, shell)
    case(CMD_PIPELINE)
      exit_status = execute_pipeline_node(node, shell)
    case(CMD_LIST)
      exit_status = execute_list_node(node, shell)
    case(CMD_IF_STATEMENT)
      exit_status = execute_if_node(node, shell)
    case(CMD_WHILE_LOOP, CMD_UNTIL_LOOP)
      exit_status = execute_while_node(node, shell)
    case(CMD_FOR_LOOP)
      exit_status = execute_for_node(node, shell)
    case(CMD_CASE_STATEMENT)
      exit_status = execute_case_node(node, shell)
    case(CMD_SUBSHELL)
      exit_status = execute_subshell_node(node, shell)
    case(CMD_BRACE_GROUP)
      exit_status = execute_brace_group_node(node, shell)
    case(CMD_FUNCTION_DEF)
      ! Function definitions: Store in shell state
      exit_status = execute_function_def(node, shell)
    case default
      write(error_unit, '(A,I0)') 'fortsh: unknown node type: ', node%node_type
      exit_status = 1
    end select

    shell%last_exit_status = exit_status
  end function execute_ast_node

  ! =====================================
  ! Simple Command Execution
  ! =====================================

  function execute_simple_command(node, shell) result(exit_status)
    use executor, only: execute_pipeline
    use fd_redirection, only: apply_single_redirection, restore_fds
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: i, func_idx, old_num_positional, j
    type(pipeline_t) :: temp_pipeline
    type(redirection_t) :: temp_redirect
    character(len=MAX_TOKEN_LEN) :: cmd_name
    character(len=1024), allocatable :: old_params(:)
    logical :: needs_quotes, redir_success
    logical :: has_redirects

    exit_status = 0

    if (.not. associated(node%simple_cmd)) then
      exit_status = 0
      return
    end if

    if (node%simple_cmd%num_words == 0) then
      exit_status = 0
      return
    end if

    ! Special handling for exec with redirections
    if (node%simple_cmd%num_words >= 1 .and. trim(node%simple_cmd%words(1)) == 'exec') then
      ! Check if this is exec with only redirections (no command to execute)
      if (node%simple_cmd%num_words == 1 .and. node%simple_cmd%num_redirects > 0) then
        ! exec without arguments but with redirections - apply redirections permanently
        do i = 1, node%simple_cmd%num_redirects
          ! Convert AST redirection to fd_redirection format
          temp_redirect%type = node%simple_cmd%redirects(i)%type
          temp_redirect%fd = node%simple_cmd%redirects(i)%fd
          temp_redirect%target_fd = node%simple_cmd%redirects(i)%target_fd
          if (allocated(node%simple_cmd%redirects(i)%filename)) then
            temp_redirect%filename = trim(node%simple_cmd%redirects(i)%filename)
          else
            temp_redirect%filename = ''
          end if
          temp_redirect%force_clobber = node%simple_cmd%redirects(i)%force_clobber

          call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
          if (.not. redir_success) then
            exit_status = 1
            return
          end if
        end do
        exit_status = 0
        return
      else if (node%simple_cmd%num_words == 1) then
        ! exec without arguments or redirections - just return success
        exit_status = 0
        return
      end if
      ! If we get here, exec has arguments, so fall through to normal execution
    end if

    ! Check if this is a function call
    cmd_name = trim(node%simple_cmd%words(1))
    do func_idx = 1, num_cached_functions
      if (trim(function_ast_cache(func_idx)%name) == trim(cmd_name)) then
        ! This is a function call! Execute the cached AST body

        ! Save old positional parameters
        old_num_positional = shell%num_positional
        if (allocated(shell%positional_params) .and. old_num_positional > 0) then
          allocate(old_params(old_num_positional))
          old_params(1:old_num_positional) = shell%positional_params(1:old_num_positional)
        end if

        ! Set new positional parameters from function arguments
        ! Need to expand arguments (variable expansion, command substitution, etc.)
        if (node%simple_cmd%num_words > 1) then
          ! Create temporary command to expand arguments
          block
            use executor, only: expand_tokens
            type(command_t) :: temp_cmd
            integer :: k

            temp_cmd%num_tokens = node%simple_cmd%num_words - 1  ! Exclude function name
            allocate(character(len=MAX_TOKEN_LEN) :: temp_cmd%tokens(temp_cmd%num_tokens))
            allocate(temp_cmd%token_quoted(temp_cmd%num_tokens))
            allocate(temp_cmd%token_escaped(temp_cmd%num_tokens))
            allocate(temp_cmd%token_quote_type(temp_cmd%num_tokens))
            allocate(temp_cmd%token_lengths(temp_cmd%num_tokens))

            ! Copy arguments (skip function name at index 1)
            do k = 1, temp_cmd%num_tokens
              ! For quoted words, use word_lengths to extract exact content (preserves trailing whitespace)
              if (allocated(node%simple_cmd%word_was_quoted) .and. k+1 <= size(node%simple_cmd%word_was_quoted) .and. &
                  node%simple_cmd%word_was_quoted(k + 1) .and. &
                  allocated(node%simple_cmd%word_lengths) .and. k+1 <= size(node%simple_cmd%word_lengths)) then
                ! Quoted word - use actual length to preserve trailing whitespace
                temp_cmd%tokens(k) = node%simple_cmd%words(k + 1)(1:node%simple_cmd%word_lengths(k + 1))
                temp_cmd%token_lengths(k) = node%simple_cmd%word_lengths(k + 1)
              else
                ! Unquoted word - trim is safe
                temp_cmd%tokens(k) = trim(node%simple_cmd%words(k + 1))
                temp_cmd%token_lengths(k) = len_trim(node%simple_cmd%words(k + 1))
              end if
              if (allocated(node%simple_cmd%word_was_quoted) .and. k+1 <= size(node%simple_cmd%word_was_quoted)) then
                temp_cmd%token_quoted(k) = node%simple_cmd%word_was_quoted(k + 1)
              else
                temp_cmd%token_quoted(k) = .false.
              end if
              if (allocated(node%simple_cmd%word_was_escaped) .and. k+1 <= size(node%simple_cmd%word_was_escaped)) then
                temp_cmd%token_escaped(k) = node%simple_cmd%word_was_escaped(k + 1)
              else
                temp_cmd%token_escaped(k) = .false.
              end if
              if (allocated(node%simple_cmd%word_quote_type) .and. k+1 <= size(node%simple_cmd%word_quote_type)) then
                temp_cmd%token_quote_type(k) = node%simple_cmd%word_quote_type(k + 1)
              else
                temp_cmd%token_quote_type(k) = QUOTE_NONE
              end if
            end do

            ! Expand the tokens (command substitution, arithmetic, variables, etc.)
            call expand_tokens(temp_cmd, shell)

            ! Now use expanded tokens as positional parameters
            shell%num_positional = temp_cmd%num_tokens
            if (shell%num_positional > 0) then
              if (.not. allocated(shell%positional_params)) then
                allocate(shell%positional_params(shell%num_positional))
                shell%positional_params_capacity = shell%num_positional
              else if (shell%positional_params_capacity < shell%num_positional) then
                deallocate(shell%positional_params)
                allocate(shell%positional_params(shell%num_positional))
                shell%positional_params_capacity = shell%num_positional
              end if
              do k = 1, shell%num_positional
                shell%positional_params(k) = trim(temp_cmd%tokens(k))
              end do
            end if

            ! Cleanup
            if (allocated(temp_cmd%tokens)) deallocate(temp_cmd%tokens)
            if (allocated(temp_cmd%token_quoted)) deallocate(temp_cmd%token_quoted)
            if (allocated(temp_cmd%token_escaped)) deallocate(temp_cmd%token_escaped)
            if (allocated(temp_cmd%token_quote_type)) deallocate(temp_cmd%token_quote_type)
            if (allocated(temp_cmd%token_lengths)) deallocate(temp_cmd%token_lengths)
          end block
        else
          shell%num_positional = 0
        end if

        ! Increment function depth for return/exit context tracking
        shell%function_depth = shell%function_depth + 1

        ! Execute function body
        if (associated(function_ast_cache(func_idx)%body)) then
          exit_status = execute_ast_node(function_ast_cache(func_idx)%body, shell)
        else
          exit_status = 0
        end if

        ! Decrement function depth
        shell%function_depth = shell%function_depth - 1

        ! Restore old positional parameters
        shell%num_positional = old_num_positional
        if (allocated(old_params)) then
          if (shell%num_positional > 0) then
            shell%positional_params(1:old_num_positional) = old_params(1:old_num_positional)
          end if
          deallocate(old_params)
        end if

        return
      end if
    end do

    ! TEMPORARY: Convert AST simple command back to old command_t format
    ! This delegates to the existing, battle-tested executor
    ! TODO: Once new parser is stable, rewrite executor to work directly with AST

    allocate(temp_pipeline%commands(1))
    temp_pipeline%num_commands = 1

    ! Initialize command in place (avoid structure copy issues)
    temp_pipeline%commands(1)%num_tokens = node%simple_cmd%num_words
    temp_pipeline%commands(1)%separator = SEP_NONE
    temp_pipeline%commands(1)%background = .false.
    temp_pipeline%commands(1)%num_redirections = 0
    temp_pipeline%commands(1)%num_prefix_assignments = 0


    ! Allocate tokens array directly in pipeline command
    allocate(character(len=MAX_TOKEN_LEN) :: temp_pipeline%commands(1)%tokens(node%simple_cmd%num_words))

    ! Allocate metadata arrays to track token properties
    allocate(temp_pipeline%commands(1)%token_quoted(node%simple_cmd%num_words))
    allocate(temp_pipeline%commands(1)%token_escaped(node%simple_cmd%num_words))
    allocate(temp_pipeline%commands(1)%token_quote_type(node%simple_cmd%num_words))
    allocate(temp_pipeline%commands(1)%token_lengths(node%simple_cmd%num_words))

    ! Initialize metadata arrays
    temp_pipeline%commands(1)%token_quoted = .false.
    temp_pipeline%commands(1)%token_escaped = .false.
    temp_pipeline%commands(1)%token_quote_type = QUOTE_NONE
    temp_pipeline%commands(1)%token_lengths = 0

    ! Copy words to tokens and metadata
    do i = 1, node%simple_cmd%num_words
      ! For quoted words, use word_lengths to extract exact content (preserves trailing whitespace)
      ! For unquoted words, trim is safe
      if (allocated(node%simple_cmd%word_was_quoted) .and. &
          i <= size(node%simple_cmd%word_was_quoted) .and. &
          node%simple_cmd%word_was_quoted(i) .and. &
          allocated(node%simple_cmd%word_lengths) .and. &
          i <= size(node%simple_cmd%word_lengths)) then
        ! Quoted word - use actual length to preserve trailing whitespace
        temp_pipeline%commands(1)%tokens(i) = node%simple_cmd%words(i)(1:node%simple_cmd%word_lengths(i))
        temp_pipeline%commands(1)%token_lengths(i) = node%simple_cmd%word_lengths(i)
      else
        ! Unquoted word - trim is safe
        temp_pipeline%commands(1)%tokens(i) = trim(node%simple_cmd%words(i))
        temp_pipeline%commands(1)%token_lengths(i) = len_trim(node%simple_cmd%words(i))
      end if

      ! Copy metadata if available
      if (allocated(node%simple_cmd%word_was_quoted) .and. &
          i <= size(node%simple_cmd%word_was_quoted)) then
        temp_pipeline%commands(1)%token_quoted(i) = node%simple_cmd%word_was_quoted(i)
      end if

      if (allocated(node%simple_cmd%word_was_escaped) .and. &
          i <= size(node%simple_cmd%word_was_escaped)) then
        temp_pipeline%commands(1)%token_escaped(i) = node%simple_cmd%word_was_escaped(i)
      end if

      if (allocated(node%simple_cmd%word_quote_type) .and. &
          i <= size(node%simple_cmd%word_quote_type)) then
        temp_pipeline%commands(1)%token_quote_type(i) = node%simple_cmd%word_quote_type(i)
      end if
    end do

    ! Copy heredoc delimiter if present (content will be read by executor)
    if (len_trim(node%simple_cmd%heredoc_delimiter) > 0) then
      temp_pipeline%commands(1)%heredoc_delimiter = trim(node%simple_cmd%heredoc_delimiter)
      temp_pipeline%commands(1)%heredoc_quoted = node%simple_cmd%heredoc_quoted
      temp_pipeline%commands(1)%heredoc_strip_tabs = node%simple_cmd%heredoc_strip_tabs
    end if

    ! Apply redirections directly (in order, left-to-right) before executing
    ! This preserves proper ordering for cases like: echo test >/tmp/r1 2>&1 >/tmp/r2
    has_redirects = (node%simple_cmd%num_redirects > 0)
    if (has_redirects) then
      do i = 1, node%simple_cmd%num_redirects
        temp_redirect%type = node%simple_cmd%redirects(i)%type
        temp_redirect%fd = node%simple_cmd%redirects(i)%fd
        temp_redirect%target_fd = node%simple_cmd%redirects(i)%target_fd
        if (allocated(node%simple_cmd%redirects(i)%filename)) then
          allocate(temp_redirect%filename, source=trim(node%simple_cmd%redirects(i)%filename))
        end if
        temp_redirect%force_clobber = node%simple_cmd%redirects(i)%force_clobber

        call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
        if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
        if (.not. redir_success) then
          exit_status = 1
          if (allocated(temp_pipeline%commands)) then
            if (allocated(temp_pipeline%commands(1)%tokens)) deallocate(temp_pipeline%commands(1)%tokens)
            if (allocated(temp_pipeline%commands(1)%token_quoted)) deallocate(temp_pipeline%commands(1)%token_quoted)
            if (allocated(temp_pipeline%commands(1)%token_escaped)) deallocate(temp_pipeline%commands(1)%token_escaped)
            if (allocated(temp_pipeline%commands(1)%token_quote_type)) deallocate(temp_pipeline%commands(1)%token_quote_type)
            if (allocated(temp_pipeline%commands(1)%token_lengths)) deallocate(temp_pipeline%commands(1)%token_lengths)
            deallocate(temp_pipeline%commands)
          end if
          call restore_fds()
          return
        end if
      end do
    end if

    ! Execute using existing executor
    ! Note: Pass empty command line - tokens array is what matters
    call execute_pipeline(temp_pipeline, shell, '')

    exit_status = shell%last_exit_status

    ! Check if fatal expansion error occurred (e.g., set -u with undefined variable)
    if (shell%fatal_expansion_error) then
      shell%fatal_expansion_error = .false.  ! Reset flag
      ! POSIX: In non-interactive shells, exit the shell entirely
      if (.not. shell%is_interactive) then
        shell%running = .false.
      end if
      ! Exit status was already set by expansion code (usually 127)
      ! Just clean up and return
      if (has_redirects) then
        call restore_fds()
      end if
      if (allocated(temp_pipeline%commands)) then
        if (allocated(temp_pipeline%commands(1)%tokens)) deallocate(temp_pipeline%commands(1)%tokens)
        if (allocated(temp_pipeline%commands(1)%token_quoted)) deallocate(temp_pipeline%commands(1)%token_quoted)
        if (allocated(temp_pipeline%commands(1)%token_escaped)) deallocate(temp_pipeline%commands(1)%token_escaped)
        if (allocated(temp_pipeline%commands(1)%token_quote_type)) deallocate(temp_pipeline%commands(1)%token_quote_type)
        if (allocated(temp_pipeline%commands(1)%token_lengths)) deallocate(temp_pipeline%commands(1)%token_lengths)
        deallocate(temp_pipeline%commands)
      end if
      return
    end if

    ! Restore file descriptors if we applied any redirections
    if (has_redirects) then
      call restore_fds()
    end if

    ! If a trap command was queued, execute it now (unless we're already executing a trap)
    if (len_trim(shell%pending_trap_command) > 0 .and. .not. shell%executing_trap) then
      call execute_pending_trap(shell)
    end if

    ! Clean up
    if (allocated(temp_pipeline%commands)) then
      if (allocated(temp_pipeline%commands(1)%tokens)) deallocate(temp_pipeline%commands(1)%tokens)
      if (allocated(temp_pipeline%commands(1)%token_quoted)) deallocate(temp_pipeline%commands(1)%token_quoted)
      if (allocated(temp_pipeline%commands(1)%token_escaped)) deallocate(temp_pipeline%commands(1)%token_escaped)
      if (allocated(temp_pipeline%commands(1)%token_quote_type)) deallocate(temp_pipeline%commands(1)%token_quote_type)
      if (allocated(temp_pipeline%commands(1)%token_lengths)) deallocate(temp_pipeline%commands(1)%token_lengths)
      deallocate(temp_pipeline%commands)
    end if

  end function execute_simple_command

  ! =====================================
  ! Pipeline Execution
  ! =====================================

  function execute_pipeline_node(node, shell) result(exit_status)
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: i, status, ret
    integer(c_int), target :: pipefd(2, 10)  ! Up to 10 pipes
    integer(c_pid_t) :: pids(10)
    integer :: num_pipes

    exit_status = 0

    if (.not. associated(node%pipeline)) then
      exit_status = 0
      return
    end if

    if (node%pipeline%num_commands == 0) then
      exit_status = 0
      return
    end if

    if (node%pipeline%num_commands == 1) then
      ! Single command - no piping needed
      if (associated(node%pipeline%commands)) then
        exit_status = execute_ast_node(node%pipeline%commands(1), shell)
      end if

      ! Handle negation
      if (node%pipeline%negate) then
        if (exit_status == 0) then
          exit_status = 1
        else
          exit_status = 0
        end if
      end if
      return
    end if

    ! Multiple commands - set up pipes
    num_pipes = node%pipeline%num_commands - 1

    ! Create all pipes
    do i = 1, num_pipes
      if (c_pipe(c_loc(pipefd(1, i))) /= 0) then
        write(error_unit, '(A)') 'fortsh: pipe creation failed'
        exit_status = 1
        return
      end if
    end do

    ! Fork and execute each command in the pipeline
    do i = 1, node%pipeline%num_commands
      pids(i) = c_fork()

      if (pids(i) == 0) then
        ! Child process
        ! Set up stdin from previous pipe
        if (i > 1) then
          ret = c_dup2(pipefd(1, i-1), int(0, c_int))  ! Read from previous pipe
        end if

        ! Set up stdout to next pipe
        if (i < node%pipeline%num_commands) then
          ret = c_dup2(pipefd(2, i), int(1, c_int))  ! Write to next pipe
        end if

        ! Close all pipe fds
        call close_all_pipes(pipefd, num_pipes)

        ! POSIX: Traps are NOT inherited by subshells (including pipeline commands)
        shell%num_traps = 0

        ! Execute command
        status = execute_ast_node(node%pipeline%commands(i), shell)
        call c_exit(status)
      end if
    end do

    ! Parent process - close all pipes and wait for children
    call close_all_pipes(pipefd, num_pipes)

    ! Wait for all children
    do i = 1, node%pipeline%num_commands
      status = wait_for_process(pids(i))
    end do

    ! Exit status is from last command
    exit_status = extract_exit_status(status)

    ! Handle negation
    if (node%pipeline%negate) then
      if (exit_status == 0) then
        exit_status = 1
      else
        exit_status = 0
      end if
    end if

  end function execute_pipeline_node

  ! =====================================
  ! List Execution (;, &&, ||, &)
  ! =====================================

  recursive function execute_list_node(node, shell) result(exit_status)
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, left_status
    integer(c_pid_t) :: pid
    integer :: status

    exit_status = 0

    if (.not. associated(node%list)) then
      return
    end if

    ! Execute left side
    if (associated(node%list%left)) then
      left_status = execute_ast_node(node%list%left, shell)
    else
      left_status = 0
    end if

    ! Handle based on separator type
    select case(node%list%separator)
    case(LIST_SEP_SEQUENTIAL)
      ! ; - Execute right side unless shell is exiting
      ! But first, handle any sourcing queued by the left side (e.g., dot command)
      if (shell%should_source) then
        call process_source_inline_ast(shell)
      end if
      ! Check for break/continue - if requested, skip the right side
      if (shell%control_depth > 0) then
        if (shell%control_stack(shell%control_depth)%break_requested .or. &
            shell%control_stack(shell%control_depth)%continue_requested) then
          ! Don't execute right side - break or continue was called
          exit_status = left_status
          return
        end if
      end if
      if (.not. shell%running) then
        ! Shell is exiting (e.g., exit builtin was called)
        exit_status = left_status
      else if (associated(node%list%right)) then
        exit_status = execute_ast_node(node%list%right, shell)
      else
        exit_status = left_status
      end if

    case(LIST_SEP_AND)
      ! && - Execute right only if left succeeded
      if (left_status == 0) then
        if (associated(node%list%right)) then
          exit_status = execute_ast_node(node%list%right, shell)
        end if
      else
        exit_status = left_status
      end if

    case(LIST_SEP_OR)
      ! || - Execute right only if left failed
      if (left_status /= 0) then
        if (associated(node%list%right)) then
          exit_status = execute_ast_node(node%list%right, shell)
        else
          exit_status = left_status
        end if
      else
        exit_status = left_status
      end if

    case(LIST_SEP_BACKGROUND)
      ! & - Execute right side in background
      pid = c_fork()
      if (pid == 0) then
        ! Child process - execute left command
        status = left_status
        call c_exit(status)
      else if (pid > 0) then
        ! Parent - save background pid and continue with right
        shell%last_bg_pid = pid
        if (associated(node%list%right)) then
          exit_status = execute_ast_node(node%list%right, shell)
        else
          exit_status = 0
        end if
      end if

    case default
      exit_status = left_status
    end select

  end function execute_list_node

  ! =====================================
  ! If Statement Execution
  ! =====================================

  recursive function execute_if_node(node, shell) result(exit_status)
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, cond_status

    exit_status = 0

    if (.not. associated(node%if_stmt)) then
      return
    end if

    ! Evaluate condition
    if (associated(node%if_stmt%condition)) then
      cond_status = execute_ast_node(node%if_stmt%condition, shell)
    else
      cond_status = 1
    end if

    ! Execute then or else part based on condition
    if (cond_status == 0) then
      ! Condition succeeded - execute then part
      if (associated(node%if_stmt%then_part)) then
        exit_status = execute_ast_node(node%if_stmt%then_part, shell)
      end if
    else
      ! Condition failed - execute else part if present
      if (associated(node%if_stmt%else_part)) then
        exit_status = execute_ast_node(node%if_stmt%else_part, shell)
      end if
    end if

  end function execute_if_node

  ! =====================================
  ! While/Until Loop Execution
  ! =====================================

  recursive function execute_while_node(node, shell) result(exit_status)
    use control_flow, only: push_control_block, pop_control_block, BLOCK_WHILE, BLOCK_UNTIL
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, cond_status
    logical :: should_continue

    exit_status = 0

    if (.not. associated(node%while_loop)) then
      return
    end if

    ! Push loop control block so break/continue can find it
    if (node%while_loop%is_until) then
      call push_control_block(shell, BLOCK_UNTIL, .true.)
    else
      call push_control_block(shell, BLOCK_WHILE, .true.)
    end if

    do
      ! Evaluate condition (suppress errexit during condition evaluation per POSIX)
      if (associated(node%while_loop%condition)) then
        shell%evaluating_condition = .true.
        cond_status = execute_ast_node(node%while_loop%condition, shell)
        shell%evaluating_condition = .false.
      else
        cond_status = 1
      end if

      ! Determine if we should continue based on while vs until
      if (node%while_loop%is_until) then
        should_continue = (cond_status /= 0)  ! until: continue while false
      else
        should_continue = (cond_status == 0)  ! while: continue while true
      end if

      if (.not. should_continue) exit

      ! Execute body
      if (associated(node%while_loop%body)) then
        exit_status = execute_ast_node(node%while_loop%body, shell)
      end if

      ! Check for break/continue from within the loop body
      if (shell%control_depth > 0) then
        if (shell%control_stack(shell%control_depth)%break_requested) then
          ! Handle multi-level break
          if (shell%control_stack(shell%control_depth)%break_level > 1) then
            ! Propagate to parent loop
            if (shell%control_depth > 1) then
              shell%control_stack(shell%control_depth - 1)%break_requested = .true.
              shell%control_stack(shell%control_depth - 1)%break_level = &
                shell%control_stack(shell%control_depth)%break_level - 1
            end if
          end if
          ! Clear flag and exit loop
          shell%control_stack(shell%control_depth)%break_requested = .false.
          shell%control_stack(shell%control_depth)%break_level = 0
          exit
        end if

        if (shell%control_stack(shell%control_depth)%continue_requested) then
          ! Handle multi-level continue
          if (shell%control_stack(shell%control_depth)%continue_level > 1) then
            ! Propagate to parent loop
            if (shell%control_depth > 1) then
              shell%control_stack(shell%control_depth - 1)%continue_requested = .true.
              shell%control_stack(shell%control_depth - 1)%continue_level = &
                shell%control_stack(shell%control_depth)%continue_level - 1
            end if
            ! Clear and exit to outer loop
            shell%control_stack(shell%control_depth)%continue_requested = .false.
            shell%control_stack(shell%control_depth)%continue_level = 0
            exit
          else
            ! Clear flag and continue to next iteration
            shell%control_stack(shell%control_depth)%continue_requested = .false.
            shell%control_stack(shell%control_depth)%continue_level = 0
            ! Just continue the loop (next iteration)
          end if
        end if
      end if
    end do

    ! Pop loop control block
    call pop_control_block(shell)

  end function execute_while_node

  ! =====================================
  ! For Loop Execution
  ! =====================================

  recursive function execute_for_node(node, shell) result(exit_status)
    use variables, only: set_shell_variable
    use control_flow, only: push_control_block, pop_control_block, BLOCK_FOR
    use glob, only: glob_match, has_unescaped_glob_chars
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, i, j, glob_count, word_idx
    character(len=MAX_TOKEN_LEN) :: glob_matches(MAX_TOKEN_LEN)
    character(len=MAX_TOKEN_LEN), allocatable :: expanded_words(:)
    integer :: total_words

    exit_status = 0

    if (.not. associated(node%for_loop)) then
      return
    end if

    ! First, expand any glob patterns in the word list
    allocate(expanded_words(MAX_TOKEN_LEN))
    total_words = 0

    do i = 1, node%for_loop%num_words
      ! Check if this word contains glob characters
      if (has_unescaped_glob_chars(trim(node%for_loop%words(i)))) then
        ! Expand the glob pattern
        call glob_match(trim(node%for_loop%words(i)), glob_matches, glob_count)
        if (glob_count > 0) then
          ! Add all matched files
          do j = 1, glob_count
            if (total_words < MAX_TOKEN_LEN) then
              total_words = total_words + 1
              expanded_words(total_words) = glob_matches(j)
            end if
          end do
        else
          ! No matches - use the pattern literally
          if (total_words < MAX_TOKEN_LEN) then
            total_words = total_words + 1
            expanded_words(total_words) = node%for_loop%words(i)
          end if
        end if
      else
        ! Not a glob pattern - use the word as-is
        if (total_words < MAX_TOKEN_LEN) then
          total_words = total_words + 1
          expanded_words(total_words) = node%for_loop%words(i)
        end if
      end if
    end do

    ! Push loop control block so break/continue can find it
    call push_control_block(shell, BLOCK_FOR, .true.)

    ! Iterate over expanded words
    do word_idx = 1, total_words
      ! Set loop variable
      call set_shell_variable(shell, trim(node%for_loop%variable), trim(expanded_words(word_idx)), &
                              len_trim(expanded_words(word_idx)))

      ! Execute body
      if (associated(node%for_loop%body)) then
        exit_status = execute_ast_node(node%for_loop%body, shell)
      end if

      ! Check for break/continue from within the loop body
      if (shell%control_depth > 0) then
        if (shell%control_stack(shell%control_depth)%break_requested) then
          ! Handle multi-level break
          if (shell%control_stack(shell%control_depth)%break_level > 1) then
            ! Propagate to parent loop
            if (shell%control_depth > 1) then
              shell%control_stack(shell%control_depth - 1)%break_requested = .true.
              shell%control_stack(shell%control_depth - 1)%break_level = &
                shell%control_stack(shell%control_depth)%break_level - 1
            end if
          end if
          ! Clear flag and exit loop
          shell%control_stack(shell%control_depth)%break_requested = .false.
          shell%control_stack(shell%control_depth)%break_level = 0
          exit
        end if

        if (shell%control_stack(shell%control_depth)%continue_requested) then
          ! Handle multi-level continue
          if (shell%control_stack(shell%control_depth)%continue_level > 1) then
            ! Propagate to parent loop
            if (shell%control_depth > 1) then
              shell%control_stack(shell%control_depth - 1)%continue_requested = .true.
              shell%control_stack(shell%control_depth - 1)%continue_level = &
                shell%control_stack(shell%control_depth)%continue_level - 1
            end if
            ! Clear and exit to outer loop
            shell%control_stack(shell%control_depth)%continue_requested = .false.
            shell%control_stack(shell%control_depth)%continue_level = 0
            exit
          else
            ! Clear flag and continue to next iteration
            shell%control_stack(shell%control_depth)%continue_requested = .false.
            shell%control_stack(shell%control_depth)%continue_level = 0
            ! Just continue the loop (next iteration)
          end if
        end if
      end if
    end do

    ! Pop loop control block
    call pop_control_block(shell)

    ! Clean up
    if (allocated(expanded_words)) deallocate(expanded_words)

  end function execute_for_node

  ! =====================================
  ! Case Statement Execution
  ! =====================================

  function execute_case_node(node, shell) result(exit_status)
    use variables, only: get_shell_variable
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    character(len=1024) :: case_value
    integer :: item_idx, pattern_idx
    logical :: matched
    character(len=MAX_TOKEN_LEN) :: pattern

    exit_status = 0

    if (.not. associated(node%case_stmt)) then
      return
    end if

    ! Get the value to match (expand variables)
    case_value = trim(node%case_stmt%word)
    ! If it starts with $, expand it
    if (case_value(1:1) == '$') then
      case_value = get_shell_variable(shell, case_value(2:))
    end if

    ! Try to match against each case item
    do item_idx = 1, node%case_stmt%num_items
      matched = .false.

      ! Check each pattern in this item
      do pattern_idx = 1, node%case_stmt%items(item_idx)%num_patterns
        pattern = trim(node%case_stmt%items(item_idx)%patterns(pattern_idx))

        ! Match pattern using glob module (handles *, ?, [abc], [[:class:]], etc.)
        matched = pattern_matches_no_dotfile_check(trim(pattern), trim(case_value))

        if (matched) exit
      end do

      ! If matched, execute the commands for this case item
      if (matched) then
        if (associated(node%case_stmt%items(item_idx)%commands)) then
          exit_status = execute_ast_node(node%case_stmt%items(item_idx)%commands, shell)
        else
          exit_status = 0
        end if
        exit  ! Only execute first match
      end if
    end do

  end function execute_case_node

  ! =====================================
  ! Subshell Execution
  ! =====================================

  recursive function execute_subshell_node(node, shell) result(exit_status)
    use fd_redirection, only: apply_single_redirection
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer(c_pid_t) :: pid
    integer :: status, i
    type(redirection_t) :: temp_redirect
    logical :: redir_success

    exit_status = 0

    if (.not. associated(node%subshell)) then
      return
    end if

    ! Fork for subshell
    pid = c_fork()
    if (pid == 0) then
      ! Child process - execute commands in subshell
      ! POSIX: Traps are NOT inherited by subshells
      shell%num_traps = 0

      ! Apply redirections in child process
      if (node%num_redirects > 0) then
        do i = 1, node%num_redirects
          temp_redirect%type = node%redirects(i)%type
          temp_redirect%fd = node%redirects(i)%fd
          temp_redirect%target_fd = node%redirects(i)%target_fd
          if (allocated(node%redirects(i)%filename)) then
            allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
          end if
          temp_redirect%force_clobber = node%redirects(i)%force_clobber

          call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
          if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
          if (.not. redir_success) then
            call c_exit(1)
          end if
        end do
      end if

      status = execute_ast_node(node%subshell, shell)
      call c_exit(status)
    else if (pid > 0) then
      ! Parent - wait for subshell
      status = wait_for_process(pid)
      exit_status = extract_exit_status(status)
    else
      write(error_unit, '(A)') 'fortsh: fork failed for subshell'
      exit_status = 1
    end if

  end function execute_subshell_node

  ! =====================================
  ! Brace Group Execution
  ! =====================================

  recursive function execute_brace_group_node(node, shell) result(exit_status)
    use fd_redirection, only: apply_single_redirection, restore_fds
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: i
    type(redirection_t) :: temp_redirect
    logical :: redir_success

    exit_status = 0

    if (.not. associated(node%subshell)) then
      return
    end if

    ! Apply redirections if present
    if (node%num_redirects > 0) then
      do i = 1, node%num_redirects
        temp_redirect%type = node%redirects(i)%type
        temp_redirect%fd = node%redirects(i)%fd
        temp_redirect%target_fd = node%redirects(i)%target_fd
        if (allocated(node%redirects(i)%filename)) then
          allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
        end if
        temp_redirect%force_clobber = node%redirects(i)%force_clobber

        call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
        if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
        if (.not. redir_success) then
          exit_status = 1
          call restore_fds()
          return
        end if
      end do
    end if

    ! Execute in current shell (no fork)
    exit_status = execute_ast_node(node%subshell, shell)

    ! Restore file descriptors
    if (node%num_redirects > 0) then
      call restore_fds()
    end if

  end function execute_brace_group_node

  ! =====================================
  ! Function Definition Execution
  ! =====================================

  function execute_function_def(node, shell) result(exit_status)
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: func_idx, cache_idx

    exit_status = 0

    if (.not. associated(node%function_def)) then
      return
    end if

    ! Store function AST body in cache
    cache_idx = -1
    do func_idx = 1, num_cached_functions
      if (trim(function_ast_cache(func_idx)%name) == trim(node%function_def%name)) then
        cache_idx = func_idx
        exit
      end if
    end do

    if (cache_idx == -1 .and. num_cached_functions < 20) then
      ! New function
      num_cached_functions = num_cached_functions + 1
      cache_idx = num_cached_functions
    end if

    if (cache_idx > 0) then
      function_ast_cache(cache_idx)%name = trim(node%function_def%name)
      function_ast_cache(cache_idx)%body => node%function_def%body
    end if

    ! Also register in shell state for compatibility
    do func_idx = 1, shell%num_functions
      if (trim(shell%functions(func_idx)%name) == trim(node%function_def%name)) then
        return  ! Already registered
      end if
    end do

    if (shell%num_functions < 20) then
      shell%num_functions = shell%num_functions + 1
      shell%functions(shell%num_functions)%name = trim(node%function_def%name)
      shell%functions(shell%num_functions)%body_lines = 1
      allocate(shell%functions(shell%num_functions)%body(1))
      shell%functions(shell%num_functions)%body(1) = 'AST_FUNCTION'
    end if

  end function execute_function_def

  ! =====================================
  ! Helper Functions
  ! =====================================

  subroutine close_all_pipes(pipefd, num_pipes)
    integer(c_int), intent(in) :: pipefd(2, 10)
    integer, intent(in) :: num_pipes
    integer :: i, ret

    do i = 1, num_pipes
      ret = close(pipefd(1, i))
      ret = close(pipefd(2, i))
    end do
  end subroutine close_all_pipes

  function wait_for_process(pid) result(status)
    integer(c_pid_t), intent(in) :: pid
    integer, target :: status
    integer(c_pid_t) :: result

    status = 0
    result = c_waitpid(pid, c_loc(status), int(0, c_int))
    if (result < 0) then
      status = 1
    end if
  end function wait_for_process

  function extract_exit_status(status) result(exit_code)
    integer, intent(in) :: status
    integer :: exit_code

    ! Extract exit code from wait status
    exit_code = ishft(status, -8)
    exit_code = iand(exit_code, 255)
  end function extract_exit_status

  subroutine execute_external_command(words, num_words, exit_status)
    character(len=*), intent(in) :: words(:)
    integer, intent(in) :: num_words
    integer, intent(out) :: exit_status
    character(len=MAX_PATH_LEN) :: cmd_path
    integer :: ret

    interface
      function system(cmd) bind(c, name='system')
        import :: c_char, c_int
        character(kind=c_char), dimension(*) :: cmd
        integer(c_int) :: system
      end function
    end interface

    exit_status = 0

    if (num_words == 0) return

    cmd_path = trim(words(1))

    ! Try to execute command
    ! For now, just use system() as a placeholder
    ! TODO: Implement proper execvp with argv array
    ret = system(trim(cmd_path) // c_null_char)
    exit_status = extract_exit_status(ret)

  end subroutine execute_external_command

  ! Execute a pending trap command (set by signal_handling module)
  subroutine execute_pending_trap(shell)
    use grammar_parser, only: parse_command_line
    use command_tree, only: destroy_command_node
    type(shell_state_t), intent(inout) :: shell
    type(command_node_t), pointer :: trap_ast
    integer :: saved_status, trap_status
    character(len=4096) :: trap_cmd

    ! Save the trap command and signal before clearing
    trap_cmd = shell%pending_trap_command

    ! Save current exit status (traps don't affect $?)
    saved_status = shell%last_exit_status

    ! Clear the pending trap
    shell%pending_trap_command = ''
    shell%pending_trap_signal = 0

    ! Set flag to prevent recursive trap execution
    shell%executing_trap = .true.

    ! Parse and execute the trap command using AST parser
    trap_ast => parse_command_line(trim(trap_cmd))
    if (associated(trap_ast)) then
      trap_status = execute_ast_node(trap_ast, shell)
      call destroy_command_node(trap_ast)
    end if

    ! Clear flag to allow future trap execution
    shell%executing_trap = .false.

    ! Restore original exit status (traps don't affect $?)
    shell%last_exit_status = saved_status
  end subroutine execute_pending_trap

  ! Process sourced files inline (for dot command in lists)
  subroutine process_source_inline_ast(shell)
    use grammar_parser, only: parse_command_line
    use command_tree, only: destroy_command_node
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: input_line
    integer :: file_unit, iostat
    type(command_node_t), pointer :: ast_root
    integer :: exit_code

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

      ! Parse and execute using AST parser
      ast_root => parse_command_line(trim(input_line))
      if (associated(ast_root)) then
        exit_code = execute_ast_node(ast_root, shell)
        shell%last_exit_status = exit_code
        call destroy_command_node(ast_root)
      end if

      ! Stop execution if exit command was encountered
      if (.not. shell%running) exit
    end do

    close(file_unit)
    shell%source_file = ''
  end subroutine process_source_inline_ast

  ! Unset a function from the AST cache
  subroutine unset_ast_function(func_name)
    character(len=*), intent(in) :: func_name
    integer :: i

    do i = 1, num_cached_functions
      if (trim(function_ast_cache(i)%name) == trim(func_name)) then
        ! Clear this function from the cache
        function_ast_cache(i)%name = ''
        function_ast_cache(i)%body => null()
        exit
      end if
    end do
  end subroutine unset_ast_function

  ! Check if a function exists in the AST cache
  function is_ast_function(func_name) result(exists)
    character(len=*), intent(in) :: func_name
    logical :: exists
    integer :: i

    exists = .false.
    do i = 1, num_cached_functions
      if (trim(function_ast_cache(i)%name) == trim(func_name) .and. &
          len_trim(function_ast_cache(i)%name) > 0) then
        exists = .true.
        return
      end if
    end do
  end function is_ast_function

end module ast_executor
