! ==============================================================================
! Module: readline_vi
! Purpose: vi editing mode (QUAL-13) - command/visual mode dispatch, motions,
!          text objects, dot-repeat, delete/yank/change-with-motion, marks,
!          and vi search. Sits above readline_editops: vi handlers mutate the
!          buffer through the editing-engine primitives and buffer accessors;
!          the readline loop redraws after the handler returns. Re-exported by
!          readline, so use-readline consumers are unchanged.
! ==============================================================================
module readline_vi
  use readline_constants
  use readline_state
  use readline_bufferops
  use readline_editops
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding
  implicit none

contains

  subroutine handle_vi_mode_switch(input_state, key)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    
    if (input_state%editing_mode /= EDITING_MODE_VI) return
    
    select case (input_state%vi_mode)
    case (VI_MODE_INSERT)
      if (key == KEY_ESC) then
        input_state%vi_mode = VI_MODE_COMMAND
        dot_recording_insert = .false.   ! AR-05b 2b: finalize captured insert
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

  ! Read / set the pending vi command buffer through the storage-variant ifdefs
  ! in one place (USE_C_STRINGS / USE_MEMORY_POOL / plain).
  function vi_get_cmd_buffer(input_state) result(s)
    type(input_state_t), intent(in) :: input_state
    character(len=8) :: s
#ifdef USE_C_STRINGS
    s = input_state%vi_command_buffer
#elif defined(USE_MEMORY_POOL)
    s = input_state%vi_command_buffer_ref%data
#else
    s = input_state%vi_command_buffer
#endif
  end function

  subroutine vi_set_cmd_buffer(input_state, s)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: s
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = s
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = s
#else
    input_state%vi_command_buffer = s
#endif
  end subroutine

  subroutine handle_vi_command_mode(input_state, key)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    character :: key_char
    integer :: repeat_count, i, vlen
    character(len=8) :: vbuf

    if (input_state%editing_mode /= EDITING_MODE_VI .or. input_state%vi_mode /= VI_MODE_COMMAND) return

    key_char = char(key)
    vbuf = vi_get_cmd_buffer(input_state)
    vlen = len_trim(vbuf)

    ! Text object pending (operator + i/a already buffered): this key is the
    ! object type — resolve and apply (AR-05b stage 3).
    if (vlen >= 2 .and. (vbuf(2:2) == 'i' .or. vbuf(2:2) == 'a')) then
      call vi_apply_text_object(input_state, vbuf(1:1), vbuf(2:2), key_char)
      call vi_set_cmd_buffer(input_state, '')
      input_state%vi_command_count = 0
      return
    end if

    ! Operator pending and this key is a text-object prefix (i/a, which are not
    ! motions): buffer "<op>i" / "<op>a" and wait for the object char.
    if (vlen == 1 .and. (key_char == 'i' .or. key_char == 'a') .and. &
        (vbuf(1:1) == 'd' .or. vbuf(1:1) == 'c' .or. vbuf(1:1) == 'y')) then
      call vi_set_cmd_buffer(input_state, vbuf(1:1) // key_char)
      return
    end if

    ! Handle pending two-character commands first
    if (vlen > 0) then
      select case (vbuf(1:1))
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
        if (.not. dot_replaying) then
          dot_kind = DOTK_MOTION; dot_key = 'd'; dot_motion = key_char
          dot_count = max(1, input_state%vi_command_count)
        end if
        call handle_vi_delete_with_motion(input_state, key_char)
        return
      case ('y')
        ! Yank with motion
        call handle_vi_yank_with_motion(input_state, key_char)
        return
      case ('c')
        ! Change with motion
        call dot_begin_insert('c', key_char, max(1, input_state%vi_command_count))
        call handle_vi_change_with_motion(input_state, key_char)
        return
      case ('r')
        ! Replace character
        if (.not. dot_replaying) then
          dot_kind = DOTK_REPLACE; dot_char = key_char
          dot_count = max(1, input_state%vi_command_count)
        end if
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

    ! Visual mode (AR-05b)
    case (ichar('v'))
      ! Charwise visual: anchor at the cursor, then motions extend the region.
      input_state%selection_anchor = input_state%cursor_pos
      input_state%selection_active = .true.
      input_state%vi_visual_linewise = .false.
      input_state%vi_mode = VI_MODE_VISUAL
      input_state%dirty = .true.
    case (ichar('V'))
      ! Linewise visual: select the whole line (single-line prompt).
      input_state%selection_anchor = 0
      input_state%cursor_pos = max(input_state%length - 1, 0)
      input_state%selection_active = .true.
      input_state%vi_visual_linewise = .true.
      input_state%vi_mode = VI_MODE_VISUAL
      input_state%dirty = .true.

    ! Dot-repeat: replay the last buffer-changing command (AR-05b)
    case (ichar('.'))
      call vi_dot_repeat(input_state)

    ! Deletion (with repeat)
    case (ichar('x'))
      ! Delete character at cursor
      do i = 1, repeat_count
        call delete_char_at_cursor(input_state)
      end do
      if (.not. dot_replaying) then
        dot_kind = DOTK_SIMPLE; dot_key = 'x'; dot_count = repeat_count
      end if
    case (ichar('X'))
      ! Delete character before cursor
      do i = 1, repeat_count
        if (input_state%cursor_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos - 1
          call delete_char_at_cursor(input_state)
        end if
      end do
      if (.not. dot_replaying) then
        dot_kind = DOTK_SIMPLE; dot_key = 'X'; dot_count = repeat_count
      end if
    case (ichar('d'))
      ! Delete with motion - set up for next character
#ifdef USE_C_STRINGS
      input_state%vi_command_buffer = 'd'
#elif defined(USE_MEMORY_POOL)
      input_state%vi_command_buffer_ref%data = 'd'
#else
      input_state%vi_command_buffer = 'd'
#endif
      input_state%vi_command_count = repeat_count

    ! Change (with repeat)
    case (ichar('c'))
      ! Change with motion - set up for next character
#ifdef USE_C_STRINGS
      input_state%vi_command_buffer = 'c'
#elif defined(USE_MEMORY_POOL)
      input_state%vi_command_buffer_ref%data = 'c'
#else
      input_state%vi_command_buffer = 'c'
#endif
      input_state%vi_command_count = repeat_count
    case (ichar('C'))
      ! Change to end of line
      call dot_begin_insert('C', ' ', 1)
      call handle_vi_change_to_eol(input_state)

    ! Undo
    case (ichar('u'))
      ! Undo (simplified)
      call state_buffer_restore(input_state)
#ifdef USE_C_STRINGS
      input_state%length = c_string_length(input_state%original_buffer_c)
#elif defined(USE_MEMORY_POOL)
      input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
      input_state%length = len_trim(input_state%original_buffer)
#endif
      input_state%cursor_pos = min(input_state%cursor_pos, input_state%length)
      input_state%dirty = .true.

    ! Yank and Put (vi-style copy/paste)
    case (ichar('y'))
      ! Yank with motion - set up for next character
#ifdef USE_C_STRINGS
      input_state%vi_command_buffer = 'y'
#elif defined(USE_MEMORY_POOL)
      input_state%vi_command_buffer_ref%data = 'y'
#else
      input_state%vi_command_buffer = 'y'
#endif
      input_state%vi_command_count = repeat_count
    case (ichar('p'))
      ! Put (paste) after cursor
      do i = 1, repeat_count
        call handle_vi_put(input_state, .false.)
      end do
      if (.not. dot_replaying) then
        dot_kind = DOTK_SIMPLE; dot_key = 'p'; dot_count = repeat_count
      end if
    case (ichar('P'))
      ! Put (paste) before cursor
      do i = 1, repeat_count
        call handle_vi_put(input_state, .true.)
      end do
      if (.not. dot_replaying) then
        dot_kind = DOTK_SIMPLE; dot_key = 'P'; dot_count = repeat_count
      end if

    ! Replace
    case (ichar('r'))
      ! Replace character - wait for next character
#ifdef USE_C_STRINGS
      input_state%vi_command_buffer = 'r'
#elif defined(USE_MEMORY_POOL)
      input_state%vi_command_buffer_ref%data = 'r'
#else
      input_state%vi_command_buffer = 'r'
#endif
      input_state%vi_command_count = repeat_count
    case (ichar('R'))
      ! Replace mode - enter insert mode with replace behavior
      input_state%vi_mode = VI_MODE_INSERT
      ! TODO: Add replace mode flag for overwrite behavior

    ! Marks
    case (ichar('m'))
      ! Set mark - next character will be the mark name
#ifdef USE_C_STRINGS
      input_state%vi_command_buffer = 'm'
#elif defined(USE_MEMORY_POOL)
      input_state%vi_command_buffer_ref%data = 'm'
#else
      input_state%vi_command_buffer = 'm'
#endif
      input_state%vi_command_count = 1
    case (ichar("'"))
      ! Jump to mark - next character will be the mark name
#ifdef USE_C_STRINGS
      input_state%vi_command_buffer = "'"
#elif defined(USE_MEMORY_POOL)
      input_state%vi_command_buffer_ref%data = "'"
#else
      input_state%vi_command_buffer = "'"
#endif
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

    ! Mode switches (with proper cursor positioning). Each begins recording the
    ! typed insert for dot-repeat (AR-05b 2b).
    case (ichar('i'))
      ! Insert at cursor
      input_state%vi_mode = VI_MODE_INSERT
      call dot_begin_insert('i', ' ', 1)
    case (ichar('a'))
      ! Insert after cursor
      if (input_state%cursor_pos < input_state%length) then
        input_state%cursor_pos = input_state%cursor_pos + 1
      end if
      input_state%vi_mode = VI_MODE_INSERT
      call dot_begin_insert('a', ' ', 1)
    case (ichar('I'))
      ! Insert at beginning of line
      input_state%cursor_pos = 0
      input_state%vi_mode = VI_MODE_INSERT
      call dot_begin_insert('I', ' ', 1)
    case (ichar('A'))
      ! Insert at end of line
      input_state%cursor_pos = input_state%length
      input_state%vi_mode = VI_MODE_INSERT
      call dot_begin_insert('A', ' ', 1)
    case (ichar('o'))
      ! Open line below (simplified - just go to end)
      input_state%cursor_pos = input_state%length
      input_state%vi_mode = VI_MODE_INSERT
      call dot_begin_insert('o', ' ', 1)
    case (ichar('O'))
      ! Open line above (simplified - just go to beginning)
      input_state%cursor_pos = 0
      input_state%vi_mode = VI_MODE_INSERT
      call dot_begin_insert('O', ' ', 1)
    end select
  end subroutine

  ! Vi visual mode (AR-05b): motions extend the selection anchored by v/V;
  ! d/x/c/s/y operate on the inclusive selection then leave visual mode. The
  ! shared selection_active/anchor machinery drives the highlight; the operative
  ! range is made inclusive of the char under the cursor to match vi.
  subroutine handle_vi_visual_mode(input_state, key)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    integer :: vs, start_pos, end_pos

    if (input_state%editing_mode /= EDITING_MODE_VI .or. &
        input_state%vi_mode /= VI_MODE_VISUAL) return

    select case (key)
    ! Motions — move the cursor; the selection follows (anchor stays fixed).
    case (ichar('h'))
      if (input_state%cursor_pos > 0) input_state%cursor_pos = input_state%cursor_pos - 1
      input_state%dirty = .true.
    case (ichar('l'))
      if (input_state%cursor_pos < input_state%length - 1) &
        input_state%cursor_pos = input_state%cursor_pos + 1
      input_state%dirty = .true.
    case (ichar('w'))
      call move_to_next_word(input_state)
    case (ichar('b'))
      call move_to_previous_word(input_state)
    case (ichar('e'))
      call move_to_word_end(input_state)
    case (ichar('0'))
      input_state%cursor_pos = 0
      input_state%dirty = .true.
    case (ichar('$'))
      input_state%cursor_pos = max(input_state%length - 1, 0)
      input_state%dirty = .true.

    ! Operators — act on the inclusive selection, then leave visual mode.
    case (ichar('d'), ichar('x'))
      call vi_visual_range(input_state, start_pos, end_pos)
      if (end_pos > start_pos) then
        call yank_range(input_state, start_pos, end_pos)
        call delete_range(input_state, start_pos, end_pos)
      end if
      call collapse_selection(input_state)
      input_state%vi_mode = VI_MODE_COMMAND
      if (input_state%cursor_pos > input_state%length - 1) &
        input_state%cursor_pos = max(input_state%length - 1, 0)
      input_state%dirty = .true.
    case (ichar('c'), ichar('s'))
      call vi_visual_range(input_state, start_pos, end_pos)
      if (end_pos > start_pos) then
        call yank_range(input_state, start_pos, end_pos)
        call delete_range(input_state, start_pos, end_pos)
      end if
      call collapse_selection(input_state)
      input_state%vi_mode = VI_MODE_INSERT
      input_state%dirty = .true.
    case (ichar('y'))
      call vi_visual_range(input_state, start_pos, end_pos)
      if (end_pos > start_pos) call yank_range(input_state, start_pos, end_pos)
      vs = start_pos - 1
      call collapse_selection(input_state)
      input_state%cursor_pos = max(0, min(vs, max(input_state%length - 1, 0)))
      input_state%vi_mode = VI_MODE_COMMAND
      input_state%dirty = .true.

    ! Leave visual mode with no change.
    case (KEY_ESC, ichar('v'))
      call collapse_selection(input_state)
      input_state%vi_mode = VI_MODE_COMMAND
      input_state%dirty = .true.
    end select
  end subroutine

  ! 1-based [start_pos, end_pos) range of the current visual selection,
  ! INCLUSIVE of the character under the cursor (vi semantics). Empty range
  ! (start_pos == end_pos) when the buffer is empty.
  subroutine vi_visual_range(input_state, start_pos, end_pos)
    type(input_state_t), intent(in) :: input_state
    integer, intent(out) :: start_pos, end_pos
    integer :: vs, ve

    start_pos = 1
    end_pos = 1
    if (input_state%length == 0) return

    if (input_state%vi_visual_linewise) then
      start_pos = 1
      end_pos = input_state%length + 1
      return
    end if

    vs = min(input_state%selection_anchor, input_state%cursor_pos)
    ve = max(input_state%selection_anchor, input_state%cursor_pos)
    if (vs < 0) vs = 0
    if (ve > input_state%length - 1) ve = input_state%length - 1
    if (vs > ve) return
    start_pos = vs + 1
    end_pos = ve + 2
  end subroutine

  ! Replay the last buffer-changing command (vi `.`). Sets dot_replaying so the
  ! replayed handlers don't re-record. (AR-05b stage 2.)
  subroutine vi_dot_repeat(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i

    if (dot_kind == DOTK_NONE) return
    dot_replaying = .true.

    select case (dot_kind)
    case (DOTK_SIMPLE)
      select case (dot_key)
      case ('x')
        do i = 1, dot_count
          call delete_char_at_cursor(input_state)
        end do
      case ('X')
        do i = 1, dot_count
          if (input_state%cursor_pos > 0) then
            input_state%cursor_pos = input_state%cursor_pos - 1
            call delete_char_at_cursor(input_state)
          end if
        end do
      case ('p')
        do i = 1, dot_count
          call handle_vi_put(input_state, .false.)
        end do
      case ('P')
        do i = 1, dot_count
          call handle_vi_put(input_state, .true.)
        end do
      end select
    case (DOTK_MOTION)
      input_state%vi_command_count = dot_count
      call handle_vi_delete_with_motion(input_state, dot_motion)
    case (DOTK_REPLACE)
      input_state%vi_command_count = dot_count
      call handle_vi_replace_char(input_state, dot_char)
    case (DOTK_INSERT)
      ! Re-establish the insert position / deletion, then re-type the captured
      ! text, then return to command mode (mimic ESC). Uses insert_char_impl so
      ! the replay isn't itself recorded.
      select case (dot_entry)
      case ('c')   ! c<motion>: delete the motion span (also sets INSERT)
        input_state%vi_command_count = dot_count
        call handle_vi_change_with_motion(input_state, dot_motion)
      case ('C')
        call handle_vi_change_to_eol(input_state)
      case ('a')
        if (input_state%cursor_pos < input_state%length) &
          input_state%cursor_pos = input_state%cursor_pos + 1
      case ('I')
        input_state%cursor_pos = 0
      case ('A', 'o')
        input_state%cursor_pos = input_state%length
      case ('O')
        input_state%cursor_pos = 0
      case default
        continue  ! 'i': insert at the current cursor
      end select
      do i = 1, dot_insert_len
        call insert_char_impl(input_state, dot_insert_buf(i:i))
      end do
      input_state%vi_mode = VI_MODE_COMMAND
      if (input_state%cursor_pos > 0) input_state%cursor_pos = input_state%cursor_pos - 1
    case (DOTK_TEXTOBJ)
      ! Re-resolve the object at the current cursor, apply the operator; for a
      ! change, re-type the captured text and return to command mode.
      call vi_apply_text_object(input_state, dot_to_op, dot_to_ia, dot_to_obj)
      if (dot_to_op == 'c') then
        do i = 1, dot_insert_len
          call insert_char_impl(input_state, dot_insert_buf(i:i))
        end do
        input_state%vi_mode = VI_MODE_COMMAND
        if (input_state%cursor_pos > 0) input_state%cursor_pos = input_state%cursor_pos - 1
      end if
    end select

    input_state%dirty = .true.
    dot_replaying = .false.
  end subroutine

  ! Apply a vi operator (d/c/y) to a text object (AR-05b stage 3). `ia` is 'i'
  ! (inner) or 'a' (around); `obj` selects the object (w " ' ` ( ) b { } B [ ]).
  subroutine vi_apply_text_object(input_state, op, ia, obj)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: op, ia, obj
    integer :: sp, ep
    logical :: ok

    call vi_text_object_range(input_state, ia == 'a', obj, sp, ep, ok)
    if (.not. ok) return

    select case (op)
    case ('y')
      call yank_range(input_state, sp, ep)
      input_state%cursor_pos = max(0, sp - 1)
    case ('d')
      call yank_range(input_state, sp, ep)
      call delete_range(input_state, sp, ep)
      if (.not. dot_replaying) then
        dot_kind = DOTK_TEXTOBJ; dot_to_op = 'd'; dot_to_ia = ia; dot_to_obj = obj
      end if
    case ('c')
      call yank_range(input_state, sp, ep)
      call delete_range(input_state, sp, ep)
      input_state%vi_mode = VI_MODE_INSERT
      if (.not. dot_replaying) then
        dot_kind = DOTK_TEXTOBJ; dot_to_op = 'c'; dot_to_ia = ia; dot_to_obj = obj
        dot_insert_len = 0; dot_recording_insert = .true.
      end if
    end select
    input_state%dirty = .true.
  end subroutine

  ! Resolve a text object to a 1-based [start_pos, end_pos) span around the
  ! cursor. `around` includes the delimiters (a") or trailing whitespace (aw).
  ! ok is .false. when no object is found or the inner span is empty.
  subroutine vi_text_object_range(input_state, around, obj, start_pos, end_pos, ok)
    type(input_state_t), intent(in) :: input_state
    logical, intent(in) :: around
    character, intent(in) :: obj
    integer, intent(out) :: start_pos, end_pos
    logical, intent(out) :: ok
    character(len=MAX_LINE_LEN) :: buf
    integer :: n, cur, s, e, cls, depth
    character :: oc, cc

    ok = .false.; start_pos = 1; end_pos = 1
    n = input_state%length
    if (n == 0) return
    call state_buffer_get(input_state, buf)
    cur = input_state%cursor_pos + 1
    if (cur < 1) cur = 1
    if (cur > n) cur = n

    select case (obj)
    case ('w')
      ! Span of the same character class around the cursor; aw adds trailing ws.
      cls = char_class(buf(cur:cur))
      s = cur
      do while (s > 1)
        if (char_class(buf(s-1:s-1)) /= cls) exit
        s = s - 1
      end do
      e = cur
      do while (e < n)
        if (char_class(buf(e+1:e+1)) /= cls) exit
        e = e + 1
      end do
      if (around) then
        do while (e < n)
          if (char_class(buf(e+1:e+1)) /= 0) exit
          e = e + 1
        end do
      end if
      start_pos = s; end_pos = e + 1; ok = .true.

    case ('"', "'", '`')
      ! Nearest matching pair of the same quote containing the cursor.
      if (buf(cur:cur) == obj) then
        s = cur
      else
        s = cur
        do while (s >= 1)
          if (buf(s:s) == obj) exit
          s = s - 1
        end do
      end if
      if (s < 1) return
      e = s + 1
      do while (e <= n)
        if (buf(e:e) == obj) exit
        e = e + 1
      end do
      if (e > n) return
      if (around) then
        start_pos = s; end_pos = e + 1
      else
        start_pos = s + 1; end_pos = e
      end if
      ok = .true.

    case ('(', ')', 'b', '{', '}', 'B', '[', ']')
      select case (obj)
      case ('(', ')', 'b'); oc = '('; cc = ')'
      case ('{', '}', 'B'); oc = '{'; cc = '}'
      case default;         oc = '['; cc = ']'
      end select
      ! Enclosing open bracket: scan left, balancing nested closers.
      depth = 0; s = cur
      do
        if (buf(s:s) == cc .and. s /= cur) then
          depth = depth + 1
        else if (buf(s:s) == oc) then
          if (depth == 0) exit
          depth = depth - 1
        end if
        s = s - 1
        if (s < 1) return
      end do
      ! Matching close: scan right, balancing nested openers.
      depth = 0; e = s + 1
      do
        if (e > n) return
        if (buf(e:e) == oc) then
          depth = depth + 1
        else if (buf(e:e) == cc) then
          if (depth == 0) exit
          depth = depth - 1
        end if
        e = e + 1
      end do
      if (around) then
        start_pos = s; end_pos = e + 1
      else
        start_pos = s + 1; end_pos = e
      end if
      ok = .true.

    case default
      return
    end select

    if (start_pos < 1) start_pos = 1
    if (end_pos > n + 1) end_pos = n + 1
    if (end_pos <= start_pos) ok = .false.
  end subroutine

  ! Motion-based delete command
  subroutine handle_vi_delete_with_motion(input_state, motion)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: motion
    integer :: start_pos, end_pos, delete_len, i, repeat_count
    character(len=MAX_LINE_LEN) :: temp_yank

    repeat_count = max(1, input_state%vi_command_count)

    select case (motion)
    case ('d')
      ! dd - delete entire line (yank into vi buffer first)
      call state_buffer_get(input_state, temp_yank)
      session_vi_yank = temp_yank(:input_state%length)
      input_state%vi_yank_length = input_state%length
      call state_buffer_clear(input_state)
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
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = ''
#else
    input_state%vi_command_buffer = ''
#endif
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
      call state_buffer_get(input_state, session_vi_yank)
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
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = ''
#else
    input_state%vi_command_buffer = ''
#endif
    input_state%vi_command_count = 0
  end subroutine

  ! Motion-based change command
  subroutine handle_vi_change_with_motion(input_state, motion)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: motion
    integer :: start_pos, end_pos, saved_cursor
    character(len=MAX_LINE_LEN) :: temp_yank

    if (motion == 'c') then
      ! cc - change entire line (yank into vi buffer first)
      call state_buffer_get(input_state, temp_yank)
      session_vi_yank = temp_yank(:input_state%length)
      input_state%vi_yank_length = input_state%length
      call state_buffer_clear(input_state)
      input_state%length = 0
      input_state%cursor_pos = 0
    else if (motion == 'w') then
      ! Vi quirk: 'cw' behaves like 'ce' (change to end of word, not to next word)
      start_pos = input_state%cursor_pos + 1
      saved_cursor = input_state%cursor_pos
      call move_to_word_end(input_state)
      end_pos = input_state%cursor_pos + 2
      call yank_range(input_state, start_pos, end_pos)
      call delete_range(input_state, start_pos, end_pos)
      input_state%cursor_pos = saved_cursor
    else
      ! For other motions, use standard delete + insert
      call handle_vi_delete_with_motion(input_state, motion)
    end if

    ! Clear the pending operator (cc/cw don't go through delete_with_motion,
    ! which is the only branch that cleared it) so the next command-mode key
    ! after the change isn't mis-read as another change motion.
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = ''
#else
    input_state%vi_command_buffer = ''
#endif
    input_state%vi_command_count = 0

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
        call state_buffer_set_char(input_state, input_state%cursor_pos+i, replace_char)
        input_state%dirty = .true.
      end if
    end do

    ! Clear command buffer
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = ''
#else
    input_state%vi_command_buffer = ''
#endif
    input_state%vi_command_count = 0
  end subroutine

  ! Vi-style yank (copy)
  subroutine handle_vi_yank(input_state)
    type(input_state_t), intent(inout) :: input_state

    ! Simplified: yank entire line (yy behavior)
    if (input_state%length > 0) then
      call state_buffer_get(input_state, session_vi_yank)
      input_state%vi_yank_length = input_state%length
    else
      session_vi_yank = ''
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

    ! Insert yanked text at insertion position. Go through the buffer
    ! accessors, NOT raw input_state%buffer(...) — under USE_MEMORY_POOL
    ! the plain allocatable is never allocated (storage is buffer_ref),
    ! so direct indexing segfaults. Mirrors handle_yank (Ctrl-Y).
#ifdef USE_C_STRINGS
    ! Use C string API for insertion
    if (.not. c_string_insert(input_state%buffer_c, insert_pos + 1, &
                               session_vi_yank(:insert_len))) then
      ! Insertion failed, silently ignore
      return
    end if
#else
    ! Shift existing text right to make room
    do i = input_state%length, insert_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
      end if
    end do

    ! Insert yanked text at insertion position
    do i = 1, insert_len
      call state_buffer_set_char(input_state, insert_pos + i, session_vi_yank(i:i))
    end do
#endif

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
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = ''
#else
    input_state%vi_command_buffer = ''
#endif
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
#ifdef USE_C_STRINGS
    input_state%vi_command_buffer = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_command_buffer_ref%data = ''
#else
    input_state%vi_command_buffer = ''
#endif
    input_state%vi_command_count = 0
  end subroutine

  ! Start vi-style search (/ or ?)
  subroutine handle_vi_search_start(input_state, forward)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(in) :: forward

    ! Enter vi search mode
    input_state%vi_in_vi_search = .true.
    input_state%vi_search_forward = forward
#ifdef USE_C_STRINGS
    input_state%vi_search_pattern = ''
#elif defined(USE_MEMORY_POOL)
    input_state%vi_search_pattern_ref%data = ''
#else
    input_state%vi_search_pattern = ''
#endif
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
    character(len=MAX_LINE_LEN) :: temp_buf

    if (input_state%vi_search_length == 0) return

    found = .false.

    ! Determine search direction based on original direction and forward flag
    if (input_state%vi_search_forward .eqv. forward) then
      ! Search in same direction as original
      if (input_state%vi_search_forward) then
        ! Search forward from current position
        call state_buffer_get(input_state, temp_buf)
        match_pos = index(temp_buf(input_state%cursor_pos+2:input_state%length), &
                         input_state%vi_search_pattern(:input_state%vi_search_length))
        if (match_pos > 0) then
          input_state%cursor_pos = input_state%cursor_pos + 1 + match_pos
          found = .true.
        end if
      else
        ! Search backward from current position
        ! Simplified: search from beginning to current position
        call state_buffer_get(input_state, temp_buf)
        do i = input_state%cursor_pos - 1, 1, -1
          match_pos = index(temp_buf(i:input_state%cursor_pos-1), &
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
        call state_buffer_get(input_state, temp_buf)
        do i = input_state%cursor_pos - 1, 1, -1
          match_pos = index(temp_buf(i:input_state%cursor_pos-1), &
                           input_state%vi_search_pattern(:input_state%vi_search_length))
          if (match_pos > 0) then
            input_state%cursor_pos = i + match_pos - 1
            found = .true.
            exit
          end if
        end do
      else
        ! Original was backward, now search forward
        call state_buffer_get(input_state, temp_buf)
        match_pos = index(temp_buf(input_state%cursor_pos+2:input_state%length), &
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
end module readline_vi
