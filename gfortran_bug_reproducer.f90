! gfortran stack corruption bug reproducer for macOS ARM64
! This more closely matches the actual fortsh issue
!
! Compile: gfortran -o reproducer gfortran_bug_reproducer.f90
! Run: ./reproducer
! Expected: Should handle character input without crashing
! Actual on macOS ARM64: Segmentation fault on character input

module terminal_state
  implicit none

  integer, parameter :: MAX_LINE = 4096
  integer, parameter :: MAX_HISTORY = 1000

  type :: input_state_type
    ! Main buffers - similar size to fortsh
    character(len=MAX_LINE) :: buffer
    character(len=MAX_LINE) :: saved_buffer
    character(len=MAX_LINE) :: suggestion
    character(len=MAX_LINE) :: last_completion_buffer

    ! History storage
    character(len=MAX_LINE) :: history(MAX_HISTORY)

    ! Menu/completion items
    character(len=256) :: menu_items(100)
    character(len=256) :: menu_prefix

    ! State tracking
    integer :: length
    integer :: cursor_pos
    integer :: history_count
    integer :: history_pos
    integer :: menu_selection
    integer :: menu_num_items
    integer :: menu_prefix_len
    integer :: suggestion_length

    ! Flags
    logical :: dirty
    logical :: in_menu_select
    logical :: in_search
    logical :: in_history
    logical :: completions_shown
    logical :: at_end_of_line

    ! Search state
    character(len=MAX_LINE) :: search_pattern
    integer :: search_pos
    integer :: search_direction
  end type input_state_type

contains

  ! This simulates the readline function that crashes
  subroutine read_line(prompt, line)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    type(input_state_type) :: state
    character :: ch

    ! Initialize
    state%buffer = ""
    state%length = 0
    state%cursor_pos = 0
    state%dirty = .false.

    print '(a,$)', prompt

    ! Read a character (simulated)
    read(*, '(a1)') ch

    ! Process the character - this is where it crashes in fortsh
    call handle_character(state, ch)

    ! The crash happens after this return
    line = state%buffer(:state%length)
  end subroutine read_line

  ! Handle a single character - the problematic function
  subroutine handle_character(state, ch)
    type(input_state_type), intent(inout) :: state
    character, intent(in) :: ch

    ! Insert character
    if (state%length < MAX_LINE) then
      state%length = state%length + 1
      state%buffer(state%length:state%length) = ch
      state%cursor_pos = state%length
      state%dirty = .true.

      ! Now redraw - passing state causes issues
      call redraw_line(state)
    end if

    ! Stack corruption occurs here during return
  end subroutine handle_character

  ! Redraw the line - taking large state as parameter
  subroutine redraw_line(state)
    type(input_state_type), intent(in) :: state
    character(len=100) :: temp

    ! Simulate redraw
    write(temp, '(a)') state%buffer(:state%length)
    print *, trim(temp)

    ! Return from here often triggers segfault
  end subroutine redraw_line

end module terminal_state

program test_crash
  use terminal_state
  implicit none
  character(len=4096) :: input

  print *, "gfortran macOS ARM64 bug reproducer"
  print *, "Type a single character and press Enter:"

  ! This call chain will crash on macOS ARM64
  call read_line("> ", input)

  print *, "You typed: ", trim(input)
  print *, "SUCCESS: No crash!"

end program test_crash