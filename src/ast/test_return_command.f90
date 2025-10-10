program test_return_command
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

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  shell%num_functions = 0
  shell%num_positional = 0
  shell%num_variables = 0

  test_count = 0
  pass_count = 0

  print *, "========================================="
  print *, "FortSH Return Command Tests"
  print *, "========================================="
  print *, ""

  ! Test 1: Function with explicit return 0
  print *, "=== Test 1: Function with return 0 ==="
  input = 'test_func() { echo "in function"; return 0; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)

  ! Now call the function
  input = 'test_func'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Function returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 2: Function with explicit return 42
  print *, "=== Test 2: Function with return 42 ==="
  input = 'test_func2() { return 42; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  ! Now call the function
  input = 'test_func2'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  test_count = test_count + 1
  if (exit_code == 42) then
    print *, "PASS: Function returned 42"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 42, got", exit_code
  end if
  print *, ""

  ! Test 3: Function with early return
  print *, "=== Test 3: Function with early return ==="
  input = 'early_return() { echo "before"; return 5; echo "after"; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  ! Now call the function
  input = 'early_return'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  test_count = test_count + 1
  if (exit_code == 5) then
    print *, "PASS: Early return worked (exit code 5)"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 5, got", exit_code
  end if
  print *, ""

  ! Test 4: Function with no explicit return (implicit 0)
  print *, "=== Test 4: Function with no explicit return ==="
  input = 'no_return() { echo "no return"; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  ! Now call the function
  input = 'no_return'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Implicit return 0 worked"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 5: Function with conditional return
  print *, "=== Test 5: Function with conditional return (true branch) ==="
  input = 'cond_return() { test -f /etc/passwd && return 10; return 20; }'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  ! Now call the function
  input = 'cond_return'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)

  test_count = test_count + 1
  if (exit_code == 10) then
    print *, "PASS: Conditional return took true branch (exit code 10)"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 10, got", exit_code
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "========================================="
  write(*, '(a,i0,a,i0,a)') " Tests passed: ", pass_count, " / ", test_count, " total"
  print *, "========================================="

end program test_return_command
