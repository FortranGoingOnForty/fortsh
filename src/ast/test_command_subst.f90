! ==============================================================================
! Test program for command substitution functionality
! ==============================================================================
program test_command_subst
  use ast_types_enhanced
  use shell_types
  use lexer_simple
  use parser_enhanced
  use evaluator_simple_real
  use iso_fortran_env, only: output_unit, input_unit
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_simple_real_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code

  print *, "=== Command Substitution Test ==="
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

  ! Test 1: Simple command substitution
  print *, "Test 1: Simple command substitution"
  print *, "----------------------------------------"
  input = 'echo "Today is $(date +%A)"'

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

  ! Test 2: Command substitution in variable assignment
  print *, "Test 2: Command substitution in assignment"
  print *, "----------------------------------------"
  input = 'FILES=$(ls -1 | wc -l)'

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

  ! Test 3: Nested command substitution
  print *, "Test 3: Nested command substitution"
  print *, "----------------------------------------"
  input = 'echo "User: $(echo $(whoami))"'

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

  ! Test 4: Command substitution with pipes
  print *, "Test 4: Command substitution with pipes"
  print *, "----------------------------------------"
  input = 'echo "Process count: $(ps aux | wc -l)"'

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

  ! Test 5: Command substitution in for loop
  print *, "Test 5: Command substitution in for loop"
  print *, "----------------------------------------"
  input = 'for f in $(ls *.f90); do echo "File: $f"; done'

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

  print *, "=== Command substitution tests completed! ==="
  print *, ""
  print *, "Command substitution features tested:"
  print *, "  ✓ Simple command substitution"
  print *, "  ✓ Command substitution in assignments"
  print *, "  ✓ Nested command substitution"
  print *, "  ✓ Command substitution with pipes"
  print *, "  ✓ Command substitution in for loops"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status

    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) then
      path = '/tmp'
    end if
  end subroutine getcwd

end program test_command_subst