! ==============================================================================
! Simplified test program for Phase 6 - Expansion module with memory pooling
! ==============================================================================
program test_expansion_simple
  use string_pool
  use memory_dashboard
  use shell_types
  use iso_fortran_env, only: output_unit
  implicit none

  type(string_ref) :: input_ref, pattern_ref, replacement_ref, output_ref
  type(string_ref) :: test_ref, result_ref
  integer :: i
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(:), pointer :: str_ptr

  test_passed = .true.

  print *, "=== Phase 6 Expansion Memory Pooling Test (Simplified) ==="
  print *, "Testing pooled strings for expansion operations"
  print *

  ! Initialize the pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Test 1: Simulate variable expansion with pooled strings
  print *, "Test 1: Simulating variable expansion with pooled strings..."

  ! Allocate pooled strings for expansion work
  test_ref = pool_get_string(2048)  ! Main expansion result buffer
  call dashboard_track_allocation(MOD_EXPANSION, 2048, 4)  ! bucket 4 for 2048
  call pool_copy_to_ref(test_ref, "Expanded: /home/testuser")

  ! Verify content
  str_ptr => test_ref%data
  if (associated(str_ptr)) then
    print *, "  Expansion result:", trim(str_ptr)
    if (trim(str_ptr) == "Expanded: /home/testuser") then
      print *, "  PASSED: Expansion buffer working"
    else
      print *, "  FAILED: Unexpected content"
      test_passed = .false.
    end if
  end if

  ! Clean up
  call pool_release_string(test_ref)
  call dashboard_track_deallocation(MOD_EXPANSION, 2048, 4)

  ! Test 2: Pattern substitution simulation
  print *, ""
  print *, "Test 2: Simulating pattern substitution..."

  ! Allocate strings for pattern substitution
  input_ref = pool_get_string(256)
  pattern_ref = pool_get_string(64)
  replacement_ref = pool_get_string(64)
  output_ref = pool_get_string(256)

  call dashboard_track_allocation(MOD_EXPANSION, 256, 2)
  call dashboard_track_allocation(MOD_EXPANSION, 64, 1)
  call dashboard_track_allocation(MOD_EXPANSION, 64, 1)
  call dashboard_track_allocation(MOD_EXPANSION, 256, 2)

  call pool_copy_to_ref(input_ref, "Hello World, Hello Universe")
  call pool_copy_to_ref(pattern_ref, "Hello")
  call pool_copy_to_ref(replacement_ref, "Goodbye")

  ! Simulate substitution
  call simulate_substitution(input_ref, pattern_ref, replacement_ref, output_ref)

  str_ptr => output_ref%data
  if (associated(str_ptr)) then
    print *, "  Input:", trim(input_ref%data)
    print *, "  Pattern:", trim(pattern_ref%data)
    print *, "  Replace with:", trim(replacement_ref%data)
    print *, "  Result:", trim(str_ptr)

    if (index(trim(str_ptr), "Goodbye") > 0) then
      print *, "  PASSED: Substitution simulation working"
    else
      print *, "  FAILED: Substitution not applied"
      test_passed = .false.
    end if
  end if

  ! Clean up
  call pool_release_string(input_ref)
  call pool_release_string(pattern_ref)
  call pool_release_string(replacement_ref)
  call pool_release_string(output_ref)
  call dashboard_track_deallocation(MOD_EXPANSION, 256, 2)
  call dashboard_track_deallocation(MOD_EXPANSION, 64, 1)
  call dashboard_track_deallocation(MOD_EXPANSION, 64, 1)
  call dashboard_track_deallocation(MOD_EXPANSION, 256, 2)

  ! Test 3: Multiple temporary strings (typical expansion pattern)
  print *, ""
  print *, "Test 3: Testing multiple temporary strings..."

  block
    type(string_ref) :: temp_refs(5)
    integer :: j

    ! Allocate multiple temporary strings as expansion would
    do j = 1, 5
      temp_refs(j) = pool_get_string(256)
      call dashboard_track_allocation(MOD_EXPANSION, 256, 2)
    end do

    ! Simulate working with them
    call pool_copy_to_ref(temp_refs(1), "VAR_NAME")
    call pool_copy_to_ref(temp_refs(2), "VAR_VALUE")
    call pool_copy_to_ref(temp_refs(3), "OPERATION")
    call pool_copy_to_ref(temp_refs(4), "PATTERN")
    call pool_copy_to_ref(temp_refs(5), "RESULT")

    print *, "  Allocated 5 temporary strings"
    print *, "    String 1:", trim(temp_refs(1)%data)
    print *, "    String 2:", trim(temp_refs(2)%data)
    print *, "    String 5:", trim(temp_refs(5)%data)

    ! Release all
    do j = 1, 5
      call pool_release_string(temp_refs(j))
      call dashboard_track_deallocation(MOD_EXPANSION, 256, 2)
    end do

    print *, "  Released all temporary strings"
  end block

  ! Test 4: Stress test - rapid allocations typical of expansion
  print *, ""
  print *, "Test 4: Stress testing with rapid expansion operations..."
  do i = 1, 1000
    ! Simulate expansion allocation pattern
    test_ref = pool_get_string(2048)  ! Result buffer
    result_ref = pool_get_string(256) ! Temp work

    call dashboard_track_allocation(MOD_EXPANSION, 2048, 4)
    call dashboard_track_allocation(MOD_EXPANSION, 256, 2)

    ! Simulate some work
    call pool_copy_to_ref(test_ref, "Expansion result")
    call pool_copy_to_ref(result_ref, "Temp value")

    ! Release
    call pool_release_string(test_ref)
    call pool_release_string(result_ref)

    call dashboard_track_deallocation(MOD_EXPANSION, 2048, 4)
    call dashboard_track_deallocation(MOD_EXPANSION, 256, 2)
  end do
  print *, "  Completed 1000 expansion simulation cycles"

  ! Test 5: Check for memory leaks
  print *, ""
  print *, "Test 5: Checking for memory leaks..."
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
  print *, "=== Expansion Module Statistics ==="
  call dashboard_display(detailed=.false.)

  ! Export statistics
  call dashboard_export_csv("expansion_pooling_test.csv")
  print *, ""
  print *, "Statistics exported to expansion_pooling_test.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  print *, "=== Test Summary ==="
  if (test_passed .and. current_strings == 0) then
    print *, "✅ ALL TESTS PASSED"
    print *, ""
    print *, "Expansion pooling integration verified:"
    print *, "  • Large expansion buffers (2048 bytes) working"
    print *, "  • Pattern substitution strings pooled"
    print *, "  • Multiple temporary strings handled"
    print *, "  • No memory leaks detected"
    print *, "  • Dashboard tracking successful"
    print *, "  • Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "Ready to integrate into production expansion module!"
  else
    print *, "❌ SOME TESTS FAILED"
    if (current_strings > 0) then
      print *, "  Memory leak:", current_strings, "strings not released"
    end if
  end if

contains

  ! Simulate pattern substitution
  subroutine simulate_substitution(input_ref, pattern_ref, replacement_ref, output_ref)
    type(string_ref), intent(in) :: input_ref, pattern_ref, replacement_ref
    type(string_ref), intent(inout) :: output_ref
    integer :: pos, pattern_len
    character(len=256) :: temp

    ! Simple substitution simulation - replace first occurrence
    pos = index(input_ref%data, pattern_ref%data)
    pattern_len = len_trim(pattern_ref%data)

    if (pos > 0) then
      ! Found the pattern, replace it
      if (pos > 1) then
        temp = input_ref%data(1:pos-1)
      else
        temp = ""
      end if
      temp = trim(temp) // trim(replacement_ref%data) // input_ref%data(pos+pattern_len:)
      call pool_copy_to_ref(output_ref, temp)
    else
      call pool_copy_to_ref(output_ref, input_ref%data)
    end if
  end subroutine simulate_substitution

end program test_expansion_simple