! ==============================================================================
! Simplified test program for Phase 6 - Parser with memory pooling
! ==============================================================================
program test_parser_simple
  use string_pool
  use memory_dashboard
  use pooled_types
  use shell_types
  use iso_fortran_env, only: output_unit
  implicit none

  type(pooled_command_t) :: cmd
  integer :: i
  character(:), pointer :: token_ptr, str_ptr
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate

  test_passed = .true.

  print *, "=== Phase 6 Parser Memory Pooling Test (Simplified) ==="
  print *, "Testing pooled command types with memory dashboard"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Test 1: Create and populate a pooled command
  print *, "Test 1: Creating pooled command with tokens..."
  call init_pooled_command(cmd)

  ! Allocate tokens
  call allocate_pooled_tokens(cmd, 4, MAX_TOKEN_LEN)
  call set_pooled_token(cmd, 1, "ls")
  call set_pooled_token(cmd, 2, "-la")
  call set_pooled_token(cmd, 3, "/tmp")
  call set_pooled_token(cmd, 4, "testdir")

  ! Verify tokens
  print *, "  Tokens allocated:", cmd%num_tokens
  do i = 1, cmd%num_tokens
    token_ptr => get_pooled_token(cmd, i)
    if (associated(token_ptr)) then
      print *, "    Token", i, ":", trim(token_ptr)
    else
      print *, "    Token", i, ": NULL"
      test_passed = .false.
    end if
  end do

  ! Test 2: Set string fields
  print *, ""
  print *, "Test 2: Setting string fields..."
  call set_pooled_string(cmd%input_file, "input.txt", MOD_PARSER)
  call set_pooled_string(cmd%output_file, "output.txt", MOD_PARSER)
  call set_pooled_string(cmd%error_file, "error.log", MOD_PARSER)
  call set_pooled_string(cmd%heredoc_delimiter, "EOF", MOD_PARSER)
  call set_pooled_string(cmd%heredoc_content, "This is heredoc content"//new_line('a')//"Multiple lines", MOD_PARSER)

  ! Verify string fields
  str_ptr => get_pooled_string(cmd%input_file)
  if (associated(str_ptr)) then
    print *, "  Input file:", trim(str_ptr)
    if (trim(str_ptr) /= "input.txt") test_passed = .false.
  else
    print *, "  Input file: NULL"
    test_passed = .false.
  end if

  str_ptr => get_pooled_string(cmd%output_file)
  if (associated(str_ptr)) then
    print *, "  Output file:", trim(str_ptr)
    if (trim(str_ptr) /= "output.txt") test_passed = .false.
  else
    print *, "  Output file: NULL"
    test_passed = .false.
  end if

  str_ptr => get_pooled_string(cmd%error_file)
  if (associated(str_ptr)) then
    print *, "  Error file:", trim(str_ptr)
    if (trim(str_ptr) /= "error.log") test_passed = .false.
  else
    print *, "  Error file: NULL"
    test_passed = .false.
  end if

  ! Test 3: Memory statistics before release
  print *, ""
  print *, "Test 3: Checking memory statistics before release..."
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)
  print *, "  Current strings in pool:", current_strings
  print *, "  Peak strings:", peak_strings
  print *, "  Cache hit rate:", int(hit_rate * 100), "%"

  if (current_strings > 0) then
    print *, "  PASSED: Strings are allocated in pool"
  else
    print *, "  FAILED: No strings in pool"
    test_passed = .false.
  end if

  ! Test 4: Release the command
  print *, ""
  print *, "Test 4: Releasing pooled command..."
  call release_pooled_command(cmd)

  ! Check that everything was released
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)
  print *, "  Current strings after release:", current_strings

  if (current_strings == 0) then
    print *, "  PASSED: All strings released (no memory leak)"
  else
    print *, "  FAILED: Memory leak -", current_strings, "strings still allocated"
    test_passed = .false.
  end if

  ! Test 5: Stress test - rapid allocations and deallocations
  print *, ""
  print *, "Test 5: Stress testing with 1000 allocate/release cycles..."
  do i = 1, 1000
    call init_pooled_command(cmd)
    call allocate_pooled_tokens(cmd, 3, 64)
    call set_pooled_token(cmd, 1, "test")
    call set_pooled_token(cmd, 2, "command")
    call set_pooled_token(cmd, 3, "tokens")
    call set_pooled_string(cmd%output_file, "test_output.txt", MOD_PARSER)
    call release_pooled_command(cmd)
  end do

  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)
  print *, "  Total allocations:", total_allocs
  print *, "  Total deallocations:", total_deallocs
  print *, "  Current strings:", current_strings
  print *, "  Cache hit rate:", int(hit_rate * 100), "%"

  if (current_strings == 0 .and. hit_rate > 0.95) then
    print *, "  PASSED: No leaks and excellent cache hit rate"
  else if (current_strings == 0) then
    print *, "  PASSED: No memory leaks"
  else
    print *, "  FAILED: Memory leak detected"
    test_passed = .false.
  end if

  ! Test 6: Test conversion from legacy command
  print *, ""
  print *, "Test 6: Testing conversion from legacy command_t..."
  block
    type(command_t) :: legacy_cmd
    type(pooled_command_t) :: pooled_cmd

    ! Create a legacy command
    allocate(character(len=MAX_TOKEN_LEN) :: legacy_cmd%tokens(3))
    legacy_cmd%tokens(1) = "echo"
    legacy_cmd%tokens(2) = "Hello"
    legacy_cmd%tokens(3) = "World"
    legacy_cmd%num_tokens = 3
    allocate(character(len=10) :: legacy_cmd%input_file)
    legacy_cmd%input_file = "input.txt"
    allocate(character(len=11) :: legacy_cmd%output_file)
    legacy_cmd%output_file = "output.txt"

    ! Convert to pooled
    call convert_to_pooled_command(legacy_cmd, pooled_cmd)

    ! Verify conversion
    token_ptr => get_pooled_token(pooled_cmd, 1)
    if (associated(token_ptr) .and. trim(token_ptr) == "echo") then
      print *, "  Token conversion: PASSED"
    else
      print *, "  Token conversion: FAILED"
      test_passed = .false.
    end if

    str_ptr => get_pooled_string(pooled_cmd%input_file)
    if (associated(str_ptr) .and. trim(str_ptr) == "input.txt") then
      print *, "  String field conversion: PASSED"
    else
      print *, "  String field conversion: FAILED"
      test_passed = .false.
    end if

    ! Clean up
    call release_pooled_command(pooled_cmd)
    if (allocated(legacy_cmd%tokens)) deallocate(legacy_cmd%tokens)
    if (allocated(legacy_cmd%input_file)) deallocate(legacy_cmd%input_file)
    if (allocated(legacy_cmd%output_file)) deallocate(legacy_cmd%output_file)
  end block

  ! Display dashboard
  print *, ""
  print *, "=== Memory Dashboard Display ==="
  call dashboard_display(detailed=.false.)

  ! Final check
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)

  ! Export statistics
  call dashboard_export_csv("parser_pooling_test.csv")
  print *, ""
  print *, "Statistics exported to parser_pooling_test.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  print *, "=== Test Summary ==="
  if (test_passed .and. current_strings == 0) then
    print *, "✅ ALL TESTS PASSED"
    print *, ""
    print *, "Parser pooling integration verified:"
    print *, "  • Pooled tokens working correctly"
    print *, "  • Pooled string fields working correctly"
    print *, "  • No memory leaks detected"
    print *, "  • Dashboard integration successful"
    print *, "  • Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "Ready to integrate into production parser!"
  else
    print *, "❌ SOME TESTS FAILED"
    if (current_strings > 0) then
      print *, "  Memory leak:", current_strings, "strings not released"
    end if
  end if

end program test_parser_simple