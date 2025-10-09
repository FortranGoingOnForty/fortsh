! ==============================================================================
! Simple test for AST modules without dependencies
! ==============================================================================
program test_ast_simple
  use ast_types
  use lexer
  implicit none

  call test_lexer()
  call test_token_types()

contains

  subroutine test_lexer()
    type(lexer_t) :: lex
    character(:), allocatable :: input
    integer :: i

    print *, "=== Lexer Test ==="

    ! Test 1: Simple command
    input = 'echo "Hello World"'
    call lex%init(input)
    call lex%tokenize()

    print *, "Input: ", input
    print *, "Tokens: ", lex%token_count
    do i = 1, lex%token_count
      print '(a,i2,a,a,a)', "  [", lex%tokens(i)%type, "] ", &
            trim(lex%tokens(i)%value), &
            get_token_name(lex%tokens(i)%type)
    end do
    print *, ""

    call lex%destroy()

    ! Test 2: For loop
    input = 'for i in 1 2 3; do echo $i; done'
    call lex%init(input)
    call lex%tokenize()

    print *, "Input: ", input
    print *, "Tokens: ", lex%token_count
    do i = 1, lex%token_count
      print '(a,i2,a,a,a)', "  [", lex%tokens(i)%type, "] ", &
            trim(lex%tokens(i)%value), &
            get_token_name(lex%tokens(i)%type)
    end do
    print *, ""

    call lex%destroy()

    ! Test 3: Pipeline
    input = 'cat file.txt | grep pattern | wc -l'
    call lex%init(input)
    call lex%tokenize()

    print *, "Input: ", input
    print *, "Tokens: ", lex%token_count
    do i = 1, lex%token_count
      print '(a,i2,a,a,a)', "  [", lex%tokens(i)%type, "] ", &
            trim(lex%tokens(i)%value), &
            get_token_name(lex%tokens(i)%type)
    end do
    print *, ""

    call lex%destroy()

    ! Test 4: Redirections
    input = 'echo test > output.txt 2>&1'
    call lex%init(input)
    call lex%tokenize()

    print *, "Input: ", input
    print *, "Tokens: ", lex%token_count
    do i = 1, lex%token_count
      print '(a,i2,a,a,a)', "  [", lex%tokens(i)%type, "] ", &
            trim(lex%tokens(i)%value), &
            get_token_name(lex%tokens(i)%type)
    end do
    print *, ""

    call lex%destroy()
  end subroutine test_lexer

  subroutine test_token_types()
    print *, "=== Token Type Test ==="
    print *, "Keywords are recognized:"
    print *, "  'for' -> ", is_keyword('for')
    print *, "  'if' -> ", is_keyword('if')
    print *, "  'echo' -> ", is_keyword('echo')
    print *, "  'break' -> ", is_keyword('break')
    print *, ""

    print *, "Token types for keywords:"
    print *, "  'for' -> ", keyword_token_type('for'), " (should be ", TOKEN_FOR, ")"
    print *, "  'done' -> ", keyword_token_type('done'), " (should be ", TOKEN_DONE, ")"
    print *, "  'break' -> ", keyword_token_type('break'), " (should be ", TOKEN_BREAK, ")"
    print *, ""
  end subroutine test_token_types

  function get_token_name(token_type) result(name)
    integer, intent(in) :: token_type
    character(20) :: name

    select case(token_type)
    case(TOKEN_EOF);        name = ' (EOF)'
    case(TOKEN_WORD);       name = ' (WORD)'
    case(TOKEN_STRING);     name = ' (STRING)'
    case(TOKEN_VARIABLE);   name = ' (VAR)'
    case(TOKEN_SEMICOLON);  name = ' (;)'
    case(TOKEN_NEWLINE);    name = ' (NEWLINE)'
    case(TOKEN_PIPE);       name = ' (|)'
    case(TOKEN_AND);        name = ' (&&)'
    case(TOKEN_OR);         name = ' (||)'
    case(TOKEN_BACKGROUND); name = ' (&)'
    case(TOKEN_REDIRECT_IN);     name = ' (<)'
    case(TOKEN_REDIRECT_OUT);    name = ' (>)'
    case(TOKEN_REDIRECT_APPEND); name = ' (>>)'
    case(TOKEN_FOR);        name = ' (FOR)'
    case(TOKEN_IN);         name = ' (IN)'
    case(TOKEN_DO);         name = ' (DO)'
    case(TOKEN_DONE);       name = ' (DONE)'
    case(TOKEN_IF);         name = ' (IF)'
    case(TOKEN_THEN);       name = ' (THEN)'
    case(TOKEN_ELSE);       name = ' (ELSE)'
    case(TOKEN_FI);         name = ' (FI)'
    case(TOKEN_BREAK);      name = ' (BREAK)'
    case(TOKEN_CONTINUE);   name = ' (CONTINUE)'
    case default;           name = ' (?)'
    end select
  end function get_token_name

end program test_ast_simple