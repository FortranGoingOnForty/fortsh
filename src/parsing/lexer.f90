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
  use shell_types, only: QUOTE_NONE, QUOTE_SINGLE, QUOTE_DOUBLE
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

  ! Context tracking for [[ ]] test expressions
  ! Inside [[ ]], && || < > are test operators, not shell operators
  logical :: in_double_bracket_context = .false.

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
    case('function', 'select', 'time', 'coproc')
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
    integer :: token_len, paren_depth
    logical :: in_escape, continuing_word, token_has_quoted_part

    num_tokens = 0
    pos = 1
    input_len = len_trim(input)
    state = LEX_NORMAL
    token_start = 1
    current_token = ''
    token_len = 0
    in_escape = .false.
    paren_depth = 0
    continuing_word = .false.
    token_has_quoted_part = .false.
    in_double_bracket_context = .false.

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
          ! Only reset token if we're NOT continuing a word
          if (.not. continuing_word) then
            token_start = pos
            token_len = 0
            current_token = ''
          end if
          pos = pos + 1
          cycle
        end if

        ! Double quote: expandable string
        if (ch == '"') then
          state = LEX_IN_DOUBLE_QUOTE
          ! Only reset token if we're NOT continuing a word
          if (.not. continuing_word) then
            token_start = pos
            token_len = 0
            current_token = ''
          end if
          pos = pos + 1
          cycle
        end if

        ! Backslash escape
        if (ch == '\') then
          if (pos < input_len) then
            ! Start a word token with the escaped character
            state = LEX_IN_WORD
            token_start = pos
            in_escape = .true.  ! Mark this token as escaped
            ! For characters that would trigger expansion ($, `, etc), preserve backslash
            ! so the expansion phase knows not to expand them
            if (next_ch == '$' .or. next_ch == '`') then
              token_len = 2
              current_token(1:2) = '\' // next_ch
            else
              token_len = 1
              current_token = next_ch
            end if
            pos = pos + 2  ! Skip backslash and next char
            cycle
          end if
        end if

        ! Multi-character operators
        ! Inside [[ ]], treat & | < > ( ) as word characters (test operators)
        if (in_double_bracket_context .and. &
            (ch == '&' .or. ch == '|' .or. ch == '<' .or. ch == '>' .or. &
             ch == '(' .or. ch == ')')) then
          state = LEX_IN_WORD
          token_start = pos
          token_len = 1
          current_token = ch
          pos = pos + 1
          cycle
        end if
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
          paren_depth = 1  ! Track that we're inside $(
          pos = pos + 2
          cycle
        end if

        ! Check for ${ - parameter expansion should be kept in word tokens
        if (ch == '$' .and. pos < input_len .and. next_ch == '{') then
          ! This is parameter expansion - include in word
          state = LEX_IN_WORD
          token_start = pos
          token_len = 2
          current_token = '${'
          paren_depth = 1  ! Track that we're inside ${
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
          ! Add sentinel char(3) to mark end of single-quoted literal
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = char(3)
          end if
          pos = pos + 1  ! Move past closing quote
          ! Check if next character continues the word (adjacent quote, word char, or escape)
          if (pos <= input_len) then
            next_ch = input(pos:pos)
            if (next_ch == "'" .or. next_ch == '"') then
              ! Adjacent quote follows - continue building this token
              state = LEX_IN_WORD
              continuing_word = .false.
              cycle
            else if (next_ch == '\') then
              ! Backslash escape follows - continue building this token
              state = LEX_IN_WORD
              continuing_word = .false.
              cycle
            else if (is_word_char(next_ch)) then
              ! Word character follows - continue building this token
              state = LEX_IN_WORD
              continuing_word = .false.
              cycle
            end if
          end if
          ! No adjacent quote or word char - finalize token
          if (continuing_word) then
            ! We're building a multi-part word - go back to LEX_IN_WORD
            state = LEX_IN_WORD
            continuing_word = .false.
          else
            ! Standalone quoted string - emit token
            call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                           token_start, pos-1, .true., quote_type=QUOTE_SINGLE)
            state = LEX_NORMAL
          end if
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
          if (next_ch == '$' .or. next_ch == '`') then
            ! For \$ and \` - keep BOTH chars so expansion can see the escape
            if (token_len < MAX_TOKEN_LEN - 1) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
              token_len = token_len + 1
              current_token(token_len:token_len) = next_ch
            end if
            pos = pos + 2
          else if (next_ch == '"' .or. next_ch == '\' .or. next_ch == char(10)) then
            ! For \" and \\ and \newline - add only escaped character
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
        else if (ch == '$' .and. pos < input_len .and. next_ch == '(') then
          ! Command substitution inside double quotes - need to find matching )
          ! while ignoring quotes inside $()
          if (token_len < MAX_TOKEN_LEN - 1) then
            token_len = token_len + 1
            current_token(token_len:token_len) = '$'
            token_len = token_len + 1
            current_token(token_len:token_len) = '('
          end if
          pos = pos + 2
          paren_depth = 1
          ! Scan to find matching ), respecting nested parens and quotes
          do while (pos <= input_len .and. paren_depth > 0)
            ch = input(pos:pos)
            if (ch == '"') then
              ! Skip double-quoted string inside command substitution
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = ch
              end if
              pos = pos + 1
              do while (pos <= input_len)
                ch = input(pos:pos)
                if (ch == '\' .and. pos < input_len) then
                  ! Skip escaped char
                  if (token_len < MAX_TOKEN_LEN - 1) then
                    token_len = token_len + 1
                    current_token(token_len:token_len) = ch
                    token_len = token_len + 1
                    current_token(token_len:token_len) = input(pos+1:pos+1)
                  end if
                  pos = pos + 2
                else if (ch == '"') then
                  if (token_len < MAX_TOKEN_LEN) then
                    token_len = token_len + 1
                    current_token(token_len:token_len) = ch
                  end if
                  pos = pos + 1
                  exit
                else
                  if (token_len < MAX_TOKEN_LEN) then
                    token_len = token_len + 1
                    current_token(token_len:token_len) = ch
                  end if
                  pos = pos + 1
                end if
              end do
            else if (ch == "'") then
              ! Skip single-quoted string
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = ch
              end if
              pos = pos + 1
              do while (pos <= input_len .and. input(pos:pos) /= "'")
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = input(pos:pos)
                end if
                pos = pos + 1
              end do
              if (pos <= input_len) then
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = "'"
                end if
                pos = pos + 1
              end if
            else if (ch == '(') then
              paren_depth = paren_depth + 1
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = ch
              end if
              pos = pos + 1
            else if (ch == ')') then
              paren_depth = paren_depth - 1
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = ch
              end if
              pos = pos + 1
            else
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = ch
              end if
              pos = pos + 1
            end if
          end do
        else if (ch == '"') then
          ! End of double-quoted string
          pos = pos + 1  ! Move past closing quote
          ! Check if next character continues the word (adjacent quote, word char, or escape)
          if (pos <= input_len) then
            next_ch = input(pos:pos)
            if (next_ch == "'" .or. next_ch == '"') then
              ! Adjacent quote follows - continue building this token
              ! Add sentinel to mark quote boundary (so expansion knows where quoted part ends)
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = char(1)  ! ASCII SOH as sentinel
              end if
              state = LEX_IN_WORD
              continuing_word = .false.
              cycle
            else if (next_ch == '\') then
              ! Backslash escape follows - continue building this token
              ! Add sentinel to mark quote boundary
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = char(1)  ! ASCII SOH as sentinel
              end if
              state = LEX_IN_WORD
              continuing_word = .false.
              cycle
            else if (is_word_char(next_ch)) then
              ! Word character follows - continue building this token
              ! Add sentinel to mark quote boundary (so expansion knows where quoted part ends)
              if (token_len < MAX_TOKEN_LEN) then
                token_len = token_len + 1
                current_token(token_len:token_len) = char(1)  ! ASCII SOH as sentinel
              end if
              state = LEX_IN_WORD
              continuing_word = .false.
              cycle
            end if
          end if
          ! No adjacent quote or word char - finalize token
          if (continuing_word) then
            ! We're building a multi-part word - go back to LEX_IN_WORD
            state = LEX_IN_WORD
            continuing_word = .false.
          else
            ! Standalone quoted string - emit token
            call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                           token_start, pos-1, .true., quote_type=QUOTE_DOUBLE)
            state = LEX_NORMAL
          end if
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
        ! Check if we're inside $() - if so, keep EVERYTHING including spaces
        ! IMPORTANT: Also check paren_depth > 0 to ensure we're actually inside the $()
        if (index(current_token(1:token_len), '$(') > 0 .and. paren_depth > 0) then
          ! Inside command substitution - track paren depth
          if (ch == '(') then
            paren_depth = paren_depth + 1
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          else if (ch == ')') then
            paren_depth = paren_depth - 1
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
            ! If paren_depth hits 0, we closed the $(...)
            if (paren_depth == 0) then
              ! End of command substitution - finish token
              call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                      token_start, pos-1, token_has_quoted_part, in_escape)
              state = LEX_NORMAL
              in_escape = .false.
              token_has_quoted_part = .false.
            end if
          else
            ! Inside $() - keep EVERYTHING including spaces
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          end if
        ! Check if we're inside ${ - if so, keep EVERYTHING until closing }
        ! IMPORTANT: Also check paren_depth > 0 to ensure we're actually inside the ${}
        else if (index(current_token(1:token_len), '${') > 0 .and. paren_depth > 0) then
          ! Inside parameter expansion - track brace depth
          if (ch == '{') then
            paren_depth = paren_depth + 1
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          else if (ch == '}') then
            paren_depth = paren_depth - 1
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
            ! If paren_depth hits 0, we closed the ${...}
            if (paren_depth == 0) then
              ! Check if next character continues the word (e.g., ${A}${B})
              ! Don't end token if next char is $ or other word character
              if (pos <= input_len) then
                next_ch = input(pos:pos)
                ! If next character starts a new expansion or is alphanumeric, continue token
                if (next_ch == '$' .or. next_ch == '{' .or. &
                    (next_ch >= 'a' .and. next_ch <= 'z') .or. &
                    (next_ch >= 'A' .and. next_ch <= 'Z') .or. &
                    (next_ch >= '0' .and. next_ch <= '9') .or. &
                    next_ch == '_' .or. next_ch == '-' .or. next_ch == '.') then
                  ! Continue building the same token - don't end it yet
                  ! state stays LEX_WORD
                else
                  ! End of parameter expansion - finish token
                  call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                          token_start, pos-1, token_has_quoted_part, in_escape)
                  state = LEX_NORMAL
                  in_escape = .false.
                  token_has_quoted_part = .false.
                end if
              else
                ! End of input - finish token
                call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                        token_start, pos-1, token_has_quoted_part, in_escape)
                state = LEX_NORMAL
                in_escape = .false.
                token_has_quoted_part = .false.
              end if
            end if
          else
            ! Inside ${ - keep EVERYTHING including spaces
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          end if
        else if (ch == '\' .and. pos < input_len) then
          ! Backslash escape in word
          ! For expansion-triggering chars, preserve backslash
          if (next_ch == '$' .or. next_ch == '`') then
            if (token_len < MAX_TOKEN_LEN - 1) then
              token_len = token_len + 1
              current_token(token_len:token_len) = '\'
              token_len = token_len + 1
              current_token(token_len:token_len) = next_ch
            end if
          else
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = next_ch
            end if
          end if
          pos = pos + 2
        else if (ch == "'" .or. ch == '"') then
          ! Quote in middle of word - continue building the same token
          ! Mark that we're continuing a word so quote handler doesn't reset the token
          continuing_word = .true.
          token_has_quoted_part = .true.  ! Track that this word contains quoted content
          ! Transition to appropriate quote state
          if (ch == "'") then
            ! Add sentinel char(2) to mark start of single-quoted literal (no expansion)
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = char(2)
            end if
            state = LEX_IN_SINGLE_QUOTE
          else
            state = LEX_IN_DOUBLE_QUOTE
          end if
          pos = pos + 1  ! Skip the opening quote
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
                                    token_start, pos-1, token_has_quoted_part, in_escape)
            state = LEX_NORMAL
            in_escape = .false.
            token_has_quoted_part = .false.
          end if
        else if (ch == '$' .and. pos < input_len .and. next_ch == '(') then
          ! $( for command/arithmetic substitution - keep in word
          if (token_len < MAX_TOKEN_LEN - 1) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
            token_len = token_len + 1
            current_token(token_len:token_len) = next_ch
            paren_depth = 1  ! Track that we're inside $(
          end if
          pos = pos + 2
        else if (ch == '$' .and. pos < input_len .and. next_ch == '{') then
          ! ${ for parameter expansion - keep in word
          if (token_len < MAX_TOKEN_LEN - 1) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
            token_len = token_len + 1
            current_token(token_len:token_len) = next_ch
            paren_depth = 1  ! Track that we're inside ${
          end if
          pos = pos + 2
        else if ((ch >= '0' .and. ch <= '9') .or. ch == '+' .or. ch == '-' .or. &
                 ch == '*' .or. ch == '/' .or. ch == '%') then
          ! Keep these chars in word (for variables and arithmetic)
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
        else if (ch == '(' .or. ch == ')') then
          ! Inside [[ ]], keep parens as part of word (regex patterns, grouping)
          if (in_double_bracket_context) then
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          ! Parentheses: Keep ONLY if inside $(( or $(
          ! Check if current token ends with $ (for x=$(cmd) or just $(cmd))
          ! NOTE: Only for '(' - ')' after $ (like $$) should end the word
          else if (ch == '(' .and. token_len >= 1 .and. current_token(token_len:token_len) == '$') then
            ! Just added $, now seeing ( - this is $( substitution - keep both
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          else if (token_len >= 2 .and. index(current_token(1:token_len), '$(') > 0) then
            ! Already inside $(...) - keep parens
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = ch
            end if
            pos = pos + 1
          else if (ch == '(' .and. token_len >= 1 .and. &
                   current_token(token_len:token_len) == '=') then
            ! Array assignment: VAR=(...) - include the parenthesized content
            ! Scan for matching ) respecting quotes and nested parens
            if (token_len < MAX_TOKEN_LEN) then
              token_len = token_len + 1
              current_token(token_len:token_len) = '('
            end if
            pos = pos + 1
            paren_depth = 1
            do while (pos <= input_len .and. paren_depth > 0)
              ch = input(pos:pos)
              if (ch == '"') then
                ! Skip double-quoted string
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = ch
                end if
                pos = pos + 1
                do while (pos <= input_len .and. input(pos:pos) /= '"')
                  if (input(pos:pos) == '\' .and. pos < input_len) then
                    if (token_len < MAX_TOKEN_LEN - 1) then
                      token_len = token_len + 1
                      current_token(token_len:token_len) = input(pos:pos)
                      token_len = token_len + 1
                      current_token(token_len:token_len) = input(pos+1:pos+1)
                    end if
                    pos = pos + 2
                  else
                    if (token_len < MAX_TOKEN_LEN) then
                      token_len = token_len + 1
                      current_token(token_len:token_len) = input(pos:pos)
                    end if
                    pos = pos + 1
                  end if
                end do
                if (pos <= input_len) then
                  if (token_len < MAX_TOKEN_LEN) then
                    token_len = token_len + 1
                    current_token(token_len:token_len) = '"'
                  end if
                  pos = pos + 1
                end if
              else if (ch == "'") then
                ! Skip single-quoted string
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = ch
                end if
                pos = pos + 1
                do while (pos <= input_len .and. input(pos:pos) /= "'")
                  if (token_len < MAX_TOKEN_LEN) then
                    token_len = token_len + 1
                    current_token(token_len:token_len) = input(pos:pos)
                  end if
                  pos = pos + 1
                end do
                if (pos <= input_len) then
                  if (token_len < MAX_TOKEN_LEN) then
                    token_len = token_len + 1
                    current_token(token_len:token_len) = "'"
                  end if
                  pos = pos + 1
                end if
              else if (ch == '(') then
                paren_depth = paren_depth + 1
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = ch
                end if
                pos = pos + 1
              else if (ch == ')') then
                paren_depth = paren_depth - 1
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = ch
                end if
                pos = pos + 1
              else
                if (token_len < MAX_TOKEN_LEN) then
                  token_len = token_len + 1
                  current_token(token_len:token_len) = ch
                end if
                pos = pos + 1
              end if
            end do
            ! Token complete with closing )
            call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                    token_start, pos-1, token_has_quoted_part, in_escape)
            state = LEX_NORMAL
            in_escape = .false.
            token_has_quoted_part = .false.
          else
            ! Not in substitution - end word, let paren be operator
            call add_word_or_keyword(tokens, num_tokens, current_token(1:token_len), &
                                    token_start, pos-1, token_has_quoted_part, in_escape)
            state = LEX_NORMAL
            in_escape = .false.
            token_has_quoted_part = .false.
          end if
        else if (ch == '{' .or. ch == '}') then
          ! Braces: Keep in word for brace expansion (e.g., {1,2,3} or file{a,b}.txt)
          ! They're only command group operators when surrounded by whitespace
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
        else if (in_double_bracket_context .and. &
                 (ch == '&' .or. ch == '|' .or. ch == '<' .or. ch == '>' .or. &
                  ch == '(' .or. ch == ')')) then
          ! Inside [[ ]], these are test operators, not shell operators
          if (token_len < MAX_TOKEN_LEN) then
            token_len = token_len + 1
            current_token(token_len:token_len) = ch
          end if
          pos = pos + 1
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
                                  token_start, pos-1, token_has_quoted_part, in_escape)
          state = LEX_NORMAL
          in_escape = .false.
          token_has_quoted_part = .false.
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
                              token_start, input_len, token_has_quoted_part, in_escape)
    else if (state == LEX_IN_SINGLE_QUOTE .or. state == LEX_IN_DOUBLE_QUOTE) then
      ! Unterminated quote - add as word with error marker
      if (state == LEX_IN_SINGLE_QUOTE) then
        call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                    token_start, input_len, .true., quote_type=QUOTE_SINGLE)
      else
        call add_token(tokens, num_tokens, TOKEN_WORD, current_token(1:token_len), &
                    token_start, input_len, .true., quote_type=QUOTE_DOUBLE)
      end if
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
  subroutine add_token(tokens, num_tokens, tok_type, value, start_pos, end_pos, quoted, escaped, quote_type)
    use shell_types, only: QUOTE_NONE
    type(token_t), intent(inout) :: tokens(:)
    integer, intent(inout) :: num_tokens
    integer, intent(in) :: tok_type, start_pos, end_pos
    character(len=*), intent(in) :: value
    logical, intent(in) :: quoted
    logical, intent(in), optional :: escaped
    integer, intent(in), optional :: quote_type

    if (num_tokens < size(tokens)) then
      num_tokens = num_tokens + 1
      tokens(num_tokens)%token_type = tok_type
      tokens(num_tokens)%value = value
      tokens(num_tokens)%value_length = len(value)  ! Store actual content length
      tokens(num_tokens)%start_pos = start_pos
      tokens(num_tokens)%end_pos = end_pos
      tokens(num_tokens)%quoted = quoted
      if (present(escaped)) then
        tokens(num_tokens)%escaped = escaped
      else
        tokens(num_tokens)%escaped = .false.
      end if
      if (present(quote_type)) then
        tokens(num_tokens)%quote_type = quote_type
      else
        tokens(num_tokens)%quote_type = QUOTE_NONE
      end if
    end if
  end subroutine add_token

  ! =====================================
  ! Helper: Add word or keyword token
  ! =====================================
  subroutine add_word_or_keyword(tokens, num_tokens, value, start_pos, end_pos, quoted, escaped)
    type(token_t), intent(inout) :: tokens(:)
    integer, intent(inout) :: num_tokens
    character(len=*), intent(in) :: value
    integer, intent(in) :: start_pos, end_pos
    logical, intent(in) :: quoted
    logical, intent(in), optional :: escaped

    integer :: tok_type

    ! Quoted strings are always words, never keywords
    if (quoted) then
      tok_type = TOKEN_WORD
    else if (is_keyword(value)) then
      tok_type = TOKEN_KEYWORD
    else
      tok_type = TOKEN_WORD
    end if

    ! Track [[ ]] context: inside test expressions, operators become words
    if (.not. quoted) then
      if (trim(value) == '[[') in_double_bracket_context = .true.
      if (trim(value) == ']]') in_double_bracket_context = .false.
    end if

    call add_token(tokens, num_tokens, tok_type, value, start_pos, end_pos, quoted, escaped)
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
