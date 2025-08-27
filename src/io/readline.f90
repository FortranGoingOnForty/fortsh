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
  integer, parameter :: KEY_CTRL_A = 1    ! Home
  integer, parameter :: KEY_CTRL_E = 5    ! End
  integer, parameter :: KEY_CTRL_K = 11   ! Kill to end of line
  integer, parameter :: KEY_CTRL_L = 12   ! Clear screen
  integer, parameter :: KEY_ESC = 27
  integer, parameter :: KEY_UP = 65
  integer, parameter :: KEY_DOWN = 66
  integer, parameter :: KEY_RIGHT = 67
  integer, parameter :: KEY_LEFT = 68
  
  ! History and line management
  integer, parameter :: MAX_HISTORY = 1000
  integer, parameter :: MAX_LINE_LEN = 1024
  
  ! Input state management
  type :: input_state_t
    character(len=MAX_LINE_LEN) :: buffer = ''
    character(len=MAX_LINE_LEN) :: original_buffer = '' ! Save original input during history navigation
    integer :: length = 0
    integer :: cursor_pos = 0  ! 0-based position in buffer
    integer :: history_pos = 0  ! Current position in history (0 = not browsing)
    logical :: dirty = .false. ! Needs redraw
    logical :: in_history = .false. ! Currently browsing history
  end type input_state_t

  type :: history_t
    character(len=MAX_LINE_LEN) :: lines(MAX_HISTORY)
    integer :: count = 0
    integer :: current = 0  ! Current position in history navigation
  end type history_t

  type(history_t), save :: command_history

contains

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
    input_state%length = 0
    input_state%cursor_pos = 0
    input_state%history_pos = 0
    input_state%dirty = .false.
    input_state%in_history = .false.
    
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
          ! Enter - finish input
          write(output_unit, '()')  ! New line
          done = .true.
          
        case(KEY_CTRL_D)
          ! Ctrl+D - EOF
          if (input_state%length == 0) then
            iostat = -1
            done = .true.
          end if
          
        case(KEY_CTRL_C)
          ! Ctrl+C - cancel input
          write(output_unit, '(a)') '^C'
          input_state%buffer = ''
          input_state%length = 0
          done = .true.
          
        case(KEY_BACKSPACE)
          ! Backspace
          call handle_backspace(input_state)
          
        case(KEY_TAB)
          ! Tab completion (placeholder)
          call handle_tab_completion(input_state)
          
        case(KEY_ESC)
          ! Escape sequence - try to read more
          call handle_escape_sequence(input_state, done)
          
        case(32:126)
          ! Regular printable characters
          call insert_char(input_state, ch)
          
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
      ! write(error_unit, '(a,a,a,i0)') 'DEBUG: Got line: "', trim(line), '", length: ', input_state%length
      if (input_state%length > 0) then
        call add_to_history(line)
      end if
    else
      line = ''
      ! write(error_unit, '(a)') 'DEBUG: iostat not 0, no line returned'
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
    
    ! Add to history if successful and non-empty
    if (iostat == 0 .and. len_trim(line) > 0) then
      call add_to_history(line)
    end if
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
    
    ! Add to history if non-empty
    if (len_trim(line) > 0) then
      call add_to_history(line)
    end if
  end subroutine

  subroutine add_to_history(line)
    character(len=*), intent(in) :: line
    integer :: i
    
    ! Debug: Show what we're trying to add
    ! write(error_unit, '(a,a)') 'DEBUG: Adding to history: "', trim(line) // '"'
    
    ! Don't add duplicate consecutive commands
    if (command_history%count > 0) then
      if (trim(command_history%lines(command_history%count)) == trim(line)) then
        return
      end if
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
    
    ! Debug: Show history count
    ! write(error_unit, '(a,i0)') 'DEBUG: History count now: ', command_history%count
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
  subroutine smart_tab_complete(partial_input, line, completed)
    character(len=*), intent(in) :: partial_input
    character(len=*), intent(out) :: line
    logical, intent(out) :: completed
    
    character(len=MAX_LINE_LEN) :: completions(50)
    character(len=MAX_LINE_LEN) :: common_prefix
    integer :: num_completions
    
    completed = .false.
    line = partial_input
    
    call tab_complete(partial_input, completions, num_completions)
    
    if (num_completions == 0) then
      ! No completions found
      return
    else if (num_completions == 1) then
      ! Single completion - use it
      line = trim(partial_input) // trim(completions(1))
      completed = .true.
    else
      ! Multiple completions - try common prefix
      common_prefix = get_common_prefix(completions, num_completions)
      
      if (len_trim(common_prefix) > 0) then
        line = trim(partial_input) // trim(common_prefix)
        completed = .true.
      end if
      
      ! Show all completions
      call show_completions(completions, num_completions)
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
    ! TODO: Implement tab completion
    ! For now, just insert spaces
    call insert_char(input_state, ' ')
    call insert_char(input_state, ' ')
  end subroutine
  
  subroutine handle_escape_sequence(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character :: ch1, ch2
    logical :: success
    
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

end module readline