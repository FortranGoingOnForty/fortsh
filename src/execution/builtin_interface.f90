module builtin_interface
  use shell_types
  implicit none

  ! Abstract interface for builtin execution
  ! This allows executor to call builtins without directly depending on the builtins module
  abstract interface
    logical function is_builtin_func(cmd_name) result(is_builtin)
      character(len=*), intent(in) :: cmd_name
    end function is_builtin_func

    subroutine execute_builtin_sub(cmd, shell)
      import :: command_t, shell_state_t
      type(command_t), intent(in) :: cmd
      type(shell_state_t), intent(inout) :: shell
    end subroutine execute_builtin_sub
  end interface

  ! Function pointers that will be set by the builtins module
  procedure(is_builtin_func), pointer :: is_builtin_ptr => null()
  procedure(execute_builtin_sub), pointer :: execute_builtin_ptr => null()

contains

  ! Wrapper functions that executor will call
  logical function is_builtin(cmd_name) result(res)
    character(len=*), intent(in) :: cmd_name
    if (associated(is_builtin_ptr)) then
      res = is_builtin_ptr(cmd_name)
    else
      res = .false.
    end if
  end function is_builtin

  subroutine execute_builtin(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    if (associated(execute_builtin_ptr)) then
      call execute_builtin_ptr(cmd, shell)
    else
      shell%last_exit_status = 127  ! Command not found
    end if
  end subroutine execute_builtin

end module builtin_interface