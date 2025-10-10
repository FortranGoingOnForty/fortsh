! ==============================================================================
! Test for arithmetic expansion $((...))
! ==============================================================================
program test_arithmetic
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

  print *, "=== Testing Arithmetic Expansion $((...)) ==="
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

  ! Test 1: Simple arithmetic
  print *, "Test 1: Simple arithmetic"
  print *, "----------------------------------------"
  input = 'echo Result: $((5 + 3))'

  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i2,a,i3,a,a,a)', "  ", i, ": type=", lex%tokens(i)%type, &
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

  ! Test 2: Arithmetic with multiplication
  print *, "Test 2: Arithmetic with multiplication"
  print *, "----------------------------------------"
  input = 'echo $((10 * 4))'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: Arithmetic with variables
  print *, "Test 3: Arithmetic with variables"
  print *, "----------------------------------------"

  ! Set some variables
  shell%num_variables = 2
  shell%variables(1)%name = 'X'
  shell%variables(1)%value = '10'
  shell%variables(2)%name = 'Y'
  shell%variables(2)%value = '5'

  input = 'echo $X + $Y = $(($X + $Y))'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 4: Complex expression
  print *, "Test 4: Complex expression with parentheses"
  print *, "----------------------------------------"
  input = 'echo $(((5 + 3) * 2))'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 5: While loop with arithmetic increment
  print *, "Test 5: Simple loop with arithmetic"
  print *, "----------------------------------------"

  shell%num_variables = 1
  shell%variables(1)%name = 'COUNT'
  shell%variables(1)%value = '0'

  input = 'for i in 1 2 3; do echo Iteration $i: $((i * 2)); done'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "=== Arithmetic expansion tests completed! ==="

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_arithmetic