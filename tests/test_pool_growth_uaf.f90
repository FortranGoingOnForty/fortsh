! MEM-3 regression: string pool refs must survive bucket overflow.
!
! Before the fix, filling a bucket past INITIAL_SLOTS made the pool reallocate
! its backing array to a new address, dangling every ref%data already handed
! out. This driver fills the 64-byte bucket well past that boundary, writes a
! distinct marker into each ref, then reads them all back: any mismatch means
! an earlier ref pointed at freed/reused memory (the use-after-free). It also
! checks pool_ref_valid: a live ref is valid, and a ref is reported stale once
! the pool is torn down (pool_cleanup), so the readline guard is deterministic.
!
! Build+run: make test-pool-growth
! Under sanitizer: make test-pool-growth FC=gfortran FCFLAGS="-g -O0 -cpp -fsanitize=address -DUSE_MEMORY_POOL"
program test_pool_growth_uaf
  use string_pool
  implicit none

  integer, parameter :: N = 150   ! > INITIAL_SLOTS (100) for the 64-byte bucket
  type(string_ref) :: refs(N)
  type(string_ref) :: probe
  character(len=32) :: marker
  integer :: i, corrupted, unallocated
  logical :: ok

  ok = .true.
  call pool_init()

  ! Fill the 64-byte bucket far past INITIAL_SLOTS. Pre-fix, the 101st request
  ! reallocated pool_64 and dangled refs(1:100).
  unallocated = 0
  do i = 1, N
    refs(i) = pool_get_string(32)
    if (.not. associated(refs(i)%data)) then
      unallocated = unallocated + 1
      cycle
    end if
    write(marker, '(a,i0,a)') "MARK[", i, "]"
    refs(i)%data = trim(marker)
  end do
  if (unallocated > 0) then
    print '(a,i0,a,i0,a)', "FAIL: ", unallocated, " of ", N, " requests returned no storage"
    ok = .false.
  end if

  ! Every earlier ref must still hold its own marker.
  corrupted = 0
  do i = 1, N
    write(marker, '(a,i0,a)') "MARK[", i, "]"
    if (.not. associated(refs(i)%data)) then
      corrupted = corrupted + 1
      cycle
    end if
    if (trim(refs(i)%data) /= trim(marker)) then
      if (corrupted < 5) then
        print '(a,i0,a,a,a,a,a)', "  ref ", i, " corrupted: got '", &
          trim(refs(i)%data), "' want '", trim(marker), "'"
      end if
      corrupted = corrupted + 1
    end if
  end do
  if (corrupted > 0) then
    print '(a,i0,a,i0,a)', "FAIL: ", corrupted, " of ", N, &
      " refs corrupted after bucket overflow (MEM-3 use-after-free)"
    ok = .false.
  else
    print '(a,i0,a)', "PASS: all ", N, " refs intact after bucket overflow"
  end if

  do i = 1, N
    call pool_release_string(refs(i))
  end do

  ! pool_ref_valid: valid while live, stale after the pool is torn down.
  probe = pool_get_string(16)
  if (.not. pool_ref_valid(probe)) then
    print '(a)', "FAIL: a freshly issued ref reports invalid"
    ok = .false.
  end if
  call pool_cleanup()   ! frees the backing storage probe points into
  if (pool_ref_valid(probe)) then
    print '(a)', "FAIL: ref still reports valid after pool_cleanup (stale not detected)"
    ok = .false.
  else
    print '(a)', "PASS: pool_ref_valid detects a stale ref after teardown"
  end if

  if (ok) then
    print '(a)', "=== ALL PASS ==="
  else
    print '(a)', "=== FAILURES ==="
    stop 1
  end if
end program test_pool_growth_uaf
