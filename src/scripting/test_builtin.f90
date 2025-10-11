! ==============================================================================
! Module: test_builtin
! Purpose: Test builtin for shell conditionals ([, [[, test commands)
! ==============================================================================
module test_builtin
  use shell_types
  use system_interface
  use variables, only: is_shell_variable_set
  use advanced_test, only: evaluate_test_expression
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

  recursive subroutine execute_test_command(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    logical :: test_result
    character(len=256) :: operator
    character(len=256) :: left_operand, right_operand
    logical :: left_result, right_result
    character(len=256) :: log_op, op2, arg2
    type(command_t) :: sub_cmd
    integer :: i, test_exit_status

    ! Check if this is [[ ]] (advanced test) - use advanced_test module
    if (trim(cmd%tokens(1)) == '[[') then
      test_exit_status = evaluate_test_expression(shell, cmd%tokens, cmd%num_tokens)
      shell%last_exit_status = test_exit_status
      return
    end if

    ! Simple test implementation for [ and test commands

    if (cmd%num_tokens < 2) then
      shell%last_exit_status = 1  ! False
      return
    end if

    ! Handle different test patterns
    if (cmd%num_tokens == 2) then
      ! test STRING - true if STRING is not empty
      test_result = (len_trim(cmd%tokens(2)) > 0)

    else if (cmd%num_tokens == 3 .or. (cmd%num_tokens == 4 .and. trim(cmd%tokens(1)) == '[')) then
      ! Unary operators: test OP ARG or [ OP ARG ]
      operator = cmd%tokens(2)
      right_operand = cmd%tokens(3)

      select case(trim(operator))
      ! String tests
      case('-z')
        test_result = (len_trim(right_operand) == 0)
      case('-n')
        test_result = (len_trim(right_operand) > 0)

      ! File existence and type tests
      case('-e')
        test_result = file_exists(trim(right_operand))
      case('-f')
        test_result = file_is_regular(trim(right_operand))
      case('-d')
        test_result = file_is_directory(trim(right_operand))
      case('-L')
        test_result = file_is_symlink(trim(right_operand))
      case('-b')
        test_result = file_is_block_device(trim(right_operand))
      case('-c')
        test_result = file_is_char_device(trim(right_operand))
      case('-p')
        test_result = file_is_fifo(trim(right_operand))
      case('-S')
        test_result = file_is_socket(trim(right_operand))

      ! Permission tests
      case('-r')
        test_result = file_is_readable(trim(right_operand))
      case('-w')
        test_result = file_is_writable(trim(right_operand))
      case('-x')
        test_result = file_is_executable(trim(right_operand))

      ! File property tests
      case('-s')
        test_result = file_has_size(trim(right_operand))
      case('-u')
        test_result = file_has_suid(trim(right_operand))
      case('-g')
        test_result = file_has_sgid(trim(right_operand))
      case('-k')
        test_result = file_has_sticky(trim(right_operand))
      case('-O')
        test_result = file_owned_by_euid(trim(right_operand))
      case('-G')
        test_result = file_owned_by_egid(trim(right_operand))

      ! Variable test
      case('-v')
        test_result = is_shell_variable_set(shell, trim(right_operand))

      case default
        test_result = .false.
      end select

    else if (cmd%num_tokens == 4 .or. (cmd%num_tokens == 5 .and. trim(cmd%tokens(1)) == '[')) then
      ! test ARG1 OP ARG2 - binary operators
      ! For '[' command, skip the closing ']' token
      left_operand = cmd%tokens(2)
      operator = cmd%tokens(3)
      right_operand = cmd%tokens(4)

      select case(trim(operator))
      ! String comparisons
      case('=', '==')
        test_result = (trim(left_operand) == trim(right_operand))
      case('!=')
        test_result = (trim(left_operand) /= trim(right_operand))
      case('<')
        test_result = (trim(left_operand) < trim(right_operand))
      case('>')
        test_result = (trim(left_operand) > trim(right_operand))

      ! Integer comparisons
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

      ! File comparisons
      case('-nt')
        test_result = file_is_newer(trim(left_operand), trim(right_operand))
      case('-ot')
        test_result = file_is_older(trim(left_operand), trim(right_operand))
      case('-ef')
        test_result = file_same_as(trim(left_operand), trim(right_operand))

      case default
        test_result = .false.
      end select

    else if (cmd%num_tokens == 5) then
      ! Logical operators: test ARG1 OP ARG2 LOG_OP ARG3
      ! OR: test ! OP ARG
      left_operand = cmd%tokens(2)
      operator = cmd%tokens(3)
      right_operand = cmd%tokens(4)

      ! Check if this is a logical AND or OR
      if (trim(cmd%tokens(4)) == '-a' .or. trim(cmd%tokens(4)) == '-o') then
        ! Pattern: test ARG1 OP ARG2 {-a|-o} ...
        ! For simplicity, only handle: test OP1 ARG1 -a OP2 ARG2

        ! Evaluate left side (OP1 ARG1)
        select case(trim(left_operand))
        case('-z')
          left_result = (len_trim(operator) == 0)
        case('-n')
          left_result = (len_trim(operator) > 0)
        case('-f')
          left_result = file_is_regular(trim(operator))
        case('-d')
          left_result = file_is_directory(trim(operator))
        case('-e')
          left_result = file_exists(trim(operator))
        case default
          left_result = .false.
        end select

        log_op = cmd%tokens(4)
        op2 = cmd%tokens(5)

        ! For now, assume op2 is a string for simple test
        ! This is simplified - full implementation would need recursive parsing
        right_result = (len_trim(op2) > 0)

        if (trim(log_op) == '-a') then
          test_result = left_result .and. right_result
        else  ! -o
          test_result = left_result .or. right_result
        end if
      else
        ! Not a logical operator pattern we recognize
        test_result = .false.
      end if

    else if (cmd%num_tokens >= 3 .and. trim(cmd%tokens(2)) == '!') then
      ! Logical NOT: test ! OP ARG
      ! Recursively evaluate the rest

      ! Create sub-command without the '!'
      sub_cmd%num_tokens = cmd%num_tokens - 1
      sub_cmd%tokens(1) = cmd%tokens(1)  ! 'test'
      do i = 2, sub_cmd%num_tokens
        sub_cmd%tokens(i) = cmd%tokens(i+1)
      end do

      ! Recursively evaluate
      call execute_test_command(sub_cmd, shell)

      ! Negate the result
      if (shell%last_exit_status == 0) then
        shell%last_exit_status = 1
      else
        shell%last_exit_status = 0
      end if
      return

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