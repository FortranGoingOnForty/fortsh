! ==============================================================================
! Module: getopts_builtin
! Purpose: Getopts built-in for option parsing in shell scripts
! ==============================================================================
module getopts_builtin
  use shell_types
  use variables
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  subroutine builtin_getopts(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: optstring, optname
    character(len=1024) :: argv_str, current_arg
    character(len=64) :: optind_str, optarg_str
    integer :: optind, argc, current_pos, i
    character :: opt_char
    logical :: found_option, requires_arg, silent_mode
    
    if (cmd%num_tokens < 3) then
      write(error_unit, '(a)') 'getopts: usage: getopts OPTSTRING NAME [ARG...]'
      shell%last_exit_status = 2
      return
    end if
    
    optstring = cmd%tokens(2)
    optname = cmd%tokens(3)
    silent_mode = (optstring(1:1) == ':')
    
    ! Get current OPTIND value
    optind_str = get_shell_variable(shell, 'OPTIND')
    if (len_trim(optind_str) == 0) then
      optind = 1
    else
      read(optind_str, *, iostat=i) optind
      if (i /= 0) optind = 1
    end if
    
    ! Build argument list from remaining tokens or positional parameters
    argc = 0
    if (cmd%num_tokens > 3) then
      ! Use provided arguments
      argc = cmd%num_tokens - 3
      do i = 4, cmd%num_tokens
        if (i == optind + 3) then
          current_arg = cmd%tokens(i)
          exit
        end if
      end do
    else
      ! Use positional parameters
      optind_str = get_shell_variable(shell, '#')
      if (len_trim(optind_str) > 0) then
        read(optind_str, *, iostat=i) argc
        if (i /= 0) argc = 0
      end if
      
      if (optind <= argc) then
        write(optind_str, '(I0)') optind
        current_arg = get_shell_variable(shell, trim(optind_str))
      end if
    end if
    
    ! Check if we're done processing options
    if (optind > argc .or. len_trim(current_arg) == 0 .or. current_arg(1:1) /= '-') then
      call set_shell_variable(shell, trim(optname), '?')
      shell%last_exit_status = 1
      return
    end if
    
    ! Handle special cases
    if (current_arg == '--') then
      ! End of options
      optind = optind + 1
      write(optind_str, '(I0)') optind
      call set_shell_variable(shell, 'OPTIND', trim(optind_str))
      call set_shell_variable(shell, trim(optname), '?')
      shell%last_exit_status = 1
      return
    end if
    
    if (current_arg == '-') then
      ! Single dash is not an option
      call set_shell_variable(shell, trim(optname), '?')
      shell%last_exit_status = 1
      return
    end if
    
    ! Get current position in the argument string
    optind_str = get_shell_variable(shell, 'OPTPOS')
    if (len_trim(optind_str) == 0) then
      current_pos = 2  ! Skip the '-'
    else
      read(optind_str, *, iostat=i) current_pos
      if (i /= 0) current_pos = 2
    end if
    
    ! Check if we've reached the end of this argument
    if (current_pos > len_trim(current_arg)) then
      optind = optind + 1
      current_pos = 2
      write(optind_str, '(I0)') optind
      call set_shell_variable(shell, 'OPTIND', trim(optind_str))
      call set_shell_variable(shell, 'OPTPOS', '')
      
      ! Get next argument
      if (cmd%num_tokens > 3) then
        if (optind + 3 <= cmd%num_tokens) then
          current_arg = cmd%tokens(optind + 3)
        else
          current_arg = ''
        end if
      else
        write(optind_str, '(I0)') optind
        current_arg = get_shell_variable(shell, trim(optind_str))
      end if
      
      if (len_trim(current_arg) == 0 .or. current_arg(1:1) /= '-') then
        call set_shell_variable(shell, trim(optname), '?')
        shell%last_exit_status = 1
        return
      end if
    end if
    
    ! Extract the current option character
    opt_char = current_arg(current_pos:current_pos)
    current_pos = current_pos + 1
    
    ! Check if this option is in the optstring
    found_option = .false.
    requires_arg = .false.
    
    do i = 1, len_trim(optstring)
      if (optstring(i:i) == opt_char) then
        found_option = .true.
        if (i < len_trim(optstring) .and. optstring(i+1:i+1) == ':') then
          requires_arg = .true.
        end if
        exit
      end if
    end do
    
    if (.not. found_option) then
      ! Invalid option
      if (silent_mode) then
        call set_shell_variable(shell, trim(optname), '?')
        call set_shell_variable(shell, 'OPTARG', opt_char)
      else
        write(error_unit, '(a,a,a)') 'getopts: illegal option -- ', opt_char, ''
        call set_shell_variable(shell, trim(optname), '?')
      end if
      
      if (current_pos > len_trim(current_arg)) then
        optind = optind + 1
        current_pos = 2
      end if
      
      write(optind_str, '(I0)') optind
      call set_shell_variable(shell, 'OPTIND', trim(optind_str))
      if (current_pos == 2) then
        call set_shell_variable(shell, 'OPTPOS', '')
      else
        write(optarg_str, '(I0)') current_pos
        call set_shell_variable(shell, 'OPTPOS', trim(optarg_str))
      end if
      
      shell%last_exit_status = 0
      return
    end if
    
    ! Valid option found
    call set_shell_variable(shell, trim(optname), opt_char)
    
    if (requires_arg) then
      ! Option requires an argument
      if (current_pos <= len_trim(current_arg)) then
        ! Argument is in the same token
        optarg_str = current_arg(current_pos:)
        optind = optind + 1
        current_pos = 2
      else
        ! Argument should be in the next token
        optind = optind + 1
        
        if (cmd%num_tokens > 3) then
          if (optind + 3 <= cmd%num_tokens) then
            optarg_str = cmd%tokens(optind + 3)
            optind = optind + 1
          else
            optarg_str = ''
          end if
        else
          write(optind_str, '(I0)') optind
          optarg_str = get_shell_variable(shell, trim(optind_str))
          if (len_trim(optarg_str) > 0) then
            optind = optind + 1
          end if
        end if
        
        current_pos = 2
      end if
      
      if (len_trim(optarg_str) == 0) then
        ! Missing argument
        if (silent_mode) then
          call set_shell_variable(shell, trim(optname), ':')
          call set_shell_variable(shell, 'OPTARG', opt_char)
        else
          write(error_unit, '(a,a,a)') 'getopts: option requires an argument -- ', opt_char, ''
          call set_shell_variable(shell, trim(optname), '?')
        end if
      else
        call set_shell_variable(shell, 'OPTARG', trim(optarg_str))
      end if
    else
      call set_shell_variable(shell, 'OPTARG', '')
    end if
    
    ! Update OPTIND and OPTPOS
    write(optind_str, '(I0)') optind
    call set_shell_variable(shell, 'OPTIND', trim(optind_str))
    
    if (current_pos == 2) then
      call set_shell_variable(shell, 'OPTPOS', '')
    else
      write(optarg_str, '(I0)') current_pos
      call set_shell_variable(shell, 'OPTPOS', trim(optarg_str))
    end if
    
    shell%last_exit_status = 0
  end subroutine

end module getopts_builtin