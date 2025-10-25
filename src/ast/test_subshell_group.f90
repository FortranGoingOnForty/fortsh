program test_subshell_group
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
  integer :: test_count, pass_count

  test_count = 0
  pass_count = 0

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  shell%num_functions = 0
  shell%num_positional = 0
  shell%num_variables = 0

  print *, "========================================="
  print *, "FortSH Subshell and Group Tests"
  print *, "========================================="
  print *, ""

  ! Test 1: Simple subshell
  print *, "=== Test 1: Simple subshell () ==="
  input = '(echo hello)'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Subshell executed"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 2: Simple command group
  print *, "=== Test 2: Simple command group { } ==="
  input = '{ echo world; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Command group executed"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 3: Subshell with multiple commands
  print *, "=== Test 3: Subshell with multiple commands ==="
  input = '(echo first; echo second)'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Multiple commands in subshell"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 4: Command group with multiple commands
  print *, "=== Test 4: Command group with multiple commands ==="
  input = '{ echo one; echo two; echo three; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Multiple commands in group"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 5: Subshell with exit code
  print *, "=== Test 5: Subshell with exit code ==="
  input = '(exit 42)'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 42) then
    print *, "PASS: Subshell returned correct exit code"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 42, got", exit_code
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "========================================="
  write(*, '(a,i15,a,i15,a)') " Tests passed: ", pass_count, " / ", test_count, " total"
  print *, "========================================="

end program test_subshell_group
