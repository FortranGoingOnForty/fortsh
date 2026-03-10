! ==============================================================================
! Module: builtins (Extended with job control)
! ==============================================================================
module builtins
  use shell_types
  use system_interface
  use io_helpers
  use job_control
  use test_builtin
  use readline
  use shell_config
  use aliases
  use shell_options
  use command_builtin, only: find_command_in_path, builtin_which, builtin_command, find_executable_in_path, &
    cmd_builtin_type => builtin_type
  use directory_builtin, only: builtin_pushd, builtin_popd, builtin_dirs
  use performance
  use parser
  use coprocess
  use substitution
  use signal_handling
  use getopts_builtin
  use printf_builtin
  use read_builtin
  use iso_fortran_env, only: output_unit, error_unit
  use completion
  use iso_c_binding
  use builtin_interface
#ifdef USE_MEMORY_POOL
  use string_pool
  use memory_dashboard
#endif
  implicit none

  ! Module constant for dashboard tracking
#ifdef USE_MEMORY_POOL
  integer, parameter :: MOD_BUILTINS = 7  ! Module ID for dashboard
#endif

  ! C interface for system() call
  interface
    function c_system(command) bind(C, name="system")
      use iso_c_binding
      character(kind=c_char), intent(in) :: command(*)
      integer(c_int) :: c_system
    end function c_system
  end interface

contains

  ! Initialize builtin interface by registering function pointers
  subroutine init_builtins()
    is_builtin_ptr => is_builtin_impl
    execute_builtin_ptr => execute_builtin_impl
  end subroutine init_builtins

  function is_builtin_impl(cmd_name) result(is_built)
    character(len=*), intent(in) :: cmd_name
    logical :: is_built

    is_built = (trim(cmd_name) == 'exit' .or. &
                trim(cmd_name) == 'cd' .or. &
                trim(cmd_name) == 'pwd' .or. &
                trim(cmd_name) == 'pushd' .or. &
                trim(cmd_name) == 'popd' .or. &
                trim(cmd_name) == 'dirs' .or. &
                trim(cmd_name) == 'prevd' .or. &
                trim(cmd_name) == 'nextd' .or. &
                trim(cmd_name) == 'dirh' .or. &
                trim(cmd_name) == 'export' .or. &
                trim(cmd_name) == 'echo' .or. &
                trim(cmd_name) == 'jobs' .or. &
                trim(cmd_name) == 'fg' .or. &
                trim(cmd_name) == 'bg' .or. &
                trim(cmd_name) == 'source' .or. &
                trim(cmd_name) == '.' .or. &
                trim(cmd_name) == ':' .or. &
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
                trim(cmd_name) == 'which' .or. &
                trim(cmd_name) == 'command' .or. &
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
                trim(cmd_name) == 'fc' .or. &
                trim(cmd_name) == 'coproc' .or. &
                trim(cmd_name) == 'complete' .or. &
                trim(cmd_name) == 'compgen' .or. &
                is_test_command(cmd_name))
  end function

  subroutine execute_builtin_impl(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    select case(trim(cmd%tokens(1)))
    case('exit')
      call builtin_exit(cmd, shell)
    case('cd')
      call builtin_cd(cmd, shell)
    case('pwd')
      call builtin_pwd(cmd, shell)
    case('pushd')
      call builtin_pushd(cmd, shell)
    case('popd')
      call builtin_popd(cmd, shell)
    case('dirs')
      call builtin_dirs(cmd, shell)
    case('prevd')
      call builtin_prevd(cmd, shell)
    case('nextd')
      call builtin_nextd(cmd, shell)
    case('dirh')
      call builtin_dirh(cmd, shell)
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
    case(':')
      ! Colon builtin - null command, always returns success
      shell%last_exit_status = 0
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
    case('command')
      call builtin_command(cmd, shell)
    case('alias')
      call builtin_alias(cmd, shell)
    case('unalias')
      call builtin_unalias(cmd, shell)
    case('abbr')
      call builtin_abbr(cmd, shell)
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
      call cmd_builtin_type(cmd, shell)
    case('which')
      call builtin_which(cmd, shell)
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
    case('eval')
      call builtin_eval(cmd, shell)
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
    case('fc')
      call builtin_fc(cmd, shell)
    case('coproc')
      call builtin_coproc(cmd, shell)
    case('complete')
      call builtin_complete(cmd, shell)
    case('compgen')
      call builtin_compgen(cmd, shell)
    case default
      ! Should not reach here if is_builtin works correctly
      shell%last_exit_status = 1
    end select
  end subroutine

  subroutine builtin_exit(cmd, shell)
    use signal_handling, only: get_trap_command, is_trap_inherited
    use grammar_parser, only: parse_command_line
    use ast_executor, only: execute_ast_node
    use command_tree, only: command_node_t, destroy_command_node
    use executor, only: execute_pipeline
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: exit_code, iostat, i
    character(len=4096) :: trap_command
    type(pipeline_t) :: trap_pipeline
    type(command_node_t), pointer :: trap_ast
    integer :: saved_exit_status, trap_exit_code

    ! Execute EXIT trap before exiting (TRAP_EXIT = 0)
    ! Don't execute if we're already in a trap or if EXIT trap was already executed
    ! Don't execute inherited traps (visible in subshell but not executed)
    if (.not. shell%executing_trap .and. .not. shell%exit_trap_executed .and. &
        .not. is_trap_inherited(shell, 0)) then
      ! Get the trap command for EXIT signal (0)
      trap_command = get_trap_command(shell, 0)

      if (len_trim(trap_command) > 0) then
        ! Mark EXIT trap as executed
        shell%exit_trap_executed = .true.

        ! Save current exit status
        saved_exit_status = shell%last_exit_status

        ! Set flag to prevent recursive trap execution
        shell%executing_trap = .true.

        ! Parse and execute the trap command
        if (shell%use_new_parser) then
          trap_ast => parse_command_line(trim(trap_command))
          if (associated(trap_ast)) then
            trap_exit_code = execute_ast_node(trap_ast, shell)
            call destroy_command_node(trap_ast)
          end if
        else
          call parse_pipeline(trim(trap_command), trap_pipeline)
          if (.not. trap_pipeline%parse_error .and. trap_pipeline%num_commands > 0) then
            call execute_pipeline(trap_pipeline, shell, trim(trap_command))
          end if

          ! Clean up pipeline
          if (allocated(trap_pipeline%commands)) then
            do i = 1, trap_pipeline%num_commands
              if (allocated(trap_pipeline%commands(i)%tokens)) deallocate(trap_pipeline%commands(i)%tokens)
              if (allocated(trap_pipeline%commands(i)%input_file)) deallocate(trap_pipeline%commands(i)%input_file)
              if (allocated(trap_pipeline%commands(i)%output_file)) deallocate(trap_pipeline%commands(i)%output_file)
              if (allocated(trap_pipeline%commands(i)%error_file)) deallocate(trap_pipeline%commands(i)%error_file)
              if (allocated(trap_pipeline%commands(i)%heredoc_delimiter)) deallocate(trap_pipeline%commands(i)%heredoc_delimiter)
              if (allocated(trap_pipeline%commands(i)%heredoc_content)) deallocate(trap_pipeline%commands(i)%heredoc_content)
              if (allocated(trap_pipeline%commands(i)%here_string)) deallocate(trap_pipeline%commands(i)%here_string)
            end do
            deallocate(trap_pipeline%commands)
          end if
        end if

        ! Clear flag
        shell%executing_trap = .false.

        ! Restore exit status (trap shouldn't affect exit code)
        shell%last_exit_status = saved_exit_status
      end if
    end if

    shell%running = .false.
    if (cmd%num_tokens > 1) then
      ! Parse the exit code from the argument
      read(cmd%tokens(2), *, iostat=iostat) exit_code
      if (iostat == 0) then
        shell%last_exit_status = exit_code
      else
        ! Invalid exit code argument - treat as syntax error (exit 2)
        shell%last_exit_status = 2
      end if
    end if
  end subroutine

  subroutine builtin_cd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
#ifdef USE_MEMORY_POOL
    type(string_ref) :: target_dir_ref
    character(len=:), allocatable :: temp_str
#else
    character(len=:), allocatable :: target_dir
#endif
    character(len=MAX_PATH_LEN) :: old_cwd
    logical :: print_dir

    print_dir = .false.

    ! Save current directory for OLDPWD
    old_cwd = shell%cwd

#ifdef USE_MEMORY_POOL
    ! Get pooled buffer for target directory
    target_dir_ref = pool_get_string(MAX_PATH_LEN)
    call dashboard_track_allocation(MOD_BUILTINS, MAX_PATH_LEN, 4)
#endif

    if (cmd%num_tokens == 1) then
      ! cd with no arguments goes to HOME
#ifdef USE_MEMORY_POOL
      temp_str = get_environment_var('HOME')
      target_dir_ref%data = temp_str
      if (allocated(temp_str)) deallocate(temp_str)
#else
      target_dir = get_environment_var('HOME')
#endif
    else if (trim(cmd%tokens(2)) == '-') then
      ! cd - goes to OLDPWD and prints it
      if (len_trim(shell%oldpwd) == 0) then
        write(error_unit, '(a)') 'cd: OLDPWD not set'
        shell%last_exit_status = 1
#ifdef USE_MEMORY_POOL
        call pool_release_string(target_dir_ref)
        call dashboard_track_deallocation(MOD_BUILTINS, MAX_PATH_LEN, 4)
#endif
        return
      end if
#ifdef USE_MEMORY_POOL
      target_dir_ref%data = trim(shell%oldpwd)
#else
      target_dir = trim(shell%oldpwd)
#endif
      print_dir = .true.
    else
      ! Check if directory contains slash - if so, don't use CDPATH
      if (index(cmd%tokens(2), '/') == 0) then
        ! Try CDPATH directories
        block
          character(len=4096) :: cdpath, path_elem
          character(len=MAX_PATH_LEN) :: test_path
          integer :: start_pos, colon_pos
          logical :: found

          ! Check both shell variable and environment variable
          cdpath = get_shell_variable(shell, 'CDPATH')
          if (len_trim(cdpath) == 0) then
            cdpath = get_environment_var('CDPATH')
          end if
          found = .false.

          if (len_trim(cdpath) > 0) then
            start_pos = 1
            do while (start_pos <= len_trim(cdpath))
              colon_pos = index(cdpath(start_pos:), ':')
              if (colon_pos > 0) then
                path_elem = cdpath(start_pos:start_pos+colon_pos-2)
                start_pos = start_pos + colon_pos
              else
                path_elem = cdpath(start_pos:)
                start_pos = len_trim(cdpath) + 1
              end if

              ! Construct test path
              if (len_trim(path_elem) > 0) then
                test_path = trim(path_elem) // '/' // trim(cmd%tokens(2))
              else
                test_path = trim(cmd%tokens(2))
              end if

              ! Test if this path exists and is a directory
              if (test_is_directory(test_path)) then
#ifdef USE_MEMORY_POOL
                target_dir_ref%data = trim(test_path)
#else
                target_dir = trim(test_path)
#endif
                found = .true.
                print_dir = .true.  ! Print directory when using CDPATH
                exit
              end if
            end do
          end if

          if (.not. found) then
            ! CDPATH didn't find it, use original argument
#ifdef USE_MEMORY_POOL
            target_dir_ref%data = trim(cmd%tokens(2))
#else
            target_dir = trim(cmd%tokens(2))
#endif
          end if
        end block
      else
        ! Contains slash - use as-is
#ifdef USE_MEMORY_POOL
        target_dir_ref%data = trim(cmd%tokens(2))
#else
        target_dir = trim(cmd%tokens(2))
#endif
      end if
    end if

#ifdef USE_MEMORY_POOL
    if (change_directory(target_dir_ref%data)) then
#else
    if (change_directory(target_dir)) then
#endif
      ! Update OLDPWD before changing cwd
      shell%oldpwd = old_cwd
      ! POSIX: Use logical path (preserve symlinks) unless -P is specified
      ! For absolute paths, use them as-is. For relative paths, resolve logically.
#ifdef USE_MEMORY_POOL
      if (len(target_dir_ref%data) > 0 .and. target_dir_ref%data(1:1) == '/') then
        ! Absolute path - use it directly (preserves symlinks like /tmp)
        shell%cwd = target_dir_ref%data
#else
      if (len(target_dir) > 0 .and. target_dir(1:1) == '/') then
        ! Absolute path - use it directly (preserves symlinks like /tmp)
        shell%cwd = target_dir
#endif
      else
        ! Relative path - use physical path from getcwd()
        shell%cwd = get_current_directory()
      end if

      ! Update PWD and OLDPWD environment variables
      if (.not. set_environment_var('PWD', trim(shell%cwd))) then
        ! Ignore error, not critical
      end if
      if (.not. set_environment_var('OLDPWD', trim(shell%oldpwd))) then
        ! Ignore error, not critical
      end if

      ! Update terminal title after directory change
      if (shell%is_interactive .and. shell%term_supports_color) then
        call set_terminal_title(trim(shell%username) // '@' // trim(shell%hostname) // ': ' // trim(shell%cwd))
      end if

      ! Add OLD directory to history so prevd can go back to it (Fish-style prevd/nextd)
      call add_to_dir_history(shell, old_cwd)

      ! Add NEW directory to history so nextd can go forward to it
      call add_to_dir_history(shell, shell%cwd)

      ! Print new directory if cd - or CDPATH was used
      if (print_dir) then
        write(output_unit, '(a)') trim(shell%cwd)
        flush(output_unit)
      end if

      shell%last_exit_status = 0
    else
#ifdef USE_MEMORY_POOL
      write(error_unit, '(a)') 'cd: cannot access ' // trim(target_dir_ref%data) // &
                              ': No such file or directory. Use "pwd" to see current location.'
#else
      write(error_unit, '(a)') 'cd: cannot access ' // trim(target_dir) // &
                              ': No such file or directory. Use "pwd" to see current location.'
#endif
      shell%last_exit_status = 1
    end if

#ifdef USE_MEMORY_POOL
    ! Release pooled buffer
    call pool_release_string(target_dir_ref)
    call dashboard_track_deallocation(MOD_BUILTINS, MAX_PATH_LEN, 4)
#endif
  end subroutine

  subroutine builtin_pwd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

    ! Use FD-aware I/O to respect redirections
    call write_stdout(trim(shell%cwd))
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_export(cmd, shell)
    use variables, only: set_shell_variable, get_shell_variable
    use system_interface, only: get_environ_entry
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos, i, j, arg_idx
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    logical :: print_mode, found
    character(len=:), allocatable :: env_entry

    print_mode = .false.

    if (cmd%num_tokens < 2) then
      ! No arguments: print all exported variables
      print_mode = .true.
    end if

    if (print_mode) then
      ! Print all environment variables (inherited from parent + shell-exported)
      i = 0
      do
        env_entry = get_environ_entry(i)
        if (.not. allocated(env_entry) .or. len(env_entry) == 0) exit
        ! Format: export VAR=value
        write(output_unit, '(a)') 'export ' // trim(env_entry)
        if (allocated(env_entry)) deallocate(env_entry)
        i = i + 1
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
    use io_helpers, only: write_stdout_checked, write_stdout_nonl_checked
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j, len_token, start_token
    logical :: first, suppress_newline, write_ok, had_error, interpret_escapes
    character(len=:), allocatable :: processed
    character(len=MAX_TOKEN_LEN) :: token

    had_error = .false.

    ! POSIX echo implementation - interprets backslash escape sequences
    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens < 1) then
      call write_stdout_checked('', write_ok)
      if (.not. write_ok) then
        call write_stderr('fortsh: echo: write error: Bad file descriptor')
        shell%last_exit_status = 1
      else
        shell%last_exit_status = 0
      end if
      return
    end if

    first = .true.
    suppress_newline = .false.
    interpret_escapes = .false.  ! Bash default: do NOT interpret escapes (use -e to enable)
    start_token = 2

    ! Parse options (must be first arguments)
    do i = 2, cmd%num_tokens
      token = cmd%tokens(i)
      if (token(1:1) /= '-' .or. len_trim(token) < 2) exit

      ! Check for valid option characters
      if (trim(token) == '-n') then
        suppress_newline = .true.
        start_token = i + 1
      else if (trim(token) == '-e') then
        interpret_escapes = .true.
        start_token = i + 1
      else if (trim(token) == '-E') then
        interpret_escapes = .false.
        start_token = i + 1
      else if (trim(token) == '-ne' .or. trim(token) == '-en') then
        suppress_newline = .true.
        interpret_escapes = .true.
        start_token = i + 1
      else if (trim(token) == '-nE' .or. trim(token) == '-En') then
        suppress_newline = .true.
        interpret_escapes = .false.
        start_token = i + 1
      else if (trim(token) == '--') then
        start_token = i + 1
        exit
      else
        ! Not a recognized option, treat as regular argument
        exit
      end if
    end do

    do i = start_token, cmd%num_tokens
      ! POSIX: Skip empty tokens ONLY if they were unquoted (empty variables disappear)
      ! Quoted empty strings "" should produce an empty argument
      if (len_trim(cmd%tokens(i)) == 0) then
        if (allocated(cmd%token_quoted)) then
          if (i <= size(cmd%token_quoted) .and. cmd%token_quoted(i)) then
            ! Token was quoted - keep it as empty argument
          else
            ! Token was not quoted - skip it
            cycle
          end if
        else
          ! No quote info available - skip empty tokens (safer default)
          cycle
        end if
      end if

      if (.not. first) then
        call write_stdout_nonl_checked(' ', write_ok)
        if (.not. write_ok) had_error = .true.
      end if

      ! Process escape sequences in token (only if interpret_escapes is true)
      token = cmd%tokens(i)
      ! Use token_lengths to preserve trailing spaces if available
      if (allocated(cmd%token_lengths) .and. i <= size(cmd%token_lengths) .and. &
          cmd%token_lengths(i) > 0) then
        len_token = cmd%token_lengths(i)
      else
        len_token = len_trim(token)
      end if

      processed = ''
      j = 1

      if (interpret_escapes) then
        do while (j <= len_token)
          if (token(j:j) == '\' .and. j < len_token) then
            ! Escape sequence
            j = j + 1
            select case (token(j:j))
              case ('a')
                processed = processed // achar(7)  ! Alert (bell)
              case ('b')
                processed = processed // achar(8)  ! Backspace
              case ('c')
                suppress_newline = .true.
                exit  ! Stop processing
              case ('f')
                processed = processed // achar(12) ! Form feed
              case ('n')
                processed = processed // new_line('a')  ! Newline
              case ('r')
                processed = processed // achar(13) ! Carriage return
              case ('t')
                processed = processed // achar(9)  ! Tab
              case ('v')
                processed = processed // achar(11) ! Vertical tab
              case ('\')
                processed = processed // '\'       ! Backslash
              case default
                ! Unknown escape - keep literal backslash and character
                processed = processed // '\' // token(j:j)
            end select
            j = j + 1
          else
            ! Regular character
            processed = processed // token(j:j)
            j = j + 1
          end if
        end do
      else
        ! -E flag: don't interpret escape sequences
        processed = token(:len_token)
      end if

      call write_stdout_nonl_checked(processed, write_ok)
      if (.not. write_ok) had_error = .true.
      first = .false.

      if (suppress_newline) exit
    end do

    if (.not. suppress_newline) then
      call write_stdout_checked('', write_ok)
      if (.not. write_ok) had_error = .true.
    end if

    if (had_error) then
      call write_stderr('fortsh: echo: write error: Bad file descriptor')
      shell%last_exit_status = 1
    else
      shell%last_exit_status = 0
    end if
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

  ! Parse job specification and return job_id
  ! Supports: %n, %%, %+, %-, %?string
  ! Returns 0 if no match found
  function parse_job_spec(shell, spec) result(job_id)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: spec
    integer :: job_id
    character(len=256) :: search_str
    integer :: iostat, i

    job_id = 0

    if (len_trim(spec) == 0) then
      ! Empty spec - use current job
      job_id = shell%current_job_id
      return
    end if

    ! Remove leading % if present
    if (spec(1:1) == '%') then
      if (len_trim(spec) == 1) then
        ! Just "%" - current job
        job_id = shell%current_job_id
        return
      end if

      select case (spec(2:2))
      case ('+')
        ! %+ - current job
        job_id = shell%current_job_id
      case ('-')
        ! %- - previous job
        job_id = shell%previous_job_id
      case ('%')
        ! %% - current job
        job_id = shell%current_job_id
      case ('?')
        ! %?string - search for string in command
        search_str = trim(spec(3:))
        do i = 1, MAX_JOBS
          if (shell%jobs(i)%job_id > 0) then
            if (index(shell%jobs(i)%command_line, trim(search_str)) > 0) then
              job_id = shell%jobs(i)%job_id
              return
            end if
          end if
        end do
      case default
        ! %n - job number
        read(spec(2:), *, iostat=iostat) job_id
        if (iostat /= 0) then
          job_id = 0
        end if
      end select
    else
      ! No % prefix - try to parse as number
      read(spec, *, iostat=iostat) job_id
      if (iostat /= 0) then
        job_id = 0
      end if
    end if
  end function parse_job_spec

  subroutine builtin_fg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, i

    if (cmd%num_tokens < 2) then
      ! Use current job, or fall back to most recent stopped job
      job_id = shell%current_job_id
      if (job_id == 0) then
        do i = MAX_JOBS, 1, -1
          if (shell%jobs(i)%job_id > 0 .and. shell%jobs(i)%state == JOB_STOPPED) then
            job_id = shell%jobs(i)%job_id
            exit
          end if
        end do
      end if

      if (job_id == 0) then
        write(error_unit, '(a)') 'fg: no current job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job spec (%n, %%, %+, %-, %?string)
      job_id = parse_job_spec(shell, cmd%tokens(2))

      if (job_id == 0) then
        write(error_unit, '(a)') 'fg: no such job'
        shell%last_exit_status = 1
        return
      end if
    end if

    call resume_job_fg(shell, job_id)
  end subroutine

  subroutine builtin_bg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, i

    if (cmd%num_tokens < 2) then
      ! Use current job, or fall back to most recent stopped job
      job_id = shell%current_job_id
      if (job_id == 0) then
        do i = MAX_JOBS, 1, -1
          if (shell%jobs(i)%job_id > 0 .and. &
              shell%jobs(i)%state == JOB_STOPPED) then
            job_id = shell%jobs(i)%job_id
            exit
          end if
        end do
      end if

      if (job_id == 0) then
        write(error_unit, '(a)') 'bg: no current job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job spec (%n, %%, %+, %-, %?string)
      job_id = parse_job_spec(shell, cmd%tokens(2))

      if (job_id == 0) then
        write(error_unit, '(a)') 'bg: no such job'
        shell%last_exit_status = 1
        return
      end if
    end if

    call resume_job_bg(shell, job_id)
  end subroutine

  subroutine builtin_source(cmd, shell)
    use variables, only: get_shell_variable
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=1024) :: filename, path_var, dir, candidate
    character(len=:), allocatable :: path_str
    logical :: file_exists, found_in_path
    integer :: i, path_start, path_end, path_len

    ! Check if filename provided
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'source: usage: source filename [arguments...]'
      shell%last_exit_status = 1
      return
    end if

    filename = trim(cmd%tokens(2))

    ! POSIX: If filename doesn't contain '/', search PATH
    if (index(filename, '/') == 0) then
      ! Get PATH variable
      path_str = get_shell_variable(shell, 'PATH')
      if (allocated(path_str)) then
        path_var = path_str
      else
        path_var = ''
      end if
      path_len = len_trim(path_var)

      found_in_path = .false.
      path_start = 1

      ! Search each directory in PATH
      do while (path_start <= path_len .and. .not. found_in_path)
        ! Find next colon or end of string
        path_end = index(path_var(path_start:), ':')
        if (path_end == 0) then
          path_end = path_len + 1
        else
          path_end = path_start + path_end - 1
        end if

        ! Extract directory
        if (path_end > path_start) then
          dir = trim(path_var(path_start:path_end-1))
          ! Build candidate path
          if (len_trim(dir) > 0) then
            candidate = trim(dir) // '/' // trim(filename)
          else
            ! Empty PATH component means current directory
            candidate = trim(filename)
          end if

          ! Check if candidate exists
          inquire(file=candidate, exist=file_exists)
          if (file_exists) then
            filename = candidate
            found_in_path = .true.
          end if
        end if

        ! Move to next PATH component
        path_start = path_end + 1
      end do

      ! If not found in PATH, try current directory as fallback
      if (.not. found_in_path) then
        inquire(file=filename, exist=file_exists)
        if (.not. file_exists) then
          write(error_unit, '(a)') 'source: ' // trim(cmd%tokens(2)) // ': No such file or directory'
          shell%last_exit_status = 1
          return
        end if
      end if
    else
      ! Contains '/' - use as-is, no PATH search
      inquire(file=filename, exist=file_exists)
      if (.not. file_exists) then
        write(error_unit, '(a)') 'source: ' // trim(filename) // ': No such file or directory'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    ! Set positional parameters from remaining arguments
    ! Save $0 (script name)
    shell%shell_name = trim(filename)

    ! Set $1, $2, ... from arguments
    shell%num_positional = 0
    if (cmd%num_tokens > 2) then
      ! Allocate positional_params if not already allocated
      if (.not. allocated(shell%positional_params)) then
        allocate(shell%positional_params(50))  ! Default size
      end if

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
    ! Don't set exit status here - will be set by the sourced file execution
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
          ! Check if there's a signal number argument
          if (cmd%num_tokens >= 3) then
            ! kill -l <num> - translate signal number to name
            read(cmd%tokens(3), *, iostat=iostat) signal_num
            if (iostat == 0) then
              select case(signal_num)
              case(1);  write(output_unit, '(a)') 'HUP'
              case(2);  write(output_unit, '(a)') 'INT'
              case(3);  write(output_unit, '(a)') 'QUIT'
              case(4);  write(output_unit, '(a)') 'ILL'
              case(5);  write(output_unit, '(a)') 'TRAP'
              case(6);  write(output_unit, '(a)') 'ABRT'
              case(7);  write(output_unit, '(a)') 'BUS'
              case(8);  write(output_unit, '(a)') 'FPE'
              case(9);  write(output_unit, '(a)') 'KILL'
              case(10); write(output_unit, '(a)') 'USR1'
              case(11); write(output_unit, '(a)') 'SEGV'
              case(12); write(output_unit, '(a)') 'USR2'
              case(13); write(output_unit, '(a)') 'PIPE'
              case(14); write(output_unit, '(a)') 'ALRM'
              case(15); write(output_unit, '(a)') 'TERM'
              case(16); write(output_unit, '(a)') 'STKFLT'
              case(17); write(output_unit, '(a)') 'CHLD'
              case(18); write(output_unit, '(a)') 'CONT'
              case(19); write(output_unit, '(a)') 'STOP'
              case(20); write(output_unit, '(a)') 'TSTP'
              case(21); write(output_unit, '(a)') 'TTIN'
              case(22); write(output_unit, '(a)') 'TTOU'
              case default
                write(error_unit, '(a,i0)') 'kill: invalid signal number: ', signal_num
                shell%last_exit_status = 1
                return
              end select
              shell%last_exit_status = 0
              return
            end if
          end if
          ! No argument or invalid - list all signals
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
        write(error_unit, '(a,i15)') 'kill: failed to kill process ', target_pid
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
          if (WIFEXITED(wait_status) .or. WIFSIGNALED(wait_status)) then
            shell%jobs(i)%state = JOB_DONE
          end if
        end if
      end do
      shell%last_exit_status = 0
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
            else if (WIFSIGNALED(wait_status)) then
              shell%last_exit_status = 128 + WTERMSIG(wait_status)
            else
              shell%last_exit_status = 1
            end if
          else
            ! PID is not a child of this shell (or doesn't exist)
            write(error_unit, '(a,i0,a)') 'wait: pid ', target_pid, ' not found'
            shell%last_exit_status = 127
          end if
        end if
      end do
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
          ! Use num_traps instead of size(traps) so that subshells can clear traps
          do k = 1, shell%num_traps
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

    ! Strip quotes from action if present
    if (len_trim(action) >= 2) then
      if (action(1:1) == '"' .and. action(len_trim(action):len_trim(action)) == '"') then
        action = action(2:len_trim(action)-1)
      else if (action(1:1) == "'" .and. action(len_trim(action):len_trim(action)) == "'") then
        action = action(2:len_trim(action)-1)
      end if
    end if

    ! Check for removal syntax: trap - signal
    ! Note: trap "" signal (empty action) means ignore the signal, not remove the trap
    if (trim(action) == '-') then
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
    integer :: eq_pos, i
    character(len=256) :: alias_name, alias_command
    character(len=1024) :: full_arg

    if (cmd%num_tokens == 1) then
      ! Show all aliases
      call show_aliases(shell)
    else if (cmd%num_tokens == 2 .and. trim(cmd%tokens(2)) == '-p') then
      ! POSIX: -p prints all aliases in reusable format (same as no args)
      call show_aliases(shell)
    else if (cmd%num_tokens >= 2) then
      ! Reconstruct the full argument from all tokens
      full_arg = trim(cmd%tokens(2))
      do i = 3, cmd%num_tokens
        full_arg = trim(full_arg) // ' ' // trim(cmd%tokens(i))
      end do

      ! Check for alias=command format
      eq_pos = index(full_arg, '=')
      if (eq_pos > 0) then
        alias_name = full_arg(:eq_pos-1)
        alias_command = full_arg(eq_pos+1:)

        ! Remove quotes or quote sentinels if present
        ! Lexer uses char(2)/char(3) for single-quote boundaries, char(1) for double-quote
        if (len_trim(alias_command) >= 2) then
          ! Check for single-quote sentinels (char(2) start, char(3) end)
          if (alias_command(1:1) == char(2) .and. &
              alias_command(len_trim(alias_command):len_trim(alias_command)) == char(3)) then
            alias_command = alias_command(2:len_trim(alias_command)-1)
          ! Check for actual quote characters (in case they weren't converted)
          else if (alias_command(1:1) == '"' .and. alias_command(len_trim(alias_command):len_trim(alias_command)) == '"') then
            alias_command = alias_command(2:len_trim(alias_command)-1)
          else if (alias_command(1:1) == "'" .and. alias_command(len_trim(alias_command):len_trim(alias_command)) == "'") then
            alias_command = alias_command(2:len_trim(alias_command)-1)
          end if
        end if

        call set_alias(shell, trim(alias_name), trim(alias_command))
      else if (cmd%num_tokens == 2) then
        ! Show specific alias (only if single argument without =)
        alias_name = cmd%tokens(2)
        alias_command = get_alias(shell, trim(alias_name))
        if (len_trim(alias_command) > 0) then
          write(output_unit, '(a)') 'alias ' // trim(alias_name) // &
                                   '=' // "'" // trim(alias_command) // "'"
        else
          call write_stderr('alias: ' // trim(alias_name) // ': not found')
          shell%last_exit_status = 1
          return
        end if
      else
        call write_stderr('alias: usage: alias [name[=value]...]')
        shell%last_exit_status = 1
        return
      end if
    end if

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_unalias(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    logical :: found, any_not_found

    if (cmd%num_tokens < 2) then
      call write_stderr('unalias: usage: unalias name...')
      shell%last_exit_status = 1
      return
    end if

    ! Check for -a flag (remove all aliases)
    if (trim(cmd%tokens(2)) == '-a') then
      call clear_all_aliases(shell)
      shell%last_exit_status = 0
      return
    end if

    any_not_found = .false.

    ! Remove each specified alias
    do i = 2, cmd%num_tokens
      found = unset_alias(shell, trim(cmd%tokens(i)))
      if (.not. found) any_not_found = .true.
    end do

    if (any_not_found) then
      shell%last_exit_status = 1
    else
      shell%last_exit_status = 0
    end if
  end subroutine

  subroutine builtin_abbr(cmd, shell)
    use abbreviations
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos
    character(len=256) :: short_form, expanded_form
    character(len=64) :: abbr_short
    character(len=256) :: abbr_expanded

    if (cmd%num_tokens == 1) then
      ! Show all abbreviations
      call show_abbreviations()
    else if (cmd%num_tokens >= 2) then
      ! Check for --erase flag
      if (trim(cmd%tokens(2)) == '--erase' .or. trim(cmd%tokens(2)) == '-e') then
        if (cmd%num_tokens >= 3) then
          abbr_short = trim(cmd%tokens(3))
          call unset_abbreviation(abbr_short)
        else
          write(error_unit, '(a)') 'abbr: --erase requires an abbreviation name'
          shell%last_exit_status = 1
          return
        end if
      else if (trim(cmd%tokens(2)) == '--show' .or. trim(cmd%tokens(2)) == '-s') then
        ! Show abbreviations (same as no args)
        call show_abbreviations()
      else
        ! Check for short=expanded format
        eq_pos = index(cmd%tokens(2), '=')
        if (eq_pos > 0) then
          short_form = cmd%tokens(2)(:eq_pos-1)
          expanded_form = cmd%tokens(2)(eq_pos+1:)

          ! Remove quotes if present
          if (expanded_form(1:1) == '"' .and. expanded_form(len_trim(expanded_form):len_trim(expanded_form)) == '"') then
            expanded_form = expanded_form(2:len_trim(expanded_form)-1)
          else if (expanded_form(1:1) == "'" .and. expanded_form(len_trim(expanded_form):len_trim(expanded_form)) == "'") then
            expanded_form = expanded_form(2:len_trim(expanded_form)-1)
          end if

          abbr_short = trim(short_form)
          abbr_expanded = trim(expanded_form)
          call set_abbreviation(abbr_short, abbr_expanded)
        else
          ! Show specific abbreviation
          abbr_short = trim(cmd%tokens(2))
          abbr_expanded = get_abbreviation(abbr_short)
          if (len(abbr_expanded) > 0) then
            write(output_unit, '(a)') 'abbr ' // trim(abbr_short) // &
                                     '=' // "'" // trim(abbr_expanded) // "'"
          else
            write(error_unit, '(a)') 'abbr: ' // trim(abbr_short) // ': not found'
            shell%last_exit_status = 1
            return
          end if
        end if
      end if
    end if

    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_help(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

    write(output_unit, '(a)') 'Fortran Shell (fortsh) - Built-in Commands:'
    write(output_unit, '(a)') '========================================'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Navigation & Directories:'
    write(output_unit, '(a)') '  cd [dir]        Change directory (cd - for previous, cd ~ for home)'
    write(output_unit, '(a)') '  pwd             Print working directory'
    write(output_unit, '(a)') '  pushd [dir]     Push directory onto stack'
    write(output_unit, '(a)') '  popd            Pop directory from stack'
    write(output_unit, '(a)') '  dirs [-clpv]    Display directory stack'
    write(output_unit, '(a)') '  prevd/nextd     Navigate directory stack'
    write(output_unit, '(a)') '  dirh            Show directory history'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Variables & Environment:'
    write(output_unit, '(a)') '  export VAR=val  Set/export environment variable'
    write(output_unit, '(a)') '  unset name      Remove variable or function'
    write(output_unit, '(a)') '  readonly VAR    Mark variable as read-only'
    write(output_unit, '(a)') '  declare [-x]    Declare variables with attributes'
    write(output_unit, '(a)') '  local VAR=val   Declare function-local variable'
    write(output_unit, '(a)') '  printenv [VAR]  Print environment variables'
    write(output_unit, '(a)') '  set [opts]      Set shell options (-e, -u, -x, -o pipefail)'
    write(output_unit, '(a)') '  shopt [opt]     Toggle shell options'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'I/O & Formatting:'
    write(output_unit, '(a)') '  echo [args]     Display text'
    write(output_unit, '(a)') '  printf fmt args Formatted output'
    write(output_unit, '(a)') '  read [-p] var   Read input into variable'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Job Control:'
    write(output_unit, '(a)') '  jobs            List active jobs'
    write(output_unit, '(a)') '  fg [%n]         Bring job to foreground'
    write(output_unit, '(a)') '  bg [%n]         Send job to background'
    write(output_unit, '(a)') '  kill [-sig] pid Send signal to process'
    write(output_unit, '(a)') '  wait [pid]      Wait for process to complete'
    write(output_unit, '(a)') '  coproc cmd      Start coprocess with bidirectional I/O'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Shell Features:'
    write(output_unit, '(a)') '  source/. file   Execute commands from file'
    write(output_unit, '(a)') '  eval [args]     Evaluate arguments as shell command'
    write(output_unit, '(a)') '  exec [cmd]      Replace shell with command'
    write(output_unit, '(a)') '  command [-v] cmd  Run command bypassing functions'
    write(output_unit, '(a)') '  type/which name Identify command type'
    write(output_unit, '(a)') '  hash [-r]       Manage command hash table'
    write(output_unit, '(a)') '  trap [cmd] sig  Set signal handlers'
    write(output_unit, '(a)') '  history         Show command history'
    write(output_unit, '(a)') '  fc              Fix/edit previous commands'
    write(output_unit, '(a)') '  alias [n=cmd]   Create/show command aliases'
    write(output_unit, '(a)') '  unalias name    Remove alias'
    write(output_unit, '(a)') '  abbr [n=cmd]    Manage abbreviations'
    write(output_unit, '(a)') '  config [cmd]    Manage shell configuration'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Scripting & Control Flow:'
    write(output_unit, '(a)') '  test / [ ] / [[ ]]  Evaluate conditions'
    write(output_unit, '(a)') '  if/then/elif/else/fi Conditional execution'
    write(output_unit, '(a)') '  for/while/until     Loop constructs'
    write(output_unit, '(a)') '  case/esac           Pattern matching'
    write(output_unit, '(a)') '  break/continue      Loop control'
    write(output_unit, '(a)') '  return [n]          Return from function'
    write(output_unit, '(a)') '  shift [n]           Shift positional parameters'
    write(output_unit, '(a)') '  getopts str var     Parse positional parameters'
    write(output_unit, '(a)') '  let expr            Arithmetic evaluation'
    write(output_unit, '(a)') '  : (colon)           Null command (always succeeds)'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'System:'
    write(output_unit, '(a)') '  umask [mode]    Get/set file creation mask'
    write(output_unit, '(a)') '  ulimit [-a]     Get/set resource limits'
    write(output_unit, '(a)') '  times           Display process times'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Completion:'
    write(output_unit, '(a)') '  complete        Define programmable completions'
    write(output_unit, '(a)') '  compgen         Generate completion matches'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Other:'
    write(output_unit, '(a)') '  perf [on|off]   Performance monitoring'
    write(output_unit, '(a)') '  memory [cmd]    Memory pool management'
    write(output_unit, '(a)') '  help            Show this help message'
    write(output_unit, '(a)') '  exit [code]     Exit shell'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Interactive Keybindings:'
    write(output_unit, '(a)') '  Up/Down         Navigate command history'
    write(output_unit, '(a)') '  Ctrl+A/E        Move to beginning/end of line'
    write(output_unit, '(a)') '  Ctrl+W/K/U      Kill word/to-end/line'
    write(output_unit, '(a)') '  Ctrl+Y          Yank (paste) killed text'
    write(output_unit, '(a)') '  Ctrl+R          Reverse history search'
    write(output_unit, '(a)') '  Ctrl+L          Clear screen'
    write(output_unit, '(a)') '  Tab             Smart completion with menu'
    write(output_unit, '(a)') '  Ctrl+F          fzf file browser'
    write(output_unit, '(a)') '  Alt+j           fzf directory jump'
    write(output_unit, '(a)') '  Alt+g           fzf git browser'
    
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
      write(output_unit, '(a,i15)') 'Commands processed: ', total_commands
      write(output_unit, '(a,i15,a)') 'Memory usage: ', get_memory_usage(), ' KB'
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
      write(output_unit, '(a,i15)') 'Current allocations: ', current_allocations
      write(output_unit, '(a,i15)') 'Peak allocations:    ', peak_allocations
      write(output_unit, '(a,i15,a)') 'Current memory:      ', current_memory_used, ' bytes'
      write(output_unit, '(a,i15,a)') 'Peak memory:         ', peak_memory_used, ' bytes'
      
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

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

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
          write(output_unit, '(a,i15)', advance='no') '[', iachar(ch)
          if (ch == '[') then
            success = read_single_char(ch)
            if (success) then
              write(output_unit, '(a,i15,a)', advance='no') '[', iachar(ch), '] = '
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
        write(output_unit, '(a,i15,a)') 'CTRL+', char_code, ' (^', char(char_code + 64), ')'
      else if (char_code == 127) then
        write(output_unit, '(a)') 'BACKSPACE/DELETE (127)'
      else
        ! Regular character
        write(output_unit, '(a,a,a,i15,a)') 'Regular: ''', ch, ''' (', char_code, ')'
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

  ! Coprocess built-in command: coproc [NAME] command [args]
  subroutine builtin_coproc(cmd, shell)
    use coprocess, only: start_coprocess, coprocs
    use variables, only: set_array_element
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=256) :: coproc_name, command_str
    integer :: coproc_id, i, cmd_start_idx
    character(len=16) :: fd_str

    ! Default name
    coproc_name = 'COPROC'

    ! Parse arguments: coproc [NAME] command [args]
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'coproc: usage: coproc [NAME] command [args]'
      shell%last_exit_status = 1
      return
    end if

    ! Check if first argument is a name (uppercase letters)
    if (cmd%num_tokens >= 3 .and. is_valid_coproc_name(cmd%tokens(2))) then
      coproc_name = trim(cmd%tokens(2))
      cmd_start_idx = 3
    else
      cmd_start_idx = 2
    end if

    ! Build command string from remaining tokens
    command_str = ''
    do i = cmd_start_idx, cmd%num_tokens
      if (i > cmd_start_idx) command_str = trim(command_str) // ' '
      command_str = trim(command_str) // trim(cmd%tokens(i))
    end do

    ! Start the coprocess
    coproc_id = start_coprocess(trim(command_str), trim(coproc_name))

    if (coproc_id < 0) then
      write(error_unit, '(a)') 'coproc: failed to start coprocess'
      shell%last_exit_status = 1
      return
    end if

    ! Create array variables: NAME[0] = read_fd, NAME[1] = write_fd
    write(fd_str, '(I0)') coprocs(coproc_id)%read_fd
    call set_array_element(shell, trim(coproc_name), 1, trim(fd_str))  ! Bash index 0 = Fortran index 1
    write(fd_str, '(I0)') coprocs(coproc_id)%write_fd
    call set_array_element(shell, trim(coproc_name), 2, trim(fd_str))  ! Bash index 1 = Fortran index 2

    shell%last_exit_status = 0
  end subroutine

  ! Helper: Check if name is valid (uppercase letters/digits/underscore)
  function is_valid_coproc_name(name) result(is_valid)
    character(len=*), intent(in) :: name
    logical :: is_valid
    integer :: i
    character :: c

    is_valid = .false.
    if (len_trim(name) == 0) return

    ! Name must start with letter or underscore
    c = name(1:1)
    if (.not. ((c >= 'A' .and. c <= 'Z') .or. c == '_')) return

    ! Rest can be letters, digits, or underscore
    do i = 2, len_trim(name)
      c = name(i:i)
      if (.not. ((c >= 'A' .and. c <= 'Z') .or. (c >= '0' .and. c <= '9') .or. c == '_')) return
    end do

    is_valid = .true.
  end function

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
    character(len=1024) :: full_path
    integer :: i
    logical :: any_not_found

    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'type: usage: type name [name ...]'
      shell%last_exit_status = 1
      return
    end if

    any_not_found = .false.

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
        if (find_executable_in_path(shell, command_name, full_path)) then
          write(output_unit, '(a)') trim(command_name) // ' is ' // trim(full_path)
        else
          write(error_unit, '(a)') trim(command_name) // ': not found'
          any_not_found = .true.
        end if
      end if
    end do

    if (any_not_found) then
      shell%last_exit_status = 1
    else
      shell%last_exit_status = 0
    end if
  end subroutine

  subroutine builtin_unset(cmd, shell)
    use ast_executor, only: unset_ast_function
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
        ! Unset function from both old and new function storage

        ! Clear from old executor's function storage
        do j = 1, shell%num_functions
          if (trim(shell%functions(j)%name) == var_name) then
            shell%functions(j)%name = ''
            shell%functions(j)%body_lines = 0
            if (allocated(shell%functions(j)%body)) deallocate(shell%functions(j)%body)
            exit
          end if
        end do

        ! Clear from AST executor's function cache
        call unset_ast_function(var_name)
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
      ! Print all readonly variables (including special readonly params)
      ! Match bash behavior: include PPID, UID, EUID, and shell options
      block
        use system_interface, only: c_getuid, c_geteuid
        character(len=20) :: ppid_str, uid_str, euid_str
        character(len=256) :: shellopts

        ! PPID - parent process ID
        write(ppid_str, '(i0)') shell%parent_pid
        write(output_unit, '(a)') 'readonly PPID=' // trim(ppid_str)

        ! UID - real user ID
        write(uid_str, '(i0)') c_getuid()
        write(output_unit, '(a)') 'readonly UID=' // trim(uid_str)

        ! EUID - effective user ID
        write(euid_str, '(i0)') c_geteuid()
        write(output_unit, '(a)') 'readonly EUID=' // trim(euid_str)

        ! SHELLOPTS - shell option settings (bash compatibility)
        shellopts = ''
        if (shell%option_braceexpand) shellopts = trim(shellopts) // ':braceexpand'
        if (shell%option_hashall) shellopts = trim(shellopts) // ':hashall'
        shellopts = trim(shellopts) // ':interactive-comments'  ! Always on
        if (len_trim(shellopts) > 0 .and. shellopts(1:1) == ':') shellopts = shellopts(2:)
        write(output_unit, '(a)') 'readonly SHELLOPTS="' // trim(shellopts) // '"'

        ! FORTSH_VERSION - shell version
        write(output_unit, '(a)') 'readonly FORTSH_VERSION="0.1.0"'

        ! HOSTNAME - system hostname (bash compatibility)
        write(output_unit, '(a)') 'readonly HOSTNAME="' // trim(shell%hostname) // '"'
      end block
      ! Print user-defined readonly variables
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
    logical :: invalid_count

    ! Default to breaking 1 level
    break_count = 1
    invalid_count = .false.

    ! Parse optional numeric argument
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=iostat) break_count
      if (iostat /= 0) then
        write(error_unit, '(a)') 'break: invalid number'
        shell%last_exit_status = 1
        return
      end if
      if (break_count < 1) then
        ! POSIX: behavior for n < 1 is unspecified, silently treat as 1
        invalid_count = .true.
        break_count = 1
      end if
    end if

    ! Find the nearest loop and set break flag
    do i = shell%control_depth, 1, -1
      if (shell%control_stack(i)%block_type == BLOCK_FOR .or. &
          shell%control_stack(i)%block_type == BLOCK_WHILE .or. &
          shell%control_stack(i)%block_type == BLOCK_UNTIL .or. &
          shell%control_stack(i)%block_type == BLOCK_FOR_ARITH) then
        ! POSIX: if break is already requested, don't change exit status
        ! This preserves the status from the first break command (e.g., "break 0 || break")
        if (.not. shell%control_stack(i)%break_requested) then
          shell%control_stack(i)%break_requested = .true.
          shell%control_stack(i)%break_level = break_count
          ! POSIX: invalid count still breaks loop, but with exit status 1
          if (invalid_count) then
            shell%last_exit_status = 1
          else
            shell%last_exit_status = 0
          end if
        end if
        return
      end if
    end do

    ! No loop found - POSIX says behavior is unspecified
    ! For maximum compatibility, silently return success (like POSIX sh)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_continue(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: continue_count, i, iostat
    logical :: invalid_count

    ! Default to continuing 1 level
    continue_count = 1
    invalid_count = .false.

    ! Parse optional numeric argument
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=iostat) continue_count
      if (iostat /= 0) then
        write(error_unit, '(a)') 'continue: invalid number'
        shell%last_exit_status = 1
        return
      end if
      if (continue_count < 1) then
        ! POSIX: behavior for n < 1 is unspecified, silently treat as 1
        invalid_count = .true.
        continue_count = 1
      end if
    end if

    ! Find the nearest loop and set continue flag
    do i = shell%control_depth, 1, -1
      if (shell%control_stack(i)%block_type == BLOCK_FOR .or. &
          shell%control_stack(i)%block_type == BLOCK_WHILE .or. &
          shell%control_stack(i)%block_type == BLOCK_UNTIL .or. &
          shell%control_stack(i)%block_type == BLOCK_FOR_ARITH) then
        ! POSIX: if continue is already requested, don't change exit status
        ! This preserves the status from the first continue command (e.g., "continue 0 || continue")
        if (.not. shell%control_stack(i)%continue_requested) then
          shell%control_stack(i)%continue_requested = .true.
          shell%control_stack(i)%continue_level = continue_count
          ! POSIX: invalid count still continues loop, but with exit status 1
          if (invalid_count) then
            shell%last_exit_status = 1
          else
            shell%last_exit_status = 0
          end if
        end if
        return
      end if
    end do

    ! No loop found - POSIX says behavior is unspecified
    ! For maximum compatibility, silently return success (like POSIX sh)
    shell%last_exit_status = 0
  end subroutine

  subroutine builtin_return(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: return_code, iostat

    ! POSIX: return outside function/sourced script should fail
    ! Return silently with exit status 2 (like bash)
    if (shell%function_depth == 0 .and. shell%source_depth == 0) then
      shell%last_exit_status = 2
      return
    end if

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
    use fd_redirection, only: apply_single_redirection
    use parser, only: expand_variables
    use system_interface, only: file_exists, file_is_executable
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=256), target :: c_prog_name
    character(len=256), target, allocatable :: c_args(:)
    type(c_ptr), allocatable, target :: argv(:)
    integer :: i, ret
    character(len=MAX_PATH_LEN) :: prog_path
    logical :: redir_success
    type(redirection_t) :: expanded_redir
    character(len=:), allocatable :: expanded_filename

    ! exec without arguments but with redirections applies them to the current shell
    if (cmd%num_tokens < 2) then
      if (cmd%num_redirections > 0) then
        ! Apply redirections to the current shell process (permanent=.true. for exec)
        do i = 1, cmd%num_redirections
          ! Make a copy of the redirection and expand the filename
          expanded_redir = cmd%redirections(i)
          if (allocated(cmd%redirections(i)%filename)) then
            call expand_variables(trim(cmd%redirections(i)%filename), expanded_filename, shell)
            if (allocated(expanded_filename)) then
              expanded_redir%filename = expanded_filename
            end if
          end if
          call apply_single_redirection(expanded_redir, redir_success, shell%option_noclobber, permanent=.true.)
          if (.not. redir_success) then
            shell%last_exit_status = 1
            return
          end if
        end do
        shell%last_exit_status = 0
        return
      else
        ! No command and no redirections - just return success
        shell%last_exit_status = 0
        return
      end if
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
    else
      ! Absolute or relative path - check if it exists
      if (.not. file_exists(trim(cmd%tokens(2)))) then
        write(error_unit, '(a)') 'exec: ' // trim(cmd%tokens(2)) // ': No such file or directory'
        shell%last_exit_status = 127
        return
      end if
      ! Check if it's executable
      if (.not. file_is_executable(trim(cmd%tokens(2)))) then
        write(error_unit, '(a)') 'exec: ' // trim(cmd%tokens(2)) // ': Permission denied'
        shell%last_exit_status = 126
        return
      end if
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

    ! Apply any redirections before exec
    if (cmd%num_redirections > 0) then
      do i = 1, cmd%num_redirections
        call apply_single_redirection(cmd%redirections(i), redir_success, shell%option_noclobber)
        if (.not. redir_success) then
          shell%last_exit_status = 1
          return
        end if
      end do
    end if

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

  subroutine builtin_eval(cmd, shell)
    use eval_builtin, only: execute_eval
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    ! Delegate to the eval_builtin module to avoid circular dependency
    call execute_eval(cmd, shell)
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
        write(output_unit, '(a)') 'hash: hash table empty'
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
      ! Silently fail (POSIX compatible behavior)
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

    ! Don't reset exit status if an error occurred during processing
    ! (e.g., command not found)
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
      else if (len_trim(arg) == 3 .and. arg(1:1) == '-' .and. &
              (arg(2:2) == 'S' .or. arg(2:2) == 'H')) then
        ! Combined flags like -Sn, -Hn, -Ss, -Hs, etc.
        if (arg(2:2) == 'S') then
          set_soft = .true.
          set_hard = .false.
        else
          set_hard = .true.
          set_soft = .false.
        end if
        select case (arg(3:3))
          case ('c'); resource = RLIMIT_CORE; limit_name = 'core file size'
          case ('d'); resource = RLIMIT_DATA; limit_name = 'data seg size'
          case ('f'); resource = RLIMIT_FSIZE; limit_name = 'file size'
          case ('l'); resource = RLIMIT_MEMLOCK; limit_name = 'max locked memory'
          case ('m'); resource = RLIMIT_RSS; limit_name = 'max memory size'
          case ('n'); resource = RLIMIT_NOFILE; limit_name = 'open files'
          case ('s'); resource = RLIMIT_STACK; limit_name = 'stack size'
          case ('t'); resource = RLIMIT_CPU; limit_name = 'cpu time'
          case ('u'); resource = RLIMIT_NPROC; limit_name = 'max user processes'
          case ('v'); resource = RLIMIT_AS; limit_name = 'virtual memory'
          case default
            write(error_unit, '(a)') 'ulimit: invalid option: ' // trim(arg)
            shell%last_exit_status = 1
            return
        end select
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
        write(str, '(i20)') val
        str = adjustl(str)
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

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

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
    use system_interface, only: get_environ_entry
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
#ifdef USE_MEMORY_POOL
    type(string_ref) :: env_value_ref
    character(len=:), allocatable :: temp_str
#else
    character(len=:), allocatable :: env_value
#endif
    character(len=:), allocatable :: env_entry

    if (cmd%num_tokens < 2) then
      ! No arguments: print all environment variables
      i = 0
      do
        env_entry = get_environ_entry(i)
        if (.not. allocated(env_entry) .or. len(env_entry) == 0) exit
        write(output_unit, '(a)') trim(env_entry)
        if (allocated(env_entry)) deallocate(env_entry)
        i = i + 1
      end do
      shell%last_exit_status = 0
    else
      ! Print specific environment variable(s)
#ifdef USE_MEMORY_POOL
      env_value_ref = pool_get_string(1024)
      call dashboard_track_allocation(MOD_BUILTINS, 1024, 3)
#endif
      do i = 2, cmd%num_tokens
#ifdef USE_MEMORY_POOL
        temp_str = get_environment_var(trim(cmd%tokens(i)))
        if (allocated(temp_str) .and. len(temp_str) > 0) then
          env_value_ref%data = temp_str
          write(output_unit, '(a)') trim(env_value_ref%data)
        end if
        if (allocated(temp_str)) deallocate(temp_str)
#else
        env_value = get_environment_var(trim(cmd%tokens(i)))
        if (allocated(env_value) .and. len(env_value) > 0) then
          write(output_unit, '(a)') env_value
        end if
#endif
      end do
#ifdef USE_MEMORY_POOL
      call pool_release_string(env_value_ref)
      call dashboard_track_deallocation(MOD_BUILTINS, 1024, 3)
#endif
      shell%last_exit_status = 0
    end if
  end subroutine

  subroutine builtin_fc(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical :: list_mode, no_line_numbers, reverse_order, subst_mode
    character(len=:), allocatable :: editor, old_str, new_str
    character(len=1024) :: line, tmpfile, edit_cmd
    integer :: first, last, i, arg_idx, iostat, tmp_unit
    integer :: eq_pos, history_count
    logical :: found

    ! Initialize flags
    list_mode = .false.
    no_line_numbers = .false.
    reverse_order = .false.
    subst_mode = .false.
    editor = ''
    first = -1
    last = -1
    arg_idx = 2

    ! Get history count
    history_count = get_history_count()
    if (history_count == 0) then
      write(error_unit, '(a)') 'fc: no commands in history'
      shell%last_exit_status = 1
      return
    end if

    ! Parse options
    do while (arg_idx <= cmd%num_tokens)
      if (cmd%tokens(arg_idx)(1:1) == '-') then
        select case(trim(cmd%tokens(arg_idx)))
        case('-l')
          list_mode = .true.
          arg_idx = arg_idx + 1
        case('-n')
          no_line_numbers = .true.
          arg_idx = arg_idx + 1
        case('-r')
          reverse_order = .true.
          arg_idx = arg_idx + 1
        case('-e')
          ! Next argument is editor name
          if (arg_idx + 1 > cmd%num_tokens) then
            write(error_unit, '(a)') 'fc: -e requires an argument'
            shell%last_exit_status = 1
            return
          end if
          editor = trim(cmd%tokens(arg_idx + 1))
          arg_idx = arg_idx + 2
        case('-s')
          subst_mode = .true.
          arg_idx = arg_idx + 1
        case default
          write(error_unit, '(a)') 'fc: invalid option: ' // trim(cmd%tokens(arg_idx))
          shell%last_exit_status = 1
          return
        end select
      else
        exit  ! Done with options
      end if
    end do

    ! Parse range arguments [first] [last] (skip for -s mode)
    if (.not. subst_mode .and. arg_idx <= cmd%num_tokens) then
      ! Parse first
      if (cmd%tokens(arg_idx)(1:1) == '-') then
        ! Negative offset from end
        read(cmd%tokens(arg_idx), *, iostat=iostat) first
        if (iostat == 0) first = history_count + first + 1
      else
        ! Try to parse as number
        read(cmd%tokens(arg_idx), *, iostat=iostat) first
        if (iostat /= 0) then
          ! Not a number, search for command starting with this string
          first = find_history_by_prefix(trim(cmd%tokens(arg_idx)))
          if (first < 0) then
            write(error_unit, '(a)') 'fc: ' // trim(cmd%tokens(arg_idx)) // ': event not found'
            shell%last_exit_status = 1
            return
          end if
        end if
      end if
      arg_idx = arg_idx + 1
    end if

    if (.not. subst_mode .and. arg_idx <= cmd%num_tokens) then
      ! Parse last
      if (cmd%tokens(arg_idx)(1:1) == '-') then
        read(cmd%tokens(arg_idx), *, iostat=iostat) last
        if (iostat == 0) last = history_count + last + 1
      else
        read(cmd%tokens(arg_idx), *, iostat=iostat) last
        if (iostat /= 0) then
          last = find_history_by_prefix(trim(cmd%tokens(arg_idx)))
          if (last < 0) then
            write(error_unit, '(a)') 'fc: ' // trim(cmd%tokens(arg_idx)) // ': event not found'
            shell%last_exit_status = 1
            return
          end if
        end if
      end if
    end if

    ! Set defaults if not specified
    if (first < 0) then
      if (list_mode) then
        first = max(1, history_count - 15)  ! Show last 16 commands by default
      else if (subst_mode) then
        first = max(1, history_count - 1)  ! Get command before fc itself
      else
        first = history_count  ! Edit last command
      end if
    end if

    if (last < 0) then
      if (list_mode) then
        last = history_count
      else
        last = first  ! Edit single command
      end if
    end if

    ! Validate range
    if (first < 1) first = 1
    if (last > history_count) last = history_count
    if (first > last .and. .not. reverse_order) then
      ! Swap if needed
      i = first
      first = last
      last = i
    end if

    ! Handle -s (substitution mode)
    if (subst_mode) then
      ! fc -s [old=new] [command]
      ! Parse old=new substitution
      old_str = ''
      new_str = ''

      if (arg_idx <= cmd%num_tokens) then
        eq_pos = index(cmd%tokens(arg_idx), '=')
        if (eq_pos > 0) then
          old_str = cmd%tokens(arg_idx)(:eq_pos-1)
          new_str = cmd%tokens(arg_idx)(eq_pos+1:)
          arg_idx = arg_idx + 1
        end if
      end if

      ! Get the command to re-execute
      call get_history_line(first, line, found)
      if (.not. found) then
        write(error_unit, '(a)') 'fc: history entry not found'
        shell%last_exit_status = 1
        return
      end if

      ! Perform substitution if requested
      if (len_trim(old_str) > 0) then
        i = index(line, trim(old_str))
        if (i > 0) then
          line = line(:i-1) // trim(new_str) // line(i+len_trim(old_str):)
        else
          write(error_unit, '(a)') 'fc: substitution failed'
          shell%last_exit_status = 1
          return
        end if
      end if

      ! Print the command being executed
      write(output_unit, '(a)') trim(line)

      ! Execute using c_system
      shell%last_exit_status = c_system(trim(line) // c_null_char)

      return
    end if

    ! Handle -l (list mode)
    if (list_mode) then
      if (reverse_order) then
        do i = last, first, -1
          call get_history_line(i, line, found)
          if (found) then
            if (no_line_numbers) then
              write(output_unit, '(a)') trim(line)
            else
              write(output_unit, '(i5,2x,a)') i, trim(line)
            end if
          end if
        end do
      else
        do i = first, last
          call get_history_line(i, line, found)
          if (found) then
            if (no_line_numbers) then
              write(output_unit, '(a)') trim(line)
            else
              write(output_unit, '(i5,2x,a)') i, trim(line)
            end if
          end if
        end do
      end if
      shell%last_exit_status = 0
      return
    end if

    ! Handle edit mode (default)
    ! Determine editor to use
    if (len_trim(editor) == 0) then
      editor = get_environment_var('FCEDIT')
      if (len_trim(editor) == 0) then
        editor = get_environment_var('EDITOR')
        if (len_trim(editor) == 0) then
          editor = 'vi'  ! Default to vi
        end if
      end if
    end if

    ! Create temporary file with commands to edit
    write(tmpfile, '(a,i15)') '/tmp/fortsh_fc_', c_getpid()

    open(newunit=tmp_unit, file=trim(tmpfile), status='replace', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fc: failed to create temporary file'
      shell%last_exit_status = 1
      return
    end if

    ! Write commands to temp file
    do i = first, last
      call get_history_line(i, line, found)
      if (found) then
        write(tmp_unit, '(a)') trim(line)
      end if
    end do
    close(tmp_unit)

    ! Launch editor
    write(edit_cmd, '(a,1x,a)') trim(editor), trim(tmpfile)
    i = c_system(trim(edit_cmd) // c_null_char)

    ! Read back edited commands and execute them
    open(newunit=tmp_unit, file=trim(tmpfile), status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fc: failed to read edited file'
      shell%last_exit_status = 1
      return
    end if

    do
      read(tmp_unit, '(a)', iostat=iostat) line
      if (iostat /= 0) exit

      if (len_trim(line) == 0 .or. line(1:1) == '#') cycle

      ! Execute the line using c_system
      shell%last_exit_status = c_system(trim(line) // c_null_char)
    end do

    close(tmp_unit)

    ! Clean up temporary file
    call unlink_file(trim(tmpfile))

    shell%last_exit_status = 0
  end subroutine

  function find_history_by_prefix(prefix) result(hist_index)
    character(len=*), intent(in) :: prefix
    integer :: hist_index
    character(len=1024) :: line
    logical :: found
    integer :: i, count, pos

    count = get_history_count()

    ! Search backwards from most recent
    do i = count, 1, -1
      call get_history_line(i, line, found)
      if (found) then
        pos = index(line, trim(prefix))
        if (pos == 1) then
          hist_index = i
          return
        end if
      end if
    end do

    hist_index = -1  ! Not found
  end function

  subroutine unlink_file(filepath)
    character(len=*), intent(in) :: filepath
    integer :: iostat

    ! Use Fortran intrinsic to delete file
    open(newunit=iostat, file=trim(filepath), status='old')
    if (iostat >= 0) then
      close(iostat, status='delete')
    end if
  end subroutine

  ! ===========================================================================
  ! PROGRAMMABLE COMPLETION BUILTINS
  ! ===========================================================================

  subroutine builtin_complete(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    character(len=256) :: arg
    type(completion_spec_t) :: spec
    logical :: remove_flag, list_flag, print_flag
    character(len=256) :: word_list_arg, function_arg, action_arg
    character(len=256) :: option_arg, prefix_arg, suffix_arg, filter_arg
    character(len=256) :: command_names(50)
    integer :: num_commands

    ! Initialize spec
    spec%is_active = .false.
    spec%command = ''
    spec%word_list_count = 0
    spec%function_name = ''
    spec%filter_pattern = ''
    spec%prefix = ''
    spec%suffix = ''
    spec%use_default = .false.
    spec%use_dirnames = .false.
    spec%use_filenames = .false.
    spec%nospace = .false.
    spec%plusdirs = .false.
    spec%nosort = .false.
    spec%builtin_alias = .false.
    spec%builtin_command = .false.
    spec%builtin_directory = .false.
    spec%builtin_file = .false.
    spec%builtin_function = .false.
    spec%builtin_hostname = .false.
    spec%builtin_variable = .false.
    spec%builtin_user = .false.
    spec%builtin_group = .false.
    spec%builtin_service = .false.
    spec%builtin_export = .false.
    spec%builtin_keyword = .false.
    spec%builtin_builtin = .false.

    remove_flag = .false.
    list_flag = .false.
    print_flag = .false.
    word_list_arg = ''
    function_arg = ''
    action_arg = ''
    option_arg = ''
    prefix_arg = ''
    suffix_arg = ''
    filter_arg = ''
    num_commands = 0

    ! Parse arguments
    i = 2
    do while (i <= cmd%num_tokens)
      arg = trim(cmd%tokens(i))

      if (arg == '-r') then
        ! Remove completion spec
        remove_flag = .true.
        i = i + 1
      else if (arg == '-p' .or. arg == '-l') then
        ! List/print completion specs
        list_flag = .true.
        i = i + 1
      else if (arg == '-W') then
        ! Word list
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          word_list_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -W requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg == '-F') then
        ! Function name
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          function_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -F requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg == '-A') then
        ! Built-in action
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          action_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -A requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg == '-o') then
        ! Option
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          option_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -o requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg == '-P') then
        ! Prefix
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          prefix_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -P requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg == '-S') then
        ! Suffix
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          suffix_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -S requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg == '-X') then
        ! Filter pattern
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          filter_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'complete: -X requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg(1:1) /= '-') then
        ! Command name
        num_commands = num_commands + 1
        if (num_commands <= 50) then
          command_names(num_commands) = trim(arg)
        end if
        i = i + 1
      else
        write(error_unit, '(a)') 'complete: invalid option: ' // trim(arg)
        shell%last_exit_status = 2
        return
      end if
    end do

    ! Handle list flag
    if (list_flag) then
      call list_completion_specs()
      shell%last_exit_status = 0
      return
    end if

    ! Handle remove flag
    if (remove_flag) then
      if (num_commands == 0) then
        ! Remove all specs
        call clear_completion_specs()
      else
        ! Remove specific specs
        do i = 1, num_commands
          if (.not. remove_completion_spec(trim(command_names(i)))) then
            shell%last_exit_status = 1
          end if
        end do
      end if
      shell%last_exit_status = 0
      return
    end if

    ! Build completion spec
    if (len_trim(word_list_arg) > 0) then
      call parse_word_list(word_list_arg, spec)
    end if

    if (len_trim(function_arg) > 0) then
      spec%function_name = function_arg
    end if

    if (len_trim(action_arg) > 0) then
      select case(trim(action_arg))
      case('alias')
        spec%builtin_alias = .true.
      case('command')
        spec%builtin_command = .true.
      case('directory')
        spec%builtin_directory = .true.
      case('file')
        spec%builtin_file = .true.
      case('function')
        spec%builtin_function = .true.
      case('hostname')
        spec%builtin_hostname = .true.
      case('variable')
        spec%builtin_variable = .true.
      case('user')
        spec%builtin_user = .true.
      case('group')
        spec%builtin_group = .true.
      case('service')
        spec%builtin_service = .true.
      case('export')
        spec%builtin_export = .true.
      case('keyword')
        spec%builtin_keyword = .true.
      case('builtin')
        spec%builtin_builtin = .true.
      case default
        write(error_unit, '(a)') 'complete: invalid action: ' // trim(action_arg)
        shell%last_exit_status = 1
        return
      end select
    end if

    if (len_trim(option_arg) > 0) then
      select case(trim(option_arg))
      case('default')
        spec%use_default = .true.
      case('dirnames')
        spec%use_dirnames = .true.
      case('filenames')
        spec%use_filenames = .true.
      case('nospace')
        spec%nospace = .true.
      case('plusdirs')
        spec%plusdirs = .true.
      case('nosort')
        spec%nosort = .true.
      case default
        write(error_unit, '(a)') 'complete: invalid option: ' // trim(option_arg)
        shell%last_exit_status = 1
        return
      end select
    end if

    if (len_trim(prefix_arg) > 0) then
      spec%prefix = prefix_arg
    end if

    if (len_trim(suffix_arg) > 0) then
      spec%suffix = suffix_arg
    end if

    if (len_trim(filter_arg) > 0) then
      spec%filter_pattern = filter_arg
    end if

    ! Register spec for each command
    if (num_commands == 0) then
      write(error_unit, '(a)') 'complete: no command names specified'
      shell%last_exit_status = 1
      return
    end if

    do i = 1, num_commands
      spec%command = trim(command_names(i))
      if (.not. register_completion_spec(spec)) then
        write(error_unit, '(a)') 'complete: failed to register spec for ' // trim(command_names(i))
        shell%last_exit_status = 1
        return
      end if
    end do

    shell%last_exit_status = 0
  end subroutine builtin_complete

  subroutine builtin_compgen(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=256) :: word_list_arg, prefix_arg
    integer :: i
    character(len=256) :: arg
    type(completion_spec_t) :: spec
    character(len=256) :: completions(MAX_COMPLETIONS)
    integer :: completion_count

    ! compgen is used for testing completion specs
    ! Syntax: compgen -W "word1 word2 word3" [prefix]

    word_list_arg = ''
    prefix_arg = ''

    ! Parse arguments
    i = 2
    do while (i <= cmd%num_tokens)
      arg = trim(cmd%tokens(i))

      if (arg == '-W') then
        ! Word list
        if (i + 1 <= cmd%num_tokens) then
          i = i + 1
          word_list_arg = trim(cmd%tokens(i))
          i = i + 1
        else
          write(error_unit, '(a)') 'compgen: -W requires an argument'
          shell%last_exit_status = 1
          return
        end if
      else if (arg(1:1) /= '-') then
        ! Prefix to match
        prefix_arg = trim(arg)
        i = i + 1
      else
        write(error_unit, '(a)') 'compgen: invalid option: ' // trim(arg)
        shell%last_exit_status = 2
        return
      end if
    end do

    ! Build a temporary spec for testing
    spec%is_active = .true.
    spec%word_list_count = 0
    spec%function_name = ''
    spec%filter_pattern = ''
    spec%prefix = ''
    spec%suffix = ''
    spec%use_default = .false.
    spec%use_dirnames = .false.
    spec%use_filenames = .false.
    spec%nospace = .false.
    spec%plusdirs = .false.
    spec%nosort = .false.

    if (len_trim(word_list_arg) > 0) then
      call parse_word_list(word_list_arg, spec)
    end if

    ! Generate completions
    call generate_word_list_completions(spec, prefix_arg, completions, completion_count)

    ! Print completions (one per line)
    do i = 1, completion_count
      write(output_unit, '(a)') trim(completions(i))
    end do

    if (completion_count > 0) then
      shell%last_exit_status = 0
    else
      shell%last_exit_status = 1
    end if
  end subroutine builtin_compgen

  ! ===========================================================================
  ! Directory History Functions (Fish-style prevd/nextd)
  ! ===========================================================================

  ! Add directory to history
  subroutine add_to_dir_history(shell, dir)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: dir
    integer :: i

    ! Don't add if it's the same as the last entry (avoid consecutive duplicates)
    if (shell%dir_history_size > 0) then
      if (trim(shell%dir_history(shell%dir_history_size)) == trim(dir)) then
        ! Duplicate of last entry, just update index to point here
        shell%dir_history_index = shell%dir_history_size
        return
      end if
    end if

    ! If we're browsing history (not at the end), truncate everything after current position
    ! This implements browser-style history: go back, then cd somewhere = discard forward history
    if (shell%dir_history_index > 0 .and. shell%dir_history_index < shell%dir_history_size) then
      shell%dir_history_size = shell%dir_history_index
    end if

    ! Add new directory
    if (shell%dir_history_size < 50) then
      shell%dir_history_size = shell%dir_history_size + 1
    else
      ! Shift history left (circular buffer)
      do i = 1, 49
        shell%dir_history(i) = shell%dir_history(i + 1)
      end do
    end if

    shell%dir_history(shell%dir_history_size) = trim(dir)
    ! Set index to point at the newly added directory (current position)
    shell%dir_history_index = shell%dir_history_size
  end subroutine add_to_dir_history

  ! prevd builtin - go to previous directory in history
  subroutine builtin_prevd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

    ! Check if we can go back (must be at index > 1)
    if (shell%dir_history_index <= 1) then
      write(error_unit, '(a)') 'prevd: no previous directory'
      shell%last_exit_status = 1
      return
    end if

    ! Move back in history
    shell%dir_history_index = shell%dir_history_index - 1

    if (change_directory(trim(shell%dir_history(shell%dir_history_index)))) then
      shell%oldpwd = shell%cwd
      shell%cwd = get_current_directory()
      write(output_unit, '(a)') trim(shell%cwd)
      shell%last_exit_status = 0
    else
      write(error_unit, '(a)') 'prevd: cannot access directory'
      shell%dir_history_index = shell%dir_history_index + 1
      shell%last_exit_status = 1
    end if
  end subroutine builtin_prevd

  ! nextd builtin - go to next directory in history
  subroutine builtin_nextd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

    ! Check if we can go forward (must be at index < size)
    if (shell%dir_history_index >= shell%dir_history_size) then
      write(error_unit, '(a)') 'nextd: no next directory'
      shell%last_exit_status = 1
      return
    end if

    ! Move forward in history
    shell%dir_history_index = shell%dir_history_index + 1

    if (change_directory(trim(shell%dir_history(shell%dir_history_index)))) then
      shell%oldpwd = shell%cwd
      shell%cwd = get_current_directory()
      write(output_unit, '(a)') trim(shell%cwd)
      shell%last_exit_status = 0
    else
      write(error_unit, '(a)') 'nextd: cannot access directory'
      shell%dir_history_index = shell%dir_history_index - 1
      shell%last_exit_status = 1
    end if
  end subroutine builtin_nextd

  ! dirh builtin - show directory history
  subroutine builtin_dirh(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i

    if (.false.) print *, cmd%num_tokens  ! Silence unused warning

    if (shell%dir_history_size == 0) then
      write(output_unit, '(a)') 'Directory history is empty'
      shell%last_exit_status = 0
      return
    end if

    write(output_unit, '(a)') 'Directory history:'
    do i = 1, shell%dir_history_size
      if (i == shell%dir_history_index) then
        ! Highlight current position
        write(output_unit, '(i3,a,a)') i, ' * ', trim(shell%dir_history(i))
      else
        write(output_unit, '(i3,a,a)') i, '   ', trim(shell%dir_history(i))
      end if
    end do

    shell%last_exit_status = 0
  end subroutine builtin_dirh

  ! Execute EXIT trap inline (to avoid circular dependency with executor module)
  subroutine execute_exit_trap_inline(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: trap_cmd
    integer :: saved_status
    type(pipeline_t) :: trap_pipeline
    integer :: i

    ! Save trap command and clear
    trap_cmd = shell%pending_trap_command
    shell%pending_trap_command = ''
    shell%pending_trap_signal = 0

    ! Save exit status (traps don't affect $?)
    saved_status = shell%last_exit_status

    ! Set flag to prevent recursive traps
    shell%executing_trap = .true.

    ! Parse trap command
    call parse_pipeline(trim(trap_cmd), trap_pipeline)

    ! Execute it in current shell context (inline execution using c_system)
    ! We use c_system instead of execute_pipeline to avoid circular dependency
    if (len_trim(trap_cmd) > 0) then
      i = c_system(trim(trap_cmd) // c_null_char)
    end if

    ! Clean up pipeline allocations
    if (allocated(trap_pipeline%commands)) then
      do i = 1, trap_pipeline%num_commands
        if (allocated(trap_pipeline%commands(i)%tokens)) deallocate(trap_pipeline%commands(i)%tokens)
        if (allocated(trap_pipeline%commands(i)%input_file)) deallocate(trap_pipeline%commands(i)%input_file)
        if (allocated(trap_pipeline%commands(i)%output_file)) deallocate(trap_pipeline%commands(i)%output_file)
        if (allocated(trap_pipeline%commands(i)%error_file)) deallocate(trap_pipeline%commands(i)%error_file)
        if (allocated(trap_pipeline%commands(i)%heredoc_delimiter)) deallocate(trap_pipeline%commands(i)%heredoc_delimiter)
        if (allocated(trap_pipeline%commands(i)%heredoc_content)) deallocate(trap_pipeline%commands(i)%heredoc_content)
        if (allocated(trap_pipeline%commands(i)%here_string)) deallocate(trap_pipeline%commands(i)%here_string)
      end do
      deallocate(trap_pipeline%commands)
    end if

    ! Clear flag
    shell%executing_trap = .false.

    ! Restore exit status (traps don't affect $?)
    shell%last_exit_status = saved_status
  end subroutine execute_exit_trap_inline


end module builtins
