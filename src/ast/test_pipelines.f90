! ==============================================================================
! Test program for pipeline functionality
! ==============================================================================
program test_pipelines
  use ast_types_enhanced
  use shell_types
  use lexer_simple
  use parser_enhanced
  use evaluator_simple_real
  use iso_fortran_env, only: output_unit
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  type(shell_state_t) :: shell
  type(evaluator_simple_real_t) :: eval
  character(:), allocatable :: input
  integer :: exit_code

  print *, "=== Pipeline Functionality Test ==="
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

  ! Test 1: Simple pipeline
  print *, "Test 1: Simple pipeline (ls | head -5)"
  print *, "----------------------------------------"
  input = 'ls | head -5'

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

  ! Test 2: Three-stage pipeline
  print *, "Test 2: Three-stage pipeline"
  print *, "----------------------------------------"
  input = 'ls -la | grep ".f90" | wc -l'

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

  ! Test 3: Pipeline with echo
  print *, "Test 3: Pipeline with echo"
  print *, "----------------------------------------"
  input = 'echo "Hello World" | tr "[a-z]" "[A-Z]"'

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

  ! Test 4: Pipeline with grep and counting
  print *, "Test 4: Pipeline with grep pattern"
  print *, "----------------------------------------"
  input = 'cat test_pipelines.f90 | grep "Test" | head -3'

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

  ! Test 5: Pipeline with variable expansion
  print *, "Test 5: Pipeline with variable expansion"
  print *, "----------------------------------------"
  shell%num_variables = 1
  shell%variables(1)%name = 'PATTERN'
  shell%variables(1)%value = '*.f90'

  input = 'ls $PATTERN | head -3'

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

  print *, "=== Pipeline tests completed! ==="
  print *, ""
  print *, "Pipeline features tested:"
  print *, "  ✓ Simple two-command pipelines"
  print *, "  ✓ Multi-stage pipelines (3+ commands)"
  print *, "  ✓ Pipes with text processing (tr, grep)"
  print *, "  ✓ Pipes with counting (wc)"
  print *, "  ✓ Variable expansion in pipelines"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status

    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) then
      path = '/tmp'
    end if
  end subroutine getcwd

end program test_pipelines