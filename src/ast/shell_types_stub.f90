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

  ! Forward declaration for AST node
  type :: ast_node_ptr_t
    class(*), pointer :: ptr => null()
  end type ast_node_ptr_t

  ! Shell function type
  type :: shell_function_t
    character(:), allocatable :: name
    type(ast_node_ptr_t) :: body  ! Points to function_node_t
  end type shell_function_t

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

    ! Positional parameters ($1, $2, etc.)
    character(256), dimension(100) :: positional_params
    integer :: num_positional = 0

    ! Script/function name ($0)
    character(256) :: script_name = ''

    ! Functions
    type(shell_function_t), dimension(100) :: functions
    integer :: num_functions = 0

    ! Control flow depth
    integer :: control_depth = 0

    ! Shell options
    logical :: echo_commands = .false.
  end type shell_state_t

end module shell_types