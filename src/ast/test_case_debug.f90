! Debug test for case statements
program test_case_debug
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

  print *, "=== Debug: Simple case statement ==="
  print *, ""

  ! Initialize shell
  shell%username = "testuser"
  shell%hostname = "testhost"
  call getcwd(shell%cwd)
  shell%is_interactive = .false.
  shell%running = .true.
  shell%last_exit_status = 0
  shell%num_variables = 1
  shell%control_depth = 0

  ! Set variable
  shell%variables(1)%name = 'VAR'
  shell%variables(1)%value = 'test'

  ! Simple case
  input = 'case test in test) echo Match;; *) echo No match;; esac'

  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i3,a,i3,a,a,a)', "  ", i, ": type=", lex%tokens(i)%type, &
                              " value='", trim(lex%tokens(i)%value), "'"
  end do
  print *, ""

  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  print *, "Evaluating..."
  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test with variable
  print *, "=== Test with variable ==="
  input = 'case $VAR in test) echo Variable matches;; *) echo No match;; esac'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_case_debug