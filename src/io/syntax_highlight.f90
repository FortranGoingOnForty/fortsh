! ==============================================================================
! Module: syntax_highlight
! Purpose: Real-time syntax highlighting for interactive command line
! ==============================================================================
module syntax_highlight
  use iso_fortran_env, only: error_unit
  use system_interface, only: c_access, X_OK
#ifdef USE_MEMORY_POOL
  use string_pool
#endif
  implicit none
  private

  ! Public interface
  public :: highlight_command_line
  public :: highlight_single_char
  public :: is_valid_command
  public :: init_syntax_highlighting
  public :: clear_command_cache
  public :: MAX_HIGHLIGHT_LEN  ! Export buffer size for callers
  public :: cleanup_syntax_highlighting
  ! v2 API — exposed for unit testing
  public :: hl_token_t, tokenize_v2, hl_token_color

  ! ANSI color codes
  integer, parameter :: COLOR_RESET = 0
  integer, parameter :: COLOR_BLACK = 30
  integer, parameter :: COLOR_RED = 31
  integer, parameter :: COLOR_GREEN = 32
  integer, parameter :: COLOR_YELLOW = 33
  integer, parameter :: COLOR_BLUE = 34
  integer, parameter :: COLOR_MAGENTA = 35
  integer, parameter :: COLOR_CYAN = 36
  integer, parameter :: COLOR_WHITE = 37
  integer, parameter :: COLOR_BRIGHT_BLACK = 90
  integer, parameter :: COLOR_BRIGHT_RED = 91
  integer, parameter :: COLOR_BRIGHT_GREEN = 92
  integer, parameter :: COLOR_BRIGHT_YELLOW = 93
  integer, parameter :: COLOR_BRIGHT_BLUE = 94
  integer, parameter :: COLOR_BRIGHT_MAGENTA = 95
  integer, parameter :: COLOR_BRIGHT_CYAN = 96
  integer, parameter :: COLOR_BRIGHT_WHITE = 97

  ! Highlight token types — position-based, context-aware
  integer, parameter, public :: HTOK_COMMAND_VALID   = 1
  integer, parameter, public :: HTOK_COMMAND_INVALID = 2
  integer, parameter, public :: HTOK_KEYWORD         = 3
  integer, parameter, public :: HTOK_BUILTIN         = 4
  integer, parameter, public :: HTOK_OPTION          = 5
  integer, parameter, public :: HTOK_STRING_SINGLE   = 6
  integer, parameter, public :: HTOK_STRING_DOUBLE   = 7
  integer, parameter, public :: HTOK_VARIABLE        = 8
  integer, parameter, public :: HTOK_COMMENT         = 9
  integer, parameter, public :: HTOK_OPERATOR        = 10
  integer, parameter, public :: HTOK_REDIRECT        = 11
  integer, parameter, public :: HTOK_NUMBER          = 12
  integer, parameter, public :: HTOK_PATH            = 13
  integer, parameter, public :: HTOK_GLOB            = 14
  integer, parameter, public :: HTOK_ASSIGNMENT      = 15
  integer, parameter, public :: HTOK_DEFAULT         = 16

  ! v2 token structure — references positions in input buffer, no string copying
  type, public :: hl_token_t
    integer :: start_pos = 0
    integer :: end_pos = 0
    integer :: token_type = HTOK_DEFAULT
  end type hl_token_t

  ! Color scheme for different token types
  integer, parameter :: COLOR_COMMAND_VALID = COLOR_GREEN
  integer, parameter :: COLOR_COMMAND_INVALID = COLOR_RED
  integer, parameter :: COLOR_KEYWORD = COLOR_BRIGHT_MAGENTA
  integer, parameter :: COLOR_OPTION = COLOR_BLUE
  integer, parameter :: COLOR_STRING = COLOR_YELLOW
  integer, parameter :: COLOR_VARIABLE = COLOR_MAGENTA
  integer, parameter :: COLOR_COMMENT = COLOR_BRIGHT_BLACK
  integer, parameter :: COLOR_OPERATOR = COLOR_CYAN
  integer, parameter :: COLOR_NUMBER = COLOR_CYAN
  integer, parameter :: COLOR_PATH = COLOR_BRIGHT_BLUE
  integer, parameter :: COLOR_GLOB = COLOR_BRIGHT_CYAN
  integer, parameter :: COLOR_ASSIGNMENT = COLOR_BRIGHT_WHITE

  ! Fixed-length parameters to avoid heap corruption with LLVM Flang
  integer, parameter :: MAX_COMMAND_LEN = 256
  integer, parameter :: MAX_HIGHLIGHT_LEN = 4096
  integer, parameter :: MAX_TOKEN_LEN = 256
  integer, parameter :: MAX_TOKENS = 100
  integer, parameter :: MAX_PATH_LEN = 4096

  ! Command validation cache
  type :: cache_entry_t
    character(len=MAX_COMMAND_LEN) :: command = ''
    logical :: is_valid = .false.
    integer :: timestamp = 0
  end type cache_entry_t

  integer, parameter :: CACHE_SIZE = 256
  type(cache_entry_t), save :: command_cache(CACHE_SIZE)
  integer, save :: cache_count = 0
  integer, save :: current_timestamp = 0

  ! Configuration
  logical, save :: highlighting_enabled = .true.
  logical, save :: cache_enabled = .true.

contains

  ! Initialize syntax highlighting system
  subroutine init_syntax_highlighting()
    character(len=256) :: term_type
    integer :: status

    ! Clear cache
    call clear_command_cache()

#ifdef USE_MEMORY_POOL
    ! Initialize string pool if using memory pooling
    call pool_init()
#endif

    ! Check for test mode FIRST - disable highlighting if in test mode
    call get_environment_variable('FORTSH_TEST_MODE', term_type, status=status)
    if (status == 0 .and. trim(term_type) == '1') then
      highlighting_enabled = .false.
      return
    end if

    ! Check if terminal supports colors based on TERM environment variable
    call get_environment_variable('TERM', term_type, status=status)

    if (status /= 0 .or. len_trim(term_type) == 0) then
      ! No TERM set - disable highlighting
      highlighting_enabled = .false.
      return
    end if

    ! Known dumb/non-ANSI terminals - disable highlighting
    select case (trim(term_type))
    case ('dumb', 'unknown', 'cons25')
      highlighting_enabled = .false.
    case default
      highlighting_enabled = .true.
    end select
  end subroutine

  ! Cleanup syntax highlighting system
  subroutine cleanup_syntax_highlighting()
#ifdef USE_MEMORY_POOL
    integer :: allocs, deallocs, current, peak
    real :: hit_rate

    ! Get final statistics before cleanup
    call pool_statistics(allocs, deallocs, current, peak, hit_rate)

    ! Only print stats in debug mode
    ! write(error_unit, '(a)') 'String pool statistics:'
    ! write(error_unit, '(a,i0)') '  Total allocations: ', allocs
    ! write(error_unit, '(a,i0)') '  Total deallocations: ', deallocs
    ! write(error_unit, '(a,i0)') '  Peak strings: ', peak
    ! write(error_unit, '(a,f5.1,a)') '  Cache hit rate: ', hit_rate * 100.0, '%'

    ! Clean up the pool
    call pool_cleanup()
#endif

    ! Clear the command cache
    call clear_command_cache()
  end subroutine

  ! Clear command validation cache
  subroutine clear_command_cache()
    integer :: i

    do i = 1, CACHE_SIZE
      command_cache(i)%command = ''
      command_cache(i)%is_valid = .false.
      command_cache(i)%timestamp = 0
    end do
    cache_count = 0
    current_timestamp = 0
  end subroutine

  ! Main function: Highlight a command line
  ! Convert to subroutine to avoid allocatable string returns (flang-new workaround)
  ! Takes input_len to avoid substring temporaries on stack
  subroutine highlight_command_line(input, highlighted, actual_len, input_len)
    character(len=*), intent(in) :: input
    character(len=MAX_HIGHLIGHT_LEN), intent(out) :: highlighted
    integer, intent(out), optional :: actual_len
    integer, intent(in), optional :: input_len  ! Explicit length to avoid substrings

    ! v2 position-based tokens — 12 bytes × MAX_TOKENS = 1.2KB on stack
    type(hl_token_t) :: v2_tokens(MAX_TOKENS)
    integer :: num_tokens
    integer :: len_used
    integer :: actual_input_len

    ! Use provided length if given, otherwise use full buffer length
    if (present(input_len)) then
      actual_input_len = input_len
    else
      actual_input_len = len(input)
    end if

    ! Bounds check - but don't use len(input) on allocatable strings (returns 0 in flang-new!)
    if (actual_input_len < 0) actual_input_len = 0

    if (.not. highlighting_enabled .or. actual_input_len == 0) then
      if (actual_input_len > 0 .and. actual_input_len <= MAX_HIGHLIGHT_LEN) then
        highlighted(1:actual_input_len) = input(1:actual_input_len)
        if (actual_input_len < MAX_HIGHLIGHT_LEN) then
          highlighted(actual_input_len+1:MAX_HIGHLIGHT_LEN) = ' '
        end if
      else
        highlighted = ' '
        actual_input_len = 0
      end if
      len_used = actual_input_len
      if (present(actual_len)) actual_len = len_used
      return
    end if

    ! v2 pipeline: tokenize → render (position-based, no string copying)
    call tokenize_v2(input, actual_input_len, v2_tokens, num_tokens)

    if (num_tokens == 0) then
      if (actual_input_len > 0 .and. actual_input_len <= MAX_HIGHLIGHT_LEN) then
        highlighted(1:actual_input_len) = input(1:actual_input_len)
        if (actual_input_len < MAX_HIGHLIGHT_LEN) then
          highlighted(actual_input_len+1:MAX_HIGHLIGHT_LEN) = ' '
        end if
      else
        highlighted = ' '
        actual_input_len = 0
      end if
      len_used = actual_input_len
      if (present(actual_len)) actual_len = len_used
      return
    end if

    call render_highlighted_v2(input, actual_input_len, v2_tokens, num_tokens, highlighted, len_used)

    if (present(actual_len)) then
      actual_len = len_used
    end if
  end subroutine

  ! Highlight a single character based on context
  ! This is a simplified version for incremental display updates
  function highlight_single_char(ch, buffer) result(highlighted)
    character, intent(in) :: ch
    character(len=*), intent(in) :: buffer
    character(len=32) :: highlighted

    character(len=32) :: colored_char
    integer :: color

    ! Simple heuristics for single character highlighting
    if (ch == '"' .or. ch == "'") then
      color = COLOR_STRING
    else if (ch == '-' .and. (len_trim(buffer) == 0 .or. buffer(len_trim(buffer):len_trim(buffer)) == ' ')) then
      color = COLOR_OPTION
    else if (ch == '#') then
      color = COLOR_COMMENT
    else if (ch == '$') then
      color = COLOR_VARIABLE
    else if (ch == '|' .or. ch == '&' .or. ch == '>' .or. ch == '<' .or. ch == ';') then
      color = COLOR_OPERATOR
    else if (ch >= '0' .and. ch <= '9') then
      color = COLOR_NUMBER
    else
      ! For now, just use reset color for regular chars
      color = COLOR_RESET
    end if

    ! Build the colored character
    if (color /= COLOR_RESET) then
      write(colored_char, '(a,i15,a,a,a)') char(27) // '[', color, 'm', ch, char(27) // '[0m'
      highlighted = trim(colored_char)
    else
      highlighted = ch
    end if
  end function

  ! Check if a command is valid (exists in PATH, is builtin, or is function)
  function is_valid_command(command) result(valid)
    character(len=*), intent(in) :: command
    logical :: valid

    integer :: cache_idx
    character(len=MAX_COMMAND_LEN) :: cmd

    cmd = trim(command)
    valid = .false.

    ! Check cache first
    if (cache_enabled) then
      cache_idx = find_in_cache(cmd)
      if (cache_idx > 0) then
        valid = command_cache(cache_idx)%is_valid
        return
      end if
    end if

    ! Check if it's a builtin command
    if (is_builtin_v2(cmd, len_trim(cmd))) then
      valid = .true.
      call add_to_cache(cmd, .true.)
      return
    end if

    ! Check if command exists in PATH
    if (command_exists_in_path(cmd)) then
      valid = .true.
      call add_to_cache(cmd, .true.)
      return
    end if

    ! Not found
    call add_to_cache(cmd, .false.)
  end function

  ! Check if command exists in PATH
  function command_exists_in_path(command) result(exists)
    use system_interface, only: file_is_executable, get_environment_var
    character(len=*), intent(in) :: command
    logical :: exists

    ! Use allocatable to avoid 9KB stack allocation
    character(len=:), allocatable :: path_env, full_path, dir
    integer :: path_start, path_end, colon_pos

    exists = .false.

    ! Get PATH environment variable using system_interface (not intrinsic!)
    path_env = get_environment_var('PATH')
    if (len_trim(path_env) == 0) then
      return
    end if

    ! Allocate buffers on heap (not using pool - too complex for mixed allocation)
    allocate(character(len=MAX_PATH_LEN) :: full_path)
    allocate(character(len=1024) :: dir)

    ! Search each directory in PATH
    path_start = 1
    do while (path_start <= len_trim(path_env))
      ! Find next colon
      colon_pos = index(path_env(path_start:), ':')
      if (colon_pos > 0) then
        path_end = path_start + colon_pos - 2
      else
        path_end = len_trim(path_env)
      end if

      ! Extract directory
      dir = path_env(path_start:path_end)

      ! Check if command exists in this directory
      full_path = trim(dir) // '/' // trim(command)
      if (file_is_executable(full_path)) then
        exists = .true.
        return
      end if

      ! Move to next directory
      if (colon_pos > 0) then
        path_start = path_start + colon_pos
      else
        exit
      end if
    end do

    ! Deallocate heap-allocated buffers
    if (allocated(path_env)) deallocate(path_env)
    if (allocated(full_path)) deallocate(full_path)
    if (allocated(dir)) deallocate(dir)
  end function

  ! Check if a path is a navigable directory (for cd-on-path-entry highlighting)
  function is_navigable_path(path) result(is_nav)
    use system_interface, only: file_is_directory, get_environment_var
    character(len=*), intent(in) :: path
    logical :: is_nav
    character(len=:), allocatable :: expanded, home_dir

    is_nav = .false.
    if (len_trim(path) == 0) return

    ! Expand tilde
    if (path(1:1) == '~') then
      home_dir = get_environment_var('HOME')
      if (allocated(home_dir) .and. len(home_dir) > 0) then
        if (len_trim(path) == 1) then
          expanded = home_dir
        else
          expanded = trim(home_dir) // path(2:len_trim(path))
        end if
      else
        return
      end if
    else
      expanded = trim(path)
    end if

    is_nav = file_is_directory(expanded)
  end function is_navigable_path

  ! Check if a path containing / points to an executable file
  function is_path_executable(path) result(is_exec)
    use system_interface, only: file_is_executable
    character(len=*), intent(in) :: path
    logical :: is_exec

    is_exec = .false.
    if (len_trim(path) == 0) return
    is_exec = file_is_executable(trim(path))
  end function is_path_executable

  ! Generate ANSI color code
  function color_code(color) result(code)
    integer, intent(in) :: color
    character(len=32) :: code

    if (color == COLOR_RESET) then
      code = char(27) // '[0m'
    else
      write(code, '(a,i0,a)') char(27) // '[', color, 'm'
    end if
    code = trim(code)
  end function

  ! Cache management functions
  function find_in_cache(command) result(idx)
    character(len=*), intent(in) :: command
    integer :: idx

    integer :: i

    idx = 0

    do i = 1, min(cache_count, CACHE_SIZE)
      if (len_trim(command_cache(i)%command) > 0) then
        if (trim(command_cache(i)%command) == trim(command)) then
          ! Update timestamp for LRU
          command_cache(i)%timestamp = current_timestamp
          current_timestamp = current_timestamp + 1
          idx = i
          return
        end if
      end if
    end do
  end function

  subroutine add_to_cache(command, is_valid)
    character(len=*), intent(in) :: command
    logical, intent(in) :: is_valid

    integer :: idx, oldest_idx, oldest_time
    integer :: i

    ! Check if already in cache
    idx = find_in_cache(command)
    if (idx > 0) then
      command_cache(idx)%is_valid = is_valid
      return
    end if

    ! Find empty slot or oldest entry
    oldest_idx = 1
    oldest_time = command_cache(1)%timestamp

    do i = 1, CACHE_SIZE
      if (len_trim(command_cache(i)%command) == 0) then
        idx = i
        exit
      end if

      if (command_cache(i)%timestamp < oldest_time) then
        oldest_time = command_cache(i)%timestamp
        oldest_idx = i
      end if
    end do

    ! Use empty slot or evict oldest
    if (idx == 0) idx = oldest_idx

    ! Store in cache
    command_cache(idx)%command = trim(command)
    command_cache(idx)%is_valid = is_valid
    command_cache(idx)%timestamp = current_timestamp
    current_timestamp = current_timestamp + 1

    if (idx > cache_count) cache_count = idx
  end subroutine

  ! ============================================================================
  ! v2 Highlighting Pipeline
  ! Position-based tokenizer with keyword, operator, and context awareness.
  ! ============================================================================

  ! Color lookup for v2 token types
  function hl_token_color(tok_type) result(color)
    integer, intent(in) :: tok_type
    integer :: color
    select case(tok_type)
    case(HTOK_COMMAND_VALID);  color = COLOR_COMMAND_VALID
    case(HTOK_COMMAND_INVALID);color = COLOR_COMMAND_INVALID
    case(HTOK_KEYWORD);        color = COLOR_KEYWORD
    case(HTOK_BUILTIN);        color = COLOR_GREEN
    case(HTOK_OPTION);         color = COLOR_OPTION
    case(HTOK_STRING_SINGLE);  color = COLOR_STRING
    case(HTOK_STRING_DOUBLE);  color = COLOR_STRING
    case(HTOK_VARIABLE);       color = COLOR_VARIABLE
    case(HTOK_COMMENT);        color = COLOR_COMMENT
    case(HTOK_OPERATOR);       color = COLOR_OPERATOR
    case(HTOK_REDIRECT);       color = COLOR_OPERATOR
    case(HTOK_NUMBER);         color = COLOR_NUMBER
    case(HTOK_PATH);           color = COLOR_PATH
    case(HTOK_GLOB);           color = COLOR_GLOB
    case(HTOK_ASSIGNMENT);     color = COLOR_ASSIGNMENT
    case default;              color = COLOR_RESET
    end select
  end function hl_token_color

  ! Check if word is a shell keyword (for highlighting)
  function is_keyword_for_highlight(word, wlen) result(is_kw)
    character(len=*), intent(in) :: word
    integer, intent(in) :: wlen
    logical :: is_kw

    is_kw = .false.
    if (wlen < 1 .or. wlen > 8) return

    select case(word(1:wlen))
    case('if', 'then', 'else', 'elif', 'fi')
      is_kw = .true.
    case('for', 'in', 'do', 'done')
      is_kw = .true.
    case('while', 'until')
      is_kw = .true.
    case('case', 'esac')
      is_kw = .true.
    case('function', 'select', 'time')
      is_kw = .true.
    case('{', '}', '!', '[[', ']]')
      is_kw = .true.
    case default
      is_kw = .false.
    end select
  end function is_keyword_for_highlight

  ! Check if keyword resets command position (followed by a command)
  function keyword_starts_command(word, wlen) result(starts)
    character(len=*), intent(in) :: word
    integer, intent(in) :: wlen
    logical :: starts

    starts = .false.
    if (wlen < 1 .or. wlen > 5) return

    select case(word(1:wlen))
    case('if', 'elif', 'while', 'until', '!')
      starts = .true.
    case('then', 'else', 'do')
      starts = .true.
    case default
      starts = .false.
    end select
  end function keyword_starts_command

  ! Check if word is a shell builtin (synced with builtins.f90)
  function is_builtin_v2(word, wlen) result(is_b)
    character(len=*), intent(in) :: word
    integer, intent(in) :: wlen
    logical :: is_b

    is_b = .false.
    if (wlen < 1 .or. wlen > 10) return

    select case(word(1:wlen))
    case('cd', 'echo', 'pwd', 'exit', 'export', 'set', 'unset')
      is_b = .true.
    case('alias', 'unalias', 'source', '.', ':')
      is_b = .true.
    case('history', 'jobs', 'fg', 'bg', 'kill', 'wait')
      is_b = .true.
    case('read', 'printf', 'test', '[')
      is_b = .true.
    case('type', 'which', 'command', 'builtin')
      is_b = .true.
    case('declare', 'local', 'readonly', 'return', 'shift')
      is_b = .true.
    case('break', 'continue')
      is_b = .true.
    case('coproc', 'let', 'eval', 'exec')
      is_b = .true.
    case('trap', 'ulimit', 'umask', 'getopts', 'hash')
      is_b = .true.
    case('help', 'fc', 'complete', 'compgen')
      is_b = .true.
    case('pushd', 'popd', 'dirs', 'prevd', 'nextd', 'dirh')
      is_b = .true.
    case('abbr', 'shopt', 'printenv', 'times')
      is_b = .true.
    case default
      is_b = .false.
    end select
  end function is_builtin_v2

  ! v2 tokenizer — state machine with multi-char operators and command position
  subroutine tokenize_v2(input, input_len, tokens, num_tokens)
    character(len=*), intent(in) :: input
    integer, intent(in) :: input_len
    type(hl_token_t), intent(out) :: tokens(MAX_TOKENS)
    integer, intent(out) :: num_tokens

    integer :: i, tok_start, wlen
    logical :: in_cmd_pos, has_slash, has_glob, has_equals
    character(len=1) :: ch, next_ch

    num_tokens = 0
    if (input_len == 0) return

    in_cmd_pos = .true.
    i = 1

    do while (i <= input_len .and. num_tokens < MAX_TOKENS)
      ch = input(i:i)

      ! Skip whitespace
      if (ch == ' ' .or. ch == char(9)) then
        i = i + 1
        cycle
      end if

      ! Comment — rest of line
      if (ch == '#') then
        num_tokens = num_tokens + 1
        tokens(num_tokens)%start_pos = i
        tokens(num_tokens)%end_pos = input_len
        tokens(num_tokens)%token_type = HTOK_COMMENT
        return  ! nothing after comment
      end if

      ! Single-quoted string
      if (ch == "'") then
        tok_start = i
        i = i + 1
        do while (i <= input_len)
          if (input(i:i) == "'") then
            i = i + 1
            exit
          end if
          i = i + 1
        end do
        num_tokens = num_tokens + 1
        tokens(num_tokens)%start_pos = tok_start
        tokens(num_tokens)%end_pos = i - 1
        tokens(num_tokens)%token_type = HTOK_STRING_SINGLE
        in_cmd_pos = .false.
        cycle
      end if

      ! Double-quoted string
      if (ch == '"') then
        tok_start = i
        i = i + 1
        do while (i <= input_len)
          if (input(i:i) == '\' .and. i + 1 <= input_len) then
            i = i + 2  ! skip escaped char
            cycle
          end if
          if (input(i:i) == '"') then
            i = i + 1
            exit
          end if
          i = i + 1
        end do
        num_tokens = num_tokens + 1
        tokens(num_tokens)%start_pos = tok_start
        tokens(num_tokens)%end_pos = i - 1
        tokens(num_tokens)%token_type = HTOK_STRING_DOUBLE
        in_cmd_pos = .false.
        cycle
      end if

      ! Variable
      if (ch == '$') then
        tok_start = i
        i = i + 1
        if (i <= input_len) then
          if (input(i:i) == '{') then
            ! ${...} expansion
            i = i + 1
            do while (i <= input_len .and. input(i:i) /= '}')
              i = i + 1
            end do
            if (i <= input_len) i = i + 1  ! skip }
          else if (input(i:i) == '(') then
            ! $() or $(()) command/arithmetic substitution
            i = i + 1
            if (i <= input_len .and. input(i:i) == '(') then
              ! $(( ... ))
              i = i + 1
              do while (i <= input_len)
                if (i + 1 <= input_len .and. input(i:i) == ')' .and. input(i+1:i+1) == ')') then
                  i = i + 2
                  exit
                end if
                i = i + 1
              end do
            else
              ! $( ... ) — find matching paren (simple, no nesting)
              do while (i <= input_len .and. input(i:i) /= ')')
                i = i + 1
              end do
              if (i <= input_len) i = i + 1  ! skip )
            end if
          else
            ! Simple $VAR
            do while (i <= input_len)
              if (.not. (is_alnum(input(i:i)) .or. input(i:i) == '_')) exit
              i = i + 1
            end do
          end if
        end if
        num_tokens = num_tokens + 1
        tokens(num_tokens)%start_pos = tok_start
        tokens(num_tokens)%end_pos = i - 1
        tokens(num_tokens)%token_type = HTOK_VARIABLE
        in_cmd_pos = .false.
        cycle
      end if

      ! Operators and redirections
      if (ch == '|' .or. ch == '&' .or. ch == ';' .or. &
          ch == '>' .or. ch == '<' .or. ch == '(' .or. ch == ')') then
        tok_start = i
        next_ch = ' '
        if (i + 1 <= input_len) next_ch = input(i+1:i+1)

        select case(ch)
        case('|')
          if (next_ch == '|') then
            i = i + 2  ! ||
          else
            i = i + 1  ! |
          end if
          num_tokens = num_tokens + 1
          tokens(num_tokens)%start_pos = tok_start
          tokens(num_tokens)%end_pos = i - 1
          tokens(num_tokens)%token_type = HTOK_OPERATOR
          in_cmd_pos = .true.

        case('&')
          if (next_ch == '&') then
            i = i + 2  ! &&
            num_tokens = num_tokens + 1
            tokens(num_tokens)%start_pos = tok_start
            tokens(num_tokens)%end_pos = i - 1
            tokens(num_tokens)%token_type = HTOK_OPERATOR
            in_cmd_pos = .true.
          else if (next_ch == '>') then
            i = i + 2  ! &>
            num_tokens = num_tokens + 1
            tokens(num_tokens)%start_pos = tok_start
            tokens(num_tokens)%end_pos = i - 1
            tokens(num_tokens)%token_type = HTOK_REDIRECT
          else
            i = i + 1  ! & (background)
            num_tokens = num_tokens + 1
            tokens(num_tokens)%start_pos = tok_start
            tokens(num_tokens)%end_pos = i - 1
            tokens(num_tokens)%token_type = HTOK_OPERATOR
            in_cmd_pos = .true.
          end if

        case(';')
          if (next_ch == ';') then
            i = i + 2  ! ;;
          else
            i = i + 1  ! ;
          end if
          num_tokens = num_tokens + 1
          tokens(num_tokens)%start_pos = tok_start
          tokens(num_tokens)%end_pos = i - 1
          tokens(num_tokens)%token_type = HTOK_OPERATOR
          in_cmd_pos = .true.

        case('>')
          if (next_ch == '>') then
            i = i + 2  ! >>
          else if (next_ch == '&') then
            i = i + 2  ! >&
          else if (next_ch == '|') then
            i = i + 2  ! >|
          else
            i = i + 1  ! >
          end if
          num_tokens = num_tokens + 1
          tokens(num_tokens)%start_pos = tok_start
          tokens(num_tokens)%end_pos = i - 1
          tokens(num_tokens)%token_type = HTOK_REDIRECT

        case('<')
          if (next_ch == '<') then
            i = i + 2  ! <<
            if (i <= input_len .and. input(i:i) == '<') i = i + 1  ! <<<
            if (i <= input_len .and. input(i:i) == '-') i = i + 1  ! <<-
          else if (next_ch == '&') then
            i = i + 2  ! <&
          else if (next_ch == '>') then
            i = i + 2  ! <>
          else
            i = i + 1  ! <
          end if
          num_tokens = num_tokens + 1
          tokens(num_tokens)%start_pos = tok_start
          tokens(num_tokens)%end_pos = i - 1
          tokens(num_tokens)%token_type = HTOK_REDIRECT

        case('(')
          if (next_ch == '(') then
            ! (( ... )) arithmetic context — consume as single token
            i = i + 2  ! skip ((
            do while (i <= input_len)
              if (i + 1 <= input_len .and. input(i:i) == ')' .and. input(i+1:i+1) == ')') then
                i = i + 2  ! skip ))
                exit
              end if
              i = i + 1
            end do
            num_tokens = num_tokens + 1
            tokens(num_tokens)%start_pos = tok_start
            tokens(num_tokens)%end_pos = i - 1
            tokens(num_tokens)%token_type = HTOK_NUMBER  ! arithmetic expression
            in_cmd_pos = .true.  ! do/command follows ))
          else
            i = i + 1
            num_tokens = num_tokens + 1
            tokens(num_tokens)%start_pos = tok_start
            tokens(num_tokens)%end_pos = i - 1
            tokens(num_tokens)%token_type = HTOK_OPERATOR
            in_cmd_pos = .true.
          end if

        case(')')
          i = i + 1
          num_tokens = num_tokens + 1
          tokens(num_tokens)%start_pos = tok_start
          tokens(num_tokens)%end_pos = i - 1
          tokens(num_tokens)%token_type = HTOK_OPERATOR

        end select
        cycle
      end if

      ! Word token — scan to end of word, then classify
      tok_start = i
      has_slash = .false.
      has_glob = .false.
      has_equals = .false.

      do while (i <= input_len)
        ch = input(i:i)
        ! Word terminators
        if (ch == ' ' .or. ch == char(9) .or. ch == ';' .or. ch == '|' .or. &
            ch == '&' .or. ch == '>' .or. ch == '<' .or. ch == '(' .or. &
            ch == ')' .or. ch == '#' .or. ch == '"' .or. ch == "'" .or. &
            ch == '$') exit
        if (ch == '/') has_slash = .true.
        if (ch == '*' .or. ch == '?' .or. ch == '[') has_glob = .true.
        if (ch == '=' .and. i > tok_start) has_equals = .true.
        i = i + 1
      end do

      wlen = i - tok_start
      if (wlen == 0) then
        i = i + 1
        cycle
      end if

      num_tokens = num_tokens + 1
      tokens(num_tokens)%start_pos = tok_start
      tokens(num_tokens)%end_pos = i - 1

      ! Check for fd-prefix redirect: all digits followed by > or <
      ! This applies regardless of command position (e.g. cmd 2>/dev/null)
      if (i <= input_len .and. (input(i:i) == '>' .or. input(i:i) == '<')) then
        if (is_all_digits(input(tok_start:i-1), wlen)) then
          ! This is an fd number — fold it into the redirect token
          num_tokens = num_tokens - 1
          next_ch = input(i:i)
          i = i + 1  ! skip > or <
          if (i <= input_len) then
            if ((next_ch == '>' .and. (input(i:i) == '>' .or. input(i:i) == '&' .or. input(i:i) == '|')) .or. &
                (next_ch == '<' .and. (input(i:i) == '<' .or. input(i:i) == '&' .or. input(i:i) == '>'))) then
              i = i + 1  ! multi-char redirect
            end if
          end if
          num_tokens = num_tokens + 1
          tokens(num_tokens)%start_pos = tok_start
          tokens(num_tokens)%end_pos = i - 1
          tokens(num_tokens)%token_type = HTOK_REDIRECT
          cycle
        end if
      end if

      ! Classify the word
      ! Keywords are structural — recognize them regardless of command position
      if (is_keyword_for_highlight(input(tok_start:), wlen)) then
        tokens(num_tokens)%token_type = HTOK_KEYWORD
        if (keyword_starts_command(input(tok_start:), wlen)) then
          in_cmd_pos = .true.
        else
          in_cmd_pos = .false.
        end if
      else if (in_cmd_pos) then
        if (is_builtin_v2(input(tok_start:), wlen)) then
          tokens(num_tokens)%token_type = HTOK_BUILTIN
          in_cmd_pos = .false.
        else if (is_valid_command(input(tok_start:tok_start+wlen-1))) then
          tokens(num_tokens)%token_type = HTOK_COMMAND_VALID
          in_cmd_pos = .false.
        else if (has_slash .and. is_path_executable(input(tok_start:tok_start+wlen-1))) then
          ! Path-to-executable (e.g. ./bin/fortsh, /usr/bin/env): check directly
          tokens(num_tokens)%token_type = HTOK_COMMAND_VALID
          in_cmd_pos = .false.
        else if (has_slash .and. is_navigable_path(input(tok_start:tok_start+wlen-1))) then
          ! Path-as-command (cd-on-path-entry): valid directory shows green
          tokens(num_tokens)%token_type = HTOK_COMMAND_VALID
          in_cmd_pos = .false.
        else
          tokens(num_tokens)%token_type = HTOK_COMMAND_INVALID
          in_cmd_pos = .false.
        end if
      else
        ! Not in command position — classify by content
        if (has_equals .and. is_valid_identifier(input(tok_start:), tok_start, i - 1)) then
          tokens(num_tokens)%token_type = HTOK_ASSIGNMENT
        else if (input(tok_start:tok_start) == '-') then
          tokens(num_tokens)%token_type = HTOK_OPTION
        else if (has_glob) then
          tokens(num_tokens)%token_type = HTOK_GLOB
        else if (has_slash) then
          tokens(num_tokens)%token_type = HTOK_PATH
        else if (is_all_digits(input(tok_start:i-1), wlen)) then
          tokens(num_tokens)%token_type = HTOK_NUMBER
        else
          tokens(num_tokens)%token_type = HTOK_DEFAULT
        end if
      end if
    end do
  end subroutine tokenize_v2

  ! Check if character is alphanumeric or underscore
  pure function is_alnum(ch) result(res)
    character(len=1), intent(in) :: ch
    logical :: res
    res = (ch >= 'a' .and. ch <= 'z') .or. (ch >= 'A' .and. ch <= 'Z') .or. &
          (ch >= '0' .and. ch <= '9') .or. ch == '_'
  end function is_alnum

  ! Check if string is all digits
  pure function is_all_digits(str, slen) result(res)
    character(len=*), intent(in) :: str
    integer, intent(in) :: slen
    logical :: res
    integer :: j
    res = slen > 0
    do j = 1, slen
      if (str(j:j) < '0' .or. str(j:j) > '9') then
        res = .false.
        return
      end if
    end do
  end function is_all_digits

  ! Check if word up to = is a valid identifier (for VAR=value detection)
  pure function is_valid_identifier(word, wstart, wend) result(res)
    character(len=*), intent(in) :: word
    integer, intent(in) :: wstart, wend
    logical :: res
    integer :: j, eq_pos, local_len
    res = .false.
    local_len = wend - wstart + 1
    ! Find = position relative to word start
    eq_pos = 0
    do j = 1, local_len
      if (word(j:j) == '=') then
        eq_pos = j
        exit
      end if
    end do
    if (eq_pos < 2) return  ! need at least 1 char before =
    ! First char must be letter or underscore
    if (.not. ((word(1:1) >= 'a' .and. word(1:1) <= 'z') .or. &
               (word(1:1) >= 'A' .and. word(1:1) <= 'Z') .or. word(1:1) == '_')) return
    ! Rest must be alnum or underscore
    do j = 2, eq_pos - 1
      if (.not. is_alnum(word(j:j))) return
    end do
    res = .true.
  end function is_valid_identifier

  ! v2 renderer — builds highlighted string from position-based tokens
  subroutine render_highlighted_v2(input, input_len, tokens, num_tokens, highlighted, actual_len)
    character(len=*), intent(in) :: input
    integer, intent(in) :: input_len
    type(hl_token_t), intent(in) :: tokens(MAX_TOKENS)
    integer, intent(in) :: num_tokens
    character(len=MAX_HIGHLIGHT_LEN), intent(out) :: highlighted
    integer, intent(out) :: actual_len

    integer :: pos, ipos, tidx, color, color_len, reset_len, j
    character(len=32) :: color_str, reset_str

    highlighted = ' '
    pos = 1
    tidx = 1

    reset_str = trim(color_code(COLOR_RESET))
    reset_len = len_trim(reset_str)

    ipos = 1
    do while (ipos <= input_len .and. pos < MAX_HIGHLIGHT_LEN - 20)
      ! Check if we're at the start of the next token
      if (tidx <= num_tokens .and. ipos == tokens(tidx)%start_pos) then
        ! Emit color code
        color = hl_token_color(tokens(tidx)%token_type)
        if (color /= COLOR_RESET) then
          color_str = trim(color_code(color))
          color_len = len_trim(color_str)
          do j = 1, color_len
            if (pos <= MAX_HIGHLIGHT_LEN) then
              highlighted(pos:pos) = color_str(j:j)
              pos = pos + 1
            end if
          end do
        end if

        ! Emit token characters
        do j = tokens(tidx)%start_pos, tokens(tidx)%end_pos
          if (pos <= MAX_HIGHLIGHT_LEN .and. j <= input_len) then
            highlighted(pos:pos) = input(j:j)
            pos = pos + 1
          end if
        end do

        ! Emit reset
        if (color /= COLOR_RESET) then
          do j = 1, reset_len
            if (pos <= MAX_HIGHLIGHT_LEN) then
              highlighted(pos:pos) = reset_str(j:j)
              pos = pos + 1
            end if
          end do
        end if

        ipos = tokens(tidx)%end_pos + 1
        tidx = tidx + 1
      else
        ! Non-token character (whitespace between tokens)
        highlighted(pos:pos) = input(ipos:ipos)
        pos = pos + 1
        ipos = ipos + 1
      end if
    end do

    actual_len = pos - 1
  end subroutine render_highlighted_v2

end module syntax_highlight