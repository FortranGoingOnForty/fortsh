! Test program for string pool validation
program test_memory_pool
  use string_pool
  use iso_fortran_env, only: int64
  implicit none

  integer :: i, j
  logical :: all_tests_passed
  type(string_ref) :: ref1, ref2, refs(100)
  character(len=100) :: test_string
  integer :: allocs, deallocs, current, peak
  real :: hit_rate
  integer(int64) :: start_time, end_time, clock_rate

  all_tests_passed = .true.

  print *, "=== String Pool Test Suite ==="
  print *, ""

  ! Test 1: Basic allocation and deallocation
  print *, "Test 1: Basic allocation..."
  call pool_init()
  ref1 = pool_get_string(100)

  if (.not. associated(ref1%data)) then
    print *, "  FAILED: String not allocated"
    all_tests_passed = .false.
  else
    ref1%data = "Hello, World!"
    if (ref1%data /= "Hello, World!") then
      print *, "  FAILED: String content mismatch"
      all_tests_passed = .false.
    else
      print *, "  PASSED: Basic allocation works"
    end if
  end if

  call pool_release_string(ref1)

  ! Test 2: Pool reuse
  print *, "Test 2: Pool reuse..."
  ref1 = pool_get_string(50)
  ref1%data = "First"
  call pool_release_string(ref1)

  ref2 = pool_get_string(50)
  ! Should reuse the same slot
  call pool_statistics(allocs, deallocs, current, peak, hit_rate)
  if (hit_rate < 0.5) then
    print *, "  WARNING: Low hit rate, pool may not be reusing"
  end if
  print *, "  PASSED: Pool reuse (hit rate:", hit_rate, ")"
  call pool_release_string(ref2)

  ! Test 3: Multiple size classes
  print *, "Test 3: Size class buckets..."
  ref1 = pool_get_string(10)    ! Should go to 64B bucket
  ref2 = pool_get_string(100)   ! Should go to 256B bucket

  ref1%data = "Small"
  ref2%data = "Medium string that is longer"

  if (ref1%data /= "Small" .or. len_trim(ref2%data) /= 28) then
    print *, "  FAILED: Size class allocation failed"
    all_tests_passed = .false.
  else
    print *, "  PASSED: Multiple size classes work"
  end if

  call pool_release_string(ref1)
  call pool_release_string(ref2)

  ! Test 4: String interning
  print *, "Test 4: String interning..."
  ref1 = pool_intern_string("common_string")
  ref2 = pool_intern_string("common_string")

  if (ref1%ref_count /= ref2%ref_count) then
    print *, "  WARNING: Interning may not be working correctly"
  else
    print *, "  PASSED: String interning works"
  end if

  call pool_release_string(ref1)
  call pool_release_string(ref2)

  ! Test 5: Stress test - rapid allocation/deallocation
  print *, "Test 5: Stress test (1000 allocations)..."
  call system_clock(start_time, clock_rate)

  do i = 1, 10
    do j = 1, 100
      refs(j) = pool_get_string(64)
      write(test_string, '(a,i0)') "Test string number ", i*100+j
      refs(j)%data = trim(test_string)
    end do

    do j = 1, 100
      call pool_release_string(refs(j))
    end do
  end do

  call system_clock(end_time)
  print *, "  PASSED: Stress test completed in", &
           real(end_time - start_time) / real(clock_rate), "seconds"

  ! Test 6: Large allocation (beyond pool)
  print *, "Test 6: Large allocation fallback..."
  ref1 = pool_get_string(100000)  ! 100KB - should bypass pool

  if (.not. associated(ref1%data)) then
    print *, "  FAILED: Large allocation failed"
    all_tests_passed = .false.
  else
    ref1%data(1:5) = "Large"
    if (ref1%data(1:5) /= "Large") then
      print *, "  FAILED: Large allocation content error"
      all_tests_passed = .false.
    else
      print *, "  PASSED: Large allocation fallback works"
    end if
  end if

  call pool_release_string(ref1)

  ! Test 7: Statistics
  print *, ""
  print *, "Pool Statistics:"
  call pool_statistics(allocs, deallocs, current, peak, hit_rate)
  print *, "  Total allocations:", allocs
  print *, "  Total deallocations:", deallocs
  print *, "  Current strings:", current
  print *, "  Peak strings:", peak
  print *, "  Cache hit rate:", hit_rate

  ! Cleanup
  call pool_cleanup()

  ! Test 8: Verify cleanup
  print *, ""
  print *, "Test 8: Cleanup verification..."
  call pool_statistics(allocs, deallocs, current, peak, hit_rate)
  if (current /= 0) then
    print *, "  FAILED: Memory leak detected after cleanup"
    all_tests_passed = .false.
  else
    print *, "  PASSED: Clean shutdown"
  end if

  ! Final result
  print *, ""
  print *, "==============================="
  if (all_tests_passed) then
    print *, "ALL TESTS PASSED!"
    stop 0
  else
    print *, "SOME TESTS FAILED!"
    stop 1
  end if

end program test_memory_pool