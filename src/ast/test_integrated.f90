! ==============================================================================
! Integrated test for multiple shell features
! ==============================================================================
program test_integrated
  use ast_types_enhanced
  use shell_types
  use lexer_simple
  use parser_enhanced
  use evaluator_simple_real
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_simple_real_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code

  print *, "=== Integrated Shell Features Test ==="
  print *, ""

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  call getcwd(shell%cwd)
  shell%is_interactive = .false.
  shell%running = .true.
  shell%last_exit_status = 0
  shell%num_variables = 0
  shell%control_depth = 0

  ! Test 1: Pipeline with redirection
  print *, "Test 1: Pipeline with redirection"
  print *, "----------------------------------------"
  input = 'ls *.f90 | head -3 > first_three.txt'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  ! Show contents of file
  call execute_command_line('cat first_three.txt 2>/dev/null')
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 2: Command substitution with redirection
  print *, "Test 2: Command substitution with redirection"
  print *, "----------------------------------------"
  input = 'echo "File count: $(ls *.f90 | wc -l)" > count.txt'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  ! Show contents of file
  call execute_command_line('cat count.txt 2>/dev/null')
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: For loop with command substitution
  print *, "Test 3: For loop with command substitution"
  print *, "----------------------------------------"
  input = 'for f in $(ls test*.f90 | head -2); do echo "Found: $f"; done'

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

  ! Test 4: If statement with pipeline
  print *, "Test 4: If statement with pipeline"
  print *, "----------------------------------------"
  input = 'if ls *.f90 | grep -q test; then echo "Test files found"; else echo "No test files"; fi'

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

  ! Test 5: Simple while loop with false
  print *, "Test 5: Simple while loop with false condition"
  print *, "----------------------------------------"

  input = 'while false; do echo "Should not print"; done'

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

  ! Cleanup
  call execute_command_line('rm -f first_three.txt count.txt')

  print *, "=== Integrated tests completed! ==="
  print *, ""
  print *, "Features tested:"
  print *, "  ✓ Pipelines with redirection"
  print *, "  ✓ Command substitution with redirection"
  print *, "  ✓ For loops with command substitution"
  print *, "  ✓ If statements with pipelines"
  print *, "  ✓ While loops with conditions"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_integrated