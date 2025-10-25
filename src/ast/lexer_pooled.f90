! ==============================================================================
! Module: lexer_pooled - Memory-pooled version of lexer module
! ==============================================================================
!
! This module provides pooled memory management for the lexer module,
! focusing on token strings and temporary buffers during tokenization.
!
! Key pooling targets:
! - Token value strings (64-256 bytes each)
! - Temporary strings during tokenization
! - Input buffer storage
! - Token array management
!
module lexer_pooled
  use ast_types
  use string_pool
  use memory_dashboard
  use iso_fortran_env, only: error_unit
  implicit none

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000

  ! Pooled token type - uses string_ref instead of allocatable
  type :: token_pooled_t
    integer :: type = TOKEN_EOF
    type(string_ref) :: value_ref           ! Pooled string reference
    integer :: line_number = 1
    integer :: column = 1
  end type token_pooled_t

  ! Pooled lexer state
  type :: lexer_pooled_t
    type(string_ref) :: input_ref           ! Pooled input string
    integer :: pos = 1
    integer :: line = 1
    integer :: column = 1
    type(token_pooled_t), allocatable :: tokens(:)
    integer :: token_count = 0
    integer :: token_capacity = 100
  contains
    procedure :: init => lexer_pooled_init
    procedure :: tokenize => lexer_pooled_tokenize
    procedure :: next_token => lexer_pooled_next_token
    procedure :: peek_char => lexer_pooled_peek_char
    procedure :: advance => lexer_pooled_advance
    procedure :: skip_whitespace => lexer_pooled_skip_whitespace
    procedure :: read_word => lexer_pooled_read_word
    procedure :: read_string => lexer_pooled_read_string
    procedure :: read_variable => lexer_pooled_read_variable
    procedure :: add_token => lexer_pooled_add_token
    procedure :: destroy => lexer_pooled_destroy
  end type lexer_pooled_t

contains

  ! Initialize lexer with pooled input string
  subroutine lexer_pooled_init(self, input_str)
    class(lexer_pooled_t), intent(inout) :: self
    character(*), intent(in) :: input_str

    ! Track entry
    call dashboard_track_entry(MOD_LEXER)

    ! Pool the input string
    self%input_ref = pool_get_string(len(input_str))
    call dashboard_track_allocation(MOD_LEXER, len(input_str), get_bucket_for_size(len(input_str)))
    call pool_copy_to_ref(self%input_ref, input_str)

    self%pos = 1
    self%line = 1
    self%column = 1
    self%token_count = 0

    if (allocated(self%tokens)) deallocate(self%tokens)
    allocate(self%tokens(self%token_capacity))

    ! Track exit
    call dashboard_track_exit(MOD_LEXER)
  end subroutine lexer_pooled_init

  ! Main tokenization routine with pooling
  subroutine lexer_pooled_tokenize(self)
    class(lexer_pooled_t), intent(inout) :: self
    type(token_pooled_t) :: token
    character(:), pointer :: input_ptr

    ! Track entry
    call dashboard_track_entry(MOD_LEXER)

    ! Get pointer to input data
    input_ptr => self%input_ref%data

    do while (self%pos <= len(input_ptr))
      call self%skip_whitespace()

      if (self%pos > len(input_ptr)) exit

      token = self%next_token()
      if (token%type == TOKEN_EOF) exit

      call self%add_token(token)
    end do

    ! Add final EOF token
    token%type = TOKEN_EOF
    token%value_ref = pool_get_string(1)
    call dashboard_track_allocation(MOD_LEXER, 1, 1)
    call pool_copy_to_ref(token%value_ref, '')
    token%line_number = self%line
    token%column = self%column
    call self%add_token(token)

    ! Track exit
    call dashboard_track_exit(MOD_LEXER)
  end subroutine lexer_pooled_tokenize

  ! Get next token with pooling
  recursive function lexer_pooled_next_token(self) result(token)
    class(lexer_pooled_t), intent(inout) :: self
    type(token_pooled_t) :: token
    character :: ch
    integer :: start_line, start_col
    character(:), pointer :: input_ptr

    input_ptr => self%input_ref%data

    call self%skip_whitespace()

    if (self%pos > len(input_ptr)) then
      token%type = TOKEN_EOF
      token%value_ref = pool_get_string(1)
      call dashboard_track_allocation(MOD_LEXER, 1, 1)
      call pool_copy_to_ref(token%value_ref, '')
      token%line_number = self%line
      token%column = self%column
      return
    end if

    ch = self%peek_char()
    start_line = self%line
    start_col = self%column

    select case(ch)
    case(char(10))  ! Newline
      call self%advance()
      token = make_pooled_token(TOKEN_NEWLINE, '', start_line, start_col)

    case(';')
      call self%advance()
      token = make_pooled_token(TOKEN_SEMICOLON, ';', start_line, start_col)

    case('|')
      call self%advance()
      if (self%peek_char() == '|') then
        call self%advance()
        token = make_pooled_token(TOKEN_OR, '||', start_line, start_col)
      else
        token = make_pooled_token(TOKEN_PIPE, '|', start_line, start_col)
      end if

    case('&')
      call self%advance()
      if (self%peek_char() == '&') then
        call self%advance()
        token = make_pooled_token(TOKEN_AND, '&&', start_line, start_col)
      else
        token = make_pooled_token(TOKEN_BACKGROUND, '&', start_line, start_col)
      end if

    case('<')
      call self%advance()
      if (self%peek_char() == '<') then
        call self%advance()
        token = make_pooled_token(TOKEN_REDIRECT_HERE, '<<', start_line, start_col)
      else
        token = make_pooled_token(TOKEN_REDIRECT_IN, '<', start_line, start_col)
      end if

    case('>')
      call self%advance()
      if (self%peek_char() == '>') then
        call self%advance()
        token = make_pooled_token(TOKEN_REDIRECT_APPEND, '>>', start_line, start_col)
      else
        token = make_pooled_token(TOKEN_REDIRECT_OUT, '>', start_line, start_col)
      end if

    case('(')
      call self%advance()
      token = make_pooled_token(TOKEN_LPAREN, '(', start_line, start_col)

    case(')')
      call self%advance()
      token = make_pooled_token(TOKEN_RPAREN, ')', start_line, start_col)

    case('{')
      call self%advance()
      token = make_pooled_token(TOKEN_LBRACE, '{', start_line, start_col)

    case('}')
      call self%advance()
      token = make_pooled_token(TOKEN_RBRACE, '}', start_line, start_col)

    case('[')
      call self%advance()
      token = make_pooled_token(TOKEN_LBRACKET, '[', start_line, start_col)

    case(']')
      call self%advance()
      token = make_pooled_token(TOKEN_RBRACKET, ']', start_line, start_col)

    case('"', "'")
      token = self%read_string()

    case('$')
      token = self%read_variable()

    case('#')
      ! Comment - skip to end of line
      do while (self%pos <= len(input_ptr) .and. self%peek_char() /= char(10))
        call self%advance()
      end do
      token = self%next_token()  ! Recursive call to get next real token

    case default
      ! Read word
      token = self%read_word()
    end select
  end function lexer_pooled_next_token

  ! Peek at current character without advancing
  function lexer_pooled_peek_char(self) result(ch)
    class(lexer_pooled_t), intent(in) :: self
    character :: ch
    character(:), pointer :: input_ptr

    input_ptr => self%input_ref%data
    if (self%pos <= len(input_ptr)) then
      ch = input_ptr(self%pos:self%pos)
    else
      ch = char(0)  ! EOF
    end if
  end function lexer_pooled_peek_char

  ! Advance position
  subroutine lexer_pooled_advance(self)
    class(lexer_pooled_t), intent(inout) :: self
    character(:), pointer :: input_ptr

    input_ptr => self%input_ref%data
    if (self%pos <= len(input_ptr)) then
      if (input_ptr(self%pos:self%pos) == char(10)) then
        self%line = self%line + 1
        self%column = 1
      else
        self%column = self%column + 1
      end if
      self%pos = self%pos + 1
    end if
  end subroutine lexer_pooled_advance

  ! Skip whitespace
  subroutine lexer_pooled_skip_whitespace(self)
    class(lexer_pooled_t), intent(inout) :: self
    character :: ch
    character(:), pointer :: input_ptr

    input_ptr => self%input_ref%data
    do while (self%pos <= len(input_ptr))
      ch = self%peek_char()
      if (ch == ' ' .or. ch == char(9)) then
        call self%advance()
      else
        exit
      end if
    end do
  end subroutine lexer_pooled_skip_whitespace

  ! Read word with pooled string
  function lexer_pooled_read_word(self) result(token)
    class(lexer_pooled_t), intent(inout) :: self
    type(token_pooled_t) :: token
    integer :: start_pos, start_line, start_col, word_len
    character(:), pointer :: input_ptr
    character :: ch
    character(len=256) :: temp_word

    input_ptr => self%input_ref%data
    start_pos = self%pos
    start_line = self%line
    start_col = self%column

    ! Read into temporary buffer first
    word_len = 0
    do while (self%pos <= len(input_ptr))
      ch = self%peek_char()
      if (ch == ' ' .or. ch == char(9) .or. ch == char(10) .or. &
          ch == ';' .or. ch == '|' .or. ch == '&' .or. &
          ch == '<' .or. ch == '>' .or. ch == '(' .or. ch == ')' .or. &
          ch == '{' .or. ch == '}' .or. ch == '[' .or. ch == ']') then
        exit
      end if
      word_len = word_len + 1
      if (word_len <= 256) then
        temp_word(word_len:word_len) = ch
      end if
      call self%advance()
    end do

    ! Allocate pooled string for word
    token%value_ref = pool_get_string(word_len)
    call dashboard_track_allocation(MOD_LEXER, word_len, get_bucket_for_size(word_len))
    call pool_copy_to_ref(token%value_ref, temp_word(1:word_len))

    ! Check if it's a keyword
    if (is_keyword(temp_word(1:word_len))) then
      token%type = keyword_token_type(temp_word(1:word_len))
    else
      token%type = TOKEN_WORD
    end if

    token%line_number = start_line
    token%column = start_col
  end function lexer_pooled_read_word

  ! Read quoted string with pooled memory
  function lexer_pooled_read_string(self) result(token)
    class(lexer_pooled_t), intent(inout) :: self
    type(token_pooled_t) :: token
    character :: quote_char, ch
    integer :: start_line, start_col, str_len
    character(:), pointer :: input_ptr
    character(len=1024) :: temp_str

    input_ptr => self%input_ref%data
    start_line = self%line
    start_col = self%column
    quote_char = self%peek_char()
    call self%advance()  ! Skip opening quote

    str_len = 0
    do while (self%pos <= len(input_ptr))
      ch = self%peek_char()
      if (ch == quote_char) then
        call self%advance()  ! Skip closing quote
        exit
      else if (ch == '\' .and. quote_char == '"') then
        ! Handle escape sequences
        call self%advance()
        if (self%pos <= len(input_ptr)) then
          ch = self%peek_char()
          select case(ch)
          case('n')
            str_len = str_len + 1
            if (str_len <= 1024) temp_str(str_len:str_len) = char(10)
          case('t')
            str_len = str_len + 1
            if (str_len <= 1024) temp_str(str_len:str_len) = char(9)
          case('\', '"', '$')
            str_len = str_len + 1
            if (str_len <= 1024) temp_str(str_len:str_len) = ch
          case default
            str_len = str_len + 1
            if (str_len <= 1024) temp_str(str_len:str_len) = ch
          end select
          call self%advance()
        end if
      else
        str_len = str_len + 1
        if (str_len <= 1024) temp_str(str_len:str_len) = ch
        call self%advance()
      end if
    end do

    ! Allocate pooled string
    token%value_ref = pool_get_string(str_len)
    call dashboard_track_allocation(MOD_LEXER, str_len, get_bucket_for_size(str_len))
    call pool_copy_to_ref(token%value_ref, temp_str(1:str_len))

    token%type = TOKEN_STRING
    token%line_number = start_line
    token%column = start_col
  end function lexer_pooled_read_string

  ! Read variable with pooled memory
  function lexer_pooled_read_variable(self) result(token)
    class(lexer_pooled_t), intent(inout) :: self
    type(token_pooled_t) :: token
    integer :: start_line, start_col, var_len
    character :: ch
    character(:), pointer :: input_ptr
    character(len=256) :: temp_var

    input_ptr => self%input_ref%data
    start_line = self%line
    start_col = self%column
    call self%advance()  ! Skip $

    var_len = 0
    if (self%peek_char() == '{') then
      ! ${var} syntax
      call self%advance()  ! Skip {

      do while (self%pos <= len(input_ptr))
        ch = self%peek_char()
        if (ch == '}') then
          call self%advance()  ! Skip }
          exit
        end if
        var_len = var_len + 1
        if (var_len <= 256) temp_var(var_len:var_len) = ch
        call self%advance()
      end do
    else
      ! $var syntax
      do while (self%pos <= len(input_ptr))
        ch = self%peek_char()
        if (.not. is_valid_var_char(ch)) exit
        var_len = var_len + 1
        if (var_len <= 256) temp_var(var_len:var_len) = ch
        call self%advance()
      end do
    end if

    ! Allocate pooled string
    token%value_ref = pool_get_string(var_len)
    call dashboard_track_allocation(MOD_LEXER, var_len, get_bucket_for_size(var_len))
    call pool_copy_to_ref(token%value_ref, temp_var(1:var_len))

    token%type = TOKEN_VARIABLE
    token%line_number = start_line
    token%column = start_col
  end function lexer_pooled_read_variable

  ! Add token to array
  subroutine lexer_pooled_add_token(self, token)
    class(lexer_pooled_t), intent(inout) :: self
    type(token_pooled_t), intent(in) :: token
    type(token_pooled_t), allocatable :: new_tokens(:)

    ! Resize array if needed
    if (self%token_count >= self%token_capacity) then
      self%token_capacity = self%token_capacity * 2
      allocate(new_tokens(self%token_capacity))
      new_tokens(1:self%token_count) = self%tokens(1:self%token_count)
      call move_alloc(new_tokens, self%tokens)
    end if

    self%token_count = self%token_count + 1
    self%tokens(self%token_count) = token
  end subroutine lexer_pooled_add_token

  ! Clean up lexer and release pooled resources
  subroutine lexer_pooled_destroy(self)
    class(lexer_pooled_t), intent(inout) :: self
    integer :: i

    ! Track entry
    call dashboard_track_entry(MOD_LEXER)

    ! Release pooled input string
    if (self%input_ref%pool_index /= 0) then
      call pool_release_string(self%input_ref)
      call dashboard_track_deallocation(MOD_LEXER, self%input_ref%str_len, &
                                        get_bucket_for_size(self%input_ref%str_len))
    end if

    ! Release all token value strings
    if (allocated(self%tokens)) then
      do i = 1, self%token_count
        if (self%tokens(i)%value_ref%pool_index /= 0) then
          call pool_release_string(self%tokens(i)%value_ref)
          call dashboard_track_deallocation(MOD_LEXER, self%tokens(i)%value_ref%str_len, &
                                            get_bucket_for_size(self%tokens(i)%value_ref%str_len))
        end if
      end do
      deallocate(self%tokens)
    end if

    self%pos = 1
    self%line = 1
    self%column = 1
    self%token_count = 0

    ! Track exit
    call dashboard_track_exit(MOD_LEXER)
  end subroutine lexer_pooled_destroy

  ! Helper: Create pooled token
  function make_pooled_token(token_type, value, line, col) result(token)
    integer, intent(in) :: token_type
    character(*), intent(in) :: value
    integer, intent(in) :: line, col
    type(token_pooled_t) :: token

    token%type = token_type
    token%value_ref = pool_get_string(len(value))
    call dashboard_track_allocation(MOD_LEXER, len(value), get_bucket_for_size(len(value)))
    call pool_copy_to_ref(token%value_ref, value)
    token%line_number = line
    token%column = col
  end function make_pooled_token

  ! Helper: Get bucket index for size
  function get_bucket_for_size(size_bytes) result(bucket_idx)
    integer, intent(in) :: size_bytes
    integer :: bucket_idx

    if (size_bytes <= 64) then
      bucket_idx = 1
    else if (size_bytes <= 256) then
      bucket_idx = 2
    else if (size_bytes <= 1024) then
      bucket_idx = 3
    else if (size_bytes <= 4096) then
      bucket_idx = 4
    else if (size_bytes <= 16384) then
      bucket_idx = 5
    else
      bucket_idx = 0  ! Direct allocation
    end if
  end function get_bucket_for_size

  ! Helper: Check if character is valid in variable name
  logical function is_valid_var_char(ch)
    character, intent(in) :: ch

    is_valid_var_char = (ch >= 'a' .and. ch <= 'z') .or. &
                        (ch >= 'A' .and. ch <= 'Z') .or. &
                        (ch >= '0' .and. ch <= '9') .or. &
                        ch == '_'
  end function is_valid_var_char

end module lexer_pooled