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

  subroutine set_shell_variable(shell, name, value, value_length)
    use iso_fortran_env, only: error_unit
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: name, value
    integer, intent(in), optional :: value_length
    integer :: i, empty_slot, iostat, actual_len, depth


    empty_slot = -1

    ! Calculate actual length (use provided length or len_trim as fallback)
    if (present(value_length)) then
      actual_len = value_length
    else
      actual_len = len_trim(value)
    end if

    ! First check local variables - if variable exists in current function scope, update it there
    if (shell%function_depth > 0) then
      depth = shell%function_depth
      if (depth <= size(shell%local_var_counts)) then
        do i = 1, shell%local_var_counts(depth)
          if (trim(shell%local_vars(depth, i)%name) == trim(name)) then
            ! Found existing local variable - update it
            shell%local_vars(depth, i)%value = value(1:actual_len)
            shell%local_vars(depth, i)%value_len = actual_len
            return
          end if
        end do
      end if
    end if

    ! Handle special built-in variables
    select case (trim(name))
      case ('PS1')
        shell%ps1 = value
        ! For prompts, always use len_trim to get actual content length
        shell%ps1_len = len_trim(value)
        return
      case ('PS2')
        shell%ps2 = value
        if (present(value_length)) then
          shell%ps2_len = value_length
        else
          shell%ps2_len = len(value)
        end if
        return
      case ('PS3')
        shell%ps3 = value
        if (present(value_length)) then
          shell%ps3_len = value_length
        else
          shell%ps3_len = len(value)
        end if
        return
      case ('PS4')
        shell%ps4 = value
        if (present(value_length)) then
          shell%ps4_len = value_length
        else
          shell%ps4_len = len(value)
        end if
        return
      case ('IFS')
        shell%ifs = value(1:actual_len)
        shell%ifs_len = actual_len
        ! Don't return - continue to add IFS to variables array too
        ! This allows checking if IFS was explicitly set vs using default
      case ('PWD')
        ! Update shell%cwd when PWD is set
        shell%cwd = value(1:min(actual_len, len(shell%cwd)))
        ! Also update environment for child processes
        if (.not. set_environment_var('PWD', trim(shell%cwd))) then
          ! Silently ignore errors
        end if
        return
      case ('OLDPWD')
        ! Update shell%oldpwd when OLDPWD is set
        shell%oldpwd = value(1:min(actual_len, len(shell%oldpwd)))
        ! Also update environment for child processes
        if (.not. set_environment_var('OLDPWD', trim(shell%oldpwd))) then
          ! Silently ignore errors
        end if
        return
      case ('PATH')
        ! PATH must ALWAYS update environment so child processes use new PATH
        if (.not. set_environment_var('PATH', value(1:actual_len))) then
          ! Silently ignore errors
        end if
        ! Clear hash table when PATH changes (bash behavior)
        shell%num_hashed_commands = 0
        ! Don't return - continue to store in variables array too
      case ('HISTFILE')
        shell%histfile = value
        return
      case ('HISTSIZE')
        read(value, *, iostat=iostat) shell%histsize
        if (iostat /= 0) shell%histsize = 1000
        return
      case ('HISTFILESIZE')
        read(value, *, iostat=iostat) shell%histfilesize
        if (iostat /= 0) shell%histfilesize = 2000
        return
      case ('HISTCONTROL')
        shell%histcontrol = value
        ! Note: histcontrol is also updated in fortsh.f90 via set_histcontrol()
        return
    end select

    ! Check if variable already exists
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        ! Check if variable is readonly
        if (shell%variables(i)%readonly) then
          write(error_unit, '(a,i0,a)') 'fortsh: line ', shell%current_line_number, ': ' // &
                                        trim(name) // ': readonly variable'
          shell%last_exit_status = 1  ! POSIX: readonly assignment failure returns 1
          ! POSIX: In non-interactive shells, stop execution after readonly violation
          if (.not. shell%is_interactive) then
            shell%running = .false.
          end if
          return
        end if
        shell%variables(i)%value = value(1:actual_len)
        shell%variables(i)%value_len = actual_len  ! Store actual length
        ! If exported, update environment
        if (shell%variables(i)%exported) then
          if (.not. set_environment_var(trim(name), trim(value))) then
            write(error_unit, '(a)') 'warning: failed to update environment variable'
          end if
        end if
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
      shell%variables(empty_slot)%value = value(1:actual_len)
      shell%variables(empty_slot)%value_len = actual_len  ! Store actual length
      shell%num_variables = shell%num_variables + 1
    end if
  end subroutine

  function get_shell_variable(shell, name) result(value)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    character(len=:), allocatable :: value
    integer :: i, depth
    character(len=20) :: fmt_buf

    value = ''

    ! First check local variables (innermost scope first)
    if (shell%function_depth > 0) then
      do depth = shell%function_depth, 1, -1
        if (depth <= size(shell%local_var_counts)) then
          do i = 1, shell%local_var_counts(depth)
            if (trim(shell%local_vars(depth, i)%name) == trim(name)) then
              ! value_len=-1 means explicitly unset local (shadows global)
              if (shell%local_vars(depth, i)%value_len == -1) then
                value = ''
                return
              end if
              value = shell%local_vars(depth, i)%value
              return
            end if
          end do
        end if
      end do
    end if

    ! Handle special variables
    select case (trim(name))
      case ('$')
        write(fmt_buf, '(i0)') shell%shell_pid
        value = trim(adjustl(fmt_buf))
        return
      case ('!')
        write(fmt_buf, '(i0)') shell%last_bg_pid
        value = trim(adjustl(fmt_buf))
        return
      case ('?')
        write(fmt_buf, '(i0)') shell%last_exit_status
        value = trim(adjustl(fmt_buf))
        return
      case ('0')
        value = trim(shell%shell_name)
        return
      case ('_')
        ! Last argument of previous command
        value = trim(shell%last_arg)
        return
      case ('-')
        ! Current shell options as flags
        value = get_shell_option_flags(shell)
        return
      case ('PPID')
        write(fmt_buf, '(i0)') int(shell%parent_pid)
        value = trim(adjustl(fmt_buf))
        return
      case ('UID')
        write(fmt_buf, '(i0)') shell%uid
        value = trim(adjustl(fmt_buf))
        return
      case ('EUID')
        write(fmt_buf, '(i0)') shell%euid
        value = trim(adjustl(fmt_buf))
        return
      case ('PWD')
        value = trim(shell%cwd)
        return
      case ('OLDPWD')
        value = trim(shell%oldpwd)
        return
      case ('RANDOM')
        write(fmt_buf, '(i0)') get_random_int()
        value = trim(adjustl(fmt_buf))
        return
      case ('SECONDS')
        write(fmt_buf, '(i0)') get_elapsed_seconds(shell)
        value = trim(adjustl(fmt_buf))
        return
      case ('LINENO')
        write(fmt_buf, '(i0)') shell%current_line_number
        value = trim(adjustl(fmt_buf))
        return
      case ('#')
        write(fmt_buf, '(I0)') shell%num_positional
        value = trim(adjustl(fmt_buf))
        return
      case ('*')
        block
          character(len=4096) :: params_buf
          call get_all_positional_params(shell, params_buf, .true.)
          value = trim(params_buf)
        end block
        return
      case ('@')
        block
          character(len=4096) :: params_buf
          call get_all_positional_params(shell, params_buf, .false.)
          value = trim(params_buf)
        end block
        return
      case ('IFS')
        ! Internal field separator - use ifs_len to preserve whitespace
        if (shell%ifs_len > 0) then
          value = shell%ifs(1:shell%ifs_len)
        else
          value = ''
        end if
        return
      case ('PS1')
        value = shell%ps1
        return
      case ('PS2')
        value = shell%ps2
        return
      case ('PS3')
        value = shell%ps3
        return
      case ('PS4')
        value = shell%ps4
        return
      case ('HISTFILE')
        value = trim(shell%histfile)
        return
      case ('HISTSIZE')
        write(fmt_buf, '(i0)') shell%histsize
        value = trim(adjustl(fmt_buf))
        return
      case ('HISTFILESIZE')
        write(fmt_buf, '(i0)') shell%histfilesize
        value = trim(adjustl(fmt_buf))
        return
      case ('HISTCONTROL')
        value = trim(shell%histcontrol)
        return
    end select
    
    ! Handle numeric positional parameters ($1, $2, ..., $n)
    if (is_numeric(trim(name))) then
      i = string_to_int(trim(name))
      if (i >= 1 .and. i <= shell%num_positional) then
        value = trim(shell%positional_params(i)%str)
        return
      else
        value = ''
        return
      end if
    end if
    
    ! Handle regular shell variables
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        ! Use value_len to preserve trailing whitespace
        if (shell%variables(i)%value_len > 0) then
          value = shell%variables(i)%value(1:shell%variables(i)%value_len)
        else
          value = shell%variables(i)%value
        end if
        return
      end if
    end do

    ! Handle environment variables if not found in shell variables
    value = get_environment_var(trim(name))
  end function

  function is_shell_variable_set(shell, name) result(is_set)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    logical :: is_set
    integer :: i, depth

    is_set = .false.

    ! First check local variables (innermost scope first)
    if (shell%function_depth > 0) then
      do depth = shell%function_depth, 1, -1
        if (depth <= size(shell%local_var_counts)) then
          do i = 1, shell%local_var_counts(depth)
            if (trim(shell%local_vars(depth, i)%name) == trim(name)) then
              ! value_len=-1 means explicitly unset local (shadows global)
              if (shell%local_vars(depth, i)%value_len == -1) then
                is_set = .false.
              else
                is_set = .true.
              end if
              return
            end if
          end do
        end if
      end do
    end if

    ! Check special variables (most are always set)
    select case (trim(name))
      case ('$', '!', '?', '0', '_', '-', 'PPID', 'UID', 'EUID', &
            'PWD', 'OLDPWD', 'RANDOM', 'SECONDS', 'LINENO', '#', '*', '@', &
            'IFS', 'PS1', 'PS2', 'PS3', 'PS4', 'HISTFILE', 'HISTSIZE', &
            'HISTFILESIZE', 'HISTCONTROL')
        is_set = .true.
        return
    end select

    ! Handle numeric positional parameters ($1, $2, ..., $n)
    if (is_numeric(trim(name))) then
      i = string_to_int(trim(name))
      if (i >= 1 .and. i <= shell%num_positional) then
        is_set = .true.
        return
      end if
    end if

    ! Check regular shell variables
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        is_set = .true.
        return
      end if
    end do

    ! Check environment variables
    if (len_trim(get_environment_var(trim(name))) > 0) then
      is_set = .true.
    end if
  end function

  ! Get the actual length of a shell variable (preserving whitespace)
  function get_shell_variable_length(shell, name) result(var_len)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    integer :: var_len
    integer :: i, depth
    character(len=20) :: temp_value

    var_len = 0

    ! First check local variables (innermost scope first)
    if (shell%function_depth > 0) then
      do depth = shell%function_depth, 1, -1
        if (depth <= size(shell%local_var_counts)) then
          do i = 1, shell%local_var_counts(depth)
            if (trim(shell%local_vars(depth, i)%name) == trim(name)) then
              ! value_len=-1 means explicitly unset local
              if (shell%local_vars(depth, i)%value_len == -1) then
                var_len = 0
              else
                var_len = len_trim(shell%local_vars(depth, i)%value)
              end if
              return
            end if
          end do
        end if
      end do
    end if

    ! Handle special variables
    select case (trim(name))
      case ('IFS')
        ! Use ifs_len to preserve whitespace (even if it's all spaces)
        var_len = shell%ifs_len
        return
      case ('PS1')
        var_len = shell%ps1_len
        return
      case ('PS2')
        var_len = shell%ps2_len
        return
      case ('PS3')
        var_len = shell%ps3_len
        return
      case ('PS4')
        var_len = shell%ps4_len
        return
      case ('PWD')
        var_len = len_trim(shell%cwd)
        return
      case ('OLDPWD')
        var_len = len_trim(shell%oldpwd)
        return
      case ('?')
        write(temp_value, '(i15)') shell%last_exit_status
        var_len = len_trim(adjustl(temp_value))
        return
      case ('#')
        write(temp_value, '(i15)') shell%num_positional
        var_len = len_trim(adjustl(temp_value))
        return
      case ('0')
        var_len = len_trim(shell%shell_name)
        return
      case ('$')
        write(temp_value, '(i0)') shell%shell_pid
        var_len = len_trim(temp_value)
        return
      case ('PPID')
        write(temp_value, '(i15)') shell%parent_pid
        var_len = len_trim(adjustl(temp_value))
        return
      case ('UID')
        write(temp_value, '(i15)') shell%uid
        var_len = len_trim(adjustl(temp_value))
        return
      case ('EUID')
        write(temp_value, '(i15)') shell%euid
        var_len = len_trim(adjustl(temp_value))
        return
      case ('SECONDS')
        var_len = 10  ! Max digits for seconds
        return
      case ('RANDOM')
        var_len = 5  ! Max digits for RANDOM (0-32767)
        return
      case ('LINENO')
        write(temp_value, '(i15)') shell%current_line_number
        var_len = len_trim(adjustl(temp_value))
        return
      case ('HISTFILE')
        var_len = len_trim(shell%histfile)
        return
      case ('HISTSIZE')
        write(temp_value, '(i15)') shell%histsize
        var_len = len_trim(adjustl(temp_value))
        return
      case ('HISTFILESIZE')
        write(temp_value, '(i15)') shell%histfilesize
        var_len = len_trim(adjustl(temp_value))
        return
      case ('HISTCONTROL')
        var_len = len_trim(shell%histcontrol)
        return
      ! Note: No case default here - fall through to regular variable handling
    end select

    ! Handle regular shell variables
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        ! Use value_len to preserve trailing whitespace
        if (shell%variables(i)%value_len > 0) then
          var_len = shell%variables(i)%value_len
        else
          var_len = len_trim(shell%variables(i)%value)
        end if
        return
      end if
    end do

    ! Check environment variables
    block
      character(len=:), allocatable :: env_val
      env_val = get_environment_var(trim(name))
      if (allocated(env_val) .and. len(env_val) > 0) then
        var_len = len(env_val)
        return
      end if
    end block

    ! Not found - return 0
    var_len = 0
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
    integer :: eq_pos, bracket_pos, bracket_end, array_index, read_status
    integer :: actual_value_len, i
    character(len=256) :: var_name, index_str
    character(len=:), allocatable :: var_value
    character(len=:), allocatable :: expanded_value
    character(len=1) :: quote_char_temp

    eq_pos = index(input_line, '=')
    if (eq_pos > 1) then
      var_name = input_line(:eq_pos-1)
      var_value = input_line(eq_pos+1:)

      ! Calculate actual content length BEFORE stripping quotes (to preserve trailing spaces)
      actual_value_len = len_trim(var_value)
      if (actual_value_len >= 2) then
        if (var_value(1:1) == "'" .or. var_value(1:1) == '"') then
          ! Find closing quote position by searching backwards
          quote_char_temp = var_value(1:1)
          do i = actual_value_len, 2, -1
            if (var_value(i:i) == quote_char_temp) then
              ! Content length is closing_quote_pos - 2
              actual_value_len = i - 2
              exit
            end if
          end do
        else
          ! No quotes, use len_trim
          actual_value_len = len_trim(var_value)
        end if
      else
        actual_value_len = len_trim(var_value)
      end if

      ! Strip surrounding quotes from value
      call strip_quotes(var_value)

      ! Check for indexed/associative array assignment: arr[index]=value or map[key]=value
      bracket_pos = index(var_name, '[')
      if (bracket_pos > 0) then
        ! arr[index]=value or map[key]=value
        bracket_end = index(var_name(bracket_pos:), ']')
        if (bracket_end > 0) then
          bracket_end = bracket_pos + bracket_end - 1
          index_str = var_name(bracket_pos+1:bracket_end-1)
          var_name = var_name(:bracket_pos-1)

          ! Strip quotes and lexer sentinel chars from array key
          call strip_quotes(index_str)
          block
            character(len=100) :: clean_key
            integer :: ci, co
            co = 0
            clean_key = ''
            do ci = 1, len_trim(index_str)
              if (ichar(index_str(ci:ci)) > 3) then
                co = co + 1
                clean_key(co:co) = index_str(ci:ci)
              end if
            end do
            index_str = clean_key
          end block

          ! Check if this is an associative array
          if (is_associative_array(shell, trim(var_name))) then
            ! Associative array: use key as-is
            call set_assoc_array_value(shell, trim(var_name), trim(index_str), trim(var_value))
            shell%last_exit_status = 0
          else
            ! Try to parse as numeric index for indexed array
            read(index_str, *, iostat=read_status) array_index
            if (read_status == 0) then
              ! Valid numeric index
              array_index = array_index + 1  ! Convert to 1-indexed
              call set_array_element(shell, trim(var_name), array_index, trim(var_value))
              shell%last_exit_status = 0
            else
              ! Non-numeric index for non-associative array - error or treat as associative
              call set_assoc_array_value(shell, trim(var_name), trim(index_str), trim(var_value))
              shell%last_exit_status = 0
            end if
          end if
        else
          shell%last_exit_status = 1
        end if
        return
      end if

      ! Check for array literal assignment: var=(value1 value2 value3)
      if (len_trim(var_value) > 2 .and. var_value(1:1) == '(' .and. &
          var_value(len_trim(var_value):len_trim(var_value)) == ')') then
        call handle_array_assignment(shell, trim(var_name), var_value)
      else
        ! Simple variable expansion during assignment
        ! Check if value needs expansion (contains $ or ~)
        if (index(var_value, '$') > 0 .or. index(var_value, '~') > 0) then
          ! Needs expansion
          call simple_expand_variables(var_value, expanded_value, shell)
          ! For expanded values, use the allocated length
          call set_shell_variable(shell, trim(var_name), expanded_value, len(expanded_value))
        else
          ! No expansion needed, preserve trailing spaces
          call set_shell_variable(shell, trim(var_name), var_value, actual_value_len)
        end if
      end if
      ! Set exit status to 0 for successful assignments
      ! Don't overwrite error codes like 1 (readonly violation)
      if (shell%last_exit_status /= 1) then
        shell%last_exit_status = 0
      end if
    else
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine handle_array_assignment(shell, var_name, array_expr)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: var_name, array_expr
    ! Use allocatable array to avoid static storage
    character(len=MAX_VAR_VALUE_LEN), allocatable :: values(:)
    integer :: count, start_pos, pos, capacity
    character(len=:), allocatable :: content
    logical :: in_quotes
    
    ! Remove parentheses
    content = array_expr(2:len_trim(array_expr)-1)

    ! Allocate initial array
    allocate(values(20))  ! Start with reasonable size
    capacity = 20
    count = 0
    pos = 1
    start_pos = 1
    in_quotes = .false.

    ! Parse space-separated values, respecting quotes
    do while (pos <= len_trim(content))
      if (content(pos:pos) == '"' .or. content(pos:pos) == "'") then
        in_quotes = .not. in_quotes
      else if (content(pos:pos) == ' ' .and. .not. in_quotes) then
        if (pos > start_pos) then
          count = count + 1
          ! Grow array if needed
          if (count > capacity) then
            call grow_string_array(values, capacity)
          end if
          values(count) = content(start_pos:pos-1)
          ! Remove quotes if present
          if (len_trim(values(count)) >= 2) then
            if ((values(count)(1:1) == '"' .and. values(count)(len_trim(values(count)):len_trim(values(count))) == '"') .or. &
                (values(count)(1:1) == "'" .and. values(count)(len_trim(values(count)):len_trim(values(count))) == "'")) then
              values(count) = values(count)(2:len_trim(values(count))-1)
            end if
          end if
        end if
        start_pos = pos + 1
      end if
      pos = pos + 1
    end do
    
    ! Handle last value
    if (start_pos <= len_trim(content)) then
      count = count + 1
      ! Grow array if needed
      if (count > capacity) then
        call grow_string_array(values, capacity)
      end if
      values(count) = content(start_pos:)
      ! Remove quotes if present
      if (len_trim(values(count)) >= 2) then
        if ((values(count)(1:1) == '"' .and. values(count)(len_trim(values(count)):len_trim(values(count))) == '"') .or. &
            (values(count)(1:1) == "'" .and. values(count)(len_trim(values(count)):len_trim(values(count))) == "'")) then
          values(count) = values(count)(2:len_trim(values(count))-1)
        end if
      end if
    end if
    
    if (count > 0) then
      call set_array_variable(shell, var_name, values(1:count), count)
    end if

    ! Clean up allocatable array
    if (allocated(values)) deallocate(values)
  end subroutine

  ! Helper subroutine to grow string array
  subroutine grow_string_array(array, current_size)
    character(len=MAX_VAR_VALUE_LEN), allocatable, intent(inout) :: array(:)
    integer, intent(inout) :: current_size
    character(len=MAX_VAR_VALUE_LEN), allocatable :: new_array(:)
    integer :: new_size

    new_size = current_size * 2
    allocate(new_array(new_size))

    ! Copy existing data
    new_array(1:current_size) = array(1:current_size)

    ! Swap arrays
    call move_alloc(new_array, array)
    current_size = new_size
  end subroutine

  subroutine simple_expand_variables(input, expanded, shell)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(inout) :: shell
    
    character(len=2048) :: result
    integer :: i, j, var_start, brace_end
    character(len=256) :: var_name
    character(len=:), allocatable :: expansion_result, var_value
    character(len=:), allocatable :: env_value
    
    result = ''
    i = 1
    j = 1
    
    do while (i <= len_trim(input))
      if (input(i:i) == '$' .and. i < len_trim(input)) then
        i = i + 1
        
        ! Handle ${parameter} expansions
        if (i <= len_trim(input) .and. input(i:i) == '{') then
          i = i + 1
          brace_end = index(input(i:), '}')
          if (brace_end > 0) then
            brace_end = brace_end + i - 1
            call expand_parameter(input(i:brace_end-1), expansion_result, shell)
            if (len_trim(expansion_result) > 0) then
              result(j:j+len_trim(expansion_result)-1) = trim(expansion_result)
              j = j + len_trim(expansion_result)
            end if
            i = brace_end + 1
          else
            ! Malformed ${, treat as literal
            result(j:j) = '$'
            result(j+1:j+1) = '{'
            j = j + 2
          end if
        else
          ! Handle simple $variable expansions
          var_start = i

          ! Check for special single-character variables first
          if (i <= len_trim(input)) then
            select case (input(i:i))
              case ('!', '?', '$', '#', '*', '@', '-', '_', '0')
                ! Single-character special variable
                var_name = input(i:i)
                i = i + 1
              case default
                ! Extract alphanumeric variable name
                do while (i <= len_trim(input))
                  if (.not. (is_alnum(input(i:i)) .or. input(i:i) == '_')) exit
                  i = i + 1
                end do
                var_name = input(var_start:i-1)
            end select
          else
            var_name = ''
          end if

          ! Check shell variables first
          if (len_trim(var_name) > 0) then
            var_value = get_shell_variable(shell, trim(var_name))
            block
              integer :: var_len
              var_len = get_shell_variable_length(shell, trim(var_name))
              if (var_len > 0) then
                ! Use actual length to preserve trailing whitespace
                result(j:j+var_len-1) = var_value(1:var_len)
                j = j + var_len
              else if (len_trim(var_value) > 0) then
                ! Fallback for compatibility
                result(j:j+len_trim(var_value)-1) = trim(var_value)
                j = j + len_trim(var_value)
              else
                ! Fall back to environment variables (not for special vars)
                if (.not. any(var_name == ['!', '?', '$', '#', '*', '@', '-', '_', '0'])) then
                  env_value = get_environment_var(trim(var_name))
                  if (allocated(env_value) .and. len(env_value) > 0) then
                    result(j:j+len(env_value)-1) = env_value
                    j = j + len(env_value)
                  end if
                end if
              end if
            end block
          end if
        end if
      else
        result(j:j) = input(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    ! Don't use trim() - preserve trailing whitespace
    if (j > 1) then
      expanded = result(1:j-1)
    else
      expanded = ''
    end if

  contains
    function is_alnum(ch) result(res)
      character, intent(in) :: ch
      logical :: res
      res = (ch >= 'a' .and. ch <= 'z') .or. &
            (ch >= 'A' .and. ch <= 'Z') .or. &
            (ch >= '0' .and. ch <= '9')
    end function
  end subroutine

  subroutine add_function(shell, name, body_lines, body_count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: name
    character(len=*), intent(in) :: body_lines(:)
    integer, intent(in) :: body_count
    integer :: i, j

    ! Find empty slot or replace existing function
    do i = 1, size(shell%functions)
      if (trim(shell%functions(i)%name) == trim(name) .or. len_trim(shell%functions(i)%name) == 0) then
        shell%functions(i)%name = name
        shell%functions(i)%body_lines = body_count

        if (allocated(shell%functions(i)%body)) deallocate(shell%functions(i)%body)
        allocate(shell%functions(i)%body(body_count))

        do j = 1, body_count
          shell%functions(i)%body(j)%str = trim(body_lines(j))
        end do

        ! Update function count to include this function
        shell%num_functions = max(shell%num_functions, i)
        return
      end if
    end do
  end subroutine

  function is_function(shell, name) result(found)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    logical :: found
    integer :: i
    
    found = .false.
    do i = 1, shell%num_functions
      if (trim(shell%functions(i)%name) == trim(name)) then
        found = .true.
        return
      end if
    end do
  end function

  function get_function_body(shell, name) result(body)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    type(string_t), allocatable :: body(:)
    integer :: i, j

    do i = 1, shell%num_functions
      if (trim(shell%functions(i)%name) == trim(name)) then
        if (allocated(shell%functions(i)%body)) then
          allocate(body(shell%functions(i)%body_lines))
          do j = 1, shell%functions(i)%body_lines
            body(j)%str = shell%functions(i)%body(j)%str
          end do
        end if
        return
      end if
    end do
  end function

  ! Array variable functions
  subroutine set_array_variable(shell, name, values, count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: name
    character(len=*), intent(in) :: values(:)
    integer, intent(in) :: count
    integer :: i, k, empty_slot

    empty_slot = -1

    ! Check if variable already exists
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        if (allocated(shell%variables(i)%array_values)) deallocate(shell%variables(i)%array_values)
        allocate(shell%variables(i)%array_values(count))
        do k = 1, count
          shell%variables(i)%array_values(k)%str = trim(values(k))
        end do
        shell%variables(i)%array_size = count
        shell%variables(i)%is_array = .true.
        return
      end if
    end do

    ! Find empty slot
    do i = 1, size(shell%variables)
      if (shell%variables(i)%name(1:1) == char(0) .or. trim(shell%variables(i)%name) == '') then
        empty_slot = i
        exit
      end if
    end do

    ! Add new array variable
    if (empty_slot > 0) then
      shell%variables(empty_slot)%name = name
      shell%variables(empty_slot)%is_array = .true.
      shell%variables(empty_slot)%array_size = count
      if (allocated(shell%variables(empty_slot)%array_values)) deallocate(shell%variables(empty_slot)%array_values)
      allocate(shell%variables(empty_slot)%array_values(count))
      do k = 1, count
        shell%variables(empty_slot)%array_values(k)%str = trim(values(k))
      end do
      shell%num_variables = shell%num_variables + 1
    end if
  end subroutine

  ! Set a single element in an array at the given index (1-indexed)
  subroutine set_array_element(shell, name, index, value)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: name
    integer, intent(in) :: index
    character(len=*), intent(in) :: value
    integer :: i, k, empty_slot, new_size
    type(string_t), allocatable :: temp_array(:)

    ! Check if variable already exists
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        ! Variable exists - make sure it's an array
        if (.not. shell%variables(i)%is_array) then
          ! Convert to array
          shell%variables(i)%is_array = .true.
          if (allocated(shell%variables(i)%array_values)) deallocate(shell%variables(i)%array_values)
          allocate(shell%variables(i)%array_values(index))
          do k = 1, index
            shell%variables(i)%array_values(k)%str = ''
          end do
          shell%variables(i)%array_size = index
        else if (.not. allocated(shell%variables(i)%array_values)) then
          ! Array exists but not allocated (from declare -a)
          allocate(shell%variables(i)%array_values(index))
          do k = 1, index
            shell%variables(i)%array_values(k)%str = ''
          end do
          shell%variables(i)%array_size = index
        else if (index > shell%variables(i)%array_size) then
          ! Need to expand the array (sparse array support)
          new_size = index
          allocate(temp_array(new_size))
          do k = 1, new_size
            temp_array(k)%str = ''
          end do
          if (shell%variables(i)%array_size > 0 .and. allocated(shell%variables(i)%array_values)) then
            do k = 1, shell%variables(i)%array_size
              temp_array(k)%str = shell%variables(i)%array_values(k)%str
            end do
          end if
          if (allocated(shell%variables(i)%array_values)) deallocate(shell%variables(i)%array_values)
          allocate(shell%variables(i)%array_values(new_size))
          do k = 1, new_size
            shell%variables(i)%array_values(k)%str = temp_array(k)%str
          end do
          shell%variables(i)%array_size = new_size
          deallocate(temp_array)
        end if

        ! Set the element
        shell%variables(i)%array_values(index)%str = value
        return
      end if
    end do

    ! Variable doesn't exist - create new array
    empty_slot = -1
    do i = 1, size(shell%variables)
      if (shell%variables(i)%name(1:1) == char(0) .or. trim(shell%variables(i)%name) == '') then
        empty_slot = i
        exit
      end if
    end do

    if (empty_slot > 0) then
      shell%variables(empty_slot)%name = name
      shell%variables(empty_slot)%is_array = .true.
      shell%variables(empty_slot)%array_size = index
      allocate(shell%variables(empty_slot)%array_values(index))
      do k = 1, index
        shell%variables(empty_slot)%array_values(k)%str = ''
      end do
      shell%variables(empty_slot)%array_values(index)%str = value
      shell%num_variables = shell%num_variables + 1
    end if
  end subroutine

  function get_array_element(shell, name, index) result(value)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    integer, intent(in) :: index
    character(len=:), allocatable :: value
    integer :: i, actual_index

    value = ''

    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name) .and. shell%variables(i)%is_array) then
        actual_index = index
        ! Bash: negative indices count from end (-1 = last element)
        if (actual_index < 0) then
          actual_index = shell%variables(i)%array_size + actual_index + 1
        end if
        if (actual_index >= 1 .and. actual_index <= shell%variables(i)%array_size) then
          value = shell%variables(i)%array_values(actual_index)%str
        end if
        return
      end if
    end do
  end function

  function get_array_all_elements(shell, name) result(result_str)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    character(len=4096) :: result_str
    integer :: i, j, pos
    logical :: first

    result_str = ''
    pos = 1
    first = .true.

    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name) .and. shell%variables(i)%is_array) then
        do j = 1, shell%variables(i)%array_size
          if (.not. allocated(shell%variables(i)%array_values(j)%str)) cycle
          if (len_trim(shell%variables(i)%array_values(j)%str) == 0) cycle
          if (.not. first) then
            result_str(pos:pos) = ' '
            pos = pos + 1
          end if
          first = .false.
          result_str(pos:pos+len_trim(shell%variables(i)%array_values(j)%str)-1) = &
            trim(shell%variables(i)%array_values(j)%str)
          pos = pos + len_trim(shell%variables(i)%array_values(j)%str)
        end do
        return
      end if
    end do
  end function

  function get_array_size(shell, name) result(size)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    integer :: size
    integer :: i
    
    size = 0
    
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name) .and. shell%variables(i)%is_array) then
        size = shell%variables(i)%array_size
        return
      end if
    end do
  end function

  subroutine declare_associative_array(shell, name)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: name
    
    integer :: i, empty_slot
    
    empty_slot = -1
    
    ! Check if variable already exists
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        ! Convert to associative array
        shell%variables(i)%is_assoc_array = .true.
        shell%variables(i)%is_array = .false.
        if (.not. allocated(shell%variables(i)%assoc_entries)) then
          allocate(shell%variables(i)%assoc_entries(50))  ! Initial size
        end if
        shell%variables(i)%assoc_size = 0
        return
      end if
    end do
    
    ! Find empty slot  
    do i = 1, size(shell%variables)
      if (shell%variables(i)%name(1:1) == char(0) .or. trim(shell%variables(i)%name) == '') then
        empty_slot = i
        exit
      end if
    end do
    
    ! Add new associative array variable
    if (empty_slot > 0) then
      shell%variables(empty_slot)%name = name
      shell%variables(empty_slot)%value = ''
      shell%variables(empty_slot)%is_assoc_array = .true.
      shell%variables(empty_slot)%is_array = .false.
      allocate(shell%variables(empty_slot)%assoc_entries(50))
      shell%variables(empty_slot)%assoc_size = 0
      shell%num_variables = shell%num_variables + 1
    else
      write(error_unit, '(a)') 'declare: too many variables defined'
    end if
  end subroutine

  subroutine set_assoc_array_value(shell, array_name, key, value)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: array_name, key, value
    
    integer :: i, j
    
    ! Find the associative array variable
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(array_name) .and. &
          shell%variables(i)%is_assoc_array) then
        
        ! Check if key already exists
        do j = 1, shell%variables(i)%assoc_size
          if (trim(shell%variables(i)%assoc_entries(j)%key) == trim(key)) then
            shell%variables(i)%assoc_entries(j)%value = value
            return
          end if
        end do
        
        ! Add new key-value pair
        if (shell%variables(i)%assoc_size < size(shell%variables(i)%assoc_entries)) then
          shell%variables(i)%assoc_size = shell%variables(i)%assoc_size + 1
          shell%variables(i)%assoc_entries(shell%variables(i)%assoc_size)%key = key
          shell%variables(i)%assoc_entries(shell%variables(i)%assoc_size)%value = value
        else
          write(error_unit, '(a)') 'associative array: too many entries'
        end if
        return
      end if
    end do
    
    write(error_unit, '(a)') 'associative array: ' // trim(array_name) // ' not declared'
  end subroutine

  function get_assoc_array_value(shell, array_name, key) result(value)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: array_name, key
    character(len=:), allocatable :: value
    
    integer :: i, j
    
    value = ''
    
    ! Find the associative array variable
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(array_name) .and. &
          shell%variables(i)%is_assoc_array) then
        
        ! Find the key
        do j = 1, shell%variables(i)%assoc_size
          if (trim(shell%variables(i)%assoc_entries(j)%key) == trim(key)) then
            value = shell%variables(i)%assoc_entries(j)%value
            return
          end if
        end do
        return  ! Key not found, return empty string
      end if
    end do
  end function

  subroutine get_assoc_array_keys(shell, array_name, keys, num_keys)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: array_name
    character(len=256), intent(out) :: keys(:)
    integer, intent(out) :: num_keys
    
    integer :: i, j
    
    num_keys = 0
    
    ! Find the associative array variable
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(array_name) .and. &
          shell%variables(i)%is_assoc_array) then
        
        num_keys = min(shell%variables(i)%assoc_size, size(keys))
        do j = 1, num_keys
          keys(j) = shell%variables(i)%assoc_entries(j)%key
        end do
        return
      end if
    end do
  end subroutine

  subroutine unset_assoc_array_key(shell, array_name, key)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: array_name, key
    integer :: i, j, k

    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(array_name) .and. &
          shell%variables(i)%is_assoc_array) then
        do j = 1, shell%variables(i)%assoc_size
          if (trim(shell%variables(i)%assoc_entries(j)%key) == trim(key)) then
            ! Shift remaining entries down
            do k = j, shell%variables(i)%assoc_size - 1
              shell%variables(i)%assoc_entries(k) = &
                shell%variables(i)%assoc_entries(k+1)
            end do
            shell%variables(i)%assoc_size = &
              shell%variables(i)%assoc_size - 1
            return
          end if
        end do
        return
      end if
    end do
  end subroutine

  function is_associative_array(shell, name) result(is_assoc)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    logical :: is_assoc
    
    integer :: i
    
    is_assoc = .false.
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        is_assoc = shell%variables(i)%is_assoc_array
        return
      end if
    end do
  end function

  ! POSIX parameter expansion implementation
  subroutine expand_parameter(param_expr, result, shell)
    character(len=*), intent(in) :: param_expr
    character(len=:), allocatable, intent(out) :: result
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: param_name, default_value
    character(len=:), allocatable :: var_value
    character(len=:), allocatable :: expanded_pattern_buf
    integer :: colon_pos, dash_pos, plus_pos, eq_pos, question_pos
    integer :: percent_pos, hash_pos, percent2_pos, hash2_pos
    logical :: has_colon
    
    result = ''
    
    ! Check for various POSIX parameter expansion forms
    colon_pos = index(param_expr, ':')
    has_colon = colon_pos > 0
    
    ! ${parameter:-word} or ${parameter-word}
    if (has_colon) then
      dash_pos = index(param_expr(colon_pos:), '-')
      if (dash_pos > 0) then
        dash_pos = dash_pos + colon_pos - 1
        param_name = param_expr(:colon_pos-1)
        default_value = param_expr(dash_pos+1:)
      end if
    else
      dash_pos = index(param_expr, '-')
      if (dash_pos > 0) then
        param_name = param_expr(:dash_pos-1)
        default_value = param_expr(dash_pos+1:)
      end if
    end if
    
    if (dash_pos > 0) then
      var_value = get_shell_variable(shell, trim(param_name))
      if (has_colon) then
        ! ${parameter:-word} - use default if unset or null
        if (len_trim(var_value) == 0) then
          result = trim(default_value)
        else
          result = trim(var_value)
        end if
      else
        ! ${parameter-word} - use default if unset only
        if (len_trim(var_value) == 0 .and. .not. variable_exists(shell, trim(param_name))) then
          result = trim(default_value)
        else
          result = trim(var_value)
        end if
      end if
      return
    end if
    
    ! ${parameter:=word} or ${parameter=word}
    if (has_colon) then
      eq_pos = index(param_expr(colon_pos:), '=')
      if (eq_pos > 0) then
        eq_pos = eq_pos + colon_pos - 1
        param_name = param_expr(:colon_pos-1)
        default_value = param_expr(eq_pos+1:)
      end if
    else
      eq_pos = index(param_expr, '=')
      if (eq_pos > 0) then
        param_name = param_expr(:eq_pos-1)
        default_value = param_expr(eq_pos+1:)
      end if
    end if
    
    if (eq_pos > 0) then
      var_value = get_shell_variable(shell, trim(param_name))
      if (has_colon) then
        ! ${parameter:=word} - assign default if unset or null
        if (len_trim(var_value) == 0) then
          call set_shell_variable(shell, trim(param_name), trim(default_value))
          result = trim(default_value)
        else
          result = trim(var_value)
        end if
      else
        ! ${parameter=word} - assign default if unset only
        if (len_trim(var_value) == 0 .and. .not. variable_exists(shell, trim(param_name))) then
          call set_shell_variable(shell, trim(param_name), trim(default_value))
          result = trim(default_value)
        else
          result = trim(var_value)
        end if
      end if
      return
    end if
    
    ! ${parameter:?word} or ${parameter?word}
    if (has_colon) then
      question_pos = index(param_expr(colon_pos:), '?')
      if (question_pos > 0) then
        question_pos = question_pos + colon_pos - 1
        param_name = param_expr(:colon_pos-1)
        default_value = param_expr(question_pos+1:)
      end if
    else
      question_pos = index(param_expr, '?')
      if (question_pos > 0) then
        param_name = param_expr(:question_pos-1)
        default_value = param_expr(question_pos+1:)
      end if
    end if
    
    if (question_pos > 0) then
      var_value = get_shell_variable(shell, trim(param_name))
      if (has_colon) then
        ! ${parameter:?word} - error if unset or null
        if (len_trim(var_value) == 0) then
          ! TODO: Should write error and exit
          result = trim(param_name) // ': ' // trim(default_value)
        else
          result = trim(var_value)
        end if
      else
        ! ${parameter?word} - error if unset only
        if (len_trim(var_value) == 0 .and. .not. variable_exists(shell, trim(param_name))) then
          ! TODO: Should write error and exit
          result = trim(param_name) // ': ' // trim(default_value)
        else
          result = trim(var_value)
        end if
      end if
      return
    end if
    
    ! ${parameter:+word} or ${parameter+word}
    if (has_colon) then
      plus_pos = index(param_expr(colon_pos:), '+')
      if (plus_pos > 0) then
        plus_pos = plus_pos + colon_pos - 1
        param_name = param_expr(:colon_pos-1)
        default_value = param_expr(plus_pos+1:)
      end if
    else
      plus_pos = index(param_expr, '+')
      if (plus_pos > 0) then
        param_name = param_expr(:plus_pos-1)
        default_value = param_expr(plus_pos+1:)
      end if
    end if
    
    if (plus_pos > 0) then
      var_value = get_shell_variable(shell, trim(param_name))
      if (has_colon) then
        ! ${parameter:+word} - use word if set and not null
        if (len_trim(var_value) > 0) then
          result = trim(default_value)
        else
          result = ''
        end if
      else
        ! ${parameter+word} - use word if set
        if (variable_exists(shell, trim(param_name))) then
          result = trim(default_value)
        else
          result = ''
        end if
      end if
      return
    end if
    
    ! ${parameter%word} - remove smallest suffix pattern
    percent_pos = index(param_expr, '%', back=.true.)
    if (percent_pos > 0 .and. param_expr(percent_pos-1:percent_pos-1) /= '%') then
      param_name = param_expr(:percent_pos-1)
      default_value = param_expr(percent_pos+1:)
      var_value = get_shell_variable(shell, trim(param_name))
      ! Expand simple $var in pattern
      expanded_pattern_buf = default_value
      if (index(default_value, '$') == 1) then
        ! Simple $var expansion (not ${} or $())
        if (len_trim(default_value) >= 2) then
          if (default_value(2:2) /= '{' .and. default_value(2:2) /= '(') then
            expanded_pattern_buf = get_shell_variable(shell, trim(default_value(2:)))
          end if
        end if
      end if
      call remove_suffix_pattern(trim(var_value), trim(expanded_pattern_buf), result, .false.)
      return
    end if

    ! ${parameter%%word} - remove largest suffix pattern
    percent2_pos = index(param_expr, '%%')
    if (percent2_pos > 0) then
      param_name = param_expr(:percent2_pos-1)
      default_value = param_expr(percent2_pos+2:)
      var_value = get_shell_variable(shell, trim(param_name))
      ! Expand simple $var in pattern
      if (len_trim(default_value) > 1 .and. default_value(1:1) == '$' .and. &
          default_value(2:2) /= '{' .and. default_value(2:2) /= '(') then
        expanded_pattern_buf = get_shell_variable(shell, trim(default_value(2:)))
      else
        expanded_pattern_buf = default_value
      end if
      call remove_suffix_pattern(trim(var_value), trim(expanded_pattern_buf), result, .true.)
      return
    end if

    ! ${parameter#word} - remove smallest prefix pattern
    hash_pos = index(param_expr, '#')
    if (hash_pos > 0 .and. param_expr(hash_pos:hash_pos+1) /= '##') then
      param_name = param_expr(:hash_pos-1)
      default_value = param_expr(hash_pos+1:)
      var_value = get_shell_variable(shell, trim(param_name))
      ! Expand simple $var in pattern
      if (len_trim(default_value) > 1 .and. default_value(1:1) == '$' .and. &
          default_value(2:2) /= '{' .and. default_value(2:2) /= '(') then
        expanded_pattern_buf = get_shell_variable(shell, trim(default_value(2:)))
      else
        expanded_pattern_buf = default_value
      end if
      call remove_prefix_pattern(trim(var_value), trim(expanded_pattern_buf), result, .false.)
      return
    end if

    ! ${parameter##word} - remove largest prefix pattern
    hash2_pos = index(param_expr, '##')
    if (hash2_pos > 0) then
      param_name = param_expr(:hash2_pos-1)
      default_value = param_expr(hash2_pos+2:)
      var_value = get_shell_variable(shell, trim(param_name))
      ! Expand simple $var in pattern
      if (len_trim(default_value) > 1 .and. default_value(1:1) == '$' .and. &
          default_value(2:2) /= '{' .and. default_value(2:2) /= '(') then
        expanded_pattern_buf = get_shell_variable(shell, trim(default_value(2:)))
      else
        expanded_pattern_buf = default_value
      end if
      call remove_prefix_pattern(trim(var_value), trim(expanded_pattern_buf), result, .true.)
      return
    end if
    
    ! Simple ${parameter} expansion
    result = trim(get_shell_variable(shell, trim(param_expr)))
  end subroutine
  
  function variable_exists(shell, name) result(exists)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    logical :: exists
    integer :: i
    
    exists = .false.
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        exists = .true.
        return
      end if
    end do
  end function
  
  subroutine remove_suffix_pattern(value, pattern, result, largest)
    character(len=*), intent(in) :: value, pattern
    character(len=*), intent(out) :: result
    logical, intent(in) :: largest
    
    integer :: i, match_pos
    
    result = value
    match_pos = 0
    
    ! Simple pattern matching - exact match only for now
    ! TODO: Add full glob pattern support
    if (largest) then
      ! Find rightmost match
      do i = len_trim(value), len_trim(pattern), -1
        if (value(i-len_trim(pattern)+1:i) == pattern) then
          match_pos = i - len_trim(pattern) + 1
          exit
        end if
      end do
    else
      ! Find leftmost match from the right
      do i = len_trim(value) - len_trim(pattern) + 1, 1, -1
        if (value(i:i+len_trim(pattern)-1) == pattern) then
          match_pos = i
        end if
      end do
    end if
    
    if (match_pos > 0) then
      result = value(:match_pos-1)
    end if
  end subroutine
  
  subroutine remove_prefix_pattern(value, pattern, result, largest)
    character(len=*), intent(in) :: value, pattern
    character(len=*), intent(out) :: result
    logical, intent(in) :: largest
    
    integer :: i, match_pos, match_end
    
    result = value
    match_pos = 0
    match_end = 0
    
    ! Simple pattern matching - exact match only for now
    ! TODO: Add full glob pattern support
    if (largest) then
      ! Find rightmost match from the left
      do i = 1, len_trim(value) - len_trim(pattern) + 1
        if (value(i:i+len_trim(pattern)-1) == pattern) then
          match_pos = i
          match_end = i + len_trim(pattern) - 1
        end if
      end do
    else
      ! Find leftmost match
      do i = 1, len_trim(value) - len_trim(pattern) + 1
        if (value(i:i+len_trim(pattern)-1) == pattern) then
          match_pos = i
          match_end = i + len_trim(pattern) - 1
          exit
        end if
      end do
    end if
    
    if (match_pos > 0) then
      result = value(match_end+1:)
    end if
  end subroutine
  
  ! Positional parameter support functions
  subroutine set_positional_params(shell, params, count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: params(:)
    integer, intent(in) :: count
    integer :: i, actual_count
    
    actual_count = min(count, size(shell%positional_params))
    shell%num_positional = actual_count
    
    do i = 1, actual_count
      shell%positional_params(i)%str = params(i)
    end do

    ! Clear any remaining parameters
    do i = actual_count + 1, size(shell%positional_params)
      shell%positional_params(i)%str = ''
    end do
  end subroutine
  
  subroutine get_all_positional_params(shell, result, as_single_word)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(out) :: result
    logical, intent(in) :: as_single_word
    integer :: i, pos
    character(len=1) :: separator

    result = ''
    if (shell%num_positional == 0) return

    if (as_single_word) then
      ! Use first character of IFS as separator for $*
      ! POSIX: If IFS is empty (set to ""), no separator is used
      if (len_trim(shell%ifs) > 0) then
        separator = shell%ifs(1:1)
      else
        separator = char(0)  ! Use NUL to indicate no separator
      end if
    else
      ! Use space for $@ (will be properly quoted during expansion)
      separator = ' '
    end if

    pos = 1
    do i = 1, shell%num_positional
      if (i > 1 .and. separator /= char(0)) then
        result(pos:pos) = separator
        pos = pos + 1
      end if
      result(pos:pos+len_trim(shell%positional_params(i)%str)-1) = trim(shell%positional_params(i)%str)
      pos = pos + len_trim(shell%positional_params(i)%str)
    end do
  end subroutine
  
  subroutine shift_positional_params(shell, count)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: count
    integer :: i, shift_count
    
    shift_count = min(count, shell%num_positional)
    
    ! Shift parameters left
    do i = 1, shell%num_positional - shift_count
      shell%positional_params(i)%str = shell%positional_params(i + shift_count)%str
    end do

    ! Clear the shifted parameters
    do i = shell%num_positional - shift_count + 1, shell%num_positional
      shell%positional_params(i)%str = ''
    end do
    
    shell%num_positional = shell%num_positional - shift_count
  end subroutine
  
  function is_numeric(str) result(is_num)
    character(len=*), intent(in) :: str
    logical :: is_num
    integer :: i
    
    is_num = .false.
    if (len_trim(str) == 0) return
    
    do i = 1, len_trim(str)
      if (str(i:i) < '0' .or. str(i:i) > '9') return
    end do
    
    is_num = .true.
  end function
  
  function string_to_int(str) result(int_val)
    character(len=*), intent(in) :: str
    integer :: int_val, iostat

    read(str, *, iostat=iostat) int_val
    if (iostat /= 0) int_val = 0  ! Error reading, return 0
  end function

  ! Helper functions for special variables
  function get_shell_option_flags(shell) result(flags)
    type(shell_state_t), intent(in) :: shell
    character(len=256) :: flags
    integer :: pos

    flags = ''
    pos = 1

    ! Build option flags string from shell options
    ! Order follows bash convention for common flags: h, i, m, B, H, s, then others
    ! h for hashall (enabled by default in most shells)
    flags(pos:pos) = 'h'
    pos = pos + 1
    if (shell%is_interactive) then
      flags(pos:pos) = 'i'
      pos = pos + 1
    end if
    if (shell%option_monitor) then
      flags(pos:pos) = 'm'
      pos = pos + 1
    end if
    ! B for braceexpand (bash extension, enabled by default)
    flags(pos:pos) = 'B'
    pos = pos + 1
    ! c flag when running in command mode (-c)
    if (shell%in_command_mode) then
      flags(pos:pos) = 'c'
      pos = pos + 1
    end if
    if (shell%option_allexport) then
      flags(pos:pos) = 'a'
      pos = pos + 1
    end if
    if (shell%option_errexit) then
      flags(pos:pos) = 'e'
      pos = pos + 1
    end if
    if (shell%option_noglob) then
      flags(pos:pos) = 'f'
      pos = pos + 1
    end if
    if (shell%option_nounset) then
      flags(pos:pos) = 'u'
      pos = pos + 1
    end if
    if (shell%option_verbose) then
      flags(pos:pos) = 'v'
      pos = pos + 1
    end if
    if (shell%option_xtrace) then
      flags(pos:pos) = 'x'
      pos = pos + 1
    end if
    if (shell%option_noclobber) then
      flags(pos:pos) = 'C'
      pos = pos + 1
    end if
  end function

  subroutine get_random_number(value)
    character(len=*), intent(out) :: value
    real :: rand_val
    integer :: rand_int

    call random_number(rand_val)
    rand_int = int(rand_val * 32768.0)
    write(value, '(i15)') rand_int
  end subroutine

  subroutine get_seconds_since_start(shell, value)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(out) :: value
    integer :: current_time, elapsed

    ! Get current time
    call system_clock(current_time)

    ! Calculate elapsed seconds
    if (shell%shell_start_time > 0) then
      elapsed = (current_time - shell%shell_start_time) / 1000  ! Assuming milliseconds
    else
      elapsed = 0
    end if

    write(value, '(i15)') elapsed
  end subroutine

  function get_random_int() result(rand_int)
    integer :: rand_int
    real :: rand_val
    call random_number(rand_val)
    rand_int = int(rand_val * 32768.0)
  end function

  function get_elapsed_seconds(shell) result(elapsed)
    type(shell_state_t), intent(in) :: shell
    integer :: elapsed, current_time
    call system_clock(current_time)
    if (shell%shell_start_time > 0) then
      elapsed = (current_time - shell%shell_start_time) / 1000
    else
      elapsed = 0
    end if
  end function

  ! Get the actual stored length of a variable (for ${#var} expansion)
  ! Returns -1 if variable not found or doesn't have stored length
  subroutine get_variable_length(shell, name, length)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: name
    integer, intent(out) :: length
    integer :: i, depth

    length = -1

    ! First check local variables (innermost scope first)
    if (shell%function_depth > 0) then
      do depth = shell%function_depth, 1, -1
        if (depth <= size(shell%local_var_counts)) then
          do i = 1, shell%local_var_counts(depth)
            if (trim(shell%local_vars(depth, i)%name) == trim(name)) then
              length = shell%local_vars(depth, i)%value_len
              return
            end if
          end do
        end if
      end do
    end if

    ! Check special prompt variables
    select case (trim(name))
      case ('PS1')
        length = shell%ps1_len
        return
      case ('PS2')
        length = shell%ps2_len
        return
      case ('PS3')
        length = shell%ps3_len
        return
      case ('PS4')
        length = shell%ps4_len
        return
    end select

    ! Check regular shell variables
    do i = 1, shell%num_variables
      if (trim(shell%variables(i)%name) == trim(name)) then
        length = shell%variables(i)%value_len
        return
      end if
    end do
  end subroutine

  ! Strip surrounding quotes (single or double) from a string
  ! Preserves trailing spaces within quotes
  subroutine strip_quotes(str)
    character(len=*), intent(inout) :: str
    integer :: i, search_end, closing_quote_pos, content_len
    character(len=len(str)) :: temp
    character(len=1) :: quote_char

    if (len_trim(str) < 2) return

    ! Check if string starts with a quote
    if (str(1:1) /= "'" .and. str(1:1) /= '"') return

    quote_char = str(1:1)

    ! Search backwards to find closing quote (use len_trim to avoid padding)
    closing_quote_pos = 0
    search_end = len_trim(str)
    do i = search_end, 2, -1
      if (str(i:i) == quote_char) then
        closing_quote_pos = i
        exit
      end if
    end do

    ! If we found a matching closing quote, extract the content (preserving all characters including trailing spaces)
    if (closing_quote_pos > 1) then
      content_len = closing_quote_pos - 2
      ! Save the original string first
      temp = str
      ! Clear the output string
      str = repeat(' ', len(str))
      ! Copy character by character from positions 2 to closing_quote_pos-1
      ! This preserves ALL characters including trailing spaces
      do i = 1, content_len
        str(i:i) = temp(i+1:i+1)
      end do
    end if
  end subroutine

  ! Check if nounset option is enabled and handle undefined variable
  ! Moved from shell_options to break circular dependency
  function check_nounset(shell, var_name) result(should_error)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: var_name
    logical :: should_error

    should_error = shell%option_nounset
    if (should_error) then
      write(error_unit, '(a)') 'fortsh: ' // trim(var_name) // ': unbound variable'
    end if
  end function

end module variables