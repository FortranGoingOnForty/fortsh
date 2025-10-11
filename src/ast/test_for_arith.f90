program test_for_arith
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  character(:), allocatable :: input
  integer :: test_count, pass_count
  type(for_arith_node_t), pointer :: for_arith_ptr

  test_count = 0
  pass_count = 0

  print *, "========================================="
  print *, "Arithmetic For Loop Parser Tests"
  print *, "========================================="
  print *, ""

  ! Test 1: Parse basic arithmetic for loop
  print *, "=== Test 1: Parse 'for ((i=0; i<3; i++)); do echo $i; done' ==="
  input = 'for ((i=0; i<3; i++)); do echo $i; done'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements > 0) then
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (for_arith_node_t)
        for_arith_ptr => node
        if (allocated(for_arith_ptr%init_expr) .and. &
            allocated(for_arith_ptr%cond_expr) .and. &
            allocated(for_arith_ptr%incr_expr)) then
          print *, "  Init: ", trim(for_arith_ptr%init_expr)
          print *, "  Cond: ", trim(for_arith_ptr%cond_expr)
          print *, "  Incr: ", trim(for_arith_ptr%incr_expr)
          print *, "PASS: Arithmetic for loop parsed correctly"
          pass_count = pass_count + 1
        else
          print *, "FAIL: Expressions not allocated"
        end if
      class default
        print *, "FAIL: Not a for_arith node"
      end select
    else
      print *, "FAIL: Statement pointer not associated"
    end if
  else
    print *, "FAIL: No statements parsed"
  end if
  print *, ""

  ! Test 2: Parse for loop with complex expressions
  print *, "=== Test 2: Parse 'for ((x=1; x<=5; x=x+2)); do echo x; done' ==="
  input = 'for ((x=1; x<=5; x=x+2)); do echo x; done'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements > 0) then
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (for_arith_node_t)
        for_arith_ptr => node
        if (allocated(for_arith_ptr%init_expr) .and. &
            allocated(for_arith_ptr%cond_expr) .and. &
            allocated(for_arith_ptr%incr_expr)) then
          print *, "  Init: ", trim(for_arith_ptr%init_expr)
          print *, "  Cond: ", trim(for_arith_ptr%cond_expr)
          print *, "  Incr: ", trim(for_arith_ptr%incr_expr)
          print *, "PASS: Complex arithmetic for loop parsed"
          pass_count = pass_count + 1
        else
          print *, "FAIL: Expressions not allocated"
        end if
      class default
        print *, "FAIL: Not a for_arith node"
      end select
    else
      print *, "FAIL: Statement pointer not associated"
    end if
  else
    print *, "FAIL: No statements parsed"
  end if
  print *, ""

  ! Test 3: Distinguish from regular for loop
  print *, "=== Test 3: Parse regular 'for x in a b c; do echo $x; done' ==="
  input = 'for x in a b c; do echo $x; done'
  call lex%init(input)
  call lex%tokenize()
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()

  test_count = test_count + 1
  if (allocated(ast%statements) .and. ast%num_statements > 0) then
    if (associated(ast%statements(1)%ptr)) then
      select type(node => ast%statements(1)%ptr)
      type is (for_node_t)
        print *, "PASS: Regular for loop parsed (not arithmetic)"
        pass_count = pass_count + 1
      type is (for_arith_node_t)
        print *, "FAIL: Incorrectly parsed as arithmetic for loop"
      class default
        print *, "FAIL: Wrong node type"
      end select
    else
      print *, "FAIL: Statement pointer not associated"
    end if
  else
    print *, "FAIL: No statements parsed"
  end if
  print *, ""

  call lex%destroy()
  call pars%destroy()

  print *, "========================================="
  write(*, '(a,i0,a,i0,a)') " Tests passed: ", pass_count, " / ", test_count, " total"
  print *, "========================================="

end program test_for_arith
