! ==============================================================================
! Simple parser test
! ==============================================================================
program test_parser_simple
  use ast_types
  use lexer
  use parser
  implicit none

  call test_simple_command()
  call test_for_loop()
  call test_nested_structure()

contains

  subroutine test_simple_command()
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    character(:), allocatable :: input

    print *, "=== Test: Simple Command ==="

    input = 'echo "Hello World"'
    print *, "Input: ", input

    ! Tokenize
    call lex%init(input)
    call lex%tokenize()
    print *, "Tokens: ", lex%token_count

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    print *, "AST created successfully"
    if (allocated(ast%statements)) then
      print *, "Number of statements: ", size(ast%statements)
    end if
    print *, ""

    call lex%destroy()
    call pars%destroy()
  end subroutine test_simple_command

  subroutine test_for_loop()
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    character(:), allocatable :: input

    print *, "=== Test: For Loop ==="

    input = 'for i in 1 2 3' // char(10) // &
            'do' // char(10) // &
            '  echo $i' // char(10) // &
            'done'
    print *, "Input: for loop with echo"

    ! Tokenize
    call lex%init(input)
    call lex%tokenize()
    print *, "Tokens: ", lex%token_count

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    print *, "AST created successfully"
    if (allocated(ast%statements)) then
      print *, "Number of statements: ", size(ast%statements)

      ! Check if first statement is a for loop
      select type(stmt => ast%statements(1))
      type is (for_node_t)
        print *, "First statement is a FOR loop"
        print *, "Variable: ", stmt%variable
        if (allocated(stmt%word_list)) then
          print *, "Number of items: ", size(stmt%word_list)
        end if
        if (allocated(stmt%body)) then
          print *, "Number of body commands: ", size(stmt%body)
        end if
      class default
        print *, "First statement type: ", stmt%node_type
      end select
    end if
    print *, ""

    call lex%destroy()
    call pars%destroy()
  end subroutine test_for_loop

  subroutine test_nested_structure()
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    character(:), allocatable :: input

    print *, "=== Test: Nested Structure ==="

    input = 'for i in 1 2' // char(10) // &
            'do' // char(10) // &
            '  for j in a b' // char(10) // &
            '  do' // char(10) // &
            '    echo "$i $j"' // char(10) // &
            '  done' // char(10) // &
            'done'
    print *, "Input: nested for loops"

    ! Tokenize
    call lex%init(input)
    call lex%tokenize()
    print *, "Tokens: ", lex%token_count

    ! Parse
    call pars%init(lex%tokens, lex%token_count)
    ast = pars%parse()

    print *, "AST created successfully"
    if (allocated(ast%statements)) then
      print *, "Number of statements: ", size(ast%statements)

      ! Check structure
      select type(stmt => ast%statements(1))
      type is (for_node_t)
        print *, "Outer loop variable: ", stmt%variable
        if (allocated(stmt%body)) then
          print *, "Outer body commands: ", size(stmt%body)

          ! Check if inner loop exists
          select type(inner => stmt%body(1))
          type is (for_node_t)
            print *, "Inner loop variable: ", inner%variable
            if (allocated(inner%body)) then
              print *, "Inner body commands: ", size(inner%body)
            end if
          class default
            print *, "Inner statement type: ", inner%node_type
          end select
        end if
      class default
        print *, "First statement type: ", stmt%node_type
      end select
    end if
    print *, ""

    call lex%destroy()
    call pars%destroy()
  end subroutine test_nested_structure

end program test_parser_simple