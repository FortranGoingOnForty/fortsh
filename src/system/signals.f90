! ==============================================================================
! Module: signal_handler
! Purpose: Signal handling for job control
! ==============================================================================
module signal_handler
  use iso_c_binding
  use system_interface
  implicit none

contains

  subroutine setup_signal_handlers()
    type(c_funptr) :: old_handler
    
    ! Ignore interactive signals for shell itself
    SIG_IGN = c_null_funptr
    old_handler = c_signal(SIGINT, SIG_IGN)
    old_handler = c_signal(SIGTSTP, SIG_IGN)
    old_handler = c_signal(SIGTTIN, SIG_IGN)
    old_handler = c_signal(SIGTTOU, SIG_IGN)
  end subroutine

end module signal_handler