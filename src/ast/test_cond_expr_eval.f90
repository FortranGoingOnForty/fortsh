program test_cond_expr_eval
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  use evaluator_simple_real
  use shell_types
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: parser
  type(evaluator_simple_real_t) :: evaluator
  type(shell_state_t), target :: shell
  type(script_node_t) :: ast
  character(:), allocatable :: input
  integer :: exit_code, test_count, pass_count
  logical :: file_exists

  test_count = 0
  pass_count = 0

  ! Initialize shell state
  call shell%init()
  call shell%set_variable('myvar', 'hello')
  call shell%set_variable('num1', '5')
  call shell%set_variable('num2', '10')
  call evaluator%init(shell)

  print *, "=== Conditional Expression Evaluator Tests ==="
  print *, ""

  ! Test 1: File existence test -f
  test_count = test_count + 1
  print *, "Test 1: [[ -f lexer_simple.f90 ]]"
  inquire(file='lexer_simple.f90', exist=file_exists)
  input = '[[ -f lexer_simple.f90 ]]'
  exit_code = run_test(input)
  if (file_exists) then
    if (exit_code == 0) then
      print *, "✓ PASS - File exists, returned 0"
      pass_count = pass_count + 1
    else
      print *, "✗ FAIL - File exists but returned", exit_code
    end if
  else
    if (exit_code /= 0) then
      print *, "✓ PASS - File doesn't exist, returned", exit_code
      pass_count = pass_count + 1
    else
      print *, "✗ FAIL - File doesn't exist but returned 0"
    end if
  end if
  print *, ""

  ! Test 2: String comparison ==
  test_count = test_count + 1
  print *, "Test 2: [[ $myvar == hello ]]"
  input = '[[ $myvar == hello ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - String comparison returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - String comparison returned", exit_code
  end if
  print *, ""

  ! Test 3: String comparison != (should be true)
  test_count = test_count + 1
  print *, "Test 3: [[ $myvar != goodbye ]]"
  input = '[[ $myvar != goodbye ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - String inequality returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - String inequality returned", exit_code
  end if
  print *, ""

  ! Test 4: Pattern matching
  test_count = test_count + 1
  print *, "Test 4: [[ hello == h* ]]"
  input = '[[ hello == h* ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - Pattern matching returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Pattern matching returned", exit_code
  end if
  print *, ""

  ! Test 5: Integer comparison -eq
  test_count = test_count + 1
  print *, "Test 5: [[ $num1 -eq 5 ]]"
  input = '[[ $num1 -eq 5 ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - Integer equality returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Integer equality returned", exit_code
  end if
  print *, ""

  ! Test 6: Integer comparison -lt
  test_count = test_count + 1
  print *, "Test 6: [[ $num1 -lt $num2 ]]"
  input = '[[ $num1 -lt $num2 ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - Integer less-than returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Integer less-than returned", exit_code
  end if
  print *, ""

  ! Test 7: Integer comparison -gt (should fail)
  test_count = test_count + 1
  print *, "Test 7: [[ $num1 -gt $num2 ]]"
  input = '[[ $num1 -gt $num2 ]]'
  exit_code = run_test(input)
  if (exit_code /= 0) then
    print *, "✓ PASS - Integer greater-than returned", exit_code
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Integer greater-than should fail but returned 0"
  end if
  print *, ""

  ! Test 8: String test -z (should fail - not empty)
  test_count = test_count + 1
  print *, "Test 8: [[ -z $myvar ]]"
  input = '[[ -z $myvar ]]'
  exit_code = run_test(input)
  if (exit_code /= 0) then
    print *, "✓ PASS - Empty string test (on non-empty) returned", exit_code
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Empty string test should fail but returned 0"
  end if
  print *, ""

  ! Test 9: String test -n (should pass - not empty)
  test_count = test_count + 1
  print *, "Test 9: [[ -n $myvar ]]"
  input = '[[ -n $myvar ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - Non-empty string test returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Non-empty string test returned", exit_code
  end if
  print *, ""

  ! Test 10: Negation !
  test_count = test_count + 1
  print *, "Test 10: [[ ! -z $myvar ]]"
  input = '[[ ! -z $myvar ]]'
  exit_code = run_test(input)
  if (exit_code == 0) then
    print *, "✓ PASS - Negation test returned 0"
    pass_count = pass_count + 1
  else
    print *, "✗ FAIL - Negation test returned", exit_code
  end if
  print *, ""

  ! Print summary
  print *, "=== Test Summary ==="
  print *, "Passed:", pass_count, "/", test_count
  if (pass_count == test_count) then
    print *, "All tests PASSED!"
    stop 0
  else
    print *, "Some tests FAILED"
    stop 1
  end if

contains
  function run_test(cmd) result(code)
    character(*), intent(in) :: cmd
    integer :: code

    call lex%init(cmd)
    call lex%tokenize()
    call parser%init(lex%tokens, lex%token_count)
    ast = parser%parse()
    code = evaluator%eval(ast)

    call parser%destroy()
    call lex%destroy()
  end function run_test

end program test_cond_expr_eval
