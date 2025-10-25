! ==============================================================================
! Module: lexer
! Purpose: Lexical analyzer for fortsh - converts text to tokens
! ==============================================================================
module lexer

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000
  use ast_types
  use iso_fortran_env, only: error_unit
  implicit none

  ! Lexer state
  type :: lexer_t
    character(:), allocatable :: input
    integer :: pos = 1
    integer :: line = 1
    integer :: column = 1
    type(token_t), allocatable :: tokens(:)
    integer :: token_count = 0
    integer :: token_capacity = 100
  contains
    procedure :: init => lexer_init
    procedure :: tokenize => lexer_tokenize
    procedure :: next_token => lexer_next_token
    procedure :: peek_char => lexer_peek_char
    procedure :: advance => lexer_advance
    procedure :: skip_whitespace => lexer_skip_whitespace
    procedure :: read_word => lexer_read_word
    procedure :: read_string => lexer_read_string
    procedure :: read_variable => lexer_read_variable
    procedure :: add_token => lexer_add_token
    procedure :: destroy => lexer_destroy
  end type lexer_t

contains

  ! Initialize lexer with input string
  subroutine lexer_init(self, input_str)
    class(lexer_t), intent(inout) :: self
    character(*), intent(in) :: input_str

    self%input = input_str
    self%pos = 1
    self%line = 1
    self%column = 1
    self%token_count = 0

    if (allocated(self%tokens)) deallocate(self%tokens)
    allocate(self%tokens(self%token_capacity))
  end subroutine lexer_init

  ! Main tokenization routine
  subroutine lexer_tokenize(self)
    class(lexer_t), intent(inout) :: self
    type(token_t) :: token

    do while (self%pos <= len(self%input))
      call self%skip_whitespace()

      if (self%pos > len(self%input)) exit

      token = self%next_token()
      if (token%type == TOKEN_EOF) exit

      call self%add_token(token)
    end do

    ! Add final EOF token
    token%type = TOKEN_EOF
    token%value = ''
    token%line_number = self%line
    token%column = self%column
    call self%add_token(token)
  end subroutine lexer_tokenize

  ! Get next token
  recursive function lexer_next_token(self) result(token)
    class(lexer_t), intent(inout) :: self
    type(token_t) :: token
    character :: ch
    integer :: start_line, start_col

    call self%skip_whitespace()

    if (self%pos > len(self%input)) then
      token%type = TOKEN_EOF
      token%value = ''
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
      token = make_token(TOKEN_NEWLINE, '', start_line, start_col)

    case(';')
      call self%advance()
      token = make_token(TOKEN_SEMICOLON, ';', start_line, start_col)

    case('|')
      call self%advance()
      if (self%peek_char() == '|') then
        call self%advance()
        token = make_token(TOKEN_OR, '||', start_line, start_col)
      else
        token = make_token(TOKEN_PIPE, '|', start_line, start_col)
      end if

    case('&')
      call self%advance()
      if (self%peek_char() == '&') then
        call self%advance()
        token = make_token(TOKEN_AND, '&&', start_line, start_col)
      else
        token = make_token(TOKEN_BACKGROUND, '&', start_line, start_col)
      end if

    case('<')
      call self%advance()
      if (self%peek_char() == '<') then
        call self%advance()
        token = make_token(TOKEN_REDIRECT_HERE, '<<', start_line, start_col)
      else
        token = make_token(TOKEN_REDIRECT_IN, '<', start_line, start_col)
      end if

    case('>')
      call self%advance()
      if (self%peek_char() == '>') then
        call self%advance()
        token = make_token(TOKEN_REDIRECT_APPEND, '>>', start_line, start_col)
      else
        token = make_token(TOKEN_REDIRECT_OUT, '>', start_line, start_col)
      end if

    case('(')
      call self%advance()
      token = make_token(TOKEN_LPAREN, '(', start_line, start_col)

    case(')')
      call self%advance()
      token = make_token(TOKEN_RPAREN, ')', start_line, start_col)

    case('{')
      call self%advance()
      token = make_token(TOKEN_LBRACE, '{', start_line, start_col)

    case('}')
      call self%advance()
      token = make_token(TOKEN_RBRACE, '}', start_line, start_col)

    case('[')
      call self%advance()
      token = make_token(TOKEN_LBRACKET, '[', start_line, start_col)

    case(']')
      call self%advance()
      token = make_token(TOKEN_RBRACKET, ']', start_line, start_col)

    case('"', "'")
      token = self%read_string()

    case('$')
      token = self%read_variable()

    case('#')
      ! Comment - skip to end of line
      do while (self%pos <= len(self%input) .and. self%peek_char() /= char(10))
        call self%advance()
      end do
      token = self%next_token()  ! Recursive call to get next real token

    case default
      ! Read word
      token = self%read_word()
    end select
  end function lexer_next_token

  ! Peek at current character without advancing
  function lexer_peek_char(self) result(ch)
    class(lexer_t), intent(in) :: self
    character :: ch

    if (self%pos <= len(self%input)) then
      ch = self%input(self%pos:self%pos)
    else
      ch = char(0)  ! EOF
    end if
  end function lexer_peek_char

  ! Advance position and update line/column
  subroutine lexer_advance(self)
    class(lexer_t), intent(inout) :: self

    if (self%pos <= len(self%input)) then
      if (self%input(self%pos:self%pos) == char(10)) then
        self%line = self%line + 1
        self%column = 1
      else
        self%column = self%column + 1
      end if
      self%pos = self%pos + 1
    end if
  end subroutine lexer_advance

  ! Skip whitespace (but not newlines)
  subroutine lexer_skip_whitespace(self)
    class(lexer_t), intent(inout) :: self
    character :: ch

    do while (self%pos <= len(self%input))
      ch = self%peek_char()
      if (ch == ' ' .or. ch == char(9)) then  ! Space or tab
        call self%advance()
      else
        exit
      end if
    end do
  end subroutine lexer_skip_whitespace

  ! Read a word token
  function lexer_read_word(self) result(token)
    class(lexer_t), intent(inout) :: self
    type(token_t) :: token
    integer :: start_pos, start_line, start_col
    character(:), allocatable :: word
    character :: ch

    start_pos = self%pos
    start_line = self%line
    start_col = self%column

    ! Read until we hit a delimiter
    do while (self%pos <= len(self%input))
      ch = self%peek_char()
      if (ch == ' ' .or. ch == char(9) .or. ch == char(10) .or. &
          ch == ';' .or. ch == '|' .or. ch == '&' .or. &
          ch == '<' .or. ch == '>' .or. ch == '(' .or. ch == ')' .or. &
          ch == '{' .or. ch == '}' .or. ch == '[' .or. ch == ']') then
        exit
      end if
      call self%advance()
    end do

    word = self%input(start_pos:self%pos-1)

    ! Check if it's a keyword
    if (is_keyword(word)) then
      token = make_token(keyword_token_type(word), word, start_line, start_col)
    else
      token = make_token(TOKEN_WORD, word, start_line, start_col)
    end if
  end function lexer_read_word

  ! Read a quoted string
  function lexer_read_string(self) result(token)
    class(lexer_t), intent(inout) :: self
    type(token_t) :: token
    character :: quote_char, ch
    integer :: start_line, start_col
    character(:), allocatable :: str

    start_line = self%line
    start_col = self%column
    quote_char = self%peek_char()
    call self%advance()  ! Skip opening quote

    str = ''
    do while (self%pos <= len(self%input))
      ch = self%peek_char()
      if (ch == quote_char) then
        call self%advance()  ! Skip closing quote
        exit
      else if (ch == '\' .and. quote_char == '"') then
        ! Handle escape sequences in double quotes
        call self%advance()
        if (self%pos <= len(self%input)) then
          ch = self%peek_char()
          select case(ch)
          case('n')
            str = str // char(10)
          case('t')
            str = str // char(9)
          case('\', '"', '$')
            str = str // ch
          case default
            str = str // ch
          end select
          call self%advance()
        end if
      else
        str = str // ch
        call self%advance()
      end if
    end do

    token = make_token(TOKEN_STRING, str, start_line, start_col)
    ! Note: expansion flag would be set when converting to word_node in parser
  end function lexer_read_string

  ! Read a variable reference
  function lexer_read_variable(self) result(token)
    class(lexer_t), intent(inout) :: self
    type(token_t) :: token
    integer :: start_line, start_col, start_pos
    character :: ch
    character(:), allocatable :: var_name

    start_line = self%line
    start_col = self%column
    call self%advance()  ! Skip $

    if (self%peek_char() == '{') then
      ! ${var} syntax
      call self%advance()  ! Skip {
      start_pos = self%pos

      do while (self%pos <= len(self%input))
        ch = self%peek_char()
        if (ch == '}') then
          var_name = self%input(start_pos:self%pos-1)
          call self%advance()  ! Skip }
          exit
        end if
        call self%advance()
      end do
    else
      ! $var syntax
      start_pos = self%pos

      do while (self%pos <= len(self%input))
        ch = self%peek_char()
        if (.not. is_valid_var_char(ch)) exit
        call self%advance()
      end do

      var_name = self%input(start_pos:self%pos-1)
    end if

    token = make_token(TOKEN_VARIABLE, var_name, start_line, start_col)
  end function lexer_read_variable

  ! Check if character is valid in variable name
  logical function is_valid_var_char(ch)
    character, intent(in) :: ch

    is_valid_var_char = (ch >= 'a' .and. ch <= 'z') .or. &
                        (ch >= 'A' .and. ch <= 'Z') .or. &
                        (ch >= '0' .and. ch <= '9') .or. &
                        ch == '_'
  end function is_valid_var_char

  ! Add token to array
  subroutine lexer_add_token(self, token)
    class(lexer_t), intent(inout) :: self
    type(token_t), intent(in) :: token
    type(token_t), allocatable :: new_tokens(:)

    ! Resize array if needed
    if (self%token_count >= self%token_capacity) then
      self%token_capacity = self%token_capacity * 2
      allocate(new_tokens(self%token_capacity))
      new_tokens(1:self%token_count) = self%tokens(1:self%token_count)
      call move_alloc(new_tokens, self%tokens)
    end if

    self%token_count = self%token_count + 1
    self%tokens(self%token_count) = token
  end subroutine lexer_add_token

  ! Clean up lexer
  subroutine lexer_destroy(self)
    class(lexer_t), intent(inout) :: self

    if (allocated(self%input)) deallocate(self%input)
    if (allocated(self%tokens)) deallocate(self%tokens)
    self%pos = 1
    self%line = 1
    self%column = 1
    self%token_count = 0
  end subroutine lexer_destroy

end module lexer