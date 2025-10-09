! ==============================================================================
! Test program for AST bridge
! ==============================================================================
program test_ast_bridge
  use ast_types
  use shell_types  ! Use the actual shell_types module
  use lexer
  use parser
  use ast_bridge
  use iso_fortran_env, only: output_unit
  implicit none

  type(shell_state_t) :: shell
  character(:), allocatable :: test_cmd
  integer :: exit_code

  print *, "=== AST Bridge Test Program ==="
  print *, ""

  ! Initialize shell state
  shell%username = "testuser"
  shell%hostname = "testhost"
  shell%cwd = "/home/testuser"
  shell%is_interactive = .false.
  shell%running = .true.
  shell%last_exit_status = 0
  shell%num_variables = 0
  shell%control_depth = 0

  ! Test 1: Basic command parsing
  print *, "Test 1: Parsing simple command"
  test_cmd = 'echo hello world'
  call print_ast_debug(test_cmd)
  print *, ""

  ! Test 2: For loop parsing
  print *, "Test 2: Parsing for loop"
  test_cmd = 'for x in a b c; do echo $x; done'
  call print_ast_debug(test_cmd)
  print *, ""

  ! Test 3: Conditional parsing
  print *, "Test 3: Parsing if statement"
  test_cmd = 'if true; then echo yes; else echo no; fi'
  call print_ast_debug(test_cmd)
  print *, ""

  ! Test 4: Pipeline parsing - Skip for now as parser doesn't handle pipes yet
  print *, "Test 4: Pipeline parsing - skipped (not implemented)"
  print *, ""

  ! Test 5: Enable AST mode and try execution
  print *, "Test 5: AST mode execution (limited)"
  call set_ast_mode(.true.)

  test_cmd = 'echo testing'
  exit_code = execute_with_ast(test_cmd, shell)
  print *, "Exit code:", exit_code
  print *, ""

  ! Test 6: Break and continue
  print *, "Test 6: Parsing break/continue"
  test_cmd = 'for i in 1 2 3; do echo $i; break; done'
  call print_ast_debug(test_cmd)
  print *, ""

  ! Test 7: While loop
  print *, "Test 7: Parsing while loop"
  test_cmd = 'while true; do echo loop; break; done'
  call print_ast_debug(test_cmd)
  print *, ""

  print *, "=== All AST bridge tests completed ==="

end program test_ast_bridge