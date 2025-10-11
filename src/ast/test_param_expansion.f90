program test_param_expansion
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

  print *, "=== Parameter Expansion Parser Tests ==="
  print *, ""

  ! Test 1: Default value
  test_count = test_count + 1
  print *, "Test 1: ${var:-default}"
  input = 'echo ${var:-default}'
  if (test_expansion("var", MOD_USE_DEFAULT, "default")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 2: Assign default
  test_count = test_count + 1
  print *, "Test 2: ${var:=default}"
  input = 'echo ${var:=default}'
  if (test_expansion("var", MOD_ASSIGN_DEFAULT, "default")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 3: String length
  test_count = test_count + 1
  print *, "Test 3: ${#var}"
  input = 'echo ${#var}'
  if (test_expansion("var", MOD_STRING_LENGTH, "")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 4: Remove prefix
  test_count = test_count + 1
  print *, "Test 4: ${var#pattern}"
  input = 'echo ${var#pattern}'
  if (test_expansion("var", MOD_REMOVE_PREFIX_MIN, "pattern")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 5: Remove longest prefix
  test_count = test_count + 1
  print *, "Test 5: ${var##pattern}"
  input = 'echo ${var##pattern}'
  if (test_expansion("var", MOD_REMOVE_PREFIX_MAX, "pattern")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 6: Remove suffix
  test_count = test_count + 1
  print *, "Test 6: ${var%pattern}"
  input = 'echo ${var%pattern}'
  if (test_expansion("var", MOD_REMOVE_SUFFIX_MIN, "pattern")) then
    pass_count = pass_count + 1
  end if
  print *, ""

  ! Test 7: Substring
  test_count = test_count + 1
  print *, "Test 7: ${var:3:5}"
  input = 'echo ${var:3:5}'
  if (test_expansion("var", MOD_SUBSTRING, "3:5")) then
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
  logical function test_expansion(expected_var, expected_mod, expected_val)
    character(*), intent(in) :: expected_var, expected_val
    integer, intent(in) :: expected_mod
    class(ast_node_t), pointer :: cmd_node, word_node

    test_expansion = .false.

    call lex%init(input)
    call lex%tokenize()
    call parser%init(lex%tokens, lex%token_count)
    cmd_node => parser%parse_command()

    if (.not. associated(cmd_node)) then
      print *, "✗ Parser returned null"
      return
    end if

    select type(cmd_node)
    type is (command_node_t)
      ! Should have at least 2 words: "echo" and "${var...}"
      if (cmd_node%num_words < 2) then
        print *, "✗ Not enough words parsed, got", cmd_node%num_words
        deallocate(cmd_node)
        return
      end if

      ! Check the second word (first is "echo")
      word_node => cmd_node%words(2)%ptr
      if (.not. associated(word_node)) then
        print *, "✗ Second word is null"
        deallocate(cmd_node)
        return
      end if

      select type(word_node)
      type is (variable_node_t)
        if (trim(word_node%name) /= trim(expected_var)) then
          print *, "✗ Variable name mismatch: got '", trim(word_node%name), &
                   "', expected '", trim(expected_var), "'"
          deallocate(cmd_node)
          return
        end if

        if (word_node%modifier_type /= expected_mod) then
          print *, "✗ Modifier type mismatch: got", word_node%modifier_type, &
                   ", expected", expected_mod
          deallocate(cmd_node)
          return
        end if

        if (trim(word_node%modifier) /= trim(expected_val)) then
          print *, "✗ Modifier value mismatch: got '", trim(word_node%modifier), &
                   "', expected '", trim(expected_val), "'"
          deallocate(cmd_node)
          return
        end if

        print *, "✓ Parsed correctly:"
        print *, "  Variable:", trim(word_node%name)
        print *, "  Modifier type:", word_node%modifier_type
        print *, "  Modifier value: '", trim(word_node%modifier), "'"
        test_expansion = .true.

      class default
        print *, "✗ Second word is not a variable"
      end select

    class default
      print *, "✗ Not a command node"
    end select

    deallocate(cmd_node)
    call parser%destroy()
    call lex%destroy()
  end function test_expansion

end program test_param_expansion
