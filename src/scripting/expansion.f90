! ==============================================================================
! Module: expansion
! Purpose: Parameter expansion and arithmetic operations
! ==============================================================================
module expansion
  use shell_types
  use variables
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  ! Parameter expansion: ${var:offset:length}
  function parameter_expansion(shell, expression) result(expanded)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: expression
    character(len=2048) :: expanded
    
    character(len=256) :: var_name, operation, param1, param2
    character(len=1024) :: var_value
    integer :: colon_pos, dash_pos, plus_pos, percent_pos, hash_pos, slash_pos
    integer :: offset, length, i
    
    expanded = ''
    
    ! Remove ${ and }
    if (len_trim(expression) < 4) return
    var_name = expression(3:len_trim(expression)-1)
    
    ! Check for various expansion operations
    colon_pos = index(var_name, ':')
    dash_pos = index(var_name, '-')
    plus_pos = index(var_name, '+')
    percent_pos = index(var_name, '%')
    hash_pos = index(var_name, '#')
    slash_pos = index(var_name, '/')
    
    if (colon_pos > 0) then
      ! ${var:offset:length} substring expansion
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
      
    else if (dash_pos > 0) then
      ! ${var:-default} default value expansion
      operation = var_name(:dash_pos-1)
      param1 = var_name(dash_pos+2:)  ! Skip :-
      var_value = get_shell_variable(shell, trim(operation))
      
      if (len_trim(var_value) > 0) then
        expanded = trim(var_value)
      else
        expanded = trim(param1)
      end if
      
    else if (plus_pos > 0) then
      ! ${var:+alternative} alternative value expansion  
      operation = var_name(:plus_pos-1)
      param1 = var_name(plus_pos+2:)  ! Skip :+
      var_value = get_shell_variable(shell, trim(operation))
      
      if (len_trim(var_value) > 0) then
        expanded = trim(param1)
      else
        expanded = ''
      end if
      
    else if (hash_pos > 0) then
      ! ${#var} length expansion
      operation = var_name(hash_pos+1:)
      var_value = get_shell_variable(shell, trim(operation))
      write(expanded, '(I0)') len_trim(var_value)
      
    else
      ! Simple variable expansion
      var_value = get_shell_variable(shell, trim(var_name))
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

  ! Arithmetic expansion: $((expression))
  function arithmetic_expansion(expression) result(result_value)
    character(len=*), intent(in) :: expression
    character(len=32) :: result_value
    
    character(len=256) :: expr
    integer :: result_int, i, j, num1, num2
    character(len=32) :: num1_str, num2_str
    character :: op
    
    result_value = '0'
    
    ! Remove $(( and ))
    if (len_trim(expression) < 6) return
    expr = expression(4:len_trim(expression)-2)
    
    ! Simple arithmetic parser for basic operations
    call parse_arithmetic_expression(trim(expr), num1, op, num2)
    
    select case (op)
    case ('+')
      result_int = num1 + num2
    case ('-')
      result_int = num1 - num2
    case ('*')
      result_int = num1 * num2
    case ('/')
      if (num2 /= 0) then
        result_int = num1 / num2
      else
        result_int = 0
      end if
    case ('%')
      if (num2 /= 0) then
        result_int = mod(num1, num2)
      else
        result_int = 0
      end if
    case default
      result_int = num1
    end select
    
    write(result_value, '(I0)') result_int
  end function

  subroutine parse_arithmetic_expression(expr, num1, op, num2)
    character(len=*), intent(in) :: expr
    integer, intent(out) :: num1, num2
    character, intent(out) :: op
    
    integer :: i, op_pos
    character(len=32) :: num1_str, num2_str
    
    num1 = 0
    num2 = 0
    op = '+'
    
    ! Find operator
    op_pos = 0
    do i = 1, len_trim(expr)
      if (index('+-*/%', expr(i:i)) > 0) then
        op_pos = i
        op = expr(i:i)
        exit
      end if
    end do
    
    if (op_pos > 1) then
      num1_str = expr(:op_pos-1)
      num2_str = expr(op_pos+1:)
      
      read(num1_str, *, iostat=i) num1
      if (i /= 0) num1 = 0
      
      read(num2_str, *, iostat=i) num2  
      if (i /= 0) num2 = 0
    else
      read(expr, *, iostat=i) num1
      if (i /= 0) num1 = 0
    end if
  end subroutine

  ! Enhanced variable expansion with array and parameter support
  subroutine enhanced_expand_variables(input, expanded, shell)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(in) :: shell
    
    character(len=4096) :: result
    integer :: i, start_pos, end_pos, bracket_count
    character(len=256) :: var_expr
    character(len=2048) :: var_value
    logical :: in_expansion
    
    result = ''
    i = 1
    
    do while (i <= len_trim(input))
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
    type(shell_state_t), intent(in) :: shell
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
  
  ! Tilde expansion - expands ~ to home directory
  subroutine tilde_expansion(shell, input, output)
    type(shell_state_t), intent(in) :: shell
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
  subroutine expand_word(shell, input, expanded_words, word_count)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: input
    character(len=1024), intent(out) :: expanded_words(:)
    integer, intent(out) :: word_count
    
    character(len=:), allocatable :: temp_result
    character(len=1024) :: tilde_expanded, quote_removed
    integer :: i
    
    word_count = 1
    
    ! Step 1: Tilde expansion
    call tilde_expansion(shell, input, tilde_expanded)
    
    ! Step 2: Parameter and variable expansion
    call simple_expand_variables(tilde_expanded, temp_result, shell)
    
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

end module expansion