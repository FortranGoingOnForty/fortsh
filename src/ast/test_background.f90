program test_background
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
  print *, "FortSH Background Job Tests"
  print *, "========================================="
  print *, ""

  ! Test 1: Simple background command
  print *, "=== Test 1: Simple background command ==="
  input = 'sleep 0.1 &'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Background command executed"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 2: Background echo
  print *, "=== Test 2: Background echo ==="
  input = 'echo "running in background" &'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Background echo executed"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 3: Multiple background jobs
  print *, "=== Test 3: Multiple background jobs ==="
  input = 'sleep 0.1 & sleep 0.1 &'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Multiple background jobs executed"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 4: Background pipeline
  print *, "=== Test 4: Background pipeline ==="
  input = 'echo hello | cat &'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Background pipeline executed"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 5: Foreground command after background
  print *, "=== Test 5: Foreground after background ==="
  input = 'sleep 0.1 &; echo "foreground"'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Foreground command after background"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "========================================="
  write(*, '(a,i0,a,i0,a)') " Tests passed: ", pass_count, " / ", test_count, " total"
  print *, "========================================="

end program test_background
