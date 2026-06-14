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

  ! AR-07 ABBR-PERSIST. Abbreviations are saved to ~/.fortsh_abbreviations as
  ! one `short<TAB>expansion` line each — a flat format loaded directly (not
  ! sourced through the executor), so there is no quote-escaping to get wrong
  ! and no save-while-loading race. A short form never contains a tab.
  function abbr_file_path() result(path)
    character(len=:), allocatable :: path
    character(len=512) :: home
    integer :: hlen
    path = ''
    call get_environment_variable('HOME', home, length=hlen)
    if (hlen <= 0) return
    path = trim(home) // '/.fortsh_abbreviations'
  end function abbr_file_path

  ! Write the whole abbreviation table to the state file (call after a change).
  subroutine persist_abbreviations()
    character(len=:), allocatable :: path
    integer :: u, i, ios

    path = abbr_file_path()
    if (len(path) == 0) return
    open(newunit=u, file=path, status='replace', action='write', iostat=ios)
    if (ios /= 0) return
    do i = 1, MAX_ABBREVIATIONS
      if (len_trim(abbr_table(i)%short_form) > 0) then
        write(u, '(a)') trim(abbr_table(i)%short_form) // char(9) // &
                        trim(abbr_table(i)%expanded_form)
      end if
    end do
    close(u)
  end subroutine persist_abbreviations

  ! Load abbreviations from the state file at startup. Reads directly into the
  ! table via set_abbreviation (no executor, so no re-save is triggered).
  subroutine restore_abbreviations()
    character(len=:), allocatable :: path
    character(len=1024) :: line
    integer :: u, ios, tab
    logical :: ex

    path = abbr_file_path()
    if (len(path) == 0) return
    inquire(file=path, exist=ex)
    if (.not. ex) return
    open(newunit=u, file=path, status='old', action='read', iostat=ios)
    if (ios /= 0) return
    do
      read(u, '(a)', iostat=ios) line
      if (ios /= 0) exit
      tab = index(line, char(9))
      if (tab > 1) then
        call set_abbreviation(line(1:tab-1), trim(line(tab+1:)))
      end if
    end do
    close(u)
  end subroutine restore_abbreviations

end module abbreviations
