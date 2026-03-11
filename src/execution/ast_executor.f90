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
  use job_control
  use glob, only: pattern_matches_no_dotfile_check
  use shell_options, only: check_errexit, trace_command
  implicit none
  private

  ! Public interface
  public :: execute_ast
  public :: execute_ast_node
  public :: unset_ast_function
  public :: is_ast_function
  public :: execute_external_command  ! Currently unused but may be needed later
  public :: register_trap_evaluator

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

  ! Register the AST evaluator with trap_dispatch (breaks circular dep with executor)
  subroutine register_trap_evaluator()
    use trap_dispatch, only: set_trap_evaluator
    call set_trap_evaluator(ast_eval_string)
  end subroutine register_trap_evaluator

  ! Wrapper matching trap_dispatch interface: parse string and execute via AST
  subroutine ast_eval_string(cmd_string, shell, exit_code)
    use grammar_parser, only: parse_command_line
    character(len=*), intent(in) :: cmd_string
    type(shell_state_t), intent(inout) :: shell
    integer, intent(out) :: exit_code
    type(command_node_t), pointer :: ast_root

    exit_code = 0
    ast_root => parse_command_line(cmd_string)
    if (associated(ast_root)) then
      exit_code = execute_ast(ast_root, shell)
    end if
  end subroutine ast_eval_string

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

    ! Update LINENO to reflect current line being executed
    if (node%line > 0) then
      shell%current_line_number = node%line
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
      ! node_type = 0 usually means uninitialized/invalid AST node from parser
      if (node%node_type == 0) then
        write(error_unit, '(A)') 'sh: -c: line 1: syntax error: unexpected end of file'
      else
        write(error_unit, '(A,I0)') 'fortsh: unknown node type: ', node%node_type
      end if
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
    use parser, only: expand_variables
    use iso_fortran_env, only: error_unit
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: i, func_idx, old_num_positional, eq_pos
    type(pipeline_t) :: temp_pipeline
    type(redirection_t) :: temp_redirect
    character(len=MAX_TOKEN_LEN) :: cmd_name
    character(len=1024), allocatable :: old_params(:)
    character(len=:), allocatable :: expanded_filename
    logical :: redir_success
    logical :: has_redirects, is_pure_assignment

    exit_status = 0

    if (.not. associated(node%simple_cmd)) then
      exit_status = 0
      return
    end if

    ! Check for empty command (e.g., from empty command substitution result like $(true))
    ! When a command substitution returns empty and is the only word, we have num_words=1
    ! but the word itself is empty
    if (node%simple_cmd%num_words > 0 .and. allocated(node%simple_cmd%words)) then
      block
        logical :: is_empty_cmd
        integer :: check_i, check_len

        ! Check if first word is empty (accounting for sentinel characters)
        is_empty_cmd = .false.
        check_len = len_trim(node%simple_cmd%words(1))
        if (check_len == 0) then
          is_empty_cmd = .true.
        else
          ! Check if word contains only sentinel characters (char(2), char(3))
          is_empty_cmd = .true.
          do check_i = 1, check_len
            if (node%simple_cmd%words(1)(check_i:check_i) /= char(2) .and. &
                node%simple_cmd%words(1)(check_i:check_i) /= char(3)) then
              is_empty_cmd = .false.
              exit
            end if
          end do
        end if

        if (is_empty_cmd) then
          ! Empty first word - check if it was a quoted literal empty string
          ! If so, it's an explicit empty command name which is "command not found"
          ! If not quoted (came from expansion), just preserve exit status
          if (allocated(node%simple_cmd%word_was_quoted)) then
            if (node%simple_cmd%word_was_quoted(1)) then
              ! Explicit empty string like '' or "" - command not found
              ! Apply any redirections first (e.g., 2>/dev/null)
              if (node%simple_cmd%num_redirects > 0) then
                block
                  use fd_redirection, only: apply_single_redirection, restore_fds
                  use parser, only: expand_variables
                  type(redirection_t) :: temp_redirect
                  logical :: redir_success
                  character(len=:), allocatable :: expanded_filename
                  integer :: redir_idx

                  do redir_idx = 1, node%simple_cmd%num_redirects
                    temp_redirect%type = node%simple_cmd%redirects(redir_idx)%type
                    temp_redirect%fd = node%simple_cmd%redirects(redir_idx)%fd
                    temp_redirect%target_fd = node%simple_cmd%redirects(redir_idx)%target_fd
                    if (allocated(node%simple_cmd%redirects(redir_idx)%filename)) then
                      call expand_variables(trim(node%simple_cmd%redirects(redir_idx)%filename), expanded_filename, shell)
                      if (allocated(expanded_filename)) then
                        temp_redirect%filename = expanded_filename
                      else
                        temp_redirect%filename = trim(node%simple_cmd%redirects(redir_idx)%filename)
                      end if
                    else
                      temp_redirect%filename = ''
                    end if
                    temp_redirect%force_clobber = node%simple_cmd%redirects(redir_idx)%force_clobber
                    call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
                  end do
                end block
              end if
              write(error_unit, '(a)') 'fortsh: : command not found'
              ! Restore file descriptors
              if (node%simple_cmd%num_redirects > 0) then
                call restore_fds()
              end if
              exit_status = 127
              shell%last_exit_status = exit_status
              return
            end if
          end if
          ! Empty from expansion - preserve exit status and return
          exit_status = shell%last_exit_status
          return
        end if
      end block
    end if

    if (node%simple_cmd%num_words == 0) then
      ! Handle pure assignments (no command, just VAR=value)
      if (node%simple_cmd%num_assignments > 0) then
        ! Process assignments as shell variable settings
        block
          use variables, only: set_shell_variable
          use parser, only: expand_variables
          integer :: assign_idx, assign_eq_pos, value_len, token_len, saved_status
          character(len=MAX_TOKEN_LEN) :: assign_name, assign_value
          character(len=:), allocatable :: expanded_value

          ! Save the exit status before assignment expansion
          ! POSIX: Pure assignment exit status should be 0 unless command substitution fails
          saved_status = shell%last_exit_status
          shell%last_exit_status = 0

          do assign_idx = 1, node%simple_cmd%num_assignments
            ! Use tracked length to preserve trailing whitespace
            if (allocated(node%simple_cmd%assignment_lengths) .and. &
                assign_idx <= size(node%simple_cmd%assignment_lengths)) then
              token_len = node%simple_cmd%assignment_lengths(assign_idx)
            else
              token_len = len_trim(node%simple_cmd%assignments(assign_idx))
            end if
            assign_eq_pos = index(node%simple_cmd%assignments(assign_idx), '=')
            if (assign_eq_pos > 1) then
              assign_name = node%simple_cmd%assignments(assign_idx)(1:assign_eq_pos-1)
              assign_value = node%simple_cmd%assignments(assign_idx)(assign_eq_pos+1:)

              ! Handle array element assignment: VAR[key]=value or VAR[idx]=value
              block
                use variables, only: is_associative_array, set_assoc_array_value, &
                                     set_array_element
                integer :: ab_pos, ab_end, ab_idx_status, ab_array_index
                character(len=256) :: ab_base_name, ab_index_str

                ab_pos = index(assign_name, '[')
                if (ab_pos > 0) then
                  ab_end = index(assign_name(ab_pos:), ']')
                  if (ab_end > 0) then
                    ab_end = ab_pos + ab_end - 1
                    ab_base_name = assign_name(1:ab_pos-1)
                    ab_index_str = assign_name(ab_pos+1:ab_end-1)

                    ! Calculate value_len for the value portion
                    if (len_trim(assign_value) > 0) then
                      value_len = len_trim(assign_value)
                    else
                      value_len = token_len - assign_eq_pos
                      if (value_len >= 2) then
                        if (node%simple_cmd%assignments(assign_idx)(assign_eq_pos+1:assign_eq_pos+1) == "'" .or. &
                            node%simple_cmd%assignments(assign_idx)(assign_eq_pos+1:assign_eq_pos+1) == '"') then
                          value_len = value_len - 2
                        end if
                      end if
                      if (value_len <= 0) value_len = 0
                    end if

                    ! Expand variables in value if needed
                    if (index(assign_value, '$') > 0 .or. index(assign_value, '~') > 0) then
                      call expand_variables(assign_value, expanded_value, shell)
                      if (allocated(expanded_value)) then
                        assign_value = expanded_value
                        value_len = len(expanded_value)
                      end if
                    end if

                    if (is_associative_array(shell, trim(ab_base_name))) then
                      call set_assoc_array_value(shell, trim(ab_base_name), &
                                                 trim(ab_index_str), assign_value(1:value_len))
                    else
                      read(ab_index_str, *, iostat=ab_idx_status) ab_array_index
                      if (ab_idx_status == 0) then
                        ab_array_index = ab_array_index + 1  ! Convert to 1-indexed
                        call set_array_element(shell, trim(ab_base_name), &
                                               ab_array_index, assign_value(1:value_len))
                      else
                        write(error_unit, '(a)') 'Error: invalid array index'
                        shell%last_exit_status = 1
                      end if
                    end if
                    cycle  ! Skip normal assignment processing
                  end if
                end if
              end block

              ! Calculate value_len - normally use len_trim, but preserve
              ! whitespace-only values (like IFS=" ")
              if (len_trim(assign_value) > 0) then
                ! Normal case: value has non-whitespace content
                value_len = len_trim(assign_value)
              else
                ! Special case: value is empty or all whitespace
                ! Use tracked length minus equals sign position
                value_len = token_len - assign_eq_pos
                ! Adjust for quotes if present in original
                if (value_len >= 2) then
                  if (node%simple_cmd%assignments(assign_idx)(assign_eq_pos+1:assign_eq_pos+1) == "'" .or. &
                      node%simple_cmd%assignments(assign_idx)(assign_eq_pos+1:assign_eq_pos+1) == '"') then
                    value_len = value_len - 2  ! Remove quote characters from length
                  end if
                end if
                if (value_len <= 0) value_len = 0
              end if

              ! Check if this is an array assignment: VAR=(...)
              if (value_len >= 2 .and. assign_value(1:1) == '(' .and. &
                  assign_value(value_len:value_len) == ')') then
                ! Array assignment - delegate to handle_array_assignment
                block
                  use variables, only: handle_array_assignment
                  call handle_array_assignment(shell, trim(assign_name), assign_value(1:value_len))
                end block
              ! Expand variables and command substitutions in the value
              else if (index(assign_value, '$') > 0 .or. index(assign_value, '~') > 0) then
                call expand_variables(assign_value, expanded_value, shell)
                if (allocated(expanded_value)) then
                  call set_shell_variable(shell, trim(assign_name), expanded_value, len(expanded_value))
                else
                  call set_shell_variable(shell, trim(assign_name), '', 0)
                end if
              else
                ! Preserve whitespace in value by passing explicit length
                ! Strip sentinel characters that may be embedded from lexer processing
                block
                  character(len=1024) :: clean_value
                  integer :: src_i, dst_i
                  clean_value = ''
                  dst_i = 1
                  do src_i = 1, value_len
                    if (assign_value(src_i:src_i) /= char(2) .and. &
                        assign_value(src_i:src_i) /= char(3) .and. &
                        assign_value(src_i:src_i) /= char(1)) then
                      clean_value(dst_i:dst_i) = assign_value(src_i:src_i)
                      dst_i = dst_i + 1
                    end if
                  end do
                  call set_shell_variable(shell, trim(assign_name), clean_value, dst_i - 1)
                end block
              end if

              ! If allexport is enabled (set -a), automatically export the variable
              if (shell%option_allexport) then
                block
                  integer :: var_idx
                  do var_idx = 1, shell%num_variables
                    if (trim(shell%variables(var_idx)%name) == trim(assign_name)) then
                      shell%variables(var_idx)%exported = .true.
                      ! Also set in environment
                      if (.not. set_environment_var(trim(assign_name), trim(shell%variables(var_idx)%value))) then
                        ! Silently ignore export errors (POSIX behavior)
                      end if
                      exit
                    end if
                  end do
                end block
              end if
            end if
          end do
        end block
      end if
      ! POSIX: Exit status of assignment is exit status of last command substitution
      ! This covers readonly violations (127) and failed command substitutions
      exit_status = shell%last_exit_status
      call check_errexit(shell, exit_status)
      return
    end if

    ! Special handling for exec with redirections
    if (node%simple_cmd%num_words >= 1 .and. trim(node%simple_cmd%words(1)) == 'exec') then
      ! Check if this is exec with only redirections (no command to execute)
      if (node%simple_cmd%num_words == 1 .and. node%simple_cmd%num_redirects > 0) then
        ! exec without arguments but with redirections - apply redirections permanently
        block
          use parser, only: expand_variables
          character(len=:), allocatable :: expanded_filename
          do i = 1, node%simple_cmd%num_redirects
            ! Convert AST redirection to fd_redirection format
            temp_redirect%type = node%simple_cmd%redirects(i)%type
            temp_redirect%fd = node%simple_cmd%redirects(i)%fd
            temp_redirect%target_fd = node%simple_cmd%redirects(i)%target_fd
            if (allocated(node%simple_cmd%redirects(i)%filename)) then
              ! Expand variables in the filename (e.g., $$ -> PID)
              call expand_variables(trim(node%simple_cmd%redirects(i)%filename), expanded_filename, shell)
              if (allocated(expanded_filename)) then
                temp_redirect%filename = expanded_filename
              else
                temp_redirect%filename = trim(node%simple_cmd%redirects(i)%filename)
              end if
            else
              temp_redirect%filename = ''
            end if
            temp_redirect%force_clobber = node%simple_cmd%redirects(i)%force_clobber

            call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber, permanent=.true.)
            if (.not. redir_success) then
              exit_status = 1
              return
            end if
          end do
        end block
        exit_status = 0
        return
      else if (node%simple_cmd%num_words == 1) then
        ! exec without arguments or redirections - just return success
        exit_status = 0
        return
      end if
      ! If we get here, exec has arguments, so fall through to normal execution
    end if

    ! Check if this is a function call (unless bypass_functions is set)
    if (node%simple_cmd%num_words >= 1) then
      cmd_name = trim(node%simple_cmd%words(1))
    else
      cmd_name = ''
    end if

    if (.not. shell%bypass_functions .and. len_trim(cmd_name) > 0) then
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
            use pipeline_helpers, only: expand_tokens
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

        ! Apply redirections for the function call
        block
          use fd_redirection, only: apply_single_redirection, restore_fds
          use parser, only: expand_variables
          type(redirection_t) :: temp_redirect
          logical :: redir_success, func_has_redirects
          character(len=:), allocatable :: expanded_filename
          integer :: redir_idx

          func_has_redirects = (node%simple_cmd%num_redirects > 0)
          if (func_has_redirects) then
            do redir_idx = 1, node%simple_cmd%num_redirects
              temp_redirect%type = node%simple_cmd%redirects(redir_idx)%type
              temp_redirect%fd = node%simple_cmd%redirects(redir_idx)%fd
              temp_redirect%target_fd = node%simple_cmd%redirects(redir_idx)%target_fd
              if (allocated(node%simple_cmd%redirects(redir_idx)%filename)) then
                call expand_variables(trim(node%simple_cmd%redirects(redir_idx)%filename), expanded_filename, shell)
                if (allocated(expanded_filename)) then
                  allocate(temp_redirect%filename, source=trim(expanded_filename))
                  deallocate(expanded_filename)
                else
                  allocate(temp_redirect%filename, source=trim(node%simple_cmd%redirects(redir_idx)%filename))
                end if
              end if
              temp_redirect%force_clobber = node%simple_cmd%redirects(redir_idx)%force_clobber

              call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
              if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
              if (.not. redir_success) then
                call restore_fds()
                exit_status = 1
                ! Restore old positional params before returning
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
          end if

        ! Increment function depth for return/exit context tracking
        shell%function_depth = shell%function_depth + 1

        ! Execute function body
        ! Save body pointer locally so unset -f during execution can't
        ! invalidate the pointer through the cache (Fortran aliasing)
        block
          type(command_node_t), pointer :: func_body
          func_body => function_ast_cache(func_idx)%body
          if (associated(func_body)) then
            exit_status = execute_ast_node(func_body, shell)
          else
            exit_status = 0
          end if
        end block

        ! Decrement function depth
        shell%function_depth = shell%function_depth - 1

        ! Restore file descriptors if we applied redirections
        if (func_has_redirects) then
          call restore_fds()
        end if
        end block

        ! Clear function return flag and use return value as exit status
        if (shell%function_return_pending) then
          exit_status = shell%function_return_value
          shell%function_return_pending = .false.
        end if

        ! Restore old positional parameters
        shell%num_positional = old_num_positional
        if (allocated(old_params)) then
          if (shell%num_positional > 0) then
            shell%positional_params(1:old_num_positional) = old_params(1:old_num_positional)
          end if
          deallocate(old_params)
        end if

        ! POSIX: exit in function should exit shell, not just return from function
        ! Preserve shell%last_exit_status which was set by builtin_exit
        if (.not. shell%running) then
          exit_status = shell%last_exit_status
        end if

        return
      end if
    end do
    end if  ! .not. shell%bypass_functions

    ! Convert AST simple command to command_t format for legacy executor dispatch.
    ! Pipeline execution is now handled directly by execute_pipeline_node (Phases 1-6).
    ! This conversion remains for individual command execution (builtins, externals,
    ! assignments, aliases, etc.) which still delegates to execute_single.

    allocate(temp_pipeline%commands(1))
    temp_pipeline%num_commands = 1

    ! Initialize command in place (avoid structure copy issues)
    temp_pipeline%commands(1)%num_tokens = node%simple_cmd%num_words
    temp_pipeline%commands(1)%separator = SEP_NONE
    temp_pipeline%commands(1)%background = .false.
    temp_pipeline%commands(1)%num_redirections = 0
    ! Copy prefix assignments from AST
    temp_pipeline%commands(1)%num_prefix_assignments = node%simple_cmd%num_assignments
    if (node%simple_cmd%num_assignments > 0 .and. allocated(node%simple_cmd%assignments)) then
      do i = 1, node%simple_cmd%num_assignments
        temp_pipeline%commands(1)%prefix_assignments(i) = node%simple_cmd%assignments(i)
      end do
    end if
    ! Check if words were pre-expanded in pipeline
    temp_pipeline%commands(1)%skip_expansion = node%simple_cmd%pre_expanded


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

    ! POSIX: For pure assignments (no command), process assignments BEFORE redirections
    ! This ensures assignment errors go to the shell's original stderr, not the redirected one
    if (node%simple_cmd%num_words > 0) then
      ! Check if all words are assignments (VAR=value pattern)
      is_pure_assignment = .true.
      do i = 1, node%simple_cmd%num_words
        eq_pos = index(trim(node%simple_cmd%words(i)), '=')
        if (eq_pos <= 1) then
          is_pure_assignment = .false.
          exit
        end if
        ! Check that everything before = is a valid var name
        if (.not. is_valid_assignment_name(node%simple_cmd%words(i)(1:eq_pos-1))) then
          is_pure_assignment = .false.
          exit
        end if
      end do

      if (is_pure_assignment) then
        ! Execute assignments before redirections
        call execute_pipeline(temp_pipeline, shell, '')
        exit_status = shell%last_exit_status

        ! Clean up and return - skip redirections for pure assignments
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
          ! Expand variables in redirect filename (e.g., /tmp/file$$)
          call expand_variables(trim(node%simple_cmd%redirects(i)%filename), expanded_filename, shell)
          if (allocated(expanded_filename)) then
            allocate(temp_redirect%filename, source=expanded_filename)
          else
            allocate(temp_redirect%filename, source=trim(node%simple_cmd%redirects(i)%filename))
          end if
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
    ! POSIX: Check errexit after command execution (including assignments with command substitutions)
    call check_errexit(shell, exit_status)
    ! If errexit triggered, return immediately
    if (.not. shell%running) then
      return
    end if

    ! Check if fatal expansion error occurred (e.g., set -u with undefined variable)
    if (shell%fatal_expansion_error) then
      ! NOTE: Don't reset fatal_expansion_error here - let it propagate to subshell handler
      ! The subshell code needs to know about the error to adjust exit code (127 -> 1)
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

    ! POSIX: Update $_ to last argument of previous command
    if (node%simple_cmd%num_words > 0 .and. allocated(node%simple_cmd%words)) then
      shell%last_arg = trim(node%simple_cmd%words(node%simple_cmd%num_words))
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
    integer :: i, status, ret, pipe_idx
    integer(c_int), allocatable, target :: pipefd(:,:)
    integer(c_pid_t), allocatable :: pids(:)
    integer(c_pid_t) :: pgid
    integer :: num_pipes, num_commands

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
        ! POSIX: Suppress errexit for negated pipelines
        if (node%pipeline%negate) shell%in_negation = .true.
        exit_status = execute_ast_node(node%pipeline%commands(1), shell)
        shell%in_negation = .false.
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
    num_commands = node%pipeline%num_commands
    num_pipes = num_commands - 1

    allocate(pipefd(2, num_pipes))
    allocate(pids(num_commands))

    ! POSIX: Pre-expand all command words before forking
    ! This ensures expansion errors go to the parent shell's stderr
    block
      logical :: was_running
      was_running = shell%running
      call pre_expand_pipeline(node, shell)
      ! Restore shell state - pipeline should still run even if expansion failed
      ! The error message already went to stderr; pipeline continues with expanded values
      shell%fatal_expansion_error = .false.
      shell%arithmetic_error = .false.
      shell%running = was_running
    end block

    ! Create all pipes
    do i = 1, num_pipes
      if (c_pipe(c_loc(pipefd(1, i))) /= 0) then
        write(error_unit, '(A)') 'fortsh: pipe creation failed'
        exit_status = 1
        deallocate(pipefd)
        deallocate(pids)
        return
      end if
    end do

    ! Xtrace: trace all pipeline commands BEFORE forking (deterministic order)
    ! Child processes will have xtrace suppressed to avoid double-tracing
    if (shell%option_xtrace) then
      call ast_trace_pipeline(node, shell)
    end if

    ! Flush all output before forking to prevent buffer duplication
    flush(output_unit)
    flush(error_unit)

    ! Fork and execute each command in the pipeline
    do i = 1, num_commands
      pids(i) = c_fork()

      if (pids(i) == 0) then
        ! Child process — mark as pipeline child so execute_external
        ! skips setpgid/tcsetpgrp (managed at pipeline level instead)
        shell%in_pipeline_child = .true.

        ! Set process group: all pipeline children share the first child's PID
        ! as their process group. Both child and parent call setpgid (race-free).
        if (i == 1) then
          pgid = c_getpid()
        else
          pgid = pids(1)
        end if
        ret = c_setpgid(0, pgid)

        ! Reset all signal handlers to default for pipeline children.
        ! Safe now because execute_external skips its own setpgid/tcsetpgrp
        ! when in_pipeline_child is set, so SIGTTOU won't stop the process.
        block
          type(c_funptr) :: old_handler
          old_handler = c_signal(SIGINT,  c_null_funptr)
          old_handler = c_signal(SIGPIPE, c_null_funptr)
          old_handler = c_signal(SIGTSTP, c_null_funptr)
          old_handler = c_signal(SIGTTIN, c_null_funptr)
          old_handler = c_signal(SIGTTOU, c_null_funptr)
        end block

        ! Set up stdin from previous pipe
        if (i > 1) then
          pipe_idx = i - 1
          ret = c_dup2(pipefd(1, pipe_idx), int(0, c_int))  ! Read from previous pipe
        end if

        ! Set up stdout to next pipe
        if (i < num_commands) then
          ret = c_dup2(pipefd(2, i), int(1, c_int))  ! Write to next pipe
        end if

        ! Close all pipe fds
        call close_all_pipes(pipefd, num_pipes)

        ! Suppress xtrace in child — parent already traced deterministically
        shell%option_xtrace = .false.

        ! POSIX: Only ignored traps (empty action) are visible in subshells
        ! Remove traps with commands, but keep traps with empty actions (ignore)
        call filter_traps_for_subshell(shell)

        ! Execute command
        status = execute_ast_node(node%pipeline%commands(i), shell)
        call c_exit(status)
      end if

      ! Parent: set process group (race-free — both parent and child call setpgid)
      if (pids(i) > 0) then
        if (i == 1) then
          pgid = pids(1)
        end if
        ret = c_setpgid(pids(i), pgid)
      end if
    end do

    ! Parent process - close all pipes
    call close_all_pipes(pipefd, num_pipes)

    if (node%pipeline%background) then
      ! Background pipeline: add job, don't wait
      block
        integer :: job_id
        character(len=1024) :: job_command
        job_command = ''
        ! Reconstruct command string from pipeline words
        do i = 1, node%pipeline%num_commands
          if (i > 1) job_command = trim(job_command) // ' | '
          if (associated(node%pipeline%commands(i)%simple_cmd)) then
            block
              integer :: w
              do w = 1, node%pipeline%commands(i)%simple_cmd%num_words
                if (w == 1 .and. i == 1) then
                  job_command = trim(node%pipeline%commands(i)%simple_cmd%words(w))
                else if (w == 1) then
                  job_command = trim(job_command) // &
                    trim(node%pipeline%commands(i)%simple_cmd%words(w))
                else
                  job_command = trim(job_command) // ' ' // &
                    trim(node%pipeline%commands(i)%simple_cmd%words(w))
                end if
              end do
            end block
          end if
        end do
        job_id = add_job(shell, pgid, trim(job_command), .false.)
        if (shell%is_interactive) then
          write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pids(1)
        end if
        shell%last_bg_pid = pids(num_commands)
      end block
      exit_status = 0
    else
      ! Foreground pipeline: give terminal, wait, restore terminal
      if (shell%is_interactive) then
        ret = c_tcsetpgrp(shell%shell_terminal, pgid)
      end if

      ! Wait for all children and collect exit statuses
      block
        integer(c_int), target :: wait_status
        integer, allocatable :: exit_statuses(:)
        allocate(exit_statuses(num_commands))

        do i = 1, num_commands
          ret = c_waitpid(pids(i), c_loc(wait_status), int(0, c_int))
          if (ret > 0) then
            if (WIFEXITED(wait_status)) then
              exit_statuses(i) = WEXITSTATUS(wait_status)
            else if (WIFSIGNALED(wait_status)) then
              exit_statuses(i) = 128 + WTERMSIG(wait_status)
            else
              exit_statuses(i) = 1
            end if
          else
            exit_statuses(i) = 1
          end if
        end do

        ! POSIX default: exit status from last command
        ! pipefail: rightmost non-zero exit status
        if (shell%option_pipefail) then
          exit_status = 0
          do i = num_commands, 1, -1
            if (exit_statuses(i) /= 0) then
              exit_status = exit_statuses(i)
              exit
            end if
          end do
        else
          exit_status = exit_statuses(num_commands)
        end if

        deallocate(exit_statuses)
      end block

      ! Restore terminal control to the shell's process group
      if (shell%is_interactive) then
        ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
      end if
    end if

    deallocate(pipefd)
    deallocate(pids)

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
    use iso_fortran_env, only: error_unit
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, left_status
    integer(c_pid_t) :: pid
    integer :: status
    character(len=1024) :: job_command, job_command2
    integer :: i, j

    exit_status = 0

    if (.not. associated(node%list)) then
      return
    end if

    ! For background jobs (&), handle specially - don't execute left side yet
    if (node%list%separator == LIST_SEP_BACKGROUND) then
      ! Special handling for left-associative parsing with semicolons
      ! For "a; b & c" which parses as "(a; b) & c", we need to:
      ! 1. Execute "a" in parent (synchronously)
      ! 2. Fork for "b" (background)
      ! 3. Execute "c" in parent
      if (associated(node%list%left)) then
        if (node%list%left%node_type == CMD_LIST) then
          if (associated(node%list%left%list)) then
            if (node%list%left%list%separator == LIST_SEP_SEQUENTIAL) then
              ! Execute the sequential commands before &, keeping the rightmost one for background
              ! Execute left part synchronously in parent
              if (associated(node%list%left%list%left)) then
                left_status = execute_ast_node(node%list%left%list%left, shell)
              end if
              ! Now fork only for the right part (the command immediately before &)
              if (associated(node%list%left%list%right)) then
                pid = c_fork()
                if (pid == 0) then
                  shell%is_interactive = .false.
                  shell%in_background = .true.
                  status = execute_ast_node(node%list%left%list%right, shell)
                  call c_exit(status)
                else if (pid > 0) then
                  shell%last_bg_pid = pid
                  ! Track job inline (duplicated code to avoid goto)
                  if (.not. shell%in_background) then
                    job_command = '<background job>'
                    if (associated(node%list%left%list%right)) then
                      if (node%list%left%list%right%node_type == CMD_SIMPLE) then
                        if (associated(node%list%left%list%right%simple_cmd)) then
                          if (node%list%left%list%right%simple_cmd%num_words > 0) then
                            job_command = ''
                            do i = 1, node%list%left%list%right%simple_cmd%num_words
                              if (i > 1) then
                                job_command = trim(job_command) // ' ' // trim(node%list%left%list%right%simple_cmd%words(i))
                              else
                                job_command = trim(node%list%left%list%right%simple_cmd%words(i))
                              end if
                            end do
                          end if
                        end if
                      end if
                    end if
                    status = add_job(shell, pid, trim(job_command), .false.)
                    if (shell%is_interactive) then
                      write(output_unit, '(a,i0,a,i0)') '[', status, '] ', pid
                    end if
                  end if
                end if
              end if
              ! Continue with right side
              if (associated(node%list%right)) then
                exit_status = execute_ast_node(node%list%right, shell)
              else
                exit_status = 0
              end if
              return
            end if
          end if
        end if
      end if

      ! Standard background handling (for non-sequential left sides)
      pid = c_fork()
      if (pid == 0) then
        ! Child process - execute left command and exit with its status
        ! Background jobs should not do terminal control or track sub-jobs
        shell%is_interactive = .false.
        shell%in_background = .true.
        ! Special case: if left side is itself a background list, execute only its left child
        ! This handles left-associative parsing: (a & b) & c should run a, not (a & b)
        if (associated(node%list%left)) then
          if (node%list%left%node_type == CMD_LIST) then
            if (associated(node%list%left%list)) then
              if (node%list%left%list%separator == LIST_SEP_BACKGROUND) then
                if (associated(node%list%left%list%left)) then
                  status = execute_ast_node(node%list%left%list%left, shell)
                else
                  status = 0
                end if
              else
                status = execute_ast_node(node%list%left, shell)
              end if
            else
              status = 0
            end if
          else
            status = execute_ast_node(node%list%left, shell)
          end if
        else
          status = 0
        end if
        call c_exit(status)
      else if (pid > 0) then
        ! Parent - add to job list and continue with right
        shell%last_bg_pid = pid
        ! Only track jobs if we're not already in a background job child
        if (.not. shell%in_background) then
          ! Reconstruct command string from AST node for job display
          job_command = '<background job>'  ! Default fallback
          if (associated(node%list%left)) then
            if (node%list%left%node_type == CMD_SIMPLE) then
              if (associated(node%list%left%simple_cmd)) then
                if (node%list%left%simple_cmd%num_words > 0) then
                  job_command = ''
                  do i = 1, node%list%left%simple_cmd%num_words
                    if (i > 1) then
                      job_command = trim(job_command) // ' ' // trim(node%list%left%simple_cmd%words(i))
                    else
                      job_command = trim(node%list%left%simple_cmd%words(i))
                    end if
                  end do
                end if
              end if
            end if
          end if

          status = add_job(shell, pid, trim(job_command), .false.)
          ! Only print job notification in interactive mode
          if (shell%is_interactive) then
            write(output_unit, '(a,i0,a,i0)') '[', status, '] ', pid
          end if
        end if

        ! Special case: if left side was a nested background list, fork for its right side too
        ! This handles left-associative parsing: (a & b) & c should fork for both a and b
        if (associated(node%list%left)) then
          if (node%list%left%node_type == CMD_LIST) then
            if (associated(node%list%left%list)) then
              if (node%list%left%list%separator == LIST_SEP_BACKGROUND) then
                if (associated(node%list%left%list%right)) then
                  pid = c_fork()
                  if (pid == 0) then
                    ! Child for the nested right side
                    shell%is_interactive = .false.
                    shell%in_background = .true.
                    left_status = execute_ast_node(node%list%left%list%right, shell)
                    call c_exit(left_status)
                  else if (pid > 0) then
                    ! Parent adds this job too
                    shell%last_bg_pid = pid
                    if (.not. shell%in_background) then
                      ! Reconstruct command string for the nested right side
                      job_command2 = '<background job>'
                      if (associated(node%list%left%list%right)) then
                        if (node%list%left%list%right%node_type == CMD_SIMPLE) then
                          if (associated(node%list%left%list%right%simple_cmd)) then
                            if (node%list%left%list%right%simple_cmd%num_words > 0) then
                              job_command2 = ''
                              do j = 1, node%list%left%list%right%simple_cmd%num_words
                                if (j > 1) then
                                  job_command2 = trim(job_command2) // ' ' // trim(node%list%left%list%right%simple_cmd%words(j))
                                else
                                  job_command2 = trim(node%list%left%list%right%simple_cmd%words(j))
                                end if
                              end do
                            end if
                          end if
                        end if
                      end if

                      status = add_job(shell, pid, trim(job_command2), .false.)
                      if (shell%is_interactive) then
                        write(output_unit, '(a,i0,a,i0)') '[', status, '] ', pid
                      end if
                    end if
                  end if
                end if
              end if
            end if
          end if
        end if

        if (associated(node%list%right)) then
          exit_status = execute_ast_node(node%list%right, shell)
        else
          exit_status = 0
        end if
        return
      else
        ! Fork failed
        exit_status = 1
        return
      end if
    end if

    ! Execute left side (for all non-background separators)
    if (associated(node%list%left)) then
      ! POSIX: Suppress errexit during left side of AND-OR lists
      if (node%list%separator == LIST_SEP_AND .or. node%list%separator == LIST_SEP_OR) then
        shell%in_and_or_list = .true.
      end if
      left_status = execute_ast_node(node%list%left, shell)
      shell%in_and_or_list = .false.
    else
      left_status = 0
    end if

    ! Errexit is checked at the simple command level instead

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
      ! Check for function return - if requested, skip the right side
      if (shell%function_return_pending) then
        exit_status = shell%function_return_value
        return
      end if
      ! Check if noexec was set - if so, skip right side (set -n behavior)
      if (shell%option_noexec .and. .not. shell%is_interactive) then
        exit_status = left_status
        return
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
      ! But first, handle any sourcing queued by the left side (e.g., dot command)
      if (shell%should_source) then
        call process_source_inline_ast(shell)
        left_status = shell%last_exit_status
      end if
      ! Check if noexec was set - if so, skip right side
      if (shell%option_noexec .and. .not. shell%is_interactive) then
        exit_status = left_status
      else if (left_status == 0) then
        if (associated(node%list%right)) then
          exit_status = execute_ast_node(node%list%right, shell)
        else
          exit_status = left_status
        end if
      else
        exit_status = left_status
      end if
      ! Mark that this result came from an AND-OR list (suppress errexit check)
      shell%last_from_and_or = .true.

    case(LIST_SEP_OR)
      ! || - Execute right only if left failed
      ! But first, handle any sourcing queued by the left side (e.g., dot command)
      if (shell%should_source) then
        call process_source_inline_ast(shell)
        left_status = shell%last_exit_status
      end if
      ! Check if noexec was set - if so, skip right side
      if (shell%option_noexec .and. .not. shell%is_interactive) then
        exit_status = left_status
      else if (left_status /= 0) then
        if (associated(node%list%right)) then
          exit_status = execute_ast_node(node%list%right, shell)
        else
          exit_status = left_status
        end if
      else
        exit_status = left_status
      end if
      ! Mark that this result came from an AND-OR list (suppress errexit check)
      shell%last_from_and_or = .true.

    case(LIST_SEP_BACKGROUND)
      ! & - Background jobs handled early in function (before left execution)
      exit_status = 0

    case default
      exit_status = left_status
    end select

  end function execute_list_node

  ! =====================================
  ! If Statement Execution
  ! =====================================

  recursive function execute_if_node(node, shell) result(exit_status)
    use fd_redirection, only: apply_single_redirection, restore_fds
    use parser, only: expand_variables
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, cond_status, i
    type(redirection_t) :: temp_redirect
    logical :: redir_success, has_redirects

    exit_status = 0

    if (.not. associated(node%if_stmt)) then
      return
    end if

    ! Apply redirections for the entire if statement
    has_redirects = (node%num_redirects > 0)
    if (has_redirects) then
      block
        character(len=:), allocatable :: expanded_filename
        do i = 1, node%num_redirects
          temp_redirect%type = node%redirects(i)%type
          temp_redirect%fd = node%redirects(i)%fd
          temp_redirect%target_fd = node%redirects(i)%target_fd
          if (allocated(node%redirects(i)%filename)) then
            call expand_variables(trim(node%redirects(i)%filename), expanded_filename, shell)
            if (allocated(expanded_filename)) then
              allocate(temp_redirect%filename, source=trim(expanded_filename))
              deallocate(expanded_filename)
            else
              allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
            end if
          end if
          temp_redirect%force_clobber = node%redirects(i)%force_clobber

          call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
          if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
          if (.not. redir_success) then
            call restore_fds()
            exit_status = 1
            return
          end if
        end do
      end block
    end if

    ! Evaluate condition
    if (associated(node%if_stmt%condition)) then
      ! POSIX: Suppress errexit during condition evaluation
      shell%evaluating_condition = .true.
      cond_status = execute_ast_node(node%if_stmt%condition, shell)
      shell%evaluating_condition = .false.
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

    ! Restore file descriptors if we applied redirections
    if (has_redirects) then
      call restore_fds()
    end if

  end function execute_if_node

  ! =====================================
  ! While/Until Loop Execution
  ! =====================================

  recursive function execute_while_node(node, shell) result(exit_status)
    use control_flow, only: push_control_block, pop_control_block, BLOCK_WHILE, BLOCK_UNTIL
    use fd_redirection, only: apply_single_redirection, restore_fds
    use parser, only: expand_variables
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, cond_status, i
    logical :: should_continue
    type(redirection_t) :: temp_redirect
    logical :: redir_success, has_redirects

    exit_status = 0

    if (.not. associated(node%while_loop)) then
      return
    end if

    ! Apply redirections for the entire while loop
    has_redirects = (node%num_redirects > 0)
    if (has_redirects) then
      block
        character(len=:), allocatable :: expanded_filename
        do i = 1, node%num_redirects
          temp_redirect%type = node%redirects(i)%type
          temp_redirect%fd = node%redirects(i)%fd
          temp_redirect%target_fd = node%redirects(i)%target_fd
          if (allocated(node%redirects(i)%filename)) then
            call expand_variables(trim(node%redirects(i)%filename), expanded_filename, shell)
            if (allocated(expanded_filename)) then
              allocate(temp_redirect%filename, source=trim(expanded_filename))
              deallocate(expanded_filename)
            else
              allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
            end if
          end if
          temp_redirect%force_clobber = node%redirects(i)%force_clobber

          call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
          if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
          if (.not. redir_success) then
            call restore_fds()
            exit_status = 1
            return
          end if
        end do
      end block
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

    ! Restore file descriptors if we applied redirections
    if (has_redirects) then
      call restore_fds()
    end if

  end function execute_while_node

  ! =====================================
  ! For Loop Execution
  ! =====================================

  recursive function execute_for_node(node, shell) result(exit_status)
    use variables, only: set_shell_variable, get_shell_variable
    use control_flow, only: push_control_block, pop_control_block, BLOCK_FOR
    use glob, only: glob_match, has_unescaped_glob_chars
    use parser, only: expand_variables
    use fd_redirection, only: apply_single_redirection, restore_fds
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, i, j, glob_count, word_idx, k, split_count
    integer, parameter :: MAX_GLOB = 256, MAX_SPLIT = 256
    character(len=MAX_TOKEN_LEN), allocatable :: glob_matches(:)
    character(len=MAX_TOKEN_LEN), allocatable :: expanded_words(:)
    character(len=:), allocatable :: expanded_word, ifs_chars
    character(len=MAX_TOKEN_LEN), allocatable :: split_words(:)
    integer :: total_words
    type(redirection_t) :: temp_redirect
    logical :: redir_success, has_redirects

    exit_status = 0

    if (.not. associated(node%for_loop)) then
      return
    end if

    ! Apply redirections for the entire for loop
    has_redirects = (node%num_redirects > 0)
    if (has_redirects) then
      block
        character(len=:), allocatable :: expanded_filename
        do i = 1, node%num_redirects
          temp_redirect%type = node%redirects(i)%type
          temp_redirect%fd = node%redirects(i)%fd
          temp_redirect%target_fd = node%redirects(i)%target_fd
          if (allocated(node%redirects(i)%filename)) then
            ! Expand variables in filename
            call expand_variables(trim(node%redirects(i)%filename), expanded_filename, shell)
            if (allocated(expanded_filename)) then
              allocate(temp_redirect%filename, source=trim(expanded_filename))
              deallocate(expanded_filename)
            else
              allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
            end if
          end if
          temp_redirect%force_clobber = node%redirects(i)%force_clobber

          call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
          if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
          if (.not. redir_success) then
            call restore_fds()
            exit_status = 1
            return
          end if
        end do
      end block
    end if

    ! Get IFS for word splitting
    ! POSIX: Empty IFS (IFS="") means no field splitting
    ! Unset IFS means use default (space, tab, newline)
    if (shell%ifs_len == 0) then
      ! IFS is set but empty - no splitting will occur
      ifs_chars = ''
    else if (shell%ifs_len > 0) then
      ! IFS is set with content - use it
      ifs_chars = shell%ifs(1:shell%ifs_len)
    else
      ! Default IFS
      ifs_chars = ' ' // achar(9) // new_line('a')
    end if

    ! First, expand variables and split on IFS, then expand globs
    allocate(expanded_words(MAX_TOKEN_LEN))
    allocate(glob_matches(MAX_GLOB))
    allocate(split_words(MAX_SPLIT))
    total_words = 0

    ! POSIX: If 'in' is omitted (num_words == 0), iterate over positional parameters
    if (node%for_loop%num_words == 0) then
      do i = 1, shell%num_positional
        if (total_words < MAX_TOKEN_LEN) then
          total_words = total_words + 1
          expanded_words(total_words) = shell%positional_params(i)
        end if
      end do
    else

    do i = 1, node%for_loop%num_words
      ! Special handling for quoted "$@" - each positional parameter becomes a separate word
      if (trim(node%for_loop%words(i)) == '$@' .and. &
          allocated(node%for_loop%words_was_quoted) .and. &
          node%for_loop%words_was_quoted(i)) then
        ! Quoted $@ - add each positional parameter as separate word without IFS splitting
        do j = 1, shell%num_positional
          if (total_words < MAX_TOKEN_LEN) then
            total_words = total_words + 1
            expanded_words(total_words) = shell%positional_params(j)
          end if
        end do
        cycle  ! Skip normal expansion for this word
      end if

      ! First expand variables (e.g., $*, $@, $var)
      ! Pass the quoted status so expand_variables can handle it correctly
      if (allocated(node%for_loop%words_was_quoted) .and. i <= size(node%for_loop%words_was_quoted)) then
        call expand_variables(trim(node%for_loop%words(i)), expanded_word, shell, &
                            was_quoted_in=node%for_loop%words_was_quoted(i))
      else
        call expand_variables(trim(node%for_loop%words(i)), expanded_word, shell, was_quoted_in=.false.)
      end if

      ! Split the expanded word on IFS characters ONLY if:
      ! 1. It was NOT originally quoted, AND
      ! 2. It contained a parameter expansion ($ or backtick)
      ! POSIX: Field splitting only occurs on results of expansions, not literal text
      if (allocated(node%for_loop%words_was_quoted) .and. i <= size(node%for_loop%words_was_quoted) .and. &
          node%for_loop%words_was_quoted(i)) then
        ! Word was quoted - do not split, treat as single word
        split_words(1) = trim(expanded_word)
        split_count = 1
      else if (index(node%for_loop%words(i), '$') > 0 .or. &
               index(node%for_loop%words(i), '`') > 0) then
        ! Word contained expansion - split on IFS
        call split_on_ifs(trim(expanded_word), ifs_chars, split_words, split_count)
      else
        ! Literal word (no expansion) - do not split on IFS
        split_words(1) = trim(expanded_word)
        split_count = 1
      end if

      ! Now process each split word for globs
      do k = 1, split_count
        ! Only expand globs if noglob option is NOT set (POSIX: set -f disables glob)
        if (.not. shell%option_noglob .and. has_unescaped_glob_chars(trim(split_words(k)))) then
          ! Expand the glob pattern
          call glob_match(trim(split_words(k)), glob_matches, glob_count)
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
              expanded_words(total_words) = split_words(k)
            end if
          end if
        else
          ! Not a glob pattern - use the word as-is
          if (total_words < MAX_TOKEN_LEN) then
            total_words = total_words + 1
            expanded_words(total_words) = split_words(k)
          end if
        end if
      end do
    end do
    end if  ! End of else branch for num_words > 0

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
    if (allocated(glob_matches)) deallocate(glob_matches)
    if (allocated(split_words)) deallocate(split_words)

    ! Restore file descriptors if we applied redirections
    if (has_redirects) then
      call restore_fds()
    end if

  end function execute_for_node

  ! =====================================
  ! Case Statement Execution
  ! =====================================

  function execute_case_node(node, shell) result(exit_status)
    use variables, only: get_shell_variable
    use parser, only: expand_variables
    use fd_redirection, only: apply_single_redirection, restore_fds
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status, i
    character(len=MAX_TOKEN_LEN) :: case_value
    integer :: item_idx, pattern_idx
    logical :: matched
    character(len=MAX_TOKEN_LEN) :: pattern
    character(len=:), allocatable :: expanded_pattern
    type(redirection_t) :: temp_redirect
    logical :: redir_success, has_redirects

    exit_status = 0

    if (.not. associated(node%case_stmt)) then
      return
    end if

    ! Apply redirections for the entire case statement
    has_redirects = (node%num_redirects > 0)
    if (has_redirects) then
      block
        character(len=:), allocatable :: expanded_filename
        do i = 1, node%num_redirects
          temp_redirect%type = node%redirects(i)%type
          temp_redirect%fd = node%redirects(i)%fd
          temp_redirect%target_fd = node%redirects(i)%target_fd
          if (allocated(node%redirects(i)%filename)) then
            call expand_variables(trim(node%redirects(i)%filename), expanded_filename, shell)
            if (allocated(expanded_filename)) then
              allocate(temp_redirect%filename, source=trim(expanded_filename))
              deallocate(expanded_filename)
            else
              allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
            end if
          end if
          temp_redirect%force_clobber = node%redirects(i)%force_clobber

          call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
          if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
          if (.not. redir_success) then
            call restore_fds()
            exit_status = 1
            return
          end if
        end do
      end block
    end if

    ! Get the value to match (expand variables)
    ! Note: Don't trim - the value might BE whitespace (e.g., " " in case " " in ...)
    case_value = node%case_stmt%word
    ! If it starts with $, expand it
    if (len_trim(case_value) > 0 .and. case_value(1:1) == '$') then
      case_value = get_shell_variable(shell, trim(case_value(2:)))
    end if

    ! Try to match against each case item
    do item_idx = 1, node%case_stmt%num_items
      matched = .false.

      ! Check each pattern in this item
      do pattern_idx = 1, node%case_stmt%items(item_idx)%num_patterns
        pattern = trim(node%case_stmt%items(item_idx)%patterns(pattern_idx))

        ! Expand variables in pattern (e.g., $P)
        call expand_variables(pattern, expanded_pattern, shell, was_quoted_in=.false.)

        ! Match pattern using glob module (handles *, ?, [abc], [[:class:]], etc.)
        ! Note: Don't trim case_value - it might BE whitespace
        matched = pattern_matches_no_dotfile_check(trim(expanded_pattern), case_value)

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

    ! Restore file descriptors if we applied redirections
    if (has_redirects) then
      call restore_fds()
    end if

  end function execute_case_node

  ! =====================================
  ! Subshell Execution
  ! =====================================

  recursive function execute_subshell_node(node, shell) result(exit_status)
    use fd_redirection, only: apply_single_redirection
    use parser, only: expand_variables
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
      ! POSIX: Only ignored traps (empty action) are visible in subshells
      ! Remove traps with commands, but keep traps with empty actions (ignore)
      call filter_traps_for_subshell(shell)

      ! Apply redirections in child process
      if (node%num_redirects > 0) then
        block
          character(len=:), allocatable :: expanded_filename
          do i = 1, node%num_redirects
            temp_redirect%type = node%redirects(i)%type
            temp_redirect%fd = node%redirects(i)%fd
            temp_redirect%target_fd = node%redirects(i)%target_fd
            if (allocated(node%redirects(i)%filename)) then
              call expand_variables(trim(node%redirects(i)%filename), expanded_filename, shell)
              if (allocated(expanded_filename)) then
                allocate(temp_redirect%filename, source=trim(expanded_filename))
                deallocate(expanded_filename)
              else
                allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
              end if
            end if
            temp_redirect%force_clobber = node%redirects(i)%force_clobber

            call apply_single_redirection(temp_redirect, redir_success, shell%option_noclobber)
            if (allocated(temp_redirect%filename)) deallocate(temp_redirect%filename)
            if (.not. redir_success) then
              call c_exit(1)
            end if
          end do
        end block
      end if

      status = execute_ast_node(node%subshell, shell)
      ! bash: expansion errors in subshells exit with 1, not 127
      if (shell%fatal_expansion_error .and. status == 127) then
        status = 1
      end if
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
    use parser, only: expand_variables
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_status
    integer :: i
    type(redirection_t) :: temp_redirect
    logical :: redir_success
    character(len=:), allocatable :: expanded_filename

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
          ! Expand variables in redirect filename (e.g., $$ becomes PID)
          call expand_variables(trim(node%redirects(i)%filename), expanded_filename, shell)
          if (allocated(expanded_filename)) then
            allocate(temp_redirect%filename, source=trim(expanded_filename))
            deallocate(expanded_filename)
          else
            allocate(temp_redirect%filename, source=trim(node%redirects(i)%filename))
          end if
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
    integer(c_int), intent(in) :: pipefd(:,:)
    integer, intent(in) :: num_pipes
    integer :: i, ret

    do i = 1, num_pipes
      ret = c_close(pipefd(1, i))
      ret = c_close(pipefd(2, i))
    end do
  end subroutine close_all_pipes

  ! Trace all commands in an AST pipeline for xtrace (set -x)
  subroutine ast_trace_pipeline(node, shell)
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j
    character(len=2048) :: trace_str

    if (.not. associated(node%pipeline)) return
    if (.not. associated(node%pipeline%commands)) return

    do i = 1, node%pipeline%num_commands
      if (node%pipeline%commands(i)%node_type /= CMD_SIMPLE) cycle
      if (.not. associated(node%pipeline%commands(i)%simple_cmd)) cycle
      if (node%pipeline%commands(i)%simple_cmd%num_words == 0) cycle

      trace_str = ''
      do j = 1, node%pipeline%commands(i)%simple_cmd%num_words
        if (j == 1) then
          trace_str = trim(node%pipeline%commands(i)%simple_cmd%words(j))
        else
          trace_str = trim(trace_str) // ' ' // trim(node%pipeline%commands(i)%simple_cmd%words(j))
        end if
      end do
      call trace_command(shell, trim(trace_str))
    end do
  end subroutine ast_trace_pipeline

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
      function c_system(cmd) bind(c, name='system')
        import :: c_char, c_int
        character(kind=c_char), dimension(*) :: cmd
        integer(c_int) :: c_system
      end function
    end interface

    exit_status = 0

    if (num_words == 0) return

    cmd_path = trim(words(1))

    ! Try to execute command
    ! For now, just use system() as a placeholder
    ! TODO: Implement proper execvp with argv array
    ret = c_system(trim(cmd_path) // c_null_char)
    exit_status = extract_exit_status(ret)

  end subroutine execute_external_command

  ! Execute a pending trap command (set by signal_handling module)
  subroutine execute_pending_trap(shell)
    use grammar_parser, only: parse_command_line
    use command_tree, only: destroy_command_node
    type(shell_state_t), intent(inout) :: shell
    type(command_node_t), pointer :: trap_ast
    integer :: saved_status, trap_status
    logical :: saved_bypass
    character(len=4096) :: trap_cmd

    ! Save the trap command and signal before clearing
    trap_cmd = shell%pending_trap_command

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

    ! Parse and execute the trap command using AST parser
    trap_ast => parse_command_line(trim(trap_cmd))
    if (associated(trap_ast)) then
      trap_status = execute_ast_node(trap_ast, shell)
      call destroy_command_node(trap_ast)
    end if

    ! Clear flag to allow future trap execution
    shell%executing_trap = .false.

    ! Restore bypass_functions and exit status
    shell%bypass_functions = saved_bypass
    shell%last_exit_status = saved_status
  end subroutine execute_pending_trap

  ! Process sourced files inline (for dot command in lists)
  subroutine process_source_inline_ast(shell)
    use grammar_parser, only: parse_command_line
    use command_tree, only: destroy_command_node
    use parser, only: has_unclosed_quote, ends_with_continuation_backslash, &
                      needs_compound_continuation, remove_line_continuations
    type(shell_state_t), intent(inout) :: shell
    character(len=16384) :: input_line
    character(len=1024) :: continuation_line
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

    ! Increment source depth for return tracking
    shell%source_depth = shell%source_depth + 1

    ! Execute each line in the file
    do
      read(file_unit, '(a)', iostat=iostat) input_line
      if (iostat /= 0) exit  ! End of file or error

      ! Skip empty lines and comments
      if (len_trim(input_line) == 0 .or. input_line(1:1) == '#') cycle

      ! Check for unclosed quotes or backslash continuation
      do while (has_unclosed_quote(input_line) .or. ends_with_continuation_backslash(input_line))
        read(file_unit, '(a)', iostat=iostat) continuation_line
        if (iostat /= 0) exit
        input_line = trim(input_line) // char(10) // trim(continuation_line)
      end do

      ! Handle line continuation (backslash-newline)
      input_line = remove_line_continuations(input_line)

      ! If EOF was reached during continuation, exit
      if (iostat /= 0) exit

      ! Check for unclosed compound commands (if/fi, do/done, case/esac, {/})
      do while (needs_compound_continuation(input_line))
        read(file_unit, '(a)', iostat=iostat) continuation_line
        if (iostat /= 0) exit
        input_line = trim(input_line) // char(10) // trim(continuation_line)
      end do

      ! Parse and execute using AST parser
      ast_root => parse_command_line(trim(input_line))
      if (associated(ast_root)) then
        exit_code = execute_ast_node(ast_root, shell)
        shell%last_exit_status = exit_code
        ! Don't destroy function definitions - their AST is cached for later execution
        if (ast_root%node_type /= CMD_FUNCTION_DEF) then
          call destroy_command_node(ast_root)
        end if
      end if

      ! Stop execution if exit command was encountered
      if (.not. shell%running) exit

      ! Stop execution if return was called from sourced script
      if (shell%function_return_pending .and. shell%source_depth > 0) exit
    end do

    ! Decrement source depth
    shell%source_depth = shell%source_depth - 1

    ! Clear the return flag if we're exiting due to return in sourced script
    if (shell%function_return_pending .and. shell%function_depth == 0) then
      shell%function_return_pending = .false.
    end if

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

  ! Split a string on IFS characters
  subroutine split_on_ifs(str, ifs_chars, words, word_count)
    character(len=*), intent(in) :: str
    character(len=*), intent(in) :: ifs_chars
    character(len=MAX_TOKEN_LEN), intent(out) :: words(:)
    integer, intent(out) :: word_count
    integer :: i, str_len, word_pos, max_words
    logical :: in_word
    character(len=MAX_TOKEN_LEN) :: current_word

    word_count = 0
    current_word = ''
    word_pos = 0
    in_word = .false.
    str_len = len_trim(str)
    max_words = size(words)

    ! Handle empty string
    if (str_len == 0) then
      return
    end if

    ! Special case: empty IFS means no splitting - return entire string as one word
    if (len(ifs_chars) == 0) then
      word_count = 1
      words(1) = str(1:str_len)
      return
    end if

    do i = 1, str_len
      if (index(ifs_chars, str(i:i)) > 0) then
        ! IFS character - end current word if in one
        if (in_word) then
          word_count = word_count + 1
          if (word_count <= max_words) then
            words(word_count) = current_word(1:word_pos)
          end if
          current_word = ''
          word_pos = 0
          in_word = .false.
        end if
      else
        ! Non-IFS character - add to current word (preserve spaces!)
        word_pos = word_pos + 1
        current_word(word_pos:word_pos) = str(i:i)
        in_word = .true.
      end if
    end do

    ! Add final word if any
    if (in_word) then
      word_count = word_count + 1
      if (word_count <= max_words) then
        words(word_count) = current_word(1:word_pos)
      end if
    end if
  end subroutine split_on_ifs

  ! Pre-expand all simple command words in a pipeline before forking
  ! POSIX: Expansion errors should go to parent shell's stderr
  subroutine pre_expand_pipeline(node, shell)
    use pipeline_helpers, only: expand_tokens
    type(command_node_t), pointer, intent(in) :: node
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j
    type(command_t) :: temp_cmd

    if (.not. associated(node%pipeline)) return
    if (.not. associated(node%pipeline%commands)) return

    do i = 1, node%pipeline%num_commands
      if (node%pipeline%commands(i)%node_type /= CMD_SIMPLE) cycle
      if (.not. associated(node%pipeline%commands(i)%simple_cmd)) cycle

      ! Build temporary command structure for expansion
      temp_cmd%num_tokens = node%pipeline%commands(i)%simple_cmd%num_words
      if (temp_cmd%num_tokens == 0) cycle

      allocate(character(len=MAX_TOKEN_LEN) :: temp_cmd%tokens(temp_cmd%num_tokens))
      allocate(temp_cmd%token_quoted(temp_cmd%num_tokens))
      allocate(temp_cmd%token_escaped(temp_cmd%num_tokens))
      allocate(temp_cmd%token_quote_type(temp_cmd%num_tokens))
      allocate(temp_cmd%token_lengths(temp_cmd%num_tokens))

      ! Copy words to temp command
      do j = 1, temp_cmd%num_tokens
        ! Preserve whitespace for quoted tokens by using word_lengths
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_was_quoted) .and. &
            allocated(node%pipeline%commands(i)%simple_cmd%word_lengths)) then
          if (node%pipeline%commands(i)%simple_cmd%word_was_quoted(j)) then
            temp_cmd%tokens(j) = node%pipeline%commands(i)%simple_cmd%words(j)( &
                                  1:node%pipeline%commands(i)%simple_cmd%word_lengths(j))
            temp_cmd%token_lengths(j) = node%pipeline%commands(i)%simple_cmd%word_lengths(j)
          else
            temp_cmd%tokens(j) = trim(node%pipeline%commands(i)%simple_cmd%words(j))
            temp_cmd%token_lengths(j) = len_trim(node%pipeline%commands(i)%simple_cmd%words(j))
          end if
        else
          temp_cmd%tokens(j) = trim(node%pipeline%commands(i)%simple_cmd%words(j))
          temp_cmd%token_lengths(j) = len_trim(node%pipeline%commands(i)%simple_cmd%words(j))
        end if
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_was_quoted)) then
          temp_cmd%token_quoted(j) = node%pipeline%commands(i)%simple_cmd%word_was_quoted(j)
        else
          temp_cmd%token_quoted(j) = .false.
        end if
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_was_escaped)) then
          temp_cmd%token_escaped(j) = node%pipeline%commands(i)%simple_cmd%word_was_escaped(j)
        else
          temp_cmd%token_escaped(j) = .false.
        end if
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_quote_type)) then
          temp_cmd%token_quote_type(j) = node%pipeline%commands(i)%simple_cmd%word_quote_type(j)
        else
          temp_cmd%token_quote_type(j) = QUOTE_NONE
        end if
      end do

      ! Expand tokens (errors go to parent stderr)
      call expand_tokens(temp_cmd, shell)

      ! Copy expanded tokens back to AST node
      ! Reallocate if number of tokens changed
      if (temp_cmd%num_tokens /= node%pipeline%commands(i)%simple_cmd%num_words) then
        if (allocated(node%pipeline%commands(i)%simple_cmd%words)) &
            deallocate(node%pipeline%commands(i)%simple_cmd%words)
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_lengths)) &
            deallocate(node%pipeline%commands(i)%simple_cmd%word_lengths)
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_was_quoted)) &
            deallocate(node%pipeline%commands(i)%simple_cmd%word_was_quoted)
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_was_escaped)) &
            deallocate(node%pipeline%commands(i)%simple_cmd%word_was_escaped)
        if (allocated(node%pipeline%commands(i)%simple_cmd%word_quote_type)) &
            deallocate(node%pipeline%commands(i)%simple_cmd%word_quote_type)

        allocate(node%pipeline%commands(i)%simple_cmd%words(temp_cmd%num_tokens))
        allocate(node%pipeline%commands(i)%simple_cmd%word_lengths(temp_cmd%num_tokens))
        allocate(node%pipeline%commands(i)%simple_cmd%word_was_quoted(temp_cmd%num_tokens))
        allocate(node%pipeline%commands(i)%simple_cmd%word_was_escaped(temp_cmd%num_tokens))
        allocate(node%pipeline%commands(i)%simple_cmd%word_quote_type(temp_cmd%num_tokens))
        node%pipeline%commands(i)%simple_cmd%num_words = temp_cmd%num_tokens
      end if

      do j = 1, temp_cmd%num_tokens
        node%pipeline%commands(i)%simple_cmd%words(j) = temp_cmd%tokens(j)
        node%pipeline%commands(i)%simple_cmd%word_lengths(j) = temp_cmd%token_lengths(j)
        node%pipeline%commands(i)%simple_cmd%word_was_quoted(j) = temp_cmd%token_quoted(j)
        node%pipeline%commands(i)%simple_cmd%word_was_escaped(j) = temp_cmd%token_escaped(j)
        node%pipeline%commands(i)%simple_cmd%word_quote_type(j) = temp_cmd%token_quote_type(j)
      end do

      ! Mark as pre-expanded so executor skips expansion
      node%pipeline%commands(i)%simple_cmd%pre_expanded = .true.

      ! Clean up
      if (allocated(temp_cmd%tokens)) deallocate(temp_cmd%tokens)
      if (allocated(temp_cmd%token_quoted)) deallocate(temp_cmd%token_quoted)
      if (allocated(temp_cmd%token_escaped)) deallocate(temp_cmd%token_escaped)
      if (allocated(temp_cmd%token_quote_type)) deallocate(temp_cmd%token_quote_type)
      if (allocated(temp_cmd%token_lengths)) deallocate(temp_cmd%token_lengths)
    end do
  end subroutine pre_expand_pipeline

  ! Check if a string is a valid shell variable name for assignment
  ! POSIX: name must start with letter or underscore, followed by letters, digits, or underscores
  function is_valid_assignment_name(name) result(valid)
    character(len=*), intent(in) :: name
    logical :: valid
    integer :: i, name_len
    character :: ch

    valid = .false.
    name_len = len_trim(name)

    if (name_len == 0) return

    ! First character must be letter or underscore
    ch = name(1:1)
    if (.not. ((ch >= 'a' .and. ch <= 'z') .or. &
               (ch >= 'A' .and. ch <= 'Z') .or. &
               ch == '_')) then
      return
    end if

    ! Remaining characters must be letter, digit, or underscore
    do i = 2, name_len
      ch = name(i:i)
      if (.not. ((ch >= 'a' .and. ch <= 'z') .or. &
                 (ch >= 'A' .and. ch <= 'Z') .or. &
                 (ch >= '0' .and. ch <= '9') .or. &
                 ch == '_')) then
        return
      end if
    end do

    valid = .true.
  end function is_valid_assignment_name

  ! Mark traps as inherited for subshell: traps remain visible for listing
  ! but will not be executed when the subshell exits
  ! POSIX: `trap` command should show parent's traps, but they don't execute in subshell
  subroutine filter_traps_for_subshell(shell)
    type(shell_state_t), intent(inout) :: shell
    integer :: i

    do i = 1, shell%num_traps
      if (shell%traps(i)%active) then
        ! Mark all traps with commands as inherited (visible but not executed)
        ! Empty command traps (ignore) remain effective
        if (len_trim(shell%traps(i)%command) > 0) then
          shell%traps(i)%inherited = .true.
        end if
      end if
    end do
  end subroutine filter_traps_for_subshell

end module ast_executor
