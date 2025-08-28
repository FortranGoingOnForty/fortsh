! ==============================================================================
! Module: shell_types
! Purpose: Common type definitions and constants
! ==============================================================================
module shell_types
  use iso_c_binding, only: c_int
  implicit none

  ! Process ID type (using c_int since c_pid_t may not be available)
  integer, parameter :: c_pid_t = c_int

  integer, parameter :: MAX_PATH_LEN = 4096
  integer, parameter :: MAX_TOKEN_LEN = 256
  integer, parameter :: MAX_TOKENS = 100
  integer, parameter :: MAX_ENV_LEN = 32768
  integer, parameter :: MAX_PIPELINE = 10
  integer, parameter :: MAX_JOBS = 100
  integer, parameter :: MAX_HEREDOC_LEN = 65536
  integer, parameter :: MAX_CONTROL_DEPTH = 20

  ! Command separator types
  integer, parameter :: SEP_NONE = 0
  integer, parameter :: SEP_SEMICOLON = 1    ! ;
  integer, parameter :: SEP_AND = 2          ! &&
  integer, parameter :: SEP_OR = 3           ! ||
  integer, parameter :: SEP_PIPE = 4         ! |
  integer, parameter :: SEP_BACKGROUND = 5   ! &

  ! Job states
  integer, parameter :: JOB_RUNNING = 1
  integer, parameter :: JOB_STOPPED = 2
  integer, parameter :: JOB_DONE = 3

  ! Control flow block types
  integer, parameter :: BLOCK_IF = 1
  integer, parameter :: BLOCK_WHILE = 2
  integer, parameter :: BLOCK_FOR = 3
  integer, parameter :: BLOCK_FUNCTION = 4

  type :: command_t
    character(len=:), allocatable :: tokens(:)
    integer :: num_tokens = 0
    character(len=:), allocatable :: input_file
    character(len=:), allocatable :: output_file
    character(len=:), allocatable :: error_file
    character(len=:), allocatable :: heredoc_delimiter
    character(len=:), allocatable :: heredoc_content
    logical :: append_output = .false.
    logical :: append_error = .false.
    logical :: redirect_stderr_to_stdout = .false.
    logical :: redirect_stdout_to_stderr = .false.
    logical :: redirect_both_to_file = .false.  ! &> redirection
    character(len=:), allocatable :: here_string  ! <<< redirection
    logical :: background = .false.
    integer :: separator = SEP_NONE
  end type command_t

  type :: pipeline_t
    type(command_t), allocatable :: commands(:)
    integer :: num_commands = 0
  end type pipeline_t

  type :: job_t
    integer :: job_id = 0
    integer(c_pid_t) :: pgid = 0
    integer(c_pid_t), allocatable :: pids(:)
    integer :: num_pids = 0
    character(len=256) :: command_line
    integer :: state = JOB_RUNNING
    logical :: notified = .false.
    logical :: foreground = .true.
  end type job_t

  ! Simple shell variable entry
  type :: shell_var_t
    character(len=256) :: name
    character(len=1024) :: value
  end type shell_var_t

  ! Shell alias entry
  type :: shell_alias_t
    character(len=256) :: name
    character(len=1024) :: command
  end type shell_alias_t

  ! Control flow block state
  type :: control_block_t
    integer :: block_type = 0        ! BLOCK_IF, BLOCK_WHILE, BLOCK_FOR, BLOCK_FUNCTION
    logical :: condition_met = .false.
    logical :: in_else_branch = .false.
    logical :: should_execute = .true.
    character(len=256) :: loop_variable = ''  ! for 'for' loops
    character(len=256) :: for_list = ''       ! space-separated list for 'for' loops
    character(len=256), allocatable :: for_values(:)  ! parsed for-loop values
    integer :: for_index = 0         ! current index in for loop
    integer :: for_count = 0         ! total count of for loop values
    character(len=256) :: condition_cmd = ''  ! while condition command
    integer :: loop_start_line = 0   ! for loop replay
  end type control_block_t

  ! Shell function definition
  type :: shell_function_t
    character(len=256) :: name
    character(len=1024), allocatable :: body(:)  ! function body lines
    integer :: body_lines = 0
    character(len=256) :: params(10)  ! parameter names
    integer :: param_count = 0
  end type shell_function_t

  type :: shell_state_t
    character(len=256) :: username
    character(len=256) :: hostname
    character(len=MAX_PATH_LEN) :: cwd
    integer :: last_exit_status = 0
    integer(c_pid_t) :: last_pid = 0
    integer(c_pid_t) :: shell_pgid = 0
    integer :: shell_terminal = 0
    logical :: is_interactive = .false.
    logical :: running = .true.
    type(job_t) :: jobs(MAX_JOBS)
    integer :: num_jobs = 0
    integer :: next_job_id = 1
    ! Shell variables (local scope)
    type(shell_var_t) :: variables(50)
    integer :: num_variables = 0
    ! Shell aliases
    type(shell_alias_t) :: aliases(50)
    integer :: num_aliases = 0
    ! Shell functions
    type(shell_function_t) :: functions(20)
    integer :: num_functions = 0
    ! Control flow state
    type(control_block_t) :: control_stack(MAX_CONTROL_DEPTH)
    integer :: control_depth = 0
    ! Function call stack for local variables
    type(shell_var_t) :: local_vars(MAX_CONTROL_DEPTH, 20)  ! stack of local variable scopes
    integer :: local_var_counts(MAX_CONTROL_DEPTH) = 0
    ! Script sourcing state
    character(len=MAX_PATH_LEN) :: source_file = ''
    logical :: should_source = .false.
  end type shell_state_t

end module shell_types