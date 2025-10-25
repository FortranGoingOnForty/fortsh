! ==============================================================================
! Debug test for built-in commands
! ==============================================================================
program test_builtins_debug
  use ast_types_enhanced
  use shell_types
  use lexer_simple
  use parser_enhanced
  use evaluator_simple_real
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_simple_real_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code, i

  print *, "=== Debug Testing Built-in Commands ==="
  print *, ""

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  call getcwd(shell%cwd)
  shell%is_interactive = .false.
  shell%running = .true.
  shell%last_exit_status = 0
  shell%num_variables = 0
  shell%control_depth = 0

  ! Test setting and getting variables
  print *, "Test: Setting MYVAR=hello with set"
  input = 'set MYVAR=hello'

  call lex%init(input)
  call lex%tokenize()

  ! Show tokens
  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i15,a,a,a,a,a)', "  Token ", i, ": type=", trim(token_type_str(lex%tokens(i)%type)), &
                          ", text='", trim(lex%tokens(i)%value), "'"
  end do

  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  ! Show shell variables
  print *, "Shell variables after set:"
  do i = 1, shell%num_variables
    print '(a,a,a,a)', "  ", trim(shell%variables(i)%name), "=", trim(shell%variables(i)%value)
  end do
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Now echo the variable
  print *, "Test: echo $MYVAR"
  input = 'echo $MYVAR'

  call lex%init(input)
  call lex%tokenize()

  ! Show tokens
  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i15,a,i15,a,a,a,a,a)', "  Token ", i, ": type=", lex%tokens(i)%type, &
                              " (", trim(token_type_str(lex%tokens(i)%type)), &
                              "), text='", trim(lex%tokens(i)%value), "'"
  end do

  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test source with explicit path
  print *, "Test: source with /tmp/test_source.sh"

  ! Create test file
  call execute_command_line('echo "echo Hello from sourced file" > /tmp/test_source.sh')

  input = 'source /tmp/test_source.sh'

  call lex%init(input)
  call lex%tokenize()

  ! Show tokens
  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i15,a,a,a,a,a)', "  Token ", i, ": type=", trim(token_type_str(lex%tokens(i)%type)), &
                          ", text='", trim(lex%tokens(i)%value), "'"
  end do

  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  ! Cleanup
  call execute_command_line('rm -f /tmp/test_source.sh')

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

  function token_type_str(token_type) result(str)
    integer, intent(in) :: token_type
    character(:), allocatable :: str

    select case(token_type)
    case(1); str = "TOKEN_WORD"
    case(2); str = "TOKEN_VARIABLE"
    case(3); str = "TOKEN_PIPE"
    case(4); str = "TOKEN_REDIRECT_IN"
    case(5); str = "TOKEN_REDIRECT_OUT"
    case(6); str = "TOKEN_REDIRECT_APPEND"
    case(7); str = "TOKEN_SEMICOLON"
    case(8); str = "TOKEN_NEWLINE"
    case(9); str = "TOKEN_AND"
    case(10); str = "TOKEN_OR"
    case(11); str = "TOKEN_BACKGROUND"
    case(12); str = "TOKEN_IF"
    case(13); str = "TOKEN_THEN"
    case(14); str = "TOKEN_ELSE"
    case(15); str = "TOKEN_FI"
    case(16); str = "TOKEN_FOR"
    case(17); str = "TOKEN_IN"
    case(18); str = "TOKEN_DO"
    case(19); str = "TOKEN_DONE"
    case(20); str = "TOKEN_WHILE"
    case(21); str = "TOKEN_BREAK"
    case(22); str = "TOKEN_CONTINUE"
    case(23); str = "TOKEN_COMMAND_SUBST_START"
    case(24); str = "TOKEN_COMMAND_SUBST_END"
    case(25); str = "TOKEN_EOF"
    case default; str = "UNKNOWN"
    end select
  end function token_type_str

end program test_builtins_debug