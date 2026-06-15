! ==============================================================================
! Main Program: Fortran Shell (Fortsh)
! ==============================================================================
program fortran_shell
  use shell_types
  use system_interface
  use signal_handler
  use signal_handling
  use parser, only: convert_backticks_to_dollar_paren, has_unclosed_quote, ends_with_continuation_backslash, &
                    needs_compound_continuation, remove_line_continuations, &
                    get_heredoc_delimiter

  use substitution, only: cleanup_all_fifos, wait_and_cleanup_proc_substs
  use grammar_parser  ! New grammar-aware parser
  use ast_executor, only: execute_ast, register_trap_evaluator
  use command_tree    ! Command tree for new parser
  use executor, only: init_completion_executor, init_control_flow_callbacks
  use job_control
  use readline
  use shell_config
  use variables, only: get_shell_variable, set_shell_variable
  use aliases
  use shell_options
  use performance
  use prompt_formatting
  use command_capture_callback, only: init_command_capture  ! For command substitution
  use builtins, only: init_builtins  ! Initialize builtin function pointers
  use coprocess, only: init_coprocess_registry
  use version, only: print_version, print_help
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  use iso_c_binding, only: c_int
  implicit none

  type(shell_state_t), allocatable :: shell
  character(len=16384) :: input_line, proc_subst_line
  character(len=:), allocatable :: expanded_line, history_expanded
  character(len=MAX_VAR_VALUE_LEN) :: prompt_str  ! Fixed-length to avoid LLVM Flang heap corruption
  character(len=MAX_VAR_VALUE_LEN) :: rprompt_str ! Right-side prompt (like zsh RPROMPT)
  character(len=:), allocatable :: rprompt_value  ! RPROMPT variable value
  integer :: iostat, num_args
  character(len=MAX_PATH_LEN) :: arg1, command_string
  logical :: execute_command_string, execute_script_file, syntax_check_only
  character(len=:), allocatable :: script_file
  ! Command duration tracking
  integer :: cmd_start_time, cmd_end_time, cmd_duration_ms, clock_rate
  real :: cmd_duration_sec
  ! New parser infrastructure
  type(command_node_t), pointer :: ast_root
  integer :: exit_code
  character(len=:), allocatable :: converted_line
  ! Terminal resize support
  character(len=16) :: cols_str, rows_str
  logical :: success

  ! macOS: set S_CTTYREF on controlling terminal to prevent PTY output loss
  ! (macOS kernel discards slave PTY buffer on child exit without this flag)
  interface
    subroutine fortsh_set_cttyref() bind(C, name="fortsh_set_cttyref")
    end subroutine
  end interface
  call fortsh_set_cttyref()

  ! Initialize performance monitoring
  call init_performance_monitoring()

  ! Silence unused function warning for convert_escape_sequences (kept for future use)
  if (.false.) input_line = convert_escape_sequences('')

  ! Allocate shell to avoid large stack allocation on macOS
  allocate(shell)

  ! Initialize these BEFORE initialize_shell since it uses them to check interactivity
  execute_command_string = .false.
  execute_script_file = .false.
  syntax_check_only = .false.

  ! Check for command-line arguments FIRST to detect non-interactive modes
  num_args = command_argument_count()

  ! Handle command-line arguments for script execution
  if (num_args > 0) then
    call get_command_argument(1, arg1)

    ! Check for --version or -v flag
    if (trim(arg1) == '--version' .or. trim(arg1) == '-v') then
      call print_version()
      call c_exit(0_c_int)
    end if

    ! Check for --help or -h flag
    if (trim(arg1) == '--help' .or. trim(arg1) == '-h') then
      call print_help()
      call c_exit(0_c_int)
    end if

    ! Check for -n flag (syntax check only, no execution)
    if (trim(arg1) == '-n') then
      syntax_check_only = .true.
      execute_script_file = .true.
      ! If there's a script file after -n, use it
      if (num_args >= 2) then
        if (.not. allocated(script_file)) allocate(character(len=MAX_PATH_LEN) :: script_file)
        call get_command_argument(2, script_file)
        execute_script_file = .true.
      end if
    ! Check for -c flag (execute command string)
    else if (trim(arg1) == '-c') then
      if (num_args >= 2) then
        call get_command_argument(2, command_string)
        execute_command_string = .true.
        ! Note: Additional arguments after command string will be processed
        ! after shell initialization (to set $0 and positional params)
      else
        write(error_unit, '(a)') 'fortsh: -c: option requires an argument'
        stop 2
      end if
    ! Check if it's not a flag (assume it's a script file)
    else if (arg1(1:1) /= '-') then
      script_file = trim(arg1)
      execute_script_file = .true.
    end if
  end if

  ! Initialize shell (reads execute_command_string/execute_script_file to set is_interactive)
  call initialize_shell(shell)

  ! Set option_noexec if -n flag was used
  if (syntax_check_only) then
    shell%option_noexec = .true.
  end if

  ! Initialize builtin function pointers (breaks circular dependency)
  call init_builtins()

  ! Initialize control flow callbacks (breaks circular dependency)
  call init_control_flow_callbacks()

  ! Initialize command history (needed even in non-interactive mode)
  call init_history()

  ! Initialize signal handling module
  call init_signal_handling(shell)

  ! Register AST evaluator for trap dispatch (breaks executor<->ast_executor circular dep)
  call register_trap_evaluator()

  ! Initialize command capture callback (for command substitution)
  call init_command_capture()

  ! Initialize completion function executor callback (for -F completion)
  call init_completion_executor()

  ! Setup signal handlers if interactive
  if (shell%is_interactive) then
    call setup_signal_handlers()

    ! Welcome message for interactive mode
    write(output_unit, '(a)') 'Welcome to Fortran Shell (fortsh)!'
    write(output_unit, '(a)') 'Type "help" for available commands or "exit" to quit.'
    write(output_unit, '(a)') ''

    ! Load configuration file
    call load_config_file(shell)

    ! Set HISTCONTROL for history management
    call set_histcontrol(shell%histcontrol)

    ! Check HISTFILE env var override before loading
    block
      character(len=:), allocatable :: histfile_env
      histfile_env = get_environment_var('HISTFILE')
      if (len(histfile_env) > 0) then
        shell%histfile = histfile_env
      end if
    end block

    ! Load command history from file (skip if /dev/null)
    if (len_trim(shell%histfile) > 0 .and. trim(shell%histfile) /= '/dev/null') then
      call load_history_from_file(trim(shell%histfile), shell%histsize)
    end if
  end if

  ! Execute command string if -c was specified
  if (execute_command_string) then
    ! Set LINENO to 1 for -c commands (POSIX: lines start at 1)
    shell%current_line_number = 1
    ! Mark that we're in command mode (for $- flag)
    shell%in_command_mode = .true.

    ! POSIX: Handle additional arguments after -c 'command'
    ! For -c 'command' arg0 arg1 arg2: arg0 becomes $0, arg1 arg2 become $1 $2
    if (num_args >= 3) then
      block
        character(len=MAX_PATH_LEN) :: c_arg
        integer :: c_idx
        ! Third argument becomes $0
        call get_command_argument(3, c_arg)
        shell%shell_name = trim(c_arg)
        ! Remaining arguments become positional parameters $1, $2, ...
        if (num_args >= 4) then
          shell%num_positional = num_args - 3
          if (.not. allocated(shell%positional_params)) then
            allocate(shell%positional_params(shell%num_positional))
            shell%positional_params_capacity = shell%num_positional
          else if (shell%positional_params_capacity < shell%num_positional) then
            deallocate(shell%positional_params)
            allocate(shell%positional_params(shell%num_positional))
            shell%positional_params_capacity = shell%num_positional
          end if
          do c_idx = 4, num_args
            call get_command_argument(c_idx, c_arg)
            shell%positional_params(c_idx - 3)%str = trim(c_arg)
          end do
        end if
      end block
    end if

    ! Check if string contains heredoc outside quotes and pre-process it
    if (has_heredoc_outside_quotes(command_string)) then
      ! Pre-process heredocs before parsing
      command_string = preprocess_heredocs_for_c(command_string, shell)
      ! write(error_unit, '(A,A)') 'DEBUG: After preprocess, command_string=', trim(command_string)
    end if

    ! Handle line continuation (backslash-newline)
    command_string = remove_line_continuations(command_string)
    ! POSIX set -v: Print input line before execution
    if (shell%option_verbose) then
      write(error_unit, '(A)') trim(command_string)
    end if

    ! Parse to AST and execute (process substitution is handled during
    ! word expansion at execution time, not pre-processing)
    converted_line = convert_backticks_to_dollar_paren(trim(command_string))
    ast_root => parse_command_line(converted_line)
    if (associated(ast_root)) then
      shell%current_command = converted_line
      exit_code = execute_ast(ast_root, shell)
      shell%last_exit_status = exit_code
      call destroy_command_node(ast_root)
      ! Handle source commands that were the last/only command in -c string
      if (shell%should_source) then
        call process_source_file(shell)
      end if
    else if (last_parse_had_error) then
      ! Parse error occurred (not just empty command)
      shell%last_exit_status = 2
    end if

    ! Process any sourced files queued by the command
    if (shell%should_source) then
      call process_source_file(shell)
    end if

    ! Execute EXIT trap if one is set (before exiting)
    call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT
    call wait_and_cleanup_proc_substs(shell)
    call cleanup_all_fifos(shell)

    ! Exit with last command's exit status
    call c_exit(shell%last_exit_status)
  end if

  ! Execute script file if specified
  if (execute_script_file) then
    shell%source_file = script_file
    shell%should_source = .true.
    call process_source_file(shell)

    ! Execute EXIT trap if one is set (before exiting)
    call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT

    ! Exit with last command's exit status (don't print Goodbye for scripts)
    if (perf_monitoring_enabled) then
      call print_performance_stats()
    end if
    call cleanup_performance_monitoring()
    call wait_and_cleanup_proc_substs(shell)
    call cleanup_all_fifos(shell)
    call c_exit(shell%last_exit_status)
  end if

  ! Main REPL loop
  do while (shell%running)
    ! Check for terminal resize (SIGWINCH)
    if (g_terminal_resized) then
      g_terminal_resized = .false.
      ! Re-query terminal dimensions
      success = get_terminal_size(shell%term_rows, shell%term_cols)
      ! Update both environment variables (for child processes) and shell variables (for $COLUMNS/$LINES)
      write(cols_str, '(I0)') shell%term_cols
      write(rows_str, '(I0)') shell%term_rows
      success = set_environment_var('COLUMNS', trim(cols_str))
      success = set_environment_var('LINES', trim(rows_str))
      call set_shell_variable(shell, 'COLUMNS', trim(cols_str))
      call set_shell_variable(shell, 'LINES', trim(rows_str))
    end if

    ! Update job status
    if (shell%is_interactive) then
      call update_job_status(shell)
      call notify_job_status(shell)
    end if

    ! Process sourced files
    if (shell%should_source) then
      call process_source_file(shell)
      cycle
    end if

    ! Read input with enhanced readline (includes prompt only if interactive)
    if (shell%is_interactive) then
      ! Use safe_expand_prompt to avoid LLVM Flang heap corruption
      call safe_expand_prompt(shell%ps1, shell, shell%ps1_len, prompt_str)

      ! Get RPROMPT if set (zsh-style right prompt). Always pass it as the
      ! readline argument — readline owns placement as a separate re-emit layer
      ! for every prompt shape (AR-87). The old multi-line ESC[nG embedding went
      ! stale on resize and was stripped by the redraw (NICE-RPROMPT2).
      rprompt_value = get_shell_variable(shell, 'RPROMPT')
      if (len_trim(rprompt_value) > 0) then
        call safe_expand_prompt(rprompt_value, shell, len(rprompt_value), rprompt_str)
        call readline_enhanced(trim(prompt_str), input_line, iostat, trim(rprompt_str), keep_raw=.true., shell=shell)
      else
        call readline_enhanced(trim(prompt_str), input_line, iostat, keep_raw=.true., shell=shell)
      end if
    else
      read(input_unit, '(a)', iostat=iostat) input_line
    end if

    ! Always re-query terminal size after readline returns — readline's
    ! SIGWINCH handler clears g_terminal_resized before we get here, so
    ! we can't rely on the flag. This is cheap (one ioctl) and ensures
    ! $COLUMNS/$LINES are correct for the command about to execute.
    block
      integer :: new_rows, new_cols
      success = get_terminal_size(new_rows, new_cols)
      if (success .and. (new_cols /= shell%term_cols .or. new_rows /= shell%term_rows)) then
        shell%term_cols = new_cols
        shell%term_rows = new_rows
        write(cols_str, '(I0)') shell%term_cols
        write(rows_str, '(I0)') shell%term_rows
        success = set_environment_var('COLUMNS', trim(cols_str))
        success = set_environment_var('LINES', trim(rows_str))
        call set_shell_variable(shell, 'COLUMNS', trim(cols_str))
        call set_shell_variable(shell, 'LINES', trim(rows_str))
      end if
    end block
    if (g_terminal_resized) then
      g_terminal_resized = .false.
    end if

    ! Check for EOF (Ctrl-D)
    if (iostat /= 0) then
      ! Only print newline in interactive mode for clean exit
      if (shell%is_interactive) then
        write(output_unit, '(a)') ''
      end if
      exit
    end if

    ! Skip empty lines
    if (len_trim(input_line) == 0) cycle

    ! Check for unclosed quotes or backslash continuation and continue reading
    do while (has_unclosed_quote(input_line) .or. ends_with_continuation_backslash(input_line))
      if (shell%is_interactive) then
        prompt_str = expand_prompt(shell%ps2, shell, shell%ps2_len)
        call readline_enhanced(prompt_str, proc_subst_line, iostat, keep_raw=.true., shell=shell)
      else
        ! Non-interactive: just read next line
        read(input_unit, '(a)', iostat=iostat) proc_subst_line
      end if

      ! Check for EOF during continuation
      if (iostat /= 0) then
        ! Only print newline in interactive mode for clean exit
        if (shell%is_interactive) then
          write(output_unit, '(a)') ''
        end if
        exit
      end if

      ! Append the continuation line with a newline character
      input_line = trim(input_line) // char(10) // trim(proc_subst_line)
    end do

    ! Handle line continuation (backslash-newline)
    input_line = remove_line_continuations(input_line)

    ! Log: about to check compound continuation
    ! Check for unclosed compound commands (if/fi, do/done, case/esac)
    do while (needs_compound_continuation(input_line))
      if (shell%is_interactive) then
        prompt_str = expand_prompt(shell%ps2, shell, shell%ps2_len)
        call readline_enhanced(prompt_str, proc_subst_line, iostat, keep_raw=.true., shell=shell)
      else
        ! Non-interactive: just read next line
        read(input_unit, '(a)', iostat=iostat) proc_subst_line
      end if

      ! Check for EOF during compound continuation
      if (iostat /= 0) then
        if (shell%is_interactive) then
          write(output_unit, '(a)') ''
        end if
        exit
      end if

      ! Append the continuation line with a newline character
      input_line = trim(input_line) // char(10) // trim(proc_subst_line)
    end do

    ! Pre-process heredocs in accumulated compound commands
    ! The compound continuation loop may have collected heredoc content inline.
    ! Extract it and store as pending so the executor doesn't try to read from stdin.
    if (has_heredoc_outside_quotes(input_line) .and. index(input_line, char(10)) > 0) then
      input_line = preprocess_heredocs_for_c(input_line, shell)
    end if

    ! Restore terminal from raw mode (readline keeps raw for continuation prompts)
    if (shell%is_interactive) call restore_readline_terminal()

    ! Expand history (!!, !n, !string, etc.) if needed
    if (needs_history_expansion(input_line)) then
      history_expanded = expand_history(input_line)
      ! Print expanded command if interactive (like bash does)
      if (shell%is_interactive) then
        write(output_unit, '(a)') trim(history_expanded)
      end if
      ! Add the EXPANDED command to history (not the original !!)
      call add_to_history(history_expanded)
      ! Now expand aliases on the history-expanded line
      call expand_alias(shell, trim(history_expanded), expanded_line)
    else
      ! No history expansion needed, add original line to history
      call add_to_history(input_line)
      ! Then expand aliases
      call expand_alias(shell, trim(input_line), expanded_line)
    end if

    ! POSIX set -v: Print input line before execution
    if (shell%option_verbose) then
      write(error_unit, '(A)') trim(expanded_line)
    end if

    ! Parse and execute via AST (process substitution handled at execution time)
    call system_clock(cmd_start_time, clock_rate)

    converted_line = convert_backticks_to_dollar_paren(expanded_line)
    ast_root => parse_command_line(converted_line)
    if (associated(ast_root)) then
      ! Store current command for job descriptions
      shell%current_command = converted_line

      ! POSIX: In noexec mode, parse but don't execute (ignored in interactive shells)
      if (shell%option_noexec .and. .not. shell%is_interactive) then
        shell%last_exit_status = 0
        exit_code = 0
      else
        exit_code = execute_ast(ast_root, shell)
        shell%last_exit_status = exit_code
      end if

      ! Reap finished process substitution children and unlink their FIFOs
      call wait_and_cleanup_proc_substs(shell)

      ! Flush output after command execution — flang-new buffers Fortran I/O
      ! and won't flush to PTY until the buffer fills or process exits.
      ! Without this, interactive output appears delayed or missing.
      flush(output_unit)
      flush(error_unit)

      call destroy_command_node(ast_root)

      ! Calculate and display duration if > 1 second
      call system_clock(cmd_end_time)
      cmd_duration_ms = (cmd_end_time - cmd_start_time) * 1000 / clock_rate
      cmd_duration_sec = real(cmd_duration_ms) / 1000.0

      if (shell%is_interactive .and. cmd_duration_sec >= 1.0) then
        if (shell%term_supports_color) then
          write(output_unit, '(a,f0.1,a)') char(27) // '[2m' // 'Executed in ', &
                                           cmd_duration_sec, 's' // char(27) // '[0m'
        else
          write(output_unit, '(a,f0.1,a)') 'Executed in ', cmd_duration_sec, 's'
        end if
      end if

      ! Update terminal title after command execution
      if (shell%is_interactive .and. shell%term_supports_color) then
        call set_terminal_title(trim(shell%username) // '@' // trim(shell%hostname) // ': ' // trim(shell%cwd))
      end if

      ! Increment command number for next prompt
      shell%command_number = shell%command_number + 1
      call increment_prompt_history()
    else if (last_parse_had_error) then
      shell%last_exit_status = 2
    end if
  end do

  ! Execute EXIT trap if one is set
  call execute_trap_for_signal(shell, 0)  ! 0 is TRAP_EXIT

  ! Save command history to file (only in interactive mode)
  if (shell%is_interactive .and. len_trim(shell%histfile) > 0 .and. get_history_count() > 0) then
    call save_history_to_file(trim(shell%histfile), shell%histfilesize)
  end if

  ! Run logout scripts if this is a login shell
  if (shell%is_login_shell) then
    call run_logout_scripts(shell)
  end if

  ! Print performance statistics if monitoring was enabled
  if (perf_monitoring_enabled) then
    call print_performance_stats()
  end if

  ! Cleanup performance monitoring
  call cleanup_performance_monitoring()

  ! Only print goodbye message in interactive mode
  if (shell%is_interactive) then
    write(output_unit, '(a)') 'Goodbye!'
  end if

  ! Clean up any leaked process substitution FIFOs before exit
  call cleanup_all_fifos(shell)

  ! Exit with the last command's exit status (preserves exit code from EXIT trap)
  call c_exit(shell%last_exit_status)

contains

  ! Remove backslash-newline line continuations from input

  ! Convert escape sequences like \n to actual characters for -c flag
  function convert_escape_sequences(input) result(output)
    character(len=*), intent(in) :: input
    character(len=len(input)*2) :: output  ! Worst case: all chars become newlines
    integer :: i, j

    output = ''
    i = 1
    j = 1

    do while (i <= len_trim(input))
      ! Check for backslash escape sequences
      if (i < len_trim(input) .and. input(i:i) == '\') then
        select case(input(i+1:i+1))
        case('n')
          ! Convert \n to actual newline
          output(j:j) = char(10)
          i = i + 2
          j = j + 1
        case('t')
          ! Convert \t to tab
          output(j:j) = char(9)
          i = i + 2
          j = j + 1
        case('\')
          ! Convert \\ to single backslash
          output(j:j) = '\'
          i = i + 2
          j = j + 1
        case default
          ! Keep backslash and next char as-is
          output(j:j) = input(i:i)
          j = j + 1
          i = i + 1
        end select
      else
        ! Regular character, copy as-is
        output(j:j) = input(i:i)
        i = i + 1
        j = j + 1
      end if
    end do
  end function

  ! Check if a string contains heredoc syntax (<<) outside of quotes
  function has_heredoc_outside_quotes(str) result(has_heredoc)
    character(len=*), intent(in) :: str
    logical :: has_heredoc
    integer :: i
    logical :: in_single_quote, in_double_quote
    character :: ch

    has_heredoc = .false.
    in_single_quote = .false.
    in_double_quote = .false.

    do i = 1, len_trim(str) - 1
      ch = str(i:i)

      ! Track quote state
      if (.not. in_double_quote .and. ch == "'") then
        in_single_quote = .not. in_single_quote
      else if (.not. in_single_quote .and. ch == '"') then
        in_double_quote = .not. in_double_quote
      end if

      ! Check for << when outside quotes (but NOT <<< which is here-string)
      if (.not. in_single_quote .and. .not. in_double_quote) then
        if (str(i:i+1) == '<<') then
          ! Skip <<< (here-string)
          if (i + 2 <= len_trim(str) .and. str(i+2:i+2) == '<') cycle
          has_heredoc = .true.
          return
        end if
      end if
    end do
  end function

  ! Check if input has unclosed compound commands that need more lines
  ! Uses the lexer to properly distinguish keywords from arguments

  ! Pre-process heredocs in -c commands
  ! Extracts heredoc content and stores it for later use
  function preprocess_heredocs_for_c(input, shell) result(output)
    use shell_types
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: input
    type(shell_state_t), intent(inout) :: shell
    character(len=len(input)*2) :: output
    integer :: i, j, k, cmd_line_end, content_pos
    integer :: delim_start, delim_end, content_start, content_end
    character(len=256) :: delimiter, delimiters(MAX_PENDING_HEREDOCS)
    logical :: quoted_delimiters(MAX_PENDING_HEREDOCS), strip_tabs_arr(MAX_PENDING_HEREDOCS)
    integer :: num_heredocs, heredoc_idx
    character(len=4096) :: heredoc_content
    logical :: quoted_delimiter, strip_tabs
    character(len=len(input)) :: cmd_line

    output = input  ! Start with original

    ! Find the line containing << — scan all lines, not just the first
    ! The heredoc operator may be inside a compound command (if/then/fi)
    block
      integer :: nl_pos, search_start, ll
      cmd_line_end = 0
      search_start = 1
      do
        nl_pos = index(input(search_start:), char(10))
        if (nl_pos == 0) then
          ll = len_trim(input)
        else
          ll = search_start + nl_pos - 2
        end if
        ! Check if this line contains << outside quotes
        if (has_heredoc_outside_quotes(input(search_start:ll))) then
          cmd_line = input(1:ll)
          cmd_line_end = ll + 1  ! position after the line (at the newline or past end)
          exit
        end if
        if (nl_pos == 0) exit
        search_start = search_start + nl_pos
      end do
    end block
    if (cmd_line_end == 0) return

    ! Count and collect all heredoc delimiters from the command line
    ! Only match << when it's outside quotes
    num_heredocs = 0
    i = 1
    do while (i <= len_trim(cmd_line))
      ! Find next << outside of quotes
      j = 0
      block
        integer :: search_pos
        logical :: in_single_quote, in_double_quote
        character :: ch

        in_single_quote = .false.
        in_double_quote = .false.
        search_pos = i

        do while (search_pos <= len_trim(cmd_line) - 1)
          ch = cmd_line(search_pos:search_pos)

          ! Track quote state
          if (.not. in_double_quote .and. ch == "'") then
            in_single_quote = .not. in_single_quote
          else if (.not. in_single_quote .and. ch == '"') then
            in_double_quote = .not. in_double_quote
          end if

          ! Check for << when outside quotes (but NOT <<< which is here-string)
          if (.not. in_single_quote .and. .not. in_double_quote) then
            if (cmd_line(search_pos:search_pos+1) == '<<') then
              ! Skip <<< (here-string)
              if (search_pos + 2 <= len_trim(cmd_line) .and. &
                  cmd_line(search_pos+2:search_pos+2) == '<') then
                search_pos = search_pos + 3
                cycle
              end if
              j = search_pos
              exit
            end if
          end if

          search_pos = search_pos + 1
        end do
      end block

      if (j == 0) exit

      ! Check for <<- (strip tabs)
      strip_tabs = .false.
      if (j + 2 <= len_trim(cmd_line) .and. cmd_line(j+2:j+2) == '-') then
        strip_tabs = .true.
        k = j + 3
      else
        k = j + 2
      end if

      ! Skip spaces after << or <<-
      do while (k <= len_trim(cmd_line) .and. cmd_line(k:k) == ' ')
        k = k + 1
      end do

      if (k > len_trim(cmd_line)) exit

      ! Check for quoted delimiter
      quoted_delimiter = .false.
      if (cmd_line(k:k) == "'" .or. cmd_line(k:k) == '"') then
        quoted_delimiter = .true.
        block
          character :: quote_char
          quote_char = cmd_line(k:k)
          k = k + 1
          delim_start = k
          ! Find closing quote
          delim_end = k
          do while (delim_end <= len_trim(cmd_line) .and. cmd_line(delim_end:delim_end) /= quote_char)
            delim_end = delim_end + 1
          end do
          delim_end = delim_end - 1
        end block
      else
        delim_start = k
        ! Find end of delimiter (space, semicolon, or end of line)
        delim_end = k
        do while (delim_end <= len_trim(cmd_line) .and. &
                 cmd_line(delim_end:delim_end) /= ' ' .and. &
                 cmd_line(delim_end:delim_end) /= ';')
          delim_end = delim_end + 1
        end do
        delim_end = delim_end - 1
      end if

      if (delim_end >= delim_start .and. num_heredocs < MAX_PENDING_HEREDOCS) then
        num_heredocs = num_heredocs + 1
        delimiters(num_heredocs) = cmd_line(delim_start:delim_end)
        quoted_delimiters(num_heredocs) = quoted_delimiter
        strip_tabs_arr(num_heredocs) = strip_tabs
      end if

      i = delim_end + 1
      if (quoted_delimiter) i = i + 1  ! Skip closing quote
    end do

    if (num_heredocs == 0) return

    ! Now extract content for each heredoc in order
    content_pos = cmd_line_end + 1  ! Start after the command line newline

    do heredoc_idx = 1, num_heredocs
      delimiter = trim(delimiters(heredoc_idx))
      strip_tabs = strip_tabs_arr(heredoc_idx)

      ! Find content until the delimiter
      content_start = content_pos
      content_end = 0

      j = content_pos
      do while (j <= len_trim(input))
        ! Check if we're at start of a line
        if (j == content_pos .or. input(j-1:j-1) == char(10)) then
          ! For <<-, skip leading tabs before checking delimiter
          k = j
          if (strip_tabs) then
            do while (k <= len_trim(input) .and. input(k:k) == char(9))
              k = k + 1
            end do
          end if
          ! Check if this line starts with the delimiter (after tabs if strip_tabs)
          if (k + len_trim(delimiter) - 1 <= len_trim(input)) then
            if (input(k:k+len_trim(delimiter)-1) == trim(delimiter)) then
              ! Check if delimiter is alone on the line or followed by newline
              if (k + len_trim(delimiter) > len_trim(input) .or. &
                  input(k+len_trim(delimiter):k+len_trim(delimiter)) == char(10)) then
                content_end = j - 1
                content_pos = k + len_trim(delimiter)
                if (content_pos <= len_trim(input) .and. &
                    input(content_pos:content_pos) == char(10)) then
                  content_pos = content_pos + 1
                end if
                exit
              end if
            end if
          end if
        end if
        j = j + 1
      end do

      ! Extract heredoc content
      if (content_end >= content_start) then
        heredoc_content = input(content_start:content_end)
      else
        heredoc_content = ''
      end if

      ! Strip leading tabs if requested
      if (strip_tabs) then
        block
          integer :: m, n
          character(len=4096) :: stripped_content
          logical :: at_line_start

          stripped_content = ''
          m = 1
          n = 1
          at_line_start = .true.

          do while (m <= len_trim(heredoc_content))
            if (at_line_start .and. heredoc_content(m:m) == char(9)) then
              ! Skip leading tab
              m = m + 1
            else
              ! Copy character
              at_line_start = .false.
              stripped_content(n:n) = heredoc_content(m:m)
              if (heredoc_content(m:m) == char(10)) then
                at_line_start = .true.
              end if
              n = n + 1
              m = m + 1
            end if
          end do

          heredoc_content = stripped_content
        end block
      end if

      ! Store in pending heredocs array
      shell%pending_heredocs(heredoc_idx)%content = trim(heredoc_content)
      shell%pending_heredocs(heredoc_idx)%delimiter = trim(delimiter)
      shell%pending_heredocs(heredoc_idx)%quoted = quoted_delimiters(heredoc_idx)
      shell%pending_heredocs(heredoc_idx)%strip_tabs = strip_tabs
    end do

    shell%num_pending_heredocs = num_heredocs
    shell%next_pending_heredoc = 1

    ! Also set legacy single heredoc for backward compatibility
    if (num_heredocs >= 1) then
      shell%pending_heredoc = shell%pending_heredocs(1)%content
      shell%pending_heredoc_delimiter = shell%pending_heredocs(1)%delimiter
      shell%pending_heredoc_quoted = shell%pending_heredocs(1)%quoted
      shell%pending_heredoc_strip_tabs = shell%pending_heredocs(1)%strip_tabs
      shell%has_pending_heredoc = .true.
    end if

    ! Return the command line plus any remaining commands after heredocs
    if (content_pos <= len_trim(input)) then
      ! There are more commands after the last heredoc
      output = trim(cmd_line) // char(10) // trim(input(content_pos:))
    else
      output = cmd_line
    end if

  end function

  subroutine run_logout_scripts(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: home_dir, logout_file
    logical :: file_exists

    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) return

    ! Execute ~/.fortsh_logout if it exists
    logout_file = trim(home_dir) // '/.fortsh_logout'
    inquire(file=logout_file, exist=file_exists)

    if (file_exists) then
      ! Source the logout file
      shell%source_file = logout_file
      shell%should_source = .true.
      call process_source_file(shell)
    end if
  end subroutine


  recursive subroutine process_source_file(shell)
    use grammar_parser, only: parse_command_line, last_parse_had_error
    use command_tree, only: destroy_command_node, command_node_t
    use ast_executor, only: execute_ast
    type(shell_state_t), intent(inout) :: shell
    character(len=16384) :: input_line, converted_line
    character(len=16384) :: continuation_line
    integer :: file_unit, iostat, exit_code
    type(command_node_t), pointer :: ast_root
    character(len=:), allocatable :: expanded_line, history_expanded

    ! Reset the source flag first
    shell%should_source = .false.

    ! Open file for reading
    open(newunit=file_unit, file=trim(shell%source_file), status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'source: failed to open ' // trim(shell%source_file)
      shell%last_exit_status = 1
      return
    end if

    ! Increment source depth for return tracking
    shell%source_depth = shell%source_depth + 1

    ! Execute each line in the file
    do
      read(file_unit, '(a)', iostat=iostat) input_line
      if (iostat /= 0) exit  ! End of file or error

      ! Skip empty lines and comments
      if (len_trim(input_line) == 0 .or. input_line(1:1) == '#') cycle

      ! Check for unclosed quotes or backslash continuation
      do while (has_unclosed_quote(input_line) .or. ends_with_continuation_backslash(input_line))
        read(file_unit, '(a)', iostat=iostat) continuation_line
        if (iostat /= 0) exit  ! End of file during continuation
        ! Append the continuation line with a newline character
        input_line = trim(input_line) // char(10) // trim(continuation_line)
      end do

      ! Handle line continuation (backslash-newline)
      input_line = remove_line_continuations(input_line)

      ! If EOF was reached during continuation, exit
      if (iostat /= 0) exit

      ! Check for unclosed compound commands (if/fi, do/done, case/esac)
      do while (needs_compound_continuation(input_line))
        read(file_unit, '(a)', iostat=iostat) continuation_line
        if (iostat /= 0) exit  ! End of file during compound command
        ! Skip comment-only continuation lines but still append them
        input_line = trim(input_line) // char(10) // trim(continuation_line)
      end do

      ! Handle heredocs: either read from file or extract from accumulated input
      block
        character(len=256) :: hd_delim
        character(len=16384) :: hd_line, hd_stripped
        character(len=16384) :: hd_content
        integer :: hd_pos, hd_tab
        logical :: hd_strip_tabs
        hd_delim = get_heredoc_delimiter(input_line)
        if (len_trim(hd_delim) > 0) then
          ! If compound continuation already consumed the heredoc content
          ! (delimiter line is in input_line), use -c preprocessor
          if (has_heredoc_outside_quotes(input_line) .and. &
              index(input_line, char(10)) > 0) then
            input_line = preprocess_heredocs_for_c(input_line, shell)
          else
            ! Read heredoc content from file
            hd_strip_tabs = (index(input_line, '<<-') > 0)
            hd_content = ''
            hd_pos = 1
            do
              read(file_unit, '(a)', iostat=iostat) hd_line
              if (iostat /= 0) exit
              if (hd_strip_tabs) then
                hd_stripped = hd_line
                hd_tab = 1
                do while (hd_tab <= len_trim(hd_stripped) .and. hd_stripped(hd_tab:hd_tab) == char(9))
                  hd_tab = hd_tab + 1
                end do
                if (hd_tab > 1) hd_stripped = hd_stripped(hd_tab:)
                if (trim(hd_stripped) == trim(hd_delim)) exit
              else
                if (trim(hd_line) == trim(hd_delim)) exit
              end if
              if (hd_pos > 1) then
                hd_content(hd_pos:hd_pos) = char(10)
                hd_pos = hd_pos + 1
              end if
              hd_content(hd_pos:hd_pos+len_trim(hd_line)-1) = trim(hd_line)
              hd_pos = hd_pos + len_trim(hd_line)
            end do
            hd_content(hd_pos:hd_pos) = char(10)
            hd_pos = hd_pos + 1
            shell%has_pending_heredoc = .true.
            shell%pending_heredoc = hd_content(:hd_pos-1)
            shell%pending_heredoc_delimiter = trim(hd_delim)
            block
              integer :: dq_pos
              dq_pos = index(input_line, "'" // trim(hd_delim) // "'")
              if (dq_pos == 0) dq_pos = index(input_line, '"' // trim(hd_delim) // '"')
              shell%pending_heredoc_quoted = (dq_pos > 0)
            end block
            shell%pending_heredoc_strip_tabs = hd_strip_tabs
          end if
        end if
      end block

      ! Normal line processing
      ! Expand history if needed, then expand aliases
      ! NOTE: We do NOT add sourced file commands to history (only interactive commands)
      if (needs_history_expansion(input_line)) then
        history_expanded = expand_history(input_line)
        call expand_alias(shell, trim(history_expanded), expanded_line)
      else
        call expand_alias(shell, trim(input_line), expanded_line)
      end if

      ! Process substitutions <() and >() before parsing
      ! POSIX set -v: Print input line before execution
      if (shell%option_verbose) then
        write(error_unit, '(A)') trim(input_line)
      end if

      ! Parse and execute via AST (process substitution handled at execution time)
      converted_line = convert_backticks_to_dollar_paren(expanded_line)
      ast_root => parse_command_line(converted_line)
      if (associated(ast_root)) then
        if (shell%option_noexec) then
          exit_code = 0
          shell%last_exit_status = 0
        else
          exit_code = execute_ast(ast_root, shell)
          shell%last_exit_status = exit_code
        end if

        ! Handle nested source commands (e.g., script calls source)
        if (shell%should_source) then
          call process_source_file(shell)
        end if
      else if (last_parse_had_error) then
        shell%last_exit_status = 2
      end if

      ! Stop execution if exit command was encountered
      if (.not. shell%running) then
        exit
      end if

      ! Stop execution if return was called from sourced script
      if (shell%function_return_pending .and. shell%source_depth > 0) exit
    end do

    ! Fire RETURN trap if set (after sourced script finishes)
    block
      use signal_handling, only: get_trap_command, TRAP_RETURN
      use ast_executor, only: execute_ast_node
      character(len=4096) :: src_return_cmd
      src_return_cmd = get_trap_command(shell, TRAP_RETURN)
      if (len_trim(src_return_cmd) > 0 .and. &
          .not. shell%executing_trap) then
        block
          type(command_node_t), pointer :: trap_node
          integer :: saved_status_src
          logical :: saved_bypass_src
          saved_status_src = shell%last_exit_status
          saved_bypass_src = shell%bypass_functions
          shell%bypass_functions = .false.
          shell%executing_trap = .true.
          trap_node => parse_command_line(trim(src_return_cmd))
          if (associated(trap_node)) then
            exit_code = execute_ast_node(trap_node, shell)
            call destroy_command_node(trap_node)
          end if
          shell%executing_trap = .false.
          shell%bypass_functions = saved_bypass_src
          shell%last_exit_status = saved_status_src
        end block
      end if
    end block

    ! Decrement source depth
    shell%source_depth = shell%source_depth - 1

    ! Clear the return flag if we're exiting due to return in sourced script
    if (shell%function_return_pending .and. shell%function_depth == 0) then
      shell%function_return_pending = .false.
    end if

    close(file_unit)
    shell%source_file = ''
  end subroutine

  subroutine initialize_shell(shell)
    type(shell_state_t), intent(out) :: shell
    character(len=:), allocatable :: temp
    character(kind=c_char), target :: c_hostname(256)
    character(len=256) :: arg
    character(len=16) :: cols_str, rows_str
    integer :: ret, i, num_args
    logical :: success

    ! Initialize allocatable arrays to avoid large stack allocation on macOS
    if (.not. allocated(shell%positional_params)) then
      allocate(shell%positional_params(50))
      shell%positional_params_capacity = 50
      do i = 1, 50
        shell%positional_params(i)%str = ''
      end do
    end if
    if (.not. allocated(shell%local_vars)) then
      allocate(shell%local_vars(MAX_CONTROL_DEPTH, MAX_LOCAL_VARS_PER_SCOPE))
    end if
    if (.not. allocated(shell%local_var_counts)) then
      allocate(shell%local_var_counts(MAX_CONTROL_DEPTH))
      shell%local_var_counts = 0
    end if

    ! Detect if this is a login shell
    ! Check if argv[0] starts with '-' or if --login flag is present
    shell%is_login_shell = .false.
    num_args = command_argument_count()

    ! Check argv[0] (program name)
    if (num_args >= 0) then
      call get_command_argument(0, arg)
      ! If program name starts with '-', it's a login shell
      if (len_trim(arg) > 0 .and. arg(1:1) == '-') then
        shell%is_login_shell = .true.
      end if
    end if

    ! Check for --login flag
    do i = 1, num_args
      call get_command_argument(i, arg)
      if (trim(arg) == '--login' .or. trim(arg) == '-l') then
        shell%is_login_shell = .true.
        exit
      end if
    end do

    ! Get username
    temp = get_environment_var('USER')
    if (len(temp) > 0) then
      shell%username = temp
    else
      shell%username = 'user'
    end if

    ! Get hostname
    ret = c_gethostname(c_loc(c_hostname), 256_c_size_t)
    if (ret == 0) then
      shell%hostname = ''
      do i = 1, 256
        if (c_hostname(i) == c_null_char) exit
        shell%hostname(i:i) = c_hostname(i)
      end do
    else
      shell%hostname = 'localhost'
    end if

    ! Get current directory
    shell%cwd = get_current_directory()

    ! Check if shell is interactive (only if not already set by -c or script file)
    ! If execute_command_string or execute_script_file is true, we already set is_interactive = false
    if (.not. execute_command_string .and. .not. execute_script_file) then
      shell%is_interactive = (c_isatty(STDIN_FD) /= 0)
    end if

    ! Setup job control if interactive
    if (shell%is_interactive) then
      shell%shell_pgid = c_getpid()
      ret = c_setpgid(shell%shell_pgid, shell%shell_pgid)
      shell%shell_terminal = STDIN_FD
      ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
      ! Enable monitor mode (job control) for interactive shells
      shell%option_monitor = .true.
    end if

    ! Query terminal size (only if interactive to avoid SIGTTOU)
    if (shell%is_interactive) then
      success = get_terminal_size(shell%term_rows, shell%term_cols)
      ! Set COLUMNS and LINES in both environment and shell variables
      write(cols_str, '(I0)') shell%term_cols
      write(rows_str, '(I0)') shell%term_rows
      success = set_environment_var('COLUMNS', trim(cols_str))
      success = set_environment_var('LINES', trim(rows_str))
      call set_shell_variable(shell, 'COLUMNS', trim(cols_str))
      call set_shell_variable(shell, 'LINES', trim(rows_str))
    end if

    ! Check terminal capabilities (ANSI support) - only if interactive
    if (shell%is_interactive) then
      shell%term_supports_color = terminal_supports_ansi()
    else
      shell%term_supports_color = .false.
    end if

    ! Set initial terminal title if interactive (only for ANSI terminals)
    if (shell%is_interactive .and. shell%term_supports_color) then
      call set_terminal_title(trim(shell%username) // '@' // trim(shell%hostname) // ': ' // trim(shell%cwd))
    end if

    ! Initialize other fields
    shell%last_exit_status = 0
    shell%last_pid = 0
    shell%running = .true.
    shell%num_jobs = 0
    shell%next_job_id = 1

    ! Initialize history control variables
    temp = get_environment_var('HOME')
    if (len(temp) > 0) then
      shell%histfile = trim(temp) // '/.fortsh_history'
    else
      shell%histfile = ''
    end if
    shell%histsize = 1000
    shell%histfilesize = 2000
    shell%histcontrol = 'ignoredups'  ! Default: ignore duplicate consecutive commands

    ! Initialize shell options and special variables
    call initialize_shell_options(shell)

    ! Save original stderr for shell messages (xtrace, errors, etc.)
    ! This ensures shell meta-output isn't affected by command redirections
    shell%original_stderr_fd = c_dup(STDERR_FD)
    if (shell%original_stderr_fd < 0) then
      shell%original_stderr_fd = STDERR_FD  ! Fallback if dup fails
    end if

    ! Initialize special shell variables
    shell%uid = get_uid()
    shell%euid = get_euid()
    call system_clock(shell%shell_start_time)
    shell%oldpwd = ''
    shell%last_arg = ''
    shell%pending_trap_command = ''
    shell%current_command = ''
    shell%ps1 = '%F{green}\u@\h%f :: %F{blue}\w%f\n> '
    shell%current_line_number = 0

    ! Initialize jobs array
    do i = 1, MAX_JOBS
      shell%jobs(i)%job_id = 0
    end do

    ! Initialize aliases array
    do i = 1, size(shell%aliases)
      shell%aliases(i)%name = ''
      shell%aliases(i)%command = ''
    end do

    ! Initialize traps array
    do i = 1, size(shell%traps)
      shell%traps(i)%command = ''
    end do

    ! Initialize control stack
    do i = 1, size(shell%control_stack)
      shell%control_stack(i)%condition_cmd = ''
    end do

    ! Initialize coprocess registry (module-level, not part of shell_state_t)
    call init_coprocess_registry()

    ! Initialize functions array
    do i = 1, size(shell%functions)
      shell%functions(i)%name = ''
      shell%functions(i)%body_lines = 0
    end do

    ! Initialize prompt string lengths (to match default values in shell_state_t)
    shell%ps1_len = len_trim(shell%ps1)  ! '\u@\h :: \w > ' = 17 chars
    shell%ps2_len = 2                    ! '> ' = 2 chars (don't trim trailing space)
    shell%ps3_len = 3                    ! '#? ' = 3 chars (don't trim trailing space)
    shell%ps4_len = 2                    ! '+ ' = 2 chars (don't trim trailing space)

    ! Check for performance monitoring environment variable
    temp = get_environment_var('FORTSH_PERF')
    if (len(temp) > 0 .and. trim(temp) == '1') then
      call set_performance_monitoring(.true.)
    end if

  end subroutine

  subroutine execute_trap_for_signal(shell, signum)
    use grammar_parser, only: parse_command_line, last_parse_had_error
    use ast_executor, only: execute_ast_node
    use command_tree, only: command_node_t, destroy_command_node
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: signum
    character(len=4096) :: trap_command
    type(command_node_t), pointer :: trap_ast
    integer :: saved_exit_status, trap_exit_code

    ! Get the trap command for this signal
    trap_command = get_trap_command(shell, signum)

    if (len_trim(trap_command) == 0) return

    ! Don't execute inherited traps (visible in subshell but not executed)
    if (is_trap_inherited(shell, signum)) return

    ! Save current exit status (trap should not affect $?)
    saved_exit_status = shell%last_exit_status

    ! Don't execute trap if we're already in one
    if (shell%executing_trap) return

    ! Don't execute EXIT trap if it was already executed by builtin_exit
    if (signum == 0 .and. shell%exit_trap_executed) return

    ! Set flag to prevent recursive trap execution
    shell%executing_trap = .true.

    ! Mark EXIT trap as executed if this is an EXIT trap
    if (signum == 0) shell%exit_trap_executed = .true.

    ! Parse and execute trap command via AST
    trap_ast => parse_command_line(trim(trap_command))
    if (associated(trap_ast)) then
      trap_exit_code = execute_ast_node(trap_ast, shell)
      call destroy_command_node(trap_ast)
    else if (last_parse_had_error) then
      shell%last_exit_status = 2
    end if

    ! Clear flag
    shell%executing_trap = .false.

    ! Restore exit status
    shell%last_exit_status = saved_exit_status
  end subroutine

end program fortran_shell