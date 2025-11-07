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
  implicit none
  private

  ! Public interface
  public :: execute_ast
  public :: execute_ast_node

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
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: i, func_idx
    type(pipeline_t) :: temp_pipeline
    character(len=MAX_TOKEN_LEN) :: cmd_name

    exit_status = 0

    if (.not. associated(node%simple_cmd)) then
      exit_status = 0
      return
    end if

    if (node%simple_cmd%num_words == 0) then
      exit_status = 0
      return
    end if

    ! Check if this is a function call
    cmd_name = trim(node%simple_cmd%words(1))
    do func_idx = 1, num_cached_functions
      if (trim(function_ast_cache(func_idx)%name) == trim(cmd_name)) then
        ! This is a function call! Execute the cached AST body
        ! TODO: Set positional parameters $1, $2, etc. from node%simple_cmd%words(2:)
        ! TODO: Save/restore old positional params
        ! TODO: Handle return builtin

        if (associated(function_ast_cache(func_idx)%body)) then
          exit_status = execute_ast_node(function_ast_cache(func_idx)%body, shell)
        else
          exit_status = 0
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

    ! Copy words to tokens
    do i = 1, node%simple_cmd%num_words
      temp_pipeline%commands(1)%tokens(i) = trim(node%simple_cmd%words(i))
    end do

    ! Convert redirections to old executor format
    if (node%simple_cmd%num_redirects > 0) then
      do i = 1, node%simple_cmd%num_redirects
        select case(node%simple_cmd%redirects(i)%type)
        case(REDIR_IN)
          ! < file
          if (allocated(node%simple_cmd%redirects(i)%filename)) then
            temp_pipeline%commands(1)%input_file = trim(node%simple_cmd%redirects(i)%filename)
          end if
        case(REDIR_OUT)
          ! > file
          if (allocated(node%simple_cmd%redirects(i)%filename)) then
            temp_pipeline%commands(1)%output_file = trim(node%simple_cmd%redirects(i)%filename)
          end if
        case(REDIR_APPEND)
          ! >> file
          if (allocated(node%simple_cmd%redirects(i)%filename)) then
            temp_pipeline%commands(1)%output_file = trim(node%simple_cmd%redirects(i)%filename)
            temp_pipeline%commands(1)%append_output = .true.
          end if
        case(REDIR_FD_OUT)
          ! 2> file (stderr redirect)
          if (node%simple_cmd%redirects(i)%fd == 2) then
            if (allocated(node%simple_cmd%redirects(i)%filename)) then
              temp_pipeline%commands(1)%error_file = trim(node%simple_cmd%redirects(i)%filename)
            end if
          end if
        end select
      end do
    end if

    ! Execute using existing executor
    ! Note: Pass empty command line - tokens array is what matters
    call execute_pipeline(temp_pipeline, shell, '')

    exit_status = shell%last_exit_status

    ! Clean up
    if (allocated(temp_pipeline%commands)) then
      if (allocated(temp_pipeline%commands(1)%tokens)) deallocate(temp_pipeline%commands(1)%tokens)
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
      ! ; - Always execute right side
      if (associated(node%list%right)) then
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
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, cond_status
    logical :: should_continue

    exit_status = 0

    if (.not. associated(node%while_loop)) then
      return
    end if

    do
      ! Evaluate condition
      if (associated(node%while_loop%condition)) then
        cond_status = execute_ast_node(node%while_loop%condition, shell)
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
    end do

  end function execute_while_node

  ! =====================================
  ! For Loop Execution
  ! =====================================

  recursive function execute_for_node(node, shell) result(exit_status)
    use variables, only: set_shell_variable
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, i

    exit_status = 0

    if (.not. associated(node%for_loop)) then
      return
    end if

    ! Iterate over words
    do i = 1, node%for_loop%num_words
      ! Set loop variable
      call set_shell_variable(shell, trim(node%for_loop%variable), trim(node%for_loop%words(i)), &
                              len_trim(node%for_loop%words(i)))

      ! Execute body
      if (associated(node%for_loop%body)) then
        exit_status = execute_ast_node(node%for_loop%body, shell)
      end if
    end do

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
    character(len=256) :: suffix, prefix

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

        ! Match pattern (simple implementation)
        if (trim(pattern) == '*') then
          ! Wildcard matches everything
          matched = .true.
        else if (index(pattern, '*') > 0) then
          ! Prefix/suffix wildcard (h* or *x or *mid*)
          if (pattern(1:1) == '*') then
            ! Suffix match: *suffix
            suffix = pattern(2:)
            if (len_trim(case_value) >= len_trim(suffix)) then
              if (case_value(len_trim(case_value)-len_trim(suffix)+1:) == trim(suffix)) then
                matched = .true.
              end if
            end if
          else if (pattern(len_trim(pattern):len_trim(pattern)) == '*') then
            ! Prefix match: prefix*
            prefix = pattern(1:len_trim(pattern)-1)
            if (case_value(1:len_trim(prefix)) == trim(prefix)) then
              matched = .true.
            end if
          end if
        else
          ! Exact match
          if (trim(case_value) == trim(pattern)) then
            matched = .true.
          end if
        end if

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
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer(c_pid_t) :: pid
    integer :: status

    exit_status = 0

    if (.not. associated(node%subshell)) then
      return
    end if

    ! Fork for subshell
    pid = c_fork()
    if (pid == 0) then
      ! Child process - execute commands in subshell
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
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status

    exit_status = 0

    if (.not. associated(node%subshell)) then
      return
    end if

    ! Execute in current shell (no fork)
    exit_status = execute_ast_node(node%subshell, shell)

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

    exit_status = 0

    if (num_words == 0) return

    cmd_path = trim(words(1))

    ! Try to execute command
    ! For now, just use system() as a placeholder
    ! TODO: Implement proper execvp with argv array
    ret = system(trim(cmd_path) // c_null_char)
    exit_status = extract_exit_status(ret)

  end subroutine execute_external_command

end module ast_executor
