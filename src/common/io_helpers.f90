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

  private
  public :: write_stdout, write_stderr, write_stdout_nonl

contains

  ! Write string to stdout with newline (respects C FD redirections)
  subroutine write_stdout(str)
    character(len=*), intent(in) :: str

    character(kind=c_char), target, allocatable :: c_str(:)
    integer(c_size_t) :: bytes_written
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

    deallocate(c_str)
  end subroutine write_stdout

  ! Write string to stdout without newline (respects C FD redirections)
  subroutine write_stdout_nonl(str)
    character(len=*), intent(in) :: str

    character(kind=c_char), target, allocatable :: c_str(:)
    integer(c_size_t) :: bytes_written
    integer :: i, str_len

    str_len = len_trim(str)
    if (str_len == 0) return

    allocate(c_str(str_len))

    ! Convert to C string
    do i = 1, str_len
      c_str(i) = str(i:i)
    end do

    ! Write to stdout via C FD
    bytes_written = c_write(STDOUT_FD, c_loc(c_str), int(str_len, c_size_t))

    deallocate(c_str)
  end subroutine write_stdout_nonl

  ! Write string to stderr with newline (respects C FD redirections)
  subroutine write_stderr(str)
    character(len=*), intent(in) :: str

    character(kind=c_char), target, allocatable :: c_str(:)
    integer(c_size_t) :: bytes_written
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
