program test_logical_ops
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
  print *, "FortSH Logical Operators Test"
  print *, "========================================="
  print *, ""

  ! Test 1: AND operator with success
  print *, "=== Test 1: true && echo 'success' ==="
  input = 'true && echo "executed"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 2: AND operator with failure
  print *, "=== Test 2: false && echo 'should not execute' ==="
  input = 'false && echo "should not see this"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 3: OR operator with failure
  print *, "=== Test 3: false || echo 'fallback' ==="
  input = 'false || echo "executed fallback"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 4: OR operator with success
  print *, "=== Test 4: true || echo 'should not execute' ==="
  input = 'true || echo "should not see this"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 5: Chained operators
  print *, "=== Test 5: true && echo 'first' && echo 'second' ==="
  input = 'true && echo "first" && echo "second"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 6: Mixed operators
  print *, "=== Test 6: false || echo 'or worked' && echo 'then and worked' ==="
  input = 'false || echo "or worked" && echo "then and worked"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 7: Command with test
  print *, "=== Test 7: test -f /etc/passwd && echo 'passwd exists' ==="
  input = 'test -f /etc/passwd && echo "passwd exists"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "========================================="
  print *, "All logical operator tests completed!"
  print *, "========================================="

end program test_logical_ops
