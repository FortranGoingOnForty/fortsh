! ==============================================================================
! Module: aliases
! Purpose: Shell alias functionality
! ==============================================================================
module aliases
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  subroutine set_alias(shell, alias_name, command)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: alias_name, command
    integer :: i, empty_slot
    
    empty_slot = -1
    
    ! Look for existing alias or empty slot
    do i = 1, size(shell%aliases)
      if (trim(shell%aliases(i)%name) == trim(alias_name)) then
        ! Update existing alias
        shell%aliases(i)%command = command
        return
      else if (shell%aliases(i)%name(1:1) == char(0) .or. trim(shell%aliases(i)%name) == '') then
        if (empty_slot == -1) empty_slot = i
      end if
    end do
    
    ! Add new alias if there's space
    if (empty_slot > 0) then
      shell%aliases(empty_slot)%name = alias_name
      shell%aliases(empty_slot)%command = command
      shell%num_aliases = shell%num_aliases + 1
    else
      write(error_unit, '(a)') 'alias: too many aliases defined'
    end if
  end subroutine

  function get_alias(shell, alias_name) result(command)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: alias_name
    character(len=:), allocatable :: command
    integer :: i
    
    command = ''
    
    do i = 1, size(shell%aliases)
      if (trim(shell%aliases(i)%name) == trim(alias_name)) then
        command = trim(shell%aliases(i)%command)
        return
      end if
    end do
  end function

  subroutine unset_alias(shell, alias_name)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: alias_name
    integer :: i
    
    do i = 1, size(shell%aliases)
      if (trim(shell%aliases(i)%name) == trim(alias_name)) then
        shell%aliases(i)%name = ''
        shell%aliases(i)%command = ''
        shell%num_aliases = shell%num_aliases - 1
        return
      end if
    end do
    
    write(error_unit, '(a)') 'unalias: ' // trim(alias_name) // ': not found'
  end subroutine

  subroutine show_aliases(shell)
    type(shell_state_t), intent(in) :: shell
    integer :: i, count
    
    count = 0
    do i = 1, size(shell%aliases)
      if (shell%aliases(i)%name(1:1) /= char(0) .and. trim(shell%aliases(i)%name) /= '') then
        write(output_unit, '(a)') 'alias ' // trim(shell%aliases(i)%name) // &
                                 '=' // "'" // trim(shell%aliases(i)%command) // "'"
        count = count + 1
      end if
    end do
    
    if (count == 0) then
      write(output_unit, '(a)') 'No aliases defined'
    end if
  end subroutine

  function is_alias(shell, name) result(found)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    logical :: found
    integer :: i
    
    found = .false.
    do i = 1, size(shell%aliases)
      if (trim(shell%aliases(i)%name) == trim(name)) then
        found = .true.
        return
      end if
    end do
  end function

  ! Expand alias in a command line
  subroutine expand_alias(shell, input_line, expanded_line)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: input_line
    character(len=:), allocatable, intent(out) :: expanded_line
    
    character(len=256) :: first_word, rest_of_line
    character(len=:), allocatable :: alias_command
    integer :: space_pos
    
    expanded_line = input_line
    
    ! Extract first word
    space_pos = index(trim(input_line), ' ')
    if (space_pos > 0) then
      first_word = input_line(:space_pos-1)
      rest_of_line = input_line(space_pos:)
    else
      first_word = trim(input_line)
      rest_of_line = ''
    end if
    
    ! Check if first word is an alias
    if (is_alias(shell, first_word)) then
      alias_command = get_alias(shell, first_word)
      if (len(alias_command) > 0) then
        expanded_line = trim(alias_command) // trim(rest_of_line)
      end if
    end if
  end subroutine

end module aliases