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
    type(command_t) :: sub_cmd, left_cmd, right_cmd
    integer :: i, j, test_exit_status, logical_op_pos
    integer :: paren_depth, check_pos
    logical :: outer_parens_wrap_all
    integer :: effective_num_tokens
    logical :: is_bracket_cmd


    ! Check if this is [[ ]] (advanced test) - use advanced_test module
    if (trim(cmd%tokens(1)) == '[[') then
      test_exit_status = evaluate_test_expression(shell, cmd%tokens, cmd%num_tokens)
      shell%last_exit_status = test_exit_status
      return
    end if

    ! Simple test implementation for [ and test commands
    !
    ! Key insight: For '[' command, the last token is always ']' which should be ignored.
    ! We normalize by converting '[' commands to 'test' commands (stripping the ']')

    if (cmd%num_tokens < 2) then
      shell%last_exit_status = 1  ! False
      return
    end if

    ! Determine if this is a '[' command and calculate effective token count
    is_bracket_cmd = (trim(cmd%tokens(1)) == '[')
    if (is_bracket_cmd) then
      ! For '[' commands, ignore the closing ']'
      effective_num_tokens = cmd%num_tokens - 1
    else
      effective_num_tokens = cmd%num_tokens
    end if

    ! Handle different test patterns (using effective token count)
    if (effective_num_tokens == 1) then
      ! [ ] or just 'test' - empty test, returns false
      test_result = .false.

    else if (effective_num_tokens == 2) then
      ! [ STRING ] or test STRING - true if STRING is not empty
      test_result = (len_trim(cmd%tokens(2)) > 0)

    else if (effective_num_tokens >= 3 .and. trim(cmd%tokens(2)) == '!') then
      ! Logical NOT: [ ! expr ] or test ! expr
      ! Handle this EARLY to ensure correct precedence
      ! Recursively evaluate the rest (without the '!')

      ! Create sub-command without the '!'
      sub_cmd%num_tokens = cmd%num_tokens - 1
      allocate(character(len=256) :: sub_cmd%tokens(sub_cmd%num_tokens))
      sub_cmd%tokens(1) = cmd%tokens(1)  ! 'test' or '['
      do i = 2, sub_cmd%num_tokens
        sub_cmd%tokens(i) = cmd%tokens(i+1)
      end do

      ! Recursively evaluate
      call execute_test_command(sub_cmd, shell)
      deallocate(sub_cmd%tokens)

      ! Negate the result
      if (shell%last_exit_status == 0) then
        shell%last_exit_status = 1
      else
        shell%last_exit_status = 0
      end if
      return

    else if (effective_num_tokens == 3) then
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

    else if (effective_num_tokens == 4) then
      ! Check for parentheses: [ ( expr ) ]
      if ((trim(cmd%tokens(2)) == '(' .or. trim(cmd%tokens(2)) == '\(') .and. &
          (trim(cmd%tokens(4)) == ')' .or. trim(cmd%tokens(4)) == '\)')) then
        ! Parenthesized single expression - evaluate the inner expression
        ! tokens(3) is the inner expression
        test_result = (len_trim(cmd%tokens(3)) > 0)
      ! Check if this is a logical operator expression (a -a b or a -o b)
      ! These should be handled specially, not as binary comparisons
      else if (trim(cmd%tokens(3)) == '-a' .or. trim(cmd%tokens(3)) == '-o') then
        ! Logical operator with simple operands: [ a -a b ] or [ a -o b ]
        ! Left side: implicit non-empty test on tokens(2)
        left_result = (len_trim(cmd%tokens(2)) > 0)
        ! Right side: implicit non-empty test on tokens(4)
        right_result = (len_trim(cmd%tokens(4)) > 0)

        if (trim(cmd%tokens(3)) == '-a') then
          test_result = left_result .and. right_result
        else  ! -o
          test_result = left_result .or. right_result
        end if
      else
        ! test ARG1 OP ARG2 - binary operators
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
      end if  ! End of logical operator check

    else if (effective_num_tokens >= 5) then
      ! Complex expressions: parentheses and logical operators
      ! First, check if the entire expression is wrapped in parentheses
      ! If so, strip them and re-evaluate
      if (trim(cmd%tokens(2)) == '\(' .or. trim(cmd%tokens(2)) == '(') then
        ! Check if this opening paren has its matching closing paren at the end
        ! by counting paren depth
        paren_depth = 1
        outer_parens_wrap_all = .false.

        ! Check up to the last effective content position
        ! For [ ( 1 -eq 1 ) ]: tokens are [, (, 1, -eq, 1, ), ]
        !   - num_tokens = 7, effective_num_tokens = 6
        !   - Content is positions 2-6, closing ) should be at position 6 = effective_num_tokens
        ! For test ( 1 -eq 1 ): tokens are test, (, 1, -eq, 1, )
        !   - num_tokens = 6, effective_num_tokens = 6
        !   - Content is positions 2-6, closing ) should be at position 6 = effective_num_tokens
        do check_pos = 3, effective_num_tokens
          if (trim(cmd%tokens(check_pos)) == '\(' .or. trim(cmd%tokens(check_pos)) == '(') then
            paren_depth = paren_depth + 1
          else if (trim(cmd%tokens(check_pos)) == '\)' .or. trim(cmd%tokens(check_pos)) == ')') then
            paren_depth = paren_depth - 1
            if (paren_depth == 0) then
              ! The opening paren at position 2 closes here
              ! It wraps everything if this closing paren is at the last effective position
              outer_parens_wrap_all = (check_pos == effective_num_tokens)
              ! Exit the loop - we found where the opening paren closes
              exit
            end if
          end if
        end do

        if (outer_parens_wrap_all) then
          ! Strip outer parentheses and recursively evaluate
          sub_cmd = cmd  ! Copy all fields
          sub_cmd%tokens(1) = cmd%tokens(1)  ! Keep the original command (test or [)
          sub_cmd%num_tokens = cmd%num_tokens - 2
          do i = 2, sub_cmd%num_tokens
            sub_cmd%tokens(i) = cmd%tokens(i + 1)
          end do
          call execute_test_command(sub_cmd, shell)
          return
        end if
      end if

      ! Check for logical operators -a (AND) or -o (OR)
      ! Search for the LOWEST precedence operator OUTSIDE parentheses
      ! POSIX: -o (OR) has lower precedence than -a (AND)
      ! So we prefer -o as the split point, and skip operators inside parens

      logical_op_pos = 0
      paren_depth = 0
      do i = 2, effective_num_tokens
        if (trim(cmd%tokens(i)) == '\(' .or. trim(cmd%tokens(i)) == '(') then
          paren_depth = paren_depth + 1
        else if (trim(cmd%tokens(i)) == '\)' .or. trim(cmd%tokens(i)) == ')') then
          paren_depth = paren_depth - 1
        else if (paren_depth == 0) then
          ! Only consider operators outside parentheses
          if (trim(cmd%tokens(i)) == '-o') then
            ! -o has lowest precedence, always use it as split point
            logical_op_pos = i
            exit  ! Found -o, use it immediately
          else if (trim(cmd%tokens(i)) == '-a') then
            ! -a has higher precedence, record but keep looking for -o
            if (logical_op_pos == 0) then
              logical_op_pos = i
            end if
          end if
        end if
      end do

      if (logical_op_pos > 0) then
        ! Found a logical operator - split and recursively evaluate
        ! Use 'test' for sub-commands to avoid dealing with closing ']'

        ! Initialize left sub-command: tokens from 2 to logical_op_pos-1
        left_cmd = cmd  ! Copy all fields first
        left_cmd%tokens(1) = 'test'
        left_cmd%num_tokens = logical_op_pos - 1
        do j = 2, left_cmd%num_tokens
          left_cmd%tokens(j) = cmd%tokens(j)
        end do

        ! Initialize right sub-command: tokens from logical_op_pos+1 to effective end
        ! Use effective_num_tokens to exclude the closing ']' for [ commands
        right_cmd = cmd  ! Copy all fields first
        right_cmd%tokens(1) = 'test'
        right_cmd%num_tokens = effective_num_tokens + 1 - logical_op_pos
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