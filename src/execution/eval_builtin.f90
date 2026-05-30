module eval_builtin
  use shell_types
  use grammar_parser, only: parse_command_line
  use command_tree, only: command_node_t
  use ast_executor, only: execute_ast
  use aliases, only: expand_alias, is_alias, get_alias
  implicit none

contains

  subroutine execute_eval(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, exit_code
    character(len=:), allocatable :: eval_command  ! grow with the command; never truncate at 4096
    type(command_node_t), pointer :: ast_root

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

    ! Expand aliases in the eval command
    ! eval should always expand aliases (like interactive mode)
    call expand_eval_aliases(shell, eval_command)

    ! Parse and execute the eval command using AST parser
    ast_root => parse_command_line(trim(eval_command))
    if (associated(ast_root)) then
      exit_code = execute_ast(ast_root, shell)
      shell%last_exit_status = exit_code
    else if (len_trim(eval_command) == 0) then
      ! Empty command is a no-op, not an error
      shell%last_exit_status = 0
    else
      ! Parse error - set failure status
      shell%last_exit_status = 1
    end if
  end subroutine execute_eval

  subroutine expand_eval_aliases(shell, command)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(inout) :: command
    character(len=256) :: first_word
    character(len=:), allocatable :: alias_value
    integer :: space_pos

    ! Extract first word
    space_pos = index(trim(command), ' ')
    if (space_pos > 0) then
      first_word = command(:space_pos-1)
    else
      first_word = trim(command)
    end if

    ! Check if it's an alias (only expand in interactive mode per POSIX)
    if (shell%is_interactive .and. is_alias(shell, trim(first_word))) then
      alias_value = get_alias(shell, trim(first_word))
      if (space_pos > 0) then
        command = trim(alias_value) // command(space_pos:)
      else
        command = trim(alias_value)
      end if
    end if
  end subroutine expand_eval_aliases

end module eval_builtin