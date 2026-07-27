! ==============================================================================
! Module: readline
! Purpose: Advanced input handling with command history and line editing
! ==============================================================================
module readline
  use shell_types
  use readline_constants
  use readline_state
  use readline_bufferops
  use readline_autopair
  use readline_history
  use readline_completion_backend
  use readline_editops
  use readline_vi
  use readline_fzf
  use string_utils, only: to_lowercase => char_lower
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

  ! Constants and core types live in readline_constants; all module-level
  ! mutable state (save vars, subsystem params, the C system() interface) lives
  ! in readline_state. Both are use-associated above.

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

  ! Append buffer content, converting each embedded newline to CR+LF so a
  ! multi-line buffer's logical lines each start at column 0 in raw mode (AR-10).
  ! Mirrors via the per-piece calls, so content_frame sees the rendered \r\n and
  ! content_byte_to_row_col rows it correctly.
  subroutine rdraw_append_nl(s)
    character(len=*), intent(in) :: s
    integer :: i
    do i = 1, len(s)
      if (s(i:i) == char(10)) then
        call rdraw_append(char(13) // char(10))
      else
        call rdraw_append_char(s(i:i))
      end if
    end do
  end subroutine

  subroutine rdraw_flush()
    if (rdraw_pos > 0) then
      write(output_unit, '(a)', advance='no') rdraw_buf(1:rdraw_pos)
      rdraw_pos = 0
    end if
    flush(output_unit)
  end subroutine


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
    dot_recording_insert = .false.  ! AR-05b 2b: never start a line mid-capture
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
  subroutine readline_enhanced(prompt, line, iostat, rprompt, keep_raw, shell)
    use signal_handler, only: g_terminal_resized
    character(len=*), intent(in) :: prompt
    character(len=*), intent(out) :: line
    integer, intent(out) :: iostat
    character(len=*), intent(in), optional :: rprompt  ! Right-side prompt (like zsh)
    logical, intent(in), optional :: keep_raw  ! Don't restore terminal on exit (for continuation)
    ! Live shell state, threaded in for completion (AR-06b: unexported vars).
    ! Optional so non-shell callers (tests, continuation prompts) still work.
    type(shell_state_t), intent(inout), optional :: shell

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
    integer :: ap_eff_len          ! AR-11: rendered buffer length (see ap_hide_tail)
    logical :: ap_hide_tail        ! AR-11: pending closers stand behind a suggestion
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
    ! RPROMPT (right-side prompt) re-emit layer — AR-08 NICE-RPROMPT1 + AR-87.
    integer :: rp_cur_row, rp_blen
    character(len=1024) :: rp_buf
    ! One-shot: the repaint triggered by a terminal resize skips the rprompt
    ! re-emit (its row-0 navigation is terminal-reflow-dependent and unreliable
    ! across a resize). rprompt comes back on the next normal redraw. (#87)
    logical :: resize_repaint
    ! Force the robust full-rebuild redraw (skip the Phase 2/3 diff) for the case
    ! the diff mis-navigates rows: a multi-line prompt + wrapping input.
    logical :: force_full_redraw
    integer :: fr_start_row, fr_end_row, fr_dummy
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
      if (.not. pool_ref_valid(module_input_state%buffer_ref)) then
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
    call undo_reset()   ! each line has its own undo history (DIV-1)
    call autopair_reset()  ! pending closers never cross a line (AR-11)

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

    ! Print the prompt (raw mode: bare LF -> CR+LF for multi-line prompts), the
    ! trailing space, then the right prompt as a separate layer (AR-87). One path
    ! for every prompt shape — the redraw re-emits the SAME layer each frame.
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

    if (present(rprompt)) then
      ! Cursor is at the input start (the prompt's last row); rp_cur_row tells
      ! the layer how far up row 0 is.
      call cursor_get_row_col(prompt, 0, term_cols, rp_cur_row, i_redraw)
      call build_rprompt_layer(prompt, rprompt, term_cols, rp_cur_row, rp_buf, rp_blen)
      if (rp_blen > 0) write(output_unit, '(a)', advance='no') rp_buf(1:rp_blen)
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
      resize_repaint = .false.
      do while (.not. done)
        ! Handle terminal resize BEFORE reading input. read_utf8_char
        ! returns every 100ms on poll timeout, so this fires promptly.
        if (g_terminal_resized) then
          g_terminal_resized = .false.
          prev_diff_valid = .false.
          prev_render_valid = .false.

          block
            integer :: reflow_rows, up_i, reflow_new, reflow_col

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

            ! Move the cursor up to the prompt origin, then clear from there
            ! down, so the dirty redraw below repaints the whole line at the NEW
            ! width with nothing stale left behind.
            !
            ! Safety net (#87): the cursor's true row offset from the prompt
            ! origin after a resize is terminal-dependent — a terminal that
            ! rewraps existing lines leaves it at cursor_get_row_col(NEW width);
            ! one that doesn't leaves it at the tracked OLD-width physical row
            ! (module_cursor_screen_row). We can't know which, and the rprompt's
            ! wide first line only adds rows on top. Move up by the MINIMUM of the
            ! two: that is <= the real offset in every case, so the ESC[J can
            ! never reach ABOVE the origin and eat real output. Worst case is an
            ! under-move, whose artifact is a harmless duplicate line, not data
            ! loss. (DSR-based exact positioning layers on top of this.)
            call cursor_get_row_col(prompt, module_input_state%cursor_pos, &
                                    term_cols, reflow_new, reflow_col)
            reflow_rows = min(module_cursor_screen_row, reflow_new)
            if (reflow_rows < 0) reflow_rows = 0
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
          resize_repaint = .true.   ! skip the rprompt re-emit for THIS repaint
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

        ! Rotate the kill/yank "was the previous key a kill/yank?" flags once
        ! per real keystroke (DIV-2): prev <- this, then this <- false. A kill
        ! op consults *_prev_key to merge consecutive kills; Alt-y (yank-pop)
        ! consults yank_op_prev_key so it only fires right after a yank.
        kill_op_prev_key = kill_op_this_key
        kill_op_this_key = .false.
        yank_op_prev_key = yank_op_this_key
        yank_op_this_key = .false.

        ! Undo (DIV-1): rotate the insert-run flag, clear the navigate guard, and
        ! snapshot the live buffer BEFORE dispatch. undo_commit_if_changed (after
        ! dispatch) pushes this snapshot iff the key actually changed the buffer.
        undo_prev_was_insert = undo_op_was_insert
        undo_op_was_insert = .false.
        undo_navigate_this_key = .false.
        call undo_capture_pre(module_input_state)

        ! AR-11 PAIRS: the pending auto-inserted closers are tracked by buffer
        ! POSITION, and only self-insert, skip-over and pair-backspace keep
        ! those positions honest. Arm the flag here; each of those three sets
        ! it, and the post-dispatch sweep below drops the whole stack for any
        ! OTHER key that moved bytes. That single choke point is why no edit
        ! path (kill, yank, history recall, completion, undo, vi ops, FZF)
        ! needs a reset of its own — and a dropped stack costs at most a
        ! skip-over, never a wrong edit.
        ap_keep_this_key = .false.

        ! Fish-style paste highlight clears on the next key. The bracketed-paste
        ! handler re-arms it after inserting, so clearing here (before dispatch)
        ! correctly leaves it lit only until the user's next keystroke/motion.
        module_paste_hl_cleared_this_key = .false.
        if (module_input_state%paste_hl_active) then
          module_input_state%paste_hl_active = .false.
          module_paste_hl_cleared_this_key = .true.  ! AR-01-fu: suppress accept on this key
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
            ! AR-11 PAIRS: accepting a menu item rewrites the buffer wholesale,
            ! so any recorded closer position is meaningless afterwards. This
            ! path cycles past the post-dispatch sweep, hence the explicit drop.
            call autopair_reset()
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
            call autopair_reset()
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
          call undo_commit_if_changed(module_input_state)  ! DIV-1 (this path cycles)
          ! AR-11 PAIRS: insert_utf8_char shifted the pending closers itself, so
          ! nothing to drop here — typing CJK or an emoji inside a pair must not
          ! cost the closing quote its skip-over.
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

        ! NICE-CTRLD (AR-08): the empty-line Ctrl-D running-jobs warning is a
        ! two-step (warn once, exit on a second consecutive Ctrl-D). Any other
        ! key resets the latch so a later Ctrl-D warns fresh.
        if (char_code /= KEY_CTRL_D) ctrld_warned = .false.

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
            ! AR-07 ABBR-ENTER: expand a pending command-position abbreviation
            ! before submitting (fish binds execute to expand-abbr first), so
            ! `gco<Enter>` runs the expansion. dirty (set by the expansion) makes
            ! the deferred-newline redraw repaint the expanded line in place.
            call try_expand_abbreviation_at_cursor(module_input_state)
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
            ! NICE-CTRLD (AR-08): if jobs are still running, warn once and don't
            ! exit; a second consecutive Ctrl-D exits (mirrors fish/bash). No
            ! jobs (or no shell state) -> exit immediately as before.
            if (present(shell) .and. .not. ctrld_warned) then
              if (has_active_jobs(shell)) then
                write(output_unit, '(a)') char(13) // char(10) // &
                  'There are still jobs active.'
                ctrld_warned = .true.
                module_input_state%length = 0
                module_input_state%cursor_pos = 0
                module_input_state%dirty = .false.
                done = .true.   ! return an empty line; the REPL re-prompts
              else
                iostat = -1
                done = .true.
              end if
            else
              iostat = -1
              done = .true.
            end if
          else if (.not. module_input_state%in_search) then
            call handle_forward_delete_char(module_input_state)
          end if

        case(KEY_CTRL_C)
          ! Ctrl+C - cancel and clear line (bash-compatible)
          if (.not. module_input_state%in_search .and. module_input_state%length == 0) then
            ! fish: Ctrl-C on an empty line does nothing — no `^C`, no newline,
            ! the same prompt is reused (NICE-CTRLC, AR-08). Stay in the loop.
            module_input_state%dirty = .false.
          else
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
          end if

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
              call handle_tab_key_separate(module_input_state, shell)
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
            ! Ctrl+W = fish backward-kill-path-component (exit menu first).
            ! Alt+Backspace remains the punctuation-aware backward-kill-word.
            if (module_input_state%in_menu_select) then
              call exit_menu_select_mode(module_input_state)
            end if
            call handle_kill_path_component(module_input_state)
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

        case(31)
          ! Ctrl-/ (and Ctrl-_, same byte 0x1f): undo (DIV-1). Skip in search/
          ! menu modes, which own their own input handling.
          if (.not. module_input_state%in_search .and. &
              .not. module_input_state%in_menu_select) then
            call handle_undo(module_input_state)
          end if

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
                   module_input_state%vi_mode == VI_MODE_VISUAL) then
            ! In Vi visual mode - route to visual handler (AR-05b)
            call handle_vi_visual_mode(module_input_state, char_code)
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

        ! Undo (DIV-1): record this keystroke's edit (if any) as an undo point.
        call undo_commit_if_changed(module_input_state)

        ! AR-11 PAIRS: see the arming comment above. A key that left the bytes
        ! alone (any cursor motion, Ctrl-L, a search keystroke) cannot have
        ! invalidated the recorded positions, so the stack survives it.
        if (.not. ap_keep_this_key) then
          if (autopair_buffer_changed(module_input_state)) call autopair_reset()
        end if

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

            ! Cursor row/col via the shared rendering model — handles wrapped
            ! and multi-line prompts correctly and matches content_byte_to_row_col
            ! (the diff positioner), so the nav-up and diff-down cancel instead
            ! of drifting (the resize "staircase"). The right prompt is a separate
            ! ESC7/ESC8 layer (re-emitted below), so it does NOT shift this row.
            call cursor_get_row_col(prompt, module_input_state%cursor_pos, &
                                    term_cols, current_row, current_col)
            ! The Phase 2/3 content diff mis-navigates rows when a MULTI-LINE
            ! prompt is combined with WRAPPING input (editing across a wrap
            ! boundary duplicates a wrapped segment). Force the robust full
            ! rebuild for that case; the fast diff still serves single-line
            ! prompts and non-wrapping input.
            force_full_redraw = .false.
            if (index(prompt(1:len_trim(prompt)), char(10)) > 0) then
              call cursor_get_row_col(prompt, 0, term_cols, fr_start_row, fr_dummy)
              call cursor_get_row_col(prompt, module_input_state%length, &
                                      term_cols, fr_end_row, fr_dummy)
              if (fr_end_row > fr_start_row) force_full_redraw = .true.
            end if
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
            ! Move up by the cursor's PHYSICAL row, tracked in
            ! module_cursor_screen_row (now the full terminal row from the prompt
            ! origin, prompt wrap rows included — cursor_get_row_col convention).
            ! Use the physical row, NOT current_row (the NEW cursor_pos's row):
            ! a cursor JUMP that forces a full redraw (e.g. Home after a paste,
            ! where clearing the paste highlight invalidates the Phase-1 cursor-
            ! only path) leaves the physical cursor on a different row than
            ! current_row implies, so current_row would repaint from the wrong
            ! origin (wrapped-line duplication).
            ! (move_up_rows declared at subroutine scope — a 'block' construct
            ! here crashes flang-new on macOS ARM64; see other workarounds.)
            move_up_rows = module_cursor_screen_row
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

            ! Save cursor-up row count before content overwrites it. Use the
            ! PHYSICAL row the old render left the cursor on
            ! (module_cursor_screen_row), NOT current_row (the row the NEW,
            ! possibly shorter, content's cursor lands on). When the old render
            ! was taller than the new content (e.g. recalling a short line over a
            ! wrapped one, or Ctrl-U on a wrapped recall), current_row
            ! under-counts the physical rows, so the differential move-up below
            ! stops short and ESC[J clears from a stale wrapped row — splicing
            ! the new tail onto old content. This mirrors the full-rebuild path
            ! at move_up_rows = module_cursor_screen_row above. (RL-2)
            nav_cursor_row = module_cursor_screen_row

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

              ! AR-11 PAIRS: when a suggestion is live and the ONLY thing right
              ! of the cursor is the closers we auto-inserted, render the buffer
              ! up to the cursor and let the suggestion stand in for them. The
              ! suggestion carries its own closing quote, so "echo \"quo" shows
              ! as `echo "quoted hello there"` rather than the nonsense
              ! `echo "quo"ted hello there"`; accepting drops the pending
              ! closers. Restricted to the plain single-line render path so the
              ! shortened length and the suggestion block below always agree —
              ! the selection / paste-highlight / prefix-search branches draw
              ! their own segments off the full length.
              ap_hide_tail = (module_input_state%suggestion_length > 0 .and. &
                              .not. module_input_state%selection_active .and. &
                              .not. module_input_state%paste_hl_active .and. &
                              .not. module_input_state%in_prefix_search .and. &
                              index(temp_buf(:module_input_state%length), char(10)) == 0 .and. &
                              autopair_tail_only(module_input_state))
              ap_eff_len = module_input_state%length
              if (ap_hide_tail) ap_eff_len = module_input_state%cursor_pos

              ! Multi-line buffer (AR-10, e.g. a pasted snippet): render with
              ! \n -> \r\n so each logical line starts at column 0. Highlight
              ! still applies (tokenize_v2 treats \n as a separator). This path
              ! only runs when the buffer actually has a newline, so every
              ! single-line case below is unchanged.
              if (index(temp_buf(:module_input_state%length), char(10)) > 0) then
                call highlight_command_line(temp_buf(:module_input_state%length), &
                                            module_highlighted_buffer, module_highlighted_len, &
                                            module_input_state%length)
                if (module_highlighted_len > 0 .and. module_highlighted_len <= len(module_highlighted_buffer)) then
                  call rdraw_append_nl(module_highlighted_buffer(:module_highlighted_len))
                else
                  call rdraw_append_nl(temp_buf(:module_input_state%length))
                end if

              ! Selection rendering: three segments — plain, reverse-video, plain
              else if (module_input_state%selection_active) then
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
                call highlight_command_line(temp_buf(:ap_eff_len), &
                                            module_highlighted_buffer, module_highlighted_len, &
                                            ap_eff_len)
                if (module_highlighted_len > 0 .and. module_highlighted_len <= len(module_highlighted_buffer)) then
                  call rdraw_append(module_highlighted_buffer(:module_highlighted_len))
                else
                  call rdraw_append(temp_buf(:ap_eff_len))
                end if
              end if

              ! Display autosuggestion if present (only when the cursor is at
              ! the end of what we just RENDERED — end of buffer normally, or
              ! end of the typed text when ap_hide_tail parked the closers).
              if (module_input_state%suggestion_length > 0 .and. &
                  module_input_state%cursor_pos == ap_eff_len) then
                cursor_visual_pos = prompt_visual_len + 1 + ap_eff_len

                if (term_cols > 0 .and. term_cols <= 500) then
                  current_col = mod(cursor_visual_pos, term_cols)
                  current_row = cursor_visual_pos / term_cols
                  if (current_col < 0) current_col = 0
                  if (current_col >= term_cols) current_col = term_cols - 1

                  available_space = term_cols - current_col
                  if (available_space < 0) available_space = 0
                  if (available_space > term_cols) available_space = 0

                  ! Render on whatever physical row the end-of-line lands (AS-2).
                  ! cursor_pos == length means this is the last row; the
                  ! suggestion is truncated to available_space-2 so it never
                  ! wraps off this row, and the trailing ESC[D backtrack returns
                  ! the cursor to end-of-input regardless of the row number.
                  if (available_space >= 3) then
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
            if (prev_render_valid .and. .not. force_full_redraw .and. &
                cframe_pos > 0 .and. prev_render_len > 0) then
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

            ! Right prompt (AR-08 NICE-RPROMPT1 + AR-87): the ESC[J above wiped
            ! it; re-emit it as a separate layer right-aligned on ROW 0 via
            ! ESC7/ESC[A/ESC[nG/ESC8 (save, up-to-row-0, absolute-column,
            ! restore). The column is recomputed from the CURRENT term_cols each
            ! redraw so it can't go stale after a resize, and the layer leaves the
            ! input cursor and the wrap-row math untouched. Single-line: row 0 is
            ! the input row. Multi-line: row 0 is the first prompt line (stable as
            ! you type). Suppressed when row-0 content reaches the rprompt zone.
            if (present(rprompt) .and. .not. resize_repaint) then
              ! Recompute the cursor's row here: the physical cursor now sits at
              ! cursor_pos (the reposition block ran, or it's at end-of-input).
              ! current_row may have been reused by the autosuggestion block.
              call cursor_get_row_col(prompt, module_input_state%cursor_pos, &
                                      term_cols, rp_cur_row, i_redraw)
              call build_rprompt_layer(prompt, rprompt, term_cols, rp_cur_row, &
                                       rp_buf, rp_blen)
              if (rp_blen > 0) call rdraw_append(rp_buf(1:rp_blen))
            end if
            ! Clear the one-shot: the next (non-resize) redraw re-emits rprompt.
            resize_repaint = .false.

            ! Show cursor, then flush entire buffer in one write
            call rdraw_append(ESC_SHOW_CURSOR)
            call rdraw_flush()

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
          ! AR-10: in a MULTI-LINE buffer the cursor may sit on an interior line
          ! (e.g. after editing line 2 of a pasted block). Step down to the LAST
          ! line first, so the newline — and the command output below it — lands
          ! beneath the whole buffer instead of overwriting the lines under the
          ! cursor. The physical cursor is at cursor_get_row_col(cursor_pos).
          call cursor_get_row_col(prompt, module_input_state%length, term_cols, &
                                  current_row, current_col)
          call cursor_get_row_col(prompt, module_input_state%cursor_pos, term_cols, &
                                  cursor_visual_pos, available_space)
          if (current_row > cursor_visual_pos) then
            do current_line = 1, current_row - cursor_visual_pos
              write(output_unit, '(a)', advance='no') char(27) // '[B'
            end do
          end if
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

  ! Wrapper to work around potential flang-new bug with repeated function calls
  subroutine insert_char_wrapper(input_state, ch)
    type(input_state_t), intent(inout) :: input_state
    character, intent(in) :: ch
    undo_op_was_insert = .true.   ! DIV-1: mark a self-insert so a run coalesces
    ! AR-05b 2b: capture text typed during a vi insert/change for dot-repeat.
    if (dot_recording_insert .and. dot_insert_len < MAX_LINE_LEN) then
      dot_insert_len = dot_insert_len + 1
      dot_insert_buf(dot_insert_len:dot_insert_len) = ch
    end if
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

    undo_op_was_insert = .true.   ! DIV-1: multi-byte self-insert coalesces too

    ! AR-05b 2b: capture typed bytes during a vi insert/change for dot-repeat.
    if (dot_recording_insert) then
      do i = 1, num_bytes
        if (dot_insert_len >= MAX_LINE_LEN) exit
        dot_insert_len = dot_insert_len + 1
        dot_insert_buf(dot_insert_len:dot_insert_len) = utf8_bytes(i:i)
      end do
    end if

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

    ! AR-11 PAIRS: shift the pending closers over the bytes just inserted. The
    ! character occupies positions cursor_pos-num_bytes+1 .. cursor_pos now that
    ! the cursor has advanced past it.
    call autopair_note_insert_n(input_state%cursor_pos - num_bytes + 1, num_bytes)
    ap_keep_this_key = .true.

    ! Update autosuggestion
    call update_autosuggestion(input_state)
  end subroutine insert_utf8_char


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
    logical :: ap_consumed

    ! Shift-phase (Sprint 3): Backspace on an active selection deletes the
    ! whole range — no further character deletion. The key is "consumed".
    if (input_state%selection_active) then
      call delete_selection(input_state)
      call update_autosuggestion(input_state)
      return
    end if

    ! AR-11 PAIRS: backspacing out of an empty pair we created — cursor sitting
    ! in "(|)" — removes both halves, so an auto-close is undone by the same
    ! single keypress that would have undone a plain insert.
    call autopair_try_backspace(input_state, ap_consumed)
    if (ap_consumed) then
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

    ! AR-11 PAIRS: a plain backspace inside a pair shifts the pending closers
    ! left; deleting one of them drops the stack (handled inside note_delete).
    ! Claiming the key keeps the post-dispatch sweep from wiping the rest.
    call autopair_note_delete(input_state%cursor_pos + 1, bytes_to_delete)
    ap_keep_this_key = .true.

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
    ! AR-11 PAIRS: as in handle_backspace — shift the pending closers left over
    ! the span just removed rather than losing them to the sweep.
    call autopair_note_delete(input_state%cursor_pos + 1, bytes_to_delete)
    ap_keep_this_key = .true.
    call update_autosuggestion(input_state)
  end subroutine

  ! Separate tab completion handler to work around macOS ARM64 crash
  ! This modifies the SAVE'd input_state directly without problematic returns
  subroutine handle_tab_key_separate(input_state, shell)
    type(input_state_t), intent(inout) :: input_state
    type(shell_state_t), intent(inout), optional :: shell
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
                           tab_num_completions, tab_completed_line, tab_completed, input_state%length, shell)

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

      ! AR-06: a UNIQUE non-directory completion gets a trailing space, so the
      ! next token can be typed immediately (fish; mirrors the menu-accept path).
      ! Directories already end in '/'. Skip glob expansions (multi-word).
      if (tab_num_completions == 1 .and. input_state%length >= 1 .and. &
          input_state%length < MAX_LINE_LEN .and. &
          .not. has_glob_chars(tab_partial_input)) then
        if (state_buffer_get_char(input_state, input_state%length) /= '/' .and. &
            state_buffer_get_char(input_state, input_state%length) /= ' ') then
          call state_buffer_set_char(input_state, input_state%length + 1, ' ')
          input_state%length = input_state%length + 1
          input_state%cursor_pos = input_state%length
        end if
      end if

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
            call menu_setup_items(input_state, tab_completions, tab_num_completions, shell)
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

            ! Enter on the FIRST item, highlighted (AR-03 menu-sel: was item 2)
            if (input_state%menu_num_items >= 1) then
              input_state%menu_selection = 1
              call update_menu_selection(input_state, 1)
              call update_live_preview(input_state)
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
        call menu_setup_items(input_state, tab_completions, tab_num_completions, shell)
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

        ! Enter on the FIRST item, highlighted (AR-03 menu-sel: was item 2)
        if (input_state%menu_num_items >= 1) then
          input_state%menu_selection = 1
          call update_menu_selection(input_state, 1)
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
  subroutine menu_setup_items(input_state, completions, num_completions, shell)
    type(input_state_t), intent(inout) :: input_state
    character(len=*), intent(in) :: completions(:)
    integer, intent(in) :: num_completions
    type(shell_state_t), intent(in), optional :: shell
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
    ! AR-03c: fish-style descriptions (var values, builtin summaries).
    call compute_menu_descs(input_state, shell)
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

  ! Description accessor, parallel to menu_item_get (AR-03c).
  function menu_desc_get(input_state, idx) result(desc)
    type(input_state_t), intent(in) :: input_state
    integer, intent(in) :: idx
    character(len=MAX_MENU_DESC_LEN) :: desc

    if (pager_active) then
      desc = pager_descs(idx)
    else
      desc = input_state%menu_descs(idx)
    end if
  end function

  ! Fill the description store for the current menu (AR-03c). The kind is
  ! derived from the line's last word: a `$`-word means variable completion
  ! (describe each with its value); a first-word means command completion
  ! (describe builtins with a one-line summary). Everything else (files, dirs,
  ! options for now) gets a blank description, which renders as the plain
  ! name-only grid — so file menus are untouched.
  subroutine compute_menu_descs(input_state, shell)
    type(input_state_t), intent(inout) :: input_state
    type(shell_state_t), intent(in), optional :: shell
    character(len=MAX_LINE_LEN) :: buf, last_word, first_word
    character(len=MAX_MENU_ITEM_LEN) :: item
    character(len=MAX_MENU_DESC_LEN) :: desc
    integer :: i, n, last_space, first_space, kind, word_count, words_before
    logical :: in_word

    ! Determine the completion kind from the line up to the cursor.
    n = input_state%cursor_pos
    if (n > input_state%length) n = input_state%length
    call state_buffer_get(input_state, buf)
    last_space = 0
    do i = 1, n
      if (buf(i:i) == ' ') last_space = i
    end do
    if (last_space > 0) then
      last_word = buf(last_space+1:n)
    else
      last_word = buf(1:n)
    end if

    ! First word = the command; word_count = how many words are present up to the
    ! cursor (so word 2 of `git ` is the subcommand position). (#88)
    first_space = 0
    do i = 1, n
      if (buf(i:i) == ' ') then
        first_space = i
        exit
      end if
    end do
    if (first_space > 0) then
      first_word = buf(1:first_space-1)
    else
      first_word = buf(1:n)
    end if
    word_count = 0
    in_word = .false.
    do i = 1, n
      if (buf(i:i) == ' ') then
        in_word = .false.
      else if (.not. in_word) then
        in_word = .true.
        word_count = word_count + 1
      end if
    end do
    ! Complete words BEFORE the word being completed: if the cursor is mid-word
    ! (last_word non-empty) the last counted word is that partial; otherwise the
    ! cursor is after a space and every counted word is complete.
    words_before = word_count
    if (len_trim(last_word) > 0) words_before = word_count - 1

    if (len_trim(last_word) >= 1 .and. last_word(1:1) == '$') then
      kind = MDESC_VAR
    else if (last_space == 0) then
      kind = MDESC_CMD
    else if (len_trim(last_word) >= 1 .and. last_word(1:1) == '-') then
      kind = MDESC_OPT          ! -flag after a command (#88)
    else if (trim(first_word) == 'git' .and. words_before == 1) then
      ! `git <subcommand>` position ONLY: exactly one complete word (git)
      ! precedes the word being completed. `git log <arg>` (words_before == 2)
      ! is NOT the subcommand position, so its items aren't labelled subcommands.
      kind = MDESC_SUB          ! (#88)
    else
      kind = MDESC_NONE
    end if

    do i = 1, input_state%menu_num_items
      desc = ' '
      if (kind == MDESC_VAR) then
        item = menu_item_get(input_state, i)
        desc = describe_variable(trim(item), shell)
      else if (kind == MDESC_CMD) then
        item = menu_item_get(input_state, i)
        desc = builtin_summary(trim(item))
      else if (kind == MDESC_OPT) then
        item = menu_item_get(input_state, i)
        desc = option_summary(trim(first_word), trim(item))
      else if (kind == MDESC_SUB) then
        item = menu_item_get(input_state, i)
        desc = git_subcommand_summary(trim(item))
      end if
      if (pager_active) then
        pager_descs(i) = desc
      else
        input_state%menu_descs(i) = desc
      end if
    end do
  end subroutine

  ! Value of a `$NAME` completion item, for the description column (AR-03c).
  ! Prefer a shell variable (covers unexported locals), fall back to environ.
  function describe_variable(item, shell) result(desc)
    character(len=*), intent(in) :: item
    type(shell_state_t), intent(in), optional :: shell
    character(len=MAX_MENU_DESC_LEN) :: desc
    character(len=MAX_LINE_LEN) :: val
    character(len=MAX_VAR_NAME_LEN) :: name
    integer :: i, vlen

    desc = ' '
    if (len_trim(item) < 1) return
    if (item(1:1) == '$') then
      name = adjustl(item(2:))
    else
      name = adjustl(item)
    end if
    if (len_trim(name) == 0) return

    val = ' '
    vlen = 0
    if (present(shell)) then
      do i = 1, shell%num_variables
        if (trim(shell%variables(i)%name) == trim(name)) then
          if (allocated(shell%variables(i)%value)) then
            vlen = len_trim(shell%variables(i)%value)
            if (vlen > 0) val = shell%variables(i)%value(1:min(vlen, MAX_LINE_LEN))
          end if
          exit
        end if
      end do
    end if
    if (vlen == 0) then
      val = get_environment_var(trim(name))
      vlen = len_trim(val)
    end if
    if (vlen > 0) desc = val(1:min(vlen, MAX_MENU_DESC_LEN))
  end function

  ! One-line summary for a builtin command, for the description column (AR-03c).
  ! Blank for non-builtins (external commands get no description here).
  function builtin_summary(name) result(desc)
    character(len=*), intent(in) :: name
    character(len=MAX_MENU_DESC_LEN) :: desc
    desc = ' '
    select case (trim(name))
    case ('cd');      desc = 'change the working directory'
    case ('pwd');     desc = 'print the working directory'
    case ('echo');    desc = 'write arguments to standard output'
    case ('printf');  desc = 'format and print arguments'
    case ('export');  desc = 'set an environment variable'
    case ('unset');   desc = 'remove a variable'
    case ('alias');   desc = 'define or show command aliases'
    case ('unalias'); desc = 'remove an alias'
    case ('source', '.'); desc = 'run a script in the current shell'
    case ('exit');    desc = 'exit the shell'
    case ('exec');    desc = 'replace the shell with a command'
    case ('read');    desc = 'read a line into variables'
    case ('test', '['); desc = 'evaluate a conditional expression'
    case ('jobs');    desc = 'list background jobs'
    case ('fg');      desc = 'resume a job in the foreground'
    case ('bg');      desc = 'resume a job in the background'
    case ('kill');    desc = 'send a signal to a job or process'
    case ('wait');    desc = 'wait for a job to finish'
    case ('history'); desc = 'show the command history'
    case ('type');    desc = 'describe how a name would be run'
    case ('hash');    desc = 'remember command locations'
    case ('umask');   desc = 'set the file-creation mask'
    case ('set');     desc = 'set shell options and parameters'
    case ('unsetopt', 'setopt'); desc = 'change a shell option'
    case ('local');   desc = 'declare a function-local variable'
    case ('return');  desc = 'return from a function'
    case ('shift');   desc = 'shift positional parameters'
    case ('eval');    desc = 'evaluate arguments as a command'
    case ('trap');    desc = 'run a command on a signal'
    case ('getopts'); desc = 'parse positional option arguments'
    case ('pushd');   desc = 'push a directory onto the stack'
    case ('popd');    desc = 'pop a directory from the stack'
    case ('dirs');    desc = 'show the directory stack'
    case ('complete'); desc = 'define completion behavior'
    case ('help');    desc = 'show help for builtins'
    end select
  end function

  ! Per-command help for an option flag, for the description column (#88).
  ! Mirrors the curated set in command_option_table. Universal --help/--version
  ! fall through to a shared tail; everything else is command-specific because a
  ! short flag means different things per command (-r is reverse in ls, recursive
  ! in cp). Blank for an unknown (command, option) pair.
  function option_summary(command, option) result(desc)
    character(len=*), intent(in) :: command, option
    character(len=MAX_MENU_DESC_LEN) :: desc
    desc = ' '
    select case (command)
    case ('ls')
      select case (option)
      case ('-a', '--all');            desc = 'include entries starting with .'
      case ('-A', '--almost-all');     desc = 'all except . and ..'
      case ('-l');                     desc = 'long listing format'
      case ('-h', '--human-readable'); desc = 'human-readable sizes (1K 234M)'
      case ('-R', '--recursive');      desc = 'list subdirectories recursively'
      case ('-r', '--reverse');        desc = 'reverse sort order'
      case ('-S');                     desc = 'sort by file size, largest first'
      case ('-t');                     desc = 'sort by modification time, newest first'
      case ('--sort');                 desc = 'sort by WORD: size, time, version...'
      case ('-d', '--directory');      desc = 'list directories themselves, not contents'
      case ('-i', '--inode');          desc = 'print each file''s inode number'
      case ('--color');                desc = 'colorize the output'
      case ('--group-directories-first'); desc = 'group directories before files'
      end select
    case ('grep')
      select case (option)
      case ('-E', '--extended-regexp'); desc = 'pattern is an extended regexp'
      case ('-F', '--fixed-strings');   desc = 'pattern is a literal string'
      case ('-i', '--ignore-case');     desc = 'case-insensitive matching'
      case ('-v', '--invert-match');    desc = 'select non-matching lines'
      case ('-w', '--word-regexp');     desc = 'match whole words only'
      case ('-c', '--count');           desc = 'print only a count of matches'
      case ('-l', '--files-with-matches'); desc = 'print only names of matching files'
      case ('-n', '--line-number');     desc = 'prefix each line with its number'
      case ('-r', '--recursive');       desc = 'search directories recursively'
      case ('-o', '--only-matching');   desc = 'show only the matched part'
      case ('--color');                 desc = 'highlight matches in color'
      case ('-A', '--after-context');   desc = 'print N lines after a match'
      case ('-B', '--before-context');  desc = 'print N lines before a match'
      case ('-C', '--context');         desc = 'print N lines around a match'
      end select
    case ('cp')
      select case (option)
      case ('-a', '--archive');     desc = 'preserve attributes, recurse, no deref'
      case ('-b', '--backup');      desc = 'back up each existing destination file'
      case ('-f', '--force');       desc = 'overwrite without prompting'
      case ('-i', '--interactive'); desc = 'prompt before overwrite'
      case ('-l', '--link');        desc = 'hard-link files instead of copying'
      case ('-n', '--no-clobber');  desc = 'never overwrite an existing file'
      case ('-r', '-R', '--recursive'); desc = 'copy directories recursively'
      case ('-s', '--symbolic-link'); desc = 'make symbolic links instead of copies'
      case ('-u', '--update');      desc = 'copy only when the source is newer'
      case ('-v', '--verbose');     desc = 'explain what is being done'
      case ('-p', '--preserve');    desc = 'preserve mode, ownership, timestamps'
      end select
    case ('mv')
      select case (option)
      case ('-b', '--backup');      desc = 'back up each existing destination file'
      case ('-f', '--force');       desc = 'overwrite without prompting'
      case ('-i', '--interactive'); desc = 'prompt before overwrite'
      case ('-n', '--no-clobber');  desc = 'never overwrite an existing file'
      case ('-u', '--update');      desc = 'move only when the source is newer'
      case ('-v', '--verbose');     desc = 'explain what is being done'
      end select
    case ('rm')
      select case (option)
      case ('-f', '--force');       desc = 'ignore nonexistent files, never prompt'
      case ('-i', '--interactive'); desc = 'prompt before every removal'
      case ('-r', '-R', '--recursive'); desc = 'remove directories and contents'
      case ('-d', '--dir');         desc = 'remove empty directories'
      case ('-v', '--verbose');     desc = 'explain what is being done'
      end select
    case ('mkdir')
      select case (option)
      case ('-m', '--mode');    desc = 'set permission mode (as in chmod)'
      case ('-p', '--parents'); desc = 'make parent directories as needed'
      case ('-v', '--verbose'); desc = 'print a message per created directory'
      end select
    case ('cat')
      select case (option)
      case ('-A', '--show-all');        desc = 'equivalent to -vET'
      case ('-b', '--number-nonblank'); desc = 'number nonempty output lines'
      case ('-E', '--show-ends');       desc = 'display $ at end of each line'
      case ('-n', '--number');          desc = 'number all output lines'
      case ('-s', '--squeeze-blank');   desc = 'collapse repeated blank lines'
      case ('-T', '--show-tabs');       desc = 'display TAB as ^I'
      case ('-v', '--show-nonprinting'); desc = 'show nonprinting characters'
      end select
    case ('sort')
      select case (option)
      case ('-b', '--ignore-leading-blanks'); desc = 'ignore leading blanks'
      case ('-f', '--ignore-case');     desc = 'fold lower case to upper case'
      case ('-n', '--numeric-sort');    desc = 'compare by numeric value'
      case ('-h', '--human-numeric-sort'); desc = 'compare human-readable numbers'
      case ('-r', '--reverse');         desc = 'reverse the comparison result'
      case ('-u', '--unique');          desc = 'output only the first of equal lines'
      case ('-k', '--key');             desc = 'sort via a key; KEYDEF gives location'
      case ('-t', '--field-separator'); desc = 'use SEP as the field separator'
      case ('-o', '--output');          desc = 'write result to FILE, not stdout'
      case ('-c', '--check');           desc = 'check whether input is sorted'
      end select
    case ('head', 'tail')
      select case (option)
      case ('-c', '--bytes');   desc = 'print the first/last N bytes'
      case ('-n', '--lines');   desc = 'print the first/last N lines'
      case ('-q', '--quiet');   desc = 'never print file-name headers'
      case ('-v', '--verbose'); desc = 'always print file-name headers'
      case ('-f', '--follow');  desc = 'output appended data as the file grows'
      end select
    case ('wc')
      select case (option)
      case ('-c', '--bytes');           desc = 'print the byte count'
      case ('-m', '--chars');           desc = 'print the character count'
      case ('-l', '--lines');           desc = 'print the newline count'
      case ('-w', '--words');           desc = 'print the word count'
      case ('-L', '--max-line-length'); desc = 'print the longest line length'
      end select
    case ('find')
      select case (option)
      case ('-name');     desc = 'file name matches a shell pattern'
      case ('-iname');    desc = 'like -name, case-insensitive'
      case ('-type');     desc = 'file is of TYPE (f, d, l, ...)'
      case ('-size');     desc = 'file uses N units of space'
      case ('-mtime');    desc = 'data last modified N*24 hours ago'
      case ('-newer');    desc = 'modified more recently than FILE'
      case ('-maxdepth'); desc = 'descend at most N directory levels'
      case ('-mindepth'); desc = 'apply tests at depth N or below'
      case ('-path');     desc = 'path matches a shell pattern'
      case ('-regex');    desc = 'path matches a regular expression'
      case ('-prune');    desc = 'do not descend into this directory'
      case ('-print');    desc = 'print the full file name, then newline'
      case ('-print0');   desc = 'print the file name, then a null byte'
      case ('-delete');   desc = 'delete matched files'
      case ('-exec');     desc = 'run a command on each matched file'
      case ('-empty');    desc = 'file is empty'
      case ('-perm');     desc = 'file permission bits match MODE'
      case ('-user');     desc = 'file is owned by USER'
      case ('-group');    desc = 'file belongs to GROUP'
      end select
    case ('ps')
      select case (option)
      case ('-e', '-A'); desc = 'select every process'
      case ('-f');       desc = 'full-format listing'
      case ('-l');       desc = 'long format'
      case ('-u');       desc = 'select by effective user'
      case ('-x');       desc = 'include processes without a tty'
      case ('-a');       desc = 'all processes with a tty except leaders'
      case ('-w');       desc = 'wide output'
      case ('-o');       desc = 'user-defined output format'
      end select
    case ('tar')
      select case (option)
      case ('-c', '--create');    desc = 'create a new archive'
      case ('-x', '--extract');   desc = 'extract files from an archive'
      case ('-t', '--list');      desc = 'list the contents of an archive'
      case ('-f', '--file');      desc = 'use the given archive file'
      case ('-v', '--verbose');   desc = 'list files as they are processed'
      case ('-z', '--gzip');      desc = 'filter the archive through gzip'
      case ('-j', '--bzip2');     desc = 'filter the archive through bzip2'
      case ('-J', '--xz');        desc = 'filter the archive through xz'
      case ('-C', '--directory'); desc = 'change to DIR before operating'
      end select
    case ('git')
      select case (option)
      case ('--bare');      desc = 'treat the repository as bare'
      case ('--git-dir');   desc = 'set the path to the repository'
      case ('--work-tree'); desc = 'set the path to the working tree'
      case ('--paginate');  desc = 'pipe output into a pager'
      case ('--no-pager');  desc = 'do not pipe output into a pager'
      case ('--exec-path');  desc = 'path to git core programs'
      case ('--html-path');  desc = 'path to git''s HTML documentation'
      case ('--man-path');   desc = 'manpath for git''s man pages'
      case ('--info-path');  desc = 'path to git''s info files'
      case ('-C');          desc = 'run as if git was started in PATH'
      case ('-c');          desc = 'pass a config parameter'
      end select
    end select

    ! Universal tail (consistent across commands).
    if (len_trim(desc) == 0) then
      select case (option)
      case ('--help');    desc = 'display help and exit'
      case ('--version'); desc = 'output version information and exit'
      end select
    end if
  end function

  ! One-line help for a git subcommand, for the description column (#88).
  ! Covers the set fortsh completes for `git <tab>`.
  function git_subcommand_summary(name) result(desc)
    character(len=*), intent(in) :: name
    character(len=MAX_MENU_DESC_LEN) :: desc
    desc = ' '
    select case (name)
    case ('add');        desc = 'add file contents to the index'
    case ('am');         desc = 'apply patches from a mailbox'
    case ('apply');      desc = 'apply a patch to files and/or the index'
    case ('archive');    desc = 'create an archive of files from a tree'
    case ('bisect');     desc = 'binary-search for the commit that broke'
    case ('blame');      desc = 'show what revision last changed each line'
    case ('branch');     desc = 'list, create, or delete branches'
    case ('checkout');   desc = 'switch branches or restore files'
    case ('cherry-pick'); desc = 'apply the changes of existing commits'
    case ('clean');      desc = 'remove untracked files from the tree'
    case ('clone');      desc = 'clone a repository into a new directory'
    case ('commit');     desc = 'record changes to the repository'
    case ('config');     desc = 'get and set repository or global options'
    case ('describe');   desc = 'name a commit from a nearby tag'
    case ('diff');       desc = 'show changes between commits, trees, etc.'
    case ('fetch');      desc = 'download objects and refs from a remote'
    case ('fsck');       desc = 'verify connectivity and validity of objects'
    case ('gc');         desc = 'clean up and optimize the repository'
    case ('grep');       desc = 'print lines matching a pattern'
    case ('init');       desc = 'create an empty repository'
    case ('log');        desc = 'show the commit logs'
    case ('merge');      desc = 'join two or more development histories'
    case ('mv');         desc = 'move or rename a file, dir, or symlink'
    case ('pull');       desc = 'fetch from and integrate with a remote'
    case ('push');       desc = 'update remote refs and their objects'
    case ('rebase');     desc = 'reapply commits on top of another base'
    case ('reflog');     desc = 'manage the reflog information'
    case ('remote');     desc = 'manage the set of tracked repositories'
    case ('reset');      desc = 'reset current HEAD to a given state'
    case ('restore');    desc = 'restore working-tree files'
    case ('revert');     desc = 'revert existing commits'
    case ('rm');         desc = 'remove files from the tree and the index'
    case ('show');       desc = 'show various types of objects'
    case ('stash');      desc = 'stash changes in a dirty working directory'
    case ('status');     desc = 'show the working-tree status'
    case ('switch');     desc = 'switch branches'
    case ('tag');        desc = 'create, list, or delete tags'
    case ('worktree');   desc = 'manage multiple working trees'
    end select
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

    ! Enter on the FIRST item, highlighted (AR-03 menu-sel: was item 2)
    if (input_state%menu_num_items >= 1) then
      input_state%menu_selection = 1
      call update_menu_selection(input_state, 1)
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
    integer :: name_col, desc_col, max_desc, dlen
    logical :: desc_present
    character(len=MAX_MENU_ITEM_LEN) :: current_item
    character(len=MAX_MENU_DESC_LEN) :: current_desc
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
    name_col = 0
    max_desc = 0
    desc_present = .false.
    do i = 1, input_state%menu_num_items
      name_col = max(name_col, len_trim(menu_item_get(input_state, i)))
      dlen = len_trim(menu_desc_get(input_state, i))
      if (dlen > 0) then
        desc_present = .true.
        max_desc = max(max_desc, dlen)
      end if
    end do

    ! AR-03c: with descriptions, render one item per row as `name<pad>desc`
    ! (fish-style); without, keep the column-major name-only grid (AR-03b).
    if (desc_present) then
      if (name_col > 40) name_col = 40
      desc_col = min(max_desc, 48)
      if (name_col + 3 + desc_col > term_cols) desc_col = max(term_cols - name_col - 3, 0)
      cols_per_item = name_col + 2 + desc_col
      items_per_row = 1
    else
      cols_per_item = name_col + 2
      items_per_row = max(1, term_cols / cols_per_item)
      desc_col = 0
    end if
    input_state%menu_has_descs = desc_present
    input_state%menu_name_col = name_col

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

    ! Draw visible rows, overwriting in place. Column-major (fish): the cell
    ! at (display row, col) holds item (col-1)*num_rows + row, so consecutive
    ! items fill down each column. For a fixed row, item_idx grows with col,
    ! so the first overflow ends the row.
    do row = input_state%menu_row_start, row_stop
      do col = 1, items_per_row
        item_idx = (col - 1) * input_state%menu_num_rows + row
        if (item_idx > input_state%menu_num_items) exit

        ! Sanitize control/escape bytes for DISPLAY only (insertion uses
        ! the real item value) so a malicious filename — or variable value in
        ! the description — can't inject ANSI.
        current_item = sanitize_for_display(menu_item_get(input_state, item_idx))
        item_len = len_trim(current_item)

        if (desc_present) then
          ! Single column: name padded to name_col, then a dim description.
          if (item_len > name_col) item_len = name_col
          if (item_idx == input_state%menu_selection) call rdraw_append(char(27) // '[7m')
          call rdraw_append(current_item(1:item_len))
          do j = item_len + 1, name_col
            call rdraw_append(' ')
          end do
          call rdraw_append('  ')
          current_desc = sanitize_for_display(menu_desc_get(input_state, item_idx))
          dlen = min(len_trim(current_desc), desc_col)
          if (dlen > 0) then
            if (item_idx /= input_state%menu_selection) call rdraw_append(char(27) // '[90m')
            call rdraw_append(current_desc(1:dlen))
            if (item_idx /= input_state%menu_selection) call rdraw_append(char(27) // '[0m')
          end if
          if (item_idx == input_state%menu_selection) call rdraw_append(char(27) // '[0m')
        else
          if (item_idx == input_state%menu_selection) then
            call rdraw_append(char(27) // '[7m')  ! Reverse video
          end if
          call rdraw_append(current_item(1:item_len))
          if (item_idx == input_state%menu_selection) then
            call rdraw_append(char(27) // '[0m')  ! Reset
          end if

          ! Pad to column width for alignment, but only when a real next-column
          ! cell exists in this same display row (column-major: that cell is
          ! col*num_rows + row).
          if (col < items_per_row .and. &
              (col * input_state%menu_num_rows + row) <= input_state%menu_num_items) then
            do j = item_len + 1, cols_per_item
              call rdraw_append(' ')
            end do
          end if
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
    integer :: num_rows, current_row

    if (.false.) print *, done  ! Silence unused warning (set by caller)

    if (.not. input_state%in_menu_select) return

    old_selection = input_state%menu_selection

    select case (key)
    case (KEY_UP, KEY_DOWN)
      ! Column-major grid (fish): consecutive items run DOWN a column, so
      ! Up/Down move within a column by +/-1, STOPPING at the column top/
      ! bottom (no wrap). At the edge, a repeat same-direction press jumps to
      ! the opposite end of the whole grid. (AR-03 NEW-2, AR-03b column-major)
      num_rows = input_state%menu_num_rows
      if (num_rows < 1) num_rows = 1
      current_row = mod(input_state%menu_selection - 1, num_rows) + 1

      if (key == KEY_UP) then
        if (current_row <= 1) then
          ! Top of the column. First press: stop and arm. Repeat: jump to last.
          if (menu_edge_armed == 1) then
            input_state%menu_selection = input_state%menu_num_items
            menu_edge_armed = 0
          else
            menu_edge_armed = 1
          end if
        else
          input_state%menu_selection = input_state%menu_selection - 1
          menu_edge_armed = 0
        end if
      else  ! KEY_DOWN
        ! "At the bottom" = no cell directly below in this column: either the
        ! column is full (current_row == num_rows) or the next index spills
        ! past the last item (a partial last column).
        if (current_row >= num_rows .or. &
            input_state%menu_selection + 1 > input_state%menu_num_items) then
          if (menu_edge_armed == 2) then
            input_state%menu_selection = 1
            menu_edge_armed = 0
          else
            menu_edge_armed = 2
          end if
        else
          input_state%menu_selection = input_state%menu_selection + 1
          menu_edge_armed = 0
        end if
      end if

    case (KEY_LEFT)
      ! Move one column left, same row. Wrap from the first column to the same
      ! row of the last column (back up one column if that row lies past the
      ! end of a partial last column).
      menu_edge_armed = 0
      num_rows = input_state%menu_num_rows
      if (num_rows < 1) num_rows = 1
      new_selection = input_state%menu_selection - num_rows
      if (new_selection < 1) then
        current_row = mod(input_state%menu_selection - 1, num_rows) + 1
        new_selection = current_row + ((input_state%menu_num_items - 1) / num_rows) * num_rows
        if (new_selection > input_state%menu_num_items) new_selection = new_selection - num_rows
        if (new_selection < 1) new_selection = input_state%menu_selection
      end if
      input_state%menu_selection = new_selection

    case (KEY_RIGHT)
      ! Move one column right, same row. Wrap from the last column to the same
      ! row of the first column (which is always full).
      menu_edge_armed = 0
      num_rows = input_state%menu_num_rows
      if (num_rows < 1) num_rows = 1
      new_selection = input_state%menu_selection + num_rows
      if (new_selection > input_state%menu_num_items) then
        new_selection = mod(input_state%menu_selection - 1, num_rows) + 1
      end if
      input_state%menu_selection = new_selection

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
    ! Column-major: an item's display row is its position within its column.
    sel_row = mod(input_state%menu_selection - 1, max(input_state%menu_num_rows, 1)) + 1
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

    if (scrolled .or. input_state%menu_has_descs) then
      ! Window moved or grew: reposition to the menu top and repaint the
      ! whole window in one buffered frame (overwrite in place, no
      ! blank-then-redraw, so no flicker). AR-03c: a description menu also
      ! repaints fully — menu_redraw_cell only knows the name-only cell, so
      ! the in-place two-cell highlight swap can't touch the desc column.
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
    if (input_state%menu_num_rows <= 0) return
    ! Column-major: row within the column, col is the column index.
    row = mod(item_idx - 1, input_state%menu_num_rows) + 1
    if (row < input_state%menu_row_start .or. &
        row > input_state%menu_row_start + input_state%menu_visible_rows - 1) return
    col = (item_idx - 1) / input_state%menu_num_rows + 1
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
    use system_interface, only: execute_argv_and_capture
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

    ! Run ps with an argv vector and no shell, so $USER can never inject
    ! commands (SEC-1). Each element below is a single argv entry.
#if defined(__APPLE__) || defined(__FreeBSD__)
    if (len_trim(username) > 0) then
      ps_output = execute_argv_and_capture( &
        [character(len=64) :: 'ps', '-u', trim(username), '-o', 'pid=', '-o', 'comm='])
    else
      ps_output = execute_argv_and_capture( &
        [character(len=64) :: 'ps', '-ax', '-o', 'pid=', '-o', 'comm='])
    end if
#else
    if (len_trim(username) > 0) then
      ps_output = execute_argv_and_capture( &
        [character(len=64) :: 'ps', '-u', trim(username), '-o', 'pid,comm', '--no-headers'])
    else
      ps_output = execute_argv_and_capture( &
        [character(len=64) :: 'ps', '-eo', 'pid,comm', '--no-headers'])
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
      ! Peek for a following byte with a short timeout. A real arrow key sends
      ! ESC[ as one burst, so the next byte is already waiting; a bare ESC has
      ! nothing following. read_single_char() blocks (no timeout), so without
      ! this poll a bare ESC would hang until the next keystroke and then
      ! mis-read it — which is why ESC never dismissed the menu. (AR-03)
      if (.not. input_ready_within(MENU_ESC_TIMEOUT_MS)) then
        call handle_menu_navigation(input_state, KEY_ESC, done)
        return
      end if
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
      ! Short-timeout peek (see above): bare ESC dismisses the shown table
      ! instead of blocking on read_single_char until the next keystroke.
      if (.not. input_ready_within(MENU_ESC_TIMEOUT_MS)) then
        call exit_menu_select_mode(input_state)
        return
      end if
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

    ! Vi visual mode (AR-05b): a bare ESC cancels the selection; arrow keys act
    ! as visual motions. Peek (short timeout) to tell a lone ESC from a sequence
    ! so a bare ESC neither blocks nor swallows the following key (same pattern
    ! as the menu ESC handling above).
    if (input_state%editing_mode == EDITING_MODE_VI .and. &
        input_state%vi_mode == VI_MODE_VISUAL) then
      if (.not. input_ready_within(MENU_ESC_TIMEOUT_MS)) then
        call handle_vi_visual_mode(input_state, KEY_ESC)
        return
      end if
      success = read_single_char(ch1)
      if (.not. success) then
        call handle_vi_visual_mode(input_state, KEY_ESC)
        return
      end if
      if (ch1 == '[') then
        success = read_single_char(ch2)
        if (.not. success) return
        select case (ch2)
        case ('C')  ! Right arrow -> extend right
          call handle_vi_visual_mode(input_state, ichar('l'))
        case ('D')  ! Left arrow -> extend left
          call handle_vi_visual_mode(input_state, ichar('h'))
        case default
          ! Up/Down or other: no horizontal motion on a single line; consume.
          continue
        end select
      end if
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
        if (input_state%in_search) then
          ! NICE-ISEARCH (AR-08): step to the next OLDER match instead of
          ! cancelling — fish/bash navigate matches with the arrows.
          input_state%search_forward = .false.
          call search_next_match(input_state)
          call update_search_display(input_state, prompt)
        else if (.not. move_cursor_logical_line(input_state, .true.)) then
          ! AR-10: in a multi-line buffer Up moves a line; at the top edge (or a
          ! single-line buffer) it browses history.
          call handle_history_up(input_state)
        end if
      case('B')  ! Down arrow
        if (input_state%in_search) then
          ! NICE-ISEARCH (AR-08): step to the next NEWER match.
          input_state%search_forward = .true.
          call search_next_match(input_state)
          call update_search_display(input_state, prompt)
        else if (.not. move_cursor_logical_line(input_state, .false.)) then
          ! AR-10: Down moves a line; at the bottom edge it browses history.
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
        ! Alt+f - forward-word: move forward a word, or accept one suggestion
        ! word at end-of-buffer (AS-6, fish nextd-or-forward-word)
        call forward_word_or_accept(input_state)
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
      case('y')
        ! Alt+y — yank-pop (DIV-2): replace the just-yanked text with the
        ! next-older kill-ring entry. No-op unless the previous key was a yank.
        call handle_yank_pop(input_state)
      case('/')
        ! Alt+/ — redo (DIV-1), the counterpart to Ctrl-/ undo.
        call handle_redo(input_state)
      case('t')
        ! Alt+t — transpose-words (DIV-4): swap the two words around the cursor.
        call handle_transpose_words(input_state)
      case(char(127))
        ! Alt+Backspace - backward-kill-word (punctuation-aware small word;
        ! distinct from Ctrl+W = backward-kill-path-component, DIV-3).
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

                        ! Strip trailing newline(s): a copied "cmd\n" pastes as
                        ! a ready-to-run "cmd", not a command plus a blank line
                        ! (and still no auto-execute). (AR-10)
                        do while (paste_len > 0 .and. &
                                  iachar(paste_buffer(paste_len:paste_len)) == 10)
                          paste_len = paste_len - 1
                        end do

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
              !   newline (10)       -> keep as a newline: a multi-line paste
              !                         becomes a real multi-line buffer (AR-10).
              !                         It is buffer content, not the Enter key,
              !                         so it never auto-executes.
              !   CR (13)            -> drop (so CR+LF collapses to one newline)
              !   DEL/NUL/other      -> drop (terminal-escape / control guard)
              !   printable + UTF-8  -> keep
              ! ESC (27) never reaches here — handled by the branch above.
              ic = iachar(ch_paste)
              if (ic == 10 .or. ic == 9 .or. (ic >= 32 .and. ic /= 127)) then
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
          ! Ctrl+Right arrow - forward-word: move forward a word, or accept
          ! one suggestion word at end-of-buffer (AS-6, fish forward-word)
          call forward_word_or_accept(input_state)
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
          ! Alt+Right - forward-word: move forward a word, or accept one
          ! suggestion word at end-of-buffer (AS-6, fish nextd-or-forward-word)
          call forward_word_or_accept(input_state)
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

    ! AR-11 PAIRS: with a live suggestion standing in for the pending closers,
    ! the cursor is visually at end-of-line even though bytes follow it. Accept
    ! wins over motion here, or Right would step into a closer the user cannot
    ! see. Guarded like the end-of-buffer accept below (no shift-extension, and
    ! not on the press that clears a paste highlight).
    if (autopair_tail_only(input_state) .and. input_state%suggestion_length > 0 &
        .and. .not. module_extending_selection &
        .and. .not. module_paste_hl_cleared_this_key) then
      call accept_autosuggestion(input_state)
      return
    end if

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
    else if ((input_state%cursor_pos == input_state%length .or. &
              autopair_tail_only(input_state)) &
             .and. input_state%suggestion_length > 0 &
             .and. .not. module_extending_selection &
             .and. .not. module_paste_hl_cleared_this_key) then
      ! At end of line with suggestion - accept it (but not during shift-extension —
      ! Shift+Right at the end of the line should not eat an autosuggestion; and
      ! not on the press that clears a paste highlight — AR-01-fu).
      call accept_autosuggestion(input_state)
    end if

    ! Shift-phase: if this call is extending a selection, update it now.
    if (module_extending_selection) then
      call update_selection_on_shift_motion(input_state, old_cursor_pos)
    end if
  end subroutine

  ! AR-10: move the cursor one logical line up/down within a multi-line buffer,
  ! keeping the target column (clamped to the destination line's length). Returns
  ! .false. — so the caller falls back to history navigation — for a single-line
  ! buffer or when already at the top (up) / bottom (down) edge, matching fish.
  ! Column math is byte-based (fine for ASCII pastes; slightly off for wide UTF-8).
  function move_cursor_logical_line(input_state, go_up) result(moved)
    type(input_state_t), intent(inout) :: input_state
    logical, intent(in) :: go_up
    logical :: moved
    character(len=MAX_LINE_LEN) :: buf
    integer :: ln, cur, i, cur_ls, col, prev_ls, nl_end, plen, target

    moved = .false.
    ln = input_state%length
    if (ln <= 0) return
    call state_buffer_get(input_state, buf)
    if (index(buf(1:ln), char(10)) == 0) return   ! single line -> history

    cur = input_state%cursor_pos
    if (cur < 0) cur = 0
    if (cur > ln) cur = ln

    ! Column 0 of the current line = position just after the preceding newline.
    cur_ls = 0
    do i = cur, 1, -1
      if (buf(i:i) == char(10)) then
        cur_ls = i
        exit
      end if
    end do
    col = cur - cur_ls

    if (go_up) then
      if (cur_ls == 0) return                      ! first line -> history
      prev_ls = 0
      do i = cur_ls - 1, 1, -1
        if (buf(i:i) == char(10)) then
          prev_ls = i
          exit
        end if
      end do
      plen = (cur_ls - 1) - prev_ls                ! previous line length (bytes)
      target = prev_ls + min(col, plen)
    else
      nl_end = 0                                   ! newline ending the current line
      do i = cur + 1, ln
        if (buf(i:i) == char(10)) then
          nl_end = i
          exit
        end if
      end do
      if (nl_end == 0) return                      ! last line -> history
      plen = 0
      do i = nl_end + 1, ln
        if (buf(i:i) == char(10)) exit
        plen = plen + 1
      end do
      target = nl_end + min(col, plen)
    end if

    if (target < 0) target = 0
    if (target > ln) target = ln
    input_state%cursor_pos = target
    input_state%dirty = .true.
    moved = .true.
  end function move_cursor_logical_line

  


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
    else if (input_state%cursor_pos == input_state%length .and. &
             input_state%suggestion_length > 0 .and. &
             .not. module_extending_selection .and. &
             .not. module_paste_hl_cleared_this_key) then
      ! Already at end of line with an autosuggestion: accept the whole thing,
      ! mirroring Right (AR-04 AS-1: End/Ctrl-E were no-ops here). Not during
      ! shift-extension, and not on the press that clears a paste highlight
      ! (AR-01-fu).
      call accept_autosuggestion(input_state)
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
      call state_kill_buffer_set(input_state, temp_buf(:input_state%cursor_pos), forward=.false.)
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
    integer :: word_start, i, cls
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

    ! Find start of the small-word to kill (DIV-3: punctuation-aware, fish
    ! backward-kill-word). Skip trailing whitespace, then step back over one
    ! class-run so "user/repo" loses just "repo", then "/", then "user".
    word_start = input_state%cursor_pos

    do while (word_start > 0 .and. &
              char_class(state_buffer_get_char(input_state, word_start)) == 0)
      word_start = word_start - 1
    end do

    if (word_start > 0) then
      cls = char_class(state_buffer_get_char(input_state, word_start))
      do while (word_start > 0 .and. &
                char_class(state_buffer_get_char(input_state, word_start)) == cls)
        word_start = word_start - 1
      end do
    end if

    ! word_start is now just before the killed run, or 0 if at beginning
    if (word_start < input_state%cursor_pos) then
      ! Save killed text
      call state_buffer_get(input_state, temp_buf)
      call state_kill_buffer_set(input_state, temp_buf(word_start+1:input_state%cursor_pos), forward=.false.)
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

  ! Ctrl+W — fish backward-kill-path-component: kill back to the previous '/'
  ! or whitespace, removing one path component (and a trailing slash). On
  ! "git@github.com:user/repo" this leaves "git@github.com:user/" (DIV-3).
  subroutine handle_kill_path_component(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_start, i
    character :: c
    character(len=MAX_LINE_LEN) :: temp_buf

    ! Selection cut, mirroring handle_kill_word.
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

    word_start = input_state%cursor_pos

    ! Skip trailing whitespace.
    do while (word_start > 0 .and. &
              char_class(state_buffer_get_char(input_state, word_start)) == 0)
      word_start = word_start - 1
    end do

    ! Skip one trailing slash so "foo/bar/" kills "bar/".
    if (word_start > 0) then
      if (state_buffer_get_char(input_state, word_start) == '/') word_start = word_start - 1
    end if

    ! Kill back to the previous '/' or whitespace.
    do while (word_start > 0)
      c = state_buffer_get_char(input_state, word_start)
      if (c == '/' .or. char_class(c) == 0) exit
      word_start = word_start - 1
    end do

    if (word_start < input_state%cursor_pos) then
      call state_buffer_get(input_state, temp_buf)
      call state_kill_buffer_set(input_state, temp_buf(word_start+1:input_state%cursor_pos), forward=.false.)
      input_state%kill_length = input_state%cursor_pos - word_start

      do i = word_start + 1, input_state%length - input_state%cursor_pos + word_start
        if (input_state%cursor_pos + i - word_start <= input_state%length) then
          call state_buffer_set_char(input_state, i, &
            state_buffer_get_char(input_state, input_state%cursor_pos + i - word_start))
        else
          call state_buffer_set_char(input_state, i, ' ')
        end if
      end do

      input_state%length = input_state%length - (input_state%cursor_pos - word_start)
      input_state%cursor_pos = word_start
      input_state%dirty = .true.
      call update_autosuggestion(input_state)
    else
      input_state%kill_length = 0
    end if
  end subroutine

  ! Alt+d — kill word forward (delete from cursor to end of next word)
  subroutine handle_kill_word_forward(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: word_end, i, chars_to_delete, cls
    character(len=MAX_LINE_LEN) :: temp_buf

    if (input_state%cursor_pos >= input_state%length) return

    word_end = input_state%cursor_pos + 1

    ! fish kill-word: skip whitespace, then consume ONE class-run (DIV-3).
    do while (word_end <= input_state%length .and. &
              char_class(state_buffer_get_char(input_state, word_end)) == 0)
      word_end = word_end + 1
    end do

    if (word_end <= input_state%length) then
      cls = char_class(state_buffer_get_char(input_state, word_end))
      do while (word_end <= input_state%length .and. &
                char_class(state_buffer_get_char(input_state, word_end)) == cls)
        word_end = word_end + 1
      end do
    end if

    chars_to_delete = word_end - input_state%cursor_pos - 1
    if (chars_to_delete <= 0) return

    ! Feed the kill ring (DIV-2 / PROBE-3: Alt-d previously discarded the text,
    ! so Ctrl-Y after Alt-d yanked a stale kill). Forward kill -> append.
    call state_buffer_get(input_state, temp_buf)
    call state_kill_buffer_set(input_state, &
      temp_buf(input_state%cursor_pos+1:input_state%cursor_pos+chars_to_delete), forward=.true.)

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


  ! Alt-y — yank-pop (DIV-2): only valid immediately after a yank/yank-pop.
  ! Removes the just-yanked span and replaces it with the next-older ring slot,
  ! cycling through the ring on repeated presses.
  subroutine handle_yank_pop(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, insert_len, src

    if (.not. yank_op_prev_key) return       ! must follow a yank
    if (kill_ring_count <= 1) return          ! nothing else to rotate to
    if (last_yank_len <= 0) return

    ! Delete the previously yanked span [last_yank_start+1 .. +last_yank_len].
    do i = last_yank_start + 1, input_state%length - last_yank_len
      call state_buffer_set_char(input_state, i, &
        state_buffer_get_char(input_state, i + last_yank_len))
    end do
    do i = input_state%length - last_yank_len + 1, input_state%length
      call state_buffer_set_char(input_state, i, ' ')
    end do
    input_state%length = input_state%length - last_yank_len
    input_state%cursor_pos = last_yank_start

    ! Rotate to the next-older slot (wrap around).
    kill_yank_index = kill_yank_index + 1
    if (kill_yank_index > kill_ring_count) kill_yank_index = 1
    src = kill_yank_index

    insert_len = min(kill_ring_len(src), MAX_LINE_LEN - input_state%length)
    if (insert_len < 0) insert_len = 0

    do i = input_state%length, input_state%cursor_pos + 1, -1
      if (i + insert_len <= MAX_LINE_LEN) then
        call state_buffer_set_char(input_state, i + insert_len, state_buffer_get_char(input_state, i))
      end if
    end do
    do i = 1, insert_len
      call state_buffer_set_char(input_state, input_state%cursor_pos + i, kill_ring(src)(i:i))
    end do

    input_state%length = input_state%length + insert_len
    last_yank_len = insert_len
    input_state%cursor_pos = input_state%cursor_pos + insert_len
    input_state%dirty = .true.
    yank_op_this_key = .true.
  end subroutine

  ! ===========================================================================
  ! Undo / redo (AR-05 DIV-1)
  ! ===========================================================================

  ! Reset the undo/redo history (per readline() call — each line is independent).
  subroutine undo_reset()
    undo_n = 0
    redo_n = 0
    undo_op_was_insert = .false.
    undo_prev_was_insert = .false.
    undo_navigate_this_key = .false.
    undo_pre_len = 0
    undo_pre_cursor = 0
  end subroutine undo_reset

  ! Capture the live buffer as this keystroke's pre-edit snapshot.
  subroutine undo_capture_pre(state)
    type(input_state_t), intent(in) :: state
    integer :: j
    undo_pre_buf = ''
    do j = 1, state%length
      undo_pre_buf(j:j) = state_buffer_get_char(state, j)
    end do
    undo_pre_len = state%length
    undo_pre_cursor = state%cursor_pos
  end subroutine undo_capture_pre

  subroutine undo_stack_push(buf, blen, bcur)
    character(len=*), intent(in) :: buf
    integer, intent(in) :: blen, bcur
    integer :: i
    if (undo_n >= UNDO_STACK_MAX) then
      do i = 1, UNDO_STACK_MAX - 1   ! drop oldest
        undo_stack(i) = undo_stack(i+1)
        undo_stack_len(i) = undo_stack_len(i+1)
        undo_stack_cur(i) = undo_stack_cur(i+1)
      end do
      undo_n = UNDO_STACK_MAX - 1
    end if
    undo_n = undo_n + 1
    undo_stack(undo_n) = buf
    undo_stack_len(undo_n) = blen
    undo_stack_cur(undo_n) = bcur
  end subroutine undo_stack_push

  subroutine redo_stack_push(buf, blen, bcur)
    character(len=*), intent(in) :: buf
    integer, intent(in) :: blen, bcur
    integer :: i
    if (redo_n >= UNDO_STACK_MAX) then
      do i = 1, UNDO_STACK_MAX - 1
        redo_stack(i) = redo_stack(i+1)
        redo_stack_len(i) = redo_stack_len(i+1)
        redo_stack_cur(i) = redo_stack_cur(i+1)
      end do
      redo_n = UNDO_STACK_MAX - 1
    end if
    redo_n = redo_n + 1
    redo_stack(redo_n) = buf
    redo_stack_len(redo_n) = blen
    redo_stack_cur(redo_n) = bcur
  end subroutine redo_stack_push

  ! After dispatch: if the buffer changed and this wasn't a coalesced insert
  ! continuation, push the pre-edit snapshot. A new edit clears the redo branch.
  subroutine undo_commit_if_changed(state)
    type(input_state_t), intent(in) :: state
    logical :: changed
    integer :: j
    if (undo_navigate_this_key) return    ! undo/redo itself is not a new edit

    changed = (state%length /= undo_pre_len)
    if (.not. changed) then
      do j = 1, state%length
        if (state_buffer_get_char(state, j) /= undo_pre_buf(j:j)) then
          changed = .true.
          exit
        end if
      end do
    end if
    if (.not. changed) return

    ! Coalesce a run of single-char inserts into one undo group.
    if (undo_op_was_insert .and. undo_prev_was_insert .and. undo_n > 0) return

    call undo_stack_push(undo_pre_buf, undo_pre_len, undo_pre_cursor)
    redo_n = 0
  end subroutine undo_commit_if_changed

  ! Restore a snapshot into the live buffer.
  subroutine state_restore_snapshot(state, buf, blen, bcur)
    type(input_state_t), intent(inout) :: state
    character(len=*), intent(in) :: buf
    integer, intent(in) :: blen, bcur
    integer :: j
    do j = 1, blen
      call state_buffer_set_char(state, j, buf(j:j))
    end do
    state%length = blen
    if (bcur > blen) then
      state%cursor_pos = blen
    else if (bcur < 0) then
      state%cursor_pos = 0
    else
      state%cursor_pos = bcur
    end if
    state%suggestion = ''
    state%suggestion_length = 0
    if (state%selection_active) call collapse_selection(state)
    state%dirty = .true.
    ! Buffer can shrink/diverge sharply; force a clean full repaint.
    prev_diff_valid = .false.
    prev_render_valid = .false.
  end subroutine state_restore_snapshot

  ! Ctrl-/ (or Ctrl-_): undo the last edit group.
  subroutine handle_undo(state)
    type(input_state_t), intent(inout) :: state
    character(len=MAX_LINE_LEN) :: cur
    integer :: j
    if (undo_n == 0) return
    ! Push the current state onto the redo stack so redo can return to it.
    cur = ''
    do j = 1, state%length
      cur(j:j) = state_buffer_get_char(state, j)
    end do
    call redo_stack_push(cur, state%length, state%cursor_pos)
    ! Restore the most recent pre-edit snapshot.
    call state_restore_snapshot(state, undo_stack(undo_n), undo_stack_len(undo_n), &
                                undo_stack_cur(undo_n))
    undo_n = undo_n - 1
    undo_navigate_this_key = .true.
    call update_autosuggestion(state)
  end subroutine handle_undo

  ! Alt-/ : redo the last undone edit.
  subroutine handle_redo(state)
    type(input_state_t), intent(inout) :: state
    character(len=MAX_LINE_LEN) :: cur
    integer :: j
    if (redo_n == 0) return
    cur = ''
    do j = 1, state%length
      cur(j:j) = state_buffer_get_char(state, j)
    end do
    call undo_stack_push(cur, state%length, state%cursor_pos)
    call state_restore_snapshot(state, redo_stack(redo_n), redo_stack_len(redo_n), &
                                redo_stack_cur(redo_n))
    redo_n = redo_n - 1
    undo_navigate_this_key = .true.
    call update_autosuggestion(state)
  end subroutine handle_redo

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

  ! Alt-t — transpose-words (DIV-4): swap the word at/before the cursor with the
  ! preceding word, leaving the cursor after the relocated word (fish/emacs).
  ! Word boundaries use the DIV-3 small-word classifier.
  subroutine handle_transpose_words(input_state)
    type(input_state_t), intent(inout) :: input_state
    character(len=MAX_LINE_LEN) :: buf, out
    integer :: c, n, w1s, w1e, w2s, w2e, i

    n = input_state%length
    c = input_state%cursor_pos
    if (n < 3 .or. c == 0) return

    call state_buffer_get(input_state, buf)

    ! word2 = the word containing or just before the cursor.
    w2e = c
    do while (w2e > 0 .and. char_class(buf(w2e:w2e)) /= 1)
      w2e = w2e - 1
    end do
    if (w2e == 0) return
    ! Extend through the rest of the word if the cursor sat inside it.
    do while (w2e < n .and. char_class(buf(w2e+1:w2e+1)) == 1)
      w2e = w2e + 1
    end do
    w2s = w2e
    do while (w2s > 1 .and. char_class(buf(w2s-1:w2s-1)) == 1)
      w2s = w2s - 1
    end do

    ! word1 = the word immediately before word2 (across the separator).
    w1e = w2s - 1
    do while (w1e > 0 .and. char_class(buf(w1e:w1e)) /= 1)
      w1e = w1e - 1
    end do
    if (w1e == 0) return    ! only one word — nothing to transpose
    w1s = w1e
    do while (w1s > 1 .and. char_class(buf(w1s-1:w1s-1)) == 1)
      w1s = w1s - 1
    end do

    ! Rebuild: prefix + word2 + separator + word1 + suffix (length unchanged).
    out = buf(1:w1s-1) // buf(w2s:w2e) // buf(w1e+1:w2s-1) // buf(w1s:w1e) // buf(w2e+1:n)
    do i = 1, n
      call state_buffer_set_char(input_state, i, out(i:i))
    end do
    input_state%length = n
    input_state%cursor_pos = w2e   ! end of the relocated word1
    input_state%dirty = .true.
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
    ! Convert embedded newlines to CR+LF (AR-10) so a multi-line paste doesn't
    ! staircase in test mode.
    if (test_mode_enabled) then
      block
        integer :: bi
        do bi = 1, insert_len
          if (bytes(bi:bi) == char(10)) then
            write(output_unit, '(a)', advance='no') char(13) // char(10)
          else
            write(output_unit, '(a)', advance='no') bytes(bi:bi)
          end if
        end do
      end block
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







  ! ============================================================================
  ! Any running or stopped jobs? (AR-08 NICE-CTRLD job warning.) JOB_RUNNING /
  ! JOB_STOPPED come from shell_types, so no dependency on the job module.
  logical function has_active_jobs(shell)
    type(shell_state_t), intent(in) :: shell
    integer :: i
    has_active_jobs = .false.
    do i = 1, size(shell%jobs)
      if (shell%jobs(i)%job_id /= 0 .and. &
          (shell%jobs(i)%state == JOB_RUNNING .or. &
           shell%jobs(i)%state == JOB_STOPPED)) then
        has_active_jobs = .true.
        return
      end if
    end do
  end function has_active_jobs

  ! Abbreviation Expansion (Fish-style)
  ! ============================================================================


  ! ============================================================================
  ! Autosuggestion Support (Fish-style)
  ! ============================================================================




  ! AR-04b: rewrite the last suggestion_replace_len chars of the buffer to the
  ! candidate's real case (idempotent) so an icase suggestion accepts to a valid
  ! path. No-op for exact-case / history suggestions (replace_len == 0).
  subroutine apply_suggestion_recase(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: j, base, anchor
    if (input_state%suggestion_replace_len <= 0) return
    ! AR-11 PAIRS: the typed token ends at the CURSOR when pending closers are
    ! parked to its right, not at end-of-buffer — recasing off the length would
    ! rewrite the closers themselves.
    anchor = input_state%length
    if (autopair_pending_tail(input_state) > 0) anchor = input_state%cursor_pos
    if (input_state%suggestion_replace_len > anchor) return
    base = anchor - input_state%suggestion_replace_len
    do j = 1, input_state%suggestion_replace_len
      call state_buffer_set_char(input_state, base + j, &
        input_state%suggestion_replace_text(j:j))
    end do
  end subroutine

  ! Accept the current autosuggestion
  subroutine accept_autosuggestion(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: j, new_length, ap_tail

    if (input_state%suggestion_length == 0) return

    ! Buffer is about to be extended — any lingering selection is stale (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

    call apply_suggestion_recase(input_state)

    ! AR-11 PAIRS: the renderer hid the pending closers behind this suggestion,
    ! and the suggestion carries its own closing quote. Drop them before
    ! appending, or accepting leaves `echo "quo"ted hello there"`.
    ap_tail = autopair_pending_tail(input_state)
    if (ap_tail > 0) then
      do j = 1, ap_tail
        call state_buffer_set_char(input_state, input_state%length - ap_tail + j, ' ')
      end do
      input_state%length = input_state%length - ap_tail
      input_state%cursor_pos = input_state%length
      call autopair_reset()
    end if

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
    input_state%suggestion_replace_len = 0
    input_state%dirty = .true.
  end subroutine

  ! Accept one word from the autosuggestion (for partial acceptance)
  subroutine accept_autosuggestion_word(input_state)
    type(input_state_t), intent(inout) :: input_state
    integer :: i, word_end

    if (input_state%suggestion_length == 0) return

    ! Buffer is about to be extended — any lingering selection is stale (#27).
    if (input_state%selection_active) call collapse_selection(input_state)

    ! AR-04b: correct the typed token's case before extending it (the prefix is
    ! already typed, so recasing is right regardless of how much suffix we take).
    call apply_suggestion_recase(input_state)

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

    ! AR-11 PAIRS: a PARTIAL accept stays inside the pair — splice the word in
    ! at the cursor and let the pending closers slide right, so the closing
    ! quote is still waiting when the rest of the argument is typed. (A full
    ! accept, above, consumes them instead: the whole suggestion ends the
    ! argument and brings its own closer.)
    if (autopair_pending_tail(input_state) > 0) then
      if (input_state%length + word_end > MAX_LINE_LEN - 1) return
      do i = input_state%length, input_state%cursor_pos + 1, -1
        call state_buffer_set_char(input_state, i + word_end, &
                                   state_buffer_get_char(input_state, i))
      end do
      do i = 1, word_end
        call state_buffer_set_char(input_state, input_state%cursor_pos + i, &
                                   input_state%suggestion(i:i))
      end do
      input_state%length = input_state%length + word_end
      call autopair_note_insert_n(input_state%cursor_pos + 1, word_end)
      input_state%cursor_pos = input_state%cursor_pos + word_end
      input_state%dirty = .true.
      call update_autosuggestion(input_state)
      return
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

  ! fish forward-word semantics (AS-6): move forward one word; or, when the
  ! cursor is at end-of-buffer with a live autosuggestion, accept one word of
  ! the suggestion. Bound to Alt-f, Alt-Right, and Ctrl-Right.
  subroutine forward_word_or_accept(input_state)
    type(input_state_t), intent(inout) :: input_state

    if ((input_state%cursor_pos == input_state%length .or. &
         autopair_tail_only(input_state)) .and. &
        input_state%suggestion_length > 0) then
      call accept_autosuggestion_word(input_state)
    else
      call move_to_next_word(input_state)
    end if
  end subroutine

  ! ===========================================================================
  ! Cursor Position Helpers for Multi-Line Support
  ! ===========================================================================


  ! Calculate cursor row and column given prompt and cursor position
  ! Returns (row, col) where row 0 = first line, col 0 = first column
  ! Cursor terminal row/col (0-based, relative to the prompt origin), computed
  ! by modeling the actual rendering: walk the prompt (skip ANSI SGR, strip the
  ! ESC[nG cursor-column escape and the RPROMPT text after it, treat \n as a new
  ! row, wrap at term_cols, count DISPLAY width), then the space after the
  ! prompt, then the buffer up to cursor_pos. This is the same model as
  ! content_byte_to_row_col (which drives the redraw's diff positioning), so a
  ! prompt that wraps — or has a wide/multibyte glyph like a checkmark — no
  ! longer makes the two disagree (the bug behind the resize "staircase").
  subroutine cursor_get_row_col(prompt, cursor_pos, term_cols, cursor_row, cursor_col)
    character(len=*), intent(in) :: prompt
    integer, intent(in) :: cursor_pos, term_cols
    integer, intent(out) :: cursor_row, cursor_col
    integer :: i, plen, byte_val, w, k
    character :: ch

    cursor_row = 0
    cursor_col = 0
    if (term_cols <= 0) return

    ! --- walk the prompt ---
    plen = len_trim(prompt)
    i = 1
    do while (i <= plen)
      ch = prompt(i:i)
      if (ch == char(27)) then
        if (i + 1 <= plen .and. prompt(i+1:i+1) == '[') then
          ! CSI: scan to the final byte (64..126)
          k = i + 2
          do while (k <= plen)
            byte_val = iachar(prompt(k:k))
            if (byte_val >= 64 .and. byte_val <= 126) exit
            k = k + 1
          end do
          if (k <= plen .and. prompt(k:k) == 'G') then
            ! ESC[nG is RPROMPT placement; skip it AND the RPROMPT text that
            ! follows, up to the next newline (the redraw strips the same).
            i = k + 1
            do while (i <= plen .and. prompt(i:i) /= char(10))
              i = i + 1
            end do
          else
            i = k + 1
          end if
        else
          ! ESC 7 / ESC 8 (save/restore) or other 2-byte escape: skip both.
          i = i + 2
        end if
        cycle
      else if (ch == char(10)) then
        cursor_row = cursor_row + 1
        cursor_col = 0
        i = i + 1
        cycle
      else if (ch == char(13)) then
        cursor_col = 0
        i = i + 1
        cycle
      else if (ch == char(0)) then
        i = i + 1
        cycle
      end if
      ! visible prompt char (display width, skip UTF-8 continuation bytes)
      byte_val = iand(iachar(ch), 255)
      if (byte_val < 128) then
        w = 1; i = i + 1
      else if (iand(byte_val, 224) == 192) then
        w = utf8_char_width(ch); i = i + 2
      else if (iand(byte_val, 240) == 224) then
        w = 2; i = i + 3
      else if (iand(byte_val, 248) == 240) then
        w = 2; i = i + 4
      else
        w = 0; i = i + 1
      end if
      cursor_col = cursor_col + w
      if (cursor_col >= term_cols) then
        cursor_row = cursor_row + 1
        cursor_col = 0
      end if
    end do

    ! --- the space after the prompt ---
    cursor_col = cursor_col + 1
    if (cursor_col >= term_cols) then
      cursor_row = cursor_row + 1
      cursor_col = 0
    end if

    ! --- the buffer, up to cursor_pos (display width per char) ---
    k = 1
    do while (k <= cursor_pos)
      ch = state_buffer_get_char(module_input_state, k)
      ! Embedded newline (AR-10 multi-line buffer): the redraw emits CR+LF, so
      ! the next logical line begins at column 0 on the next row.
      if (ch == char(10)) then
        cursor_row = cursor_row + 1
        cursor_col = 0
        k = k + 1
        cycle
      end if
      byte_val = iand(iachar(ch), 255)
      if (byte_val < 128) then
        w = 1; k = k + 1
      else if (iand(byte_val, 224) == 192) then
        w = utf8_char_width(ch); k = k + 2
      else if (iand(byte_val, 240) == 224) then
        w = 2; k = k + 3
      else if (iand(byte_val, 248) == 240) then
        w = 2; k = k + 4
      else
        w = 0; k = k + 1
      end if
      cursor_col = cursor_col + w
      ! Deferred wrap: a char that lands EXACTLY on term_cols fills the row and
      ! leaves the cursor in the terminal's pending-wrap state — still on this
      ! physical row, not advanced. Only a char that OVERFLOWS past term_cols is
      ! on the next row. Using '>= term_cols' here advanced the row one early, so
      ! the trailing cursor's module_cursor_screen_row was one too high and the
      ! next keystroke's move-up over-counted and scrolled the screen after an
      ! exact-width paste. Reset to the overflow (not 0) so a wide char that
      ! crosses the boundary keeps correct column accounting. (RL-1)
      if (cursor_col > term_cols) then
        cursor_row = cursor_row + 1
        cursor_col = cursor_col - term_cols
      end if
    end do
  end subroutine

  ! AR-87: rightmost display column occupied on ROW 0 (the first prompt row) by
  ! the rendered prompt + space + input. For a multi-line prompt that is just the
  ! first prompt line (the input is on a lower row); for a single-line prompt it
  ! includes the input. Returns term_cols when row 0 is wrapped full. Drives the
  ! right-prompt room check.
  function rprompt_row0_end(prompt, term_cols) result(end_col)
    character(len=*), intent(in) :: prompt
    integer, intent(in) :: term_cols
    integer :: end_col
    integer :: nl, w, er, ec

    end_col = 0
    if (term_cols <= 0) return
    nl = index(prompt(1:len_trim(prompt)), char(10))
    if (nl > 0) then
      ! Multi-line prompt: row 0 is the first prompt line only.
      w = visual_length(prompt(1:nl-1))
      if (w < 0) w = 0
      if (w >= term_cols) then
        end_col = term_cols
      else
        end_col = w
      end if
    else
      ! Single-line prompt: row 0 holds prompt + space + the whole input.
      call cursor_get_row_col(prompt, module_input_state%length, term_cols, er, ec)
      if (er == 0) then
        end_col = ec
      else
        end_col = term_cols
      end if
    end if
  end function rprompt_row0_end

  ! AR-87: build the right-prompt re-emit layer — a self-contained byte sequence
  ! that paints rprompt right-aligned on ROW 0 and returns the cursor where it
  ! was. cur_row is how many physical rows the cursor currently sits below the
  ! prompt origin (so ESC[A reaches row 0). Returns blen=0 (paints nothing) when
  ! there is no room (row-0 content + a 4-col gap would overlap the rprompt).
  ! Used by both the initial paint and the redraw so placement stays identical.
  subroutine build_rprompt_layer(prompt, rprompt, term_cols, cur_row, buf, blen)
    character(len=*), intent(in) :: prompt, rprompt
    integer, intent(in) :: term_cols, cur_row
    character(len=*), intent(out) :: buf
    integer, intent(out) :: blen
    integer :: rp_vlen, start_col, used, up, rp_len
    character(len=16) :: colbuf

    blen = 0
    buf = ''
    rp_len = len_trim(rprompt)
    if (rp_len == 0) return
    rp_vlen = visual_length(rprompt)
    if (rp_vlen <= 0) return
    start_col = term_cols - rp_vlen
    if (start_col < 0) return
    used = rprompt_row0_end(prompt, term_cols)
    if (used + 4 > start_col) return                 ! no room (keep a 4-col gap)
    if (rp_len + 3*max(cur_row,0) + 32 > len(buf)) return

    buf(blen+1:blen+2) = char(27) // '7'             ! save cursor (real input pos)
    blen = blen + 2
    do up = 1, cur_row                               ! up to row 0
      buf(blen+1:blen+3) = char(27) // '[A'
      blen = blen + 3
    end do
    write(colbuf, '(I0)') start_col + 1              ! absolute column (1-based)
    buf(blen+1:blen+2) = char(27) // '['
    blen = blen + 2
    buf(blen+1:blen+len_trim(colbuf)) = trim(colbuf)
    blen = blen + len_trim(colbuf)
    buf(blen+1:blen+1) = 'G'
    blen = blen + 1
    buf(blen+1:blen+rp_len) = rprompt(1:rp_len)       ! the right prompt
    blen = blen + rp_len
    buf(blen+1:blen+4) = char(27) // '[0m'           ! clear attrs
    blen = blen + 4
    buf(blen+1:blen+2) = char(27) // '8'             ! restore cursor
    blen = blen + 2
  end subroutine build_rprompt_layer

  ! Walk a rendered content buffer (with ANSI codes) and return the visual
  ! row that byte_pos falls on (0-based, wrapping at term_cols).
  subroutine content_byte_to_row_col(buf, buf_len, byte_pos, term_cols, row, col_out)
    integer, intent(in) :: buf_len, byte_pos, term_cols
    character(len=*), intent(in) :: buf
    integer, intent(out) :: row, col_out
    integer :: pos, col, bv, w

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
      ! Visible character: advance by DISPLAY width and skip UTF-8 continuation
      ! bytes, so the row/col matches what the terminal actually renders (a 3-
      ! byte char like a checkmark is 1-2 columns, not 3). Must stay consistent
      ! with cursor_get_row_col so the redraw's diff-down cancels the nav-up.
      bv = iand(iachar(buf(pos:pos)), 255)
      if (bv < 128) then
        w = 1; pos = pos + 1
      else if (iand(bv, 224) == 192) then
        w = utf8_char_width(buf(pos:pos)); pos = pos + 2
      else if (iand(bv, 240) == 224) then
        w = 2; pos = pos + 3
      else if (iand(bv, 248) == 240) then
        w = 2; pos = pos + 4
      else
        w = 0; pos = pos + 1   ! stray continuation byte
      end if
      col = col + w
      if (col >= term_cols) then
        row = row + 1
        col = 0
      end if
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