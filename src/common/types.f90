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
  end type shell_state_t

end module shell_types