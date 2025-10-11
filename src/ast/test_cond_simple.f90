program test_cond_simple
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: parser
  character(:), allocatable :: input
  class(ast_node_t), pointer :: result
  integer :: test_count, pass_count

  test_count = 0
  pass_count = 0

  print *, "=== Conditional Expression Parser Tests ==="
  print *, ""

  ! Test 1: Simple file test
  test_count = test_count + 1
  print *, "Test 1: [[ -f file.txt ]]"
  input = '[[ -f file.txt ]]'
  if (test_parse(input, "cond_expr")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 2: String comparison
  test_count = test_count + 1
  print *, "Test 2: [[ $var == value ]]"
  input = '[[ $var == value ]]'
  if (test_parse(input, "cond_expr")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 3: Integer comparison
  test_count = test_count + 1
  print *, "Test 3: [[ $num -lt 10 ]]"
  input = '[[ $num -lt 10 ]]'
  if (test_parse(input, "cond_expr")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 4: Pattern matching
  test_count = test_count + 1
  print *, "Test 4: [[ $file == *.txt ]]"
  input = '[[ $file == *.txt ]]'
  if (test_parse(input, "cond_expr")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 5: Complex expression with &&
  test_count = test_count + 1
  print *, "Test 5: [[ -f file && -r file ]]"
  input = '[[ -f file && -r file ]]'
  if (test_parse(input, "cond_expr")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Print summary
  print *, "=== Test Summary ==="
  print *, "Passed:", pass_count, "/", test_count
  if (pass_count == test_count) then
    print *, "✓ All tests PASSED!"
    stop 0
  else
    print *, "✗ Some tests FAILED"
    stop 1
  end if

contains
  logical function test_parse(cmd, expected_type)
    character(*), intent(in) :: cmd
    character(*), intent(in) :: expected_type
    class(ast_node_t), pointer :: node

    call lex%init(cmd)
    call lex%tokenize()
    call parser%init(lex%tokens, lex%token_count)
    node => parser%parse_command()

    test_parse = .false.

    if (associated(node)) then
      select type(node)
      type is (cond_expr_node_t)
        if (expected_type == "cond_expr") then
          print *, "✓ Parsed as cond_expr_node_t"
          print *, "  Expression: '", trim(node%expression), "'"
          test_parse = .true.
        else
          print *, "✗ Wrong type: got cond_expr_node_t"
        end if
      class default
        print *, "✗ Wrong node type, expected:", trim(expected_type)
      end select
      deallocate(node)
    else
      print *, "✗ Parser returned null"
    end if

    call parser%destroy()
    call lex%destroy()
  end function test_parse

end program test_cond_simple
