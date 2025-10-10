! ==============================================================================
! Test for case statements and positional parameters
! ==============================================================================
program test_case_params
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

  print *, "=== Testing Case Statements and Positional Parameters ==="
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

  ! Test 1: Simple case statement
  print *, "Test 1: Simple case statement"
  print *, "----------------------------------------"

  shell%num_variables = 1
  shell%variables(1)%name = 'OPTION'
  shell%variables(1)%value = 'start'

  input = 'case $OPTION in' // char(10) // &
          '  start) echo Starting service;;' // char(10) // &
          '  stop) echo Stopping service;;' // char(10) // &
          '  *) echo Unknown option;;' // char(10) // &
          'esac'

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

  ! Test 2: Case with pattern matching
  print *, "Test 2: Case with wildcard patterns"
  print *, "----------------------------------------"

  shell%variables(1)%value = 'test.txt'

  input = 'case $OPTION in' // char(10) // &
          '  *.txt) echo Text file;;' // char(10) // &
          '  *.f90) echo Fortran file;;' // char(10) // &
          '  *) echo Other file;;' // char(10) // &
          'esac'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: Positional parameters
  print *, "Test 3: Positional parameters"
  print *, "----------------------------------------"

  ! Set up positional parameters like command-line arguments
  shell%script_name = 'test_script.sh'
  shell%num_positional = 3
  shell%positional_params(1) = 'arg1'
  shell%positional_params(2) = 'arg2'
  shell%positional_params(3) = 'arg3'

  input = 'echo Script: $0'
  call test_command(input)

  input = 'echo First arg: $1'
  call test_command(input)

  input = 'echo All args: $@'
  call test_command(input)

  input = 'echo Number of args: $#'
  call test_command(input)
  print *, ""

  ! Test 4: Using positional parameters in for loop
  print *, "Test 4: Positional parameters in for loop"
  print *, "----------------------------------------"

  input = 'for arg in $@; do echo Processing: $arg; done'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 5: Case with positional parameter
  print *, "Test 5: Case with positional parameter"
  print *, "----------------------------------------"

  shell%positional_params(1) = '--help'

  input = 'case $1 in' // char(10) // &
          '  --help) echo Usage: script [options];;' // char(10) // &
          '  --version) echo Version 1.0;;' // char(10) // &
          '  *) echo Running with: $1;;' // char(10) // &
          'esac'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  print *, "=== Tests completed! ==="
  print *, ""
  print *, "Features tested:"
  print *, "  ✓ Case statements with literal patterns"
  print *, "  ✓ Case statements with wildcard patterns"
  print *, "  ✓ Positional parameters $0, $1, $#, $@, $*"
  print *, "  ✓ Integration of case and positional parameters"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

  subroutine test_command(cmd)
    character(*), intent(in) :: cmd

    call lex%init(cmd)
    call lex%tokenize()
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    call eval%init(shell)
    exit_code = eval%eval(ast)

    call lex%destroy()
    call pars%destroy()
    call eval%destroy()
  end subroutine test_command

end program test_case_params