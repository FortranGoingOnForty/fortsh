! ==============================================================================
! Module: readline_autopair
! Purpose: Smart quotes and brackets (AR-11 PAIRS) — auto-insertion of the
!          closing character when an opener is typed, cursor advancement when
!          the user types the closer we already inserted, and pair-aware
!          backspace. Decision logic + the pending-closer stack live here; the
!          call sites are insert_char_impl (readline_editops) and the keystroke
!          dispatch / backspace handler (readline).
!
!          A leaf over readline_bufferops: it reads and writes the live input
!          buffer and nothing else — no redraw, no cursor escapes, no terminal
!          I/O. Sits between bufferops and editops in the build order.
!
! Design notes
! ------------
! * The pending-closer stack tracks ONLY closers this module inserted, so a
!   hand-typed ')' sitting in front of an unrelated ')' still inserts rather
!   than silently skipping. It is LIFO by nesting: for "([|])" the top entry is
!   the ']' at the cursor and the enclosing ')' sits at a LARGER position.
! * Positions are maintained through self-insert and backspace only. Every
!   other keystroke wipes the stack via the ap_keep_this_key rotation in the
!   readline input loop (same idiom as kill_op_this_key / undo_op_was_insert),
!   so no edit path can leave a stale entry behind. The worst case of a wipe is
!   a lost skip-over — never a wrong edit.
! * Every use of a stack entry re-checks the byte actually sitting at the
!   recorded position, as a second line of defence against staleness.
! ==============================================================================
module readline_autopair
  use readline_constants
  use readline_state
  use readline_bufferops
  implicit none

  ! set -o autopair. ON by default — this default is duplicated in
  ! shell_state_t%option_autopair (common/types.f90) because set_global_autopair
  ! is only ever called from `set -o`, never at startup. Keep the two in sync.
  logical, save :: global_autopair = .true.

  ! Pending auto-inserted closers, innermost last.
  integer, parameter :: AUTOPAIR_MAX = 32
  integer, save :: ap_pos(AUTOPAIR_MAX) = 0    ! 1-based buffer position of the closer
  character, save :: ap_ch(AUTOPAIR_MAX) = ' ' ! the closer byte itself
  integer, save :: ap_n = 0

  ! Set by the handlers that MAINTAIN the stack (self-insert, skip-over,
  ! backspace). The input loop resets the stack after dispatch when this is
  ! still false, i.e. for every other key.
  logical, save :: ap_keep_this_key = .false.

  ! Quote context of the buffer prefix ending at the cursor.
  integer, parameter :: AP_CTX_PLAIN = 0
  integer, parameter :: AP_CTX_SQ    = 1  ! inside '...'
  integer, parameter :: AP_CTX_DQ    = 2  ! inside "..."

contains

  ! `set -o autopair` / `set +o autopair`. Disabling drops any pending state so
  ! the next closer typed is taken literally.
  subroutine set_global_autopair(enabled)
    logical, intent(in) :: enabled
    global_autopair = enabled
    if (.not. enabled) call autopair_reset()
  end subroutine set_global_autopair

  ! Drop all pending closers. Called per readline() line and by the input loop
  ! for any keystroke that does not maintain the stack.
  subroutine autopair_reset()
    ap_n = 0
  end subroutine autopair_reset

  !============================================================================
  ! PAIR TABLE
  !============================================================================

  ! The closing character for an opener, or ' ' when `ch` opens nothing.
  pure function autopair_closer_for(ch) result(closer)
    character, intent(in) :: ch
    character :: closer
    select case (ch)
    case ('(');  closer = ')'
    case ('[');  closer = ']'
    case ('{');  closer = '}'
    case ('"');  closer = '"'
    case ("'");  closer = "'"
    case ('`');  closer = '`'
    case default; closer = ' '
    end select
  end function autopair_closer_for

  ! True for any byte that can act as a closer (the quotes are both).
  pure function autopair_is_closer(ch) result(yes)
    character, intent(in) :: ch
    logical :: yes
    yes = (ch == ')' .or. ch == ']' .or. ch == '}' .or. &
           ch == '"' .or. ch == "'" .or. ch == '`')
  end function autopair_is_closer

  !============================================================================
  ! BUFFER PREDICATES
  !============================================================================

  ! Byte at a 1-based buffer position, or NUL when the position is off either
  ! end. NUL is the "no such character" sentinel for the guards below.
  function ap_char_at(state, pos) result(ch)
    type(input_state_t), intent(in) :: state
    integer, intent(in) :: pos
    character :: ch
    if (pos < 1 .or. pos > state%length) then
      ch = char(0)
    else
      ch = state_buffer_get_char(state, pos)
    end if
  end function ap_char_at

  ! Word constituent: [A-Za-z0-9_]. Used by the quote guard (G2) so an
  ! apostrophe inside a word ("don't") never opens a pair.
  pure function ap_is_word(ch) result(yes)
    character, intent(in) :: ch
    logical :: yes
    integer :: ic
    ic = iachar(ch)
    yes = (ic >= iachar('a') .and. ic <= iachar('z')) .or. &
          (ic >= iachar('A') .and. ic <= iachar('Z')) .or. &
          (ic >= iachar('0') .and. ic <= iachar('9')) .or. &
          ch == '_'
  end function ap_is_word

  ! G1: auto-close only when the character AFTER the cursor is one we are
  ! willing to push a closer in front of — end of line, whitespace, a
  ! terminator, or another closer. Typing '(' just before an existing word
  ! gives "(foo", never "()foo", which is what keeps the feature out of the
  ! way. Closers must be on the list or nesting inside a pair we just made
  ! would not work: with the cursor in "${|}" the next byte is the '}' we
  ! inserted ourselves, and in 'echo "|"' it is the closing quote.
  pure function ap_next_ok(ch) result(yes)
    character, intent(in) :: ch
    logical :: yes
    yes = autopair_is_closer(ch) .or. &
          ch == char(0) .or. ch == ' ' .or. ch == char(9) .or. &
          ch == ';' .or. ch == '&' .or. ch == '|' .or. &
          ch == ',' .or. ch == '>'
  end function ap_next_ok

  ! Quote state of buffer(1:cursor_pos). Mirrors parser's has_unclosed_quote,
  ! but stops at the cursor rather than at len_trim, and reads through the
  ! buffer accessors. Backslash escapes everywhere except inside '...', where
  ! it is a literal byte.
  function autopair_context(state) result(ctx)
    type(input_state_t), intent(in) :: state
    integer :: ctx
    integer :: i
    logical :: sq, dq, esc
    character :: c

    sq = .false.; dq = .false.; esc = .false.
    do i = 1, state%cursor_pos
      c = state_buffer_get_char(state, i)
      if (esc) then
        esc = .false.
        cycle
      end if
      if (c == '\' .and. .not. sq) then
        esc = .true.
        cycle
      end if
      if (c == "'" .and. .not. dq) then
        sq = .not. sq
      else if (c == '"' .and. .not. sq) then
        dq = .not. dq
      end if
    end do

    if (sq) then
      ctx = AP_CTX_SQ
    else if (dq) then
      ctx = AP_CTX_DQ
    else
      ctx = AP_CTX_PLAIN
    end if
  end function autopair_context

  ! True when the character about to be inserted is backslash-escaped, i.e. an
  ! ODD number of backslashes sits immediately before the cursor. `\"` must
  ! insert a lone quote. Callers skip this test inside '...', where backslash
  ! carries no special meaning.
  function ap_prev_escaped(state) result(esc)
    type(input_state_t), intent(in) :: state
    logical :: esc
    integer :: i, n
    n = 0
    i = state%cursor_pos
    do while (i >= 1)
      if (state_buffer_get_char(state, i) /= '\') exit
      n = n + 1
      i = i - 1
    end do
    esc = (mod(n, 2) == 1)
  end function ap_prev_escaped

  !============================================================================
  ! STACK MAINTENANCE
  !============================================================================

  subroutine autopair_push(pos, ch)
    integer, intent(in) :: pos
    character, intent(in) :: ch
    if (ap_n >= AUTOPAIR_MAX) return
    ap_n = ap_n + 1
    ap_pos(ap_n) = pos
    ap_ch(ap_n) = ch
  end subroutine autopair_push

  ! A byte was inserted and now occupies `at_pos`; everything at or after it
  ! shifted one to the right.
  subroutine autopair_note_insert(at_pos)
    integer, intent(in) :: at_pos
    call autopair_note_insert_n(at_pos, 1)
  end subroutine autopair_note_insert

  ! As above for an `n`-byte insertion starting at `at_pos` — one multi-byte
  ! UTF-8 character. Typing 世 inside a pair must SHIFT the pending closer, not
  ! forfeit it, or the closing quote of `echo 'Hello 世界'` stops skipping over
  ! and the line ends up unbalanced.
  subroutine autopair_note_insert_n(at_pos, n)
    integer, intent(in) :: at_pos, n
    integer :: i
    if (n <= 0) return
    do i = 1, ap_n
      if (ap_pos(i) >= at_pos) ap_pos(i) = ap_pos(i) + n
    end do
  end subroutine autopair_note_insert_n

  ! `n` bytes starting at `from_pos` were removed. An entry INSIDE the removed
  ! span means the pair itself was broken, so the whole stack is dropped rather
  ! than half-tracked; entries after the span shift left.
  subroutine autopair_note_delete(from_pos, n)
    integer, intent(in) :: from_pos, n
    integer :: i
    if (n <= 0) return
    do i = 1, ap_n
      if (ap_pos(i) >= from_pos .and. ap_pos(i) < from_pos + n) then
        call autopair_reset()
        return
      end if
    end do
    do i = 1, ap_n
      if (ap_pos(i) >= from_pos + n) ap_pos(i) = ap_pos(i) - n
    end do
  end subroutine autopair_note_delete

  ! True when everything to the RIGHT of the cursor is exactly the closers we
  ! inserted, innermost first. The line then reads as if the cursor were at the
  ! end, which is what lets an autosuggestion appear inside a pair: the pending
  ! closers are provisional, so the renderer hides them behind the suggestion
  ! (which carries its own closing quote) and accepting drops them.
  !
  ! Without this, typing `git commit -m "` killed autosuggestions for the whole
  ! quoted argument — the single most common place they are wanted.
  function autopair_tail_only(state) result(yes)
    type(input_state_t), intent(in) :: state
    logical :: yes
    integer :: i, slot

    yes = .false.
    if (.not. global_autopair) return
    if (ap_n <= 0) return
    if (state%length - state%cursor_pos /= ap_n) return

    do i = 1, ap_n
      ! The stack top is the INNERMOST closer, so it sits nearest the cursor.
      slot = ap_n - i + 1
      if (ap_pos(slot) /= state%cursor_pos + i) return
      if (state_buffer_get_char(state, state%cursor_pos + i) /= ap_ch(slot)) return
    end do
    yes = .true.
  end function autopair_tail_only

  ! Number of pending closers parked to the right of the cursor, or 0 when the
  ! tail is anything else. Callers use it to size the span an accepted
  ! suggestion replaces.
  function autopair_pending_tail(state) result(n)
    type(input_state_t), intent(in) :: state
    integer :: n
    n = 0
    if (autopair_tail_only(state)) n = ap_n
  end function autopair_pending_tail

  ! Did this keystroke move any bytes? Compared against the pre-dispatch
  ! snapshot the undo layer already takes for free (undo_capture_pre), so the
  ! input loop's sweep can keep the stack across pure cursor motion — arrowing
  ! back inside "(|)" and typing ')' still skips over — and drop it only when
  ! an unaudited edit path could have invalidated the recorded positions.
  function autopair_buffer_changed(state) result(changed)
    type(input_state_t), intent(in) :: state
    logical :: changed
    integer :: j
    changed = (state%length /= undo_pre_len)
    if (changed) return
    do j = 1, state%length
      if (state_buffer_get_char(state, j) /= undo_pre_buf(j:j)) then
        changed = .true.
        return
      end if
    end do
  end function autopair_buffer_changed

  ! Is the top-of-stack closer the byte sitting immediately at the cursor?
  ! Re-reads the buffer, and drops the whole stack if the recorded position no
  ! longer holds what we put there.
  function ap_top_at_cursor(state, ch) result(yes)
    type(input_state_t), intent(in) :: state
    character, intent(in) :: ch
    logical :: yes
    yes = .false.
    if (ap_n <= 0) return
    if (ap_ch(ap_n) /= ch) return
    if (ap_pos(ap_n) /= state%cursor_pos + 1) return
    if (state%cursor_pos + 1 > state%length) return
    yes = (state_buffer_get_char(state, state%cursor_pos + 1) == ch)
  end function ap_top_at_cursor

  !============================================================================
  ! DECISIONS — the three things the call sites ask
  !============================================================================

  ! Should typing `ch` also insert its closer? See the guard table in the
  ! feature notes: escape, G1 (next char), G2 (no quote pairing after a word
  ! character or after the same quote), and the quote-context restrictions.
  function autopair_should_close(state, ch) result(do_close)
    type(input_state_t), intent(in) :: state
    character, intent(in) :: ch
    logical :: do_close
    character :: closer, prev, nxt
    integer :: ctx

    do_close = .false.
    if (.not. global_autopair) return
    closer = autopair_closer_for(ch)
    if (closer == ' ') return
    ! Stack full: degrade to plain insertion rather than pair something we
    ! cannot track (an untracked closer could never be skipped over).
    if (ap_n >= AUTOPAIR_MAX) return

    ctx = autopair_context(state)
    ! Inside '...' everything is literal — including the backslash — so no pair
    ! is ever helpful, and the closing quote is reached by skip-over instead.
    if (ctx == AP_CTX_SQ) return
    if (ap_prev_escaped(state)) return

    ! Inside "..." the substitution openers still pair ("${", "$(", backtick),
    ! but a quote does not: '"' closes the string and "'" is a literal byte.
    if (ctx == AP_CTX_DQ) then
      if (ch == '"' .or. ch == "'") return
    end if

    nxt = ap_char_at(state, state%cursor_pos + 1)
    if (.not. ap_next_ok(nxt)) return

    if (ch == '"' .or. ch == "'" .or. ch == '`') then
      prev = ap_char_at(state, state%cursor_pos)
      ! G2: no pairing after a word character ("don't") or after the same
      ! quote, so a third '"' extends """ instead of opening yet another pair.
      if (ap_is_word(prev)) return
      if (prev == ch) return
    end if

    do_close = .true.
  end function autopair_should_close

  ! Insert `closer` at the cursor WITHOUT advancing it, and record it as
  ! pending. Called right after the opener has been inserted normally.
  ! `ok` reports whether the byte actually went in — callers that echo the
  ! closer themselves (test mode) must not draw one that was refused.
  subroutine autopair_insert_closer(state, closer, ok)
    type(input_state_t), intent(inout) :: state
    character, intent(in) :: closer
    logical, intent(out) :: ok
    integer :: i

    ok = .false.
    ! Same -1 headroom guard as insert_char_impl.
    if (state%length >= MAX_LINE_LEN - 1) return

    do i = state%length, state%cursor_pos + 1, -1
      call state_buffer_set_char(state, i + 1, state_buffer_get_char(state, i))
    end do
    call state_buffer_set_char(state, state%cursor_pos + 1, closer)
    state%length = state%length + 1

    ! Shift the enclosing pairs BEFORE pushing, so the new entry keeps the
    ! position it was actually written at.
    call autopair_note_insert(state%cursor_pos + 1)
    call autopair_push(state%cursor_pos + 1, closer)

    state%dirty = .true.
    ap_keep_this_key = .true.
    ok = .true.
  end subroutine autopair_insert_closer

  ! An opener typed while a selection is live SURROUNDS the selection rather
  ! than typing over it — the editor convention, and strictly more useful here
  ! since replacing is still reachable by deleting first. The selection is kept
  ! over the original text (now shifted one right) so it can be wrapped again.
  ! `consumed` is .true. when the keystroke was handled here.
  subroutine autopair_wrap_selection(state, ch, consumed)
    type(input_state_t), intent(inout) :: state
    character, intent(in) :: ch
    logical, intent(out) :: consumed
    integer :: sel_start, sel_end, i
    character :: closer

    consumed = .false.
    if (.not. global_autopair) return
    if (.not. state%selection_active) return
    if (state%selection_anchor < 0) return

    closer = autopair_closer_for(ch)
    if (closer == ' ') return

    sel_start = min(state%selection_anchor, state%cursor_pos)
    sel_end   = max(state%selection_anchor, state%cursor_pos)
    if (sel_end <= sel_start) return
    if (state%length + 2 > MAX_LINE_LEN - 1) return

    ! The selected text occupies 1-based positions sel_start+1 .. sel_end.
    ! Open a two-byte gap around it, working right to left: the tail past the
    ! selection moves by 2, the selection itself by 1.
    do i = state%length, sel_end + 1, -1
      call state_buffer_set_char(state, i + 2, state_buffer_get_char(state, i))
    end do
    do i = sel_end, sel_start + 1, -1
      call state_buffer_set_char(state, i + 1, state_buffer_get_char(state, i))
    end do
    call state_buffer_set_char(state, sel_start + 1, ch)
    call state_buffer_set_char(state, sel_end + 2, closer)

    state%length = state%length + 2
    state%selection_anchor = sel_start + 1
    state%cursor_pos = sel_end + 1
    state%dirty = .true.

    ! No stack bookkeeping: the closer lands at the far end of the selection,
    ! not at the cursor, so it is not a pending closer to skip over. Leaving
    ! ap_keep_this_key false lets the input loop's sweep drop the old entries,
    ! whose positions this two-part shift would otherwise have invalidated.
    consumed = .true.
  end subroutine autopair_wrap_selection

  ! Typing a closer we already inserted moves over it instead of doubling it.
  ! `consumed` is .true. when the keystroke was handled here.
  subroutine autopair_try_skip(state, ch, consumed)
    type(input_state_t), intent(inout) :: state
    character, intent(in) :: ch
    logical, intent(out) :: consumed

    consumed = .false.
    if (.not. global_autopair) return
    if (.not. autopair_is_closer(ch)) return
    if (ap_n <= 0) return

    if (.not. ap_top_at_cursor(state, ch)) then
      ! Either an unrelated closer, or our record has gone stale under an edit
      ! path that failed to reset. Drop the stack and take the key literally.
      if (ap_n > 0 .and. ap_ch(ap_n) == ch .and. ap_pos(ap_n) == state%cursor_pos + 1) &
        call autopair_reset()
      return
    end if

    ! A backslash before the cursor means the user wants a literal closer.
    if (autopair_context(state) /= AP_CTX_SQ) then
      if (ap_prev_escaped(state)) return
    end if

    ap_n = ap_n - 1
    state%cursor_pos = state%cursor_pos + 1
    state%dirty = .true.
    ap_keep_this_key = .true.
    consumed = .true.
  end subroutine autopair_try_skip

  ! Backspace with the cursor between an opener and the closer we inserted for
  ! it removes both. `consumed` is .true. when the keystroke was handled here.
  subroutine autopair_try_backspace(state, consumed)
    type(input_state_t), intent(inout) :: state
    logical, intent(out) :: consumed
    integer :: i, del_from
    character :: opener, closer

    consumed = .false.
    if (.not. global_autopair) return
    if (ap_n <= 0) return
    if (state%cursor_pos < 1) return
    if (ap_pos(ap_n) /= state%cursor_pos + 1) return
    if (state%cursor_pos + 1 > state%length) return

    opener = state_buffer_get_char(state, state%cursor_pos)
    closer = state_buffer_get_char(state, state%cursor_pos + 1)
    if (closer /= ap_ch(ap_n)) then
      call autopair_reset()
      return
    end if
    if (autopair_closer_for(opener) /= closer) return

    del_from = state%cursor_pos
    do i = del_from, state%length - 2
      call state_buffer_set_char(state, i, state_buffer_get_char(state, i + 2))
    end do
    call state_buffer_set_char(state, state%length - 1, ' ')
    call state_buffer_set_char(state, state%length, ' ')

    state%length = state%length - 2
    state%cursor_pos = state%cursor_pos - 1

    ap_n = ap_n - 1
    call autopair_note_delete(del_from, 2)

    state%dirty = .true.
    ap_keep_this_key = .true.
    consumed = .true.
  end subroutine autopair_try_backspace

end module readline_autopair
