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
  integer, parameter :: BLOCK_FOR_ARITH = 5

  ! File descriptor redirection types
  integer, parameter :: REDIR_IN = 1      ! < file
  integer, parameter :: REDIR_OUT = 2     ! > file
  integer, parameter :: REDIR_APPEND = 3  ! >> file
  integer, parameter :: REDIR_FD_IN = 4   ! n< file
  integer, parameter :: REDIR_FD_OUT = 5  ! n> file
  integer, parameter :: REDIR_FD_APPEND = 6  ! n>> file
  integer, parameter :: REDIR_DUP_IN = 7  ! <&n
  integer, parameter :: REDIR_DUP_OUT = 8 ! >&n
  integer, parameter :: REDIR_CLOSE = 9   ! n>&-

  type :: redirection_t
    integer :: type = 0           ! REDIR_* constant
    integer :: fd = -1            ! file descriptor number (-1 for default)
    integer :: target_fd = -1     ! target fd for duplication
    character(len=:), allocatable :: filename
    logical :: close_fd = .false. ! for n>&- syntax
  end type redirection_t

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
    ! Enhanced POSIX file descriptor redirection
    type(redirection_t) :: redirections(10)
    integer :: num_redirections = 0
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

  ! Associative array entry
  type :: assoc_array_entry_t
    character(len=256) :: key
    character(len=1024) :: value
  end type assoc_array_entry_t

  ! Simple shell variable entry
  type :: shell_var_t
    character(len=256) :: name
    character(len=1024) :: value
    logical :: is_array = .false.
    logical :: is_assoc_array = .false.
    logical :: readonly = .false.      ! Variable is read-only
    logical :: exported = .false.      ! Variable is exported to environment
    character(len=1024), allocatable :: array_values(:)
    integer :: array_size = 0
    type(assoc_array_entry_t), allocatable :: assoc_entries(:)
    integer :: assoc_size = 0
  end type shell_var_t

  ! Shell alias entry
  type :: shell_alias_t
    character(len=256) :: name
    character(len=1024) :: command
  end type shell_alias_t

  ! Control flow block state
  type :: control_block_t
    integer :: block_type = 0        ! BLOCK_IF, BLOCK_WHILE, BLOCK_FOR, BLOCK_FUNCTION, BLOCK_FOR_ARITH
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
    ! Loop body buffering for proper iteration
    character(len=1024), allocatable :: loop_body(:)  ! commands in loop body
    integer :: loop_body_count = 0   ! number of commands in loop body
    logical :: capturing_loop_body = .false.  ! currently capturing commands
    integer :: capture_nesting_depth = 0  ! track nested loops during capture
    ! Arithmetic for loop fields (for (( init; cond; incr )) )
    character(len=256) :: arith_init = ''      ! initialization expression
    character(len=256) :: arith_condition = '' ! condition expression
    character(len=256) :: arith_increment = '' ! increment expression
    logical :: arith_first_iteration = .true.  ! track if init has been executed
    ! Case statement fields
    logical :: case_found_match = .false.  ! whether any case pattern has matched
    logical :: case_in_match = .false.     ! whether we're currently in a matched pattern's commands
    ! Loop control (break/continue)
    logical :: break_requested = .false.   ! 'break' was called
    logical :: continue_requested = .false. ! 'continue' was called
    integer :: break_level = 0             ! how many levels to break (break n)
    integer :: continue_level = 0          ! how many levels to continue (continue n)
  end type control_block_t

  ! Shell function definition
  type :: shell_function_t
    character(len=256) :: name
    character(len=1024), allocatable :: body(:)  ! function body lines
    integer :: body_lines = 0
    character(len=256) :: params(10)  ! parameter names
    integer :: param_count = 0
  end type shell_function_t

  ! Shell trap definition
  type :: shell_trap_t
    integer :: signal = 0
    character(len=1024) :: command = ''
    logical :: active = .false.
  end type shell_trap_t

  ! Command hash table entry (for 'hash' builtin)
  type :: command_hash_entry_t
    character(len=256) :: command_name = ''
    character(len=MAX_PATH_LEN) :: full_path = ''
    integer :: hits = 0
  end type command_hash_entry_t

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
    ! Shell traps
    type(shell_trap_t) :: traps(20)
    integer :: num_traps = 0
    ! Command hash table
    type(command_hash_entry_t) :: command_hash(50)
    integer :: num_hashed_commands = 0
    ! Control flow state
    type(control_block_t) :: control_stack(MAX_CONTROL_DEPTH)
    integer :: control_depth = 0
    ! Function call stack for local variables
    type(shell_var_t) :: local_vars(MAX_CONTROL_DEPTH, 20)  ! stack of local variable scopes
    integer :: local_var_counts(MAX_CONTROL_DEPTH) = 0
    ! Script sourcing state
    character(len=MAX_PATH_LEN) :: source_file = ''
    logical :: should_source = .false.
    ! Shell options (POSIX compliance)
    logical :: option_errexit = .false.        ! set -e (exit on error)
    logical :: option_nounset = .false.        ! set -u (error on undefined variables)
    logical :: option_pipefail = .false.       ! set -o pipefail
    logical :: option_verbose = .false.        ! set -v (verbose)
    logical :: option_xtrace = .false.         ! set -x (trace execution)
    logical :: option_noclobber = .false.      ! set -C (no clobber)
    logical :: option_monitor = .false.        ! set -m (job control)
    logical :: option_allexport = .false.      ! set -a (auto export)
    ! Bash-style shell options (shopt)
    logical :: shopt_nullglob = .false.        ! nullglob (empty glob matches)
    logical :: shopt_failglob = .false.        ! failglob (error on no glob matches) 
    logical :: shopt_globstar = .false.        ! globstar (** recursive)
    logical :: shopt_nocaseglob = .false.      ! nocaseglob (case insensitive)
    logical :: shopt_extglob = .false.         ! extglob (extended patterns)
    logical :: shopt_dotglob = .false.         ! dotglob (include hidden files)
    ! Special process variables
    integer(c_pid_t) :: shell_pid = 0          ! $$ (shell process ID)
    integer(c_pid_t) :: last_bg_pid = 0        ! $! (last background process)
    character(len=256) :: shell_name = 'fortsh' ! $0 (shell name)
    integer(c_pid_t) :: parent_pid = 0         ! $PPID (parent process ID)
    character(len=1024) :: last_arg = ''       ! $_ (last argument of previous command)
    integer :: uid = 0                         ! $UID (user ID)
    integer :: euid = 0                        ! $EUID (effective user ID)
    integer :: shell_start_time = 0            ! For $SECONDS
    integer :: current_line_number = 0         ! $LINENO (current line in script)
    character(len=MAX_PATH_LEN) :: oldpwd = '' ! $OLDPWD (previous working directory)
    logical :: is_login_shell = .false.        ! Started as login shell
    ! Prompt strings
    character(len=1024) :: ps1 = '\u@\h :: \w\$ ' ! Primary prompt (fortsh style!)
    character(len=256) :: ps2 = '> '              ! Continuation prompt
    character(len=256) :: ps3 = '#? '             ! Select prompt
    character(len=256) :: ps4 = '+ '              ! Trace prompt (set -x)
    integer :: command_number = 0              ! For \# in prompts
    ! Positional parameters
    character(len=1024) :: positional_params(50) ! $1, $2, ..., $n
    integer :: num_positional = 0             ! $# (number of positional parameters)
    ! Field splitting
    character(len=256) :: ifs = ' \t\n'       ! $IFS (internal field separator)
    ! History control
    character(len=MAX_PATH_LEN) :: histfile = ''  ! $HISTFILE (history file path)
    integer :: histsize = 1000                ! $HISTSIZE (max commands in memory)
    integer :: histfilesize = 2000            ! $HISTFILESIZE (max lines in file)
    character(len=256) :: histcontrol = ''    ! $HISTCONTROL (ignorespace:ignoredups:erasedups)
    ! Function execution control
    logical :: function_return_pending = .false.  ! Set by 'return' builtin to exit function
    integer :: function_return_value = 0      ! Return value from 'return' builtin
    integer :: function_depth = 0             ! Current function call depth (for local vars)
  end type shell_state_t

end module shell_types