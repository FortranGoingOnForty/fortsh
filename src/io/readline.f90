! ==============================================================================
! Module: readline
! Purpose: Advanced input handling with command history and line editing
! ==============================================================================
module readline
  use shell_types
  use system_interface
  use completion, only: get_completion_spec, generate_completions, completion_spec_t, MAX_COMPLETIONS
  use syntax_highlight, only: highlight_command_line, init_syntax_highlighting
  use abbreviations, only: try_expand_abbreviation
  use glob, only: pattern_matches
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
  integer, parameter :: KEY_CTRL_S = 19   ! Forward-i-search
  integer, parameter :: KEY_CTRL_G = 7    ! Cancel (alternate to Ctrl+C)
  integer, parameter :: KEY_CTRL_T = 20   ! Transpose characters
  integer, parameter :: KEY_ESC = 27
  integer, parameter :: KEY_UP = 65
  integer, parameter :: KEY_DOWN = 66
  integer, parameter :: KEY_RIGHT = 67
  integer, parameter :: KEY_LEFT = 68
  
  ! History and line management
  integer, parameter :: MAX_HISTORY = 1000
  integer, parameter :: MAX_LINE_LEN = 1024

  ! Glob expansion constants (from glob module)
  integer, parameter :: MAX_GLOB_MATCHES = 1000
  ! MAX_TOKEN_LEN is already defined in shell_types
  
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
    logical :: in_search = .false. ! Currently in i-search mode (forward or reverse)
    logical :: search_forward = .false. ! True = forward, False = reverse
    character(len=MAX_LINE_LEN) :: search_string = '' ! Current search query
    integer :: search_length = 0 ! Length of search string
    integer :: search_match_index = 0 ! Current history match index

    ! Editing mode support
    integer :: editing_mode = EDITING_MODE_EMACS
    integer :: vi_mode = VI_MODE_INSERT
    character(len=MAX_LINE_LEN) :: vi_command_buffer = ''
    integer :: vi_command_count = 0
    logical :: vi_repeat_pending = .false.

    ! Advanced vi mode features
    character(len=MAX_LINE_LEN) :: vi_yank_buffer = ''  ! Vi-style yank buffer
    integer :: vi_yank_length = 0
    integer :: vi_marks(26) = 0  ! Mark positions for 'a'-'z' (0 = not set)
    character(len=MAX_LINE_LEN) :: vi_search_pattern = ''
    integer :: vi_search_length = 0
    logical :: vi_search_forward = .true.
    logical :: vi_in_vi_search = .false.

    ! Autosuggestion support (fish-style)
    character(len=MAX_LINE_LEN) :: suggestion = ''  ! Current suggestion from history
    integer :: suggestion_length = 0  ! Length of suggestion

    ! Menu selection support (zsh/fish-style interactive completion)
    logical :: in_menu_select = .false.  ! Currently in menu selection mode
    character(len=MAX_LINE_LEN) :: menu_items(50) = ''  ! Completion items for menu
    integer :: menu_num_items = 0  ! Number of items in menu
    integer :: menu_selection = 1  ! Currently selected item (1-based)
    character(len=MAX_LINE_LEN) :: menu_prefix = ''  ! Command prefix before completion word
    integer :: menu_prefix_len = 0  ! Actual length of prefix INCLUDING trailing space
  end type input_state_t

  type :: history_t
    character(len=MAX_LINE_LEN) :: lines(MAX_HISTORY)
    integer :: count = 0
    integer :: current = 0  ! Current position in history navigation
  end type history_t

  type(history_t), save :: command_history

  ! Type to hold completion candidates with scores for fuzzy matching
  type :: scored_completion_t
    character(len=MAX_LINE_LEN) :: text
    integer :: score
  end type scored_completion_t

  ! Module-level HISTCONTROL setting (set by shell)
  character(len=256), save :: current_histcontrol = ''

  ! Module-level editing mode (set by shell via option_vi)
  integer, save :: global_editing_mode = EDITING_MODE_EMACS

  ! Detect macOS to work around menu mode crashes
  logical, save :: is_macos_system = .false.
  logical, save :: macos_detected = .false.

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

  ! Check if we're on macOS (called once at startup)
  subroutine detect_macos()
    character(len=256) :: sysname
    integer :: status

    if (.not. macos_detected) then
      ! First try OSTYPE environment variable
      call get_environment_variable("OSTYPE", sysname, status=status)
      if (status == 0) then
        is_macos_system = (index(sysname, "darwin") > 0)
      else
        ! Try checking for macOS-specific environment variables
        call get_environment_variable("__CF_USER_TEXT_ENCODING", sysname, status=status)
        if (status == 0) then
          ! This env var is macOS-specific
          is_macos_system = .true.
        else
          ! Check for another Apple-specific env variable
          call get_environment_variable("Apple_PubSub_Socket_Render", sysname, status=status)
          is_macos_system = (status == 0)
        end if
      end if
      macos_detected = .true.
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
    input_state%suggestion = ''
    input_state%suggestion_length = 0

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
          ! Enter - accept menu selection, finish input, or accept search
          if (input_state%in_menu_select) then
            call handle_menu_navigation(input_state, KEY_ENTER, done)
          else if (input_state%in_search) then
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
          ! Tab completion or menu navigation
          if (input_state%in_menu_select) then
            call handle_menu_navigation(input_state, KEY_TAB, done)
          else
            ! Call separate subroutine to work around macOS ARM64 crash
            call handle_tab_key_separate(input_state)
            ! All completion logic is now handled in the separate subroutine
          end if

        case(KEY_ESC)
          ! Escape sequence - parse it (will route to menu if needed)
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
          ! Kill to end of line (exit menu mode first if active)
          if (input_state%in_menu_select) then
            call exit_menu_select_mode(input_state)
          end if
          call handle_kill_to_end(input_state)

        case(KEY_CTRL_U)
          ! Kill entire line (exit menu mode first if active)
          if (input_state%in_menu_select) then
            call exit_menu_select_mode(input_state)
          end if
          call handle_kill_line(input_state)
          
        case(KEY_CTRL_W)
          ! Kill previous word (exit menu mode first if active)
          if (input_state%in_menu_select) then
            call exit_menu_select_mode(input_state)
          end if
          call handle_kill_word(input_state)
          
        case(KEY_CTRL_Y)
          ! Yank (paste) killed text
          call handle_yank(input_state)
          
        case(KEY_CTRL_L)
          ! Clear screen and redraw
          call handle_clear_screen(input_state, prompt)

        case(KEY_CTRL_R)
          ! Reverse-i-search
          call handle_isearch(input_state, prompt, .false.)
        case(KEY_CTRL_S)
          ! Forward-i-search
          call handle_isearch(input_state, prompt, .true.)

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

        case(KEY_CTRL_T)
          ! Transpose characters (swap current char with previous)
          call handle_transpose_chars(input_state)

        case(32:126)
          ! Regular printable characters
          if (input_state%in_menu_select) then
            ! Exit menu mode and process character normally
            call exit_menu_select_mode(input_state)
            call insert_char(input_state, ch)
          else if (input_state%in_search) then
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
        ! INLINE redraw to avoid gfortran bug on macOS with large derived types
        if (input_state%dirty) then
          block
            character(len=:), allocatable :: highlighted
            integer :: i_redraw, term_cols, term_rows
            integer :: prompt_visual_len, cursor_visual_pos, current_line
            integer :: suggestion_display_len, available_space
            logical :: success

            ! Get terminal size for multiline handling
            success = get_terminal_size(term_rows, term_cols)
            if (.not. success .or. term_cols <= 0) then
              term_cols = 80
            end if
            if (term_cols < 20) then
              term_cols = 80
            end if

            ! Calculate visual length of prompt (excluding ANSI codes)
            prompt_visual_len = visual_length(prompt)
            if (prompt_visual_len < 0) then
              prompt_visual_len = 0
            end if

            ! Calculate current cursor position and line
            cursor_visual_pos = prompt_visual_len + input_state%cursor_pos
            if (term_cols > 0) then
              current_line = cursor_visual_pos / term_cols
            else
              current_line = 0
            end if
            if (current_line < 0) current_line = 0
            if (current_line > 100) current_line = 0

            ! Move cursor up to the first line if we're on a wrapped line
            if (current_line > 0) then
              do i_redraw = 1, current_line
                write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
              end do
            end if

            ! Move to beginning of line and clear from cursor to end of screen
            write(output_unit, '(a)', advance='no') char(13)  ! Carriage return
            write(output_unit, '(a)', advance='no') char(27) // '[J'  ! Clear from cursor down

            ! Redraw prompt and buffer
            write(output_unit, '(a)', advance='no') prompt
            if (input_state%length > 0) then
              ! Apply syntax highlighting (safe - doesn't take input_state)
              highlighted = highlight_command_line(input_state%buffer(:input_state%length))
              write(output_unit, '(a)', advance='no') highlighted

              ! Display autosuggestion if present (only when cursor is at end)
              if (input_state%suggestion_length > 0 .and. &
                  input_state%cursor_pos == input_state%length) then
                ! Calculate available space on current line
                available_space = term_cols - mod(prompt_visual_len + input_state%length, term_cols)
                if (available_space < 0) available_space = 0

                ! Truncate suggestion to fit
                if (available_space > 2) then
                  suggestion_display_len = min(input_state%suggestion_length, available_space - 1)
                  if (suggestion_display_len < 0) suggestion_display_len = 0
                  if (suggestion_display_len > MAX_LINE_LEN) suggestion_display_len = 0

                  if (suggestion_display_len > 0) then
                    write(output_unit, '(a)', advance='no') char(27) // '[2m'  ! Dim mode
                    write(output_unit, '(a)', advance='no') input_state%suggestion(:suggestion_display_len)
                    write(output_unit, '(a)', advance='no') char(27) // '[0m'   ! Reset color

                    ! Move cursor back to correct position (after suggestion)
                    do i_redraw = 1, suggestion_display_len
                      write(output_unit, '(a)', advance='no') char(27) // '[D'  ! Cursor left
                    end do
                  end if
                end if
              end if
            end if

            ! Position cursor correctly (if not at end of input)
            if (input_state%cursor_pos < input_state%length) then
              ! Cursor not at end - move back to correct position
              do i_redraw = 1, input_state%length - input_state%cursor_pos
                write(output_unit, '(a)', advance='no') char(27) // '[D'  ! Cursor left
              end do
            end if

            flush(output_unit)
          end block
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
    integer :: pos, expansion_start, expansion_end, out_pos
    character(len=256) :: expansion, replacement
    logical :: found_expansion
    integer :: repl_len

    work_line = input_line
    expanded_line = ''
    pos = 1
    out_pos = 1

    do while (pos <= len_trim(work_line))
      if (work_line(pos:pos) == '!' .and. pos <= len_trim(work_line)) then
        ! Skip if this is $! (special variable for last background PID)
        if (pos > 1 .and. work_line(pos-1:pos-1) == '$') then
          ! This is $!, not a history expansion - copy the ! as-is
          expanded_line(out_pos:out_pos) = '!'
          out_pos = out_pos + 1
          pos = pos + 1
        else
          ! Found potential history expansion
          expansion_start = pos
          expansion_end = find_history_expansion_end(work_line, pos)

          if (expansion_end > expansion_start) then
            expansion = work_line(expansion_start:expansion_end)
            call process_history_expansion(expansion, replacement, found_expansion)

            if (found_expansion) then
              repl_len = len_trim(replacement)
              if (out_pos + repl_len - 1 <= len(expanded_line)) then
                expanded_line(out_pos:out_pos+repl_len-1) = trim(replacement)
                out_pos = out_pos + repl_len
              end if
              pos = expansion_end + 1
            else
              expanded_line(out_pos:out_pos) = '!'
              out_pos = out_pos + 1
              pos = pos + 1
            end if
          else
            expanded_line(out_pos:out_pos) = '!'
            out_pos = out_pos + 1
            pos = pos + 1
          end if
        end if
      else
        expanded_line(out_pos:out_pos) = work_line(pos:pos)
        out_pos = out_pos + 1
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
      ! Skip if it's part of $! (special variable for last background PID)
      if (pos > 1 .and. line(pos-1:pos-1) == '$') then
        ! This is $!, not a history expansion
      else if (pos == 1 .or. line(pos-1:pos-1) == ' ' .or. line(pos-1:pos-1) == char(9)) then
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
    character :: key_char
    integer :: repeat_count, i

    if (input_state%editing_mode /= EDITING_MODE_VI .or. input_state%vi_mode /= VI_MODE_COMMAND) return

    key_char = char(key)

    ! Handle pending two-character commands first
    if (len_trim(input_state%vi_command_buffer) > 0) then
      select case (input_state%vi_command_buffer(1:1))
      case ('m')
        ! Setting a mark
        call handle_vi_mark_set(input_state, key_char)
        return
      case ("'")
        ! Jumping to a mark
        call handle_vi_mark_jump(input_state, key_char)
        return
      case ('d')
        ! Delete with motion
        call handle_vi_delete_with_motion(input_state, key_char)
        return
      case ('y')
        ! Yank with motion
        call handle_vi_yank_with_motion(input_state, key_char)
        return
      case ('c')
        ! Change with motion
        call handle_vi_change_with_motion(input_state, key_char)
        return
      case ('r')
        ! Replace character
        call handle_vi_replace_char(input_state, key_char)
        return
      end select
    end if

    ! Handle repeat counts (1-9)
    if (key >= ichar('1') .and. key <= ichar('9') .and. .not. input_state%vi_repeat_pending) then
      input_state%vi_repeat_pending = .true.
      input_state%vi_command_count = key - ichar('0')
      return
    else if (key >= ichar('0') .and. key <= ichar('9') .and. input_state%vi_repeat_pending) then
      input_state%vi_command_count = input_state%vi_command_count * 10 + (key - ichar('0'))
      return
    end if

    ! Get repeat count (default to 1)
    if (input_state%vi_repeat_pending) then
      repeat_count = input_state%vi_command_count
      input_state%vi_repeat_pending = .false.
      input_state%vi_command_count = 0
    else
      repeat_count = 1
    end if

    select case (key)
    ! Navigation (with repeat)
    case (ichar('h'))
      ! Move left
      do i = 1, repeat_count
        if (input_state%cursor_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos - 1
        end if
      end do
      input_state%dirty = .true.
    case (ichar('l'))
      ! Move right
      do i = 1, repeat_count
        if (input_state%cursor_pos < input_state%length - 1) then
          input_state%cursor_pos = input_state%cursor_pos + 1
        end if
      end do
      input_state%dirty = .true.
    case (ichar('j'))
      ! Move down (history down)
      do i = 1, repeat_count
        call handle_history_down(input_state)
      end do
    case (ichar('k'))
      ! Move up (history up)
      do i = 1, repeat_count
        call handle_history_up(input_state)
      end do
    case (ichar('0'))
      ! Beginning of line (no repeat)
      input_state%cursor_pos = 0
      input_state%dirty = .true.
    case (ichar('$'))
      ! End of line (no repeat)
      input_state%cursor_pos = input_state%length
      input_state%dirty = .true.
    case (ichar('w'))
      ! Next word
      do i = 1, repeat_count
        call move_to_next_word(input_state)
      end do
    case (ichar('b'))
      ! Previous word
      do i = 1, repeat_count
        call move_to_previous_word(input_state)
      end do
    case (ichar('e'))
      ! End of current word
      do i = 1, repeat_count
        call move_to_word_end(input_state)
      end do

    ! Deletion (with repeat)
    case (ichar('x'))
      ! Delete character at cursor
      do i = 1, repeat_count
        call delete_char_at_cursor(input_state)
      end do
    case (ichar('X'))
      ! Delete character before cursor
      do i = 1, repeat_count
        if (input_state%cursor_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos - 1
          call delete_char_at_cursor(input_state)
        end if
      end do
    case (ichar('d'))
      ! Delete with motion - set up for next character
      input_state%vi_command_buffer = 'd'
      input_state%vi_command_count = repeat_count

    ! Change (with repeat)
    case (ichar('c'))
      ! Change with motion - set up for next character
      input_state%vi_command_buffer = 'c'
      input_state%vi_command_count = repeat_count
    case (ichar('C'))
      ! Change to end of line
      call handle_vi_change_to_eol(input_state)

    ! Undo
    case (ichar('u'))
      ! Undo (simplified)
      input_state%buffer = input_state%original_buffer
      input_state%length = len_trim(input_state%original_buffer)
      input_state%cursor_pos = min(input_state%cursor_pos, input_state%length)
      input_state%dirty = .true.

    ! Yank and Put (vi-style copy/paste)
    case (ichar('y'))
      ! Yank with motion - set up for next character
      input_state%vi_command_buffer = 'y'
      input_state%vi_command_count = repeat_count
    case (ichar('p'))
      ! Put (paste) after cursor
      do i = 1, repeat_count
        call handle_vi_put(input_state, .false.)
      end do
    case (ichar('P'))
      ! Put (paste) before cursor
      do i = 1, repeat_count
        call handle_vi_put(input_state, .true.)
      end do

    ! Replace
    case (ichar('r'))
      ! Replace character - wait for next character
      input_state%vi_command_buffer = 'r'
      input_state%vi_command_count = repeat_count
    case (ichar('R'))
      ! Replace mode - enter insert mode with replace behavior
      input_state%vi_mode = VI_MODE_INSERT
      ! TODO: Add replace mode flag for overwrite behavior

    ! Marks
    case (ichar('m'))
      ! Set mark - next character will be the mark name
      input_state%vi_command_buffer = 'm'
      input_state%vi_command_count = 1
    case (ichar("'"))
      ! Jump to mark - next character will be the mark name
      input_state%vi_command_buffer = "'"
      input_state%vi_command_count = 1

    ! Vi search
    case (ichar('/'))
      ! Forward search
      call handle_vi_search_start(input_state, .true.)
    case (ichar('?'))
      ! Backward search
      call handle_vi_search_start(input_state, .false.)
    case (ichar('n'))
      ! Next search match
      call handle_vi_search_next(input_state, .true.)
    case (ichar('N'))
      ! Previous search match
      call handle_vi_search_next(input_state, .false.)

    ! Mode switches (with proper cursor positioning)
    case (ichar('i'))
      ! Insert at cursor
      input_state%vi_mode = VI_MODE_INSERT
    case (ichar('a'))
      ! Insert after cursor
      if (input_state%cursor_pos < input_state%length) then
        input_state%cursor_pos = input_state%cursor_pos + 1
      end if
      input_state%vi_mode = VI_MODE_INSERT
    case (ichar('I'))
      ! Insert at beginning of line
      input_state%cursor_pos = 0
      input_state%vi_mode = VI_MODE_INSERT
    case (ichar('A'))
      ! Insert at end of line
      input_state%cursor_pos = input_state%length
      input_state%vi_mode = VI_MODE_INSERT
    case (ichar('o'))
      ! Open line below (simplified - just go to end)
      input_state%cursor_pos = input_state%length
      input_state%vi_mode = VI_MODE_INSERT
    case (ichar('O'))
      ! Open line above (simplified - just go to beginning)
      input_state%cursor_pos = 0
      input_state%vi_mode = VI_MODE_INSERT
    end select
  end subroutine

  ! Motion-based delete command
  subroutine handle_vi_delete_with_motion(input_state, motion)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: motion
    integer :: start_pos, end_pos, delete_len, i, repeat_count

    repeat_count = max(1, input_state%vi_command_count)

    select case (motion)
    case ('d')
      ! dd - delete entire line
      input_state%vi_yank_buffer = input_state%buffer(:input_state%length)
      input_state%vi_yank_length = input_state%length
      input_state%buffer = ''
      input_state%length = 0
      input_state%cursor_pos = 0
      input_state%dirty = .true.

    case ('w')
      ! dw - delete to next word
      do i = 1, repeat_count
        start_pos = input_state%cursor_pos + 1
        call move_to_next_word(input_state)
        end_pos = input_state%cursor_pos + 1
        delete_len = end_pos - start_pos
        if (delete_len > 0) then
          call yank_range(input_state, start_pos, end_pos)
          call delete_range(input_state, start_pos, end_pos)
        end if
      end do

    case ('$')
      ! d$ - delete to end of line
      start_pos = input_state%cursor_pos + 1
      end_pos = input_state%length + 1
      call yank_range(input_state, start_pos, end_pos)
      call delete_range(input_state, start_pos, end_pos)

    case ('0')
      ! d0 - delete to beginning of line
      start_pos = 1
      end_pos = input_state%cursor_pos + 1
      call yank_range(input_state, start_pos, end_pos)
      call delete_range(input_state, start_pos, end_pos)

    case ('b')
      ! db - delete to previous word
      do i = 1, repeat_count
        end_pos = input_state%cursor_pos + 1
        call move_to_previous_word(input_state)
        start_pos = input_state%cursor_pos + 1
        call yank_range(input_state, start_pos, end_pos)
        call delete_range(input_state, start_pos, end_pos)
      end do

    case ('e')
      ! de - delete to end of word
      do i = 1, repeat_count
        start_pos = input_state%cursor_pos + 1
        call move_to_word_end(input_state)
        end_pos = input_state%cursor_pos + 2
        call yank_range(input_state, start_pos, end_pos)
        call delete_range(input_state, start_pos, end_pos)
      end do
    end select

    ! Clear command buffer
    input_state%vi_command_buffer = ''
    input_state%vi_command_count = 0
  end subroutine

  ! Motion-based yank command
  subroutine handle_vi_yank_with_motion(input_state, motion)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: motion
    integer :: start_pos, end_pos, saved_cursor, repeat_count, i

    repeat_count = max(1, input_state%vi_command_count)
    saved_cursor = input_state%cursor_pos

    select case (motion)
    case ('y')
      ! yy - yank entire line
      input_state%vi_yank_buffer = input_state%buffer(:input_state%length)
      input_state%vi_yank_length = input_state%length

    case ('w')
      ! yw - yank to next word
      start_pos = input_state%cursor_pos + 1
      do i = 1, repeat_count
        call move_to_next_word(input_state)
      end do
      end_pos = input_state%cursor_pos + 1
      call yank_range(input_state, start_pos, end_pos)
      input_state%cursor_pos = saved_cursor

    case ('$')
      ! y$ - yank to end of line
      start_pos = input_state%cursor_pos + 1
      end_pos = input_state%length + 1
      call yank_range(input_state, start_pos, end_pos)

    case ('0')
      ! y0 - yank to beginning of line
      start_pos = 1
      end_pos = input_state%cursor_pos + 1
      call yank_range(input_state, start_pos, end_pos)

    case ('b')
      ! yb - yank to previous word
      end_pos = input_state%cursor_pos + 1
      do i = 1, repeat_count
        call move_to_previous_word(input_state)
      end do
      start_pos = input_state%cursor_pos + 1
      call yank_range(input_state, start_pos, end_pos)
      input_state%cursor_pos = saved_cursor

    case ('e')
      ! ye - yank to end of word
      start_pos = input_state%cursor_pos + 1
      do i = 1, repeat_count
        call move_to_word_end(input_state)
      end do
      end_pos = input_state%cursor_pos + 2
      call yank_range(input_state, start_pos, end_pos)
      input_state%cursor_pos = saved_cursor
    end select

    ! Clear command buffer
    input_state%vi_command_buffer = ''
    input_state%vi_command_count = 0
  end subroutine

  ! Motion-based change command
  subroutine handle_vi_change_with_motion(input_state, motion)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: motion

    ! Change is like delete + insert mode
    call handle_vi_delete_with_motion(input_state, motion)
    input_state%vi_mode = VI_MODE_INSERT
  end subroutine

  ! Change to end of line
  subroutine handle_vi_change_to_eol(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: start_pos, end_pos

    start_pos = input_state%cursor_pos + 1
    end_pos = input_state%length + 1
    call yank_range(input_state, start_pos, end_pos)
    call delete_range(input_state, start_pos, end_pos)
    input_state%vi_mode = VI_MODE_INSERT
  end subroutine

  ! Replace single character
  subroutine handle_vi_replace_char(input_state, replace_char)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: replace_char
    integer :: i, repeat_count

    repeat_count = max(1, input_state%vi_command_count)

    ! Replace up to repeat_count characters
    do i = 1, repeat_count
      if (input_state%cursor_pos + i - 1 < input_state%length) then
        input_state%buffer(input_state%cursor_pos+i:input_state%cursor_pos+i) = replace_char
        input_state%dirty = .true.
      end if
    end do

    ! Clear command buffer
    input_state%vi_command_buffer = ''
    input_state%vi_command_count = 0
  end subroutine

  ! Helper: Yank a range of characters
  subroutine yank_range(input_state, start_pos, end_pos)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: start_pos, end_pos
    integer :: yank_len

    yank_len = max(0, min(end_pos - start_pos, MAX_LINE_LEN))
    if (yank_len > 0 .and. start_pos >= 1 .and. start_pos <= input_state%length) then
      input_state%vi_yank_buffer = input_state%buffer(start_pos:start_pos+yank_len-1)
      input_state%vi_yank_length = yank_len
    end if
  end subroutine

  ! Helper: Delete a range of characters
  subroutine delete_range(input_state, start_pos, end_pos)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: start_pos, end_pos
    integer :: delete_len, i

    delete_len = end_pos - start_pos
    if (delete_len <= 0) return

    ! Shift remaining characters left
    do i = start_pos, input_state%length - delete_len
      if (end_pos + i - start_pos <= input_state%length) then
        input_state%buffer(i:i) = input_state%buffer(end_pos+i-start_pos:end_pos+i-start_pos)
      end if
    end do

    input_state%length = input_state%length - delete_len
    input_state%cursor_pos = max(0, min(start_pos - 1, input_state%length))
    input_state%dirty = .true.
  end subroutine

  ! Move to end of current word
  subroutine move_to_word_end(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos

    pos = input_state%cursor_pos + 1

    ! If on whitespace, skip to next word
    do while (pos <= input_state%length .and. input_state%buffer(pos:pos) == ' ')
      pos = pos + 1
    end do

    ! Find end of word
    do while (pos <= input_state%length .and. input_state%buffer(pos:pos) /= ' ')
      pos = pos + 1
    end do

    input_state%cursor_pos = max(0, min(pos - 2, input_state%length - 1))
    input_state%dirty = .true.
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

    ! pos is now at a space (or 0 if at beginning)
    ! cursor_pos represents position between characters,
    ! so space position is correct (cursor will be after space, before first char of word)
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

  ! Enhanced tab completion with programmable completion system integration
  subroutine enhanced_tab_complete(partial_input, completions, num_completions, shell)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions
    type(shell_state_t), intent(inout), optional :: shell

    character(len=MAX_LINE_LEN) :: last_word, prefix_part, command_name
    character(len=256) :: temp_completions(MAX_COMPLETIONS)
    integer :: last_space_pos, i, first_space_pos, temp_count
    logical :: is_command, used_programmable_completion
    type(completion_spec_t) :: spec

    num_completions = 0
    used_programmable_completion = .false.

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
      command_name = ''
    else
      last_word = trim(partial_input(last_space_pos+1:))
      prefix_part = partial_input(:last_space_pos)
      is_command = .false.

      ! Extract command name (first word)
      first_space_pos = index(partial_input, ' ')
      if (first_space_pos > 0) then
        command_name = partial_input(:first_space_pos-1)
      else
        command_name = trim(partial_input)
      end if
    end if

    ! Try programmable completion first (if shell state available and not completing command)
    if (.not. is_command .and. present(shell)) then
      spec = get_completion_spec(trim(command_name))
      if (spec%is_active) then
        ! Use our programmable completion system!
        call generate_completions(trim(command_name), trim(last_word), temp_completions, temp_count, shell)
        if (temp_count > 0) then
          ! Copy completions (convert from 256 to MAX_LINE_LEN)
          do i = 1, min(temp_count, 50)
            completions(i) = trim(temp_completions(i))
          end do
          num_completions = min(temp_count, 50)
          used_programmable_completion = .true.
        end if
      end if
    end if

    ! Fall back to default completion if programmable completion didn't produce results
    if (.not. used_programmable_completion) then
      if (is_command) then
        ! Complete commands (builtins + PATH executables)
        call complete_commands_enhanced(last_word, completions, num_completions)

        ! Add prefix back to completions
        do i = 1, num_completions
          completions(i) = trim(completions(i))
        end do
      else
        ! Check if last_word contains glob characters
        if (has_glob_chars(last_word)) then
          ! Expand glob pattern instead of regular file completion
          call expand_glob_for_completion(last_word, completions, num_completions)
        else
          ! Complete files and directories normally
          call complete_files_enhanced(last_word, completions, num_completions)
        end if

        ! Filter completions based on command type
        ! cd, pushd, popd should only show directories
        if (trim(command_name) == 'cd' .or. trim(command_name) == 'pushd' .or. &
            trim(command_name) == 'popd') then
          call filter_directories_only(completions, num_completions)
        end if

        ! Don't add prefix to completions - they are for display only
        ! The prefix will be added when constructing the completed line
      end if
    end if
  end subroutine

  ! Filter completions to only keep directories (entries ending with /)
  subroutine filter_directories_only(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(inout) :: completions(50)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: temp_completions(50)
    integer :: i, new_count, original_count

    original_count = num_completions
    new_count = 0
    do i = 1, num_completions
      ! Keep only entries that end with / (directories)
      if (len_trim(completions(i)) > 0) then
        if (completions(i)(len_trim(completions(i)):len_trim(completions(i))) == '/') then
          new_count = new_count + 1
          temp_completions(new_count) = completions(i)
        end if
      end if
    end do

    ! Copy filtered results back
    do i = 1, new_count
      completions(i) = temp_completions(i)
    end do
    num_completions = new_count
  end subroutine

  ! Check if a string contains glob characters
  function has_glob_chars(str) result(has_globs)
    character(len=*), intent(in) :: str
    logical :: has_globs

    has_globs = (index(str, '*') > 0 .or. &
                 index(str, '?') > 0 .or. &
                 index(str, '[') > 0)
  end function has_glob_chars

  ! Expand glob pattern for tab completion using real filesystem
  subroutine expand_glob_for_completion(pattern, completions, num_completions)
    character(len=*), intent(in) :: pattern
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions

    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    character(len=MAX_LINE_LEN) :: ls_command, ls_output
    character(len=MAX_LINE_LEN) :: entries(100)
    integer :: num_entries, i, last_slash_pos
    character(len=MAX_LINE_LEN) :: full_path
    logical :: is_dir

    num_completions = 0

    ! Extract directory path and filename pattern (same logic as complete_files_enhanced)
    last_slash_pos = 0
    do i = len_trim(pattern), 1, -1
      if (pattern(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do

    if (last_slash_pos > 0) then
      dir_path = pattern(:last_slash_pos-1)
      file_pattern = pattern(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(pattern)
    end if

    ! Use ls command to get directory listing (same as scan_directory)
    ls_command = 'ls -1a "' // trim(dir_path) // '" 2>/dev/null'
    ls_output = execute_and_capture(ls_command)

    ! Parse ls output into individual entries
    call parse_ls_output(ls_output, entries, num_entries)

    ! Match entries against glob pattern
    do i = 1, num_entries
      if (num_completions >= 50) exit

      ! Skip . and ..
      if (trim(entries(i)) == '.' .or. trim(entries(i)) == '..') cycle

      ! Use pattern_matches from glob module to match against pattern
      if (pattern_matches(file_pattern, trim(entries(i)))) then
        ! Build full path
        if (trim(dir_path) == '.') then
          full_path = trim(entries(i))
        else
          full_path = trim(dir_path) // '/' // trim(entries(i))
        end if

        ! Check if it's a directory and add trailing slash
        is_dir = is_directory(full_path)
        num_completions = num_completions + 1
        if (is_dir) then
          completions(num_completions) = trim(full_path) // '/'
        else
          completions(num_completions) = trim(full_path)
        end if
      end if
    end do
  end subroutine expand_glob_for_completion

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
    type(scored_completion_t) :: scored(100)  ! Temp storage for scoring
    integer :: i, num_scored, score

    num_completions = 0
    num_scored = 0

    ! Score builtin commands using fuzzy matching
    do i = 1, size(builtin_commands)
      score = fuzzy_match_score(prefix, trim(builtin_commands(i)))
      if (score >= 0) then  ! Negative score = no match
        num_scored = num_scored + 1
        if (num_scored <= 100) then
          scored(num_scored)%text = trim(builtin_commands(i))
          scored(num_scored)%score = score
        end if
      end if
    end do

    ! Add common system commands
    call add_system_commands_fuzzy(prefix, scored, num_scored)

    ! Sort by score
    if (num_scored > 0) then
      call sort_completions_by_score(scored, num_scored)
    end if

    ! Copy top matches to output (limit to 50)
    num_completions = min(num_scored, 50)
    do i = 1, num_completions
      completions(i) = scored(i)%text
    end do
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

  ! Fuzzy version of add_system_commands
  subroutine add_system_commands_fuzzy(prefix, scored, num_scored)
    character(len=*), intent(in) :: prefix
    type(scored_completion_t), intent(inout) :: scored(:)
    integer, intent(inout) :: num_scored

    character(len=50), parameter :: common_commands(15) = [ &
      'ls       ', 'cat      ', 'grep     ', 'find     ', &
      'sort     ', 'head     ', 'tail     ', 'wc       ', &
      'cp       ', 'mv       ', 'rm       ', 'mkdir    ', &
      'rmdir    ', 'chmod    ', 'which    ' &
    ]
    integer :: i, score

    do i = 1, size(common_commands)
      if (num_scored >= size(scored)) exit
      score = fuzzy_match_score(prefix, trim(common_commands(i)))
      if (score >= 0) then  ! Negative score = no match
        num_scored = num_scored + 1
        scored(num_scored)%text = trim(common_commands(i))
        scored(num_scored)%score = score
      end if
    end do
  end subroutine

  ! Enhanced file completion with real filesystem access
  subroutine complete_files_enhanced(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(50)
    integer, intent(out) :: num_completions

    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    character(len=:), allocatable :: debug_mode
    integer :: last_slash_pos, i
    logical :: debug_enabled

    ! Check if debug mode is enabled
    debug_mode = get_environment_var('FORTSH_DEBUG_COMPLETION')
    debug_enabled = (allocated(debug_mode) .and. trim(debug_mode) == '1')

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

    ! Add directory navigation options ONLY when explicitly requested
    ! Don't add ./ when user is trying to complete dotfiles like .fortshrc
    if (len_trim(file_pattern) == 0) then
      ! Empty pattern - offer . and ..
      if (num_completions < 50) then
        num_completions = num_completions + 1
        if (trim(dir_path) == '.') then
          completions(num_completions) = './'
        else
          completions(num_completions) = trim(dir_path) // '/./'
        end if
      end if

      if (num_completions < 50) then
        num_completions = num_completions + 1
        if (trim(dir_path) == '.') then
          completions(num_completions) = '../'
        else
          completions(num_completions) = trim(dir_path) // '/../'
        end if
      end if
    else if (trim(file_pattern) == '.' .or. trim(file_pattern) == '..') then
      ! Exact match for . or .. - complete with /
      if (trim(file_pattern) == '.') then
        if (num_completions < 50) then
          num_completions = num_completions + 1
          if (trim(dir_path) == '.') then
            completions(num_completions) = './'
          else
            completions(num_completions) = trim(dir_path) // '/./'
          end if
        end if
      else if (trim(file_pattern) == '..') then
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
    ! Otherwise, let scan_directory handle ALL matches including dotfiles

    ! Get actual filesystem entries
    call scan_directory(dir_path, file_pattern, completions, num_completions)
  end subroutine

  ! Scan directory for matching files and directories (with fuzzy matching)
  subroutine scan_directory(dir_path, pattern, completions, num_completions)
    character(len=*), intent(in) :: dir_path, pattern
    character(len=MAX_LINE_LEN), intent(inout) :: completions(50)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: ls_command, ls_output, expanded_dir
    character(len=MAX_LINE_LEN) :: entries(100)  ! Temp storage for directory entries
    character(len=MAX_LINE_LEN) :: full_path, check_path
    character(len=:), allocatable :: home_dir, debug_mode
    type(scored_completion_t) :: scored(100)
    integer :: num_entries, i, pattern_len, num_scored, score, j
    logical :: is_dir, debug_enabled

    ! Check if debug mode is enabled
    debug_mode = get_environment_var('FORTSH_DEBUG_COMPLETION')
    debug_enabled = (allocated(debug_mode) .and. trim(debug_mode) == '1')

    pattern_len = len_trim(pattern)

    ! Expand tilde if present (shell doesn't expand ~ inside quotes)
    expanded_dir = dir_path
    if (len_trim(dir_path) > 0 .and. dir_path(1:1) == '~') then
      home_dir = get_environment_var('HOME')
      if (allocated(home_dir) .and. len(home_dir) > 0) then
        if (len_trim(dir_path) == 1) then
          ! Just ~
          expanded_dir = home_dir
        else if (dir_path(2:2) == '/') then
          ! ~/something
          expanded_dir = trim(home_dir) // dir_path(2:)
        else
          ! ~user (not supported for now, just use as-is)
          expanded_dir = dir_path
        end if
      end if
    end if

    ! Use ls command to get directory listing
    ls_command = 'ls -1a "' // trim(expanded_dir) // '" 2>/dev/null'
    ls_output = execute_and_capture(ls_command)

    ! Parse ls output into individual entries
    call parse_ls_output(ls_output, entries, num_entries)

    ! Score entries using fuzzy matching
    num_scored = 0
    do i = 1, num_entries
      if (num_scored >= 100) exit

      ! Skip . and .. unless explicitly requested
      if (trim(entries(i)) == '.' .or. trim(entries(i)) == '..') then
        if (pattern_len == 0 .or. (pattern_len > 0 .and. pattern(1:1) /= '.')) then
          cycle
        end if
      end if

      ! Calculate fuzzy match score
      score = fuzzy_match_score(pattern, trim(entries(i)))
      if (score >= 0) then  ! Negative score = no match
        ! Build full path for directory check (use original dir_path to preserve ~ in display)
        if (trim(dir_path) == '.') then
          full_path = trim(entries(i))
        else
          full_path = trim(dir_path) // '/' // trim(entries(i))
        end if

        ! Check if it's a directory using expanded path
        if (trim(expanded_dir) == '.') then
          check_path = trim(entries(i))
        else
          check_path = trim(expanded_dir) // '/' // trim(entries(i))
        end if
        is_dir = is_directory(check_path)

        num_scored = num_scored + 1
        if (is_dir) then
          scored(num_scored)%text = trim(full_path) // '/'
        else
          scored(num_scored)%text = trim(full_path)
        end if
        scored(num_scored)%score = score

        ! Bonus for directories (make them appear first in same score bracket)
        if (is_dir) then
          scored(num_scored)%score = scored(num_scored)%score + 5
        end if
      end if
    end do

    ! Sort by score
    if (num_scored > 0) then
      call sort_completions_by_score(scored, num_scored)
    end if

    ! Copy to output (add to existing completions, limit total to 50)
    do j = 1, num_scored
      if (num_completions >= 50) exit
      num_completions = num_completions + 1
      completions(num_completions) = scored(j)%text
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

    character(len=MAX_LINE_LEN) :: common_prefix, prefix_part, last_word
    character(len=4096) :: expanded_matches
    integer :: last_space_pos, i, pos, j
    logical :: is_glob_pattern

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
      last_word = partial_input(last_space_pos+1:)
    else
      prefix_part = ''
      last_word = trim(partial_input)
    end if

    ! Check if we're completing a glob pattern
    is_glob_pattern = has_glob_chars(last_word)

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
      ! Multiple completions
      if (is_glob_pattern) then
        ! For glob patterns: expand all matches into command line (like bash)
        ! Build space-separated list of all matches
        expanded_matches = ''
        pos = 1

        do j = 1, num_completions
          if (j > 1) then
            ! Add space separator
            expanded_matches(pos:pos) = ' '
            pos = pos + 1
          end if

          ! Add this match
          expanded_matches(pos:pos+len_trim(completions(j))-1) = trim(completions(j))
          pos = pos + len_trim(completions(j))
        end do

        ! Replace glob pattern with expanded matches
        if (last_space_pos > 0) then
          completed_line = prefix_part(:last_space_pos) // expanded_matches(:pos-1)
        else
          completed_line = expanded_matches(:pos-1)
        end if
        completed = .true.
      else
        ! For regular completion: try common prefix
        common_prefix = get_common_prefix(completions, num_completions)

        if (len_trim(common_prefix) > len_trim(last_word)) then
          ! We have a common prefix that extends what user typed - use it
          if (last_space_pos > 0) then
            completed_line = prefix_part(:last_space_pos) // trim(common_prefix)
          else
            completed_line = trim(common_prefix)
          end if
          completed = .true.
        else
          ! No useful common prefix - we'll show the completions list instead
          ! Keep completed = .false. but don't treat as "no completions"
          ! The caller will see num_completions > 0 and should show them
          completed = .false.
        end if
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

    ! Check for abbreviation expansion BEFORE inserting space
    if (ch == ' ') then
      call try_expand_abbreviation_at_cursor(input_state)
    end if

    ! If cursor is at end, simple append
    if (input_state%cursor_pos >= input_state%length) then
      input_state%length = input_state%length + 1
      input_state%buffer(input_state%length:input_state%length) = ch
      input_state%cursor_pos = input_state%length
      ! Always trigger highlighting for real-time color updates
      input_state%dirty = .true.
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

    ! Update autosuggestion after inserting character
    call update_autosuggestion(input_state)
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
      ! Always trigger highlighting for real-time color updates
      input_state%dirty = .true.
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

    ! Update autosuggestion after deleting character
    call update_autosuggestion(input_state)
  end subroutine

  ! Separate tab completion handler to work around macOS ARM64 crash
  ! This modifies the SAVE'd input_state directly without problematic returns
  subroutine handle_tab_key_separate(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: tab_num_completions, i, last_space_pos
    logical :: tab_completed, tab_made_progress, tab_buffer_changed
    character(len=MAX_LINE_LEN) :: tab_completions(50)
    character(len=MAX_LINE_LEN) :: tab_partial_input
    character(len=MAX_LINE_LEN) :: tab_completed_line
    character(len=MAX_LINE_LEN) :: tab_saved_input

    ! Exit history mode if we're browsing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Get the current buffer content
    tab_partial_input = input_state%buffer(:input_state%length)
    tab_saved_input = tab_partial_input

    ! Check if buffer has changed since we last showed completions
    tab_buffer_changed = (trim(input_state%buffer(:input_state%length)) /= &
                     trim(input_state%last_completion_buffer))

    ! Attempt smart completion
    call smart_tab_complete(tab_partial_input, tab_completions, &
                           tab_num_completions, tab_completed_line, tab_completed)

    if (tab_num_completions == 0) then
      ! No completions found - ring bell
      write(output_unit, '(a)', advance='no') char(7)
      flush(output_unit)
    else if (tab_completed) then
      ! We have a completed line - update buffer
      tab_made_progress = (len_trim(tab_completed_line) > len_trim(tab_saved_input))

      input_state%buffer = tab_completed_line
      input_state%length = len_trim(tab_completed_line)
      input_state%cursor_pos = input_state%length
      input_state%dirty = .true.

      if (tab_num_completions > 1) then
        if (tab_made_progress) then
          input_state%completions_shown = .false.
        else
          if (.not. input_state%completions_shown .or. tab_buffer_changed) then
            write(output_unit, '()')
            call show_completions(tab_completions, tab_num_completions)
            input_state%last_completion_buffer = input_state%buffer(:input_state%length)
            input_state%completions_shown = .true.
            input_state%dirty = .true.
          else
            ! Second tab - enter menu selection mode
            ! Detect macOS once
            call detect_macos()

            if (is_macos_system) then
              ! macOS: Just show completions again, don't enter menu mode
              write(output_unit, '()')
              write(output_unit, '(a)') "Note: Menu selection disabled on macOS (compiler bug workaround)"
              write(output_unit, '(a)') "Tab completion works - continue typing to filter"
              call show_completions(tab_completions, tab_num_completions)
              input_state%dirty = .true.
            else
              ! Normal platforms: Enter menu mode
              input_state%in_menu_select = .true.
              input_state%menu_num_items = tab_num_completions
              input_state%menu_selection = 1

              ! Copy menu items
              do i = 1, tab_num_completions
                input_state%menu_items(i) = tab_completions(i)
              end do

              ! Store menu prefix
              last_space_pos = 0
              do i = len_trim(tab_partial_input), 1, -1
                if (tab_partial_input(i:i) == ' ') then
                  last_space_pos = i
                  exit
                end if
              end do

              if (last_space_pos > 0) then
                input_state%menu_prefix = tab_partial_input(:last_space_pos)
                input_state%menu_prefix_len = last_space_pos
              else
                input_state%menu_prefix = ''
                input_state%menu_prefix_len = 0
              end if

              ! Draw the menu with selection
              call draw_completion_menu(input_state, .true.)
            end if
          end if
        end if
      end if
    else
      ! We have completions but no single completion to apply
      ! Show the available options
      if (.not. input_state%completions_shown .or. tab_buffer_changed) then
        ! First tab - show completions
        write(output_unit, '()')
        call show_completions(tab_completions, tab_num_completions)
        input_state%last_completion_buffer = input_state%buffer(:input_state%length)
        input_state%completions_shown = .true.
        input_state%dirty = .true.
      else
        ! Second tab - enter menu selection mode
        call detect_macos()

        if (is_macos_system) then
          ! macOS: Just show completions again, don't enter menu mode
          write(output_unit, '()')
          write(output_unit, '(a)') "Note: Menu selection disabled on macOS (compiler bug workaround)"
          write(output_unit, '(a)') "Tab completion works - continue typing to filter"
          call show_completions(tab_completions, tab_num_completions)
          input_state%dirty = .true.
        else
          ! Normal platforms: Enter menu mode
          input_state%in_menu_select = .true.
          input_state%menu_num_items = tab_num_completions
          input_state%menu_selection = 1

          ! Copy menu items
          do i = 1, tab_num_completions
            input_state%menu_items(i) = tab_completions(i)
          end do

          ! Store menu prefix
          last_space_pos = 0
          do i = len_trim(tab_partial_input), 1, -1
            if (tab_partial_input(i:i) == ' ') then
              last_space_pos = i
              exit
            end if
          end do

          if (last_space_pos > 0) then
            input_state%menu_prefix = tab_partial_input(:last_space_pos)
            input_state%menu_prefix_len = last_space_pos
          else
            input_state%menu_prefix = ''
            input_state%menu_prefix_len = 0
          end if

          ! Draw the menu with selection
          call draw_completion_menu(input_state, .true.)
        end if
      end if
    end if
  end subroutine handle_tab_key_separate

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

    if (num_completions == 0) then
      ! No completions found - ring bell (ASCII 7)
      write(output_unit, '(a)', advance='no') char(7)  ! Bell for audio feedback
      flush(output_unit)
    else if (completed) then
      ! We have a completed line - update buffer
      ! Check if we made actual progress
      made_progress = (len_trim(completed_line) > len_trim(saved_input))

      ! Update the input buffer with completion
      input_state%buffer = completed_line
      input_state%length = len_trim(completed_line)
      input_state%cursor_pos = input_state%length
      input_state%dirty = .true.

      ! Update autosuggestion to account for the completion
      ! If the completed line still matches a history entry, show the rest
      call update_autosuggestion(input_state)

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
          else
            ! Second tab (double-tab) at common prefix - enter menu selection mode!
            call enter_menu_select_mode(input_state, completions, num_completions, completed_line)
          end if
        end if
      else
        ! Single completion - reset flag
        input_state%completions_shown = .false.
      end if
    else
      ! We have completions but no single completion to apply
      ! Show the available options
      if (.not. input_state%completions_shown .or. buffer_changed) then
        ! First tab - show completions
        write(output_unit, '()')  ! New line
        call show_completions(completions, num_completions)
        input_state%last_completion_buffer = input_state%buffer(:input_state%length)
        input_state%completions_shown = .true.
        input_state%dirty = .true.
      else
        ! Second tab (double-tab) - enter menu selection mode!
        call enter_menu_select_mode(input_state, completions, num_completions, partial_input)
      end if
    end if
  end subroutine

  ! ===========================================================================
  ! Menu Selection Mode (zsh/fish-style interactive completion)
  ! ===========================================================================

  subroutine enter_menu_select_mode(input_state, completions, num_completions, current_input)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN), intent(in) :: completions(50)
    integer, intent(in) :: num_completions
    character(len=*), intent(in) :: current_input
    integer :: i, last_space_pos

    ! macOS workaround: Don't enter menu mode due to gfortran bug
    block
      character(len=256) :: ostype
      integer :: status
      logical :: is_macos

      ! Check if we're on macOS at runtime
      call get_environment_variable("OSTYPE", ostype, status=status)
      if (status == 0) then
        is_macos = (index(ostype, "darwin") > 0)
      else
        ! Alternative check using uname
        call execute_command_line("uname -s | grep -q Darwin", wait=.true., exitstat=status)
        is_macos = (status == 0)
      end if

      if (is_macos) then
        write(output_unit, '()')
        write(output_unit, '(a)') "Note: Menu selection disabled on macOS (gfortran bug workaround)"
        call show_completions(completions, num_completions)
        input_state%completions_shown = .true.
        input_state%dirty = .true.
        return
      end if
    end block

    ! Store menu items
    input_state%in_menu_select = .true.
    input_state%menu_num_items = num_completions
    input_state%menu_selection = 1  ! Start with first item selected

    do i = 1, num_completions
      input_state%menu_items(i) = completions(i)
    end do

    ! Find the prefix (everything before the last word being completed)
    last_space_pos = 0
    do i = len_trim(current_input), 1, -1
      if (current_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do

    if (last_space_pos > 0) then
      input_state%menu_prefix = current_input(:last_space_pos)
      input_state%menu_prefix_len = last_space_pos  ! Store length WITH the space
    else
      input_state%menu_prefix = ''
      input_state%menu_prefix_len = 0
    end if

    ! Draw the menu with first item highlighted
    call draw_completion_menu(input_state, .true.)
  end subroutine

  subroutine draw_completion_menu(input_state, initial_draw)
    type(input_state_t), intent(in) :: input_state
    logical, intent(in) :: initial_draw
    integer :: i, cols_per_item, items_per_row, row, col, item_idx
    integer :: term_rows, term_cols
    logical :: success

    ! Get terminal size
    success = get_terminal_size(term_rows, term_cols)
    if (.not. success .or. term_cols <= 0) then
      term_cols = 80
    end if

    ! Add newline only on initial draw, not on redraw
    if (initial_draw) then
      write(output_unit, '()')  ! New line
    end if

    ! Calculate layout - try to fit multiple items per row
    cols_per_item = 0
    do i = 1, input_state%menu_num_items
      cols_per_item = max(cols_per_item, len_trim(input_state%menu_items(i)))
    end do
    cols_per_item = cols_per_item + 2  ! Add spacing

    items_per_row = max(1, term_cols / cols_per_item)

    ! Draw menu items
    item_idx = 1
    do while (item_idx <= input_state%menu_num_items)
      ! Draw one row
      do col = 1, items_per_row
        if (item_idx > input_state%menu_num_items) exit

        ! Highlight selected item with reverse video
        if (item_idx == input_state%menu_selection) then
          write(output_unit, '(a)', advance='no') char(27) // '[7m'  ! Reverse video
        end if

        write(output_unit, '(a)', advance='no') trim(input_state%menu_items(item_idx))

        if (item_idx == input_state%menu_selection) then
          write(output_unit, '(a)', advance='no') char(27) // '[0m'  ! Reset
        end if

        ! Add spacing between columns
        if (col < items_per_row .and. item_idx < input_state%menu_num_items) then
          write(output_unit, '(a)', advance='no') '  '
        end if

        item_idx = item_idx + 1
      end do
      write(output_unit, '()')  ! New line after each row
    end do

    ! Mark that we need to redraw the command line
    flush(output_unit)
  end subroutine

  subroutine handle_menu_navigation(input_state, key, done)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    logical, intent(inout) :: done
    integer :: old_selection

    if (.not. input_state%in_menu_select) return

    old_selection = input_state%menu_selection

    select case (key)
    case (KEY_UP)
      ! Move up (previous item)
      input_state%menu_selection = input_state%menu_selection - 1
      if (input_state%menu_selection < 1) then
        input_state%menu_selection = input_state%menu_num_items  ! Wrap to end
      end if

    case (KEY_DOWN)
      ! Move down (next item)
      input_state%menu_selection = input_state%menu_selection + 1
      if (input_state%menu_selection > input_state%menu_num_items) then
        input_state%menu_selection = 1  ! Wrap to beginning
      end if

    case (KEY_RIGHT, KEY_TAB)
      ! Move to next item (like Tab cycling)
      input_state%menu_selection = input_state%menu_selection + 1
      if (input_state%menu_selection > input_state%menu_num_items) then
        input_state%menu_selection = 1
      end if

    case (KEY_LEFT)
      ! Move to previous item
      input_state%menu_selection = input_state%menu_selection - 1
      if (input_state%menu_selection < 1) then
        input_state%menu_selection = input_state%menu_num_items
      end if

    case (10, 13)  ! Enter (LF or CR)
      ! Accept selection - insert into command line
      call accept_menu_selection(input_state)
      done = .true.
      return

    case (KEY_ESC)
      ! Cancel menu mode
      call exit_menu_select_mode(input_state)
      return

    case default
      ! Any other key exits menu mode and processes normally
      call exit_menu_select_mode(input_state)
      return
    end select

    ! Update menu highlighting if selection changed (in-place update)
    if (old_selection /= input_state%menu_selection) then
      call update_menu_selection(input_state, old_selection)
    end if
  end subroutine

  subroutine accept_menu_selection(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: completed_line

    ! Build completed command with selected item
    if (input_state%menu_prefix_len > 0) then
      ! Use stored prefix_len which includes the trailing space
      completed_line = input_state%menu_prefix(:input_state%menu_prefix_len) // &
                      trim(input_state%menu_items(input_state%menu_selection))
    else
      completed_line = trim(input_state%menu_items(input_state%menu_selection))
    end if

    ! Update buffer
    input_state%buffer = completed_line
    input_state%length = len_trim(completed_line)
    input_state%cursor_pos = input_state%length

    ! Exit menu mode
    call exit_menu_select_mode(input_state)

    ! Update autosuggestion
    call update_autosuggestion(input_state)

    ! Mark for redraw
    input_state%dirty = .true.
  end subroutine

  subroutine exit_menu_select_mode(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, num_rows, term_rows, term_cols, cols_per_item, items_per_row
    logical :: success

    ! Clear the menu from screen before exiting
    if (input_state%menu_num_items > 0) then
      ! Calculate how many rows the menu uses
      success = get_terminal_size(term_rows, term_cols)
      if (.not. success .or. term_cols <= 0) then
        term_cols = 80
      end if

      ! Calculate layout to determine number of rows used
      cols_per_item = 0
      do i = 1, input_state%menu_num_items
        cols_per_item = max(cols_per_item, len_trim(input_state%menu_items(i)))
      end do
      cols_per_item = cols_per_item + 2

      items_per_row = max(1, term_cols / cols_per_item)
      num_rows = (input_state%menu_num_items + items_per_row - 1) / items_per_row

      ! Move cursor down past the menu, then clear everything above
      write(output_unit, '(a)', advance='no') char(13)  ! Carriage return
      write(output_unit, '(a)', advance='no') char(27) // '[J'  ! Clear from cursor down
    end if

    input_state%in_menu_select = .false.
    input_state%menu_num_items = 0
    input_state%menu_selection = 1
    input_state%menu_prefix_len = 0
    input_state%completions_shown = .false.
    input_state%dirty = .true.
  end subroutine

  subroutine update_menu_selection(input_state, old_selection)
    type(input_state_t), intent(in) :: input_state
    integer, intent(in) :: old_selection
    integer :: term_rows, term_cols, cols_per_item, items_per_row, i
    integer :: old_row, old_col, new_row, new_col, col_offset
    integer :: menu_start_row, cursor_save_row
    logical :: success
    character(len=10) :: row_str, col_str

    ! Get terminal size
    success = get_terminal_size(term_rows, term_cols)
    if (.not. success .or. term_cols <= 0) then
      term_cols = 80
    end if

    ! Calculate layout - same as draw_completion_menu
    cols_per_item = 0
    do i = 1, input_state%menu_num_items
      cols_per_item = max(cols_per_item, len_trim(input_state%menu_items(i)))
    end do
    cols_per_item = cols_per_item + 2  ! Add spacing

    items_per_row = max(1, term_cols / cols_per_item)

    ! Calculate positions of old and new selections (1-indexed)
    ! Row number (which row of the menu grid)
    old_row = (old_selection - 1) / items_per_row + 1
    new_row = (input_state%menu_selection - 1) / items_per_row + 1

    ! Column within that row
    old_col = mod(old_selection - 1, items_per_row) + 1
    new_col = mod(input_state%menu_selection - 1, items_per_row) + 1

    ! Save cursor position (we're currently at the command line)
    write(output_unit, '(a)', advance='no') char(27) // '7'  ! Save cursor

    ! Update old selection (remove highlighting)
    if (old_selection > 0 .and. old_selection <= input_state%menu_num_items) then
      ! Move to old item's position
      ! Menu starts 1 line below the command line
      write(row_str, '(I0)') old_row
      col_offset = (old_col - 1) * cols_per_item + 1
      write(col_str, '(I0)') col_offset

      ! Use relative positioning - move up to menu, then position within menu
      do i = 1, (input_state%menu_num_items + items_per_row - 1) / items_per_row - old_row + 1
        write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
      end do
      write(output_unit, '(a)', advance='no') ESC_MOVE_BOL
      if (col_offset > 1) then
        write(col_str, '(I0)') col_offset - 1
        write(output_unit, '(a)', advance='no') char(27) // '[' // trim(col_str) // 'C'  ! Move right
      end if

      ! Write item without highlighting
      write(output_unit, '(a)', advance='no') trim(input_state%menu_items(old_selection))
    end if

    ! Restore cursor to command line
    write(output_unit, '(a)', advance='no') char(27) // '8'  ! Restore cursor

    ! Save again for new item
    write(output_unit, '(a)', advance='no') char(27) // '7'  ! Save cursor

    ! Update new selection (add highlighting)
    write(row_str, '(I0)') new_row
    col_offset = (new_col - 1) * cols_per_item + 1
    write(col_str, '(I0)') col_offset

    ! Move to new item's position
    do i = 1, (input_state%menu_num_items + items_per_row - 1) / items_per_row - new_row + 1
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
    end do
    write(output_unit, '(a)', advance='no') ESC_MOVE_BOL
    if (col_offset > 1) then
      write(col_str, '(I0)') col_offset - 1
      write(output_unit, '(a)', advance='no') char(27) // '[' // trim(col_str) // 'C'  ! Move right
    end if

    ! Write item with highlighting
    write(output_unit, '(a)', advance='no') char(27) // '[7m'  ! Reverse video
    write(output_unit, '(a)', advance='no') trim(input_state%menu_items(input_state%menu_selection))
    write(output_unit, '(a)', advance='no') char(27) // '[0m'  ! Reset

    ! Restore cursor to command line
    write(output_unit, '(a)', advance='no') char(27) // '8'  ! Restore cursor

    flush(output_unit)
  end subroutine

  subroutine handle_escape_sequence(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character :: ch1, ch2
    logical :: success

    ! Check if we're in menu select mode - route arrow keys to menu navigation
    if (input_state%in_menu_select) then
      ! Try to read the next character to see if it's an arrow key
      success = read_single_char(ch1)
      if (.not. success) then
        ! Just ESC by itself - exit menu
        call handle_menu_navigation(input_state, KEY_ESC, done)
        return
      end if

      if (ch1 == '[') then
        ! ANSI escape sequence
        success = read_single_char(ch2)
        if (.not. success) return

        select case(ch2)
        case('A')  ! Up arrow
          call handle_menu_navigation(input_state, KEY_UP, done)
        case('B')  ! Down arrow
          call handle_menu_navigation(input_state, KEY_DOWN, done)
        case('C')  ! Right arrow
          call handle_menu_navigation(input_state, KEY_RIGHT, done)
        case('D')  ! Left arrow
          call handle_menu_navigation(input_state, KEY_LEFT, done)
        case default
          ! Unknown escape sequence in menu mode
          continue
        end select
      end if
      return
    end if

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
      case('1', '2', '3', '4', '5', '6')
        ! Extended escape sequence (e.g., Ctrl+Arrow = ESC[1;5C)
        ! Parse it to check if it's a key we care about
        call handle_extended_escape_sequence(input_state)
      case default
        ! Unknown escape sequence - ignore it
        continue
      end select
    else
      ! Not '[', so it's an Alt+key combination (ESC followed by character)
      select case(ch1)
      case('.')
        ! Alt+. - Insert last argument from previous command
        call handle_yank_last_arg(input_state)
      case('b')
        ! Alt+b - Move backward one word
        call move_to_previous_word(input_state)
      case('f')
        ! Alt+f - Move forward one word
        call move_to_next_word(input_state)
      case('d')
        ! Alt+d - Delete word forward
        call handle_delete_word_forward(input_state)
      case('u')
        ! Alt+u - Uppercase word (from cursor to end of word)
        call handle_uppercase_word(input_state)
      case('l')
        ! Alt+l - Lowercase word (from cursor to end of word)
        call handle_lowercase_word(input_state)
      case('c')
        ! Alt+c - Capitalize word (uppercase first char, lowercase rest)
        call handle_capitalize_word(input_state)
      case(char(127))
        ! Alt+Backspace - Delete word backward (same as Ctrl+W)
        call handle_kill_word(input_state)
      case default
        ! Unknown Alt+key combination
        continue
      end select
    end if
  end subroutine

  ! Handle extended escape sequences like ESC[1;5C (Ctrl+Right Arrow)
  subroutine handle_extended_escape_sequence(input_state)
    type(input_state_t), intent(inout) :: input_state
    character :: ch, modifier, terminator
    logical :: success
    integer :: count

    ! Extended sequences have format: ESC[1;5C
    ! We've already read '1' (or similar), now read rest of sequence
    ! Format: [digit];[modifier][letter]

    ! Read until we find a semicolon or letter
    count = 0
    do while (count < 10)  ! Safety limit
      success = read_single_char(ch)
      if (.not. success) return

      if (ch == ';') then
        ! Found semicolon, next char is the modifier
        success = read_single_char(modifier)
        if (.not. success) return

        ! Read the terminating letter
        success = read_single_char(terminator)
        if (.not. success) return

        ! Check for Ctrl+Right arrow (modifier=5, terminator=C)
        if (modifier == '5' .and. terminator == 'C') then
          ! Ctrl+Right arrow - accept one word from autosuggestion
          if (input_state%cursor_pos == input_state%length .and. &
              input_state%suggestion_length > 0) then
            call accept_autosuggestion_word(input_state)
          end if
        ! Check for Alt+Up arrow (modifier=3, terminator=A)
        else if (modifier == '3' .and. terminator == 'A') then
          ! Alt+Up - Go to parent directory (cd ..)
          call handle_alt_up(input_state)
        ! Check for Alt+Left arrow (modifier=3, terminator=D)
        else if (modifier == '3' .and. terminator == 'D') then
          ! Alt+Left - Go to previous directory (prevd)
          call handle_alt_left(input_state)
        ! Check for Alt+Right arrow (modifier=3, terminator=C)
        else if (modifier == '3' .and. terminator == 'C') then
          ! Alt+Right - Go to next directory (nextd)
          call handle_alt_right(input_state)
        end if
        ! For other extended sequences, we just consume them
        return
      else if ((ch >= 'A' .and. ch <= 'Z') .or. (ch >= 'a' .and. ch <= 'z')) then
        ! Found letter terminator without semicolon, done
        return
      end if

      count = count + 1
    end do
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
    else if (input_state%cursor_pos == input_state%length .and. input_state%suggestion_length > 0) then
      ! At end of line with suggestion - accept it
      call accept_autosuggestion(input_state)
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

  ! Calculate visual length of string (excluding ANSI escape codes)
  function visual_length(str) result(vlen)
    character(len=*), intent(in) :: str
    integer :: vlen
    integer :: i, slen
    logical :: in_escape

    vlen = 0
    slen = len_trim(str)
    in_escape = .false.

    do i = 1, slen
      if (in_escape) then
        ! Inside escape sequence, skip until we find the terminator
        if (str(i:i) >= 'A' .and. str(i:i) <= 'Z') then
          in_escape = .false.  ! Capital letter terminates escape sequence
        else if (str(i:i) >= 'a' .and. str(i:i) <= 'z') then
          in_escape = .false.  ! Lowercase letter terminates escape sequence
        end if
      else if (str(i:i) == char(27)) then
        ! ESC character starts escape sequence
        in_escape = .true.
      else if (str(i:i) == char(13)) then
        ! Carriage return - doesn't add to visual length
        continue
      else
        ! Regular character
        vlen = vlen + 1
      end if
    end do
  end function

  ! ===========================================================================
  ! Fuzzy Matching Functions
  ! ===========================================================================

  ! Calculate fuzzy match score (higher = better match)
  ! Returns -1 if no match (pattern chars not found in order)
  ! Returns 0+ for matches with bonus points for:
  !   - Consecutive character matches
  !   - Matches at word boundaries
  !   - Matches at start of string
  function fuzzy_match_score(pattern, candidate) result(score)
    character(len=*), intent(in) :: pattern, candidate
    integer :: score

    integer :: pattern_len, candidate_len
    integer :: pattern_idx, candidate_idx
    integer :: match_positions(MAX_LINE_LEN)
    integer :: num_matches, i
    integer :: consecutive_bonus, boundary_bonus
    logical :: case_match, is_prefix_match
    character :: pattern_char, candidate_char

    pattern_len = len_trim(pattern)
    candidate_len = len_trim(candidate)

    ! Empty pattern matches everything with base score
    if (pattern_len == 0) then
      score = 100
      return
    end if

    ! Pattern longer than candidate = no match
    if (pattern_len > candidate_len) then
      score = -1
      return
    end if

    ! For short patterns (1-2 chars), require prefix match for better UX
    ! This prevents "RE" from matching "parser_enhanced.mod"
    if (pattern_len <= 2) then
      is_prefix_match = .true.
      do i = 1, pattern_len
        if (to_lowercase(pattern(i:i)) /= to_lowercase(candidate(i:i))) then
          is_prefix_match = .false.
          exit
        end if
      end do
      if (.not. is_prefix_match) then
        score = -1
        return
      end if
    end if

    ! Find all pattern characters in order
    pattern_idx = 1
    num_matches = 0

    do candidate_idx = 1, candidate_len
      if (pattern_idx > pattern_len) exit

      pattern_char = pattern(pattern_idx:pattern_idx)
      candidate_char = candidate(candidate_idx:candidate_idx)

      ! Case-insensitive comparison
      if (to_lowercase(pattern_char) == to_lowercase(candidate_char)) then
        num_matches = num_matches + 1
        match_positions(num_matches) = candidate_idx
        pattern_idx = pattern_idx + 1
      end if
    end do

    ! Not all pattern characters found = no match
    if (pattern_idx <= pattern_len) then
      score = -1
      return
    end if

    ! Base score: 100 points for matching
    score = 100

    ! Bonus for matching at start
    if (match_positions(1) == 1) then
      score = score + 50
    end if

    ! Bonus for consecutive matches
    consecutive_bonus = 0
    do i = 2, num_matches
      if (match_positions(i) == match_positions(i-1) + 1) then
        consecutive_bonus = consecutive_bonus + 10
      end if
    end do
    score = score + consecutive_bonus

    ! Bonus for matches at word boundaries (after space, -, _, /)
    boundary_bonus = 0
    do i = 1, num_matches
      if (match_positions(i) > 1) then
        candidate_char = candidate(match_positions(i)-1:match_positions(i)-1)
        if (candidate_char == ' ' .or. candidate_char == '-' .or. &
            candidate_char == '_' .or. candidate_char == '/') then
          boundary_bonus = boundary_bonus + 15
        end if
      end if
    end do
    score = score + boundary_bonus

    ! Bonus for case-sensitive match
    case_match = .true.
    do i = 1, num_matches
      pattern_char = pattern(i:i)
      candidate_char = candidate(match_positions(i):match_positions(i))
      if (pattern_char /= candidate_char) then
        case_match = .false.
        exit
      end if
    end do
    if (case_match) then
      score = score + 20
    end if

    ! Penalty for longer candidates (prefer shorter matches)
    score = score - (candidate_len - pattern_len)

    ! Penalty for gaps between matches
    do i = 2, num_matches
      score = score - (match_positions(i) - match_positions(i-1) - 1)
    end do
  end function

  ! Helper: convert character to lowercase
  function to_lowercase(c) result(lower)
    character, intent(in) :: c
    character :: lower
    integer :: ascii_val

    ascii_val = ichar(c)
    if (ascii_val >= ichar('A') .and. ascii_val <= ichar('Z')) then
      lower = char(ascii_val + 32)
    else
      lower = c
    end if
  end function

  ! Sort completions by fuzzy match score (bubble sort - good enough for small arrays)
  subroutine sort_completions_by_score(scored_completions, count)
    type(scored_completion_t), intent(inout) :: scored_completions(:)
    integer, intent(in) :: count

    type(scored_completion_t) :: temp
    integer :: i, j
    logical :: swapped

    ! Bubble sort (descending order - highest scores first)
    do i = 1, count - 1
      swapped = .false.
      do j = 1, count - i
        if (scored_completions(j)%score < scored_completions(j+1)%score) then
          temp = scored_completions(j)
          scored_completions(j) = scored_completions(j+1)
          scored_completions(j+1) = temp
          swapped = .true.
        end if
      end do
      if (.not. swapped) exit
    end do
  end subroutine

  subroutine redraw_line(prompt, input_state)
    character(len=*), intent(in) :: prompt
    type(input_state_t), intent(in) :: input_state
    character(len=:), allocatable :: highlighted
    integer :: term_rows, term_cols, total_visual_chars
    integer :: prompt_visual_len, current_line, end_line
    integer :: cursor_visual_pos, cursor_line, cursor_col
    integer :: i, suggestion_display_len, available_space
    logical :: success

    ! Get terminal size
    success = get_terminal_size(term_rows, term_cols)
    if (.not. success .or. term_cols <= 0) then
      term_cols = 80  ! Fallback
    end if

    ! Additional safety check
    if (term_cols < 20) then
      term_cols = 80  ! Ensure reasonable minimum
    end if

    ! Calculate visual length of prompt (excluding ANSI codes)
    prompt_visual_len = visual_length(prompt)

    ! Safety check for prompt length
    if (prompt_visual_len < 0) then
      prompt_visual_len = 0
    end if

    ! Calculate current cursor position in visual characters
    cursor_visual_pos = prompt_visual_len + input_state%cursor_pos

    ! Calculate which line the cursor is currently on (0-indexed)
    ! Extra safety: ensure term_cols is positive before division
    if (term_cols > 0) then
      current_line = cursor_visual_pos / term_cols
    else
      current_line = 0
    end if

    ! Safety check: limit current_line to reasonable value
    if (current_line < 0) current_line = 0
    if (current_line > 100) current_line = 0  ! Probably an error

    ! Move cursor up to the first line (where prompt starts)
    ! IMPORTANT: Only move up if we're not already at top (avoid negative positioning)
    if (current_line > 0) then
      do i = 1, current_line
        write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
      end do
    end if

    ! Move to beginning of current line
    write(output_unit, '(a)', advance='no') ESC_MOVE_BOL

    ! Clear from cursor to end of screen (clears all wrapped lines)
    write(output_unit, '(a)', advance='no') char(27) // '[J'

    ! Redraw prompt and full buffer with syntax highlighting
    write(output_unit, '(a)', advance='no') prompt
    if (input_state%length > 0) then
      highlighted = highlight_command_line(input_state%buffer(:input_state%length))
      write(output_unit, '(a)', advance='no') highlighted
    end if

    ! Display autosuggestion if cursor is at end
    ! IMPORTANT: Truncate suggestion to prevent wrapping beyond terminal width
    if (input_state%suggestion_length > 0 .and. input_state%cursor_pos == input_state%length) then
      ! Calculate available space on current line
      available_space = term_cols - mod(prompt_visual_len + input_state%length, term_cols)

      ! Safety check: ensure available_space is positive
      if (available_space < 0) available_space = 0

      ! Ensure we have enough space (need at least 2 chars: 1 for suggestion + 1 for cursor)
      if (available_space > 2) then
        ! Truncate suggestion if it would overflow the line
        suggestion_display_len = min(input_state%suggestion_length, available_space - 1)

        ! Additional safety check
        if (suggestion_display_len < 0) suggestion_display_len = 0
        if (suggestion_display_len > MAX_LINE_LEN) suggestion_display_len = 0

        if (suggestion_display_len > 0) then
          ! Gray color (ANSI code 90 or dim mode)
          write(output_unit, '(a)', advance='no') char(27) // '[2m'  ! Dim mode
          write(output_unit, '(a)', advance='no') input_state%suggestion(:suggestion_display_len)
          write(output_unit, '(a)', advance='no') char(27) // '[0m'  ! Reset

          ! Move cursor back to where it should be (after suggestion)
          do i = 1, suggestion_display_len
            write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
          end do
        end if
      end if
    end if

    ! Position cursor correctly (if not at end of input)
    if (input_state%cursor_pos < input_state%length) then
      ! Cursor not at end - move back to correct position
      do i = 1, input_state%length - input_state%cursor_pos
        write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
      end do
    end if

    flush(output_unit)
  end subroutine

  ! Partial redraw - only from cursor to end (reduces flashing)
  subroutine redraw_from_cursor(input_state)
    use syntax_highlight, only: highlight_command_line
    type(input_state_t), intent(in) :: input_state
    character(len=:), allocatable :: highlighted
    integer :: i, cursor_col

    if (input_state%length == 0) return

    ! Save current cursor column (we're already at the right position)
    cursor_col = input_state%cursor_pos

    ! Move to just before cursor position (account for prompt already displayed)
    ! We need to move back to start of buffer to redraw with highlighting
    if (cursor_col > 0) then
      do i = 1, cursor_col
        write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
      end do
    end if

    ! Clear from here to end of line
    write(output_unit, '(a)', advance='no') char(27) // '[K'

    ! Redraw buffer with highlighting
    highlighted = highlight_command_line(input_state%buffer(:input_state%length))
    write(output_unit, '(a)', advance='no') highlighted

    ! Move cursor back to correct position
    do i = input_state%length, cursor_col + 1, -1
      write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
    end do

    flush(output_unit)
  end subroutine

  ! Helper to convert integer to string
  function int_to_str(n) result(str)
    integer, intent(in) :: n
    character(len=20) :: str
    write(str, '(i0)') n
  end function

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
    character(len=:), allocatable :: highlighted
    integer :: i, term_rows, term_cols, available_space, suggestion_display_len
    logical :: success

    ! Clear screen and move cursor to home position (0,0)
    write(output_unit, '(a)', advance='no') char(27) // '[2J' // char(27) // '[H'

    ! Since we're now at home position, just redraw everything from scratch
    ! No need to calculate cursor movement - we know we're at top left

    ! Draw prompt
    write(output_unit, '(a)', advance='no') prompt

    ! Draw the current buffer with syntax highlighting
    if (input_state%length > 0) then
      highlighted = highlight_command_line(input_state%buffer(:input_state%length))
      write(output_unit, '(a)', advance='no') highlighted
    end if

    ! Position cursor correctly
    if (input_state%cursor_pos < input_state%length) then
      ! Need to move cursor back from end of line
      do i = 1, input_state%length - input_state%cursor_pos
        write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
      end do
    end if

    ! Handle autosuggestion if cursor is at end
    if (input_state%suggestion_length > 0 .and. input_state%cursor_pos == input_state%length) then
      ! Get terminal width for suggestion truncation
      success = get_terminal_size(term_rows, term_cols)
      if (.not. success .or. term_cols <= 0) then
        term_cols = 80
      end if

      ! Calculate available space
      available_space = term_cols - mod(visual_length(prompt) + input_state%length, term_cols)

      if (available_space > 2) then
        suggestion_display_len = min(input_state%suggestion_length, available_space - 1)

        if (suggestion_display_len > 0) then
          ! Display suggestion in gray
          write(output_unit, '(a)', advance='no') char(27) // '[2m'
          write(output_unit, '(a)', advance='no') input_state%suggestion(:suggestion_display_len)
          write(output_unit, '(a)', advance='no') char(27) // '[0m'

          ! Move cursor back to correct position after suggestion
          do i = 1, suggestion_display_len
            write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
          end do
        end if
      end if
    end if

    flush(output_unit)
    input_state%dirty = .false.
  end subroutine

  ! Transpose characters (Ctrl+t) - swap char at cursor with previous char
  subroutine handle_transpose_chars(input_state)
    type(input_state_t), intent(inout) :: input_state
    character :: temp

    ! Need at least 2 characters
    if (input_state%length < 2) return

    ! If at end of line, transpose last two chars
    if (input_state%cursor_pos >= input_state%length) then
      if (input_state%length >= 2) then
        temp = input_state%buffer(input_state%length:input_state%length)
        input_state%buffer(input_state%length:input_state%length) = &
          input_state%buffer(input_state%length-1:input_state%length-1)
        input_state%buffer(input_state%length-1:input_state%length-1) = temp
        input_state%dirty = .true.
      end if
    ! If at beginning, do nothing
    else if (input_state%cursor_pos == 0) then
      return
    ! Normal case: swap char at cursor with previous char, move cursor forward
    else
      temp = input_state%buffer(input_state%cursor_pos+1:input_state%cursor_pos+1)
      input_state%buffer(input_state%cursor_pos+1:input_state%cursor_pos+1) = &
        input_state%buffer(input_state%cursor_pos:input_state%cursor_pos)
      input_state%buffer(input_state%cursor_pos:input_state%cursor_pos) = temp
      input_state%cursor_pos = input_state%cursor_pos + 1
      input_state%dirty = .true.
    end if
  end subroutine

  ! Yank last argument from previous command (Alt+.)
  subroutine handle_yank_last_arg(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: last_cmd, last_arg
    integer :: i, arg_start, arg_end
    logical :: in_arg

    ! Get last command from history
    if (command_history%count == 0) return

    last_cmd = command_history%lines(command_history%count)

    ! Find last argument (last non-space word)
    arg_end = 0
    arg_start = 0
    in_arg = .false.

    ! Scan backwards to find last argument
    do i = len_trim(last_cmd), 1, -1
      if (last_cmd(i:i) /= ' ' .and. last_cmd(i:i) /= char(9)) then
        if (.not. in_arg) then
          arg_end = i
          in_arg = .true.
        end if
      else if (in_arg) then
        arg_start = i + 1
        exit
      end if
    end do

    ! If we found an arg but arg_start is still 0, it starts at position 1
    if (in_arg .and. arg_start == 0) arg_start = 1

    if (arg_start > 0 .and. arg_end >= arg_start) then
      last_arg = last_cmd(arg_start:arg_end)

      ! Insert the last argument at cursor position
      call insert_string_at_cursor(input_state, trim(last_arg))
    end if
  end subroutine

  ! Delete word forward (Alt+d)
  subroutine handle_delete_word_forward(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_end, i

    if (input_state%cursor_pos >= input_state%length) return

    word_end = input_state%cursor_pos + 1

    ! Skip any leading whitespace
    do while (word_end <= input_state%length .and. &
              input_state%buffer(word_end:word_end) == ' ')
      word_end = word_end + 1
    end do

    ! Find end of word (non-space characters)
    do while (word_end <= input_state%length .and. &
              input_state%buffer(word_end:word_end) /= ' ')
      word_end = word_end + 1
    end do

    if (word_end > input_state%cursor_pos + 1) then
      ! Save deleted text to kill buffer
      input_state%kill_buffer = input_state%buffer(input_state%cursor_pos+1:word_end-1)
      input_state%kill_length = word_end - input_state%cursor_pos - 1

      ! Shift remaining text left
      do i = input_state%cursor_pos + 1, input_state%length - (word_end - input_state%cursor_pos - 1)
        if (word_end + i - input_state%cursor_pos - 1 <= input_state%length) then
          input_state%buffer(i:i) = &
            input_state%buffer(word_end + i - input_state%cursor_pos - 1: &
                              word_end + i - input_state%cursor_pos - 1)
        else
          input_state%buffer(i:i) = ' '
        end if
      end do

      ! Update length
      input_state%length = input_state%length - (word_end - input_state%cursor_pos - 1)
      input_state%dirty = .true.
    end if
  end subroutine

  ! Uppercase word (Alt+u) - convert from cursor to end of word to uppercase
  subroutine handle_uppercase_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos, word_end
    character :: ch

    if (input_state%cursor_pos >= input_state%length) return

    pos = input_state%cursor_pos + 1

    ! Skip any leading whitespace
    do while (pos <= input_state%length .and. &
              input_state%buffer(pos:pos) == ' ')
      pos = pos + 1
    end do

    ! Uppercase characters until end of word
    do while (pos <= input_state%length .and. &
              input_state%buffer(pos:pos) /= ' ')
      ch = input_state%buffer(pos:pos)
      if (ch >= 'a' .and. ch <= 'z') then
        input_state%buffer(pos:pos) = char(ichar(ch) - 32)
      end if
      pos = pos + 1
    end do

    ! Move cursor to end of word
    input_state%cursor_pos = pos - 1
    input_state%dirty = .true.
  end subroutine

  ! Lowercase word (Alt+l) - convert from cursor to end of word to lowercase
  subroutine handle_lowercase_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos
    character :: ch

    if (input_state%cursor_pos >= input_state%length) return

    pos = input_state%cursor_pos + 1

    ! Skip any leading whitespace
    do while (pos <= input_state%length .and. &
              input_state%buffer(pos:pos) == ' ')
      pos = pos + 1
    end do

    ! Lowercase characters until end of word
    do while (pos <= input_state%length .and. &
              input_state%buffer(pos:pos) /= ' ')
      ch = input_state%buffer(pos:pos)
      if (ch >= 'A' .and. ch <= 'Z') then
        input_state%buffer(pos:pos) = char(ichar(ch) + 32)
      end if
      pos = pos + 1
    end do

    ! Move cursor to end of word
    input_state%cursor_pos = pos - 1
    input_state%dirty = .true.
  end subroutine

  ! Capitalize word (Alt+c) - uppercase first char, lowercase rest
  subroutine handle_capitalize_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos
    character :: ch
    logical :: first_char

    if (input_state%cursor_pos >= input_state%length) return

    pos = input_state%cursor_pos + 1

    ! Skip any leading whitespace
    do while (pos <= input_state%length .and. &
              input_state%buffer(pos:pos) == ' ')
      pos = pos + 1
    end do

    first_char = .true.

    ! Capitalize first character, lowercase rest until end of word
    do while (pos <= input_state%length .and. &
              input_state%buffer(pos:pos) /= ' ')
      ch = input_state%buffer(pos:pos)

      if (first_char) then
        ! Uppercase first character
        if (ch >= 'a' .and. ch <= 'z') then
          input_state%buffer(pos:pos) = char(ichar(ch) - 32)
        end if
        first_char = .false.
      else
        ! Lowercase remaining characters
        if (ch >= 'A' .and. ch <= 'Z') then
          input_state%buffer(pos:pos) = char(ichar(ch) + 32)
        end if
      end if

      pos = pos + 1
    end do

    ! Move cursor to end of word
    input_state%cursor_pos = pos - 1
    input_state%dirty = .true.
  end subroutine

  ! Alt+Up: Replace line with "cd .." (Fish-style parent directory navigation)
  subroutine handle_alt_up(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=5) :: cmd

    cmd = 'cd ..'

    ! Clear current buffer
    input_state%buffer = ''

    ! Insert "cd .."
    input_state%buffer(1:5) = cmd
    input_state%length = 5
    input_state%cursor_pos = 5

    ! Clear suggestion since we're replacing the line
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    input_state%dirty = .true.
  end subroutine

  ! Alt+Left: Replace line with "prevd" (Fish-style previous directory)
  subroutine handle_alt_left(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=5) :: cmd

    cmd = 'prevd'

    ! Clear current buffer
    input_state%buffer = ''

    ! Insert "prevd"
    input_state%buffer(1:5) = cmd
    input_state%length = 5
    input_state%cursor_pos = 5

    ! Clear suggestion since we're replacing the line
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    input_state%dirty = .true.
  end subroutine

  ! Alt+Right: Replace line with "nextd" (Fish-style next directory)
  subroutine handle_alt_right(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=5) :: cmd

    cmd = 'nextd'

    ! Clear current buffer
    input_state%buffer = ''

    ! Insert "nextd"
    input_state%buffer(1:5) = cmd
    input_state%length = 5
    input_state%cursor_pos = 5

    ! Clear suggestion since we're replacing the line
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    input_state%dirty = .true.
  end subroutine

  ! Helper: Insert string at cursor position
  subroutine insert_string_at_cursor(input_state, str)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: str
    integer :: i, str_len, insert_len

    str_len = len_trim(str)
    if (str_len == 0) return

    insert_len = min(str_len, MAX_LINE_LEN - input_state%length)
    if (insert_len == 0) return

    ! Shift existing text right to make room
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        input_state%buffer(i + insert_len:i + insert_len) = input_state%buffer(i:i)
      end if
    end do

    ! Insert string at cursor position
    do i = 1, insert_len
      input_state%buffer(input_state%cursor_pos + i:input_state%cursor_pos + i) = str(i:i)
    end do

    ! Update length and cursor position
    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
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
  subroutine handle_isearch(input_state, prompt, forward)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    logical, intent(in) :: forward

    ! Save current buffer if entering search for first time
    if (.not. input_state%in_search) then
      input_state%original_buffer = input_state%buffer(:input_state%length)
      input_state%in_search = .true.
      input_state%search_forward = forward
      input_state%search_string = ''
      input_state%search_length = 0
      input_state%search_match_index = 0
    else
      ! Ctrl+R/Ctrl+S pressed again - find next match
      ! Allow switching direction mid-search
      input_state%search_forward = forward
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

    if (input_state%search_forward) then
      ! Forward search - search from current match towards newer history
      do i = input_state%search_match_index + 1, command_history%count
        if (index(command_history%lines(i), trim(search_str)) > 0) then
          input_state%search_match_index = i
          input_state%buffer = command_history%lines(i)
          input_state%length = len_trim(command_history%lines(i))
          input_state%cursor_pos = input_state%length
          return
        end if
      end do

      ! Wrap around to beginning if no match found
      if (input_state%search_match_index > 0) then
        do i = 1, input_state%search_match_index - 1
          if (index(command_history%lines(i), trim(search_str)) > 0) then
            input_state%search_match_index = i
            input_state%buffer = command_history%lines(i)
            input_state%length = len_trim(command_history%lines(i))
            input_state%cursor_pos = input_state%length
            return
          end if
        end do
      end if
    else
      ! Reverse search - search from current match towards older history
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

      ! Search through history in the appropriate direction
      search_str = input_state%search_string(:input_state%search_length)

      if (input_state%search_forward) then
        ! Forward search - from beginning to end
        do i = 1, command_history%count
          if (index(command_history%lines(i), trim(search_str)) > 0) then
            input_state%search_match_index = i
            input_state%buffer = command_history%lines(i)
            input_state%length = len_trim(command_history%lines(i))
            input_state%cursor_pos = input_state%length
            exit
          end if
        end do
      else
        ! Reverse search - from end to beginning
        do i = command_history%count, 1, -1
          if (index(command_history%lines(i), trim(search_str)) > 0) then
            input_state%search_match_index = i
            input_state%buffer = command_history%lines(i)
            input_state%length = len_trim(command_history%lines(i))
            input_state%cursor_pos = input_state%length
            exit
          end if
        end do
      end if

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

        if (input_state%search_forward) then
          ! Forward search
          do i = 1, command_history%count
            if (index(command_history%lines(i), trim(search_str)) > 0) then
              input_state%search_match_index = i
              input_state%buffer = command_history%lines(i)
              input_state%length = len_trim(command_history%lines(i))
              input_state%cursor_pos = input_state%length
              exit
            end if
          end do
        else
          ! Reverse search
          do i = command_history%count, 1, -1
            if (index(command_history%lines(i), trim(search_str)) > 0) then
              input_state%search_match_index = i
              input_state%buffer = command_history%lines(i)
              input_state%length = len_trim(command_history%lines(i))
              input_state%cursor_pos = input_state%length
              exit
            end if
          end do
        end if
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

    ! Clear the search prompt and show normal prompt with result using proper redraw
    write(output_unit, '(a)', advance='no') char(13) // ESC_CLEAR_LINE
    flush(output_unit)

    ! Use redraw_line to properly display with syntax highlighting and cursor positioning
    call redraw_line(prompt, input_state)
  end subroutine

  subroutine update_search_display(input_state, prompt)
    type(input_state_t), intent(in) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=512) :: search_prompt
    character(len=32) :: direction_str

    ! Determine search direction string
    if (input_state%search_forward) then
      direction_str = '(i-search)'
    else
      direction_str = '(reverse-i-search)'
    end if

    ! Build search prompt
    if (input_state%search_length > 0) then
      write(search_prompt, '(a,a,a,a)') trim(direction_str), '`', &
            input_state%search_string(:input_state%search_length), "': "
    else
      write(search_prompt, '(a,a)') trim(direction_str), '`'': '
    end if

    ! Clear line and redraw
    write(output_unit, '(a)', advance='no') char(13) // ESC_CLEAR_LINE
    write(output_unit, '(a)', advance='no') trim(search_prompt)
    if (input_state%length > 0) then
      write(output_unit, '(a)', advance='no') input_state%buffer(:input_state%length)
    end if
    flush(output_unit)
  end subroutine

  ! ============================================================================
  ! Advanced Vi Mode Features
  ! ============================================================================

  ! Vi-style yank (copy)
  subroutine handle_vi_yank(input_state)
    type(input_state_t), intent(inout) :: input_state

    ! Simplified: yank entire line (yy behavior)
    if (input_state%length > 0) then
      input_state%vi_yank_buffer = input_state%buffer(:input_state%length)
      input_state%vi_yank_length = input_state%length
    else
      input_state%vi_yank_buffer = ''
      input_state%vi_yank_length = 0
    end if
  end subroutine

  ! Vi-style put (paste)
  subroutine handle_vi_put(input_state, before_cursor)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(in) :: before_cursor
    integer :: i, insert_len, insert_pos

    if (input_state%vi_yank_length == 0) return

    insert_len = min(input_state%vi_yank_length, MAX_LINE_LEN - input_state%length)
    if (insert_len == 0) return

    ! Determine insertion position
    if (before_cursor) then
      insert_pos = input_state%cursor_pos
    else
      ! After cursor
      insert_pos = min(input_state%cursor_pos + 1, input_state%length)
    end if

    ! Shift existing text right to make room
    do i = input_state%length, insert_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        input_state%buffer(i + insert_len:i + insert_len) = input_state%buffer(i:i)
      end if
    end do

    ! Insert yanked text at insertion position
    do i = 1, insert_len
      input_state%buffer(insert_pos + i:insert_pos + i) = input_state%vi_yank_buffer(i:i)
    end do

    ! Update length and cursor position
    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = insert_pos + insert_len - 1
    input_state%dirty = .true.
  end subroutine

  ! Set a vi mark
  subroutine handle_vi_mark_set(input_state, mark_char)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: mark_char
    integer :: mark_index

    ! Convert character to mark index (a-z = 1-26)
    if (mark_char >= 'a' .and. mark_char <= 'z') then
      mark_index = iachar(mark_char) - iachar('a') + 1
      input_state%vi_marks(mark_index) = input_state%cursor_pos
    end if

    ! Clear command buffer
    input_state%vi_command_buffer = ''
    input_state%vi_command_count = 0
  end subroutine

  ! Jump to a vi mark
  subroutine handle_vi_mark_jump(input_state, mark_char)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: mark_char
    integer :: mark_index, mark_pos

    ! Convert character to mark index (a-z = 1-26)
    if (mark_char >= 'a' .and. mark_char <= 'z') then
      mark_index = iachar(mark_char) - iachar('a') + 1
      mark_pos = input_state%vi_marks(mark_index)

      ! Jump to mark if it's set (non-zero) and valid
      if (mark_pos > 0 .and. mark_pos <= input_state%length) then
        input_state%cursor_pos = mark_pos
        input_state%dirty = .true.
      end if
    end if

    ! Clear command buffer
    input_state%vi_command_buffer = ''
    input_state%vi_command_count = 0
  end subroutine

  ! Start vi-style search (/ or ?)
  subroutine handle_vi_search_start(input_state, forward)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(in) :: forward

    ! Enter vi search mode
    input_state%vi_in_vi_search = .true.
    input_state%vi_search_forward = forward
    input_state%vi_search_pattern = ''
    input_state%vi_search_length = 0

    ! Visual feedback: show search prompt
    write(output_unit, '()')  ! New line
    if (forward) then
      write(output_unit, '(a)', advance='no') '/'
    else
      write(output_unit, '(a)', advance='no') '?'
    end if
    flush(output_unit)
  end subroutine

  ! Find next/previous search match in vi mode
  subroutine handle_vi_search_next(input_state, forward)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(in) :: forward
    integer :: i, match_pos
    logical :: found

    if (input_state%vi_search_length == 0) return

    found = .false.

    ! Determine search direction based on original direction and forward flag
    if (input_state%vi_search_forward .eqv. forward) then
      ! Search in same direction as original
      if (input_state%vi_search_forward) then
        ! Search forward from current position
        match_pos = index(input_state%buffer(input_state%cursor_pos+2:input_state%length), &
                         input_state%vi_search_pattern(:input_state%vi_search_length))
        if (match_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos + 1 + match_pos
          found = .true.
        end if
      else
        ! Search backward from current position
        ! Simplified: search from beginning to current position
        do i = input_state%cursor_pos - 1, 1, -1
          match_pos = index(input_state%buffer(i:input_state%cursor_pos-1), &
                           input_state%vi_search_pattern(:input_state%vi_search_length))
          if (match_pos > 0) then
            input_state%cursor_pos = i + match_pos - 1
            found = .true.
            exit
          end if
        end do
      end if
    else
      ! Search in opposite direction
      if (input_state%vi_search_forward) then
        ! Original was forward, now search backward
        do i = input_state%cursor_pos - 1, 1, -1
          match_pos = index(input_state%buffer(i:input_state%cursor_pos-1), &
                           input_state%vi_search_pattern(:input_state%vi_search_length))
          if (match_pos > 0) then
            input_state%cursor_pos = i + match_pos - 1
            found = .true.
            exit
          end if
        end do
      else
        ! Original was backward, now search forward
        match_pos = index(input_state%buffer(input_state%cursor_pos+2:input_state%length), &
                         input_state%vi_search_pattern(:input_state%vi_search_length))
        if (match_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos + 1 + match_pos
          found = .true.
        end if
      end if
    end if

    if (found) then
      input_state%dirty = .true.
    end if
  end subroutine

  ! ============================================================================
  ! Abbreviation Expansion (Fish-style)
  ! ============================================================================

  ! Try to expand an abbreviation at cursor position (called when space is typed)
  subroutine try_expand_abbreviation_at_cursor(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: word_before_cursor
    character(len=:), allocatable :: expanded_form
    integer :: word_start, word_end, i, expanded_len

    ! Extract word before cursor
    word_end = input_state%cursor_pos
    word_start = word_end

    ! Find start of word (go backwards until space or beginning)
    do while (word_start > 0)
      if (input_state%buffer(word_start:word_start) == ' ') then
        word_start = word_start + 1
        exit
      end if
      word_start = word_start - 1
    end do

    if (word_start == 0) word_start = 1

    ! Extract the word
    if (word_end > word_start) then
      word_before_cursor = input_state%buffer(word_start:word_end)
    else
      return  ! No word to expand
    end if

    ! Check if it's an abbreviation
    expanded_form = try_expand_abbreviation(trim(word_before_cursor))
    if (len(expanded_form) == 0) return  ! Not an abbreviation

    ! Replace the word with expanded form
    expanded_len = len(expanded_form)

    ! First, remove the original word by shifting left
    do i = word_end + 1, input_state%length
      input_state%buffer(word_start + i - word_end - 1:word_start + i - word_end - 1) = &
        input_state%buffer(i:i)
    end do
    input_state%length = input_state%length - (word_end - word_start + 1)
    input_state%cursor_pos = word_start - 1

    ! Then insert the expanded form
    ! Make room for expanded text
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + expanded_len <= MAX_LINE_LEN) then
        input_state%buffer(i + expanded_len:i + expanded_len) = input_state%buffer(i:i)
      end if
    end do

    ! Insert expanded text
    do i = 1, expanded_len
      if (input_state%cursor_pos + i <= MAX_LINE_LEN) then
        input_state%buffer(input_state%cursor_pos + i:input_state%cursor_pos + i) = &
          expanded_form(i:i)
      end if
    end do

    input_state%length = input_state%length + expanded_len
    input_state%cursor_pos = input_state%cursor_pos + expanded_len
    input_state%dirty = .true.
  end subroutine try_expand_abbreviation_at_cursor

  ! ============================================================================
  ! Autosuggestion Support (Fish-style)
  ! ============================================================================

  ! Update autosuggestion based on current input
  subroutine update_autosuggestion(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, newline_pos, j
    character(len=MAX_LINE_LEN) :: current_input
    character(len=MAX_LINE_LEN) :: suggestion_candidate


    ! Clear suggestion if buffer is empty or in special modes
    if (input_state%length == 0 .or. input_state%in_search .or. input_state%in_history) then
      input_state%suggestion = ''
      input_state%suggestion_length = 0
      return
    end if

    ! Get current input
    current_input = input_state%buffer(:input_state%length)

    ! Search history backwards for matching command
    do i = command_history%count, 1, -1
      ! Check if history entry starts with current input
      if (len_trim(command_history%lines(i)) > input_state%length) then
        if (command_history%lines(i)(:input_state%length) == current_input(:input_state%length)) then
          ! Found a match! Store the rest as suggestion
          ! CRITICAL FIX: Stop at first newline to avoid multi-line suggestions (heredocs, etc.)
          suggestion_candidate = command_history%lines(i)(input_state%length+1:)

          ! Find first newline character
          newline_pos = 0
          do j = 1, len_trim(suggestion_candidate)
            if (suggestion_candidate(j:j) == char(10) .or. suggestion_candidate(j:j) == char(13)) then
              newline_pos = j - 1
              exit
            end if
          end do

          if (newline_pos >= 0 .and. newline_pos < len_trim(suggestion_candidate)) then
            ! Found newline - truncate before it (or clear if newline is first char)
            if (newline_pos > 0) then
              input_state%suggestion = suggestion_candidate(:newline_pos)
              input_state%suggestion_length = newline_pos
            else
              ! Newline is first character - no suggestion
              input_state%suggestion = ''
              input_state%suggestion_length = 0
            end if
          else
            ! No newline found, use full suggestion
            input_state%suggestion = suggestion_candidate
            input_state%suggestion_length = len_trim(suggestion_candidate)
          end if
          return
        end if
      end if
    end do

    ! No match found
    input_state%suggestion = ''
    input_state%suggestion_length = 0
  end subroutine

  ! Accept the current autosuggestion
  subroutine accept_autosuggestion(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i

    if (input_state%suggestion_length == 0) return

    ! Append suggestion to buffer
    do i = 1, input_state%suggestion_length
      if (input_state%length + i <= MAX_LINE_LEN) then
        input_state%buffer(input_state%length + i:input_state%length + i) = &
          input_state%suggestion(i:i)
      end if
    end do

    input_state%length = input_state%length + input_state%suggestion_length
    input_state%cursor_pos = input_state%length
    input_state%suggestion = ''
    input_state%suggestion_length = 0
    input_state%dirty = .true.
  end subroutine

  ! Accept one word from the autosuggestion (for partial acceptance)
  subroutine accept_autosuggestion_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, word_end

    if (input_state%suggestion_length == 0) return

    ! Find the end of the first word in the suggestion
    word_end = 0
    do i = 1, input_state%suggestion_length
      if (input_state%suggestion(i:i) == ' ' .or. input_state%suggestion(i:i) == '/') then
        word_end = i
        exit
      end if
    end do

    if (word_end == 0) then
      ! No space found, accept entire suggestion
      call accept_autosuggestion(input_state)
      return
    end if

    ! Append first word to buffer
    do i = 1, word_end
      if (input_state%length + i <= MAX_LINE_LEN) then
        input_state%buffer(input_state%length + i:input_state%length + i) = &
          input_state%suggestion(i:i)
      end if
    end do

    input_state%length = input_state%length + word_end
    input_state%cursor_pos = input_state%length
    input_state%dirty = .true.

    ! Update suggestion to remove accepted part
    call update_autosuggestion(input_state)
  end subroutine

end module readline