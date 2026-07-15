! ==============================================================================
! Module: readline_history
! Purpose: Command-history data operations and history expansion (QUAL-13 split).
!          Pure over the shared command_history store in readline_state; no
!          terminal I/O beyond `show_history`/file save-load. Re-exported by
!          readline so `use readline` consumers (fortsh, builtins) are unchanged.
! ==============================================================================
module readline_history
  use readline_constants   ! history_t, MAX_HISTORY, MAX_LINE_LEN
  use readline_state       ! command_history, current_histcontrol
  use iso_fortran_env, only: output_unit, error_unit
#ifdef USE_MEMORY_POOL
  use memory_dashboard     ! MOD_HISTORY, dashboard_track_allocation/deallocation
#endif
  implicit none

contains

  ! Initialize history with allocated array
  subroutine init_history()
    if (.not. command_history%initialized) then
      ! Type already specifies character(len=MAX_LINE_LEN), so just allocate array
      allocate(command_history%lines(MAX_HISTORY))
      command_history%lines = ''
      command_history%count = 0
      command_history%current = 0
      command_history%initialized = .true.
#ifdef USE_MEMORY_POOL
      ! Track history array allocation (MAX_HISTORY * MAX_LINE_LEN bytes)
      call dashboard_track_allocation(MOD_HISTORY, MAX_HISTORY * MAX_LINE_LEN, 5)
#endif
    end if
  end subroutine

  ! Clean up history allocations
  subroutine cleanup_history()
    if (command_history%initialized) then
#ifdef USE_MEMORY_POOL
      ! Track history array deallocation before releasing
      call dashboard_track_deallocation(MOD_HISTORY, MAX_HISTORY * MAX_LINE_LEN, 5)
#endif
      if (allocated(command_history%lines)) deallocate(command_history%lines)
      command_history%count = 0
      command_history%current = 0
      command_history%initialized = .false.
    end if
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
      ! Bash is silent when history is empty
      return
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

    ! Create empty file if no history (matches bash behavior)
    if (command_history%count == 0) then
      open(newunit=unit, file=trim(filepath), status='replace', &
           action='write', iostat=iostat)
      if (iostat == 0) close(unit)
      return
    end if

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

    ! Ensure history is initialized before loading
    call init_history()

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

end module readline_history
