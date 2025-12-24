! ==============================================================================
! Module: performance
! Purpose: Performance monitoring and optimization for fortsh
! ==============================================================================
module performance
  use iso_fortran_env, only: output_unit, error_unit, int64
  use iso_c_binding, only: c_long
  implicit none

  ! Performance monitoring state
  logical :: perf_monitoring_enabled = .false.
  logical :: memory_tracking_enabled = .true.
  
  ! Timing information
  integer(int64) :: startup_time = 0
  integer(int64) :: total_commands = 0
  integer(int64) :: total_parse_time = 0
  integer(int64) :: total_exec_time = 0
  integer(int64) :: total_glob_time = 0
  
  ! Memory tracking
  integer :: total_allocations = 0
  integer :: current_allocations = 0
  integer :: peak_allocations = 0
  integer(int64) :: total_memory_used = 0
  integer(int64) :: peak_memory_used = 0
  integer(int64) :: current_memory_used = 0
  
  ! Memory pools for common allocations
  integer, parameter :: MAX_POOLED_TOKENS = 100
  integer, parameter :: MAX_TOKEN_POOLS = 10
  
  type :: token_pool_t
    character(len=256), allocatable :: tokens(:)
    integer :: size = 0
    integer :: capacity = 0
    logical :: in_use = .false.
  end type token_pool_t
  
  type(token_pool_t) :: token_pools(MAX_TOKEN_POOLS)
  integer :: next_pool_index = 1

contains

  ! Initialize performance monitoring
  subroutine init_performance_monitoring()
    integer(int64) :: current_time
    
    call system_clock(current_time)
    startup_time = current_time
    
    ! Initialize token pools
    call init_token_pools()
    
    if (perf_monitoring_enabled) then
      write(output_unit, '(a)') '[PERF] Performance monitoring initialized'
    end if
  end subroutine

  ! Enable/disable performance monitoring
  subroutine set_performance_monitoring(enabled)
    logical, intent(in) :: enabled
    perf_monitoring_enabled = enabled
  end subroutine

  ! Start timing a section
  subroutine start_timer(timer_id, start_time)
    character(len=*), intent(in) :: timer_id
    integer(int64), intent(out) :: start_time
    
    call system_clock(start_time)
    
    if (perf_monitoring_enabled) then
      write(output_unit, '(a,a)') '[PERF] Started timer: ', timer_id
    end if
  end subroutine

  ! End timing a section and accumulate
  subroutine end_timer(timer_id, start_time, total_time)
    character(len=*), intent(in) :: timer_id
    integer(int64), intent(in) :: start_time
    integer(int64), intent(inout) :: total_time
    
    integer(int64) :: end_time, elapsed
    
    call system_clock(end_time)
    elapsed = end_time - start_time
    total_time = total_time + elapsed
    
    if (perf_monitoring_enabled) then
      write(output_unit, '(a,a,a,i15,a)') '[PERF] ', timer_id, ' took ', elapsed, ' ticks'
    end if
  end subroutine

  ! Track memory allocation
  subroutine track_allocation(size_bytes, location)
    integer, intent(in) :: size_bytes
    character(len=*), intent(in), optional :: location
    
    if (.not. memory_tracking_enabled) return
    
    total_allocations = total_allocations + 1
    current_allocations = current_allocations + 1
    current_memory_used = current_memory_used + size_bytes
    total_memory_used = total_memory_used + size_bytes
    
    if (current_allocations > peak_allocations) then
      peak_allocations = current_allocations
    end if
    
    if (current_memory_used > peak_memory_used) then
      peak_memory_used = current_memory_used
    end if
    
    if (perf_monitoring_enabled .and. present(location)) then
      write(output_unit, '(a,i15,a,a)') '[MEM] Allocated ', size_bytes, ' bytes at ', location
    end if
  end subroutine

  ! Track memory deallocation
  subroutine track_deallocation(size_bytes, location)
    integer, intent(in) :: size_bytes
    character(len=*), intent(in), optional :: location
    
    if (.not. memory_tracking_enabled) return
    
    current_allocations = current_allocations - 1
    current_memory_used = current_memory_used - size_bytes
    
    if (perf_monitoring_enabled .and. present(location)) then
      write(output_unit, '(a,i15,a,a)') '[MEM] Deallocated ', size_bytes, ' bytes at ', location
    end if
  end subroutine

  ! Initialize token memory pools
  subroutine init_token_pools()
    integer :: i
    
    do i = 1, MAX_TOKEN_POOLS
      token_pools(i)%capacity = 0
      token_pools(i)%size = 0
      token_pools(i)%in_use = .false.
    end do
  end subroutine

  ! Get a token array from pool (performance optimization)
  function get_pooled_tokens(requested_size) result(pool_id)
    integer, intent(in) :: requested_size
    integer :: pool_id
    
    integer :: i, best_fit, best_fit_size
    
    pool_id = 0
    best_fit = 0
    best_fit_size = huge(1)
    
    ! Find best-fit available pool
    do i = 1, MAX_TOKEN_POOLS
      if (.not. token_pools(i)%in_use .and. &
          token_pools(i)%capacity >= requested_size .and. &
          token_pools(i)%capacity < best_fit_size) then
        best_fit = i
        best_fit_size = token_pools(i)%capacity
      end if
    end do
    
    if (best_fit > 0) then
      pool_id = best_fit
      token_pools(pool_id)%in_use = .true.
      token_pools(pool_id)%size = requested_size
    else
      ! Create new pool
      pool_id = find_empty_pool()
      if (pool_id > 0) then
        allocate(token_pools(pool_id)%tokens(requested_size))
        token_pools(pool_id)%capacity = requested_size
        token_pools(pool_id)%size = requested_size
        token_pools(pool_id)%in_use = .true.
        call track_allocation(requested_size * 256, 'token_pool')
      end if
    end if
  end function

  ! Return tokens to pool
  subroutine return_pooled_tokens(pool_id)
    integer, intent(in) :: pool_id
    
    if (pool_id > 0 .and. pool_id <= MAX_TOKEN_POOLS) then
      token_pools(pool_id)%in_use = .false.
      token_pools(pool_id)%size = 0
    end if
  end subroutine

  ! Find empty pool slot
  function find_empty_pool() result(pool_id)
    integer :: pool_id
    integer :: i
    
    pool_id = 0
    do i = 1, MAX_TOKEN_POOLS
      if (token_pools(i)%capacity == 0) then
        pool_id = i
        return
      end if
    end do
  end function

  ! Optimize memory usage by compacting pools
  subroutine optimize_memory_pools()
    integer :: i, active_pools
    
    active_pools = 0
    
    ! Count active pools
    do i = 1, MAX_TOKEN_POOLS
      if (token_pools(i)%capacity > 0 .and. .not. token_pools(i)%in_use) then
        active_pools = active_pools + 1
      end if
    end do
    
    ! If we have too many unused pools, deallocate smaller ones
    if (active_pools > 5) then
      do i = 1, MAX_TOKEN_POOLS
        if (token_pools(i)%capacity > 0 .and. &
            .not. token_pools(i)%in_use .and. &
            token_pools(i)%capacity < 20) then
          
          if (allocated(token_pools(i)%tokens)) then
            call track_deallocation(token_pools(i)%capacity * 256, 'token_pool_cleanup')
            deallocate(token_pools(i)%tokens)
          end if
          token_pools(i)%capacity = 0
        end if
      end do
    end if
  end subroutine

  ! Print performance statistics
  subroutine print_performance_stats()
    integer(int64) :: current_time, uptime, count_rate
    real :: avg_parse_time, avg_exec_time, avg_glob_time
    
    call system_clock(current_time, count_rate)
    uptime = current_time - startup_time
    
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') '===================================='
    write(output_unit, '(a)') 'FORTSH PERFORMANCE STATISTICS'
    write(output_unit, '(a)') '===================================='
    
    ! Runtime statistics
    write(output_unit, '(a,f0.3,a)') 'Uptime:           ', real(uptime)/real(count_rate), ' seconds'
    write(output_unit, '(a,i15)') 'Total commands:   ', total_commands
    
    ! Performance timings
    if (total_commands > 0) then
      avg_parse_time = real(total_parse_time) / real(count_rate) / real(total_commands) * 1000.0
      avg_exec_time = real(total_exec_time) / real(count_rate) / real(total_commands) * 1000.0  
      avg_glob_time = real(total_glob_time) / real(count_rate) / real(total_commands) * 1000.0
      
      write(output_unit, '(a,f0.3,a)') 'Avg parse time:   ', avg_parse_time, ' ms'
      write(output_unit, '(a,f0.3,a)') 'Avg exec time:    ', avg_exec_time, ' ms'
      write(output_unit, '(a,f0.3,a)') 'Avg glob time:    ', avg_glob_time, ' ms'
    end if
    
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'MEMORY STATISTICS'
    write(output_unit, '(a)') '===================================='
    write(output_unit, '(a,i15)') 'Total allocations:  ', total_allocations
    write(output_unit, '(a,i15)') 'Current allocations:', current_allocations
    write(output_unit, '(a,i15)') 'Peak allocations:   ', peak_allocations
    write(output_unit, '(a,i15,a)') 'Total memory used:  ', total_memory_used, ' bytes'
    write(output_unit, '(a,i15,a)') 'Current memory:     ', current_memory_used, ' bytes'
    write(output_unit, '(a,i15,a)') 'Peak memory:        ', peak_memory_used, ' bytes'
    
    ! Memory pool statistics
    call print_pool_stats()
    
    write(output_unit, '(a)') '===================================='
  end subroutine

  ! Print memory pool statistics
  subroutine print_pool_stats()
    integer :: i, active_pools, total_capacity, used_capacity
    
    active_pools = 0
    total_capacity = 0
    used_capacity = 0
    
    do i = 1, MAX_TOKEN_POOLS
      if (token_pools(i)%capacity > 0) then
        active_pools = active_pools + 1
        total_capacity = total_capacity + token_pools(i)%capacity
        if (token_pools(i)%in_use) then
          used_capacity = used_capacity + token_pools(i)%size
        end if
      end if
    end do
    
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'TOKEN POOL STATISTICS'
    write(output_unit, '(a)') '===================================='
    write(output_unit, '(a,i15)') 'Active pools:       ', active_pools
    write(output_unit, '(a,i15)') 'Total capacity:     ', total_capacity
    write(output_unit, '(a,i15)') 'Used capacity:      ', used_capacity
    if (total_capacity > 0) then
      write(output_unit, '(a,f0.1,a)') 'Pool utilization:   ', &
        real(used_capacity)/real(total_capacity)*100.0, '%'
    end if
  end subroutine

  ! Cleanup performance monitoring
  subroutine cleanup_performance_monitoring()
    integer :: i
    
    ! Cleanup token pools
    do i = 1, MAX_TOKEN_POOLS
      if (allocated(token_pools(i)%tokens)) then
        deallocate(token_pools(i)%tokens)
      end if
    end do
    
    if (perf_monitoring_enabled) then
      write(output_unit, '(a)') '[PERF] Performance monitoring cleaned up'
    end if
  end subroutine

  ! Get memory usage estimate
  function get_memory_usage() result(usage_kb)
    integer :: usage_kb
    usage_kb = int(current_memory_used / 1024)
  end function

  ! Check if memory optimization is needed
  function needs_memory_optimization() result(needed)
    logical :: needed
    needed = (current_memory_used > 1024*1024) .or. (current_allocations > 100)
  end function

  ! Perform automatic memory optimization
  subroutine auto_optimize_memory()
    if (needs_memory_optimization()) then
      call optimize_memory_pools()
      if (perf_monitoring_enabled) then
        write(output_unit, '(a)') '[PERF] Auto memory optimization triggered'
      end if
    end if
  end subroutine

end module performance