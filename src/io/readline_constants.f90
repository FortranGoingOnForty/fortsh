! ==============================================================================
! Module: readline_constants
! Purpose: Key codes, sizing constants, mode enums, and the core input/history
!          types shared across the readline family of modules (QUAL-13 split).
!          Compile-time-only content — no procedures, no mutable state.
! ==============================================================================
module readline_constants
#ifdef USE_C_STRINGS
  use fortsh_c_strings
#endif
#ifdef USE_MEMORY_POOL
  use string_pool
#endif
  implicit none

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
#if defined(USE_C_STRINGS) || defined(FORTSH_NATIVE_LONG_STRINGS)
  ! The active string implementation supports the full interactive line buffer.
  integer, parameter :: MAX_LINE_LEN = 8192
#else
  ! Legacy limit for older flang-new versions without C string library. Raised
  ! from 128 to match the mainline minimum; not used by CI (flang-new enables
  ! USE_C_STRINGS), but 127 usable chars truncated far too early on that build.
  integer, parameter :: MAX_LINE_LEN = 1024    ! Buffer size - actual limit is 1023 chars
#endif
#else
  integer, parameter :: MAX_HISTORY = 1000
  integer, parameter :: MAX_LINE_LEN = 8192
#endif

  ! Glob expansion constants (from glob module)
  integer, parameter :: MAX_GLOB_MATCHES = 1000
  ! MAX_TOKEN_LEN is already defined in shell_types

  ! Editing mode constants
  integer, parameter :: EDITING_MODE_EMACS = 1
  integer, parameter :: EDITING_MODE_VI = 2
  integer, parameter :: VI_MODE_INSERT = 1
  integer, parameter :: VI_MODE_COMMAND = 2
  integer, parameter :: VI_MODE_VISUAL = 3  ! AR-05b: charwise/linewise visual

  ! Reduced buffer sizes to prevent static storage issues
  ! Was causing 204KB allocation (50*4096), now only 25KB (40*256)
  integer, parameter :: MAX_MENU_ITEM_LEN = 256
  integer, parameter :: MAX_MENU_ITEMS = 40  ! Increased from 20 for better usability
  integer, parameter :: MAX_LOCAL_COMPLETIONS = 40  ! Max completions to process locally
  integer, parameter :: MAX_SCORED_ITEMS = 512  ! Max scored completion items (raised for pager)

  ! Pager item store capacity: backs the scrollable completion menu.
  integer, parameter :: PAGER_STORE_MAX = 512

  ! AR-03c: completion menu description column sizing + kind tags.
  integer, parameter :: MAX_MENU_DESC_LEN = 64
  integer, parameter :: MDESC_NONE = 0   ! file/dir/unknown: no description
  integer, parameter :: MDESC_VAR  = 1   ! $var: show its value
  integer, parameter :: MDESC_CMD  = 2   ! command position: builtin summary
  integer, parameter :: MDESC_OPT  = 3   ! -flag: per-command option help (#88)
  integer, parameter :: MDESC_SUB  = 4   ! git <subcommand>: subcommand help (#88)

  ! Timeout (ms) to wait for a byte following ESC before treating it as a bare ESC.
  integer, parameter :: MENU_ESC_TIMEOUT_MS = 50

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
    logical :: vi_visual_linewise = .false.  ! AR-05b: V vs v in visual mode

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
    ! AR-04b: icase path suggestion. When >0, accepting the suggestion first
    ! rewrites the last suggestion_replace_len chars of the buffer to
    ! suggestion_replace_text (the candidate's real case) so the result is a
    ! valid path. 0 for exact-case and history suggestions (plain append).
    integer :: suggestion_replace_len = 0
    character(len=MAX_LINE_LEN) :: suggestion_replace_text

    ! Prefix history search (fish-style up/down arrow with typed prefix)
    logical :: in_prefix_search = .false.     ! Currently in prefix search mode
    character(len=MAX_LINE_LEN) :: prefix_search_text  ! Frozen prefix text
    integer :: prefix_search_len = 0          ! Length of frozen prefix
    integer :: prefix_search_idx = 0          ! Current match index in history (0 = at present/original)
    logical :: prefix_search_flash = .false.  ! Transient: flash reverse video on no-match

    ! Menu selection support (zsh/fish-style interactive completion)
    logical :: in_menu_select = .false.  ! Currently in menu selection mode
    character(len=MAX_MENU_ITEM_LEN) :: menu_items(MAX_MENU_ITEMS)  ! Completion items for menu (fixed-length to avoid flang-new bug)
    character(len=MAX_MENU_DESC_LEN) :: menu_descs(MAX_MENU_ITEMS)  ! AR-03c: per-item description (parallel to menu_items)
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
    integer :: menu_name_col = 0  ! AR-03c: name column width when descs shown
    logical :: menu_has_descs = .false.  ! AR-03c: a description column is rendered
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

  ! Type to hold completion candidates with scores for fuzzy matching
  type :: scored_completion_t
    character(len=MAX_LINE_LEN) :: text
    integer :: score
  end type scored_completion_t

end module readline_constants
