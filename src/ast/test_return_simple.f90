program test_return_simple
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
  print *, "FortSH Return Command Simple Test"
  print *, "========================================="
  print *, ""

  ! Test 1: Simple function with return 42
  print *, "=== Test: Function with return 42 ==="
  input = 'test_func() { return 42; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Function defined, exit_code:", exit_code

  ! Now call the function
  input = 'test_func'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  if (exit_code == 42) then
    print *, "✓ PASS: Function returned 42"
  else
    print *, "✗ FAIL: Expected 42, got", exit_code
  end if
  print *, ""

  ! Test 2: Test return without argument
  print *, "=== Test: return (no argument) ==="
  input = 'no_arg() { return; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  input = 'no_arg'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  if (exit_code == 0) then
    print *, "✓ PASS: return with no arg returned 0"
  else
    print *, "✗ FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 3: Test type command recognizes return
  print *, "=== Test: type return ==="
  input = 'type return'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "========================================="
  print *, "Tests complete!"
  print *, "========================================="

end program test_return_simple
