program test_proc_subst
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  implicit none

  type(lexer_simple_t) :: lexer
  type(parser_enhanced_t) :: parser
  type(script_node_t) :: ast
  integer :: test_count, pass_count

  test_count = 0
  pass_count = 0

  print *, "=== Process Substitution Parser Tests ==="
  print *, ""

  ! Test 1: Input substitution <(command)
  test_count = test_count + 1
  if (test_parse_proc_subst("diff <(ls dir1) <(ls dir2)", 2, .true.)) then
    pass_count = pass_count + 1
  end if

  ! Test 2: Output substitution >(command)
  test_count = test_count + 1
  if (test_parse_proc_subst("tee >(wc -l)", 1, .false.)) then
    pass_count = pass_count + 1
  end if

  ! Test 3: Mixed input/output substitution
  test_count = test_count + 1
  if (test_parse_proc_subst("cat <(echo hello) >(cat > output.txt)", 2, .true.)) then
    pass_count = pass_count + 1
  end if

  ! Print summary
  print *, ""
  print *, "=== Test Summary ==="
  print *, "Passed:", pass_count, "/", test_count
  if (pass_count == test_count) then
    print *, "✓ All tests PASSED!"
    stop 0
  else
    print *, "✗", test_count - pass_count, "tests FAILED"
    stop 1
  end if

contains

  logical function test_parse_proc_subst(input, expected_proc_subst_count, first_is_input)
    character(*), intent(in) :: input
    integer, intent(in) :: expected_proc_subst_count
    logical, intent(in) :: first_is_input
    type(lexer_simple_t) :: test_lexer
    type(parser_enhanced_t) :: test_parser
    type(script_node_t) :: test_ast
    integer :: proc_subst_count, i, j
    logical :: found_proc_subst, correct_direction

    test_parse_proc_subst = .false.
    proc_subst_count = 0
    found_proc_subst = .false.
    correct_direction = .false.

    ! Tokenize
    call test_lexer%init(input)
    call test_lexer%tokenize()

    ! Parse
    call test_parser%init(test_lexer%tokens, test_lexer%token_count)
    test_ast = test_parser%parse()

    ! Count process substitutions in the AST
    if (test_ast%num_statements > 0) then
      ! Navigate through the AST to find command nodes
      do i = 1, test_ast%num_statements
        if (associated(test_ast%statements(i)%ptr)) then
          select type(stmt => test_ast%statements(i)%ptr)
          type is (command_node_t)
            ! Check words for process substitution nodes
            if (allocated(stmt%words)) then
              do j = 1, stmt%num_words
                if (associated(stmt%words(j)%ptr)) then
                  select type(word => stmt%words(j)%ptr)
                  type is (proc_subst_node_t)
                    proc_subst_count = proc_subst_count + 1
                    found_proc_subst = .true.
                    if (proc_subst_count == 1) then
                      correct_direction = (word%is_input .eqv. first_is_input)
                    end if
                  end select
                end if
              end do
            end if
          end select
        end if
      end do
    end if

    ! Check results
    if (proc_subst_count == expected_proc_subst_count .and. &
        found_proc_subst .and. correct_direction) then
      print *, "✓ PASS: '", trim(input), "'"
      print *, "  Found", proc_subst_count, "process substitution(s)"
      test_parse_proc_subst = .true.
    else
      print *, "✗ FAIL: '", trim(input), "'"
      print *, "  Expected", expected_proc_subst_count, "process substitutions"
      print *, "  Found", proc_subst_count
    end if

    ! Cleanup
    call test_lexer%destroy()
    call test_parser%destroy()

  end function test_parse_proc_subst

end program test_proc_subst
