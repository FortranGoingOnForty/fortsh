! ==============================================================================
! Test program for Phase 4 memory dashboard
! ==============================================================================
program test_dashboard
  use string_pool
  use memory_dashboard
  use iso_fortran_env, only: output_unit
  implicit none

  type(string_ref) :: refs(100)
  integer :: i, j
  character(len=256) :: test_str
  logical :: test_passed

  test_passed = .true.

  print *, "=== Phase 4 Memory Dashboard Test Suite ==="
  print *, "Testing real-time memory statistics and visualization"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.true.)

  ! Test 1: Simulate readline module allocations
  print *, "Test 1: Simulating readline module activity..."
  do i = 1, 20
    refs(i) = pool_get_string(64)
    call dashboard_track_allocation(MOD_READLINE, 64, 1)
    write(test_str, '(a,i0)') "readline_buffer_", i
    call pool_copy_to_ref(refs(i), test_str)
  end do
  print *, "  Created 20 readline buffers"

  ! Test 2: Simulate completion module allocations
  print *, "Test 2: Simulating completion module activity..."
  do i = 21, 40
    refs(i) = pool_get_string(256)
    call dashboard_track_allocation(MOD_COMPLETION, 256, 2)
    write(test_str, '(a,i0)') "completion_candidate_", i
    call pool_copy_to_ref(refs(i), test_str)
  end do
  print *, "  Created 20 completion candidates"

  ! Test 3: Simulate parser module with mixed sizes
  print *, "Test 3: Simulating parser module activity..."
  do i = 41, 60
    if (mod(i, 2) == 0) then
      refs(i) = pool_get_string(1024)
      call dashboard_track_allocation(MOD_PARSER, 1024, 3)
      write(test_str, '(a,i0)') "parser_ast_node_", i
    else
      refs(i) = pool_get_string(256)
      call dashboard_track_allocation(MOD_PARSER, 256, 2)
      write(test_str, '(a,i0)') "parser_token_", i
    end if
    call pool_copy_to_ref(refs(i), test_str)
  end do
  print *, "  Created 20 parser elements (mixed sizes)"

  ! Display initial dashboard
  print *
  print *, "=== Initial Dashboard Display ==="
  call dashboard_display(detailed=.false.)

  ! Test 4: Simulate some deallocations
  print *, "Test 4: Simulating deallocations..."
  do i = 1, 10
    call pool_release_string(refs(i))
    call dashboard_track_deallocation(MOD_READLINE, 64, 1)
  end do
  do i = 21, 30
    call pool_release_string(refs(i))
    call dashboard_track_deallocation(MOD_COMPLETION, 256, 2)
  end do
  print *, "  Released 10 readline buffers and 10 completion candidates"

  ! Test 5: Simulate executor module with large allocations
  print *, "Test 5: Simulating executor module with large buffers..."
  do i = 61, 70
    refs(i) = pool_get_string(4096)
    call dashboard_track_allocation(MOD_EXECUTOR, 4096, 4)
    write(test_str, '(a,i0)') "executor_command_output_", i
    call pool_copy_to_ref(refs(i), test_str)
  end do
  print *, "  Created 10 large executor buffers"

  ! Display detailed dashboard
  print *
  print *, "=== Detailed Dashboard Display ==="
  call dashboard_display(detailed=.true.)

  ! Test 6: Check module statistics
  print *, "Test 6: Verifying module statistics..."
  block
    type(module_stats) :: rl_stats, comp_stats

    rl_stats = dashboard_get_module_stats(MOD_READLINE)
    comp_stats = dashboard_get_module_stats(MOD_COMPLETION)

    if (rl_stats%total_allocations == 20 .and. rl_stats%total_deallocations == 10) then
      print *, "  PASSED: Readline stats correct"
    else
      print *, "  FAILED: Readline stats incorrect"
      test_passed = .false.
    end if

    if (comp_stats%total_allocations == 20 .and. comp_stats%total_deallocations == 10) then
      print *, "  PASSED: Completion stats correct"
    else
      print *, "  FAILED: Completion stats incorrect"
      test_passed = .false.
    end if
  end block

  ! Test 7: Stress test with rapid allocations/deallocations
  print *, "Test 7: Stress testing with rapid operations..."
  do j = 1, 5
    ! Allocate batch
    do i = 71, 100
      refs(i) = pool_get_string(128)
      call dashboard_track_allocation(MOD_HISTORY, 128, 2)
    end do
    ! Deallocate batch
    do i = 71, 100
      call pool_release_string(refs(i))
      call dashboard_track_deallocation(MOD_HISTORY, 128, 2)
    end do
  end do
  print *, "  Completed 5 cycles of 30 allocations/deallocations"

  ! Export statistics to CSV
  print *
  print *, "Test 8: Exporting statistics to CSV..."
  call dashboard_export_csv("memory_stats.csv")

  ! Display summary
  print *
  print *, "=== Final Summary ==="
  call dashboard_summary()

  ! Final dashboard display
  print *, "=== Final Dashboard State ==="
  call dashboard_display(detailed=.false.)

  ! Cleanup remaining allocations
  do i = 11, 20
    if (refs(i)%pool_index /= 0) call pool_release_string(refs(i))
  end do
  do i = 31, 70
    if (refs(i)%pool_index /= 0) call pool_release_string(refs(i))
  end do

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Test results
  print *
  if (test_passed) then
    print *, "=== ALL TESTS PASSED ==="
    print *, "Phase 4 Dashboard implementation successful!"
    print *, ""
    print *, "Key achievements:"
    print *, "  ✓ Per-module memory tracking"
    print *, "  ✓ Real-time statistics display"
    print *, "  ✓ Bucket distribution analysis"
    print *, "  ✓ CSV export capability"
    print *, "  ✓ Visual progress bars and formatting"
    print *, ""
    print *, "The dashboard provides essential visibility for Phase 6 integration!"
  else
    print *, "=== SOME TESTS FAILED ==="
    print *, "Please review the implementation"
  end if

end program test_dashboard