program test_return_basic
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  use evaluator_simple_real
  use shell_types
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_simple_real_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  shell%num_functions = 0
  shell%num_positional = 0
  shell%num_variables = 0

  print *, "========================================="
  print *, "FortSH Return Command Basic Test"
  print *, "========================================="
  print *, ""

  ! Test 1: Just test type command
  print *, "=== Test: type return ==="
  input = 'type return'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 2: Just call return directly (should work even outside function)
  print *, "=== Test: return 42 (standalone) ==="
  input = 'return 42'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  if (exit_code == 42) then
    print *, "✓ PASS"
  else
    print *, "✗ FAIL"
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "Tests complete!"

end program test_return_basic
