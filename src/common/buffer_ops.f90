!===============================================================================
! buffer_ops.f90 - Unified buffer operations abstraction
!
! Purpose: Provide consistent API for buffer operations that works on both
!          native Fortran strings (Linux) and C strings (macOS ARM64)
!
! This module shields the readline code from platform differences.
!===============================================================================
module buffer_ops
#ifdef USE_C_STRINGS
  use fortsh_c_strings
#endif
  use, intrinsic :: iso_c_binding
  implicit none
  private

  public :: buf_set_string, buf_get_string, buf_clear, buf_length
  public :: buf_copy, buf_get_char, buf_set_char
  public :: buf_substring, buf_append

contains

  !-----------------------------------------------------------------------------
  ! Set buffer from Fortran string
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_set_string(c_buf, str)
    type(c_string_buffer), intent(inout) :: c_buf
    character(len=*), intent(in) :: str
    logical :: success

    success = c_string_set(c_buf, str)
    ! Silently ignore overflow for now (matches old behavior)
  end subroutine buf_set_string
#else
  subroutine buf_set_string(fortran_buf, str)
    character(len=:), allocatable, intent(inout) :: fortran_buf
    character(len=*), intent(in) :: str

    fortran_buf = str
  end subroutine buf_set_string
#endif

  !-----------------------------------------------------------------------------
  ! Get buffer as Fortran string
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_get_string(c_buf, str, actual_len)
    type(c_string_buffer), intent(in) :: c_buf
    character(len=*), intent(out) :: str
    integer, intent(out), optional :: actual_len
    integer :: len_out

    call c_string_to_fortran(c_buf, str, len_out)
    if (present(actual_len)) actual_len = len_out
  end subroutine buf_get_string
#else
  subroutine buf_get_string(fortran_buf, str, actual_len)
    character(len=:), allocatable, intent(in) :: fortran_buf
    character(len=*), intent(out) :: str
    integer, intent(out), optional :: actual_len

    str = fortran_buf
    if (present(actual_len)) actual_len = len_trim(fortran_buf)
  end subroutine buf_get_string
#endif

  !-----------------------------------------------------------------------------
  ! Clear buffer
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_clear(c_buf)
    type(c_string_buffer), intent(in) :: c_buf

    call c_string_clear(c_buf)
  end subroutine buf_clear
#else
  subroutine buf_clear(fortran_buf)
    character(len=:), allocatable, intent(inout) :: fortran_buf

    fortran_buf = ''
  end subroutine buf_clear
#endif

  !-----------------------------------------------------------------------------
  ! Get buffer length
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  function buf_length(c_buf) result(len)
    type(c_string_buffer), intent(in) :: c_buf
    integer :: len

    len = c_string_length(c_buf)
  end function buf_length
#else
  function buf_length(fortran_buf) result(len)
    character(len=:), allocatable, intent(in) :: fortran_buf
    integer :: len

    len = len_trim(fortran_buf)
  end function buf_length
#endif

  !-----------------------------------------------------------------------------
  ! Copy buffer
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_copy(dest_c, src_c)
    type(c_string_buffer), intent(in) :: dest_c, src_c
    logical :: success

    success = c_string_copy(dest_c, src_c)
  end subroutine buf_copy
#else
  subroutine buf_copy(dest, src)
    character(len=:), allocatable, intent(inout) :: dest
    character(len=:), allocatable, intent(in) :: src

    dest = src
  end subroutine buf_copy
#endif

  !-----------------------------------------------------------------------------
  ! Get character at position (1-based)
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  function buf_get_char(c_buf, pos) result(ch)
    type(c_string_buffer), intent(in) :: c_buf
    integer, intent(in) :: pos
    character(len=1) :: ch

    ch = c_string_get_char(c_buf, pos)
  end function buf_get_char
#else
  function buf_get_char(fortran_buf, pos) result(ch)
    character(len=:), allocatable, intent(in) :: fortran_buf
    integer, intent(in) :: pos
    character(len=1) :: ch

    if (pos >= 1 .and. pos <= len(fortran_buf)) then
      ch = fortran_buf(pos:pos)
    else
      ch = ' '
    end if
  end function buf_get_char
#endif

  !-----------------------------------------------------------------------------
  ! Set character at position (1-based)
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_set_char(c_buf, pos, ch)
    type(c_string_buffer), intent(in) :: c_buf
    integer, intent(in) :: pos
    character(len=1), intent(in) :: ch
    logical :: success

    success = c_string_set_char(c_buf, pos, ch)
  end subroutine buf_set_char
#else
  subroutine buf_set_char(fortran_buf, pos, ch)
    character(len=:), allocatable, intent(inout) :: fortran_buf
    integer, intent(in) :: pos
    character(len=1), intent(in) :: ch

    if (pos >= 1 .and. pos <= len(fortran_buf)) then
      fortran_buf(pos:pos) = ch
    end if
  end subroutine buf_set_char
#endif

  !-----------------------------------------------------------------------------
  ! Extract substring
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_substring(dest_c, src_c, start_pos, end_pos)
    type(c_string_buffer), intent(in) :: dest_c, src_c
    integer, intent(in) :: start_pos, end_pos
    logical :: success

    success = c_string_substring(dest_c, src_c, start_pos, end_pos)
  end subroutine buf_substring
#else
  subroutine buf_substring(dest, src, start_pos, end_pos)
    character(len=:), allocatable, intent(inout) :: dest
    character(len=:), allocatable, intent(in) :: src
    integer, intent(in) :: start_pos, end_pos

    if (start_pos >= 1 .and. end_pos <= len(src) .and. start_pos <= end_pos) then
      dest = src(start_pos:end_pos)
    else
      dest = ''
    end if
  end subroutine buf_substring
#endif

  !-----------------------------------------------------------------------------
  ! Append to buffer
  !-----------------------------------------------------------------------------
#ifdef USE_C_STRINGS
  subroutine buf_append(c_buf, str)
    type(c_string_buffer), intent(in) :: c_buf
    character(len=*), intent(in) :: str
    logical :: success

    success = c_string_append(c_buf, str)
  end subroutine buf_append
#else
  subroutine buf_append(fortran_buf, str)
    character(len=:), allocatable, intent(inout) :: fortran_buf
    character(len=*), intent(in) :: str

    fortran_buf = fortran_buf // str
  end subroutine buf_append
#endif

end module buffer_ops
