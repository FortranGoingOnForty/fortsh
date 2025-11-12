! ==============================================================================
! Module: aliases
! Purpose: Shell alias functionality
! ==============================================================================
module aliases
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  use io_helpers, only: write_stderr
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
      call write_stderr('alias: too many aliases defined')
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

    call write_stderr('unalias: ' // trim(alias_name) // ': not found')
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

  function expand_alias_with_params(shell, alias_name, args, num_args) result(expanded_command)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: alias_name
    character(len=*), intent(in) :: args(:)
    integer, intent(in) :: num_args
    character(len=2048) :: expanded_command
    
    character(len=1024) :: alias_command
    character(len=2048) :: work_command
    integer :: pos, param_start, param_end, param_num
    character(len=16) :: param_str
    character(len=256) :: replacement
    
    ! Get the alias command
    alias_command = ''
    call get_alias_command(shell, alias_name, alias_command)
    if (len_trim(alias_command) == 0) then
      expanded_command = ''
      return
    end if
    
    work_command = alias_command
    expanded_command = ''
    pos = 1
    
    ! Process parameter substitutions
    do while (pos <= len_trim(work_command))
      if (work_command(pos:pos) == '$' .and. pos < len_trim(work_command)) then
        param_start = pos + 1
        
        ! Check for different parameter formats
        if (work_command(param_start:param_start) == '{') then
          ! ${n} format
          param_start = param_start + 1
          param_end = param_start
          do while (param_end <= len_trim(work_command) .and. work_command(param_end:param_end) /= '}')
            param_end = param_end + 1
          end do
          
          if (param_end <= len_trim(work_command) .and. work_command(param_end:param_end) == '}') then
            param_str = work_command(param_start:param_end-1)
            pos = param_end + 1
          else
            expanded_command = trim(expanded_command) // '$'
            pos = pos + 1
            cycle
          end if
        else if (work_command(param_start:param_start) >= '0' .and. work_command(param_start:param_start) <= '9') then
          ! $n format
          param_end = param_start
          do while (param_end <= len_trim(work_command) .and. &
                    work_command(param_end:param_end) >= '0' .and. work_command(param_end:param_end) <= '9')
            param_end = param_end + 1
          end do
          param_str = work_command(param_start:param_end-1)
          pos = param_end
        else if (work_command(param_start:param_start) == '*') then
          ! $* - all parameters
          replacement = ''
          do param_num = 1, num_args
            if (param_num > 1) replacement = trim(replacement) // ' '
            replacement = trim(replacement) // trim(args(param_num))
          end do
          expanded_command = trim(expanded_command) // trim(replacement)
          pos = param_start + 1
          cycle
        else if (work_command(param_start:param_start) == '@') then
          ! $@ - all parameters (same as $* for aliases)
          replacement = ''
          do param_num = 1, num_args
            if (param_num > 1) replacement = trim(replacement) // ' '
            replacement = trim(replacement) // trim(args(param_num))
          end do
          expanded_command = trim(expanded_command) // trim(replacement)
          pos = param_start + 1
          cycle
        else if (work_command(param_start:param_start) == '#') then
          ! $# - number of parameters
          write(replacement, '(I0)') num_args
          expanded_command = trim(expanded_command) // trim(replacement)
          pos = param_start + 1
          cycle
        else
          expanded_command = trim(expanded_command) // '$'
          pos = pos + 1
          cycle
        end if
        
        ! Convert parameter string to number
        read(param_str, *, iostat=param_end) param_num
        if (param_end == 0 .and. param_num >= 0 .and. param_num <= num_args) then
          if (param_num == 0) then
            ! $0 is the alias name itself
            replacement = alias_name
          else if (param_num <= num_args) then
            replacement = args(param_num)
          else
            replacement = ''
          end if
          expanded_command = trim(expanded_command) // trim(replacement)
        else
          expanded_command = trim(expanded_command) // '$' // trim(param_str)
        end if
      else
        expanded_command = trim(expanded_command) // work_command(pos:pos)
        pos = pos + 1
      end if
    end do
    
    ! If no parameters were used, append all arguments at the end
    if (index(alias_command, '$') == 0 .and. num_args > 0) then
      do param_num = 1, num_args
        expanded_command = trim(expanded_command) // ' ' // trim(args(param_num))
      end do
    end if
  end function

  subroutine get_alias_command(shell, alias_name, command)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: alias_name
    character(len=*), intent(out) :: command
    
    integer :: i
    
    command = ''
    do i = 1, size(shell%aliases)
      if (trim(shell%aliases(i)%name) == trim(alias_name)) then
        command = shell%aliases(i)%command
        return
      end if
    end do
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