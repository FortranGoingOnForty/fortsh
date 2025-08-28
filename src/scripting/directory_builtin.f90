! ==============================================================================
! Module: directory_builtin  
! Purpose: Directory stack operations (pushd/popd/dirs)
! ==============================================================================
module directory_builtin
  use shell_types
  use variables
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding, only: c_int, c_char, c_null_char, c_ptr, c_associated
  implicit none

  integer, parameter :: MAX_DIR_STACK = 32
  
  type :: dir_stack_t
    character(len=1024) :: directories(MAX_DIR_STACK)
    integer :: top
  end type

  type(dir_stack_t), save :: dir_stack = dir_stack_t(directories=repeat(' ', 1024), top=0)

  interface
    function chdir_c(path) bind(c, name='chdir') result(status)
      import :: c_int, c_char
      character(kind=c_char), intent(in) :: path(*)
      integer(c_int) :: status
    end function
    
    function getcwd_c(buf, size) bind(c, name='getcwd') result(ptr)
      import :: c_int, c_char, c_ptr
      character(kind=c_char), intent(out) :: buf(*)
      integer(c_int), value :: size
      type(c_ptr) :: ptr
    end function
  end interface

contains

  subroutine builtin_pushd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=1024) :: new_dir, current_dir
    integer :: arg_index, status
    logical :: no_change, swap_top
    
    no_change = .false.
    swap_top = .false.
    arg_index = 2
    
    ! Parse options
    do while (arg_index <= cmd%num_tokens)
      if (cmd%tokens(arg_index)(1:1) == '-') then
        select case (trim(cmd%tokens(arg_index)))
        case ('-n')
          no_change = .true.
          arg_index = arg_index + 1
        case default
          write(error_unit, '(a,a)') 'pushd: unknown option: ', trim(cmd%tokens(arg_index))
          shell%last_exit_status = 1
          return
        end select
      else
        exit
      end if
    end do
    
    ! Get current directory
    call get_current_dir(current_dir, status)
    if (status /= 0) then
      write(error_unit, '(a)') 'pushd: cannot get current directory'
      shell%last_exit_status = 1
      return
    end if
    
    if (arg_index > cmd%num_tokens) then
      ! No directory specified - swap top two directories
      if (dir_stack%top < 1) then
        write(error_unit, '(a)') 'pushd: no other directory'
        shell%last_exit_status = 1
        return
      end if
      
      new_dir = dir_stack%directories(dir_stack%top)
      dir_stack%directories(dir_stack%top) = current_dir
      
      if (.not. no_change) then
        call change_dir(new_dir, status)
        if (status /= 0) then
          ! Restore original state
          dir_stack%directories(dir_stack%top) = new_dir
          shell%last_exit_status = 1
          return
        end if
      end if
      
      call print_directory_stack()
    else
      ! Directory specified
      new_dir = cmd%tokens(arg_index)
      
      ! Handle special cases
      if (new_dir == '~') then
        new_dir = get_shell_variable(shell, 'HOME')
        if (len_trim(new_dir) == 0) new_dir = '/'
      end if
      
      ! Push current directory onto stack
      if (dir_stack%top >= MAX_DIR_STACK) then
        write(error_unit, '(a)') 'pushd: directory stack full'
        shell%last_exit_status = 1
        return
      end if
      
      dir_stack%top = dir_stack%top + 1
      dir_stack%directories(dir_stack%top) = current_dir
      
      if (.not. no_change) then
        call change_dir(new_dir, status)
        if (status /= 0) then
          ! Remove from stack on failure
          dir_stack%top = dir_stack%top - 1
          shell%last_exit_status = 1
          return
        end if
        
        ! Update PWD variable
        call get_current_dir(current_dir, status)
        if (status == 0) then
          call set_shell_variable(shell, 'PWD', trim(current_dir))
        end if
      end if
      
      call print_directory_stack()
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_popd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=1024) :: new_dir, current_dir
    integer :: arg_index, status, n
    logical :: no_change
    character(len=16) :: n_str
    
    no_change = .false.
    n = 0
    arg_index = 2
    
    ! Parse options
    do while (arg_index <= cmd%num_tokens)
      if (cmd%tokens(arg_index)(1:1) == '-') then
        select case (trim(cmd%tokens(arg_index)))
        case ('-n')
          no_change = .true.
          arg_index = arg_index + 1
        case default
          write(error_unit, '(a,a)') 'popd: unknown option: ', trim(cmd%tokens(arg_index))
          shell%last_exit_status = 1
          return
        end select
      else
        ! Numeric argument
        if (cmd%tokens(arg_index)(1:1) == '+' .or. cmd%tokens(arg_index)(1:1) == '-' .or. &
            (cmd%tokens(arg_index)(1:1) >= '0' .and. cmd%tokens(arg_index)(1:1) <= '9')) then
          n_str = cmd%tokens(arg_index)
          read(n_str, *, iostat=status) n
          if (status /= 0) then
            write(error_unit, '(a,a)') 'popd: invalid number: ', trim(cmd%tokens(arg_index))
            shell%last_exit_status = 1
            return
          end if
        end if
        arg_index = arg_index + 1
      end if
    end do
    
    if (dir_stack%top < 1) then
      write(error_unit, '(a)') 'popd: directory stack empty'
      shell%last_exit_status = 1
      return
    end if
    
    if (n == 0) then
      ! Pop top directory
      new_dir = dir_stack%directories(dir_stack%top)
      dir_stack%top = dir_stack%top - 1
      
      if (.not. no_change) then
        call change_dir(new_dir, status)
        if (status /= 0) then
          ! Restore stack on failure
          dir_stack%top = dir_stack%top + 1
          shell%last_exit_status = 1
          return
        end if
        
        ! Update PWD variable
        call get_current_dir(current_dir, status)
        if (status == 0) then
          call set_shell_variable(shell, 'PWD', trim(current_dir))
        end if
      end if
    else
      ! Remove specific entry from stack
      if (n > 0) then
        n = dir_stack%top - n + 1
      else
        n = -n + 1
      end if
      
      if (n < 1 .or. n > dir_stack%top) then
        write(error_unit, '(a)') 'popd: directory stack index out of range'
        shell%last_exit_status = 1
        return
      end if
      
      ! Shift directories down
      do status = n, dir_stack%top - 1
        dir_stack%directories(status) = dir_stack%directories(status + 1)
      end do
      dir_stack%top = dir_stack%top - 1
    end if
    
    call print_directory_stack()
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_dirs(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    integer :: arg_index
    logical :: clear_stack, long_format, one_per_line
    
    clear_stack = .false.
    long_format = .false.
    one_per_line = .false.
    arg_index = 2
    
    ! Parse options
    do while (arg_index <= cmd%num_tokens)
      select case (trim(cmd%tokens(arg_index)))
      case ('-c')
        clear_stack = .true.
      case ('-l')
        long_format = .true.
      case ('-p')
        one_per_line = .true.
      case ('-v')
        ! Verbose (numbered) output
        call print_directory_stack_verbose()
        shell%last_exit_status = 0
        return
      case default
        write(error_unit, '(a,a)') 'dirs: unknown option: ', trim(cmd%tokens(arg_index))
        shell%last_exit_status = 1
        return
      end select
      arg_index = arg_index + 1
    end do
    
    if (clear_stack) then
      dir_stack%top = 0
    else if (one_per_line) then
      call print_directory_stack_lines()
    else
      call print_directory_stack()
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine print_directory_stack()
    character(len=1024) :: current_dir
    integer :: i, status
    
    call get_current_dir(current_dir, status)
    if (status == 0) then
      write(output_unit, '(a)', advance='no') trim(current_dir)
    else
      write(output_unit, '(a)', advance='no') '~'
    end if
    
    do i = dir_stack%top, 1, -1
      write(output_unit, '(a,a)', advance='no') ' ', trim(dir_stack%directories(i))
    end do
    write(output_unit, '(a)') ''
  end subroutine

  subroutine print_directory_stack_lines()
    character(len=1024) :: current_dir
    integer :: i, status
    
    call get_current_dir(current_dir, status)
    if (status == 0) then
      write(output_unit, '(a)') trim(current_dir)
    else
      write(output_unit, '(a)') '~'
    end if
    
    do i = dir_stack%top, 1, -1
      write(output_unit, '(a)') trim(dir_stack%directories(i))
    end do
  end subroutine

  subroutine print_directory_stack_verbose()
    character(len=1024) :: current_dir
    integer :: i, status
    
    call get_current_dir(current_dir, status)
    if (status == 0) then
      write(output_unit, '(a,a)') ' 0  ', trim(current_dir)
    else
      write(output_unit, '(a,a)') ' 0  ', '~'
    end if
    
    do i = dir_stack%top, 1, -1
      write(output_unit, '(I2,a,a)') dir_stack%top - i + 1, '  ', trim(dir_stack%directories(i))
    end do
  end subroutine

  subroutine get_current_dir(dir, status)
    character(len=*), intent(out) :: dir
    integer, intent(out) :: status
    
    character(kind=c_char) :: c_dir(1024)
    type(c_ptr) :: result
    integer :: i
    
    result = getcwd_c(c_dir, 1024)
    if (c_associated(result)) then
      status = 0
      dir = ''
      do i = 1, 1023
        if (c_dir(i) == c_null_char) exit
        dir(i:i) = c_dir(i)
      end do
    else
      status = 1
      dir = ''
    end if
  end subroutine

  subroutine change_dir(path, status)
    character(len=*), intent(in) :: path
    integer, intent(out) :: status
    
    character(kind=c_char) :: c_path(len_trim(path) + 1)
    integer :: i
    
    ! Convert to C string
    do i = 1, len_trim(path)
      c_path(i) = path(i:i)
    end do
    c_path(len_trim(path) + 1) = c_null_char
    
    status = chdir_c(c_path)
  end subroutine

end module directory_builtin