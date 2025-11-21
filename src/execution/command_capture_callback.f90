module command_capture_callback
  use shell_types
  use grammar_parser, only: parse_command_line
  use ast_executor, only: execute_ast
  use command_tree, only: command_node_t
  implicit none

contains

  ! Callback function for command_capture module
  subroutine execute_for_capture(shell, command, exit_status)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command
    integer, intent(out) :: exit_status

    type(command_node_t), pointer :: ast_root

    ! Parse using new parser and execute via AST
    ast_root => parse_command_line(command)
    if (associated(ast_root)) then
      exit_status = execute_ast(ast_root, shell)
      ! If errexit triggered (shell%running = .false.), use the failing exit status
      if (.not. shell%running) then
        exit_status = shell%last_exit_status
      end if
      ! TODO: Add AST cleanup when deallocate_command_tree is available
    else
      exit_status = 127
    end if
  end subroutine execute_for_capture

  ! Initialize command capture callback
  subroutine init_command_capture()
    use command_capture, only: set_execute_callback
    call set_execute_callback(execute_for_capture)
  end subroutine init_command_capture

end module command_capture_callback