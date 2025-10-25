! ==============================================================================
! Module: memory_profiler
! Purpose: Track memory allocations and detect leaks
!
! Provides instrumentation similar to valgrind/AddressSanitizer
! ==============================================================================
module memory_profiler
  use iso_fortran_env, only: int64, real64, error_unit
  implicit none
  private

  public :: mem_track_alloc, mem_track_dealloc, mem_report
  public :: mem_check_leaks, mem_enable_tracking, mem_disable_tracking
  public :: mem_get_current_usage, mem_get_peak_usage

  ! Tracking record for each allocation
  type :: alloc_record
    integer(int64) :: address = 0
    integer(int64) :: size = 0
    character(len=256) :: location = ''
    character(len=64) :: type_name = ''
    integer :: line_number = 0
    logical :: active = .false.
    integer(int64) :: alloc_time = 0
  end type alloc_record

  ! Site statistics for reporting
  type :: site_stats
    character(len=256) :: location = ''
    integer :: count = 0
    integer(int64) :: total_size = 0
  end type site_stats

  ! Module state
  integer, parameter :: MAX_TRACKED = 10000
  type(alloc_record) :: allocations(MAX_TRACKED)
  integer :: num_allocations = 0
  integer :: num_deallocations = 0
  integer :: num_active = 0
  integer(int64) :: current_usage = 0
  integer(int64) :: peak_usage = 0
  logical :: tracking_enabled = .false.
  integer(int64) :: start_time = 0

  ! Leak detection thresholds
  integer, parameter :: LEAK_WARNING_SIZE = 1048576  ! 1MB
  integer, parameter :: LEAK_ERROR_SIZE = 10485760   ! 10MB

contains

  ! Enable memory tracking
  subroutine mem_enable_tracking()
    tracking_enabled = .true.
    call system_clock(start_time)
    write(error_unit, '(a)') '=== Memory profiling ENABLED ==='
  end subroutine mem_enable_tracking

  ! Disable memory tracking
  subroutine mem_disable_tracking()
    tracking_enabled = .false.
    write(error_unit, '(a)') '=== Memory profiling DISABLED ==='
  end subroutine mem_disable_tracking

  ! Track an allocation
  subroutine mem_track_alloc(ptr_address, size, location, type_name, line_num)
    integer(int64), intent(in) :: ptr_address
    integer(int64), intent(in) :: size
    character(len=*), intent(in) :: location
    character(len=*), intent(in) :: type_name
    integer, intent(in) :: line_num
    integer :: i, slot
    integer(int64) :: current_time

    if (.not. tracking_enabled) return

    ! Find empty slot
    slot = 0
    do i = 1, MAX_TRACKED
      if (.not. allocations(i)%active) then
        slot = i
        exit
      end if
    end do

    if (slot == 0) then
      write(error_unit, '(a)') 'WARNING: Memory tracker full, cannot track allocation'
      return
    end if

    call system_clock(current_time)

    ! Record allocation
    allocations(slot)%address = ptr_address
    allocations(slot)%size = size
    allocations(slot)%location = location
    allocations(slot)%type_name = type_name
    allocations(slot)%line_number = line_num
    allocations(slot)%active = .true.
    allocations(slot)%alloc_time = current_time

    ! Update statistics
    num_allocations = num_allocations + 1
    num_active = num_active + 1
    current_usage = current_usage + size
    if (current_usage > peak_usage) peak_usage = current_usage

    ! Warn on large allocations
    if (size > LEAK_WARNING_SIZE) then
      write(error_unit, '(a,i0,a,a,a,i0)') &
        'LARGE ALLOCATION: ', size, ' bytes at ', trim(location), ':', line_num
    end if

  end subroutine mem_track_alloc

  ! Track a deallocation
  subroutine mem_track_dealloc(ptr_address, location, line_num)
    integer(int64), intent(in) :: ptr_address
    character(len=*), intent(in) :: location
    integer, intent(in) :: line_num
    integer :: i
    logical :: found

    if (.not. tracking_enabled) return

    found = .false.
    do i = 1, MAX_TRACKED
      if (allocations(i)%active .and. allocations(i)%address == ptr_address) then
        found = .true.
        current_usage = current_usage - allocations(i)%size
        allocations(i)%active = .false.
        num_deallocations = num_deallocations + 1
        num_active = num_active - 1
        exit
      end if
    end do

    if (.not. found) then
      write(error_unit, '(a,z16,a,a,a,i0)') &
        'WARNING: Deallocating untracked pointer 0x', ptr_address, &
        ' at ', trim(location), ':', line_num
    end if

  end subroutine mem_track_dealloc

  ! Check for memory leaks
  subroutine mem_check_leaks()
    integer :: i, leak_count
    integer(int64) :: leaked_bytes
    character(len=512) :: leak_msg

    if (.not. tracking_enabled) return

    leak_count = 0
    leaked_bytes = 0

    write(error_unit, '(a)') ''
    write(error_unit, '(a)') '=== MEMORY LEAK CHECK ==='

    do i = 1, MAX_TRACKED
      if (allocations(i)%active) then
        leak_count = leak_count + 1
        leaked_bytes = leaked_bytes + allocations(i)%size

        write(leak_msg, '(a,i0,a,a,a,i0,a,a)') &
          'LEAK: ', allocations(i)%size, ' bytes from ', &
          trim(allocations(i)%location), ':', allocations(i)%line_number, &
          ' (', trim(allocations(i)%type_name), ')'
        write(error_unit, '(a)') trim(leak_msg)
      end if
    end do

    if (leak_count > 0) then
      write(error_unit, '(a,i0,a,i0,a)') &
        'TOTAL: ', leak_count, ' leaks, ', leaked_bytes, ' bytes leaked'
      if (leaked_bytes > LEAK_ERROR_SIZE) then
        write(error_unit, '(a)') 'ERROR: Severe memory leak detected!'
      end if
    else
      write(error_unit, '(a)') 'No memory leaks detected'
    end if

    write(error_unit, '(a)') '========================='
    write(error_unit, '()')

  end subroutine mem_check_leaks

  ! Generate memory report
  subroutine mem_report()
    integer :: i, bucket_counts(10), bucket_sizes(10)
    integer(int64) :: total_time
    real(real64) :: elapsed_seconds

    if (.not. tracking_enabled) return

    call system_clock(total_time)
    elapsed_seconds = real(total_time - start_time) / 1000.0

    write(error_unit, '(a)') ''
    write(error_unit, '(a)') '=== MEMORY USAGE REPORT ==='
    write(error_unit, '(a,f8.2,a)') 'Profiling duration: ', elapsed_seconds, ' seconds'
    write(error_unit, '(a,i0)') 'Total allocations: ', num_allocations
    write(error_unit, '(a,i0)') 'Total deallocations: ', num_deallocations
    write(error_unit, '(a,i0)') 'Currently active: ', num_active
    write(error_unit, '(a,i0,a)') 'Current usage: ', current_usage, ' bytes'
    write(error_unit, '(a,i0,a)') 'Peak usage: ', peak_usage, ' bytes'

    ! Size distribution
    bucket_counts = 0
    bucket_sizes = [16, 64, 256, 1024, 4096, 16384, 65536, 262144, 1048576, huge(1)]

    do i = 1, MAX_TRACKED
      if (allocations(i)%active) then
        if (allocations(i)%size <= bucket_sizes(1)) then
          bucket_counts(1) = bucket_counts(1) + 1
        else if (allocations(i)%size <= bucket_sizes(2)) then
          bucket_counts(2) = bucket_counts(2) + 1
        else if (allocations(i)%size <= bucket_sizes(3)) then
          bucket_counts(3) = bucket_counts(3) + 1
        else if (allocations(i)%size <= bucket_sizes(4)) then
          bucket_counts(4) = bucket_counts(4) + 1
        else if (allocations(i)%size <= bucket_sizes(5)) then
          bucket_counts(5) = bucket_counts(5) + 1
        else if (allocations(i)%size <= bucket_sizes(6)) then
          bucket_counts(6) = bucket_counts(6) + 1
        else if (allocations(i)%size <= bucket_sizes(7)) then
          bucket_counts(7) = bucket_counts(7) + 1
        else if (allocations(i)%size <= bucket_sizes(8)) then
          bucket_counts(8) = bucket_counts(8) + 1
        else if (allocations(i)%size <= bucket_sizes(9)) then
          bucket_counts(9) = bucket_counts(9) + 1
        else
          bucket_counts(10) = bucket_counts(10) + 1
        end if
      end if
    end do

    write(error_unit, '(a)') ''
    write(error_unit, '(a)') 'Size distribution of active allocations:'
    write(error_unit, '(a,i0)') '    0-16 bytes: ', bucket_counts(1)
    write(error_unit, '(a,i0)') '   17-64 bytes: ', bucket_counts(2)
    write(error_unit, '(a,i0)') '  65-256 bytes: ', bucket_counts(3)
    write(error_unit, '(a,i0)') '  257-1K bytes: ', bucket_counts(4)
    write(error_unit, '(a,i0)') '    1-4K bytes: ', bucket_counts(5)
    write(error_unit, '(a,i0)') '   4-16K bytes: ', bucket_counts(6)
    write(error_unit, '(a,i0)') '  16-64K bytes: ', bucket_counts(7)
    write(error_unit, '(a,i0)') ' 64-256K bytes: ', bucket_counts(8)
    write(error_unit, '(a,i0)') '  256K-1M bytes: ', bucket_counts(9)
    write(error_unit, '(a,i0)') '     >1M bytes: ', bucket_counts(10)

    ! Top allocation sites
    call report_top_allocators()

    write(error_unit, '(a)') '========================='
    write(error_unit, '()')

  end subroutine mem_report

  ! Report top allocation sites
  subroutine report_top_allocators()
    type(site_stats) :: sites(100)
    integer :: num_sites, i, j
    logical :: found

    num_sites = 0
    sites%count = 0
    sites%total_size = 0

    ! Aggregate by location
    do i = 1, MAX_TRACKED
      if (allocations(i)%active) then
        found = .false.
        do j = 1, num_sites
          if (sites(j)%location == allocations(i)%location) then
            sites(j)%count = sites(j)%count + 1
            sites(j)%total_size = sites(j)%total_size + allocations(i)%size
            found = .true.
            exit
          end if
        end do

        if (.not. found .and. num_sites < 100) then
          num_sites = num_sites + 1
          sites(num_sites)%location = allocations(i)%location
          sites(num_sites)%count = 1
          sites(num_sites)%total_size = allocations(i)%size
        end if
      end if
    end do

    ! Sort and display top sites
    if (num_sites > 0) then
      write(error_unit, '(a)') ''
      write(error_unit, '(a)') 'Top allocation sites:'
      call sort_sites_by_size(sites, num_sites)
      do i = 1, min(5, num_sites)
        write(error_unit, '(2x,a,a,i0,a,i0,a)') &
          trim(sites(i)%location), ': ', &
          sites(i)%count, ' allocations, ', &
          sites(i)%total_size, ' bytes'
      end do
    end if

  end subroutine report_top_allocators

  ! Sort allocation sites by total size
  subroutine sort_sites_by_size(sites, n)
    type(site_stats), intent(inout) :: sites(:)
    integer, intent(in) :: n
    type(site_stats) :: temp
    integer :: i, j

    do i = 1, n-1
      do j = i+1, n
        if (sites(j)%total_size > sites(i)%total_size) then
          temp = sites(i)
          sites(i) = sites(j)
          sites(j) = temp
        end if
      end do
    end do

  end subroutine sort_sites_by_size

  ! Get current memory usage
  function mem_get_current_usage() result(usage)
    integer(int64) :: usage
    usage = current_usage
  end function mem_get_current_usage

  ! Get peak memory usage
  function mem_get_peak_usage() result(usage)
    integer(int64) :: usage
    usage = peak_usage
  end function mem_get_peak_usage

end module memory_profiler