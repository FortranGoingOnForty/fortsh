! ==============================================================================
! Module: lexer_simple
! Purpose: Simple lexer for enhanced AST (no module conflicts)
! ==============================================================================
module lexer_simple
  use ast_types_enhanced, only: token_t, TOKEN_EOF, TOKEN_WORD, TOKEN_STRING, &
                                TOKEN_VARIABLE, TOKEN_SEMICOLON, TOKEN_NEWLINE, &
                                TOKEN_PIPE, TOKEN_AND, TOKEN_OR, TOKEN_BACKGROUND, &
                                TOKEN_REDIRECT_IN, TOKEN_REDIRECT_OUT, &
                                TOKEN_REDIRECT_APPEND, TOKEN_REDIRECT_HERE, &
                                TOKEN_IF, TOKEN_THEN, TOKEN_ELSE, TOKEN_ELIF, &
                                TOKEN_FI, TOKEN_FOR, TOKEN_IN, TOKEN_DO, TOKEN_DONE, &
                                TOKEN_WHILE, TOKEN_BREAK, TOKEN_CONTINUE, &
                                TOKEN_COMMAND_SUBST_START, TOKEN_LPAREN, TOKEN_RPAREN, &
                                is_keyword, keyword_token_type
  implicit none

  type :: lexer_simple_t
    character(:), allocatable :: input
    integer :: position = 1
    integer :: length = 0
    type(token_t), allocatable :: tokens(:)
    integer :: token_count = 0
    integer :: line_number = 1
    integer :: column = 1
  contains
    procedure :: init => lexer_init
    procedure :: tokenize => lexer_tokenize
    procedure :: destroy => lexer_destroy
  end type lexer_simple_t

contains

  subroutine lexer_init(self, input)
    class(lexer_simple_t), intent(inout) :: self
    character(*), intent(in) :: input

    self%input = input
    self%length = len(input)
    self%position = 1
    self%line_number = 1
    self%column = 1
    self%token_count = 0

    if (allocated(self%tokens)) deallocate(self%tokens)
    allocate(self%tokens(200))  ! Pre-allocate space
  end subroutine lexer_init

  subroutine lexer_tokenize(self)
    class(lexer_simple_t), intent(inout) :: self
    character :: ch
    character(256) :: word
    integer :: word_len

    self%token_count = 0

    do while (self%position <= self%length)
      ch = self%input(self%position:self%position)

      ! Skip whitespace (except newline)
      if (ch == ' ' .or. ch == char(9)) then
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      ! Handle newline
      if (ch == char(10)) then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_NEWLINE
        self%tokens(self%token_count)%value = ''
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%line_number = self%line_number + 1
        self%column = 1
        cycle
      end if

      ! Handle semicolon
      if (ch == ';') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_SEMICOLON
        self%tokens(self%token_count)%value = ';'
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      ! Handle pipe
      if (ch == '|') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_PIPE
        self%tokens(self%token_count)%value = '|'
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      ! Handle parentheses (for command substitution)
      if (ch == '(') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_LPAREN
        self%tokens(self%token_count)%value = '('
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      if (ch == ')') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_RPAREN
        self%tokens(self%token_count)%value = ')'
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      ! Handle redirection operators
      if (ch == '<') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_REDIRECT_IN
        self%tokens(self%token_count)%value = '<'
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      if (ch == '>') then
        ! Check for append (>>)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '>') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_REDIRECT_APPEND
          self%tokens(self%token_count)%value = '>>'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_REDIRECT_OUT
          self%tokens(self%token_count)%value = '>'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      ! Handle variable or command substitution
      if (ch == '$') then
        ! Check for command substitution $(...)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '(') then
          ! Command substitution - for now just tokenize $( as a special token
          ! The parser will handle finding the matching )
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_COMMAND_SUBST_START
          self%tokens(self%token_count)%value = '$('
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          ! Regular variable
          self%position = self%position + 1
          self%column = self%column + 1
          word = ''
          word_len = 0
          do while (self%position <= self%length)
            ch = self%input(self%position:self%position)
            if (.not. is_word_char(ch)) exit
            word_len = word_len + 1
            word(word_len:word_len) = ch
            self%position = self%position + 1
            self%column = self%column + 1
          end do
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_VARIABLE
          self%tokens(self%token_count)%value = word(1:word_len)
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column - word_len - 1
        end if
        cycle
      end if

      ! Handle words
      if (is_word_char(ch)) then
        word = ''
        word_len = 0
        do while (self%position <= self%length)
          ch = self%input(self%position:self%position)
          if (.not. is_word_char(ch)) exit
          word_len = word_len + 1
          word(word_len:word_len) = ch
          self%position = self%position + 1
          self%column = self%column + 1
        end do

        self%token_count = self%token_count + 1

        ! Check if it's a keyword
        if (is_keyword(word(1:word_len))) then
          self%tokens(self%token_count)%type = keyword_token_type(word(1:word_len))
        else
          self%tokens(self%token_count)%type = TOKEN_WORD
        end if

        self%tokens(self%token_count)%value = word(1:word_len)
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column - word_len
        cycle
      end if

      ! Skip unknown characters
      self%position = self%position + 1
      self%column = self%column + 1
    end do

    ! Add EOF token
    self%token_count = self%token_count + 1
    self%tokens(self%token_count)%type = TOKEN_EOF
    self%tokens(self%token_count)%value = ''
    self%tokens(self%token_count)%line_number = self%line_number
    self%tokens(self%token_count)%column = self%column
  end subroutine lexer_tokenize

  logical function is_word_char(ch)
    character, intent(in) :: ch

    is_word_char = (ch >= 'a' .and. ch <= 'z') .or. &
                   (ch >= 'A' .and. ch <= 'Z') .or. &
                   (ch >= '0' .and. ch <= '9') .or. &
                   ch == '_' .or. ch == '-' .or. ch == '.' .or. &
                   ch == '*' .or. ch == '?' .or. ch == '[' .or. ch == ']' .or. &
                   ch == '/' .or. ch == '=' .or. ch == '~' .or. ch == '+'
  end function is_word_char

  subroutine lexer_destroy(self)
    class(lexer_simple_t), intent(inout) :: self

    if (allocated(self%tokens)) deallocate(self%tokens)
    if (allocated(self%input)) deallocate(self%input)
    self%token_count = 0
    self%position = 1
  end subroutine lexer_destroy

end module lexer_simple