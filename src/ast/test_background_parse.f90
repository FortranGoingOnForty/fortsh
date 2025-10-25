program test_background_parse
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  character(:), allocatable :: input
  integer :: test_count, pass_count
  type(command_node_t), pointer :: cmd_ptr
  type(pipeline_node_t), pointer :: pipe_ptr

  test_count = 0
  pass_count = 0

  print *, "========================================="
  print *, "Background Job Parser Tests"
  print *, "========================================="
  print *, ""

  ! Test 1: Parse simple background command
  print *, "=== Test 1: Parse 'echo hello &' ==="
  input = 'echo hello &'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements > 0) then
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (command_node_t)
        cmd_ptr => node
        if (cmd_ptr%background) then
          print *, "PASS: Background flag set correctly"
          pass_count = pass_count + 1
        else
          print *, "FAIL: Background flag not set"
        end if
      class default
        print *, "FAIL: Not a command node"
      end select
    else
      print *, "FAIL: Statement pointer not associated"
    end if
  else
    print *, "FAIL: No statements parsed"
  end if
  print *, ""

  ! Test 2: Parse background pipeline
  print *, "=== Test 2: Parse 'echo hello | cat &' ==="
  input = 'echo hello | cat &'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements > 0) then
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (pipeline_node_t)
        pipe_ptr => node
        if (pipe_ptr%background) then
          print *, "PASS: Pipeline background flag set"
          pass_count = pass_count + 1
        else
          print *, "FAIL: Pipeline background flag not set"
        end if
      class default
        print *, "FAIL: Not a pipeline node"
      end select
    else
      print *, "FAIL: Statement pointer not associated"
    end if
  else
    print *, "FAIL: No statements parsed"
  end if
  print *, ""

  ! Test 3: Parse foreground command (no &)
  print *, "=== Test 3: Parse 'echo hello' (foreground) ==="
  input = 'echo hello'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements > 0) then
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (command_node_t)
        cmd_ptr => node
        if (.not. cmd_ptr%background) then
          print *, "PASS: Background flag not set (foreground)"
          pass_count = pass_count + 1
        else
          print *, "FAIL: Background flag incorrectly set"
        end if
      class default
        print *, "FAIL: Not a command node"
      end select
    else
      print *, "FAIL: Statement pointer not associated"
    end if
  else
    print *, "FAIL: No statements parsed"
  end if
  print *, ""

  ! Test 4: Multiple commands, one background
  print *, "=== Test 4: Parse 'echo a &; echo b' ==="
  input = 'echo a &; echo b'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements >= 2) then
    ! First should be background
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (command_node_t)
        cmd_ptr => node
        if (cmd_ptr%background) then
          ! Second should be foreground
          if (associated(ast%statements(2)%ptr)) then
            select type(node2 => ast%statements(2)%ptr)
            type is (command_node_t)
              if (.not. node2%background) then
                print *, "PASS: Mixed background/foreground parsed"
                pass_count = pass_count + 1
              else
                print *, "FAIL: Second command incorrectly background"
              end if
            class default
              print *, "FAIL: Second not a command node"
            end select
          else
            print *, "FAIL: Second statement not associated"
          end if
        else
          print *, "FAIL: First command not background"
        end if
      class default
        print *, "FAIL: First not a command node"
      end select
    else
      print *, "FAIL: First statement not associated"
    end if
  else
    print *, "FAIL: Not enough statements parsed"
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()

  print *, "========================================="
  write(*, '(a,i15,a,i15,a)') " Tests passed: ", pass_count, " / ", test_count, " total"
  print *, "========================================="

end program test_background_parse
