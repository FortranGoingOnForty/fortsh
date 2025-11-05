!===============================================================================
! fortsh_c_strings.f90 - Fortran wrapper for C string buffer library
!
! Purpose: Provide safe string operations that bypass flang-new ARM64 bugs
!
! Usage:
!   use fortsh_c_strings
!   type(c_string_buffer) :: buf
!   character(len=1024) :: fortran_str
!
!   buf = c_string_create(1024)
!   call c_string_set(buf, "Hello, World!")
!   call c_string_to_fortran(buf, fortran_str)
!   call c_string_destroy(buf)
!
!===============================================================================
module fortsh_c_strings
  use, intrinsic :: iso_c_binding
  implicit none
  private

  ! Public types
  public :: c_string_buffer

  ! Public functions
  public :: c_string_create, c_string_destroy, c_string_clear
  public :: c_string_length, c_string_capacity
  public :: c_string_set, c_string_copy, c_string_substring
  public :: c_string_get_char, c_string_set_char
  public :: c_string_insert, c_string_delete, c_string_append
  public :: c_string_trim, c_string_find, c_string_compare
  public :: c_string_to_fortran, c_string_from_fortran
  public :: c_string_c_str

  !-----------------------------------------------------------------------------
  ! Opaque handle to C buffer
  !-----------------------------------------------------------------------------
  type :: c_string_buffer
    type(c_ptr) :: handle = c_null_ptr
  end type c_string_buffer

  !-----------------------------------------------------------------------------
  ! C function interfaces
  !-----------------------------------------------------------------------------
  interface

    ! Buffer management
    function fortsh_buffer_create_c(capacity) bind(C, name='fortsh_buffer_create')
      import :: c_ptr, c_size_t
      integer(c_size_t), value :: capacity
      type(c_ptr) :: fortsh_buffer_create_c
    end function

    subroutine fortsh_buffer_destroy_c(buf) bind(C, name='fortsh_buffer_destroy')
      import :: c_ptr
      type(c_ptr), value :: buf
    end subroutine

    subroutine fortsh_buffer_clear_c(buf) bind(C, name='fortsh_buffer_clear')
      import :: c_ptr
      type(c_ptr), value :: buf
    end subroutine

    function fortsh_buffer_length_c(buf) bind(C, name='fortsh_buffer_length')
      import :: c_ptr, c_size_t
      type(c_ptr), value :: buf
      integer(c_size_t) :: fortsh_buffer_length_c
    end function

    function fortsh_buffer_capacity_c(buf) bind(C, name='fortsh_buffer_capacity')
      import :: c_ptr, c_size_t
      type(c_ptr), value :: buf
      integer(c_size_t) :: fortsh_buffer_capacity_c
    end function

    ! String operations
    function fortsh_buffer_set_c(buf, str) bind(C, name='fortsh_buffer_set')
      import :: c_ptr, c_int, c_char
      type(c_ptr), value :: buf
      character(kind=c_char), dimension(*) :: str
      integer(c_int) :: fortsh_buffer_set_c
    end function

    function fortsh_buffer_copy_c(dest, src) bind(C, name='fortsh_buffer_copy')
      import :: c_ptr, c_int
      type(c_ptr), value :: dest, src
      integer(c_int) :: fortsh_buffer_copy_c
    end function

    function fortsh_buffer_substring_c(dest, src, start, end) bind(C, name='fortsh_buffer_substring')
      import :: c_ptr, c_int, c_size_t
      type(c_ptr), value :: dest, src
      integer(c_size_t), value :: start, end
      integer(c_int) :: fortsh_buffer_substring_c
    end function

    function fortsh_buffer_get_char_c(buf, pos) bind(C, name='fortsh_buffer_get_char')
      import :: c_ptr, c_size_t, c_char
      type(c_ptr), value :: buf
      integer(c_size_t), value :: pos
      character(kind=c_char) :: fortsh_buffer_get_char_c
    end function

    function fortsh_buffer_set_char_c(buf, pos, ch) bind(C, name='fortsh_buffer_set_char')
      import :: c_ptr, c_int, c_size_t, c_char
      type(c_ptr), value :: buf
      integer(c_size_t), value :: pos
      character(kind=c_char), value :: ch
      integer(c_int) :: fortsh_buffer_set_char_c
    end function

    ! Buffer manipulation
    function fortsh_buffer_insert_c(buf, pos, str) bind(C, name='fortsh_buffer_insert')
      import :: c_ptr, c_int, c_size_t, c_char
      type(c_ptr), value :: buf
      integer(c_size_t), value :: pos
      character(kind=c_char), dimension(*) :: str
      integer(c_int) :: fortsh_buffer_insert_c
    end function

    function fortsh_buffer_delete_c(buf, start, count) bind(C, name='fortsh_buffer_delete')
      import :: c_ptr, c_int, c_size_t
      type(c_ptr), value :: buf
      integer(c_size_t), value :: start, count
      integer(c_int) :: fortsh_buffer_delete_c
    end function

    function fortsh_buffer_append_c(buf, str) bind(C, name='fortsh_buffer_append')
      import :: c_ptr, c_int, c_char
      type(c_ptr), value :: buf
      character(kind=c_char), dimension(*) :: str
      integer(c_int) :: fortsh_buffer_append_c
    end function

    subroutine fortsh_buffer_trim_c(buf) bind(C, name='fortsh_buffer_trim')
      import :: c_ptr
      type(c_ptr), value :: buf
    end subroutine

    ! Fortran interop
    function fortsh_buffer_to_fortran_c(buf, fortran_str, fortran_len) &
        bind(C, name='fortsh_buffer_to_fortran')
      import :: c_ptr, c_size_t, c_char
      type(c_ptr), value :: buf
      character(kind=c_char), dimension(*) :: fortran_str
      integer(c_size_t), value :: fortran_len
      integer(c_size_t) :: fortsh_buffer_to_fortran_c
    end function

    function fortsh_buffer_from_fortran_c(buf, fortran_str, fortran_len) &
        bind(C, name='fortsh_buffer_from_fortran')
      import :: c_ptr, c_int, c_size_t, c_char
      type(c_ptr), value :: buf
      character(kind=c_char), dimension(*) :: fortran_str
      integer(c_size_t), value :: fortran_len
      integer(c_int) :: fortsh_buffer_from_fortran_c
    end function

    function fortsh_buffer_c_str_c(buf) bind(C, name='fortsh_buffer_c_str')
      import :: c_ptr
      type(c_ptr), value :: buf
      type(c_ptr) :: fortsh_buffer_c_str_c
    end function

    ! Utility
    function fortsh_buffer_find_c(buf, pattern) bind(C, name='fortsh_buffer_find')
      import :: c_ptr, c_int, c_char
      type(c_ptr), value :: buf
      character(kind=c_char), dimension(*) :: pattern
      integer(c_int) :: fortsh_buffer_find_c
    end function

    function fortsh_buffer_compare_c(buf, str) bind(C, name='fortsh_buffer_compare')
      import :: c_ptr, c_int, c_char
      type(c_ptr), value :: buf
      character(kind=c_char), dimension(*) :: str
      integer(c_int) :: fortsh_buffer_compare_c
    end function

  end interface

contains

  !-----------------------------------------------------------------------------
  ! Fortran-friendly wrappers
  !-----------------------------------------------------------------------------

  function c_string_create(capacity) result(buf)
    integer, intent(in) :: capacity
    type(c_string_buffer) :: buf

    buf%handle = fortsh_buffer_create_c(int(capacity, c_size_t))
  end function c_string_create

  subroutine c_string_destroy(buf)
    type(c_string_buffer), intent(inout) :: buf

    if (c_associated(buf%handle)) then
      call fortsh_buffer_destroy_c(buf%handle)
      buf%handle = c_null_ptr
    end if
  end subroutine c_string_destroy

  subroutine c_string_clear(buf)
    type(c_string_buffer), intent(in) :: buf

    if (c_associated(buf%handle)) then
      call fortsh_buffer_clear_c(buf%handle)
    end if
  end subroutine c_string_clear

  function c_string_length(buf) result(len)
    type(c_string_buffer), intent(in) :: buf
    integer :: len

    if (c_associated(buf%handle)) then
      len = int(fortsh_buffer_length_c(buf%handle))
    else
      len = 0
    end if
  end function c_string_length

  function c_string_capacity(buf) result(cap)
    type(c_string_buffer), intent(in) :: buf
    integer :: cap

    if (c_associated(buf%handle)) then
      cap = int(fortsh_buffer_capacity_c(buf%handle))
    else
      cap = 0
    end if
  end function c_string_capacity

  function c_string_set(buf, str) result(status)
    type(c_string_buffer), intent(in) :: buf
    character(len=*), intent(in) :: str
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(buf%handle)) then
      status = .false.
      return
    end if

    ! Convert to null-terminated C string
    ret = fortsh_buffer_set_c(buf%handle, trim(str) // c_null_char)
    status = (ret == 0)
  end function c_string_set

  function c_string_copy(dest, src) result(status)
    type(c_string_buffer), intent(in) :: dest, src
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(dest%handle) .or. .not. c_associated(src%handle)) then
      status = .false.
      return
    end if

    ret = fortsh_buffer_copy_c(dest%handle, src%handle)
    status = (ret == 0)
  end function c_string_copy

  function c_string_substring(dest, src, start_pos, end_pos) result(status)
    type(c_string_buffer), intent(in) :: dest, src
    integer, intent(in) :: start_pos, end_pos
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(dest%handle) .or. .not. c_associated(src%handle)) then
      status = .false.
      return
    end if

    ! Convert from Fortran 1-based to C 0-based indexing
    ret = fortsh_buffer_substring_c(dest%handle, src%handle, &
                                     int(start_pos - 1, c_size_t), &
                                     int(end_pos - 1, c_size_t))
    status = (ret == 0)
  end function c_string_substring

  function c_string_get_char(buf, pos) result(ch)
    type(c_string_buffer), intent(in) :: buf
    integer, intent(in) :: pos
    character(len=1) :: ch

    if (.not. c_associated(buf%handle)) then
      ch = ' '
      return
    end if

    ! Convert from Fortran 1-based to C 0-based indexing
    ch = fortsh_buffer_get_char_c(buf%handle, int(pos - 1, c_size_t))
  end function c_string_get_char

  function c_string_set_char(buf, pos, ch) result(status)
    type(c_string_buffer), intent(in) :: buf
    integer, intent(in) :: pos
    character(len=1), intent(in) :: ch
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(buf%handle)) then
      status = .false.
      return
    end if

    ! Convert from Fortran 1-based to C 0-based indexing
    ret = fortsh_buffer_set_char_c(buf%handle, int(pos - 1, c_size_t), ch)
    status = (ret == 0)
  end function c_string_set_char

  function c_string_insert(buf, pos, str) result(status)
    type(c_string_buffer), intent(in) :: buf
    integer, intent(in) :: pos
    character(len=*), intent(in) :: str
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(buf%handle)) then
      status = .false.
      return
    end if

    ! Convert from Fortran 1-based to C 0-based indexing
    ret = fortsh_buffer_insert_c(buf%handle, int(pos - 1, c_size_t), &
                                  trim(str) // c_null_char)
    status = (ret == 0)
  end function c_string_insert

  function c_string_delete(buf, start_pos, count) result(status)
    type(c_string_buffer), intent(in) :: buf
    integer, intent(in) :: start_pos, count
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(buf%handle)) then
      status = .false.
      return
    end if

    ! Convert from Fortran 1-based to C 0-based indexing
    ret = fortsh_buffer_delete_c(buf%handle, int(start_pos - 1, c_size_t), &
                                  int(count, c_size_t))
    status = (ret == 0)
  end function c_string_delete

  function c_string_append(buf, str) result(status)
    type(c_string_buffer), intent(in) :: buf
    character(len=*), intent(in) :: str
    logical :: status
    integer(c_int) :: ret

    if (.not. c_associated(buf%handle)) then
      status = .false.
      return
    end if

    ret = fortsh_buffer_append_c(buf%handle, trim(str) // c_null_char)
    status = (ret == 0)
  end function c_string_append

  subroutine c_string_trim(buf)
    type(c_string_buffer), intent(in) :: buf

    if (c_associated(buf%handle)) then
      call fortsh_buffer_trim_c(buf%handle)
    end if
  end subroutine c_string_trim

  subroutine c_string_to_fortran(buf, fortran_str, actual_len)
    type(c_string_buffer), intent(in) :: buf
    character(len=*), intent(out) :: fortran_str
    integer, intent(out), optional :: actual_len
    integer(c_size_t) :: len_copied

    fortran_str = ''  ! Initialize

    if (.not. c_associated(buf%handle)) then
      if (present(actual_len)) actual_len = 0
      return
    end if

    len_copied = fortsh_buffer_to_fortran_c(buf%handle, fortran_str, &
                                            int(len(fortran_str), c_size_t))

    if (present(actual_len)) actual_len = int(len_copied)
  end subroutine c_string_to_fortran

  function c_string_from_fortran(buf, fortran_str) result(status)
    type(c_string_buffer), intent(in) :: buf
    character(len=*), intent(in) :: fortran_str
    logical :: status
    integer(c_int) :: ret
    integer :: actual_len, i

    if (.not. c_associated(buf%handle)) then
      status = .false.
      return
    end if

    ! Find actual length (trim trailing spaces manually to get exact length)
    actual_len = len_trim(fortran_str)

    ret = fortsh_buffer_from_fortran_c(buf%handle, fortran_str, &
                                       int(actual_len, c_size_t))
    status = (ret == 0)
  end function c_string_from_fortran

  function c_string_find(buf, pattern) result(pos)
    type(c_string_buffer), intent(in) :: buf
    character(len=*), intent(in) :: pattern
    integer :: pos

    if (.not. c_associated(buf%handle)) then
      pos = 0  ! Not found (Fortran 1-based convention)
      return
    end if

    pos = int(fortsh_buffer_find_c(buf%handle, trim(pattern) // c_null_char))

    ! Convert from C 0-based to Fortran 1-based, with -1 meaning not found
    if (pos >= 0) then
      pos = pos + 1  ! Convert to 1-based
    else
      pos = 0  ! Fortran convention for not found
    end if
  end function c_string_find

  function c_string_compare(buf, str) result(cmp)
    type(c_string_buffer), intent(in) :: buf
    character(len=*), intent(in) :: str
    integer :: cmp

    if (.not. c_associated(buf%handle)) then
      cmp = -1
      return
    end if

    cmp = int(fortsh_buffer_compare_c(buf%handle, trim(str) // c_null_char))
  end function c_string_compare

  function c_string_c_str(buf) result(ptr)
    type(c_string_buffer), intent(in) :: buf
    type(c_ptr) :: ptr

    if (c_associated(buf%handle)) then
      ptr = fortsh_buffer_c_str_c(buf%handle)
    else
      ptr = c_null_ptr
    end if
  end function c_string_c_str

end module fortsh_c_strings
