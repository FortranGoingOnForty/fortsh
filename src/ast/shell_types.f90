! ==============================================================================
! Module: shell_types
! Purpose: Stub module for shell state types - to be integrated with main shell
! ==============================================================================
module shell_types
  implicit none

  ! Shell variable type
  type :: shell_var_t
    character(:), allocatable :: name
    character(:), allocatable :: value
    logical :: is_export = .false.
    logical :: is_readonly = .false.
  end type shell_var_t

  ! Main shell state
  type :: shell_state_t
    ! Environment variables
    type(shell_var_t), allocatable :: vars(:)
    integer :: var_count = 0

    ! Exit code of last command
    integer :: last_exit_code = 0

    ! Current working directory
    character(256) :: cwd = ''

    ! Shell options
    logical :: interactive = .false.
    logical :: echo_commands = .false.
  end type shell_state_t

end module shell_types