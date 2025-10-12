! ==============================================================================
! Module: readline
! Purpose: Advanced input handling with command history and line editing
! ==============================================================================
module readline
  use shell_types
  use system_interface
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  use iso_c_binding
  implicit none

  ! Constants for special keys
  integer, parameter :: KEY_ENTER = 10
  integer, parameter :: KEY_BACKSPACE = 127
  integer, parameter :: KEY_DELETE = 127  ! Same as backspace on most terminals
  integer, parameter :: KEY_TAB = 9
  integer, parameter :: KEY_CTRL_C = 3
  integer, parameter :: KEY_CTRL_D = 4
  integer, parameter :: KEY_CTRL_A = 1    ! Home (beginning of line)
  integer, parameter :: KEY_CTRL_E = 5    ! End (end of line)
  integer, parameter :: KEY_CTRL_K = 11   ! Kill to end of line
  integer, parameter :: KEY_CTRL_L = 12   ! Clear screen
  integer, parameter :: KEY_CTRL_W = 23   ! Kill previous word
  integer, parameter :: KEY_CTRL_U = 21   ! Kill entire line
  integer, parameter :: KEY_CTRL_Y = 25   ! Yank (paste) killed text
  integer, parameter :: KEY_CTRL_F = 6    ! Forward character (same as right arrow)
  integer, parameter :: KEY_CTRL_B = 2    ! Backward character (same as left arrow)
  integer, parameter :: KEY_CTRL_R = 18   ! Reverse-i-search
  integer, parameter :: KEY_CTRL_G = 7    ! Cancel (alternate to Ctrl+C)
  integer, parameter :: KEY_ESC = 27
  integer, parameter :: KEY_UP = 65
  integer, parameter :: KEY_DOWN = 66
  integer, parameter :: KEY_RIGHT = 67
  integer, parameter :: KEY_LEFT = 68
  
  ! History and line management
  integer, parameter :: MAX_HISTORY = 1000
  integer, parameter :: MAX_LINE_LEN = 1024
  
  ! Input state management
  ! Editing mode constants
  integer, parameter :: EDITING_MODE_EMACS = 1
  integer, parameter :: EDITING_MODE_VI = 2
  integer, parameter :: VI_MODE_INSERT = 1
  integer, parameter :: VI_MODE_COMMAND = 2

  type :: input_state_t
    character(len=MAX_LINE_LEN) :: buffer = ''
    character(len=MAX_LINE_LEN) :: original_buffer = '' ! Save original input during history navigation
    character(len=MAX_LINE_LEN) :: kill_buffer = ''    ! Kill ring buffer for cut/paste
    character(len=MAX_LINE_LEN) :: last_completion_buffer = '' ! Buffer when we last showed completions
    integer :: length = 0
    integer :: cursor_pos = 0  ! 0-based position in buffer
    integer :: history_pos = 0  ! Current position in history (0 = not browsing)
    integer :: kill_length = 0  ! Length of text in kill buffer
    logical :: dirty = .false. ! Needs redraw
    logical :: in_history = .false. ! Currently browsing history
    logical :: completions_shown = .false. ! Have we shown completion list for current buffer?

    ! Reverse-i-search state
    logical :: in_search = .false. ! Currently in reverse-i-search mode
    character(len=MAX_LINE_LEN) :: search_string = '' ! Current search query
    integer :: search_length = 0 ! Length of search string
    integer :: search_match_index = 0 ! Current history match index

    ! Editing mode support
    integer :: editing_mode = EDITING_MODE_EMACS
    integer :: vi_mode = VI_MODE_INSERT
    character(len=MAX_LINE_LEN) :: vi_command_buffer = ''
    integer :: vi_command_count = 0
    logical :: vi_repeat_pending = .false.
  end type input_state_t

  type :: history_t
    character(len=MAX_LINE_LEN) :: lines(MAX_HISTORY)
    integer :: count = 0
    integer :: current = 0  ! Current position in history navigation
  end type history_t

  type(history_t), save :: command_history

  ! Module-level HISTCONTROL setting (set by shell)
  character(len=256), save :: current_histcontrol = ''

  ! Module-level editing mode (set by shell via option_vi)
  integer, save :: global_editing_mode = EDITING_MODE_EMACS

contains

  ! Set the HISTCONTROL setting for history management
  subroutine set_histcontrol(histcontrol)
    character(len=*), intent(in) :: histcontrol
    current_histcontrol = histcontrol
  end subroutine

  ! Set the global editing mode (vi or emacs)
  subroutine set_global_editing_mode(vi_mode)
    logical, intent(in) :: vi_mode
    if (vi_mode) then
      global_editing_mode = EDITING_MODE_VI
    else
      global_editing_mode = EDITING_MODE_EMACS
    end if
  end subroutine

  ! Enhanced readline with character-by-character input processing
  subroutine readline_enhanced(prompt, line, iostat)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat
    
    type(input_state_t) :: input_state
    type(termios_t) :: original_termios
    character :: ch
    logical :: success, done, raw_enabled
    integer :: char_code
    
    iostat = 0
    done = .false.
    raw_enabled = .false.
    
    ! Try to enable raw mode (only works in interactive mode)
    success = enable_raw_mode(original_termios)
    if (success) then
      raw_enabled = .true.
    end if
    
    ! Print prompt
    write(output_unit, '(a)', advance='no') prompt
    flush(output_unit)
    
    ! Initialize input state
    input_state%buffer = ''
    input_state%original_buffer = ''
    input_state%kill_buffer = ''
    input_state%last_completion_buffer = ''
    input_state%length = 0
    input_state%cursor_pos = 0
    input_state%history_pos = 0
    input_state%kill_length = 0
    input_state%dirty = .false.
    input_state%in_history = .false.
    input_state%completions_shown = .false.
    input_state%in_search = .false.
    input_state%search_string = ''
    input_state%search_length = 0
    input_state%search_match_index = 0
    input_state%editing_mode = global_editing_mode  ! Initialize from global state
    input_state%vi_mode = VI_MODE_INSERT

    if (raw_enabled) then
      ! Enhanced input processing
      do while (.not. done)
        success = read_single_char(ch)
        if (.not. success) then
          iostat = -1
          exit
        end if
        
        char_code = iachar(ch)
        
        select case(char_code)
        case(KEY_ENTER)
          ! Enter - finish input or accept search
          if (input_state%in_search) then
            call accept_search(input_state, prompt)
            done = .true.
          else
            write(output_unit, '()')  ! New line
            done = .true.
          end if

        case(KEY_CTRL_D)
          ! Ctrl+D - EOF
          if (input_state%length == 0) then
            iostat = -1
            done = .true.
          end if

        case(KEY_CTRL_C)
          ! Ctrl+C - cancel and clear line (bash-compatible)
          ! Move to beginning, clear line, print ^C on new line
          write(output_unit, '(a)', advance='no') ESC_MOVE_BOL // ESC_CLEAR_LINE
          write(output_unit, '(a)') '^C'

          ! Clear buffer and exit search mode if active
          if (input_state%in_search) then
            input_state%in_search = .false.
            input_state%search_string = ''
            input_state%search_length = 0
            input_state%search_match_index = 0
          end if

          ! Clear buffer and return empty line
          input_state%buffer = ''
          input_state%length = 0
          input_state%cursor_pos = 0
          done = .true.

        case(KEY_BACKSPACE)
          ! Backspace
          if (input_state%in_search) then
            call search_backspace(input_state, prompt)
          else
            call handle_backspace(input_state)
          end if
          
        case(KEY_TAB)
          ! Tab completion (placeholder)
          call handle_tab_completion(input_state)
          
        case(KEY_ESC)
          ! Escape sequence - try to read more
          call handle_escape_sequence(input_state, done)
          
        case(KEY_CTRL_A)
          ! Home - move to beginning of line
          call handle_home(input_state)
          
        case(KEY_CTRL_E)
          ! End - move to end of line
          call handle_end(input_state)
          
        case(KEY_CTRL_F)
          ! Forward character (same as right arrow)
          call handle_cursor_right(input_state)
          
        case(KEY_CTRL_B)
          ! Backward character (same as left arrow)
          call handle_cursor_left(input_state)
          
        case(KEY_CTRL_K)
          ! Kill to end of line
          call handle_kill_to_end(input_state)
          
        case(KEY_CTRL_U)
          ! Kill entire line
          call handle_kill_line(input_state)
          
        case(KEY_CTRL_W)
          ! Kill previous word
          call handle_kill_word(input_state)
          
        case(KEY_CTRL_Y)
          ! Yank (paste) killed text
          call handle_yank(input_state)
          
        case(KEY_CTRL_L)
          ! Clear screen and redraw
          call handle_clear_screen(input_state, prompt)

        case(KEY_CTRL_R)
          ! Reverse-i-search
          call handle_reverse_search(input_state, prompt)

        case(KEY_CTRL_G)
          ! Cancel search if active (bash-compatible)
          if (input_state%in_search) then
            ! Clear line and exit search mode
            write(output_unit, '(a)', advance='no') ESC_MOVE_BOL // ESC_CLEAR_LINE
            write(output_unit, '(a)') '^C'

            input_state%in_search = .false.
            input_state%search_string = ''
            input_state%search_length = 0
            input_state%search_match_index = 0

            ! Clear buffer and return empty line
            input_state%buffer = ''
            input_state%length = 0
            input_state%cursor_pos = 0
            done = .true.
          end if

        case(32:126)
          ! Regular printable characters
          if (input_state%in_search) then
            call search_add_char(input_state, ch, prompt)
          else if (input_state%editing_mode == EDITING_MODE_VI .and. &
                   input_state%vi_mode == VI_MODE_COMMAND) then
            ! In Vi command mode - route to command handler
            call handle_vi_command_mode(input_state, char_code)
            ! Check if we switched back to insert mode
            if (input_state%vi_mode == VI_MODE_INSERT) then
              call handle_vi_mode_switch(input_state, char_code)
            end if
          else
            call insert_char(input_state, ch)
          end if
          
        case default
          ! Ignore other control characters for now
        end select
        
        ! Redraw line if needed
        if (input_state%dirty) then
          call redraw_line(prompt, input_state)
          input_state%dirty = .false.
        end if
      end do
      
      ! Restore terminal
      if (.not. restore_terminal(original_termios)) then
        ! Warning but don't fail
      end if
    else
      ! Fallback to line-based input
      read(input_unit, '(a)', iostat=iostat) input_state%buffer
      if (iostat == 0) input_state%length = len_trim(input_state%buffer)
    end if
    
    ! Return the result
    if (iostat == 0) then
      line = input_state%buffer(:input_state%length)
      ! Note: History addition is now handled in the main loop AFTER expansion
      ! This prevents history expansion commands like !! from referencing themselves
    else
      line = ''
    end if
  end subroutine

  ! Simple fallback readline - uses standard input for now
  ! This is a placeholder for a full readline implementation
  subroutine readline_simple(prompt, line, iostat)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat

    ! Print prompt
    write(output_unit, '(a)', advance='no') prompt
    flush(output_unit)

    ! Read line using standard input (no special key handling yet)
    read(input_unit, '(a)', iostat=iostat) line

    ! Note: History addition is now handled in the main loop AFTER expansion
  end subroutine

  ! Enhanced readline with tab completion support
  ! Note: This is a simplified version that detects tab in the input
  subroutine readline_with_completion(prompt, line, iostat)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat
    
    character(len=MAX_LINE_LEN) :: temp_line
    character(len=MAX_LINE_LEN) :: completions(50)
    integer :: num_completions, tab_pos
    
    ! Print prompt
    write(output_unit, '(a)', advance='no') prompt
    flush(output_unit)
    
    ! Read line using standard input
    read(input_unit, '(a)', iostat=iostat) temp_line
    
    if (iostat /= 0) then
      line = ''
      return
    end if
    
    ! Check for tab character in input (simplified detection)
    tab_pos = index(temp_line, char(KEY_TAB))
    if (tab_pos > 0) then
      ! Extract partial input before tab
      if (tab_pos == 1) then
        temp_line = ''
      else
        temp_line = temp_line(:tab_pos-1)
      end if
      
      ! Perform tab completion
      call tab_complete(temp_line, completions, num_completions)
      
      if (num_completions > 0) then
        if (num_completions == 1) then
          ! Single completion - auto-complete
          line = trim(temp_line) // trim(completions(1))
          write(output_unit, '(a)') trim(line)
        else
          ! Multiple completions - show options
          call show_completions(completions, num_completions)
          line = temp_line
        end if
      else
        line = temp_line
      end if
    else
      line = temp_line
    end if

    ! Note: History addition is now handled in the main loop AFTER expansion
  end subroutine

  subroutine add_to_history(line)
    character(len=*), intent(in) :: line
    ! Call enhanced version with current histcontrol setting
    call add_to_history_with_control(line, current_histcontrol)
  end subroutine

  ! Add command to history with HISTCONTROL support
  subroutine add_to_history_with_control(line, histcontrol)
    character(len=*), intent(in) :: line
    character(len=*), intent(in) :: histcontrol
    integer :: i
    logical :: ignorespace, ignoredups, ignoreboth, erasedups

    ! Parse HISTCONTROL settings
    ignorespace = index(histcontrol, 'ignorespace') > 0
    ignoredups = index(histcontrol, 'ignoredups') > 0
    ignoreboth = index(histcontrol, 'ignoreboth') > 0
    erasedups = index(histcontrol, 'erasedups') > 0

    ! Apply ignoreboth
    if (ignoreboth) then
      ignorespace = .true.
      ignoredups = .true.
    end if

    ! Check ignorespace: don't add if line starts with space
    if (ignorespace .and. len_trim(line) > 0) then
      if (line(1:1) == ' ') return
    end if

    ! Check ignoredups: don't add if duplicate of last command
    if (ignoredups .and. command_history%count > 0) then
      if (trim(command_history%lines(command_history%count)) == trim(line)) then
        return
      end if
    end if

    ! Check erasedups: remove all previous instances of this command
    if (erasedups) then
      do i = 1, command_history%count
        if (trim(command_history%lines(i)) == trim(line)) then
          call delete_history_entry(i)
          exit  ! Only one match possible after this
        end if
      end do
    end if

    ! Shift history if at max capacity
    if (command_history%count >= MAX_HISTORY) then
      do i = 1, MAX_HISTORY - 1
        command_history%lines(i) = command_history%lines(i + 1)
      end do
      command_history%count = MAX_HISTORY - 1
    end if

    ! Add new command
    command_history%count = command_history%count + 1
    command_history%lines(command_history%count) = line

    ! Reset current position
    command_history%current = command_history%count + 1
  end subroutine

  ! Delete a history entry by index
  subroutine delete_history_entry(index)
    integer, intent(in) :: index
    integer :: i

    if (index < 1 .or. index > command_history%count) return

    ! Shift remaining entries down
    do i = index, command_history%count - 1
      command_history%lines(i) = command_history%lines(i + 1)
    end do

    ! Decrement count
    command_history%count = command_history%count - 1

    ! Adjust current position if needed
    if (command_history%current > command_history%count + 1) then
      command_history%current = command_history%count + 1
    end if
  end subroutine

  subroutine get_history_line(index, line, found)
    integer, intent(in) :: index
    character(len=*), intent(out) :: line
    logical, intent(out) :: found
    
    if (index >= 1 .and. index <= command_history%count) then
      line = command_history%lines(index)
      found = .true.
    else
      line = ''
      found = .false.
    end if
  end subroutine

  function get_history_count() result(count)
    integer :: count
    count = command_history%count
  end function

  ! Show command history (for 'history' builtin)
  subroutine show_history()
    integer :: i
    
    if (command_history%count == 0) then
      write(output_unit, '(a)') 'No commands in history.'
    else
      do i = 1, command_history%count
        write(output_unit, '(i4,2x,a)') i, trim(command_history%lines(i))
      end do
    end if
  end subroutine

  ! Clear history
  subroutine clear_history()
    command_history%count = 0
    command_history%current = 0
  end subroutine

  ! Save history to file
  subroutine save_history_to_file(filepath, max_lines)
    character(len=*), intent(in) :: filepath
    integer, intent(in) :: max_lines
    integer :: unit, iostat, i, start_index

    ! Don't save if no history
    if (command_history%count == 0) return

    ! Calculate starting index based on max_lines
    if (max_lines > 0 .and. command_history%count > max_lines) then
      start_index = command_history%count - max_lines + 1
    else
      start_index = 1
    end if

    ! Open file for writing (truncate existing)
    open(newunit=unit, file=trim(filepath), status='replace', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: warning: could not save history to ' // trim(filepath)
      return
    end if

    ! Write history lines
    do i = start_index, command_history%count
      write(unit, '(a)', iostat=iostat) trim(command_history%lines(i))
      if (iostat /= 0) exit
    end do

    close(unit)
  end subroutine

  ! Load history from file
  subroutine load_history_from_file(filepath, max_lines)
    character(len=*), intent(in) :: filepath
    integer, intent(in) :: max_lines
    integer :: unit, iostat
    character(len=MAX_LINE_LEN) :: line
    logical :: file_exists

    ! Check if file exists
    inquire(file=filepath, exist=file_exists)
    if (.not. file_exists) return

    ! Open file for reading
    open(newunit=unit, file=trim(filepath), status='old', action='read', iostat=iostat)
    if (iostat /= 0) return

    ! Clear existing history
    command_history%count = 0
    command_history%current = 0

    ! Read lines
    do
      read(unit, '(a)', iostat=iostat) line
      if (iostat /= 0) exit  ! EOF or error

      ! Skip empty lines
      if (len_trim(line) == 0) cycle

      ! Add to history (respecting max_lines)
      if (max_lines > 0 .and. command_history%count >= max_lines) then
        ! Shift history to make room
        command_history%lines(1:MAX_HISTORY-1) = command_history%lines(2:MAX_HISTORY)
        command_history%count = command_history%count - 1
      end if

      ! Add to history without duplicate check (loading from file)
      command_history%count = command_history%count + 1
      command_history%lines(command_history%count) = line
    end do

    close(unit)
    command_history%current = command_history%count + 1
  end subroutine

  ! Append new history entries to file (for concurrent shells)
  subroutine append_history_to_file(filepath, start_index)
    character(len=*), intent(in) :: filepath
    integer, intent(in) :: start_index
    integer :: unit, iostat, i

    if (start_index > command_history%count) return

    ! Open file for appending
    open(newunit=unit, file=trim(filepath), status='old', position='append', action='write', iostat=iostat)
    if (iostat /= 0) then
      ! File doesn't exist, create it
      open(newunit=unit, file=trim(filepath), status='new', action='write', iostat=iostat)
      if (iostat /= 0) return
    end if

    ! Append new entries
    do i = start_index, command_history%count
      write(unit, '(a)', iostat=iostat) trim(command_history%lines(i))
      if (iostat /= 0) exit
    end do

    close(unit)
  end subroutine

  ! History expansion functions
  function expand_history(input_line) result(expanded_line)
    character(len=*), intent(in) :: input_line
    character(len=len(input_line)) :: expanded_line

    character(len=len(input_line)) :: work_line
    integer :: pos, expansion_start, expansion_end
    character(len=256) :: expansion, replacement
    logical :: found_expansion

    work_line = input_line
    expanded_line = ''
    pos = 1

    do while (pos <= len_trim(work_line))
      if (work_line(pos:pos) == '!' .and. pos <= len_trim(work_line)) then
        ! Found potential history expansion
        expansion_start = pos
        expansion_end = find_history_expansion_end(work_line, pos)

        if (expansion_end > expansion_start) then
          expansion = work_line(expansion_start:expansion_end)
          call process_history_expansion(expansion, replacement, found_expansion)

          if (found_expansion) then
            expanded_line = trim(expanded_line) // trim(replacement)
            pos = expansion_end + 1
          else
            expanded_line = trim(expanded_line) // '!'
            pos = pos + 1
          end if
        else
          expanded_line = trim(expanded_line) // '!'
          pos = pos + 1
        end if
      else
        expanded_line = trim(expanded_line) // work_line(pos:pos)
        pos = pos + 1
      end if
    end do
  end function

  function find_history_expansion_end(line, start_pos) result(end_pos)
    character(len=*), intent(in) :: line
    integer, intent(in) :: start_pos
    integer :: end_pos
    
    integer :: pos
    character :: ch
    
    pos = start_pos + 1  ! Skip the '!'
    end_pos = start_pos
    
    if (pos > len_trim(line)) return
    
    ch = line(pos:pos)
    
    if (ch == '!') then
      ! !! expansion
      end_pos = pos
    else if (ch >= '0' .and. ch <= '9') then
      ! !n expansion (number)
      do while (pos <= len_trim(line) .and. line(pos:pos) >= '0' .and. line(pos:pos) <= '9')
        end_pos = pos
        pos = pos + 1
      end do
    else if (ch == '-') then
      ! !-n expansion (negative number)
      pos = pos + 1
      if (pos <= len_trim(line) .and. line(pos:pos) >= '0' .and. line(pos:pos) <= '9') then
        do while (pos <= len_trim(line) .and. line(pos:pos) >= '0' .and. line(pos:pos) <= '9')
          end_pos = pos
          pos = pos + 1
        end do
      end if
    else if ((ch >= 'a' .and. ch <= 'z') .or. (ch >= 'A' .and. ch <= 'Z') .or. ch == '_') then
      ! !string expansion
      do while (pos <= len_trim(line) .and. &
                ((line(pos:pos) >= 'a' .and. line(pos:pos) <= 'z') .or. &
                 (line(pos:pos) >= 'A' .and. line(pos:pos) <= 'Z') .or. &
                 (line(pos:pos) >= '0' .and. line(pos:pos) <= '9') .or. &
                 line(pos:pos) == '_' .or. line(pos:pos) == '-'))
        end_pos = pos
        pos = pos + 1
      end do
    end if
  end function

  subroutine process_history_expansion(expansion, replacement, found)
    character(len=*), intent(in) :: expansion
    character(len=*), intent(out) :: replacement
    logical, intent(out) :: found
    
    character(len=256) :: search_pattern
    integer :: history_num, i, search_len
    
    replacement = ''
    found = .false.
    
    if (len_trim(expansion) < 2) return
    
    select case (expansion(2:2))
    case ('!')
      ! !! - last command
      if (command_history%count > 0) then
        replacement = command_history%lines(command_history%count)
        found = .true.
      end if
      
    case ('0':'9')
      ! !n - command number n
      read(expansion(2:), *, iostat=i) history_num
      if (i == 0 .and. history_num >= 1 .and. history_num <= command_history%count) then
        replacement = command_history%lines(history_num)
        found = .true.
      end if
      
    case ('-')
      ! !-n - n commands back
      if (len_trim(expansion) > 2) then
        read(expansion(3:), *, iostat=i) history_num
        if (i == 0 .and. history_num > 0) then
          history_num = command_history%count - history_num + 1
          if (history_num >= 1 .and. history_num <= command_history%count) then
            replacement = command_history%lines(history_num)
            found = .true.
          end if
        end if
      end if
      
    case default
      ! !string - last command starting with string
      search_pattern = expansion(2:)
      search_len = len_trim(search_pattern)
      
      if (search_len > 0) then
        ! Search backwards through history
        do i = command_history%count, 1, -1
          if (len_trim(command_history%lines(i)) >= search_len) then
            if (command_history%lines(i)(1:search_len) == search_pattern) then
              replacement = command_history%lines(i)
              found = .true.
              exit
            end if
          end if
        end do
      end if
    end select
  end subroutine

  function needs_history_expansion(line) result(needs_expansion)
    character(len=*), intent(in) :: line
    logical :: needs_expansion

    integer :: pos, old_pos

    needs_expansion = .false.
    pos = index(line, '!')

    do while (pos > 0 .and. pos <= len_trim(line))
      ! Check if this ! is the start of a history expansion
      if (pos == 1 .or. line(pos-1:pos-1) == ' ' .or. line(pos-1:pos-1) == char(9)) then
        ! Check what follows the ! (if there is something after it)
        if (pos < len_trim(line)) then
          if (line(pos+1:pos+1) == '!' .or. &
              (line(pos+1:pos+1) >= '0' .and. line(pos+1:pos+1) <= '9') .or. &
              line(pos+1:pos+1) == '-' .or. &
              (line(pos+1:pos+1) >= 'a' .and. line(pos+1:pos+1) <= 'z') .or. &
              (line(pos+1:pos+1) >= 'A' .and. line(pos+1:pos+1) <= 'Z')) then
            needs_expansion = .true.
            return
          end if
        end if
      end if

      ! Look for next !
      old_pos = pos
      pos = index(line(pos+1:), '!')
      if (pos > 0) pos = pos + old_pos
    end do
  end function

  ! Editing mode control functions
  subroutine set_editing_mode(input_state, mode)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: mode
    
    if (mode == EDITING_MODE_EMACS .or. mode == EDITING_MODE_VI) then
      input_state%editing_mode = mode
      if (mode == EDITING_MODE_VI) then
        input_state%vi_mode = VI_MODE_INSERT
      end if
    end if
  end subroutine

  subroutine handle_vi_mode_switch(input_state, key)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    
    if (input_state%editing_mode /= EDITING_MODE_VI) return
    
    select case (input_state%vi_mode)
    case (VI_MODE_INSERT)
      if (key == KEY_ESC) then
        input_state%vi_mode = VI_MODE_COMMAND
        ! Move cursor back one position in command mode
        if (input_state%cursor_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos - 1
        end if
        input_state%dirty = .true.
      end if
      
    case (VI_MODE_COMMAND)
      select case (key)
      case (ichar('i'))
        ! Insert mode
        input_state%vi_mode = VI_MODE_INSERT
      case (ichar('a'))
        ! Append mode
        input_state%vi_mode = VI_MODE_INSERT
        if (input_state%cursor_pos < input_state%length) then
          input_state%cursor_pos = input_state%cursor_pos + 1
        end if
      case (ichar('I'))
        ! Insert at beginning
        input_state%vi_mode = VI_MODE_INSERT
        input_state%cursor_pos = 0
      case (ichar('A'))
        ! Append at end
        input_state%vi_mode = VI_MODE_INSERT
        input_state%cursor_pos = input_state%length
      case (ichar('o'))
        ! Open new line below (simplified)
        input_state%vi_mode = VI_MODE_INSERT
        input_state%cursor_pos = input_state%length
      case (ichar('O'))
        ! Open new line above (simplified)
        input_state%vi_mode = VI_MODE_INSERT
        input_state%cursor_pos = 0
      end select
      input_state%dirty = .true.
    end select
  end subroutine

  subroutine handle_vi_command_mode(input_state, key)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    
    if (input_state%editing_mode /= EDITING_MODE_VI .or. input_state%vi_mode /= VI_MODE_COMMAND) return
    
    select case (key)
    ! Navigation
    case (ichar('h'))
      ! Move left
      if (input_state%cursor_pos > 0) then
        input_state%cursor_pos = input_state%cursor_pos - 1
        input_state%dirty = .true.
      end if
    case (ichar('l'))
      ! Move right
      if (input_state%cursor_pos < input_state%length - 1) then
        input_state%cursor_pos = input_state%cursor_pos + 1
        input_state%dirty = .true.
      end if
    case (ichar('j'))
      ! Move down (history down)
      call handle_history_down(input_state)
    case (ichar('k'))
      ! Move up (history up)
      call handle_history_up(input_state)
    case (ichar('0'))
      ! Beginning of line
      input_state%cursor_pos = 0
      input_state%dirty = .true.
    case (ichar('$'))
      ! End of line
      input_state%cursor_pos = input_state%length
      input_state%dirty = .true.
    case (ichar('w'))
      ! Next word
      call move_to_next_word(input_state)
    case (ichar('b'))
      ! Previous word
      call move_to_previous_word(input_state)
      
    ! Deletion
    case (ichar('x'))
      ! Delete character at cursor
      call delete_char_at_cursor(input_state)
    case (ichar('X'))
      ! Delete character before cursor
      if (input_state%cursor_pos > 0) then
        input_state%cursor_pos = input_state%cursor_pos - 1
        call delete_char_at_cursor(input_state)
      end if
    case (ichar('d'))
      ! Delete (simplified - would need more complex handling)
      call handle_vi_delete_command(input_state)
      
    ! Undo/Redo (simplified)
    case (ichar('u'))
      ! Undo (simplified)
      input_state%buffer = input_state%original_buffer
      input_state%length = len_trim(input_state%original_buffer)
      input_state%cursor_pos = min(input_state%cursor_pos, input_state%length)
      input_state%dirty = .true.
    end select
  end subroutine

  subroutine handle_vi_delete_command(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    ! Simplified delete command - just delete current character
    call delete_char_at_cursor(input_state)
  end subroutine

  subroutine move_to_next_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos
    
    pos = input_state%cursor_pos + 1
    
    ! Skip current word
    do while (pos <= input_state%length .and. input_state%buffer(pos:pos) /= ' ')
      pos = pos + 1
    end do
    
    ! Skip spaces
    do while (pos <= input_state%length .and. input_state%buffer(pos:pos) == ' ')
      pos = pos + 1
    end do
    
    input_state%cursor_pos = min(pos - 1, input_state%length)
    input_state%dirty = .true.
  end subroutine

  subroutine move_to_previous_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos
    
    if (input_state%cursor_pos <= 0) return
    
    pos = input_state%cursor_pos - 1
    
    ! Skip spaces
    do while (pos > 0 .and. input_state%buffer(pos:pos) == ' ')
      pos = pos - 1
    end do
    
    ! Find beginning of word
    do while (pos > 0 .and. input_state%buffer(pos:pos) /= ' ')
      pos = pos - 1
    end do
    
    if (input_state%buffer(pos:pos) == ' ') pos = pos + 1
    
    input_state%cursor_pos = pos
    input_state%dirty = .true.
  end subroutine

  subroutine delete_char_at_cursor(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i
    
    if (input_state%cursor_pos >= input_state%length) return
    
    ! Shift characters left
    do i = input_state%cursor_pos + 1, input_state%length - 1
      input_state%buffer(i:i) = input_state%buffer(i+1:i+1)
    end do
    
    input_state%length = input_state%length - 1
    input_state%buffer(input_state%length+1:input_state%length+1) = ' '
    input_state%dirty = .true.
  end subroutine

  function get_editing_mode_name(input_state) result(mode_name)
    type(input_state_t), intent(in) :: input_state
    character(len=16) :: mode_name
    
    select case (input_state%editing_mode)
    case (EDITING_MODE_EMACS)
      mode_name = 'emacs'
    case (EDITING_MODE_VI)
      if (input_state%vi_mode == VI_MODE_INSERT) then
        mode_name = 'vi-insert'
      else
        mode_name = 'vi-command'
      end if
    case default
      mode_name = 'unknown'
    end select
  end function

  ! Basic tab completion - simplified implementation
  subroutine tab_complete(partial_input, completions, num_completions)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)  ! Max 50 completions
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: last_word, dir_path, file_pattern
    integer :: last_space_pos, i
    
    num_completions = 0
    
    ! Find the last word to complete
    last_space_pos = 0
    do i = len_trim(partial_input), 1, -1
      if (partial_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do
    
    if (last_space_pos == 0) then
      last_word = trim(partial_input)
    else
      last_word = trim(partial_input(last_space_pos+1:))
    end if
    
    ! If it's the first word, complete commands
    if (last_space_pos == 0) then
      call complete_commands(last_word, completions, num_completions)
    else
      ! Otherwise, complete files/directories
      call complete_files(last_word, completions, num_completions)
    end if
  end subroutine

  ! Enhanced tab completion with real filesystem integration
  subroutine enhanced_tab_complete(partial_input, completions, num_completions)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: last_word, prefix_part
    integer :: last_space_pos, i
    logical :: is_command
    
    num_completions = 0
    
    ! Find the last word to complete
    last_space_pos = 0
    do i = len_trim(partial_input), 1, -1
      if (partial_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do
    
    if (last_space_pos == 0) then
      last_word = trim(partial_input)
      prefix_part = ''
      is_command = .true.
    else
      last_word = trim(partial_input(last_space_pos+1:))
      prefix_part = partial_input(:last_space_pos)
      is_command = .false.
    end if
    
    if (is_command) then
      ! Complete commands (builtins + PATH executables)
      call complete_commands_enhanced(last_word, completions, num_completions)
      
      ! Add prefix back to completions
      do i = 1, num_completions
        completions(i) = trim(completions(i))
      end do
    else
      ! Complete files and directories
      call complete_files_enhanced(last_word, completions, num_completions)

      ! Don't add prefix to completions - they are for display only
      ! The prefix will be added when constructing the completed line
    end if
  end subroutine

  subroutine complete_commands(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    
    character(len=50), parameter :: builtin_commands(19) = [ &
      'cd       ', 'echo     ', 'exit     ', 'export   ', &
      'pwd      ', 'jobs     ', 'fg       ', 'bg       ', &
      'history  ', 'source   ', 'test     ', 'if       ', &
      'kill     ', 'wait     ', 'trap     ', 'config   ', &
      'alias    ', 'unalias  ', 'help     ' &
    ]
    integer :: i, prefix_len
    
    num_completions = 0
    prefix_len = len_trim(prefix)
    
    ! Complete builtin commands
    do i = 1, size(builtin_commands)
      if (prefix_len == 0 .or. &
          index(trim(builtin_commands(i)), prefix(1:prefix_len)) == 1) then
        num_completions = num_completions + 1
        if (num_completions <= 50) then
          completions(num_completions) = trim(builtin_commands(i))
        end if
      end if
    end do
    
    ! TODO: Add external command completion from PATH
  end subroutine

  subroutine complete_files(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: dir_path, file_pattern, current_dir
    integer :: last_slash_pos, i
    
    num_completions = 0
    
    ! Extract directory path and filename pattern
    last_slash_pos = 0
    do i = len_trim(prefix), 1, -1
      if (prefix(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do
    
    if (last_slash_pos > 0) then
      dir_path = prefix(:last_slash_pos-1)
      file_pattern = prefix(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(prefix)
    end if
    
    ! Add common directory completions
    if (len_trim(file_pattern) == 0 .or. file_pattern(1:1) == '.') then
      if (num_completions < 50) then
        num_completions = num_completions + 1
        if (trim(dir_path) == '.') then
          completions(num_completions) = './'
        else
          completions(num_completions) = trim(dir_path) // '/./'
        end if
      end if
      
      if (len_trim(file_pattern) == 0 .or. index(file_pattern, '..') == 1) then
        if (num_completions < 50) then
          num_completions = num_completions + 1
          if (trim(dir_path) == '.') then
            completions(num_completions) = '../'
          else
            completions(num_completions) = trim(dir_path) // '/../'
          end if
        end if
      end if
    end if
    
    ! Add some common file extensions for demonstration
    if (len_trim(file_pattern) == 0) then
      if (num_completions < 47) then
        completions(num_completions + 1) = 'Makefile'
        completions(num_completions + 2) = 'README'
        completions(num_completions + 3) = 'LICENSE'
        num_completions = num_completions + 3
      end if
    end if
  end subroutine

  ! Enhanced command completion with PATH executable scanning
  subroutine complete_commands_enhanced(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    
    character(len=50), parameter :: builtin_commands(20) = [ &
      'cd       ', 'echo     ', 'exit     ', 'export   ', &
      'pwd      ', 'jobs     ', 'fg       ', 'bg       ', &
      'history  ', 'source   ', 'test     ', 'if       ', &
      'kill     ', 'wait     ', 'trap     ', 'config   ', &
      'alias    ', 'unalias  ', 'help     ', 'rawtest  ' &
    ]
    integer :: i, prefix_len
    
    num_completions = 0
    prefix_len = len_trim(prefix)
    
    ! Complete builtin commands
    do i = 1, size(builtin_commands)
      if (prefix_len == 0 .or. &
          index(trim(builtin_commands(i)), prefix(1:prefix_len)) == 1) then
        num_completions = num_completions + 1
        if (num_completions <= 50) then
          completions(num_completions) = trim(builtin_commands(i))
        end if
      end if
    end do
    
    ! Add common system commands
    call add_system_commands(prefix, completions, num_completions)
  end subroutine

  subroutine add_system_commands(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(inout) :: completions(50)
    integer, intent(inout) :: num_completions
    
    character(len=50), parameter :: common_commands(15) = [ &
      'ls       ', 'cat      ', 'grep     ', 'find     ', &
      'sort     ', 'head     ', 'tail     ', 'wc       ', &
      'cp       ', 'mv       ', 'rm       ', 'mkdir    ', &
      'rmdir    ', 'chmod    ', 'which    ' &
    ]
    integer :: i, prefix_len
    
    prefix_len = len_trim(prefix)
    
    do i = 1, size(common_commands)
      if (num_completions >= 50) exit
      if (prefix_len == 0 .or. &
          index(trim(common_commands(i)), prefix(1:prefix_len)) == 1) then
        num_completions = num_completions + 1
        completions(num_completions) = trim(common_commands(i))
      end if
    end do
  end subroutine

  ! Enhanced file completion with real filesystem access
  subroutine complete_files_enhanced(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    integer :: last_slash_pos, i
    
    num_completions = 0
    
    ! Extract directory path and filename pattern
    last_slash_pos = 0
    do i = len_trim(prefix), 1, -1
      if (prefix(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do
    
    if (last_slash_pos > 0) then
      dir_path = prefix(:last_slash_pos-1)
      file_pattern = prefix(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(prefix)
    end if
    
    ! Add directory navigation options
    if (len_trim(file_pattern) == 0 .or. file_pattern(1:1) == '.') then
      ! Current directory
      if (num_completions < 50) then
        num_completions = num_completions + 1
        if (trim(dir_path) == '.') then
          completions(num_completions) = './'
        else
          completions(num_completions) = trim(dir_path) // '/./'
        end if
      end if
      
      ! Parent directory
      if (len_trim(file_pattern) == 0 .or. index(file_pattern, '..') == 1) then
        if (num_completions < 50) then
          num_completions = num_completions + 1
          if (trim(dir_path) == '.') then
            completions(num_completions) = '../'
          else
            completions(num_completions) = trim(dir_path) // '/../'
          end if
        end if
      end if
    end if
    
    ! Get actual filesystem entries
    call scan_directory(dir_path, file_pattern, completions, num_completions)
  end subroutine

  ! Scan directory for matching files and directories
  subroutine scan_directory(dir_path, pattern, completions, num_completions)
    character(len=*), intent(in) :: dir_path, pattern
    character(len=MAX_LINE_LEN), intent(inout) :: completions(50)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: ls_command, ls_output
    character(len=MAX_LINE_LEN) :: entries(100)  ! Temp storage for directory entries
    character(len=MAX_LINE_LEN) :: full_path
    integer :: num_entries, i, pattern_len
    logical :: is_dir

    pattern_len = len_trim(pattern)

    ! Use ls command to get directory listing
    ls_command = 'ls -1a "' // trim(dir_path) // '" 2>/dev/null'
    ls_output = execute_and_capture(ls_command)

    ! Parse ls output into individual entries
    call parse_ls_output(ls_output, entries, num_entries)

    ! Filter entries by pattern and add to completions
    do i = 1, num_entries
      if (num_completions >= 50) exit

      ! Skip . and .. unless explicitly requested
      if (trim(entries(i)) == '.' .or. trim(entries(i)) == '..') then
        if (pattern_len == 0 .or. (pattern_len > 0 .and. pattern(1:1) /= '.')) then
          cycle
        end if
      end if

      ! Check if entry matches pattern
      if (pattern_len == 0 .or. index(entries(i), pattern(1:pattern_len)) == 1) then
        num_completions = num_completions + 1

        ! Build full path for directory check
        if (trim(dir_path) == '.') then
          full_path = trim(entries(i))
        else
          full_path = trim(dir_path) // '/' // trim(entries(i))
        end if

        ! Check if it's a directory and add trailing slash
        is_dir = is_directory(full_path)
        if (is_dir) then
          completions(num_completions) = trim(full_path) // '/'
        else
          completions(num_completions) = trim(full_path)
        end if
      end if
    end do
  end subroutine

  ! Check if a path is a directory
  function is_directory(path) result(is_dir)
    character(len=*), intent(in) :: path
    logical :: is_dir
    character(len=MAX_LINE_LEN) :: test_command, output

    ! Use test command to check if path is a directory
    test_command = 'test -d "' // trim(path) // '" && echo "yes" || echo "no"'
    output = execute_and_capture(test_command)
    is_dir = (index(output, 'yes') > 0)
  end function

  ! Parse ls output into individual entries
  subroutine parse_ls_output(output, entries, num_entries)
    character(len=*), intent(in) :: output
    character(len=MAX_LINE_LEN), intent(out) :: entries(100)
    integer, intent(out) :: num_entries
    
    integer :: pos, start, output_len
    
    num_entries = 0
    pos = 1
    output_len = len_trim(output)
    
    do while (pos <= output_len .and. num_entries < 100)
      ! Skip whitespace
      do while (pos <= output_len .and. (output(pos:pos) == ' ' .or. output(pos:pos) == char(9)))
        pos = pos + 1
      end do
      
      if (pos > output_len) exit
      
      start = pos
      
      ! Find end of entry (newline or space)
      do while (pos <= output_len .and. output(pos:pos) /= char(10) .and. output(pos:pos) /= ' ')
        pos = pos + 1
      end do
      
      if (pos > start) then
        num_entries = num_entries + 1
        entries(num_entries) = output(start:pos-1)
      end if
      
      pos = pos + 1
    end do
  end subroutine

  subroutine show_completions(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(in) :: completions(50)
    integer, intent(in) :: num_completions
    integer :: i
    
    if (num_completions > 1) then
      write(output_unit, '(a)') ''
      do i = 1, num_completions
        write(output_unit, '(a)', advance='no') trim(completions(i)) // '  '
        if (mod(i, 8) == 0) write(output_unit, '(a)') ''  ! New line every 8 items
      end do
      write(output_unit, '(a)') ''
    end if
  end subroutine

  ! Find common prefix among completions
  function get_common_prefix(completions, num_completions) result(prefix)
    character(len=MAX_LINE_LEN), intent(in) :: completions(50)
    integer, intent(in) :: num_completions
    character(len=MAX_LINE_LEN) :: prefix
    
    integer :: i, j, min_len, common_len
    logical :: matches
    
    prefix = ''
    if (num_completions == 0) return
    
    if (num_completions == 1) then
      prefix = trim(completions(1))
      return
    end if
    
    ! Find minimum length
    min_len = len_trim(completions(1))
    do i = 2, num_completions
      min_len = min(min_len, len_trim(completions(i)))
    end do
    
    ! Find common prefix length
    common_len = 0
    do j = 1, min_len
      matches = .true.
      do i = 2, num_completions
        if (completions(1)(j:j) /= completions(i)(j:j)) then
          matches = .false.
          exit
        end if
      end do
      
      if (matches) then
        common_len = j
      else
        exit
      end if
    end do
    
    if (common_len > 0) then
      prefix = completions(1)(:common_len)
    end if
  end function

  ! Enhanced tab completion that handles partial completion
  subroutine smart_tab_complete(partial_input, completions, num_completions, completed_line, completed)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    character(len=*), intent(out) :: completed_line
    logical, intent(out) :: completed

    character(len=MAX_LINE_LEN) :: common_prefix, prefix_part
    integer :: last_space_pos, i

    completed = .false.
    completed_line = partial_input

    ! Find the prefix (command and any earlier arguments)
    last_space_pos = 0
    do i = len_trim(partial_input), 1, -1
      if (partial_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do

    if (last_space_pos > 0) then
      prefix_part = partial_input(:last_space_pos)
    else
      prefix_part = ''
    end if

    call enhanced_tab_complete(partial_input, completions, num_completions)

    if (num_completions == 0) then
      ! No completions found
      return
    else if (num_completions == 1) then
      ! Single completion - add prefix back (preserve spacing)
      if (last_space_pos > 0) then
        completed_line = prefix_part(:last_space_pos) // trim(completions(1))
      else
        completed_line = trim(completions(1))
      end if
      completed = .true.
    else
      ! Multiple completions - try common prefix
      common_prefix = get_common_prefix(completions, num_completions)

      if (len_trim(common_prefix) > 0) then
        if (last_space_pos > 0) then
          completed_line = prefix_part(:last_space_pos) // trim(common_prefix)
        else
          completed_line = trim(common_prefix)
        end if
        completed = .true.
      end if
    end if
  end subroutine

  ! Helper functions for enhanced readline
  subroutine insert_char(input_state, ch)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: ch
    integer :: i

    ! Check if we have room
    if (input_state%length >= MAX_LINE_LEN) return

    ! If we're browsing history, exit history mode when typing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Reset completion state when buffer changes
    input_state%completions_shown = .false.
    
    ! If cursor is at end, simple append
    if (input_state%cursor_pos >= input_state%length) then
      input_state%length = input_state%length + 1
      input_state%buffer(input_state%length:input_state%length) = ch
      input_state%cursor_pos = input_state%length
      write(output_unit, '(a)', advance='no') ch
      flush(output_unit)
    else
      ! Insert in middle - shift characters right
      do i = input_state%length, input_state%cursor_pos + 1, -1
        input_state%buffer(i+1:i+1) = input_state%buffer(i:i)
      end do
      input_state%cursor_pos = input_state%cursor_pos + 1
      input_state%buffer(input_state%cursor_pos:input_state%cursor_pos) = ch
      input_state%length = input_state%length + 1
      input_state%dirty = .true.
    end if
  end subroutine
  
  subroutine handle_backspace(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i

    if (input_state%cursor_pos <= 0) return

    ! If we're browsing history, exit history mode when editing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Reset completion state when buffer changes
    input_state%completions_shown = .false.
    
    ! If cursor is at end, simple deletion
    if (input_state%cursor_pos >= input_state%length) then
      input_state%length = input_state%length - 1
      input_state%cursor_pos = input_state%cursor_pos - 1
      input_state%buffer(input_state%length+1:input_state%length+1) = ' '
      write(output_unit, '(a)', advance='no') char(8) // ' ' // char(8)  ! Backspace, space, backspace
      flush(output_unit)
    else
      ! Delete in middle - shift characters left
      do i = input_state%cursor_pos, input_state%length - 1
        input_state%buffer(i:i) = input_state%buffer(i+1:i+1)
      end do
      input_state%cursor_pos = input_state%cursor_pos - 1
      input_state%length = input_state%length - 1
      input_state%buffer(input_state%length+1:input_state%length+1) = ' '
      input_state%dirty = .true.
    end if
  end subroutine
  
  subroutine handle_tab_completion(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: partial_input
    character(len=MAX_LINE_LEN) :: completions(50)
    character(len=MAX_LINE_LEN) :: completed_line
    character(len=MAX_LINE_LEN) :: saved_input
    integer :: num_completions
    logical :: completed, made_progress, buffer_changed

    ! Exit history mode if we're browsing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Get the current buffer content
    partial_input = input_state%buffer(:input_state%length)
    saved_input = partial_input

    ! Check if buffer has changed since we last showed completions
    buffer_changed = (trim(input_state%buffer(:input_state%length)) /= &
                     trim(input_state%last_completion_buffer))

    ! Attempt smart completion
    call smart_tab_complete(partial_input, completions, num_completions, completed_line, completed)

    if (completed) then
      ! Check if we made actual progress
      made_progress = (len_trim(completed_line) > len_trim(saved_input))

      ! Update the input buffer with completion
      input_state%buffer = completed_line
      input_state%length = len_trim(completed_line)
      input_state%cursor_pos = input_state%length
      input_state%dirty = .true.

      if (num_completions > 1) then
        if (made_progress) then
          ! We completed to common prefix - don't show options yet
          ! User can press tab again to see options
          input_state%completions_shown = .false.
        else
          ! At common prefix already - show available options only if not already shown
          if (.not. input_state%completions_shown .or. buffer_changed) then
            write(output_unit, '()')  ! New line
            call show_completions(completions, num_completions)
            input_state%last_completion_buffer = input_state%buffer(:input_state%length)
            input_state%completions_shown = .true.
            input_state%dirty = .true.
          end if
        end if
      else
        ! Single completion - reset flag
        input_state%completions_shown = .false.
      end if
    else
      ! No completions found - ring bell (ASCII 7)
      write(output_unit, '(a)', advance='no') char(7)  ! Bell for audio feedback
      flush(output_unit)
    end if
  end subroutine
  
  subroutine handle_escape_sequence(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character :: ch1, ch2
    logical :: success

    ! Check if we're in Vi insert mode - ESC switches to command mode
    if (input_state%editing_mode == EDITING_MODE_VI .and. &
        input_state%vi_mode == VI_MODE_INSERT) then
      call handle_vi_mode_switch(input_state, KEY_ESC)
      return
    end if

    ! Try to read the next character
    success = read_single_char(ch1)
    if (.not. success) return

    if (ch1 == '[') then
      ! ANSI escape sequence
      success = read_single_char(ch2)
      if (.not. success) return

      select case(ch2)
      case('A')  ! Up arrow
        call handle_history_up(input_state)
      case('B')  ! Down arrow
        call handle_history_down(input_state)
      case('C')  ! Right arrow
        call handle_cursor_right(input_state)
      case('D')  ! Left arrow
        call handle_cursor_left(input_state)
      case default
        ! Unknown escape sequence
        continue
      end select
    end if
  end subroutine
  
  subroutine handle_cursor_left(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    if (input_state%cursor_pos > 0) then
      input_state%cursor_pos = input_state%cursor_pos - 1
      write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
      flush(output_unit)
    end if
  end subroutine
  
  subroutine handle_cursor_right(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    if (input_state%cursor_pos < input_state%length) then
      input_state%cursor_pos = input_state%cursor_pos + 1
      write(output_unit, '(a)', advance='no') ESC_CURSOR_RIGHT
      flush(output_unit)
    end if
  end subroutine
  
  subroutine handle_history_up(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: history_line
    logical :: found
    
    ! If not currently browsing history, save the current input
    if (.not. input_state%in_history) then
      input_state%original_buffer = input_state%buffer
      input_state%history_pos = command_history%count + 1
      input_state%in_history = .true.
    end if
    
    ! Move up in history
    if (input_state%history_pos > 1) then
      input_state%history_pos = input_state%history_pos - 1
      call get_history_line(input_state%history_pos, history_line, found)
      
      if (found) then
        input_state%buffer = history_line
        input_state%length = len_trim(history_line)
        input_state%cursor_pos = input_state%length
        input_state%dirty = .true.
      end if
    end if
  end subroutine
  
  subroutine handle_history_down(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: history_line
    logical :: found
    
    ! Only navigate down if we're currently in history
    if (.not. input_state%in_history) return
    
    ! Move down in history
    if (input_state%history_pos < command_history%count) then
      input_state%history_pos = input_state%history_pos + 1
      call get_history_line(input_state%history_pos, history_line, found)
      
      if (found) then
        input_state%buffer = history_line
        input_state%length = len_trim(history_line)
        input_state%cursor_pos = input_state%length
        input_state%dirty = .true.
      end if
    else if (input_state%history_pos <= command_history%count) then
      ! Reached the end of history, restore original input
      input_state%buffer = input_state%original_buffer
      input_state%length = len_trim(input_state%original_buffer)
      input_state%cursor_pos = input_state%length
      input_state%history_pos = command_history%count + 1
      input_state%in_history = .false.
      input_state%dirty = .true.
    end if
  end subroutine
  
  subroutine redraw_line(prompt, input_state)
    character(len=*), intent(in) :: prompt
    type(input_state_t), intent(in) :: input_state
    integer :: i
    
    ! Move to beginning of line and clear it
    write(output_unit, '(a)', advance='no') ESC_MOVE_BOL // ESC_CLEAR_LINE
    
    ! Redraw prompt and current buffer
    write(output_unit, '(a)', advance='no') prompt
    if (input_state%length > 0) then
      write(output_unit, '(a)', advance='no') input_state%buffer(:input_state%length)
    end if
    
    ! Position cursor correctly
    do i = input_state%length, input_state%cursor_pos + 1, -1
      write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
    end do
    
    flush(output_unit)
  end subroutine

  ! Advanced line editing functions for Phase 5
  subroutine handle_home(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    ! Move cursor to beginning of line
    if (input_state%cursor_pos > 0) then
      do while (input_state%cursor_pos > 0)
        write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
        input_state%cursor_pos = input_state%cursor_pos - 1
      end do
      flush(output_unit)
    end if
  end subroutine
  
  subroutine handle_end(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    ! Move cursor to end of line
    do while (input_state%cursor_pos < input_state%length)
      write(output_unit, '(a)', advance='no') ESC_CURSOR_RIGHT
      input_state%cursor_pos = input_state%cursor_pos + 1
    end do
    flush(output_unit)
  end subroutine
  
  subroutine handle_kill_to_end(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    ! Save text from cursor to end of line in kill buffer
    if (input_state%cursor_pos < input_state%length) then
      input_state%kill_buffer = input_state%buffer(input_state%cursor_pos+1:input_state%length)
      input_state%kill_length = input_state%length - input_state%cursor_pos
      
      ! Clear from cursor to end of line
      input_state%length = input_state%cursor_pos
      input_state%dirty = .true.
    else
      ! Nothing to kill
      input_state%kill_length = 0
    end if
  end subroutine
  
  subroutine handle_kill_line(input_state)
    type(input_state_t), intent(inout) :: input_state
    
    ! Save entire line in kill buffer
    if (input_state%length > 0) then
      input_state%kill_buffer = input_state%buffer(:input_state%length)
      input_state%kill_length = input_state%length
      
      ! Clear the line
      input_state%buffer = ''
      input_state%length = 0
      input_state%cursor_pos = 0
      input_state%dirty = .true.
    else
      input_state%kill_length = 0
    end if
  end subroutine
  
  subroutine handle_kill_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_start, i
    
    if (input_state%cursor_pos == 0) then
      input_state%kill_length = 0
      return
    end if
    
    ! Find start of current word (skip trailing spaces first)
    word_start = input_state%cursor_pos
    
    ! Skip any trailing whitespace
    do while (word_start > 0 .and. input_state%buffer(word_start:word_start) == ' ')
      word_start = word_start - 1
    end do
    
    ! Find beginning of word (non-space characters)
    do while (word_start > 0 .and. input_state%buffer(word_start:word_start) /= ' ')
      word_start = word_start - 1
    end do
    
    ! word_start is now at space before word, or 0 if at beginning
    if (word_start < input_state%cursor_pos) then
      ! Save killed text
      input_state%kill_buffer = input_state%buffer(word_start+1:input_state%cursor_pos)
      input_state%kill_length = input_state%cursor_pos - word_start
      
      ! Shift remaining text left
      do i = word_start + 1, input_state%length - input_state%cursor_pos + word_start
        if (input_state%cursor_pos + i - word_start <= input_state%length) then
          input_state%buffer(i:i) = input_state%buffer(input_state%cursor_pos + i - word_start: &
                                                        input_state%cursor_pos + i - word_start)
        else
          input_state%buffer(i:i) = ' '
        end if
      end do
      
      ! Update length and cursor position
      input_state%length = input_state%length - (input_state%cursor_pos - word_start)
      input_state%cursor_pos = word_start
      input_state%dirty = .true.
    else
      input_state%kill_length = 0
    end if
  end subroutine
  
  subroutine handle_yank(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, insert_len
    
    if (input_state%kill_length == 0) return
    
    insert_len = min(input_state%kill_length, MAX_LINE_LEN - input_state%length)
    if (insert_len == 0) return
    
    ! Shift existing text right to make room
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        input_state%buffer(i + insert_len:i + insert_len) = input_state%buffer(i:i)
      end if
    end do
    
    ! Insert killed text at cursor position
    do i = 1, insert_len
      input_state%buffer(input_state%cursor_pos + i:input_state%cursor_pos + i) = &
        input_state%kill_buffer(i:i)
    end do
    
    ! Update length and cursor position
    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
  end subroutine
  
  subroutine handle_clear_screen(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt

    ! Clear screen with ANSI escape sequence
    write(output_unit, '(a)', advance='no') char(27) // '[2J' // char(27) // '[H'
    flush(output_unit)

    ! Immediately redraw the prompt and current line
    write(output_unit, '(a)', advance='no') prompt
    if (input_state%length > 0) then
      write(output_unit, '(a)', advance='no') input_state%buffer(:input_state%length)
    end if
    flush(output_unit)

    ! Don't need dirty flag since we just redrew
    input_state%dirty = .false.
  end subroutine

  ! Cursor flash effect for visual feedback
  subroutine cursor_flash_effect()
    integer :: i, j
    integer, parameter :: FLASH_COUNT = 3
    integer, parameter :: DELAY_ITERATIONS = 50000

    ! Flash cursor multiple times with visible delay
    do i = 1, FLASH_COUNT
      ! Hide cursor
      write(output_unit, '(a)', advance='no') ESC_HIDE_CURSOR
      flush(output_unit)

      ! Small delay using busy-wait
      do j = 1, DELAY_ITERATIONS
        ! Busy wait
      end do

      ! Show cursor
      write(output_unit, '(a)', advance='no') ESC_SHOW_CURSOR
      flush(output_unit)

      ! Small delay using busy-wait
      do j = 1, DELAY_ITERATIONS
        ! Busy wait
      end do
    end do
  end subroutine

  ! Reverse-i-search implementation
  subroutine handle_reverse_search(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt

    ! Save current buffer if entering search for first time
    if (.not. input_state%in_search) then
      input_state%original_buffer = input_state%buffer(:input_state%length)
      input_state%in_search = .true.
      input_state%search_string = ''
      input_state%search_length = 0
      input_state%search_match_index = 0
    else
      ! Ctrl+R pressed again - find next match
      call search_next_match(input_state)
    end if

    ! Display search prompt
    call update_search_display(input_state, prompt)
  end subroutine

  subroutine search_next_match(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i
    character(len=MAX_LINE_LEN) :: search_str

    if (input_state%search_length == 0) return

    search_str = input_state%search_string(:input_state%search_length)

    ! Start from current match and search backwards
    do i = input_state%search_match_index - 1, 1, -1
      if (index(command_history%lines(i), trim(search_str)) > 0) then
        input_state%search_match_index = i
        input_state%buffer = command_history%lines(i)
        input_state%length = len_trim(command_history%lines(i))
        input_state%cursor_pos = input_state%length
        return
      end if
    end do

    ! Wrap around to end if no match found
    if (input_state%search_match_index > 0) then
      do i = command_history%count, input_state%search_match_index + 1, -1
        if (index(command_history%lines(i), trim(search_str)) > 0) then
          input_state%search_match_index = i
          input_state%buffer = command_history%lines(i)
          input_state%length = len_trim(command_history%lines(i))
          input_state%cursor_pos = input_state%length
          return
        end if
      end do
    end if
  end subroutine

  subroutine search_add_char(input_state, ch, prompt)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: ch
    character(len=*), intent(in) :: prompt
    integer :: i
    character(len=MAX_LINE_LEN) :: search_str

    ! Add character to search string
    if (input_state%search_length < MAX_LINE_LEN) then
      input_state%search_length = input_state%search_length + 1
      input_state%search_string(input_state%search_length:input_state%search_length) = ch

      ! Search backwards through history
      search_str = input_state%search_string(:input_state%search_length)
      do i = command_history%count, 1, -1
        if (index(command_history%lines(i), trim(search_str)) > 0) then
          input_state%search_match_index = i
          input_state%buffer = command_history%lines(i)
          input_state%length = len_trim(command_history%lines(i))
          input_state%cursor_pos = input_state%length
          exit
        end if
      end do

      call update_search_display(input_state, prompt)
    end if
  end subroutine

  subroutine search_backspace(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    integer :: i
    character(len=MAX_LINE_LEN) :: search_str

    if (input_state%search_length > 0) then
      input_state%search_length = input_state%search_length - 1

      if (input_state%search_length > 0) then
        ! Search again with shorter string
        search_str = input_state%search_string(:input_state%search_length)
        do i = command_history%count, 1, -1
          if (index(command_history%lines(i), trim(search_str)) > 0) then
            input_state%search_match_index = i
            input_state%buffer = command_history%lines(i)
            input_state%length = len_trim(command_history%lines(i))
            input_state%cursor_pos = input_state%length
            exit
          end if
        end do
      else
        ! Empty search - clear buffer
        input_state%buffer = ''
        input_state%length = 0
        input_state%cursor_pos = 0
        input_state%search_match_index = 0
      end if

      call update_search_display(input_state, prompt)
    end if
  end subroutine

  subroutine cancel_search(input_state)
    type(input_state_t), intent(inout) :: input_state

    ! Restore original buffer
    input_state%buffer = input_state%original_buffer
    input_state%length = len_trim(input_state%original_buffer)
    input_state%cursor_pos = input_state%length
    input_state%in_search = .false.
    input_state%search_string = ''
    input_state%search_length = 0
    input_state%search_match_index = 0
    input_state%dirty = .true.
  end subroutine

  subroutine accept_search(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt

    ! Keep the current buffer (matched command)
    input_state%in_search = .false.
    input_state%search_string = ''
    input_state%search_length = 0
    input_state%search_match_index = 0

    ! Clear the search prompt and show normal prompt with result
    write(output_unit, '(a)', advance='no') char(13) // ESC_CLEAR_LINE
    write(output_unit, '(a)', advance='no') prompt
    if (input_state%length > 0) then
      write(output_unit, '(a)') input_state%buffer(:input_state%length)
    else
      write(output_unit, '()')
    end if
    flush(output_unit)
  end subroutine

  subroutine update_search_display(input_state, prompt)
    type(input_state_t), intent(in) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=512) :: search_prompt

    ! Build search prompt
    if (input_state%search_length > 0) then
      write(search_prompt, '(a,a,a)') '(reverse-i-search)`', &
            input_state%search_string(:input_state%search_length), "': "
    else
      search_prompt = '(reverse-i-search)`'': '
    end if

    ! Clear line and redraw
    write(output_unit, '(a)', advance='no') char(13) // ESC_CLEAR_LINE
    write(output_unit, '(a)', advance='no') trim(search_prompt)
    if (input_state%length > 0) then
      write(output_unit, '(a)', advance='no') input_state%buffer(:input_state%length)
    end if
    flush(output_unit)
  end subroutine

end module readline