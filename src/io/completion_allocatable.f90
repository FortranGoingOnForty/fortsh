! Allocatable completion storage - matches modern shell design
module completion_allocatable
  use, intrinsic :: iso_fortran_env
  implicit none

  integer, parameter :: MAX_LINE_LEN = 4096
  integer, parameter :: INITIAL_CAPACITY = 20  ! Start small
  integer, parameter :: GROWTH_FACTOR = 2      ! Double when growing

  ! Dynamic completion list using allocatable arrays
  type :: completion_list_t
    character(len=:), allocatable :: items(:)
    integer :: capacity = 0
    integer :: count = 0
  contains
    procedure :: init => init_completion_list
    procedure :: add => add_completion
    procedure :: grow => grow_completion_list
    procedure :: clear => clear_completion_list
    procedure :: get_visible => get_visible_items
  end type

contains

  ! Initialize with small capacity
  subroutine init_completion_list(this, initial_size)
    class(completion_list_t), intent(inout) :: this
    integer, optional, intent(in) :: initial_size
    integer :: size

    size = INITIAL_CAPACITY
    if (present(initial_size)) size = initial_size

    if (allocated(this%items)) deallocate(this%items)
    allocate(character(len=MAX_LINE_LEN) :: this%items(size))
    this%capacity = size
    this%count = 0
  end subroutine

  ! Add item, growing if needed
  subroutine add_completion(this, item)
    class(completion_list_t), intent(inout) :: this
    character(len=*), intent(in) :: item

    ! Grow if needed
    if (this%count >= this%capacity) then
      call this%grow()
    end if

    this%count = this%count + 1
    this%items(this%count) = item
  end subroutine

  ! Double capacity when full
  subroutine grow_completion_list(this)
    class(completion_list_t), intent(inout) :: this
    character(len=MAX_LINE_LEN), allocatable :: temp(:)
    integer :: new_capacity

    new_capacity = this%capacity * GROWTH_FACTOR
    allocate(temp(new_capacity))

    ! Copy existing items
    temp(1:this%count) = this%items(1:this%count)

    ! Swap arrays
    call move_alloc(temp, this%items)
    this%capacity = new_capacity
  end subroutine

  ! Get only visible items for display (like fish/zsh pager)
  function get_visible_items(this, start_idx, max_visible) result(visible)
    class(completion_list_t), intent(in) :: this
    integer, intent(in) :: start_idx
    integer, intent(in) :: max_visible
    character(len=MAX_LINE_LEN) :: visible(max_visible)
    integer :: i, end_idx

    end_idx = min(start_idx + max_visible - 1, this%count)
    do i = start_idx, end_idx
      visible(i - start_idx + 1) = this%items(i)
    end do
  end function

  ! Clean up
  subroutine clear_completion_list(this)
    class(completion_list_t), intent(inout) :: this
    if (allocated(this%items)) deallocate(this%items)
    this%capacity = 0
    this%count = 0
  end subroutine

end module