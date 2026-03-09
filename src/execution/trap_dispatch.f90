! Trap dispatch module — breaks circular dependency between executor and ast_executor.
! executor.f90 calls eval_trap_string() which delegates to the AST pipeline
! registered by ast_executor at startup via set_trap_evaluator().
module trap_dispatch
  use shell_types
  implicit none
  private
  public :: eval_trap_string, set_trap_evaluator

  abstract interface
    subroutine trap_eval_iface(cmd_string, shell, exit_code)
      import :: shell_state_t
      character(len=*), intent(in) :: cmd_string
      type(shell_state_t), intent(inout) :: shell
      integer, intent(out) :: exit_code
    end subroutine trap_eval_iface
  end interface

  procedure(trap_eval_iface), pointer :: trap_evaluator => null()

contains

  subroutine set_trap_evaluator(proc)
    procedure(trap_eval_iface) :: proc
    trap_evaluator => proc
  end subroutine set_trap_evaluator

  subroutine eval_trap_string(cmd_string, shell, exit_code)
    character(len=*), intent(in) :: cmd_string
    type(shell_state_t), intent(inout) :: shell
    integer, intent(out) :: exit_code

    exit_code = 0
    if (associated(trap_evaluator)) then
      call trap_evaluator(cmd_string, shell, exit_code)
    end if
  end subroutine eval_trap_string

end module trap_dispatch
