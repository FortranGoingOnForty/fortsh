! ==============================================================================
! Module: memory_dashboard
! Purpose: Real-time memory pool statistics and visualization
! Phase 4 of the memory pooling project
! ==============================================================================
module memory_dashboard
  use iso_fortran_env, only: int32, int64, output_unit
  use string_pool
  implicit none
  private

  ! Public interface
  public :: dashboard_init, dashboard_register_module, dashboard_track_allocation
  public :: dashboard_track_deallocation, dashboard_display, dashboard_get_module_stats
  public :: dashboard_cleanup, dashboard_export_csv, dashboard_summary
  public :: module_stats  ! Export type for testing
  public :: MOD_READLINE, MOD_COMPLETION, MOD_PARSER, MOD_EXECUTOR, MOD_EXPANSION
  public :: MOD_BUILTIN, MOD_AST, MOD_LEXER, MOD_EVALUATOR, MOD_HISTORY, MOD_VARIABLES

  ! Module tracking
  integer, parameter :: MAX_MODULES = 50
  integer, parameter :: MODULE_NAME_LEN = 32

  ! Module IDs - these should match the actual modules in fortsh
  integer, parameter :: MOD_READLINE = 1
  integer, parameter :: MOD_COMPLETION = 2
  integer, parameter :: MOD_PARSER = 3
  integer, parameter :: MOD_EXECUTOR = 4
  integer, parameter :: MOD_EXPANSION = 5
  integer, parameter :: MOD_BUILTIN = 6
  integer, parameter :: MOD_AST = 7
  integer, parameter :: MOD_LEXER = 8
  integer, parameter :: MOD_EVALUATOR = 9
  integer, parameter :: MOD_HISTORY = 10
  integer, parameter :: MOD_VARIABLES = 11
  integer, parameter :: MOD_UNKNOWN = 99

  ! Module statistics
  type :: module_stats
    character(len=MODULE_NAME_LEN) :: name = "unknown"
    integer(int64) :: total_allocations = 0
    integer(int64) :: total_deallocations = 0
    integer(int64) :: current_bytes = 0
    integer(int64) :: peak_bytes = 0
    integer(int64) :: total_bytes_allocated = 0
    integer :: current_strings = 0
    integer :: peak_strings = 0
    ! Bucket-specific stats
    integer(int64) :: bucket_allocs(5) = 0  ! Count per bucket size
    integer(int64) :: bucket_bytes(5) = 0   ! Current bytes per bucket
  end type module_stats

  ! Global dashboard state
  type :: dashboard_state
    type(module_stats) :: modules(MAX_MODULES)
    integer :: num_registered = 0
    logical :: initialized = .false.
    logical :: verbose = .false.
    integer(int64) :: session_start_time = 0
    ! Pool efficiency metrics
    real :: overall_hit_rate = 0.0
    integer(int64) :: total_pool_expansions = 0
    integer(int64) :: fragmentation_bytes = 0
  end type dashboard_state

  type(dashboard_state) :: dashboard

  ! ANSI color codes for terminal output
  character(len=*), parameter :: RESET = char(27)//"[0m"
  character(len=*), parameter :: BOLD = char(27)//"[1m"
  character(len=*), parameter :: RED = char(27)//"[31m"
  character(len=*), parameter :: GREEN = char(27)//"[32m"
  character(len=*), parameter :: YELLOW = char(27)//"[33m"
  character(len=*), parameter :: BLUE = char(27)//"[34m"
  character(len=*), parameter :: CYAN = char(27)//"[36m"

contains

  ! Initialize the dashboard
  subroutine dashboard_init(verbose)
    logical, intent(in), optional :: verbose

    dashboard%initialized = .true.
    dashboard%verbose = .false.
    if (present(verbose)) dashboard%verbose = verbose

    ! Get start time (simplified - would use system clock in real implementation)
    dashboard%session_start_time = 0

    ! Register known modules
    call dashboard_register_module(MOD_READLINE, "readline")
    call dashboard_register_module(MOD_COMPLETION, "completion")
    call dashboard_register_module(MOD_PARSER, "parser")
    call dashboard_register_module(MOD_EXECUTOR, "executor")
    call dashboard_register_module(MOD_EXPANSION, "expansion")
    call dashboard_register_module(MOD_BUILTIN, "builtin")
    call dashboard_register_module(MOD_AST, "ast")
    call dashboard_register_module(MOD_LEXER, "lexer")
    call dashboard_register_module(MOD_EVALUATOR, "evaluator")
    call dashboard_register_module(MOD_HISTORY, "history")
    call dashboard_register_module(MOD_VARIABLES, "variables")

  end subroutine dashboard_init

  ! Register a module for tracking
  subroutine dashboard_register_module(module_id, module_name)
    integer, intent(in) :: module_id
    character(len=*), intent(in) :: module_name

    if (.not. dashboard%initialized) call dashboard_init()

    if (module_id <= MAX_MODULES) then
      dashboard%modules(module_id)%name = module_name
      if (module_id > dashboard%num_registered) then
        dashboard%num_registered = module_id
      end if
    end if

  end subroutine dashboard_register_module

  ! Track an allocation from a specific module
  subroutine dashboard_track_allocation(module_id, size_bytes, bucket_idx)
    integer, intent(in) :: module_id
    integer, intent(in) :: size_bytes
    integer, intent(in), optional :: bucket_idx

    if (.not. dashboard%initialized) return
    if (module_id > MAX_MODULES) return

    ! Update module stats
    dashboard%modules(module_id)%total_allocations = &
      dashboard%modules(module_id)%total_allocations + 1
    dashboard%modules(module_id)%current_bytes = &
      dashboard%modules(module_id)%current_bytes + size_bytes
    dashboard%modules(module_id)%total_bytes_allocated = &
      dashboard%modules(module_id)%total_bytes_allocated + size_bytes
    dashboard%modules(module_id)%current_strings = &
      dashboard%modules(module_id)%current_strings + 1

    ! Update peak if necessary
    if (dashboard%modules(module_id)%current_bytes > dashboard%modules(module_id)%peak_bytes) then
      dashboard%modules(module_id)%peak_bytes = dashboard%modules(module_id)%current_bytes
    end if
    if (dashboard%modules(module_id)%current_strings > dashboard%modules(module_id)%peak_strings) then
      dashboard%modules(module_id)%peak_strings = dashboard%modules(module_id)%current_strings
    end if

    ! Track bucket-specific stats
    if (present(bucket_idx) .and. bucket_idx >= 1 .and. bucket_idx <= 5) then
      dashboard%modules(module_id)%bucket_allocs(bucket_idx) = &
        dashboard%modules(module_id)%bucket_allocs(bucket_idx) + 1
      dashboard%modules(module_id)%bucket_bytes(bucket_idx) = &
        dashboard%modules(module_id)%bucket_bytes(bucket_idx) + size_bytes
    end if

  end subroutine dashboard_track_allocation

  ! Track a deallocation from a specific module
  subroutine dashboard_track_deallocation(module_id, size_bytes, bucket_idx)
    integer, intent(in) :: module_id
    integer, intent(in) :: size_bytes
    integer, intent(in), optional :: bucket_idx

    if (.not. dashboard%initialized) return
    if (module_id > MAX_MODULES) return

    dashboard%modules(module_id)%total_deallocations = &
      dashboard%modules(module_id)%total_deallocations + 1
    dashboard%modules(module_id)%current_bytes = &
      dashboard%modules(module_id)%current_bytes - size_bytes
    dashboard%modules(module_id)%current_strings = &
      dashboard%modules(module_id)%current_strings - 1

    ! Update bucket stats
    if (present(bucket_idx) .and. bucket_idx >= 1 .and. bucket_idx <= 5) then
      dashboard%modules(module_id)%bucket_bytes(bucket_idx) = &
        dashboard%modules(module_id)%bucket_bytes(bucket_idx) - size_bytes
    end if

  end subroutine dashboard_track_deallocation

  ! Display the dashboard
  subroutine dashboard_display(detailed)
    logical, intent(in), optional :: detailed
    logical :: show_details
    integer :: i, j, total_allocs, total_deallocs, current_strings, peak_strings
    real :: hit_rate
    integer(int64) :: total_current, total_peak, total_allocated
    character(len=80) :: bar
    real :: percent

    show_details = .false.
    if (present(detailed)) show_details = detailed

    ! Get current pool statistics
    call pool_statistics(total_allocs, total_deallocs, current_strings, peak_strings, hit_rate)

    ! Print header
    write(output_unit,'(a)') ""
    write(output_unit,'(a)') BOLD//CYAN// &
      "======================================================================"//RESET
    write(output_unit,'(a)') BOLD//CYAN// &
      "           FORTSH MEMORY POOL STATISTICS DASHBOARD"//RESET
    write(output_unit,'(a)') BOLD//CYAN// &
      "======================================================================"//RESET
    write(output_unit,'(a)') ""

    ! Overall statistics
    write(output_unit,'(a)') BOLD//"═══ Overall Pool Performance ═══"//RESET
    write(output_unit,'(a,i12)') "  Total Allocations:     ", total_allocs
    write(output_unit,'(a,i12)') "  Total Deallocations:  ", total_deallocs
    write(output_unit,'(a,i12)') "  Current Strings:      ", current_strings
    write(output_unit,'(a,i12)') "  Peak Strings:         ", peak_strings

    ! Cache performance with color coding
    if (hit_rate > 0.95) then
      write(output_unit,'(a,f6.1,a)') "  Cache Hit Rate:       "//GREEN, hit_rate * 100.0, "%"//RESET
    else if (hit_rate > 0.80) then
      write(output_unit,'(a,f6.1,a)') "  Cache Hit Rate:       "//YELLOW, hit_rate * 100.0, "%"//RESET
    else
      write(output_unit,'(a,f6.1,a)') "  Cache Hit Rate:       "//RED, hit_rate * 100.0, "%"//RESET
    end if

    ! Memory usage bar graph
    if (peak_strings > 0) then
      percent = real(current_strings) / real(peak_strings)
      call draw_progress_bar(bar, percent)
      write(output_unit,'(a)') "  Memory Usage: "//trim(bar)
    end if

    write(output_unit,'(a)') ""

    ! Per-module statistics
    write(output_unit,'(a)') BOLD//"═══ Module Memory Usage ═══"//RESET
    write(output_unit,'(a)') "  Module          Allocs    Deallocs  Current   Peak     Bytes"
    write(output_unit,'(a)') &
      "  ---------------------------------------------------------------"

    total_current = 0
    total_peak = 0
    total_allocated = 0

    do i = 1, dashboard%num_registered
      if (dashboard%modules(i)%total_allocations > 0) then
        write(output_unit,'(a,a16,i10,i10,i8,i8,a,a)') "  ", &
          adjustl(dashboard%modules(i)%name), &
          int(dashboard%modules(i)%total_allocations), &
          int(dashboard%modules(i)%total_deallocations), &
          dashboard%modules(i)%current_strings, &
          dashboard%modules(i)%peak_strings, &
          "  ", format_bytes(dashboard%modules(i)%current_bytes)

        total_current = total_current + dashboard%modules(i)%current_bytes
        total_peak = total_peak + dashboard%modules(i)%peak_bytes
        total_allocated = total_allocated + dashboard%modules(i)%total_bytes_allocated
      end if
    end do

    write(output_unit,'(a)') &
      "  ---------------------------------------------------------------"
    write(output_unit,'(a,a)') "  Total Current Memory:                                ", &
      format_bytes(total_current)
    write(output_unit,'(a,a)') "  Total Peak Memory:                                   ", &
      format_bytes(total_peak)

    ! Detailed bucket analysis if requested
    if (show_details) then
      write(output_unit,'(a)') ""
      write(output_unit,'(a)') BOLD//"═══ Bucket Distribution ═══"//RESET
      write(output_unit,'(a)') "  Size     Module          Allocations   Current Bytes"
      write(output_unit,'(a)') &
        "  --------------------------------------------------------"

      do j = 1, 5
        select case(j)
        case(1)
          write(output_unit,'(a)') "  64 bytes:"
        case(2)
          write(output_unit,'(a)') "  256 bytes:"
        case(3)
          write(output_unit,'(a)') "  1024 bytes:"
        case(4)
          write(output_unit,'(a)') "  4096 bytes:"
        case(5)
          write(output_unit,'(a)') "  16384 bytes:"
        end select

        do i = 1, dashboard%num_registered
          if (dashboard%modules(i)%bucket_allocs(j) > 0) then
            write(output_unit,'(a,a16,i14,a,a)') "           ", &
              adjustl(dashboard%modules(i)%name), &
              int(dashboard%modules(i)%bucket_allocs(j)), &
              "    ", format_bytes(dashboard%modules(i)%bucket_bytes(j))
          end if
        end do
      end do
    end if

    write(output_unit,'(a)') ""
    write(output_unit,'(a)') BOLD//CYAN// &
      "======================================================================"//RESET
    write(output_unit,'(a)') ""

  end subroutine dashboard_display

  ! Draw a progress bar
  subroutine draw_progress_bar(bar, percent)
    character(len=*), intent(out) :: bar
    real, intent(in) :: percent
    integer :: filled_chars, i, bar_len
    integer, parameter :: BAR_WIDTH = 30
    character(len=10) :: percent_str

    filled_chars = min(int(percent * BAR_WIDTH), BAR_WIDTH)
    bar = " ["

    ! Build the bar safely
    do i = 1, filled_chars
      if (len_trim(bar) < len(bar) - 20) then  ! Leave room for percentage
        bar = trim(bar) // "█"
      end if
    end do

    do i = filled_chars + 1, BAR_WIDTH
      if (len_trim(bar) < len(bar) - 20) then  ! Leave room for percentage
        bar = trim(bar) // "─"
      end if
    end do

    bar = trim(bar) // "] "
    write(percent_str, '(f5.1,a)') percent * 100.0, "%"

    ! Only append percentage if there's room
    bar_len = len_trim(bar) + len_trim(percent_str)
    if (bar_len < len(bar)) then
      bar = trim(bar) // trim(adjustl(percent_str))
    end if

  end subroutine draw_progress_bar

  ! Format bytes for display
  function format_bytes(bytes) result(formatted)
    integer(int64), intent(in) :: bytes
    character(len=20) :: formatted

    if (bytes < 1024) then
      write(formatted, '(i0,a)') bytes, " B"
    else if (bytes < 1024*1024) then
      write(formatted, '(f0.1,a)') real(bytes)/1024.0, " KB"
    else if (bytes < int(1024,int64)*1024*1024) then
      write(formatted, '(f0.1,a)') real(bytes)/(1024.0*1024.0), " MB"
    else
      write(formatted, '(f0.1,a)') real(bytes)/(1024.0*1024.0*1024.0), " GB"
    end if

    formatted = adjustr(formatted)

  end function format_bytes

  ! Get statistics for a specific module
  function dashboard_get_module_stats(module_id) result(stats)
    integer, intent(in) :: module_id
    type(module_stats) :: stats

    if (module_id > 0 .and. module_id <= MAX_MODULES) then
      stats = dashboard%modules(module_id)
    else
      stats%name = "invalid"
    end if

  end function dashboard_get_module_stats

  ! Export statistics to CSV
  subroutine dashboard_export_csv(filename)
    character(len=*), intent(in) :: filename
    integer :: unit, i, iostat

    open(newunit=unit, file=filename, status='replace', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(output_unit,'(a)') "Error: Could not open CSV file for export"
      return
    end if

    ! Write header
    write(unit,'(a)') "Module,Total_Allocations,Total_Deallocations,Current_Strings," // &
                      "Peak_Strings,Current_Bytes,Peak_Bytes,Total_Bytes_Allocated"

    ! Write data
    do i = 1, dashboard%num_registered
      if (dashboard%modules(i)%total_allocations > 0) then
        write(unit,'(a,",",i0,",",i0,",",i0,",",i0,",",i0,",",i0,",",i0)') &
          trim(dashboard%modules(i)%name), &
          dashboard%modules(i)%total_allocations, &
          dashboard%modules(i)%total_deallocations, &
          dashboard%modules(i)%current_strings, &
          dashboard%modules(i)%peak_strings, &
          dashboard%modules(i)%current_bytes, &
          dashboard%modules(i)%peak_bytes, &
          dashboard%modules(i)%total_bytes_allocated
      end if
    end do

    close(unit)
    write(output_unit,'(a,a)') "Statistics exported to: ", trim(filename)

  end subroutine dashboard_export_csv

  ! Display a summary
  subroutine dashboard_summary()
    integer(int64) :: total_saved, total_allocated
    integer :: i
    real :: efficiency

    write(output_unit,'(a)') ""
    write(output_unit,'(a)') BOLD//"═══ Memory Pool Summary ═══"//RESET

    total_allocated = 0
    do i = 1, dashboard%num_registered
      total_allocated = total_allocated + dashboard%modules(i)%total_bytes_allocated
    end do

    ! Calculate approximate memory saved (assuming 50% reduction from pooling)
    total_saved = total_allocated / 2

    write(output_unit,'(a,a)') "  Total Memory Processed: ", format_bytes(total_allocated)
    write(output_unit,'(a,a)') "  Estimated Memory Saved: ", format_bytes(total_saved)

    if (total_allocated > 0) then
      efficiency = real(total_saved) / real(total_allocated) * 100.0
      write(output_unit,'(a,f5.1,a)') "  Pool Efficiency:        ", efficiency, "%"
    end if

    write(output_unit,'(a)') ""

  end subroutine dashboard_summary

  ! Clean up the dashboard
  subroutine dashboard_cleanup()
    integer :: i

    do i = 1, MAX_MODULES
      dashboard%modules(i)%total_allocations = 0
      dashboard%modules(i)%total_deallocations = 0
      dashboard%modules(i)%current_bytes = 0
      dashboard%modules(i)%peak_bytes = 0
      dashboard%modules(i)%total_bytes_allocated = 0
      dashboard%modules(i)%current_strings = 0
      dashboard%modules(i)%peak_strings = 0
      dashboard%modules(i)%bucket_allocs = 0
      dashboard%modules(i)%bucket_bytes = 0
    end do

    dashboard%num_registered = 0
    dashboard%initialized = .false.

  end subroutine dashboard_cleanup

end module memory_dashboard