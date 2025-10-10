! Test for loop with command substitution
program test_for_loop_fix
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

  print *, "=== Testing For Loop ==="

  ! Initialize shell
  shell%username = "testuser"
  shell%hostname = "testhost"
  call getcwd(shell%cwd)
  shell%is_interactive = .false.
  shell%running = .true.
  shell%last_exit_status = 0
  shell%num_variables = 0
  shell%control_depth = 0

  ! Test 1: Simple for loop (should work)
  print *, "Test 1: Simple for loop"
  input = 'for x in a b c; do echo $x; done'

  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i2,a,i3,a,a)', "  ", i, ": type=", lex%tokens(i)%type, &
                             " value='", trim(lex%tokens(i)%value), "'"
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

  ! Test 2: For loop with glob (should work)
  print *, "Test 2: For loop with glob pattern"
  input = 'for f in test*.f90; do echo Found $f; done'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: For loop with command substitution (problematic)
  print *, "Test 3: For loop with command substitution"
  input = 'for f in $(ls test*.f90); do echo Found: $f; done'

  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i2,a,i3,a,a)', "  ", i, ": type=", lex%tokens(i)%type, &
                             " value='", trim(lex%tokens(i)%value), "'"
  end do

  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_for_loop_fix