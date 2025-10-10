! ==============================================================================
! Test for new built-in commands
! ==============================================================================
program test_builtins
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

  print *, "=== Testing New Built-in Commands ==="
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

  ! Test 1: set command - set variable
  print *, "Test 1: set command - setting variables"
  print *, "----------------------------------------"
  input = 'set MYVAR=hello'

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

  ! Test 2: declare command
  print *, "Test 2: declare command"
  print *, "----------------------------------------"
  input = 'declare NEWVAR=world'

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

  ! Test 3: echo variables
  print *, "Test 3: echo variables"
  print *, "----------------------------------------"
  input = 'echo $MYVAR $NEWVAR'

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

  ! Test 4: unset command
  print *, "Test 4: unset command"
  print *, "----------------------------------------"
  input = 'unset MYVAR'

  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  call eval%init(shell)
  exit_code = eval%eval(ast)
  print *, "Exit code:", exit_code

  ! Check if variable is gone
  input = 'echo MYVAR=$MYVAR NEWVAR=$NEWVAR'
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

  ! Test 5: set command - show all variables
  print *, "Test 5: set command - show all variables"
  print *, "----------------------------------------"
  input = 'set'

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

  ! Test 6: type command
  print *, "Test 6: type command"
  print *, "----------------------------------------"

  ! Test built-in
  input = 'type echo'
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

  ! Test another built-in
  input = 'type unset'
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

  ! Test external command
  input = 'type ls'
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

  ! Test 7: source command (create a test file first)
  print *, "Test 7: source command"
  print *, "----------------------------------------"

  ! Create a test file to source
  call execute_command_line('echo "echo Hello from sourced file" > /tmp/test_source.sh')
  call execute_command_line('echo "echo Line 2 of sourced file" >> /tmp/test_source.sh')

  input = 'source /tmp/test_source.sh'

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
  call execute_command_line('rm -f /tmp/test_source.sh')

  print *, "=== Built-in command tests completed! ==="
  print *, ""
  print *, "Built-ins tested:"
  print *, "  ✓ set - set and show variables"
  print *, "  ✓ declare - declare variables"
  print *, "  ✓ unset - remove variables"
  print *, "  ✓ type - show command type"
  print *, "  ✓ source - execute commands from file"

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_builtins