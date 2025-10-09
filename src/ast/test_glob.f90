program test_glob
  use iso_c_binding
  implicit none

  type, bind(C) :: glob_t
    integer(c_size_t) :: gl_pathc
    type(c_ptr) :: gl_pathv
    integer(c_size_t) :: gl_offs
  end type glob_t

  interface
    function c_glob(pattern, flags, errfunc, pglob) bind(C, name="glob")
      use iso_c_binding
      import :: glob_t
      character(kind=c_char), dimension(*), intent(in) :: pattern
      integer(c_int), value :: flags
      type(c_funptr), value :: errfunc
      type(glob_t), intent(inout) :: pglob
      integer(c_int) :: c_glob
    end function c_glob

    subroutine c_globfree(pglob) bind(C, name="globfree")
      use iso_c_binding
      import :: glob_t
      type(glob_t), intent(inout) :: pglob
    end subroutine c_globfree
  end interface

  integer(c_int), parameter :: GLOB_NOCHECK = 16  ! Correct value for Linux
  type(glob_t) :: pglob
  integer(c_int) :: status
  type(c_ptr), dimension(:), pointer :: pathv_array
  type(c_ptr) :: path_ptr
  character(kind=c_char), pointer :: path_chars(:)
  character(256) :: match_str
  integer :: i, j

  ! Test glob with *.f90 pattern
  status = c_glob("*.f90" // c_null_char, 0, c_null_funptr, pglob)

  print *, "Glob status:", status
  print *, "Match count:", pglob%gl_pathc

  if (status == 0 .and. pglob%gl_pathc > 0) then
    call c_f_pointer(pglob%gl_pathv, pathv_array, [int(pglob%gl_pathc)])

    do i = 1, int(pglob%gl_pathc)
      path_ptr = pathv_array(i)
      if (c_associated(path_ptr)) then
        call c_f_pointer(path_ptr, path_chars, [256])
        match_str = ''
        do j = 1, 256
          if (path_chars(j) == c_null_char) exit
          match_str(j:j) = path_chars(j)
        end do
        print *, "Match", i, ":", trim(match_str)
      end if
    end do

    call c_globfree(pglob)
  end if

end program test_glob