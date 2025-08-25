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
      ! Check for empty name (null character or spaces)
      if (shell%variables(i)%name(1:1) == char(0) .or. trim(shell%variables(i)%name) == '') then
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
    character(len=:), allocatable :: expanded_value
    
    eq_pos = index(input_line, '=')
    if (eq_pos > 1) then
      var_name = input_line(:eq_pos-1)
      var_value = input_line(eq_pos+1:)
      
      ! Simple variable expansion during assignment
      call simple_expand_variables(var_value, expanded_value, shell)
      call set_shell_variable(shell, trim(var_name), expanded_value)
      shell%last_exit_status = 0
    else
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine simple_expand_variables(input, expanded, shell)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(in) :: shell
    
    character(len=1024) :: result
    integer :: i, j, var_start
    character(len=256) :: var_name
    character(len=1024) :: var_value
    character(len=:), allocatable :: env_value
    
    result = ''
    i = 1
    j = 1
    
    do while (i <= len_trim(input))
      if (input(i:i) == '$' .and. i < len_trim(input)) then
        i = i + 1
        var_start = i
        
        ! Extract variable name  
        do while (i <= len_trim(input))
          if (.not. (is_alnum(input(i:i)) .or. input(i:i) == '_')) exit
          i = i + 1
        end do
        
        var_name = input(var_start:i-1)
        
        ! Check shell variables first
        var_value = get_shell_variable(shell, trim(var_name))
        if (len_trim(var_value) > 0) then
          result(j:j+len_trim(var_value)-1) = trim(var_value)
          j = j + len_trim(var_value)
        else
          ! Fall back to environment variables
          env_value = get_environment_var(trim(var_name))
          if (allocated(env_value) .and. len(env_value) > 0) then
            result(j:j+len(env_value)-1) = env_value
            j = j + len(env_value)
          end if
        end if
      else
        result(j:j) = input(i:i)
        i = i + 1
        j = j + 1
      end if
    end do
    
    expanded = trim(result)
    
  contains
    function is_alnum(ch) result(res)
      character, intent(in) :: ch
      logical :: res
      res = (ch >= 'a' .and. ch <= 'z') .or. &
            (ch >= 'A' .and. ch <= 'Z') .or. &
            (ch >= '0' .and. ch <= '9')
    end function
  end subroutine

end module variables