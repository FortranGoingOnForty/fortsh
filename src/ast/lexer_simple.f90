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
                                TOKEN_REDIRECT_HERE_STRING, &
                                TOKEN_PROC_SUBST_IN, TOKEN_PROC_SUBST_OUT, &
                                TOKEN_IF, TOKEN_THEN, TOKEN_ELSE, TOKEN_ELIF, &
                                TOKEN_FI, TOKEN_FOR, TOKEN_IN, TOKEN_DO, TOKEN_DONE, &
                                TOKEN_WHILE, TOKEN_BREAK, TOKEN_CONTINUE, &
                                TOKEN_COMMAND_SUBST_START, TOKEN_ARITH_START, TOKEN_ARITH_END, &
                                TOKEN_LPAREN, TOKEN_RPAREN, TOKEN_LBRACE, TOKEN_RBRACE, &
                                TOKEN_LBRACKET_DOUBLE, TOKEN_RBRACKET_DOUBLE, &
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

      ! Handle pipe and OR operator
      if (ch == '|') then
        ! Check for OR operator (||)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '|') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_OR
          self%tokens(self%token_count)%value = '||'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          ! Regular pipe
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_PIPE
          self%tokens(self%token_count)%value = '|'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      ! Handle ampersand and AND operator
      if (ch == '&') then
        ! Check for AND operator (&&)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '&') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_AND
          self%tokens(self%token_count)%value = '&&'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          ! Background operator
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_BACKGROUND
          self%tokens(self%token_count)%value = '&'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
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
        ! Check for )) for arithmetic expansion
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == ')') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_ARITH_END
          self%tokens(self%token_count)%value = '))'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_RPAREN
          self%tokens(self%token_count)%value = ')'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      ! Handle braces (for function definitions and command grouping)
      if (ch == '{') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_LBRACE
        self%tokens(self%token_count)%value = '{'
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      if (ch == '}') then
        self%token_count = self%token_count + 1
        self%tokens(self%token_count)%type = TOKEN_RBRACE
        self%tokens(self%token_count)%value = '}'
        self%tokens(self%token_count)%line_number = self%line_number
        self%tokens(self%token_count)%column = self%column
        self%position = self%position + 1
        self%column = self%column + 1
        cycle
      end if

      ! Handle brackets (for conditional expressions)
      if (ch == '[') then
        ! Check for [[ (conditional expression)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '[') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_LBRACKET_DOUBLE
          self%tokens(self%token_count)%value = '[['
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          ! Single bracket - treat as word for now (for test [ ... ])
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_WORD
          self%tokens(self%token_count)%value = '['
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      if (ch == ']') then
        ! Check for ]] (end conditional expression)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == ']') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_RBRACKET_DOUBLE
          self%tokens(self%token_count)%value = ']]'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          ! Single bracket - treat as word for now (for test [ ... ])
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_WORD
          self%tokens(self%token_count)%value = ']'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      ! Handle redirection operators and process substitution
      if (ch == '<') then
        ! Check for process substitution <(...)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '(') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_PROC_SUBST_IN
          self%tokens(self%token_count)%value = '<('
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        ! Check for here document (<<) or here string (<<<)
        else if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '<') then
          ! Check for here string (<<<)
          if (self%position + 1 < self%length .and. &
              self%input(self%position+2:self%position+2) == '<') then
            self%token_count = self%token_count + 1
            self%tokens(self%token_count)%type = TOKEN_REDIRECT_HERE_STRING
            self%tokens(self%token_count)%value = '<<<'
            self%tokens(self%token_count)%line_number = self%line_number
            self%tokens(self%token_count)%column = self%column
            self%position = self%position + 3
            self%column = self%column + 3
          else
            ! Here document (<<)
            self%token_count = self%token_count + 1
            self%tokens(self%token_count)%type = TOKEN_REDIRECT_HERE
            self%tokens(self%token_count)%value = '<<'
            self%tokens(self%token_count)%line_number = self%line_number
            self%tokens(self%token_count)%column = self%column
            self%position = self%position + 2
            self%column = self%column + 2
          end if
        else
          ! Regular input redirection (<)
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_REDIRECT_IN
          self%tokens(self%token_count)%value = '<'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      if (ch == '>') then
        ! Check for process substitution >(...)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '(') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_PROC_SUBST_OUT
          self%tokens(self%token_count)%value = '>('
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        ! Check for append (>>)
        else if (self%position < self%length .and. &
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

      ! Handle exclamation mark (negation or inequality)
      if (ch == '!') then
        ! Check for != operator
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '=') then
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_WORD
          self%tokens(self%token_count)%value = '!='
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 2
          self%column = self%column + 2
        else
          ! Standalone ! (negation)
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_WORD
          self%tokens(self%token_count)%value = '!'
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column
          self%position = self%position + 1
          self%column = self%column + 1
        end if
        cycle
      end if

      ! Handle variable, command substitution, or arithmetic expansion
      if (ch == '$') then
        ! Check for arithmetic expansion $((...)) or command substitution $(...)
        if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '(') then
          ! Check if it's arithmetic expansion $((
          if (self%position + 1 < self%length .and. &
              self%input(self%position+2:self%position+2) == '(') then
            ! Arithmetic expansion
            self%token_count = self%token_count + 1
            self%tokens(self%token_count)%type = TOKEN_ARITH_START
            self%tokens(self%token_count)%value = '$(('
            self%tokens(self%token_count)%line_number = self%line_number
            self%tokens(self%token_count)%column = self%column
            self%position = self%position + 3
            self%column = self%column + 3
          else
            ! Command substitution
            self%token_count = self%token_count + 1
            self%tokens(self%token_count)%type = TOKEN_COMMAND_SUBST_START
            self%tokens(self%token_count)%value = '$('
            self%tokens(self%token_count)%line_number = self%line_number
            self%tokens(self%token_count)%column = self%column
            self%position = self%position + 2
            self%column = self%column + 2
          end if
        else if (self%position < self%length .and. &
            self%input(self%position+1:self%position+1) == '{') then
          ! Parameter expansion ${...}
          self%position = self%position + 2  ! Skip ${
          self%column = self%column + 2

          word = ''
          word_len = 0
          ! Read everything until }
          do while (self%position <= self%length)
            ch = self%input(self%position:self%position)
            if (ch == '}') exit
            word_len = word_len + 1
            word(word_len:word_len) = ch
            self%position = self%position + 1
            self%column = self%column + 1
          end do

          ! Skip the closing }
          if (self%position <= self%length .and. &
              self%input(self%position:self%position) == '}') then
            self%position = self%position + 1
            self%column = self%column + 1
          end if

          ! Create TOKEN_VARIABLE with the full content (e.g., "var:-default")
          self%token_count = self%token_count + 1
          self%tokens(self%token_count)%type = TOKEN_VARIABLE
          self%tokens(self%token_count)%value = word(1:word_len)
          self%tokens(self%token_count)%line_number = self%line_number
          self%tokens(self%token_count)%column = self%column - word_len - 3
        else
          ! Regular variable
          self%position = self%position + 1
          self%column = self%column + 1

          ! Check for special single-character variables
          if (self%position <= self%length) then
            ch = self%input(self%position:self%position)
            if (ch == '#' .or. ch == '?' .or. ch == '$' .or. ch == '!' .or. &
                ch == '@' .or. ch == '*' .or. (ch >= '0' .and. ch <= '9')) then
              ! Special variable - single character
              self%token_count = self%token_count + 1
              self%tokens(self%token_count)%type = TOKEN_VARIABLE
              self%tokens(self%token_count)%value = ch
              self%tokens(self%token_count)%line_number = self%line_number
              self%tokens(self%token_count)%column = self%column - 1
              self%position = self%position + 1
              self%column = self%column + 1
              cycle
            end if
          end if

          ! Regular variable name
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