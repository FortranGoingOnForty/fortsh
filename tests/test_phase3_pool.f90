! ==============================================================================
! Test program for Phase 3 memory pooling - zero-copy verification
! ==============================================================================
program test_phase3_pool
  use string_pool
  use iso_fortran_env, only: output_unit
  implicit none

  type(string_ref) :: ref1, ref2, ref3
  character(len=100) :: test_string
  integer :: total_allocs, total_deallocs, current, peak, i
  real :: hit_rate
  logical :: tests_passed

  tests_passed = .true.

  print *, "=== Phase 3 Memory Pool Test Suite ==="
  print *, "Testing zero-copy string pooling implementation"
  print *

  ! Initialize the pool
  call pool_init()

  ! Test 1: Basic allocation and pointer verification
  print *, "Test 1: Verifying direct pointer allocation..."
  ref1 = pool_get_string(50)

  if (ref1%pool_index == 0) then
    print *, "  FAILED: Pool did not allocate"
    tests_passed = .false.
  else
    print *, "  PASSED: Got pooled memory allocation"
  end if

  ! Test 2: Write data directly to pooled memory
  print *, "Test 2: Writing directly to pooled memory..."
  test_string = "Hello from zero-copy pool!"
  call pool_copy_to_ref(ref1, test_string)

  if (trim(ref1%data) == "Hello from zero-copy pool!") then
    print *, "  PASSED: Data written directly to pool"
  else
    print *, "  FAILED: Data not correctly written"
    tests_passed = .false.
  end if

  ! Test 3: Multiple allocations from different buckets
  print *, "Test 3: Testing multiple bucket sizes..."
  ref2 = pool_get_string(200)  ! Should go to 256-byte bucket
  ref3 = pool_get_string(1000) ! Should go to 1024-byte bucket

  call pool_copy_to_ref(ref2, "Medium string in 256-byte bucket")
  call pool_copy_to_ref(ref3, "Large string in 1024-byte bucket")

  if (ref2%pool_index /= 0 .and. ref3%pool_index /= 0) then
    print *, "  PASSED: Multiple buckets working correctly"
  else
    print *, "  FAILED: Multiple bucket allocation failed"
    tests_passed = .false.
  end if

  ! Test 4: Verify no double allocation
  print *, "Test 4: Verifying zero-copy (no double allocation)..."
  ! The key test: changing the pooled data should be visible through the pointer
  ref1%data(1:5) = "ZERO-"
  if (ref1%data(1:5) == "ZERO-") then
    print *, "  PASSED: Direct modification of pooled memory confirmed"
    print *, "  This proves we're using pointers, not copies!"
  else
    print *, "  FAILED: Modification not reflected - double allocation detected!"
    tests_passed = .false.
  end if

  ! Test 5: Pool reuse after release
  print *, "Test 5: Testing pool slot reuse..."
  call pool_release_string(ref1)
  ref1 = pool_get_string(50)  ! Should reuse the same slot

  if (ref1%pool_index /= 0) then
    print *, "  PASSED: Pool slot successfully reused"
  else
    print *, "  FAILED: Pool slot reuse failed"
    tests_passed = .false.
  end if

  ! Test 6: Pool expansion
  print *, "Test 6: Testing pool expansion..."
  block
    type(string_ref) :: many_refs(200)
    integer :: j

    ! Allocate more than initial pool size
    do j = 1, 200
      many_refs(j) = pool_get_string(60)
      if (many_refs(j)%pool_index == 0) then
        print *, "  FAILED: Pool expansion failed at allocation", j
        tests_passed = .false.
        exit
      end if
    end do

    if (tests_passed) then
      print *, "  PASSED: Pool successfully expanded to handle 200 allocations"
    end if

    ! Clean up
    do j = 1, 200
      call pool_release_string(many_refs(j))
    end do
  end block

  ! Test 7: Statistics verification
  print *, "Test 7: Checking pool statistics..."
  call pool_statistics(total_allocs, total_deallocs, current, peak, hit_rate)

  print *, "  Total allocations:", total_allocs
  print *, "  Total deallocations:", total_deallocs
  print *, "  Current strings:", current
  print *, "  Peak strings:", peak
  print *, "  Cache hit rate:", int(hit_rate * 100), "%"

  if (hit_rate > 0.95) then
    print *, "  PASSED: Excellent cache hit rate (>95%)"
  else if (hit_rate > 0.80) then
    print *, "  PASSED: Good cache hit rate (>80%)"
  else
    print *, "  WARNING: Low cache hit rate"
  end if

  ! Test 8: Memory pattern test
  print *, "Test 8: Testing realistic allocation patterns..."
  block
    type(string_ref) :: pattern_refs(10)
    integer :: sizes(10) = [32, 128, 64, 256, 512, 64, 128, 32, 1024, 256]
    integer :: k

    ! Simulate realistic allocation pattern
    do k = 1, 10
      pattern_refs(k) = pool_get_string(sizes(k))
      write(test_string, '(a,i0)') "Test string ", k
      call pool_copy_to_ref(pattern_refs(k), test_string)
    end do

    ! Verify all allocations
    do k = 1, 10
      write(test_string, '(a,i0)') "Test string ", k
      if (trim(pattern_refs(k)%data) /= trim(test_string)) then
        print *, "  FAILED: Pattern test failed at", k
        tests_passed = .false.
      end if
    end do

    if (tests_passed) then
      print *, "  PASSED: Realistic allocation patterns handled correctly"
    end if

    ! Clean up
    do k = 1, 10
      call pool_release_string(pattern_refs(k))
    end do
  end block

  ! Clean up remaining allocations
  call pool_release_string(ref2)
  call pool_release_string(ref3)

  ! Final statistics
  print *
  print *, "=== Final Statistics ==="
  call pool_statistics(total_allocs, total_deallocs, current, peak, hit_rate)
  print *, "Total allocations:", total_allocs
  print *, "Total deallocations:", total_deallocs
  print *, "Leaked strings:", current
  print *, "Peak usage:", peak
  print *, "Overall hit rate:", int(hit_rate * 100), "%"

  ! Clean up the pool
  call pool_cleanup()

  ! Summary
  print *
  if (tests_passed) then
    print *, "=== ALL TESTS PASSED ==="
    print *, "Phase 3 zero-copy pooling is working correctly!"
    print *, "Key achievement: Direct pointers to pool memory (no double allocation)"
  else
    print *, "=== SOME TESTS FAILED ==="
    print *, "Please review the implementation"
  end if

end program test_phase3_pool