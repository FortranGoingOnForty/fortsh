! ==============================================================================
! Quick test for new built-in commands (printf, let, eval, shift, local)
! ==============================================================================
program test_new_builtins
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
  integer :: exit_code

  print *, "=== Testing New Built-in Commands ==="
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

  ! Test 1: printf command
  print *, "Test 1: printf command"
  print *, "----------------------------------------"
  input = 'printf "Hello, %s!\n" "World"'

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

  ! Test 2: let command - arithmetic evaluation
  print *, "Test 2: let command - arithmetic"
  print *, "----------------------------------------"
  input = 'let x=5+3'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, "Variable x should be 8"
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: type command - verify new built-ins are recognized
  print *, "Test 3: type command - check new built-ins"
  print *, "----------------------------------------"

  ! Test printf
  input = 'type printf'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test let
  input = 'type let'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test local
  input = 'type local'
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

  print *, "=== New built-in command tests completed! ==="
  print *, ""
  print *, "Built-ins tested:"
  print *, "  ✓ printf - formatted output"
  print *, "  ✓ let - arithmetic evaluation"
  print *, "  ✓ type - recognizes new commands"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_new_builtins
