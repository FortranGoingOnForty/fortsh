! ==============================================================================
! Module: readline
! Purpose: Advanced input handling with command history and line editing
! ==============================================================================
module readline
  use shell_types
  use system_interface
  use completion, only: get_completion_spec, generate_completions, completion_spec_t, MAX_COMPLETIONS
  use syntax_highlight, only: highlight_command_line, highlight_single_char, init_syntax_highlighting, MAX_HIGHLIGHT_LEN
  use abbreviations, only: try_expand_abbreviation
  use suggestions, only: compute_path_suggestion, compute_history_suggestion, &
                         suggestion_result_t, SUGGEST_NONE
  use glob, only: pattern_matches
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  use iso_c_binding
  use buffer_ops
#ifdef USE_C_STRINGS
  use fortsh_c_strings
#endif
#ifdef USE_MEMORY_POOL
  use string_pool
  use memory_dashboard
#endif
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

  ! Note: c_signal, SIG_DFL, and SIGCHLD are imported from system_interface

  ! Constants for special keys
  integer, parameter :: KEY_ENTER = 10
  integer, parameter :: KEY_BACKSPACE = 127
  integer, parameter :: KEY_DELETE = 127  ! Same as backspace on most terminals
  integer, parameter :: KEY_TAB = 9
  integer, parameter :: KEY_CTRL_C = 3
  integer, parameter :: KEY_CTRL_D = 4
  integer, parameter :: KEY_CTRL_V = 22   ! Paste from system clipboard / kill buffer
  integer, parameter :: KEY_CTRL_X = 24   ! Cut selection / Process kill mode
  integer, parameter :: KEY_CTRL_A = 1    ! Home (beginning of line)
  integer, parameter :: KEY_CTRL_E = 5    ! End (end of line)
  integer, parameter :: KEY_CTRL_K = 11   ! Kill to end of line
  integer, parameter :: KEY_CTRL_L = 12   ! Clear screen
  integer, parameter :: KEY_CTRL_W = 23   ! Kill previous word
  integer, parameter :: KEY_CTRL_U = 21   ! Kill to beginning of line (unix-line-discard)
  integer, parameter :: KEY_CTRL_Y = 25   ! Yank (paste) killed text
  integer, parameter :: KEY_CTRL_F = 6    ! FZF file browser
  integer, parameter :: KEY_CTRL_B = 2    ! Backward character (same as left arrow)
  integer, parameter :: KEY_CTRL_R = 18   ! Reverse-i-search
  integer, parameter :: KEY_CTRL_S = 19   ! Forward-i-search
  integer, parameter :: KEY_CTRL_G = 7    ! Cancel (alternate to Ctrl+C)
  integer, parameter :: KEY_CTRL_H = 8    ! FZF history browser
  integer, parameter :: KEY_CTRL_T = 20   ! Transpose characters
  integer, parameter :: KEY_CTRL_N = 14   ! Next history (emacs binding)
  integer, parameter :: KEY_CTRL_P = 16   ! Previous history (emacs binding)
  integer, parameter :: KEY_ESC = 27
  integer, parameter :: KEY_UP = 65
  integer, parameter :: KEY_DOWN = 66
  integer, parameter :: KEY_RIGHT = 67
  integer, parameter :: KEY_LEFT = 68
  
  ! History and line management
  ! NOTE: The 128-byte limit was based on older flang-new versions.
  ! Testing with flang-new 21.x shows both fixed-length and allocatable strings
  ! work correctly with >128 bytes. The C string library provides additional safety.
  ! MAX_HISTORY can be increased safely because it uses array allocation, not per-element size
#ifdef __APPLE__
  integer, parameter :: MAX_HISTORY = 100      ! Increased from 10 (heap-allocated array, safe)
#ifdef USE_C_STRINGS
  ! C string library enabled - use larger buffers (tested working with flang-new 21.x)
  integer, parameter :: MAX_LINE_LEN = 1024
#else
  ! Legacy limit for older flang-new versions without C string library
  integer, parameter :: MAX_LINE_LEN = 128     ! Buffer size - actual limit is 127 chars!
#endif
#else
  integer, parameter :: MAX_HISTORY = 1000
  integer, parameter :: MAX_LINE_LEN = 1024
#endif

  ! Glob expansion constants (from glob module)
  integer, parameter :: MAX_GLOB_MATCHES = 1000
  ! MAX_TOKEN_LEN is already defined in shell_types
  
  ! Input state management
  ! Editing mode constants
  integer, parameter :: EDITING_MODE_EMACS = 1
  integer, parameter :: EDITING_MODE_VI = 2
  integer, parameter :: VI_MODE_INSERT = 1
  integer, parameter :: VI_MODE_COMMAND = 2

  ! Reduced buffer sizes to prevent static storage issues
  ! Was causing 204KB allocation (50*4096), now only 25KB (40*256)
  integer, parameter :: MAX_MENU_ITEM_LEN = 256
  integer, parameter :: MAX_MENU_ITEMS = 40  ! Increased from 20 for better usability
  integer, parameter :: MAX_LOCAL_COMPLETIONS = 40  ! Max completions to process locally
  integer, parameter :: MAX_DIR_ENTRIES = 200  ! Max directory entries (increased for better completion)
  integer, parameter :: MAX_SCORED_ITEMS = 512  ! Max scored completion items (raised for pager)

  ! Pager item store: backs the scrollable completion menu (fish-style
  ! disclosure + row scrolling). tab_completions stays capped at
  ! MAX_LOCAL_COMPLETIONS for common-prefix logic; the menu reads from
  ! here when pager_active. pager_collect gates filling so backend calls
  ! from the autosuggestion path can't clobber the store between draws.
  integer, parameter :: PAGER_STORE_MAX = 512
  character(len=MAX_MENU_ITEM_LEN), save :: pager_items(PAGER_STORE_MAX)
  integer, save :: pager_item_count = 0
  logical, save :: pager_active = .false.
  logical, save :: pager_collect = .false.

  ! Menu vertical-scroll edge state (AR-03 NEW-2): Up/Down STOP at the top/
  ! bottom of the table (no infinite wrap). When already at an edge, the NEXT
  ! same-direction press jumps to the opposite edge. 0=none, 1=armed-at-top,
  ! 2=armed-at-bottom. Reset whenever a menu opens/closes or any other nav key
  ! moves the selection.
  integer, save :: menu_edge_armed = 0

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

  type :: input_state_t
#ifdef USE_C_STRINGS
    ! C string buffers - bypass flang-new 128-byte bug on macOS ARM64
    ! These allow unlimited string length without heap corruption
    type(c_string_buffer) :: buffer_c
    type(c_string_buffer) :: original_buffer_c
    type(c_string_buffer) :: kill_buffer_c
    type(c_string_buffer) :: last_completion_buffer_c
#else
    ! Use allocatable strings to avoid stack allocation on macOS
    character(len=:), allocatable :: buffer
    character(len=:), allocatable :: original_buffer  ! Save original input during history navigation
    character(len=:), allocatable :: kill_buffer      ! Kill ring buffer for cut/paste
    character(len=:), allocatable :: last_completion_buffer  ! Buffer when we last showed completions
#endif
    integer :: length = 0
    integer :: cursor_pos = 0  ! 0-based position in buffer
    integer :: history_pos = 0  ! Current position in history (0 = not browsing)
    integer :: kill_length = 0  ! Length of text in kill buffer
    logical :: dirty = .false. ! Needs redraw
    logical :: in_history = .false. ! Currently browsing history
    logical :: completions_shown = .false. ! Have we shown completion list for current buffer?
    integer :: last_completion_buffer_len = 0  ! Length of last_completion_buffer (includes trailing spaces!)

    ! Reverse-i-search state
    logical :: in_search = .false. ! Currently in i-search mode (forward or reverse)
    logical :: search_forward = .false. ! True = forward, False = reverse
    character(len=:), allocatable :: search_string  ! Current search query
    integer :: search_length = 0 ! Length of search string
    integer :: search_match_index = 0 ! Current history match index

    ! Editing mode support
    integer :: editing_mode = EDITING_MODE_EMACS
    integer :: vi_mode = VI_MODE_INSERT
    character(len=:), allocatable :: vi_command_buffer
    integer :: vi_command_count = 0
    logical :: vi_repeat_pending = .false.

    ! Advanced vi mode features
    character(len=:), allocatable :: vi_yank_buffer  ! Vi-style yank buffer
    integer :: vi_yank_length = 0
    integer :: vi_marks(26) = 0  ! Mark positions for 'a'-'z' (0 = not set)
    character(len=:), allocatable :: vi_search_pattern
    integer :: vi_search_length = 0
    logical :: vi_search_forward = .true.
    logical :: vi_in_vi_search = .false.

    ! Autosuggestion support (fish-style)
    ! CRITICAL: Must use fixed-length (NOT deferred-length) for flang-new compatibility
    character(len=MAX_LINE_LEN) :: suggestion  ! Current suggestion from history (fixed-length to avoid flang-new bug)
    integer :: suggestion_length = 0  ! Length of suggestion

    ! Prefix history search (fish-style up/down arrow with typed prefix)
    logical :: in_prefix_search = .false.     ! Currently in prefix search mode
    character(len=MAX_LINE_LEN) :: prefix_search_text  ! Frozen prefix text
    integer :: prefix_search_len = 0          ! Length of frozen prefix
    integer :: prefix_search_idx = 0          ! Current match index in history (0 = at present/original)
    logical :: prefix_search_flash = .false.  ! Transient: flash reverse video on no-match

    ! Menu selection support (zsh/fish-style interactive completion)
    logical :: in_menu_select = .false.  ! Currently in menu selection mode
    character(len=MAX_MENU_ITEM_LEN) :: menu_items(MAX_MENU_ITEMS)  ! Completion items for menu (fixed-length to avoid flang-new bug)
    integer :: menu_num_items = 0  ! Number of items in menu
    integer :: menu_total_items = 0  ! Total number of completions available (before truncation)
    integer :: menu_selection = 1  ! Currently selected item (1-based)
    character(len=:), allocatable :: menu_prefix  ! Command prefix before completion word
    integer :: menu_prefix_len = 0  ! Actual length of prefix INCLUDING trailing space
    character(len=MAX_LINE_LEN) :: menu_prompt  ! Prompt when in menu mode (fixed-length to avoid flang-new bugs)
    logical :: skip_cursor_up_on_redraw = .false.  ! Skip upward cursor movement on next redraw
    ! Cached grid layout (avoid recalculating on every navigation)
    integer :: menu_cols_per_item = 0
    integer :: menu_items_per_row = 0
    integer :: menu_num_rows = 0
    ! Pager window (fish-style disclosure + row scrolling)
    integer :: menu_row_start = 1      ! First visible grid row (1-based)
    logical :: menu_disclosed = .false. ! Expanded to full available height
    integer :: menu_visible_rows = 0   ! Rows shown by the last draw
    integer :: menu_drawn_lines = 0    ! Lines of the last menu render (rows + progress line)

    ! Process kill mode support (Ctrl-X)
    logical :: in_process_kill_mode = .false.  ! Currently in process kill mode
    logical :: in_signal_input = .false.  ! Entering signal to send
    integer :: selected_pid = 0  ! PID of selected process
    character(len=:), allocatable :: selected_process_name  ! Name of selected process

    ! Track if initialized
    logical :: initialized = .false.

#ifdef USE_MEMORY_POOL
    ! Pool references for memory management
    type(string_ref) :: buffer_ref
    type(string_ref) :: original_buffer_ref
    type(string_ref) :: kill_buffer_ref
    type(string_ref) :: last_completion_buffer_ref
    type(string_ref) :: search_string_ref
    type(string_ref) :: vi_command_buffer_ref
    type(string_ref) :: vi_yank_buffer_ref
    type(string_ref) :: vi_search_pattern_ref
    type(string_ref) :: menu_prefix_ref
    type(string_ref) :: selected_process_name_ref
#endif

    ! Text selection state (shift phase, Sprint 1)
    ! Appended at end of type per overview.md pattern #5 — do not reorder.
    ! Selection range is [min(anchor, cursor_pos) .. max(anchor, cursor_pos))
    ! measured in BYTES (consistent with cursor_pos and length — pattern #11).
    integer :: selection_anchor = -1      ! -1 = no anchor set
    logical :: selection_active = .false. ! .true. iff a selection is live

    ! Paste highlight (fish-style): the span just inserted by a bracketed paste
    ! is shown in reverse video until the next keystroke. This is DISTINCT from
    ! selection_active on purpose — selection_active triggers type-over delete in
    ! insert_char_impl, which would erase the pasted text on the next key.
    ! Range is [paste_hl_start .. paste_hl_end) in BYTES, like the selection.
    logical :: paste_hl_active = .false.
    integer :: paste_hl_start = 0
    integer :: paste_hl_end = 0
  end type input_state_t

  type :: history_t
    ! Use allocatable array to avoid stack allocation on macOS
    ! CRITICAL: Must use fixed-length (NOT deferred-length) for flang-new compatibility
    character(len=MAX_LINE_LEN), allocatable :: lines(:)
    integer :: count = 0
    integer :: current = 0  ! Current position in history navigation
    logical :: initialized = .false.
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
  ! it survives the per-command string-pool invalidation and re-init
  character(len=MAX_LINE_LEN), save :: session_kill_buffer = ''

  ! Vi yank register: also session-lifetime. Fixed-length module storage,
  ! NOT the per-state vi_yank_buffer allocatable — under USE_MEMORY_POOL
  ! that allocatable is never allocated (init only touches the pooled
  ! ref), so state_buffer_get into it and the self-slice that followed
  ! segfaulted on every yy. Module storage is always valid and survives
  ! the per-command re-init, matching vim's session-scoped register.
  character(len=MAX_LINE_LEN), save :: session_vi_yank = ''

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

contains

  !============================================================================
  ! REDRAW BUFFER HELPERS — accumulate output, flush in one write()
  !============================================================================

  subroutine rdraw_clear()
    rdraw_pos = 0
  end subroutine

  subroutine rdraw_append(s)
    character(len=*), intent(in) :: s
    integer :: slen
    slen = len(s)
    if (rdraw_mirror .and. cframe_pos + slen <= REDRAW_BUF_SIZE) then
      content_frame(cframe_pos+1:cframe_pos+slen) = s
      cframe_pos = cframe_pos + slen
    end if
    if (rdraw_pos + slen > REDRAW_BUF_SIZE) then
      call rdraw_flush()
    end if
    if (slen > REDRAW_BUF_SIZE) then
      write(output_unit, '(a)', advance='no') s
      return
    end if
    rdraw_buf(rdraw_pos+1:rdraw_pos+slen) = s
    rdraw_pos = rdraw_pos + slen
  end subroutine

  subroutine rdraw_append_char(ch)
    character, intent(in) :: ch
    if (rdraw_mirror .and. cframe_pos + 1 <= REDRAW_BUF_SIZE) then
      cframe_pos = cframe_pos + 1
      content_frame(cframe_pos:cframe_pos) = ch
    end if
    if (rdraw_pos + 1 > REDRAW_BUF_SIZE) call rdraw_flush()
    rdraw_pos = rdraw_pos + 1
    rdraw_buf(rdraw_pos:rdraw_pos) = ch
  end subroutine

  subroutine rdraw_flush()
    if (rdraw_pos > 0) then
      write(output_unit, '(a)', advance='no') rdraw_buf(1:rdraw_pos)
      rdraw_pos = 0
    end if
    flush(output_unit)
  end subroutine

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

  ! Set kill buffer from string
  subroutine state_kill_buffer_set(state, str)
    type(input_state_t), intent(inout) :: state
    character(len=*), intent(in) :: str
    if (.false.) print *, state%kill_length  ! Silence unused-dummy warning
    session_kill_buffer = str
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

  !============================================================================
  ! TEXT SELECTION HELPERS (shift phase, Sprint 1)
  !============================================================================
  ! Three-state machine:
  !   - Inactive:  selection_anchor = -1, selection_active = .false.
  !   - Active:    selection_anchor in [0, length], selection_active = .true.,
  !                selected range = [min(anchor, cursor_pos), max(anchor, cursor_pos))
  !
  ! Extending vs collapsing:
  !   - Shift+motion calls set module_extending_selection=.true. before calling
  !     a base movement handler, then call update_selection_on_shift_motion()
  !     after to install/extend the selection against the old cursor position.
  !   - Plain motion handlers check module_extending_selection at the top; if
  !     .false. and selection_active, they collapse (char motions snap to the
  !     appropriate edge; word/line motions just clear state and proceed).
  !============================================================================

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

  ! Copy the selected byte range into the kill buffer. No-op if selection
  ! is not active. Does NOT modify the main buffer or clear the selection —
  ! callers decide whether this is a copy (Alt+W) or a cut (Ctrl+W) by
  ! whether they follow up with delete_selection + collapse.
  subroutine copy_selection_to_kill_buffer(state)
    type(input_state_t), intent(inout) :: state
    integer :: sel_start, sel_end, span
    character(len=MAX_LINE_LEN) :: temp_buf

    if (.not. state%selection_active) return
    if (state%selection_anchor < 0) return

    sel_start = min(state%selection_anchor, state%cursor_pos)
    sel_end   = max(state%selection_anchor, state%cursor_pos)
    span      = sel_end - sel_start

    if (span <= 0) return

    ! state_buffer_get returns 1-indexed character data; sel_start/sel_end
    ! are 0-based byte offsets, so the slice is [sel_start+1 .. sel_end].
    call state_buffer_get(state, temp_buf)
    call state_kill_buffer_set(state, temp_buf(sel_start+1:sel_end))
    state%kill_length = span

    ! Sprint 5: also write to system clipboard (no-op if no tool detected).
    call clipboard_copy(temp_buf(sel_start+1:sel_end), span)

    call debug_selection_log('copy-to-kill', state)
  end subroutine copy_selection_to_kill_buffer

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

  !============================================================================
  ! END TEXT SELECTION HELPERS
  !============================================================================

  !============================================================================
  ! CLIPBOARD BRIDGE (shift phase, Sprint 5)
  !============================================================================
  ! Provides system-clipboard copy and paste via external tools.
  ! Probe order: pbcopy (macOS), wl-copy (Wayland), xclip (X11), xsel (X11).
  ! If no tool is found, operations no-op gracefully — the in-session
  ! kill_buffer remains the source of truth. Pattern #19, #22.
  !============================================================================

  ! Detect the clipboard tool at startup (idempotent).
  subroutine clipboard_detect()
    if (clipboard_initialized) return
    clipboard_initialized = .true.

    ! Probe in preference order via a native $PATH scan (access(X_OK)),
    ! not a `which` subprocess.
    if (command_in_path('pbcopy')) then
      clipboard_tool = CLIP_PBCOPY
    else if (command_in_path('wl-copy')) then
      clipboard_tool = CLIP_WLCOPY
    else if (command_in_path('xclip')) then
      clipboard_tool = CLIP_XCLIP
    else if (command_in_path('xsel')) then
      clipboard_tool = CLIP_XSEL
    end if
    ! No tool found — clipboard_tool stays CLIP_NONE.
  end subroutine clipboard_detect

  ! Copy text to the system clipboard. No-op if no tool was detected.
  subroutine clipboard_copy(text, text_len)
    use iso_c_binding, only: c_ptr, c_null_char, c_loc, c_int, c_associated
    character(len=*), intent(in) :: text
    integer, intent(in) :: text_len
    type(c_ptr) :: pipe_ptr
    integer(c_int) :: rc
    character(len=256), target :: c_command
    character(len=4), target :: c_mode
    ! Buffer for writing — must be null-terminated for c_fputs.
    ! Use MAX_LINE_LEN+1 to accommodate the NUL terminator.
    character(len=MAX_LINE_LEN+1), target :: c_text

    if (.not. clipboard_initialized) call clipboard_detect()
    if (clipboard_tool == CLIP_NONE) return
    if (text_len <= 0) return

    ! Build the popen command for the detected tool.
    select case (clipboard_tool)
    case (CLIP_PBCOPY)
      c_command = 'pbcopy' // c_null_char
    case (CLIP_WLCOPY)
      c_command = 'wl-copy' // c_null_char
    case (CLIP_XCLIP)
      c_command = 'xclip -selection clipboard' // c_null_char
    case (CLIP_XSEL)
      c_command = 'xsel --clipboard --input' // c_null_char
    case default
      return
    end select

    c_mode = 'w' // c_null_char

    pipe_ptr = c_popen(c_loc(c_command), c_loc(c_mode))
    if (.not. c_associated(pipe_ptr)) return

    ! Write the text, null-terminated, to the pipe.
    c_text = text(1:text_len) // c_null_char
    rc = c_fputs(c_loc(c_text), pipe_ptr)

    rc = c_pclose(pipe_ptr)
  end subroutine clipboard_copy

  ! Paste text from the system clipboard into a buffer.
  ! Returns the number of bytes read (0 if no tool or empty clipboard).
  subroutine clipboard_paste(buffer, buffer_len, bytes_read)
    character(len=*), intent(out) :: buffer
    integer, intent(in) :: buffer_len
    integer, intent(out) :: bytes_read
    character(len=:), allocatable :: result
    character(len=256) :: paste_cmd

    bytes_read = 0

    if (.not. clipboard_initialized) call clipboard_detect()
    if (clipboard_tool == CLIP_NONE) return

    ! Build the paste command.
    select case (clipboard_tool)
    case (CLIP_PBCOPY)
      paste_cmd = 'pbpaste -Prefer txt 2>/dev/null'
    case (CLIP_WLCOPY)
      paste_cmd = 'wl-paste --no-newline 2>/dev/null'
    case (CLIP_XCLIP)
      paste_cmd = 'xclip -selection clipboard -o 2>/dev/null'
    case (CLIP_XSEL)
      paste_cmd = 'xsel --clipboard --output 2>/dev/null'
    case default
      return
    end select

    result = execute_and_capture(trim(paste_cmd))
    if (.not. allocated(result)) return
    if (len_trim(result) == 0) return

    bytes_read = min(len_trim(result), buffer_len)
    buffer = ''
    buffer(1:bytes_read) = result(1:bytes_read)
  end subroutine clipboard_paste

  !============================================================================
  ! END CLIPBOARD BRIDGE
  !============================================================================

  ! Initialize input_state_t with allocated strings
  subroutine init_input_state(state)
    type(input_state_t), intent(inout) :: state

#ifdef USE_C_STRINGS
    ! C strings take precedence on macOS ARM64 (flang-new workaround)
    ! C string buffer allocations - bypass flang-new 128-byte bug
    state%buffer_c = c_string_create(MAX_LINE_LEN)
    state%original_buffer_c = c_string_create(MAX_LINE_LEN)
    state%kill_buffer_c = c_string_create(MAX_LINE_LEN)
    state%last_completion_buffer_c = c_string_create(MAX_LINE_LEN)
    allocate(character(len=MAX_LINE_LEN) :: state%search_string)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_command_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_yank_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_search_pattern)
    allocate(character(len=MAX_LINE_LEN) :: state%menu_prefix)
    allocate(character(len=256) :: state%selected_process_name)
#elif defined(USE_MEMORY_POOL)
    ! Memory pool path for Linux
    ! Initialize pool if needed
    call pool_init()

    ! Use pooled allocations for frequently-used buffers with dashboard tracking
    state%buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%original_buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%kill_buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%last_completion_buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%search_string_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%vi_command_buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%vi_yank_buffer_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%vi_search_pattern_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%menu_prefix_ref = pool_get_string(MAX_LINE_LEN)
    call dashboard_track_allocation(MOD_READLINE, MAX_LINE_LEN, 3)

    state%selected_process_name_ref = pool_get_string(256)
    call dashboard_track_allocation(MOD_READLINE, 256, 2)

    ! CHUNK 2: Allocatable strings removed - using pooled refs instead
    ! These allocations are redundant since we have pooled memory
    ! Code must now use state%buffer_ref%data instead of state%buffer
    ! allocate(character(len=MAX_LINE_LEN) :: state%buffer)
    ! allocate(character(len=MAX_LINE_LEN) :: state%original_buffer)
    ! allocate(character(len=MAX_LINE_LEN) :: state%kill_buffer)
    ! allocate(character(len=MAX_LINE_LEN) :: state%last_completion_buffer)
    ! allocate(character(len=MAX_LINE_LEN) :: state%search_string)
    ! allocate(character(len=MAX_LINE_LEN) :: state%vi_command_buffer)
    ! allocate(character(len=MAX_LINE_LEN) :: state%vi_yank_buffer)
    ! allocate(character(len=MAX_LINE_LEN) :: state%vi_search_pattern)
    ! allocate(character(len=MAX_LINE_LEN) :: state%menu_prefix)
    ! allocate(character(len=256) :: state%selected_process_name)
#else
    ! Traditional allocations
    allocate(character(len=MAX_LINE_LEN) :: state%buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%original_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%kill_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%last_completion_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%search_string)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_command_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_yank_buffer)
    allocate(character(len=MAX_LINE_LEN) :: state%vi_search_pattern)
    ! suggestion is now fixed-length, no allocation needed
    allocate(character(len=MAX_LINE_LEN) :: state%menu_prefix)
    allocate(character(len=256) :: state%selected_process_name)
#endif

    ! menu_items and menu_prompt are now fixed-length, no allocation needed

    ! Initialize all strings to empty
#ifdef USE_MEMORY_POOL
    ! CHUNK 2: Initialize pooled refs to empty
    state%buffer_ref%data = ''
    state%original_buffer_ref%data = ''
    state%kill_buffer_ref%data = ''
    state%last_completion_buffer_ref%data = ''
    state%search_string_ref%data = ''
    state%vi_command_buffer_ref%data = ''
    state%vi_yank_buffer_ref%data = ''
    state%vi_search_pattern_ref%data = ''
    state%menu_prefix_ref%data = ''
    state%selected_process_name_ref%data = ''
#else
#ifdef USE_C_STRINGS
    ! Initialize C string buffers to empty
    call c_string_clear(state%buffer_c)
    call c_string_clear(state%original_buffer_c)
    call c_string_clear(state%kill_buffer_c)
    call c_string_clear(state%last_completion_buffer_c)
    state%search_string = ''
    state%vi_command_buffer = ''
    state%vi_yank_buffer = ''
    state%vi_search_pattern = ''
    state%menu_prefix = ''
    state%selected_process_name = ''
#else
#ifdef USE_MEMORY_POOL
    state%buffer_ref%data = ''
#else
    state%buffer = ''
#endif
#ifdef USE_MEMORY_POOL
    state%original_buffer_ref%data = ''
#else
    state%original_buffer = ''
#endif
#ifdef USE_MEMORY_POOL
    state%kill_buffer_ref%data = ''
#else
    state%kill_buffer = ''
#endif
#ifdef USE_MEMORY_POOL
    state%last_completion_buffer_ref%data = ''
#else
    state%last_completion_buffer = ''
#endif
#endif  ! USE_C_STRINGS
#ifdef USE_MEMORY_POOL
    state%search_string_ref%data = ''
#else
    state%search_string = ''
#endif
#ifdef USE_MEMORY_POOL
    state%vi_command_buffer_ref%data = ''
#else
    state%vi_command_buffer = ''
#endif
#ifdef USE_MEMORY_POOL
    state%vi_yank_buffer_ref%data = ''
#else
    state%vi_yank_buffer = ''
#endif
#ifdef USE_MEMORY_POOL
    state%vi_search_pattern_ref%data = ''
#else
    state%vi_search_pattern = ''
#endif
#ifdef USE_MEMORY_POOL
    state%menu_prefix_ref%data = ''
#else
    state%menu_prefix = ''
#endif
#ifdef USE_MEMORY_POOL
    state%selected_process_name_ref%data = ''
#else
    state%selected_process_name = ''
#endif
#endif  ! Close USE_C_STRINGS/MEMORY_POOL buffer initialization
    ! These are fixed-length, initialize regardless of pooling
    state%suggestion = ''
    state%menu_prompt = ''
    state%menu_items = ''

    ! Initialize numeric fields
    state%length = 0
    state%cursor_pos = 0
    state%history_pos = 0
    state%kill_length = 0
    state%search_length = 0
    state%search_match_index = 0
    state%editing_mode = global_editing_mode
    state%vi_mode = VI_MODE_INSERT
    state%vi_command_count = 0
    state%vi_yank_length = 0
    state%vi_marks = 0
    state%vi_search_length = 0
    state%suggestion_length = 0
    state%menu_num_items = 0
    state%menu_total_items = 0
    state%menu_selection = 1
    state%menu_prefix_len = 0
    state%menu_row_start = 1
    state%menu_disclosed = .false.
    state%menu_visible_rows = 0
    state%menu_drawn_lines = 0
    state%selected_pid = 0

    ! Initialize logical fields
    state%dirty = .false.
    state%in_history = .false.
    state%completions_shown = .false.
    state%in_search = .false.
    state%search_forward = .false.
    state%vi_repeat_pending = .false.
    state%vi_search_forward = .true.
    state%vi_in_vi_search = .false.
    state%in_menu_select = .false.
    state%skip_cursor_up_on_redraw = .false.
    state%in_process_kill_mode = .false.
    state%in_signal_input = .false.

    ! Set initialized flag
    state%initialized = .true.
  end subroutine

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

  ! Clean up input_state_t allocations
  subroutine cleanup_input_state(state)
    type(input_state_t), intent(inout) :: state

    if (state%initialized) then
#ifdef USE_MEMORY_POOL
      ! Release pooled memory with dashboard tracking
      call pool_release_string(state%buffer_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%original_buffer_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%kill_buffer_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%last_completion_buffer_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%search_string_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%vi_command_buffer_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%vi_yank_buffer_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%vi_search_pattern_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%menu_prefix_ref)
      call dashboard_track_deallocation(MOD_READLINE, MAX_LINE_LEN, 3)

      call pool_release_string(state%selected_process_name_ref)
      call dashboard_track_deallocation(MOD_READLINE, 256, 2)
#elif defined(USE_C_STRINGS)
      ! Destroy C string buffers
      call c_string_destroy(state%buffer_c)
      call c_string_destroy(state%original_buffer_c)
      call c_string_destroy(state%kill_buffer_c)
      call c_string_destroy(state%last_completion_buffer_c)
      if (allocated(state%search_string)) deallocate(state%search_string)
      if (allocated(state%vi_command_buffer)) deallocate(state%vi_command_buffer)
      if (allocated(state%vi_yank_buffer)) deallocate(state%vi_yank_buffer)
      if (allocated(state%vi_search_pattern)) deallocate(state%vi_search_pattern)
      if (allocated(state%menu_prefix)) deallocate(state%menu_prefix)
      if (allocated(state%selected_process_name)) deallocate(state%selected_process_name)
#else
      ! CHUNK 2: Only deallocate allocatable strings when NOT using pooling
      ! Deallocate strings
      if (allocated(state%buffer)) deallocate(state%buffer)
      if (allocated(state%original_buffer)) deallocate(state%original_buffer)
      if (allocated(state%kill_buffer)) deallocate(state%kill_buffer)
      if (allocated(state%last_completion_buffer)) deallocate(state%last_completion_buffer)
      if (allocated(state%search_string)) deallocate(state%search_string)
      if (allocated(state%vi_command_buffer)) deallocate(state%vi_command_buffer)
      if (allocated(state%vi_yank_buffer)) deallocate(state%vi_yank_buffer)
      if (allocated(state%vi_search_pattern)) deallocate(state%vi_search_pattern)
      ! suggestion is now fixed-length, no deallocation needed
      if (allocated(state%menu_prefix)) deallocate(state%menu_prefix)
      if (allocated(state%selected_process_name)) deallocate(state%selected_process_name)
      ! menu_items and menu_prompt are now fixed-length, no deallocation needed
#endif
      state%initialized = .false.
    end if
  end subroutine

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

  subroutine set_global_fuzzy_complete(enabled)
    logical, intent(in) :: enabled
    global_fuzzy_complete = enabled
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

#ifdef __APPLE__
  ! Safe terminal size detection for macOS (avoids get_terminal_size crash on flang-new)
  subroutine safe_get_terminal_size(rows, cols)
    integer, intent(out) :: rows, cols
    integer :: r, c
    logical :: ok

    ! Default fallback values
    cols = 80
    rows = 24

    ! Native ioctl via the C helper — no `tput` subprocess, and safe on
    ! flang-new (the ioctl runs in C, not the crashing Fortran c_loc path).
    ok = get_term_size_native(r, c)
    if (ok) then
      if (c > 0 .and. c < 500) cols = c
      if (r > 0 .and. r < 500) rows = r
    end if
  end subroutine safe_get_terminal_size
#endif

  ! Enhanced readline with character-by-character input processing
  subroutine readline_enhanced(prompt, line, iostat, rprompt, keep_raw)
    use signal_handler, only: g_terminal_resized
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat
    character(len=*), intent(in), optional :: rprompt  ! Right-side prompt (like zsh)
    logical, intent(in), optional :: keep_raw  ! Don't restore terminal on exit (for continuation)

    ! Use module-level module_input_state directly (avoids flang-new pointer corruption bug)
    character :: ch
    logical :: success, done, raw_enabled
    integer :: char_code
    ! Variables for redraw (moved out of block to avoid flang-new crash)
    integer :: i_redraw, term_cols, term_rows
    integer :: move_up_rows  ! prompt rows + physical wrap row, for redraw move-up
    integer :: prompt_visual_len, cursor_visual_pos, current_line
    integer :: suggestion_display_len, available_space
    integer :: current_col, current_row
    integer :: nav_cursor_row  ! Saved current_row for cursor-up navigation
    integer :: highlighted_len  ! Actual length of highlighted string
    integer :: sel_start, sel_end  ! Selection byte range for Sprint 2 rendering
    logical :: defer_redraw  ! Coalesce: skip redraw while more input is queued
    logical :: submit_pending  ! Normal Enter: defer the newline until after the
                               ! in-place redraw (clears paste highlight first)
    integer :: first_diff_byte, diff_row, diff_col  ! Phase 2/3 diff
    integer :: last_sgr_start, last_sgr_end, sgr_scan, sgr_esc_end  ! SGR restore
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction
    ! Variables for UTF-8 support (moved out of block to avoid flang-new crash)
    character(len=4) :: utf8_char
    integer :: utf8_num_bytes, utf8_i
    logical :: debug_utf8
    integer :: debug_stat
    ! Variables for RPROMPT (right-side prompt)
    integer :: rprompt_visual_len, padding_needed
    logical :: rprompt_displayed
    ! Variables for multiline prompt support
    integer :: prompt_line_count

    ! Check if UTF-8 debug mode is enabled
    call get_environment_variable('FORTSH_DEBUG_UTF8', status=debug_stat)
    debug_utf8 = (debug_stat == 0)

    ! Initialize module-level input_state on first use (avoids flang-new pointer corruption bug)
    if (.not. module_input_state_initialized) then
      ! Initialize input state with allocated strings (only on first use)
      call init_input_state(module_input_state)
      ! Initialize syntax highlighting
      call init_syntax_highlighting()
      ! Probe for system clipboard tool (Sprint 5 — pattern #19: once at init)
      call clipboard_detect()
      module_input_state_initialized = .true.
    else
      ! On subsequent calls, just reset the buffer and cursor
#ifdef USE_C_STRINGS
      call state_buffer_clear(module_input_state)
#elif defined(USE_MEMORY_POOL)
      ! Check if buffer_ref is still valid, reinitialize if not.
      ! Command execution invalidates the string pool, so this is the
      ! NORMAL path between commands. The kill ring and vi yank register
      ! contents live in module-level session storage (session_kill_buffer
      ! / session_vi_yank) and survive on their own; only their per-state
      ! length companions would be wiped by init, so carry those over.
      if (.not. associated(module_input_state%buffer_ref%data)) then
        block
          integer :: saved_kill_len, saved_vi_len
          saved_kill_len = module_input_state%kill_length
          saved_vi_len = module_input_state%vi_yank_length
          call init_input_state(module_input_state)
          module_input_state%kill_length = saved_kill_len
          module_input_state%vi_yank_length = saved_vi_len
        end block
      else
        call state_buffer_clear(module_input_state)
      end if
#else
      call state_buffer_clear(module_input_state)
#endif
      module_input_state%length = 0
      module_input_state%cursor_pos = 0
      module_input_state%history_pos = 0
      module_input_state%in_menu_select = .false.
      module_input_state%in_search = .false.
      module_input_state%in_process_kill_mode = .false.
      module_input_state%in_signal_input = .false.
      ! Sync editing mode from global (set -o vi / set -o emacs)
      module_input_state%editing_mode = global_editing_mode
    end if

    ! Initialize variables
    iostat = 0
    done = .false.
    submit_pending = .false.
    raw_enabled = .false.
    highlighted_len = 0
    prev_diff_valid = .false.
    prev_render_valid = .false.

    ! Initialize history on first use
    call init_history()


    ! Try to enable raw mode (only works in interactive mode)
    ! If already in raw mode (keep_raw from previous call), skip re-enabling
    ! to avoid overwriting module_original_termios with the raw state
    if (module_termios_saved) then
      ! Already have saved original termios and raw mode is active
      raw_enabled = .true.
    else
      success = enable_raw_mode(module_original_termios)
      if (success) then
        raw_enabled = .true.
        module_termios_saved = .true.
      end if
    end if


    ! Print prompt (and RPROMPT if provided)
    prompt_visual_len = visual_length(prompt)
    if (prompt_visual_len < 0) prompt_visual_len = 0

    ! Count newlines in prompt for multiline prompt support
    prompt_line_count = 0
    do i_redraw = 1, len_trim(prompt)
      if (prompt(i_redraw:i_redraw) == char(10)) prompt_line_count = prompt_line_count + 1
    end do
    ! Get terminal width for RPROMPT positioning
    success = get_terminal_size(term_rows, term_cols)
    if (.not. success) term_cols = 80  ! Default fallback

    ! Check if we have RPROMPT and enough space
    ! Note: multi-line prompt RPROMPT is handled in fortsh.f90 by embedding into the prompt string
    rprompt_displayed = .false.
    if (present(rprompt) .and. len_trim(rprompt) > 0) then
      rprompt_visual_len = visual_length(rprompt)
      if (rprompt_visual_len < 0) rprompt_visual_len = 0

      ! Single-line prompt: place RPROMPT on same line
      padding_needed = term_cols - prompt_visual_len - 1 - rprompt_visual_len

      if (padding_needed >= 4) then  ! Minimum 4 chars gap
        rprompt_displayed = .true.
        write(output_unit, '(a)', advance='no') prompt
        write(output_unit, '(a)', advance='no') ' '

        ! Save cursor position before printing RPROMPT
        write(output_unit, '(a)', advance='no') char(27) // '7'

        ! Print padding to right-align RPROMPT
        do i_redraw = 1, padding_needed - 1
          write(output_unit, '(a)', advance='no') ' '
        end do

        ! Print RPROMPT
        write(output_unit, '(a)', advance='no') trim(rprompt)

        ! Restore cursor position (back to after prompt + space)
        write(output_unit, '(a)', advance='no') char(27) // '8'
      else
        ! Not enough space - just print prompt normally
        write(output_unit, '(a)', advance='no') prompt
        write(output_unit, '(a)', advance='no') ' '
      end if
    else
      ! No RPROMPT - just print prompt
      ! In raw mode, bare LF doesn't CR — replace with CR+LF for multi-line prompts
      block
        integer :: pr_i
        do pr_i = 1, len_trim(prompt)
          if (prompt(pr_i:pr_i) == char(10)) then
            write(output_unit, '(a)', advance='no') char(13) // char(10)  ! CR+LF
          else
            write(output_unit, '(a)', advance='no') prompt(pr_i:pr_i)
          end if
        end do
      end block
      write(output_unit, '(a)', advance='no') ' '  ! Space after prompt
    end if

    flush(output_unit)

    module_input_state%menu_prompt = prompt  ! Store prompt for menu mode, live preview, and FZF functions

    ! Initialize cursor screen position tracking. Use the SAME computation
    ! the redraw uses (cursor_get_row_col), so module_cursor_screen_row holds
    ! the wrap-row convention (rows below the last prompt line, excluding
    ! prompt newlines) consistently from the first redraw. Setting it to
    ! prompt_line_count here used a different (inclusive) convention, which
    ! made the first full redraw's move-up over-count by prompt_line_count
    ! and repaint a wrapped line from the wrong origin.
    call cursor_get_row_col(prompt, 0, term_cols, &
                            module_cursor_screen_row, module_cursor_screen_col)


    ! Log readline state
    if (raw_enabled) then
      ! Enhanced input processing
      do while (.not. done)
        ! Handle terminal resize BEFORE reading input. read_utf8_char
        ! returns every 100ms on poll timeout, so this fires promptly.
        if (g_terminal_resized) then
          g_terminal_resized = .false.
          rprompt_displayed = .false.
          prev_diff_valid = .false.
          prev_render_valid = .false.

          block
            integer :: old_cols, reflow_rows, up_i
            old_cols = term_cols

            success = get_terminal_size(term_rows, term_cols)
            if (.not. success) then
              term_cols = 80; term_rows = 24
            end if

            ! Update COLUMNS/LINES env vars so $COLUMNS/$LINES reflect
            ! the new size immediately, not just at the next prompt.
            block
              character(len=16) :: cols_s, rows_s
              write(cols_s, '(I0)') term_cols
              write(rows_s, '(I0)') term_rows
              success = set_environment_var('COLUMNS', trim(cols_s))
              success = set_environment_var('LINES', trim(rows_s))
            end block

            reflow_rows = (old_cols + term_cols - 1) / term_cols &
                          + prompt_line_count
            do up_i = 1, reflow_rows
              write(output_unit, '(a)', advance='no') char(27) // '[A'
            end do
            write(output_unit, '(a)', advance='no') char(13)
            write(output_unit, '(a)', advance='no') char(27) // '[J'
            flush(output_unit)
          end block

          prompt_visual_len = visual_length(prompt)
          if (prompt_visual_len < 0) prompt_visual_len = 0
          prompt_line_count = 0
          block
            integer :: pr_i2
            do pr_i2 = 1, len_trim(prompt)
              if (prompt(pr_i2:pr_i2) == char(10)) prompt_line_count = prompt_line_count + 1
            end do
          end block

          module_cursor_screen_row = 0
          module_cursor_screen_col = 0
          module_input_state%skip_cursor_up_on_redraw = .true.
          module_input_state%dirty = .true.
          cycle  ! repaint via the dirty-redraw block below
        end if

        ! Read a complete UTF-8 character (1-4 bytes)
        success = read_utf8_char(utf8_char, utf8_num_bytes)
        if (.not. success) then
          iostat = -1
          exit
        end if
        ! Poll timeout (no input within 100ms) — cycle back to check
        ! for signals, but let dirty redraws (e.g. post-resize) through.
        if (utf8_num_bytes == 0) then
          if (module_input_state%dirty) then
            goto 500  ! jump to redraw block
          end if
          cycle
        end if

        ! Fish-style paste highlight clears on the next key. The bracketed-paste
        ! handler re-arms it after inserting, so clearing here (before dispatch)
        ! correctly leaves it lit only until the user's next keystroke/motion.
        if (module_input_state%paste_hl_active) then
          module_input_state%paste_hl_active = .false.
          module_input_state%dirty = .true.
          ! The previous frame was rendered WITH the reverse-video highlight.
          ! A cursor-only key must not take the Phase-1 "just move the
          ! cursor" shortcut, or the highlight stays on screen — the
          ! Phase-1 guard checks paste_hl_active after this clear, so it
          ! can't catch this itself. Also invalidate the render frame so
          ! the redraw does a CLEAN full repaint from the prompt origin,
          ! not a Phase-2/3 partial diff against the stale highlighted
          ! frame — that partial diff navigates to the first-changed byte
          ! and, on a wrapped line where the cursor also jumped, repaints
          ! from the wrong row (duplicated wrapped line).
          prev_diff_valid = .false.
          prev_render_valid = .false.
        end if

        ! If multi-byte UTF-8 character, insert all bytes with correct visual width
        if (utf8_num_bytes > 1) then
          ! In search mode, ignore multi-byte characters (search uses ASCII only)
          if (module_input_state%in_search) cycle
          ! Cancel prefix search on any typed character
          if (module_input_state%in_prefix_search) call cancel_prefix_search(module_input_state)
          ! Completion menu handling mirrors the single-byte path: typing
          ! while navigating accepts the selection (space-separated), typing
          ! with the menu merely shown dismisses it
          if (module_input_state%in_menu_select) then
            if (module_input_state%in_process_kill_mode) then
              call exit_menu_select_mode(module_input_state)
              module_input_state%in_process_kill_mode = .false.
            else
              call accept_menu_selection(module_input_state)
              if (module_input_state%length > 0) then
                call state_buffer_get(module_input_state, temp_buf)
                if (temp_buf(module_input_state%length:module_input_state%length) /= '/') then
                  call insert_char_wrapper(module_input_state, ' ')
                end if
              end if
            end if
          else if (module_input_state%completions_shown .and. &
                   module_input_state%menu_num_items > 0) then
            call exit_menu_select_mode(module_input_state)
          end if
          ! Multi-byte UTF-8 character (emoji, CJK, etc.)
          ! Determine visual width: 3-4 byte UTF-8 is always 2-wide, 2-byte varies
          if (utf8_num_bytes >= 3) then
            utf8_i = 2  ! Visual width for 3-4 byte UTF-8 (emoji, CJK)
          else
            utf8_i = utf8_char_width(utf8_char(1:1))  ! 2-byte can be 1 or 2
          end if
          call insert_utf8_char(module_input_state, utf8_char(1:utf8_num_bytes), utf8_num_bytes, utf8_i)
          cycle  ! Skip the control character processing below
        end if

        ! Single-byte character - process normally
        ch = utf8_char(1:1)
        char_code = iachar(ch)

        ! Log every character received
        if (char_code == 27) then
        else if (char_code < 32 .or. char_code == 127) then
        end if

        ! Cancel prefix search on any key except escape (arrows handled inside escape handler)
        if (module_input_state%in_prefix_search .and. char_code /= KEY_ESC) then
          call cancel_prefix_search(module_input_state)
        end if

        ! Completion menu state machine, centralized (fish pager behavior).
        ! With the table drawn the physical cursor is parked below it, so
        ! any key path that redraws from line state corrupts the display
        ! unless the table is taken down first.
        ! - Drawn but not entered: TAB enters it (tab handler), arrows
        !   enter it (escape handler), Enter erases it before submitting
        !   (enter handler); every other key dismisses it, then acts on
        !   the line normally.
        ! - Entered (in_menu_select): TAB/Enter/arrows/ESC navigate or
        !   accept (menu handlers), printable chars accept-and-continue
        !   (32:126 case); any other control key exits the menu first.
        if (.not. module_input_state%in_signal_input .and. &
            .not. module_input_state%in_search .and. &
            module_input_state%menu_num_items > 0 .and. &
            char_code /= KEY_TAB .and. char_code /= KEY_ESC .and. &
            char_code /= KEY_ENTER .and. char_code /= 13) then
          if (.not. module_input_state%in_menu_select) then
            if (module_input_state%completions_shown) then
              call exit_menu_select_mode(module_input_state)
            end if
          else if (char_code < 32 .or. char_code == 127) then
            call exit_menu_select_mode(module_input_state)
            module_input_state%in_process_kill_mode = .false.
          end if
        end if

        select case(char_code)
        case(KEY_ENTER)
          ! Enter - accept menu selection, finish input, or accept search
          if (module_input_state%in_signal_input) then
            ! Send signal to selected process
            write(output_unit, '()')  ! New line
            call send_signal_to_process(module_input_state)
            ! Exit signal mode and return to normal prompt
            module_input_state%in_signal_input = .false.
            module_input_state%in_process_kill_mode = .false.
            call state_buffer_clear(module_input_state)
            module_input_state%length = 0
            module_input_state%cursor_pos = 0
            done = .true.
          else if (module_input_state%in_process_kill_mode .and. module_input_state%in_menu_select) then
            ! Select process from menu
            call handle_process_selection(module_input_state)
          else if (module_input_state%in_menu_select) then
            call handle_menu_navigation(module_input_state, KEY_ENTER, done)
            ! If menu selection was accepted, output newline
            if (done) then
              write(output_unit, '()')  ! New line
            end if
          else if (module_input_state%in_search) then
            ! Accept search result and execute immediately (bash behavior)
            call accept_search(module_input_state, prompt)
            write(output_unit, '(a)', advance='no') char(13) // char(10)
            flush(output_unit)
            done = .true.
          else if (module_input_state%completions_shown .and. &
                   module_input_state%menu_num_items > 0) then
            ! Table drawn but not entered: erase it before submitting so it
            ! doesn't linger above the output (fish behavior). This leaves the
            ! cursor on the command line row with the screen below cleared, so
            ! submit immediately with an inline newline — no deferred redraw
            ! (a redraw here would repaint over the just-cleared region).
            call clear_menu_display_below(module_input_state)
            module_input_state%suggestion_length = 0
            write(output_unit, '(a)', advance='no') char(13) // char(10)
            flush(output_unit)
            done = .true.
          else
            ! Normal submit. Clear shadow text (suggestion) from cursor to end
            ! of line, then DEFER the newline: if the line is still dirty (a
            ! paste whose reverse-video highlight must be cleared), the redraw
            ! block below repaints it un-highlighted IN PLACE first, and the
            ! deferred newline (emitted after that block) then moves below the
            ! clean line. Emitting the newline here would either repaint on top
            ! of the command output or strand the highlight in scrollback.
            if (module_input_state%suggestion_length > 0) then
              write(output_unit, '(a)', advance='no') char(27) // '[K'
            end if
            submit_pending = .true.
            done = .true.
          end if

        case(KEY_CTRL_D)
          ! Ctrl+D - EOF on empty line, forward delete on non-empty (bash behavior)
          if (.not. module_input_state%in_search .and. module_input_state%length == 0) then
            iostat = -1
            done = .true.
          else if (.not. module_input_state%in_search) then
            call handle_forward_delete_char(module_input_state)
          end if

        case(KEY_CTRL_C)
          ! Ctrl+C - cancel and clear line (bash-compatible)
          if (module_input_state%in_search) then
            ! Clean up the search status line first
            call cleanup_search_status_line()
            module_input_state%in_search = .false.
            call clear_search_string(module_input_state)
            module_input_state%search_length = 0
            module_input_state%search_match_index = 0
          end if

          ! Move to beginning, clear line, print ^C on new line
          write(output_unit, '(a)', advance='no') ESC_MOVE_BOL // ESC_CLEAR_LINE
          write(output_unit, '(a)') '^C'

          ! Clear buffer and return empty line
          module_input_state%length = 0
          module_input_state%cursor_pos = 0
          module_input_state%dirty = .false.  ! Prevent redraw with empty buffer
          done = .true.

        case(KEY_CTRL_X)
          ! Ctrl+X — dual-mode (Sprint 5):
          !   1. If a selection is active, CUT (same as Ctrl+W on selection:
          !      copy to kill buffer + system clipboard, then delete range).
          !   2. Otherwise, enter process kill mode (existing behavior).
          if (module_input_state%selection_active) then
            call copy_selection_to_kill_buffer(module_input_state)
            call delete_selection(module_input_state)
            call update_autosuggestion(module_input_state)
          else if (.not. module_input_state%in_search .and. &
              .not. module_input_state%in_process_kill_mode) then
            call enter_process_kill_mode(module_input_state)
          end if

        case(KEY_BACKSPACE)
          ! Backspace
          if (module_input_state%in_signal_input) then
            ! For signal mode, delete last char and update display
            if (module_input_state%length > 0) then
              module_input_state%length = module_input_state%length - 1
              module_input_state%cursor_pos = module_input_state%length
              call update_signal_display(module_input_state)
            end if
          else if (module_input_state%in_search) then
            ! For search mode, delete last search char and re-search
            call search_backspace(module_input_state, prompt)
          else
            call handle_backspace(module_input_state)
          end if
          
        case(KEY_TAB)
          ! No-op in search mode
          if (module_input_state%in_search) then
            continue
          else
            ! Initialize test mode if needed
            if (.not. test_mode_initialized) call init_test_mode()

            ! Skip completion if explicitly disabled (FORTSH_NO_COMPLETION=1)
            if (completion_disabled) then
              ! Completion disabled - do nothing
              continue
            else if (module_input_state%in_menu_select) then
              call handle_menu_navigation(module_input_state, KEY_TAB, done)
            else
              ! Call separate subroutine to work around macOS ARM64 crash
              call handle_tab_key_separate(module_input_state)
              ! All completion logic is now handled in the separate subroutine
            end if
          end if

        case(KEY_ESC)
          ! Escape sequence - parse it (will route to menu if needed)
          call handle_escape_sequence(module_input_state, done, prompt)
          
        case(KEY_CTRL_A)
          ! Home - no-op in search mode
          if (.not. module_input_state%in_search) call handle_home(module_input_state)

        case(KEY_CTRL_E)
          ! End - no-op in search mode
          if (.not. module_input_state%in_search) call handle_end(module_input_state)

        case(KEY_CTRL_F)
          ! FZF file browser - no-op in search mode
          if (.not. module_input_state%in_search) then
            call launch_fzf_file_browser(module_input_state, prompt)
          end if

        case(KEY_CTRL_B)
          ! Backward character - no-op in search mode
          if (.not. module_input_state%in_search) call handle_cursor_left(module_input_state)

        case(KEY_CTRL_K)
          ! Kill to end of line - no-op in search mode
          if (.not. module_input_state%in_search) then
            if (module_input_state%in_menu_select) then
              call exit_menu_select_mode(module_input_state)
            end if
            call handle_kill_to_end(module_input_state)
          end if

        case(KEY_CTRL_U)
          if (module_input_state%in_search) then
            ! Clear search query and restore original buffer
            call search_clear_query(module_input_state, prompt)
          else
            ! Kill to beginning of line (exit menu mode first if active)
            if (module_input_state%in_menu_select) then
              call exit_menu_select_mode(module_input_state)
            end if
            call handle_kill_line(module_input_state)
          end if

        case(KEY_CTRL_W)
          if (module_input_state%in_search) then
            ! Delete last word from search query
            call search_kill_word(module_input_state, prompt)
          else
            ! Kill previous word (exit menu mode first if active)
            if (module_input_state%in_menu_select) then
              call exit_menu_select_mode(module_input_state)
            end if
            call handle_kill_word(module_input_state)
          end if
          
        case(KEY_CTRL_V)
          ! Ctrl+V — paste (Sprint 5). Reads from the system clipboard
          ! first; falls back to the in-session kill_buffer if no
          ! clipboard tool is available or the clipboard is empty.
          ! If a selection is active, it's deleted first (paste-over).
          if (.not. module_input_state%in_search) call handle_paste(module_input_state)

        case(KEY_CTRL_Y)
          ! Yank - no-op in search mode
          if (.not. module_input_state%in_search) call handle_yank(module_input_state)

        case(KEY_CTRL_L)
          ! Clear screen
          if (.not. module_input_state%in_search .and. &
              .not. module_input_state%in_menu_select) then
            call handle_clear_screen(module_input_state, prompt)
          end if

        case(KEY_CTRL_R)
          ! Reverse-i-search
          call handle_isearch(module_input_state, prompt, .false.)
        case(KEY_CTRL_S)
          ! Forward-i-search
          call handle_isearch(module_input_state, prompt, .true.)

        case(KEY_CTRL_G)
          ! Cancel search if active - restore original buffer and continue editing
          if (module_input_state%in_search) then
            call cancel_search(module_input_state)
          end if

        case(KEY_CTRL_H)
          ! FZF history browser - no-op in search mode
          if (.not. module_input_state%in_search) then
            call launch_fzf_history_browser(module_input_state, prompt)
          end if

        case(KEY_CTRL_P)
          ! Previous history (emacs binding, like Up arrow)
          if (.not. module_input_state%in_search) then
            call handle_history_up(module_input_state)
          end if

        case(KEY_CTRL_N)
          ! Next history (emacs binding, like Down arrow)
          if (.not. module_input_state%in_search) then
            call handle_history_down(module_input_state)
          end if

        case(KEY_CTRL_T)
          ! Transpose characters - no-op in search mode
          if (.not. module_input_state%in_search) call handle_transpose_chars(module_input_state)

        case(32:126)
          ! Regular printable characters
          if (module_input_state%in_signal_input) then
            ! Handle signal input for process kill
            call handle_signal_input(module_input_state, ch)
          else if (module_input_state%in_menu_select) then
            if (module_input_state%in_process_kill_mode) then
              ! Process menu: typing cancels it and edits the line
              call exit_menu_select_mode(module_input_state)
              module_input_state%in_process_kill_mode = .false.
              call insert_char_wrapper(module_input_state, ch)
            else
              ! Typing while navigating the menu accepts the selected item,
              ! then the typed character continues the line, space-separated
              ! (fish appends a space after non-directory completions)
              call accept_menu_selection(module_input_state)
              if (module_input_state%length > 0) then
                call state_buffer_get(module_input_state, temp_buf)
                if (temp_buf(module_input_state%length:module_input_state%length) /= '/') then
                  call insert_char_wrapper(module_input_state, ' ')
                end if
              end if
              call insert_char_wrapper(module_input_state, ch)
            end if
          else if (module_input_state%in_search) then
            call search_add_char(module_input_state, ch, prompt)
          else if (module_input_state%editing_mode == EDITING_MODE_VI .and. &
                   module_input_state%vi_mode == VI_MODE_COMMAND) then
            ! In Vi command mode - route to command handler
            call handle_vi_command_mode(module_input_state, char_code)
            ! Check if we switched back to insert mode
            if (module_input_state%vi_mode == VI_MODE_INSERT) then
              call handle_vi_mode_switch(module_input_state, char_code)
            end if
          else
            call insert_char_wrapper(module_input_state, ch)
          end if

        case default
          ! Ignore other control characters for now
        end select


        ! Coalesce input bursts (paste / fast typing): if bytes are already
        ! queued on stdin, defer the redraw and loop to consume them, so the
        ! whole burst lands in ONE frame (like bash/zsh) instead of redrawing
        ! per character. dirty stays set, so the draw happens on the first
        ! drained iteration. Never defer when the line is being submitted
        ! (done) or in modes that own their own display.
        defer_redraw = .false.
        if (module_input_state%dirty .and. .not. done .and. &
            .not. module_input_state%in_menu_select .and. &
            .not. module_input_state%in_search) then
          if (input_pending()) defer_redraw = .true.
        end if

        ! Redraw line if needed
500     continue
        ! INLINE redraw to avoid gfortran bug on macOS with large derived types
        ! Skip redraw when in menu selection mode - menu handles its own display
        ! In test mode, skip full redraw to avoid polluting PTY output
        ! Skip when a done-setting key already emitted its own newline (Ctrl-C,
        ! search accept, menu submit, EOF): a redraw here would repaint the
        ! command line BELOW that newline, on top of the command output. The
        ! normal Enter submit is the exception — it sets submit_pending and
        ! defers its newline to AFTER this block, so the redraw runs IN PLACE
        ! first (repainting un-highlighted, clearing a paste's reverse-video),
        ! then the deferred newline moves below the clean line.
        if (.not. test_mode_initialized) call init_test_mode()
        if (module_input_state%dirty .and. .not. defer_redraw .and. &
            (.not. done .or. submit_pending) .and. &
            .not. module_input_state%in_menu_select .and. .not. test_mode_enabled) then
          ! Search mode: delegate to two-line search display instead of normal redraw
          if (module_input_state%in_search) then
            call update_search_display(module_input_state, prompt)
            module_input_state%dirty = .false.
            cycle
          end if

          ! Display diffing (Phase 1): skip full clear+redraw when content
          ! unchanged and only the cursor moved. Emit cursor-movement escapes
          ! instead (~6 bytes vs ~700 bytes per keystroke).
          if (prev_diff_valid .and. &
              .not. module_input_state%selection_active .and. &
              .not. module_input_state%paste_hl_active .and. &
              .not. module_input_state%in_prefix_search .and. &
              module_input_state%length == prev_diff_buf_len .and. &
              module_input_state%suggestion_length == prev_diff_suggest_len) then
            call state_buffer_get(module_input_state, temp_buf)
            if (module_input_state%length == 0 .or. &
                temp_buf(:module_input_state%length) == &
                prev_diff_content(:prev_diff_buf_len)) then
              if (module_input_state%cursor_pos == prev_diff_cursor_pos) then
                module_input_state%dirty = .false.
                cycle
              end if
              if (prev_diff_suggest_len == 0 .or. &
                  (prev_diff_cursor_pos /= prev_diff_buf_len .and. &
                   module_input_state%cursor_pos /= module_input_state%length)) then
                call cursor_get_row_col(prompt, module_input_state%cursor_pos, &
                                        term_cols, current_row, current_col)
                call cursor_move(module_cursor_screen_row, module_cursor_screen_col, &
                                 current_row, current_col)
                module_cursor_screen_row = current_row
                module_cursor_screen_col = current_col
                prev_diff_cursor_pos = module_input_state%cursor_pos
                module_input_state%dirty = .false.
                cycle
              end if
            end if
          end if

          ! WORKAROUND: Removed 'block' construct to avoid flang-new crash on macOS ARM64
          ! Variables moved to subroutine level

          ! Get terminal size for multiline handling
#ifdef __APPLE__
            ! WORKAROUND: the Fortran get_terminal_size (c_loc on winsize)
            ! crashes on flang-new; use the native C ioctl helper instead.
            call safe_get_terminal_size(term_rows, term_cols)
#else
            ! Linux: Use actual terminal size
            success = get_terminal_size(term_rows, term_cols)
            if (.not. success) then
              ! Fallback to reasonable defaults
              term_cols = 80
              term_rows = 24
            end if
#endif

            ! Calculate visual length of prompt (excluding ANSI codes)
            prompt_visual_len = visual_length(prompt)
            if (prompt_visual_len < 0) then
              prompt_visual_len = 0
            end if

            ! Cursor-up count: how many terminal rows from the cursor
            ! position back to the start of the prompt. For multi-line
            ! prompts, count only the last line's visual width for cursor
            ! math (earlier lines contribute prompt_line_count rows).
            ! The redraw strips ESC[nG RPROMPT content, so the visible
            ! prompt is just the base text — use last-line width only.
            block
              integer :: last_nl_pos, last_line_vis
              last_nl_pos = 0
              do i_redraw = 1, len_trim(prompt)
                if (prompt(i_redraw:i_redraw) == char(10)) last_nl_pos = i_redraw
              end do
              if (last_nl_pos > 0 .and. last_nl_pos < len_trim(prompt)) then
                last_line_vis = visual_length(prompt(last_nl_pos+1:len_trim(prompt)))
              else
                last_line_vis = prompt_visual_len
              end if
              if (last_line_vis < 0) last_line_vis = 0
              cursor_visual_pos = last_line_vis + 1 + module_input_state%cursor_pos
              current_row = prompt_line_count + cursor_visual_pos / term_cols
              if (rprompt_displayed) current_row = current_row + 1
            end block
            current_col = mod(cursor_visual_pos, term_cols)
            ! Calculate where start of prompt is (always row 0, col 0 of prompt line)
            ! === Buffered redraw: accumulate entire frame, write once ===
            ! This prevents ESC[J clear from rendering as a blank frame before
            ! the new content arrives, eliminating visible flashing.
            call rdraw_clear()

            ! Move cursor to start of prompt UNLESS we just exited menu mode.
            ! Move up by the PHYSICAL cursor row (module_cursor_screen_row,
            ! tracked from the previous render), NOT current_row (the row the
            ! NEW cursor_pos will land on). They're equal for an edit at the
            ! cursor, but a cursor JUMP that forces a full redraw (e.g. Home
            ! after a paste, where clearing the paste highlight invalidates the
            ! Phase-1 cursor-only path) leaves the physical cursor on a
            ! different row than current_row implies — using current_row then
            ! under/over-moves and repaints from the wrong origin (line
            ! duplication on wrapped input).
            ! Move up by the cursor's PHYSICAL row, not current_row. current_row
            ! is prompt_line_count + the NEW cursor_pos's wrap row; the physical
            ! cursor is at prompt_line_count + the OLD wrap row, tracked in
            ! module_cursor_screen_row (which counts wrap rows only, excluding
            ! prompt lines — same convention as cursor_get_row_col). They match
            ! for an edit at the cursor, but a cursor JUMP that forces a full
            ! redraw (Home after a paste: clearing the paste highlight
            ! invalidates the Phase-1 cursor-only path) leaves the physical
            ! cursor on a different wrap row than current_row implies, so using
            ! current_row repaints from the wrong origin (wrapped-line dup).
            ! (move_up_rows declared at subroutine scope — a 'block' construct
            ! here crashes flang-new on macOS ARM64; see other workarounds.)
            move_up_rows = prompt_line_count + module_cursor_screen_row
            if (.not. module_input_state%skip_cursor_up_on_redraw) then
              do i_redraw = 1, move_up_rows
                call rdraw_append(char(27) // '[A')
              end do
              call rdraw_append_char(char(13))
            else
              call rdraw_append_char(char(13))
            end if

            ! Clear the skip flag after using it
            module_input_state%skip_cursor_up_on_redraw = .false.

            ! Hide cursor during redraw
            call rdraw_append(ESC_HIDE_CURSOR)

            ! Clear from cursor to end of screen
            call rdraw_append(char(27) // '[J')

            ! Save cursor-up row count before content overwrites it
            nav_cursor_row = current_row

            ! Phase 2: mirror rendered content for line-level diff
            cframe_pos = 0
            rdraw_mirror = .true.

            ! Redraw prompt (replace bare LF with CR+LF for raw mode).
            ! Strip ESC[nG (cursor-column) escapes — these are embedded
            ! RPROMPT positioning from fortsh.f90 that becomes stale
            ! after a terminal resize and causes line duplication.
            block
              integer :: pr_j, pr_plen
              logical :: in_cg_esc
              pr_plen = len_trim(prompt)
              in_cg_esc = .false.
              pr_j = 1
              do while (pr_j <= pr_plen)
                if (prompt(pr_j:pr_j) == char(27) .and. pr_j + 1 <= pr_plen &
                    .and. prompt(pr_j+1:pr_j+1) == '[') then
                  ! Check if this is ESC[<digits>G (cursor column)
                  block
                    integer :: esc_end
                    esc_end = pr_j + 2
                    do while (esc_end <= pr_plen .and. &
                              prompt(esc_end:esc_end) >= '0' .and. &
                              prompt(esc_end:esc_end) <= '9')
                      esc_end = esc_end + 1
                    end do
                    if (esc_end <= pr_plen .and. prompt(esc_end:esc_end) == 'G') then
                      ! Skip this ESC[nG sequence and any RPROMPT text
                      ! up to the next newline (the RPROMPT content that
                      ! follows the cursor-position escape)
                      esc_end = esc_end + 1
                      do while (esc_end <= pr_plen .and. prompt(esc_end:esc_end) /= char(10))
                        esc_end = esc_end + 1
                      end do
                      pr_j = esc_end
                      cycle
                    else
                      ! Other ESC[ sequence — emit normally
                      call rdraw_append_char(prompt(pr_j:pr_j))
                      pr_j = pr_j + 1
                    end if
                  end block
                else if (prompt(pr_j:pr_j) == char(10)) then
                  call rdraw_append(char(13) // char(10))
                  pr_j = pr_j + 1
                else if (prompt(pr_j:pr_j) == char(0)) then
                  pr_j = pr_j + 1
                else
                  call rdraw_append_char(prompt(pr_j:pr_j))
                  pr_j = pr_j + 1
                end if
              end do
            end block
            call rdraw_append_char(' ')
            if (module_input_state%length > 0) then
              ! Try syntax highlighting
              call state_buffer_get(module_input_state, temp_buf)

              ! Selection rendering: three segments — plain, reverse-video, plain
              if (module_input_state%selection_active) then
                sel_start = min(module_input_state%selection_anchor, module_input_state%cursor_pos)
                sel_end   = max(module_input_state%selection_anchor, module_input_state%cursor_pos)
                if (sel_start < 0) sel_start = 0
                if (sel_end > module_input_state%length) sel_end = module_input_state%length
                if (sel_start > 0) then
                  call rdraw_append(temp_buf(1:sel_start))
                end if
                if (sel_end > sel_start) then
                  call rdraw_append(char(27) // '[7m')
                  call rdraw_append(temp_buf(sel_start+1:sel_end))
                  call rdraw_append(char(27) // '[27m')
                end if
                if (sel_end < module_input_state%length) then
                  call rdraw_append(temp_buf(sel_end+1:module_input_state%length))
                end if

              ! Paste highlight: just-pasted span in reverse video (fish-style).
              ! Mutually exclusive with selection (paste-over clears selection).
              else if (module_input_state%paste_hl_active) then
                sel_start = max(0, module_input_state%paste_hl_start)
                sel_end   = min(module_input_state%length, module_input_state%paste_hl_end)
                if (sel_start > 0) then
                  call rdraw_append(temp_buf(1:sel_start))
                end if
                if (sel_end > sel_start) then
                  call rdraw_append(char(27) // '[7m')
                  call rdraw_append(temp_buf(sel_start+1:sel_end))
                  call rdraw_append(char(27) // '[27m')
                end if
                if (sel_end < module_input_state%length) then
                  call rdraw_append(temp_buf(sel_end+1:module_input_state%length))
                end if

              ! Prefix search mode: prefix in reverse video + rest plain
              else if (module_input_state%in_prefix_search .and. &
                  (module_input_state%prefix_search_idx /= 0 .or. module_input_state%prefix_search_flash)) then
                call rdraw_append(char(27) // '[7m')
                do i_redraw = 1, module_input_state%prefix_search_len
                  call rdraw_append_char(temp_buf(i_redraw:i_redraw))
                end do
                call rdraw_append(char(27) // '[0m')
                if (module_input_state%prefix_search_flash) then
                  module_input_state%prefix_search_flash = .false.
                end if
                if (module_input_state%length > module_input_state%prefix_search_len) then
                  call rdraw_append(temp_buf(module_input_state%prefix_search_len+1:module_input_state%length))
                end if
              else
                call highlight_command_line(temp_buf(:module_input_state%length), &
                                            module_highlighted_buffer, module_highlighted_len, &
                                            module_input_state%length)
                if (module_highlighted_len > 0 .and. module_highlighted_len <= len(module_highlighted_buffer)) then
                  call rdraw_append(module_highlighted_buffer(:module_highlighted_len))
                else
                  call rdraw_append(temp_buf(:module_input_state%length))
                end if
              end if

              ! Display autosuggestion if present (only when cursor is at end)
              if (module_input_state%suggestion_length > 0 .and. &
                  module_input_state%cursor_pos == module_input_state%length) then
                cursor_visual_pos = prompt_visual_len + 1 + module_input_state%length

                if (term_cols > 0 .and. term_cols <= 500) then
                  current_col = mod(cursor_visual_pos, term_cols)
                  current_row = cursor_visual_pos / term_cols
                  if (current_col < 0) current_col = 0
                  if (current_col >= term_cols) current_col = term_cols - 1

                  available_space = term_cols - current_col
                  if (available_space < 0) available_space = 0
                  if (available_space > term_cols) available_space = 0

                  if (current_row == 0 .and. available_space >= 3) then
                    suggestion_display_len = min(module_input_state%suggestion_length, available_space - 2)
                    if (suggestion_display_len < 0) suggestion_display_len = 0
                    if (suggestion_display_len > MAX_LINE_LEN) suggestion_display_len = 0
                    if (suggestion_display_len > module_input_state%suggestion_length) suggestion_display_len = 0

                    if (suggestion_display_len >= 1) then
                      call rdraw_append(char(27) // '[90m')
                      do i_redraw = 1, suggestion_display_len
                        if (i_redraw <= MAX_LINE_LEN) then
                          call rdraw_append_char(module_input_state%suggestion(i_redraw:i_redraw))
                        end if
                      end do
                      call rdraw_append(char(27) // '[0m')
                      do i_redraw = 1, suggestion_display_len
                        call rdraw_append(char(27) // '[D')
                      end do
                    end if
                  end if
                end if
              end if
            end if

            ! Phase 2: stop mirroring, compare, conditionally rebuild
            rdraw_mirror = .false.

            ! Phase 2+3: find first differing byte, skip matching prefix
            first_diff_byte = 0
            if (prev_render_valid .and. cframe_pos > 0 .and. prev_render_len > 0) then
              do i_redraw = 1, min(cframe_pos, prev_render_len)
                if (content_frame(i_redraw:i_redraw) /= prev_render_frame(i_redraw:i_redraw)) then
                  first_diff_byte = i_redraw
                  exit
                end if
              end do
              if (first_diff_byte == 0 .and. cframe_pos /= prev_render_len) then
                first_diff_byte = min(cframe_pos, prev_render_len) + 1
              end if
              if (first_diff_byte > 0) then
                call adjust_diff_to_boundary(content_frame, cframe_pos, first_diff_byte)
                call content_byte_to_row_col(content_frame, cframe_pos, first_diff_byte, &
                                             term_cols, diff_row, diff_col)
                rdraw_pos = 0
                if (.not. module_input_state%skip_cursor_up_on_redraw) then
                  if (nav_cursor_row > 0) then
                    do i_redraw = 1, nav_cursor_row
                      call rdraw_append(char(27) // '[A')
                    end do
                  end if
                end if
                call rdraw_append(ESC_HIDE_CURSOR)
                if (diff_row > 0) then
                  do i_redraw = 1, diff_row
                    call rdraw_append(char(27) // '[B')
                  end do
                end if
                call rdraw_append_char(char(13))
                if (diff_col > 0) then
                  do i_redraw = 1, diff_col
                    call rdraw_append(char(27) // '[C')
                  end do
                end if
                call rdraw_append(char(27) // '[J')
                if (first_diff_byte <= cframe_pos) then
                  ! Restore ANSI attribute state: the terminal's SGR state
                  ! after cursor movement is whatever the PREVIOUS render
                  ! left (typically ESC[0m = reset), not what the content
                  ! expects at this byte. Find and re-emit the last SGR
                  ! sequence (ESC[...m) before first_diff_byte.
                  last_sgr_start = 0
                  last_sgr_end = 0
                  sgr_scan = 1
                  do while (sgr_scan < first_diff_byte)
                    if (content_frame(sgr_scan:sgr_scan) == char(27) .and. &
                        sgr_scan + 1 < first_diff_byte .and. &
                        content_frame(sgr_scan+1:sgr_scan+1) == '[') then
                      sgr_esc_end = sgr_scan + 2
                      do while (sgr_esc_end <= cframe_pos .and. &
                                .not. (iachar(content_frame(sgr_esc_end:sgr_esc_end)) >= 64 &
                                .and. iachar(content_frame(sgr_esc_end:sgr_esc_end)) <= 126))
                        sgr_esc_end = sgr_esc_end + 1
                      end do
                      if (sgr_esc_end <= cframe_pos .and. &
                          content_frame(sgr_esc_end:sgr_esc_end) == 'm') then
                        last_sgr_start = sgr_scan
                        last_sgr_end = sgr_esc_end
                      end if
                      sgr_scan = sgr_esc_end + 1
                    else
                      sgr_scan = sgr_scan + 1
                    end if
                  end do
                  if (last_sgr_start > 0) then
                    call rdraw_append(content_frame(last_sgr_start:last_sgr_end))
                  end if
                  call rdraw_append(content_frame(first_diff_byte:cframe_pos))
                end if
              end if
            end if

            prev_render_frame(1:cframe_pos) = content_frame(1:cframe_pos)
            prev_render_len = cframe_pos
            prev_render_valid = .true.

            ! Position cursor correctly (if not at end of input). The repaint
            ! left the cursor at the END of the content; move it back to the
            ! cursor position. On a WRAPPED line the cursor position can be on
            ! an earlier visual row than the end, so move UP by the row
            ! difference first, THEN horizontally — moving only left (the old
            ! behavior) stranded the cursor on the end's row.
            if (module_input_state%cursor_pos < module_input_state%length) then
              call cursor_get_row_col(prompt, module_input_state%length, term_cols, current_row, current_col)
              call cursor_get_row_col(prompt, module_input_state%cursor_pos, term_cols, cursor_visual_pos, i_redraw)
              ! Vertical: target row (cursor_visual_pos) <= end row (current_row)
              if (current_row > cursor_visual_pos) then
                do current_line = 1, current_row - cursor_visual_pos
                  call rdraw_append(char(27) // '[A')
                end do
              end if
              ! Horizontal: from end col to target col (column is preserved
              ! across the vertical move)
              if (i_redraw < current_col) then
                do current_line = 1, current_col - i_redraw
                  call rdraw_append(char(27) // '[D')
                end do
              else if (i_redraw > current_col) then
                do current_line = 1, i_redraw - current_col
                  call rdraw_append(char(27) // '[C')
                end do
              end if
            end if

            ! Show cursor, then flush entire buffer in one write
            call rdraw_append(ESC_SHOW_CURSOR)
            call rdraw_flush()

            ! RPROMPT was cleared by ESC[J above; subsequent redraws
            ! don't need the extra cursor-up compensation.
            rprompt_displayed = .false.

            ! Debug: show state before recalculating cursor position
            if (debug_utf8) then
              write(error_unit, '(a,i0,a,i0,a,i0)') '[REDRAW] BEFORE cursor_get_row_col: cursor_pos=', &
                module_input_state%cursor_pos, ' screen_row=', module_cursor_screen_row, ' screen_col=', module_cursor_screen_col
            end if

            ! Update screen cursor position tracking to match where we actually positioned the cursor
            call cursor_get_row_col(prompt, module_input_state%cursor_pos, term_cols, &
                                    module_cursor_screen_row, module_cursor_screen_col)

            ! Debug: show state after recalculating cursor position
            if (debug_utf8) then
              write(error_unit, '(a,i0,a,i0)') '[REDRAW] AFTER cursor_get_row_col: screen_row=', &
                module_cursor_screen_row, ' screen_col=', module_cursor_screen_col
            end if

          ! Save state for display diffing (Phase 1)
          if (module_input_state%length > 0) then
            call state_buffer_get(module_input_state, temp_buf)
            prev_diff_content(:module_input_state%length) = temp_buf(:module_input_state%length)
          end if
          prev_diff_buf_len = module_input_state%length
          prev_diff_cursor_pos = module_input_state%cursor_pos
          prev_diff_suggest_len = module_input_state%suggestion_length
          prev_diff_valid = .true.

          module_input_state%dirty = .false.
        end if

        ! Deferred submit newline (normal Enter): emitted AFTER the redraw
        ! above so the command line is repainted in place (un-highlighted)
        ! before we move past it. The cursor is left at the input position
        ! (end of line for a paste); \r\n moves cleanly to the next row.
        if (submit_pending) then
          write(output_unit, '(a)', advance='no') char(13) // char(10)
          flush(output_unit)
          submit_pending = .false.
        end if
      end do

      ! Restore terminal (unless keep_raw requested for continuation prompts)
      if (present(keep_raw)) then
        if (.not. keep_raw) then
          if (.not. restore_terminal(module_original_termios)) then
          end if
        end if
      else
        if (.not. restore_terminal(module_original_termios)) then
        end if
      end if
    else
      ! Fallback to line-based input
#ifdef USE_C_STRINGS
      ! Read into temp buffer, then copy to C string
      read(input_unit, '(a)', iostat=iostat) temp_buf
      if (iostat == 0) then
        module_input_state%length = len_trim(temp_buf)
        if (.not. c_string_set(module_input_state%buffer_c, temp_buf(:module_input_state%length))) then
          iostat = -1
        end if
      end if
#else
#ifdef USE_MEMORY_POOL
      read(input_unit, '(a)', iostat=iostat) module_input_state%buffer_ref%data
      if (iostat == 0) module_input_state%length = len_trim(module_input_state%buffer_ref%data)
#else
      read(input_unit, '(a)', iostat=iostat) module_input_state%buffer
      if (iostat == 0) module_input_state%length = len_trim(module_input_state%buffer)
#endif
#endif
    end if

    ! Return the result
    if (iostat == 0) then
      call state_buffer_get(module_input_state, temp_buf)
      line = temp_buf(:module_input_state%length)
      ! Note: History addition is now handled in the main loop AFTER expansion
      ! This prevents history expansion commands like !! from referencing themselves
    else
      line = ''
    end if

    ! Clean up allocated memory in module_input_state
    call cleanup_input_state(module_input_state)

    ! Note: module_input_state persists as a module variable, no deallocation needed

  end subroutine

  ! Simple fallback readline - uses standard input for now
  ! This is a placeholder for a full readline implementation
  subroutine readline_simple(prompt, line, iostat)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat

    ! Print prompt
    write(output_unit, '(a)', advance='no') prompt
    write(output_unit, '(a)', advance='no') ' '  ! Space after prompt
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
    character(len=MAX_LINE_LEN) :: completions(MAX_LOCAL_COMPLETIONS)
    integer :: num_completions, tab_pos

    ! Print prompt
    write(output_unit, '(a)', advance='no') prompt
    write(output_unit, '(a)', advance='no') ' '  ! Space after prompt
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
#ifdef USE_C_STRINGS
    if (len_trim(input_state%vi_command_buffer) > 0) then
      select case (input_state%vi_command_buffer(1:1))
#elif defined(USE_MEMORY_POOL)
    if (len_trim(input_state%vi_command_buffer_ref%data) > 0) then
      select case (input_state%vi_command_buffer_ref%data(1:1))
#else
    if (len_trim(input_state%vi_command_buffer) > 0) then
      select case (input_state%vi_command_buffer(1:1))
#endif
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
    case (ichar('P'))
      ! Put (paste) before cursor
      do i = 1, repeat_count
        call handle_vi_put(input_state, .true.)
      end do

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
    integer :: pos
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
      ! Emacs mode (Alt+f): Skip spaces first, then move to END of word
      ! Skip any leading spaces
      do while (pos <= input_state%length .and. state_buffer_get_char(input_state, pos) == ' ')
        pos = pos + 1
      end do
      ! Skip word characters (stop at end of word)
      do while (pos <= input_state%length .and. state_buffer_get_char(input_state, pos) /= ' ')
        pos = pos + 1
      end do
      input_state%cursor_pos = min(pos - 1, input_state%length)
    end if

    input_state%dirty = .true.

    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine

  subroutine move_to_previous_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos
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

    ! Skip spaces
    do while (pos > 0 .and. state_buffer_get_char(input_state, pos) == ' ')
      pos = pos - 1
    end do

    ! Find beginning of word
    do while (pos > 0 .and. state_buffer_get_char(input_state, pos) /= ' ')
      pos = pos - 1
    end do

    ! pos is now at a space (or 0 if at beginning)
    ! cursor_pos represents position between characters,
    ! so space position is correct (cursor will be after space, before first char of word)
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
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)  ! Max 50 completions
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: last_word
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
  subroutine enhanced_tab_complete(partial_input, completions, num_completions, shell, input_len)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    type(shell_state_t), intent(inout), optional :: shell
    integer, intent(in), optional :: input_len

    character(len=MAX_LINE_LEN) :: last_word, prefix_part, command_name
    character(len=256) :: temp_completions(MAX_COMPLETIONS)  ! Must match completion module's expectation
    integer :: last_space_pos, i, first_space_pos, temp_count, actual_len
    logical :: is_command, used_programmable_completion
    type(completion_spec_t) :: spec

    ! Use provided length if given, otherwise use len_trim
    if (present(input_len)) then
      actual_len = input_len
    else
      actual_len = len_trim(partial_input)
    end if

    num_completions = 0
    used_programmable_completion = .false.

    ! Find the last word to complete (respect quotes)
    last_space_pos = 0
    block
      logical :: in_sq, in_dq
      in_sq = .false.
      in_dq = .false.
      do i = 1, actual_len
        if (partial_input(i:i) == "'" .and. .not. in_dq) then
          in_sq = .not. in_sq
        else if (partial_input(i:i) == '"' .and. .not. in_sq) then
          in_dq = .not. in_dq
        else if (partial_input(i:i) == ' ' .and. .not. in_sq .and. .not. in_dq) then
          last_space_pos = i
        end if
      end do
    end block

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
          do i = 1, min(temp_count, MAX_LOCAL_COMPLETIONS)
            completions(i) = trim(temp_completions(i))
          end do
          num_completions = min(temp_count, MAX_LOCAL_COMPLETIONS)
          completion_total_matches = completion_total_matches + temp_count
          if (pager_collect) then
            do i = 1, temp_count
              if (pager_item_count >= PAGER_STORE_MAX) exit
              pager_item_count = pager_item_count + 1
              pager_items(pager_item_count) = temp_completions(i)(1:min(len(temp_completions(i)), MAX_MENU_ITEM_LEN))
            end do
          end if
          used_programmable_completion = .true.
        end if
      end if
    end if

    ! Fall back to default completion if programmable completion didn't produce results
    if (.not. used_programmable_completion) then
      if (is_command) then
        ! Check if this looks like a directory path for cd-less navigation
        if (looks_like_directory_path(last_word)) then
          ! Complete as files/directories for path-like input
          if (has_glob_chars(last_word)) then
            call expand_glob_for_completion(last_word, completions, num_completions)
          else
            call complete_files_enhanced(last_word, completions, num_completions)
          end if
          ! Command position: a command must be runnable, so keep only
          ! executables (to run) and directories (to descend) — fish's two-pass
          ! EXECUTABLES_ONLY + DIRECTORIES_ONLY. This replaces the old behavior
          ! that filtered to dirs-only on a trailing-slash path (dropping
          ! executables on `./`+Tab) and applied NO filter when a pattern was
          ! present (offering plain data files like `./readme.txt`). (AR-02
          ! cand-2/3)
          call filter_executables_and_dirs_only(completions, num_completions)
        else
          ! Complete commands (builtins + PATH executables)
          call complete_commands_enhanced(last_word, completions, num_completions)
        end if

        ! Add prefix back to completions
        do i = 1, num_completions
          completions(i) = trim(completions(i))
        end do
      else
        ! Check if completing a variable name ($VAR)
        if (len_trim(last_word) > 1 .and. last_word(1:1) == '$') then
          ! Variable completion — match against shell variables
          call complete_variable_names(last_word, completions, num_completions)
        else if (has_glob_chars(last_word)) then
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
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: temp_completions(MAX_LOCAL_COMPLETIONS)  ! Local temp storage
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

    ! Filter the pager store the same way so directory-only menus
    ! (cd/pushd/popd) never page through files
    if (pager_item_count > 0) then
      new_count = 0
      do i = 1, pager_item_count
        if (len_trim(pager_items(i)) > 0) then
          if (pager_items(i)(len_trim(pager_items(i)):len_trim(pager_items(i))) == '/') then
            new_count = new_count + 1
            pager_items(new_count) = pager_items(i)
          end if
        end if
      end do
      pager_item_count = new_count
    end if

    ! The directory-only count of matches beyond the stored cap is
    ! unknowable, so the "more items" indicator must not claim one
    completion_total_matches = 0
  end subroutine

  ! True if a completion string is something runnable as a command: a directory
  ! (trailing '/', to descend into) or an executable file (access X_OK).
  ! Handles a leading ~ for the access test.
  function is_exec_or_dir_completion(path) result(keep)
    character(len=*), intent(in) :: path
    logical :: keep
    character(len=MAX_LINE_LEN) :: resolved
    character(len=:), allocatable :: home
    integer :: plen

    keep = .false.
    plen = len_trim(path)
    if (plen == 0) return
    if (path(plen:plen) == '/') then
      keep = .true.            ! directory — keep to allow descending
      return
    end if
    resolved = path(1:plen)
    if (path(1:1) == '~' .and. plen >= 2) then
      if (path(2:2) == '/') then
        home = get_environment_var('HOME')
        if (allocated(home)) then
          if (len(home) > 0) resolved = trim(home) // path(2:plen)
        end if
      end if
    end if
    keep = file_is_executable(trim(resolved))
  end function is_exec_or_dir_completion

  ! Filter completions to executables-or-directories (command position). A
  ! command must be runnable, so plain data files are dropped. Mirrors
  ! filter_directories_only: filters both the completion array AND the pager
  ! store so the menu shows the same set. (AR-02 cand-2/3)
  subroutine filter_executables_and_dirs_only(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: temp_completions(MAX_LOCAL_COMPLETIONS)
    integer :: i, new_count

    new_count = 0
    do i = 1, num_completions
      if (is_exec_or_dir_completion(completions(i))) then
        new_count = new_count + 1
        temp_completions(new_count) = completions(i)
      end if
    end do
    do i = 1, new_count
      completions(i) = temp_completions(i)
    end do
    num_completions = new_count

    if (pager_item_count > 0) then
      new_count = 0
      do i = 1, pager_item_count
        if (is_exec_or_dir_completion(pager_items(i))) then
          new_count = new_count + 1
          pager_items(new_count) = pager_items(i)
        end if
      end do
      pager_item_count = new_count
    end if

    ! filtered count beyond the stored cap is unknowable; suppress the
    ! "more items" indicator rather than claim a wrong total
    completion_total_matches = 0
  end subroutine

  ! Check if a string contains glob characters
  function has_glob_chars(str) result(has_globs)
    character(len=*), intent(in) :: str
    logical :: has_globs

    has_globs = (index(str, '*') > 0 .or. &
                 index(str, '?') > 0 .or. &
                 index(str, '[') > 0)
  end function has_glob_chars

  ! Check if a string looks like a directory path (for cd-less navigation)
  function looks_like_directory_path(str) result(looks_like_path)
    character(len=*), intent(in) :: str
    logical :: looks_like_path
    character(len=:), allocatable :: trimmed

    trimmed = trim(str)
    if (len(trimmed) == 0) then
      looks_like_path = .false.
      return
    end if

    ! Check for path indicators:
    ! - Starts with / (absolute path)
    ! - Starts with ~ (home directory)
    ! - Starts with . (current/parent directory)
    ! - Contains / anywhere (path separator)
    looks_like_path = (trimmed(1:1) == '/' .or. &
                       trimmed(1:1) == '~' .or. &
                       trimmed(1:1) == '.' .or. &
                       index(trimmed, '/') > 0)
  end function looks_like_directory_path

  ! Expand glob pattern for tab completion using real filesystem
  subroutine expand_glob_for_completion(pattern, completions, num_completions)
    character(len=*), intent(in) :: pattern
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    integer, parameter :: MAX_DIR_ENTRIES = 4096
    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    character(len=256), allocatable :: entries(:)
    logical, allocatable :: is_dir_flags(:)
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

    ! Enumerate the directory natively (opendir/readdir) — same as scan_directory
    allocate(entries(MAX_DIR_ENTRIES), is_dir_flags(MAX_DIR_ENTRIES))
    call list_directory(trim(dir_path), entries, is_dir_flags, num_entries)

    ! Match entries against glob pattern. Keep scanning past the storage cap
    ! so the true match count reaches the menu's "more items" indicator.
    do i = 1, num_entries
      ! Skip . and ..
      if (trim(entries(i)) == '.' .or. trim(entries(i)) == '..') cycle

      ! Use pattern_matches from glob module to match against pattern
      if (pattern_matches(file_pattern, trim(entries(i)))) then
        completion_total_matches = completion_total_matches + 1
        if (num_completions >= MAX_LOCAL_COMPLETIONS .and. &
            (.not. pager_collect .or. pager_item_count >= PAGER_STORE_MAX)) cycle  ! count only

        ! Build full path
        if (trim(dir_path) == '.') then
          full_path = trim(entries(i))
        else
          full_path = trim(dir_path) // '/' // trim(entries(i))
        end if

        ! Directory-ness comes straight from readdir (no per-entry test -d)
        is_dir = is_dir_flags(i)
        if (is_dir) full_path = trim(full_path) // '/'
        if (num_completions < MAX_LOCAL_COMPLETIONS) then
          num_completions = num_completions + 1
          completions(num_completions) = trim(full_path)
        end if
        if (pager_collect .and. pager_item_count < PAGER_STORE_MAX) then
          pager_item_count = pager_item_count + 1
          pager_items(pager_item_count) = full_path(1:MAX_MENU_ITEM_LEN)
        end if
      end if
    end do

    ! Clean up allocatable arrays
    if (allocated(entries)) deallocate(entries)
    if (allocated(is_dir_flags)) deallocate(is_dir_flags)
  end subroutine expand_glob_for_completion

  subroutine complete_commands(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
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
        if (num_completions <= MAX_LOCAL_COMPLETIONS) then
          completions(num_completions) = trim(builtin_commands(i))
        end if
      end if
    end do
    
    ! TODO: Add external command completion from PATH
  end subroutine

  subroutine complete_files(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
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
    
    ! Don't add ./ and ../ automatically - they're not based on user input
    ! Let scan_directory find all matches naturally
    
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
  subroutine complete_variable_names(prefix_with_dollar, completions, num_completions)
    character(len=*), intent(in) :: prefix_with_dollar
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=256) :: var_prefix
    integer :: i, score, eqpos
    character(len=:), allocatable :: entry

    num_completions = 0
    ! Strip the $ from the prefix
    var_prefix = prefix_with_dollar(2:)

    ! Iterate the environment natively (no `env | cut | tr` subprocess); each
    ! entry is "NAME=value", so match on the NAME before '='.
    i = 0
    do
      entry = get_environ_entry(i)
      if (len(entry) == 0) exit  ! end of environ
      i = i + 1
      if (num_completions >= MAX_LOCAL_COMPLETIONS) cycle
      eqpos = index(entry, '=')
      if (eqpos <= 1) cycle
      score = fuzzy_match_score(trim(var_prefix), entry(1:eqpos-1))
      if (score >= 0) then
        num_completions = num_completions + 1
        completions(num_completions) = '$' // entry(1:eqpos-1)
      end if
      if (i > 100000) exit  ! safety bound
    end do
  end subroutine

  subroutine complete_commands_enhanced(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=50), parameter :: builtin_commands(20) = [ &
      'cd       ', 'echo     ', 'exit     ', 'export   ', &
      'pwd      ', 'jobs     ', 'fg       ', 'bg       ', &
      'history  ', 'source   ', 'test     ', 'if       ', &
      'kill     ', 'wait     ', 'trap     ', 'config   ', &
      'alias    ', 'unalias  ', 'help     ', 'rawtest  ' &
    ]
    ! Use allocatable array to avoid static storage
    type(scored_completion_t), allocatable :: scored(:)
    integer :: i, num_scored, score

    ! Allocate scored array (room for builtins + a $PATH scan, capped at the
    ! pager store size; output is still trimmed to 50 below)
    allocate(scored(PAGER_STORE_MAX))
    num_completions = 0
    num_scored = 0

    ! Score builtin commands using fuzzy matching
    do i = 1, size(builtin_commands)
      score = fuzzy_match_score(prefix, trim(builtin_commands(i)))
      if (score >= 0) then  ! Negative score = no match
        num_scored = num_scored + 1
        if (num_scored <= size(scored)) then
          scored(num_scored)%text = trim(builtin_commands(i))
          scored(num_scored)%score = score
        end if
      end if
    end do

    ! Add common system commands (kept as a fallback; deduped by the PATH scan)
    call add_system_commands_fuzzy(prefix, scored, num_scored)

    ! Scan $PATH for executables matching the prefix (cand-1). This is what
    ! makes `pyt`+Tab complete python3/pytest instead of only ~35 hardcoded
    ! names. Deduped against builtins and common commands.
    call add_path_commands_fuzzy(prefix, scored, num_scored)

    ! Sort by score
    if (num_scored > 0) then
      call sort_completions_by_score(scored, num_scored)
    end if

    ! Copy top matches to the output array, which is sized MAX_LOCAL_COMPLETIONS.
    ! (Was a literal 50 — a latent overflow that never fired until the $PATH
    ! scan let num_scored exceed 40, smashing the stack. The pager store below
    ! holds the full set for the scrollable menu.)
    num_completions = min(num_scored, MAX_LOCAL_COMPLETIONS)
    do i = 1, num_completions
      completions(i) = scored(i)%text
    end do
    completion_total_matches = completion_total_matches + num_scored

    ! Fill the pager store for menu scrolling
    if (pager_collect) then
      do i = 1, num_scored
        if (pager_item_count >= PAGER_STORE_MAX) exit
        pager_item_count = pager_item_count + 1
        pager_items(pager_item_count) = scored(i)%text(1:MAX_MENU_ITEM_LEN)
      end do
    end if

    ! Clean up allocatable array
    if (allocated(scored)) deallocate(scored)
  end subroutine

  subroutine add_system_commands(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
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
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
      if (prefix_len == 0 .or. &
          index(trim(common_commands(i)), prefix(1:prefix_len)) == 1) then
        num_completions = num_completions + 1
        completions(num_completions) = trim(common_commands(i))
      end if
    end do
  end subroutine

  ! Scan $PATH for executables whose basename starts with `prefix` and add them
  ! to the scored set (deduped by basename against what's already there). Prefix
  ! match (not fuzzy) keeps it cheap and matches fish's command completion; the
  ! cheap prefix test runs BEFORE the access(X_OK) syscall so we only stat
  ! candidates. Bounded by size(scored). (AR-02 cand-1)
  subroutine add_path_commands_fuzzy(prefix, scored, num_scored)
    character(len=*), intent(in) :: prefix
    type(scored_completion_t), intent(inout) :: scored(:)
    integer, intent(inout) :: num_scored

    integer, parameter :: DIR_ENTRIES = 4096
    character(len=:), allocatable :: path_env
    character(len=1024) :: dir
    character(len=256), allocatable :: names(:)
    logical, allocatable :: is_dir_flags(:)
    character(len=MAX_LINE_LEN) :: full_path
    integer :: num_entries, i, j, ds, sep, plen, path_len, score, cap, nlen
    logical :: dup

    path_env = get_environment_var('PATH')
    if (.not. allocated(path_env)) return
    path_len = len_trim(path_env)
    if (path_len == 0) return

    plen = len_trim(prefix)
    cap = size(scored)
    allocate(names(DIR_ENTRIES), is_dir_flags(DIR_ENTRIES))

    ! Walk PATH, splitting on ':'
    ds = 1
    do while (ds <= path_len)
      if (num_scored >= cap) exit
      sep = index(path_env(ds:path_len), ':')
      if (sep == 0) then
        dir = path_env(ds:path_len)
        ds = path_len + 1
      else
        dir = path_env(ds:ds+sep-2)
        ds = ds + sep
      end if
      if (len_trim(dir) == 0) cycle   ! empty PATH element

      call list_directory(trim(dir), names, is_dir_flags, num_entries)
      do i = 1, num_entries
        if (num_scored >= cap) exit
        if (is_dir_flags(i)) cycle    ! a command must be a file, not a dir
        nlen = len_trim(names(i))
        if (nlen == 0) cycle
        ! cheap prefix filter before the access() syscall
        if (plen > 0) then
          if (nlen < plen) cycle
          if (names(i)(1:plen) /= prefix(1:plen)) cycle
        end if
        full_path = trim(dir) // '/' // names(i)(1:nlen)
        if (.not. file_is_executable(trim(full_path))) cycle
        ! dedupe by basename (earlier PATH entry / builtin / common-cmd wins)
        dup = .false.
        do j = 1, num_scored
          if (trim(scored(j)%text) == names(i)(1:nlen)) then
            dup = .true.
            exit
          end if
        end do
        if (dup) cycle
        score = fuzzy_match_score(prefix, names(i)(1:nlen))
        if (score < 0) cycle
        num_scored = num_scored + 1
        scored(num_scored)%text = names(i)(1:nlen)
        scored(num_scored)%score = score
      end do
    end do

    if (allocated(names)) deallocate(names)
    if (allocated(is_dir_flags)) deallocate(is_dir_flags)
  end subroutine add_path_commands_fuzzy

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
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=MAX_LINE_LEN) :: dir_path, file_pattern, clean_prefix
    character(len=:), allocatable :: debug_mode
    integer :: last_slash_pos, i, cp_len
    logical :: debug_enabled

    ! Check if debug mode is enabled
    debug_mode = get_environment_var('FORTSH_DEBUG_COMPLETION')
    debug_enabled = (allocated(debug_mode) .and. trim(debug_mode) == '1')

    num_completions = 0

    ! Strip leading/trailing quotes from prefix for filesystem access
    clean_prefix = trim(prefix)
    cp_len = len_trim(clean_prefix)
    if (cp_len >= 2) then
      if ((clean_prefix(1:1) == "'" .and. clean_prefix(cp_len:cp_len) == "'") .or. &
          (clean_prefix(1:1) == '"' .and. clean_prefix(cp_len:cp_len) == '"')) then
        clean_prefix = clean_prefix(2:cp_len-1)
      else if (clean_prefix(1:1) == "'" .or. clean_prefix(1:1) == '"') then
        ! Unclosed quote (user still typing) — strip leading quote only
        clean_prefix = clean_prefix(2:cp_len)
      end if
    end if

    ! Extract directory path and filename pattern
    last_slash_pos = 0
    last_slash_pos = 0
    do i = len_trim(clean_prefix), 1, -1
      if (clean_prefix(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do

    if (last_slash_pos > 0) then
      dir_path = clean_prefix(:last_slash_pos-1)
      file_pattern = clean_prefix(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(clean_prefix)
    end if

    ! Preserve explicit "./" prefix: when user typed "./something", dir_path
    ! is "." but completions should include "./" to match what was typed.
    ! Pass "./" as dir_path so scan_directory builds paths with "./" prefix.
    if (len_trim(clean_prefix) >= 2 .and. clean_prefix(1:2) == './') then
      if (trim(dir_path) == '.') dir_path = './'
    end if

    ! scan_directory handles all matches including dotfiles when pattern is empty
    call scan_directory(dir_path, file_pattern, completions, num_completions)
  end subroutine

  ! Scan directory for matching files and directories (with fuzzy matching)
  subroutine scan_directory(dir_path, pattern, completions, num_completions)
    character(len=*), intent(in) :: dir_path, pattern
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    integer, parameter :: MAX_DIR_ENTRIES = 4096
    character(len=1024) :: expanded_dir
    character(len=256), allocatable :: entries(:)       ! one filename per slot
    logical, allocatable :: is_dir_flags(:)             ! parallel to entries
    character(len=MAX_LINE_LEN) :: full_path
    character(len=:), allocatable :: home_dir, debug_mode
    ! Use allocatable array to avoid static storage
    type(scored_completion_t), allocatable :: scored(:)
    integer :: num_entries, i, pattern_len, num_scored, score, j, total_matches
    logical :: is_dir, debug_enabled

    ! Check if debug mode is enabled
    debug_mode = get_environment_var('FORTSH_DEBUG_COMPLETION')
    debug_enabled = (allocated(debug_mode) .and. trim(debug_mode) == '1')

    ! Allocate scored array
    allocate(scored(MAX_SCORED_ITEMS))

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

    ! Enumerate the directory natively via opendir/readdir — no `ls` subprocess.
    ! This removes shell injection, dependence on the host `ls`/locale, and (the
    ! bug that started this) any chance of a subprocess printing onto the
    ! terminal mid-redraw. readdir reports directory-ness directly (symlinks to
    ! directories are followed). Pattern matching stays below in fuzzy_match_score.
    allocate(entries(MAX_DIR_ENTRIES), is_dir_flags(MAX_DIR_ENTRIES))
    call list_directory(trim(expanded_dir), entries, is_dir_flags, num_entries)

    ! Score entries using fuzzy matching. Keep scanning past the storage cap
    ! so total_matches reflects the real match count — the menu reports
    ! "... N more items available" from it.
    num_scored = 0
    total_matches = 0
    do i = 1, num_entries
      ! Skip . and .. unless the user explicitly typed a leading dot
      if (trim(entries(i)) == '.' .or. trim(entries(i)) == '..') then
        if (pattern_len == 0 .or. (pattern_len > 0 .and. pattern(1:1) /= '.')) then
          cycle
        end if
      end if

      ! Directory-ness comes straight from readdir; the name is already clean
      ! (no ls -F markers to strip).
      is_dir = is_dir_flags(i)
      full_path = trim(entries(i))

      ! Calculate fuzzy match score
      score = fuzzy_match_score(pattern, trim(full_path))
      if (score >= 0) then  ! Negative score = no match
        total_matches = total_matches + 1
        if (num_scored >= MAX_SCORED_ITEMS) cycle  ! count, but storage is full

        ! Build full path for display (use original dir_path to preserve ~ in display)
        if (trim(dir_path) == '.') then
          full_path = trim(full_path)
        else if (trim(dir_path) == './') then
          ! Explicit ./ prefix — preserve it without adding extra slash
          full_path = './' // trim(full_path)
        else if (trim(dir_path) == '/') then
          ! Root directory - don't add extra slash
          full_path = '/' // trim(full_path)
        else
          full_path = trim(dir_path) // '/' // trim(full_path)
        end if

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

    completion_total_matches = completion_total_matches + total_matches

    ! Sort by score
    if (num_scored > 0) then
      call sort_completions_by_score(scored, num_scored)
    end if

    ! Copy to output (add to existing completions, limit to MAX_LOCAL_COMPLETIONS)
    do j = 1, num_scored
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
      num_completions = num_completions + 1
      completions(num_completions) = scored(j)%text
    end do

    ! Fill the pager store with the full sorted set for menu scrolling
    if (pager_collect) then
      do j = 1, num_scored
        if (pager_item_count >= PAGER_STORE_MAX) exit
        pager_item_count = pager_item_count + 1
        pager_items(pager_item_count) = scored(j)%text(1:MAX_MENU_ITEM_LEN)
      end do
    end if

    ! Debug output
    if (debug_enabled) then
    end if

    ! Clean up allocatable arrays
    if (allocated(scored)) deallocate(scored)
    if (allocated(entries)) deallocate(entries)
    if (allocated(is_dir_flags)) deallocate(is_dir_flags)
  end subroutine


  ! Parse ls output into individual entries
  subroutine parse_ls_output(output, entries, num_entries, use_tab_delim)
    character(len=*), intent(in) :: output
    character(len=MAX_LINE_LEN), allocatable, intent(out) :: entries(:)
    integer, intent(out) :: num_entries
    logical, intent(in), optional :: use_tab_delim

    integer :: pos, start, output_len, count_pass
    logical :: tab_mode
    character :: delim

    tab_mode = .false.
    if (present(use_tab_delim)) tab_mode = use_tab_delim
    delim = merge(char(9), ' ', tab_mode)

    output_len = len_trim(output)

    ! First pass: count entries
    num_entries = 0
    pos = 1
    do while (pos <= output_len)
      ! Skip delimiter characters
      do while (pos <= output_len .and. (output(pos:pos) == delim .or. &
                (.not. tab_mode .and. output(pos:pos) == char(9))))
        pos = pos + 1
      end do

      if (pos > output_len) exit

      start = pos

      ! Find end of entry
      do while (pos <= output_len .and. output(pos:pos) /= delim)
        pos = pos + 1
      end do

      if (pos > start) then
        num_entries = num_entries + 1
      end if

      pos = pos + 1
    end do

    ! Allocate array based on actual count
    if (num_entries > 0) then
      allocate(entries(num_entries))

      ! Second pass: fill entries
      count_pass = 0
      pos = 1
      do while (pos <= output_len .and. count_pass < num_entries)
        ! Skip delimiter characters
        do while (pos <= output_len .and. (output(pos:pos) == delim .or. &
                  (.not. tab_mode .and. output(pos:pos) == char(9))))
          pos = pos + 1
        end do

        if (pos > output_len) exit

        start = pos

        ! Find end of entry
        do while (pos <= output_len .and. output(pos:pos) /= delim)
          pos = pos + 1
        end do

        if (pos > start) then
          count_pass = count_pass + 1
          entries(count_pass) = output(start:pos-1)
        end if

        pos = pos + 1
      end do
    else
      ! No entries - allocate empty array
      allocate(entries(0))
    end if
  end subroutine

  subroutine show_completions(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(in) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(in) :: num_completions
    integer :: i, j, max_len, col_width, num_cols, items_in_row
    integer :: term_width, status
    character(len=10) :: cols_env

    if (num_completions > 1) then
      write(output_unit, '(a)') ''

      ! Find maximum length of completions
      max_len = 0
      do i = 1, num_completions
        max_len = max(max_len, len_trim(completions(i)))
      end do

      ! Column width = max length + 2 spaces padding
      col_width = max_len + 2

      ! Get terminal width (default to 80 if not available)
      call get_environment_variable("COLUMNS", cols_env, status=status)
      if (status == 0 .and. len_trim(cols_env) > 0) then
        read(cols_env, *, iostat=status) term_width
        if (status /= 0) term_width = 80
      else
        term_width = 80
      end if

      ! Calculate number of columns that fit
      num_cols = max(1, term_width / col_width)

      ! Print items in rows, aligned to columns
      do i = 1, num_completions
        ! Print item padded to column width (sanitize control/escape bytes in
        ! filenames so they can't inject terminal escape sequences)
        write(output_unit, '(a)', advance='no') sanitize_for_display(trim(completions(i)))

        ! Calculate position in current row
        items_in_row = mod(i - 1, num_cols) + 1

        ! Add padding unless it's the last item in the row or the last item overall
        if (items_in_row < num_cols .and. i < num_completions) then
          ! Pad to column width
          do j = len_trim(completions(i)) + 1, col_width
            write(output_unit, '(a)', advance='no') ' '
          end do
        else
          ! End of row - print newline
          write(output_unit, '(a)') ''
        end if
      end do

      ! Ensure we end with a blank line if last row wasn't complete
      if (mod(num_completions, num_cols) /= 0) then
        write(output_unit, '(a)') ''
      end if
    end if
  end subroutine

  ! Find common prefix among completions
  function get_common_prefix(completions, num_completions) result(prefix)
    character(len=MAX_LINE_LEN), intent(in) :: completions(MAX_LOCAL_COMPLETIONS)
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

  ! Backslash-escape shell metacharacters in a filename for unquoted insertion.
  ! Matches bash's completion escaping: spaces, quotes, parens, etc.
  function escape_for_completion(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    integer :: i, ilen, opos
    character(len=1) :: ch
    character(len=MAX_LINE_LEN) :: buf

    ilen = len_trim(input)
    opos = 1
    do i = 1, ilen
      ch = input(i:i)
      select case(ch)
      case(' ', "'", '"', '\', '(', ')', '&', '|', ';', '<', '>', &
           '*', '?', '[', ']', '{', '}', '$', '!', '#', '~', '`')
        if (opos + 1 <= MAX_LINE_LEN) then
          buf(opos:opos) = '\'
          opos = opos + 1
          buf(opos:opos) = ch
          opos = opos + 1
        end if
      case default
        if (opos <= MAX_LINE_LEN) then
          buf(opos:opos) = ch
          opos = opos + 1
        end if
      end select
    end do
    if (opos > 1) then
      output = buf(1:opos-1)
    else
      output = ''
    end if
  end function escape_for_completion

  ! Enhanced tab completion that handles partial completion
  subroutine smart_tab_complete(partial_input, completions, num_completions, completed_line, completed, input_len)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    character(len=*), intent(out) :: completed_line
    logical, intent(out) :: completed
    integer, intent(in), optional :: input_len

    character(len=MAX_LINE_LEN) :: common_prefix, prefix_part, last_word
    character(len=4096) :: expanded_matches
    integer :: last_space_pos, i, pos, j, actual_len
    logical :: is_glob_pattern

    ! Fresh completion run — backends below accumulate the true match count
    ! and (while pager_collect is set) fill the pager item store
    completion_total_matches = 0
    pager_item_count = 0
    pager_collect = .true.

    ! Use provided length if given, otherwise use len_trim
    if (present(input_len)) then
      actual_len = input_len
    else
      actual_len = len_trim(partial_input)
    end if

    completed = .false.
    completed_line = partial_input

    ! Find the prefix (command and any earlier arguments)
    ! Respect quotes: spaces inside quotes don't count as word boundaries
    last_space_pos = 0
    block
      logical :: in_single_quote, in_double_quote
      in_single_quote = .false.
      in_double_quote = .false.
      do i = 1, actual_len
        if (partial_input(i:i) == "'" .and. .not. in_double_quote) then
          in_single_quote = .not. in_single_quote
        else if (partial_input(i:i) == '"' .and. .not. in_single_quote) then
          in_double_quote = .not. in_double_quote
        else if (partial_input(i:i) == ' ' .and. .not. in_single_quote .and. .not. in_double_quote) then
          last_space_pos = i
        end if
      end do
    end block

    if (last_space_pos > 0) then
      prefix_part = partial_input(:last_space_pos)
      last_word = partial_input(last_space_pos+1:)
    else
      prefix_part = ''
      last_word = trim(partial_input)
    end if

    ! Check if we're completing a glob pattern
    is_glob_pattern = has_glob_chars(last_word)

    ! Pass the actual length to preserve trailing spaces
    call enhanced_tab_complete(partial_input, completions, num_completions, input_len=actual_len)

    ! Backends are done — stop pager collection so later backend calls
    ! (e.g. from the autosuggestion path) can't clobber the store
    pager_collect = .false.

    if (num_completions == 0) then
      ! No completions found
      return
    else if (num_completions == 1) then
      ! Single completion - reconstruct with proper quoting
      block
        character(len=1) :: quote_char
        integer :: lw_len

        lw_len = len_trim(last_word)
        quote_char = ' '

        ! Check if last_word starts with a quote
        if (lw_len > 0 .and. (last_word(1:1) == "'" .or. last_word(1:1) == '"')) then
          quote_char = last_word(1:1)
        end if

        ! Completions already include the full path from scan_directory.
        ! Just wrap in quotes if the original word was quoted.
        if (quote_char /= ' ') then
          if (last_space_pos > 0) then
            completed_line = prefix_part(:last_space_pos) // quote_char // &
              trim(completions(1)) // quote_char
          else
            completed_line = quote_char // trim(completions(1)) // quote_char
          end if
        else
          block
            character(len=:), allocatable :: comp_result
            ! Don't escape variable completions ($VAR) or command substitutions
            if (len_trim(completions(1)) > 0 .and. &
                (completions(1)(1:1) == '$' .or. completions(1)(1:1) == '~')) then
              comp_result = trim(completions(1))
            else
              comp_result = escape_for_completion(trim(completions(1)))
            end if
            if (last_space_pos > 0) then
              completed_line = prefix_part(:last_space_pos) // comp_result
            else
              completed_line = comp_result
            end if
          end block
        end if
      end block
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
            expanded_matches(pos:pos) = ' '
            pos = pos + 1
          end if

          block
            character(len=:), allocatable :: esc_match
            if (len_trim(completions(j)) > 0 .and. &
                (completions(j)(1:1) == '$' .or. completions(j)(1:1) == '~')) then
              esc_match = trim(completions(j))
            else
              esc_match = escape_for_completion(trim(completions(j)))
            end if
            expanded_matches(pos:pos+len(esc_match)-1) = esc_match
            pos = pos + len(esc_match)
          end block
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

  ! Wrapper to work around potential flang-new bug with repeated function calls
  subroutine insert_char_wrapper(input_state, ch)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: ch
    call insert_char_impl(input_state, ch)
  end subroutine

  ! Insert a complete multi-byte UTF-8 character
  ! Handles cursor tracking correctly for wide characters
  subroutine insert_utf8_char(input_state, utf8_bytes, num_bytes, visual_width)
    use iso_fortran_env, only: output_unit, error_unit
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: utf8_bytes
    integer, intent(in) :: num_bytes, visual_width
    integer :: i, j, term_cols
    logical :: debug_utf8
    integer :: debug_stat

    ! Shift-phase type-over (Sprint 3): replace active selection before
    ! inserting a new multi-byte character.
    if (input_state%selection_active) call delete_selection(input_state)

    ! Check if UTF-8 debug mode is enabled
    call get_environment_variable('FORTSH_DEBUG_UTF8', status=debug_stat)
    debug_utf8 = (debug_stat == 0)

    ! Check if we have room
    if (input_state%length + num_bytes > MAX_LINE_LEN - 1) return

    ! Exit history mode if needed
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Reset completion state
    input_state%completions_shown = .false.

    ! Insert all bytes at cursor position
    if (input_state%cursor_pos >= input_state%length) then
      ! Append at end

      ! Debug: show state before insertion
      if (debug_utf8) then
        write(error_unit, '(a,i0,a,i0,a,i0)') '[INSERT_UTF8] BEFORE: cursor_pos=', &
          input_state%cursor_pos, ' length=', input_state%length, ' screen_col=', module_cursor_screen_col
      end if

      do i = 1, num_bytes
        call state_buffer_set_char(input_state, input_state%length + i, utf8_bytes(i:i))
        ! Output byte to terminal
        write(output_unit, '(a)', advance='no') utf8_bytes(i:i)
      end do
      flush(output_unit)

      input_state%length = input_state%length + num_bytes
      input_state%cursor_pos = input_state%cursor_pos + num_bytes

      ! Update screen cursor position by VISUAL width, not byte count!
      call get_terminal_size_from_env(term_cols)
      module_cursor_screen_col = module_cursor_screen_col + visual_width

      ! Debug: show state after insertion
      if (debug_utf8) then
        write(error_unit, '(a,i0,a,i0,a,i0,a,i0)') '[INSERT_UTF8] AFTER: cursor_pos=', &
          input_state%cursor_pos, ' length=', input_state%length, ' screen_col=', module_cursor_screen_col, &
          ' visual_width=', visual_width
      end if

      ! Handle line wrapping
      if (module_cursor_screen_col >= term_cols) then
        write(output_unit, '(a)', advance='no') char(13) // char(10)
        flush(output_unit)
        module_cursor_screen_col = 0
        module_cursor_screen_row = module_cursor_screen_row + 1
      else
        input_state%dirty = .true.
      end if
    else
      ! Insert in middle - shift characters right
      do j = input_state%length, input_state%cursor_pos + 1, -1
        call state_buffer_set_char(input_state, j + num_bytes, state_buffer_get_char(input_state, j))
      end do

      ! Insert new bytes
      do i = 1, num_bytes
        call state_buffer_set_char(input_state, input_state%cursor_pos + i, utf8_bytes(i:i))
      end do

      input_state%length = input_state%length + num_bytes
      input_state%cursor_pos = input_state%cursor_pos + num_bytes
      input_state%dirty = .true.
    end if

    ! Update autosuggestion
    call update_autosuggestion(input_state)
  end subroutine insert_utf8_char

  ! Helper functions for enhanced readline
  subroutine insert_char_impl(input_state, ch)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: ch
    integer :: term_cols
    character(len=:), allocatable :: temp_buffer  ! Heap allocation to avoid stack overflow

    ! Shift-phase type-over (Sprint 3): typing a character while a selection
    ! is active replaces the selection. delete_selection removes the bytes,
    ! moves cursor to the left edge, and clears selection state.
    if (input_state%selection_active) call delete_selection(input_state)

    ! Allocate temp buffer on heap
    allocate(character(len=MAX_LINE_LEN) :: temp_buffer)

    ! Check if we have room for one more character
    ! CRITICAL: Must be >= MAX_LINE_LEN - 1 to prevent writing to position MAX_LINE_LEN + 1
    ! during middle insertions which shift characters right
    if (input_state%length >= MAX_LINE_LEN - 1) then
      if (allocated(temp_buffer)) deallocate(temp_buffer)
      return
    end if

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

    ! Update autosuggestion after inserting character
    call update_autosuggestion(input_state)

    ! If autosuggestion was generated, we need to redraw to show it
    if (input_state%cursor_pos == input_state%length .and. input_state%suggestion_length > 0) then
      input_state%dirty = .true.
    end if
  end subroutine

  ! Determine how many bytes to delete for a UTF-8 character
  ! Returns the number of bytes to delete (1-4)
  ! Looks at the byte immediately before cursor and walks backward to find the start
  function utf8_char_bytes_before_cursor(input_state) result(num_bytes)
    use iso_fortran_env, only: error_unit
    type(input_state_t), intent(in) :: input_state
    integer :: num_bytes
    integer :: pos, byte_val, start_pos
    character :: ch
    logical :: debug_utf8

    ! Check if debug mode is enabled
    call get_environment_variable('FORTSH_DEBUG_UTF8', status=byte_val)
    debug_utf8 = (byte_val == 0)

    if (input_state%cursor_pos <= 0) then
      num_bytes = 0
      return
    end if

    start_pos = input_state%cursor_pos

    ! Start at the byte immediately before cursor
    pos = input_state%cursor_pos
    ch = state_buffer_get_char(input_state, pos)
    byte_val = iand(iachar(ch), 255)

    if (debug_utf8) then
      write(error_unit, '(a,i0,a,z2.2)') '[UTF8 DEBUG] cursor_pos=', input_state%cursor_pos, ' byte=0x', byte_val
    end if

    ! If it's a continuation byte (10xx xxxx), walk backward to find lead byte
    if (iand(byte_val, 192) == 128) then
      ! Continuation byte - count how many bytes back to the lead byte
      num_bytes = 1
      pos = pos - 1

      ! Walk backward through continuation bytes (max 3 more)
      do while (pos > 0 .and. num_bytes < 4)
        ch = state_buffer_get_char(input_state, pos)
        byte_val = iand(iachar(ch), 255)

        if (iand(byte_val, 192) == 128) then
          ! Still a continuation byte
          if (debug_utf8) then
            write(error_unit, '(a,i0,a,z2.2)') '[UTF8 DEBUG]   pos=', pos, ' continuation byte=0x', byte_val
          end if
          num_bytes = num_bytes + 1
          pos = pos - 1
        else
          ! Found the lead byte (not a continuation byte)
          if (debug_utf8) then
            write(error_unit, '(a,i0,a,z2.2)') '[UTF8 DEBUG]   pos=', pos, ' lead byte=0x', byte_val
          end if
          num_bytes = num_bytes + 1
          exit
        end if
      end do

      if (debug_utf8) then
        write(error_unit, '(a,i0,a,i0,a,i0)') '[UTF8 DEBUG] Moving back ', num_bytes, &
          ' bytes from ', start_pos, ' to ', start_pos - num_bytes
      end if
    else
      ! Not a continuation byte - single byte character (ASCII or orphaned byte)
      num_bytes = 1
      if (debug_utf8) then
        write(error_unit, '(a)') '[UTF8 DEBUG] Single byte character'
      end if
    end if
  end function utf8_char_bytes_before_cursor

  ! Determine how many bytes make up the UTF-8 character at the cursor
  ! Returns the number of bytes (1-4) for moving right
  function utf8_char_bytes_at_cursor(input_state) result(num_bytes)
    type(input_state_t), intent(in) :: input_state
    integer :: num_bytes
    integer :: byte_val
    character :: ch

    if (input_state%cursor_pos >= input_state%length) then
      num_bytes = 0
      return
    end if

    ! Get the byte at cursor position
    ch = state_buffer_get_char(input_state, input_state%cursor_pos + 1)
    byte_val = iand(iachar(ch), 255)

    ! Determine character length based on lead byte
    if (byte_val < 128) then
      ! ASCII character (0x00-0x7F): 1 byte
      num_bytes = 1
    else if (iand(byte_val, 224) == 192) then
      ! 2-byte UTF-8 (0xC0-0xDF)
      num_bytes = 2
    else if (iand(byte_val, 240) == 224) then
      ! 3-byte UTF-8 (0xE0-0xEF)
      num_bytes = 3
    else if (iand(byte_val, 248) == 240) then
      ! 4-byte UTF-8 (0xF0-0xF7)
      num_bytes = 4
    else
      ! Invalid or continuation byte - treat as single byte
      num_bytes = 1
    end if
  end function utf8_char_bytes_at_cursor

  subroutine handle_backspace(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i
    integer :: bytes_to_delete, delete_count

    ! Shift-phase (Sprint 3): Backspace on an active selection deletes the
    ! whole range — no further character deletion. The key is "consumed".
    if (input_state%selection_active) then
      call delete_selection(input_state)
      call update_autosuggestion(input_state)
      return
    end if

    ! Defensive checks for buffer corruption
    if (input_state%cursor_pos <= 0) return
    if (input_state%length <= 0) return
    if (input_state%cursor_pos > input_state%length) then
      ! Cursor beyond buffer - fix it
      input_state%cursor_pos = input_state%length
    end if
    if (input_state%length > MAX_LINE_LEN) then
      ! Buffer overflow detected - reset to safe state
      input_state%length = 0
      input_state%cursor_pos = 0
      input_state%dirty = .true.
      return
    end if

    ! If we're browsing history, exit history mode when editing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Reset completion state when buffer changes
    input_state%completions_shown = .false.

    ! Determine how many bytes to delete (1 for ASCII, 2-4 for UTF-8)
    bytes_to_delete = utf8_char_bytes_before_cursor(input_state)
    if (bytes_to_delete <= 0) return

    ! If cursor is at end, simple deletion
    if (input_state%cursor_pos >= input_state%length) then
      ! Delete UTF-8 character (1-4 bytes) from buffer
      input_state%length = input_state%length - bytes_to_delete
      input_state%cursor_pos = input_state%cursor_pos - bytes_to_delete

      ! Clear the deleted bytes
      do delete_count = 1, bytes_to_delete
        call state_buffer_set_char(input_state, input_state%length + delete_count, ' ')
      end do

      ! Don't manually move cursor - let redraw handle it
      ! This avoids conflicts between cursor_move() escape sequences and redraw escape sequences
      ! Just trigger redraw which will position everything correctly
      input_state%dirty = .true.
    else
      ! Delete in middle - shift characters left by bytes_to_delete positions
      do i = input_state%cursor_pos - bytes_to_delete + 1, input_state%length - bytes_to_delete
        call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, i + bytes_to_delete))
      end do
      input_state%cursor_pos = input_state%cursor_pos - bytes_to_delete
      input_state%length = input_state%length - bytes_to_delete

      ! Clear the bytes at the end
      do delete_count = 1, bytes_to_delete
        call state_buffer_set_char(input_state, input_state%length + delete_count, ' ')
      end do

      ! Middle deletion requires full redraw
      input_state%dirty = .true.
    end if

    ! Update autosuggestion after deleting character
    call update_autosuggestion(input_state)
  end subroutine

  ! Delete character at cursor position (forward delete — Delete key / Ctrl+D)
  subroutine handle_forward_delete_char(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, bytes_to_delete, delete_count

    ! Shift-phase (Sprint 3): Delete on an active selection removes the
    ! whole range and consumes the key.
    if (input_state%selection_active) then
      call delete_selection(input_state)
      call update_autosuggestion(input_state)
      return
    end if

    ! Nothing to delete if cursor is at end or buffer is empty
    if (input_state%cursor_pos >= input_state%length) return
    if (input_state%length <= 0) return

    ! Exit history mode on edit
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if
    input_state%completions_shown = .false.

    ! Determine how many bytes the character at cursor occupies (UTF-8: 1-4)
    bytes_to_delete = utf8_char_bytes_at_cursor(input_state)
    if (bytes_to_delete <= 0) bytes_to_delete = 1

    ! Shift characters left to fill the gap
    do i = input_state%cursor_pos + 1, input_state%length - bytes_to_delete
      call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, i + bytes_to_delete))
    end do
    input_state%length = input_state%length - bytes_to_delete

    ! Clear trailing bytes
    do delete_count = 1, bytes_to_delete
      call state_buffer_set_char(input_state, input_state%length + delete_count, ' ')
    end do

    input_state%dirty = .true.
    call update_autosuggestion(input_state)
  end subroutine

  ! Separate tab completion handler to work around macOS ARM64 crash
  ! This modifies the SAVE'd input_state directly without problematic returns
  subroutine handle_tab_key_separate(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: tab_num_completions, i, last_space_pos
#ifdef __APPLE__
    integer :: j  ! only the flang-new menu_prefix copy loop uses j; declaring
                  ! it unconditionally would warn as unused on gfortran
#endif
    logical :: tab_completed, tab_made_progress, tab_buffer_changed
    character(len=MAX_LINE_LEN) :: tab_completions(MAX_LOCAL_COMPLETIONS)
    character(len=MAX_LINE_LEN) :: tab_partial_input
    character(len=MAX_LINE_LEN) :: tab_completed_line
    character(len=MAX_LINE_LEN) :: tab_saved_input

    ! Exit history mode if we're browsing
    if (input_state%in_history) then
      input_state%in_history = .false.
      input_state%history_pos = 0
    end if

    ! Clear any existing autosuggestion — tab completion replaces it
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    ! Don't complete empty buffer - just ring bell
    if (input_state%length == 0) then
      write(output_unit, '(a)', advance='no') char(7)
      flush(output_unit)
      return
    end if

    ! Get the current buffer content
    call state_buffer_get(input_state, tab_partial_input)
    tab_partial_input = tab_partial_input(:input_state%length)
    tab_saved_input = tab_partial_input

    ! Check if buffer has changed since we last showed completions
    ! IMPORTANT: Compare actual length (NOT trimmed!) to handle trailing spaces correctly
    tab_buffer_changed = .not. state_buffer_equals_last_completion(input_state)

    ! Attempt smart completion (pass input_state%length to preserve trailing spaces)
    call smart_tab_complete(tab_partial_input, tab_completions, &
                           tab_num_completions, tab_completed_line, tab_completed, input_state%length)

    if (tab_num_completions == 0) then
      ! No completions found - ring bell
      write(output_unit, '(a)', advance='no') char(7)
      flush(output_unit)
    else if (tab_completed) then
      ! We have a completed line - update buffer
      ! For glob patterns, always consider it as progress (inline expansion happened)
      ! For regular completion, check if line got longer
      tab_made_progress = (len_trim(tab_completed_line) > len_trim(tab_saved_input)) .or. &
                         has_glob_chars(tab_partial_input)

      call state_buffer_set(input_state, tab_completed_line)
      input_state%length = len_trim(tab_completed_line)
      input_state%cursor_pos = input_state%length
      input_state%dirty = .true.

      ! Recompute autosuggestion for the completed buffer — without this,
      ! the stale suggestion from before tab (e.g. "tsh" for "fort" → "fortsh")
      ! persists and renders as ghost text after the completed word.
      call update_autosuggestion(input_state)

      if (tab_num_completions > 1) then
        if (tab_made_progress) then
          input_state%completions_shown = .false.
        else
          if (.not. input_state%completions_shown .or. tab_buffer_changed) then
            ! First tab - store completions and draw grid menu
            call menu_setup_items(input_state, tab_completions, tab_num_completions)
            write(output_unit, '()')  ! Blank line before menu
            call draw_completion_menu(input_state, .true.)
            call state_last_completion_buffer_set_from_buffer(input_state)
            input_state%completions_shown = .true.
            ! Don't set dirty - menu is already drawn, no need to redraw command line
          else
            ! Second tab - enter menu selection mode
            ! Activate menu mode (items already stored and displayed)
            input_state%in_menu_select = .true.

            ! Clear autosuggestion when entering menu mode
            input_state%suggestion = ''
            input_state%suggestion_length = 0

            ! Store menu prefix (use actual length, NOT trimmed!)
            last_space_pos = 0
            do i = input_state%length, 1, -1
              if (tab_partial_input(i:i) == ' ') then
                last_space_pos = i
                exit
              end if
            end do

            if (last_space_pos > 0) then
#ifdef __APPLE__
              ! Copy character by character to avoid substring on allocatable (flang-new bug)
              ! __APPLE__ implies USE_C_STRINGS, so use allocatable directly
              input_state%menu_prefix = ''
              do j = 1, last_space_pos
                input_state%menu_prefix(j:j) = tab_partial_input(j:j)
              end do
#else
              ! Linux: Direct substring operation works fine
#ifdef USE_MEMORY_POOL
              input_state%menu_prefix_ref%data = tab_partial_input(:last_space_pos)
#else
              input_state%menu_prefix = tab_partial_input(:last_space_pos)
#endif
#endif
              input_state%menu_prefix_len = last_space_pos
            else
#ifdef USE_C_STRINGS
              input_state%menu_prefix = ''
#elif defined(USE_MEMORY_POOL)
              input_state%menu_prefix_ref%data = ''
#else
              input_state%menu_prefix = ''
#endif
              input_state%menu_prefix_len = 0
            end if

            ! Advance selection to second item to show we've entered menu mode
            ! Update in place without reprinting the whole menu
            if (input_state%menu_num_items > 1) then
              input_state%menu_selection = 2  ! Change from 1 to 2
              call update_menu_selection(input_state, 1)  ! Update display (old was 1, new is 2)
            end if
            flush(output_unit)
          end if
        end if
      end if
    else
      ! We have completions but no single completion to apply
      ! Show the available options
      if (.not. input_state%completions_shown .or. tab_buffer_changed) then
        ! First tab - store completions and draw grid menu
        call menu_setup_items(input_state, tab_completions, tab_num_completions)
        write(output_unit, '()')  ! Blank line before menu
        call draw_completion_menu(input_state, .true.)
        call state_last_completion_buffer_set_from_buffer(input_state)
        input_state%completions_shown = .true.
        ! Don't set dirty - command line is already displayed above menu
      else
        ! Second tab - enter menu selection mode
        ! Activate menu mode (items already stored and displayed)
        input_state%in_menu_select = .true.

        ! Clear autosuggestion when entering menu mode
        input_state%suggestion = ''
        input_state%suggestion_length = 0

        ! Store menu prefix (use actual length, NOT trimmed!)
        last_space_pos = 0
        do i = input_state%length, 1, -1
          if (tab_partial_input(i:i) == ' ') then
            last_space_pos = i
            exit
          end if
        end do

        if (last_space_pos > 0) then
#ifdef __APPLE__
          ! Copy character by character to avoid substring on allocatable (flang-new bug)
          ! __APPLE__ implies USE_C_STRINGS, so use allocatable directly
          input_state%menu_prefix = ''
          do i = 1, last_space_pos
            input_state%menu_prefix(i:i) = tab_partial_input(i:i)
          end do
#else
          ! Linux: Direct substring operation works fine
#ifdef USE_MEMORY_POOL
          input_state%menu_prefix_ref%data = tab_partial_input(:last_space_pos)
#else
          input_state%menu_prefix = tab_partial_input(:last_space_pos)
#endif
#endif
          input_state%menu_prefix_len = last_space_pos
        else
#ifdef USE_C_STRINGS
          input_state%menu_prefix = ''
#elif defined(USE_MEMORY_POOL)
          input_state%menu_prefix_ref%data = ''
#else
          input_state%menu_prefix = ''
#endif
          input_state%menu_prefix_len = 0
        end if

        ! Advance selection to second item to show we've entered menu mode
        ! Update in place without reprinting the whole menu
        if (input_state%menu_num_items > 1) then
          input_state%menu_selection = 2  ! Change from 1 to 2
          call update_menu_selection(input_state, 1)  ! Update display (old was 1, new is 2)
          ! Update command line preview with selected item
          call update_live_preview(input_state)
        end if
        flush(output_unit)
      end if
    end if
  end subroutine handle_tab_key_separate

  subroutine handle_tab_completion(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: partial_input
    character(len=MAX_LINE_LEN) :: completions(MAX_LOCAL_COMPLETIONS)
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
    call state_buffer_get(input_state, partial_input)
    partial_input = partial_input(:input_state%length)
    saved_input = partial_input

    ! Check if buffer has changed since we last showed completions
    buffer_changed = .not. state_buffer_equals_last_completion(input_state)

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
      call state_buffer_set(input_state, completed_line)
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
            ! Store completions for menu mode and draw once
            call menu_setup_items(input_state, completions, num_completions)
            write(output_unit, '()')  ! Blank line before menu
            call draw_completion_menu(input_state, .true.)
            call state_last_completion_buffer_set_from_buffer(input_state)
            input_state%completions_shown = .true.
            ! Don't set dirty - command line is already displayed above menu
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
        ! First tab - store completions and draw menu
        call menu_setup_items(input_state, completions, num_completions)
        write(output_unit, '()')  ! Blank line before menu
        call draw_completion_menu(input_state, .true.)
        call state_last_completion_buffer_set_from_buffer(input_state)
        input_state%completions_shown = .true.
        ! Don't set dirty - command line is already displayed above menu
      else
        ! Second tab (double-tab) - enter menu selection mode!
        call enter_menu_select_mode(input_state, completions, num_completions, partial_input)
      end if
    end if
  end subroutine

  ! ===========================================================================
  ! Menu Selection Mode (zsh/fish-style interactive completion)
  ! ===========================================================================

  ! Configure menu item sourcing and reset the pager window for a fresh
  ! menu. The pager store backs the menu when it covers the completion
  ! set (making it scrollable past MAX_MENU_ITEMS); otherwise fall back
  ! to copying into the fixed menu_items array.
  subroutine menu_setup_items(input_state, completions, num_completions)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: completions(:)
    integer, intent(in) :: num_completions
    character(len=MAX_MENU_ITEM_LEN) :: temp_buffer
    integer :: i, j, copy_len

    pager_active = (pager_item_count > 0 .and. pager_item_count >= num_completions)
    if (pager_active) then
      input_state%menu_num_items = pager_item_count
    else
      input_state%menu_num_items = min(num_completions, MAX_MENU_ITEMS)
      do i = 1, input_state%menu_num_items
        ! Copy via temp buffer to avoid flang-new bugs with allocatables
        temp_buffer = ' '
        copy_len = min(MAX_MENU_ITEM_LEN, len_trim(completions(i)))
        do j = 1, copy_len
          temp_buffer(j:j) = completions(i)(j:j)
        end do
        input_state%menu_items(i) = temp_buffer
      end do
    end if
    input_state%menu_total_items = max(input_state%menu_num_items, completion_total_matches)
    input_state%menu_selection = 1
    input_state%menu_row_start = 1
    input_state%menu_disclosed = .false.
    menu_edge_armed = 0
  end subroutine

  ! Menu item accessor: pager-backed menus read from the module store,
  ! fixed menus (process kill, small fallbacks) from menu_items
  function menu_item_get(input_state, idx) result(item)
    type(input_state_t), intent(in) :: input_state
    integer, intent(in) :: idx
    character(len=MAX_MENU_ITEM_LEN) :: item

    if (pager_active) then
      item = pager_items(idx)
    else
      item = input_state%menu_items(idx)
    end if
  end function

  subroutine enter_menu_select_mode(input_state, completions, num_completions, current_input)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN), intent(in) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(in) :: num_completions
    character(len=*), intent(in) :: current_input
    integer :: i, last_space_pos

    ! Store menu items (matches the already-drawn first-tab menu)
    input_state%in_menu_select = .true.
    call menu_setup_items(input_state, completions, num_completions)

    ! Clear autosuggestion when entering menu mode
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    ! Find the prefix (everything before the last word being completed)
    last_space_pos = 0
    do i = len_trim(current_input), 1, -1
      if (current_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do

    if (last_space_pos > 0) then
      ! Copy character by character to avoid substring on allocatable
#ifdef USE_C_STRINGS
      input_state%menu_prefix = ''
#elif defined(USE_MEMORY_POOL)
      input_state%menu_prefix_ref%data = ''
#else
      input_state%menu_prefix = ''
#endif
      do i = 1, last_space_pos
#ifdef USE_C_STRINGS
        input_state%menu_prefix(i:i) = current_input(i:i)
#elif defined(USE_MEMORY_POOL)
        input_state%menu_prefix_ref%data(i:i) = current_input(i:i)
#else
        input_state%menu_prefix(i:i) = current_input(i:i)
#endif
      end do
      input_state%menu_prefix_len = last_space_pos  ! Store length WITH the space
    else
#ifdef USE_C_STRINGS
      input_state%menu_prefix = ''
#elif defined(USE_MEMORY_POOL)
      input_state%menu_prefix_ref%data = ''
#else
      input_state%menu_prefix = ''
#endif
      input_state%menu_prefix_len = 0
    end if

    ! Advance selection to second item to make it clear we've entered menu mode
    ! This provides visual feedback that menu selection is now active
    ! Update in place without reprinting the whole menu
    if (input_state%menu_num_items > 1) then
      input_state%menu_selection = 2  ! Change from 1 to 2
      call update_menu_selection(input_state, 1)  ! Update display (old was 1, new is 2)
      ! Show initial preview
      call update_live_preview(input_state)
    end if
    flush(output_unit)
  end subroutine

  ! Compute the pager window height for the current menu: how many grid
  ! rows fit, honoring fish-style disclosure. Mirrors fish's pager:
  ! undisclosed menus get at most max(height/2, 4) rows; disclosed menus
  ! the full available height. A remainder of exactly one row is shown
  ! instead of spending the progress line announcing it.
  subroutine menu_window_metrics(input_state, total_rows, visible_rows)
    type(input_state_t), intent(in) :: input_state
    integer, intent(out) :: total_rows, visible_rows
    integer :: term_rows, term_cols, avail
    logical :: success

    success = get_terminal_size(term_rows, term_cols)
    if (.not. success .or. term_rows <= 0) term_rows = 24

    total_rows = input_state%menu_num_rows

    ! Reserve: command line + blank line + progress line
    avail = max(term_rows - 3, 4)
    if (input_state%menu_disclosed) then
      visible_rows = min(total_rows, avail)
    else
      visible_rows = min(total_rows, max(avail / 2, 4))
      if (total_rows - visible_rows == 1) visible_rows = total_rows
    end if
  end subroutine

  ! Render the menu window. The caller positions the cursor at the start
  ! of the first menu line (the line after the blank separator). Output
  ! is assembled in rdraw_buf and flushed in one write() so the terminal
  ! repaints once per frame — no flicker. Rows are overwritten in place
  ! (ESC[K clears each line's tail); ESC[J at the end drops any lines a
  ! previous taller render left behind. The cursor ends on the line after
  ! the last drawn line, which all erase math relies on (menu_drawn_lines).
  subroutine draw_completion_menu(input_state, initial_draw)
    type(input_state_t), intent(inout) :: input_state  ! inout to cache layout
    logical, intent(in) :: initial_draw
    integer :: i, j, cols_per_item, items_per_row, col, item_idx
    integer :: term_rows, term_cols, item_len
    integer :: total_rows, visible_rows, row, row_stop
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=128) :: progress
    character(len=32) :: numbuf
    logical :: success

    if (.false.) print *, initial_draw  ! Silence unused warning

    ! Get terminal size
    success = get_terminal_size(term_rows, term_cols)
    if (.not. success .or. term_cols <= 0) then
      term_cols = 80
    end if

    ! Calculate layout (ALWAYS recalculate to ensure correctness)
    ! Note: Caller is responsible for outputting initial newline before calling with initial_draw=true
    cols_per_item = 0
    do i = 1, input_state%menu_num_items
      current_item = menu_item_get(input_state, i)
      item_len = len_trim(current_item)
      cols_per_item = max(cols_per_item, item_len)
    end do
    cols_per_item = cols_per_item + 2  ! Add spacing
    items_per_row = max(1, term_cols / cols_per_item)

    ! Cache the layout (always update cache for use by update_live_preview and navigation)
    input_state%menu_cols_per_item = cols_per_item
    input_state%menu_items_per_row = items_per_row
    input_state%menu_num_rows = (input_state%menu_num_items + items_per_row - 1) / items_per_row

    ! Pager window: clamp the start row so the window stays on the grid
    call menu_window_metrics(input_state, total_rows, visible_rows)
    if (input_state%menu_row_start > total_rows - visible_rows + 1) then
      input_state%menu_row_start = total_rows - visible_rows + 1
    end if
    if (input_state%menu_row_start < 1) input_state%menu_row_start = 1
    input_state%menu_visible_rows = visible_rows
    row_stop = input_state%menu_row_start + visible_rows - 1

    call rdraw_append(char(27) // '[?25l')  ! Hide cursor during the frame

    ! Draw visible rows, overwriting in place
    do row = input_state%menu_row_start, row_stop
      do col = 1, items_per_row
        item_idx = (row - 1) * items_per_row + col
        if (item_idx > input_state%menu_num_items) exit

        ! Sanitize control/escape bytes for DISPLAY only (insertion uses
        ! the real item value) so a malicious filename can't inject ANSI
        current_item = sanitize_for_display(menu_item_get(input_state, item_idx))
        item_len = len_trim(current_item)

        if (item_idx == input_state%menu_selection) then
          call rdraw_append(char(27) // '[7m')  ! Reverse video
        end if
        call rdraw_append(current_item(1:item_len))
        if (item_idx == input_state%menu_selection) then
          call rdraw_append(char(27) // '[0m')  ! Reset
        end if

        ! Pad to column width for alignment (except after the row's last item)
        if (col < items_per_row .and. item_idx < input_state%menu_num_items) then
          do j = item_len + 1, cols_per_item
            call rdraw_append(' ')
          end do
        end if
      end do
      call rdraw_append(char(27) // '[K' // char(13) // char(10))  ! Clear tail, next line
    end do

    ! Progress line (fish parity): undisclosed remainder, scroll position,
    ! or storage truncation
    progress = ''
    if (.not. input_state%menu_disclosed .and. total_rows > visible_rows) then
      write(numbuf, '(i0)') total_rows - visible_rows
      progress = '...and ' // trim(numbuf) // ' more rows'
    else if (input_state%menu_row_start > 1 .or. row_stop < total_rows) then
      write(progress, '(a,i0,a,i0,a,i0)') &
        'rows ', input_state%menu_row_start, ' to ', row_stop, ' of ', total_rows
    end if
    if (input_state%menu_total_items > input_state%menu_num_items) then
      write(numbuf, '(i0)') input_state%menu_total_items - input_state%menu_num_items
      if (len_trim(progress) > 0) then
        progress = trim(progress) // '; ' // trim(numbuf) // ' more items not shown'
      else
        progress = '  ... ' // trim(numbuf) // ' more items available'
      end if
    end if

    if (len_trim(progress) > 0) then
      call rdraw_append(trim(progress) // char(27) // '[K' // char(13) // char(10))
      input_state%menu_drawn_lines = visible_rows + 1
    else
      input_state%menu_drawn_lines = visible_rows
    end if

    ! Clear anything below from a previous taller render, show cursor
    call rdraw_append(char(27) // '[J' // char(27) // '[?25h')
    call rdraw_flush()
  end subroutine

  subroutine handle_menu_navigation(input_state, key, done)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    logical, intent(inout) :: done
    integer :: old_selection, new_selection
    integer :: items_per_row
    integer :: current_row, current_col, target_row, last_row

    if (.false.) print *, done  ! Silence unused warning (set by caller)

    if (.not. input_state%in_menu_select) return

    old_selection = input_state%menu_selection

    select case (key)
    case (KEY_UP, KEY_DOWN)
      ! 2D navigation: move up/down by one row in the grid, STOPPING at the
      ! top/bottom (no infinite wrap). When already at the edge, the next
      ! same-direction press jumps to the opposite edge. (AR-03 NEW-2)
      items_per_row = input_state%menu_items_per_row

      current_row = (input_state%menu_selection - 1) / items_per_row + 1
      current_col = mod(input_state%menu_selection - 1, items_per_row) + 1
      last_row = (input_state%menu_num_items - 1) / items_per_row + 1

      if (key == KEY_UP) then
        if (current_row <= 1) then
          ! At the top. First press: stop (no move) and arm. Repeat: jump
          ! to the last item.
          if (menu_edge_armed == 1) then
            input_state%menu_selection = input_state%menu_num_items
            menu_edge_armed = 0
          else
            menu_edge_armed = 1
          end if
        else
          target_row = current_row - 1
          new_selection = (target_row - 1) * items_per_row + current_col
          if (new_selection < 1) new_selection = 1
          if (new_selection > input_state%menu_num_items) &
            new_selection = input_state%menu_num_items
          input_state%menu_selection = new_selection
          menu_edge_armed = 0
        end if
      else  ! KEY_DOWN
        ! "At the bottom" = the cell one row down (same column) does not exist.
        if (current_row >= last_row .or. &
            current_row * items_per_row + current_col > input_state%menu_num_items) then
          if (menu_edge_armed == 2) then
            input_state%menu_selection = 1
            menu_edge_armed = 0
          else
            menu_edge_armed = 2
          end if
        else
          target_row = current_row + 1
          new_selection = (target_row - 1) * items_per_row + current_col
          if (new_selection > input_state%menu_num_items) &
            new_selection = input_state%menu_num_items
          input_state%menu_selection = new_selection
          menu_edge_armed = 0
        end if
      end if

    case (KEY_LEFT)
      ! Move left one item (same row)
      menu_edge_armed = 0
      input_state%menu_selection = input_state%menu_selection - 1
      if (input_state%menu_selection < 1) then
        input_state%menu_selection = input_state%menu_num_items  ! Wrap to end
      end if

    case (KEY_RIGHT)
      ! Move right one item (same row)
      menu_edge_armed = 0
      input_state%menu_selection = input_state%menu_selection + 1
      if (input_state%menu_selection > input_state%menu_num_items) then
        input_state%menu_selection = 1  ! Wrap to beginning
      end if

    case (KEY_TAB)
      ! Tab continues to cycle sequentially through all items (wrap is fine —
      ! Tab is the explicit "cycle through everything" key, not scroll)
      menu_edge_armed = 0
      input_state%menu_selection = input_state%menu_selection + 1
      if (input_state%menu_selection > input_state%menu_num_items) then
        input_state%menu_selection = 1
      end if

    case (10, 13)  ! Enter (LF or CR)
      ! Accept selection - insert into command line and continue editing
      call accept_menu_selection(input_state)
      ! Don't set done = .true. - let user continue editing
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
      ! Update command line preview with selected item
      call update_live_preview(input_state)
    end if
  end subroutine

  subroutine accept_menu_selection(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: completed_line
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=1) :: ch
    integer :: i, j, item_len, completed_len

    ! Build completed command character by character (copy to local vars first)
    completed_line = ''
    completed_len = 0

    if (input_state%menu_prefix_len > 0) then
      ! Copy directly from menu_prefix character-by-character (avoid temp assignment)
      ! CRITICAL: Don't use intermediate variable - flang-new bug causes corruption
      do i = 1, input_state%menu_prefix_len
#ifdef USE_C_STRINGS
        ch = input_state%menu_prefix(i:i)
#elif defined(USE_MEMORY_POOL)
        ch = input_state%menu_prefix_ref%data(i:i)
#else
        ch = input_state%menu_prefix(i:i)
#endif
        completed_len = completed_len + 1
        completed_line(completed_len:completed_len) = ch
      end do
    end if

    current_item = menu_item_get(input_state, input_state%menu_selection)
    item_len = len_trim(current_item)
    do j = 1, item_len
      ch = current_item(j:j)
      completed_len = completed_len + 1
      completed_line(completed_len:completed_len) = ch
    end do

    ! Exit menu mode FIRST (clears menu from screen and positions cursor at start of command line)
    call exit_menu_select_mode(input_state)

    ! Update buffer after menu is cleared
    call state_buffer_set(input_state, completed_line)
    input_state%length = completed_len
    input_state%cursor_pos = completed_len  ! Cursor at end

    ! Mark dirty to trigger redraw (exit_menu_select_mode already set
    ! skip_cursor_up_on_redraw and invalidated the display-diff frames)
    input_state%dirty = .true.

    ! Update autosuggestion for future use
    call update_autosuggestion(input_state)
  end subroutine

  subroutine exit_menu_select_mode(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i

    ! Clear the menu from screen before exiting
    if (input_state%menu_num_items > 0) then
      ! Move cursor up to where the command line was. The cursor is parked
      ! on the line after the last drawn menu line; erase what was drawn,
      ! not a recomputed layout (the window may show fewer rows than the
      ! item count implies, and the terminal may have resized since).
      ! Layout: [cmd][blank][drawn menu lines][cursor here]
      do i = 1, input_state%menu_drawn_lines + 2
        call rdraw_append(char(27) // '[A')  ! Cursor up
      end do

      ! Now at command line - clear from next line down to remove menu
      call rdraw_append(char(13))            ! Start of command line
      call rdraw_append(char(27) // '[K')    ! Clear current line (old command)
      call rdraw_append(char(27) // '[B')    ! Down to blank line
      call rdraw_append(char(27) // '[J')    ! Clear from cursor down (all menu)
      call rdraw_append(char(27) // '[A')    ! Back up to command line
      call rdraw_append(char(13))            ! Start of command line
      call rdraw_flush()

      ! Cursor is now at the start of the command line row with the screen
      ! below cleared. The next redraw must start from here rather than
      ! moving up, and the display-diff frames are stale. Every menu exit
      ! path needs this, not just Enter-accept.
      input_state%skip_cursor_up_on_redraw = .true.
      prev_diff_valid = .false.
      prev_render_valid = .false.
    end if

    input_state%in_menu_select = .false.
    input_state%menu_num_items = 0
    input_state%menu_total_items = 0
    input_state%menu_selection = 1
    input_state%menu_prefix_len = 0
    input_state%menu_row_start = 1
    input_state%menu_disclosed = .false.
    input_state%menu_visible_rows = 0
    input_state%menu_drawn_lines = 0
    input_state%completions_shown = .false.
    pager_active = .false.
    input_state%dirty = .true.
  end subroutine

  ! Activate menu selection on a table that is already drawn (first tab,
  ! not yet entered) — used when an arrow key enters the menu, matching
  ! fish's pager. Same activation as the second-tab path but without
  ! advancing the selection: the arrow itself navigates from item 1.
  subroutine activate_menu_select_from_shown(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: buf
    integer :: i, last_space_pos

    input_state%in_menu_select = .true.

    ! Clear autosuggestion when entering menu mode
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    ! Derive menu prefix from the current buffer (unchanged since the tab
    ! that drew the table — any edit would have dismissed it)
    call state_buffer_get(input_state, buf)
    last_space_pos = 0
    do i = input_state%length, 1, -1
      if (buf(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do

    if (last_space_pos > 0) then
#ifdef __APPLE__
      ! Copy character by character to avoid substring on allocatable (flang-new bug)
      input_state%menu_prefix = ''
      do i = 1, last_space_pos
        input_state%menu_prefix(i:i) = buf(i:i)
      end do
#else
#ifdef USE_MEMORY_POOL
      input_state%menu_prefix_ref%data = buf(:last_space_pos)
#else
      input_state%menu_prefix = buf(:last_space_pos)
#endif
#endif
      input_state%menu_prefix_len = last_space_pos
    else
#ifdef USE_C_STRINGS
      input_state%menu_prefix = ''
#elif defined(USE_MEMORY_POOL)
      input_state%menu_prefix_ref%data = ''
#else
      input_state%menu_prefix = ''
#endif
      input_state%menu_prefix_len = 0
    end if
  end subroutine

  ! Erase the drawn table without touching the command line row, leaving
  ! the cursor on the command line at column 0. Used when Enter submits
  ! with the table shown but not entered: exit_menu_select_mode would
  ! clear the command line row and schedule a redraw, but submission
  ! needs the rendered line left intact.
  subroutine clear_menu_display_below(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i

    if (input_state%menu_num_items <= 0) return

    ! Layout: [cmd][blank][drawn menu lines][cursor here]
    ! Move up to the blank line, erase it and everything below, then step
    ! up onto the command line row
    do i = 1, input_state%menu_drawn_lines + 1
      call rdraw_append(char(27) // '[A')
    end do
    call rdraw_append(char(13))
    call rdraw_append(char(27) // '[J')
    call rdraw_append(char(27) // '[A')
    call rdraw_flush()

    input_state%menu_num_items = 0
    input_state%menu_total_items = 0
    input_state%menu_selection = 1
    input_state%menu_prefix_len = 0
    input_state%menu_row_start = 1
    input_state%menu_disclosed = .false.
    input_state%menu_visible_rows = 0
    input_state%menu_drawn_lines = 0
    input_state%completions_shown = .false.
    pager_active = .false.
  end subroutine

  subroutine update_menu_selection(input_state, old_selection)
    type(input_state_t), intent(inout) :: input_state  ! inout to pass to draw function
    integer, intent(in) :: old_selection
    integer :: i, total_rows, visible_rows, sel_row, old_drawn
    logical :: scrolled

    ! Window adjustment (fish): selection above the window pulls it up;
    ! selection below it discloses first, then scrolls
    call menu_window_metrics(input_state, total_rows, visible_rows)
    sel_row = (input_state%menu_selection - 1) / input_state%menu_items_per_row + 1
    scrolled = .false.
    if (sel_row < input_state%menu_row_start) then
      input_state%menu_row_start = sel_row
      scrolled = .true.
    else if (sel_row > input_state%menu_row_start + visible_rows - 1) then
      if (.not. input_state%menu_disclosed) then
        input_state%menu_disclosed = .true.
        call menu_window_metrics(input_state, total_rows, visible_rows)
      end if
      if (sel_row > input_state%menu_row_start + visible_rows - 1) then
        input_state%menu_row_start = sel_row - visible_rows + 1
      end if
      scrolled = .true.
    end if

    if (scrolled) then
      ! Window moved or grew: reposition to the menu top and repaint the
      ! whole window in one buffered frame (overwrite in place, no
      ! blank-then-redraw, so no flicker)
      old_drawn = input_state%menu_drawn_lines
      call rdraw_append(char(13))
      do i = 1, old_drawn
        call rdraw_append(char(27) // '[A')
      end do
      call draw_completion_menu(input_state, .false.)
    else
      ! Window unchanged: rewrite only the two cells whose highlight
      ! changed (~60 bytes instead of a full repaint)
      call menu_redraw_cell(input_state, old_selection, .false.)
      call menu_redraw_cell(input_state, input_state%menu_selection, .true.)
      call rdraw_flush()
    end if
  end subroutine

  ! Rewrite one menu cell in place, relative to the parked cursor (the
  ! line after the last drawn menu line). Appends to rdraw_buf; the
  ! caller flushes. Off-window indices are ignored.
  subroutine menu_redraw_cell(input_state, item_idx, selected)
    type(input_state_t), intent(in) :: input_state
    integer, intent(in) :: item_idx
    logical, intent(in) :: selected
    integer :: row, col, vrow, up, left, item_len
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=16) :: numbuf

    if (item_idx < 1 .or. item_idx > input_state%menu_num_items) return
    if (input_state%menu_items_per_row <= 0) return
    row = (item_idx - 1) / input_state%menu_items_per_row + 1
    if (row < input_state%menu_row_start .or. &
        row > input_state%menu_row_start + input_state%menu_visible_rows - 1) return
    col = mod(item_idx - 1, input_state%menu_items_per_row) + 1
    vrow = row - input_state%menu_row_start + 1
    up = input_state%menu_drawn_lines - vrow + 1
    left = (col - 1) * input_state%menu_cols_per_item

    current_item = sanitize_for_display(menu_item_get(input_state, item_idx))
    item_len = len_trim(current_item)

    call rdraw_append(char(13))
    write(numbuf, '(i0)') up
    call rdraw_append(char(27) // '[' // trim(numbuf) // 'A')
    if (left > 0) then
      write(numbuf, '(i0)') left
      call rdraw_append(char(27) // '[' // trim(numbuf) // 'C')
    end if
    if (selected) call rdraw_append(char(27) // '[7m')
    if (item_len > 0) call rdraw_append(current_item(1:item_len))
    if (selected) call rdraw_append(char(27) // '[0m')
    ! Park the cursor back on the line after the last drawn line
    write(numbuf, '(i0)') up
    call rdraw_append(char(27) // '[' // trim(numbuf) // 'B' // char(13))
  end subroutine

  subroutine update_live_preview(input_state)
    type(input_state_t), intent(in) :: input_state
    integer :: i, j, up_rows, prompt_rows
    integer :: prompt_len, highlighted_len, item_len, preview_len
    character(len=MAX_LINE_LEN) :: preview_line, current_prefix
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=MAX_HIGHLIGHT_LEN) :: highlighted_preview  ! Fixed-length to avoid flang-new bugs
    character(len=16) :: numbuf
    character(len=1) :: ch

    ! Initialize buffer
    highlighted_preview = ' '
    highlighted_len = 0
    preview_line = ''

    ! menu_prompt holds the FULL prompt, which may span several terminal
    ! rows (the default fortsh prompt is two lines). The rewrite below
    ! re-emits all of it, so the up-move must land on the FIRST prompt
    ! row: one per drawn menu line, plus one per prompt row. (The "blank
    ! separator" is just the newline terminating the command line — it
    ! does not occupy a row of its own.)
    prompt_rows = 1
    do i = 1, len_trim(input_state%menu_prompt)
      if (input_state%menu_prompt(i:i) == char(10)) prompt_rows = prompt_rows + 1
    end do
    up_rows = input_state%menu_drawn_lines + prompt_rows

    call rdraw_append(char(27) // '[?25l')

    ! Build preview line character by character (copy to local vars first)
    preview_len = 0
    if (input_state%menu_prefix_len > 0) then
      ! IMPORTANT: Copy allocatable menu_prefix character-by-character to avoid flang-new bug
      ! Direct assignment creates a temporary that gets corrupted
      current_prefix = ''  ! Initialize
      do i = 1, input_state%menu_prefix_len
#ifdef USE_C_STRINGS
        current_prefix(i:i) = input_state%menu_prefix(i:i)
#elif defined(USE_MEMORY_POOL)
        current_prefix(i:i) = input_state%menu_prefix_ref%data(i:i)
#else
        current_prefix(i:i) = input_state%menu_prefix(i:i)
#endif
      end do

      ! Now copy to preview_line
      do i = 1, input_state%menu_prefix_len
        ch = current_prefix(i:i)
        preview_len = preview_len + 1
        preview_line(preview_len:preview_len) = ch
      end do
    end if
    current_item = menu_item_get(input_state, input_state%menu_selection)
    item_len = len_trim(current_item)
    do j = 1, item_len
      ch = current_item(j:j)
      preview_len = preview_len + 1
      preview_line(preview_len:preview_len) = ch
    end do

    ! Move cursor up past the menu to the first prompt row
    do i = 1, up_rows
      call rdraw_append(char(27) // '[A')  ! Cursor up
    end do

    ! Move to start of line
    call rdraw_append(char(13))  ! CR

    ! Clear the entire line
    call rdraw_append(char(27) // '[K')  ! Clear from cursor to end of line

    ! Apply syntax highlighting to preview (use preview_len we calculated)
    call highlight_command_line(preview_line, highlighted_preview, highlighted_len, preview_len)

    ! Redraw prompt character by character (copy to local var first)
    ! IMPORTANT: Copy allocatable menu_prompt character-by-character to avoid flang-new bug
    current_prefix = ''
    prompt_len = len_trim(input_state%menu_prompt)
    if (prompt_len > 0) then
      do i = 1, prompt_len
        current_prefix(i:i) = input_state%menu_prompt(i:i)
      end do
      call rdraw_append(current_prefix(1:prompt_len))
    end if

    ! Write space after prompt (to match the original spacing)
    call rdraw_append(' ')

    ! Redraw highlighted preview
    if (highlighted_len > 0 .and. highlighted_len <= MAX_HIGHLIGHT_LEN) then
      call rdraw_append(highlighted_preview(1:highlighted_len))
    end if

    ! Clear the tail of the command row: ESC[K at the top of this frame
    ! only cleared the FIRST prompt row, so a longer previous preview
    ! would otherwise leave its tail behind on this row
    call rdraw_append(char(27) // '[K')

    ! Park the cursor back on the line after the last drawn menu line,
    ! with relative moves only — ESC[u is unreliable across terminals
    ! and breaks if the prompt rewrite ever scrolls the screen
    write(numbuf, '(i0)') input_state%menu_drawn_lines + 1
    call rdraw_append(char(27) // '[' // trim(numbuf) // 'B' // char(13) // char(27) // '[?25h')

    call rdraw_flush()
    ! highlighted_preview is now fixed-length, no deallocation needed
  end subroutine

  ! ===========================================================================
  ! Process Kill Mode (Ctrl-X quick process termination)
  ! ===========================================================================

  subroutine enter_process_kill_mode(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: processes(MAX_MENU_ITEMS)
    integer :: pids(MAX_MENU_ITEMS)
    integer :: num_processes, i

    ! Get process list
    call get_process_list(processes, pids, num_processes)

    if (num_processes == 0) then
      write(output_unit, '(a)') ''
      write(output_unit, '(a)') 'No processes found.'
      return
    end if

    ! Clear the current line
    write(output_unit, '(a)', advance='no') char(13)  ! CR
    write(output_unit, '(a)', advance='no') char(27) // '[K'  ! Clear line

    ! Enter process kill mode
    input_state%in_process_kill_mode = .true.
    input_state%in_menu_select = .true.  ! Reuse menu selection infrastructure
    input_state%menu_num_items = num_processes
    pager_active = .false.               ! Process menu reads menu_items directly
    input_state%menu_row_start = 1
    input_state%menu_disclosed = .false.

    ! Store process info in menu items (format: "PID: process_name")
    do i = 1, num_processes
      write(input_state%menu_items(i), '(i8,a,a)') pids(i), ': ', trim(processes(i))
    end do

    ! Store PIDs for later use (we'll extract from menu_items when needed)
    input_state%menu_selection = 1

    ! Draw the process menu
    write(output_unit, '(a)') 'Select process to signal (arrow keys to navigate, Enter to select, ESC to cancel):'
    call draw_completion_menu(input_state, .true.)
  end subroutine

  subroutine get_process_list(processes, pids, num_processes)
    use system_interface, only: execute_and_capture
    character(len=MAX_LINE_LEN), intent(out) :: processes(MAX_MENU_ITEMS)
    integer, intent(out) :: pids(MAX_MENU_ITEMS)
    integer, intent(out) :: num_processes

    integer :: iostat, pid, line_start, line_end, output_len
    character(len=512) :: line, cmd_name, username
    character(len=:), allocatable :: ps_output
    integer :: stat

    num_processes = 0

    call get_environment_variable('USER', username, status=stat)
    if (stat /= 0) username = ''

    ! Capture ps output via pipe+fork (no temp file, no world-readable leak)
#if defined(__APPLE__) || defined(__FreeBSD__)
    if (len_trim(username) > 0) then
      ps_output = execute_and_capture('ps -u ' // trim(username) // ' -o pid= -o comm=')
    else
      ps_output = execute_and_capture('ps -ax -o pid= -o comm=')
    end if
#else
    if (len_trim(username) > 0) then
      ps_output = execute_and_capture('ps -u ' // trim(username) // ' -o pid,comm --no-headers')
    else
      ps_output = execute_and_capture('ps -eo pid,comm --no-headers')
    end if
#endif

    if (.not. allocated(ps_output)) return
    output_len = len(ps_output)
    if (output_len == 0) return

    ! Parse line by line from captured output
    line_start = 1
    do while (line_start <= output_len .and. num_processes < MAX_MENU_ITEMS)
      line_end = index(ps_output(line_start:), char(10))
      if (line_end == 0) then
        line = ps_output(line_start:output_len)
        line_start = output_len + 1
      else
        line_end = line_start + line_end - 2
        line = ps_output(line_start:line_end)
        line_start = line_end + 2
      end if

      if (len_trim(line) > 0 .and. index(line, 'PID') == 0) then
        read(line, *, iostat=iostat) pid, cmd_name
        if (iostat == 0) then
          num_processes = num_processes + 1
          pids(num_processes) = pid
          processes(num_processes) = trim(cmd_name)
        end if
      end if
    end do
  end subroutine

  subroutine handle_process_selection(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=256) :: pid_str
    integer :: colon_pos, iostat

    ! Extract PID from selected menu item (format: "PID: process_name")
    colon_pos = index(input_state%menu_items(input_state%menu_selection), ':')
    if (colon_pos > 0) then
      pid_str = input_state%menu_items(input_state%menu_selection)(:colon_pos-1)
      read(pid_str, *, iostat=iostat) input_state%selected_pid

      if (iostat == 0) then
        ! Store process name
        input_state%selected_process_name = &
          input_state%menu_items(input_state%menu_selection)(colon_pos+2:)

        ! Clear menu and enter signal input mode
        call exit_menu_select_mode(input_state)

        ! Enter signal input mode - like reverse-i-search
        input_state%in_process_kill_mode = .true.
        input_state%in_signal_input = .true.

        ! Clear the buffer for signal input
        call state_buffer_clear(input_state)
        input_state%length = 0
        input_state%cursor_pos = 0

        ! Clear dirty flag set by exit_menu_select_mode
        ! We handle our own display, don't want normal redraw
        input_state%dirty = .false.

        ! Display the signal prompt (like reverse-i-search display)
        call update_signal_display(input_state)
      end if
    end if
  end subroutine

  subroutine update_signal_display(input_state)
    type(input_state_t), intent(in) :: input_state
    character(len=512) :: signal_prompt
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction

    ! Build signal prompt: (signal: PID 1234 firefox):
    write(signal_prompt, '(a,i15,a,a,a)') '(signal: PID ', input_state%selected_pid, ' ', &
          trim(input_state%selected_process_name), '): '

    ! Clear line and redraw with signal prompt
    write(output_unit, '(a)', advance='no') char(13) // ESC_CLEAR_LINE
    write(output_unit, '(a)', advance='no') trim(signal_prompt)
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
    end if
    flush(output_unit)
  end subroutine

  subroutine handle_signal_input(input_state, ch)
    type(input_state_t), intent(inout) :: input_state
    character(len=1), intent(in) :: ch

    ! Add character to buffer directly (like search mode does)
    ! Don't use insert_char() to avoid setting dirty flag
    if (input_state%length < MAX_LINE_LEN) then
      input_state%length = input_state%length + 1
      call state_buffer_set_char(input_state, input_state%length, ch)
      input_state%cursor_pos = input_state%length
    end if

    ! Update the signal display (inline prompt like reverse-i-search)
    call update_signal_display(input_state)
  end subroutine

  subroutine send_signal_to_process(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: signal_num, iostat, result
    character(len=MAX_LINE_LEN) :: signal_str
    interface
      function c_kill(pid, sig) bind(C, name="kill")
        use iso_c_binding
        integer(c_int), value :: pid, sig
        integer(c_int) :: c_kill
      end function c_kill
    end interface

    ! Parse signal from buffer (can be number or SIG<name>)
    call state_buffer_get(input_state, signal_str)
    signal_str = signal_str(:input_state%length)

    ! Try to parse as number first
    read(signal_str, *, iostat=iostat) signal_num

    if (iostat /= 0) then
      ! Try to parse as signal name
      call parse_signal_name(signal_str, signal_num)
    end if

    if (signal_num > 0) then
      ! Send the signal
      result = c_kill(input_state%selected_pid, signal_num)

      if (result == 0) then
        ! Success - green
        write(output_unit, '(a)', advance='no') char(27) // '[1;32m'  ! Bold green
        write(output_unit, '(a)', advance='no') ' ✓ '
        write(output_unit, '(a)', advance='no') char(27) // '[0m'
        write(output_unit, '(a,i15,a,i15)') 'Sent signal ', signal_num, &
          ' to PID ', input_state%selected_pid
      else
        ! Failure - red
        write(output_unit, '(a)', advance='no') char(27) // '[1;31m'  ! Bold red
        write(output_unit, '(a)', advance='no') ' ✗ '
        write(output_unit, '(a)', advance='no') char(27) // '[0m'
        write(output_unit, '(a,i15,a,i0)') 'Failed to send signal ', signal_num, &
          ' to PID ', input_state%selected_pid
        write(output_unit, '(a)', advance='no') char(27) // '[33m'    ! Yellow
        write(output_unit, '(a)') ' (permission denied or process not found)'
        write(output_unit, '(a)', advance='no') char(27) // '[0m'
      end if
    else
      ! Invalid signal - red
      write(output_unit, '(a)', advance='no') char(27) // '[1;31m'  ! Bold red
      write(output_unit, '(a)', advance='no') ' ✗ '
      write(output_unit, '(a)', advance='no') char(27) // '[0m'
      write(output_unit, '(a)', advance='no') 'Invalid signal: '
      write(output_unit, '(a)', advance='no') char(27) // '[33m'    ! Yellow
      write(output_unit, '(a)', advance='no') trim(signal_str)
      write(output_unit, '(a)', advance='no') char(27) // '[0m'
      write(output_unit, '(a)') ' (use number or SIGTERM, SIGKILL, etc.)'
    end if

    ! Don't set dirty - we're exiting readline, caller will handle prompt
    ! Cleanup is done in Enter key handler
  end subroutine

  subroutine parse_signal_name(name, signal_num)
    character(len=*), intent(in) :: name
    integer, intent(out) :: signal_num
    character(len=32) :: upper_name
    integer :: i

    ! Convert to uppercase
    upper_name = name
    do i = 1, len_trim(upper_name)
      if (upper_name(i:i) >= 'a' .and. upper_name(i:i) <= 'z') then
        upper_name(i:i) = char(iachar(upper_name(i:i)) - 32)
      end if
    end do

    ! Remove SIG prefix if present
    if (upper_name(1:3) == 'SIG') then
      upper_name = upper_name(4:)
    end if

    ! Map common signal names to numbers
    select case(trim(upper_name))
    case('HUP', 'SIGHUP')
      signal_num = 1
    case('INT', 'SIGINT')
      signal_num = 2
    case('QUIT', 'SIGQUIT')
      signal_num = 3
    case('ILL', 'SIGILL')
      signal_num = 4
    case('TRAP', 'SIGTRAP')
      signal_num = 5
    case('ABRT', 'SIGABRT')
      signal_num = 6
    case('BUS', 'SIGBUS')
      signal_num = 7
    case('FPE', 'SIGFPE')
      signal_num = 8
    case('KILL', 'SIGKILL')
      signal_num = 9
    case('USR1', 'SIGUSR1')
      signal_num = 10
    case('SEGV', 'SIGSEGV')
      signal_num = 11
    case('USR2', 'SIGUSR2')
      signal_num = 12
    case('PIPE', 'SIGPIPE')
      signal_num = 13
    case('ALRM', 'SIGALRM')
      signal_num = 14
    case('TERM', 'SIGTERM')
      signal_num = 15
    case('STKFLT', 'SIGSTKFLT')
      signal_num = 16
    case('CHLD', 'SIGCHLD')
      signal_num = 17
    case('CONT', 'SIGCONT')
      signal_num = 18
    case('STOP', 'SIGSTOP')
      signal_num = 19
    case('TSTP', 'SIGTSTP')
      signal_num = 20
    case('TTIN', 'SIGTTIN')
      signal_num = 21
    case('TTOU', 'SIGTTOU')
      signal_num = 22
    case default
      signal_num = -1  ! Invalid signal
    end select
  end subroutine

  subroutine handle_escape_sequence(input_state, done, prompt)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character(len=*), intent(in) :: prompt
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

    ! Menu drawn but not entered (first tab): arrow keys enter and navigate
    ! it (fish pager behavior). Bare ESC or any other sequence dismisses the
    ! table; the key itself is swallowed (its bytes are consumed so trailing
    ! sequence characters don't leak into the line as literal input).
    if (input_state%completions_shown .and. input_state%menu_num_items > 0 .and. &
        .not. input_state%in_signal_input .and. .not. input_state%in_search) then
      success = read_single_char(ch1)
      if (.not. success) then
        ! Bare ESC - dismiss the table
        call exit_menu_select_mode(input_state)
        return
      end if

      if (ch1 == '[') then
        success = read_single_char(ch2)
        if (.not. success) return

        select case(ch2)
        case('A')
          call activate_menu_select_from_shown(input_state)
          call handle_menu_navigation(input_state, KEY_UP, done)
        case('B')
          call activate_menu_select_from_shown(input_state)
          call handle_menu_navigation(input_state, KEY_DOWN, done)
        case('C')
          call activate_menu_select_from_shown(input_state)
          call handle_menu_navigation(input_state, KEY_RIGHT, done)
        case('D')
          call activate_menu_select_from_shown(input_state)
          call handle_menu_navigation(input_state, KEY_LEFT, done)
        case default
          ! Consume the rest of the sequence (parameter bytes through the
          ! terminator) so it doesn't leak, then dismiss the table
          block
            character :: chx
            chx = ch2
            do while ((chx >= '0' .and. chx <= '9') .or. chx == ';')
              if (.not. read_single_char(chx)) exit
            end do
          end block
          call exit_menu_select_mode(input_state)
        end select
      else
        ! Alt+key combination - dismiss the table, swallow the key
        call exit_menu_select_mode(input_state)
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
    if (.not. success) then
      ! Bare ESC with no follow-up — accept search result for editing
      if (input_state%in_search) then
        call accept_search_for_editing(input_state)
      end if
      return
    end if

    if (ch1 == '[') then
      ! ANSI escape sequence
      success = read_single_char(ch2)
      if (.not. success) then
        return
      end if

      select case(ch2)
      case('A')  ! Up arrow
        ! In search mode, cancel search and restore buffer
        if (input_state%in_search) then
          call cancel_search(input_state)
        else
          call handle_history_up(input_state)
        end if
      case('B')  ! Down arrow
        ! In search mode, cancel search and restore buffer
        if (input_state%in_search) then
          call cancel_search(input_state)
        else
          call handle_history_down(input_state)
        end if
      case('C')  ! Right arrow
        ! In search mode, accept search and allow editing
        if (input_state%in_search) then
          call accept_search_for_editing(input_state)
        else
          if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
          call handle_cursor_right(input_state)
        end if
      case('D')  ! Left arrow
        ! In search mode, accept search and allow editing
        if (input_state%in_search) then
          call accept_search_for_editing(input_state)
        else
          if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
          call handle_cursor_left(input_state)
        end if
      case('2')
        ! Could be bracketed paste (ESC[200~ or ESC[201~) or extended escape
        if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
        call handle_paste_or_extended(input_state, done)
      case('1', '3', '4', '5', '6')
        ! Extended escape sequence (e.g., Ctrl+Arrow = ESC[1;5C) or simple (ESC[3~)
        if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
        call handle_extended_escape_sequence(input_state, done, ch2)
      case('H')  ! Home key (VT100/ANSI encoding; tilde variant ESC[1~ in extended handler)
        if (input_state%in_search) then
          call accept_search_for_editing(input_state)
        else
          if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
          call handle_home(input_state)
        end if
      case('F')  ! End key (VT100/ANSI encoding; tilde variant ESC[4~ in extended handler)
        if (input_state%in_search) then
          call accept_search_for_editing(input_state)
        else
          if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
          call handle_end(input_state)
        end if
      case default
        ! Unknown escape sequence - ignore it
        continue
      end select
    else
      ! Not '[', so it's an Alt+key combination (ESC followed by character)
      if (input_state%in_prefix_search) call cancel_prefix_search(input_state)
      ! In search mode, only Alt+Backspace is meaningful — everything else is no-op
      if (input_state%in_search) then
        if (ch1 == char(127)) then
          call search_kill_word(input_state, prompt)
        end if
        return
      end if

      select case(ch1)
      case('.')
        ! Alt+. - Insert last argument from previous command
        call handle_yank_last_arg(input_state)
      case('b')
        ! Alt+b - Move backward one word
        call move_to_previous_word(input_state)
      case('B')
        ! Alt+Shift+b - Extend selection one word back (shift phase, Sprint 1)
        ! ESC-uppercase is xterm's encoding for Alt+Shift+letter. Routes through
        ! the shift-extending path so move_to_previous_word grows the selection.
        module_extending_selection = .true.
        call move_to_previous_word(input_state)
        module_extending_selection = .false.
      case('d')
        ! Alt+d - Delete forward one word (emacs standard)
        call handle_kill_word_forward(input_state)
      case('f')
        ! Alt+f - Move forward one word
        call move_to_next_word(input_state)
      case('F')
        ! Alt+Shift+f - Extend selection one word forward (shift phase, Sprint 1)
        module_extending_selection = .true.
        call move_to_next_word(input_state)
        module_extending_selection = .false.
      case('j')
        ! Alt+j - Jump to directory with fzf
        call launch_fzf_directory_browser(input_state)
      case('g')
        ! Alt+g - Git browser with fzf
        call launch_fzf_git_browser(input_state)
      case('u')
        ! Alt+u - Uppercase word (from cursor to end of word)
        call handle_uppercase_word(input_state)
      case('l')
        ! Alt+l - Lowercase word (from cursor to end of word)
        call handle_lowercase_word(input_state)
      case('c')
        ! Alt+c - Capitalize word (uppercase first char, lowercase rest)
        call handle_capitalize_word(input_state)
      case('w')
        ! Alt+w — dual-mode:
        !   1. If a selection is active, copy it to the kill buffer and
        !      collapse selection (emacs kill-ring-save). Buffer unchanged;
        !      Ctrl+Y yanks it back wherever the user moves next.
        !   2. Else if the cursor is at end-of-buffer with a live autosuggestion,
        !      accept one word from the suggestion (existing behavior).
        ! (Sprint 5 adds the system-clipboard mirror.)
        if (input_state%selection_active) then
          call copy_selection_to_kill_buffer(input_state)
          call collapse_selection(input_state)
          input_state%dirty = .true.  ! force redraw without reverse video
        else if (input_state%cursor_pos == input_state%length .and. &
            input_state%suggestion_length > 0) then
          call accept_autosuggestion_word(input_state)
        end if
      case(char(127))
        ! Alt+Backspace - Delete word backward (same as Ctrl+W)
        call handle_kill_word(input_state)
      case(char(27))
        ! Alt+ESC sequence — could be Alt+Delete (ESC ESC [ 3 ~)
        block
          character :: ach1, ach2, ach3
          logical :: asuc
          asuc = read_single_char(ach1)
          if (asuc .and. ach1 == '[') then
            asuc = read_single_char(ach2)
            if (asuc .and. ach2 == '3') then
              asuc = read_single_char(ach3)
              if (asuc .and. ach3 == '~') then
                ! Alt+Delete — kill word forward
                call handle_kill_word_forward(input_state)
              end if
            end if
          end if
        end block
      case default
        ! Unknown Alt+key combination
        continue
      end select
    end if
  end subroutine

  ! Handle bracketed paste or extended escape sequences starting with '2'
  subroutine handle_paste_or_extended(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character :: ch1, ch2, ch3
    logical :: success
    character(len=MAX_LINE_LEN) :: paste_buffer
    integer :: paste_len
    character :: ch_paste
    integer :: ic, inserted

    if (.false.) print *, done  ! Silence unused warning

    ! After ESC[2, check next chars for:
    ! - 00~ = paste start (ESC[200~)
    ! - 01~ = paste end (ESC[201~)
    ! - or it's an extended sequence like ESC[2;...

    success = read_single_char(ch1)
    if (.not. success) return

    if (ch1 == '0') then
      ! Could be 200~ or 201~
      success = read_single_char(ch2)
      if (.not. success) return

      if (ch2 == '0') then
        ! Check for ~ to confirm ESC[200~
        success = read_single_char(ch3)
        if (.not. success) return

        if (ch3 == '~') then
          ! PASTE START MARKER DETECTED!
          ! Buffer all text until we see ESC[201~

          ! Debug output if FORTSH_DEBUG_PASTE is set
          block
            use iso_fortran_env, only: error_unit
            character(len=16) :: debug_paste
            integer :: stat
            call get_environment_variable('FORTSH_DEBUG_PASTE', debug_paste, status=stat)
            if (stat == 0 .and. len_trim(debug_paste) > 0) then
              write(error_unit, '(A)') '[DEBUG: PASTE START detected (ESC[200~)]'
            end if
          end block

          paste_len = 0
          paste_buffer = ''

          ! Read characters until we find ESC[201~
          do while (paste_len < MAX_LINE_LEN - 1)
            success = read_single_char(ch_paste)
            if (.not. success) exit

            ! Check if this is the start of the end marker
            if (ch_paste == char(27)) then  ! ESC
              ! Peek ahead for [201~
              success = read_single_char(ch1)
              if (.not. success) exit
              if (ch1 == '[') then
                success = read_single_char(ch1)
                if (.not. success) exit
                if (ch1 == '2') then
                  success = read_single_char(ch1)
                  if (.not. success) exit
                  if (ch1 == '0') then
                    success = read_single_char(ch1)
                    if (.not. success) exit
                    if (ch1 == '1') then
                      success = read_single_char(ch1)
                      if (.not. success) exit
                      if (ch1 == '~') then
                        ! PASTE END MARKER FOUND!

                        ! Debug output if FORTSH_DEBUG_PASTE is set
                        block
                          use iso_fortran_env, only: error_unit
                          character(len=16) :: debug_paste
                          integer :: stat
                          call get_environment_variable('FORTSH_DEBUG_PASTE', debug_paste, status=stat)
                          if (stat == 0 .and. len_trim(debug_paste) > 0) then
                            write(error_unit, '(A,I0,A)') '[DEBUG: PASTE END detected (ESC[201~), buffered ', paste_len, ' chars]'
                          end if
                        end block

                        ! Insert the whole sanitized paste in one operation so
                        ! it lands in a single redraw, and light the just-pasted
                        ! span in reverse video until the next keystroke.
                        call insert_bytes_at_cursor(input_state, paste_buffer, paste_len, inserted)
                        if (inserted > 0) then
                          input_state%paste_hl_start = input_state%cursor_pos - inserted
                          input_state%paste_hl_end   = input_state%cursor_pos
                          input_state%paste_hl_active = .true.
                        end if
                        input_state%dirty = .true.
                        return
                      end if
                    end if
                  end if
                end if
              end if
              ! Not the end marker: this was an embedded escape sequence in the
              ! pasted content. Drop the ESC and the lookahead bytes we consumed
              ! (ANSI-injection guard) — any printable remainder still in the
              ! stream comes through as literal text below.
            else
              ! Regular pasted byte: sanitize before buffering.
              !   tab (9)            -> keep
              !   newline (10)       -> single space (keeps the line single, so a
              !                         multi-line paste can't split into commands)
              !   CR/DEL/NUL/other   -> drop (terminal-escape / control guard)
              !   printable + UTF-8  -> keep
              ! ESC (27) never reaches here — handled by the branch above.
              ic = iachar(ch_paste)
              if (ic == 10) then
                paste_len = paste_len + 1
                paste_buffer(paste_len:paste_len) = ' '
              else if (ic == 9 .or. (ic >= 32 .and. ic /= 127)) then
                paste_len = paste_len + 1
                paste_buffer(paste_len:paste_len) = ch_paste
              end if
            end if
          end do
        end if
      else if (ch2 == '1') then
        ! ESC[201~ - paste end without start (shouldn't happen, ignore)
        success = read_single_char(ch3)
        return
      end if
    end if

    ! Not a paste marker, could be extended escape (rare for '2')
    ! Just ignore it for now
  end subroutine

  ! Handle extended escape sequences like ESC[1;5C (Ctrl+Right Arrow)
  subroutine handle_extended_escape_sequence(input_state, done, initial_digit)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character, intent(in) :: initial_digit
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

        ! In search mode, consume the sequence but don't act on it
        if (input_state%in_search) then
          return
        end if

        ! Check for Ctrl+Right arrow (modifier=5, terminator=C)
        if (modifier == '5' .and. terminator == 'C') then
          ! Ctrl+Right arrow - accept one word from autosuggestion
          if (input_state%cursor_pos == input_state%length .and. &
              input_state%suggestion_length > 0) then
            call accept_autosuggestion_word(input_state)
          end if
        ! ============================================================
        ! Shift-phase selection extension (modifiers 2 and 6)
        ! Sprint 1: state only; Sprint 2 adds the visible highlight.
        ! ============================================================
        ! Shift+Left — extend selection one char back
        else if (modifier == '2' .and. terminator == 'D') then
          module_extending_selection = .true.
          call handle_cursor_left(input_state)
          module_extending_selection = .false.
        ! Shift+Right — extend selection one char forward
        else if (modifier == '2' .and. terminator == 'C') then
          module_extending_selection = .true.
          call handle_cursor_right(input_state)
          module_extending_selection = .false.
        ! Shift+Up — treat as Shift+Home on single-line prompt (#25)
        else if (modifier == '2' .and. terminator == 'A') then
          module_extending_selection = .true.
          call handle_home(input_state)
          module_extending_selection = .false.
        ! Shift+Down — treat as Shift+End on single-line prompt (#25)
        else if (modifier == '2' .and. terminator == 'B') then
          module_extending_selection = .true.
          call handle_end(input_state)
          module_extending_selection = .false.
        ! Shift+Home — extend selection to start of line
        else if (modifier == '2' .and. terminator == 'H') then
          module_extending_selection = .true.
          call handle_home(input_state)
          module_extending_selection = .false.
        ! Shift+End — extend selection to end of line
        else if (modifier == '2' .and. terminator == 'F') then
          module_extending_selection = .true.
          call handle_end(input_state)
          module_extending_selection = .false.
        ! Ctrl+Shift+Left — extend selection by one word back
        else if (modifier == '6' .and. terminator == 'D') then
          module_extending_selection = .true.
          call move_to_previous_word(input_state)
          module_extending_selection = .false.
        ! Ctrl+Shift+Right — extend selection by one word forward
        else if (modifier == '6' .and. terminator == 'C') then
          module_extending_selection = .true.
          call move_to_next_word(input_state)
          module_extending_selection = .false.
        ! Check for Alt+Left/Right for word movement (modifier=3)
        else if (modifier == '3' .and. terminator == 'D') then
          ! Alt+Left - Move cursor backward one word (standard behavior)
          call move_to_previous_word(input_state)
        else if (modifier == '3' .and. terminator == 'C') then
          ! Alt+Right - Move cursor forward one word (standard behavior)
          call move_to_next_word(input_state)
        ! Check for Alt+Shift+Up arrow (modifier=4, terminator=A)
        else if (modifier == '4' .and. terminator == 'A') then
          ! Alt+Shift+Up - Go to parent directory (cd ..)
          call handle_alt_up(input_state, done)
        ! Check for Alt+Shift+Left arrow (modifier=4, terminator=D)
        else if (modifier == '4' .and. terminator == 'D') then
          ! Alt+Shift+Left - Go to previous directory (prevd)
          call handle_alt_left(input_state, done)
        ! Check for Alt+Shift+Right arrow (modifier=4, terminator=C)
        else if (modifier == '4' .and. terminator == 'C') then
          ! Alt+Shift+Right - Go to next directory (nextd)
          call handle_alt_right(input_state, done)
        ! Alt+Delete: modifier=3, initial_digit=3, terminator=~
        else if (modifier == '3' .and. terminator == '~' .and. initial_digit == '3') then
          call handle_kill_word_forward(input_state)
        ! Ctrl+Delete: modifier=5, initial_digit=3, terminator=~
        else if (modifier == '5' .and. terminator == '~' .and. initial_digit == '3') then
          call handle_kill_word_forward(input_state)
        end if
        ! For other extended sequences, we just consume them
        return
      else if (ch == '~') then
        ! Tilde-terminated sequence: ESC[3~ (delete), ESC[1~ (home), ESC[4~ (end), etc.
        if (.not. input_state%in_search) then
          select case(initial_digit)
          case('3')  ! Delete key — forward delete character
            call handle_forward_delete_char(input_state)
          case('1')  ! Home key
            call handle_home(input_state)
          case('4')  ! End key
            call handle_end(input_state)
          case default
            continue  ! Page up/down — no action
          end select
        end if
        return
      else if ((ch >= 'A' .and. ch <= 'Z') .or. (ch >= 'a' .and. ch <= 'z')) then
        ! Found letter terminator without semicolon, done
        return
      end if

      count = count + 1
    end do
  end subroutine

  subroutine handle_cursor_left(input_state)
    use iso_fortran_env, only: error_unit
    type(input_state_t), intent(inout) :: input_state
    integer :: old_row, old_col, new_row, new_col, term_cols
    integer :: bytes_to_move
    integer :: old_cursor_pos
    logical :: debug_utf8
    integer :: debug_stat

    ! Shift-phase: plain Left with an active selection snaps cursor to the
    ! LEFT edge and clears selection, without further motion (#25, #26).
    ! Char-motion uses the snap-to-edge convention (matches VS Code/TextEdit).
    if (input_state%selection_active .and. .not. module_extending_selection) then
      input_state%cursor_pos = min(input_state%selection_anchor, input_state%cursor_pos)
      call collapse_selection(input_state)
      input_state%dirty = .true.
      return
    end if

    ! Capture pre-motion cursor so shift-extending can anchor the selection.
    old_cursor_pos = input_state%cursor_pos

    ! Check if UTF-8 debug mode is enabled
    call get_environment_variable('FORTSH_DEBUG_UTF8', status=debug_stat)
    debug_utf8 = (debug_stat == 0)

    if (input_state%cursor_pos > 0) then
      ! Get terminal size
      call get_terminal_size_from_env(term_cols)

      ! Use the tracked cursor position as the starting point
      ! This is more accurate than recalculating, especially after direct character output
      old_row = module_cursor_screen_row
      old_col = module_cursor_screen_col

      if (debug_utf8) then
        write(error_unit, '(a,i0,a,i0,a,i0)') '[CURSOR_LEFT] BEFORE: cursor_pos=', &
          input_state%cursor_pos, ' old_row=', old_row, ' old_col=', old_col
      end if

      ! Determine how many bytes to move left (1-4 for complete UTF-8 character)
      bytes_to_move = utf8_char_bytes_before_cursor(input_state)
      if (bytes_to_move <= 0) bytes_to_move = 1

      if (debug_utf8) then
        write(error_unit, '(a,i0)') '[CURSOR_LEFT] bytes_to_move=', bytes_to_move
      end if

      ! Move cursor left in buffer by complete UTF-8 character
      input_state%cursor_pos = input_state%cursor_pos - bytes_to_move

      ! Calculate new cursor position
      call cursor_get_row_col(input_state%menu_prompt, input_state%cursor_pos, term_cols, new_row, new_col)

      if (debug_utf8) then
        write(error_unit, '(a,i0,a,i0,a,i0)') '[CURSOR_LEFT] AFTER: cursor_pos=', &
          input_state%cursor_pos, ' new_row=', new_row, ' new_col=', new_col
      end if

      ! Move cursor on screen (handles line wrapping)
      call cursor_move(old_row, old_col, new_row, new_col)

      ! Update module cursor tracking
      module_cursor_screen_row = new_row
      module_cursor_screen_col = new_col
    end if

    ! Shift-phase: if this call is extending a selection, update it now.
    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine

  subroutine handle_cursor_right(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: old_row, old_col, new_row, new_col, term_cols
    integer :: bytes_to_move
    integer :: old_cursor_pos

    ! Shift-phase: plain Right with an active selection snaps cursor to the
    ! RIGHT edge and clears selection, without further motion (#25, #26).
    if (input_state%selection_active .and. .not. module_extending_selection) then
      input_state%cursor_pos = max(input_state%selection_anchor, input_state%cursor_pos)
      if (input_state%cursor_pos > input_state%length) then
        input_state%cursor_pos = input_state%length
      end if
      call collapse_selection(input_state)
      input_state%dirty = .true.
      return
    end if

    old_cursor_pos = input_state%cursor_pos

    if (input_state%cursor_pos < input_state%length) then
      ! Get terminal size
      call get_terminal_size_from_env(term_cols)

      ! Use the tracked cursor position as the starting point
      ! This is more accurate than recalculating, especially after direct character output
      old_row = module_cursor_screen_row
      old_col = module_cursor_screen_col

      ! Determine how many bytes to move right (1-4 for complete UTF-8 character)
      bytes_to_move = utf8_char_bytes_at_cursor(input_state)
      if (bytes_to_move <= 0) bytes_to_move = 1

      ! Move cursor right in buffer by complete UTF-8 character
      input_state%cursor_pos = input_state%cursor_pos + bytes_to_move

      ! Don't go past end of buffer
      if (input_state%cursor_pos > input_state%length) then
        input_state%cursor_pos = input_state%length
      end if

      ! Calculate new cursor position
      call cursor_get_row_col(input_state%menu_prompt, input_state%cursor_pos, term_cols, new_row, new_col)

      ! Move cursor on screen (handles line wrapping)
      call cursor_move(old_row, old_col, new_row, new_col)

      ! Update module cursor tracking
      module_cursor_screen_row = new_row
      module_cursor_screen_col = new_col
    else if (input_state%cursor_pos == input_state%length .and. input_state%suggestion_length > 0 &
             .and. .not. module_extending_selection) then
      ! At end of line with suggestion - accept it (but not during shift-extension —
      ! Shift+Right at the end of the line should not eat an autosuggestion).
      call accept_autosuggestion(input_state)
    end if

    ! Shift-phase: if this call is extending a selection, update it now.
    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
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

  ! Cancel prefix search and accept current buffer content
  subroutine cancel_prefix_search(input_state)
    type(input_state_t), intent(inout) :: input_state
    input_state%in_prefix_search = .false.
    input_state%prefix_search_len = 0
    input_state%prefix_search_idx = 0
    input_state%prefix_search_flash = .false.
  end subroutine

  ! Calculate display width of UTF-8 character
  ! Returns 1 for ASCII, 2 for wide chars (emoji, CJK), 0 for combining
  function utf8_char_width(byte1) result(width)
    character(len=1), intent(in) :: byte1
    integer :: width
    integer :: code

    code = iachar(byte1)

    ! ASCII characters (0-127) have width 1
    if (code < 128) then
      width = 1
      return
    end if

    ! UTF-8 multi-byte character
    ! Simple heuristic: assume wide (emoji, CJK)
    ! Could be improved with full Unicode width tables
    if (code >= 192) then  ! Start of 2, 3, or 4 byte sequence
      width = 2  ! Assume wide
    else
      width = 1  ! Continuation byte or other
    end if
  end function utf8_char_width

  ! Calculate visual length of string (excluding ANSI escape codes)
  ! Handles CSI (ESC[...m), OSC (ESC]...BEL), multi-line prompts, and UTF-8 wide chars
  function visual_length(str) result(vlen)
    character(len=*), intent(in) :: str
    integer :: vlen
    integer :: i, slen
    integer :: state
    integer :: terminator_code
    integer :: last_newline_pos

    ! State machine for parsing escape sequences
    integer, parameter :: STATE_NORMAL = 0
    integer, parameter :: STATE_ESC = 1
    integer, parameter :: STATE_CSI = 2
    integer, parameter :: STATE_OSC = 3

    vlen = 0
    last_newline_pos = 0
    slen = len_trim(str)
    ! Stop at first null byte (buffer padding)
    ! len_trim doesn't strip nulls, so we must scan for them
    block
      integer :: null_scan
      do null_scan = 1, slen
        if (iachar(str(null_scan:null_scan)) == 0) then
          slen = null_scan - 1
          exit
        end if
      end do
    end block
    state = STATE_NORMAL

    i = 1
    do while (i <= slen)
      select case (state)
      case (STATE_NORMAL)
        if (str(i:i) == char(27)) then  ! ESC
          state = STATE_ESC
          i = i + 1
        else if (str(i:i) == char(0)) then  ! NUL
          ! Null byte from buffer padding - skip
          i = i + 1
        else if (str(i:i) == char(13)) then  ! CR
          ! Carriage return - doesn't add to visual length
          i = i + 1
        else if (str(i:i) == char(10)) then  ! LF
          ! Newline resets visual position (for multi-line prompts)
          vlen = 0
          last_newline_pos = i
          i = i + 1
        else
          ! Regular character - count it (account for wide UTF-8 chars)
          vlen = vlen + utf8_char_width(str(i:i))
          i = i + 1
        end if

      case (STATE_ESC)
        if (str(i:i) == '[') then
          ! CSI sequence: ESC[...[@-~]
          state = STATE_CSI
          i = i + 1
        else if (str(i:i) == ']') then
          ! OSC sequence: ESC]...BEL or ESC]...ESC\
          state = STATE_OSC
          i = i + 1
        else
          ! Other escape sequence (e.g., ESC c for reset)
          ! Skip this character and return to normal
          state = STATE_NORMAL
          i = i + 1
        end if

      case (STATE_CSI)
        ! CSI sequences end with character in range [@-~] (64-126)
        terminator_code = iachar(str(i:i))
        if (terminator_code >= 64 .and. terminator_code <= 126) then
          ! Found terminator (includes letters, @, and punctuation)
          state = STATE_NORMAL
        end if
        i = i + 1

      case (STATE_OSC)
        ! OSC sequences end with BEL (07) or ST (ESC\)
        if (str(i:i) == char(7)) then  ! BEL
          state = STATE_NORMAL
          i = i + 1
        else if (i < slen .and. str(i:i) == char(27) .and. str(i+1:i+1) == '\') then
          ! ST = ESC\
          state = STATE_NORMAL
          i = i + 2
        else
          i = i + 1
        end if
      end select
    end do

    ! Debug: log visual_length result for multi-line prompts
    if (last_newline_pos > 0 .and. slen > 10) then
    end if
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

    ! Initialize match_positions to avoid uninitialized warning
    match_positions = 0

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

    ! Require prefix match unless fuzzy-complete is enabled.
    ! With fuzzy off (default): behaves like bash/zsh — only prefix matches.
    ! With fuzzy on (set -o fuzzy-complete): short patterns still require
    ! prefix, longer patterns allow fuzzy subsequence matching.
    if (.not. global_fuzzy_complete .or. pattern_len <= 3) then
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
    character(len=:), allocatable :: highlighted  ! Heap allocation to avoid stack overflow
    integer :: highlighted_len
    integer :: term_rows, term_cols
    integer :: prompt_visual_len, current_line
    integer :: cursor_visual_pos
    integer :: i, k, suggestion_display_len, available_space
    logical :: success
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction

    ! Allocate highlight buffer on heap (too large for stack)
    ! Do NOT use 'highlighted = ...' — deferred-length allocatable assignment
    ! reallocates to match RHS length, causing heap corruption downstream
    allocate(character(len=MAX_HIGHLIGHT_LEN) :: highlighted)
    highlighted_len = 0

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

    ! Calculate current cursor position in visual characters (add 1 for space after prompt)
    cursor_visual_pos = prompt_visual_len + 1 + input_state%cursor_pos

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
    write(output_unit, '(a)', advance='no') ' '  ! Space after prompt
    if (input_state%length > 0) then
      ! Extract buffer for highlighting
      call state_buffer_get(input_state, temp_buf)
      call highlight_command_line(temp_buf(:input_state%length), highlighted, highlighted_len)
      if (highlighted_len > 0 .and. highlighted_len <= MAX_HIGHLIGHT_LEN) then
        write(output_unit, '(a)', advance='no') highlighted(1:highlighted_len)
      end if
    end if

    ! Display autosuggestion if cursor is at end
    ! IMPORTANT: Truncate suggestion to prevent wrapping beyond terminal width
    if (input_state%suggestion_length > 0 .and. input_state%cursor_pos == input_state%length) then
      ! Calculate available space on current line (add 1 for space after prompt)
      available_space = term_cols - mod(prompt_visual_len + 1 + input_state%length, term_cols)

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
          ! Use bright black (gray) color for suggestions - ANSI code 90
          ! This is more visible than dim mode and better supported across terminals
          write(output_unit, '(a)', advance='no') char(27) // '[90m'

          ! Display suggestion character-by-character (avoid substring)
          do k = 1, suggestion_display_len
            write(output_unit, '(a)', advance='no') input_state%suggestion(k:k)
          end do

          write(output_unit, '(a)', advance='no') char(27) // '[0m'  ! Reset

          ! Move cursor back using simple cursor-left commands
          do k = 1, suggestion_display_len
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

    ! Deallocate heap-allocated buffer
    if (allocated(highlighted)) deallocate(highlighted)
  end subroutine

  ! Partial redraw - only from cursor to end (reduces flashing)
  subroutine redraw_from_cursor(input_state)
    use syntax_highlight, only: highlight_command_line
    type(input_state_t), intent(in) :: input_state
    character(len=:), allocatable :: highlighted  ! Heap allocation to avoid stack overflow
    integer :: i, cursor_col, highlighted_len
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction

    ! Allocate highlight buffer on heap (too large for stack)
    ! Do NOT use 'highlighted = ...' — deferred-length allocatable assignment
    ! reallocates to match RHS length, causing heap corruption downstream
    allocate(character(len=MAX_HIGHLIGHT_LEN) :: highlighted)
    highlighted_len = 0

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
    call state_buffer_get(input_state, temp_buf)
    call highlight_command_line(temp_buf(:input_state%length), highlighted, highlighted_len)
    if (highlighted_len > 0 .and. highlighted_len <= MAX_HIGHLIGHT_LEN) then
      write(output_unit, '(a)', advance='no') highlighted(1:highlighted_len)
    end if

    ! Move cursor back to correct position
    do i = input_state%length, cursor_col + 1, -1
      write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
    end do

    flush(output_unit)

    ! Deallocate heap-allocated buffer
    if (allocated(highlighted)) deallocate(highlighted)
  end subroutine

  ! Helper to convert integer to string
  function int_to_str(n) result(str)
    integer, intent(in) :: n
    character(len=20) :: str
    write(str, '(i15)') n
  end function

  ! Advanced line editing functions for Phase 5
  subroutine handle_home(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: old_cursor_pos

    ! Plain motion with active selection: clear selection, then proceed with
    ! normal motion. Home/End don't snap — they always go to 0/length — so a
    ! simple clear is correct (#25, #26).
    if (input_state%selection_active .and. .not. module_extending_selection) then
      call collapse_selection(input_state)
      input_state%dirty = .true.
    end if

    old_cursor_pos = input_state%cursor_pos

    ! Move cursor to beginning of line
    if (input_state%cursor_pos > 0) then
      input_state%cursor_pos = 0
      ! Mark dirty to trigger full redraw with correct cursor position
      input_state%dirty = .true.
    end if

    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine

  subroutine handle_end(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: old_cursor_pos

    if (input_state%selection_active .and. .not. module_extending_selection) then
      call collapse_selection(input_state)
      input_state%dirty = .true.
    end if

    old_cursor_pos = input_state%cursor_pos

    ! Move cursor to end of line
    if (input_state%cursor_pos < input_state%length) then
      input_state%cursor_pos = input_state%length
      ! Mark dirty to trigger full redraw with correct cursor position
      input_state%dirty = .true.
    end if

    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine
  
  subroutine handle_kill_to_end(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: temp_buf

    ! Save text from cursor to end of line in kill buffer
    if (input_state%cursor_pos < input_state%length) then
      ! Extract substring and save to kill buffer
      call state_buffer_get(input_state, temp_buf)
      call state_kill_buffer_set(input_state, temp_buf(input_state%cursor_pos+1:input_state%length))
      input_state%kill_length = input_state%length - input_state%cursor_pos

      ! Clear from cursor to end of line
      input_state%length = input_state%cursor_pos
      input_state%dirty = .true.

      ! Update autosuggestion after killing to end
      call update_autosuggestion(input_state)
    else
      ! Nothing to kill
      input_state%kill_length = 0
    end if
  end subroutine
  
  subroutine handle_kill_line(input_state)
    use iso_fortran_env, only: output_unit
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: temp_buf, shifted_buf
    integer :: remaining_len

    ! unix-line-discard: kill from beginning of line to cursor position.
    ! Text after the cursor is preserved (mirrors Ctrl+K which kills to end).
    if (input_state%cursor_pos > 0) then
      call state_buffer_get(input_state, temp_buf)

      ! Save killed text (before cursor) in kill buffer
      call state_kill_buffer_set(input_state, temp_buf(:input_state%cursor_pos))
      input_state%kill_length = input_state%cursor_pos

      ! Shift remaining text (after cursor) to beginning of buffer. Copy via a
      ! separate buffer: an overlapping self-assignment of temp_buf is undefined
      ! in Fortran and SIGSEGVs under flang (same idiom as the old dd/cc crash).
      remaining_len = input_state%length - input_state%cursor_pos
      if (remaining_len > 0) then
        shifted_buf = ''
        shifted_buf(1:remaining_len) = temp_buf(input_state%cursor_pos+1:input_state%length)
        call state_buffer_set(input_state, shifted_buf)
      else
        call state_buffer_clear(input_state)
      end if

      input_state%length = remaining_len
      input_state%cursor_pos = 0

      ! Clear any autosuggestion
      input_state%suggestion = ''
      input_state%suggestion_length = 0

      ! Update autosuggestion for remaining text
      call update_autosuggestion(input_state)

      input_state%dirty = .true.
    else
      ! Cursor at beginning — nothing to kill
      input_state%kill_length = 0
    end if
  end subroutine
  
  subroutine handle_kill_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_start, i
    character(len=MAX_LINE_LEN) :: temp_buf

    ! Shift-phase (Sprint 3): Ctrl+W with an active selection becomes a
    ! cut — copy the selected range to the kill buffer, then remove it.
    ! No fall-through to kill-word. Ctrl+Y (handle_yank) pastes it back.
    if (input_state%selection_active) then
      call copy_selection_to_kill_buffer(input_state)
      call delete_selection(input_state)
      call update_autosuggestion(input_state)
      return
    end if

    if (input_state%cursor_pos == 0) then
      input_state%kill_length = 0
      return
    end if

    ! Find start of current word (skip trailing spaces first)
    word_start = input_state%cursor_pos

    ! Skip any trailing whitespace
    do while (word_start > 0 .and. state_buffer_get_char(input_state, word_start) == ' ')
      word_start = word_start - 1
    end do

    ! Find beginning of word (non-space characters)
    do while (word_start > 0 .and. state_buffer_get_char(input_state, word_start) /= ' ')
      word_start = word_start - 1
    end do

    ! word_start is now at space before word, or 0 if at beginning
    if (word_start < input_state%cursor_pos) then
      ! Save killed text
      call state_buffer_get(input_state, temp_buf)
      call state_kill_buffer_set(input_state, temp_buf(word_start+1:input_state%cursor_pos))
      input_state%kill_length = input_state%cursor_pos - word_start

      ! Shift remaining text left
      do i = word_start + 1, input_state%length - input_state%cursor_pos + word_start
        if (input_state%cursor_pos + i - word_start <= input_state%length) then
          call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, input_state%cursor_pos + i - word_start))
        else
          call state_buffer_set_char(input_state, i, ' ')
        end if
      end do

      ! Update length and cursor position
      input_state%length = input_state%length - (input_state%cursor_pos - word_start)
      input_state%cursor_pos = word_start
      input_state%dirty = .true.

      ! Update autosuggestion after killing word
      call update_autosuggestion(input_state)
    else
      input_state%kill_length = 0
    end if
  end subroutine

  ! Alt+d — kill word forward (delete from cursor to end of next word)
  subroutine handle_kill_word_forward(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_end, i, chars_to_delete

    if (input_state%cursor_pos >= input_state%length) return

    word_end = input_state%cursor_pos + 1

    ! Skip whitespace first
    do while (word_end <= input_state%length .and. state_buffer_get_char(input_state, word_end) == ' ')
      word_end = word_end + 1
    end do

    ! Skip word characters
    do while (word_end <= input_state%length .and. state_buffer_get_char(input_state, word_end) /= ' ')
      word_end = word_end + 1
    end do

    chars_to_delete = word_end - input_state%cursor_pos - 1
    if (chars_to_delete <= 0) return

    ! Shift remaining text left
    do i = input_state%cursor_pos + 1, input_state%length - chars_to_delete
      call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, i + chars_to_delete))
    end do
    do i = input_state%length - chars_to_delete + 1, input_state%length
      call state_buffer_set_char(input_state, i, ' ')
    end do

    input_state%length = input_state%length - chars_to_delete
    input_state%dirty = .true.
    call update_autosuggestion(input_state)
  end subroutine

  subroutine handle_yank(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, insert_len

    ! Shift-phase (Sprint 3): yanking into an active selection first
    ! deletes the selection, then pastes the kill buffer at the cursor.
    ! This gives the natural "paste over" behavior. Selection is collapsed
    ! by delete_selection before the existing yank logic runs.
    if (input_state%selection_active) call delete_selection(input_state)

    if (input_state%kill_length == 0) return
    
    insert_len = min(input_state%kill_length, MAX_LINE_LEN - input_state%length)
    if (insert_len == 0) return
    
    ! Shift existing text right to make room
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
      end if
    end do

    ! Insert killed text at cursor position (session_kill_buffer is the
    ! kill ring's single source of truth — see state_kill_buffer_set)
    do i = 1, insert_len
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, session_kill_buffer(i:i))
    end do
    
    ! Update length and cursor position
    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
  end subroutine

  ! Ctrl+V paste handler (Sprint 5). Reads from the system clipboard;
  ! if the clipboard is empty or no tool is available, falls back to
  ! yanking from the in-session kill_buffer. If a selection is active
  ! it is deleted first (paste-over behavior, same as Ctrl+Y).
  subroutine handle_paste(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: paste_buf
    integer :: paste_len, insert_len, i, j

    ! Delete active selection first (paste-over).
    if (input_state%selection_active) call delete_selection(input_state)

    ! Try the system clipboard.
    paste_len = 0
    call clipboard_paste(paste_buf, MAX_LINE_LEN, paste_len)

    if (paste_len > 0) then
      ! Truncate to available space.
      insert_len = min(paste_len, MAX_LINE_LEN - input_state%length)
      if (insert_len <= 0) return

      ! Shift existing text right.
      do i = input_state%length, input_state%cursor_pos + 1, -1
        if (i + insert_len <= MAX_LINE_LEN) then
          call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
        end if
      end do

      ! Insert clipboard text at cursor.
      do j = 1, insert_len
        call state_buffer_set_char(input_state, input_state%cursor_pos + j, paste_buf(j:j))
      end do

      input_state%length = input_state%length + insert_len
      input_state%cursor_pos = input_state%cursor_pos + insert_len
      input_state%dirty = .true.
    else
      ! Clipboard empty or unavailable — fall back to kill buffer (same as C-y).
      call handle_yank(input_state)
    end if
  end subroutine handle_paste

  subroutine handle_clear_screen(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=4096) :: highlighted  ! Fixed-length to avoid flang-new allocatable bugs
    integer :: i, term_rows, term_cols, available_space, suggestion_display_len, highlighted_len
    logical :: success
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction

    highlighted = ' '
    highlighted_len = 0

    ! Hide cursor, clear screen, and move cursor to home position (0,0)
    write(output_unit, '(a)', advance='no') ESC_HIDE_CURSOR
    write(output_unit, '(a)', advance='no') char(27) // '[2J' // char(27) // '[H'

    ! Since we're now at home position, just redraw everything from scratch
    ! No need to calculate cursor movement - we know we're at top left

    ! Draw prompt
    write(output_unit, '(a)', advance='no') prompt
    write(output_unit, '(a)', advance='no') ' '  ! Space after prompt

    ! Draw the current buffer with syntax highlighting
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      call highlight_command_line(temp_buf(:input_state%length), highlighted, highlighted_len, input_state%length)
      if (highlighted_len > 0 .and. highlighted_len <= len(highlighted)) then
        write(output_unit, '(a)', advance='no') highlighted(1:highlighted_len)
      end if
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

      ! Calculate available space (add 1 for space after prompt)
      available_space = term_cols - mod(visual_length(prompt) + 1 + input_state%length, term_cols)

      if (available_space > 2) then
        suggestion_display_len = min(input_state%suggestion_length, available_space - 1)

        if (suggestion_display_len > 0) then
          ! Use bright black (gray) color for suggestions - ANSI code 90
          write(output_unit, '(a)', advance='no') char(27) // '[90m'

          ! Display suggestion character-by-character (avoid substring)
          do i = 1, suggestion_display_len
            write(output_unit, '(a)', advance='no') input_state%suggestion(i:i)
          end do

          write(output_unit, '(a)', advance='no') char(27) // '[0m'

          ! Move cursor back using simple cursor-left commands
          do i = 1, suggestion_display_len
            write(output_unit, '(a)', advance='no') ESC_CURSOR_LEFT
          end do
        end if
      end if
    end if

    write(output_unit, '(a)', advance='no') ESC_SHOW_CURSOR
    flush(output_unit)
    input_state%dirty = .false.

    ! Update cursor tracking after clearing screen and redrawing
    call get_terminal_size_from_env(term_cols)
    call cursor_get_row_col(prompt, input_state%cursor_pos, term_cols, &
                            module_cursor_screen_row, module_cursor_screen_col)
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
        temp = state_buffer_get_char(input_state, input_state%length)
        call state_buffer_set_char(input_state, input_state%length, state_buffer_get_char(input_state, input_state%length-1))
        call state_buffer_set_char(input_state, input_state%length-1, temp)
        input_state%dirty = .true.
      end if
    ! If at beginning, do nothing
    else if (input_state%cursor_pos == 0) then
      return
    ! Normal case: swap char at cursor with previous char, move cursor forward
    else
      temp = state_buffer_get_char(input_state, input_state%cursor_pos+1)
      call state_buffer_set_char(input_state, input_state%cursor_pos+1, state_buffer_get_char(input_state, input_state%cursor_pos))
      call state_buffer_set_char(input_state, input_state%cursor_pos, temp)
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
    character(len=MAX_LINE_LEN) :: temp_buf

    if (input_state%cursor_pos >= input_state%length) return

    word_end = input_state%cursor_pos + 1

    ! Skip any leading whitespace
    do while (word_end <= input_state%length .and. &
              state_buffer_get_char(input_state, word_end) == ' ')
      word_end = word_end + 1
    end do

    ! Find end of word (non-space characters)
    do while (word_end <= input_state%length .and. &
              state_buffer_get_char(input_state, word_end) /= ' ')
      word_end = word_end + 1
    end do

    if (word_end > input_state%cursor_pos + 1) then
      ! Save deleted text to kill buffer
      call state_buffer_get(input_state, temp_buf)
      call state_kill_buffer_set(input_state, temp_buf(input_state%cursor_pos+1:word_end-1))
      input_state%kill_length = word_end - input_state%cursor_pos - 1

      ! Shift remaining text left
      do i = input_state%cursor_pos + 1, input_state%length - (word_end - input_state%cursor_pos - 1)
        if (word_end + i - input_state%cursor_pos - 1 <= input_state%length) then
          call state_buffer_set_char(input_state, i, state_buffer_get_char(input_state, word_end + i - input_state%cursor_pos - 1))
        else
          call state_buffer_set_char(input_state, i, ' ')
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
    integer :: pos
    character :: ch

    if (input_state%cursor_pos >= input_state%length) return

    pos = input_state%cursor_pos + 1

    ! Skip any leading whitespace
    do while (pos <= input_state%length .and. &
              state_buffer_get_char(input_state, pos) == ' ')
      pos = pos + 1
    end do

    ! Uppercase characters until end of word
    do while (pos <= input_state%length .and. &
              state_buffer_get_char(input_state, pos) /= ' ')
      ch = state_buffer_get_char(input_state, pos)
      if (ch >= 'a' .and. ch <= 'z') then
        call state_buffer_set_char(input_state, pos, char(ichar(ch) - 32))
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
              state_buffer_get_char(input_state, pos) == ' ')
      pos = pos + 1
    end do

    ! Lowercase characters until end of word
    do while (pos <= input_state%length .and. &
              state_buffer_get_char(input_state, pos) /= ' ')
      ch = state_buffer_get_char(input_state, pos)
      if (ch >= 'A' .and. ch <= 'Z') then
        call state_buffer_set_char(input_state, pos, char(ichar(ch) + 32))
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
              state_buffer_get_char(input_state, pos) == ' ')
      pos = pos + 1
    end do

    first_char = .true.

    ! Capitalize first character, lowercase rest until end of word
    do while (pos <= input_state%length .and. &
              state_buffer_get_char(input_state, pos) /= ' ')
      ch = state_buffer_get_char(input_state, pos)

      if (first_char) then
        ! Uppercase first character
        if (ch >= 'a' .and. ch <= 'z') then
          call state_buffer_set_char(input_state, pos, char(ichar(ch) - 32))
        end if
        first_char = .false.
      else
        ! Lowercase remaining characters
        if (ch >= 'A' .and. ch <= 'Z') then
          call state_buffer_set_char(input_state, pos, char(ichar(ch) + 32))
        end if
      end if

      pos = pos + 1
    end do

    ! Move cursor to end of word
    input_state%cursor_pos = pos - 1
    input_state%dirty = .true.
  end subroutine

  ! Alt+Up: Replace line with "cd .." and execute (Fish-style parent directory navigation)
  subroutine handle_alt_up(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character(len=5) :: cmd

    ! Buffer replacement — clear any stale selection (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

    cmd = 'cd ..'

    ! Clear current buffer and insert "cd .."
    call state_buffer_set(input_state, cmd)
    input_state%length = 5
    input_state%cursor_pos = 5

    ! Clear suggestion since we're replacing the line
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    ! Don't set dirty - we don't want to redraw, just execute silently (Fish behavior)
    ! input_state%dirty = .true.

    ! Print newline before execution (like pressing Enter)
    write(output_unit, '()')

    ! Auto-execute the command (Fish behavior)
    done = .true.
  end subroutine

  ! Alt+Left: Replace line with "prevd" and execute (Fish-style previous directory)
  subroutine handle_alt_left(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character(len=5) :: cmd

    if (input_state%selection_active) call collapse_selection(input_state)

    cmd = 'prevd'

    ! Clear current buffer and insert "prevd"
    call state_buffer_set(input_state, cmd)
    input_state%length = 5
    input_state%cursor_pos = 5

    ! Clear suggestion since we're replacing the line
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    ! Don't set dirty - we don't want to redraw, just execute silently (Fish behavior)
    ! input_state%dirty = .true.

    ! Print newline before execution (like pressing Enter)
    write(output_unit, '()')

    ! Auto-execute the command (Fish behavior)
    done = .true.
  end subroutine

  ! Alt+Right: Replace line with "nextd" and execute (Fish-style next directory)
  subroutine handle_alt_right(input_state, done)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(inout) :: done
    character(len=5) :: cmd

    if (input_state%selection_active) call collapse_selection(input_state)

    cmd = 'nextd'

    ! Clear current buffer and insert "nextd"
    call state_buffer_set(input_state, cmd)
    input_state%length = 5
    input_state%cursor_pos = 5

    ! Clear suggestion since we're replacing the line
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    ! Don't set dirty - we don't want to redraw, just execute silently (Fish behavior)
    ! input_state%dirty = .true.

    ! Print newline before execution (like pressing Enter)
    write(output_unit, '()')

    ! Auto-execute the command (Fish behavior)
    done = .true.
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

  ! Insert exactly n bytes at the cursor in one operation (used for paste).
  ! Unlike insert_string_at_cursor this takes an explicit byte count (no
  ! len_trim, so trailing spaces and control bytes survive) and inserts in a
  ! single O(n) shift. `inserted` returns the count actually inserted (clamped
  ! to the buffer), so the caller can highlight exactly the pasted span.
  subroutine insert_bytes_at_cursor(input_state, bytes, n, inserted)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: bytes
    integer, intent(in) :: n
    integer, intent(out) :: inserted
    integer :: insert_len, cur, oldlen
    character(len=:), allocatable :: src, dst

    inserted = 0
    if (n <= 0) return

    ! Paste-over: a paste replaces any active selection (mirrors insert_char_impl)
    if (input_state%selection_active) call delete_selection(input_state)

    ! Same -1 headroom guard as insert_char_impl to avoid writing past the buffer
    insert_len = min(n, MAX_LINE_LEN - 1 - input_state%length)
    if (insert_len <= 0) return

    cur = input_state%cursor_pos
    oldlen = input_state%length

    ! Build the result in a SEPARATE buffer rather than a self-aliased slice
    ! move within one variable — the dd/cc SIGSEGV (obs #791) was exactly that
    ! idiom, which flang-new/aarch64 miscompiles.
    allocate(character(len=MAX_LINE_LEN) :: src)
    allocate(character(len=MAX_LINE_LEN) :: dst)
    call state_buffer_get(input_state, src)
    ! Blank-fill via a SLICE — `dst = ''` would reallocate a deferred-length
    ! allocatable to length 0, dropping every slice write that follows.
    dst(:) = ' '
    if (cur > 0) dst(1:cur) = src(1:cur)
    dst(cur+1:cur+insert_len) = bytes(1:insert_len)
    if (oldlen > cur) dst(cur+insert_len+1:oldlen+insert_len) = src(cur+1:oldlen)
    call state_buffer_set(input_state, dst)
    deallocate(src)
    deallocate(dst)

    input_state%length = oldlen + insert_len
    input_state%cursor_pos = cur + insert_len
    input_state%dirty = .true.
    inserted = insert_len

    ! Test mode skips the dirty redraw, so echo the inserted bytes directly —
    ! this replaces the per-char echo the old char-by-char paste loop relied on.
    if (test_mode_enabled) then
      write(output_unit, '(a)', advance='no') bytes(1:insert_len)
      flush(output_unit)
    end if

    call update_autosuggestion(input_state)
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
      call state_buffer_save(input_state)
      input_state%in_search = .true.
      input_state%search_forward = forward
      call clear_search_string(input_state)
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

    call get_search_string(input_state, search_str, input_state%search_length)

    if (input_state%search_forward) then
      ! Forward search - search from current match towards newer history
      do i = input_state%search_match_index + 1, command_history%count
        if (index(command_history%lines(i), trim(search_str)) > 0) then
          input_state%search_match_index = i
          call state_buffer_set(input_state, command_history%lines(i))
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
            call state_buffer_set(input_state, command_history%lines(i))
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
          call state_buffer_set(input_state, command_history%lines(i))
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
            call state_buffer_set(input_state, command_history%lines(i))
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
      call set_search_char(input_state, input_state%search_length, ch)
      call get_search_string(input_state, search_str, input_state%search_length)

      ! Search through history in the appropriate direction
      if (input_state%search_forward) then
        ! Forward search - from beginning to end
        do i = 1, command_history%count
          if (index(command_history%lines(i), trim(search_str)) > 0) then
            input_state%search_match_index = i
            call state_buffer_set(input_state, command_history%lines(i))
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
            call state_buffer_set(input_state, command_history%lines(i))
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
        call get_search_string(input_state, search_str, input_state%search_length)

        if (input_state%search_forward) then
          ! Forward search
          do i = 1, command_history%count
            if (index(command_history%lines(i), trim(search_str)) > 0) then
              input_state%search_match_index = i
              call state_buffer_set(input_state, command_history%lines(i))
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
              call state_buffer_set(input_state, command_history%lines(i))
              input_state%length = len_trim(command_history%lines(i))
              input_state%cursor_pos = input_state%length
              exit
            end if
          end do
        end if
      else
        ! Empty search - restore original buffer on prompt line
        call state_buffer_restore(input_state)
#ifdef USE_C_STRINGS
        input_state%length = c_string_length(input_state%original_buffer_c)
#elif defined(USE_MEMORY_POOL)
        input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
        input_state%length = len_trim(input_state%original_buffer)
#endif
        input_state%cursor_pos = input_state%length
        input_state%search_match_index = 0
      end if

      call update_search_display(input_state, prompt)
    end if
  end subroutine

  ! Clear the entire search query (Ctrl-U in search mode)
  subroutine search_clear_query(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt

    if (input_state%search_length == 0) return

    call clear_search_string(input_state)
    input_state%search_length = 0

    ! Restore original buffer
    call state_buffer_restore(input_state)
#ifdef USE_C_STRINGS
    input_state%length = c_string_length(input_state%original_buffer_c)
#elif defined(USE_MEMORY_POOL)
    input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
    input_state%length = len_trim(input_state%original_buffer)
#endif
    input_state%cursor_pos = input_state%length
    input_state%search_match_index = 0

    call update_search_display(input_state, prompt)
  end subroutine search_clear_query

  ! Delete last word from search query (Ctrl-W / Alt-Backspace in search mode)
  subroutine search_kill_word(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=MAX_LINE_LEN) :: search_str
    integer :: i, new_len

    if (input_state%search_length == 0) return

    call get_search_string(input_state, search_str, input_state%search_length)

    ! Skip trailing spaces
    new_len = input_state%search_length
    do while (new_len > 0 .and. search_str(new_len:new_len) == ' ')
      new_len = new_len - 1
    end do
    ! Skip back to previous space or beginning
    do while (new_len > 0 .and. search_str(new_len:new_len) /= ' ')
      new_len = new_len - 1
    end do

    input_state%search_length = new_len

    if (new_len > 0) then
      ! Re-search with shorter query
      call get_search_string(input_state, search_str, new_len)
      input_state%search_match_index = 0
      if (input_state%search_forward) then
        do i = 1, command_history%count
          if (index(command_history%lines(i), trim(search_str(:new_len))) > 0) then
            input_state%search_match_index = i
            call state_buffer_set(input_state, command_history%lines(i))
            input_state%length = len_trim(command_history%lines(i))
            input_state%cursor_pos = input_state%length
            exit
          end if
        end do
      else
        do i = command_history%count, 1, -1
          if (index(command_history%lines(i), trim(search_str(:new_len))) > 0) then
            input_state%search_match_index = i
            call state_buffer_set(input_state, command_history%lines(i))
            input_state%length = len_trim(command_history%lines(i))
            input_state%cursor_pos = input_state%length
            exit
          end if
        end do
      end if
    else
      ! Empty query - restore original buffer
      call state_buffer_restore(input_state)
#ifdef USE_C_STRINGS
      input_state%length = c_string_length(input_state%original_buffer_c)
#elif defined(USE_MEMORY_POOL)
      input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
      input_state%length = len_trim(input_state%original_buffer)
#endif
      input_state%cursor_pos = input_state%length
      input_state%search_match_index = 0
    end if

    call update_search_display(input_state, prompt)
  end subroutine search_kill_word

  ! Clean up the status line below the prompt when exiting search mode
  subroutine cleanup_search_status_line()
    ! Move up from status line to prompt line, clear everything below
    if (module_search_status_shown) then
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! cursor up
    end if
    write(output_unit, '(a)', advance='no') char(13)          ! BOL
    write(output_unit, '(a)', advance='no') char(27) // '[J'  ! clear from cursor down
    module_search_status_shown = .false.
    flush(output_unit)
  end subroutine cleanup_search_status_line

  subroutine cancel_search(input_state)
    type(input_state_t), intent(inout) :: input_state

    ! Restore original buffer
    call state_buffer_restore(input_state)
#ifdef USE_C_STRINGS
    input_state%length = c_string_length(input_state%original_buffer_c)
#elif defined(USE_MEMORY_POOL)
    input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
    input_state%length = len_trim(input_state%original_buffer)
#endif
    input_state%cursor_pos = input_state%length
    input_state%in_search = .false.
    call clear_search_string(input_state)
    input_state%search_length = 0
    input_state%search_match_index = 0

    call cleanup_search_status_line()
    input_state%dirty = .true.
  end subroutine

  subroutine accept_search(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=MAX_LINE_LEN) :: temp_buf
    character(len=4096) :: highlighted
    integer :: highlighted_len, pv_len, term_rows, term_cols
    character(len=8) :: col_str
    logical :: success

    ! Keep the current buffer (matched command)
    input_state%in_search = .false.
    call clear_search_string(input_state)
    input_state%search_length = 0
    input_state%search_match_index = 0

    ! Clear status line and rewrite command text without redrawing prompt
    if (module_search_status_shown) then
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! cursor up from status line
    end if

    ! Position cursor after prompt, clear to end of screen
    pv_len = visual_length(prompt)
    if (pv_len < 0) pv_len = 0
    write(col_str, '(i0)') pv_len + 2
    write(output_unit, '(a)', advance='no') char(27) // '[' // trim(col_str) // 'G'
    write(output_unit, '(a)', advance='no') char(27) // '[J'

    ! Write syntax-highlighted command text
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      call highlight_command_line(temp_buf(:input_state%length), &
                                  highlighted, highlighted_len, &
                                  input_state%length)
      if (highlighted_len > 0 .and. highlighted_len <= len(highlighted)) then
        write(output_unit, '(a)', advance='no') highlighted(:highlighted_len)
      else
        write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
      end if
    end if

    module_search_status_shown = .false.
    flush(output_unit)

    ! Update cursor screen position tracking so subsequent redraws work correctly
    success = get_terminal_size(term_rows, term_cols)
    if (.not. success .or. term_cols <= 0) term_cols = 80
    call cursor_get_row_col(prompt, input_state%cursor_pos, term_cols, &
                            module_cursor_screen_row, module_cursor_screen_col)
  end subroutine

  subroutine accept_search_for_editing(input_state)
    ! Accept the search result and prepare for normal editing
    ! Called when arrow keys are pressed during Ctrl+R search
    type(input_state_t), intent(inout) :: input_state

    ! Keep the current buffer (matched command)
    input_state%in_search = .false.
    call clear_search_string(input_state)
    input_state%search_length = 0
    input_state%search_match_index = 0

    ! Clean up status line, mark for normal redraw
    call cleanup_search_status_line()
    input_state%dirty = .true.
  end subroutine

  subroutine update_search_display(input_state, prompt)
    type(input_state_t), intent(in) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=MAX_LINE_LEN) :: temp_buf, search_str
    character(len=4096) :: highlighted
    integer :: highlighted_len, pv_len
    character(len=16) :: direction_label
    character(len=8) :: col_str

    ! Hide cursor during search redraw to prevent flashing
    write(output_unit, '(a)', advance='no') ESC_HIDE_CURSOR

    ! 1. If status line already shown, cursor is on status line — move up first
    if (module_search_status_shown) then
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! cursor up to prompt line
    end if

    ! 2. Position cursor right after the prompt (don't rewrite the prompt)
    !    Use cursor horizontal absolute ESC[{col}G to jump to the command area
    pv_len = visual_length(prompt)
    if (pv_len < 0) pv_len = 0
    write(col_str, '(i0)') pv_len + 2  ! +1 for space, +1 for 1-based column
    write(output_unit, '(a)', advance='no') char(27) // '[' // trim(col_str) // 'G'

    ! 3. Clear from cursor to end of screen (clears old command text + old status line)
    write(output_unit, '(a)', advance='no') char(27) // '[J'

    ! 4. Write matched command text with syntax highlighting
    if (input_state%length > 0) then
      call state_buffer_get(input_state, temp_buf)
      call highlight_command_line(temp_buf(:input_state%length), &
                                  highlighted, highlighted_len, &
                                  input_state%length)
      if (highlighted_len > 0 .and. highlighted_len <= len(highlighted)) then
        write(output_unit, '(a)', advance='no') highlighted(:highlighted_len)
      else
        write(output_unit, '(a)', advance='no') temp_buf(:input_state%length)
      end if
    end if

    ! 5. Move to status line below
    write(output_unit, '(a)', advance='no') char(10) // char(13)  ! newline + BOL

    ! 6. Render search status line
    if (input_state%search_forward) then
      direction_label = 'fwd-search: '
    else
      direction_label = 'bck-search: '
    end if
    write(output_unit, '(a)', advance='no') trim(direction_label)
    if (input_state%search_length > 0) then
      call get_search_string(input_state, search_str, input_state%search_length)
      write(output_unit, '(a)', advance='no') search_str(:input_state%search_length)
    end if
    ! Cursor naturally sits at end of query text on the status line
    module_search_status_shown = .true.

    write(output_unit, '(a)', advance='no') ESC_SHOW_CURSOR
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

  ! ============================================================================
  ! Abbreviation Expansion (Fish-style)
  ! ============================================================================

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

  ! ============================================================================
  ! Autosuggestion Support (Fish-style)
  ! ============================================================================

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
    end if
  end subroutine try_path_suggestion

  subroutine update_autosuggestion(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: j
    ! CRITICAL: Use fixed-length (NOT deferred-length) for flang-new compatibility
    character(len=MAX_LINE_LEN), allocatable :: current_input
    type(suggestion_result_t) :: hist_result

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

    ! Priority 1: history-based suggestion (fish-style: history first)
    if (command_history%count > 0 .and. allocated(command_history%lines)) then
      hist_result = compute_history_suggestion( &
        current_input, input_state%length, &
        command_history%lines, command_history%count)

      if (hist_result%source /= SUGGEST_NONE) then
        input_state%suggestion = ''
        do j = 1, hist_result%length
          input_state%suggestion(j:j) = hist_result%text(j:j)
        end do
        input_state%suggestion_length = hist_result%length
        if (allocated(current_input)) deallocate(current_input)
        return
      end if
    end if

    ! Priority 2: path-based suggestion (fallback when no history match)
    call try_path_suggestion(current_input(1:input_state%length), input_state)

    if (allocated(current_input)) deallocate(current_input)
  end subroutine

  ! Accept the current autosuggestion
  subroutine accept_autosuggestion(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: j, new_length

    if (input_state%suggestion_length == 0) return

    ! Buffer is about to be extended — any lingering selection is stale (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

    ! Safety check: ensure we won't overflow
    new_length = input_state%length + input_state%suggestion_length
    if (new_length > MAX_LINE_LEN) then
      input_state%suggestion_length = MAX_LINE_LEN - input_state%length
      if (input_state%suggestion_length < 0) input_state%suggestion_length = 0
      new_length = input_state%length + input_state%suggestion_length
    end if

    ! Append suggestion to buffer using character-by-character assignment
    do j = 1, input_state%suggestion_length
      call state_buffer_set_char(input_state, input_state%length + j, input_state%suggestion(j:j))
    end do

    input_state%length = new_length
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

    ! Buffer is about to be extended — any lingering selection is stale (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

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

    ! Safety check: ensure we won't overflow
    if (input_state%length + word_end > MAX_LINE_LEN) then
      word_end = MAX_LINE_LEN - input_state%length
      if (word_end <= 0) return
    end if

    ! Append first word to buffer using accessor (handles memory pool + C strings)
    do i = 1, word_end
      call state_buffer_set_char(input_state, input_state%length + i, input_state%suggestion(i:i))
    end do

    input_state%length = input_state%length + word_end
    input_state%cursor_pos = input_state%length
    input_state%dirty = .true.

    ! Update suggestion to remove accepted part
    call update_autosuggestion(input_state)
  end subroutine

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

  subroutine launch_fzf_file_browser(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=1024) :: fzf_cmd
    character(len=512) :: preview_cmd
    integer :: unit, iostat, exit_status
    logical :: file_exists
    character(len=256) :: bat_path
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

    ! Build fzf command with options (including multi-select)
    write(fzf_cmd, '(a)') 'fzf --multi --height=40% --reverse --border ' // &
          '--preview=''' // trim(preview_cmd) // ''' ' // &
          '--preview-window=right:60%:wrap ' // &
          '--bind=''ctrl-/:toggle-preview'' ' // &
          '--header=''TAB: Multi-select | Ctrl-/: Toggle Preview | ESC: Cancel'' ' // &
          '> /tmp/fortsh_fzf_selection.tmp 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'  ! Clear screen
    write(output_unit, '(a)', advance='no') char(27) // '[H'   ! Move cursor home
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection(s) if fzf exited successfully (supports multi-select)
    if (exit_status == 0) then
      inquire(file='/tmp/fortsh_fzf_selection.tmp', exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file='/tmp/fortsh_fzf_selection.tmp', &
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
        ! Clean up temp file
        call safe_execute_command('rm -f /tmp/fortsh_fzf_selection.tmp 2>/dev/null')
      end if
    end if

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

    ! Build fzf command for history
    ! tac reverses the file so recent commands appear first
    ! Use exact match for consistency
    write(fzf_cmd, '(a)') 'tac ' // trim(history_file) // ' | ' // &
          'fzf --height=40% --reverse --border ' // &
          '--no-sort ' // &
          '--tiebreak=index ' // &
          '--header=''Ctrl-H: History Browser | Select: Replace Line | ESC: Cancel'' ' // &
          '> /tmp/fortsh_fzf_history.tmp 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'  ! Clear screen
    write(output_unit, '(a)', advance='no') char(27) // '[H'   ! Move cursor home
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection if fzf exited successfully
    if (exit_status == 0) then
      inquire(file='/tmp/fortsh_fzf_history.tmp', exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file='/tmp/fortsh_fzf_history.tmp', &
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
        ! Clean up temp file
        call safe_execute_command('rm -f /tmp/fortsh_fzf_history.tmp 2>/dev/null')
      end if
    end if

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
    character(len=MAX_LINE_LEN) :: temp_buf

    ! Check if fzf is installed
    call safe_execute_command('command -v fzf >/dev/null 2>&1', exitstat=exit_status)
    if (exit_status /= 0) then
      write(output_unit, '()')
      write(output_unit, '(a)') 'Error: fzf is not installed.'
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
          '> /tmp/fortsh_fzf_dir.tmp 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'
    write(output_unit, '(a)', advance='no') char(27) // '[H'
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection and cd into it
    if (exit_status == 0) then
      inquire(file='/tmp/fortsh_fzf_dir.tmp', exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file='/tmp/fortsh_fzf_dir.tmp', &
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
        call safe_execute_command('rm -f /tmp/fortsh_fzf_dir.tmp 2>/dev/null')
      end if
    end if

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

    write(fzf_cmd, '(a)') trim(git_cmd) // ' | ' // &
          'fzf --height=40% --reverse --border --ansi ' // &
          '--preview=''' // trim(preview_cmd) // ''' ' // &
          '--preview-window=right:60%:wrap ' // &
          '--header=''Alt-G: Git Browser | Select file or branch | ESC: Cancel'' ' // &
          '> /tmp/fortsh_fzf_git.tmp 2>/dev/null'

    ! Clear screen and show fzf
    write(output_unit, '(a)', advance='no') char(27) // '[2J'
    write(output_unit, '(a)', advance='no') char(27) // '[H'
    flush(output_unit)

    ! Execute fzf
    call safe_execute_command(trim(fzf_cmd), exitstat=exit_status)

    ! Read selection
    if (exit_status == 0) then
      inquire(file='/tmp/fortsh_fzf_git.tmp', exist=file_exists)
      if (file_exists) then
        open(newunit=unit, file='/tmp/fortsh_fzf_git.tmp', &
             status='old', action='read', iostat=iostat)
        if (iostat == 0) then
          read(unit, '(a)', iostat=iostat) selected_item
          close(unit)

          if (iostat == 0 .and. len_trim(selected_item) > 0) then
            ! Insert selected item at cursor
            call insert_string_at_cursor(input_state, trim(selected_item))
          end if
        end if
        call safe_execute_command('rm -f /tmp/fortsh_fzf_git.tmp 2>/dev/null')
      end if
    end if

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

  ! ===========================================================================
  ! Cursor Position Helpers for Multi-Line Support
  ! ===========================================================================

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

  ! Calculate cursor row and column given prompt and cursor position
  ! Returns (row, col) where row 0 = first line, col 0 = first column
  subroutine cursor_get_row_col(prompt, cursor_pos, term_cols, cursor_row, cursor_col)
    use iso_fortran_env, only: output_unit, error_unit
    character(len=*), intent(in) :: prompt
    integer, intent(in) :: cursor_pos, term_cols
    integer, intent(out) :: cursor_row, cursor_col
    integer :: prompt_visual_len, total_pos, visual_width
    integer :: i, byte_val
    character :: ch
    logical :: debug_utf8

    ! Check if debug mode is enabled
    call get_environment_variable('FORTSH_DEBUG_UTF8', status=byte_val)
    debug_utf8 = (byte_val == 0)

    if (term_cols <= 0) then
      cursor_row = 0
      cursor_col = 0
      return
    end if

    ! Calculate visual length of prompt (excluding ANSI codes)
    prompt_visual_len = visual_length(prompt)
    if (prompt_visual_len < 0) prompt_visual_len = 0

    ! Calculate visual width of buffer from position 1 to cursor_pos
    ! This accounts for multi-byte UTF-8 characters and their display width
    visual_width = 0
    i = 1
    do while (i <= cursor_pos)
      ch = state_buffer_get_char(module_input_state, i)
      byte_val = iand(iachar(ch), 255)

      if (debug_utf8) then
        write(error_unit, '(a,i0,a,z2.2,a,i0)') '[VISUAL] pos=', i, ' byte=0x', byte_val, ' visual_width=', visual_width
      end if

      ! Check if this is a UTF-8 lead byte
      if (byte_val < 128) then
        ! ASCII - 1 byte, 1 column
        visual_width = visual_width + 1
        i = i + 1
      else if (iand(byte_val, 224) == 192) then
        ! 2-byte UTF-8 - usually 1 column, but could be 2
        visual_width = visual_width + utf8_char_width(ch)
        i = i + 2
      else if (iand(byte_val, 240) == 224) then
        ! 3-byte UTF-8 (CJK) - 2 columns
        visual_width = visual_width + 2
        i = i + 3
      else if (iand(byte_val, 248) == 240) then
        ! 4-byte UTF-8 (emoji) - 2 columns
        visual_width = visual_width + 2
        i = i + 4
      else
        ! Continuation byte or invalid - skip
        i = i + 1
      end if
    end do

    if (debug_utf8) then
      write(error_unit, '(a,i0,a,i0,a,i0,a,i0)') '[VISUAL] cursor_pos=', cursor_pos, &
        ' prompt_len=', prompt_visual_len, ' visual_width=', visual_width, &
        ' total=', prompt_visual_len + 1 + visual_width
    end if

    ! Total position = prompt + space + visual width of buffer content
    total_pos = prompt_visual_len + 1 + visual_width

    ! Calculate row and column (0-based)
    cursor_row = total_pos / term_cols
    cursor_col = mod(total_pos, term_cols)
  end subroutine

  ! Walk a rendered content buffer (with ANSI codes) and return the visual
  ! row that byte_pos falls on (0-based, wrapping at term_cols).
  subroutine content_byte_to_row_col(buf, buf_len, byte_pos, term_cols, row, col_out)
    integer, intent(in) :: buf_len, byte_pos, term_cols
    character(len=*), intent(in) :: buf
    integer, intent(out) :: row, col_out
    integer :: pos, col

    row = 0
    col = 0
    pos = 1
    col_out = 0
    if (term_cols <= 0) return
    do while (pos < byte_pos .and. pos <= buf_len)
      if (buf(pos:pos) == char(27) .and. pos + 1 <= buf_len &
          .and. buf(pos+1:pos+1) == '[') then
        pos = pos + 2
        do while (pos <= buf_len)
          if (iachar(buf(pos:pos)) >= 64 .and. iachar(buf(pos:pos)) <= 126) then
            pos = pos + 1
            exit
          end if
          pos = pos + 1
        end do
        cycle
      end if
      if (buf(pos:pos) == char(0)) then
        pos = pos + 1
        cycle
      end if
      if (buf(pos:pos) == char(13) .and. pos + 1 <= buf_len &
          .and. buf(pos+1:pos+1) == char(10)) then
        row = row + 1
        col = 0
        pos = pos + 2
        cycle
      end if
      col = col + 1
      if (col >= term_cols) then
        row = row + 1
        col = 0
      end if
      pos = pos + 1
    end do
    col_out = col
  end subroutine

  ! Move cursor from old position to new position, handling line wrapping
  subroutine cursor_move(old_row, old_col, new_row, new_col)
    use iso_fortran_env, only: output_unit, error_unit
    integer, intent(in) :: old_row, old_col, new_row, new_col
    integer :: row_diff, col_diff, i
    logical :: debug_utf8
    integer :: stat

    ! Check if debug mode is enabled
    call get_environment_variable('FORTSH_DEBUG_UTF8', status=stat)
    debug_utf8 = (stat == 0)

    if (debug_utf8) then
      write(error_unit, '(a,i0,a,i0,a,i0,a,i0)') '[CURSOR_MOVE] from (', old_row, ',', old_col, ') to (', new_row, ',', new_col, ')'
    end if

    row_diff = new_row - old_row

    ! Move up/down first
    if (row_diff > 0) then
      ! Move down
      do i = 1, row_diff
        write(output_unit, '(a)', advance='no') char(27) // '[B'  ! ESC[B = down
      end do
    else if (row_diff < 0) then
      ! Move up
      do i = 1, abs(row_diff)
        write(output_unit, '(a)', advance='no') char(27) // '[A'  ! ESC[A = up
      end do
    end if

    ! Then move left/right to correct column
    col_diff = new_col - old_col

    if (debug_utf8) then
      write(error_unit, '(a,i0)') '[CURSOR_MOVE] col_diff=', col_diff
    end if

    if (col_diff > 0) then
      ! Move right
      do i = 1, col_diff
        write(output_unit, '(a)', advance='no') char(27) // '[C'  ! ESC[C = right
      end do
    else if (col_diff < 0) then
      ! Move left
      if (debug_utf8) then
        write(error_unit, '(a,i0,a)') '[CURSOR_MOVE] Moving left ', abs(col_diff), ' columns'
      end if
      do i = 1, abs(col_diff)
        write(output_unit, '(a)', advance='no') char(27) // '[D'  ! ESC[D = left
      end do
    end if

    flush(output_unit)
  end subroutine

  ! Back up diff_pos if it lands inside an ANSI escape or UTF-8 sequence.
  ! Writing a partial ESC[...m produces visible garbage; a partial UTF-8
  ! sequence produces replacement characters. Backing up to the start of
  ! the sequence is safe because ANSI codes are zero-width and the visual
  ! column calculation already skips them.
  subroutine adjust_diff_to_boundary(buf, buf_len, diff_pos)
    integer, intent(in) :: buf_len
    character(len=*), intent(in) :: buf
    integer, intent(inout) :: diff_pos
    integer :: scan, byte_val

    if (diff_pos <= 1 .or. diff_pos > buf_len) return

    ! UTF-8: if diff_pos is a continuation byte (10xxxxxx), back up to lead
    byte_val = iand(iachar(buf(diff_pos:diff_pos)), 255)
    if (iand(byte_val, 192) == 128) then
      do while (diff_pos > 1)
        diff_pos = diff_pos - 1
        byte_val = iand(iachar(buf(diff_pos:diff_pos)), 255)
        if (iand(byte_val, 192) /= 128) exit
      end do
      return
    end if

    ! ANSI: scan backward for an unterminated ESC[ sequence
    scan = diff_pos - 1
    do while (scan >= 1)
      if (buf(scan:scan) == char(27)) then
        if (scan + 1 <= buf_len .and. buf(scan+1:scan+1) == '[') then
          diff_pos = scan
        end if
        return
      end if
      byte_val = iachar(buf(scan:scan))
      if (byte_val >= 64 .and. byte_val <= 126 .and. buf(scan:scan) /= '[') return
      if (byte_val < 32 .and. buf(scan:scan) /= char(27)) return
      scan = scan - 1
    end do
  end subroutine

  ! Restore terminal from raw mode — called by REPL after all continuation prompts
  subroutine restore_readline_terminal()
    if (module_termios_saved) then
      if (.not. restore_terminal(module_original_termios)) then
      end if
      module_termios_saved = .false.  ! Next readline call will re-save and re-enable
    end if
  end subroutine

end module readline