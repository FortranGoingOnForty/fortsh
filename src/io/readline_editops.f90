! ==============================================================================
! Module: readline_editops
! Purpose: Buffer-editing engine below the terminal render layer (QUAL-13) -
!          text selection, word motions, range delete/yank, single-character
!          insertion, kill-ring yank, history-line navigation, and the path/
!          abbreviation autosuggestion compute. These mutate the input buffer
!          and state; the readline render loop redraws after the handler returns,
!          so nothing here calls the cursor/redraw core. A leaf over
!          readline_bufferops (+ completion/history/suggestion/abbrev modules),
!          shared with readline_vi. Re-exported by readline, so use-readline
!          consumers are unchanged.
! ==============================================================================
module readline_editops
  use readline_constants
  use readline_state
  use readline_bufferops
  use readline_autopair
  use readline_history, only: get_history_line
  use readline_completion_backend, only: complete_files_enhanced
  use suggestions, only: compute_path_suggestion, compute_history_suggestion, &
                         suggestion_result_t, SUGGEST_NONE
  use abbreviations, only: try_expand_abbreviation
  use system_interface
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  use iso_c_binding
  implicit none

contains

  !============================================================================
  ! TEST MODE INITIALIZATION
  !============================================================================
  ! Initialize test mode from environment variable
  ! This disables tab completion and syntax highlighting for reliable testing
  subroutine init_test_mode()
    character(len=:), allocatable :: test_mode_env, no_completion_env

    if (test_mode_initialized) return

    test_mode_env = get_environment_var('FORTSH_TEST_MODE')
    test_mode_enabled = (allocated(test_mode_env) .and. trim(test_mode_env) == '1')

    ! Completion can be disabled independently of test mode
    no_completion_env = get_environment_var('FORTSH_NO_COMPLETION')
    completion_disabled = (allocated(no_completion_env) .and. trim(no_completion_env) == '1')

    test_mode_initialized = .true.
  end subroutine init_test_mode

  ! Initialize debug flag from environment (idempotent).
  subroutine init_debug_selection()
    integer :: status
    character(len=8) :: env_val
    if (debug_selection_initialized) return
    call get_environment_variable('FORTSH_DEBUG_SELECTION', env_val, status=status)
    debug_selection = (status == 0 .and. trim(env_val) == '1')
    debug_selection_initialized = .true.
  end subroutine init_debug_selection

  ! Emit a debug trace line if FORTSH_DEBUG_SELECTION=1.
  subroutine debug_selection_log(tag, state)
    use iso_fortran_env, only: error_unit
    character(len=*), intent(in) :: tag
    type(input_state_t), intent(in) :: state
    if (.not. debug_selection_initialized) call init_debug_selection()
    if (.not. debug_selection) return
    if (state%selection_active) then
      write(error_unit, '(a,a,a,i0,a,i0,a,i0,a,l1)') &
        '[SEL:', trim(tag), '] cursor_pos=', state%cursor_pos, &
        ' anchor=', state%selection_anchor, &
        ' length=', state%length, &
        ' active=', state%selection_active
    else
      write(error_unit, '(a,a,a,i0,a,i0,a,l1)') &
        '[SEL:', trim(tag), '] cursor_pos=', state%cursor_pos, &
        ' length=', state%length, &
        ' active=', state%selection_active
    end if
  end subroutine debug_selection_log

  ! Clear selection state (no cursor motion, no dirty flag).
  ! Caller is responsible for setting dirty if a redraw is needed.
  subroutine collapse_selection(state)
    type(input_state_t), intent(inout) :: state
    if (.not. state%selection_active) return
    state%selection_anchor = -1
    state%selection_active = .false.
    call debug_selection_log('collapse', state)
  end subroutine collapse_selection

  ! Called AFTER a base movement handler has moved the cursor while
  ! module_extending_selection is .true. Establishes a new selection anchored
  ! at old_cursor_pos if one isn't already active, or extends the existing
  ! one. If the motion brings cursor back to anchor, auto-collapses.
  subroutine update_selection_on_shift_motion(state, old_cursor_pos)
    type(input_state_t), intent(inout) :: state
    integer, intent(in) :: old_cursor_pos

    if (state%cursor_pos == old_cursor_pos) then
      ! No actual motion occurred (e.g. Shift+Left at pos 0). Leave state alone.
      return
    end if

    if (.not. state%selection_active) then
      ! Starting a fresh selection — anchor at the position before this motion.
      state%selection_anchor = old_cursor_pos
      state%selection_active = .true.
    end if

    ! If the motion brought cursor back to anchor, the selection is empty — collapse.
    if (state%selection_anchor == state%cursor_pos) then
      call collapse_selection(state)
    end if

    ! Selection rendering needs a full redraw (Sprint 2 handles the highlight).
    state%dirty = .true.
    call debug_selection_log('extend', state)
  end subroutine update_selection_on_shift_motion

  ! Remove the selected byte range from the buffer, set cursor to the left
  ! edge, and clear selection state. No-op if selection is not active.
  ! Unused in Sprint 1 itself, but lands now for use in Sprint 3.
  subroutine delete_selection(state)
    type(input_state_t), intent(inout) :: state
    integer :: sel_start, sel_end, span, i
    character(len=MAX_LINE_LEN) :: temp_buf

    if (.not. state%selection_active) return
    if (state%selection_anchor < 0) then
      ! Defensive: active flag set without an anchor; just clear state.
      call collapse_selection(state)
      return
    end if

    sel_start = min(state%selection_anchor, state%cursor_pos)
    sel_end   = max(state%selection_anchor, state%cursor_pos)
    span      = sel_end - sel_start

    if (span <= 0) then
      call collapse_selection(state)
      return
    end if

    ! Read current buffer, shift bytes after sel_end leftward, rewrite.
    call state_buffer_get(state, temp_buf)
    do i = sel_end + 1, state%length
      call state_buffer_set_char(state, i - span, temp_buf(i:i))
    end do
    ! Pad the now-unused tail so stale bytes don't leak on later reads.
    do i = state%length - span + 1, state%length
      call state_buffer_set_char(state, i, ' ')
    end do

    state%length     = state%length - span
    state%cursor_pos = sel_start
    state%dirty      = .true.
    call collapse_selection(state)
    call debug_selection_log('delete', state)
  end subroutine delete_selection

  ! Begin recording an insert/change for dot-repeat (AR-05b 2b). `entry` is the
  ! command that entered insert (i/a/A/I/o/O/C/c); `motion` is the change motion
  ! for entry=='c'. No-op while replaying.
  subroutine dot_begin_insert(entry, motion, count)
    character, intent(in) :: entry, motion
    integer, intent(in) :: count
    if (dot_replaying) return
    dot_kind = DOTK_INSERT
    dot_entry = entry
    dot_motion = motion
    dot_count = max(1, count)
    dot_insert_len = 0
    dot_recording_insert = .true.
  end subroutine

  ! Helper: Yank a range of characters
  subroutine yank_range(input_state, start_pos, end_pos)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: start_pos, end_pos
    integer :: yank_len
    character(len=MAX_LINE_LEN) :: temp_buf

    yank_len = max(0, min(end_pos - start_pos, MAX_LINE_LEN))
    if (yank_len > 0 .and. start_pos >= 1 .and. start_pos <= input_state%length) then
      ! Extract buffer to temp, then substring
      call state_buffer_get(input_state, temp_buf)
      session_vi_yank = temp_buf(start_pos:start_pos+yank_len-1)
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
        call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, end_pos+i-start_pos))
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
    do while (pos <= input_state%length .and. state_buffer_get_char(input_state, pos) == ' ')
      pos = pos + 1
    end do

    ! Find end of word (pos will be one past the last character)
    do while (pos <= input_state%length .and. state_buffer_get_char(input_state, pos) /= ' ')
      pos = pos + 1
    end do

    ! cursor_pos is 0-indexed, pos is 1-indexed buffer position
    ! After loop, pos is at space after word, so pos-1 is last char buffer position
    ! To get cursor at last char: cursor_pos + 1 = pos - 1, so cursor_pos = pos - 2
    input_state%cursor_pos = max(0, min(pos - 2, input_state%length - 1))
    input_state%dirty = .true.
  end subroutine

  subroutine move_to_next_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos, cls
    integer :: old_cursor_pos

    ! Plain word-motion with active selection: clear, then proceed from
    ! current cursor. No snap — word motion runs through the old cursor
    ! anyway (#25, #26).
    if (input_state%selection_active .and. .not. module_extending_selection) then
      call collapse_selection(input_state)
      input_state%dirty = .true.
    end if

    old_cursor_pos = input_state%cursor_pos

    pos = input_state%cursor_pos + 1

    ! Vi mode vs Emacs mode have different word movement behavior
    if (input_state%editing_mode == EDITING_MODE_VI) then
      ! Vi mode 'w': move to START of next word
      ! 1. Skip remaining non-space chars of current word
      do while (pos <= input_state%length .and. state_buffer_get_char(input_state, pos) /= ' ')
        pos = pos + 1
      end do
      ! 2. Skip spaces
      do while (pos <= input_state%length .and. state_buffer_get_char(input_state, pos) == ' ')
        pos = pos + 1
      end do
      ! 3. Now at START of next word (or end of line)
      input_state%cursor_pos = min(pos - 1, input_state%length)
    else
      ! Emacs mode (Alt+f): fish forward-word — skip whitespace, then consume
      ! ONE class-run (punctuation runs are their own small-word; DIV-3).
      do while (pos <= input_state%length .and. &
                char_class(state_buffer_get_char(input_state, pos)) == 0)
        pos = pos + 1
      end do
      if (pos <= input_state%length) then
        cls = char_class(state_buffer_get_char(input_state, pos))
        do while (pos <= input_state%length .and. &
                  char_class(state_buffer_get_char(input_state, pos)) == cls)
          pos = pos + 1
        end do
      end if
      input_state%cursor_pos = min(pos - 1, input_state%length)
    end if

    input_state%dirty = .true.

    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine

  subroutine move_to_previous_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos, cls
    integer :: old_cursor_pos

    ! Plain word-motion with active selection: clear, then proceed from
    ! current cursor (#25, #26).
    if (input_state%selection_active .and. .not. module_extending_selection) then
      call collapse_selection(input_state)
      input_state%dirty = .true.
    end if

    old_cursor_pos = input_state%cursor_pos

    if (input_state%cursor_pos <= 0) then
      if (module_extending_selection) then
        call update_selection_on_shift_motion(input_state, old_cursor_pos)
      end if
      return
    end if

    pos = input_state%cursor_pos - 1

    if (input_state%editing_mode == EDITING_MODE_VI) then
      ! Vi 'b': whitespace-delimited (vi word-style refinement is AR-05b/DIV-7).
      do while (pos > 0 .and. state_buffer_get_char(input_state, pos) == ' ')
        pos = pos - 1
      end do
      do while (pos > 0 .and. state_buffer_get_char(input_state, pos) /= ' ')
        pos = pos - 1
      end do
    else
      ! Emacs (Alt+b): fish backward-word — skip whitespace, then step back over
      ! ONE class-run so a punctuation run is its own small-word (DIV-3).
      do while (pos > 0 .and. char_class(state_buffer_get_char(input_state, pos)) == 0)
        pos = pos - 1
      end do
      if (pos > 0) then
        cls = char_class(state_buffer_get_char(input_state, pos))
        do while (pos > 0 .and. char_class(state_buffer_get_char(input_state, pos)) == cls)
          pos = pos - 1
        end do
      end if
    end if

    ! pos is now just before the word start (or 0). cursor_pos is a
    ! between-characters index, so this lands the cursor at the word start.
    input_state%cursor_pos = pos
    input_state%dirty = .true.

    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine

  subroutine delete_char_at_cursor(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i

    if (input_state%cursor_pos >= input_state%length) return

    ! Shift characters left
    do i = input_state%cursor_pos + 1, input_state%length - 1
      call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, i+1))
    end do

    input_state%length = input_state%length - 1
    call state_buffer_set_char(input_state, input_state%length+1, ' ')
    input_state%dirty = .true.
  end subroutine

  ! Helper functions for enhanced readline
  subroutine insert_char_impl(input_state, ch)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: ch
    integer :: term_cols
    character(len=:), allocatable :: temp_buffer  ! Heap allocation to avoid stack overflow
    logical :: ap_do_close, ap_ok, ap_consumed
    character :: ap_closer

    ! AR-11 PAIRS: typing the closer we auto-inserted walks over it instead of
    ! doubling it. This lives here rather than in the keystroke dispatch so the
    ! vi dot-repeat replay — which calls insert_char_impl directly, bypassing
    ! insert_char_wrapper so it isn't re-recorded — reproduces the original edit
    ! byte for byte: a recorded "()" replays as auto-close then skip-over.
    ! Skipped while a selection is live, where the key must type over instead.
    if (.not. input_state%selection_active) then
      call autopair_try_skip(input_state, ch, ap_consumed)
      if (ap_consumed) then
        call update_autosuggestion(input_state)
        return
      end if
    end if

    ! Shift-phase type-over (Sprint 3): typing a character while a selection
    ! is active replaces the selection. delete_selection removes the bytes,
    ! moves cursor to the left edge, and clears selection state.
    if (input_state%selection_active) call delete_selection(input_state)

    ! temp_buffer (the right-shift scratch) is only needed for a middle
    ! insertion; the append path never touches it. Allocate it lazily in the
    ! else branch instead of on every keystroke — at MAX_LINE_LEN = 8192 the
    ! per-keystroke append allocation was 8 KB of pure waste. (QUAL-8)

    ! Check if we have room for one more character
    ! CRITICAL: Must be >= MAX_LINE_LEN - 1 to prevent writing to position MAX_LINE_LEN + 1
    ! during middle insertions which shift characters right.
    ! At the cap, ring the bell instead of dropping the char silently (QUAL-6):
    ! the input still fits far more than the old 1023, but overflow must be
    ! audible rather than truncating the command invisibly on its way to exec.
    if (input_state%length >= MAX_LINE_LEN - 1) then
      write(output_unit, '(a)', advance='no') char(7)
      flush(output_unit)
      return
    end if

    ! If we're browsing history, exit history mode when typing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Reset completion state when buffer changes
    input_state%completions_shown = .false.

    ! Check for abbreviation expansion BEFORE inserting the separator. fish
    ! expands on space and the command separators ; | & > < ) (AR-07
    ! ABBR-TRIGGERS); the command-position gate inside keeps it correct.
    if (ch == ' ' .or. ch == ';' .or. ch == '|' .or. ch == '&' .or. &
        ch == '>' .or. ch == '<' .or. ch == ')') then
      call try_expand_abbreviation_at_cursor(input_state)
    end if

    ! AR-11 PAIRS: decide about auto-closing BEFORE the opener goes in — the
    ! guards read the quote context and the character at the cursor, both of
    ! which the insertion itself changes (typing '"' flips PLAIN to DQ). Run it
    ! after the abbreviation expansion above, which can move the cursor.
    ap_do_close = autopair_should_close(input_state, ch)
    ap_closer = autopair_closer_for(ch)

    ! If cursor is at end, simple append
    if (input_state%cursor_pos >= input_state%length) then
      input_state%length = input_state%length + 1
      call state_buffer_set_char(input_state, input_state%length, ch)
      input_state%cursor_pos = input_state%length

      ! Update screen cursor position tracking
      call get_terminal_size_from_env(term_cols)
      module_cursor_screen_col = module_cursor_screen_col + 1

      ! Handle line wrapping - if we just filled the last column, wrap to next line
      if (module_cursor_screen_col >= term_cols) then
        ! Line wrap: write char + CR+LF directly since no dirty redraw follows
        write(output_unit, '(a)', advance='no') ch
        write(output_unit, '(a)', advance='no') char(13) // char(10)  ! CR+LF
        flush(output_unit)
        module_cursor_screen_col = 0
        module_cursor_screen_row = module_cursor_screen_row + 1
        ! Don't trigger redraw - character already on screen, cursor already positioned correctly
        ! Redraw would move cursor back up to row 0, causing snap-back
      else if (test_mode_enabled) then
        ! Test mode skips the dirty redraw entirely, so we must echo the
        ! character directly here — it's the only output path.
        write(output_unit, '(a)', advance='no') ch
        flush(output_unit)
      else
        ! Normal mode: skip direct character output — the dirty redraw will
        ! draw it with syntax highlighting. Writing + flushing the plain char
        ! here then clearing + redrawing causes visible flashing (clear is
        ! rendered as a blank frame before the redraw content arrives).
        input_state%dirty = .true.
      end if
    else
      ! Insert in middle - use temp to avoid substring overlap issues
      ! Allocate the right-shift scratch only here, where it is actually used.
      allocate(character(len=MAX_LINE_LEN) :: temp_buffer)
      ! Initialize temp with current buffer
      call state_buffer_get(input_state, temp_buffer)

      ! Shift part after cursor one position right in temp
      if (input_state%cursor_pos < input_state%length) then
        temp_buffer(input_state%cursor_pos+2:input_state%length+1) = &
          temp_buffer(input_state%cursor_pos+1:input_state%length)
      end if

      ! Insert new character at cursor+1
      temp_buffer(input_state%cursor_pos+1:input_state%cursor_pos+1) = ch

      ! Copy result back to buffer
      call state_buffer_set(input_state, temp_buffer)
      input_state%length = input_state%length + 1
      input_state%cursor_pos = input_state%cursor_pos + 1

      ! Middle insertion requires full redraw
      input_state%dirty = .true.
    end if

    ! Deallocate heap-allocated temp buffer
    if (allocated(temp_buffer)) deallocate(temp_buffer)

    ! AR-11 PAIRS: keep any pending closers pointing at the right bytes (the
    ! insert above shifted everything from the cursor rightward), and mark the
    ! keystroke as one that MAINTAINS the stack, so the input loop's
    ! post-dispatch sweep leaves it alone.
    call autopair_note_insert(input_state%cursor_pos)
    ap_keep_this_key = .true.

    ! Auto-close: drop the closer in at the cursor without advancing it.
    if (ap_do_close) then
      call autopair_insert_closer(input_state, ap_closer, ap_ok)
      if (ap_ok) then
        ! The cursor now sits mid-buffer, so the fast append/wrap paths above
        ! no longer describe the screen — force the full redraw.
        !
        ! Nothing is echoed for test mode here on purpose. Test mode has no
        ! redraw and echoes only the APPEND path, so every mid-buffer edit is
        ! already silent there; emitting the closer plus a BS would draw a
        ! glyph that the next keystroke visually overwrites, which is worse
        ! than staying quiet. Test-mode specs assert on executed output, and
        ! the buffer itself is correct either way.
        input_state%dirty = .true.
      end if
    end if

    ! Update autosuggestion after inserting character
    call update_autosuggestion(input_state)

    ! If autosuggestion was generated, we need to redraw to show it
    if (input_state%cursor_pos == input_state%length .and. input_state%suggestion_length > 0) then
      input_state%dirty = .true.
    end if
  end subroutine

  subroutine handle_history_up(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: history_line
    logical :: found

    ! History navigation replaces the buffer wholesale — selection byte
    ! offsets from the old buffer would point into stale data (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

    ! If there's text on the line and we're not yet in any history mode,
    ! enter prefix search mode (fish-style)
    if (.not. input_state%in_history .and. .not. input_state%in_prefix_search &
        .and. input_state%length > 0) then
      call state_buffer_save(input_state)
      ! Freeze the prefix
      input_state%prefix_search_len = input_state%length
      input_state%prefix_search_text = ''
      call state_buffer_get(input_state, input_state%prefix_search_text)
      input_state%in_prefix_search = .true.
      input_state%prefix_search_idx = 0  ! 0 = at present
      ! Clear shadow text — prefix search replaces it
      input_state%suggestion_length = 0
      input_state%suggestion = ''
    end if

    ! Prefix search: find previous match
    if (input_state%in_prefix_search) then
      call prefix_search_move(input_state, -1)
      return
    end if

    ! Standard history navigation (empty line)
    if (.not. input_state%in_history) then
      call state_buffer_save(input_state)
      input_state%history_pos = command_history%count + 1
      input_state%in_history = .true.
    end if

    if (input_state%history_pos > 1) then
      input_state%history_pos = input_state%history_pos - 1
      call get_history_line(input_state%history_pos, history_line, found)
      if (found) then
        call state_buffer_set(input_state, history_line)
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

    ! Buffer replacement — clear any stale selection (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

    ! Prefix search: find next match or return to present
    if (input_state%in_prefix_search) then
      call prefix_search_move(input_state, +1)
      return
    end if

    ! Only navigate down if we're currently in history
    if (.not. input_state%in_history) return

    ! Move down in history
    if (input_state%history_pos < command_history%count) then
      input_state%history_pos = input_state%history_pos + 1
      call get_history_line(input_state%history_pos, history_line, found)

      if (found) then
        call state_buffer_set(input_state, history_line)
        input_state%length = len_trim(history_line)
        input_state%cursor_pos = input_state%length
        input_state%dirty = .true.
      end if
    else if (input_state%history_pos <= command_history%count) then
      ! Reached the end of history, restore original input
      call state_buffer_restore(input_state)
#ifdef USE_C_STRINGS
      input_state%length = c_string_length(input_state%original_buffer_c)
#elif defined(USE_MEMORY_POOL)
      input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
      input_state%length = len_trim(input_state%original_buffer)
#endif
      input_state%cursor_pos = input_state%length
      input_state%history_pos = command_history%count + 1
      input_state%in_history = .false.
      input_state%dirty = .true.
    end if
  end subroutine

  ! --------------------------------------------------------------------------
  ! Prefix history search: find next/previous history entry matching prefix.
  ! direction: -1 = backward (older), +1 = forward (newer)
  ! --------------------------------------------------------------------------
  subroutine prefix_search_move(input_state, direction)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: direction

    character(len=MAX_LINE_LEN) :: history_line
    integer :: i, start_idx, hist_len, j
    logical :: matches, found

    if (command_history%count == 0) return

    ! Search backward (older entries)
    if (direction < 0) then
      ! Determine starting point
      if (input_state%prefix_search_idx == 0) then
        ! At present — start from most recent
        start_idx = command_history%count
      else
        start_idx = input_state%prefix_search_idx - 1
      end if

      do i = start_idx, 1, -1
        call get_history_line(i, history_line, found)
        if (.not. found) cycle
        hist_len = len_trim(history_line)
        if (hist_len <= input_state%prefix_search_len) cycle

        ! Check prefix match character-by-character
        matches = .true.
        do j = 1, input_state%prefix_search_len
          if (history_line(j:j) /= input_state%prefix_search_text(j:j)) then
            matches = .false.
            exit
          end if
        end do

        if (matches) then
          input_state%prefix_search_idx = i
          call state_buffer_set(input_state, history_line)
          input_state%length = hist_len
          input_state%cursor_pos = input_state%length
          input_state%suggestion_length = 0
          input_state%suggestion = ''
          input_state%dirty = .true.
          return
        end if
      end do
      ! No match found — flash reverse video to indicate no match
      input_state%prefix_search_flash = .true.
      input_state%dirty = .true.

    else
      ! Search forward (newer entries)
      if (input_state%prefix_search_idx == 0) return  ! Already at present

      start_idx = input_state%prefix_search_idx + 1

      do i = start_idx, command_history%count
        call get_history_line(i, history_line, found)
        if (.not. found) cycle
        hist_len = len_trim(history_line)
        if (hist_len <= input_state%prefix_search_len) cycle

        matches = .true.
        do j = 1, input_state%prefix_search_len
          if (history_line(j:j) /= input_state%prefix_search_text(j:j)) then
            matches = .false.
            exit
          end if
        end do

        if (matches) then
          input_state%prefix_search_idx = i
          call state_buffer_set(input_state, history_line)
          input_state%length = hist_len
          input_state%cursor_pos = input_state%length
          input_state%suggestion_length = 0
          input_state%suggestion = ''
          input_state%dirty = .true.
          return
        end if
      end do

      ! No more forward matches — return to present (original text)
      call state_buffer_restore(input_state)
      input_state%length = input_state%prefix_search_len
      input_state%cursor_pos = input_state%length
      input_state%prefix_search_idx = 0
      input_state%dirty = .true.
      call update_autosuggestion(input_state)
    end if
  end subroutine

  subroutine handle_yank(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, insert_len

    ! Shift-phase (Sprint 3): yanking into an active selection first
    ! deletes the selection, then pastes the kill buffer at the cursor.
    ! This gives the natural "paste over" behavior. Selection is collapsed
    ! by delete_selection before the existing yank logic runs.
    if (input_state%selection_active) call delete_selection(input_state)

    ! Yank the ring head (slot 1).
    if (kill_ring_count == 0 .or. kill_ring_len(1) == 0) return

    insert_len = min(kill_ring_len(1), MAX_LINE_LEN - input_state%length)
    if (insert_len <= 0) return

    ! Shift existing text right to make room
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
      end if
    end do

    do i = 1, insert_len
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, kill_ring(1)(i:i))
    end do

    ! Record the inserted span so a following Alt-y (yank-pop) can replace it.
    last_yank_start = input_state%cursor_pos
    last_yank_len = insert_len
    kill_yank_index = 1
    yank_op_this_key = .true.

    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
  end subroutine

  ! Try to expand an abbreviation at cursor position (called when space is typed)
  subroutine try_expand_abbreviation_at_cursor(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=:), allocatable :: word_before_cursor  ! Heap allocation to avoid stack overflow
    character(len=:), allocatable :: expanded_form
    integer :: word_start, word_end, i, expanded_len
    character(len=MAX_LINE_LEN) :: temp_buf


    ! Allocate buffer on heap
    allocate(character(len=MAX_LINE_LEN) :: word_before_cursor)

    ! Extract word before cursor
    word_end = input_state%cursor_pos
    word_start = word_end

    ! Find start of word (go backwards until space or beginning)
    do while (word_start > 0)
      if (state_buffer_get_char(input_state, word_start) == ' ') then
        word_start = word_start + 1
        exit
      end if
      word_start = word_start - 1
    end do

    if (word_start == 0) word_start = 1

    ! Extract the word
    if (word_end > word_start) then
      call state_buffer_get(input_state, temp_buf)
      word_before_cursor = temp_buf(word_start:word_end)
    else
      if (allocated(word_before_cursor)) deallocate(word_before_cursor)
      return  ! No word to expand
    end if

    ! AR-07 ABBR-POSITION: expand only at command position — the word is the
    ! command (start of line, or the first word after a command separator).
    ! An abbreviation in argument position (e.g. `echo gco`) stays literal,
    ! matching fish's default Position::Command.
    block
      integer :: p
      character :: pc
      logical :: cmd_pos
      p = word_start - 1
      do while (p > 0)
        pc = state_buffer_get_char(input_state, p)
        if (pc /= ' ' .and. pc /= char(9)) exit
        p = p - 1
      end do
      if (p <= 0) then
        cmd_pos = .true.
      else
        pc = state_buffer_get_char(input_state, p)
        cmd_pos = (pc == ';' .or. pc == '|' .or. pc == '&' .or. &
                   pc == '(' .or. pc == '{' .or. pc == char(10))
      end if
      if (.not. cmd_pos) then
        if (allocated(word_before_cursor)) deallocate(word_before_cursor)
        return
      end if
    end block

    ! Check if it's an abbreviation
    expanded_form = try_expand_abbreviation(trim(word_before_cursor))
    if (len(expanded_form) == 0) then
      if (allocated(word_before_cursor)) deallocate(word_before_cursor)
      return  ! Not an abbreviation
    end if

    ! Replace the word with expanded form
    expanded_len = len(expanded_form)

    ! First, remove the original word by shifting left
    do i = word_end + 1, input_state%length
      call state_buffer_set_char(input_state, word_start + i - word_end - 1, state_buffer_get_char(input_state, i))
    end do
    input_state%length = input_state%length - (word_end - word_start + 1)
    input_state%cursor_pos = word_start - 1

    ! Then insert the expanded form
    ! Make room for expanded text
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + expanded_len <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, i + expanded_len, state_buffer_get_char(input_state, i))
      end if
    end do

    ! Insert expanded text
    do i = 1, expanded_len
      if (input_state%cursor_pos + i <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, input_state%cursor_pos + i, expanded_form(i:i))
      end if
    end do

    input_state%length = input_state%length + expanded_len
    input_state%cursor_pos = input_state%cursor_pos + expanded_len
    input_state%dirty = .true.

    ! Deallocate heap buffer
    if (allocated(word_before_cursor)) deallocate(word_before_cursor)
  end subroutine try_expand_abbreviation_at_cursor

  ! Update autosuggestion based on current input
  ! Try to suggest path completion (fish-style lookahead)
  subroutine try_path_suggestion(current_input, input_state)
    character(len=*), intent(in) :: current_input
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: last_word
    character(len=MAX_LINE_LEN) :: completions(MAX_LOCAL_COMPLETIONS)
    integer :: num_completions, last_space_pos, i, input_len, last_word_len
    type(suggestion_result_t) :: path_result
    ! Memoize: skip dir scan if the last word hasn't changed
    character(len=MAX_LINE_LEN), save :: prev_last_word = ''
    integer, save :: prev_last_word_len = 0
    character(len=MAX_LINE_LEN), save :: prev_completions(MAX_LOCAL_COMPLETIONS)
    integer, save :: prev_num_completions = 0

    ! Clear any existing suggestion
    input_state%suggestion = ''
    input_state%suggestion_length = 0
    input_state%suggestion_replace_len = 0

    ! SAFETY (AR-01): a trailing space means the user FINISHED the current
    ! token. We must NOT keep suggesting a path completion for the PREVIOUS
    ! token — len_trim() below would silently drop the space and re-suggest
    ! e.g. a "/" for a just-completed directory. That stale "/" ghost renders
    ! after the space and, if accepted, becomes a SEPARATE argument:
    ! `rm -rf /path/dir ` -> `rm -rf /path/dir /`  (deletes /). Bail here so a
    ! finished token carries no path suggestion. (History suggestions, handled
    ! before this is called, already match the full line incl. the space.)
    if (len(current_input) >= 1) then
      if (current_input(len(current_input):len(current_input)) == ' ' .or. &
          current_input(len(current_input):len(current_input)) == char(9)) then
        return
      end if
    end if

    input_len = len_trim(current_input)
    if (input_len == 0) return

    ! Find the last word (what user is currently typing)
    last_space_pos = 0
    do i = input_len, 1, -1
      if (current_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do

    if (last_space_pos > 0) then
      last_word = trim(current_input(last_space_pos+1:))
    else
      last_word = trim(current_input)
    end if

    last_word_len = len_trim(last_word)
    if (last_word_len == 0) return

    ! Reuse cached completions if the last word is unchanged
    if (last_word_len == prev_last_word_len .and. &
        last_word(1:last_word_len) == prev_last_word(1:prev_last_word_len)) then
      num_completions = prev_num_completions
      completions = prev_completions
    else
      call complete_files_enhanced(last_word(1:last_word_len), completions, num_completions)
      prev_last_word = last_word
      prev_last_word_len = last_word_len
      prev_completions = completions
      prev_num_completions = num_completions
    end if

    ! Delegate suggestion selection to the suggestions module
    path_result = compute_path_suggestion(last_word, last_word_len, completions, num_completions)

    if (path_result%source /= SUGGEST_NONE) then
      ! Copy result into input_state character-by-character for flang-new safety
      input_state%suggestion = ''
      do i = 1, path_result%length
        input_state%suggestion(i:i) = path_result%text(i:i)
      end do
      input_state%suggestion_length = path_result%length
      ! AR-04b: carry the corrected typed prefix for an icase match.
      input_state%suggestion_replace_len = path_result%replace_len
      if (path_result%replace_len > 0) then
        input_state%suggestion_replace_text = ''
        do i = 1, min(path_result%replace_len, MAX_LINE_LEN)
          input_state%suggestion_replace_text(i:i) = path_result%replace_text(i:i)
        end do
      end if
    end if
  end subroutine try_path_suggestion

  subroutine update_autosuggestion(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: j, search_max
    ! CRITICAL: Use fixed-length (NOT deferred-length) for flang-new compatibility
    character(len=MAX_LINE_LEN), allocatable :: current_input
    type(suggestion_result_t) :: hist_result

    ! AR-04b: default to plain-append accept; only the icase path branch in
    ! try_path_suggestion sets a recase. History suggestions never recase.
    input_state%suggestion_replace_len = 0

    ! Disable autosuggestion in test mode - prevents output pollution
    if (.not. test_mode_initialized) call init_test_mode()
    if (test_mode_enabled) then
      input_state%suggestion = ''
      input_state%suggestion_length = 0
      return
    end if

    ! Allocate buffer on heap
    allocate(current_input)
    current_input = ''

    ! Defensive check: ensure length and cursor_pos are valid
    if (input_state%length < 0 .or. input_state%length > MAX_LINE_LEN) then
      input_state%length = 0
      input_state%cursor_pos = 0
      input_state%suggestion = ''
      input_state%suggestion_length = 0
      if (allocated(current_input)) deallocate(current_input)
      return
    end if

    ! Clear suggestion if buffer is empty or in special modes
    if (input_state%length == 0 .or. input_state%in_search .or. input_state%in_history &
        .or. input_state%in_prefix_search) then
      input_state%suggestion = ''
      input_state%suggestion_length = 0
      if (allocated(current_input)) deallocate(current_input)
      return
    end if

    ! Get current input - copy character-by-character (avoid substring on allocatable)
    current_input = ''
    do j = 1, input_state%length
      current_input(j:j) = state_buffer_get_char(input_state, j)
    end do

    ! Priority 1: history-based suggestion (fish-style: history first).
    ! AS-7: a history entry that is `cd`/`pushd` into a now-missing directory
    ! is rejected (mirrors fish autosuggest_validate_from_history); keep
    ! searching older entries via max_index until a valid match or none.
    if (command_history%count > 0 .and. allocated(command_history%lines)) then
      search_max = command_history%count
      do
        hist_result = compute_history_suggestion( &
          current_input, input_state%length, &
          command_history%lines, command_history%count, search_max)

        if (hist_result%source == SUGGEST_NONE) exit

        if (history_suggestion_valid(current_input(1:input_state%length), &
                                     hist_result%text(1:hist_result%length))) then
          input_state%suggestion = ''
          do j = 1, hist_result%length
            input_state%suggestion(j:j) = hist_result%text(j:j)
          end do
          input_state%suggestion_length = hist_result%length
          if (allocated(current_input)) deallocate(current_input)
          return
        end if

        ! Rejected — search entries older than this match.
        if (hist_result%matched_index <= 1) exit
        search_max = hist_result%matched_index - 1
      end do
    end if

    ! Priority 2: path-based suggestion (fallback when no history match)
    call try_path_suggestion(current_input(1:input_state%length), input_state)

    if (allocated(current_input)) deallocate(current_input)
  end subroutine

  ! Get terminal columns from environment variable
  subroutine get_terminal_size_from_env(term_cols)
    integer, intent(out) :: term_cols
    character(len=16) :: cols_str
    integer :: stat, iostat_val

    call get_environment_variable('COLUMNS', cols_str, status=stat)
    if (stat == 0 .and. len_trim(cols_str) > 0) then
      read(cols_str, *, iostat=iostat_val) term_cols
      if (iostat_val /= 0 .or. term_cols <= 0) then
        term_cols = 80  ! Fallback
      end if
    else
      term_cols = 80  ! Fallback
    end if
  end subroutine
  ! Character class for fish-style punctuation-aware word motion (DIV-3):
  ! 0 = whitespace, 1 = word char (alnum + '_'), 2 = punctuation (other).
  ! A "small word" is a maximal run of a single non-space class, so a
  ! punctuation run (e.g. "@", "://") is its own word, matching fish.
  pure integer function char_class(c)
    character, intent(in) :: c
    integer :: ic
    ic = iachar(c)
    if (c == ' ' .or. c == char(9)) then
      char_class = 0
    else if ((ic >= iachar('0') .and. ic <= iachar('9')) .or. &
             (ic >= iachar('A') .and. ic <= iachar('Z')) .or. &
             (ic >= iachar('a') .and. ic <= iachar('z')) .or. &
             c == '_') then
      char_class = 1
    else
      char_class = 2
    end if
  end function char_class

  ! AS-7: a history suggestion is invalid only when we are confident its command
  ! is `cd`/`pushd` into a LITERAL path that no longer exists (mirrors fish
  ! autosuggest_validate_from_history). Anything ambiguous — globs, $vars,
  ! command substitution, quoted or multi-token args, options, ~user — is
  ! treated as valid so a genuine suggestion is never hidden.
  logical function history_suggestion_valid(typed, remainder)
    character(len=*), intent(in) :: typed, remainder
    character(len=MAX_LINE_LEN) :: full, arg, expanded
    character(len=:), allocatable :: home
    integer :: n, p, cmd_start, cmd_end, arg_start, i

    history_suggestion_valid = .true.

    ! Reconstruct the full command. Do NOT trim `typed` — its trailing space
    ! (e.g. "cd ") is the separator before the suggested path.
    full = typed // remainder
    n = len_trim(full)
    if (n == 0) return

    ! Command word = first whitespace-delimited token.
    p = 1
    do while (p <= n .and. (full(p:p) == ' ' .or. full(p:p) == char(9)))
      p = p + 1
    end do
    cmd_start = p
    do while (p <= n .and. full(p:p) /= ' ' .and. full(p:p) /= char(9))
      p = p + 1
    end do
    cmd_end = p - 1
    if (cmd_end < cmd_start) return
    if (.not. (full(cmd_start:cmd_end) == 'cd' .or. &
               full(cmd_start:cmd_end) == 'pushd')) return

    ! Argument = the rest of the line.
    do while (p <= n .and. (full(p:p) == ' ' .or. full(p:p) == char(9)))
      p = p + 1
    end do
    arg_start = p
    if (n < arg_start) return                 ! no arg -> HOME, valid
    if (full(arg_start:arg_start) == '-') return  ! cd - / options, valid

    ! Ambiguous tokens -> skip validation (treat as valid).
    do i = arg_start, n
      select case (full(i:i))
      case ('$', '`', '*', '?', '[', '"', "'", ' ', char(9))
        return
      end select
    end do

    arg = full(arg_start:n)

    ! Expand a leading ~ (but not ~user, which we can't resolve here).
    if (arg(1:1) == '~') then
      home = get_environment_var('HOME')
      if (.not. allocated(home)) return
      if (len_trim(arg) == 1) then
        expanded = trim(home)
      else if (arg(2:2) == '/') then
        expanded = trim(home) // trim(arg(2:))
      else
        return
      end if
    else
      expanded = arg
    end if

    if (.not. file_is_directory(trim(expanded))) history_suggestion_valid = .false.
  end function history_suggestion_valid

end module readline_editops
