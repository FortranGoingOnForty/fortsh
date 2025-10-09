! ==============================================================================
! Test program for AST-based execution model
! Demonstrates how nested loops and break/continue would work
! ==============================================================================
program test_ast
  use ast_types
  use lexer
  use parser
  use evaluator
  use shell_types
  implicit none

  ! Test nested loops with break
  call test_nested_loops_with_break()

  ! Test for loop with continue
  call test_for_loop_with_continue()

  ! Test proper parsing
  call test_parser()

contains

  subroutine test_nested_loops_with_break()
    character(:), allocatable :: script
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(evaluator_t) :: eval
    type(shell_state_t) :: shell
    type(script_node_t) :: ast
    integer :: exit_code

    print *, "=== Test: Nested loops with break ==="

    ! Script with nested loops and break
    script = &
      'for i in 1 2 3' // char(10) // &
      'do' // char(10) // &
      '  echo "Outer: $i"' // char(10) // &
      '  for j in a b c' // char(10) // &
      '  do' // char(10) // &
      '    echo "  Inner: $j"' // char(10) // &
      '    [ "$j" = "b" ] && break' // char(10) // &
      '  done' // char(10) // &
      '  echo "Back in outer"' // char(10) // &
      'done'

    ! Tokenize
    call lex%init(script)
    call lex%tokenize()

    print *, "Tokens generated: ", lex%token_count

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    print *, "AST built successfully"

    ! Evaluate
    call eval%init(shell)
    exit_code = eval%eval(ast)

    print *, "Exit code: ", exit_code
    print *, ""

    ! Clean up
    call lex%destroy()
    call pars%destroy()
    call eval%destroy()
  end subroutine test_nested_loops_with_break

  subroutine test_for_loop_with_continue()
    character(:), allocatable :: script
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(evaluator_t) :: eval
    type(shell_state_t) :: shell
    type(script_node_t) :: ast
    integer :: exit_code

    print *, "=== Test: For loop with continue ==="

    script = &
      'for i in 1 2 3 4 5' // char(10) // &
      'do' // char(10) // &
      '  [ "$i" = "3" ] && continue' // char(10) // &
      '  echo "Processing: $i"' // char(10) // &
      'done'

    ! Tokenize
    call lex%init(script)
    call lex%tokenize()

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    ! Evaluate
    call eval%init(shell)
    exit_code = eval%eval(ast)

    print *, "Exit code: ", exit_code
    print *, ""

    ! Clean up
    call lex%destroy()
    call pars%destroy()
    call eval%destroy()
  end subroutine test_for_loop_with_continue

  subroutine test_parser()
    character(:), allocatable :: script
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    integer :: i

    print *, "=== Test: Parser functionality ==="

    ! Simple script
    script = &
      'echo "Hello World"' // char(10) // &
      'if [ -f test.txt ]' // char(10) // &
      'then' // char(10) // &
      '  cat test.txt' // char(10) // &
      'else' // char(10) // &
      '  echo "No file"' // char(10) // &
      'fi'

    ! Tokenize
    call lex%init(script)
    call lex%tokenize()

    print *, "Generated tokens:"
    do i = 1, min(10, lex%token_count)
      print '(a,i3,a,i2,a,a)', &
        "  Token ", i, " type=", lex%tokens(i)%type, &
        " value=", trim(lex%tokens(i)%value)
    end do

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    print *, "AST structure:"
    call print_ast_structure(ast)
    print *, ""

    ! Clean up
    call lex%destroy()
    call pars%destroy()
  end subroutine test_parser

  recursive subroutine print_ast_structure(node, indent)
    class(ast_node_t), intent(in) :: node
    integer, intent(in), optional :: indent
    integer :: ind, i

    ind = 0
    if (present(indent)) ind = indent

    ! Print node type
    write(*, '(a,a,i0)', advance='no') repeat(' ', ind*2), 'Node type: ', node%node_type

    select type(node)
    type is (script_node_t)
      print *, ' (SCRIPT)'
      if (allocated(node%statements)) then
        do i = 1, size(node%statements)
          call print_ast_structure(node%statements(i), ind+1)
        end do
      end if

    type is (for_node_t)
      print *, ' (FOR loop) var=', trim(node%variable)
      if (allocated(node%body)) then
        do i = 1, size(node%body)
          call print_ast_structure(node%body(i), ind+1)
        end do
      end if

    type is (if_node_t)
      print *, ' (IF statement)'
      if (allocated(node%then_branch)) then
        write(*, '(a)') repeat(' ', (ind+1)*2) // 'THEN:'
        do i = 1, size(node%then_branch)
          call print_ast_structure(node%then_branch(i), ind+2)
        end do
      end if
      if (allocated(node%else_branch)) then
        write(*, '(a)') repeat(' ', (ind+1)*2) // 'ELSE:'
        do i = 1, size(node%else_branch)
          call print_ast_structure(node%else_branch(i), ind+2)
        end do
      end if

    type is (command_node_t)
      print *, ' (COMMAND)'
      if (allocated(node%words)) then
        do i = 1, size(node%words)
          select type(word => node%words(i))
          type is (word_node_t)
            write(*, '(a,a)') repeat(' ', (ind+1)*2) // 'Word: ', trim(word%text)
          end select
        end do
      end if

    type is (break_node_t)
      print *, ' (BREAK) levels=', node%levels

    type is (continue_node_t)
      print *, ' (CONTINUE) levels=', node%levels

    class default
      print *, ''
    end select
  end subroutine print_ast_structure

end program test_ast