! ==============================================================================
! Module: readline_state
! Purpose: Module-level mutable state shared across the readline family
!          (QUAL-13 split). Session-lifetime save variables, subsystem sizing
!          params tied to that state, and the C system() interface. No
!          procedures — behaviour lives in readline and its submodules, which
!          use-associate this state.
! ==============================================================================
module readline_state
  use readline_constants
  use system_interface   ! termios_t
  use iso_c_binding
  implicit none

  ! Module-level terminal state for FZF functions
  ! Needed because LLVM flang-new's execute_command_line requires cooked mode
  type(termios_t), save :: module_original_termios
  logical, save :: module_termios_saved = .false.

  ! Import c_system from builtins module (it already works there)
  ! We'll reference it via the module instead of defining our own
  interface
    function readline_c_system(command) bind(C, name="system")
      use iso_c_binding
      integer(c_int) :: readline_c_system
      character(kind=c_char), intent(in) :: command(*)
    end function readline_c_system
  end interface

  ! Pager item store: backs the scrollable completion menu (fish-style
  ! disclosure + row scrolling). tab_completions stays capped at
  ! MAX_LOCAL_COMPLETIONS for common-prefix logic; the menu reads from
  ! here when pager_active. pager_collect gates filling so backend calls
  ! from the autosuggestion path can't clobber the store between draws.
  character(len=MAX_MENU_ITEM_LEN), save :: pager_items(PAGER_STORE_MAX)
  integer, save :: pager_item_count = 0
  logical, save :: pager_active = .false.

  ! AR-03c: completion menu description column (fish-style). Descriptions are
  ! computed at menu build from the completion kind + the item + shell state
  ! (variable value, builtin summary); rendered dim to the right of the name.
  ! Parallel to pager_items / menu_items so menu_desc_get mirrors menu_item_get.
  character(len=MAX_MENU_DESC_LEN), save :: pager_descs(PAGER_STORE_MAX)
  logical, save :: pager_collect = .false.

  ! Menu vertical-scroll edge state (AR-03 NEW-2): Up/Down STOP at the top/
  ! bottom of the table (no infinite wrap). When already at an edge, the NEXT
  ! same-direction press jumps to the opposite edge. 0=none, 1=armed-at-top,
  ! 2=armed-at-bottom. Reset whenever a menu opens/closes or any other nav key
  ! moves the selection.
  integer, save :: menu_edge_armed = 0

  ! Set for the single keystroke that clears a fish-style paste highlight
  ! (AR-01-fu). The highlight is dropped at the top of the input loop before
  ! the key dispatches, so a cursor-motion key that lands at end-of-line would
  ! otherwise BOTH clear the highlight AND accept the autosuggestion in one
  ! press — risky when the pasted text is, say, an `rm -rf` path. When this is
  ! true, Right/End/Ctrl-E clear the highlight and stop instead of accepting;
  ! the next press accepts as usual (fish forward-char semantics). Reset each
  ! real keystroke.
  logical, save :: module_paste_hl_cleared_this_key = .false.
  ! AR-08 NICE-CTRLD: latched after the first empty-line Ctrl-D warned about
  ! running jobs; a second consecutive Ctrl-D then exits. Reset by any other key.
  logical, save :: ctrld_warned = .false.

  ! True number of matches found by the most recent completion scan, before
  ! MAX_SCORED_ITEMS / MAX_LOCAL_COMPLETIONS truncation. Feeds the menu's
  ! "... N more items available" indicator with the real total — without it
  ! the indicator can never fire, since stored completions are capped at
  ! MAX_LOCAL_COMPLETIONS == MAX_MENU_ITEMS. Reset per smart_tab_complete run.
  integer, save :: completion_total_matches = 0

  ! Test mode configuration
  logical, save :: test_mode_enabled = .false.
  logical, save :: completion_disabled = .false.
  logical, save :: test_mode_initialized = .false.

  type(history_t), save :: command_history

  ! Module-level HISTCONTROL setting (set by shell)
  character(len=256), save :: current_histcontrol = ''

  ! Module-level editing mode (set by shell via option_vi)
  integer, save :: global_editing_mode = EDITING_MODE_EMACS

  ! Fuzzy completion: off by default (prefix-only like bash/zsh)
  ! Enable with: set -o fuzzy-complete
  logical, save :: global_fuzzy_complete = .false.

  ! Detect macOS for potential platform-specific workarounds
  logical, save :: is_macos_system = .false.
  logical, save :: macos_detected = .false.

  ! Module-level input_state to work around flang-new pointer corruption bug
  type(input_state_t), save, target :: module_input_state
  logical, save :: module_input_state_initialized = .false.

  ! Kill ring content (see state_kill_buffer_set): session-lifetime, so
  ! it survives the per-command string-pool invalidation and re-init.
  ! session_kill_buffer mirrors the ring head (slot 1) for direct readers.
  character(len=MAX_LINE_LEN), save :: session_kill_buffer = ''

  ! Multi-slot kill ring (AR-05 DIV-2), emacs/fish-style. Slot 1 is newest.
  ! All kill ops (Ctrl-K/U/W, Alt-d, Alt-Backspace, selection cut) push_front
  ! via state_kill_buffer_set; consecutive kills accumulate into slot 1
  ! (forward kills append, backward kills prepend). Ctrl-Y yanks slot 1; Alt-y
  ! (yank-pop) rotates through older slots, replacing the just-yanked span.
  ! Module-scoped so it survives the per-command pool re-init, like the kill
  ! buffer above — see [[fortsh-yank-registers-session-scoped]].
  integer, parameter :: KILL_RING_SLOTS = 16
  character(len=MAX_LINE_LEN), save :: kill_ring(KILL_RING_SLOTS) = ''
  integer, save :: kill_ring_len(KILL_RING_SLOTS) = 0
  integer, save :: kill_ring_count = 0   ! filled slots (0..KILL_RING_SLOTS)
  ! Consecutive-kill accumulation: rotated each keystroke (prev <- this; this
  ! <- false), so a kill op can tell whether the immediately preceding key was
  ! also a kill and merge into slot 1 instead of pushing a new slot.
  logical, save :: kill_op_prev_key = .false.
  logical, save :: kill_op_this_key = .false.
  ! Yank-pop chain: Alt-y only acts when the previous key was a yank/yank-pop.
  logical, save :: yank_op_prev_key = .false.
  logical, save :: yank_op_this_key = .false.
  integer, save :: kill_yank_index = 0   ! ring slot the last yank came from
  integer, save :: last_yank_start = 0   ! buffer offset where the last yank landed
  integer, save :: last_yank_len = 0     ! length of the last-yanked span

  ! Undo/redo (AR-05 DIV-1). Each edit pushes the PRE-edit snapshot (buffer +
  ! cursor) onto the undo stack; undo restores it and moves the current state to
  ! the redo stack; a fresh edit clears redo. Consecutive single-char inserts
  ! coalesce into one group (undo removes a whole typed run, like fish). Reset
  ! per readline() call — each command line has its own history.
  integer, parameter :: UNDO_STACK_MAX = 128
  character(len=MAX_LINE_LEN), save :: undo_stack(UNDO_STACK_MAX)
  integer, save :: undo_stack_len(UNDO_STACK_MAX) = 0
  integer, save :: undo_stack_cur(UNDO_STACK_MAX) = 0
  integer, save :: undo_n = 0
  character(len=MAX_LINE_LEN), save :: redo_stack(UNDO_STACK_MAX)
  integer, save :: redo_stack_len(UNDO_STACK_MAX) = 0
  integer, save :: redo_stack_cur(UNDO_STACK_MAX) = 0
  integer, save :: redo_n = 0
  ! Pre-dispatch snapshot of the live buffer, captured each keystroke.
  character(len=MAX_LINE_LEN), save :: undo_pre_buf = ''
  integer, save :: undo_pre_len = 0
  integer, save :: undo_pre_cursor = 0
  ! Insert-run coalescing + a guard so undo/redo itself isn't recorded as an edit.
  logical, save :: undo_op_was_insert = .false.
  logical, save :: undo_prev_was_insert = .false.
  logical, save :: undo_navigate_this_key = .false.

  ! Vi yank register: also session-lifetime. Fixed-length module storage,
  ! NOT the per-state vi_yank_buffer allocatable — under USE_MEMORY_POOL
  ! that allocatable is never allocated (init only touches the pooled
  ! ref), so state_buffer_get into it and the self-slice that followed
  ! segfaulted on every yy. Module storage is always valid and survives
  ! the per-command re-init, matching vim's session-scoped register.
  character(len=MAX_LINE_LEN), save :: session_vi_yank = ''

  ! Vi dot-repeat (AR-05b stage 2). The last buffer-changing command, replayed
  ! by `.`. Session-scoped module state (like the yank register) so it survives
  ! the per-command input_state re-init. Stage 2a covers the non-insert family;
  ! DOT_INSERT (captured text for c/i/a) lands in 2b.
  integer, parameter :: DOTK_NONE = 0
  integer, parameter :: DOTK_SIMPLE = 1   ! a direct key change: x X p P
  integer, parameter :: DOTK_MOTION = 2   ! operator+motion: d<motion> (dd/dw/...)
  integer, parameter :: DOTK_REPLACE = 3  ! r<char>
  integer, parameter :: DOTK_INSERT = 4   ! insert/change + typed text (i/a/c<m>/...)
  integer, parameter :: DOTK_TEXTOBJ = 5  ! d/c/y on a text object (diw, ci", ...)
  integer, save :: dot_kind = DOTK_NONE
  integer, save :: dot_count = 1
  character, save :: dot_key = ' '       ! the key for DOTK_SIMPLE
  character, save :: dot_motion = ' '    ! the motion for DOTK_MOTION / change-motion
  character, save :: dot_char = ' '      ! the replacement char for DOTK_REPLACE
  character, save :: dot_entry = ' '     ! insert-entry cmd for DOTK_INSERT (i a A I o O C c)
  character, save :: dot_to_op = ' '     ! operator for DOTK_TEXTOBJ (d c y)
  character, save :: dot_to_ia = ' '     ! 'i' or 'a' for DOTK_TEXTOBJ
  character, save :: dot_to_obj = ' '    ! object char for DOTK_TEXTOBJ (w " ' ( { [ ...)
  character(len=MAX_LINE_LEN), save :: dot_insert_buf = ''  ! text typed during the insert
  integer, save :: dot_insert_len = 0
  logical, save :: dot_recording_insert = .false.  ! capturing typed insert text
  logical, save :: dot_replaying = .false.  ! suppress recording during replay

  ! Module-level syntax highlighting buffer (fixed-length to avoid flang-new allocatable bugs)
  character(len=4096), save :: module_highlighted_buffer
  integer, save :: module_highlighted_len

  ! Redraw output buffer — accumulates the entire redraw frame so it can be
  ! written to the terminal in a single write() call.  This prevents the
  ! ESC[J clear from being rendered as a blank frame before the new content
  ! arrives, eliminating visible flashing (especially on FreeBSD).
  integer, parameter :: REDRAW_BUF_SIZE = 16384
  character(len=REDRAW_BUF_SIZE), save :: rdraw_buf
  integer, save :: rdraw_pos = 0

  ! Display diffing (Phase 1): skip full redraws when only cursor moved
  integer, save :: prev_diff_buf_len = -1
  integer, save :: prev_diff_cursor_pos = -1
  integer, save :: prev_diff_suggest_len = 0
  logical, save :: prev_diff_valid = .false.
  character(len=MAX_LINE_LEN), save :: prev_diff_content

  ! Display diffing (Phase 2): line-level content comparison
  ! Mirror rendered content into content_frame during redraw; compare
  ! with prev_render_frame to skip unchanged leading lines.
  logical, save :: rdraw_mirror = .false.
  character(len=REDRAW_BUF_SIZE), save :: content_frame
  integer, save :: cframe_pos = 0
  character(len=REDRAW_BUF_SIZE), save :: prev_render_frame
  integer, save :: prev_render_len = 0
  logical, save :: prev_render_valid = .false.

  ! Track actual cursor screen position (row, col) to fix redraw issues
  ! Used to know where cursor is on screen vs where buffer says it should be
  integer, save :: module_cursor_screen_row = 0
  integer, save :: module_cursor_screen_col = 0

  ! Track whether the search status line is currently displayed below the prompt
  logical, save :: module_search_status_shown = .false.

  ! Shift-phase selection state (Sprint 1)
  ! When .true., the next base movement handler call should extend the active
  ! selection rather than collapse it. Set by the shift-arrow dispatch in
  ! handle_extended_escape_sequence immediately before calling a base handler,
  ! cleared immediately after. Module-level rather than per-state so handlers
  ! don't need a new parameter (avoids flang-new derived-type ABI issues — #6).
  logical, save :: module_extending_selection = .false.

  ! FORTSH_DEBUG_SELECTION env flag — dumps selection state to stderr when set.
  ! Probed once at init; cached. Pattern #20 from overview.md.
  logical, save :: debug_selection = .false.
  logical, save :: debug_selection_initialized = .false.

  ! Clipboard bridge state (shift phase, Sprint 5).
  ! Probed once at init; the detected tool is cached. Pattern #19.
  integer, parameter :: CLIP_NONE   = 0
  integer, parameter :: CLIP_PBCOPY = 1  ! macOS
  integer, parameter :: CLIP_WLCOPY = 2  ! Wayland
  integer, parameter :: CLIP_XCLIP  = 3  ! X11
  integer, parameter :: CLIP_XSEL   = 4  ! X11 fallback
  integer, save :: clipboard_tool = CLIP_NONE
  logical, save :: clipboard_initialized = .false.

end module readline_state
