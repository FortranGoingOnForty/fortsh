! ==============================================================================
! Module: variables
! Purpose: Shell variable management and assignment  
! ==============================================================================
module variables
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  subroutine set_shell_variable(shell, name, value)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: name, value
    integer :: i, empty_slot
    
    empty_slot = -1
    
    ! Check if variable already exists
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        shell%variables(i)%value = value
        return
      end if
    end do
    
    ! Find empty slot
    do i = 1, size(shell%variables)
      if (len_trim(shell%variables(i)%name) == 0) then
        empty_slot = i
        exit
      end if
    end do
    
    ! Add new variable
    if (empty_slot > 0) then
      shell%variables(empty_slot)%name = name
      shell%variables(empty_slot)%value = value
      shell%num_variables = shell%num_variables + 1
    end if
  end subroutine

  function get_shell_variable(shell, name) result(value)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    character(len=1024) :: value
    integer :: i
    
    value = ''
    
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        value = shell%variables(i)%value
        return
      end if
    end do
  end function

  function is_assignment(input_line) result(is_assign)
    character(len=*), intent(in) :: input_line
    logical :: is_assign
    integer :: eq_pos
    
    eq_pos = index(input_line, '=')
    is_assign = (eq_pos > 1 .and. eq_pos < len_trim(input_line))
  end function

  subroutine handle_assignment(shell, input_line)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input_line
    integer :: eq_pos
    character(len=256) :: var_name, var_value
    
    eq_pos = index(input_line, '=')
    if (eq_pos > 1) then
      var_name = input_line(:eq_pos-1)
      var_value = input_line(eq_pos+1:)
      call set_shell_variable(shell, trim(var_name), trim(var_value))
      shell%last_exit_status = 0
    else
      shell%last_exit_status = 1
    end if
  end subroutine

end module variables