! ==============================================================================
! Module: builtins (Extended with job control)
! ==============================================================================
module builtins
  use shell_types
  use system_interface
  use job_control
  use test_builtin
  use readline
  use shell_config
  use aliases
  use shell_options
  use command_builtin, only: find_command_in_path
  use performance
  use parser
  use coprocess
  use substitution
  use signal_handling
  use getopts_builtin
  use printf_builtin
  use read_builtin
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  function is_builtin(cmd_name) result(is_built)
    character(len=*), intent(in) :: cmd_name
    logical :: is_built

    is_built = (trim(cmd_name) == 'exit' .or. &
                trim(cmd_name) == 'cd' .or. &
                trim(cmd_name) == 'pwd' .or. &
                trim(cmd_name) == 'export' .or. &
                trim(cmd_name) == 'echo' .or. &
                trim(cmd_name) == 'jobs' .or. &
                trim(cmd_name) == 'fg' .or. &
                trim(cmd_name) == 'bg' .or. &
                trim(cmd_name) == 'source' .or. &
                trim(cmd_name) == '.' .or. &
                trim(cmd_name) == 'history' .or. &
                trim(cmd_name) == 'kill' .or. &
                trim(cmd_name) == 'wait' .or. &
                trim(cmd_name) == 'trap' .or. &
                trim(cmd_name) == 'config' .or. &
                trim(cmd_name) == 'alias' .or. &
                trim(cmd_name) == 'unalias' .or. &
                trim(cmd_name) == 'help' .or. &
                trim(cmd_name) == 'perf' .or. &
                trim(cmd_name) == 'memory' .or. &
                trim(cmd_name) == 'rawtest' .or. &
                trim(cmd_name) == 'defun' .or. &
                trim(cmd_name) == 'set' .or. &
                trim(cmd_name) == 'shopt' .or. &
                trim(cmd_name) == 'type' .or. &
                trim(cmd_name) == 'unset' .or. &
                trim(cmd_name) == 'readonly' .or. &
                trim(cmd_name) == 'declare' .or. &
                trim(cmd_name) == 'printenv' .or. &
                trim(cmd_name) == 'local' .or. &
                trim(cmd_name) == 'shift' .or. &
                trim(cmd_name) == 'break' .or. &
                trim(cmd_name) == 'continue' .or. &
                trim(cmd_name) == 'return' .or. &
                trim(cmd_name) == 'exec' .or. &
                trim(cmd_name) == 'eval' .or. &
                trim(cmd_name) == 'hash' .or. &
                trim(cmd_name) == 'umask' .or. &
                trim(cmd_name) == 'ulimit' .or. &
                trim(cmd_name) == 'times' .or. &
                trim(cmd_name) == 'let' .or. &
                trim(cmd_name) == 'getopts' .or. &
                trim(cmd_name) == 'printf' .or. &
                trim(cmd_name) == 'read' .or. &
                is_test_command(cmd_name))
  end function

  subroutine execute_builtin(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    select case(trim(cmd%tokens(1)))
    case('exit')
      call builtin_exit(cmd, shell)
    case('cd')
      call builtin_cd(cmd, shell)
    case('pwd')
      call builtin_pwd(cmd, shell)
    case('export')
      call builtin_export(cmd, shell)
    case('echo')
      call builtin_echo(cmd, shell)
    case('jobs')
      call builtin_jobs(cmd, shell)
    case('fg')
      call builtin_fg(cmd, shell)
    case('bg')
      call builtin_bg(cmd, shell)
    case('source', '.')
      call builtin_source(cmd, shell)
    case('history')
      call builtin_history(cmd, shell)
    case('kill')
      call builtin_kill(cmd, shell)
    case('wait')
      call builtin_wait(cmd, shell)
    case('trap')
      call builtin_trap(cmd, shell)
    case('config')
      call builtin_config(cmd, shell)
    case('alias')
      call builtin_alias(cmd, shell)
    case('unalias')
      call builtin_unalias(cmd, shell)
    case('help')
      call builtin_help(cmd, shell)
    case('perf')
      call builtin_perf(cmd, shell)
    case('memory')
      call builtin_memory(cmd, shell)
    case('rawtest')
      call builtin_rawtest(cmd, shell)
    case('defun')
      call builtin_defun(cmd, shell)
    case('test', '[', '[[')
      call execute_test_command(cmd, shell)
    case('set')
      call builtin_set(cmd, shell)
    case('shopt')
      call builtin_shopt(cmd, shell)
    case('type')
      call builtin_type(cmd, shell)
    case('unset')
      call builtin_unset(cmd, shell)
    case('readonly')
      call builtin_readonly(cmd, shell)
    case('declare')
      call builtin_declare(cmd, shell)
    case('printenv')
      call builtin_printenv(cmd, shell)
    case('local')
      call builtin_local(cmd, shell)
    case('shift')
      call builtin_shift(cmd, shell)
    case('break')
      call builtin_break(cmd, shell)
    case('continue')
      call builtin_continue(cmd, shell)
    case('return')
      call builtin_return(cmd, shell)
    case('exec')
      call builtin_exec(cmd, shell)
    case('hash')
      call builtin_hash(cmd, shell)
    case('umask')
      call builtin_umask(cmd, shell)
    case('ulimit')
      call builtin_ulimit(cmd, shell)
    case('times')
      call builtin_times(cmd, shell)
    case('let')
      call builtin_let(cmd, shell)
    case('getopts')
      call builtin_getopts(cmd, shell)
    case('printf')
      call builtin_printf(cmd, shell)
    case('read')
      call builtin_read(cmd, shell)
    case default
      ! Should not reach here if is_builtin works correctly
      shell%last_exit_status = 1
    end select
  end subroutine

  subroutine builtin_exit(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    shell%running = .false.
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=shell%last_exit_status) shell%last_exit_status
    end if
  end subroutine

  subroutine builtin_cd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: target_dir
    
    if (cmd%num_tokens == 1) then
      target_dir = get_environment_var('HOME')
    else
      target_dir = trim(cmd%tokens(2))
    end if
    
    if (change_directory(target_dir)) then
      shell%cwd = get_current_directory()
      shell%last_exit_status = 0
    else
      write(error_unit, '(a)') 'cd: cannot access ' // trim(target_dir) // &
                              ': No such file or directory. Use "pwd" to see current location.'
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine builtin_pwd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    write(output_unit, '(a)') trim(shell%cwd)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_export(cmd, shell)
    use variables, only: set_shell_variable, get_shell_variable
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos, i, j, arg_idx
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    logical :: print_mode, found

    print_mode = .false.

    if (cmd%num_tokens < 2) then
      ! No arguments: print all exported variables
      print_mode = .true.
    end if

    if (print_mode) then
      ! Print all exported variables
      do i = 1, shell%num_variables
        if (shell%variables(i)%exported .and. len_trim(shell%variables(i)%name) > 0) then
          write(output_unit, '(a)') 'export ' // trim(shell%variables(i)%name) // '=' // &
                                   trim(shell%variables(i)%value)
        end if
      end do
      shell%last_exit_status = 0
      return
    end if

    ! Process each argument
    do arg_idx = 2, cmd%num_tokens
      eq_pos = index(cmd%tokens(arg_idx), '=')

      if (eq_pos > 0) then
        ! VAR=value form - set and export
        var_name = cmd%tokens(arg_idx)(:eq_pos-1)
        var_value = cmd%tokens(arg_idx)(eq_pos+1:)

        ! Set as shell variable first
        call set_shell_variable(shell, trim(var_name), trim(var_value))

        ! Mark as exported
        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == trim(var_name)) then
            shell%variables(j)%exported = .true.
            ! Also set in environment
            if (.not. set_environment_var(trim(var_name), trim(var_value))) then
              write(error_unit, '(a)') 'export: failed to set environment variable'
              shell%last_exit_status = 1
              return
            end if
            exit
          end if
        end do
      else
        ! Just VAR - mark existing variable as exported
        var_name = trim(cmd%tokens(arg_idx))
        found = .false.

        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == var_name) then
            shell%variables(j)%exported = .true.
            found = .true.
            ! Export current value to environment
            if (.not. set_environment_var(var_name, trim(shell%variables(j)%value))) then
              write(error_unit, '(a)') 'export: failed to set environment variable'
              shell%last_exit_status = 1
              return
            end if
            exit
          end if
        end do

        if (.not. found) then
          ! Variable doesn't exist, create it with empty value and export
          call set_shell_variable(shell, var_name, '')
          do j = 1, shell%num_variables
            if (trim(shell%variables(j)%name) == var_name) then
              shell%variables(j)%exported = .true.
              if (.not. set_environment_var(var_name, '')) then
                write(error_unit, '(a)') 'export: failed to set environment variable'
                shell%last_exit_status = 1
                return
              end if
              exit
            end if
          end do
        end if
      end if
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_echo(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    logical :: first
    
    ! Simple echo implementation
    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens < 1) then
      write(*,'(a)') ''
      shell%last_exit_status = 0
      return
    end if
    
    first = .true.
    do i = 2, cmd%num_tokens
      if (.not. first) write(*,'(a)',advance='no') ' '
      write(*,'(a)',advance='no') trim(cmd%tokens(i))
      first = .false.
    end do
    write(*,'(a)') ''
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_jobs(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical :: show_pids
    
    ! Check for -p flag to show PIDs
    show_pids = .false.
    if (cmd%num_tokens > 1 .and. trim(cmd%tokens(2)) == '-p') then
      show_pids = .true.
    end if
    
    call list_jobs(shell, show_pids)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_fg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, iostat, i
    
    if (cmd%num_tokens < 2) then
      ! Bring most recent stopped job to foreground
      job_id = 0
      do i = MAX_JOBS, 1, -1
        if (shell%jobs(i)%job_id > 0 .and. shell%jobs(i)%state == JOB_STOPPED) then
          job_id = shell%jobs(i)%job_id
          exit
        end if
      end do
      
      if (job_id == 0) then
        write(error_unit, '(a)') 'fg: no stopped job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job number (handle %n syntax)
      if (cmd%tokens(2)(1:1) == '%') then
        read(cmd%tokens(2)(2:), *, iostat=iostat) job_id
      else
        read(cmd%tokens(2), *, iostat=iostat) job_id
      end if
      
      if (iostat /= 0) then
        write(error_unit, '(a)') 'fg: invalid job id'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    call resume_job_fg(shell, job_id)
  end subroutine

  subroutine builtin_bg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, iostat, i
    
    if (cmd%num_tokens < 2) then
      ! Continue most recent stopped job in background
      job_id = 0
      do i = MAX_JOBS, 1, -1
        if (shell%jobs(i)%job_id > 0 .and. &
            shell%jobs(i)%state == JOB_STOPPED) then
          job_id = shell%jobs(i)%job_id
          exit
        end if
      end do
      
      if (job_id == 0) then
        write(error_unit, '(a)') 'bg: no stopped job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job number (handle %n syntax)
      if (cmd%tokens(2)(1:1) == '%') then
        read(cmd%tokens(2)(2:), *, iostat=iostat) job_id
      else
        read(cmd%tokens(2), *, iostat=iostat) job_id
      end if
      
      if (iostat /= 0) then
        write(error_unit, '(a)') 'bg: invalid job id'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    call resume_job_bg(shell, job_id)
  end subroutine

  subroutine builtin_source(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=1024) :: filename
    logical :: file_exists
    integer :: i
    
    ! Check if filename provided
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'source: usage: source filename [arguments...]'
      shell%last_exit_status = 1
      return
    end if
    
    filename = trim(cmd%tokens(2))
    
    ! Check if file exists and is readable
    inquire(file=filename, exist=file_exists)
    if (.not. file_exists) then
      write(error_unit, '(a)') 'source: ' // trim(filename) // ': No such file or directory'
      shell%last_exit_status = 1
      return
    end if
    
    ! Set positional parameters from remaining arguments
    ! Save $0 (script name)
    shell%shell_name = trim(filename)

    ! Set $1, $2, ... from arguments
    shell%num_positional = 0
    if (cmd%num_tokens > 2) then
      do i = 3, cmd%num_tokens
        shell%num_positional = shell%num_positional + 1
        if (shell%num_positional <= size(shell%positional_params)) then
          shell%positional_params(shell%num_positional) = trim(cmd%tokens(i))
        end if
      end do
    end if

    ! Mark the shell to source this file on next main loop iteration
    ! This avoids circular dependency issues
    shell%source_file = filename
    shell%should_source = .true.
    shell%last_exit_status = 0

    write(output_unit, '(a)') 'source: ' // trim(filename) // ' queued for execution'
  end subroutine

  subroutine builtin_history(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, n, offset, iostat, history_start_index
    character(len=256) :: arg

    ! Handle history command options
    if (cmd%num_tokens > 1) then
      arg = trim(cmd%tokens(2))

      select case(arg)
      case('-c', '--clear')
        ! Clear history
        call clear_history()
        write(output_unit, '(a)') 'Command history cleared.'
        shell%last_exit_status = 0
        return

      case('-d')
        ! Delete history entry at offset
        if (cmd%num_tokens < 3) then
          write(error_unit, '(a)') 'history: -d requires an argument'
          shell%last_exit_status = 1
          return
        end if

        read(cmd%tokens(3), *, iostat=iostat) offset
        if (iostat /= 0 .or. offset < 1) then
          write(error_unit, '(a)') 'history: -d: invalid offset'
          shell%last_exit_status = 1
          return
        end if

        call delete_history_entry(offset)
        shell%last_exit_status = 0
        return

      case('-a')
        ! Append new history lines to history file
        if (len_trim(shell%histfile) == 0) then
          write(error_unit, '(a)') 'history: HISTFILE not set'
          shell%last_exit_status = 1
          return
        end if

        ! We'll append all history for simplicity (could track last saved index)
        call save_history_to_file(trim(shell%histfile), shell%histfilesize)
        shell%last_exit_status = 0
        return

      case('-r')
        ! Read history file and append to current history
        if (len_trim(shell%histfile) == 0) then
          write(error_unit, '(a)') 'history: HISTFILE not set'
          shell%last_exit_status = 1
          return
        end if

        call load_history_from_file(trim(shell%histfile), shell%histsize)
        shell%last_exit_status = 0
        return

      case('-w')
        ! Write current history to history file
        if (len_trim(shell%histfile) == 0) then
          write(error_unit, '(a)') 'history: HISTFILE not set'
          shell%last_exit_status = 1
          return
        end if

        call save_history_to_file(trim(shell%histfile), shell%histfilesize)
        shell%last_exit_status = 0
        return

      case default
        ! Try to parse as number (show last n commands)
        read(arg, *, iostat=iostat) n
        if (iostat /= 0) then
          write(error_unit, '(a)') 'history: unknown option: ' // trim(arg)
          shell%last_exit_status = 1
          return
        end if

        ! Show last n commands
        history_start_index = max(1, get_history_count() - n + 1)
        do i = history_start_index, get_history_count()
          write(output_unit, '(i4,2x,a)') i, trim(command_history%lines(i))
        end do
        shell%last_exit_status = 0
        return
      end select
    else
      ! Show all history
      call show_history()
      shell%last_exit_status = 0
    end if
  end subroutine

  subroutine builtin_kill(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: signal_num, target_pid, iostat, ret
    integer :: i, arg_start
    logical :: found_signal
    
    signal_num = 15  ! Default: SIGTERM
    arg_start = 2
    found_signal = .false.
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'kill: usage: kill [-signal] pid...'
      shell%last_exit_status = 1
      return
    end if
    
    ! Check if first argument is a signal specifier or -l flag
    if (cmd%tokens(2)(1:1) == '-') then
      if (len_trim(cmd%tokens(2)) > 1) then
        ! Check for -l flag (list signals)
        if (trim(cmd%tokens(2)) == '-l') then
          write(output_unit, '(a)') 'Available signals:'
          write(output_unit, '(a)') '  1) SIGHUP    2) SIGINT    3) SIGQUIT   4) SIGILL'
          write(output_unit, '(a)') '  5) SIGTRAP   6) SIGABRT   7) SIGBUS    8) SIGFPE'
          write(output_unit, '(a)') '  9) SIGKILL  10) SIGUSR1  11) SIGSEGV  12) SIGUSR2'
          write(output_unit, '(a)') ' 13) SIGPIPE  14) SIGALRM  15) SIGTERM  16) SIGSTKFLT'
          write(output_unit, '(a)') ' 17) SIGCHLD  18) SIGCONT  19) SIGSTOP  20) SIGTSTP'
          write(output_unit, '(a)') ' 21) SIGTTIN  22) SIGTTOU'
          shell%last_exit_status = 0
          return
        end if
        
        read(cmd%tokens(2)(2:), *, iostat=iostat) signal_num
        if (iostat /= 0) then
          ! Try named signals
          select case(trim(cmd%tokens(2)(2:)))
          case('TERM', 'term')
            signal_num = 15
          case('KILL', 'kill') 
            signal_num = 9
          case('INT', 'int')
            signal_num = 2
          case('STOP', 'stop')
            signal_num = 19
          case('CONT', 'cont')
            signal_num = 18
          case('HUP', 'hup')
            signal_num = 1
          case('QUIT', 'quit')
            signal_num = 3
          case default
            write(error_unit, '(a)') 'kill: invalid signal specification'
            shell%last_exit_status = 1
            return
          end select
        end if
        found_signal = .true.
        arg_start = 3
      end if
    end if
    
    if (cmd%num_tokens < arg_start) then
      write(error_unit, '(a)') 'kill: usage: kill [-signal] pid...'
      shell%last_exit_status = 1
      return
    end if
    
    ! Kill each specified process
    do i = arg_start, cmd%num_tokens
      ! Handle job syntax (%n)
      if (cmd%tokens(i)(1:1) == '%') then
        read(cmd%tokens(i)(2:), *, iostat=iostat) target_pid
        if (iostat == 0) then
          ! Find job by job_id and get its pgid
          target_pid = find_job_pgid(shell, target_pid)
          if (target_pid <= 0) then
            write(error_unit, '(a)') 'kill: no such job'
            shell%last_exit_status = 1
            cycle
          end if
          target_pid = -target_pid  ! Kill entire process group
        else
          write(error_unit, '(a)') 'kill: invalid job specification'
          shell%last_exit_status = 1
          cycle
        end if
      else
        read(cmd%tokens(i), *, iostat=iostat) target_pid
        if (iostat /= 0) then
          write(error_unit, '(a)') 'kill: invalid pid'
          shell%last_exit_status = 1
          cycle
        end if
      end if
      
      ret = c_kill(int(target_pid, c_pid_t), int(signal_num, c_int))
      if (ret /= 0) then
        write(error_unit, '(a,i0)') 'kill: failed to kill process ', target_pid
        shell%last_exit_status = 1
      end if
    end do
    
    if (shell%last_exit_status /= 1) then
      shell%last_exit_status = 0
    end if
  end subroutine


  subroutine builtin_wait(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: target_pid, iostat, ret
    integer(c_int), target :: wait_status
    integer :: i
    
    if (cmd%num_tokens == 1) then
      ! Wait for all background jobs
      do i = 1, MAX_JOBS
        if (shell%jobs(i)%job_id > 0 .and. &
            shell%jobs(i)%state == JOB_RUNNING) then
          ret = c_waitpid(shell%jobs(i)%pgid, c_loc(wait_status), 0)
          if (WIFEXITED(wait_status)) then
            shell%jobs(i)%state = JOB_DONE
          end if
        end if
      end do
    else
      ! Wait for specific job or PID
      do i = 2, cmd%num_tokens
        if (cmd%tokens(i)(1:1) == '%') then
          ! Job syntax
          read(cmd%tokens(i)(2:), *, iostat=iostat) target_pid
          if (iostat == 0) then
            target_pid = find_job_pgid(shell, target_pid)
          else
            write(error_unit, '(a)') 'wait: invalid job specification'
            shell%last_exit_status = 1
            cycle
          end if
        else
          read(cmd%tokens(i), *, iostat=iostat) target_pid
          if (iostat /= 0) then
            write(error_unit, '(a)') 'wait: invalid pid'
            shell%last_exit_status = 1
            cycle
          end if
        end if
        
        if (target_pid > 0) then
          ret = c_waitpid(int(target_pid, c_pid_t), c_loc(wait_status), 0)
          if (ret > 0) then
            if (WIFEXITED(wait_status)) then
              shell%last_exit_status = WEXITSTATUS(wait_status)
            else
              shell%last_exit_status = 1
            end if
          else
            write(error_unit, '(a,i0)') 'wait: pid ', target_pid, ' is not a child of this shell'
            shell%last_exit_status = 1
          end if
        end if
      end do
    end if
    
    if (shell%last_exit_status /= 1) then
      shell%last_exit_status = 0
    end if
  end subroutine

  subroutine builtin_trap(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: action
    character(len=256) :: signal_spec
    integer :: i, j, k, signum
    logical :: list_mode, remove_mode

    list_mode = .false.
    remove_mode = .false.

    ! trap (no arguments) - list all traps
    if (cmd%num_tokens == 1) then
      call list_traps(shell)
      shell%last_exit_status = 0
      return
    end if

    ! trap -l (list signals)
    if (cmd%num_tokens == 2 .and. trim(cmd%tokens(2)) == '-l') then
      write(output_unit, '(a)') 'Available signals:'
      write(output_unit, '(a)') '  1) SIGHUP    2) SIGINT    3) SIGQUIT   4) SIGILL'
      write(output_unit, '(a)') '  5) SIGTRAP   6) SIGABRT   7) SIGBUS    8) SIGFPE'
      write(output_unit, '(a)') '  9) SIGKILL  10) SIGUSR1  11) SIGSEGV  12) SIGUSR2'
      write(output_unit, '(a)') ' 13) SIGPIPE  14) SIGALRM  15) SIGTERM  16) SIGSTKFLT'
      write(output_unit, '(a)') ' 17) SIGCHLD  18) SIGCONT  19) SIGSTOP  20) SIGTSTP'
      write(output_unit, '(a)') ' 21) SIGTTIN  22) SIGTTOU'
      write(output_unit, '(a)') ''
      write(output_unit, '(a)') 'Special signals:'
      write(output_unit, '(a)') '  0) EXIT      DEBUG        ERR          RETURN'
      shell%last_exit_status = 0
      return
    end if

    ! trap -p [signal...] (print traps)
    if (trim(cmd%tokens(2)) == '-p') then
      if (cmd%num_tokens == 2) then
        ! Print all traps
        call list_traps(shell)
      else
        ! Print specific traps
        do j = 3, cmd%num_tokens
          signum = signal_name_to_number(trim(cmd%tokens(j)))
          if (signum == -999) then
            write(error_unit, '(a)') 'trap: invalid signal: ' // trim(cmd%tokens(j))
            shell%last_exit_status = 1
            return
          end if
          ! Print trap for this signal if it exists
          do k = 1, size(shell%traps)
            if (shell%traps(k)%signal == signum .and. shell%traps(k)%active) then
              write(output_unit, '(a)') 'trap -- ' // "'" // &
                                        trim(shell%traps(k)%command) // "' " // &
                                        trim(signal_number_to_name(signum))
              exit
            end if
          end do
        end do
      end if
      shell%last_exit_status = 0
      return
    end if

    ! trap action signal [signal...]
    if (cmd%num_tokens < 3) then
      write(error_unit, '(a)') 'trap: usage: trap [-lp] [action signal_spec ...]'
      shell%last_exit_status = 1
      return
    end if

    ! Get action
    action = trim(cmd%tokens(2))

    ! Check for removal syntax: trap - signal or trap "" signal
    if (trim(action) == '-' .or. len_trim(action) == 0) then
      remove_mode = .true.
    end if

    ! Process each signal
    do i = 3, cmd%num_tokens
      signal_spec = trim(cmd%tokens(i))

      ! Convert signal name/number to signal number
      signum = signal_name_to_number(signal_spec)

      if (signum == -999) then
        write(error_unit, '(a)') 'trap: invalid signal specification: ' // trim(signal_spec)
        shell%last_exit_status = 1
        cycle
      end if

      ! Check if signal is trappable
      if (.not. is_trappable_signal(signum) .and. signum > 0) then
        write(error_unit, '(a)') 'trap: ' // trim(signal_spec) // ': cannot trap signal'
        shell%last_exit_status = 1
        cycle
      end if

      if (remove_mode) then
        ! Remove trap
        call remove_signal_trap(shell, signum)
      else
        ! Set trap
        call set_signal_trap(shell, signum, action)
      end if
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_config(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    if (cmd%num_tokens == 1) then
      ! Show current config
      call show_config()
    else
      select case(trim(cmd%tokens(2)))
      case('show')
        call show_config()
      case('create')
        call create_default_config()
      case('reload')
        call load_config_file(shell)
      case default
        write(error_unit, '(a)') 'config: usage: config [show|create|reload]'
        shell%last_exit_status = 1
        return
      end select
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_alias(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos
    character(len=256) :: alias_name, alias_command
    
    if (cmd%num_tokens == 1) then
      ! Show all aliases
      call show_aliases(shell)
    else if (cmd%num_tokens == 2) then
      ! Check for alias=command format
      eq_pos = index(cmd%tokens(2), '=')
      if (eq_pos > 0) then
        alias_name = cmd%tokens(2)(:eq_pos-1)
        alias_command = cmd%tokens(2)(eq_pos+1:)
        
        ! Remove quotes if present
        if (alias_command(1:1) == '"' .and. alias_command(len_trim(alias_command):len_trim(alias_command)) == '"') then
          alias_command = alias_command(2:len_trim(alias_command)-1)
        else if (alias_command(1:1) == "'" .and. alias_command(len_trim(alias_command):len_trim(alias_command)) == "'") then
          alias_command = alias_command(2:len_trim(alias_command)-1)
        end if
        
        call set_alias(shell, trim(alias_name), trim(alias_command))
      else
        ! Show specific alias
        alias_name = cmd%tokens(2)
        alias_command = get_alias(shell, trim(alias_name))
        if (len(alias_command) > 0) then
          write(output_unit, '(a)') 'alias ' // trim(alias_name) // &
                                   '=' // "'" // trim(alias_command) // "'"
        else
          write(error_unit, '(a)') 'alias: ' // trim(alias_name) // ': not found'
          shell%last_exit_status = 1
          return
        end if
      end if
    else
      write(error_unit, '(a)') 'alias: usage: alias [name[=value]...]'
      shell%last_exit_status = 1
      return
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_unalias(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'unalias: usage: unalias name...'
      shell%last_exit_status = 1
      return
    end if
    
    ! Remove each specified alias
    do i = 2, cmd%num_tokens
      call unset_alias(shell, trim(cmd%tokens(i)))
    end do
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_help(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    write(output_unit, '(a)') 'Fortran Shell (fortsh) - Built-in Commands:'
    write(output_unit, '(a)') '========================================'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Navigation & Files:'
    write(output_unit, '(a)') '  cd [dir]      - Change directory (use cd ~ for home)'
    write(output_unit, '(a)') '  pwd           - Print working directory'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Variables & Environment:'
    write(output_unit, '(a)') '  export VAR=val - Set environment variable'
    write(output_unit, '(a)') '  echo [args]    - Display text'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Job Control:'
    write(output_unit, '(a)') '  jobs          - List active jobs'
    write(output_unit, '(a)') '  fg [%n]       - Bring job to foreground'
    write(output_unit, '(a)') '  bg [%n]       - Send job to background'  
    write(output_unit, '(a)') '  kill [-sig] pid - Send signal to process'
    write(output_unit, '(a)') '  wait [pid]    - Wait for process to complete'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Shell Features:'
    write(output_unit, '(a)') '  history       - Show command history'
    write(output_unit, '(a)') '  alias [n=cmd] - Create/show command aliases'
    write(output_unit, '(a)') '  unalias name  - Remove alias'
    write(output_unit, '(a)') '  config [cmd]  - Manage shell configuration (.fshrc)'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Control Flow:'
    write(output_unit, '(a)') '  test / [ ]    - Evaluate conditions'
    write(output_unit, '(a)') '  if/then/else/fi - Conditional execution'
    write(output_unit, '(a)') '  while/do/done - Loop constructs'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Other:'
    write(output_unit, '(a)') '  source file   - Execute script (not yet implemented)'
    write(output_unit, '(a)') '  trap          - Signal handling (basic support)'
    write(output_unit, '(a)') '  rawtest       - Test raw terminal input (interactive only)'
    write(output_unit, '(a)') '  help          - Show this help message'
    write(output_unit, '(a)') '  exit [code]   - Exit shell'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Interactive Editing (available in interactive mode):'
    write(output_unit, '(a)') '  ↑/↓           - Navigate command history'
    write(output_unit, '(a)') '  ←/→, Ctrl+B/F - Move cursor left/right'
    write(output_unit, '(a)') '  Ctrl+A        - Move to beginning of line (Home)'
    write(output_unit, '(a)') '  Ctrl+E        - Move to end of line (End)'
    write(output_unit, '(a)') '  Tab           - Smart command/file completion'
    write(output_unit, '(a)') '  Ctrl+K        - Kill text to end of line'
    write(output_unit, '(a)') '  Ctrl+U        - Kill entire line'  
    write(output_unit, '(a)') '  Ctrl+W        - Kill previous word'
    write(output_unit, '(a)') '  Ctrl+Y        - Yank (paste) killed text'
    write(output_unit, '(a)') '  Ctrl+L        - Clear screen'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Features: Advanced readline, tab completion, history, aliases, job control'
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_perf(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    if (cmd%num_tokens > 1) then
      select case(trim(cmd%tokens(2)))
      case('on')
        call set_performance_monitoring(.true.)
        write(output_unit, '(a)') 'Performance monitoring enabled'
      case('off')
        call set_performance_monitoring(.false.)
        write(output_unit, '(a)') 'Performance monitoring disabled'
      case('stats', 'status')
        call print_performance_stats()
      case('reset')
        total_commands = 0
        total_parse_time = 0
        total_exec_time = 0
        total_glob_time = 0
        write(output_unit, '(a)') 'Performance counters reset'
      case default
        write(error_unit, '(a)') 'perf: Usage: perf [on|off|stats|reset]'
        shell%last_exit_status = 1
        return
      end select
    else
      ! Show current status
      if (perf_monitoring_enabled) then
        write(output_unit, '(a)') 'Performance monitoring: ENABLED'
      else
        write(output_unit, '(a)') 'Performance monitoring: DISABLED'
      end if
      write(output_unit, '(a,i0)') 'Commands processed: ', total_commands
      write(output_unit, '(a,i0,a)') 'Memory usage: ', get_memory_usage(), ' KB'
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_memory(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    if (cmd%num_tokens > 1) then
      select case(trim(cmd%tokens(2)))
      case('optimize')
        call optimize_memory_pools()
        write(output_unit, '(a)') 'Memory pools optimized'
      case('stats')
        call print_pool_stats()
      case('auto')
        call auto_optimize_memory()
        write(output_unit, '(a)') 'Auto memory optimization triggered'
      case default
        write(error_unit, '(a)') 'memory: Usage: memory [optimize|stats|auto]'
        shell%last_exit_status = 1
        return
      end select
    else
      ! Show memory status
      write(output_unit, '(a)') 'Memory Usage Summary:'
      write(output_unit, '(a)') '===================='
      write(output_unit, '(a,i0)') 'Current allocations: ', current_allocations
      write(output_unit, '(a,i0)') 'Peak allocations:    ', peak_allocations
      write(output_unit, '(a,i0,a)') 'Current memory:      ', current_memory_used, ' bytes'
      write(output_unit, '(a,i0,a)') 'Peak memory:         ', peak_memory_used, ' bytes'
      
      if (needs_memory_optimization()) then
        write(output_unit, '(a)') ''
        write(output_unit, '(a)') 'Tip: Memory optimization recommended. Run "memory optimize"'
      end if
    end if
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_rawtest(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    type(termios_t) :: original_termios
    character :: ch
    logical :: success
    integer :: char_code
    
    write(output_unit, '(a)') 'Raw mode test - press keys to see codes, q to quit:'
    write(output_unit, '(a)') 'Entering raw mode...'
    
    ! Enable raw mode
    success = enable_raw_mode(original_termios)
    if (.not. success) then
      write(error_unit, '(a)') 'rawtest: Failed to enable raw mode'
      shell%last_exit_status = 1
      return
    end if
    
    ! Read characters until 'q' is pressed
    do
      success = read_single_char(ch)
      if (.not. success) exit
      
      char_code = iachar(ch)
      
      ! Exit on 'q'
      if (ch == 'q' .or. ch == 'Q') exit
      
      ! Handle special characters
      if (char_code == 27) then
        ! Escape sequence - try to read more
        write(output_unit, '(a)', advance='no') 'ESC '
        success = read_single_char(ch)
        if (success) then
          write(output_unit, '(a,i0)', advance='no') '[', iachar(ch)
          if (ch == '[') then
            success = read_single_char(ch)
            if (success) then
              write(output_unit, '(a,i0,a)', advance='no') '[', iachar(ch), '] = '
              select case(ch)
              case('A')
                write(output_unit, '(a)') 'UP ARROW'
              case('B')
                write(output_unit, '(a)') 'DOWN ARROW'
              case('C')
                write(output_unit, '(a)') 'RIGHT ARROW'
              case('D')
                write(output_unit, '(a)') 'LEFT ARROW'
              case default
                write(output_unit, '(a)') 'UNKNOWN ESCAPE'
              end select
            end if
          else
            write(output_unit, '(a)') '] = ALT+key'
          end if
        end if
      else if (char_code < 32) then
        ! Control character
        write(output_unit, '(a,i0,a)') 'CTRL+', char_code, ' (^', char(char_code + 64), ')'
      else if (char_code == 127) then
        write(output_unit, '(a)') 'BACKSPACE/DELETE (127)'
      else
        ! Regular character
        write(output_unit, '(a,a,a,i0,a)') 'Regular: ''', ch, ''' (', char_code, ')'
      end if
    end do
    
    ! Restore terminal
    success = restore_terminal(original_termios)
    if (.not. success) then
      write(error_unit, '(a)') 'rawtest: Warning - failed to restore terminal'
    end if
    
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Raw mode test completed.'
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_defun(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=1024) :: function_body(1)
    character(len=256) :: func_name
    integer :: i

    if (cmd%num_tokens < 3) then
      write(error_unit, '(a)') 'defun: usage: defun function_name "command1; command2"'
      shell%last_exit_status = 1
      return
    end if

    func_name = trim(cmd%tokens(2))

    ! Reconstruct the function body from all remaining tokens
    ! This handles cases where the parser split the quoted string
    function_body(1) = trim(cmd%tokens(3))
    do i = 4, cmd%num_tokens
      function_body(1) = trim(function_body(1)) // ' ' // trim(cmd%tokens(i))
    end do

    ! Strip quotes from function body
    if (len_trim(function_body(1)) >= 2) then
      if (function_body(1)(1:1) == '"' .or. function_body(1)(1:1) == "'") then
        ! Check if last character is also a quote
        if (function_body(1)(len_trim(function_body(1)):len_trim(function_body(1))) == '"' .or. &
            function_body(1)(len_trim(function_body(1)):len_trim(function_body(1))) == "'") then
          ! Remove first and last character (quotes)
          function_body(1) = function_body(1)(2:len_trim(function_body(1))-1)
        end if
      end if
    end if

    call add_function(shell, func_name, function_body, 1)
    write(output_unit, '(a)') 'Function ' // trim(func_name) // ' defined'
    shell%last_exit_status = 0
  end subroutine

  ! Coprocess built-in commands
  subroutine builtin_coproc(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: coproc_name
    character(len=1024) :: command
    integer :: coproc_id
    
    if (cmd%num_tokens < 2) then
      call list_coprocesses()
      shell%last_exit_status = 0
      return
    end if
    
    if (cmd%num_tokens == 2) then
      ! coproc command
      command = trim(cmd%tokens(2))
      coproc_id = start_coprocess(command)
    else
      ! coproc name command
      coproc_name = trim(cmd%tokens(2))
      command = trim(cmd%tokens(3))
      coproc_id = start_coprocess(command, coproc_name)
    end if
    
    if (coproc_id > 0) then
      shell%last_exit_status = 0
    else
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine builtin_timeout(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    integer :: timeout_seconds, i
    character(len=1024) :: command
    
    if (cmd%num_tokens < 3) then
      write(error_unit, '(a)') 'timeout: usage: timeout DURATION COMMAND...'
      shell%last_exit_status = 1
      return
    end if
    
    read(cmd%tokens(2), *, iostat=i) timeout_seconds
    if (i /= 0 .or. timeout_seconds <= 0) then
      write(error_unit, '(a)') 'timeout: invalid duration'
      shell%last_exit_status = 1
      return
    end if
    
    ! Reconstruct command from remaining tokens
    command = ''
    do i = 3, cmd%num_tokens
      if (i > 3) command = trim(command) // ' '
      command = trim(command) // trim(cmd%tokens(i))
    end do
    
    ! Execute command with timeout - placeholder
    shell%last_exit_status = 0
  end subroutine

  ! =============================================================================
  ! POSIX Required Built-ins (Phase 10: Critical POSIX Compliance)
  ! =============================================================================

  subroutine builtin_type(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    character(len=256) :: command_name
    integer :: i
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'type: usage: type name [name ...]'
      shell%last_exit_status = 1
      return
    end if
    
    do i = 2, cmd%num_tokens
      command_name = trim(cmd%tokens(i))
      
      if (is_builtin(command_name)) then
        write(output_unit, '(a)') trim(command_name) // ' is a shell builtin'
      else if (is_alias(shell, command_name)) then
        write(output_unit, '(a)') trim(command_name) // ' is aliased to `' // &
                                 trim(get_alias(shell, command_name)) // "'"
      else if (is_function(shell, command_name)) then
        write(output_unit, '(a)') trim(command_name) // ' is a function'
      else
        ! Try to find in PATH
        call find_command_in_path(shell, command_name, .false., .false.)
        if (shell%last_exit_status == 0) then
          write(output_unit, '(a)') trim(command_name) // ' is hashed'
        else
          write(output_unit, '(a)') trim(command_name) // ': not found'
          shell%last_exit_status = 1
        end if
      end if
    end do
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_unset(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    logical :: unset_functions = .false.
    character(len=256) :: var_name
    integer :: i, j, start_idx
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'unset: usage: unset [-f] name [name ...]'
      shell%last_exit_status = 1
      return
    end if
    
    start_idx = 2
    if (trim(cmd%tokens(2)) == '-f') then
      unset_functions = .true.
      start_idx = 3
      if (cmd%num_tokens < 3) then
        write(error_unit, '(a)') 'unset: usage: unset [-f] name [name ...]'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    do i = start_idx, cmd%num_tokens
      var_name = trim(cmd%tokens(i))
      
      if (unset_functions) then
        ! Unset function
        do j = 1, shell%num_functions
          if (trim(shell%functions(j)%name) == var_name) then
            shell%functions(j)%name = ''
            shell%functions(j)%body_lines = 0
            if (allocated(shell%functions(j)%body)) deallocate(shell%functions(j)%body)
            exit
          end if
        end do
      else
        ! Unset variable
        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == var_name) then
            ! Check if variable is readonly
            if (shell%variables(j)%readonly) then
              write(error_unit, '(a)') 'unset: ' // trim(var_name) // ': cannot unset readonly variable'
              shell%last_exit_status = 1
              return
            end if
            ! Unset from environment if exported
            if (shell%variables(j)%exported) then
              call unset_environment_var(var_name)
            end if
            shell%variables(j)%name = ''
            shell%variables(j)%value = ''
            shell%variables(j)%is_array = .false.
            shell%variables(j)%is_assoc_array = .false.
            shell%variables(j)%readonly = .false.
            shell%variables(j)%exported = .false.
            shell%variables(j)%array_size = 0
            shell%variables(j)%assoc_size = 0
            exit
          end if
        end do
      end if
    end do
    
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_readonly(cmd, shell)
    use variables, only: set_shell_variable
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos, i, j, arg_idx
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    logical :: print_mode, found

    print_mode = .false.

    if (cmd%num_tokens < 2) then
      ! No arguments: print all readonly variables
      print_mode = .true.
    end if

    if (print_mode) then
      ! Print all readonly variables
      do i = 1, shell%num_variables
        if (shell%variables(i)%readonly .and. len_trim(shell%variables(i)%name) > 0) then
          write(output_unit, '(a)') 'readonly ' // trim(shell%variables(i)%name) // '=' // &
                                   trim(shell%variables(i)%value)
        end if
      end do
      shell%last_exit_status = 0
      return
    end if

    ! Process each argument
    do arg_idx = 2, cmd%num_tokens
      eq_pos = index(cmd%tokens(arg_idx), '=')

      if (eq_pos > 0) then
        ! VAR=value form - set and mark readonly
        var_name = cmd%tokens(arg_idx)(:eq_pos-1)
        var_value = cmd%tokens(arg_idx)(eq_pos+1:)

        ! Check if variable already exists and is readonly
        found = .false.
        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == trim(var_name)) then
            if (shell%variables(j)%readonly) then
              write(error_unit, '(a)') trim(var_name) // ': readonly variable'
              shell%last_exit_status = 1
              return
            end if
            found = .true.
            exit
          end if
        end do

        ! Set the variable
        call set_shell_variable(shell, trim(var_name), trim(var_value))

        ! Mark as readonly
        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == trim(var_name)) then
            shell%variables(j)%readonly = .true.
            exit
          end if
        end do
      else
        ! Just VAR - mark existing variable as readonly
        var_name = trim(cmd%tokens(arg_idx))
        found = .false.

        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == var_name) then
            if (shell%variables(j)%readonly) then
              write(error_unit, '(a)') trim(var_name) // ': readonly variable'
              shell%last_exit_status = 1
              return
            end if
            shell%variables(j)%readonly = .true.
            found = .true.
            exit
          end if
        end do

        if (.not. found) then
          ! Variable doesn't exist, create it with empty value and mark readonly
          call set_shell_variable(shell, var_name, '')
          do j = 1, shell%num_variables
            if (trim(shell%variables(j)%name) == var_name) then
              shell%variables(j)%readonly = .true.
              exit
            end if
          end do
        end if
      end if
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_local(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, eq_pos, depth, var_index
    character(len=256) :: var_name, var_value

    ! Check if we're inside a function
    if (shell%function_depth == 0) then
      write(error_unit, '(a)') 'local: can only be used in a function'
      shell%last_exit_status = 1
      return
    end if

    ! Check depth is within bounds
    depth = shell%function_depth
    if (depth > size(shell%local_var_counts)) then
      write(error_unit, '(a)') 'local: function nesting too deep'
      shell%last_exit_status = 1
      return
    end if

    ! Process each variable assignment
    do i = 2, cmd%num_tokens
      eq_pos = index(cmd%tokens(i), '=')

      if (eq_pos > 0) then
        ! Variable assignment: local var=value
        var_name = cmd%tokens(i)(:eq_pos-1)
        var_value = cmd%tokens(i)(eq_pos+1:)

        ! Find or create local variable slot
        var_index = shell%local_var_counts(depth) + 1
        if (var_index > size(shell%local_vars, 2)) then
          write(error_unit, '(a)') 'local: too many local variables'
          shell%last_exit_status = 1
          return
        end if

        ! Store local variable
        shell%local_vars(depth, var_index)%name = var_name
        shell%local_vars(depth, var_index)%value = var_value
        shell%local_vars(depth, var_index)%readonly = .false.
        shell%local_vars(depth, var_index)%exported = .false.
        shell%local_var_counts(depth) = var_index
      else
        ! Just declare local: local var (unset or empty)
        var_name = trim(cmd%tokens(i))

        var_index = shell%local_var_counts(depth) + 1
        if (var_index > size(shell%local_vars, 2)) then
          write(error_unit, '(a)') 'local: too many local variables'
          shell%last_exit_status = 1
          return
        end if

        shell%local_vars(depth, var_index)%name = var_name
        shell%local_vars(depth, var_index)%value = ''
        shell%local_vars(depth, var_index)%readonly = .false.
        shell%local_vars(depth, var_index)%exported = .false.
        shell%local_var_counts(depth) = var_index
      end if
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_shift(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: shift_count, iostat
    
    shift_count = 1  ! Default shift by 1
    
    if (cmd%num_tokens > 1) then
      ! Parse shift count from argument
      read(cmd%tokens(2), *, iostat=iostat) shift_count
      if (iostat /= 0) then
        write(error_unit, '(a)') 'shift: numeric argument required'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    if (shift_count < 0) then
      write(error_unit, '(a)') 'shift: shift count out of range'
      shell%last_exit_status = 1
      return
    end if
    
    if (shift_count > shell%num_positional) then
      write(error_unit, '(a)') 'shift: shift count out of range'
      shell%last_exit_status = 1
      return
    end if
    
    call shift_positional_params(shell, shift_count)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_break(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: break_count, i, iostat

    ! Default to breaking 1 level
    break_count = 1

    ! Parse optional numeric argument
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=iostat) break_count
      if (iostat /= 0) then
        write(error_unit, '(a)') 'break: invalid number'
        shell%last_exit_status = 1
        return
      end if
      if (break_count < 1) then
        write(error_unit, '(a)') 'break: count must be >= 1'
        shell%last_exit_status = 1
        return
      end if
    end if

    ! Find the nearest loop and set break flag
    do i = shell%control_depth, 1, -1
      if (shell%control_stack(i)%block_type == BLOCK_FOR .or. &
          shell%control_stack(i)%block_type == BLOCK_WHILE .or. &
          shell%control_stack(i)%block_type == BLOCK_FOR_ARITH) then
        shell%control_stack(i)%break_requested = .true.
        shell%control_stack(i)%break_level = break_count
        shell%last_exit_status = 0
        return
      end if
    end do

    ! No loop found
    write(error_unit, '(a)') 'break: not in a loop'
    shell%last_exit_status = 1
  end subroutine

  subroutine builtin_continue(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: continue_count, i, iostat

    ! Default to continuing 1 level
    continue_count = 1

    ! Parse optional numeric argument
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=iostat) continue_count
      if (iostat /= 0) then
        write(error_unit, '(a)') 'continue: invalid number'
        shell%last_exit_status = 1
        return
      end if
      if (continue_count < 1) then
        write(error_unit, '(a)') 'continue: count must be >= 1'
        shell%last_exit_status = 1
        return
      end if
    end if

    ! Find the nearest loop and set continue flag
    do i = shell%control_depth, 1, -1
      if (shell%control_stack(i)%block_type == BLOCK_FOR .or. &
          shell%control_stack(i)%block_type == BLOCK_WHILE .or. &
          shell%control_stack(i)%block_type == BLOCK_FOR_ARITH) then
        shell%control_stack(i)%continue_requested = .true.
        shell%control_stack(i)%continue_level = continue_count
        shell%last_exit_status = 0
        return
      end if
    end do

    ! No loop found
    write(error_unit, '(a)') 'continue: not in a loop'
    shell%last_exit_status = 1
  end subroutine

  subroutine builtin_return(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: return_code, iostat

    ! Default to last command's exit status
    return_code = shell%last_exit_status

    ! Parse optional return value argument
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=iostat) return_code
      if (iostat /= 0) then
        write(error_unit, '(a)') 'return: numeric argument required'
        shell%last_exit_status = 2
        return
      end if
    end if

    ! Set the return value and flag to exit function
    shell%function_return_value = return_code
    shell%last_exit_status = return_code
    shell%function_return_pending = .true.
  end subroutine

  subroutine builtin_exec(cmd, shell)
    use command_builtin, only: find_command_full_path
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=256), target :: c_prog_name
    character(len=256), target, allocatable :: c_args(:)
    type(c_ptr), allocatable, target :: argv(:)
    integer :: i, ret
    character(len=MAX_PATH_LEN) :: prog_path

    ! exec without arguments is an error (could be used for redirections in future)
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'exec: usage: exec command [arguments ...]'
      shell%last_exit_status = 2
      return
    end if

    ! Get the command name
    c_prog_name = trim(cmd%tokens(2)) // c_null_char

    ! Find full path for the command (if it's not an absolute/relative path)
    if (index(cmd%tokens(2), '/') == 0) then
      prog_path = find_command_full_path(trim(cmd%tokens(2)))
      if (len_trim(prog_path) == 0) then
        write(error_unit, '(a)') 'exec: ' // trim(cmd%tokens(2)) // ': command not found'
        shell%last_exit_status = 127
        return
      end if
      c_prog_name = trim(prog_path) // c_null_char
    end if

    ! Build argv array for execvp (NULL-terminated array of C string pointers)
    ! argv[0] is the program name, argv[1..n-1] are arguments, argv[n] is NULL
    allocate(c_args(cmd%num_tokens - 1))
    allocate(argv(cmd%num_tokens))

    ! First argument is program name
    c_args(1) = trim(cmd%tokens(2)) // c_null_char
    argv(1) = c_loc(c_args(1))

    ! Copy remaining arguments
    do i = 3, cmd%num_tokens
      c_args(i - 1) = trim(cmd%tokens(i)) // c_null_char
      argv(i - 1) = c_loc(c_args(i - 1))
    end do

    ! NULL-terminate the argv array
    argv(cmd%num_tokens) = c_null_ptr

    ! Replace the current process with the new command
    ! If execvp succeeds, this function never returns
    ret = c_execvp(c_loc(c_prog_name), c_loc(argv))

    ! If we reach here, execvp failed
    ! Clean up allocations
    deallocate(c_args)
    deallocate(argv)

    ! Report error
    write(error_unit, '(a)') 'exec: ' // trim(cmd%tokens(2)) // ': cannot execute'
    shell%last_exit_status = 126
  end subroutine

  subroutine builtin_hash(cmd, shell)
    use command_builtin, only: find_command_full_path
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=256) :: cmd_name, pathname
    integer :: i, j
    logical :: remove_mode, list_mode, path_mode, delete_mode
    character(len=MAX_PATH_LEN) :: found_path

    remove_mode = .false.
    list_mode = .false.
    path_mode = .false.
    delete_mode = .false.

    ! Parse options
    if (cmd%num_tokens > 1) then
      if (trim(cmd%tokens(2)) == '-r') then
        ! Clear hash table
        shell%num_hashed_commands = 0
        do i = 1, size(shell%command_hash)
          shell%command_hash(i)%command_name = ''
          shell%command_hash(i)%full_path = ''
          shell%command_hash(i)%hits = 0
        end do
        shell%last_exit_status = 0
        return
      else if (trim(cmd%tokens(2)) == '-l') then
        list_mode = .true.
      else if (trim(cmd%tokens(2)) == '-d') then
        delete_mode = .true.
        if (cmd%num_tokens < 3) then
          write(error_unit, '(a)') 'hash: -d requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (trim(cmd%tokens(2)) == '-p') then
        path_mode = .true.
        if (cmd%num_tokens < 4) then
          write(error_unit, '(a)') 'hash: usage: hash -p pathname name'
          shell%last_exit_status = 1
          return
        end if
      end if
    end if

    ! hash with no arguments - display hash table
    if (cmd%num_tokens == 1) then
      if (shell%num_hashed_commands == 0) then
        shell%last_exit_status = 0
        return
      end if
      write(output_unit, '(a)') 'hits    command'
      do i = 1, shell%num_hashed_commands
        if (len_trim(shell%command_hash(i)%command_name) > 0) then
          write(output_unit, '(i4,4x,a)') shell%command_hash(i)%hits, &
            trim(shell%command_hash(i)%full_path)
        end if
      end do
      shell%last_exit_status = 0
      return
    end if

    ! hash -l - list format
    if (list_mode) then
      do i = 1, shell%num_hashed_commands
        if (len_trim(shell%command_hash(i)%command_name) > 0) then
          write(output_unit, '(a)') 'builtin hash -p ' // &
            trim(shell%command_hash(i)%full_path) // ' ' // &
            trim(shell%command_hash(i)%command_name)
        end if
      end do
      shell%last_exit_status = 0
      return
    end if

    ! hash -d name - delete specific command
    if (delete_mode) then
      cmd_name = trim(cmd%tokens(3))
      do i = 1, shell%num_hashed_commands
        if (trim(shell%command_hash(i)%command_name) == cmd_name) then
          ! Remove this entry by shifting others down
          do j = i, shell%num_hashed_commands - 1
            shell%command_hash(j) = shell%command_hash(j + 1)
          end do
          shell%command_hash(shell%num_hashed_commands)%command_name = ''
          shell%command_hash(shell%num_hashed_commands)%full_path = ''
          shell%command_hash(shell%num_hashed_commands)%hits = 0
          shell%num_hashed_commands = shell%num_hashed_commands - 1
          shell%last_exit_status = 0
          return
        end if
      end do
      write(error_unit, '(a)') 'hash: ' // trim(cmd_name) // ': not found'
      shell%last_exit_status = 1
      return
    end if

    ! hash -p pathname name - add with explicit path
    if (path_mode) then
      pathname = trim(cmd%tokens(3))
      cmd_name = trim(cmd%tokens(4))

      ! Check if command already exists
      do i = 1, shell%num_hashed_commands
        if (trim(shell%command_hash(i)%command_name) == cmd_name) then
          shell%command_hash(i)%full_path = pathname
          shell%last_exit_status = 0
          return
        end if
      end do

      ! Add new entry
      if (shell%num_hashed_commands < size(shell%command_hash)) then
        shell%num_hashed_commands = shell%num_hashed_commands + 1
        shell%command_hash(shell%num_hashed_commands)%command_name = cmd_name
        shell%command_hash(shell%num_hashed_commands)%full_path = pathname
        shell%command_hash(shell%num_hashed_commands)%hits = 0
        shell%last_exit_status = 0
      else
        write(error_unit, '(a)') 'hash: hash table full'
        shell%last_exit_status = 1
      end if
      return
    end if

    ! hash name [name...] - add commands to hash table
    do i = 2, cmd%num_tokens
      cmd_name = trim(cmd%tokens(i))

      ! Search PATH for command
      found_path = find_command_full_path(cmd_name)
      if (len_trim(found_path) == 0) then
        write(error_unit, '(a)') 'hash: ' // trim(cmd_name) // ': not found'
        shell%last_exit_status = 1
        cycle
      end if

      ! Check if command already exists
      do j = 1, shell%num_hashed_commands
        if (trim(shell%command_hash(j)%command_name) == cmd_name) then
          shell%command_hash(j)%full_path = found_path
          shell%last_exit_status = 0
          goto 100  ! Skip to next command
        end if
      end do

      ! Add new entry
      if (shell%num_hashed_commands < size(shell%command_hash)) then
        shell%num_hashed_commands = shell%num_hashed_commands + 1
        shell%command_hash(shell%num_hashed_commands)%command_name = cmd_name
        shell%command_hash(shell%num_hashed_commands)%full_path = found_path
        shell%command_hash(shell%num_hashed_commands)%hits = 0
      else
        write(error_unit, '(a)') 'hash: hash table full'
        shell%last_exit_status = 1
      end if

100   continue
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_umask(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer(c_int) :: current_mask, new_mask, temp_mask
    integer :: new_mask_int, iostat
    logical :: symbolic_mode, print_mode
    character(len=16) :: mask_str

    symbolic_mode = .false.
    print_mode = .false.

    ! Parse options
    if (cmd%num_tokens > 1) then
      if (trim(cmd%tokens(2)) == '-S') then
        symbolic_mode = .true.
      else if (trim(cmd%tokens(2)) == '-p') then
        print_mode = .true.
      else if (cmd%tokens(2)(1:1) == '-') then
        write(error_unit, '(a)') 'umask: invalid option: ' // trim(cmd%tokens(2))
        shell%last_exit_status = 1
        return
      end if
    end if

    ! Get current umask (set to 0 temporarily, then restore)
    current_mask = c_umask(0_c_int)  ! Save the current mask
    temp_mask = c_umask(current_mask) ! Restore it

    ! If no value specified, display current mask
    if (cmd%num_tokens == 1 .or. symbolic_mode .or. print_mode) then
      if (symbolic_mode) then
        ! Display in symbolic form: u=rwx,g=rx,o=rx
        call print_umask_symbolic(current_mask)
      else if (print_mode) then
        ! Display in a form that can be reused as input
        write(mask_str, '(o4.4)') current_mask
        write(output_unit, '(a)') 'umask ' // trim(adjustl(mask_str))
      else
        ! Display in octal (default)
        write(mask_str, '(o4.4)') current_mask
        write(output_unit, '(a)') trim(adjustl(mask_str))
      end if
      shell%last_exit_status = 0
      return
    end if

    ! Set new mask
    ! Determine starting index for mask value (skip -S or -p if present)
    if (trim(cmd%tokens(2)) == '-S' .or. trim(cmd%tokens(2)) == '-p') then
      if (cmd%num_tokens < 3) then
        write(error_unit, '(a)') 'umask: usage: umask [-p] [-S] [mode]'
        shell%last_exit_status = 1
        return
      end if
      mask_str = trim(cmd%tokens(3))
    else
      mask_str = trim(cmd%tokens(2))
    end if

    ! Parse octal mask value
    read(mask_str, '(o10)', iostat=iostat) new_mask_int
    if (iostat /= 0) then
      write(error_unit, '(a)') 'umask: invalid mode: ' // trim(mask_str)
      shell%last_exit_status = 1
      return
    end if

    ! Validate mask (should be 0-0777)
    if (new_mask_int < 0 .or. new_mask_int > int(o'0777')) then
      write(error_unit, '(a)') 'umask: octal number out of range'
      shell%last_exit_status = 1
      return
    end if

    ! Set the new mask
    new_mask = int(new_mask_int, c_int)
    temp_mask = c_umask(new_mask)

    shell%last_exit_status = 0
  end subroutine

  subroutine print_umask_symbolic(mask)
    integer(c_int), intent(in) :: mask
    character(len=9) :: perm_str
    integer :: u_perm, g_perm, o_perm

    ! Extract permissions for user, group, and others
    ! umask inverts permissions, so we need to flip bits
    u_perm = iand(ishft(not(mask), -6), 7)  ! User permissions
    g_perm = iand(ishft(not(mask), -3), 7)  ! Group permissions
    o_perm = iand(not(mask), 7)             ! Other permissions

    ! Build symbolic string
    perm_str = 'u='
    if (iand(u_perm, 4) /= 0) perm_str = trim(perm_str) // 'r'
    if (iand(u_perm, 2) /= 0) perm_str = trim(perm_str) // 'w'
    if (iand(u_perm, 1) /= 0) perm_str = trim(perm_str) // 'x'

    perm_str = trim(perm_str) // ',g='
    if (iand(g_perm, 4) /= 0) perm_str = trim(perm_str) // 'r'
    if (iand(g_perm, 2) /= 0) perm_str = trim(perm_str) // 'w'
    if (iand(g_perm, 1) /= 0) perm_str = trim(perm_str) // 'x'

    perm_str = trim(perm_str) // ',o='
    if (iand(o_perm, 4) /= 0) perm_str = trim(perm_str) // 'r'
    if (iand(o_perm, 2) /= 0) perm_str = trim(perm_str) // 'w'
    if (iand(o_perm, 1) /= 0) perm_str = trim(perm_str) // 'x'

    write(output_unit, '(a)') trim(perm_str)
  end subroutine

  subroutine builtin_ulimit(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    type(rlimit_t) :: rlim
    integer :: i, ret, resource
    character(len=256) :: arg, value_str
    logical :: show_all, set_hard, set_soft, setting_value
    integer(c_long) :: new_limit
    character(len=20) :: limit_name

    ! Default: query soft limit for file size
    resource = RLIMIT_FSIZE
    show_all = .false.
    set_hard = .false.
    set_soft = .true.  ! Default to soft limit
    setting_value = .false.
    limit_name = 'file size'

    ! Parse options
    i = 2
    do while (i <= cmd%num_tokens)
      arg = trim(cmd%tokens(i))

      if (arg == '-a') then
        show_all = .true.
        i = i + 1
      else if (arg == '-H') then
        set_hard = .true.
        set_soft = .false.
        i = i + 1
      else if (arg == '-S') then
        set_soft = .true.
        set_hard = .false.
        i = i + 1
      else if (arg == '-c') then
        resource = RLIMIT_CORE
        limit_name = 'core file size'
        i = i + 1
      else if (arg == '-d') then
        resource = RLIMIT_DATA
        limit_name = 'data seg size'
        i = i + 1
      else if (arg == '-f') then
        resource = RLIMIT_FSIZE
        limit_name = 'file size'
        i = i + 1
      else if (arg == '-l') then
        resource = RLIMIT_MEMLOCK
        limit_name = 'max locked memory'
        i = i + 1
      else if (arg == '-m') then
        resource = RLIMIT_RSS
        limit_name = 'max memory size'
        i = i + 1
      else if (arg == '-n') then
        resource = RLIMIT_NOFILE
        limit_name = 'open files'
        i = i + 1
      else if (arg == '-s') then
        resource = RLIMIT_STACK
        limit_name = 'stack size'
        i = i + 1
      else if (arg == '-t') then
        resource = RLIMIT_CPU
        limit_name = 'cpu time'
        i = i + 1
      else if (arg == '-u') then
        resource = RLIMIT_NPROC
        limit_name = 'max user processes'
        i = i + 1
      else if (arg == '-v') then
        resource = RLIMIT_AS
        limit_name = 'virtual memory'
        i = i + 1
      else
        ! This is the value to set
        value_str = arg
        setting_value = .true.
        exit
      end if
    end do

    ! Display all limits if -a was specified
    if (show_all) then
      call display_all_limits(shell)
      return
    end if

    ! Get current limit
    ret = c_getrlimit(resource, rlim)
    if (ret /= 0) then
      write(error_unit, '(a)') 'ulimit: failed to get resource limit'
      shell%last_exit_status = 1
      return
    end if

    ! If setting a new value
    if (setting_value) then
      ! Parse the new limit value
      if (trim(value_str) == 'unlimited') then
        new_limit = RLIM_INFINITY
      else
        read(value_str, *, iostat=ret) new_limit
        if (ret /= 0) then
          write(error_unit, '(a)') 'ulimit: invalid number: ' // trim(value_str)
          shell%last_exit_status = 1
          return
        end if

        ! Convert based on resource type (some are in KB)
        if (resource == RLIMIT_FSIZE .or. resource == RLIMIT_CORE .or. &
            resource == RLIMIT_DATA .or. resource == RLIMIT_STACK .or. &
            resource == RLIMIT_RSS .or. resource == RLIMIT_MEMLOCK .or. &
            resource == RLIMIT_AS) then
          new_limit = new_limit * 1024  ! Convert KB to bytes
        end if
      end if

      ! Set the new limit
      if (set_hard) then
        rlim%rlim_max = new_limit
      else
        rlim%rlim_cur = new_limit
      end if

      ret = c_setrlimit(resource, rlim)
      if (ret /= 0) then
        write(error_unit, '(a)') 'ulimit: failed to set resource limit'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Display current limit
      if (set_hard) then
        call display_limit(rlim%rlim_max, resource)
      else
        call display_limit(rlim%rlim_cur, resource)
      end if
    end if

    shell%last_exit_status = 0

  contains

    subroutine display_limit(limit_value, res)
      integer(c_long), intent(in) :: limit_value
      integer(c_int), intent(in) :: res
      integer(c_long) :: display_value

      if (limit_value == RLIM_INFINITY .or. limit_value < 0) then
        write(output_unit, '(a)') 'unlimited'
      else
        ! Convert bytes to KB for display
        if (res == RLIMIT_FSIZE .or. res == RLIMIT_CORE .or. &
            res == RLIMIT_DATA .or. res == RLIMIT_STACK .or. &
            res == RLIMIT_RSS .or. res == RLIMIT_MEMLOCK .or. &
            res == RLIMIT_AS) then
          display_value = limit_value / 1024
        else
          display_value = limit_value
        end if
        write(output_unit, '(i0)') display_value
      end if
    end subroutine

    subroutine display_all_limits(sh)
      type(shell_state_t), intent(inout) :: sh
      type(rlimit_t) :: r
      integer :: res_ret

      write(output_unit, '(a)') 'core file size          (blocks, -c) ' // get_limit_str(RLIMIT_CORE)
      write(output_unit, '(a)') 'data seg size           (kbytes, -d) ' // get_limit_str(RLIMIT_DATA)
      write(output_unit, '(a)') 'file size               (blocks, -f) ' // get_limit_str(RLIMIT_FSIZE)
      write(output_unit, '(a)') 'max locked memory       (kbytes, -l) ' // get_limit_str(RLIMIT_MEMLOCK)
      write(output_unit, '(a)') 'max memory size         (kbytes, -m) ' // get_limit_str(RLIMIT_RSS)
      write(output_unit, '(a)') 'open files                      (-n) ' // get_limit_str(RLIMIT_NOFILE)
      write(output_unit, '(a)') 'stack size              (kbytes, -s) ' // get_limit_str(RLIMIT_STACK)
      write(output_unit, '(a)') 'cpu time                (seconds,-t) ' // get_limit_str(RLIMIT_CPU)
      write(output_unit, '(a)') 'max user processes              (-u) ' // get_limit_str(RLIMIT_NPROC)
      write(output_unit, '(a)') 'virtual memory          (kbytes, -v) ' // get_limit_str(RLIMIT_AS)

      sh%last_exit_status = 0
    end subroutine

    function get_limit_str(res) result(str)
      integer(c_int), intent(in) :: res
      character(len=20) :: str
      type(rlimit_t) :: r
      integer :: res_ret
      integer(c_long) :: val

      res_ret = c_getrlimit(res, r)
      if (res_ret /= 0) then
        str = 'error'
        return
      end if

      if (r%rlim_cur == RLIM_INFINITY .or. r%rlim_cur < 0) then
        str = 'unlimited'
      else
        ! Convert to appropriate units
        if (res == RLIMIT_FSIZE .or. res == RLIMIT_CORE .or. &
            res == RLIMIT_DATA .or. res == RLIMIT_STACK .or. &
            res == RLIMIT_RSS .or. res == RLIMIT_MEMLOCK .or. &
            res == RLIMIT_AS) then
          val = r%rlim_cur / 1024
        else
          val = r%rlim_cur
        end if
        write(str, '(i0)') val
      end if
    end function

  end subroutine

  subroutine builtin_times(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    type(rusage_t) :: self_usage, children_usage
    integer :: ret
    real :: self_user_sec, self_sys_sec, children_user_sec, children_sys_sec
    integer :: self_user_min, self_sys_min, children_user_min, children_sys_min

    ! Get resource usage for the shell itself
    ret = c_getrusage(RUSAGE_SELF, self_usage)
    if (ret /= 0) then
      write(error_unit, '(a)') 'times: failed to get resource usage'
      shell%last_exit_status = 1
      return
    end if

    ! Get resource usage for all children
    ret = c_getrusage(RUSAGE_CHILDREN, children_usage)
    if (ret /= 0) then
      write(error_unit, '(a)') 'times: failed to get child resource usage'
      shell%last_exit_status = 1
      return
    end if

    ! Convert timeval structures to seconds (tv_sec + tv_usec/1000000)
    self_user_sec = real(self_usage%ru_utime%tv_sec) + real(self_usage%ru_utime%tv_usec) / 1000000.0
    self_sys_sec = real(self_usage%ru_stime%tv_sec) + real(self_usage%ru_stime%tv_usec) / 1000000.0
    children_user_sec = real(children_usage%ru_utime%tv_sec) + real(children_usage%ru_utime%tv_usec) / 1000000.0
    children_sys_sec = real(children_usage%ru_stime%tv_sec) + real(children_usage%ru_stime%tv_usec) / 1000000.0

    ! Extract minutes and seconds
    self_user_min = int(self_user_sec / 60.0)
    self_user_sec = self_user_sec - (self_user_min * 60.0)
    self_sys_min = int(self_sys_sec / 60.0)
    self_sys_sec = self_sys_sec - (self_sys_min * 60.0)
    children_user_min = int(children_user_sec / 60.0)
    children_user_sec = children_user_sec - (children_user_min * 60.0)
    children_sys_min = int(children_sys_sec / 60.0)
    children_sys_sec = children_sys_sec - (children_sys_min * 60.0)

    ! Print in bash format: user_time system_time (one line for shell, one for children)
    write(output_unit, '(i0,a,f5.3,a,1x,i0,a,f5.3,a)') &
      self_user_min, 'm', self_user_sec, 's', &
      self_sys_min, 'm', self_sys_sec, 's'
    write(output_unit, '(i0,a,f5.3,a,1x,i0,a,f5.3,a)') &
      children_user_min, 'm', children_user_sec, 's', &
      children_sys_min, 'm', children_sys_sec, 's'

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_let(cmd, shell)
    use expansion, only: arithmetic_expansion_shell
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, iostat
    character(len=1024) :: expr, arith_expr, result_str
    integer(kind=8) :: result_val

    ! Default to success
    shell%last_exit_status = 0

    ! Process each argument as an arithmetic expression
    do i = 2, cmd%num_tokens
      ! Build arithmetic expression - remove quotes if present
      expr = trim(cmd%tokens(i))
      if (len_trim(expr) > 0) then
        if (expr(1:1) == '"' .and. expr(len_trim(expr):len_trim(expr)) == '"') then
          expr = expr(2:len_trim(expr)-1)
        else if (expr(1:1) == "'" .and. expr(len_trim(expr):len_trim(expr)) == "'") then
          expr = expr(2:len_trim(expr)-1)
        end if
      end if

      ! Evaluate as $((expression))
      arith_expr = '$((' // trim(expr) // '))'
      result_str = arithmetic_expansion_shell(trim(arith_expr), shell)

      ! Convert to integer to check result
      read(result_str, *, iostat=iostat) result_val
      if (iostat /= 0) result_val = 0

      ! Set exit status based on last expression result
      ! Exit status 0 if non-zero, 1 if zero
      if (result_val /= 0) then
        shell%last_exit_status = 0
      else
        shell%last_exit_status = 1
      end if
    end do
  end subroutine

  subroutine builtin_declare(cmd, shell)
    use variables, only: set_shell_variable, declare_associative_array
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos, i, j, arg_idx
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    logical :: readonly_flag, export_flag, print_mode, print_funcs
    logical :: array_flag, assoc_array_flag, found

    readonly_flag = .false.
    export_flag = .false.
    print_mode = .false.
    print_funcs = .false.
    array_flag = .false.
    assoc_array_flag = .false.

    if (cmd%num_tokens < 2) then
      ! No arguments: print all variables
      print_mode = .true.
    end if

    ! Parse options
    arg_idx = 2
    do while (arg_idx <= cmd%num_tokens)
      if (cmd%tokens(arg_idx)(1:1) == '-') then
        select case (trim(cmd%tokens(arg_idx)))
          case ('-r')
            readonly_flag = .true.
          case ('-x')
            export_flag = .true.
          case ('-p')
            print_mode = .true.
          case ('-f')
            print_funcs = .true.
            print_mode = .true.
          case ('-a')
            array_flag = .true.
          case ('-A')
            assoc_array_flag = .true.
          case default
            write(error_unit, '(a)') 'declare: invalid option: ' // trim(cmd%tokens(arg_idx))
            shell%last_exit_status = 1
            return
        end select
        arg_idx = arg_idx + 1
      else
        exit
      end if
    end do

    if (print_mode) then
      ! Print functions if -f flag is set
      if (print_funcs) then
        do i = 1, shell%num_functions
          if (len_trim(shell%functions(i)%name) > 0 .and. shell%functions(i)%body_lines > 0) then
            write(output_unit, '(a)') trim(shell%functions(i)%name) // ' ()'
            write(output_unit, '(a)') '{'
            if (allocated(shell%functions(i)%body)) then
              do j = 1, shell%functions(i)%body_lines
                write(output_unit, '(a)') '    ' // trim(shell%functions(i)%body(j))
              end do
            end if
            write(output_unit, '(a)') '}'
          end if
        end do
        shell%last_exit_status = 0
        return
      end if

      ! Print all variables with declare syntax
      do i = 1, shell%num_variables
        if (len_trim(shell%variables(i)%name) > 0) then
          if (shell%variables(i)%readonly .and. shell%variables(i)%exported) then
            write(output_unit, '(a)') 'declare -rx ' // trim(shell%variables(i)%name) // '=' // &
                                     trim(shell%variables(i)%value)
          else if (shell%variables(i)%readonly) then
            write(output_unit, '(a)') 'declare -r ' // trim(shell%variables(i)%name) // '=' // &
                                     trim(shell%variables(i)%value)
          else if (shell%variables(i)%exported) then
            write(output_unit, '(a)') 'declare -x ' // trim(shell%variables(i)%name) // '=' // &
                                     trim(shell%variables(i)%value)
          else
            write(output_unit, '(a)') 'declare -- ' // trim(shell%variables(i)%name) // '=' // &
                                     trim(shell%variables(i)%value)
          end if
        end if
      end do
      shell%last_exit_status = 0
      return
    end if

    ! Process variable assignments
    do while (arg_idx <= cmd%num_tokens)
      eq_pos = index(cmd%tokens(arg_idx), '=')

      if (eq_pos > 0) then
        ! VAR=value form
        var_name = cmd%tokens(arg_idx)(:eq_pos-1)
        var_value = cmd%tokens(arg_idx)(eq_pos+1:)

        ! Check if variable already exists and is readonly
        found = .false.
        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == trim(var_name)) then
            if (shell%variables(j)%readonly .and. .not. readonly_flag) then
              write(error_unit, '(a)') trim(var_name) // ': readonly variable'
              shell%last_exit_status = 1
              return
            end if
            found = .true.
            exit
          end if
        end do

        ! Set the variable
        call set_shell_variable(shell, trim(var_name), trim(var_value))

        ! Apply attributes
        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == trim(var_name)) then
            if (readonly_flag) shell%variables(j)%readonly = .true.
            if (export_flag) then
              shell%variables(j)%exported = .true.
              if (.not. set_environment_var(trim(var_name), trim(var_value))) then
                write(error_unit, '(a)') 'declare: failed to export variable'
                shell%last_exit_status = 1
                return
              end if
            end if
            exit
          end if
        end do
      else
        ! Just VAR - declare variable or apply attributes
        var_name = trim(cmd%tokens(arg_idx))
        found = .false.

        ! Handle array declarations
        if (assoc_array_flag) then
          ! declare -A arrayname
          call declare_associative_array(shell, var_name)
          arg_idx = arg_idx + 1
          cycle
        else if (array_flag) then
          ! declare -a arrayname
          ! Create an empty indexed array
          call set_shell_variable(shell, var_name, '')
          do j = 1, shell%num_variables
            if (trim(shell%variables(j)%name) == var_name) then
              shell%variables(j)%is_array = .true.
              exit
            end if
          end do
          arg_idx = arg_idx + 1
          cycle
        end if

        do j = 1, shell%num_variables
          if (trim(shell%variables(j)%name) == var_name) then
            if (readonly_flag) shell%variables(j)%readonly = .true.
            if (export_flag) then
              shell%variables(j)%exported = .true.
              if (.not. set_environment_var(var_name, trim(shell%variables(j)%value))) then
                write(error_unit, '(a)') 'declare: failed to export variable'
                shell%last_exit_status = 1
                return
              end if
            end if
            found = .true.
            exit
          end if
        end do

        if (.not. found) then
          ! Variable doesn't exist, create it with empty value
          call set_shell_variable(shell, var_name, '')
          do j = 1, shell%num_variables
            if (trim(shell%variables(j)%name) == var_name) then
              if (readonly_flag) shell%variables(j)%readonly = .true.
              if (export_flag) then
                shell%variables(j)%exported = .true.
                if (.not. set_environment_var(var_name, '')) then
                  write(error_unit, '(a)') 'declare: failed to export variable'
                  shell%last_exit_status = 1
                  return
                end if
              end if
              exit
            end if
          end do
        end if
      end if

      arg_idx = arg_idx + 1
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_printenv(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    character(len=:), allocatable :: env_value

    if (cmd%num_tokens < 2) then
      ! No arguments: print all environment variables
      do i = 1, shell%num_variables
        if (shell%variables(i)%exported .and. len_trim(shell%variables(i)%name) > 0) then
          write(output_unit, '(a)') trim(shell%variables(i)%name) // '=' // &
                                   trim(shell%variables(i)%value)
        end if
      end do
      shell%last_exit_status = 0
    else
      ! Print specific environment variable(s)
      do i = 2, cmd%num_tokens
        env_value = get_environment_var(trim(cmd%tokens(i)))
        if (allocated(env_value) .and. len(env_value) > 0) then
          write(output_unit, '(a)') env_value
        else
          ! Variable not found - bash printenv doesn't error, just prints nothing
          continue
        end if
      end do
      shell%last_exit_status = 0
    end if
  end subroutine

end module builtins