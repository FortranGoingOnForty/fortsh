! ==============================================================================
! Module: readline_fzf
! Purpose: fzf integration — file, history, directory, and git browsers, plus
!          the raw-mode-safe command runner and temp-file helpers they share
!          (QUAL-13 split). Leaf over readline_bufferops + system_interface: the
!          browsers shell out to fzf, read the selection, and insert it via
!          insert_string_at_cursor / state_buffer_set; the caller in readline
!          handles any redraw afterward, so nothing here touches the render core.
!          Re-exported by readline, so `use readline` consumers are unchanged.
! ==============================================================================
module readline_fzf
  use readline_constants
  use readline_state
  use readline_bufferops
  use system_interface
  use iso_fortran_env, only: output_unit
  use iso_c_binding
  implicit none

contains

  ! ===========================================================================
  ! Helper function for execute_command_line in raw mode (flang-new workaround)
  ! ===========================================================================
  subroutine safe_execute_command(command, exitstat)
    character(len=*), intent(in) :: command
    integer, intent(out), optional :: exitstat
    type(termios_t) :: temp_termios
    logical :: success
    integer(c_int) :: c_exit_code
    type(c_funptr) :: old_sigchld_handler

    ! Flush all I/O before system() call
    flush(output_unit)
    flush(0)  ! stdin

    ! CRITICAL: Must restore terminal to cooked mode before fork/exec
    if (module_termios_saved) then
      success = restore_terminal(module_original_termios)
    end if

    ! CRITICAL FIX: Temporarily restore SIGCHLD to default handler
    ! The shell's SIGCHLD handler causes auto-reaping of child processes,
    ! which makes system()'s wait() fail with ECHILD (errno 10)
    old_sigchld_handler = c_signal(SIGCHLD, SIG_DFL)

    ! Use C system() instead of execute_command_line (flang-new workaround)
    c_exit_code = readline_c_system(trim(command) // c_null_char)

    ! Restore the original SIGCHLD handler
    old_sigchld_handler = c_signal(SIGCHLD, old_sigchld_handler)

    ! Re-enable raw mode for continued readline operation
    if (module_termios_saved) then
      success = enable_raw_mode(temp_termios)
      if (success) then
        ! Update saved state with new termios
        module_original_termios = temp_termios
      end if
    end if

    ! Convert C exit code to Fortran exitstat
    ! system() returns: (exit_status << 8) | signal_number
    ! Extract just the exit status
    if (present(exitstat)) then
      if (c_exit_code == -1) then
        exitstat = -1  ! Fork/exec failed
      else
        exitstat = ishft(c_exit_code, -8)  ! Shift right 8 bits
      end if
    end if
  end subroutine

  ! ===========================================================================
  ! FZF Integration (Ctrl-F fuzzy file finder)
  ! ===========================================================================

  ! Create a private 0600 temp file (mkstemp: O_EXCL, no symlink follow) for an
  ! fzf browser's output. Replaces the fixed /tmp/fortsh_fzf_*.tmp names that a
  ! pre-planted symlink could hijack to truncate a victim file, and that leaked
  ! selections world-readable under umask 022 (SEC-2). ok=.false. → abort browse.
  subroutine fzf_open_tempfile(tmpfile, ok)
    character(len=*), intent(out) :: tmpfile
    logical, intent(out) :: ok
    ok = make_temp_file('fortsh_fzf_', tmpfile)
  end subroutine

  ! Delete an fzf temp file on any exit path (fzf cancel included). Uses a
  ! Fortran open+close(delete) so no shell is involved.
  subroutine fzf_remove_tempfile(tmpfile)
    character(len=*), intent(in) :: tmpfile
    integer :: u, ios
    if (len_trim(tmpfile) == 0) return
    open(newunit=u, file=trim(tmpfile), status='old', iostat=ios)
    if (ios == 0) close(u, status='delete')
  end subroutine

  subroutine launch_fzf_file_browser(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=1024) :: fzf_cmd
    character(len=512) :: preview_cmd
    integer :: unit, iostat, exit_status
    logical :: file_exists
    character(len=256) :: bat_path
    character(len=1024) :: tmpfile
    logical :: temp_ok
    ! Variables for block construct workaround (flang-new compatibility)
    character(len=1024) :: line, combined_selection
    logical :: first_line
    integer :: i, moves
    character(len=MAX_LINE_LEN) :: temp_buf


    ! Check if fzf is installed
    call safe_execute_command('command -v fzf >/dev/null 2>&1', exitstat=exit_status)
    if (exit_status /= 0) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: fzf is not installed. Please install fzf first.'
      write(output_unit, '(a)') '  Ubuntu/Debian: sudo apt install fzf'
      write(output_unit, '(a)') '  macOS: brew install fzf'
      write(output_unit, '(a)') '  Arch: sudo pacman -S fzf'
      input_state%dirty = .true.
      return
    end if

    ! Check if bat is available for syntax highlighting
    call safe_execute_command('command -v bat >/dev/null 2>&1', exitstat=exit_status)
    if (exit_status == 0) then
      bat_path = 'bat'
    else
      ! Try batcat (Debian/Ubuntu package name)
      call safe_execute_command('command -v batcat >/dev/null 2>&1', exitstat=exit_status)
      if (exit_status == 0) then
        bat_path = 'batcat'
      else
        bat_path = ''  ! Will use cat fallback
      end if
    end if

    ! Build preview command
    if (len_trim(bat_path) > 0) then
      write(preview_cmd, '(a)') trim(bat_path) // &
           ' --color=always --style=numbers,changes --line-range=:500 "{}"'
    else
      preview_cmd = 'head -n 500 "{}"'
    end if

    ! Secure temp file for fzf's output (SEC-2)
    call fzf_open_tempfile(tmpfile, temp_ok)
    if (.not. temp_ok) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: could not create a temporary file.'
      input_state%dirty = .true.
      return
    end if

    ! Build fzf command with options (including multi-select)
    write(fzf_cmd, '(a)') 'fzf --multi --height=40% --reverse --border ' // &
          '--preview=''' // trim(preview_cmd) // ''' ' // &
          '--preview-window=right:60%:wrap ' // &
          '--bind=''ctrl-/:toggle-preview'' ' // &
          '--header=''TAB: Multi-select | Ctrl-/: Toggle Preview | ESC: Cancel'' ' // &
          '> ' // trim(tmpfile) // ' 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'  ! Clear screen
    write(output_unit, '(a)', advance='no') char(27) // '[H'   ! Move cursor home
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection(s) if fzf exited successfully (supports multi-select)
    if (exit_status == 0) then
      inquire(file=trim(tmpfile), exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file=trim(tmpfile), &
             status='old', action='read', iostat=iostat)
        if (iostat == 0) then
          ! WORKAROUND: Removed block construct for flang-new compatibility
          ! Variables moved to subroutine level
          first_line = .true.
          combined_selection = ''

          ! Read all lines (one per selected file)
          do
            read(unit, '(a)', iostat=iostat) line
            if (iostat /= 0) exit

            if (len_trim(line) > 0) then
              if (first_line) then
                combined_selection = trim(line)
                first_line = .false.
              else
                ! Add space between multiple selections
                combined_selection = trim(combined_selection) // ' ' // trim(line)
              end if
            end if
          end do
          close(unit)

          ! Insert combined selections at cursor position
          if (len_trim(combined_selection) > 0) then
            call insert_string_at_cursor(input_state, trim(combined_selection))
          end if
        end if
      end if
    end if
    call fzf_remove_tempfile(tmpfile)  ! remove on all paths, incl. ESC cancel

    ! Restore terminal and redraw prompt
    write(output_unit, '(a)', advance='no') char(27) // '[2J'  ! Clear screen
    write(output_unit, '(a)', advance='no') char(27) // '[H'   ! Move cursor home
    write(output_unit, '(a)', advance='no') trim(prompt)

    ! Redraw current line
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
      ! Move cursor to correct position (if not at end)
      if (input_state%cursor_pos < input_state%length) then
        ! Move cursor back from end to cursor position using ANSI escape codes
        ! WORKAROUND: Removed block construct for flang-new compatibility
        ! Variables moved to subroutine level
        moves = input_state%length - input_state%cursor_pos
        do i = 1, moves
          write(output_unit, '(a)', advance='no') char(27) // '[D'  ! Cursor left
        end do
      end if
    end if
    flush(output_unit)

    input_state%dirty = .true.
  end subroutine

  subroutine launch_fzf_history_browser(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=1024) :: fzf_cmd, selected_cmd, history_file
    integer :: unit, iostat, exit_status
    logical :: file_exists
    character(len=1024) :: tmpfile
    logical :: temp_ok
    character(len=MAX_LINE_LEN) :: temp_buf

    ! Check if fzf is installed
    call safe_execute_command('command -v fzf >/dev/null 2>&1', exitstat=exit_status)
    if (exit_status /= 0) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: fzf is not installed. Please install fzf first.'
      input_state%dirty = .true.
      return
    end if

    ! Get history file path
    call get_environment_variable('HOME', history_file)
    history_file = trim(history_file) // '/.fortsh_history'

    ! Check if history file exists
    inquire(file=trim(history_file), exist=file_exists)
    if (.not. file_exists) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'No history file found.'
      input_state%dirty = .true.
      return
    end if

    ! Secure temp file for fzf's output (SEC-2)
    call fzf_open_tempfile(tmpfile, temp_ok)
    if (.not. temp_ok) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: could not create a temporary file.'
      input_state%dirty = .true.
      return
    end if

    ! Build fzf command for history
    ! tac reverses the file so recent commands appear first
    ! Use exact match for consistency
    write(fzf_cmd, '(a)') 'tac ' // trim(history_file) // ' | ' // &
          'fzf --height=40% --reverse --border ' // &
          '--no-sort ' // &
          '--tiebreak=index ' // &
          '--header=''Ctrl-H: History Browser | Select: Replace Line | ESC: Cancel'' ' // &
          '> ' // trim(tmpfile) // ' 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'  ! Clear screen
    write(output_unit, '(a)', advance='no') char(27) // '[H'   ! Move cursor home
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection if fzf exited successfully
    if (exit_status == 0) then
      inquire(file=trim(tmpfile), exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file=trim(tmpfile), &
             status='old', action='read', iostat=iostat)
        if (iostat == 0) then
          read(unit, '(a)', iostat=iostat) selected_cmd
          close(unit)

          if (iostat == 0 .and. len_trim(selected_cmd) > 0) then
            ! Replace entire line with selected command
            call state_buffer_set(input_state, trim(selected_cmd))
            input_state%length = len_trim(selected_cmd)
            input_state%cursor_pos = input_state%length
          end if
        end if
      end if
    end if
    call fzf_remove_tempfile(tmpfile)

    ! Restore terminal and redraw prompt
    write(output_unit, '(a)', advance='no') char(27) // '[2J'  ! Clear screen
    write(output_unit, '(a)', advance='no') char(27) // '[H'   ! Move cursor home
    write(output_unit, '(a)', advance='no') trim(prompt)

    ! Redraw current line
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
    end if
    flush(output_unit)

    input_state%dirty = .true.
  end subroutine

  subroutine launch_fzf_directory_browser(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=1024) :: fzf_cmd, selected_dir
    integer :: unit, iostat, exit_status
    logical :: file_exists
    character(len=1024) :: tmpfile
    logical :: temp_ok
    character(len=MAX_LINE_LEN) :: temp_buf

    ! Check if fzf is installed
    call safe_execute_command('command -v fzf >/dev/null 2>&1', exitstat=exit_status)
    if (exit_status /= 0) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: fzf is not installed.'
      input_state%dirty = .true.
      return
    end if

    ! Secure temp file for fzf's output (SEC-2)
    call fzf_open_tempfile(tmpfile, temp_ok)
    if (.not. temp_ok) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: could not create a temporary file.'
      input_state%dirty = .true.
      return
    end if

    ! Build fzf command for directories only
    ! Use find to list directories, fd if available (faster)
    write(fzf_cmd, '(a)') '(command -v fd >/dev/null 2>&1 && ' // &
          'fd --type d --hidden --exclude .git || ' // &
          'find . -type d -not -path ''*/\.git/*'' 2>/dev/null) | ' // &
          'fzf --height=40% --reverse --border ' // &
          '--preview=''ls -lah "{}"'' ' // &
          '--preview-window=right:60%:wrap ' // &
          '--header=''Alt-J: Jump to Directory | Select: CD into dir | ESC: Cancel'' ' // &
          '> ' // trim(tmpfile) // ' 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'
    write(output_unit, '(a)', advance='no') char(27) // '[H'
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection and cd into it
    if (exit_status == 0) then
      inquire(file=trim(tmpfile), exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file=trim(tmpfile), &
             status='old', action='read', iostat=iostat)
        if (iostat == 0) then
          read(unit, '(a)', iostat=iostat) selected_dir
          close(unit)

          if (iostat == 0 .and. len_trim(selected_dir) > 0) then
            ! Replace line with cd command
            call state_buffer_set(input_state, 'cd ' // trim(selected_dir))
#ifdef USE_C_STRINGS
            input_state%length = len(trim('cd ' // trim(selected_dir)))
#else
#ifdef USE_MEMORY_POOL
            input_state%length = len_trim(input_state%buffer_ref%data)
#else
            input_state%length = len_trim(input_state%buffer)
#endif
#endif
            input_state%cursor_pos = input_state%length
          end if
        end if
      end if
    end if
    call fzf_remove_tempfile(tmpfile)

    ! Restore terminal
    write(output_unit, '(a)', advance='no') char(27) // '[2J'
    write(output_unit, '(a)', advance='no') char(27) // '[H'
    write(output_unit, '(a)', advance='no') trim(input_state%menu_prompt)
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
    end if
    flush(output_unit)

    input_state%dirty = .true.
  end subroutine

  subroutine launch_fzf_git_browser(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=1024) :: fzf_cmd, selected_item, git_cmd
    character(len=512) :: preview_cmd
    character(len=MAX_LINE_LEN) :: temp_buf
    character(len=1024) :: tmpfile
    logical :: temp_ok
    integer :: unit, iostat, exit_status
    logical :: file_exists, in_git_repo
    ! Variables for block construct workaround (flang-new compatibility)
    integer :: i, moves

    ! Check if in git repo
    call safe_execute_command('git rev-parse --git-dir >/dev/null 2>&1', exitstat=exit_status)
    in_git_repo = (exit_status == 0)

    if (.not. in_git_repo) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Not in a git repository.'
      input_state%dirty = .true.
      return
    end if

    ! Check if fzf is installed
    call safe_execute_command('command -v fzf >/dev/null 2>&1', exitstat=exit_status)
    if (exit_status /= 0) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: fzf is not installed.'
      input_state%dirty = .true.
      return
    end if

    ! Build git file browser (changed/staged files + branches)
    ! Show modified files and branches
    write(git_cmd, '(a)') '{ echo "=== Changed Files ==="; ' // &
          'git status --short; ' // &
          'echo ""; echo "=== Branches ==="; ' // &
          'git branch --all; }'

    write(preview_cmd, '(a)') 'if [[ "{}" == *"==="* ]]; then echo "Select an item below"; ' // &
          'elif git show "{}" >/dev/null 2>&1; then git show --stat "{}"; ' // &
          'else git diff "{}"; fi'

    ! Secure temp file for fzf's output (SEC-2)
    call fzf_open_tempfile(tmpfile, temp_ok)
    if (.not. temp_ok) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: could not create a temporary file.'
      input_state%dirty = .true.
      return
    end if

    write(fzf_cmd, '(a)') trim(git_cmd) // ' | ' // &
          'fzf --height=40% --reverse --border --ansi ' // &
          '--preview=''' // trim(preview_cmd) // ''' ' // &
          '--preview-window=right:60%:wrap ' // &
          '--header=''Alt-G: Git Browser | Select file or branch | ESC: Cancel'' ' // &
          '> ' // trim(tmpfile) // ' 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'
    write(output_unit, '(a)', advance='no') char(27) // '[H'
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection
    if (exit_status == 0) then
      inquire(file=trim(tmpfile), exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file=trim(tmpfile), &
             status='old', action='read', iostat=iostat)
        if (iostat == 0) then
          read(unit, '(a)', iostat=iostat) selected_item
          close(unit)

          if (iostat == 0 .and. len_trim(selected_item) > 0) then
            ! Insert selected item at cursor
            call insert_string_at_cursor(input_state, trim(selected_item))
          end if
        end if
      end if
    end if
    call fzf_remove_tempfile(tmpfile)

    ! Restore terminal
    write(output_unit, '(a)', advance='no') char(27) // '[2J'
    write(output_unit, '(a)', advance='no') char(27) // '[H'
    write(output_unit, '(a)', advance='no') trim(input_state%menu_prompt)
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
      ! Move cursor to correct position
      if (input_state%cursor_pos < input_state%length) then
        ! WORKAROUND: Removed block construct for flang-new compatibility
        ! Variables moved to subroutine level
        moves = input_state%length - input_state%cursor_pos
        do i = 1, moves
          write(output_unit, '(a)', advance='no') char(27) // '[D'
        end do
      end if
    end if
    flush(output_unit)

    input_state%dirty = .true.
  end subroutine

end module readline_fzf
