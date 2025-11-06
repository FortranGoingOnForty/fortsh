! ==============================================================================
! Module: command_capture
! Purpose: Command execution with output capture (for command substitution)
! ==============================================================================
! This module is separate from substitution to break circular dependencies:
! - parser uses expansion/substitution
! - expansion uses substitution
! - substitution needs to execute commands (uses parser)
!
! By isolating command execution here, we break the cycle.
! ==============================================================================
module command_capture
  use iso_c_binding
  use shell_types
  use system_interface
  implicit none

  ! C function bindings for file descriptor manipulation
  interface
    function dup(fd) bind(c, name='dup')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: dup
    end function

    function dup2(oldfd, newfd) bind(c, name='dup2')
      import :: c_int
      integer(c_int), value :: oldfd, newfd
      integer(c_int) :: dup2
    end function

    function close(fd) bind(c, name='close')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: close
    end function

    function c_fsync(fd) bind(c, name='fsync')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: c_fsync
    end function
  end interface

contains

  ! Execute a command and capture its output
  ! Used for command substitution: $(command) and `command`
  !
  ! TEMPORARY STUB: This is temporarily disabled to break circular module dependencies
  ! during Phase 0 of the parser rewrite. The circular dependency chain is:
  !   parser → expansion → command_capture → parser
  ! This will be properly fixed when the new grammar-aware parser is implemented,
  ! which will separate parsing from expansion phases.
  !
  ! TODO(parser-rewrite): Re-enable this once the new parser is functional
  subroutine execute_command_and_capture(shell, command, output)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command
    character(len=*), intent(out) :: output

    ! Temporarily return empty output to break circular dependency
    ! This means command substitution $(cmd) and `cmd` will not work during Phase 0
    output = ''

    ! Suppress unused parameter warning
    if (len(command) > 0) then
      ! Command parameter acknowledged
    end if

    ! Mark as not implemented for Phase 0
    shell%last_exit_status = 1
  end subroutine execute_command_and_capture

end module command_capture
