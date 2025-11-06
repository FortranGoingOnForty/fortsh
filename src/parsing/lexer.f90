! =====================================
! Lexer Module - Phase 1 of Grammar-Aware Parser
! =====================================
! Tokenizes shell input into meaningful units
! Part of the parser rewrite project
!
! Status: PHASE 0 - Skeleton only, delegates to old parser
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

contains

  ! =====================================
  ! tokenize - Main entry point for lexical analysis
  ! =====================================
  ! Breaks input string into tokens
  ! Phase 0: Stub implementation
  subroutine tokenize(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    type(token_t), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens

    ! Phase 0: Stub - just return empty
    ! Phase 1: Will implement actual tokenization
    num_tokens = 0

    ! Prevent unused variable warnings
    if (len(input) > 0) then
      ! Do nothing, just reference it
    end if
    if (size(tokens) > 0) then
      ! Do nothing, just reference it
    end if
  end subroutine tokenize

  ! =====================================
  ! next_token - Get next token from stream
  ! =====================================
  ! Phase 0: Stub
  function next_token(tokens, pos) result(tok)
    type(token_t), intent(in) :: tokens(:)
    integer, intent(inout) :: pos
    type(token_t) :: tok

    ! Phase 0: Return EOF token
    tok%token_type = TOKEN_EOF
    tok%value = ''
    tok%start_pos = pos
    tok%end_pos = pos
    tok%quoted = .false.

    ! Prevent unused warning
    if (size(tokens) > 0) then
      ! Do nothing
    end if
  end function next_token

  ! =====================================
  ! peek_token - Look ahead without consuming
  ! =====================================
  ! Phase 0: Stub
  function peek_token(tokens, pos) result(tok)
    type(token_t), intent(in) :: tokens(:)
    integer, intent(in) :: pos
    type(token_t) :: tok

    ! Phase 0: Return EOF token
    tok%token_type = TOKEN_EOF
    tok%value = ''
    tok%start_pos = pos
    tok%end_pos = pos
    tok%quoted = .false.

    ! Prevent unused warning
    if (size(tokens) > 0) then
      ! Do nothing
    end if
  end function peek_token

  ! =====================================
  ! is_keyword - Check if word is a shell keyword
  ! =====================================
  ! This is simple enough to implement now
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

end module lexer
