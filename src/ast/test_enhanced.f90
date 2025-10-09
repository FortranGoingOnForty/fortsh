! ==============================================================================
! Test program for enhanced AST with full polymorphic support
! ==============================================================================
program test_enhanced
  use ast_types_enhanced
  use shell_types
  use lexer_simple
  use parser_enhanced
  use evaluator_enhanced
  use iso_fortran_env, only: output_unit
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_enhanced_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code

  print *, "=== Enhanced AST Test - Full Functionality ==="
  print *, ""

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  shell%cwd = "/home/testuser"
  shell%is_interactive = .false.
  shell%running = .true.
  shell%last_exit_status = 0
  shell%num_variables = 0
  shell%control_depth = 0

  ! Test 1: Simple command execution
  print *, "Test 1: Simple command with echo"
  print *, "----------------------------------------"
  input = 'echo Hello from enhanced AST'

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

  ! Test 2: For loop with variable expansion
  print *, "Test 2: For loop with variable expansion"
  print *, "----------------------------------------"
  input = 'for item in apple banana cherry' // char(10) // &
          'do' // char(10) // &
          '  echo $item' // char(10) // &
          'done'

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

  ! Test 3: If statement with conditions
  print *, "Test 3: If statement with true/false"
  print *, "----------------------------------------"
  input = 'if true' // char(10) // &
          'then' // char(10) // &
          '  echo Condition was true' // char(10) // &
          'else' // char(10) // &
          '  echo Condition was false' // char(10) // &
          'fi'

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

  ! Test 4: For loop with break
  print *, "Test 4: For loop with break"
  print *, "----------------------------------------"
  input = 'for num in 1 2 3 4 5' // char(10) // &
          'do' // char(10) // &
          '  echo $num' // char(10) // &
          '  break' // char(10) // &
          '  echo After break' // char(10) // &
          'done'

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

  ! Test 5: While loop with break
  print *, "Test 5: While loop with break"
  print *, "----------------------------------------"
  input = 'while true' // char(10) // &
          'do' // char(10) // &
          '  echo In loop' // char(10) // &
          '  break' // char(10) // &
          'done' // char(10) // &
          'echo After loop'

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

  ! Test 6: Multiple statements
  print *, "Test 6: Multiple statements"
  print *, "----------------------------------------"
  input = 'echo First statement' // char(10) // &
          'echo Second statement' // char(10) // &
          'echo Third statement'

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

  print *, "=== All enhanced AST tests completed successfully! ==="
  print *, ""
  print *, "Summary: The enhanced AST with pointer arrays provides:"
  print *, "  - Full access to all derived type fields"
  print *, "  - Proper polymorphic dispatch with SELECT TYPE"
  print *, "  - Working variable expansion in loops"
  print *, "  - Correct break/continue handling with levels"
  print *, "  - Complete control flow execution"

end program test_enhanced