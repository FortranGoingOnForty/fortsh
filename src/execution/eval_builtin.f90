module eval_builtin
  use shell_types
  use grammar_parser, only: parse_command_line
  use command_tree, only: command_node_t
  use ast_executor, only: execute_ast
  implicit none

contains

  subroutine execute_eval(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, exit_code
    character(len=4096) :: eval_command
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

    ! Parse and execute the eval command using AST parser
    ast_root => parse_command_line(trim(eval_command))
    if (associated(ast_root)) then
      exit_code = execute_ast(ast_root, shell)
      shell%last_exit_status = exit_code
    else
      ! Parse error - set failure status
      shell%last_exit_status = 1
    end if
  end subroutine execute_eval

end module eval_builtin