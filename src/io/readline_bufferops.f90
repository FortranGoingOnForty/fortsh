! ==============================================================================
! Module: readline_bufferops
! Purpose: Platform-abstracted accessors for the live input buffer, kill ring,
!          search string, and last-completion buffer, plus insert_string_at_cursor
!          (QUAL-13 split). A leaf over readline_state: it reads/writes state and
!          module-level kill-ring storage, and calls no redraw/cursor code. Shared
!          by readline and readline_fzf so the fzf browsers can insert into and
!          read the buffer without a use-cycle. Re-exported by readline, so
!          `use readline` consumers are unchanged.
! ==============================================================================
module readline_bufferops
  use readline_state
  implicit none

contains

  !============================================================================
  ! BUFFER OPERATION WRAPPERS - Platform abstraction layer
  !============================================================================
  ! These wrappers handle three platforms:
  !   1. USE_C_STRINGS (macOS ARM64) - C string buffers for >128 byte support
  !   2. USE_MEMORY_POOL (Linux with pooling) - Pooled string references
  !   3. Default - Standard Fortran allocatable strings
  !
  ! This abstraction keeps the main code clean and platform-agnostic.
  !============================================================================

  ! Clear main buffer
  subroutine state_buffer_clear(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    call c_string_clear(state%buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%buffer_ref%data = ''
#else
    state%buffer = ''
#endif
#endif
  end subroutine state_buffer_clear

  ! Set main buffer from string
  subroutine state_buffer_set(state, str)
    type(input_state_t), intent(inout) :: state
    character(len=*), intent(in) :: str
#ifdef USE_C_STRINGS
    logical :: success
    success = c_string_set(state%buffer_c, str)
    if (.not. success) then
      ! Fallback: truncate to buffer size
      ! This maintains old behavior on overflow
    end if
#else
#ifdef USE_MEMORY_POOL
    state%buffer_ref%data = str
#else
    state%buffer = str
#endif
#endif
  end subroutine state_buffer_set

  ! Get main buffer as string
  subroutine state_buffer_get(state, str, actual_len)
    type(input_state_t), intent(in) :: state
    character(len=*), intent(out) :: str
    integer, intent(out), optional :: actual_len
#ifdef USE_C_STRINGS
    integer :: len_out
    call c_string_to_fortran(state%buffer_c, str, len_out)
    if (present(actual_len)) actual_len = len_out
#else
#ifdef USE_MEMORY_POOL
    str = state%buffer_ref%data
    if (present(actual_len)) actual_len = len_trim(state%buffer_ref%data)
#else
    str = state%buffer
    if (present(actual_len)) actual_len = len_trim(state%buffer)
#endif
#endif
  end subroutine state_buffer_get

  ! Get character at position (1-based)
  function state_buffer_get_char(state, pos) result(ch)
    type(input_state_t), intent(in) :: state
    integer, intent(in) :: pos
    character(len=1) :: ch
#ifdef USE_C_STRINGS
    ch = c_string_get_char(state%buffer_c, pos)
#else
#ifdef USE_MEMORY_POOL
    if (pos >= 1 .and. pos <= len(state%buffer_ref%data)) then
      ch = state%buffer_ref%data(pos:pos)
    else
      ch = ' '
    end if
#else
    if (pos >= 1 .and. pos <= len(state%buffer)) then
      ch = state%buffer(pos:pos)
    else
      ch = ' '
    end if
#endif
#endif
  end function state_buffer_get_char

  ! Set character at position (1-based)
  subroutine state_buffer_set_char(state, pos, ch)
    type(input_state_t), intent(inout) :: state
    integer, intent(in) :: pos
    character(len=1), intent(in) :: ch
#ifdef USE_C_STRINGS
    logical :: success
    success = c_string_set_char(state%buffer_c, pos, ch)
#else
#ifdef USE_MEMORY_POOL
    if (pos >= 1 .and. pos <= len(state%buffer_ref%data)) then
      state%buffer_ref%data(pos:pos) = ch
    end if
#else
    if (pos >= 1 .and. pos <= len(state%buffer)) then
      state%buffer(pos:pos) = ch
    end if
#endif
#endif
  end subroutine state_buffer_set_char

  ! Copy main buffer to original_buffer
  subroutine state_buffer_save(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    logical :: success
    success = c_string_copy(state%original_buffer_c, state%buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%original_buffer_ref%data = state%buffer_ref%data
#else
    state%original_buffer = state%buffer
#endif
#endif
  end subroutine state_buffer_save

  ! Restore main buffer from original_buffer
  subroutine state_buffer_restore(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    logical :: success
    success = c_string_copy(state%buffer_c, state%original_buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%buffer_ref%data = state%original_buffer_ref%data
#else
    state%buffer = state%original_buffer
#endif
#endif
  end subroutine state_buffer_restore

  ! Get search string into a fixed-length buffer
  subroutine get_search_string(state, str, slen)
    type(input_state_t), intent(in) :: state
    character(len=*), intent(out) :: str
    integer, intent(in) :: slen
    integer :: j
    str = ''
    if (slen <= 0) return
#ifdef USE_C_STRINGS
    do j = 1, min(slen, len(str))
      str(j:j) = state%search_string(j:j)
    end do
#elif defined(USE_MEMORY_POOL)
    do j = 1, min(slen, len(str))
      str(j:j) = state%search_string_ref%data(j:j)
    end do
#else
    do j = 1, min(slen, len(str))
      str(j:j) = state%search_string(j:j)
    end do
#endif
  end subroutine get_search_string

  ! Set a character in the search string at position pos
  subroutine set_search_char(state, pos, ch)
    type(input_state_t), intent(inout) :: state
    integer, intent(in) :: pos
    character, intent(in) :: ch
#ifdef USE_C_STRINGS
    state%search_string(pos:pos) = ch
#elif defined(USE_MEMORY_POOL)
    state%search_string_ref%data(pos:pos) = ch
#else
    state%search_string(pos:pos) = ch
#endif
  end subroutine set_search_char

  ! Clear the search string
  subroutine clear_search_string(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    state%search_string = ''
#elif defined(USE_MEMORY_POOL)
    state%search_string_ref%data = ''
#else
    state%search_string = ''
#endif
  end subroutine clear_search_string

  ! Clear original buffer
  subroutine state_original_buffer_clear(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    call c_string_clear(state%original_buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%original_buffer_ref%data = ''
#else
    state%original_buffer = ''
#endif
#endif
  end subroutine state_original_buffer_clear

  ! Clear kill buffer
  ! The kill ring content lives in plain module storage, NOT per-state
  ! pooled/C-string buffers: it is SESSION state (Ctrl-Y must paste a
  ! Ctrl-U'd line even after other commands ran, like bash/zsh/fish),
  ! and command execution invalidates the string pool, which forces a
  ! full init_input_state that would wipe any per-state copy.
  subroutine state_kill_buffer_clear(state)
    type(input_state_t), intent(inout) :: state
    if (.false.) print *, state%kill_length  ! Silence unused-dummy warning
    session_kill_buffer = ''
  end subroutine state_kill_buffer_clear

  ! Push killed text onto the kill ring (DIV-2). On a kill that immediately
  ! follows another kill (kill_op_prev_key), the text MERGES into slot 1 —
  ! forward kills append, backward kills prepend — so e.g. two Alt-d kills
  ! yank back together. Otherwise a new slot is pushed to the front. `forward`
  ! selects the merge side (default .true.).
  subroutine state_kill_buffer_set(state, str, forward)
    type(input_state_t), intent(inout) :: state
    character(len=*), intent(in) :: str
    logical, intent(in), optional :: forward
    logical :: fwd
    integer :: i, slen, hlen, newlen
    character(len=MAX_LINE_LEN) :: tmp

    fwd = .true.
    if (present(forward)) fwd = forward
    slen = len(str)
    if (slen <= 0) return
    if (slen > MAX_LINE_LEN) slen = MAX_LINE_LEN

    if (kill_op_prev_key .and. kill_ring_count > 0) then
      ! Merge into the head entry.
      hlen = kill_ring_len(1)
      newlen = min(hlen + slen, MAX_LINE_LEN)
      if (fwd) then
        if (hlen < MAX_LINE_LEN) kill_ring(1)(hlen+1:newlen) = str(1:newlen-hlen)
      else
        tmp = ''
        tmp(1:slen) = str(1:slen)
        if (hlen > 0 .and. slen < MAX_LINE_LEN) tmp(slen+1:newlen) = kill_ring(1)(1:newlen-slen)
        kill_ring(1) = tmp
      end if
      kill_ring_len(1) = newlen
    else
      ! Push a new slot to the front.
      do i = min(kill_ring_count, KILL_RING_SLOTS - 1), 1, -1
        kill_ring(i+1) = kill_ring(i)
        kill_ring_len(i+1) = kill_ring_len(i)
      end do
      kill_ring(1) = ''
      kill_ring(1)(1:slen) = str(1:slen)
      kill_ring_len(1) = slen
      kill_ring_count = min(kill_ring_count + 1, KILL_RING_SLOTS)
    end if

    kill_op_this_key = .true.
    kill_yank_index = 1
    ! Mirror the head for direct readers (handle_yank reads the ring directly,
    ! but other code and tests still consult session_kill_buffer).
    session_kill_buffer = ''
    session_kill_buffer(1:kill_ring_len(1)) = kill_ring(1)(1:kill_ring_len(1))
    state%kill_length = kill_ring_len(1)
  end subroutine state_kill_buffer_set

  ! Get kill buffer as string
  subroutine state_kill_buffer_get(state, str)
    type(input_state_t), intent(in) :: state
    character(len=*), intent(out) :: str
    if (.false.) print *, state%kill_length  ! Silence unused-dummy warning
    str = session_kill_buffer
  end subroutine state_kill_buffer_get

  ! Clear last completion buffer
  subroutine state_last_completion_buffer_clear(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    call c_string_clear(state%last_completion_buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%last_completion_buffer_ref%data = ''
#else
    state%last_completion_buffer = ''
#endif
#endif
  end subroutine state_last_completion_buffer_clear

  ! Set last completion buffer from main buffer
  subroutine state_last_completion_buffer_set_from_buffer(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    logical :: success
    success = c_string_copy(state%last_completion_buffer_c, state%buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%last_completion_buffer_ref%data = state%buffer_ref%data(:state%length)
#else
    state%last_completion_buffer = state%buffer(:state%length)
#endif
#endif
    state%last_completion_buffer_len = state%length
  end subroutine state_last_completion_buffer_set_from_buffer

  ! Compare buffer with last completion buffer
  function state_buffer_equals_last_completion(state) result(equals)
    type(input_state_t), intent(in) :: state
    logical :: equals
#ifdef USE_C_STRINGS
    character(len=MAX_LINE_LEN) :: buf, last_buf
    call c_string_to_fortran(state%buffer_c, buf)
    call c_string_to_fortran(state%last_completion_buffer_c, last_buf)
    equals = (trim(buf) == trim(last_buf))
#else
#ifdef USE_MEMORY_POOL
    equals = (trim(state%buffer_ref%data(:state%length)) == &
              trim(state%last_completion_buffer_ref%data(:state%last_completion_buffer_len)))
#else
    integer :: i
    equals = .true.
    if (state%length /= state%last_completion_buffer_len) then
      equals = .false.
      return
    end if
    do i = 1, state%length
      if (state%buffer(i:i) /= state%last_completion_buffer(i:i)) then
        equals = .false.
        return
      end if
    end do
#endif
#endif
  end function state_buffer_equals_last_completion

  !============================================================================
  ! END BUFFER OPERATION WRAPPERS
  !============================================================================

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
        call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
      end if
    end do

    ! Insert string at cursor position
    do i = 1, insert_len
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, str(i:i))
    end do

    ! Update length and cursor position
    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
  end subroutine

end module readline_bufferops
