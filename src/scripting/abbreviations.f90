! ==============================================================================
! Module: abbreviations
! Purpose: Shell abbreviation functionality (fish-style auto-expanding shortcuts)
! ==============================================================================
module abbreviations
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Maximum number of abbreviations
  integer, parameter :: MAX_ABBREVIATIONS = 100

  ! Abbreviation entry type
  type :: abbr_entry_t
    character(len=64) :: short_form = ''
    character(len=256) :: expanded_form = ''
  end type abbr_entry_t

  ! Global abbreviation storage
  type(abbr_entry_t), save :: abbr_table(MAX_ABBREVIATIONS)
  integer, save :: num_abbreviations = 0

contains

  ! Add or update an abbreviation
  subroutine set_abbreviation(short_form, expanded_form)
    character(len=*), intent(in) :: short_form, expanded_form
    integer :: i, empty_slot

    empty_slot = -1

    ! Look for existing abbreviation or empty slot
    do i = 1, MAX_ABBREVIATIONS
      if (trim(abbr_table(i)%short_form) == trim(short_form)) then
        ! Update existing abbreviation
        abbr_table(i)%expanded_form = expanded_form
        return
      else if (len_trim(abbr_table(i)%short_form) == 0) then
        if (empty_slot == -1) empty_slot = i
      end if
    end do

    ! Add new abbreviation if there's space
    if (empty_slot > 0) then
      abbr_table(empty_slot)%short_form = short_form
      abbr_table(empty_slot)%expanded_form = expanded_form
      num_abbreviations = num_abbreviations + 1
    else
      write(error_unit, '(a)') 'abbr: too many abbreviations defined'
    end if
  end subroutine set_abbreviation

  ! Get the expanded form of an abbreviation
  function get_abbreviation(short_form) result(expanded_form)
    character(len=*), intent(in) :: short_form
    character(len=:), allocatable :: expanded_form
    integer :: i

    expanded_form = ''

    do i = 1, MAX_ABBREVIATIONS
      if (trim(abbr_table(i)%short_form) == trim(short_form)) then
        expanded_form = trim(abbr_table(i)%expanded_form)
        return
      end if
    end do
  end function get_abbreviation

  ! Check if a word is an abbreviation
  function is_abbreviation(word) result(found)
    character(len=*), intent(in) :: word
    logical :: found
    integer :: i

    found = .false.
    do i = 1, MAX_ABBREVIATIONS
      if (trim(abbr_table(i)%short_form) == trim(word)) then
        found = .true.
        return
      end if
    end do
  end function is_abbreviation

  ! Remove an abbreviation
  subroutine unset_abbreviation(short_form)
    character(len=*), intent(in) :: short_form
    integer :: i

    do i = 1, MAX_ABBREVIATIONS
      if (trim(abbr_table(i)%short_form) == trim(short_form)) then
        abbr_table(i)%short_form = ''
        abbr_table(i)%expanded_form = ''
        num_abbreviations = num_abbreviations - 1
        return
      end if
    end do

    write(error_unit, '(a)') 'abbr: ' // trim(short_form) // ': not found'
  end subroutine unset_abbreviation

  ! Show all abbreviations
  subroutine show_abbreviations()
    integer :: i, count

    count = 0
    do i = 1, MAX_ABBREVIATIONS
      if (len_trim(abbr_table(i)%short_form) > 0) then
        write(output_unit, '(a)') 'abbr ' // trim(abbr_table(i)%short_form) // &
                                 '=' // "'" // trim(abbr_table(i)%expanded_form) // "'"
        count = count + 1
      end if
    end do

    if (count == 0) then
      write(output_unit, '(a)') 'No abbreviations defined'
    end if
  end subroutine show_abbreviations

  ! Erase all abbreviations
  subroutine erase_all_abbreviations()
    integer :: i

    do i = 1, MAX_ABBREVIATIONS
      abbr_table(i)%short_form = ''
      abbr_table(i)%expanded_form = ''
    end do
    num_abbreviations = 0
  end subroutine erase_all_abbreviations

  ! Expand abbreviation in current word (returns expanded form or empty if not an abbr)
  ! This is called from readline when space/enter is pressed
  function try_expand_abbreviation(word) result(expanded)
    character(len=*), intent(in) :: word
    character(len=:), allocatable :: expanded

    if (is_abbreviation(word)) then
      expanded = get_abbreviation(word)
    else
      expanded = ''
    end if
  end function try_expand_abbreviation

end module abbreviations
