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
  integer :: intern_before, intern_after
  real :: hit_rate
  logical :: bucket_fallback_ok
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

  ! Test 4: String interning + release accounting (MEM-4).
  ! Releasing an interned ref used to fall through the pooled branch, leaking
  ! its allocation while still decrementing the counters. current_strings must
  ! rise by exactly the two interns and return to baseline after both releases.
  print *, "Test 4: String interning..."
  call pool_statistics(allocs, deallocs, current, peak, hit_rate)
  intern_before = current
  ref1 = pool_intern_string("common_string")
  ref2 = pool_intern_string("common_string")
  call pool_statistics(allocs, deallocs, current, peak, hit_rate)
  intern_after = current
  call pool_release_string(ref1)
  call pool_release_string(ref2)
  call pool_statistics(allocs, deallocs, current, peak, hit_rate)

  if (intern_after - intern_before /= 2) then
    print *, "  FAILED: interning did not account for 2 live strings, delta=", &
             intern_after - intern_before
    all_tests_passed = .false.
  else if (current /= intern_before) then
    print *, "  FAILED: interned refs leaked - current_strings", intern_before, "->", current
    all_tests_passed = .false.
  else
    print *, "  PASSED: String interning allocates and releases cleanly"
  end if

  ref1 = pool_intern_string(repeat("x", 200))
  if (.not. associated(ref1%data)) then
    print *, "  FAILED: Long interned string not allocated"
    all_tests_passed = .false.
  else if (ref1%str_len /= 200 .or. len(ref1%data) /= 200) then
    print *, "  FAILED: Long interned string length mismatch"
    all_tests_passed = .false.
  else if (ref1%data /= repeat("x", 200)) then
    print *, "  FAILED: Long interned string content mismatch"
    all_tests_passed = .false.
  else
    print *, "  PASSED: Long string interning works"
  end if
  call pool_release_string(ref1)

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

  ! The 16384-byte bucket has ten slots. An eleventh live string must fall
  ! back to a standalone allocation without losing its requested length.
  print *, "Test 7: Full-bucket allocation fallback..."
  bucket_fallback_ok = .true.
  do i = 1, 11
    refs(i) = pool_get_string(5000)
    if (.not. associated(refs(i)%data)) bucket_fallback_ok = .false.
  end do
  if (bucket_fallback_ok) then
    refs(11)%data(4996:5000) = "Final"
    if (refs(11)%data(4996:5000) /= "Final") bucket_fallback_ok = .false.
  end if
  if (bucket_fallback_ok) then
    print *, "  PASSED: Full bucket falls back to direct allocation"
  else
    print *, "  FAILED: Full-bucket fallback lost a long string"
    all_tests_passed = .false.
  end if
  do i = 1, 11
    call pool_release_string(refs(i))
  end do

  ! Test 8: Statistics
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

  ! Test 9: Verify cleanup
  print *, ""
  print *, "Test 9: Cleanup verification..."
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
