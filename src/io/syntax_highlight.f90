! ==============================================================================
! Module: syntax_highlight
! Purpose: Real-time syntax highlighting for interactive command line
! ==============================================================================
module syntax_highlight
  use iso_fortran_env, only: error_unit
  use system_interface, only: c_access, X_OK
  implicit none
  private

  ! Public interface
  public :: highlight_command_line
  public :: highlight_single_char
  public :: is_valid_command
  public :: init_syntax_highlighting
  public :: clear_command_cache

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

  ! Token types for syntax highlighting
  integer, parameter :: TOKEN_COMMAND = 1
  integer, parameter :: TOKEN_OPTION = 2
  integer, parameter :: TOKEN_STRING = 3
  integer, parameter :: TOKEN_VARIABLE = 4
  integer, parameter :: TOKEN_COMMENT = 5
  integer, parameter :: TOKEN_OPERATOR = 6
  integer, parameter :: TOKEN_NUMBER = 7
  integer, parameter :: TOKEN_PATH = 8

  ! Color scheme for different token types
  integer, parameter :: COLOR_COMMAND_VALID = COLOR_GREEN
  integer, parameter :: COLOR_COMMAND_INVALID = COLOR_RED
  integer, parameter :: COLOR_OPTION = COLOR_BLUE
  integer, parameter :: COLOR_STRING = COLOR_YELLOW
  integer, parameter :: COLOR_VARIABLE = COLOR_MAGENTA
  integer, parameter :: COLOR_COMMENT = COLOR_BRIGHT_BLACK
  integer, parameter :: COLOR_OPERATOR = COLOR_CYAN
  integer, parameter :: COLOR_NUMBER = COLOR_CYAN
  integer, parameter :: COLOR_PATH = COLOR_BRIGHT_BLUE

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
    ! Clear cache
    call clear_command_cache()

    ! Check if terminal supports colors
    ! For now, assume yes (can enhance with terminfo later)
    highlighting_enabled = .true.
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
  function highlight_command_line(input) result(highlighted)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: highlighted

    character(len=MAX_TOKEN_LEN) :: tokens(MAX_TOKENS)
    integer :: num_tokens
    character(len=32) :: token_colors(MAX_TOKENS)
    character(len=MAX_HIGHLIGHT_LEN) :: temp_highlighted
    integer :: actual_len

    if (.not. highlighting_enabled .or. len_trim(input) == 0) then
      highlighted = input
      return
    end if

    ! Tokenize input
    call tokenize_for_highlighting(input, tokens, num_tokens)

    if (num_tokens == 0) then
      highlighted = input
      return
    end if

    ! Determine color for each token
    call colorize_tokens(tokens, num_tokens, token_colors)

    ! Build highlighted string into temp buffer
    call build_highlighted_string(input, tokens, num_tokens, token_colors, temp_highlighted, actual_len)

    ! Allocate result with exact length needed
    if (actual_len > 0) then
      highlighted = temp_highlighted(1:actual_len)
    else
      highlighted = input
    end if
  end function

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
      write(colored_char, '(a,i0,a,a,a)') char(27) // '[', color, 'm', ch, char(27) // '[0m'
      highlighted = trim(colored_char)
    else
      highlighted = ch
    end if
  end function

  ! Tokenize input for syntax highlighting
  subroutine tokenize_for_highlighting(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    character(len=MAX_TOKEN_LEN), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens

    character(len=4096) :: working
    integer :: i, token_start, token_end
    logical :: in_quotes, in_comment
    character(len=1) :: quote_char

    ! Initialize
    working = input
    num_tokens = 0

    i = 1
    in_quotes = .false.
    in_comment = .false.
    quote_char = ' '

    do while (i <= len_trim(working))
      ! Skip whitespace
      do while (i <= len_trim(working) .and. working(i:i) == ' ')
        i = i + 1
      end do

      if (i > len_trim(working)) exit

      ! Check for comment
      if (working(i:i) == '#' .and. .not. in_quotes) then
        ! Rest of line is comment
        num_tokens = num_tokens + 1
        if (num_tokens <= MAX_TOKENS) then
          tokens(num_tokens) = trim(working(i:))
        end if
        exit
      end if

      ! Start of token
      token_start = i
      in_quotes = .false.

      ! Check if this is an operator character - treat as single-char token
      if (working(i:i) == ';' .or. working(i:i) == '|' .or. &
          working(i:i) == '&' .or. working(i:i) == '>' .or. working(i:i) == '<') then
        ! Operator - add as single character token
        num_tokens = num_tokens + 1
        if (num_tokens <= MAX_TOKENS) then
          tokens(num_tokens) = working(i:i)
        end if
        i = i + 1
        cycle  ! Continue to next iteration
      end if

      ! Find end of token
      do while (i <= len_trim(working))
        if (.not. in_quotes) then
          if (working(i:i) == '"' .or. working(i:i) == "'") then
            in_quotes = .true.
            quote_char = working(i:i)
          else if (working(i:i) == ' ' .or. working(i:i) == ';' .or. &
                   working(i:i) == '|' .or. working(i:i) == '&' .or. &
                   working(i:i) == '>' .or. working(i:i) == '<') then
            exit
          end if
        else
          if (working(i:i) == quote_char) then
            in_quotes = .false.
            i = i + 1
            exit
          end if
        end if
        i = i + 1
      end do

      ! Extract token
      token_end = i - 1
      if (token_end >= token_start) then
        num_tokens = num_tokens + 1
        if (num_tokens <= MAX_TOKENS) then
          tokens(num_tokens) = trim(working(token_start:token_end))
        end if
      end if
    end do
  end subroutine

  ! Determine colors for tokens
  subroutine colorize_tokens(tokens, num_tokens, colors)
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    character(len=*), intent(out) :: colors(:)

    integer :: i
    character(len=256) :: token

    do i = 1, num_tokens
      token = trim(tokens(i))

      if (len_trim(token) == 0) then
        colors(i) = color_code(COLOR_RESET)
        cycle
      end if

      ! Determine token type and color
      if (i == 1) then
        ! First token is the command
        if (is_valid_command(trim(token))) then
          colors(i) = color_code(COLOR_COMMAND_VALID)
        else
          colors(i) = color_code(COLOR_COMMAND_INVALID)
        end if
      else if (token(1:1) == '#') then
        ! Comment
        colors(i) = color_code(COLOR_COMMENT)
      else if (token(1:1) == '$') then
        ! Variable
        colors(i) = color_code(COLOR_VARIABLE)
      else if (token(1:1) == '"' .or. token(1:1) == "'") then
        ! String
        colors(i) = color_code(COLOR_STRING)
      else if (token(1:1) == '-') then
        ! Option/flag
        colors(i) = color_code(COLOR_OPTION)
      else if (is_number(token)) then
        ! Number
        colors(i) = color_code(COLOR_NUMBER)
      else if (index(token, '/') > 0) then
        ! Likely a path
        colors(i) = color_code(COLOR_PATH)
      else
        ! Default
        colors(i) = color_code(COLOR_RESET)
      end if
    end do
  end subroutine

  ! Build highlighted string with ANSI codes - preserves original spacing
  subroutine build_highlighted_string(input, tokens, num_tokens, colors, highlighted, actual_len)
    character(len=*), intent(in) :: input
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    character(len=*), intent(in) :: colors(:)
    character(len=MAX_HIGHLIGHT_LEN), intent(out) :: highlighted
    integer, intent(out) :: actual_len

    character(len=MAX_HIGHLIGHT_LEN) :: result_buffer
    integer :: i, input_pos, token_len, result_pos, color_len, reset_len
    integer :: buffer_size
    character(len=256) :: token_trimmed
    character(len=32) :: color_str, reset_str
    logical :: in_token

    ! Handle empty input
    if (len(input) == 0) then
      highlighted = ''
      actual_len = 0
      return
    end if

    ! Use fixed buffer
    buffer_size = MAX_HIGHLIGHT_LEN

    ! Initialize result buffer tracking
    result_pos = 1
    input_pos = 1
    reset_str = color_code(COLOR_RESET)
    reset_len = len_trim(reset_str)

    ! Walk through input character by character, preserving all spacing
    do while (input_pos <= len(input))
      in_token = .false.

      ! Check if current position starts a token
      do i = 1, num_tokens
        token_trimmed = trim(tokens(i))
        token_len = len_trim(token_trimmed)

        ! Skip empty tokens to avoid infinite loop
        if (token_len == 0) cycle

        ! Try to match token at current position
        if (input_pos + token_len - 1 <= len(input)) then
          if (input(input_pos:input_pos+token_len-1) == token_trimmed(:token_len)) then
            ! Found a token - add color, token, and reset
            color_str = trim(colors(i))
            color_len = len_trim(color_str)

            ! Bounds check before writing
            if (result_pos + color_len + token_len + reset_len - 1 <= buffer_size) then
              ! Add color code
              if (color_len > 0) then
                result_buffer(result_pos:result_pos+color_len-1) = color_str(:color_len)
                result_pos = result_pos + color_len
              end if
              ! Add token
              if (token_len > 0) then
                result_buffer(result_pos:result_pos+token_len-1) = token_trimmed(:token_len)
                result_pos = result_pos + token_len
              end if
              ! Add reset code
              if (reset_len > 0) then
                result_buffer(result_pos:result_pos+reset_len-1) = reset_str(:reset_len)
                result_pos = result_pos + reset_len
              end if
            end if

            input_pos = input_pos + token_len
            in_token = .true.
            exit
          end if
        end if
      end do

      ! If not in a token, just copy the character (whitespace, etc.)
      if (.not. in_token) then
        if (result_pos <= buffer_size) then
          result_buffer(result_pos:result_pos) = input(input_pos:input_pos)
          result_pos = result_pos + 1
        end if
        input_pos = input_pos + 1
      end if
    end do

    ! Extract final result (result_pos is one past the last character)
    if (result_pos > 1) then
      highlighted = result_buffer(1:result_pos-1)
      actual_len = result_pos - 1
    else
      highlighted = ''
      actual_len = 0
    end if
  end subroutine

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
    if (is_builtin(cmd)) then
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

  ! Check if command is a shell builtin
  function is_builtin(command) result(is_built)
    character(len=*), intent(in) :: command
    logical :: is_built

    character(len=len(command)) :: cmd

    cmd = trim(command)
    is_built = .false.

    ! Check common builtins
    select case(cmd)
      case('cd', 'echo', 'pwd', 'exit', 'export', 'set', 'unset', &
           'alias', 'unalias', 'source', 'history', 'jobs', 'fg', 'bg', &
           'kill', 'wait', 'read', 'printf', 'test', '[', 'type', &
           'command', 'builtin', 'declare', 'local', 'return', 'shift', &
           'break', 'continue', 'if', 'then', 'else', 'elif', 'fi', &
           'for', 'while', 'until', 'do', 'done', 'case', 'esac', &
           'function', 'select', 'time', 'coproc', 'let', 'eval', &
           'exec', 'trap', 'ulimit', 'umask', 'getopts', 'hash', &
           'help', 'fc', 'complete', 'compgen')
        is_built = .true.
    end select
  end function

  ! Check if command exists in PATH
  function command_exists_in_path(command) result(exists)
    use system_interface, only: file_is_executable
    character(len=*), intent(in) :: command
    logical :: exists

    character(len=MAX_PATH_LEN) :: path_env
    character(len=MAX_PATH_LEN) :: full_path
    integer :: path_start, path_end, colon_pos
    character(len=1024) :: dir

    exists = .false.

    ! Get PATH environment variable using intrinsic
    path_env = ''
    call get_environment_variable('PATH', path_env)
    if (len_trim(path_env) == 0) then
      return
    end if

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
  end function

  ! Check if string is a number
  function is_number(str) result(is_num)
    character(len=*), intent(in) :: str
    logical :: is_num

    integer :: iostat
    real :: dummy

    is_num = .false.

    if (len_trim(str) == 0) return

    ! Try to read as number
    read(str, *, iostat=iostat) dummy
    is_num = (iostat == 0)
  end function

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

end module syntax_highlight