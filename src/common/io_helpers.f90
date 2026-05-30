! ==============================================================================
! Module: io_helpers
! Purpose: C file descriptor-aware I/O helpers
!
! This module provides I/O functions that respect C file descriptor
! redirections (via dup2), unlike Fortran's standard I/O which uses
! separate internal buffering and doesn't see FD changes.
! ==============================================================================
module io_helpers
  use iso_c_binding
  use system_interface, only: STDOUT_FD, STDERR_FD, c_write
  implicit none

  ! Note: c_write returns c_intptr_t (signed) to detect -1 error

  interface
    function c_get_errno() bind(C, name="fortsh_get_errno")
      import :: c_int
      integer(c_int) :: c_get_errno
    end function c_get_errno

    function c_strerror(errnum) bind(C, name="fortsh_strerror")
      import :: c_int, c_ptr
      integer(c_int), value :: errnum
      type(c_ptr) :: c_strerror
    end function c_strerror
  end interface

  ! errno from the most recent failed write, captured immediately so callers
  ! can report an accurate strerror() message (e.g. ENOSPC for /dev/full).
  integer, save :: last_write_errno = 0

  private
  public :: write_stdout, write_stderr, write_stdout_nonl
  public :: write_stdout_checked, write_stdout_nonl_checked
  public :: write_error_message

contains

  ! Translate the errno from the most recent failed *_checked write into a
  ! human-readable message, matching what bash prints (e.g. for `> /dev/full`).
  function write_error_message() result(msg)
    character(len=256) :: msg
    type(c_ptr) :: cptr
    character(kind=c_char), pointer :: cstr(:)
    integer :: slen, ci
    cptr = c_strerror(int(last_write_errno, c_int))
    if (.not. c_associated(cptr)) then
      msg = 'Unknown error'
      return
    end if
    call c_f_pointer(cptr, cstr, [256])
    slen = 0
    do ci = 1, 256
      if (cstr(ci) == c_null_char) exit
      slen = slen + 1
    end do
    msg = ''
    do ci = 1, slen
      msg(ci:ci) = cstr(ci)
    end do
  end function write_error_message

  ! Write string to stdout with newline (respects C FD redirections)
  subroutine write_stdout(str)
    character(len=*), intent(in) :: str
    logical :: success
    call write_stdout_checked(str, success)
  end subroutine write_stdout

  ! Write string to stdout with newline, returning success status
  subroutine write_stdout_checked(str, success)
    character(len=*), intent(in) :: str
    logical, intent(out) :: success

    character(kind=c_char), target, allocatable :: c_str(:)
    integer(c_intptr_t) :: bytes_written
    integer :: i, str_len

    str_len = len_trim(str)
    allocate(c_str(str_len + 1))

    ! Convert to C string
    do i = 1, str_len
      c_str(i) = str(i:i)
    end do
    c_str(str_len + 1) = char(10)  ! newline

    ! Write to stdout via C FD (this respects dup2 redirections)
    bytes_written = c_write(STDOUT_FD, c_loc(c_str), int(str_len + 1, c_size_t))

    ! c_write returns -1 on error; capture errno before anything else clobbers it
    success = (bytes_written >= 0)
    if (.not. success) last_write_errno = int(c_get_errno())

    deallocate(c_str)
  end subroutine write_stdout_checked

  ! Write string to stdout without newline (respects C FD redirections)
  subroutine write_stdout_nonl(str)
    character(len=*), intent(in) :: str
    logical :: success
    call write_stdout_nonl_checked(str, success)
  end subroutine write_stdout_nonl

  ! Write string to stdout without newline, returning success status
  subroutine write_stdout_nonl_checked(str, success)
    character(len=*), intent(in) :: str
    logical, intent(out) :: success

    character(kind=c_char), target, allocatable :: c_str(:)
    integer(c_intptr_t) :: bytes_written
    integer :: i, str_len

    success = .true.

    ! Use actual length, not trimmed length, to preserve trailing/leading spaces
    str_len = len(str)
    if (str_len == 0) return

    allocate(c_str(str_len))

    ! Convert to C string
    do i = 1, str_len
      c_str(i) = str(i:i)
    end do

    ! Write to stdout via C FD
    bytes_written = c_write(STDOUT_FD, c_loc(c_str), int(str_len, c_size_t))

    ! c_write returns -1 on error; capture errno before anything else clobbers it
    success = (bytes_written >= 0)
    if (.not. success) last_write_errno = int(c_get_errno())

    deallocate(c_str)
  end subroutine write_stdout_nonl_checked

  ! Write string to stderr with newline (respects C FD redirections)
  subroutine write_stderr(str)
    character(len=*), intent(in) :: str

    character(kind=c_char), target, allocatable :: c_str(:)
    integer(c_intptr_t) :: bytes_written
    integer :: i, str_len

    str_len = len_trim(str)
    allocate(c_str(str_len + 1))

    ! Convert to C string
    do i = 1, str_len
      c_str(i) = str(i:i)
    end do
    c_str(str_len + 1) = char(10)  ! newline

    ! Write to stderr via C FD (this respects dup2 redirections)
    bytes_written = c_write(STDERR_FD, c_loc(c_str), int(str_len + 1, c_size_t))

    deallocate(c_str)
  end subroutine write_stderr

end module io_helpers
