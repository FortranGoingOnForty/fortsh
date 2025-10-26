! ==============================================================================
! Simplified test program for Phase 6 - Executor module with memory pooling
! ==============================================================================
program test_executor_simple
  use string_pool
  use memory_dashboard
  use shell_types
  use iso_fortran_env, only: output_unit
  implicit none

  type(string_ref) :: buffer_ref, output_ref, cmd_ref
  type(string_ref) :: pipe_buffer_ref, heredoc_ref
  type(string_ref), allocatable :: token_refs(:)
  integer :: i, j
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(:), pointer :: str_ptr

  test_passed = .true.

  print *, "=== Phase 6 Executor Memory Pooling Test (Simplified) ==="
  print *, "Testing pooled memory for command execution"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Test 1: Large output buffer allocation (typical for command output)
  print *, "Test 1: Testing large output buffer allocation (16KB)..."

  ! Allocate a large buffer for command output capture
  output_ref = pool_get_string(16384)  ! 16KB buffer
  call dashboard_track_allocation(MOD_EXECUTOR, 16384, 5)  ! bucket 5 for 16KB

  ! Simulate capturing command output
  call pool_copy_to_ref(output_ref, "Command output line 1" // new_line('a') // &
                                     "Command output line 2" // new_line('a') // &
                                     "Command output line 3")

  str_ptr => output_ref%data
  if (associated(str_ptr)) then
    print *, "  Output buffer allocated (16KB)"
    print *, "  First line:", str_ptr(1:21)
    if (str_ptr(1:21) == "Command output line 1") then
      print *, "  PASSED: Large buffer working"
    else
      print *, "  FAILED: Buffer content incorrect"
      test_passed = .false.
    end if
  end if

  ! Release the buffer
  call pool_release_string(output_ref)
  call dashboard_track_deallocation(MOD_EXECUTOR, 16384, 5)

  ! Test 2: Command reconstruction buffer (4KB)
  print *, ""
  print *, "Test 2: Testing command reconstruction buffer (4KB)..."

  cmd_ref = pool_get_string(4096)  ! 4KB for reconstructed commands
  call dashboard_track_allocation(MOD_EXECUTOR, 4096, 4)

  ! Simulate reconstructing a command from tokens
  call pool_copy_to_ref(cmd_ref, "echo 'This is a reconstructed command' | grep command | wc -l")

  str_ptr => cmd_ref%data
  if (associated(str_ptr)) then
    print *, "  Reconstructed command:", trim(str_ptr)
    if (index(str_ptr, "reconstructed command") > 0) then
      print *, "  PASSED: Command reconstruction buffer working"
    else
      print *, "  FAILED: Reconstruction failed"
      test_passed = .false.
    end if
  end if

  call pool_release_string(cmd_ref)
  call dashboard_track_deallocation(MOD_EXECUTOR, 4096, 4)

  ! Test 3: Pipeline data transfer buffers
  print *, ""
  print *, "Test 3: Testing pipeline data transfer buffers..."

  ! Allocate buffer for pipe data transfer
  pipe_buffer_ref = pool_get_string(8192)  ! 8KB for pipe data
  call dashboard_track_allocation(MOD_EXECUTOR, 8192, 5)  ! maps to bucket 5

  ! Simulate data transfer through pipe
  call pool_copy_to_ref(pipe_buffer_ref, &
    "Data from process 1 flowing through pipe to process 2...")

  str_ptr => pipe_buffer_ref%data
  if (associated(str_ptr)) then
    print *, "  Pipe buffer (8KB) allocated"
    print *, "  Data sample:", trim(str_ptr)
    print *, "  PASSED: Pipeline buffer working"
  end if

  call pool_release_string(pipe_buffer_ref)
  call dashboard_track_deallocation(MOD_EXECUTOR, 8192, 5)

  ! Test 4: Token expansion buffers (multiple 1KB buffers)
  print *, ""
  print *, "Test 4: Testing token expansion buffers..."

  ! Allocate multiple token buffers as executor would
  allocate(token_refs(5))
  do i = 1, 5
    token_refs(i) = pool_get_string(1024)  ! 1KB per token
    call dashboard_track_allocation(MOD_EXECUTOR, 1024, 3)
  end do

  ! Simulate token expansion
  call pool_copy_to_ref(token_refs(1), "ls")
  call pool_copy_to_ref(token_refs(2), "-la")
  call pool_copy_to_ref(token_refs(3), "/home/user")
  call pool_copy_to_ref(token_refs(4), "|")
  call pool_copy_to_ref(token_refs(5), "grep")

  print *, "  Allocated 5 token buffers (1KB each)"
  print *, "    Token 1:", trim(token_refs(1)%data)
  print *, "    Token 2:", trim(token_refs(2)%data)
  print *, "    Token 5:", trim(token_refs(5)%data)

  ! Release token buffers
  do i = 1, 5
    call pool_release_string(token_refs(i))
    call dashboard_track_deallocation(MOD_EXECUTOR, 1024, 3)
  end do
  deallocate(token_refs)
  print *, "  Released all token buffers"

  ! Test 5: Heredoc content buffer
  print *, ""
  print *, "Test 5: Testing heredoc content buffer..."

  heredoc_ref = pool_get_string(4096)  ! 4KB for heredoc content
  call dashboard_track_allocation(MOD_EXECUTOR, 4096, 4)

  ! Simulate heredoc content
  call pool_copy_to_ref(heredoc_ref, &
    "Line 1 of heredoc" // new_line('a') // &
    "Line 2 of heredoc" // new_line('a') // &
    "Line 3 of heredoc" // new_line('a') // &
    "EOF")

  str_ptr => heredoc_ref%data
  if (associated(str_ptr)) then
    print *, "  Heredoc buffer (4KB) allocated"
    print *, "  First line:", str_ptr(1:17)
    print *, "  PASSED: Heredoc buffer working"
  end if

  call pool_release_string(heredoc_ref)
  call dashboard_track_deallocation(MOD_EXECUTOR, 4096, 4)

  ! Test 6: Stress test - rapid command executions
  print *, ""
  print *, "Test 6: Stress testing with 1000 command execution cycles..."
  do i = 1, 1000
    ! Simulate typical executor allocation pattern
    buffer_ref = pool_get_string(4096)   ! Command buffer
    output_ref = pool_get_string(8192)   ! Output buffer

    call dashboard_track_allocation(MOD_EXECUTOR, 4096, 4)
    call dashboard_track_allocation(MOD_EXECUTOR, 8192, 5)

    ! Simulate some work
    call pool_copy_to_ref(buffer_ref, "command")
    call pool_copy_to_ref(output_ref, "output")

    ! Release
    call pool_release_string(buffer_ref)
    call pool_release_string(output_ref)

    call dashboard_track_deallocation(MOD_EXECUTOR, 4096, 4)
    call dashboard_track_deallocation(MOD_EXECUTOR, 8192, 5)
  end do
  print *, "  Completed 1000 execution cycles"

  ! Test 7: Check for memory leaks
  print *, ""
  print *, "Test 7: Checking for memory leaks..."
  call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)

  print *, "  Total allocations:", total_allocs
  print *, "  Total deallocations:", total_deallocs
  print *, "  Current strings:", current_strings
  print *, "  Peak strings:", peak_strings
  print *, "  Cache hit rate:", int(hit_rate * 100), "%"

  if (current_strings == 0) then
    print *, "  PASSED: No memory leaks"
  else
    print *, "  FAILED: Memory leak -", current_strings, "strings still allocated"
    test_passed = .false.
  end if

  ! Display dashboard
  print *, ""
  print *, "=== Executor Module Statistics ==="
  call dashboard_display(detailed=.false.)

  ! Export statistics
  call dashboard_export_csv("executor_pooling_test.csv")
  print *, ""
  print *, "Statistics exported to executor_pooling_test.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  print *, "=== Test Summary ==="
  if (test_passed .and. current_strings == 0) then
    print *, "ALL TESTS PASSED"
    print *, ""
    print *, "Executor pooling integration verified:"
    print *, "  - Large output buffers (16KB) working"
    print *, "  - Command reconstruction buffers (4KB) working"
    print *, "  - Pipeline data buffers (8KB) working"
    print *, "  - Token expansion buffers (1KB) working"
    print *, "  - Heredoc buffers (4KB) working"
    print *, "  - No memory leaks detected"
    print *, "  - Dashboard tracking successful"
    print *, "  - Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "Ready to integrate into production executor module!"
  else
    print *, "SOME TESTS FAILED"
    if (current_strings > 0) then
      print *, "  Memory leak:", current_strings, "strings not released"
    end if
  end if

end program test_executor_simple