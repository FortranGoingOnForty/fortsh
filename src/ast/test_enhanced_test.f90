program test_enhanced_test
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
  print *, "FortSH Enhanced Test Command Tests"
  print *, "========================================="
  print *, ""

  ! Test 1: String tests - empty string
  print *, "=== Test 1: test -z '' (empty string) ==="
  input = 'test -z ""'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  call eval%init(shell)
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Empty string test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 2: String tests - non-empty string
  print *, "=== Test 2: test -n 'hello' (non-empty string) ==="
  input = 'test -n hello'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Non-empty string test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 3: File tests - file exists
  print *, "=== Test 3: test -f /etc/passwd (file exists) ==="
  input = 'test -f /etc/passwd'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: File exists test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 4: File tests - readable
  print *, "=== Test 4: test -r /etc/passwd (file readable) ==="
  input = 'test -r /etc/passwd'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: File readable test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 5: Directory test
  print *, "=== Test 5: test -d /tmp (directory exists) ==="
  input = 'test -d /tmp'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Directory test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 6: String comparison - equal
  print *, "=== Test 6: test 'foo' = 'foo' (strings equal) ==="
  input = 'test foo = foo'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: String equality test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 7: String comparison - not equal
  print *, "=== Test 7: test 'foo' != 'bar' (strings not equal) ==="
  input = 'test foo != bar'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: String inequality test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 8: Integer comparison - equal
  print *, "=== Test 8: test 5 -eq 5 (integers equal) ==="
  input = 'test 5 -eq 5'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Integer equality test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 9: Integer comparison - less than
  print *, "=== Test 9: test 3 -lt 5 (3 < 5) ==="
  input = 'test 3 -lt 5'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Integer less-than test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 10: Integer comparison - greater than
  print *, "=== Test 10: test 10 -gt 5 (10 > 5) ==="
  input = 'test 10 -gt 5'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 0) then
    print *, "PASS: Integer greater-than test returned 0"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 0, got", exit_code
  end if
  print *, ""

  ! Test 11: Negative test - file doesn't exist
  print *, "=== Test 11: test -f /nonexistent (should fail) ==="
  input = 'test -f /nonexistent'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 1) then
    print *, "PASS: Non-existent file test returned 1"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 1, got", exit_code
  end if
  print *, ""

  ! Test 12: Negative test - strings not equal
  print *, "=== Test 12: test 'foo' = 'bar' (should fail) ==="
  input = 'test foo = bar'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  exit_code = eval%eval(ast)
  test_count = test_count + 1
  if (exit_code == 1) then
    print *, "PASS: Unequal strings test returned 1"
    pass_count = pass_count + 1
  else
    print *, "FAIL: Expected 1, got", exit_code
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "========================================="
  write(*, '(a,i15,a,i15,a)') " Tests passed: ", pass_count, " / ", test_count, " total"
  print *, "========================================="

end program test_enhanced_test
