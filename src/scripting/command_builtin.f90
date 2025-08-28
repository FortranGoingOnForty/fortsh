! ==============================================================================
! Module: command_builtin
! Purpose: Command identification built-ins (type, which, command)
! ==============================================================================
module command_builtin
  use shell_types
  use variables
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding, only: c_int, c_char, c_null_char
  implicit none

  interface
    function access_c(path, mode) bind(c, name='access') result(status)
      import :: c_int, c_char
      character(kind=c_char), intent(in) :: path(*)
      integer(c_int), value :: mode
      integer(c_int) :: status
    end function
  end interface

  integer, parameter :: F_OK = 0  ! File exists
  integer, parameter :: X_OK = 1  ! Execute permission

contains

  subroutine builtin_type(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    integer :: i, arg_index
    logical :: all_flag, path_flag, type_flag, function_flag
    character(len=256) :: command_name
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'type: usage: type [-afptP] name [name ...]'
      shell%last_exit_status = 2
      return
    end if
    
    all_flag = .false.
    path_flag = .false.
    type_flag = .false.
    function_flag = .false.
    arg_index = 2
    
    ! Parse options
    do while (arg_index <= cmd%num_tokens)
      if (cmd%tokens(arg_index)(1:1) == '-') then
        select case (trim(cmd%tokens(arg_index)))
        case ('-a')
          all_flag = .true.
        case ('-p')
          path_flag = .true.
        case ('-t')
          type_flag = .true.
        case ('-f')
          function_flag = .true.
        case ('-P')
          path_flag = .true.
        case ('--')
          arg_index = arg_index + 1
          exit
        case default
          write(error_unit, '(a,a)') 'type: unknown option: ', trim(cmd%tokens(arg_index))
          shell%last_exit_status = 1
          return
        end select
        arg_index = arg_index + 1
      else
        exit
      end if
    end do
    
    if (arg_index > cmd%num_tokens) then
      write(error_unit, '(a)') 'type: usage: type [-afptP] name [name ...]'
      shell%last_exit_status = 2
      return
    end if
    
    shell%last_exit_status = 0
    
    ! Process each command name
    do i = arg_index, cmd%num_tokens
      command_name = cmd%tokens(i)
      call identify_command_type(shell, command_name, all_flag, path_flag, type_flag, function_flag)
    end do
  end subroutine

  subroutine builtin_which(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    integer :: i, arg_index
    logical :: all_flag, silent_flag
    character(len=256) :: command_name
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'which: usage: which [-as] command [command ...]'
      shell%last_exit_status = 2
      return
    end if
    
    all_flag = .false.
    silent_flag = .false.
    arg_index = 2
    
    ! Parse options
    do while (arg_index <= cmd%num_tokens)
      if (cmd%tokens(arg_index)(1:1) == '-') then
        select case (trim(cmd%tokens(arg_index)))
        case ('-a')
          all_flag = .true.
        case ('-s')
          silent_flag = .true.
        case ('--')
          arg_index = arg_index + 1
          exit
        case default
          write(error_unit, '(a,a)') 'which: unknown option: ', trim(cmd%tokens(arg_index))
          shell%last_exit_status = 1
          return
        end select
        arg_index = arg_index + 1
      else
        exit
      end if
    end do
    
    if (arg_index > cmd%num_tokens) then
      write(error_unit, '(a)') 'which: usage: which [-as] command [command ...]'
      shell%last_exit_status = 2
      return
    end if
    
    shell%last_exit_status = 0
    
    ! Process each command name
    do i = arg_index, cmd%num_tokens
      command_name = cmd%tokens(i)
      call find_command_in_path(shell, command_name, all_flag, silent_flag)
    end do
  end subroutine

  subroutine builtin_command(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    integer :: arg_index
    logical :: path_flag, verbose_flag
    character(len=256) :: command_name
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'command: usage: command [-pVv] command [arg ...]'
      shell%last_exit_status = 2
      return
    end if
    
    path_flag = .false.
    verbose_flag = .false.
    arg_index = 2
    
    ! Parse options
    do while (arg_index <= cmd%num_tokens)
      if (cmd%tokens(arg_index)(1:1) == '-') then
        select case (trim(cmd%tokens(arg_index)))
        case ('-p')
          path_flag = .true.
        case ('-V')
          verbose_flag = .true.
        case ('-v')
          verbose_flag = .true.
        case ('--')
          arg_index = arg_index + 1
          exit
        case default
          write(error_unit, '(a,a)') 'command: unknown option: ', trim(cmd%tokens(arg_index))
          shell%last_exit_status = 1
          return
        end select
        arg_index = arg_index + 1
      else
        exit
      end if
    end do
    
    if (arg_index > cmd%num_tokens) then
      write(error_unit, '(a)') 'command: usage: command [-pVv] command [arg ...]'
      shell%last_exit_status = 2
      return
    end if
    
    command_name = cmd%tokens(arg_index)
    
    if (verbose_flag) then
      call identify_command_type(shell, command_name, .false., path_flag, .false., .false.)
    else
      ! Execute the command (simplified - would need full execution logic)
      write(output_unit, '(a,a)') 'command: would execute ', trim(command_name)
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine identify_command_type(shell, command_name, all_flag, path_flag, type_flag, function_flag)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command_name
    logical, intent(in) :: all_flag, path_flag, type_flag, function_flag
    
    logical :: found_any
    character(len=1024) :: full_path
    
    found_any = .false.
    
    ! Check if it's a shell keyword
    if (.not. path_flag .and. is_shell_keyword(command_name)) then
      if (type_flag) then
        write(output_unit, '(a)') 'keyword'
      else
        write(output_unit, '(a,a,a)') trim(command_name), ' is a shell keyword'
      end if
      found_any = .true.
      if (.not. all_flag) return
    end if
    
    ! Check if it's a function
    if (.not. path_flag .and. is_shell_function(shell, command_name)) then
      if (type_flag) then
        write(output_unit, '(a)') 'function'
      else
        write(output_unit, '(a,a,a)') trim(command_name), ' is a function'
      end if
      found_any = .true.
      if (.not. all_flag) return
    end if
    
    ! Check if it's a built-in
    if (.not. path_flag .and. is_builtin_command(command_name)) then
      if (type_flag) then
        write(output_unit, '(a)') 'builtin'
      else
        write(output_unit, '(a,a,a)') trim(command_name), ' is a shell builtin'
      end if
      found_any = .true.
      if (.not. all_flag) return
    end if
    
    ! Check if it's an alias
    if (.not. path_flag .and. is_shell_alias(shell, command_name)) then
      if (type_flag) then
        write(output_unit, '(a)') 'alias'
      else
        write(output_unit, '(a,a,a)') trim(command_name), ' is aliased'
      end if
      found_any = .true.
      if (.not. all_flag) return
    end if
    
    ! Search in PATH
    if (find_executable_in_path(shell, command_name, full_path)) then
      if (type_flag) then
        write(output_unit, '(a)') 'file'
      else
        write(output_unit, '(a,a,a,a)') trim(command_name), ' is ', trim(full_path), ''
      end if
      found_any = .true.
    end if
    
    if (.not. found_any) then
      write(error_unit, '(a,a,a)') trim(command_name), ': not found'
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine find_command_in_path(shell, command_name, all_flag, silent_flag)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command_name
    logical, intent(in) :: all_flag, silent_flag
    
    character(len=1024) :: full_path
    
    if (find_executable_in_path(shell, command_name, full_path)) then
      if (.not. silent_flag) then
        write(output_unit, '(a)') trim(full_path)
      end if
    else
      if (.not. silent_flag) then
        write(error_unit, '(a,a,a)') trim(command_name), ': not found'
      end if
      shell%last_exit_status = 1
    end if
  end subroutine

  function find_executable_in_path(shell, command_name, full_path) result(found)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: command_name
    character(len=*), intent(out) :: full_path
    logical :: found
    
    character(len=4096) :: path_var
    character(len=1024) :: path_component
    character(len=1024) :: candidate_path
    integer :: start_pos, end_pos, colon_pos
    
    found = .false.
    full_path = ''
    
    ! If command contains '/', it's an absolute or relative path
    if (index(command_name, '/') > 0) then
      if (is_executable_file(command_name)) then
        full_path = command_name
        found = .true.
      end if
      return
    end if
    
    ! Get PATH variable
    path_var = get_shell_variable(shell, 'PATH')
    if (len_trim(path_var) == 0) then
      path_var = '/usr/bin:/bin'
    end if
    
    ! Search each directory in PATH
    start_pos = 1
    do while (start_pos <= len_trim(path_var))
      colon_pos = index(path_var(start_pos:), ':')
      if (colon_pos == 0) then
        end_pos = len_trim(path_var)
      else
        end_pos = start_pos + colon_pos - 2
      end if
      
      path_component = path_var(start_pos:end_pos)
      if (len_trim(path_component) == 0) then
        path_component = '.'
      end if
      
      ! Construct full path
      if (path_component(len_trim(path_component):len_trim(path_component)) == '/') then
        write(candidate_path, '(a,a)') trim(path_component), trim(command_name)
      else
        write(candidate_path, '(a,a,a)') trim(path_component), '/', trim(command_name)
      end if
      
      if (is_executable_file(candidate_path)) then
        full_path = candidate_path
        found = .true.
        return
      end if
      
      if (colon_pos == 0) exit
      start_pos = start_pos + colon_pos
    end do
  end function

  function is_executable_file(path) result(executable)
    character(len=*), intent(in) :: path
    logical :: executable
    
    character(kind=c_char) :: c_path(len_trim(path) + 1)
    integer :: i, status
    
    ! Convert to C string
    do i = 1, len_trim(path)
      c_path(i) = path(i:i)
    end do
    c_path(len_trim(path) + 1) = c_null_char
    
    ! Check if file exists and is executable
    status = access_c(c_path, F_OK + X_OK)
    executable = (status == 0)
  end function

  function is_shell_keyword(command_name) result(is_keyword)
    character(len=*), intent(in) :: command_name
    logical :: is_keyword
    
    character(len=16), parameter :: keywords(20) = [ &
      'if       ', 'then     ', 'else     ', 'elif     ', 'fi       ', &
      'for      ', 'while    ', 'until    ', 'do       ', 'done     ', &
      'case     ', 'esac     ', 'function ', 'select   ', 'time     ', &
      'coproc   ', '{        ', '}        ', '!        ', '[[       ' ]
    
    integer :: i
    
    is_keyword = .false.
    do i = 1, size(keywords)
      if (trim(command_name) == trim(keywords(i))) then
        is_keyword = .true.
        return
      end if
    end do
  end function

  function is_builtin_command(command_name) result(is_builtin)
    character(len=*), intent(in) :: command_name
    logical :: is_builtin
    
    character(len=16), parameter :: builtins(25) = [ &
      'cd       ', 'pwd      ', 'echo     ', 'printf   ', 'read     ', &
      'export   ', 'unset    ', 'set      ', 'shift    ', 'test     ', &
      'true     ', 'false    ', 'exit     ', 'return   ', 'break    ', &
      'continue ', 'source   ', '.        ', 'eval     ', 'exec     ', &
      'jobs     ', 'fg       ', 'bg       ', 'kill     ', 'wait     ' ]
    
    integer :: i
    
    is_builtin = .false.
    do i = 1, size(builtins)
      if (trim(command_name) == trim(builtins(i))) then
        is_builtin = .true.
        return
      end if
    end do
  end function

  function is_shell_function(shell, command_name) result(is_function)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: command_name
    logical :: is_function
    
    ! Simplified - in real implementation would check function table
    is_function = .false.
  end function

  function is_shell_alias(shell, command_name) result(is_alias)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: command_name
    logical :: is_alias
    
    ! Simplified - in real implementation would check alias table
    is_alias = .false.
  end function

end module command_builtin