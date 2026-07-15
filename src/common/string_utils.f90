! Shared ASCII case-conversion helpers.
!
! Consolidates the string- and char-level to_upper/to_lower copies that had
! drifted across six modules (expansion, signals, printf_builtin,
! prompt_formatting, suggestions, readline). All operate on ASCII only: a
! letter is shifted by 32, everything else passes through unchanged.
!
! String and char helpers carry distinct names on purpose — a Fortran generic
! interface cannot disambiguate a len=* scalar from a len=1 scalar (same type,
! kind and rank), so consumers rename on import (e.g. to_lowercase => char_lower)
! to keep their existing call sites unchanged.
module string_utils
  implicit none
  private

  public :: to_upper, to_lower       ! whole-string
  public :: char_upper, char_lower   ! single character

contains

  pure function to_upper(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: i, code

    output = input
    do i = 1, len_trim(input)
      code = iachar(input(i:i))
      if (code >= iachar('a') .and. code <= iachar('z')) then
        output(i:i) = achar(code - 32)
      end if
    end do
  end function to_upper

  pure function to_lower(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: i, code

    output = input
    do i = 1, len_trim(input)
      code = iachar(input(i:i))
      if (code >= iachar('A') .and. code <= iachar('Z')) then
        output(i:i) = achar(code + 32)
      end if
    end do
  end function to_lower

  pure function char_upper(c) result(uc)
    character(len=1), intent(in) :: c
    character(len=1) :: uc
    integer :: code

    code = iachar(c)
    if (code >= iachar('a') .and. code <= iachar('z')) then
      uc = achar(code - 32)
    else
      uc = c
    end if
  end function char_upper

  pure function char_lower(c) result(lc)
    character(len=1), intent(in) :: c
    character(len=1) :: lc
    integer :: code

    code = iachar(c)
    if (code >= iachar('A') .and. code <= iachar('Z')) then
      lc = achar(code + 32)
    else
      lc = c
    end if
  end function char_lower

end module string_utils
