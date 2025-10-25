! ==============================================================================
! Simple test for command substitution
! ==============================================================================
program test_cmd_subst_simple
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
  integer :: i

  print *, "=== Simple Command Substitution Test ==="
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

  ! Test: Simple echo with command substitution
  print *, "Test: echo with command substitution"
  print *, "Input: echo Result: $(echo hello)"
  print *, "----------------------------------------"
  input = 'echo Result: $(echo hello)'

  ! Tokenize
  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:"
  do i = 1, lex%token_count
    print '(a,i15,a,i15,a,a)', "  Token ", i, " (type=", lex%tokens(i)%type, &
           "): '", trim(lex%tokens(i)%value), "'"
  end do

  ! Parse
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  print *, ""
  print *, "Executing command..."

  ! Execute
  call eval%init(shell)
  exit_code = eval%eval(ast)

  print *, ""
  print *, "Exit code:", exit_code

  call lex%destroy()
  call pars%destroy()
  call eval%destroy()

contains

  subroutine getcwd(path)
    character(*), intent(out) :: path
    integer :: status
    call get_environment_variable('PWD', path, status=status)
    if (status /= 0) path = '/tmp'
  end subroutine getcwd

end program test_cmd_subst_simple