! ==============================================================================
! Module: expansion
! Purpose: Parameter expansion and arithmetic operations
! ==============================================================================
module expansion
  use shell_types
  use variables  ! includes check_nounset
  use substitution, only: execute_command_and_capture
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000

contains

  ! Parameter expansion: ${var:offset:length}
  function parameter_expansion(shell, expression) result(expanded)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: expression
    character(len=2048) :: expanded

    character(len=256) :: var_name, operation, param1, param2, pattern, replacement
    character(len=1024) :: var_value
    integer :: colon_pos, dash_pos, plus_pos, percent_pos, hash_pos, slash_pos, equals_pos, question_pos
    integer :: offset, length, i, double_op_pos, at_pos
    character :: transform_op
    logical :: replace_all, greedy, has_colon, var_is_set, var_is_null

    ! Array expansion variables
    integer :: bracket_pos, bracket_end, j, num_keys
    character(len=256) :: array_name, array_key
    character(len=256), allocatable :: keys(:)
    logical :: is_keys_expansion, is_length_expansion, is_all_expansion

    expanded = ''

    ! Remove ${ and }
    if (len_trim(expression) < 4) return
    var_name = expression(3:len_trim(expression)-1)
    write(error_unit, '(A,A,A)') 'DEBUG START: var_name=[', trim(var_name), ']'

    ! ========================================================================
    ! Check for array bracket syntax FIRST: ${array[key]}, ${!array[@]}, ${#array[@]}
    ! ========================================================================
    bracket_pos = index(var_name, '[')
    if (bracket_pos > 0) then
      bracket_end = index(var_name, ']')
      if (bracket_end > bracket_pos) then
        ! Extract array name and key
        array_name = var_name(:bracket_pos-1)
        array_key = var_name(bracket_pos+1:bracket_end-1)

        ! Check for special prefixes (! for keys, # for length)
        is_keys_expansion = .false.
        is_length_expansion = .false.

        if (len_trim(array_name) > 0 .and. array_name(1:1) == '!') then
          ! ${!array[@]} - get all keys
          is_keys_expansion = .true.
          array_name = array_name(2:)  ! Remove ! prefix
        else if (len_trim(array_name) > 0 .and. array_name(1:1) == '#') then
          ! ${#array[@]} - get array length
          is_length_expansion = .true.
          array_name = array_name(2:)  ! Remove # prefix
        end if

        ! Check for [@] or [*] (all values/keys)
        is_all_expansion = (trim(array_key) == '@' .or. trim(array_key) == '*')

        ! Handle associative arrays
        if (is_associative_array(shell, trim(array_name))) then
          if (is_keys_expansion .and. is_all_expansion) then
            ! ${!array[@]} - return all keys
            allocate(keys(50))  ! Match size in get_assoc_array_keys
            call get_assoc_array_keys(shell, trim(array_name), keys, num_keys)
            expanded = ''
            do j = 1, min(num_keys, 50)
              if (len_trim(expanded) + len_trim(keys(j)) + 2 > 2048) exit  ! Prevent overflow
              if (j > 1) expanded = trim(expanded) // ' '
              expanded = trim(expanded) // trim(keys(j))
            end do
            deallocate(keys)
            return
          else if (is_length_expansion .and. is_all_expansion) then
            ! ${#array[@]} - return number of keys
            allocate(keys(50))
            call get_assoc_array_keys(shell, trim(array_name), keys, num_keys)
            deallocate(keys)
            write(expanded, '(I0)') num_keys
            return
          else if (is_all_expansion) then
            ! ${array[@]} - return all values
            ! Get all keys, then get value for each key
            allocate(keys(50))
            call get_assoc_array_keys(shell, trim(array_name), keys, num_keys)
            expanded = ''
            do j = 1, min(num_keys, 50)
              var_value = get_assoc_array_value(shell, trim(array_name), trim(keys(j)))
              if (len_trim(expanded) + len_trim(var_value) + 2 > 2048) exit  ! Prevent overflow
              if (j > 1) expanded = trim(expanded) // ' '
              expanded = trim(expanded) // trim(var_value)
            end do
            deallocate(keys)
            return
          else
            ! ${array[key]} - get value for specific key
            var_value = get_assoc_array_value(shell, trim(array_name), trim(array_key))
            expanded = trim(var_value)
            return
          end if
        else
          ! Handle indexed arrays (use existing get_array_element if available)
          ! For now, if not an associative array, try normal variable expansion
          if (.not. is_all_expansion) then
            ! Try to get indexed array element
            ! Note: indexed arrays use numeric indices
            ! This would call get_array_element(shell, array_name, index)
            ! For now, fall through to normal variable expansion
          end if
        end if
      end if
    end if

    ! Check for various expansion operations (need to check in right order!)

    ! Check for @ transformations first: ${var@U}, ${var@L}, ${var@u}, ${var@Q}, ${var@E}
    at_pos = index(var_name, '@')
    if (at_pos > 0 .and. at_pos < len_trim(var_name)) then
      ! Extract variable name and transformation operator
      operation = var_name(:at_pos-1)
      transform_op = var_name(at_pos+1:at_pos+1)
      var_value = get_shell_variable(shell, trim(operation))

      select case (transform_op)
      case ('U')
        ! ${var@U} - convert to uppercase
        expanded = to_upper(trim(var_value))
        return
      case ('L')
        ! ${var@L} - convert to lowercase
        expanded = to_lower(trim(var_value))
        return
      case ('u')
        ! ${var@u} - capitalize first character
        if (len_trim(var_value) > 0) then
          expanded = to_upper(var_value(1:1))
          if (len_trim(var_value) > 1) expanded = trim(expanded) // var_value(2:)
        end if
        return
      case ('l')
        ! ${var@l} - lowercase first character
        if (len_trim(var_value) > 0) then
          expanded = to_lower(var_value(1:1))
          if (len_trim(var_value) > 1) expanded = trim(expanded) // var_value(2:)
        end if
        return
      case ('Q')
        ! ${var@Q} - shell-quote value (wrap in single quotes, escape embedded quotes)
        expanded = quote_value(trim(var_value))
        return
      case ('E')
        ! ${var@E} - expand escape sequences
        expanded = expand_escape_sequences(trim(var_value))
        return
      end select
    end if

    ! Check for case conversion first (^, ^^, ,, ,,)
    ! Find the position of ^ or , to determine if it's case conversion
    i = len_trim(var_name)
    if (i > 1) then
      if (var_name(i:i) == '^') then
        ! Check for ^^ (uppercase all) or ^ (uppercase first)
        if (i > 1 .and. var_name(i-1:i-1) == '^') then
          ! ${var^^} - uppercase all
          operation = var_name(:i-2)
          var_value = get_shell_variable(shell, trim(operation))
          expanded = to_upper(trim(var_value))
        else
          ! ${var^} - uppercase first
          operation = var_name(:i-1)
          var_value = get_shell_variable(shell, trim(operation))
          if (len_trim(var_value) > 0) then
            expanded = to_upper(var_value(1:1))
            if (len_trim(var_value) > 1) expanded = trim(expanded) // var_value(2:)
          end if
        end if
        return
      else if (var_name(i:i) == ',') then
        ! Check for ,, (lowercase all) or , (lowercase first)
        if (i > 1 .and. var_name(i-1:i-1) == ',') then
          ! ${var,,} - lowercase all
          operation = var_name(:i-2)
          var_value = get_shell_variable(shell, trim(operation))
          expanded = to_lower(trim(var_value))
        else
          ! ${var,} - lowercase first
          operation = var_name(:i-1)
          var_value = get_shell_variable(shell, trim(operation))
          if (len_trim(var_value) > 0) then
            expanded = to_lower(var_value(1:1))
            if (len_trim(var_value) > 1) expanded = trim(expanded) // var_value(2:)
          end if
        end if
        return
      end if
    end if

    ! Now check for other operations
    colon_pos = index(var_name, ':')
    dash_pos = index(var_name, '-')
    plus_pos = index(var_name, '+')
    equals_pos = index(var_name, '=')
    question_pos = index(var_name, '?')
    percent_pos = index(var_name, '%')
    hash_pos = index(var_name, '#')
    slash_pos = index(var_name, '/')
    write(error_unit, '(A,A,A,I0)') 'DEBUG AFTER OPS: var_name=[', trim(var_name), '] dash_pos=', dash_pos

    ! Pattern replacement: ${var/pattern/replacement} or ${var//pattern/replacement}
    if (slash_pos > 0) then
      ! Find second slash to separate pattern from replacement
      i = index(var_name(slash_pos+1:), '/')
      if (i > 0) then
        i = slash_pos + i
        operation = var_name(:slash_pos-1)
        pattern = var_name(slash_pos+1:i-1)
        replacement = var_name(i+1:)

        ! Check if it's replace all (//)
        if (slash_pos > 1 .and. var_name(slash_pos-1:slash_pos-1) == '/') then
          replace_all = .true.
          operation = var_name(:slash_pos-2)
        else
          replace_all = .false.
        end if

        var_value = get_shell_variable(shell, trim(operation))
        call pattern_replace(trim(var_value), trim(pattern), trim(replacement), &
                            replace_all, expanded)
        return
      end if
    end if

    ! Suffix removal: ${var%pattern} or ${var%%pattern}
    if (percent_pos > 0) then
      ! Check for %%
      if (percent_pos < len_trim(var_name) .and. var_name(percent_pos+1:percent_pos+1) == '%') then
        ! ${var%%pattern} - remove largest matching suffix
        greedy = .true.
        operation = var_name(:percent_pos-1)
        pattern = var_name(percent_pos+2:)
      else
        ! ${var%pattern} - remove smallest matching suffix
        greedy = .false.
        operation = var_name(:percent_pos-1)
        pattern = var_name(percent_pos+1:)
      end if
      var_value = get_shell_variable(shell, trim(operation))
      call remove_suffix(trim(var_value), trim(pattern), greedy, expanded)
      return
    end if

    ! Prefix removal: ${var#pattern} or ${var##pattern}
    ! But first check if it's ${#var} (length)
    if (hash_pos == 1 .and. len_trim(var_name) > 1) then
      ! ${#var} length expansion
      operation = var_name(2:)
      var_value = get_shell_variable(shell, trim(operation))
      write(expanded, '(I0)') len_trim(var_value)
      return
    else if (hash_pos > 1) then
      ! Check for ##
      if (hash_pos < len_trim(var_name) .and. var_name(hash_pos+1:hash_pos+1) == '#') then
        ! ${var##pattern} - remove largest matching prefix
        greedy = .true.
        operation = var_name(:hash_pos-1)
        pattern = var_name(hash_pos+2:)
      else
        ! ${var#pattern} - remove smallest matching prefix
        greedy = .false.
        operation = var_name(:hash_pos-1)
        pattern = var_name(hash_pos+1:)
      end if
      var_value = get_shell_variable(shell, trim(operation))
      call remove_prefix(trim(var_value), trim(pattern), greedy, expanded)
      return
    end if

    ! Check if colon is for substring expansion (followed by digit) or parameter expansion (followed by operator)
    if (colon_pos > 0) then
      ! Check what follows the colon
      if (colon_pos < len_trim(var_name)) then
        ! If followed by an operator (-+?=), it's parameter expansion, not substring
        if (var_name(colon_pos+1:colon_pos+1) == '-' .or. &
            var_name(colon_pos+1:colon_pos+1) == '+' .or. &
            var_name(colon_pos+1:colon_pos+1) == '?' .or. &
            var_name(colon_pos+1:colon_pos+1) == '=') then
          ! This is parameter expansion like ${var:-word}, handle it below
        else
          ! This is substring expansion ${var:offset:length}
          call parse_substring_expansion(var_name, operation, param1, param2)
          var_value = get_shell_variable(shell, trim(operation))

          if (len_trim(param1) > 0) then
            read(param1, *) offset
            if (len_trim(param2) > 0) then
              read(param2, *) length
              if (offset >= 0 .and. offset < len_trim(var_value)) then
                i = min(length, len_trim(var_value) - offset)
                expanded = var_value(offset+1:offset+i)
              end if
            else
              if (offset >= 0 .and. offset < len_trim(var_value)) then
                expanded = var_value(offset+1:)
              end if
            end if
          else
            expanded = var_value
          end if
          return
        end if
      end if
    end if

    if (dash_pos > 0 .or. plus_pos > 0 .or. equals_pos > 0 .or. question_pos > 0) then
      ! ${var-word}, ${var:-word}, ${var+word}, ${var:+word}, ${var=word}, ${var:=word}, ${var?word}, ${var:?word}
      write(error_unit, '(A,I0,A,I0,A,I0,A,I0)') 'DEBUG: dash=', dash_pos, &
           ' plus=', plus_pos, ' eq=', equals_pos, ' q=', question_pos

      ! Determine which operator we have
      if (dash_pos > 0 .and. (plus_pos == 0 .or. dash_pos < plus_pos) .and. &
          (equals_pos == 0 .or. dash_pos < equals_pos) .and. (question_pos == 0 .or. dash_pos < question_pos)) then
        ! Dash operator
        write(error_unit, '(A)') 'DEBUG: Entering dash operator handler'
        has_colon = (dash_pos > 1 .and. var_name(dash_pos-1:dash_pos-1) == ':')
        if (has_colon) then
          operation = var_name(:dash_pos-2)
          param1 = var_name(dash_pos+1:)
        else
          operation = var_name(:dash_pos-1)
          param1 = var_name(dash_pos+1:)
        end if

        write(error_unit, '(A,L1,A,A,A,A,A)') 'DEBUG: has_colon=', has_colon, &
             ' op=', trim(operation), ' param1=', trim(param1)
        var_is_set = is_shell_variable_set(shell, trim(operation))
        var_value = get_shell_variable(shell, trim(operation))
        var_is_null = (len_trim(var_value) == 0)
        write(error_unit, '(A,L1,A,A,A,L1)') 'DEBUG: var_is_set=', var_is_set, &
             ' val=', trim(var_value), ' null=', var_is_null

        ! ${var-word}: use word if var is unset
        ! ${var:-word}: use word if var is unset or null
        if (has_colon) then
          if (.not. var_is_set .or. var_is_null) then
            expanded = trim(param1)
          else
            expanded = trim(var_value)
          end if
        else
          if (.not. var_is_set) then
            expanded = trim(param1)
          else
            expanded = trim(var_value)
          end if
        end if
        write(error_unit, '(A,A,A)') 'DEBUG: expanded=', trim(expanded), '|'

      else if (plus_pos > 0 .and. (equals_pos == 0 .or. plus_pos < equals_pos) .and. &
               (question_pos == 0 .or. plus_pos < question_pos)) then
        ! Plus operator
        has_colon = (plus_pos > 1 .and. var_name(plus_pos-1:plus_pos-1) == ':')
        if (has_colon) then
          operation = var_name(:plus_pos-2)
          param1 = var_name(plus_pos+1:)
        else
          operation = var_name(:plus_pos-1)
          param1 = var_name(plus_pos+1:)
        end if

        var_is_set = is_shell_variable_set(shell, trim(operation))
        var_value = get_shell_variable(shell, trim(operation))
        var_is_null = (len_trim(var_value) == 0)

        ! ${var+word}: use word if var is set (even if null)
        ! ${var:+word}: use word if var is set and not null
        if (has_colon) then
          if (var_is_set .and. .not. var_is_null) then
            expanded = trim(param1)
          else
            expanded = ''
          end if
        else
          if (var_is_set) then
            expanded = trim(param1)
          else
            expanded = ''
          end if
        end if

      else if (equals_pos > 0 .and. (question_pos == 0 .or. equals_pos < question_pos)) then
        ! Equals operator (assign and expand)
        has_colon = (equals_pos > 1 .and. var_name(equals_pos-1:equals_pos-1) == ':')
        if (has_colon) then
          operation = var_name(:equals_pos-2)
          param1 = var_name(equals_pos+1:)
        else
          operation = var_name(:equals_pos-1)
          param1 = var_name(equals_pos+1:)
        end if

        var_is_set = is_shell_variable_set(shell, trim(operation))
        var_value = get_shell_variable(shell, trim(operation))
        var_is_null = (len_trim(var_value) == 0)

        ! ${var=word}: assign word if var is unset, then expand to var
        ! ${var:=word}: assign word if var is unset or null, then expand to var
        if (has_colon) then
          if (.not. var_is_set .or. var_is_null) then
            call set_shell_variable(shell, trim(operation), trim(param1))
            expanded = trim(param1)
          else
            expanded = trim(var_value)
          end if
        else
          if (.not. var_is_set) then
            call set_shell_variable(shell, trim(operation), trim(param1))
            expanded = trim(param1)
          else
            expanded = trim(var_value)
          end if
        end if

      else if (question_pos > 0) then
        ! Question operator (error if unset)
        has_colon = (question_pos > 1 .and. var_name(question_pos-1:question_pos-1) == ':')
        if (has_colon) then
          operation = var_name(:question_pos-2)
          param1 = var_name(question_pos+1:)
        else
          operation = var_name(:question_pos-1)
          param1 = var_name(question_pos+1:)
        end if

        var_is_set = is_shell_variable_set(shell, trim(operation))
        var_value = get_shell_variable(shell, trim(operation))
        var_is_null = (len_trim(var_value) == 0)

        ! ${var?word}: error if var is unset
        ! ${var:?word}: error if var is unset or null
        if (has_colon) then
          if (.not. var_is_set .or. var_is_null) then
            if (len_trim(param1) > 0) then
              write(error_unit, '(A)') trim(operation) // ': ' // trim(param1)
            else
              write(error_unit, '(A)') trim(operation) // ': parameter null or not set'
            end if
            shell%last_exit_status = 127
            shell%fatal_expansion_error = .true.  ! Signal to abort execution
            expanded = ''
          else
            expanded = trim(var_value)
          end if
        else
          if (.not. var_is_set) then
            if (len_trim(param1) > 0) then
              write(error_unit, '(A)') trim(operation) // ': ' // trim(param1)
            else
              write(error_unit, '(A)') trim(operation) // ': parameter not set'
            end if
            shell%last_exit_status = 127
            shell%fatal_expansion_error = .true.  ! Signal to abort execution
            expanded = ''
          else
            expanded = trim(var_value)
          end if
        end if
      end if
      return

    else if (hash_pos > 0) then
      ! ${#var} length expansion
      operation = var_name(hash_pos+1:)
      var_value = get_shell_variable(shell, trim(operation))
      write(expanded, '(I0)') len_trim(var_value)
      
    else
      ! Simple variable expansion
      var_value = get_shell_variable(shell, trim(var_name))

      ! Check if variable is unset and set -u is enabled
      if (len_trim(var_value) == 0 .and. .not. is_shell_variable_set(shell, trim(var_name))) then
        if (check_nounset(shell, trim(var_name))) then
          shell%last_exit_status = 1
          shell%fatal_expansion_error = .true.
          expanded = ''
          return
        end if
      end if

      expanded = trim(var_value)
    end if

  end function

  subroutine parse_substring_expansion(input, var_name, offset_str, length_str)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: var_name, offset_str, length_str
    integer :: first_colon, second_colon
    
    var_name = ''
    offset_str = ''
    length_str = ''
    
    first_colon = index(input, ':')
    if (first_colon == 0) return
    
    var_name = input(:first_colon-1)
    
    second_colon = index(input(first_colon+1:), ':')
    if (second_colon > 0) then
      second_colon = first_colon + second_colon
      offset_str = input(first_colon+1:second_colon-1)
      length_str = input(second_colon+1:)
    else
      offset_str = input(first_colon+1:)
    end if
  end subroutine

  ! ============================================================================
  ! Parameter Expansion Helper Functions
  ! ============================================================================

  ! Convert string to uppercase
  function to_upper(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: i, char_code

    output = input
    do i = 1, len_trim(input)
      char_code = ichar(input(i:i))
      if (char_code >= ichar('a') .and. char_code <= ichar('z')) then
        output(i:i) = char(char_code - 32)
      end if
    end do
  end function

  ! Convert string to lowercase
  function to_lower(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: i, char_code

    output = input
    do i = 1, len_trim(input)
      char_code = ichar(input(i:i))
      if (char_code >= ichar('A') .and. char_code <= ichar('Z')) then
        output(i:i) = char(char_code + 32)
      end if
    end do
  end function

  ! Quote value - wrap in single quotes and escape embedded single quotes
  ! Used for ${var@Q} transformation
  function quote_value(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    character(len=:), allocatable :: temp_output
    integer :: i, out_pos, capacity

    if (len_trim(input) == 0) then
      output = "''"
      return
    end if

    ! Allocate with initial capacity
    capacity = len(input) * 2 + 10
    allocate(character(len=capacity) :: temp_output)
    temp_output = "'"
    out_pos = 2

    do i = 1, len_trim(input)
      if (input(i:i) == "'") then
        ! Ensure we have space for escape sequence
        if (out_pos + 4 > capacity) then
          call grow_string_buffer_exp(temp_output, capacity, capacity * 2, out_pos - 1)
        end if
        ! Escape single quote: ' becomes '\''
        temp_output(out_pos:out_pos+3) = "'\'''"
        out_pos = out_pos + 4
      else
        if (out_pos > capacity) then
          call grow_string_buffer_exp(temp_output, capacity, capacity * 2, out_pos - 1)
        end if
        temp_output(out_pos:out_pos) = input(i:i)
        out_pos = out_pos + 1
      end if
    end do

    if (out_pos > capacity) then
      call grow_string_buffer_exp(temp_output, capacity, capacity * 2, out_pos - 1)
    end if
    temp_output(out_pos:out_pos) = "'"
    output = temp_output(1:out_pos)
    deallocate(temp_output)
  end function

  ! Expand escape sequences in string
  ! Used for ${var@E} transformation
  function expand_escape_sequences(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    character(len=:), allocatable :: temp_output
    integer :: i, out_pos, capacity

    ! Allocate with initial capacity
    capacity = len(input) + 100
    allocate(character(len=capacity) :: temp_output)
    temp_output = ''
    out_pos = 1
    i = 1

    do while (i <= len_trim(input))
      if (input(i:i) == '\' .and. i < len_trim(input)) then
        ! Escape sequence
        i = i + 1
        select case (input(i:i))
        case ('n')
          temp_output(out_pos:out_pos) = char(10)  ! newline
          out_pos = out_pos + 1
        case ('t')
          temp_output(out_pos:out_pos) = char(9)   ! tab
          out_pos = out_pos + 1
        case ('r')
          temp_output(out_pos:out_pos) = char(13)  ! carriage return
          out_pos = out_pos + 1
        case ('b')
          temp_output(out_pos:out_pos) = char(8)   ! backspace
          out_pos = out_pos + 1
        case ('f')
          temp_output(out_pos:out_pos) = char(12)  ! form feed
          out_pos = out_pos + 1
        case ('v')
          temp_output(out_pos:out_pos) = char(11)  ! vertical tab
          out_pos = out_pos + 1
        case ('a')
          temp_output(out_pos:out_pos) = char(7)   ! alert/bell
          out_pos = out_pos + 1
        case ('e')
          temp_output(out_pos:out_pos) = char(27)  ! escape
          out_pos = out_pos + 1
        case ('\')
          temp_output(out_pos:out_pos) = '\'       ! backslash
          out_pos = out_pos + 1
        case ('"')
          temp_output(out_pos:out_pos) = '"'       ! double quote
          out_pos = out_pos + 1
        case ("'")
          temp_output(out_pos:out_pos) = "'"       ! single quote
          out_pos = out_pos + 1
        case default
          ! Unknown escape - preserve backslash and character
          temp_output(out_pos:out_pos+1) = '\' // input(i:i)
          out_pos = out_pos + 2
        end select
        i = i + 1
      else
        temp_output(out_pos:out_pos) = input(i:i)
        out_pos = out_pos + 1
        i = i + 1
      end if
    end do

    output = temp_output(1:out_pos-1)
    deallocate(temp_output)
  end function

  ! Pattern replacement in string
  subroutine pattern_replace(input, pattern, replacement, replace_all, output)
    character(len=*), intent(in) :: input, pattern, replacement
    logical, intent(in) :: replace_all
    character(len=*), intent(out) :: output
    integer :: pos, last_pos
    character(len=2048) :: temp

    output = ''
    temp = input

    if (len_trim(pattern) == 0) then
      output = input
      return
    end if

    last_pos = 1
    do
      pos = index(temp(last_pos:), trim(pattern))
      if (pos == 0) then
        ! No more matches, append rest
        output = trim(output) // temp(last_pos:)
        exit
      end if

      ! Append text before match + replacement
      pos = last_pos + pos - 1
      output = trim(output) // temp(last_pos:pos-1) // trim(replacement)
      last_pos = pos + len_trim(pattern)

      if (.not. replace_all) then
        ! Only replace first occurrence
        output = trim(output) // temp(last_pos:)
        exit
      end if
    end do
  end subroutine

  ! Remove suffix matching pattern (greedy or non-greedy)
  subroutine remove_suffix(input, pattern, greedy, output)
    character(len=*), intent(in) :: input, pattern
    logical, intent(in) :: greedy
    character(len=*), intent(out) :: output
    integer :: pos, best_pos, i

    output = input

    if (len_trim(pattern) == 0) return

    if (greedy) then
      ! Remove largest matching suffix (%%)
      ! Try to match from start of string
      best_pos = 0
      do i = 1, len_trim(input)
        if (match_pattern(input(i:), trim(pattern))) then
          best_pos = i
          exit
        end if
      end do
      if (best_pos > 0) then
        output = input(1:best_pos-1)
      end if
    else
      ! Remove smallest matching suffix (%)
      ! Try to match from end of string
      do i = len_trim(input), 1, -1
        if (match_pattern(input(i:), trim(pattern))) then
          output = input(1:i-1)
          return
        end if
      end do
    end if
  end subroutine

  ! Remove prefix matching pattern (greedy or non-greedy)
  subroutine remove_prefix(input, pattern, greedy, output)
    character(len=*), intent(in) :: input, pattern
    logical, intent(in) :: greedy
    character(len=*), intent(out) :: output
    integer :: pos, best_pos, i

    output = input

    if (len_trim(pattern) == 0) return

    if (greedy) then
      ! Remove largest matching prefix (##)
      ! Try to match from end, working backwards
      best_pos = 0
      do i = len_trim(input), 1, -1
        if (match_pattern(input(1:i), trim(pattern))) then
          best_pos = i
          exit
        end if
      end do
      if (best_pos > 0) then
        output = input(best_pos+1:)
      end if
    else
      ! Remove smallest matching prefix (#)
      ! Try to match from start
      do i = 1, len_trim(input)
        if (match_pattern(input(1:i), trim(pattern))) then
          output = input(i+1:)
          return
        end if
      end do
    end if
  end subroutine

  ! Simple pattern matching (supports * and ? wildcards)
  function match_pattern(str, pattern) result(matches)
    character(len=*), intent(in) :: str, pattern
    logical :: matches
    integer :: s_pos, p_pos, s_len, p_len
    integer :: star_pos, s_star_pos

    s_len = len_trim(str)
    p_len = len_trim(pattern)
    s_pos = 1
    p_pos = 1
    star_pos = 0
    s_star_pos = 0

    do while (s_pos <= s_len)
      if (p_pos <= p_len) then
        if (pattern(p_pos:p_pos) == '*') then
          ! Found *, record position and try to match rest
          star_pos = p_pos
          s_star_pos = s_pos
          p_pos = p_pos + 1
          cycle
        else if (pattern(p_pos:p_pos) == '?' .or. pattern(p_pos:p_pos) == str(s_pos:s_pos)) then
          ! Match single character
          p_pos = p_pos + 1
          s_pos = s_pos + 1
          cycle
        end if
      end if

      ! No match, backtrack if we had a *
      if (star_pos > 0) then
        p_pos = star_pos + 1
        s_star_pos = s_star_pos + 1
        s_pos = s_star_pos
      else
        matches = .false.
        return
      end if
    end do

    ! Check remaining pattern for trailing *
    do while (p_pos <= p_len .and. pattern(p_pos:p_pos) == '*')
      p_pos = p_pos + 1
    end do

    matches = (p_pos > p_len)
  end function

  ! ============================================================================
  ! Arithmetic Expansion: $((expression))
  ! Comprehensive arithmetic evaluator with full operator support
  ! ============================================================================

  ! Note: This version doesn't have shell context - used when called from parser
  function arithmetic_expansion(expression) result(result_value)
    character(len=*), intent(in) :: expression
    character(len=32) :: result_value
    character(len=512) :: expr
    integer(kind=8) :: result_int

    result_value = '0'

    ! Remove $(( and ))
    if (len_trim(expression) < 6) return
    expr = adjustl(expression(4:len_trim(expression)-2))

    ! Evaluate the arithmetic expression (without shell context for variable resolution)
    result_int = eval_expression(trim(expr))
    write(result_value, '(I0)') result_int
  end function

  ! Version with shell context for variable resolution
  function arithmetic_expansion_shell(expression, shell) result(result_value)
    character(len=*), intent(in) :: expression
    type(shell_state_t), intent(inout) :: shell
    character(len=32) :: result_value
    character(len=512) :: expr
    integer(kind=8) :: result_int

    result_value = '0'

    ! Remove $(( and ))
    if (len_trim(expression) < 6) return
    expr = adjustl(expression(4:len_trim(expression)-2))

    ! Evaluate with shell context for variable resolution
    result_int = eval_expression_shell(trim(expr), shell)
    write(result_value, '(I0)') result_int
  end function

  ! Main expression evaluator - handles full expressions
  recursive function eval_expression(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value

    value = eval_logical_or(trim(adjustl(expr)))
  end function

  ! Logical OR (lowest precedence)
  recursive function eval_logical_or(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_logical_and(expr)

    pos = find_operator(expr, '||')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_logical_and(trim(adjustl(left_expr)))
      right_val = eval_logical_or(trim(adjustl(right_expr)))
      if (value /= 0 .or. right_val /= 0) then
        value = 1
      else
        value = 0
      end if
    end if
  end function

  ! Logical AND
  recursive function eval_logical_and(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_bitwise_or(expr)

    pos = find_operator(expr, '&&')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_bitwise_or(trim(adjustl(left_expr)))
      right_val = eval_logical_and(trim(adjustl(right_expr)))
      if (value /= 0 .and. right_val /= 0) then
        value = 1
      else
        value = 0
      end if
    end if
  end function

  ! Bitwise OR
  recursive function eval_bitwise_or(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_bitwise_xor(expr)

    pos = find_single_operator(expr, '|')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_bitwise_xor(trim(adjustl(left_expr)))
      right_val = eval_bitwise_or(trim(adjustl(right_expr)))
      value = ior(int(value), int(right_val))
    end if
  end function

  ! Bitwise XOR
  recursive function eval_bitwise_xor(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_bitwise_and(expr)

    pos = find_single_operator(expr, '^')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_bitwise_and(trim(adjustl(left_expr)))
      right_val = eval_bitwise_xor(trim(adjustl(right_expr)))
      value = ieor(int(value), int(right_val))
    end if
  end function

  ! Bitwise AND
  recursive function eval_bitwise_and(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_equality(expr)

    pos = find_single_operator(expr, '&')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_equality(trim(adjustl(left_expr)))
      right_val = eval_bitwise_and(trim(adjustl(right_expr)))
      value = iand(int(value), int(right_val))
    end if
  end function

  ! Equality (==, !=)
  recursive function eval_equality(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! Try ==
    pos = find_operator(expr, '==')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_comparison(trim(adjustl(left_expr)))
      right_val = eval_comparison(trim(adjustl(right_expr)))
      if (value == right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    ! Try !=
    pos = find_operator(expr, '!=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_comparison(trim(adjustl(left_expr)))
      right_val = eval_comparison(trim(adjustl(right_expr)))
      if (value /= right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    value = eval_comparison(expr)
  end function

  ! Comparison (<, <=, >, >=)
  recursive function eval_comparison(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! Try <=
    pos = find_operator(expr, '<=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive(trim(adjustl(left_expr)))
      right_val = eval_additive(trim(adjustl(right_expr)))
      if (value <= right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    ! Try >=
    pos = find_operator(expr, '>=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive(trim(adjustl(left_expr)))
      right_val = eval_additive(trim(adjustl(right_expr)))
      if (value >= right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    ! Try <
    pos = find_single_operator(expr, '<')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_additive(trim(adjustl(left_expr)))
      right_val = eval_additive(trim(adjustl(right_expr)))
      if (value < right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    ! Try >
    pos = find_single_operator(expr, '>')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_additive(trim(adjustl(left_expr)))
      right_val = eval_additive(trim(adjustl(right_expr)))
      if (value > right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    value = eval_additive(expr)
  end function

  ! Addition and Subtraction
  recursive function eval_additive(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! Find rightmost + or - (to maintain left-to-right evaluation)
    pos = find_rightmost_additive(expr)

    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_additive(trim(adjustl(left_expr)))
      right_val = eval_multiplicative(trim(adjustl(right_expr)))

      if (expr(pos:pos) == '+') then
        value = value + right_val
      else
        value = value - right_val
      end if
    else
      value = eval_multiplicative(expr)
    end if
  end function

  ! Multiplication, Division, Modulo
  recursive function eval_multiplicative(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr
    character :: op

    ! Find rightmost *, /, or %
    pos = find_rightmost_multiplicative(expr, op)

    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_multiplicative(trim(adjustl(left_expr)))
      right_val = eval_power(trim(adjustl(right_expr)))

      select case (op)
      case ('*')
        value = value * right_val
      case ('/')
        if (right_val /= 0) then
          value = value / right_val
        else
          value = 0  ! Division by zero
        end if
      case ('%')
        if (right_val /= 0) then
          value = mod(value, right_val)
        else
          value = 0  ! Modulo by zero
        end if
      end select
    else
      value = eval_power(expr)
    end if
  end function

  ! Exponentiation (**)
  recursive function eval_power(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, exponent
    integer :: pos, i
    character(len=512) :: base_expr, exp_expr

    pos = find_operator(expr, '**')
    if (pos > 0) then
      base_expr = expr(:pos-1)
      exp_expr = expr(pos+2:)
      value = eval_unary(trim(adjustl(base_expr)))
      exponent = eval_power(trim(adjustl(exp_expr)))  ! Right-associative

      ! Calculate power
      if (exponent < 0) then
        value = 0  ! Integer division for negative exponents
      else if (exponent == 0) then
        value = 1
      else
        do i = 2, int(exponent)
          value = value * eval_unary(trim(adjustl(base_expr)))
        end do
      end if
    else
      value = eval_unary(expr)
    end if
  end function

  ! Unary operators (!, -, +)
  recursive function eval_unary(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value
    character(len=512) :: rest

    if (len_trim(expr) == 0) then
      value = 0
      return
    end if

    ! Logical NOT
    if (expr(1:1) == '!') then
      rest = adjustl(expr(2:))
      value = eval_unary(rest)
      if (value == 0) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    ! Unary minus
    if (expr(1:1) == '-' .and. len_trim(expr) > 1) then
      rest = adjustl(expr(2:))
      value = -eval_unary(rest)
      return
    end if

    ! Unary plus
    if (expr(1:1) == '+' .and. len_trim(expr) > 1) then
      rest = adjustl(expr(2:))
      value = eval_unary(rest)
      return
    end if

    value = eval_primary(expr)
  end function

  ! Primary expressions (numbers, variables, parentheses)
  function eval_primary(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value
    character(len=512) :: inner_expr, temp_expr
    integer :: iostat, paren_end

    if (len_trim(expr) == 0) then
      value = 0
      return
    end if

    ! Handle parentheses
    if (expr(1:1) == '(') then
      paren_end = find_matching_paren(expr, 1)
      if (paren_end > 1) then
        inner_expr = expr(2:paren_end-1)
        value = eval_expression(trim(adjustl(inner_expr)))
        return
      end if
    end if

    ! Try to parse as number
    temp_expr = trim(adjustl(expr))
    read(temp_expr, *, iostat=iostat) value
    if (iostat == 0) return

    ! Variable without shell context - return 0
    value = 0
  end function

  ! ============================================================================
  ! Shell-aware arithmetic evaluation (with variable resolution)
  ! ============================================================================

  recursive function eval_expression_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value
    ! Assignment operators have lowest precedence
    value = eval_assignment_shell(trim(adjustl(expr)), shell)
  end function

  ! Assignment operators (=, +=, -=, *=, /=, %=)
  recursive function eval_assignment_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val, current_val
    integer :: pos, op_len, iostat
    character(len=512) :: var_name, right_expr, var_value_str
    character(len=1024) :: temp_value

    ! Check for assignment operators (right-to-left associative, so find rightmost)
    pos = find_rightmost_assignment(expr, op_len)

    if (pos > 0) then
      ! Extract variable name (left side) and expression (right side)
      var_name = trim(adjustl(expr(:pos-1)))
      right_expr = expr(pos+op_len:)

      ! Evaluate right side
      right_val = eval_assignment_shell(trim(adjustl(right_expr)), shell)

      ! Determine which operator and perform operation
      if (op_len == 1) then
        ! Simple assignment: =
        value = right_val
      else
        ! Compound assignment - get current value
        temp_value = get_shell_variable(shell, trim(var_name))
        if (len_trim(temp_value) > 0) then
          read(temp_value, *, iostat=iostat) current_val
          if (iostat /= 0) current_val = 0
        else
          current_val = 0
        end if

        ! Apply compound operator
        select case (expr(pos:pos+op_len-1))
        case ('+=')
          value = current_val + right_val
        case ('-=')
          value = current_val - right_val
        case ('*=')
          value = current_val * right_val
        case ('/=')
          if (right_val /= 0) then
            value = current_val / right_val
          else
            value = 0
          end if
        case ('%=')
          if (right_val /= 0) then
            value = mod(current_val, right_val)
          else
            value = 0
          end if
        case default
          value = right_val
        end select
      end if

      ! Set the variable
      write(var_value_str, '(I0)') value
      call set_shell_variable(shell, trim(var_name), trim(var_value_str))
    else
      ! No assignment, evaluate as logical OR
      value = eval_logical_or_shell(expr, shell)
    end if
  end function

  ! Helper function to find leftmost assignment operator (for right-associativity)
  function find_rightmost_assignment(expr, op_len) result(pos)
    character(len=*), intent(in) :: expr
    integer, intent(out) :: op_len
    integer :: pos, i, paren_depth

    pos = 0
    op_len = 0
    paren_depth = 0

    ! Scan from left to right, tracking parentheses
    ! This gives right-associativity: a=b=c becomes a=(b=c)
    do i = 1, len_trim(expr)
      if (expr(i:i) == '(') then
        paren_depth = paren_depth + 1
      else if (expr(i:i) == ')') then
        paren_depth = paren_depth - 1
      else if (paren_depth == 0) then
        ! Check for compound assignment operators (2 chars)
        if (i < len_trim(expr)) then
          if (expr(i:i+1) == '+=' .or. expr(i:i+1) == '-=' .or. &
              expr(i:i+1) == '*=' .or. expr(i:i+1) == '/=' .or. &
              expr(i:i+1) == '%=') then
            pos = i
            op_len = 2
            return
          end if
        end if
        ! Check for simple assignment (but not ==, !=, <=, >=)
        if (expr(i:i) == '=') then
          ! Check it's not a comparison operator
          if (i > 1) then
            if (expr(i-1:i-1) == '=' .or. expr(i-1:i-1) == '!' .or. &
                expr(i-1:i-1) == '<' .or. expr(i-1:i-1) == '>') then
              cycle  ! Skip this =, it's part of a comparison
            end if
          end if
          if (i < len_trim(expr)) then
            if (expr(i+1:i+1) == '=') then
              cycle  ! Skip this =, it's part of ==
            end if
          end if
          pos = i
          op_len = 1
          return
        end if
      end if
    end do
  end function

  recursive function eval_logical_or_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_logical_and_shell(expr, shell)
    pos = find_operator(expr, '||')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_logical_and_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_logical_or_shell(trim(adjustl(right_expr)), shell)
      if (value /= 0 .or. right_val /= 0) then
        value = 1
      else
        value = 0
      end if
    end if
  end function

  recursive function eval_logical_and_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_bitwise_or_shell(expr, shell)
    pos = find_operator(expr, '&&')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_bitwise_or_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_logical_and_shell(trim(adjustl(right_expr)), shell)
      if (value /= 0 .and. right_val /= 0) then
        value = 1
      else
        value = 0
      end if
    end if
  end function

  recursive function eval_bitwise_or_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_bitwise_xor_shell(expr, shell)
    pos = find_single_operator(expr, '|')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_bitwise_xor_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_bitwise_or_shell(trim(adjustl(right_expr)), shell)
      value = ior(int(value), int(right_val))
    end if
  end function

  recursive function eval_bitwise_xor_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_bitwise_and_shell(expr, shell)
    pos = find_single_operator(expr, '^')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_bitwise_and_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_bitwise_xor_shell(trim(adjustl(right_expr)), shell)
      value = ieor(int(value), int(right_val))
    end if
  end function

  recursive function eval_bitwise_and_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    value = eval_equality_shell(expr, shell)
    pos = find_single_operator(expr, '&')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_equality_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_bitwise_and_shell(trim(adjustl(right_expr)), shell)
      value = iand(int(value), int(right_val))
    end if
  end function

  recursive function eval_equality_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    pos = find_operator(expr, '==')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_comparison_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_comparison_shell(trim(adjustl(right_expr)), shell)
      if (value == right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    pos = find_operator(expr, '!=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_comparison_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_comparison_shell(trim(adjustl(right_expr)), shell)
      if (value /= right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    value = eval_comparison_shell(expr, shell)
  end function

  recursive function eval_comparison_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    pos = find_operator(expr, '<=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_additive_shell(trim(adjustl(right_expr)), shell)
      if (value <= right_val) then; value = 1; else; value = 0; end if
      return
    end if

    pos = find_operator(expr, '>=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_additive_shell(trim(adjustl(right_expr)), shell)
      if (value >= right_val) then; value = 1; else; value = 0; end if
      return
    end if

    pos = find_single_operator(expr, '<')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_additive_shell(trim(adjustl(right_expr)), shell)
      if (value < right_val) then; value = 1; else; value = 0; end if
      return
    end if

    pos = find_single_operator(expr, '>')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_additive_shell(trim(adjustl(right_expr)), shell)
      if (value > right_val) then; value = 1; else; value = 0; end if
      return
    end if

    value = eval_additive_shell(expr, shell)
  end function

  recursive function eval_additive_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    pos = find_rightmost_additive(expr)
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_multiplicative_shell(trim(adjustl(right_expr)), shell)
      if (expr(pos:pos) == '+') then
        value = value + right_val
      else
        value = value - right_val
      end if
    else
      value = eval_multiplicative_shell(expr, shell)
    end if
  end function

  recursive function eval_multiplicative_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr
    character :: op

    pos = find_rightmost_multiplicative(expr, op)
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_multiplicative_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_power_shell(trim(adjustl(right_expr)), shell)
      select case (op)
      case ('*'); value = value * right_val
      case ('/')
        if (right_val /= 0) then; value = value / right_val; else; value = 0; end if
      case ('%')
        if (right_val /= 0) then; value = mod(value, right_val); else; value = 0; end if
      end select
    else
      value = eval_power_shell(expr, shell)
    end if
  end function

  recursive function eval_power_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, exponent, base_val
    integer :: pos, i
    character(len=512) :: base_expr, exp_expr

    pos = find_operator(expr, '**')
    if (pos > 0) then
      base_expr = expr(:pos-1)
      exp_expr = expr(pos+2:)
      base_val = eval_unary_shell(trim(adjustl(base_expr)), shell)
      exponent = eval_power_shell(trim(adjustl(exp_expr)), shell)
      if (exponent < 0) then; value = 0
      else if (exponent == 0) then; value = 1
      else
        value = base_val
        do i = 2, int(exponent)
          value = value * base_val
        end do
      end if
    else
      value = eval_unary_shell(expr, shell)
    end if
  end function

  recursive function eval_unary_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, current_val
    character(len=512) :: rest, var_name, var_value_str
    character(len=1024) :: temp_value
    integer :: iostat

    if (len_trim(expr) == 0) then; value = 0; return; end if

    ! Pre-increment: ++x
    if (len_trim(expr) > 2 .and. expr(1:2) == '++') then
      var_name = trim(adjustl(expr(3:)))
      ! Get current value
      temp_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(temp_value) > 0) then
        read(temp_value, *, iostat=iostat) current_val
        if (iostat /= 0) current_val = 0
      else
        current_val = 0
      end if
      ! Increment
      value = current_val + 1
      ! Set variable
      write(var_value_str, '(I0)') value
      call set_shell_variable(shell, trim(var_name), trim(var_value_str))
      return
    end if

    ! Pre-decrement: --x
    if (len_trim(expr) > 2 .and. expr(1:2) == '--') then
      var_name = trim(adjustl(expr(3:)))
      ! Get current value
      temp_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(temp_value) > 0) then
        read(temp_value, *, iostat=iostat) current_val
        if (iostat /= 0) current_val = 0
      else
        current_val = 0
      end if
      ! Decrement
      value = current_val - 1
      ! Set variable
      write(var_value_str, '(I0)') value
      call set_shell_variable(shell, trim(var_name), trim(var_value_str))
      return
    end if

    if (expr(1:1) == '!') then
      rest = adjustl(expr(2:))
      value = eval_unary_shell(rest, shell)
      if (value == 0) then; value = 1; else; value = 0; end if
      return
    end if

    if (expr(1:1) == '-' .and. len_trim(expr) > 1) then
      rest = adjustl(expr(2:))
      value = -eval_unary_shell(rest, shell)
      return
    end if

    if (expr(1:1) == '+' .and. len_trim(expr) > 1) then
      rest = adjustl(expr(2:))
      value = eval_unary_shell(rest, shell)
      return
    end if

    value = eval_primary_shell(expr, shell)
  end function

  function eval_primary_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, new_val
    character(len=512) :: inner_expr, temp_expr, var_name, var_value_str
    character(len=1024) :: var_value
    integer :: iostat, paren_end, expr_len

    if (len_trim(expr) == 0) then; value = 0; return; end if

    expr_len = len_trim(expr)

    ! Check for post-increment: x++
    if (expr_len > 2 .and. expr(expr_len-1:expr_len) == '++') then
      var_name = trim(adjustl(expr(:expr_len-2)))
      ! Get current value
      var_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(var_value) > 0) then
        read(var_value, *, iostat=iostat) value
        if (iostat /= 0) value = 0
      else
        value = 0
      end if
      ! Increment and set
      new_val = value + 1
      write(var_value_str, '(I0)') new_val
      call set_shell_variable(shell, trim(var_name), trim(var_value_str))
      ! Return old value
      return
    end if

    ! Check for post-decrement: x--
    if (expr_len > 2 .and. expr(expr_len-1:expr_len) == '--') then
      var_name = trim(adjustl(expr(:expr_len-2)))
      ! Get current value
      var_value = get_shell_variable(shell, trim(var_name))
      if (len_trim(var_value) > 0) then
        read(var_value, *, iostat=iostat) value
        if (iostat /= 0) value = 0
      else
        value = 0
      end if
      ! Decrement and set
      new_val = value - 1
      write(var_value_str, '(I0)') new_val
      call set_shell_variable(shell, trim(var_name), trim(var_value_str))
      ! Return old value
      return
    end if

    ! Handle parentheses
    if (expr(1:1) == '(') then
      paren_end = find_matching_paren(expr, 1)
      if (paren_end > 1) then
        inner_expr = expr(2:paren_end-1)
        value = eval_expression_shell(trim(adjustl(inner_expr)), shell)
        return
      end if
    end if

    ! Try to parse as number
    temp_expr = trim(adjustl(expr))
    read(temp_expr, *, iostat=iostat) value
    if (iostat == 0) return

    ! Resolve as variable
    var_value = get_shell_variable(shell, trim(adjustl(expr)))
    if (len_trim(var_value) > 0) then
      read(var_value, *, iostat=iostat) value
      if (iostat == 0) return
    end if

    ! Variable not found or not numeric - return 0
    value = 0
  end function

  ! Helper: Find matching closing parenthesis
  function find_matching_paren(expr, start_pos) result(end_pos)
    character(len=*), intent(in) :: expr
    integer, intent(in) :: start_pos
    integer :: end_pos, depth, i

    depth = 0
    do i = start_pos, len_trim(expr)
      if (expr(i:i) == '(') then
        depth = depth + 1
      else if (expr(i:i) == ')') then
        depth = depth - 1
        if (depth == 0) then
          end_pos = i
          return
        end if
      end if
    end do
    end_pos = 0
  end function

  ! Helper: Find operator (2-char) outside parentheses
  function find_operator(expr, op) result(pos)
    character(len=*), intent(in) :: expr, op
    integer :: pos, i, depth

    depth = 0
    do i = 1, len_trim(expr) - len(op) + 1
      if (expr(i:i) == '(') then
        depth = depth + 1
      else if (expr(i:i) == ')') then
        depth = depth - 1
      else if (depth == 0 .and. expr(i:i+len(op)-1) == op) then
        pos = i
        return
      end if
    end do
    pos = 0
  end function

  ! Helper: Find single-char operator outside parentheses
  function find_single_operator(expr, op) result(pos)
    character(len=*), intent(in) :: expr
    character, intent(in) :: op
    integer :: pos, i, depth

    depth = 0
    do i = 1, len_trim(expr)
      if (expr(i:i) == '(') then
        depth = depth + 1
      else if (expr(i:i) == ')') then
        depth = depth - 1
      else if (depth == 0 .and. expr(i:i) == op) then
        ! Make sure it's not part of a 2-char operator
        if (i < len_trim(expr)) then
          if (op == '&' .and. expr(i+1:i+1) == '&') cycle
          if (op == '|' .and. expr(i+1:i+1) == '|') cycle
          if (op == '=' .and. expr(i+1:i+1) == '=') cycle
          if (op == '!' .and. expr(i+1:i+1) == '=') cycle
          if (op == '<' .and. (expr(i+1:i+1) == '=' .or. expr(i+1:i+1) == '<')) cycle
          if (op == '>' .and. (expr(i+1:i+1) == '=' .or. expr(i+1:i+1) == '>')) cycle
          if (op == '*' .and. expr(i+1:i+1) == '*') cycle
        end if
        if (i > 1) then
          if (op == '=' .and. (expr(i-1:i-1) == '=' .or. expr(i-1:i-1) == '!' .or. &
                               expr(i-1:i-1) == '<' .or. expr(i-1:i-1) == '>')) cycle
        end if
        pos = i
        return
      end if
    end do
    pos = 0
  end function

  ! Helper: Find rightmost +/- at depth 0
  function find_rightmost_additive(expr) result(pos)
    character(len=*), intent(in) :: expr
    integer :: pos, i, depth

    pos = 0
    depth = 0
    do i = len_trim(expr), 1, -1
      if (expr(i:i) == ')') then
        depth = depth + 1
      else if (expr(i:i) == '(') then
        depth = depth - 1
      else if (depth == 0 .and. (expr(i:i) == '+' .or. expr(i:i) == '-')) then
        ! Skip if it's part of ++ or -- (increment/decrement)
        if (i > 1 .and. expr(i-1:i) == '++') cycle
        if (i > 1 .and. expr(i-1:i) == '--') cycle
        if (i < len_trim(expr) .and. expr(i:i+1) == '++') cycle
        if (i < len_trim(expr) .and. expr(i:i+1) == '--') cycle
        ! Skip if it's part of unary operator at start
        if (i == 1) cycle
        ! Skip if previous char makes this unary
        if (expr(i-1:i-1) == '(' .or. expr(i-1:i-1) == '+' .or. &
            expr(i-1:i-1) == '-' .or. expr(i-1:i-1) == '*' .or. &
            expr(i-1:i-1) == '/' .or. expr(i-1:i-1) == '%' .or. &
            expr(i-1:i-1) == '=' .or. expr(i-1:i-1) == '!' .or. &
            expr(i-1:i-1) == '<' .or. expr(i-1:i-1) == '>' .or. &
            expr(i-1:i-1) == '&' .or. expr(i-1:i-1) == '|' .or. &
            expr(i-1:i-1) == '^') cycle
        pos = i
        return
      end if
    end do
  end function

  ! Helper: Find rightmost *,/,% at depth 0
  function find_rightmost_multiplicative(expr, op) result(pos)
    character(len=*), intent(in) :: expr
    character, intent(out) :: op
    integer :: pos, i, depth

    pos = 0
    depth = 0
    do i = len_trim(expr), 1, -1
      if (expr(i:i) == ')') then
        depth = depth + 1
      else if (expr(i:i) == '(') then
        depth = depth - 1
      else if (depth == 0) then
        if (expr(i:i) == '*' .or. expr(i:i) == '/' .or. expr(i:i) == '%') then
          ! Skip ** (power operator)
          if (expr(i:i) == '*' .and. i < len_trim(expr) .and. expr(i+1:i+1) == '*') cycle
          if (expr(i:i) == '*' .and. i > 1 .and. expr(i-1:i-1) == '*') cycle
          pos = i
          op = expr(i:i)
          return
        end if
      end if
    end do
    op = ' '
  end function

  ! Enhanced variable expansion with array and parameter support
  subroutine enhanced_expand_variables(input, expanded, shell)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(inout) :: shell

    character(len=:), allocatable :: result
    integer :: i, start_pos, end_pos, bracket_count, result_capacity, result_pos
    character(len=256) :: var_expr
    character(len=2048) :: var_value
    logical :: in_expansion, in_single_quote, in_double_quote

    ! Allocate with initial capacity
    result_capacity = len(input) * 2 + 256
    allocate(character(len=result_capacity) :: result)
    result = ''
    result_pos = 0
    i = 1
    in_single_quote = .false.
    in_double_quote = .false.

    do while (i <= len_trim(input))
      ! Handle quote characters
      if (input(i:i) == "'" .and. .not. in_double_quote) then
        ! Single quote - toggle single quote mode (not escapable)
        in_single_quote = .not. in_single_quote
        result = trim(result) // input(i:i)
        i = i + 1
        cycle
      else if (input(i:i) == '"' .and. .not. in_single_quote) then
        ! Double quote - toggle double quote mode (check for escaping)
        if (i > 1 .and. input(i-1:i-1) == '\') then
          ! Escaped double quote - already added backslash, add quote
          result(len_trim(result):len_trim(result)) = '"'
          i = i + 1
          cycle
        else
          in_double_quote = .not. in_double_quote
          result = trim(result) // input(i:i)
          i = i + 1
          cycle
        end if
      end if

      ! Skip all expansions inside single quotes
      if (in_single_quote) then
        result = trim(result) // input(i:i)
        i = i + 1
        cycle
      end if

      ! Now handle expansions (only active outside single quotes)
      if (i < len_trim(input) - 2 .and. input(i:i+2) == '$((') then
        ! Arithmetic expansion $((expr))
        start_pos = i
        bracket_count = 2
        i = i + 3
        
        do while (i <= len_trim(input) .and. bracket_count > 0)
          if (input(i:i) == '(') bracket_count = bracket_count + 1
          if (input(i:i) == ')') bracket_count = bracket_count - 1
          i = i + 1
        end do
        
        if (bracket_count == 0) then
          var_expr = input(start_pos:i-1)
          var_value = arithmetic_expansion(var_expr)
          result = trim(result) // trim(var_value)
        end if

      else if (i < len_trim(input) - 1 .and. input(i:i+1) == '$(' .and. &
               (i >= len_trim(input) - 2 .or. input(i:i+2) /= '$((')) then
        ! Command substitution $(command)
        ! NOTE: We already checked for $(( above, so this is definitely $(
        start_pos = i
        bracket_count = 1
        i = i + 2

        do while (i <= len_trim(input) .and. bracket_count > 0)
          if (input(i:i) == '(') bracket_count = bracket_count + 1
          if (input(i:i) == ')') bracket_count = bracket_count - 1
          i = i + 1
        end do

        if (bracket_count == 0) then
          ! Extract command from $( ... )
          var_expr = input(start_pos+2:i-2)  ! Skip $( and )
          call execute_command_and_capture(trim(var_expr), var_value)
          result = trim(result) // trim(var_value)
        end if

      else if (i < len_trim(input) - 1 .and. input(i:i+1) == '${') then
        ! Parameter expansion ${var}
        start_pos = i
        bracket_count = 1
        i = i + 2

        do while (i <= len_trim(input) .and. bracket_count > 0)
          if (input(i:i) == '{') bracket_count = bracket_count + 1
          if (input(i:i) == '}') bracket_count = bracket_count - 1
          i = i + 1
        end do

        if (bracket_count == 0) then
          var_expr = input(start_pos:i-1)
          write(error_unit, '(A,A,A)') 'DEBUG BEFORE CALL: var_expr=[', trim(var_expr), ']'
          var_value = parameter_expansion(shell, var_expr)
          write(error_unit, '(A,A,A)') 'DEBUG AFTER CALL: var_value=[', trim(var_value), ']'
          result = trim(result) // trim(var_value)
        end if
        
      else if (input(i:i) == '$') then
        ! Simple variable expansion $var
        start_pos = i + 1
        i = i + 1
        
        do while (i <= len_trim(input) .and. (is_alnum(input(i:i)) .or. input(i:i) == '_'))
          i = i + 1
        end do
        
        if (i > start_pos) then
          var_expr = input(start_pos:i-1)
          var_value = get_shell_variable(shell, trim(var_expr))
          result = trim(result) // trim(var_value)
        else
          result = trim(result) // '$'
        end if
        
      else
        result = trim(result) // input(i:i)
        i = i + 1
      end if
    end do
    
    expanded = trim(result)
  end subroutine

  function is_alnum(c) result(is_valid)
    character, intent(in) :: c
    logical :: is_valid
    
    is_valid = (c >= 'a' .and. c <= 'z') .or. &
               (c >= 'A' .and. c <= 'Z') .or. &
               (c >= '0' .and. c <= '9')
  end function

  ! Field splitting based on IFS
  subroutine field_split(input, ifs_chars, fields, field_count)
    character(len=*), intent(in) :: input, ifs_chars
    character(len=1024), intent(out) :: fields(:)
    integer, intent(out) :: field_count
    
    integer :: i, start_pos, field_idx
    logical :: in_field, is_ifs_char
    character(len=1024) :: current_field
    
    field_count = 0
    field_idx = 1
    start_pos = 1
    in_field = .false.
    current_field = ''
    
    ! Handle empty input
    if (len_trim(input) == 0) then
      return
    end if
    
    do i = 1, len_trim(input)
      is_ifs_char = index(ifs_chars, input(i:i)) > 0
      
      if (.not. is_ifs_char) then
        ! Non-IFS character
        if (.not. in_field) then
          ! Start of new field
          in_field = .true.
          start_pos = i
          current_field = input(i:i)
        else
          ! Continue current field
          current_field = trim(current_field) // input(i:i)
        end if
      else
        ! IFS character - end current field if we were in one
        if (in_field) then
          if (field_idx <= size(fields)) then
            fields(field_idx) = trim(current_field)
            field_idx = field_idx + 1
            field_count = field_count + 1
          end if
          in_field = .false.
          current_field = ''
        end if
      end if
    end do
    
    ! Handle last field if we ended in one
    if (in_field .and. field_idx <= size(fields)) then
      fields(field_idx) = trim(current_field)
      field_count = field_count + 1
    end if
    
    ! If no fields were created but input wasn't empty, create one field
    if (field_count == 0 .and. len_trim(input) > 0) then
      fields(1) = trim(input)
      field_count = 1
    end if
  end subroutine
  
  ! Word splitting for unquoted variable expansions
  subroutine word_split(shell, input, words, word_count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input
    character(len=1024), intent(out) :: words(:)
    integer, intent(out) :: word_count
    
    character(len=256) :: ifs_to_use
    
    ! Use shell's IFS or default
    if (len_trim(shell%ifs) > 0) then
      ifs_to_use = trim(shell%ifs)
    else
      ifs_to_use = ' '//char(9)//char(10)  ! space, tab, newline
    end if
    
    call field_split(input, trim(ifs_to_use), words, word_count)
  end subroutine

  ! Quote removal - removes outer quotes from strings
  function remove_quotes(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)) :: output
    integer :: len_input
    
    len_input = len_trim(input)
    output = input
    
    if (len_input < 2) return
    
    ! Remove single quotes
    if (input(1:1) == "'" .and. input(len_input:len_input) == "'") then
      if (len_input == 2) then
        output = ''
      else
        output = input(2:len_input-1)
      end if
      return
    end if
    
    ! Remove double quotes (but preserve escaped characters inside)
    if (input(1:1) == '"' .and. input(len_input:len_input) == '"') then
      if (len_input == 2) then
        output = ''
      else
        output = input(2:len_input-1)
        ! TODO: Process escape sequences within double quotes
      end if
      return
    end if
  end function
  
  ! Brace expansion - expands braces to multiple words
  ! Examples:
  !   {a,b,c} → a b c
  !   {1..5} → 1 2 3 4 5
  !   {a..e} → a b c d e
  !   {1..10..2} → 1 3 5 7 9
  !   file{1,2,3}.txt → file1.txt file2.txt file3.txt (prefix/suffix support)
  !   {A,B{1,2},C} → A B{1,2} C (respects nested braces)
  function expand_braces(word) result(expanded)
    character(*), intent(in) :: word
    character(len=:), allocatable :: expanded
    integer :: brace_start, brace_end, dot_pos, depth, pos
    character(len=:), allocatable :: prefix, brace_content, suffix, item
    character(1024) :: result_buf
    integer :: i, start_val, end_val, step_val, current_val
    integer :: start_char, end_char, current_char
    integer :: last_pos, second_dot
    logical :: is_numeric, is_alpha, has_step, found_comma
    character(16) :: num_str
    character(len=:), allocatable :: start_str, end_str, step_str

    expanded = word
    result_buf = ''

    ! Find opening brace
    brace_start = index(word, '{')
    if (brace_start == 0) return

    ! Find MATCHING closing brace by counting depth (supports nested braces)
    depth = 0
    brace_end = 0
    do pos = brace_start, len_trim(word)
      if (word(pos:pos) == '{') then
        depth = depth + 1
      else if (word(pos:pos) == '}') then
        depth = depth - 1
        if (depth == 0) then
          brace_end = pos
          exit
        end if
      end if
    end do

    if (brace_end == 0) return

    ! Extract prefix, brace content, and suffix
    if (brace_start > 1) then
      prefix = word(1:brace_start-1)
    else
      prefix = ''
    end if

    brace_content = word(brace_start+1:brace_end-1)

    if (brace_end < len_trim(word)) then
      suffix = word(brace_end+1:)
    else
      suffix = ''
    end if

    if (len_trim(brace_content) == 0) return

    ! Check if it's a range expansion (contains ..)
    dot_pos = index(brace_content, '..')
    if (dot_pos > 0) then
      ! Range expansion: {start..end} or {start..end..step}

      ! Extract start
      start_str = brace_content(1:dot_pos-1)

      ! Check for step (second ..)
      second_dot = index(brace_content(dot_pos+2:), '..')
      has_step = (second_dot > 0)

      if (has_step) then
        ! {start..end..step}
        second_dot = dot_pos + 1 + second_dot
        end_str = brace_content(dot_pos+2:second_dot-1)
        step_str = brace_content(second_dot+2:)
        read(step_str, *, iostat=i) step_val
        if (i /= 0) then
          step_val = 1
        end if
      else
        ! {start..end}
        end_str = brace_content(dot_pos+2:)
        step_val = 1
      end if

      ! Check if numeric or alphabetic
      is_numeric = .false.
      is_alpha = .false.

      read(start_str, *, iostat=i) start_val
      if (i == 0) then
        ! Numeric range
        read(end_str, *, iostat=i) end_val
        if (i == 0) then
          is_numeric = .true.
        end if
      end if

      if (.not. is_numeric .and. len_trim(start_str) == 1 .and. len_trim(end_str) == 1) then
        ! Alphabetic range
        start_char = ichar(start_str(1:1))
        end_char = ichar(end_str(1:1))
        is_alpha = .true.
      end if

      if (is_numeric) then
        ! Numeric range expansion
        if (start_val <= end_val) then
          current_val = start_val
          do while (current_val <= end_val)
            write(num_str, '(i15)') current_val
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(num_str) // trim(suffix)
            else
              result_buf = trim(prefix) // trim(num_str) // trim(suffix)
            end if
            current_val = current_val + step_val
          end do
        else
          ! Descending range
          current_val = start_val
          do while (current_val >= end_val)
            write(num_str, '(i15)') current_val
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(num_str) // trim(suffix)
            else
              result_buf = trim(prefix) // trim(num_str) // trim(suffix)
            end if
            current_val = current_val - step_val
          end do
        end if
        expanded = trim(result_buf)
        ! Recursively expand if result still contains braces
        if (index(expanded, '{') > 0) then
          expanded = recursive_expand_all_braces(expanded)
        end if
        return
      else if (is_alpha) then
        ! Alphabetic range expansion
        if (start_char <= end_char) then
          current_char = start_char
          do while (current_char <= end_char)
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // char(current_char) // trim(suffix)
            else
              result_buf = trim(prefix) // char(current_char) // trim(suffix)
            end if
            current_char = current_char + step_val
          end do
        else
          ! Descending range
          current_char = start_char
          do while (current_char >= end_char)
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // char(current_char) // trim(suffix)
            else
              result_buf = trim(prefix) // char(current_char) // trim(suffix)
            end if
            current_char = current_char - step_val
          end do
        end if
        expanded = trim(result_buf)
        return
      end if
    else
      ! List expansion: {a,b,c} - respect nested braces when finding commas
      ! Only expand if there's at least one comma at depth 0
      found_comma = .false.
      last_pos = 1
      depth = 0
      do i = 1, len_trim(brace_content)
        if (brace_content(i:i) == '{') then
          depth = depth + 1
        else if (brace_content(i:i) == '}') then
          depth = depth - 1
        else if (brace_content(i:i) == ',' .and. depth == 0) then
          ! Found a comma at depth 0 - extract item
          found_comma = .true.
          item = brace_content(last_pos:i-1)
          if (len_trim(result_buf) > 0) then
            result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(item) // trim(suffix)
          else
            result_buf = trim(prefix) // trim(item) // trim(suffix)
          end if
          last_pos = i + 1
        end if
      end do

      ! Only expand if we found at least one comma
      if (.not. found_comma) then
        ! No comma found - not a valid brace expansion, return unchanged
        return
      end if

      ! Don't forget last item
      item = brace_content(last_pos:)
      if (len_trim(result_buf) > 0) then
        result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(item) // trim(suffix)
      else
        result_buf = trim(prefix) // trim(item) // trim(suffix)
      end if
      expanded = trim(result_buf)
      ! Recursively expand if result still contains braces
      if (index(expanded, '{') > 0) then
        expanded = recursive_expand_all_braces(expanded)
      end if
      return
    end if

  end function expand_braces

  ! Helper function to recursively expand all braces in space-separated results
  function recursive_expand_all_braces(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    ! Use allocatable array to avoid static storage
    character(len=1024), allocatable :: words(:)
    character(len=1024) :: temp_result
    integer :: word_count, i, j, out_pos, capacity
    character(len=:), allocatable :: final_result
    integer :: final_result_capacity, final_result_len
    character(len=:), allocatable :: temp_piece

    ! Allocate initial array
    allocate(words(20))  ! Start with reasonable size
    capacity = 20

    ! Allocate final_result buffer to avoid stack allocation
    final_result_capacity = max(512, len(input) * 2)
    allocate(character(len=final_result_capacity) :: final_result)
    final_result_len = 0

    ! Split by spaces
    word_count = 0
    j = 1
    out_pos = 1
    do i = 1, len_trim(input)
      if (input(i:i) == ' ') then
        if (out_pos > 1) then
          word_count = word_count + 1
          ! Grow array if needed
          if (word_count > capacity) then
            call grow_expansion_array(words, capacity)
          end if
          words(word_count) = temp_result(:out_pos-1)
          out_pos = 1
        end if
      else
        temp_result(out_pos:out_pos) = input(i:i)
        out_pos = out_pos + 1
      end if
    end do
    ! Don't forget last word
    if (out_pos > 1) then
      word_count = word_count + 1
      ! Grow array if needed
      if (word_count > capacity) then
        call grow_expansion_array(words, capacity)
      end if
      words(word_count) = temp_result(:out_pos-1)
    end if

    ! Recursively expand each word and recombine
    do i = 1, word_count
      if (index(words(i), '{') > 0) then
        ! Still has braces - recurse
        temp_result = expand_braces(trim(words(i)))
        if (final_result_len > 0) then
          temp_piece = ' ' // trim(temp_result)
        else
          temp_piece = trim(temp_result)
        end if
      else
        ! No braces - use as-is
        if (final_result_len > 0) then
          temp_piece = ' ' // trim(words(i))
        else
          temp_piece = trim(words(i))
        end if
      end if

      ! Grow buffer if needed
      if (final_result_len + len(temp_piece) > final_result_capacity) then
        call grow_string_buffer_exp(final_result, final_result_capacity, &
                                     max(final_result_capacity * 2, final_result_len + len(temp_piece) + 256), &
                                     final_result_len)
      end if

      ! Append the piece
      final_result(final_result_len+1:final_result_len+len(temp_piece)) = temp_piece
      final_result_len = final_result_len + len(temp_piece)
    end do

    output = final_result(:final_result_len)

    ! Clean up allocatable arrays
    if (allocated(words)) deallocate(words)
    if (allocated(final_result)) deallocate(final_result)
    if (allocated(temp_piece)) deallocate(temp_piece)
  end function recursive_expand_all_braces

  ! Helper subroutine to grow expansion array
  subroutine grow_expansion_array(array, current_size)
    character(len=1024), allocatable, intent(inout) :: array(:)
    integer, intent(inout) :: current_size
    character(len=1024), allocatable :: new_array(:)
    integer :: new_size

    new_size = current_size * 2
    allocate(new_array(new_size))

    ! Copy existing data
    new_array(1:current_size) = array(1:current_size)

    ! Swap arrays
    call move_alloc(new_array, array)
    current_size = new_size
  end subroutine

  ! Tilde expansion - expands ~ to home directory
  subroutine tilde_expansion(shell, input, output)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: output
    character(len=1024) :: home_dir
    character(len=:), allocatable :: env_home
    integer :: tilde_pos, slash_pos

    output = input

    ! Find tilde at start of word
    tilde_pos = 1
    if (len_trim(input) == 0 .or. input(1:1) /= '~') return

    ! Get home directory
    env_home = get_environment_var('HOME')
    if (allocated(env_home) .and. len(env_home) > 0) then
      home_dir = env_home
    else
      home_dir = '/home/' // trim(shell%username)
    end if

    if (len_trim(input) == 1) then
      ! Just ~
      output = trim(home_dir)
    else if (input(2:2) == '/') then
      ! ~/path
      output = trim(home_dir) // input(2:)
    else if (input(2:2) == ' ' .or. input(2:2) == char(9)) then
      ! ~ followed by whitespace
      output = trim(home_dir) // input(2:)
    else
      ! ~username - not implemented, leave as-is
      ! TODO: Implement ~username expansion using getpwnam()
      return
    end if
  end subroutine
  
  ! Complete word expansion including all POSIX expansions
  ! Order follows POSIX standard:
  !   1. Brace expansion
  !   2. Tilde expansion
  !   3. Parameter and variable expansion
  !   4. Quote removal
  !   5. Field splitting
  subroutine expand_word(shell, input, expanded_words, word_count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input
    character(len=1024), intent(out) :: expanded_words(:)
    integer, intent(out) :: word_count

    character(len=:), allocatable :: temp_result, brace_expanded
    character(len=1024) :: tilde_expanded, quote_removed
    integer :: i

    word_count = 1

    ! Step 0: Brace expansion (happens FIRST, before all other expansions)
    brace_expanded = expand_braces(input)

    ! Step 1: Tilde expansion
    call tilde_expansion(shell, brace_expanded, tilde_expanded)

    ! Step 2: Parameter and variable expansion
    call enhanced_expand_variables(tilde_expanded, temp_result, shell)

    ! Step 3: Quote removal
    quote_removed = remove_quotes(temp_result)

    ! Step 4: Field splitting (if not quoted)
    ! TODO: Track whether original input was quoted to skip field splitting
    call word_split(shell, quote_removed, expanded_words, word_count)

    ! If no words resulted, return the processed result as single word
    if (word_count == 0) then
      word_count = 1
      expanded_words(1) = quote_removed
    end if
  end subroutine

  ! Helper to grow an allocatable string buffer
  subroutine grow_string_buffer_exp(buffer, old_capacity, new_capacity, content_len)
    character(len=:), allocatable, intent(inout) :: buffer
    integer, intent(inout) :: old_capacity
    integer, intent(in) :: new_capacity
    integer, intent(in) :: content_len  ! Actual used length of buffer
    character(len=:), allocatable :: temp

    ! Validate content_len
    if (content_len < 0 .or. content_len > old_capacity) then
      ! Invalid content length - this is a bug, but don't crash
      if (allocated(buffer)) deallocate(buffer)
      allocate(character(len=new_capacity) :: buffer)
      buffer = ''
      old_capacity = new_capacity
      return
    end if

    ! Allocate temp buffer and copy only actual content
    allocate(character(len=new_capacity) :: temp)
    temp = ''  ! Initialize entire buffer to prevent heap corruption

    if (allocated(buffer) .and. content_len > 0) then
      ! Only copy the actual content (content_len bytes), not uninitialized data
      temp(1:content_len) = buffer(1:content_len)
      deallocate(buffer)
    end if

    ! Allocate new larger buffer
    allocate(character(len=new_capacity) :: buffer)
    buffer = ''  ! Initialize entire buffer
    if (content_len > 0) then
      buffer(1:content_len) = temp(1:content_len)
    end if
    old_capacity = new_capacity

    deallocate(temp)
  end subroutine

end module expansion