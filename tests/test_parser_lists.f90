! ==============================================================================
! Test program for parser with linked list node collection
! ==============================================================================
program test_parser_lists
  use ast_types
  use lexer
  use parser
  implicit none

  call test_simple_command()
  call test_for_loop_collection()
  call test_nested_commands()

  print *, ""
  print *, "=== All parser list tests passed! ==="

contains

  subroutine test_simple_command()
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    character(:), allocatable :: input

    print *, "=== Test: Simple Command with Arguments ==="

    input = 'echo hello world'
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

      ! Check the first statement is a command
      select type(stmt => ast%statements(1))
      type is (command_node_t)
        print *, "  First statement is a COMMAND"
        if (allocated(stmt%words)) then
          print *, "  Number of words: ", size(stmt%words)

          ! Print each word
          block
            integer :: i
            do i = 1, size(stmt%words)
              select type(w => stmt%words(i))
              type is (word_node_t)
                print *, "    Word ", i, ": ", w%text
              end select
            end do
          end block
        end if
      class default
        print *, "  First statement type: ", stmt%node_type
      end select
    else
      print *, "No statements parsed"
    end if
    print *, ""

    call lex%destroy()
    call pars%destroy()
  end subroutine test_simple_command

  subroutine test_for_loop_collection()
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    character(:), allocatable :: input

    print *, "=== Test: For Loop Word Collection ==="

    input = 'for item in apple banana cherry' // char(10) // &
            'do' // char(10) // &
            '  echo $item' // char(10) // &
            'done'
    print *, "Input: for loop with 3 items"

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
        print *, "  First statement is a FOR loop"
        print *, "  Variable: ", stmt%variable
        if (allocated(stmt%word_list)) then
          print *, "  Number of items in word list: ", size(stmt%word_list)

          ! Print each word in the list
          block
            integer :: i
            do i = 1, size(stmt%word_list)
              select type(w => stmt%word_list(i))
              type is (word_node_t)
                print *, "    Item ", i, ": ", w%text
              end select
            end do
          end block
        else
          print *, "  No word list collected"
        end if
        if (allocated(stmt%body)) then
          print *, "  Number of body commands: ", size(stmt%body)
        else
          print *, "  No body commands collected"
        end if
      class default
        print *, "  First statement type: ", stmt%node_type
      end select
    end if
    print *, ""

    call lex%destroy()
    call pars%destroy()
  end subroutine test_for_loop_collection

  subroutine test_nested_commands()
    type(lexer_t) :: lex
    type(parser_t) :: pars
    type(script_node_t) :: ast
    character(:), allocatable :: input

    print *, "=== Test: Multiple Commands ==="

    input = 'echo first' // char(10) // &
            'echo second' // char(10) // &
            'echo third'
    print *, "Input: three echo commands"

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

      ! Check each statement
      block
        integer :: i
        do i = 1, size(ast%statements)
          select type(stmt => ast%statements(i))
          type is (command_node_t)
            print *, "  Statement ", i, " is a COMMAND"
            if (allocated(stmt%words)) then
              print *, "    Words: ", size(stmt%words)
            end if
          class default
            print *, "  Statement ", i, " type: ", stmt%node_type
          end select
        end do
      end block
    else
      print *, "No statements parsed"
    end if
    print *, ""

    call lex%destroy()
    call pars%destroy()
  end subroutine test_nested_commands

end program test_parser_lists