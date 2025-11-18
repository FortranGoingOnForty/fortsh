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

  private
  public :: write_stdout, write_stderr, write_stdout_nonl
  public :: write_stdout_checked, write_stdout_nonl_checked

contains

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

    ! c_write returns -1 on error
    success = (bytes_written >= 0)

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

    ! c_write returns -1 on error
    success = (bytes_written >= 0)

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
