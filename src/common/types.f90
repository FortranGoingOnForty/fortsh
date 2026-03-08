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
  integer, parameter :: MAX_TOKEN_LEN = 4096  ! Increased from 1024 to handle command substitution output
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
  integer, parameter :: BLOCK_UNTIL = 6
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
  integer, parameter :: REDIR_READWRITE = 10  ! <> file (open for read/write)
  integer, parameter :: REDIR_HERE_STRING = 11  ! <<< string (here-string)

  type :: redirection_t
    integer :: type = 0           ! REDIR_* constant
    integer :: fd = -1            ! file descriptor number (-1 for default)
    integer :: target_fd = -1     ! target fd for duplication
    character(len=:), allocatable :: filename
    character(len=:), allocatable :: target_fd_expr  ! for variable FD like >&${var}
    logical :: close_fd = .false. ! for n>&- syntax
    logical :: force_clobber = .false. ! for >| operator (override noclobber)
  end type redirection_t

  ! =====================================
  ! Pending heredoc entry for -c flag processing
  ! =====================================
  integer, parameter :: MAX_PENDING_HEREDOCS = 10

  type :: pending_heredoc_entry_t
    character(len=4096) :: content = ''
    character(len=256) :: delimiter = ''
    logical :: quoted = .false.
    logical :: strip_tabs = .false.
  end type pending_heredoc_entry_t

  ! =====================================
  ! Token types for new grammar-aware parser
  ! =====================================
  integer, parameter :: TOKEN_WORD = 1
  integer, parameter :: TOKEN_KEYWORD = 2
  integer, parameter :: TOKEN_OPERATOR = 3
  integer, parameter :: TOKEN_REDIRECT = 4
  integer, parameter :: TOKEN_ASSIGN = 5
  integer, parameter :: TOKEN_EOF = 6
  integer, parameter :: TOKEN_NEWLINE = 7

  ! =====================================
  ! Quote types for tracking quote style
  ! =====================================
  integer, parameter :: QUOTE_NONE = 0     ! No quotes
  integer, parameter :: QUOTE_SINGLE = 1   ! Single quotes 'text' - no expansion
  integer, parameter :: QUOTE_DOUBLE = 2   ! Double quotes "text" - allows expansion

  type :: token_t
    integer :: token_type           ! TOKEN_* constant
    character(len=MAX_TOKEN_LEN) :: value
    integer :: value_length = 0     ! Actual content length (excludes fixed-length padding)
    integer :: start_pos
    integer :: end_pos
    integer :: line = 1             ! Line number (for LINENO tracking)
    logical :: quoted               ! DEPRECATED - use quote_type instead
    logical :: escaped              ! Token had backslash escape (don't glob expand)
    integer :: quote_type = QUOTE_NONE  ! QUOTE_* constant - tracks quote style
  end type token_t

  ! =====================================
  ! Command node types for grammar parser
  ! =====================================
  integer, parameter :: CMD_SIMPLE = 1
  integer, parameter :: CMD_PIPELINE = 2
  integer, parameter :: CMD_LIST = 3
  integer, parameter :: CMD_FOR_LOOP = 4
  integer, parameter :: CMD_WHILE_LOOP = 5
  integer, parameter :: CMD_UNTIL_LOOP = 6
  integer, parameter :: CMD_IF_STATEMENT = 7
  integer, parameter :: CMD_CASE_STATEMENT = 8
  integer, parameter :: CMD_SUBSHELL = 9
  integer, parameter :: CMD_BRACE_GROUP = 10
  integer, parameter :: CMD_FUNCTION_DEF = 11

  type :: command_t
    character(len=:), allocatable :: tokens(:)
    integer :: num_tokens = 0
    ! Token metadata arrays - track per-token properties from lexer
    integer, allocatable :: token_lengths(:)  ! Actual length of each token (for trailing space preservation)
    logical, allocatable :: token_quoted(:)   ! Was token quoted? (prevents field splitting)
    logical, allocatable :: token_escaped(:)  ! Was token escaped? (prevents glob expansion)
    integer, allocatable :: token_quote_type(:)  ! Quote type for each token (QUOTE_* constant)
    character(len=:), allocatable :: input_file
    character(len=:), allocatable :: output_file
    character(len=:), allocatable :: error_file
    character(len=:), allocatable :: heredoc_delimiter
    character(len=:), allocatable :: heredoc_content
    logical :: heredoc_quoted = .false.  ! delimiter was quoted (suppress variable expansion)
    logical :: heredoc_strip_tabs = .false.  ! <<- operator (strip leading tabs)
    logical :: append_output = .false.
    logical :: append_error = .false.
    logical :: force_clobber = .false.  ! >| operator (override noclobber)
    logical :: redirect_stderr_to_stdout = .false.
    logical :: redirect_stdout_to_stderr = .false.
    logical :: redirect_both_to_file = .false.  ! &> redirection
    character(len=:), allocatable :: here_string  ! <<< redirection
    logical :: background = .false.
    integer :: separator = SEP_NONE
    ! Command grouping support
    logical :: is_command_group = .false.        ! { cmd1; cmd2; }
    character(len=:), allocatable :: group_content  ! content between { }
    ! Subshell grouping support
    logical :: is_subshell = .false.             ! ( cmd1; cmd2 )
    character(len=:), allocatable :: subshell_content  ! content between ( )
    ! Enhanced POSIX file descriptor redirection
    type(redirection_t) :: redirections(10)
    integer :: num_redirections = 0
    ! Prefix assignments (VAR=value command)
    character(len=256) :: prefix_assignments(10) = ''  ! VAR=value pairs
    integer :: num_prefix_assignments = 0
    ! Skip expansion flag (words already expanded in pipeline)
    logical :: skip_expansion = .false.
  end type command_t

  type :: pipeline_t
    type(command_t), allocatable :: commands(:)
    integer :: num_commands = 0
    logical :: parse_error = .false.  ! Set when a syntax error occurs during parsing
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
    integer :: value_len = 0           ! Actual length of value (preserves trailing spaces)
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
    character(len=1024) :: condition_cmd = ''  ! while condition command (must match control_flow usage)
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
    logical :: inherited = .false.  ! Trap inherited from parent (visible but not executed)
  end type shell_trap_t

  ! Command hash table entry (for 'hash' builtin)
  type :: command_hash_entry_t
    character(len=256) :: command_name = ''
    character(len=MAX_PATH_LEN) :: full_path = ''
    integer :: hits = 0
  end type command_hash_entry_t

  ! Process substitution FIFO tracking
  type :: proc_subst_fifo_t
    character(len=MAX_PATH_LEN) :: fifo_path = ''
    integer(c_pid_t) :: pid = 0
    logical :: active = .false.
    logical :: is_input = .false.  ! True for <(), False for >()
  end type proc_subst_fifo_t

  type :: shell_state_t
    character(len=256) :: username
    character(len=256) :: hostname
    character(len=MAX_PATH_LEN) :: cwd
    integer :: last_exit_status = 0
    integer(c_pid_t) :: last_pid = 0
    integer(c_pid_t) :: shell_pgid = 0
    integer :: shell_terminal = 0
    ! Terminal dimensions (updated on SIGWINCH)
    integer :: term_rows = 24
    integer :: term_cols = 80
    logical :: term_supports_color = .true.  ! Terminal supports ANSI escape codes
    logical :: is_interactive = .false.
    logical :: in_command_mode = .false.  ! Running with -c flag
    logical :: in_background = .false.
    logical :: running = .true.
    logical :: fatal_expansion_error = .false.  ! Set by ${VAR?error} to abort execution
    logical :: arithmetic_error = .false.        ! Set when arithmetic expansion fails
    character(len=256) :: arithmetic_error_msg = ''  ! Error message from arithmetic expansion
    type(job_t) :: jobs(MAX_JOBS)
    integer :: num_jobs = 0
    integer :: next_job_id = 1
    integer :: current_job_id = 0   ! %% or %+ (most recent job)
    integer :: previous_job_id = 0  ! %- (previous job)
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
    ! Pending trap execution (to avoid circular dependency in signal_handling)
    character(len=1024) :: pending_trap_command = ''
    integer :: pending_trap_signal = 0
    logical :: executing_trap = .false.  ! Prevent recursive trap execution
    logical :: exit_trap_executed = .false.  ! Track if EXIT trap has been executed
    logical :: evaluating_condition = .false.  ! Suppress errexit during if/while/until condition evaluation
    logical :: in_and_or_list = .false.       ! Suppress errexit in && and || lists
    logical :: in_negation = .false.          ! Suppress errexit for negated pipelines (!)
    logical :: in_command_substitution = .false.  ! Suppress errexit in command substitution
    logical :: in_capture_child = .false.     ! In forked child for output capture (suppress messages)
    logical :: last_from_and_or = .false.     ! Last result was from an AND-OR list (suppress errexit check)
    ! Command hash table
    type(command_hash_entry_t) :: command_hash(50)
    integer :: num_hashed_commands = 0
    ! Control flow state
    type(control_block_t) :: control_stack(MAX_CONTROL_DEPTH)
    integer :: control_depth = 0
    logical :: case_pattern_skip_first_token = .false.  ! Skip first token in case pattern execution
    ! Function call stack for local variables (allocatable to avoid large stack allocation)
    type(shell_var_t), allocatable :: local_vars(:,:)  ! stack of local variable scopes
    integer, allocatable :: local_var_counts(:)
    ! Script sourcing state
    character(len=MAX_PATH_LEN) :: source_file = ''
    logical :: should_source = .false.
    ! Shell options (POSIX compliance)
    logical :: option_errexit = .false.        ! set -e (exit on error)
    logical :: option_nounset = .false.        ! set -u (error on undefined variables)
    logical :: option_pipefail = .false.       ! set -o pipefail
    logical :: option_verbose = .false.        ! set -v (verbose)
    logical :: option_xtrace = .false.         ! set -x (trace execution)
    ! Parser selection (experimental feature)
    logical :: use_new_parser = .false.        ! Use grammar-aware parser (FORTSH_USE_NEW_PARSER=1)
    logical :: option_noclobber = .false.      ! set -C (no clobber)
    logical :: option_monitor = .false.        ! set -m (job control)
    logical :: option_allexport = .false.      ! set -a (auto export)
    logical :: option_noglob = .false.         ! set -f (disable glob expansion)
    logical :: option_vi = .false.             ! set -o vi (vi editing mode)
    ! Additional POSIX/bash shell options (stubs for compatibility)
    logical :: option_braceexpand = .true.     ! set -o braceexpand (enabled by default)
    logical :: option_emacs = .true.           ! set -o emacs (default editing mode)
    logical :: option_errtrace = .false.       ! set -o errtrace (ERR trap inheritance)
    logical :: option_functrace = .false.      ! set -o functrace (DEBUG/RETURN trap inheritance)
    logical :: option_hashall = .true.         ! set -o hashall (hash commands, on by default)
    logical :: option_histexpand = .false.     ! set -o histexpand (! history expansion)
    logical :: option_history = .false.        ! set -o history (command history)
    logical :: option_ignoreeof = .false.      ! set -o ignoreeof (don't exit on Ctrl-D)
    logical :: option_interactive_comments = .true.  ! set -o interactive-comments (on by default)
    logical :: option_keyword = .false.        ! set -o keyword (recognize keywords anywhere)
    logical :: option_noexec = .false.         ! set -o noexec (read but don't execute)
    logical :: option_nolog = .false.          ! set -o nolog (don't log to history)
    logical :: option_notify = .false.         ! set -o notify (immediate job status)
    logical :: option_onecmd = .false.         ! set -o onecmd (exit after one command)
    logical :: option_physical = .false.       ! set -o physical (resolve symlinks in cd)
    logical :: option_posix = .false.          ! set -o posix (POSIX mode)
    logical :: option_privileged = .false.     ! set -o privileged (restricted mode)
    integer :: original_stderr_fd = 2          ! Saved copy of original stderr for shell messages
    ! Bash-style shell options (shopt)
    logical :: shopt_nullglob = .false.        ! nullglob (empty glob matches)
    logical :: shopt_failglob = .false.        ! failglob (error on no glob matches)
    logical :: shopt_globstar = .false.        ! globstar (** recursive)
    logical :: shopt_nocaseglob = .false.      ! nocaseglob (case insensitive)
    logical :: shopt_nocasematch = .false.     ! nocasematch (case insensitive regex)
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
    character(len=1024) :: ps1 = '%F{green}\u@\h%f :: %F{blue}\w%f\n> ' ! 2-line prompt with zsh colors
    integer :: ps1_len = 0                     ! Actual length of PS1 (preserves trailing spaces)
    character(len=256) :: ps2 = '> '              ! Continuation prompt
    integer :: ps2_len = 0                     ! Actual length of PS2
    character(len=256) :: ps3 = '#? '             ! Select prompt
    integer :: ps3_len = 0                     ! Actual length of PS3
    character(len=256) :: ps4 = '+ '              ! Trace prompt (set -x)
    integer :: ps4_len = 0                     ! Actual length of PS4
    integer :: command_number = 0              ! For \# in prompts
    ! Positional parameters (allocatable to avoid large stack allocation on macOS)
    character(len=1024), allocatable :: positional_params(:) ! $1, $2, ..., $n
    integer :: num_positional = 0             ! $# (number of positional parameters)
    integer :: positional_params_capacity = 0 ! Allocated size of positional_params
    ! Field splitting
    character(len=256) :: ifs = ' \t\n'       ! $IFS (internal field separator)
    integer :: ifs_len = -1                   ! -1 = unset (use default), 0 = empty, >0 = set
    ! History control
    character(len=MAX_PATH_LEN) :: histfile = ''  ! $HISTFILE (history file path)
    integer :: histsize = 1000                ! $HISTSIZE (max commands in memory)
    integer :: histfilesize = 2000            ! $HISTFILESIZE (max lines in file)
    character(len=256) :: histcontrol = ''    ! $HISTCONTROL (ignorespace:ignoredups:erasedups)
    ! Function execution control
    logical :: function_return_pending = .false.  ! Set by 'return' builtin to exit function
    integer :: function_return_value = 0      ! Return value from 'return' builtin
    integer :: function_depth = 0             ! Current function call depth (for local vars)
    integer :: source_depth = 0               ! Current sourced script depth (for return)
    logical :: bypass_functions = .false.     ! Set by 'command' builtin to skip function lookup
    logical :: bypass_aliases = .false.       ! Set by 'command' builtin to skip alias expansion
    ! Process substitution
    type(proc_subst_fifo_t) :: proc_subst_fifos(10)
    integer :: num_proc_subst_fifos = 0
    ! Directory history (Fish-style prevd/nextd)
    character(len=MAX_PATH_LEN) :: dir_history(50)  ! Circular buffer of directories
    integer :: dir_history_size = 0                  ! Number of directories in history
    integer :: dir_history_index = 0                 ! Current position in history

    ! Pending heredocs for -c flag processing (array for multiple heredocs on same line)
    type(pending_heredoc_entry_t) :: pending_heredocs(MAX_PENDING_HEREDOCS)
    integer :: num_pending_heredocs = 0
    integer :: next_pending_heredoc = 1  ! Index of next heredoc to consume

    ! Legacy single heredoc support (for backward compatibility during transition)
    character(len=4096) :: pending_heredoc = ''
    character(len=256) :: pending_heredoc_delimiter = ''
    logical :: pending_heredoc_quoted = .false.
    logical :: pending_heredoc_strip_tabs = .false.
    logical :: has_pending_heredoc = .false.

    ! Current command being executed (for job descriptions)
    character(len=1024) :: current_command = ''
  end type shell_state_t

end module shell_types