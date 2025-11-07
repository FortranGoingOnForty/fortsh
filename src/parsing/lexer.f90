! =====================================
! Lexer Module - Phase 1 of Grammar-Aware Parser
! =====================================
! Tokenizes shell input into meaningful units
! Part of the parser rewrite project
!
! Status: PHASE 1 - Full implementation
! Author: Parser Rewrite Team
! Created: 2025-11-05

module lexer
  use iso_fortran_env
  use shell_types
  implicit none
  private

  ! Public interface
  public :: tokenize
  public :: next_token
  public :: peek_token
  public :: is_keyword
  public :: is_operator

  ! Lexer state enumeration
  integer, parameter :: LEX_NORMAL = 1
  integer, parameter :: LEX_IN_SINGLE_QUOTE = 2
  integer, parameter :: LEX_IN_DOUBLE_QUOTE = 3
  integer, parameter :: LEX_IN_WORD = 4
  integer, parameter :: LEX_IN_OPERATOR = 5

contains

  ! =====================================
  ! Character Classification Helpers
  ! =====================================

  pure function is_whitespace(ch) result(is_ws)
    character(len=1), intent(in) :: ch
    logical :: is_ws
    is_ws = (ch == ' ' .or. ch == char(9) .or. ch == char(13))  ! space, tab, CR
  end function is_whitespace

  pure function is_operator_start(ch) result(is_op)
    character(len=1), intent(in) :: ch
    logical :: is_op
    is_op = (ch == '|' .or. ch == '&' .or. ch == ';' .or. &
             ch == '<' .or. ch == '>' .or. ch == '(' .or. ch == ')')
  end function is_operator_start

  pure function is_word_char(ch) result(is_wc)
    character(len=1), intent(in) :: ch
    logical :: is_wc
    ! Word characters: anything that's not whitespace, operator, or special
    is_wc = .not. (is_whitespace(ch) .or. is_operator_start(ch) .or. &
                   ch == char(10) .or. ch == '#' .or. ch == '"' .or. &
                   ch == "'" .or. ch == '\')
  end function is_word_char

  ! =====================================
  ! Operator Recognition
  ! =====================================

  function is_operator(str) result(is_op)
    character(len=*), intent(in) :: str
    logical :: is_op

    select case(trim(str))
    ! Logical operators
    case('&&', '||')
      is_op = .true.
    ! Pipe and background
    case('|', '&')
      is_op = .true.
    ! Separators
    case(';', ';;')
      is_op = .true.
    ! Redirections
    case('<', '>', '>>', '<>', '>&', '<&', '>|', '<<', '<<-', '<<<')
      is_op = .true.
    ! Grouping
    case('(', ')', '{', '}')
      is_op = .true.
    case default
      is_op = .false.
    end select
  end function is_operator

  ! =====================================
  ! is_keyword - Check if word is a shell keyword
  ! =====================================
  function is_keyword(word) result(is_kw)
    character(len=*), intent(in) :: word
    logical :: is_kw

    select case(trim(word))
    ! Control flow keywords
    case('if', 'then', 'else', 'elif', 'fi')
      is_kw = .true.
    case('for', 'in', 'do', 'done')
      is_kw = .true.
    case('while', 'until')
      is_kw = .true.
    case('case', 'esac')
      is_kw = .true.
    ! Other keywords
    case('function', 'select', 'time')
      is_kw = .true.
    case('{', '}')
      is_kw = .true.
    case('!') ! Negation operator (context-dependent)
      is_kw = .true.
    case default
      is_kw = .false.
    end select
  end function is_keyword

  ! =====================================
  ! tokenize - Main entry point for lexical analysis
  ! =====================================
  subroutine tokenize(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    type(token_t), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens

    integer :: pos, input_len, state, token_start
    character(len=1) :: ch, next_ch
    character(len=MAX_TOKEN_LEN) :: current_token
    integer :: token_len
    logical :: in_escape

    num_tokens = 0
    pos = 1
    input_len = len_trim(input)
    state = LEX_NORMAL
    token_start = 1
    current_token = ''
    token_len = 0
    in_escape = .false.

    do while (pos <= input_len .and. num_tokens < size(tokens))
      ch = input(pos:pos)

      ! Get next character for lookahead (if available)
      if (pos < input_len) then
        next_ch = input(pos+1:pos+1)
      else
        next_ch = ' '
      end if

      select case(state)

      ! ============ NORMAL STATE ============
      case(LEX_NORMAL)

        ! Skip whitespace
        if (is_whitespace(ch)) then
          pos = pos + 1
          cycle
        end if

        ! Newline - significant token
        if (ch == char(10)) then
          call add_token(tokens, num_tokens, TOKEN_NEWLINE, char(10), pos, pos, .false.)
          pos = pos + 1
          cycle
        end if

        ! Comments: # to end of line
        if (ch == '#') then
          ! Skip until newline or end of input
          do while (pos <= input_len .and. input(pos:pos) /= char(10))
            pos = pos + 1
          end do
          cycle
        end if

        ! Single quote: literal string
        if (ch == "'") then
          state = LEX_IN_SINGLE_QUOTE
          token_start = pos
          token_len = 0
          current_token = ''
          pos = pos + 1
          cycle
        end if

        ! Double quote: expandable string
        if (ch == '"') then
          state = LEX_IN_DOUBLE_QUOTE
          token_start = pos
          token_len = 0
          current_token = ''
          pos = pos + 1
          cycle
        end if

        ! Backslash escape
        if (ch == '\') then
          if (pos < input_len) then
            ! Start a word token with the escaped character
            state = LEX_IN_WORD
            token_start = pos
            token_len = 1
            current_token = next_ch
            pos = pos + 2  ! Skip backslash and next char
            cycle
          end if
        end if

        ! Multi-character operators
        if (is_operator_start(ch)) then
          state = LEX_IN_OPERATOR
          token_start = pos
          token_len = 1
          current_token = ch
          pos = pos + 1
          cycle
        end if

        ! Check for $( or $(( - these should be kept in word tokens for expansion
        if (ch == '$' .and. pos < input_len .and. next_ch == '(') then
          ! This is command substitution or arithmetic - include in word
          state = LEX_IN_WORD
          token_start = pos
          token_len = 2
          current_token = '$('
          pos = pos + 2
          cycle
        end if

        ! Assignment detection: VAR=value
        ! (This is complex - we'll detect it as WORD and let parser handle it)

        ! Start of word
        state = LEX_IN_WORD
        token_start = pos
        token_len = 1
        current_token = ch
        pos = pos + 1

      ! ============ SINGLE QUOTE STATE ============
      case(LEX_IN_SINGLE_QUOTE)
        if (ch == "'") then
          ! End of single-quoted string
          call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                         token_start, pos, .true.)
          state = LEX_NORMAL
          pos = pos + 1
        else
          ! Add character to token (everything is literal)
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
        end if

      ! ============ DOUBLE QUOTE STATE ============
      case(LEX_IN_DOUBLE_QUOTE)
        if (ch == '\' .and. pos < input_len) then
          ! Backslash escape in double quotes (only for $, `, ", \, newline)
          if (next_ch == '$' .or. next_ch == '`' .or. next_ch == '"' .or. &
              next_ch == '\' .or. next_ch == char(10)) then
            ! Add escaped character
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = next_ch
            end if
            pos = pos + 2
          else
            ! Backslash is literal
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          end if
        else if (ch == '"') then
          ! End of double-quoted string
          call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                         token_start, pos, .true.)
          state = LEX_NORMAL
          pos = pos + 1
        else
          ! Add character to token
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
        end if

      ! ============ WORD STATE ============
      case(LEX_IN_WORD)
        if (ch == '\' .and. pos < input_len) then
          ! Backslash escape in word
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = next_ch
          end if
          pos = pos + 2
        else if (ch == "'" .or. ch == '"') then
          ! Quote in middle of word - need to handle this specially
          ! For now, end the word and let the quote start a new token
          call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                  token_start, pos-1, .false.)
          state = LEX_NORMAL
          ! Don't increment pos, let NORMAL state handle the quote
        else if (ch == '#') then
          ! # is normally comment, but in $# it's part of variable
          ! Keep it if current token is just $
          if (token_len == 1 .and. current_token(1:1) == '$') then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
            pos = pos + 1
          else
            ! End word, let # start a comment
            call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                    token_start, pos-1, .false.)
            state = LEX_NORMAL
          end if
        else if ((ch >= '0' .and. ch <= '9') .or. ch == '+' .or. ch == '-' .or. &
                 ch == '*' .or. ch == '/' .or. ch == '%') then
          ! Keep these chars in word (for variables and arithmetic)
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
        else if (ch == '(' .or. ch == ')') then
          ! Parentheses: Keep ONLY if inside $(( or $(
          ! Check if current token starts with $(
          if (token_len >= 2 .and. current_token(1:2) == '$(') then
            ! Inside command/arithmetic substitution - keep parens
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          else
            ! Not in substitution - end word, let paren be operator
            call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                    token_start, pos-1, .false.)
            state = LEX_NORMAL
          end if
        else if (is_word_char(ch)) then
          ! Continue word
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
        else
          ! End of word
          call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                  token_start, pos-1, .false.)
          state = LEX_NORMAL
          ! Don't increment pos, let NORMAL state handle this character
        end if

      ! ============ OPERATOR STATE ============
      case(LEX_IN_OPERATOR)
        ! Try to match multi-character operators
        if (token_len == 1) then
          select case(current_token(1:1))
          case('&')
            if (ch == '&') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_OPERATOR, '&&', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else
              call add_token(tokens, num_tokens, TOKEN_OPERATOR, '&', token_start, pos-1, .false.)
              state = LEX_NORMAL
            end if
          case('|')
            if (ch == '|') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_OPERATOR, '||', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else
              call add_token(tokens, num_tokens, TOKEN_OPERATOR, '|', token_start, pos-1, .false.)
              state = LEX_NORMAL
            end if
          case('>')
            if (ch == '>') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '>>', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else if (ch == '&') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '>&', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else if (ch == '|') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '>|', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '>', token_start, pos-1, .false.)
              state = LEX_NORMAL
            end if
          case('<')
            if (ch == '<') then
              ! Could be << or <<< or <<-
              if (pos < input_len .and. next_ch == '<') then
                current_token(2:3) = '<<'
                token_len = 3
                call add_token(tokens, num_tokens, TOKEN_REDIRECT, '<<<', token_start, pos+1, .false.)
                state = LEX_NORMAL
                pos = pos + 2
              else if (pos < input_len .and. next_ch == '-') then
                current_token(2:3) = '<-'
                token_len = 3
                call add_token(tokens, num_tokens, TOKEN_REDIRECT, '<<-', token_start, pos+1, .false.)
                state = LEX_NORMAL
                pos = pos + 2
              else
                current_token(2:2) = ch
                token_len = 2
                call add_token(tokens, num_tokens, TOKEN_REDIRECT, '<<', token_start, pos, .false.)
                state = LEX_NORMAL
                pos = pos + 1
              end if
            else if (ch == '>') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '<>', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else if (ch == '&') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '<&', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else
              call add_token(tokens, num_tokens, TOKEN_REDIRECT, '<', token_start, pos-1, .false.)
              state = LEX_NORMAL
            end if
          case(';')
            if (ch == ';') then
              current_token(2:2) = ch
              token_len = 2
              call add_token(tokens, num_tokens, TOKEN_OPERATOR, ';;', token_start, pos, .false.)
              state = LEX_NORMAL
              pos = pos + 1
            else
              call add_token(tokens, num_tokens, TOKEN_OPERATOR, ';', token_start, pos-1, .false.)
              state = LEX_NORMAL
            end if
          case('(', ')')
            call add_token(tokens, num_tokens, TOKEN_OPERATOR, current_token(1:1), &
                          token_start, pos-1, .false.)
            state = LEX_NORMAL
          case default
            ! Single-character operator
            call add_token(tokens, num_tokens, TOKEN_OPERATOR, current_token(1:1), &
                          token_start, pos-1, .false.)
            state = LEX_NORMAL
          end select
        else
          ! Multi-character operator complete
          state = LEX_NORMAL
        end if

      end select
    end do

    ! Flush any remaining token
    if (state == LEX_IN_WORD .and. token_len > 0) then
      call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                              token_start, input_len, .false.)
    else if (state == LEX_IN_SINGLE_QUOTE .or. state == LEX_IN_DOUBLE_QUOTE) then
      ! Unterminated quote - add as word with error marker
      call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                    token_start, input_len, .true.)
    else if (state == LEX_IN_OPERATOR .and. token_len > 0) then
      ! Flush operator
      call add_token(tokens, num_tokens, TOKEN_OPERATOR, current_token(1:token_len), &
                    token_start, input_len, .false.)
    end if

    ! Add EOF token
    call add_token(tokens, num_tokens, TOKEN_EOF, '', input_len+1, input_len+1, .false.)

  end subroutine tokenize

  ! =====================================
  ! Helper: Add token to array
  ! =====================================
  subroutine add_token(tokens, num_tokens, tok_type, value, start_pos, end_pos, quoted)
    type(token_t), intent(inout) :: tokens(:)
    integer, intent(inout) :: num_tokens
    integer, intent(in) :: tok_type, start_pos, end_pos
    character(len=*), intent(in) :: value
    logical, intent(in) :: quoted

    if (num_tokens < size(tokens)) then
      num_tokens = num_tokens + 1
      tokens(num_tokens)%token_type = tok_type
      tokens(num_tokens)%value = value
      tokens(num_tokens)%start_pos = start_pos
      tokens(num_tokens)%end_pos = end_pos
      tokens(num_tokens)%quoted = quoted
    end if
  end subroutine add_token

  ! =====================================
  ! Helper: Add word or keyword token
  ! =====================================
  subroutine add_word_or_keyword(tokens, num_tokens, value, start_pos, end_pos, quoted)
    type(token_t), intent(inout) :: tokens(:)
    integer, intent(inout) :: num_tokens
    character(len=*), intent(in) :: value
    integer, intent(in) :: start_pos, end_pos
    logical, intent(in) :: quoted

    integer :: tok_type

    ! Quoted strings are always words, never keywords
    if (quoted) then
      tok_type = TOKEN_WORD
    else if (is_keyword(value)) then
      tok_type = TOKEN_KEYWORD
    else
      tok_type = TOKEN_WORD
    end if

    call add_token(tokens, num_tokens, tok_type, value, start_pos, end_pos, quoted)
  end subroutine add_word_or_keyword

  ! =====================================
  ! next_token - Get next token from stream
  ! =====================================
  function next_token(tokens, pos) result(tok)
    type(token_t), intent(in) :: tokens(:)
    integer, intent(inout) :: pos
    type(token_t) :: tok

    if (pos <= size(tokens) .and. pos > 0) then
      tok = tokens(pos)
      pos = pos + 1
    else
      ! Return EOF token
      tok%token_type = TOKEN_EOF
      tok%value = ''
      tok%start_pos = 0
      tok%end_pos = 0
      tok%quoted = .false.
    end if
  end function next_token

  ! =====================================
  ! peek_token - Look ahead without consuming
  ! =====================================
  function peek_token(tokens, pos) result(tok)
    type(token_t), intent(in) :: tokens(:)
    integer, intent(in) :: pos
    type(token_t) :: tok

    if (pos <= size(tokens) .and. pos > 0) then
      tok = tokens(pos)
    else
      ! Return EOF token
      tok%token_type = TOKEN_EOF
      tok%value = ''
      tok%start_pos = 0
      tok%end_pos = 0
      tok%quoted = .false.
    end if
  end function peek_token

end module lexer
