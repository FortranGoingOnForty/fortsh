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
  public :: MAX_HIGHLIGHT_LEN  ! Export buffer size for callers

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

  ! Module-level working buffer to avoid stack overflow and substring temporaries
  character(len=4096), save :: module_working_buffer = ' '

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
  ! Convert to subroutine to avoid allocatable string returns (flang-new workaround)
  ! Takes input_len to avoid substring temporaries on stack
  subroutine highlight_command_line(input, highlighted, actual_len, input_len)
    character(len=*), intent(in) :: input
    character(len=MAX_HIGHLIGHT_LEN), intent(out) :: highlighted
    integer, intent(out), optional :: actual_len
    integer, intent(in), optional :: input_len  ! Explicit length to avoid substrings

    ! Use allocatable to avoid stack overflow (25KB is too much for stack!)
    character(len=MAX_TOKEN_LEN), allocatable :: tokens(:)
    integer :: num_tokens
    character(len=32), allocatable :: token_colors(:)  ! Move to heap (3.2KB)
    integer :: len_used
    integer :: actual_input_len

    ! Allocate arrays on heap
    allocate(tokens(MAX_TOKENS))
    allocate(token_colors(MAX_TOKENS))

    ! Use provided length if given, otherwise use full buffer length
    if (present(input_len)) then
      actual_input_len = input_len
    else
      actual_input_len = len(input)
    end if

    ! Bounds check - but don't use len(input) on allocatable strings (returns 0 in flang-new!)
    if (actual_input_len < 0) actual_input_len = 0
    ! Don't check upper bound against len(input) for allocatable strings
    ! if (actual_input_len > len(input)) actual_input_len = len(input)

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

    ! Tokenize input (pass full buffer with length to avoid substring operation)
    call tokenize_for_highlighting(input, tokens, num_tokens, actual_input_len)

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

    call colorize_tokens(tokens, num_tokens, token_colors)

    ! WORKAROUND: build_highlighted_string has too many substring operations
    ! For now, just highlight the first token (command) in color, rest in plain text
    call build_simple_highlighted_string(input, tokens, num_tokens, token_colors, highlighted, len_used, actual_input_len)
    ! DEBUG: write(*, '(a)') '[DEBUG: Built highlighted string]'

    ! DEBUG: write(*, '(a,i0,a)') '[DEBUG: len_used=', len_used, ']'

    ! Return actual length used
    ! DEBUG: write(*, '(a,l1,a)') '[DEBUG: present(actual_len)=', present(actual_len), ']'
    if (present(actual_len)) then
      ! DEBUG: write(*, '(a)') '[DEBUG: About to set actual_len]'
      actual_len = len_used
      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG: Set actual_len to ', actual_len, ']'
    end if

    ! DEBUG: write(*, '(a)') '[DEBUG: Exiting highlight_command_line]'

    ! Deallocate heap-allocated arrays
    if (allocated(tokens)) deallocate(tokens)
    if (allocated(token_colors)) deallocate(token_colors)
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
      write(colored_char, '(a,i0,a,a,a)') char(27) // '[', color, 'm', ch, char(27) // '[0m'
      highlighted = trim(colored_char)
    else
      highlighted = ch
    end if
  end function

  ! Tokenize input for syntax highlighting
  subroutine tokenize_for_highlighting(input, tokens, num_tokens, input_len)
    character(len=*), intent(in) :: input
    character(len=MAX_TOKEN_LEN), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens
    integer, intent(in) :: input_len  ! Explicit length to avoid substrings

    integer :: i, token_start, token_end, j
    logical :: in_quotes, in_comment
    character(len=1) :: quote_char, current_char

    ! Use module-level working buffer (avoids stack overflow and substring temporaries)

    ! DEBUG: write(*, '(a,i0,a)') '[DEBUG tokenize: input len=', len(input), ']'

    ! Initialize tokens array to all spaces to make len_trim safe
    do j = 1, size(tokens)
      tokens(j) = ' '
    end do

    ! Initialize working buffer to spaces
    module_working_buffer = ' '

    ! Copy input character by character to avoid substring temporaries (flang-new bug)
    if (input_len > 0 .and. input_len <= len(module_working_buffer)) then
      do j = 1, input_len
        module_working_buffer(j:j) = input(j:j)
      end do
    end if

    ! DEBUG: write(*, '(a)') '[DEBUG tokenize: copied input to working]'

    num_tokens = 0

    i = 1
    in_quotes = .false.
    in_comment = .false.
    quote_char = ' '

    ! DEBUG: write(*, '(a)') '[DEBUG tokenize: entering main loop]'

    do while (i <= input_len)
      ! DEBUG: write(*, '(a,i0,a,i0,a)') '[DEBUG tokenize: loop i=', i, ' input_len=', input_len, ']'

      ! Skip whitespace
      ! DEBUG: write(*, '(a)') '[DEBUG tokenize: about to skip whitespace]'
      do while (i <= input_len .and. module_working_buffer(i:i) == ' ')
        i = i + 1
      end do
      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG tokenize: after whitespace skip, i=', i, ']'

      if (i > input_len) exit

      ! DEBUG: write(*, '(a)') '[DEBUG tokenize: about to check for comment]'
      ! Check for comment
      if (module_working_buffer(i:i) == '#' .and. .not. in_quotes) then
        ! DEBUG: write(*, '(a)') '[DEBUG tokenize: found comment]'
        ! Rest of line is comment
        num_tokens = num_tokens + 1
        if (num_tokens <= MAX_TOKENS) then
          ! DEBUG: write(*, '(a)') '[DEBUG tokenize: about to trim working for comment token]'
          tokens(num_tokens) = module_working_buffer(i:input_len)
          ! DEBUG: write(*, '(a)') '[DEBUG tokenize: trimmed working for comment token]'
        end if
        exit
      end if
      ! DEBUG: write(*, '(a)') '[DEBUG tokenize: not a comment, continuing]'

      ! Start of token
      token_start = i
      in_quotes = .false.

      ! DEBUG: write(*, '(a)') '[DEBUG tokenize: about to check for operator]'
      ! Check if this is an operator character - treat as single-char token
      if (module_working_buffer(i:i) == ';' .or. module_working_buffer(i:i) == '|' .or. &
          module_working_buffer(i:i) == '&' .or. module_working_buffer(i:i) == '>' .or. module_working_buffer(i:i) == '<') then
        ! DEBUG: write(*, '(a)') '[DEBUG tokenize: found operator]'
        ! Operator - add as single character token
        num_tokens = num_tokens + 1
        if (num_tokens <= MAX_TOKENS) then
          tokens(num_tokens) = module_working_buffer(i:i)
        end if
        i = i + 1
        cycle  ! Continue to next iteration
      end if

      ! DEBUG: write(*, '(a)') '[DEBUG tokenize: not an operator, finding end of token]'
      ! Find end of token
      do while (i <= input_len)
        ! DEBUG: write(*, '(a,i0,a)') '[DEBUG tokenize: in end-of-token loop, i=', i, ']'
        if (.not. in_quotes) then
          if (module_working_buffer(i:i) == '"' .or. module_working_buffer(i:i) == "'") then
            in_quotes = .true.
            quote_char = module_working_buffer(i:i)
          else if (module_working_buffer(i:i) == ' ' .or. module_working_buffer(i:i) == ';' .or. &
                   module_working_buffer(i:i) == '|' .or. module_working_buffer(i:i) == '&' .or. &
                   module_working_buffer(i:i) == '>' .or. module_working_buffer(i:i) == '<') then
            exit
          end if
        else
          if (module_working_buffer(i:i) == quote_char) then
            in_quotes = .false.
            i = i + 1
            exit
          end if
        end if
        i = i + 1
      end do

      ! DEBUG: write(*, '(a)') '[DEBUG tokenize: about to extract token]'
      ! Extract token
      token_end = i - 1
      if (token_end >= token_start) then
        ! DEBUG: write(*, '(a,i0,a,i0,a)') '[DEBUG tokenize: token_start=', token_start, ' token_end=', token_end, ']'
        num_tokens = num_tokens + 1
        if (num_tokens <= MAX_TOKENS) then
          ! DEBUG: write(*, '(a)') '[DEBUG tokenize: about to assign token - NO TRIM]'
          ! SAFETY: Don't use trim() - it walks the string
          if (token_end - token_start + 1 <= MAX_TOKEN_LEN) then
            tokens(num_tokens) = module_working_buffer(token_start:token_end)
          else
            tokens(num_tokens) = module_working_buffer(token_start:token_start+MAX_TOKEN_LEN-1)
          end if
          ! DEBUG: write(*, '(a)') '[DEBUG tokenize: assigned token]'
        end if
      end if
    end do

    ! DEBUG: write(*, '(a,i0,a)') '[DEBUG tokenize: exiting with num_tokens=', num_tokens, ']'

    ! Deallocate heap-allocated working buffer
  end subroutine

  ! Determine colors for tokens
  subroutine colorize_tokens(tokens, num_tokens, colors)
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    character(len=*), intent(out) :: colors(:)

    integer :: i, token_len
    character(len=256) :: token

    ! DEBUG: write(*, '(a)') '[DEBUG colorize: entering colorize_tokens]'

    do i = 1, num_tokens
      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG colorize: processing token ', i, ']'

      ! SAFETY: tokens array is initialized to spaces, so len_trim is safe here
      token_len = len_trim(tokens(i))
      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG colorize: after len_trim, token_len=', token_len, ']'

      if (token_len > 0 .and. token_len <= len(token)) then
        token(1:token_len) = tokens(i)(1:token_len)
        if (token_len < len(token)) then
          token(token_len+1:) = ' '
        end if
      else
        token = ' '
        token_len = 0
      end if

      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG colorize: final token_len=', token_len, ']'

      if (token_len == 0) then
        colors(i) = color_code(COLOR_RESET)
        cycle
      end if

      ! DEBUG: write(*, '(a)') '[DEBUG colorize: determining token type]'
      ! Determine token type and color
      if (i == 1) then
        ! DEBUG: write(*, '(a)') '[DEBUG colorize: first token (command)]'
        ! DEBUG: write(*, '(a,a,a)') '[DEBUG colorize: calling is_valid_command with token="', token(1:token_len), '"]'
        ! First token is the command - use token_len for bounds
        if (is_valid_command(token(1:token_len))) then
          ! DEBUG: write(*, '(a)') '[DEBUG colorize: command is valid]'
          colors(i) = color_code(COLOR_COMMAND_VALID)
        else
          ! DEBUG: write(*, '(a)') '[DEBUG colorize: command is invalid]'
          colors(i) = color_code(COLOR_COMMAND_INVALID)
        end if
        ! DEBUG: write(*, '(a)') '[DEBUG colorize: after is_valid_command]'
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

      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG colorize: finished processing token ', i, ']'
    end do

    ! DEBUG: write(*, '(a)') '[DEBUG colorize: exiting colorize_tokens]'
  end subroutine

  ! Simple highlighting - just color the first token, avoid substring operations
  subroutine build_simple_highlighted_string(input, tokens, num_tokens, colors, highlighted, actual_len, input_len)
    character(len=*), intent(in) :: input
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    character(len=*), intent(in) :: colors(:)
    character(len=MAX_HIGHLIGHT_LEN), intent(out) :: highlighted
    integer, intent(out) :: actual_len
    integer, intent(in) :: input_len

    integer :: first_token_len, i, j, pos, color_len, reset_len
    character(len=32) :: color_str, reset_str

    ! Initialize output buffer
    highlighted = ' '
    pos = 1

    if (num_tokens > 0 .and. input_len > 0) then
      first_token_len = len_trim(tokens(1))
      color_str = trim(colors(1))
      reset_str = trim(color_code(COLOR_RESET))
      color_len = len_trim(color_str)
      reset_len = len_trim(reset_str)

      ! Write: color_code + first_token + reset_code + rest_of_input

      ! 1. Copy color code
      do i = 1, color_len
        if (pos <= MAX_HIGHLIGHT_LEN) then
          highlighted(pos:pos) = color_str(i:i)
          pos = pos + 1
        end if
      end do

      ! 2. Copy first token (from tokens array, not input - avoids substring on input)
      do i = 1, first_token_len
        if (pos <= MAX_HIGHLIGHT_LEN) then
          highlighted(pos:pos) = tokens(1)(i:i)
          pos = pos + 1
        end if
      end do

      ! 3. Copy reset code
      do i = 1, reset_len
        if (pos <= MAX_HIGHLIGHT_LEN) then
          highlighted(pos:pos) = reset_str(i:i)
          pos = pos + 1
        end if
      end do

      ! 4. Copy rest of input after first token
      ! Skip whitespace and the first token in input, copy the rest
      j = first_token_len + 1
      do while (j <= input_len .and. module_working_buffer(j:j) == ' ')
        ! Copy whitespace
        if (pos <= MAX_HIGHLIGHT_LEN) then
          highlighted(pos:pos) = ' '
          pos = pos + 1
        end if
        j = j + 1
      end do

      ! Copy remaining characters
      do while (j <= input_len)
        if (pos <= MAX_HIGHLIGHT_LEN) then
          highlighted(pos:pos) = module_working_buffer(j:j)
          pos = pos + 1
        end if
        j = j + 1
      end do

      actual_len = pos - 1
    else
      ! No tokens or empty input - return plain
      actual_len = input_len
      do i = 1, input_len
        if (i <= MAX_HIGHLIGHT_LEN) then
          highlighted(i:i) = input(i:i)
        end if
      end do
    end if
  end subroutine

  ! Build highlighted string with ANSI codes - preserves original spacing
  subroutine build_highlighted_string(input, tokens, num_tokens, colors, highlighted, actual_len)
    character(len=*), intent(in) :: input
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    character(len=*), intent(in) :: colors(:)
    character(len=MAX_HIGHLIGHT_LEN), intent(out) :: highlighted
    integer, intent(out) :: actual_len

    ! Use allocatable to avoid stack allocation
    character(len=:), allocatable :: result_buffer
    character(len=:), allocatable :: token_trimmed  ! Move to heap
    character(len=:), allocatable :: color_str, reset_str  ! Move to heap
    integer :: i, input_pos, token_len, result_pos, color_len, reset_len
    integer :: buffer_size
    logical :: in_token


    ! Allocate buffers on heap
    allocate(character(len=MAX_HIGHLIGHT_LEN) :: result_buffer)
    allocate(character(len=256) :: token_trimmed)
    allocate(character(len=32) :: color_str)
    allocate(character(len=32) :: reset_str)

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
        ! SAFETY: tokens are initialized to spaces, so len_trim is safe
        token_len = len_trim(tokens(i))

        if (token_len > 0 .and. token_len <= len(token_trimmed)) then
          token_trimmed(1:token_len) = tokens(i)(1:token_len)
        else
          token_len = 0
        end if

        ! Skip empty tokens to avoid infinite loop
        if (token_len == 0) cycle

        ! Try to match token at current position
        if (input_pos + token_len - 1 <= len(input)) then
          if (input(input_pos:input_pos+token_len-1) == token_trimmed(1:token_len)) then
            ! Found a token - add color, token, and reset
            color_len = len_trim(colors(i))

            if (color_len > 0 .and. color_len <= len(color_str)) then
              color_str(1:color_len) = colors(i)(1:color_len)
            else
              color_len = 0
            end if


            ! Bounds check before writing
            if (result_pos + color_len + token_len + reset_len - 1 <= buffer_size) then
              ! Add color code
              if (color_len > 0) then
                result_buffer(result_pos:result_pos+color_len-1) = color_str(1:color_len)
                result_pos = result_pos + color_len
              end if
              ! Add token
              if (token_len > 0) then
                result_buffer(result_pos:result_pos+token_len-1) = token_trimmed(1:token_len)
                result_pos = result_pos + token_len
              end if
              ! Add reset code
              if (reset_len > 0) then
                result_buffer(result_pos:result_pos+reset_len-1) = reset_str(1:reset_len)
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
        ! DEBUG: write(*, '(a)') '[DEBUG build: not in token, copying character]'
        if (result_pos <= buffer_size) then
          result_buffer(result_pos:result_pos) = input(input_pos:input_pos)
          result_pos = result_pos + 1
        end if
        input_pos = input_pos + 1
      end if
    end do


    ! DEBUG: write(*, '(a)') '[DEBUG build: exited outer loop]'

    ! DEBUG: write(*, '(a,i0,a)') '[DEBUG build: result_pos=', result_pos, ']'

    ! Extract final result (result_pos is one past the last character)
    if (result_pos > 1) then
      ! DEBUG: write(*, '(a)') '[DEBUG build: result_pos > 1, extracting result]'
      ! Copy the result to output buffer
      ! Must use substring assignment to fixed-length string
      actual_len = result_pos - 1

      ! DEBUG: write(*, '(a,i0,a)') '[DEBUG build: actual_len=', actual_len, ']'

      ! Safety check to prevent buffer overflow
      if (actual_len > 0 .and. actual_len <= MAX_HIGHLIGHT_LEN) then
        ! DEBUG: write(*, '(a)') '[DEBUG build: about to copy result_buffer to highlighted]'
        highlighted(1:actual_len) = result_buffer(1:actual_len)
        ! DEBUG: write(*, '(a)') '[DEBUG build: copied result_buffer to highlighted]'
        ! Pad rest with spaces (Fortran requirement for fixed-length strings)
        if (actual_len < MAX_HIGHLIGHT_LEN) then
          ! DEBUG: write(*, '(a)') '[DEBUG build: about to pad with spaces]'
          highlighted(actual_len+1:MAX_HIGHLIGHT_LEN) = ' '
          ! DEBUG: write(*, '(a)') '[DEBUG build: padded with spaces]'
        end if
      else
        ! DEBUG: write(*, '(a)') '[DEBUG build: actual_len out of bounds, using fallback]'
        ! Safety fallback
        highlighted = ''
        actual_len = 0
      end if
    else
      ! DEBUG: write(*, '(a)') '[DEBUG build: result_pos <= 1, using empty]'
      highlighted = ''
      actual_len = 0
    end if

    ! DEBUG: write(*, '(a)') '[DEBUG build: done with build_highlighted_string]'

    ! Deallocate heap-allocated buffers
    if (allocated(result_buffer)) deallocate(result_buffer)
    if (allocated(token_trimmed)) deallocate(token_trimmed)
    if (allocated(color_str)) deallocate(color_str)
    if (allocated(reset_str)) deallocate(reset_str)
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

    ! Use allocatable to avoid 9KB stack allocation
    character(len=:), allocatable :: path_env, full_path, dir
    integer :: path_start, path_end, colon_pos

    ! Allocate buffers on heap
    allocate(character(len=MAX_PATH_LEN) :: path_env)
    allocate(character(len=MAX_PATH_LEN) :: full_path)
    allocate(character(len=1024) :: dir)

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

    ! Deallocate heap-allocated buffers
    if (allocated(path_env)) deallocate(path_env)
    if (allocated(full_path)) deallocate(full_path)
    if (allocated(dir)) deallocate(dir)
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