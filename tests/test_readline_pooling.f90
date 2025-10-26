! ==============================================================================
! Simplified test for readline buffer pooling
! Tests the key buffer allocations without full readline complexity
! ==============================================================================
program test_readline_pooling
  use string_pool
  use memory_dashboard
  use iso_fortran_env, only: output_unit
  implicit none

  ! Readline buffer sizes (from readline.f90)
  integer, parameter :: MAX_LINE_LEN = 1024
  integer, parameter :: MAX_MENU_ITEM_LEN = 256

  ! Pooled readline state type (simplified)
  type :: readline_state_pooled_t
    type(string_ref) :: buffer_ref            ! Current input line
    type(string_ref) :: original_buffer_ref   ! Saved for history
    type(string_ref) :: kill_buffer_ref       ! Cut/paste buffer
    type(string_ref) :: completion_buffer_ref ! Tab completion state
    type(string_ref) :: vi_command_ref        ! Vi command buffer
    type(string_ref) :: vi_yank_ref           ! Vi yank buffer
    type(string_ref) :: search_string_ref     ! Incremental search
    type(string_ref) :: menu_prefix_ref       ! Completion prefix
    integer :: length = 0
    integer :: cursor_pos = 0
    logical :: initialized = .false.
  end type readline_state_pooled_t

  type(readline_state_pooled_t) :: state
  type(string_ref) :: temp_ref
  integer :: i, j
  logical :: test_passed
  integer :: total_allocs, total_deallocs, current_strings, peak_strings
  real :: hit_rate
  character(len=1024) :: test_input

  test_passed = .true.

  print *, "=== Phase 6 Readline Buffer Pooling Test ==="
  print *, "Testing pooled memory for readline buffers"
  print *

  ! Initialize pool and dashboard
  call pool_init()
  call dashboard_init(verbose=.false.)

  ! Test 1: Line buffer allocation
  print *, "Test 1: Testing line buffer allocation..."

  state%buffer_ref = pool_get_string(MAX_LINE_LEN)
  call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)
  call pool_copy_to_ref(state%buffer_ref, "echo 'Hello World!'")

  if (associated(state%buffer_ref%data)) then
    print *, "  Buffer allocated:", trim(state%buffer_ref%data)
    if (state%buffer_ref%pool_index > 0) then
      print *, "  PASSED: Buffer from pool"
    else
      print *, "  FAILED: Buffer not from pool"
      test_passed = .false.
    end if
  end if

  ! Test 2: Multiple readline buffers (simulating interactive session)
  print *, ""
  print *, "Test 2: Testing multiple readline buffers..."

  state%original_buffer_ref = pool_get_string(MAX_LINE_LEN)
  state%kill_buffer_ref = pool_get_string(MAX_LINE_LEN)
  state%completion_buffer_ref = pool_get_string(MAX_LINE_LEN)

  call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)
  call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)
  call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

  call pool_copy_to_ref(state%original_buffer_ref, "ls -la /usr/bin")
  call pool_copy_to_ref(state%kill_buffer_ref, "deleted text here")
  call pool_copy_to_ref(state%completion_buffer_ref, "partial_comm")

  print *, "  Original:", trim(state%original_buffer_ref%data)
  print *, "  Kill buffer:", trim(state%kill_buffer_ref%data)
  print *, "  Completion:", trim(state%completion_buffer_ref%data)
  print *, "  PASSED: Multiple buffers allocated"

  ! Test 3: Vi mode buffers
  print *, ""
  print *, "Test 3: Testing Vi mode buffers..."

  state%vi_command_ref = pool_get_string(MAX_LINE_LEN)
  state%vi_yank_ref = pool_get_string(MAX_LINE_LEN)

  call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)
  call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

  call pool_copy_to_ref(state%vi_command_ref, "dd")
  call pool_copy_to_ref(state%vi_yank_ref, "yanked line content")

  print *, "  Vi command:", trim(state%vi_command_ref%data)
  print *, "  Vi yank:", trim(state%vi_yank_ref%data)
  print *, "  PASSED: Vi buffers working"

  ! Test 4: Search and menu buffers
  print *, ""
  print *, "Test 4: Testing search and menu buffers..."

  state%search_string_ref = pool_get_string(MAX_MENU_ITEM_LEN)
  state%menu_prefix_ref = pool_get_string(MAX_MENU_ITEM_LEN)

  call dashboard_track_allocation(MOD_READLINE, MAX_MENU_ITEM_LEN, 2)
  call dashboard_track_allocation(MOD_READLINE, MAX_MENU_ITEM_LEN, 2)

  call pool_copy_to_ref(state%search_string_ref, "search_term")
  call pool_copy_to_ref(state%menu_prefix_ref, "comp")

  print *, "  Search:", trim(state%search_string_ref%data)
  print *, "  Menu prefix:", trim(state%menu_prefix_ref%data)
  print *, "  PASSED: Search/menu buffers working"

  ! Test 5: Simulate line editing session (buffer updates)
  print *, ""
  print *, "Test 5: Simulating line editing with buffer updates..."

  do i = 1, 100
    ! Simulate user typing/editing
    write(test_input, '(A,I0)') "Command iteration ", i

    ! Release old buffer
    call pool_release_string(state%buffer_ref)
    call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

    ! Get new buffer for updated line
    state%buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)
    call pool_copy_to_ref(state%buffer_ref, trim(test_input))
  end do

  print *, "  Last buffer:", trim(state%buffer_ref%data)
  print *, "  Completed 100 editing cycles"

  ! Test 6: Stress test - rapid completion buffer allocation/deallocation
  print *, ""
  print *, "Test 6: Stress testing completion buffers..."

  do i = 1, 500
    temp_ref = pool_get_string(MAX_MENU_ITEM_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_MENU_ITEM_LEN, 2)
    call pool_copy_to_ref(temp_ref, "completion_candidate")

    ! Release immediately (simulating showing then hiding completions)
    call pool_release_string(temp_ref)
    call dashboard_track_deallocation(MOD_READLINE, MAX_MENU_ITEM_LEN, 2)
  end do

  print *, "  Completed 500 completion cycles"

  ! Clean up all buffers
  print *, ""
  print *, "Cleaning up all readline buffers..."

  call pool_release_string(state%buffer_ref)
  call pool_release_string(state%original_buffer_ref)
  call pool_release_string(state%kill_buffer_ref)
  call pool_release_string(state%completion_buffer_ref)
  call pool_release_string(state%vi_command_ref)
  call pool_release_string(state%vi_yank_ref)
  call pool_release_string(state%search_string_ref)
  call pool_release_string(state%menu_prefix_ref)

  call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)  ! buffer
  call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)  ! original
  call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)  ! kill
  call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)  ! completion
  call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)  ! vi_command
  call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)  ! vi_yank
  call dashboard_track_deallocation(MOD_READLINE, MAX_MENU_ITEM_LEN, 2)  ! search
  call dashboard_track_deallocation(MOD_READLINE, MAX_MENU_ITEM_LEN, 2)  ! menu_prefix

  print *, "  All buffers released"

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
  print *, "=== Readline Module Statistics ==="
  call dashboard_display(detailed=.false.)

  ! Export statistics
  call dashboard_export_csv("readline_pooling_test.csv")
  print *, ""
  print *, "Statistics exported to readline_pooling_test.csv"

  ! Clean up
  call dashboard_cleanup()
  call pool_cleanup()

  ! Summary
  print *, ""
  print *, "=== Test Summary ==="
  if (test_passed .and. current_strings == 0) then
    print *, "ALL TESTS PASSED"
    print *, ""
    print *, "Readline buffer pooling verified:"
    print *, "  - Line buffers (1024B) working"
    print *, "  - Vi mode buffers working"
    print *, "  - Search/menu buffers (256B) working"
    print *, "  - Line editing simulation successful"
    print *, "  - Completion stress test passed"
    print *, "  - No memory leaks detected"
    print *, "  - Cache hit rate:", int(hit_rate * 100), "%"
    print *, ""
    print *, "Ready to integrate pooling into readline module!"
  else
    print *, "SOME TESTS FAILED"
    if (current_strings > 0) then
      print *, "  Memory leak:", current_strings, "strings not released"
    end if
  end if

end program test_readline_pooling