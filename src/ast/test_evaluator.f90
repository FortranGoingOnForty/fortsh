! ==============================================================================
! Test program for AST evaluator
! ==============================================================================
program test_evaluator
  use ast_types
  use lexer
  use parser
  use shell_types
  use evaluator
  implicit none

  type(lexer_t) :: lex
  type(parser_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code

  print *, "=== AST Evaluator Test ==="
  print *, ""

  ! Test 1: Simple command
  print *, "Test 1: Simple command"
  input = 'echo hello world'
  print *, "Input: ", input

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code: ", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 2: For loop
  print *, "Test 2: For loop"
  input = 'for x in a b c' // char(10) // &
          'do' // char(10) // &
          '  echo $x' // char(10) // &
          'done'
  print *, "Input: for loop with 3 items"

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code: ", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: Break statement
  print *, "Test 3: Loop with break"
  input = 'for x in 1 2 3 4 5' // char(10) // &
          'do' // char(10) // &
          '  echo $x' // char(10) // &
          '  break' // char(10) // &
          'done'
  print *, "Input: for loop with break"

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code: ", exit_code
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "=== All evaluator tests completed ==="

end program test_evaluator