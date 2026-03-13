! ==============================================================================
! Module: expansion
! Purpose: Parameter expansion and arithmetic operations
! ==============================================================================
module expansion
  use shell_types
  use variables  ! includes check_nounset
  use command_capture, only: execute_command_and_capture
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000

  ! Arithmetic error tracking
  logical :: arithmetic_error = .false.
  character(len=256) :: arithmetic_error_msg = ''

contains

  ! Parameter expansion: ${var:offset:length}
  function parameter_expansion(shell, expression) result(expanded)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: expression
    character(len=:), allocatable :: expanded

    character(len=256) :: var_name, operation, param1, param2, replacement
    character(len=32) :: num_buf
    character(len=:), allocatable :: pattern
    character(len=:), allocatable :: var_value
    integer :: colon_pos, dash_pos, plus_pos, percent_pos, hash_pos, slash_pos, equals_pos, question_pos
    integer :: offset, length, i, at_pos
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

        ! Strip quotes from array subscript (bash strips quotes)
        call strip_quotes(array_key)

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
            write(num_buf, '(I0)') num_keys
            expanded = trim(num_buf)
            return
          else if (is_all_expansion) then
            ! ${array[@]} - return all values
            ! Get all keys, then get value for each key
            allocate(keys(50))
            call get_assoc_array_keys(shell, trim(array_name), keys, num_keys)
            expanded = ''
            do j = 1, min(num_keys, 50)
              var_value = get_assoc_array_value(shell, trim(array_name), trim(keys(j)))
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
    !     write(error_unit, '(A,A,A,I0)') 'DEBUG AFTER OPS: var_name=[', trim(var_name), '] dash_pos=', dash_pos

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

        ! Check for anchor prefix in pattern
        if (len_trim(pattern) > 0 .and. pattern(1:1) == '#') then
          ! Anchored at start: ${var/#pat/repl}
          pattern = pattern(2:)
          if (len_trim(pattern) == 0) then
            ! Empty pattern with # anchor: prepend replacement
            expanded = trim(replacement) // trim(var_value)
          else if (len_trim(var_value) >= len_trim(pattern) .and. &
                   var_value(1:len_trim(pattern)) == trim(pattern)) then
            expanded = trim(replacement) // var_value(len_trim(pattern)+1:len_trim(var_value))
          else
            expanded = var_value
          end if
        else if (len_trim(pattern) > 0 .and. pattern(1:1) == '%') then
          ! Anchored at end: ${var/%pat/repl}
          pattern = pattern(2:)
          if (len_trim(pattern) == 0) then
            ! Empty pattern with % anchor: append replacement
            expanded = trim(var_value) // trim(replacement)
          else if (len_trim(var_value) >= len_trim(pattern) .and. &
                   var_value(len_trim(var_value)-len_trim(pattern)+1:len_trim(var_value)) == &
                   trim(pattern)) then
            expanded = var_value(1:len_trim(var_value)-len_trim(pattern)) // trim(replacement)
          else
            expanded = var_value
          end if
        else
          call pattern_replace(trim(var_value), trim(pattern), trim(replacement), &
                              replace_all, expanded)
        end if
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
      ! Expand simple $var in pattern
      if (len_trim(pattern) >= 1 .and. pattern(1:1) == '$') then
        if (len_trim(pattern) >= 2) then
          if (pattern(2:2) /= '{' .and. pattern(2:2) /= '(') then
            pattern = get_shell_variable(shell, trim(pattern(2:)))
          end if
        end if
      end if
      call remove_suffix(trim(var_value), trim(pattern), greedy, expanded)
      return
    end if

    ! Prefix removal: ${var#pattern} or ${var##pattern}
    ! But first check if it's ${#var} (length)
    if (hash_pos == 1) then
      ! Check if this is just ${#} (number of positional params)
      if (len_trim(var_name) == 1) then
        ! ${#} alone - return number of positional parameters
        write(num_buf, '(I0)') shell%num_positional
        expanded = trim(num_buf)
        return
      else if (len_trim(var_name) > 1) then
        ! ${#var} length expansion
        operation = var_name(2:)

        ! Check for special parameters
        if (trim(operation) == '@' .or. trim(operation) == '*') then
          ! ${#@} or ${#*} - return number of positional parameters
          write(num_buf, '(I0)') shell%num_positional
          expanded = trim(num_buf)
          return
        else if (len(trim(operation)) > 0) then
          ! Check if it's a positional parameter (digit)
          read(operation, *, iostat=i) j
          if (i == 0 .and. j > 0) then
            ! ${#1}, ${#2}, etc. - return length of specific positional parameter
            if (j <= shell%num_positional) then
              write(num_buf, '(I0)') len_trim(shell%positional_params(j)%str)
              expanded = trim(num_buf)
            else
              expanded = '0'
            end if
            return
          else
            ! Regular variable length
            var_value = get_shell_variable(shell, trim(operation))
            write(num_buf, '(I0)') len_trim(var_value)
            expanded = trim(num_buf)
            return
          end if
        end if
      end if
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
      ! Expand simple $var in pattern
      if (len_trim(pattern) >= 1 .and. pattern(1:1) == '$') then
        if (len_trim(pattern) >= 2) then
          if (pattern(2:2) /= '{' .and. pattern(2:2) /= '(') then
            pattern = get_shell_variable(shell, trim(pattern(2:)))
          end if
        end if
      end if
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
            read(param1, *, iostat=i) offset
            if (i /= 0) offset = 0
            ! Handle negative offsets (count from end)
            if (offset < 0) offset = len_trim(var_value) + offset
            if (offset < 0) offset = 0
            if (len_trim(param2) > 0) then
              read(param2, *, iostat=i) length
              if (i /= 0) length = 0
              if (offset < len_trim(var_value)) then
                i = min(length, len_trim(var_value) - offset)
                expanded = var_value(offset+1:offset+i)
              end if
            else
              if (offset < len_trim(var_value)) then
                expanded = var_value(offset+1:len_trim(var_value))
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
    !       write(error_unit, '(A,I0,A,I0,A,I0,A,I0)') 'DEBUG: dash=', dash_pos, &
    !        ' plus=', plus_pos, ' eq=', equals_pos, ' q=', question_pos

      ! Determine which operator we have
      if (dash_pos > 0 .and. (plus_pos == 0 .or. dash_pos < plus_pos) .and. &
          (equals_pos == 0 .or. dash_pos < equals_pos) .and. (question_pos == 0 .or. dash_pos < question_pos)) then
        ! Dash operator
    !         write(error_unit, '(A)') 'DEBUG: Entering dash operator handler'
        has_colon = (dash_pos > 1 .and. var_name(dash_pos-1:dash_pos-1) == ':')
        if (has_colon) then
          operation = var_name(:dash_pos-2)
          param1 = var_name(dash_pos+1:)
        else
          operation = var_name(:dash_pos-1)
          param1 = var_name(dash_pos+1:)
        end if

    !         write(error_unit, '(A,L1,A,A,A,A,A)') 'DEBUG: has_colon=', has_colon, &
    !          ' op=', trim(operation), ' param1=', trim(param1)
        var_is_set = is_shell_variable_set(shell, trim(operation))
        var_value = get_shell_variable(shell, trim(operation))
        var_is_null = (len_trim(var_value) == 0)
    !         write(error_unit, '(A,L1,A,A,A,L1)') 'DEBUG: var_is_set=', var_is_set, &
    !          ' val=', trim(var_value), ' null=', var_is_null

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
    !         write(error_unit, '(A,A,A)') 'DEBUG: expanded=', trim(expanded), '|'

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
            shell%last_exit_status = 127  ! bash uses 127 for direct expansion errors
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
            shell%last_exit_status = 127  ! bash uses 127 for direct expansion errors
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
      write(num_buf, '(I0)') len_trim(var_value)
      expanded = trim(num_buf)

    else
      ! Simple variable expansion
      var_value = get_shell_variable(shell, trim(var_name))

      ! Check if variable is unset and set -u is enabled
      if (len_trim(var_value) == 0 .and. .not. is_shell_variable_set(shell, trim(var_name))) then
        if (check_nounset(shell, trim(var_name))) then
          shell%last_exit_status = 127  ! bash uses 127 for direct expansion errors
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
    integer :: best_pos, i

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
      ! Try to match from end of string - include len_trim+1 for empty suffix
      do i = len_trim(input) + 1, 1, -1
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
    integer :: best_pos, i

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
      ! Try to match from start - start at 0 to test empty prefix
      do i = 0, len_trim(input)
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

    ! Clear any previous error
    arithmetic_error = .false.
    arithmetic_error_msg = ''

    ! Evaluate the arithmetic expression (without shell context for variable resolution)
    result_int = eval_expression(trim(expr))

    ! Check for arithmetic errors
    if (arithmetic_error) then
      write(error_unit, '(a,a)') 'fortsh: arithmetic expression: ', trim(arithmetic_error_msg)
      result_value = ''  ! Return empty string to signal error
    else
      write(result_value, '(I0)') result_int
    end if
  end function

  ! Version with shell context for variable resolution
  function arithmetic_expansion_shell(expression, shell) result(result_value)
    character(len=*), intent(in) :: expression
    type(shell_state_t), intent(inout) :: shell
    character(len=32) :: result_value
    character(len=512) :: expr
    character(len=:), allocatable :: expanded_expr
    integer(kind=8) :: result_int

    result_value = '0'

    ! Remove $(( and ))
    if (len_trim(expression) < 6) return
    expr = adjustl(expression(4:len_trim(expression)-2))

    ! Clear any previous error
    arithmetic_error = .false.
    arithmetic_error_msg = ''
    shell%arithmetic_error = .false.
    shell%arithmetic_error_msg = ''

    ! Expand ALL parameter expansions ($var, $1, $(cmd), etc.) before evaluation
    ! This handles variables, positional parameters, and command substitutions
    ! NOTE: Only call enhanced_expand_variables if there are $ characters to expand,
    ! because it has a bug where it strips internal whitespace.
    if (index(expr, '$') > 0) then
      call enhanced_expand_variables(expr, expanded_expr, shell)
    else
      expanded_expr = trim(expr)
    end if

    ! Evaluate with shell context for any remaining variable resolution
    result_int = eval_expression_shell(trim(expanded_expr), shell)

    ! Check for arithmetic errors
    if (arithmetic_error) then
      write(error_unit, '(a,a)') 'fortsh: arithmetic expression: ', trim(arithmetic_error_msg)
      shell%last_exit_status = 1  ! bash returns 1 for arithmetic errors
      shell%arithmetic_error = .true.
      shell%arithmetic_error_msg = trim(arithmetic_error_msg)
      result_value = ''  ! Return empty string to signal error
    else
      write(result_value, '(I0)') result_int
    end if
  end function

  ! Main expression evaluator - handles full expressions
  recursive function eval_expression(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value

    value = eval_ternary(trim(adjustl(expr)))
  end function

  ! Ternary conditional operator (? :)
  recursive function eval_ternary(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value
    integer :: qmark_pos, colon_pos, depth, i
    character(len=512) :: condition_expr, true_expr, false_expr

    ! Find ? outside parentheses
    qmark_pos = 0
    depth = 0
    do i = 1, len_trim(expr)
      if (expr(i:i) == '(') then
        depth = depth + 1
      else if (expr(i:i) == ')') then
        depth = depth - 1
      else if (depth == 0 .and. expr(i:i) == '?') then
        qmark_pos = i
        exit
      end if
    end do

    if (qmark_pos > 0) then
      ! Find matching : after the ?
      colon_pos = 0
      depth = 0
      do i = qmark_pos + 1, len_trim(expr)
        if (expr(i:i) == '(') then
          depth = depth + 1
        else if (expr(i:i) == ')') then
          depth = depth - 1
        else if (depth == 0 .and. expr(i:i) == ':') then
          colon_pos = i
          exit
        end if
      end do

      if (colon_pos > 0) then
        condition_expr = expr(:qmark_pos-1)
        true_expr = expr(qmark_pos+1:colon_pos-1)
        false_expr = expr(colon_pos+1:)

        ! Evaluate condition
        value = eval_logical_or(trim(adjustl(condition_expr)))
        if (value /= 0) then
          ! Condition is true, evaluate true expression
          value = eval_ternary(trim(adjustl(true_expr)))
        else
          ! Condition is false, evaluate false expression
          value = eval_ternary(trim(adjustl(false_expr)))
        end if
        return
      end if
    end if

    ! No ternary operator found
    value = eval_logical_or(expr)
  end function

  ! Logical OR (lowest precedence except ternary)
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
      value = eval_shift(trim(adjustl(left_expr)))
      right_val = eval_shift(trim(adjustl(right_expr)))
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
      value = eval_shift(trim(adjustl(left_expr)))
      right_val = eval_shift(trim(adjustl(right_expr)))
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
      value = eval_shift(trim(adjustl(left_expr)))
      right_val = eval_shift(trim(adjustl(right_expr)))
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
      value = eval_shift(trim(adjustl(left_expr)))
      right_val = eval_shift(trim(adjustl(right_expr)))
      if (value > right_val) then
        value = 1
      else
        value = 0
      end if
      return
    end if

    value = eval_shift(expr)
  end function

  ! Shift operations (<<, >>)
  recursive function eval_shift(expr) result(value)
    character(len=*), intent(in) :: expr
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! Try << (left shift)
    pos = find_operator(expr, '<<')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive(trim(adjustl(left_expr)))  ! Changed from eval_shift
      right_val = eval_additive(trim(adjustl(right_expr)))
      ! Left shift by right_val bits
      value = ishft(value, int(right_val))
      return
    end if

    ! Try >> (right shift)
    pos = find_operator(expr, '>>')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive(trim(adjustl(left_expr)))  ! Changed from eval_shift
      right_val = eval_additive(trim(adjustl(right_expr)))
      ! Right shift by right_val bits (negative for right shift in ishft)
      value = ishft(value, -int(right_val))
      return
    end if

    ! No shift operator found
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
          arithmetic_error = .true.
          arithmetic_error_msg = 'division by zero'
          value = 0  ! Division by zero
        end if
      case ('%')
        if (right_val /= 0) then
          value = mod(value, right_val)
        else
          arithmetic_error = .true.
          arithmetic_error_msg = 'division by zero'
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

    ! Bitwise NOT (~)
    if (expr(1:1) == '~') then
      rest = adjustl(expr(2:))
      value = eval_unary(rest)
      ! Bitwise NOT in two's complement: ~n = -(n + 1)
      value = -(value + 1)
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

    ! Try to parse as number (with octal/hex support)
    temp_expr = trim(adjustl(expr))
    value = parse_arithmetic_number(temp_expr, iostat)
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
    ! Comma operator has lowest precedence
    value = eval_comma_shell(trim(adjustl(expr)), shell)
  end function

  ! Comma operator (evaluates left-to-right, returns rightmost value)
  recursive function eval_comma_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value
    integer :: comma_pos, paren_depth, i
    character(len=1) :: ch

    ! Find comma at top level (not inside parentheses)
    paren_depth = 0
    comma_pos = 0
    do i = 1, len_trim(expr)
      ch = expr(i:i)
      if (ch == '(') then
        paren_depth = paren_depth + 1
      else if (ch == ')') then
        paren_depth = paren_depth - 1
      else if (ch == ',' .and. paren_depth == 0) then
        ! Evaluate left side (for side effects), then continue with right
        value = eval_assignment_shell(trim(adjustl(expr(:i-1))), shell)
        ! Continue evaluating right side (may have more commas)
        value = eval_comma_shell(trim(adjustl(expr(i+1:))), shell)
        return
      end if
    end do

    ! No comma found, evaluate as assignment
    value = eval_assignment_shell(trim(adjustl(expr)), shell)
  end function

  ! Assignment operators (=, +=, -=, *=, /=, %=)
  recursive function eval_assignment_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val, current_val
    integer :: pos, op_len, iostat
    character(len=512) :: var_name, right_expr, var_value_str
    character(len=:), allocatable :: temp_value

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
            arithmetic_error = .true.
            arithmetic_error_msg = 'division by zero'
            value = 0
          end if
        case ('%=')
          if (right_val /= 0) then
            value = mod(current_val, right_val)
          else
            arithmetic_error = .true.
            arithmetic_error_msg = 'division by zero'
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
      ! No assignment, evaluate as ternary
      value = eval_ternary_shell(expr, shell)
    end if
  end function

  ! Ternary conditional operator (? :)
  recursive function eval_ternary_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value
    integer :: qmark_pos, colon_pos, depth, i
    character(len=512) :: condition_expr, true_expr, false_expr

    ! Find ? outside parentheses
    qmark_pos = 0
    depth = 0
    do i = 1, len_trim(expr)
      if (expr(i:i) == '(') then
        depth = depth + 1
      else if (expr(i:i) == ')') then
        depth = depth - 1
      else if (depth == 0 .and. expr(i:i) == '?') then
        qmark_pos = i
        exit
      end if
    end do

    if (qmark_pos > 0) then
      ! Find matching : after the ?
      colon_pos = 0
      depth = 0
      do i = qmark_pos + 1, len_trim(expr)
        if (expr(i:i) == '(') then
          depth = depth + 1
        else if (expr(i:i) == ')') then
          depth = depth - 1
        else if (depth == 0 .and. expr(i:i) == ':') then
          colon_pos = i
          exit
        end if
      end do

      if (colon_pos > 0) then
        condition_expr = expr(:qmark_pos-1)
        true_expr = expr(qmark_pos+1:colon_pos-1)
        false_expr = expr(colon_pos+1:)

        ! Evaluate condition
        value = eval_logical_or_shell(trim(adjustl(condition_expr)), shell)
        if (value /= 0) then
          ! Condition is true, evaluate true expression
          value = eval_ternary_shell(trim(adjustl(true_expr)), shell)
        else
          ! Condition is false, evaluate false expression
          value = eval_ternary_shell(trim(adjustl(false_expr)), shell)
        end if
        return
      end if
    end if

    ! No ternary operator found
    value = eval_logical_or_shell(expr, shell)
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

    ! FIRST check for || operator (lowest precedence in logical chain)
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
    else
      ! No || found, delegate to next precedence level
      value = eval_logical_and_shell(expr, shell)
    end if
  end function

  recursive function eval_logical_and_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! FIRST check for && operator (lowest precedence in this chain)
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
    else
      ! No && found, delegate to next precedence level
      value = eval_bitwise_or_shell(expr, shell)
    end if
  end function

  recursive function eval_bitwise_or_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! FIRST check for | operator
    pos = find_single_operator(expr, '|')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_bitwise_xor_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_bitwise_or_shell(trim(adjustl(right_expr)), shell)
      value = ior(int(value), int(right_val))
    else
      value = eval_bitwise_xor_shell(expr, shell)
    end if
  end function

  recursive function eval_bitwise_xor_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! FIRST check for ^ operator
    pos = find_single_operator(expr, '^')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_bitwise_and_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_bitwise_xor_shell(trim(adjustl(right_expr)), shell)
      value = ieor(int(value), int(right_val))
    else
      value = eval_bitwise_and_shell(expr, shell)
    end if
  end function

  recursive function eval_bitwise_and_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! FIRST check for & operator
    pos = find_single_operator(expr, '&')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_equality_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_bitwise_and_shell(trim(adjustl(right_expr)), shell)
      value = iand(int(value), int(right_val))
    else
      value = eval_equality_shell(expr, shell)
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
      value = eval_shift_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_shift_shell(trim(adjustl(right_expr)), shell)
      if (value <= right_val) then; value = 1; else; value = 0; end if
      return
    end if

    pos = find_operator(expr, '>=')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_shift_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_shift_shell(trim(adjustl(right_expr)), shell)
      if (value >= right_val) then; value = 1; else; value = 0; end if
      return
    end if

    pos = find_single_operator(expr, '<')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_shift_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_shift_shell(trim(adjustl(right_expr)), shell)
      if (value < right_val) then; value = 1; else; value = 0; end if
      return
    end if

    pos = find_single_operator(expr, '>')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+1:)
      value = eval_shift_shell(trim(adjustl(left_expr)), shell)
      right_val = eval_shift_shell(trim(adjustl(right_expr)), shell)
      if (value > right_val) then; value = 1; else; value = 0; end if
      return
    end if

    value = eval_shift_shell(expr, shell)
  end function

  ! Shift operations (<<, >>)
  recursive function eval_shift_shell(expr, shell) result(value)
    character(len=*), intent(in) :: expr
    type(shell_state_t), intent(inout) :: shell
    integer(kind=8) :: value, right_val
    integer :: pos
    character(len=512) :: left_expr, right_expr

    ! Try << (left shift)
    pos = find_operator(expr, '<<')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)  ! Changed from eval_shift_shell
      right_val = eval_additive_shell(trim(adjustl(right_expr)), shell)
      ! Left shift by right_val bits
      value = ishft(value, int(right_val))
      return
    end if

    ! Try >> (right shift)
    pos = find_operator(expr, '>>')
    if (pos > 0) then
      left_expr = expr(:pos-1)
      right_expr = expr(pos+2:)
      value = eval_additive_shell(trim(adjustl(left_expr)), shell)  ! Changed from eval_shift_shell
      right_val = eval_additive_shell(trim(adjustl(right_expr)), shell)
      ! Right shift by right_val bits (negative for right shift in ishft)
      value = ishft(value, -int(right_val))
      return
    end if

    ! No shift operator found
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
        if (right_val /= 0) then
          value = value / right_val
        else
          arithmetic_error = .true.
          arithmetic_error_msg = 'division by zero'
          value = 0
        end if
      case ('%')
        if (right_val /= 0) then
          value = mod(value, right_val)
        else
          arithmetic_error = .true.
          arithmetic_error_msg = 'division by zero'
          value = 0
        end if
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
    character(len=512) :: rest, var_name, var_value_str, trimmed_expr
    character(len=:), allocatable :: temp_value
    integer :: iostat

    if (len_trim(expr) == 0) then; value = 0; return; end if

    ! Trim leading/trailing whitespace for all checks
    trimmed_expr = trim(adjustl(expr))

    ! Pre-increment: ++x (only if followed by a variable name, not a number)
    if (len_trim(trimmed_expr) > 2 .and. trimmed_expr(1:2) == '++') then
      var_name = trim(adjustl(trimmed_expr(3:)))
      ! Check if it starts with a letter or underscore (variable name)
      ! If it starts with a digit, it's double unary plus, not increment
      if (len_trim(var_name) > 0) then
        if ((var_name(1:1) >= 'a' .and. var_name(1:1) <= 'z') .or. &
            (var_name(1:1) >= 'A' .and. var_name(1:1) <= 'Z') .or. &
            var_name(1:1) == '_') then
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
        ! Otherwise fall through to unary plus handling
      end if
    end if

    ! Pre-decrement: --x (only if followed by a variable name, not a number)
    if (len_trim(trimmed_expr) > 2 .and. trimmed_expr(1:2) == '--') then
      var_name = trim(adjustl(trimmed_expr(3:)))
      ! Check if it starts with a letter or underscore (variable name)
      ! If it starts with a digit, it's double unary minus, not decrement
      if (len_trim(var_name) > 0) then
        if ((var_name(1:1) >= 'a' .and. var_name(1:1) <= 'z') .or. &
            (var_name(1:1) >= 'A' .and. var_name(1:1) <= 'Z') .or. &
            var_name(1:1) == '_') then
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
        ! Otherwise fall through to unary minus handling
      end if
    end if

    if (trimmed_expr(1:1) == '!') then
      rest = adjustl(trimmed_expr(2:))
      value = eval_unary_shell(rest, shell)
      if (value == 0) then; value = 1; else; value = 0; end if
      return
    end if

    ! Bitwise NOT (~)
    if (trimmed_expr(1:1) == '~') then
      rest = adjustl(trimmed_expr(2:))
      value = eval_unary_shell(rest, shell)
      ! Bitwise NOT in two's complement: ~n = -(n + 1)
      value = -(value + 1)
      return
    end if

    if (trimmed_expr(1:1) == '-' .and. len_trim(trimmed_expr) > 1) then
      rest = adjustl(trimmed_expr(2:))
      value = -eval_unary_shell(rest, shell)
      return
    end if

    if (trimmed_expr(1:1) == '+' .and. len_trim(trimmed_expr) > 1) then
      rest = adjustl(trimmed_expr(2:))
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
    character(len=:), allocatable :: var_value
    integer :: iostat, paren_end, expr_len

    if (len_trim(expr) == 0) then; value = 0; return; end if

    expr_len = len_trim(expr)

    ! Check for post-increment: x++ (only if x is a valid variable name)
    if (expr_len > 2 .and. expr(expr_len-1:expr_len) == '++') then
      var_name = trim(adjustl(expr(:expr_len-2)))
      ! Only treat as post-increment if var_name is a valid identifier (no operators)
      if (is_valid_identifier(var_name)) then
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
    end if

    ! Check for post-decrement: x-- (only if x is a valid variable name)
    if (expr_len > 2 .and. expr(expr_len-1:expr_len) == '--') then
      var_name = trim(adjustl(expr(:expr_len-2)))
      ! Only treat as post-decrement if var_name is a valid identifier (no operators)
      if (is_valid_identifier(var_name)) then
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

    ! Try to parse as number (with octal/hex support)
    temp_expr = trim(adjustl(expr))
    value = parse_arithmetic_number(temp_expr, iostat)
    if (iostat == 0) return

    ! Check if it's a valid identifier before treating as variable
    if (.not. is_valid_identifier(trim(adjustl(expr)))) then
      ! Not a number and not a valid identifier - syntax error
      arithmetic_error = .true.
      arithmetic_error_msg = 'syntax error in expression (error token is "' // trim(adjustl(expr)) // '")'
      value = 0
      return
    end if

    ! Resolve as variable (valid identifier)
    var_value = get_shell_variable(shell, trim(adjustl(expr)))
    if (len_trim(var_value) > 0) then
      value = parse_arithmetic_number(trim(var_value), iostat)
      if (iostat == 0) return
      ! Variable exists but is not numeric - try recursive evaluation
      value = eval_expression_shell(trim(var_value), shell)
      return
    end if

    ! Valid identifier but variable not found or empty - return 0
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
          ! Also check if < or > is the second char of << or >>
          if (op == '<' .and. expr(i-1:i-1) == '<') cycle
          if (op == '>' .and. expr(i-1:i-1) == '>') cycle
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
    integer :: pos, i, depth, j
    character(len=1) :: prev_ch
    logical :: is_unary

    pos = 0
    depth = 0
    do i = len_trim(expr), 1, -1
      if (expr(i:i) == ')') then
        depth = depth + 1
      else if (expr(i:i) == '(') then
        depth = depth - 1
      else if (depth == 0 .and. (expr(i:i) == '+' .or. expr(i:i) == '-')) then
        ! Skip if it's part of unary operator at start
        if (i == 1) cycle
        ! Skip if this is part of ++ or -- (increment/decrement operators)
        ! Check for both pre-increment (++x) and post-increment (x++)
        if (i < len_trim(expr)) then
          if (expr(i:i) == '+' .and. expr(i+1:i+1) == '+') then
            ! Skip for pre-increment: ++x (followed by letter/underscore)
            if (i+2 <= len_trim(expr)) then
              if ((expr(i+2:i+2) >= 'a' .and. expr(i+2:i+2) <= 'z') .or. &
                  (expr(i+2:i+2) >= 'A' .and. expr(i+2:i+2) <= 'Z') .or. &
                  expr(i+2:i+2) == '_') cycle
            end if
          end if
          if (expr(i:i) == '-' .and. expr(i+1:i+1) == '-') then
            ! Skip for pre-decrement: --x (followed by letter/underscore)
            if (i+2 <= len_trim(expr)) then
              if ((expr(i+2:i+2) >= 'a' .and. expr(i+2:i+2) <= 'z') .or. &
                  (expr(i+2:i+2) >= 'A' .and. expr(i+2:i+2) <= 'Z') .or. &
                  expr(i+2:i+2) == '_') cycle
            end if
          end if
        end if
        ! Skip for post-increment/decrement: x++ or x-- (preceded by valid identifier)
        if (i > 1) then
          if ((expr(i:i) == '+' .and. expr(i+1:i+1) == '+') .or. &
              (expr(i:i) == '-' .and. expr(i+1:i+1) == '-')) then
            ! Extract the full token before the operator
            ! Find the start of the identifier by scanning backwards
            j = i - 1
            do while (j > 1)
              if (.not. ((expr(j-1:j-1) >= 'a' .and. expr(j-1:j-1) <= 'z') .or. &
                         (expr(j-1:j-1) >= 'A' .and. expr(j-1:j-1) <= 'Z') .or. &
                         (expr(j-1:j-1) >= '0' .and. expr(j-1:j-1) <= '9') .or. &
                         expr(j-1:j-1) == '_')) exit
              j = j - 1
            end do
            ! Now j points to the start of the potential identifier
            ! Check if it's a valid identifier (not just digits, must start with letter/_)
            if (is_valid_identifier(expr(j:i-1))) cycle
          end if
        end if
        ! Skip if previous non-space char makes this unary
        ! Find previous non-space character
        prev_ch = ' '
        do j = i-1, 1, -1
          if (expr(j:j) /= ' ') then
            prev_ch = expr(j:j)
            exit
          end if
        end do
        ! If no non-space char found (i.e., at start), it's unary
        is_unary = (prev_ch == ' ')
        ! Check if previous char makes this unary
        if (.not. is_unary) then
          is_unary = (prev_ch == '(' .or. prev_ch == '+' .or. &
              prev_ch == '-' .or. prev_ch == '*' .or. &
              prev_ch == '/' .or. prev_ch == '%' .or. &
              prev_ch == '=' .or. prev_ch == '!' .or. &
              prev_ch == '<' .or. prev_ch == '>' .or. &
              prev_ch == '&' .or. prev_ch == '|' .or. &
              prev_ch == '^' .or. prev_ch == ',')
        end if
        if (is_unary) cycle
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
    integer :: i, start_pos, bracket_count, result_capacity, result_pos
    character(len=256) :: var_expr
    character(len=:), allocatable :: var_value
    logical :: in_single_quote, in_double_quote

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
          ! Use shell-aware version to handle command substitutions inside arithmetic
          var_value = arithmetic_expansion_shell(var_expr, shell)
          result = trim(result) // trim(var_value)
        end if

      else if (i < len_trim(input) - 1 .and. input(i:i+1) == '$(' .and. &
               (i >= len_trim(input) - 2 .or. input(i:i+2) /= '$((')) then
        ! Command substitution $(command)
        ! NOTE: We already checked for $(( above, so this is definitely $(
        start_pos = i
        bracket_count = 1
        i = i + 2

        ! Find matching ) with quote awareness
        do while (i <= len_trim(input) .and. bracket_count > 0)
          if (input(i:i) == '"') then
            ! Skip double-quoted string inside command substitution
            i = i + 1
            do while (i <= len_trim(input))
              if (input(i:i) == '\' .and. i < len_trim(input)) then
                i = i + 2
              else if (input(i:i) == '"') then
                i = i + 1
                exit
              else
                i = i + 1
              end if
            end do
          else if (input(i:i) == "'") then
            ! Skip single-quoted string
            i = i + 1
            do while (i <= len_trim(input) .and. input(i:i) /= "'")
              i = i + 1
            end do
            if (i <= len_trim(input)) i = i + 1
          else if (input(i:i) == '(') then
            bracket_count = bracket_count + 1
            i = i + 1
          else if (input(i:i) == ')') then
            bracket_count = bracket_count - 1
            i = i + 1
          else
            i = i + 1
          end if
        end do

        if (bracket_count == 0) then
          ! Extract command from $( ... )
          var_expr = input(start_pos+2:i-2)  ! Skip $( and )
          ! POSIX: errexit should not trigger in command substitution
          shell%in_command_substitution = .true.
          call execute_command_and_capture(shell, trim(var_expr), var_value)
          shell%in_command_substitution = .false.
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
          var_value = parameter_expansion(shell, var_expr)
          result = trim(result) // trim(var_value)
        end if
        
      else if (input(i:i) == '$') then
        ! Check if $ is escaped with backslash
        if (i > 1 .and. input(i-1:i-1) == '\') then
          ! Escaped $ - output literal $ (backslash already in result)
          ! Just add the $ and don't expand
          result = trim(result) // '$'
          i = i + 1
          cycle  ! Skip the rest of $ expansion logic
        else
          ! Simple variable expansion $var or special parameters
          start_pos = i + 1
          i = i + 1

          ! Check for special parameters first (single character)
          if (i <= len_trim(input)) then
          ! POSIX special parameters: $, !, ?, 0, -, _, #, *, @
          if (index('$!?0-_#*@', input(i:i)) > 0) then
            var_expr = input(i:i)
            var_value = get_shell_variable(shell, trim(var_expr))
            result = trim(result) // trim(var_value)
            i = i + 1
          else if (is_alnum(input(i:i)) .or. input(i:i) == '_') then
            ! Regular variable name (alphanumeric + underscore)
            do while (i <= len_trim(input) .and. (is_alnum(input(i:i)) .or. input(i:i) == '_'))
              i = i + 1
            end do
            var_expr = input(start_pos:i-1)
            var_value = get_shell_variable(shell, trim(var_expr))
            result = trim(result) // trim(var_value)
          else
            ! Just a lone $
            result = trim(result) // '$'
          end if
        else
          ! $ at end of string
          result = trim(result) // '$'
        end if
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

  ! Check if a string is a valid shell variable identifier
  function is_valid_identifier(str) result(is_valid)
    character(len=*), intent(in) :: str
    logical :: is_valid
    integer :: i
    character(len=1) :: c

    is_valid = .false.
    if (len_trim(str) == 0) return

    ! First character must be letter or underscore
    c = str(1:1)
    if (.not. ((c >= 'a' .and. c <= 'z') .or. &
               (c >= 'A' .and. c <= 'Z') .or. &
               c == '_')) return

    ! Remaining characters must be letters, digits, or underscores
    do i = 2, len_trim(str)
      c = str(i:i)
      if (.not. ((c >= 'a' .and. c <= 'z') .or. &
                 (c >= 'A' .and. c <= 'Z') .or. &
                 (c >= '0' .and. c <= '9') .or. &
                 c == '_')) return
    end do

    is_valid = .true.
  end function is_valid_identifier

  ! Field splitting based on IFS
  subroutine field_split(input, ifs_chars, fields, field_count)
    character(len=*), intent(in) :: input, ifs_chars
    character(len=*), intent(out) :: fields(:)
    integer, intent(out) :: field_count

    integer :: i, field_idx, input_len
    logical :: prev_was_ifs, is_ifs_char, is_whitespace_ifs
    logical :: prev_was_nonws_ifs  ! Previous was non-whitespace IFS
    character(len=:), allocatable :: current_field
    logical :: has_whitespace_ifs

    field_count = 0
    field_idx = 1
    current_field = ''
    prev_was_ifs = .false.
    prev_was_nonws_ifs = .false.

    ! Handle empty input
    input_len = len_trim(input)
    if (input_len == 0) then
      return
    end if

    ! Check if IFS contains whitespace characters
    has_whitespace_ifs = (index(ifs_chars, ' ') > 0) .or. &
                         (index(ifs_chars, char(9)) > 0) .or. &
                         (index(ifs_chars, char(10)) > 0)

    ! Special handling for first character
    is_ifs_char = index(ifs_chars, input(1:1)) > 0
    is_whitespace_ifs = is_ifs_char .and. &
                        (input(1:1) == ' ' .or. input(1:1) == char(9) .or. input(1:1) == char(10))

    ! Leading non-whitespace IFS characters create empty fields
    if (is_ifs_char .and. .not. is_whitespace_ifs) then
      ! Add empty field for leading delimiter
      if (field_idx <= size(fields)) then
        fields(field_idx) = ''
        field_idx = field_idx + 1
        field_count = field_count + 1
      end if
      prev_was_ifs = .true.
      prev_was_nonws_ifs = .true.
    else if (.not. is_ifs_char) then
      ! Start with non-IFS character
      current_field = input(1:1)
      prev_was_ifs = .false.
      prev_was_nonws_ifs = .false.
    else
      ! Leading whitespace IFS - skip
      prev_was_ifs = .true.
      prev_was_nonws_ifs = .false.
    end if

    ! Process remaining characters
    do i = 2, input_len
      is_ifs_char = index(ifs_chars, input(i:i)) > 0
      is_whitespace_ifs = is_ifs_char .and. &
                          (input(i:i) == ' ' .or. input(i:i) == char(9) .or. input(i:i) == char(10))

      if (.not. is_ifs_char) then
        ! Non-IFS character
        if (prev_was_ifs .and. len_trim(current_field) > 0) then
          ! Save previous field
          if (field_idx <= size(fields)) then
            fields(field_idx) = current_field
            field_idx = field_idx + 1
            field_count = field_count + 1
          end if
          current_field = ''
        end if
        current_field = trim(current_field) // input(i:i)
        prev_was_ifs = .false.
        prev_was_nonws_ifs = .false.
      else
        ! IFS character
        if (len_trim(current_field) > 0) then
          ! Save current field when we have content
          if (field_idx <= size(fields)) then
            fields(field_idx) = current_field
            field_idx = field_idx + 1
            field_count = field_count + 1
          end if
          current_field = ''
        else if (.not. is_whitespace_ifs) then
          ! Non-whitespace IFS
          ! POSIX: Only create empty field for consecutive non-whitespace IFS
          ! without any whitespace between them. So "::" creates empty, but ": :" doesn't
          if (prev_was_nonws_ifs) then
            if (field_idx <= size(fields)) then
              fields(field_idx) = ''
              field_idx = field_idx + 1
              field_count = field_count + 1
            end if
          end if
        end if

        ! Track state for next iteration
        prev_was_ifs = .true.
        if (.not. is_whitespace_ifs) then
          prev_was_nonws_ifs = .true.
        else
          ! Whitespace IFS resets the consecutive non-whitespace tracking
          prev_was_nonws_ifs = .false.
        end if
      end if
    end do

    ! Handle last field
    ! Note: Trailing IFS delimiters should NOT create empty fields (POSIX)
    if (len_trim(current_field) > 0) then
      if (field_idx <= size(fields)) then
        fields(field_idx) = current_field
        field_count = field_count + 1
      end if
    end if
  end subroutine
  
  ! Word splitting for unquoted variable expansions
  subroutine word_split(shell, input, words, word_count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: words(:)
    integer, intent(out) :: word_count

    character(len=256) :: ifs_to_use
    logical :: ifs_is_set
    integer :: ifs_actual_len

    ! Check if IFS is explicitly set (even if empty)
    ifs_is_set = is_shell_variable_set(shell, 'IFS')

    if (ifs_is_set) then
      ifs_to_use = shell%ifs
      ! Get the actual length of IFS from shell%ifs_len (preserves whitespace-only values)
      ifs_actual_len = shell%ifs_len

      ! If IFS is set to empty string (length 0), no field splitting occurs
      ! But if IFS=" " (length 1), we should still split on that space
      if (ifs_actual_len == 0) then
        ! Empty IFS - return the entire input as a single field
        words(1) = input
        word_count = 1
        return
      end if
      ! Use the actual IFS length, not trimmed length
      call field_split(input, ifs_to_use(1:ifs_actual_len), words, word_count)
    else
      ! IFS not set - use default
      ifs_to_use = ' '//char(9)//char(10)  ! space, tab, newline
      call field_split(input, trim(ifs_to_use), words, word_count)
    end if

    ! POSIX: Remove null (empty) fields after field splitting
    ! Empty unquoted fields should be discarded
    call remove_null_fields(words, word_count)
  end subroutine

  ! Remove null (empty) fields from word list
  ! According to POSIX, after field splitting, null fields should be removed
  subroutine remove_null_fields(words, word_count)
    character(len=*), intent(inout) :: words(:)
    integer, intent(inout) :: word_count
    integer :: i, j

    j = 1
    do i = 1, word_count
      if (len_trim(words(i)) > 0) then
        if (i /= j) then
          words(j) = words(i)
        end if
        j = j + 1
      end if
    end do
    word_count = j - 1
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
    character(len=:), allocatable :: result_buf
    integer :: i, start_val, end_val, step_val, current_val
    integer :: start_char, end_char, current_char
    integer :: last_pos, second_dot
    logical :: is_numeric, is_alpha, has_step, found_comma
    character(16) :: num_str
    character(len=:), allocatable :: start_str, end_str, step_str
    integer :: buf_pos, buf_cap, num_len, plen, slen, num_values, max_digits

    expanded = word

    ! Find opening brace that is NOT part of ${...} parameter expansion
    brace_start = 0
    pos = 1
    do while (pos <= len_trim(word))
      if (word(pos:pos) == '{') then
        ! Skip if preceded by $ (this is ${...} parameter expansion)
        if (pos > 1 .and. word(pos-1:pos-1) == '$') then
          ! Skip past matching closing brace
          depth = 1
          pos = pos + 1
          do while (pos <= len_trim(word) .and. depth > 0)
            if (word(pos:pos) == '{') depth = depth + 1
            if (word(pos:pos) == '}') depth = depth - 1
            pos = pos + 1
          end do
          cycle
        end if
        brace_start = pos
        exit
      end if
      pos = pos + 1
    end do
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
        ! Numeric range expansion — O(n) with pre-allocated buffer
        if (start_val <= end_val) then
          num_values = (end_val - start_val) / step_val + 1
        else
          num_values = (start_val - end_val) / step_val + 1
        end if
        plen = len_trim(prefix)
        slen = len_trim(suffix)
        ! Conservative estimate: max digits for any value in range + sign
        max_digits = 12  ! enough for any 32-bit integer
        buf_cap = num_values * (plen + max_digits + slen + 1)
        allocate(character(len=buf_cap) :: result_buf)
        buf_pos = 1

        if (start_val <= end_val) then
          current_val = start_val
          do while (current_val <= end_val)
            write(num_str, '(I0)') current_val
            num_len = len_trim(num_str)
            if (buf_pos > 1) then
              result_buf(buf_pos:buf_pos) = ' '
              buf_pos = buf_pos + 1
            end if
            if (plen > 0) then
              result_buf(buf_pos:buf_pos+plen-1) = prefix(1:plen)
              buf_pos = buf_pos + plen
            end if
            result_buf(buf_pos:buf_pos+num_len-1) = num_str(1:num_len)
            buf_pos = buf_pos + num_len
            if (slen > 0) then
              result_buf(buf_pos:buf_pos+slen-1) = suffix(1:slen)
              buf_pos = buf_pos + slen
            end if
            current_val = current_val + step_val
          end do
        else
          current_val = start_val
          do while (current_val >= end_val)
            write(num_str, '(I0)') current_val
            num_len = len_trim(num_str)
            if (buf_pos > 1) then
              result_buf(buf_pos:buf_pos) = ' '
              buf_pos = buf_pos + 1
            end if
            if (plen > 0) then
              result_buf(buf_pos:buf_pos+plen-1) = prefix(1:plen)
              buf_pos = buf_pos + plen
            end if
            result_buf(buf_pos:buf_pos+num_len-1) = num_str(1:num_len)
            buf_pos = buf_pos + num_len
            if (slen > 0) then
              result_buf(buf_pos:buf_pos+slen-1) = suffix(1:slen)
              buf_pos = buf_pos + slen
            end if
            current_val = current_val - step_val
          end do
        end if
        expanded = result_buf(1:buf_pos-1)
        ! Recursively expand if result still contains braces
        if (index(expanded, '{') > 0) then
          expanded = recursive_expand_all_braces(expanded)
        end if
        return
      else if (is_alpha) then
        ! Alphabetic range expansion — O(n) with pre-allocated buffer
        plen = len_trim(prefix)
        slen = len_trim(suffix)
        if (start_char <= end_char) then
          num_values = (end_char - start_char) / step_val + 1
        else
          num_values = (start_char - end_char) / step_val + 1
        end if
        buf_cap = num_values * (plen + 1 + slen + 1)
        allocate(character(len=buf_cap) :: result_buf)
        buf_pos = 1

        if (start_char <= end_char) then
          current_char = start_char
          do while (current_char <= end_char)
            if (buf_pos > 1) then
              result_buf(buf_pos:buf_pos) = ' '
              buf_pos = buf_pos + 1
            end if
            if (plen > 0) then
              result_buf(buf_pos:buf_pos+plen-1) = prefix(1:plen)
              buf_pos = buf_pos + plen
            end if
            result_buf(buf_pos:buf_pos) = char(current_char)
            buf_pos = buf_pos + 1
            if (slen > 0) then
              result_buf(buf_pos:buf_pos+slen-1) = suffix(1:slen)
              buf_pos = buf_pos + slen
            end if
            current_char = current_char + step_val
          end do
        else
          current_char = start_char
          do while (current_char >= end_char)
            if (buf_pos > 1) then
              result_buf(buf_pos:buf_pos) = ' '
              buf_pos = buf_pos + 1
            end if
            if (plen > 0) then
              result_buf(buf_pos:buf_pos+plen-1) = prefix(1:plen)
              buf_pos = buf_pos + plen
            end if
            result_buf(buf_pos:buf_pos) = char(current_char)
            buf_pos = buf_pos + 1
            if (slen > 0) then
              result_buf(buf_pos:buf_pos+slen-1) = suffix(1:slen)
              buf_pos = buf_pos + slen
            end if
            current_char = current_char - step_val
          end do
        end if
        expanded = result_buf(1:buf_pos-1)
        return
      end if
    else
      ! List expansion: {a,b,c} - respect nested braces when finding commas
      ! Only expand if there's at least one comma at depth 0

      ! First pass: count commas to estimate buffer size
      found_comma = .false.
      num_values = 1
      depth = 0
      do i = 1, len_trim(brace_content)
        if (brace_content(i:i) == '{') then
          depth = depth + 1
        else if (brace_content(i:i) == '}') then
          depth = depth - 1
        else if (brace_content(i:i) == ',' .and. depth == 0) then
          found_comma = .true.
          num_values = num_values + 1
        end if
      end do

      ! Only expand if we found at least one comma
      if (.not. found_comma) then
        ! No comma found at this level - check if inner content has braces to expand
        if (index(brace_content, '{') > 0) then
          item = recursive_expand_all_braces(brace_content)
          expanded = add_braces_to_words(item, prefix, suffix)
          return
        end if
        return
      end if

      ! Pre-allocate buffer: each item up to full brace_content length + prefix + suffix + space
      plen = len_trim(prefix)
      slen = len_trim(suffix)
      buf_cap = num_values * (plen + len_trim(brace_content) + slen + 1)
      allocate(character(len=buf_cap) :: result_buf)
      buf_pos = 1

      ! Second pass: extract items and write directly
      last_pos = 1
      depth = 0
      do i = 1, len_trim(brace_content)
        if (brace_content(i:i) == '{') then
          depth = depth + 1
        else if (brace_content(i:i) == '}') then
          depth = depth - 1
        else if (brace_content(i:i) == ',' .and. depth == 0) then
          item = brace_content(last_pos:i-1)
          num_len = len_trim(item)
          if (buf_pos > 1) then
            result_buf(buf_pos:buf_pos) = ' '
            buf_pos = buf_pos + 1
          end if
          if (plen > 0) then
            result_buf(buf_pos:buf_pos+plen-1) = prefix(1:plen)
            buf_pos = buf_pos + plen
          end if
          if (num_len > 0) then
            result_buf(buf_pos:buf_pos+num_len-1) = item(1:num_len)
            buf_pos = buf_pos + num_len
          end if
          if (slen > 0) then
            result_buf(buf_pos:buf_pos+slen-1) = suffix(1:slen)
            buf_pos = buf_pos + slen
          end if
          last_pos = i + 1
        end if
      end do

      ! Don't forget last item
      item = brace_content(last_pos:)
      num_len = len_trim(item)
      if (buf_pos > 1) then
        result_buf(buf_pos:buf_pos) = ' '
        buf_pos = buf_pos + 1
      end if
      if (plen > 0) then
        result_buf(buf_pos:buf_pos+plen-1) = prefix(1:plen)
        buf_pos = buf_pos + plen
      end if
      if (num_len > 0) then
        result_buf(buf_pos:buf_pos+num_len-1) = item(1:num_len)
        buf_pos = buf_pos + num_len
      end if
      if (slen > 0) then
        result_buf(buf_pos:buf_pos+slen-1) = suffix(1:slen)
        buf_pos = buf_pos + slen
      end if
      expanded = result_buf(1:buf_pos-1)
      ! Recursively expand if result still contains braces
      if (index(expanded, '{') > 0) then
        expanded = recursive_expand_all_braces(expanded)
      end if
      return
    end if

  end function expand_braces

  ! --------------------------------------------------------------------------
  ! Expand braces and return results as separate words in an allocatable array.
  ! This avoids the MAX_TOKEN_LEN bottleneck of the space-separated string
  ! approach and matches bash/zsh behavior for arbitrarily large expansions.
  ! --------------------------------------------------------------------------
  subroutine expand_braces_to_words(word, words, word_count)
    character(len=*), intent(in) :: word
    character(len=MAX_TOKEN_LEN), allocatable, intent(out) :: words(:)
    integer, intent(out) :: word_count

    character(len=:), allocatable :: expanded, wrd
    integer :: i, wstart, cap

    ! Use existing expand_braces which returns space-separated result
    expanded = expand_braces(word)

    ! Count words to allocate exact size
    word_count = 0
    if (len(expanded) == 0) then
      allocate(words(1))
      words(1) = word
      word_count = 1
      return
    end if

    ! Count spaces to estimate word count
    cap = 1
    do i = 1, len(expanded)
      if (expanded(i:i) == ' ') cap = cap + 1
    end do

    allocate(words(cap))
    word_count = 0
    wstart = 1

    do i = 1, len(expanded) + 1
      if (i > len(expanded) .or. expanded(i:i) == ' ') then
        if (i > wstart) then
          word_count = word_count + 1
          words(word_count) = expanded(wstart:i - 1)
        end if
        wstart = i + 1
      end if
    end do

    if (word_count == 0) then
      word_count = 1
      words(1) = word
    end if
  end subroutine expand_braces_to_words

  ! Helper function to recursively expand all braces in space-separated results
  function recursive_expand_all_braces(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    ! Use allocatable array to avoid static storage
    type(string_t), allocatable :: words(:)
    character(len=:), allocatable :: temp_result
    integer :: word_count, i, j, out_pos, capacity
    character(len=:), allocatable :: final_result
    integer :: final_result_capacity, final_result_len
    character(len=:), allocatable :: temp_piece

    ! Allocate initial array
    allocate(words(20))  ! Start with reasonable size
    allocate(character(len=max(1, len_trim(input))) :: temp_result)
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
          words(word_count)%str = temp_result(:out_pos-1)
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
      words(word_count)%str = temp_result(:out_pos-1)
    end if

    ! Recursively expand each word and recombine
    do i = 1, word_count
      if (index(words(i)%str, '{') > 0) then
        ! Still has braces - recurse
        temp_result = expand_braces(trim(words(i)%str))
        if (final_result_len > 0) then
          temp_piece = ' ' // trim(temp_result)
        else
          temp_piece = trim(temp_result)
        end if
      else
        ! No braces - use as-is
        if (final_result_len > 0) then
          temp_piece = ' ' // trim(words(i)%str)
        else
          temp_piece = trim(words(i)%str)
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

  ! Helper function to add literal braces around each word in a space-separated list
  ! e.g., "a1 a2" with prefix="" and suffix="" becomes "{a1} {a2}"
  function add_braces_to_words(words_str, prefix, suffix) result(output)
    character(len=*), intent(in) :: words_str, prefix, suffix
    character(len=:), allocatable :: output
    character(len=:), allocatable :: result_buf, word_buf
    integer :: i, word_start, word_len

    result_buf = ''
    word_start = 1
    i = 1

    do while (i <= len_trim(words_str))
      if (words_str(i:i) == ' ') then
        ! End of word - add braces around it
        word_len = i - word_start
        if (word_len > 0) then
          word_buf = words_str(word_start:i-1)
          if (len_trim(result_buf) > 0) then
            result_buf = trim(result_buf) // ' ' // trim(prefix) // '{' // &
                         trim(word_buf) // '}' // trim(suffix)
          else
            result_buf = trim(prefix) // '{' // trim(word_buf) // '}' // trim(suffix)
          end if
        end if
        word_start = i + 1
      end if
      i = i + 1
    end do

    ! Handle last word
    if (word_start <= len_trim(words_str)) then
      word_buf = words_str(word_start:len_trim(words_str))
      if (len_trim(result_buf) > 0) then
        result_buf = trim(result_buf) // ' ' // trim(prefix) // '{' // &
                     trim(word_buf) // '}' // trim(suffix)
      else
        result_buf = trim(prefix) // '{' // trim(word_buf) // '}' // trim(suffix)
      end if
    end if

    output = trim(result_buf)
  end function add_braces_to_words

  ! Helper subroutine to grow expansion array
  subroutine grow_expansion_array(array, current_size)
    type(string_t), allocatable, intent(inout) :: array(:)
    integer, intent(inout) :: current_size
    type(string_t), allocatable :: new_array(:)
    integer :: new_size, k

    new_size = current_size * 2
    allocate(new_array(new_size))

    ! Copy existing data
    do k = 1, current_size
      if (allocated(array(k)%str)) then
        new_array(k)%str = array(k)%str
      else
        new_array(k)%str = ''
      end if
    end do

    ! Swap arrays
    call move_alloc(new_array, array)
    current_size = new_size
  end subroutine

  ! Tilde expansion - expands ~ to home directory
  subroutine tilde_expansion(shell, input, output)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: output
    character(len=:), allocatable :: home_dir
    character(len=:), allocatable :: env_home
    integer :: tilde_pos

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

  ! Check if input is a quoted literal with no expansions inside
  ! Returns true for "literal", 'literal', but false for "$var", "$(cmd)", etc.
  function is_quoted_literal(input) result(is_literal)
    character(len=*), intent(in) :: input
    logical :: is_literal
    integer :: len_input, i
    character(1) :: quote_char

    is_literal = .false.
    len_input = len_trim(input)

    ! Must be at least 2 chars for quotes
    if (len_input < 2) return

    ! Check for matching outer quotes
    if (input(1:1) == '"' .and. input(len_input:len_input) == '"') then
      quote_char = '"'
    else if (input(1:1) == "'" .and. input(len_input:len_input) == "'") then
      quote_char = "'"
      ! Single quotes never have expansions, so it's always literal
      is_literal = .true.
      return
    else
      ! Not fully quoted
      return
    end if

    ! For double quotes, check if there are expansion operators inside
    do i = 2, len_input - 1
      if (input(i:i) == '$' .or. input(i:i) == '`') then
        ! Has expansion - not a pure literal
        return
      end if
    end do

    ! No expansion operators found
    is_literal = .true.
  end function

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
    type(string_t), intent(out) :: expanded_words(:)
    integer, intent(out) :: word_count

    character(len=:), allocatable :: temp_result, brace_expanded
    character(len=:), allocatable :: tilde_expanded, quote_removed
    character(len=:), allocatable :: temp_split_words(:)
    integer :: k

    word_count = 1

    ! Step 0: Brace expansion (happens FIRST, before all other expansions)
    brace_expanded = expand_braces(input)

    ! Step 1: Tilde expansion
    ! Pre-allocate for intent(out) character(len=*) parameter
    allocate(character(len=len(brace_expanded) + 4096) :: tilde_expanded)
    call tilde_expansion(shell, brace_expanded, tilde_expanded)

    ! Step 2: Parameter and variable expansion
    call enhanced_expand_variables(tilde_expanded, temp_result, shell)

    ! Step 3: Quote removal
    quote_removed = remove_quotes(temp_result)

    ! Step 4: Field splitting (if not quoted)
    ! POSIX: Field splitting only applies to results of parameter expansion,
    ! command substitution, and arithmetic expansion - NOT to literal quoted strings.
    ! Check if the original input was entirely quoted with no expansions inside.
    if (is_quoted_literal(input)) then
      ! Skip field splitting for quoted literals
      expanded_words(1)%str = quote_removed
      word_count = 1
    else
      ! Use temp buffer for word_split (expects character(len=*) array)
      allocate(character(len=max(1, len(quote_removed))) :: temp_split_words(size(expanded_words)))
      call word_split(shell, quote_removed, temp_split_words, word_count)
      do k = 1, word_count
        expanded_words(k)%str = trim(temp_split_words(k))
      end do
      deallocate(temp_split_words)
    end if

    ! POSIX: If field splitting results in zero words (empty unquoted expansion),
    ! keep it as zero words - don't add back an empty field
    ! Note: This means unquoted empty variables disappear from the command line
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

  ! Parse arithmetic number with octal and hex support
  ! Returns value and sets iostat (0 = success, non-zero = error)
  function parse_arithmetic_number(str, iostat) result(value)
    character(len=*), intent(in) :: str
    integer, intent(out) :: iostat
    integer(kind=8) :: value
    integer :: i, len_str, digit
    character(len=256) :: trimmed_str

    value = 0
    iostat = 0
    trimmed_str = trim(adjustl(str))
    len_str = len_trim(trimmed_str)

    if (len_str == 0) then
      iostat = 1
      return
    end if

    ! Check for hexadecimal (0x or 0X)
    if (len_str >= 3 .and. trimmed_str(1:1) == '0' .and. &
        (trimmed_str(2:2) == 'x' .or. trimmed_str(2:2) == 'X')) then
      ! Parse hexadecimal
      do i = 3, len_str
        if (trimmed_str(i:i) >= '0' .and. trimmed_str(i:i) <= '9') then
          digit = ichar(trimmed_str(i:i)) - ichar('0')
        else if (trimmed_str(i:i) >= 'a' .and. trimmed_str(i:i) <= 'f') then
          digit = ichar(trimmed_str(i:i)) - ichar('a') + 10
        else if (trimmed_str(i:i) >= 'A' .and. trimmed_str(i:i) <= 'F') then
          digit = ichar(trimmed_str(i:i)) - ichar('A') + 10
        else
          iostat = 1
          return
        end if
        value = value * 16 + digit
      end do
      return
    end if

    ! Check for octal (starts with 0 and has only 0-7 digits)
    if (len_str >= 2 .and. trimmed_str(1:1) == '0') then
      ! Verify all digits are 0-7 for octal
      do i = 2, len_str
        if (trimmed_str(i:i) < '0' .or. trimmed_str(i:i) > '7') then
          ! Not a valid octal, try decimal
          read(trimmed_str, *, iostat=iostat) value
          return
        end if
      end do
      ! Parse as octal
      do i = 1, len_str
        digit = ichar(trimmed_str(i:i)) - ichar('0')
        value = value * 8 + digit
      end do
      return
    end if

    ! Default: parse as decimal
    ! First verify the string contains only valid decimal characters (digits and optional leading +/-)
    i = 1
    if (len_str > 0 .and. (trimmed_str(1:1) == '+' .or. trimmed_str(1:1) == '-')) then
      i = 2
    end if
    do while (i <= len_str)
      if (trimmed_str(i:i) < '0' .or. trimmed_str(i:i) > '9') then
        iostat = 1  ! Not a valid decimal number
        return
      end if
      i = i + 1
    end do
    read(trimmed_str, *, iostat=iostat) value
  end function

end module expansion