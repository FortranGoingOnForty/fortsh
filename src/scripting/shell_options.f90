! ==============================================================================
! Module: shell_options
! Purpose: Shell options management (set, shopt, POSIX compliance)
! ==============================================================================
module shell_options
  use shell_types
  use variables, only: set_shell_variable
  use system_interface, only: get_pid, get_ppid
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  ! Initialize shell special variables and options
  subroutine initialize_shell_options(shell)
    type(shell_state_t), intent(inout) :: shell
    
    ! Set special process variables
    shell%shell_pid = get_pid()
    shell%parent_pid = get_ppid()
    shell%shell_name = 'fortsh'
    
    ! Set default POSIX options (conservative defaults)
    shell%option_errexit = .false.
    shell%option_nounset = .false.
    shell%option_pipefail = .false.
    shell%option_verbose = .false.
    shell%option_xtrace = .false.
    shell%option_noclobber = .false.
    shell%option_monitor = .true.     ! Enable job control by default
    shell%option_allexport = .false.
    
    ! Set default bash-style options
    shell%shopt_nullglob = .false.
    shell%shopt_failglob = .false.
    shell%shopt_globstar = .false.
    shell%shopt_nocaseglob = .false.
    shell%shopt_extglob = .false.
    shell%shopt_dotglob = .false.
  end subroutine

  ! Handle 'set' builtin command for POSIX options
  subroutine builtin_set(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=256) :: option_str, option_name, param_idx_str
    integer :: i, arg_len, param_idx
    logical :: enable_option, setting_positional

    if (cmd%num_tokens == 1) then
      ! Show all variables (simplified)
      call show_shell_variables(shell)
      return
    end if

    setting_positional = .false.
    i = 2
    do while (i <= cmd%num_tokens)
      option_str = trim(cmd%tokens(i))
      arg_len = len_trim(option_str)

      ! Check for '--' which signals end of options and start of positional parameters
      if (option_str == '--') then
        setting_positional = .true.
        i = i + 1
        ! Clear existing positional parameters
        shell%num_positional = 0
        ! Set remaining arguments as positional parameters
        param_idx = 1
        do while (i <= cmd%num_tokens .and. param_idx <= 50)
          shell%positional_params(param_idx) = trim(cmd%tokens(i))
          write(param_idx_str, '(I0)') param_idx
          call set_shell_variable(shell, trim(param_idx_str), trim(cmd%tokens(i)))
          param_idx = param_idx + 1
          i = i + 1
        end do
        shell%num_positional = param_idx - 1
        write(param_idx_str, '(I0)') shell%num_positional
        call set_shell_variable(shell, '#', trim(param_idx_str))
        exit
      end if

      ! If argument doesn't start with - or +, treat rest as positional parameters
      if (arg_len >= 1 .and. option_str(1:1) /= '-' .and. option_str(1:1) /= '+') then
        setting_positional = .true.
        shell%num_positional = 0
        param_idx = 1
        do while (i <= cmd%num_tokens .and. param_idx <= 50)
          shell%positional_params(param_idx) = trim(cmd%tokens(i))
          write(param_idx_str, '(I0)') param_idx
          call set_shell_variable(shell, trim(param_idx_str), trim(cmd%tokens(i)))
          param_idx = param_idx + 1
          i = i + 1
        end do
        shell%num_positional = param_idx - 1
        write(param_idx_str, '(I0)') shell%num_positional
        call set_shell_variable(shell, '#', trim(param_idx_str))
        exit
      end if

      if (arg_len < 2) then
        i = i + 1
        cycle
      end if

      ! Check if enabling (+) or disabling (-) option
      if (option_str(1:1) == '-') then
        enable_option = .true.
        option_name = option_str(2:arg_len)
      else if (option_str(1:1) == '+') then
        enable_option = .false.
        option_name = option_str(2:arg_len)
      else
        write(error_unit, '(a)') 'set: invalid option format: ' // trim(option_str)
        shell%last_exit_status = 1
        i = i + 1
        cycle
      end if
      
      ! Handle single-letter options
      if (len_trim(option_name) == 1) then
        select case (option_name(1:1))
          case ('e')
            shell%option_errexit = enable_option
            if (enable_option .and. shell%option_verbose) then
              write(output_unit, '(a)') 'set: errexit enabled'
            end if
          case ('u')
            shell%option_nounset = enable_option
            if (enable_option .and. shell%option_verbose) then
              write(output_unit, '(a)') 'set: nounset enabled'
            end if
          case ('v')
            shell%option_verbose = enable_option
          case ('x')
            shell%option_xtrace = enable_option
          case ('C')
            shell%option_noclobber = enable_option
          case ('m')
            shell%option_monitor = enable_option
          case ('a')
            shell%option_allexport = enable_option
          case ('o')
            ! Handle -o followed by option name (should be separate argument)
            if (i < cmd%num_tokens) then
              i = i + 1
              option_name = trim(cmd%tokens(i))
              select case (trim(option_name))
                case ('pipefail')
                  shell%option_pipefail = enable_option
                  if (enable_option .and. shell%option_verbose) then
                    write(output_unit, '(a)') 'set: pipefail enabled'
                  end if
                case ('errexit')
                  shell%option_errexit = enable_option
                case ('nounset')
                  shell%option_nounset = enable_option
                case ('verbose')
                  shell%option_verbose = enable_option
                case ('xtrace')
                  shell%option_xtrace = enable_option
                case ('noclobber')
                  shell%option_noclobber = enable_option
                case ('monitor')
                  shell%option_monitor = enable_option
                case ('allexport')
                  shell%option_allexport = enable_option
                case default
                  write(error_unit, '(a)') 'set: unknown option: ' // trim(option_name)
                  shell%last_exit_status = 1
              end select
            else
              write(error_unit, '(a)') 'set: option -o requires an argument'
              shell%last_exit_status = 1
            end if
          case default
            write(error_unit, '(a)') 'set: unknown option: -' // option_name(1:1)
            shell%last_exit_status = 1
        end select
      else
        write(error_unit, '(a)') 'set: unknown option: ' // trim(option_str)
        shell%last_exit_status = 1
      end if
      
      ! Always increment 
      i = i + 1
    end do
    
    shell%last_exit_status = 0
  end subroutine

  ! Handle 'shopt' builtin command for bash-style options
  subroutine builtin_shopt(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: option_name, flag
    integer :: i
    logical :: show_all = .false., enable_option = .true.
    
    if (cmd%num_tokens == 1) then
      show_all = .true.
    end if
    
    i = 2
    do while (i <= cmd%num_tokens)
      flag = trim(cmd%tokens(i))
      
      if (flag == '-s') then
        enable_option = .true.
      else if (flag == '-u') then
        enable_option = .false.
      else if (flag == '-p') then
        show_all = .true.
      else
        option_name = trim(flag)
        call set_shopt_option(shell, option_name, enable_option)
      end if
      
      i = i + 1
    end do
    
    if (show_all) then
      call show_shopt_options(shell)
    end if
    
    shell%last_exit_status = 0
  end subroutine

  ! Set a shopt option
  subroutine set_shopt_option(shell, option_name, enable)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: option_name
    logical, intent(in) :: enable
    
    select case (trim(option_name))
      case ('nullglob')
        shell%shopt_nullglob = enable
      case ('failglob')
        shell%shopt_failglob = enable
      case ('globstar')
        shell%shopt_globstar = enable
      case ('nocaseglob')
        shell%shopt_nocaseglob = enable
      case ('extglob')
        shell%shopt_extglob = enable
      case ('dotglob')
        shell%shopt_dotglob = enable
      case default
        write(error_unit, '(a)') 'shopt: unknown option: ' // trim(option_name)
        shell%last_exit_status = 1
    end select
  end subroutine

  ! Show all shopt options
  subroutine show_shopt_options(shell)
    type(shell_state_t), intent(in) :: shell
    
    write(output_unit, '(a,a)') 'shopt ', merge('-s nullglob   ', '-u nullglob   ', shell%shopt_nullglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s failglob   ', '-u failglob   ', shell%shopt_failglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s globstar   ', '-u globstar   ', shell%shopt_globstar)
    write(output_unit, '(a,a)') 'shopt ', merge('-s nocaseglob ', '-u nocaseglob ', shell%shopt_nocaseglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s extglob    ', '-u extglob    ', shell%shopt_extglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s dotglob    ', '-u dotglob    ', shell%shopt_dotglob)
  end subroutine

  ! Show shell variables (simplified version for 'set' without args)
  subroutine show_shell_variables(shell)
    type(shell_state_t), intent(in) :: shell
    integer :: i
    
    write(output_unit, '(a)') '# Shell variables:'
    do i = 1, shell%num_variables
      if (shell%variables(i)%name(1:1) /= char(0) .and. trim(shell%variables(i)%name) /= '') then
        if (shell%variables(i)%is_array) then
          write(output_unit, '(a)') trim(shell%variables(i)%name) // '=(array)'
        else if (shell%variables(i)%is_assoc_array) then
          write(output_unit, '(a)') trim(shell%variables(i)%name) // '=(associative array)'
        else
          write(output_unit, '(a)') trim(shell%variables(i)%name) // '=' // &
                                   '"' // trim(shell%variables(i)%value) // '"'
        end if
      end if
    end do
    
    write(output_unit, '(a)') '# Special variables:'
    write(output_unit, '(a,i0)') '$$=', shell%shell_pid
    write(output_unit, '(a,i0)') '$!=', shell%last_bg_pid
    write(output_unit, '(a)') '$0=' // trim(shell%shell_name)
    write(output_unit, '(a,i0)') '$PPID=', shell%parent_pid
    write(output_unit, '(a,i0)') '$?=', shell%last_exit_status
  end subroutine

  ! Check if errexit option is enabled and handle command failure
  subroutine check_errexit(shell, exit_status)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: exit_status
    
    if (shell%option_errexit .and. exit_status /= 0) then
      if (shell%option_verbose) then
        write(error_unit, '(a,i0)') 'fortsh: errexit: exiting due to command failure (status: ', exit_status
        write(error_unit, '(a)') ')'
      end if
      shell%running = .false.
      shell%last_exit_status = exit_status
    end if
  end subroutine

  ! Check if nounset option is enabled and handle undefined variable
  function check_nounset(shell, var_name) result(should_error)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: var_name
    logical :: should_error
    
    should_error = shell%option_nounset
    if (should_error) then
      write(error_unit, '(a)') 'fortsh: ' // trim(var_name) // ': unbound variable'
    end if
  end function

  ! Trace command execution if xtrace is enabled
  subroutine trace_command(shell, command_line)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: command_line
    
    if (shell%option_xtrace) then
      write(error_unit, '(a)') '+ ' // trim(command_line)
    end if
  end subroutine

end module shell_options