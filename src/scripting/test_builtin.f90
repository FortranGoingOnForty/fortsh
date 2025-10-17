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
    type(command_t) :: sub_cmd, left_cmd, right_cmd
    integer :: i, j, test_exit_status, logical_op_pos

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
      case('-L', '-h')
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

    else if (cmd%num_tokens >= 5) then
      ! First, check if the entire expression is wrapped in parentheses
      ! If so, strip them and re-evaluate
      if (trim(cmd%tokens(2)) == '\(' .or. trim(cmd%tokens(2)) == '(') then
        ! Check if there's a matching closing parenthesis
        if (trim(cmd%tokens(cmd%num_tokens)) == '\)' .or. trim(cmd%tokens(cmd%num_tokens)) == ')') then
          ! Strip parentheses and recursively evaluate
          sub_cmd = cmd  ! Copy all fields
          sub_cmd%tokens(1) = 'test'
          sub_cmd%num_tokens = cmd%num_tokens - 2
          do i = 2, sub_cmd%num_tokens
            sub_cmd%tokens(i) = cmd%tokens(i + 1)
          end do
          call execute_test_command(sub_cmd, shell)
          return
        end if
      end if

      ! Check for logical operators -a (AND) or -o (OR)
      ! Search for the logical operator in the token stream

      logical_op_pos = 0
      do i = 2, cmd%num_tokens
        if (trim(cmd%tokens(i)) == '-a' .or. trim(cmd%tokens(i)) == '-o') then
          logical_op_pos = i
          exit
        end if
      end do

      if (logical_op_pos > 0) then
        ! Found a logical operator - split and recursively evaluate

        ! Initialize left sub-command
        left_cmd = cmd  ! Copy all fields first
        left_cmd%tokens(1) = 'test'
        left_cmd%num_tokens = logical_op_pos - 1
        do j = 2, left_cmd%num_tokens
          left_cmd%tokens(j) = cmd%tokens(j)
        end do

        ! Initialize right sub-command
        right_cmd = cmd  ! Copy all fields first
        right_cmd%tokens(1) = 'test'
        right_cmd%num_tokens = cmd%num_tokens - logical_op_pos + 1
        do j = 2, right_cmd%num_tokens
          right_cmd%tokens(j) = cmd%tokens(j + logical_op_pos - 1)
        end do

        ! Recursively evaluate left side
        call execute_test_command(left_cmd, shell)
        left_result = (shell%last_exit_status == 0)

        ! Recursively evaluate right side
        call execute_test_command(right_cmd, shell)
        right_result = (shell%last_exit_status == 0)

        ! Combine results with logical operator
        if (trim(cmd%tokens(logical_op_pos)) == '-a') then
          test_result = left_result .and. right_result
        else  ! -o
          test_result = left_result .or. right_result
        end if
      else
        ! No logical operator found - unknown pattern
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