! ==============================================================================
! Module: test_builtin
! Purpose: Test builtin for shell conditionals ([, [[, test commands)
! ==============================================================================
module test_builtin
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  function is_test_command(cmd_name) result(is_test)
    character(len=*), intent(in) :: cmd_name
    logical :: is_test
    
    is_test = (trim(cmd_name) == 'test' .or. &
               trim(cmd_name) == '[' .or. &
               trim(cmd_name) == '[[')
  end function

  subroutine execute_test_command(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    logical :: test_result
    character(len=256) :: operator
    character(len=256) :: left_operand, right_operand
    
    ! Simple test implementation - would need to parse arguments properly
    ! For now, implement basic tests
    
    if (cmd%num_tokens < 2) then
      shell%last_exit_status = 1  ! False
      return
    end if
    
    ! Handle different test patterns
    if (cmd%num_tokens == 2) then
      ! test STRING - true if STRING is not empty
      test_result = (len_trim(cmd%tokens(2)) > 0)
      
    else if (cmd%num_tokens == 4) then
      ! test ARG1 OP ARG2 - binary operators
      left_operand = cmd%tokens(2)
      operator = cmd%tokens(3)
      right_operand = cmd%tokens(4)
      
      select case(trim(operator))
      case('=', '==')
        test_result = (trim(left_operand) == trim(right_operand))
      case('!=')
        test_result = (trim(left_operand) /= trim(right_operand))
      case('-eq')
        test_result = string_to_int(left_operand) == string_to_int(right_operand)
      case('-ne')
        test_result = string_to_int(left_operand) /= string_to_int(right_operand)
      case('-lt')
        test_result = string_to_int(left_operand) < string_to_int(right_operand)
      case('-le')
        test_result = string_to_int(left_operand) <= string_to_int(right_operand)
      case('-gt')
        test_result = string_to_int(left_operand) > string_to_int(right_operand)
      case('-ge')
        test_result = string_to_int(left_operand) >= string_to_int(right_operand)
      case default
        test_result = .false.
      end select
      
    else
      ! More complex expressions - simplified for now
      test_result = .false.
    end if
    
    ! Set exit status based on test result
    if (test_result) then
      shell%last_exit_status = 0  ! True
    else
      shell%last_exit_status = 1  ! False
    end if
  end subroutine

  function string_to_int(str) result(int_val)
    character(len=*), intent(in) :: str
    integer :: int_val
    integer :: iostat
    
    read(str, *, iostat=iostat) int_val
    if (iostat /= 0) int_val = 0
  end function

end module test_builtin