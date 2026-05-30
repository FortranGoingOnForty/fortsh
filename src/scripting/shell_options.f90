! ==============================================================================
! Module: shell_options
! Purpose: Shell options management (set, shopt, POSIX compliance)
! ==============================================================================
module shell_options
  use shell_types
  use variables, only: set_shell_variable
  use system_interface, only: get_pid, get_ppid
  use readline, only: set_global_editing_mode, set_global_fuzzy_complete
  use iso_fortran_env, only: output_unit, error_unit
  use io_helpers, only: write_stdout
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
    shell%option_monitor = .false.    ! Job control only for interactive mode (set later)
    shell%option_allexport = .false.
    shell%option_noglob = .false.
    shell%option_vi = .false.         ! Emacs mode by default

    ! Set default bash-style options
    shell%shopt_nullglob = .false.
    shell%shopt_failglob = .false.
    shell%shopt_globstar = .false.
    shell%shopt_nocaseglob = .false.
    shell%shopt_nocasematch = .false.
    shell%shopt_extglob = .false.
    shell%shopt_dotglob = .false.
    shell%shopt_expand_aliases = .false.
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
        ! Clear and resize positional parameters to hold all args (no 50 cap)
        shell%num_positional = 0
        if (allocated(shell%positional_params)) deallocate(shell%positional_params)
        allocate(shell%positional_params(max(1, cmd%num_tokens - i + 1)))
        param_idx = 1
        do while (i <= cmd%num_tokens)
          shell%positional_params(param_idx)%str = trim(cmd%tokens(i))
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
        if (allocated(shell%positional_params)) deallocate(shell%positional_params)
        allocate(shell%positional_params(max(1, cmd%num_tokens - i + 1)))
        param_idx = 1
        do while (i <= cmd%num_tokens)
          shell%positional_params(param_idx)%str = trim(cmd%tokens(i))
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
      
      ! Handle options — iterate over each character to support combined flags like -eo
      block
        integer :: fi
        logical :: had_error
        character(len=256) :: long_opt_name
        had_error = .false.
        fi = 1
        do while (fi <= len_trim(option_name))
          select case (option_name(fi:fi))
          case ('e')
            shell%option_errexit = enable_option
          case ('u')
            shell%option_nounset = enable_option
          case ('n')
            shell%option_noexec = enable_option
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
          case ('f')
            shell%option_noglob = enable_option
          case ('o')
            ! -o requires the next argument as the option name
            if (i >= cmd%num_tokens) then
              call list_shell_options(shell)
              shell%last_exit_status = 0
            else
              i = i + 1
              long_opt_name = trim(cmd%tokens(i))
              select case (trim(long_opt_name))
                case ('allexport')
                  shell%option_allexport = enable_option
                case ('braceexpand')
                  shell%option_braceexpand = enable_option
                case ('emacs')
                  shell%option_emacs = enable_option
                  shell%option_vi = .not. enable_option
                  call set_global_editing_mode(.not. enable_option)
                case ('errexit')
                  shell%option_errexit = enable_option
                case ('errtrace')
                  shell%option_errtrace = enable_option
                case ('functrace')
                  shell%option_functrace = enable_option
                case ('fuzzy-complete')
                  shell%option_fuzzy_complete = enable_option
                  call set_global_fuzzy_complete(enable_option)
                case ('hashall')
                  shell%option_hashall = enable_option
                case ('histexpand')
                  shell%option_histexpand = enable_option
                case ('history')
                  shell%option_history = enable_option
                case ('ignoreeof')
                  shell%option_ignoreeof = enable_option
                case ('interactive-comments')
                  shell%option_interactive_comments = enable_option
                case ('keyword')
                  shell%option_keyword = enable_option
                case ('monitor')
                  shell%option_monitor = enable_option
                case ('noclobber')
                  shell%option_noclobber = enable_option
                case ('noexec')
                  shell%option_noexec = enable_option
                case ('noglob')
                  shell%option_noglob = enable_option
                case ('nolog')
                  shell%option_nolog = enable_option
                case ('notify')
                  shell%option_notify = enable_option
                case ('nounset')
                  shell%option_nounset = enable_option
                case ('onecmd')
                  shell%option_onecmd = enable_option
                case ('physical')
                  shell%option_physical = enable_option
                case ('pipefail')
                  shell%option_pipefail = enable_option
                case ('posix')
                  shell%option_posix = enable_option
                case ('privileged')
                  shell%option_privileged = enable_option
                case ('verbose')
                  shell%option_verbose = enable_option
                case ('vi')
                  shell%option_vi = enable_option
                  shell%option_emacs = .not. enable_option
                  call set_global_editing_mode(enable_option)
                case ('xtrace')
                  shell%option_xtrace = enable_option
                case default
                  write(error_unit, '(a)') 'set: unknown option: ' // trim(long_opt_name)
                  shell%last_exit_status = 1
              end select
            end if
          case default
            write(error_unit, '(a)') 'set: unknown option: -' // option_name(fi:fi)
            had_error = .true.
            shell%last_exit_status = 1
          end select
          fi = fi + 1
        end do
      end block
      
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
      case ('nocasematch')
        shell%shopt_nocasematch = enable
      case ('extglob')
        shell%shopt_extglob = enable
      case ('dotglob')
        shell%shopt_dotglob = enable
      case ('expand_aliases')
        shell%shopt_expand_aliases = enable
      case default
        write(error_unit, '(a)') 'shopt: unknown option: ' // trim(option_name)
        shell%last_exit_status = 1
    end select
  end subroutine

  ! Show all shopt options
  subroutine show_shopt_options(shell)
    type(shell_state_t), intent(in) :: shell

    write(output_unit, '(a,a)') 'shopt ', merge('-s nullglob    ', '-u nullglob    ', shell%shopt_nullglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s failglob    ', '-u failglob    ', shell%shopt_failglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s globstar    ', '-u globstar    ', shell%shopt_globstar)
    write(output_unit, '(a,a)') 'shopt ', merge('-s nocaseglob  ', '-u nocaseglob  ', shell%shopt_nocaseglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s nocasematch ', '-u nocasematch ', shell%shopt_nocasematch)
    write(output_unit, '(a,a)') 'shopt ', merge('-s extglob     ', '-u extglob     ', shell%shopt_extglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s dotglob     ', '-u dotglob     ', shell%shopt_dotglob)
    write(output_unit, '(a,a)') 'shopt ', merge('-s expand_aliases', '-u expand_aliases', shell%shopt_expand_aliases)
  end subroutine

  ! Show shell variables (simplified version for 'set' without args)
  ! Uses write_stdout (C-level fd write) instead of Fortran output_unit
  ! so output respects dup2 redirections on all compilers (flang-new caches fd)
  subroutine show_shell_variables(shell)
    type(shell_state_t), intent(in) :: shell
    integer :: i
    character(len=64) :: num_str

    call write_stdout('# Shell variables:')
    do i = 1, shell%num_variables
      if (shell%variables(i)%name(1:1) /= char(0) .and. trim(shell%variables(i)%name) /= '') then
        if (shell%variables(i)%is_array) then
          call write_stdout(trim(shell%variables(i)%name) // '=(array)')
        else if (shell%variables(i)%is_assoc_array) then
          call write_stdout(trim(shell%variables(i)%name) // '=(associative array)')
        else
          block
            character(len=:), allocatable :: val
            logical :: needs_quote
            integer :: vi
            val = trim(shell%variables(i)%value)
            needs_quote = .false.
            do vi = 1, len(val)
              select case(val(vi:vi))
              case(' ', char(9), char(10), '"', "'", '\', '$', '`', &
                   '!', '(', ')', '{', '}', '[', ']', '|', '&', ';', &
                   '<', '>', '?', '*', '#', '~')
                needs_quote = .true.
                exit
              end select
            end do
            if (needs_quote) then
              call write_stdout(trim(shell%variables(i)%name) // '=' // "'" // val // "'")
            else
              call write_stdout(trim(shell%variables(i)%name) // '=' // val)
            end if
          end block
        end if
      end if
    end do

    call write_stdout('# Special variables:')
    write(num_str, '(i15)') shell%shell_pid
    call write_stdout('$$=' // trim(adjustl(num_str)))
    write(num_str, '(i15)') shell%last_bg_pid
    call write_stdout('$!=' // trim(adjustl(num_str)))
    call write_stdout('$0=' // trim(shell%shell_name))
    write(num_str, '(i15)') shell%parent_pid
    call write_stdout('$PPID=' // trim(adjustl(num_str)))
    write(num_str, '(i15)') shell%last_exit_status
    call write_stdout('$?=' // trim(adjustl(num_str)))
  end subroutine

  ! Check if errexit option is enabled and handle command failure
  subroutine check_errexit(shell, exit_status)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: exit_status

    ! POSIX: Don't trigger errexit in these contexts:
    ! - During if/while/until condition evaluation (evaluating_condition flag)
    ! - In AND-OR lists (&&, ||)
    ! - In negated pipelines (!)
    ! - In command substitution
    if (shell%evaluating_condition) return
    if (shell%in_and_or_list) return
    if (shell%in_negation) return
    if (shell%in_command_substitution) return

    if (shell%option_errexit .and. exit_status /= 0) then
      ! POSIX: errexit exits silently (no message)
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
    use prompt_formatting, only: expand_prompt
    use iso_c_binding, only: c_size_t, c_loc, c_char
    use system_interface, only: c_write
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command_line
    character(len=:), allocatable :: expanded_ps4
    character(len=2048) :: trace_line
    integer :: ps4_actual_len, trace_len
    character(kind=c_char), target, allocatable :: c_trace(:)
    integer(c_size_t) :: bytes_written
    integer :: i

    if (shell%option_xtrace) then
      ! Expand PS4 prompt (supports escape sequences like \h, \w, etc.)
      expanded_ps4 = expand_prompt(shell%ps4, shell, shell%ps4_len)
      ! Don't trim PS4 - it typically has a trailing space (e.g., '+ ')
      ps4_actual_len = shell%ps4_len
      if (ps4_actual_len > len(expanded_ps4)) ps4_actual_len = len_trim(expanded_ps4)

      ! Build trace line
      trace_line = expanded_ps4(1:ps4_actual_len) // trim(command_line)
      trace_len = len_trim(trace_line)

      ! Write to original stderr (shell's stderr, not affected by per-command redirections)
      ! This matches bash behavior where xtrace goes to shell's stderr
      allocate(c_trace(trace_len + 1))
      do i = 1, trace_len
        c_trace(i) = trace_line(i:i)
      end do
      c_trace(trace_len + 1) = char(10)  ! newline

      bytes_written = c_write(shell%original_stderr_fd, c_loc(c_trace), int(trace_len + 1, c_size_t))
      deallocate(c_trace)
    end if
  end subroutine

  ! List all shell options (for set -o)
  subroutine list_shell_options(shell)
    type(shell_state_t), intent(in) :: shell

    ! Print each option with its current state (on/off), alphabetically sorted
    call print_option('allexport', shell%option_allexport)
    call print_option('braceexpand', shell%option_braceexpand)
    call print_option('emacs', shell%option_emacs)
    call print_option('errexit', shell%option_errexit)
    call print_option('errtrace', shell%option_errtrace)
    call print_option('functrace', shell%option_functrace)
    call print_option('hashall', shell%option_hashall)
    call print_option('histexpand', shell%option_histexpand)
    call print_option('history', shell%option_history)
    call print_option('ignoreeof', shell%option_ignoreeof)
    call print_option('interactive-comments', shell%option_interactive_comments)
    call print_option('keyword', shell%option_keyword)
    call print_option('monitor', shell%option_monitor)
    call print_option('noclobber', shell%option_noclobber)
    call print_option('noexec', shell%option_noexec)
    call print_option('noglob', shell%option_noglob)
    call print_option('nolog', shell%option_nolog)
    call print_option('notify', shell%option_notify)
    call print_option('nounset', shell%option_nounset)
    call print_option('onecmd', shell%option_onecmd)
    call print_option('physical', shell%option_physical)
    call print_option('pipefail', shell%option_pipefail)
    call print_option('posix', shell%option_posix)
    call print_option('privileged', shell%option_privileged)
    call print_option('verbose', shell%option_verbose)
    call print_option('vi', shell%option_vi)
    call print_option('xtrace', shell%option_xtrace)
  end subroutine

  ! Helper to print an option with proper formatting
  subroutine print_option(name, value)
    character(len=*), intent(in) :: name
    logical, intent(in) :: value
    character(len=32) :: status

    if (value) then
      status = 'on'
    else
      status = 'off'
    end if
    write(output_unit, '(a,a,a)') name, '      	', trim(status)
  end subroutine

end module shell_options