! ==============================================================================
! Test program for I/O redirection functionality
! ==============================================================================
program test_redirection
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
  logical :: file_exists

  print *, "=== I/O Redirection Test ==="
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

  ! Test 1: Output redirection (>)
  print *, "Test 1: Output redirection (echo > test.txt)"
  print *, "----------------------------------------"
  input = 'echo "Hello from redirection test" > test_output.txt'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  ! Verify file was created
  inquire(file='test_output.txt', exist=file_exists)
  if (file_exists) then
    print *, "✓ File created successfully"
    call execute_command_line('cat test_output.txt')
  else
    print *, "✗ File was not created"
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 2: Append redirection (>>)
  print *, "Test 2: Append redirection (echo >> test.txt)"
  print *, "----------------------------------------"
  input = 'echo "Second line appended" >> test_output.txt'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  print *, "File contents after append:"
  call execute_command_line('cat test_output.txt')
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 3: Input redirection (<)
  print *, "Test 3: Input redirection (wc < test.txt)"
  print *, "----------------------------------------"

  ! First create a test input file
  call execute_command_line('echo "Line 1" > test_input.txt')
  call execute_command_line('echo "Line 2" >> test_input.txt')
  call execute_command_line('echo "Line 3" >> test_input.txt')

  input = 'wc -l < test_input.txt'

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

  ! Test 4: Combined redirection
  print *, "Test 4: Combined redirection"
  print *, "----------------------------------------"
  input = 'grep "Line" < test_input.txt > grep_output.txt'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  print *, "grep_output.txt contents:"
  call execute_command_line('cat grep_output.txt')
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Test 5: Redirection with variables
  print *, "Test 5: Redirection with variables"
  print *, "----------------------------------------"
  shell%num_variables = 1
  shell%variables(1)%name = 'MSG'
  shell%variables(1)%value = 'Variable content test'

  input = 'echo $MSG > var_output.txt'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  print *, "var_output.txt contents:"
  call execute_command_line('cat var_output.txt')
  print *, ""

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

  ! Cleanup test files
  call execute_command_line('rm -f test_output.txt test_input.txt grep_output.txt var_output.txt')

  print *, "=== Redirection tests completed! ==="
  print *, ""
  print *, "Redirection features tested:"
  print *, "  ✓ Output redirection (>)"
  print *, "  ✓ Append redirection (>>)"
  print *, "  ✓ Input redirection (<)"
  print *, "  ✓ Combined input/output redirection"
  print *, "  ✓ Variable expansion with redirection"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status

    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) then
      path = '/tmp'
    end if
  end subroutine getcwd

end program test_redirection