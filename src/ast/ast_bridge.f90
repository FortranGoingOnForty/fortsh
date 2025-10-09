! ==============================================================================
! Module: ast_bridge
! Purpose: Bridge between old string-based and new AST-based execution
! ==============================================================================
module ast_bridge
  use ast_types
  use shell_types  ! Use the actual shell_types module
  use lexer
  use parser  ! Use our AST parser
  use evaluator_integrated
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Global flag to enable AST mode
  logical :: use_ast_mode = .false.

contains

  ! Initialize AST mode based on command line arguments or environment
  subroutine init_ast_mode()
    character(256) :: ast_env
    integer :: i, argc
    character(256) :: arg

    ! Check environment variable
    call get_environment_variable('FORTSH_AST_MODE', ast_env)
    if (trim(ast_env) == '1' .or. trim(ast_env) == 'true') then
      use_ast_mode = .true.
      write(output_unit, '(a)') 'AST mode enabled via environment'
      return
    end if

    ! Check command line arguments
    argc = command_argument_count()
    do i = 1, argc
      call get_command_argument(i, arg)
      if (trim(arg) == '--ast-mode') then
        use_ast_mode = .true.
        write(output_unit, '(a)') 'AST mode enabled via command line'
        return
      end if
    end do
  end subroutine init_ast_mode

  ! Execute command using AST-based approach
  function execute_with_ast(command, shell_state) result(exit_code)
    character(*), intent(in) :: command
    type(shell_state_t), intent(inout) :: shell_state
    integer :: exit_code

    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    type(evaluator_integrated_t) :: eval

    ! Default success
    exit_code = 0

    ! Skip empty commands
    if (len_trim(command) == 0) return

    ! Tokenize input
    call lex%init(command)
    call lex%tokenize()

    ! Check for tokenization errors
    if (lex%token_count == 0) then
      write(error_unit, '(a)') 'AST: Failed to tokenize input'
      exit_code = 1
      call lex%destroy()
      return
    end if

    ! Parse tokens into AST
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    ! Initialize evaluator with shell state
    call eval%init(shell_state)

    ! Evaluate AST
    exit_code = eval%eval(ast)

    ! Update shell's last exit code
    shell_state%last_exit_status = exit_code

    ! Clean up
    call lex%destroy()
    call pars%destroy()
    call eval%destroy()

  end function execute_with_ast

  ! Wrapper function that dispatches based on mode
  function execute_command_adaptive(command, shell_state) result(exit_code)
    character(*), intent(in) :: command
    type(shell_state_t), intent(inout) :: shell_state
    integer :: exit_code

    if (use_ast_mode) then
      ! Use new AST-based execution
      exit_code = execute_with_ast(command, shell_state)

      ! Log for debugging (if verbose mode needed in future)
    else
      ! Fall back to old string-based execution
      ! This would call the existing execute_pipeline or similar
      exit_code = 0  ! Placeholder - would call old executor
    end if

  end function execute_command_adaptive

  ! Print AST structure for debugging
  subroutine print_ast_debug(command)
    character(*), intent(in) :: command
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    integer :: i

    write(output_unit, '(a)') '=== AST Debug Output ==='
    write(output_unit, '(a,a)') 'Command: ', command

    ! Tokenize
    call lex%init(command)
    call lex%tokenize()

    write(output_unit, '(a,i0)') 'Tokens: ', lex%token_count
    do i = 1, lex%token_count
      write(output_unit, '(a,i0,a,i0,a,a)') &
        '  Token[', i, '] type=', lex%tokens(i)%type, &
        ' value=', lex%tokens(i)%value
    end do

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    write(output_unit, '(a)') 'AST Structure:'
    if (allocated(ast%statements)) then
      write(output_unit, '(a,i0)') '  Statements: ', size(ast%statements)
      do i = 1, size(ast%statements)
        write(output_unit, '(a,i0,a,i0)') &
          '    Statement[', i, '] type=', ast%statements(i)%node_type
        call print_node_info(ast%statements(i), 2)
      end do
    else
      write(output_unit, '(a)') '  No statements'
    end if

    ! Clean up
    call lex%destroy()
    call pars%destroy()

    write(output_unit, '(a)') '=== End AST Debug ==='

  end subroutine print_ast_debug

  ! Helper to print node information recursively
  recursive subroutine print_node_info(node, indent)
    class(ast_node_t), intent(in) :: node
    integer, intent(in) :: indent
    character(100) :: indent_str
    integer :: i

    ! Create indentation
    indent_str = repeat('  ', indent)

    select case(node%node_type)
    case(NODE_COMMAND)
      write(output_unit, '(a,a)') trim(indent_str), 'Command node'

    case(NODE_FOR)
      write(output_unit, '(a,a)') trim(indent_str), 'For loop node'

    case(NODE_WHILE)
      write(output_unit, '(a,a)') trim(indent_str), 'While loop node'

    case(NODE_IF)
      write(output_unit, '(a,a)') trim(indent_str), 'If statement node'

    case(NODE_PIPELINE)
      write(output_unit, '(a,a)') trim(indent_str), 'Pipeline node'

    case(NODE_BREAK)
      write(output_unit, '(a,a)') trim(indent_str), 'Break node'

    case(NODE_CONTINUE)
      write(output_unit, '(a,a)') trim(indent_str), 'Continue node'

    case default
      write(output_unit, '(a,a,i0)') trim(indent_str), 'Node type: ', node%node_type
    end select

  end subroutine print_node_info

  ! Check if AST mode is enabled
  logical function is_ast_mode()
    is_ast_mode = use_ast_mode
  end function is_ast_mode

  ! Enable/disable AST mode programmatically
  subroutine set_ast_mode(enabled)
    logical, intent(in) :: enabled

    use_ast_mode = enabled
    if (enabled) then
      write(output_unit, '(a)') 'AST mode enabled'
    else
      write(output_unit, '(a)') 'AST mode disabled (using legacy execution)'
    end if
  end subroutine set_ast_mode

end module ast_bridge