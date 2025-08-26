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
  use performance
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
    case('test', '[', '[[')
      call execute_test_command(cmd, shell)
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
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'export: usage: export VAR=value'
      shell%last_exit_status = 1
      return
    end if
    
    eq_pos = index(cmd%tokens(2), '=')
    if (eq_pos > 0) then
      var_name = cmd%tokens(2)(:eq_pos-1)
      var_value = cmd%tokens(2)(eq_pos+1:)
      
      if (set_environment_var(trim(var_name), trim(var_value))) then
        shell%last_exit_status = 0
      else
        write(error_unit, '(a)') 'export: failed to set variable'
        shell%last_exit_status = 1
      end if
    else
      write(error_unit, '(a)') 'export: usage: export VAR=value'
      shell%last_exit_status = 1
    end if
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
    
    ! Simplified version - would need file reading implementation
    write(error_unit, '(a)') 'source: not yet implemented'
    shell%last_exit_status = 1
  end subroutine

  subroutine builtin_history(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    ! Handle history command options
    if (cmd%num_tokens > 1) then
      select case(trim(cmd%tokens(2)))
      case('-c', '--clear')
        call clear_history()
        write(output_unit, '(a)') 'Command history cleared.'
      case default
        write(error_unit, '(a)') 'history: unknown option'
        shell%last_exit_status = 1
        return
      end select
    else
      ! Show all history
      call show_history()
    end if
    
    shell%last_exit_status = 0
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
    
    ! Simplified trap implementation - in a full shell this would
    ! handle signal trap management
    if (cmd%num_tokens < 3) then
      write(error_unit, '(a)') 'trap: usage: trap action signal...'
      shell%last_exit_status = 1
      return
    end if
    
    ! For now, just acknowledge the trap command
    write(output_unit, '(a)') 'trap: signal trapping not yet fully implemented'
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
    write(output_unit, '(a)') '  help          - Show this help message'
    write(output_unit, '(a)') '  exit [code]   - Exit shell'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Features: Tab completion, command history, aliases, variables, job control'
    
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

end module builtins