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
    ! User and host information
    character(256) :: username = ''
    character(256) :: hostname = ''

    ! Current working directory
    character(256) :: cwd = ''

    ! Shell state
    logical :: is_interactive = .false.
    logical :: running = .true.
    integer :: last_exit_status = 0

    ! Variables
    type(shell_var_t), dimension(1000) :: variables
    integer :: num_variables = 0

    ! Control flow depth
    integer :: control_depth = 0

    ! Shell options
    logical :: echo_commands = .false.
  end type shell_state_t

end module shell_types