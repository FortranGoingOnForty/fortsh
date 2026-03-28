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
  integer, parameter :: KEY_CTRL_X = 24   ! Process kill mode
  integer, parameter :: KEY_CTRL_A = 1    ! Home (beginning of line)
  integer, parameter :: KEY_CTRL_E = 5    ! End (end of line)
  integer, parameter :: KEY_CTRL_K = 11   ! Kill to end of line
  integer, parameter :: KEY_CTRL_L = 12   ! Clear screen
  integer, parameter :: KEY_CTRL_W = 23   ! Kill previous word
  integer, parameter :: KEY_CTRL_U = 21   ! Kill entire line
  integer, parameter :: KEY_CTRL_Y = 25   ! Yank (paste) killed text
  integer, parameter :: KEY_CTRL_F = 6    ! FZF file browser
  integer, parameter :: KEY_CTRL_B = 2    ! Backward character (same as left arrow)
  integer, parameter :: KEY_CTRL_R = 18   ! Reverse-i-search
  integer, parameter :: KEY_CTRL_S = 19   ! Forward-i-search
  integer, parameter :: KEY_CTRL_G = 7    ! Cancel (alternate to Ctrl+C)
  integer, parameter :: KEY_CTRL_H = 8    ! FZF history browser
  integer, parameter :: KEY_CTRL_T = 20   ! Transpose characters
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
  integer, parameter :: MAX_SCORED_ITEMS = 50  ! Max scored completion items (increased from 30)

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

  ! Detect macOS for potential platform-specific workarounds
  logical, save :: is_macos_system = .false.
  logical, save :: macos_detected = .false.

  ! Module-level input_state to work around flang-new pointer corruption bug
  type(input_state_t), save, target :: module_input_state
  logical, save :: module_input_state_initialized = .false.

  ! Module-level syntax highlighting buffer (fixed-length to avoid flang-new allocatable bugs)
  character(len=4096), save :: module_highlighted_buffer
  integer, save :: module_highlighted_len

  ! Track actual cursor screen position (row, col) to fix redraw issues
  ! Used to know where cursor is on screen vs where buffer says it should be
  integer, save :: module_cursor_screen_row = 0
  integer, save :: module_cursor_screen_col = 0

  ! Track whether the search status line is currently displayed below the prompt
  logical, save :: module_search_status_shown = .false.

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
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
    state%search_string_ref%data(pos:pos) = ch
#else
    state%search_string(pos:pos) = ch
#endif
  end subroutine set_search_char

  ! Clear the search string
  subroutine clear_search_string(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_MEMORY_POOL
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
  subroutine state_kill_buffer_clear(state)
    type(input_state_t), intent(inout) :: state
#ifdef USE_C_STRINGS
    call c_string_clear(state%kill_buffer_c)
#else
#ifdef USE_MEMORY_POOL
    state%kill_buffer_ref%data = ''
#else
    state%kill_buffer = ''
#endif
#endif
  end subroutine state_kill_buffer_clear

  ! Set kill buffer from string
  subroutine state_kill_buffer_set(state, str)
    type(input_state_t), intent(inout) :: state
    character(len=*), intent(in) :: str
#ifdef USE_C_STRINGS
    logical :: success
    success = c_string_set(state%kill_buffer_c, str)
#else
#ifdef USE_MEMORY_POOL
    state%kill_buffer_ref%data = str
#else
    state%kill_buffer = str
#endif
#endif
  end subroutine state_kill_buffer_set

  ! Get kill buffer as string
  subroutine state_kill_buffer_get(state, str)
    type(input_state_t), intent(in) :: state
    character(len=*), intent(out) :: str
#ifdef USE_C_STRINGS
    call c_string_to_fortran(state%kill_buffer_c, str)
#else
#ifdef USE_MEMORY_POOL
    str = state%kill_buffer_ref%data
#else
    str = state%kill_buffer
#endif
#endif
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
    character(len=:), allocatable :: cols_str, rows_str
    integer :: cols_val, rows_val, ios

    ! Default fallback values
    cols = 80
    rows = 24

    ! Try to get columns using tput
    cols_str = execute_and_capture('tput cols 2>/dev/null')
    if (allocated(cols_str) .and. len_trim(cols_str) > 0) then
      read(cols_str, *, iostat=ios) cols_val
      if (ios == 0 .and. cols_val > 0 .and. cols_val < 500) then
        cols = cols_val
      end if
    end if

    ! Try to get rows using tput
    rows_str = execute_and_capture('tput lines 2>/dev/null')
    if (allocated(rows_str) .and. len_trim(rows_str) > 0) then
      read(rows_str, *, iostat=ios) rows_val
      if (ios == 0 .and. rows_val > 0 .and. rows_val < 500) then
        rows = rows_val
      end if
    end if

    ! Clean up
    if (allocated(cols_str)) deallocate(cols_str)
    if (allocated(rows_str)) deallocate(rows_str)
  end subroutine safe_get_terminal_size
#endif

  ! Enhanced readline with character-by-character input processing
  subroutine readline_enhanced(prompt, line, iostat, rprompt)
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat
    character(len=*), intent(in), optional :: rprompt  ! Right-side prompt (like zsh)

    ! Use module-level module_input_state directly (avoids flang-new pointer corruption bug)
    character :: ch
    logical :: success, done, raw_enabled
    integer :: char_code
    ! Variables for redraw (moved out of block to avoid flang-new crash)
    integer :: i_redraw, term_cols, term_rows
    integer :: prompt_visual_len, cursor_visual_pos, current_line
    integer :: suggestion_display_len, available_space
    integer :: current_col, current_row
    integer :: highlighted_len  ! Actual length of highlighted string
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction
    ! Variables for UTF-8 support (moved out of block to avoid flang-new crash)
    character(len=4) :: utf8_char
    integer :: utf8_num_bytes, utf8_i
    logical :: debug_utf8
    integer :: debug_stat
    ! Variables for RPROMPT (right-side prompt)
    integer :: rprompt_visual_len, padding_needed
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
      module_input_state_initialized = .true.
    else
      ! On subsequent calls, just reset the buffer and cursor
#ifdef USE_MEMORY_POOL
      ! Check if buffer_ref is still valid, reinitialize if not
      if (.not. associated(module_input_state%buffer_ref%data)) then
        call init_input_state(module_input_state)
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
    end if

    ! Initialize variables
    iostat = 0
    done = .false.
    raw_enabled = .false.
    highlighted_len = 0

    ! Initialize history on first use
    call init_history()


    ! Try to enable raw mode (only works in interactive mode)
    success = enable_raw_mode(module_original_termios)
    if (success) then
      raw_enabled = .true.
      module_termios_saved = .true.
    else
      ! Log raw mode failure
      block
        integer :: dbu3
        open(newunit=dbu3, file='/tmp/fortsh_readline_debug.log', &
             status='unknown', position='append', action='write')
        write(dbu3, '(A)') 'WARNING: raw mode FAILED to enable'
        close(dbu3)
      end block
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
    if (present(rprompt) .and. len_trim(rprompt) > 0) then
      rprompt_visual_len = visual_length(rprompt)
      if (rprompt_visual_len < 0) rprompt_visual_len = 0

      ! Single-line prompt: place RPROMPT on same line
      padding_needed = term_cols - prompt_visual_len - 1 - rprompt_visual_len

      if (padding_needed >= 4) then  ! Minimum 4 chars gap
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
      write(output_unit, '(a)', advance='no') prompt
      write(output_unit, '(a)', advance='no') ' '  ! Space after prompt
    end if

    flush(output_unit)

    module_input_state%menu_prompt = prompt  ! Store prompt for menu mode, live preview, and FZF functions

    ! Initialize cursor screen position tracking
    ! For multiline prompts, cursor starts at row = prompt_line_count (0-indexed from prompt start)
    ! Column = prompt_visual_length + 1 (for space after prompt)
    module_cursor_screen_row = prompt_line_count
    module_cursor_screen_col = prompt_visual_len + 1


    ! Log readline state
    block
      integer :: dbu4
      open(newunit=dbu4, file='/tmp/fortsh_readline_debug.log', &
           status='unknown', position='append', action='write')
      write(dbu4, '(A,L1,A,I0,A,I0,A,I0)') &
        'READLINE_START: raw=', raw_enabled, &
        ' prompt_vlen=', prompt_visual_len, &
        ' prompt_lines=', prompt_line_count, &
        ' term_cols=', term_cols
      close(dbu4)
    end block

    if (raw_enabled) then
      ! Enhanced input processing
      do while (.not. done)
        ! Read a complete UTF-8 character (1-4 bytes)
        success = read_utf8_char(utf8_char, utf8_num_bytes)
        if (.not. success) then
          block
            integer :: dbu5
            open(newunit=dbu5, file='/tmp/fortsh_readline_debug.log', &
                 status='unknown', position='append', action='write')
            write(dbu5, '(A)') 'READ_CHAR: read_utf8_char returned FALSE (EOF)'
            close(dbu5)
          end block
          iostat = -1
          exit
        end if

        ! If multi-byte UTF-8 character, insert all bytes with correct visual width
        if (utf8_num_bytes > 1) then
          ! In search mode, ignore multi-byte characters (search uses ASCII only)
          if (module_input_state%in_search) cycle
          ! Cancel prefix search on any typed character
          if (module_input_state%in_prefix_search) call cancel_prefix_search(module_input_state)
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

        if (char_code == 27) then
        else if (char_code < 32 .or. char_code == 127) then
        end if

        ! Cancel prefix search on any key except escape (arrows handled inside escape handler)
        if (module_input_state%in_prefix_search .and. char_code /= KEY_ESC) then
          call cancel_prefix_search(module_input_state)
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
            call accept_search(module_input_state, prompt)
          else
            ! Clear shadow text (suggestion) from cursor to end of line before newline
            if (module_input_state%suggestion_length > 0) then
              write(output_unit, '(a)', advance='no') char(27) // '[K'
            end if
            write(output_unit, '()')  ! New line
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
          ! Ctrl+X - Enter process kill mode (no-op in search mode)
          if (.not. module_input_state%in_search .and. &
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
            ! Kill entire line (exit menu mode first if active)
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
          
        case(KEY_CTRL_Y)
          ! Yank - no-op in search mode
          if (.not. module_input_state%in_search) call handle_yank(module_input_state)

        case(KEY_CTRL_L)
          ! Clear screen - no-op in search mode or menu mode
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

        case(KEY_CTRL_T)
          ! Transpose characters - no-op in search mode
          if (.not. module_input_state%in_search) call handle_transpose_chars(module_input_state)

        case(32:126)
          ! Regular printable characters
          if (module_input_state%in_signal_input) then
            ! Handle signal input for process kill
            call handle_signal_input(module_input_state, ch)
          else if (module_input_state%in_menu_select) then
            ! Exit menu mode and process character normally
            call exit_menu_select_mode(module_input_state)
            call insert_char_wrapper(module_input_state, ch)
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


        ! Redraw line if needed
        ! INLINE redraw to avoid gfortran bug on macOS with large derived types
        ! Skip redraw when in menu selection mode - menu handles its own display
        ! In test mode, skip full redraw to avoid polluting PTY output
        if (.not. test_mode_initialized) call init_test_mode()

        ! Debug: log dirty state before check
        block
          integer :: dbu2
          open(newunit=dbu2, file='/tmp/fortsh_readline_debug.log', &
               status='unknown', position='append', action='write')
          write(dbu2, '(A,L1,A,L1,A,L1,A,I0)') &
            'LOOP: dirty=', module_input_state%dirty, &
            ' in_menu=', module_input_state%in_menu_select, &
            ' test_mode=', test_mode_enabled, &
            ' char_code=', char_code
          close(dbu2)
        end block

        if (module_input_state%dirty .and. .not. module_input_state%in_menu_select .and. .not. test_mode_enabled) then
          ! Search mode: delegate to two-line search display instead of normal redraw
          if (module_input_state%in_search) then
            call update_search_display(module_input_state, prompt)
            module_input_state%dirty = .false.
            cycle
          end if
          ! WORKAROUND: Removed 'block' construct to avoid flang-new crash on macOS ARM64
          ! Variables moved to subroutine level

          ! Get terminal size for multiline handling
#ifdef __APPLE__
            ! WORKAROUND: get_terminal_size crashes on flang-new
            ! Use tput command as a safe alternative
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

            ! Calculate current cursor position (add 1 for space after prompt)
            cursor_visual_pos = prompt_visual_len + 1 + module_input_state%cursor_pos

            ! Calculate row/col from buffer state not stale screen tracking
            current_row = cursor_visual_pos / term_cols
            current_col = mod(cursor_visual_pos, term_cols)

            ! Debug logging for cursor positioning
            block
              integer :: dbu
              open(newunit=dbu, file='/tmp/fortsh_readline_debug.log', &
                   status='unknown', position='append', action='write')
              write(dbu, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
                'REDRAW: prompt_vlen=', prompt_visual_len, &
                ' cursor_pos=', module_input_state%cursor_pos, &
                ' cursor_vpos=', cursor_visual_pos, &
                ' row=', current_row, ' col=', current_col, &
                ' term_cols=', term_cols, &
                ' prompt_lines=', prompt_line_count
              write(dbu, '(A,L1,A,I0,A,I0)') &
                '  skip_up=', module_input_state%skip_cursor_up_on_redraw, &
                ' move_up_count=', current_row + prompt_line_count, &
                ' buf_len=', module_input_state%length
              write(dbu, '(A,I0,A,A,A)') '  prompt_len_trim=', len_trim(prompt), &
                ' prompt=[', prompt(1:min(40, len_trim(prompt))), ']'
              close(dbu)
            end block

            ! Calculate where start of prompt is (always row 0, col 0 of prompt line)
            ! Move cursor to start of prompt UNLESS we just exited menu mode
            if (.not. module_input_state%skip_cursor_up_on_redraw) then
              ! Move to start of first line of this command
              ! For multiline prompts, we need to move up by both the buffer rows AND the prompt lines
              if (current_row + prompt_line_count > 0) then
                ! Move up to first line of prompt
                do i_redraw = 1, current_row + prompt_line_count
                  write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
                end do
              end if
              ! Move to column 0 of that line
              write(output_unit, '(a)', advance='no') char(13)  ! Carriage return
            else
              ! Just move to start of current line
              write(output_unit, '(a)', advance='no') char(13)  ! Carriage return
            end if

            ! Clear the skip flag after using it
            module_input_state%skip_cursor_up_on_redraw = .false.

            ! Clear from cursor to end of screen
            write(output_unit, '(a)', advance='no') char(27) // '[J'  ! Clear from cursor down

            ! Redraw prompt and buffer
            write(output_unit, '(a)', advance='no') prompt
            write(output_unit, '(a)', advance='no') ' '  ! Space after prompt
            if (module_input_state%length > 0) then
              ! Try syntax highlighting
              call state_buffer_get(module_input_state, temp_buf)

              ! In prefix search mode, render prefix in reverse video + rest plain
              if (module_input_state%in_prefix_search .and. &
                  (module_input_state%prefix_search_idx /= 0 .or. module_input_state%prefix_search_flash)) then
                ! Prefix in reverse video
                write(output_unit, '(a)', advance='no') char(27) // '[7m'
                do i_redraw = 1, module_input_state%prefix_search_len
                  write(output_unit, '(a)', advance='no') temp_buf(i_redraw:i_redraw)
                end do
                write(output_unit, '(a)', advance='no') char(27) // '[0m'
                ! Clear flash flag after rendering (transient — one frame only)
                if (module_input_state%prefix_search_flash) then
                  module_input_state%prefix_search_flash = .false.
                end if
                ! Remainder in plain text
                if (module_input_state%length > module_input_state%prefix_search_len) then
                  write(output_unit, '(a)', advance='no') &
                    temp_buf(module_input_state%prefix_search_len+1:module_input_state%length)
                end if
              else
                call highlight_command_line(temp_buf(:module_input_state%length), &
                                            module_highlighted_buffer, module_highlighted_len, &
                                            module_input_state%length)
                if (module_highlighted_len > 0 .and. module_highlighted_len <= len(module_highlighted_buffer)) then
                  write(output_unit, '(a)', advance='no') module_highlighted_buffer(:module_highlighted_len)
                else
                  ! Fallback to plain text (temp_buf already extracted above)
                  write(output_unit, '(a)', advance='no') temp_buf(:module_input_state%length)
                end if
              end if

              ! Display autosuggestion if present (only when cursor is at end)
              if (module_input_state%suggestion_length > 0 .and. &
                  module_input_state%cursor_pos == module_input_state%length) then
                ! Calculate column position after command (add 1 for space after prompt)
                cursor_visual_pos = prompt_visual_len + 1 + module_input_state%length

                ! Safety check for term_cols
                if (term_cols > 0 .and. term_cols <= 500) then
                  current_col = mod(cursor_visual_pos, term_cols)
                  current_row = cursor_visual_pos / term_cols

                  ! Additional safety: ensure current_col is reasonable
                  if (current_col < 0) current_col = 0
                  if (current_col >= term_cols) current_col = term_cols - 1

                  ! Calculate available space on current line
                  available_space = term_cols - current_col
                  if (available_space < 0) available_space = 0
                  if (available_space > term_cols) available_space = 0

                  ! CRITICAL: Prevent cursor jumping by ensuring suggestion never causes line wrap
                  ! The bug: if (prompt + input + suggestion) wraps to next line, then cursor-left
                  ! commands move cursor on the WRONG line, causing visible cursor jumping.
                  !
                  ! Solution:
                  ! 1. NEVER show suggestions if input has already wrapped (current_row > 0)
                  ! 2. Limit suggestion to fit on current line with safety margin
                  ! 3. Leave 2 char margin for ANSI codes
                  ! 4. Show if we have at least 3 chars of space (enough for 1 char + ANSI codes)
                  if (current_row == 0 .and. available_space >= 3) then
                    ! Limit suggestion to available space minus safety margin
                    suggestion_display_len = min(module_input_state%suggestion_length, available_space - 2)

                    if (suggestion_display_len < 0) suggestion_display_len = 0
                    if (suggestion_display_len > MAX_LINE_LEN) suggestion_display_len = 0
                    if (suggestion_display_len > module_input_state%suggestion_length) suggestion_display_len = 0

                    ! Show suggestion if we have at least 1 character
                    if (suggestion_display_len >= 1) then
                      ! Use bright black (gray) color for suggestions - ANSI code 90
                      write(output_unit, '(a)', advance='no') char(27) // '[90m'

                      ! Write character by character to avoid substring temporaries (flang-new crash)
                      do i_redraw = 1, suggestion_display_len
                        if (i_redraw <= MAX_LINE_LEN) then
                          write(output_unit, '(a)', advance='no') module_input_state%suggestion(i_redraw:i_redraw)
                        end if
                      end do

                      write(output_unit, '(a)', advance='no') char(27) // '[0m'   ! Reset color

                      ! Move cursor back using simple cursor-left commands
                      ! This is safe because we've guaranteed no wrapping above
                      do i_redraw = 1, suggestion_display_len
                        write(output_unit, '(a)', advance='no') char(27) // '[D'  ! Cursor left
                      end do
                    end if
                  end if
                end if
              end if
            end if

            ! Position cursor correctly (if not at end of input)
            if (module_input_state%cursor_pos < module_input_state%length) then
              ! Cursor not at end - calculate visual width difference
              ! IMPORTANT: Must use visual width, not byte count, for UTF-8 support

              ! Current cursor position (at end of drawn input)
              call cursor_get_row_col(prompt, module_input_state%length, term_cols, current_row, current_col)

              ! Desired cursor position
              call cursor_get_row_col(prompt, module_input_state%cursor_pos, term_cols, cursor_visual_pos, i_redraw)

              ! Move cursor left by VISUAL column difference
              ! (Not byte difference - emoji is 4 bytes but 2 visual columns!)
              if (current_col > i_redraw) then
                do current_line = 1, current_col - i_redraw
                  write(output_unit, '(a)', advance='no') char(27) // '[D'  ! Cursor left
                end do
              end if
            end if

            flush(output_unit)

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

          module_input_state%dirty = .false.
        end if
      end do
      
      ! Restore terminal
      if (.not. restore_terminal(module_original_termios)) then
        ! Warning but don't fail
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
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
      input_state%vi_command_buffer_ref%data = 'd'
#else
      input_state%vi_command_buffer = 'd'
#endif
      input_state%vi_command_count = repeat_count

    ! Change (with repeat)
    case (ichar('c'))
      ! Change with motion - set up for next character
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
      input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
#ifdef USE_C_STRINGS
      input_state%length = c_string_length(input_state%original_buffer_c)
#else
      input_state%length = len_trim(input_state%original_buffer)
#endif
#endif
      input_state%cursor_pos = min(input_state%cursor_pos, input_state%length)
      input_state%dirty = .true.

    ! Yank and Put (vi-style copy/paste)
    case (ichar('y'))
      ! Yank with motion - set up for next character
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
      input_state%vi_command_buffer_ref%data = 'm'
#else
      input_state%vi_command_buffer = 'm'
#endif
      input_state%vi_command_count = 1
    case (ichar("'"))
      ! Jump to mark - next character will be the mark name
#ifdef USE_MEMORY_POOL
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

    repeat_count = max(1, input_state%vi_command_count)

    select case (motion)
    case ('d')
      ! dd - delete entire line
      call state_buffer_get(input_state, input_state%vi_yank_buffer)
      input_state%vi_yank_buffer = input_state%vi_yank_buffer(:input_state%length)
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
#ifdef USE_MEMORY_POOL
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
      call state_buffer_get(input_state, input_state%vi_yank_buffer)
      input_state%vi_yank_buffer = input_state%vi_yank_buffer(:input_state%length)
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
#ifdef USE_MEMORY_POOL
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

    if (motion == 'c') then
      ! cc - change entire line
      call state_buffer_get(input_state, input_state%vi_yank_buffer)
      input_state%vi_yank_buffer = input_state%vi_yank_buffer(:input_state%length)
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
#ifdef USE_MEMORY_POOL
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
      input_state%vi_yank_buffer = temp_buf(start_pos:start_pos+yank_len-1)
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
  end subroutine

  subroutine move_to_previous_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: pos
    
    if (input_state%cursor_pos <= 0) return

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

    ! Find the last word to complete
    last_space_pos = 0
    do i = actual_len, 1, -1
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
          do i = 1, min(temp_count, MAX_LOCAL_COMPLETIONS)
            completions(i) = trim(temp_completions(i))
          end do
          num_completions = min(temp_count, MAX_LOCAL_COMPLETIONS)
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
          ! Only filter to directories when pattern is empty (path ends with /)
          ! i.e., cd-less navigation. When there's a filename pattern (./bin/fort),
          ! keep all matches so executables can be completed.
          if (len_trim(last_word) > 0 .and. &
              last_word(len_trim(last_word):len_trim(last_word)) == '/') then
            call filter_directories_only(completions, num_completions)
          end if
        else
          ! Complete commands (builtins + PATH executables)
          call complete_commands_enhanced(last_word, completions, num_completions)
        end if

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

    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    character(len=1024) :: ls_command
    character(len=:), allocatable :: ls_output_alloc
    character(len=8192) :: ls_output  ! Large buffer for ls output (8KB)
    character(len=MAX_LINE_LEN), allocatable :: entries(:)  ! Now allocatable to avoid stack overflow
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
    ls_output_alloc = execute_and_capture(ls_command)

    ! Copy to fixed buffer (use larger buffer to avoid truncation)
    if (allocated(ls_output_alloc)) then
      ls_output = ls_output_alloc(:min(len(ls_output), len(ls_output_alloc)))
    else
      ls_output = ''
    end if

    ! Parse ls output into individual entries
    call parse_ls_output(ls_output, entries, num_entries)

    ! Match entries against glob pattern
    do i = 1, num_entries
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit

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

    ! Clean up allocatable array
    if (allocated(entries)) deallocate(entries)
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

    ! Allocate scored array
    allocate(scored(100))  ! This should be enough for builtins
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

    ! Preserve explicit "./" prefix: when user typed "./something", dir_path
    ! is "." but completions should include "./" to match what was typed.
    ! Pass "./" as dir_path so scan_directory builds paths with "./" prefix.
    if (len_trim(prefix) >= 2 .and. prefix(1:2) == './') then
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

    character(len=1024) :: ls_command, expanded_dir  ! Large enough for command
    character(len=:), allocatable :: ls_output_alloc  ! From execute_and_capture
    character(len=2048) :: ls_output  ! 2KB buffer - large enough for ls but safe for stack
    character(len=MAX_LINE_LEN), allocatable :: entries(:)  ! Now allocatable to avoid stack overflow
    character(len=MAX_LINE_LEN) :: full_path
    character(len=:), allocatable :: home_dir, debug_mode
    ! Use allocatable array to avoid static storage
    type(scored_completion_t), allocatable :: scored(:)
    integer :: num_entries, i, pattern_len, num_scored, score, j
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

    ! Use ls command with -F flag to mark directories with / (avoids calling test -d for each file)
    ! Use tr to convert newlines to spaces for easier parsing
    ls_command = 'ls -1aF "' // trim(expanded_dir) // '" 2>/dev/null | tr ' // "'" // char(92) // 'n' // "' ' '"

    ! Debug output
    if (debug_enabled) then
    end if

    ! Get output from command (allocatable result)
    ls_output_alloc = execute_and_capture(ls_command)

    ! Copy to fixed buffer (avoids flang-new issues with allocatable strings)
    ls_output = ls_output_alloc(:min(len(ls_output), len(ls_output_alloc)))

    ! Clean up allocatable
    if (allocated(ls_output_alloc)) deallocate(ls_output_alloc)

    ! Parse ls output into individual entries
    call parse_ls_output(ls_output, entries, num_entries)

    ! Debug output
    if (debug_enabled) then
    end if

    ! Score entries using fuzzy matching
    num_scored = 0
    do i = 1, num_entries
      if (num_scored >= MAX_SCORED_ITEMS) exit

      ! Skip . and .. unless explicitly requested (ls -F adds / to these too)
      if (trim(entries(i)) == './' .or. trim(entries(i)) == '../' .or. &
          trim(entries(i)) == '.' .or. trim(entries(i)) == '..') then
        if (pattern_len == 0 .or. (pattern_len > 0 .and. pattern(1:1) /= '.')) then
          cycle
        end if
      end if

      ! Check if entry is a directory (ls -F adds / to directories)
      is_dir = .false.
      if (len_trim(entries(i)) > 0) then
        if (entries(i)(len_trim(entries(i)):len_trim(entries(i))) == '/') then
          is_dir = .true.
          ! Remove the trailing / for matching
          full_path = entries(i)(:len_trim(entries(i))-1)
        else
          ! Remove executable markers (*) and other ls -F markers (@, =, |, %)
          if (index('*@=|%', entries(i)(len_trim(entries(i)):len_trim(entries(i)))) > 0) then
            full_path = entries(i)(:len_trim(entries(i))-1)
          else
            full_path = trim(entries(i))
          end if
        end if
      else
        full_path = trim(entries(i))
      end if

      ! Calculate fuzzy match score (without the ls -F marker)
      score = fuzzy_match_score(pattern, trim(full_path))
      if (score >= 0) then  ! Negative score = no match
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

    ! Debug output
    if (debug_enabled) then
    end if

    ! Clean up allocatable arrays
    if (allocated(scored)) deallocate(scored)
    if (allocated(entries)) deallocate(entries)
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
    character(len=MAX_LINE_LEN), allocatable, intent(out) :: entries(:)
    integer, intent(out) :: num_entries

    integer :: pos, start, output_len, count_pass

    output_len = len_trim(output)

    ! First pass: count entries
    num_entries = 0
    pos = 1
    do while (pos <= output_len)
      ! Skip whitespace
      do while (pos <= output_len .and. (output(pos:pos) == ' ' .or. output(pos:pos) == char(9)))
        pos = pos + 1
      end do

      if (pos > output_len) exit

      start = pos

      ! Find end of entry (space only, since execute_and_capture converts newlines to spaces)
      do while (pos <= output_len .and. output(pos:pos) /= ' ')
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
        ! Skip whitespace
        do while (pos <= output_len .and. (output(pos:pos) == ' ' .or. output(pos:pos) == char(9)))
          pos = pos + 1
        end do

        if (pos > output_len) exit

        start = pos

        ! Find end of entry
        do while (pos <= output_len .and. output(pos:pos) /= ' ')
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
        ! Print item padded to column width
        write(output_unit, '(a)', advance='no') trim(completions(i))

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

    ! Use provided length if given, otherwise use len_trim
    if (present(input_len)) then
      actual_len = input_len
    else
      actual_len = len_trim(partial_input)
    end if

    completed = .false.
    completed_line = partial_input

    ! Find the prefix (command and any earlier arguments)
    last_space_pos = 0
    do i = actual_len, 1, -1
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

    ! Pass the actual length to preserve trailing spaces
    call enhanced_tab_complete(partial_input, completions, num_completions, input_len=actual_len)

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

      ! Output character directly to screen (avoid full redraw)
      write(output_unit, '(a)', advance='no') ch
      flush(output_unit)

      ! Update screen cursor position tracking
      call get_terminal_size_from_env(term_cols)
      module_cursor_screen_col = module_cursor_screen_col + 1

      ! Handle line wrapping - if we just filled the last column, wrap to next line
      if (module_cursor_screen_col >= term_cols) then
        ! Explicitly move cursor to next line (terminal won't auto-wrap cursor until next char)
        write(output_unit, '(a)', advance='no') char(13) // char(10)  ! CR+LF
        flush(output_unit)
        module_cursor_screen_col = 0
        module_cursor_screen_row = module_cursor_screen_row + 1
        ! Don't trigger redraw - character already on screen, cursor already positioned correctly
        ! Redraw would move cursor back up to row 0, causing snap-back
      else
        ! Only trigger syntax highlighting when NOT wrapping
        ! This gives immediate feedback (e.g., "exit" turning green)
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
    integer :: tab_num_completions, i, j, last_space_pos, copy_len
    logical :: tab_completed, tab_made_progress, tab_buffer_changed
    character(len=MAX_LINE_LEN) :: tab_completions(MAX_LOCAL_COMPLETIONS)
    character(len=MAX_LINE_LEN) :: tab_partial_input
    character(len=MAX_LINE_LEN) :: tab_completed_line
    character(len=MAX_LINE_LEN) :: tab_saved_input
    character(len=MAX_MENU_ITEM_LEN) :: temp_buffer

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
            input_state%menu_total_items = tab_num_completions
            input_state%menu_num_items = min(tab_num_completions, MAX_MENU_ITEMS)
            do i = 1, input_state%menu_num_items
              ! Copy via temp buffer to avoid flang-new bugs with allocatables
              temp_buffer = ' '
              copy_len = min(MAX_MENU_ITEM_LEN, len_trim(tab_completions(i)))
              do j = 1, copy_len
                temp_buffer(j:j) = tab_completions(i)(j:j)
              end do
              input_state%menu_items(i) = temp_buffer
            end do
            input_state%menu_selection = 1
            write(output_unit, '()')  ! Blank line before menu
            call draw_completion_menu(input_state, .true.)
            call state_last_completion_buffer_set_from_buffer(input_state)
            input_state%completions_shown = .true.
            ! Don't set dirty - menu is already drawn, no need to redraw command line
          else
            ! Second tab - enter menu selection mode
            ! Activate menu mode (items already stored and displayed)
            write(error_unit, '(a)') '[ENTERING_MENU_SELECT_MODE]'
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
#ifdef USE_MEMORY_POOL
              input_state%menu_prefix_ref%data = ''
              do j = 1, last_space_pos
                input_state%menu_prefix_ref%data(j:j) = tab_partial_input(j:j)
              end do
#else
              input_state%menu_prefix = ''
              do j = 1, last_space_pos
                input_state%menu_prefix(j:j) = tab_partial_input(j:j)
              end do
#endif
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
#ifdef USE_MEMORY_POOL
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
        input_state%menu_total_items = tab_num_completions
        input_state%menu_num_items = min(tab_num_completions, MAX_MENU_ITEMS)
        do i = 1, input_state%menu_num_items
          ! Copy via temp buffer to avoid flang-new bugs with allocatables
          temp_buffer = ' '
          copy_len = min(MAX_MENU_ITEM_LEN, len_trim(tab_completions(i)))
          do j = 1, copy_len
            temp_buffer(j:j) = tab_completions(i)(j:j)
          end do
          input_state%menu_items(i) = temp_buffer
        end do
        input_state%menu_selection = 1
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
#ifdef USE_MEMORY_POOL
          input_state%menu_prefix_ref%data = ''
          do i = 1, last_space_pos
            input_state%menu_prefix_ref%data(i:i) = tab_partial_input(i:i)
          end do
#else
          input_state%menu_prefix = ''
          do i = 1, last_space_pos
            input_state%menu_prefix(i:i) = tab_partial_input(i:i)
          end do
#endif
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
#ifdef USE_MEMORY_POOL
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
    character(len=MAX_MENU_ITEM_LEN) :: temp_buffer
    integer :: num_completions, i
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
            input_state%menu_total_items = num_completions
            input_state%menu_num_items = min(num_completions, MAX_MENU_ITEMS)
            do i = 1, input_state%menu_num_items
              ! Use temp_buffer and explicit copy to avoid truncation warnings
              temp_buffer = completions(i)(1:min(len_trim(completions(i)), MAX_MENU_ITEM_LEN))
              input_state%menu_items(i) = temp_buffer
            end do
            input_state%menu_selection = 1
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
        input_state%menu_total_items = num_completions
        input_state%menu_num_items = min(num_completions, MAX_MENU_ITEMS)
        do i = 1, input_state%menu_num_items
          ! Use temp_buffer and explicit copy to avoid truncation warnings
          temp_buffer = completions(i)(1:min(len_trim(completions(i)), MAX_MENU_ITEM_LEN))
          input_state%menu_items(i) = temp_buffer
        end do
        input_state%menu_selection = 1
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

  subroutine enter_menu_select_mode(input_state, completions, num_completions, current_input)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN), intent(in) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(in) :: num_completions
    character(len=*), intent(in) :: current_input
    character(len=MAX_MENU_ITEM_LEN) :: temp_buffer
    integer :: i, last_space_pos

    ! Store menu items
    input_state%in_menu_select = .true.
    input_state%menu_total_items = num_completions
    input_state%menu_num_items = min(num_completions, MAX_MENU_ITEMS)

    ! Clear autosuggestion when entering menu mode
    input_state%suggestion = ''
    input_state%suggestion_length = 0

    do i = 1, input_state%menu_num_items
      ! Use temp_buffer and explicit copy to avoid truncation warnings
      temp_buffer = completions(i)(1:min(len_trim(completions(i)), MAX_MENU_ITEM_LEN))
      input_state%menu_items(i) = temp_buffer
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
      ! Copy character by character to avoid substring on allocatable
#ifdef USE_MEMORY_POOL
      input_state%menu_prefix_ref%data = ''
#else
      input_state%menu_prefix = ''
#endif
      do i = 1, last_space_pos
        input_state%menu_prefix(i:i) = current_input(i:i)
      end do
      input_state%menu_prefix_len = last_space_pos  ! Store length WITH the space
    else
#ifdef USE_MEMORY_POOL
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
      write(error_unit, '(a)') '[CALLING_PREVIEW_FROM_ENTER_MENU]'
      call update_live_preview(input_state)
    end if
    flush(output_unit)
  end subroutine

  subroutine draw_completion_menu(input_state, initial_draw)
    type(input_state_t), intent(inout) :: input_state  ! inout to cache layout
    logical, intent(in) :: initial_draw
    integer :: i, j, cols_per_item, items_per_row, col, item_idx
    integer :: term_rows, term_cols, item_len
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=1) :: ch
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
      current_item = input_state%menu_items(i)
      item_len = len_trim(current_item)
      cols_per_item = max(cols_per_item, item_len)
    end do
    cols_per_item = cols_per_item + 2  ! Add spacing
    items_per_row = max(1, term_cols / cols_per_item)

    ! Cache the layout (always update cache for use by update_live_preview and navigation)
    input_state%menu_cols_per_item = cols_per_item
    input_state%menu_items_per_row = items_per_row
    input_state%menu_num_rows = (input_state%menu_num_items + items_per_row - 1) / items_per_row

    ! Draw menu items
    item_idx = 1
    do while (item_idx <= input_state%menu_num_items)
      ! Draw one row
      do col = 1, items_per_row
        if (item_idx > input_state%menu_num_items) exit

        ! Copy item to local variable to avoid substring operations on array element
        current_item = input_state%menu_items(item_idx)
        item_len = len_trim(current_item)

        ! Highlight selected item with reverse video
        if (item_idx == input_state%menu_selection) then
          write(output_unit, '(a)', advance='no') char(27) // '[7m'  ! Reverse video
        end if

        ! Write menu item character by character from local variable
        do j = 1, item_len
          ch = current_item(j:j)
          write(output_unit, '(a)', advance='no') ch
        end do

        if (item_idx == input_state%menu_selection) then
          write(output_unit, '(a)', advance='no') char(27) // '[0m'  ! Reset
        end if

        ! Pad to column width for alignment (except last column in row)
        if (col < items_per_row .and. item_idx < input_state%menu_num_items) then
          ! Pad with spaces to reach full column width
          do j = item_len + 1, cols_per_item
            write(output_unit, '(a)', advance='no') ' '
          end do
        end if

        item_idx = item_idx + 1
      end do
      write(output_unit, '()')  ! New line after each row
    end do

    ! Show "more items" indicator if there are truncated completions
    if (input_state%menu_total_items > input_state%menu_num_items) then
      write(output_unit, '(a,i15,a)') &
        '  ... ', input_state%menu_total_items - input_state%menu_num_items, ' more items available'
    end if

    ! Mark that we need to redraw the command line
    flush(output_unit)
  end subroutine

  subroutine handle_menu_navigation(input_state, key, done)
    type(input_state_t), intent(inout) :: input_state
    integer, intent(in) :: key
    logical, intent(inout) :: done
    integer :: old_selection, new_selection
    integer :: items_per_row
    integer :: current_row, current_col, target_row

    if (.false.) print *, done  ! Silence unused warning (set by caller)

    if (.not. input_state%in_menu_select) return

    old_selection = input_state%menu_selection

    select case (key)
    case (KEY_UP, KEY_DOWN)
      ! 2D navigation: move up/down by one row in the grid
      ! Use cached layout from input_state (avoids repeated array iterations)
      items_per_row = input_state%menu_items_per_row

      ! Calculate current position in grid (1-indexed)
      current_row = (input_state%menu_selection - 1) / items_per_row + 1
      current_col = mod(input_state%menu_selection - 1, items_per_row) + 1

      if (key == KEY_UP) then
        ! Move up one row
        target_row = current_row - 1
        if (target_row < 1) then
          ! Wrap to bottom row, same column
          target_row = (input_state%menu_num_items - 1) / items_per_row + 1
        end if
      else  ! KEY_DOWN
        ! Move down one row
        target_row = current_row + 1
        if ((target_row - 1) * items_per_row + current_col > input_state%menu_num_items) then
          ! Wrap to top row, same column
          target_row = 1
        end if
      end if

      ! Calculate new selection
      new_selection = (target_row - 1) * items_per_row + current_col
      ! Clamp to valid range
      if (new_selection < 1) new_selection = 1
      if (new_selection > input_state%menu_num_items) then
        ! If target position doesn't exist (incomplete last row), go to last item
        new_selection = input_state%menu_num_items
      end if
      input_state%menu_selection = new_selection

    case (KEY_LEFT)
      ! Move left one item (same row)
      input_state%menu_selection = input_state%menu_selection - 1
      if (input_state%menu_selection < 1) then
        input_state%menu_selection = input_state%menu_num_items  ! Wrap to end
      end if

    case (KEY_RIGHT)
      ! Move right one item (same row)
      input_state%menu_selection = input_state%menu_selection + 1
      if (input_state%menu_selection > input_state%menu_num_items) then
        input_state%menu_selection = 1  ! Wrap to beginning
      end if

    case (KEY_TAB)
      ! Tab continues to cycle sequentially through all items
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
#ifdef USE_MEMORY_POOL
        ch = input_state%menu_prefix_ref%data(i:i)
#else
        ch = input_state%menu_prefix(i:i)
#endif
        completed_len = completed_len + 1
        completed_line(completed_len:completed_len) = ch
      end do
    end if

    current_item = input_state%menu_items(input_state%menu_selection)
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

    ! CRITICAL: Set flag to skip upward cursor movement on redraw
    ! We're already on the first line after exit_menu_select_mode,
    ! so the redraw shouldn't try to move up based on cursor position
    input_state%skip_cursor_up_on_redraw = .true.

    ! Mark dirty to trigger redraw
    input_state%dirty = .true.

    ! Update autosuggestion for future use
    call update_autosuggestion(input_state)
  end subroutine

  subroutine exit_menu_select_mode(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, num_rows, term_rows, term_cols, cols_per_item, items_per_row, extra_lines
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

      ! Account for "more items" indicator line if present
      extra_lines = 0
      if (input_state%menu_total_items > input_state%menu_num_items) then
        extra_lines = 1
      end if

      ! Move cursor up to where the command line was (before the blank line and menu)
      ! Cursor is currently on empty line after the menu rows + extra lines
      ! Layout: [cmd][blank][row1]...[rowN][extra?][cursor here]
      ! Move up: num_rows (menu content) + extra_lines (more items) + 1 (blank line) + 1 (to command line)
      do i = 1, num_rows + extra_lines + 2
        write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
      end do

      ! Now at command line - clear from next line down to remove menu
      write(output_unit, '(a)', advance='no') char(13)  ! Carriage return (start of command line)
      write(output_unit, '(a)', advance='no') char(27) // '[K'  ! Clear current line (remove old command)
      write(output_unit, '(a)', advance='no') char(27) // '[B'  ! Move down to first menu line
      write(output_unit, '(a)', advance='no') char(27) // '[J'  ! Clear from cursor down (all menu)
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Move back up to command line
      write(output_unit, '(a)', advance='no') char(13)  ! Back to start of command line
    end if

    input_state%in_menu_select = .false.
    input_state%menu_num_items = 0
    input_state%menu_total_items = 0
    input_state%menu_selection = 1
    input_state%menu_prefix_len = 0
    input_state%completions_shown = .false.
    input_state%dirty = .true.
  end subroutine

  subroutine update_menu_selection(input_state, old_selection)
    type(input_state_t), intent(inout) :: input_state  ! inout to pass to draw function
    integer, intent(in) :: old_selection
    integer :: i, num_menu_rows, extra_lines, total_lines

    if (.false.) print *, old_selection  ! Silence unused warning

    ! Use cached layout from input_state (avoids repeated array iterations)
    num_menu_rows = input_state%menu_num_rows

    ! Account for "more items" indicator line if present
    extra_lines = 0
    if (input_state%menu_total_items > input_state%menu_num_items) then
      extra_lines = 1
    end if
    total_lines = num_menu_rows + extra_lines

    ! Move cursor up to the blank line before menu
    ! Cursor is currently on new line after last menu row (each row ends with newline)
    ! Menu layout: [blank line] [row 1] [row 2] ... [row N] [more items?] [cursor on new line]
    ! So we move up: num_menu_rows + extra_lines + 1 to get to blank line
    do i = 1, total_lines + 1
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
    end do
    write(output_unit, '(a)', advance='no') char(13)  ! Carriage return

    ! Clear the menu area including blank line (clear all lines including extra and blank)
    do i = 1, total_lines + 1
      write(output_unit, '(a)', advance='no') char(27) // '[K'  ! Clear line
      if (i < total_lines + 1) then
        write(output_unit, '()')  ! Move to next line
      end if
    end do

    ! Move back up to start (the blank line before menu)
    if (total_lines > 0) then
      do i = 1, total_lines
        write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
      end do
      write(output_unit, '(a)', advance='no') char(13)  ! Carriage return
    else
      write(output_unit, '(a)', advance='no') char(13)  ! Carriage return
    end if

    ! We're now positioned at the START of the blank line
    ! Output a blank line (to match initial draw spacing)
    write(output_unit, '()')  ! Blank line before menu

    ! Redraw the menu with the new selection highlighted
    call draw_completion_menu(input_state, .false.)

    flush(output_unit)
  end subroutine

  subroutine update_live_preview(input_state)
    type(input_state_t), intent(in) :: input_state
    integer :: i, j, num_menu_rows, extra_lines
    integer :: prompt_len, highlighted_len, item_len, preview_len
    character(len=MAX_LINE_LEN) :: preview_line, current_prefix
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=MAX_HIGHLIGHT_LEN) :: highlighted_preview  ! Fixed-length to avoid flang-new bugs
    character(len=1) :: ch

    ! Initialize buffer
    highlighted_preview = ' '
    highlighted_len = 0
    preview_line = ''

    ! Use cached menu layout (avoids repeated array iterations and len_trim calls)
    num_menu_rows = input_state%menu_num_rows

    ! Account for "more items" indicator line if present
    extra_lines = 0
    if (input_state%menu_total_items > input_state%menu_num_items) then
      extra_lines = 1
    end if

    ! Save current cursor position (after menu) - ESC[s
    write(output_unit, '(a)', advance='no') char(27) // '[s'

    ! Build preview line character by character (copy to local vars first)
    preview_len = 0
    if (input_state%menu_prefix_len > 0) then
      ! IMPORTANT: Copy allocatable menu_prefix character-by-character to avoid flang-new bug
      ! Direct assignment creates a temporary that gets corrupted
      current_prefix = ''  ! Initialize
      do i = 1, input_state%menu_prefix_len
#ifdef USE_MEMORY_POOL
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
    current_item = input_state%menu_items(input_state%menu_selection)
    item_len = len_trim(current_item)
    do j = 1, item_len
      ch = current_item(j:j)
      preview_len = preview_len + 1
      preview_line(preview_len:preview_len) = ch
    end do

    ! Move cursor up past menu to command line
    ! We need to go up: num_menu_rows + extra_lines (menu content) + 1 (blank line before menu) + 1 (to command line)
    do i = 1, num_menu_rows + extra_lines + 2
      write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
    end do

    ! Move to start of line
    write(output_unit, '(a)', advance='no') char(13)  ! CR

    ! Clear the entire line
    write(output_unit, '(a)', advance='no') char(27) // '[K'  ! Clear from cursor to end of line

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
      do i = 1, prompt_len
        ch = current_prefix(i:i)
        write(output_unit, '(a)', advance='no') ch
      end do
    end if

    ! Write space after prompt (to match the original spacing)
    write(output_unit, '(a)', advance='no') ' '

    ! Redraw highlighted preview character by character (already local var)
    if (highlighted_len > 0 .and. highlighted_len <= MAX_HIGHLIGHT_LEN) then
      do i = 1, highlighted_len
        ch = highlighted_preview(i:i)
        write(output_unit, '(a)', advance='no') ch
      end do
    end if

    ! Restore cursor position (back to after menu) - ESC[u
    write(output_unit, '(a)', advance='no') char(27) // '[u'

    flush(output_unit)
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
    character(len=MAX_LINE_LEN), intent(out) :: processes(MAX_MENU_ITEMS)
    integer, intent(out) :: pids(MAX_MENU_ITEMS)
    integer, intent(out) :: num_processes

    integer :: unit, iostat, pid
    character(len=512) :: line, cmd_name, username
    integer :: stat

    num_processes = 0

    ! Get current username for filtering
    call get_environment_variable('USER', username, status=stat)
    if (stat /= 0) then
      username = ''  ! Fall back to showing all processes if USER not set
    end if

    ! Use ps command to get process list for current user
    ! -u USER: processes for current user only
    ! -o pid,comm: output PID and command name
    ! --no-headers: no headers
    open(newunit=unit, file='/tmp/fortsh_procs.tmp', status='replace', &
         action='write', iostat=iostat)
    if (iostat /= 0) return
    close(unit)

    ! Execute ps and capture output - filter to current user
#ifdef __APPLE__
    ! macOS uses BSD ps which doesn't support --no-headers
    if (len_trim(username) > 0) then
      call execute_command_line('ps -u ' // trim(username) // &
                               ' -o pid= -o comm= > /tmp/fortsh_procs.tmp 2>/dev/null', &
                               exitstat=iostat)
    else
      call execute_command_line('ps -ax -o pid= -o comm= > /tmp/fortsh_procs.tmp 2>/dev/null', &
                               exitstat=iostat)
    end if
#else
    ! Linux uses GNU ps with --no-headers
    if (len_trim(username) > 0) then
      call execute_command_line('ps -u ' // trim(username) // &
                               ' -o pid,comm --no-headers > /tmp/fortsh_procs.tmp 2>/dev/null', &
                               exitstat=iostat)
    else
      call execute_command_line('ps -eo pid,comm --no-headers > /tmp/fortsh_procs.tmp 2>/dev/null', &
                               exitstat=iostat)
    end if
#endif

    if (iostat == 0) then
      ! Read the process list
      open(newunit=unit, file='/tmp/fortsh_procs.tmp', status='old', &
           action='read', iostat=iostat)

      if (iostat == 0) then
        ! Skip header if BSD-style (first line contains PID)
        read(unit, '(a)', iostat=iostat) line
        if (iostat == 0 .and. index(line, 'PID') > 0) then
          ! This was a header, skip it
        else if (iostat == 0) then
          ! Not a header, process it
          read(line, *, iostat=iostat) pid, cmd_name
          if (iostat == 0 .and. num_processes < MAX_MENU_ITEMS) then
            num_processes = num_processes + 1
            pids(num_processes) = pid
            processes(num_processes) = trim(cmd_name)
          end if
        end if

        ! Read remaining lines
        do while (iostat == 0 .and. num_processes < MAX_MENU_ITEMS)
          read(unit, '(a)', iostat=iostat) line
          if (iostat == 0 .and. len_trim(line) > 0) then
            ! Parse PID and command
            read(line, *, iostat=iostat) pid, cmd_name
            if (iostat == 0) then
              num_processes = num_processes + 1
              pids(num_processes) = pid
              processes(num_processes) = trim(cmd_name)
            end if
          end if
        end do

        close(unit)
      end if
    end if

    ! Clean up temp file
    call execute_command_line('rm -f /tmp/fortsh_procs.tmp 2>/dev/null')
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
      case('d')
        ! Alt+d - Delete forward one word (emacs standard)
        call handle_kill_word_forward(input_state)
      case('f')
        ! Alt+f - Move forward one word
        call move_to_next_word(input_state)
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
        ! Alt+w - Accept one word from autosuggestion
        if (input_state%cursor_pos == input_state%length .and. &
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
    integer :: paste_len, i
    character :: ch_paste

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

                        ! Insert buffered text at cursor position
                        do i = 1, paste_len
                          call insert_char_wrapper(input_state, paste_buffer(i:i))
                        end do
                        input_state%dirty = .true.
                        return
                      end if
                    end if
                  end if
                end if
              end if
              ! Not end marker, add ESC and what we read to buffer
              paste_len = paste_len + 1
              paste_buffer(paste_len:paste_len) = char(27)
              if (paste_len < MAX_LINE_LEN) then
                paste_len = paste_len + 1
                paste_buffer(paste_len:paste_len) = ch1
              end if
            else
              ! Regular character, add to paste buffer
              paste_len = paste_len + 1
              paste_buffer(paste_len:paste_len) = ch_paste
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
    logical :: debug_utf8
    integer :: debug_stat

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
  end subroutine
  
  subroutine handle_cursor_right(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: old_row, old_col, new_row, new_col, term_cols
    integer :: bytes_to_move

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
    else if (input_state%cursor_pos == input_state%length .and. input_state%suggestion_length > 0) then
      ! At end of line with suggestion - accept it
      call accept_autosuggestion(input_state)
    end if
  end subroutine
  
  subroutine handle_history_up(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: history_line
    logical :: found

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
#ifdef USE_MEMORY_POOL
      input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
#ifdef USE_C_STRINGS
      input_state%length = c_string_length(input_state%original_buffer_c)
#else
      input_state%length = len_trim(input_state%original_buffer)
#endif
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

    ! State machine for parsing escape sequences
    integer, parameter :: STATE_NORMAL = 0
    integer, parameter :: STATE_ESC = 1
    integer, parameter :: STATE_CSI = 2
    integer, parameter :: STATE_OSC = 3

    vlen = 0
    slen = len_trim(str)
    state = STATE_NORMAL

    i = 1
    do while (i <= slen)
      select case (state)
      case (STATE_NORMAL)
        if (str(i:i) == char(27)) then  ! ESC
          state = STATE_ESC
          i = i + 1
        else if (str(i:i) == char(13)) then  ! CR
          ! Carriage return - doesn't add to visual length
          i = i + 1
        else if (str(i:i) == char(10)) then  ! LF
          ! Newline resets visual position (for multi-line prompts)
          vlen = 0
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

    ! For short patterns (1-3 chars), require prefix match for better UX
    ! This prevents "RE" from matching "parser_enhanced.mod"
    ! and "tes" from matching "ast_types.mod"
    if (pattern_len <= 3) then
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

    ! Move cursor to beginning of line
    if (input_state%cursor_pos > 0) then
      input_state%cursor_pos = 0
      ! Mark dirty to trigger full redraw with correct cursor position
      input_state%dirty = .true.
    end if
  end subroutine
  
  subroutine handle_end(input_state)
    type(input_state_t), intent(inout) :: input_state

    ! Move cursor to end of line
    if (input_state%cursor_pos < input_state%length) then
      input_state%cursor_pos = input_state%length
      ! Mark dirty to trigger full redraw with correct cursor position
      input_state%dirty = .true.
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
    character(len=MAX_LINE_LEN) :: temp_buf
    integer :: current_row, current_col, i

    ! Save entire line in kill buffer
    if (input_state%length > 0) then
      ! Copy buffer to kill buffer via temp
      call state_buffer_get(input_state, temp_buf)
      call state_kill_buffer_set(input_state, temp_buf(:input_state%length))
      input_state%kill_length = input_state%length

      ! IMPORTANT: Move cursor to start of prompt BEFORE clearing buffer
      ! Otherwise redraw won't know where we are
      ! Use actual screen cursor position, not calculated from buffer
      current_row = module_cursor_screen_row
      current_col = module_cursor_screen_col

      ! Move up to first line if needed
      if (current_row > 0) then
        do i = 1, current_row
          write(output_unit, '(a)', advance='no') char(27) // '[A'  ! Cursor up
        end do
      end if

      ! Move to column 0
      write(output_unit, '(a)', advance='no') char(13)  ! CR
      flush(output_unit)

      ! Update cursor tracking - we're now at start of first line
      module_cursor_screen_row = 0
      module_cursor_screen_col = 0

      ! Now clear the line
      call state_buffer_clear(input_state)
      input_state%length = 0
      input_state%cursor_pos = 0

      ! Clear any autosuggestion
      input_state%suggestion = ''
      input_state%suggestion_length = 0

      input_state%dirty = .true.
    else
      input_state%kill_length = 0
    end if
  end subroutine
  
  subroutine handle_kill_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_start, i
    character(len=MAX_LINE_LEN) :: temp_buf

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
    
    if (input_state%kill_length == 0) return
    
    insert_len = min(input_state%kill_length, MAX_LINE_LEN - input_state%length)
    if (insert_len == 0) return
    
    ! Shift existing text right to make room
    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
      end if
    end do

    ! Insert killed text at cursor position
    do i = 1, insert_len
#ifdef USE_C_STRINGS
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, c_string_get_char(input_state%kill_buffer_c, i))
#else
#ifdef USE_MEMORY_POOL
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, input_state%kill_buffer_ref%data(i:i))
#else
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, input_state%kill_buffer(i:i))
#endif
#endif
    end do
    
    ! Update length and cursor position
    input_state%length = input_state%length + insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
  end subroutine
  
  subroutine handle_clear_screen(input_state, prompt)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: prompt
    character(len=4096) :: highlighted  ! Fixed-length to avoid flang-new allocatable bugs
    integer :: i, term_rows, term_cols, available_space, suggestion_display_len, highlighted_len
    logical :: success
    character(len=MAX_LINE_LEN) :: temp_buf  ! For buffer extraction

    highlighted = ' '
    highlighted_len = 0

    ! Clear screen and move cursor to home position (0,0)
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
#ifdef USE_MEMORY_POOL
        input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
#ifdef USE_C_STRINGS
        input_state%length = c_string_length(input_state%original_buffer_c)
#else
        input_state%length = len_trim(input_state%original_buffer)
#endif
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
#ifdef USE_MEMORY_POOL
    input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
#ifdef USE_C_STRINGS
    input_state%length = c_string_length(input_state%original_buffer_c)
#else
    input_state%length = len_trim(input_state%original_buffer)
#endif
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
#ifdef USE_MEMORY_POOL
      input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
#ifdef USE_C_STRINGS
      input_state%length = c_string_length(input_state%original_buffer_c)
#else
      input_state%length = len_trim(input_state%original_buffer)
#endif
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
#ifdef USE_MEMORY_POOL
    input_state%length = len_trim(input_state%original_buffer_ref%data)
#else
#ifdef USE_C_STRINGS
    input_state%length = c_string_length(input_state%original_buffer_c)
#else
    input_state%length = len_trim(input_state%original_buffer)
#endif
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
      call state_buffer_get(input_state, input_state%vi_yank_buffer)
      input_state%vi_yank_buffer = input_state%vi_yank_buffer(:input_state%length)
      input_state%vi_yank_length = input_state%length
    else
#ifdef USE_MEMORY_POOL
      input_state%vi_yank_buffer_ref%data = ''
#else
      input_state%vi_yank_buffer = ''
#endif
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

    ! Insert yanked text at insertion position
#ifdef USE_C_STRINGS
    ! Use C string API for insertion
    if (.not. c_string_insert(input_state%buffer_c, insert_pos + 1, &
                               input_state%vi_yank_buffer(:insert_len))) then
      ! Insertion failed, silently ignore
      return
    end if
#else
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
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
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
#ifdef USE_MEMORY_POOL
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

    ! Clear any existing suggestion
    input_state%suggestion = ''
    input_state%suggestion_length = 0

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

    ! Get filesystem completions for the last word
    call complete_files_enhanced(last_word(1:last_word_len), completions, num_completions)

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
           ' --color=always --style=numbers,changes --line-range=:500 {}'
    else
      preview_cmd = 'head -n 500 {}'
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
          '--preview=''ls -lah {}'' ' // &
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

    write(preview_cmd, '(a)') 'if [[ {} == *"==="* ]]; then echo "Select an item below"; ' // &
          'elif git show {}  >/dev/null 2>&1; then git show --stat {}; ' // &
          'else git diff {}; fi'

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

end module readline