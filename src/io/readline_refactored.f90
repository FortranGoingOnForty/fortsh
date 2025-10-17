! Refactored input_state_t with allocatable arrays to avoid static storage issues
! This prevents the massive 250KB+ structure from being moved to static storage

module readline_types_refactored
  use, intrinsic :: iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  integer, parameter :: MAX_LINE_LEN = 4096
  integer, parameter :: MAX_MENU_ITEMS = 50

  ! Refactored with allocatable arrays to reduce stack footprint
  type :: input_state_refactored_t
    ! Core buffers - allocatable to avoid static storage
    character(len=:), allocatable :: buffer
    character(len=:), allocatable :: original_buffer
    character(len=:), allocatable :: kill_buffer
    character(len=:), allocatable :: last_completion_buffer

    ! State counters
    integer :: length = 0
    integer :: cursor_pos = 0
    integer :: history_pos = 0
    integer :: kill_length = 0

    ! Flags
    logical :: dirty = .false.
    logical :: in_history = .false.
    logical :: completions_shown = .false.

    ! Search state
    logical :: in_search = .false.
    logical :: search_forward = .false.
    character(len=:), allocatable :: search_string
    integer :: search_length = 0
    integer :: search_match_index = 0

    ! Vi mode
    integer :: editing_mode = 1  ! EDITING_MODE_EMACS
    integer :: vi_mode = 1       ! VI_MODE_INSERT
    character(len=:), allocatable :: vi_command_buffer
    integer :: vi_command_count = 0
    logical :: vi_repeat_pending = .false.

    ! Advanced vi
    character(len=:), allocatable :: vi_yank_buffer
    integer :: vi_yank_length = 0
    integer :: vi_marks(26) = 0
    character(len=:), allocatable :: vi_search_pattern
    integer :: vi_search_length = 0
    logical :: vi_search_forward = .true.
    logical :: vi_in_vi_search = .false.

    ! Autosuggestion
    character(len=:), allocatable :: suggestion
    integer :: suggestion_length = 0

    ! Menu selection - use allocatable array to avoid massive static allocation
    logical :: in_menu_select = .false.
    type(menu_item_t), allocatable :: menu_items(:)
    integer :: menu_num_items = 0
    integer :: menu_selection = 1
    character(len=:), allocatable :: menu_prefix
    integer :: menu_prefix_len = 0
  end type

  ! Separate type for menu items to allow dynamic allocation
  type :: menu_item_t
    character(len=:), allocatable :: text
  end type

contains

  ! Initialize the refactored input state with allocations
  subroutine init_input_state_refactored(state)
    type(input_state_refactored_t), intent(out) :: state
    integer :: i

    ! Allocate core buffers with reasonable initial size
    allocate(character(len=MAX_LINE_LEN) :: state%buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%original_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%kill_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%last_completion_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%search_string)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_command_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_yank_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_search_pattern)
    allocate(character(len=MAX_LINE_LEN) :: state%suggestion)
    allocate(character(len=MAX_LINE_LEN) :: state%menu_prefix)

    ! Initialize buffers
    state%buffer = ''
    state%original_buffer = ''
    state%kill_buffer = ''
    state%last_completion_buffer = ''
    state%search_string = ''
    state%vi_command_buffer = ''
    state%vi_yank_buffer = ''
    state%vi_search_pattern = ''
    state%suggestion = ''
    state%menu_prefix = ''

    ! Allocate menu items array
    allocate(state%menu_items(MAX_MENU_ITEMS))
    do i = 1, MAX_MENU_ITEMS
      allocate(character(len=MAX_LINE_LEN) :: state%menu_items(i)%text)
      state%menu_items(i)%text = ''
    end do

    ! Initialize counters
    state%length = 0
    state%cursor_pos = 0
    state%history_pos = 0
    state%kill_length = 0
    state%search_length = 0
    state%search_match_index = 0
    state%vi_command_count = 0
    state%vi_yank_length = 0
    state%vi_search_length = 0
    state%suggestion_length = 0
    state%menu_num_items = 0
    state%menu_selection = 1
    state%menu_prefix_len = 0

    ! Initialize flags
    state%dirty = .false.
    state%in_history = .false.
    state%completions_shown = .false.
    state%in_search = .false.
    state%search_forward = .false.
    state%vi_repeat_pending = .false.
    state%vi_search_forward = .true.
    state%vi_in_vi_search = .false.
    state%in_menu_select = .false.

    ! Initialize vi marks
    state%vi_marks = 0
  end subroutine

  ! Clean up allocated memory
  subroutine cleanup_input_state_refactored(state)
    type(input_state_refactored_t), intent(inout) :: state
    integer :: i

    ! Deallocate string buffers
    if (allocated(state%buffer)) deallocate(state%buffer)
    if (allocated(state%original_buffer)) deallocate(state%original_buffer)
    if (allocated(state%kill_buffer)) deallocate(state%kill_buffer)
    if (allocated(state%last_completion_buffer)) deallocate(state%last_completion_buffer)
    if (allocated(state%search_string)) deallocate(state%search_string)
    if (allocated(state%vi_command_buffer)) deallocate(state%vi_command_buffer)
    if (allocated(state%vi_yank_buffer)) deallocate(state%vi_yank_buffer)
    if (allocated(state%vi_search_pattern)) deallocate(state%vi_search_pattern)
    if (allocated(state%suggestion)) deallocate(state%suggestion)
    if (allocated(state%menu_prefix)) deallocate(state%menu_prefix)

    ! Deallocate menu items
    if (allocated(state%menu_items)) then
      do i = 1, size(state%menu_items)
        if (allocated(state%menu_items(i)%text)) then
          deallocate(state%menu_items(i)%text)
        end if
      end do
      deallocate(state%menu_items)
    end if
  end subroutine

  ! Copy data from old structure to new (for migration)
  subroutine migrate_to_refactored(old_buffer, old_length, old_cursor_pos, new_state)
    character(len=*), intent(in) :: old_buffer
    integer, intent(in) :: old_length, old_cursor_pos
    type(input_state_refactored_t), intent(inout) :: new_state

    ! Copy buffer content
    new_state%buffer(:old_length) = old_buffer(:old_length)
    new_state%length = old_length
    new_state%cursor_pos = old_cursor_pos
  end subroutine

end module readline_types_refactored