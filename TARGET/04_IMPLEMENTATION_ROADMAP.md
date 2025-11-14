# Terminal Integration Implementation Roadmap

**Status:** fortsh is 85-90% complete for terminal integration
**Goal:** Achieve 100% parity with bash/zsh for terminal handling
**Estimated Total Effort:** 15-20 hours of focused work

---

## Quick Reference: Implementation Phases

| Phase | Features | Effort | Priority | ROI |
|-------|----------|--------|----------|-----|
| **Phase 1** | Window size + SIGWINCH | 2-3h | CRITICAL | ⭐⭐⭐⭐⭐ |
| **Phase 2** | Bracketed paste | 4-6h | CRITICAL | ⭐⭐⭐⭐⭐ |
| **Phase 3** | Prompt width calc | 2-3h | HIGH | ⭐⭐⭐⭐ |
| **Phase 4** | Job specs + title | 3-4h | MEDIUM | ⭐⭐⭐ |
| **Phase 5** | Terminal type adapt | 2-3h | LOW | ⭐⭐ |
| **Phase 6** | Polish (optional) | 2-4h | LOW | ⭐ |

**Recommended Start:** Phase 1 (window size) - highest impact, lowest complexity

---

## PHASE 1: Window Size Detection & SIGWINCH (2-3 hours)

### Why This First?
- ✅ Low complexity (simple ioctl call)
- ✅ High impact (fixes resize bugs)
- ✅ Foundation for prompt width calculation
- ✅ No major refactoring required

### Implementation Steps

#### Step 1.1: Add Window Size Structure (15 min)

**File:** `src/system/interface.f90`

```fortran
! Add after termios_t definition
type, bind(C) :: winsize_t
    integer(c_short) :: ws_row      ! Terminal height (lines)
    integer(c_short) :: ws_col      ! Terminal width (columns)
    integer(c_short) :: ws_xpixel   ! Width in pixels (usually 0)
    integer(c_short) :: ws_ypixel   ! Height in pixels (usually 0)
end type winsize_t

! Add ioctl binding
interface
    function c_ioctl_winsize(fd, request, ws) bind(C, name="ioctl")
        import c_int, winsize_t
        integer(c_int), value :: fd
        integer(c_int), value :: request
        type(winsize_t) :: ws
        integer(c_int) :: c_ioctl_winsize
    end function c_ioctl_winsize
end interface

! Platform-specific TIOCGWINSZ constant
! macOS/BSD: 0x40087468
! Linux:     0x00005413
#if defined(__APPLE__) || defined(__MACH__)
    integer(c_int), parameter :: TIOCGWINSZ = int(z'40087468', c_int)
#else
    integer(c_int), parameter :: TIOCGWINSZ = int(z'00005413', c_int)
#endif
```

#### Step 1.2: Add Query Function (30 min)

**File:** `src/system/interface.f90`

```fortran
function get_terminal_size(rows, cols) result(success)
    integer, intent(out) :: rows, cols
    logical :: success
    type(winsize_t) :: ws
    integer(c_int) :: ret

    ret = c_ioctl_winsize(STDOUT_FILENO, TIOCGWINSZ, ws)

    if (ret == 0) then
        rows = ws%ws_row
        cols = ws%ws_col
        success = .true.
    else
        ! Fallback to environment variables
        call get_environment_variable('LINES', status=ret)
        if (ret == 0) then
            read(line_str, *) rows
        else
            rows = 24  ! Default
        end if

        call get_environment_variable('COLUMNS', status=ret)
        if (ret == 0) then
            read(col_str, *) cols
        else
            cols = 80  ! Default
        end if
        success = .false.
    end if
end function get_terminal_size
```

#### Step 1.3: Add SIGWINCH Handler (45 min)

**File:** `src/system/signals.f90`

```fortran
! Add signal constant (platform-specific)
#if defined(__APPLE__) || defined(__MACH__)
    integer, parameter :: SIGWINCH = 28  ! macOS/BSD
#else
    integer, parameter :: SIGWINCH = 28  ! Linux (same)
#endif

! Global flag for resize detection
logical, volatile :: g_terminal_resized = .false.

! Signal handler
subroutine sigwinch_handler(sig) bind(C)
    integer(c_int), value :: sig
    g_terminal_resized = .true.
end subroutine sigwinch_handler

! In setup_signal_handlers:
subroutine setup_signal_handlers()
    ! ... existing code ...

    ! Handle window resize
    old_handler = c_signal(SIGWINCH, c_funloc(sigwinch_handler))
end subroutine setup_signal_handlers
```

#### Step 1.4: Update Shell State (30 min)

**File:** `src/fortsh_ast.f90`

```fortran
type :: shell_state_t
    ! ... existing fields ...

    ! Terminal dimensions
    integer :: term_rows = 24
    integer :: term_cols = 80
end type shell_state_t

! In shell initialization:
subroutine initialize_shell(shell)
    type(shell_state_t), intent(inout) :: shell
    logical :: success

    ! ... existing initialization ...

    ! Query initial terminal size
    success = get_terminal_size(shell%term_rows, shell%term_cols)

    ! Update environment variables (for child processes)
    write(rows_str, '(I0)') shell%term_rows
    write(cols_str, '(I0)') shell%term_cols
    call set_shell_variable(shell, 'LINES', trim(rows_str))
    call set_shell_variable(shell, 'COLUMNS', trim(cols_str))
end subroutine initialize_shell
```

#### Step 1.5: Check for Resize in REPL (30 min)

**File:** `src/io/readline.f90` (or main loop)

```fortran
! At the start of readline() or main REPL loop:
if (g_terminal_resized) then
    g_terminal_resized = .false.

    ! Re-query terminal size
    success = get_terminal_size(shell%term_rows, shell%term_cols)

    ! Update environment variables
    write(rows_str, '(I0)') shell%term_rows
    write(cols_str, '(I0)') shell%term_cols
    call set_shell_variable(shell, 'LINES', trim(rows_str))
    call set_shell_variable(shell, 'COLUMNS', trim(cols_str))

    ! Notify readline to recalculate line wrapping
    ! (may need to add this functionality if not present)
    call update_readline_width(shell%term_cols)
end if
```

### Testing Strategy

```bash
# Test 1: Query terminal size
$ echo $COLUMNS $LINES
80 24

# Test 2: Resize window
$ echo $COLUMNS $LINES
80 24
# <-- Resize window to 120x40
$ echo $COLUMNS $LINES
120 40

# Test 3: Multi-line command after resize
$ echo "Very long command that wraps across multiple lines when typed"
# <-- Cursor should position correctly

# Test 4: Child processes see correct size
$ bash -c 'echo $COLUMNS'
120
```

### Completion Criteria
- ✅ `$COLUMNS` and `$LINES` set correctly on startup
- ✅ Values update when terminal resized
- ✅ Readline adjusts line wrapping after resize
- ✅ No cursor positioning glitches

---

## PHASE 2: Bracketed Paste Mode (4-6 hours)

### Why This Matters?
- 🔒 Security: Prevents pasted `sudo rm -rf` from executing immediately
- 👤 UX: Users expect to review pasted code before execution
- 📊 Standard: All modern shells support this (bash 5+, zsh, fish)

### Implementation Steps

#### Step 2.1: Send Enable Sequence (15 min)

**File:** `src/io/readline.f90`

```fortran
! At the start of enable_raw_mode or readline initialization:
subroutine enable_bracketed_paste()
    ! ESC[?2004h = Enable bracketed paste
    write(STDOUT_FILENO, '(A)', advance='no') char(27) // '[?2004h'
    call flush(STDOUT_FILENO)
end subroutine enable_bracketed_paste

subroutine disable_bracketed_paste()
    ! ESC[?2004l = Disable bracketed paste
    write(STDOUT_FILENO, '(A)', advance='no') char(27) // '[?2004l'
    call flush(STDOUT_FILENO)
end subroutine disable_bracketed_paste

! In enable_raw_mode():
success = enable_raw_mode(module_original_termios)
call enable_bracketed_paste()

! In restore_terminal():
call disable_bracketed_paste()
success = restore_terminal(module_original_termios)
```

#### Step 2.2: Parse Paste Markers (2-3 hours)

**File:** `src/io/readline.f90`

```fortran
! State machine for escape sequence parsing
integer, parameter :: PARSE_NORMAL = 0
integer, parameter :: PARSE_ESC = 1
integer, parameter :: PARSE_CSI = 2
integer, parameter :: PARSE_PASTE_START = 3
integer, parameter :: PARSE_PASTE_DATA = 4

! In read_char or input processing loop:
function read_input_with_paste(buffer, buffer_len) result(chars_read)
    character(len=*), intent(out) :: buffer
    integer, intent(in) :: buffer_len
    integer :: chars_read

    integer :: state = PARSE_NORMAL
    integer :: pos = 1
    character :: ch
    character(len=16) :: escape_buf
    integer :: esc_pos = 1

    do while (pos <= buffer_len)
        ch = getchar()

        select case (state)
        case (PARSE_NORMAL)
            if (ch == char(27)) then  ! ESC
                state = PARSE_ESC
                esc_pos = 1
                escape_buf(esc_pos:esc_pos) = ch
                esc_pos = esc_pos + 1
            else
                buffer(pos:pos) = ch
                pos = pos + 1
            end if

        case (PARSE_ESC)
            escape_buf(esc_pos:esc_pos) = ch
            esc_pos = esc_pos + 1

            if (ch == '[') then
                state = PARSE_CSI
            else
                ! Not a CSI sequence, output as-is
                buffer(pos:pos+esc_pos-2) = escape_buf(1:esc_pos-1)
                pos = pos + esc_pos - 1
                state = PARSE_NORMAL
            end if

        case (PARSE_CSI)
            escape_buf(esc_pos:esc_pos) = ch
            esc_pos = esc_pos + 1

            ! Check for paste start: ESC[200~
            if (escape_buf(1:6) == char(27) // '[200~') then
                state = PARSE_PASTE_DATA
                pos = 1  ! Reset buffer for paste data
            else if (ch >= '@' .and. ch <= '~') then
                ! End of CSI sequence (not paste-related)
                buffer(pos:pos+esc_pos-2) = escape_buf(1:esc_pos-1)
                pos = pos + esc_pos - 1
                state = PARSE_NORMAL
            end if

        case (PARSE_PASTE_DATA)
            ! Buffer pasted text until ESC[201~
            if (ch == char(27)) then
                ! Might be end marker
                escape_buf(1:1) = ch
                esc_pos = 2
                state = PARSE_PASTE_END_CHECK
            else
                buffer(pos:pos) = ch
                pos = pos + 1
            end if

        case (PARSE_PASTE_END_CHECK)
            escape_buf(esc_pos:esc_pos) = ch
            esc_pos = esc_pos + 1

            if (escape_buf(1:6) == char(27) // '[201~') then
                ! End of paste - return all buffered data
                chars_read = pos - 1
                return
            else
                ! False alarm, add to buffer
                buffer(pos:pos+esc_pos-2) = escape_buf(1:esc_pos-1)
                pos = pos + esc_pos - 1
                state = PARSE_PASTE_DATA
            end if
        end select
    end do

    chars_read = pos - 1
end function read_input_with_paste
```

#### Step 2.3: Handle Pasted Text (1-2 hours)

**File:** `src/io/readline.f90`

```fortran
! In main readline loop:
logical :: in_paste_mode = .false.
character(len=MAX_LINE_LEN) :: paste_buffer

! When paste detected:
if (detected_paste_start) then
    in_paste_mode = .true.

    ! Read all pasted text into buffer
    call read_paste_data(paste_buffer, paste_len)

    ! Insert entire paste at cursor position
    call insert_text_at_cursor(line_buffer, cursor_pos, &
                               paste_buffer(1:paste_len))

    ! Redraw line
    call redraw_line(line_buffer, cursor_pos, prompt)

    in_paste_mode = .false.
end if
```

### Testing Strategy

```bash
# Test 1: Paste single line
# Paste: echo "hello"
# Expected: Appears in buffer, doesn't execute until Enter

# Test 2: Paste multi-line code
# Paste:
for i in 1 2 3; do
  echo $i
done
# Expected: All 3 lines appear in buffer, doesn't execute

# Test 3: Paste with newlines
# Paste: echo "line 1
# line 2"
# Expected: Both lines buffered, waiting for Enter

# Test 4: Security test
# Paste: sudo rm -rf /
# Expected: Appears in buffer, does NOT execute
```

### Completion Criteria
- ✅ Paste sequences detected and stripped
- ✅ Multi-line paste doesn't execute lines
- ✅ Paste data inserted at cursor position
- ✅ User can review before executing
- ✅ Bracketed paste disabled in non-interactive mode

---

## PHASE 3: Prompt Width Calculation (2-3 hours)

### Why This Matters?
- Colored prompts break cursor positioning if escape codes counted
- Common user customization (everyone wants fancy prompts)
- Affects multi-line editing accuracy

### Implementation Steps

#### Step 3.1: ANSI Code Stripping Function (1 hour)

**File:** `src/io/readline.f90` or `src/utils/string_utils.f90`

```fortran
! Calculate visible width of string (ignore ANSI codes)
function calculate_visible_width(str) result(width)
    character(len=*), intent(in) :: str
    integer :: width

    integer :: i, len_str
    logical :: in_escape = .false.
    integer :: esc_state

    ! Escape sequence states
    integer, parameter :: STATE_NORMAL = 0
    integer, parameter :: STATE_ESC = 1
    integer, parameter :: STATE_CSI = 2
    integer, parameter :: STATE_OSC = 3

    len_str = len(str)
    width = 0
    esc_state = STATE_NORMAL

    i = 1
    do while (i <= len_str)
        select case (esc_state)
        case (STATE_NORMAL)
            if (str(i:i) == char(27)) then  ! ESC
                esc_state = STATE_ESC
                i = i + 1
            else
                ! Regular character - count it
                width = width + 1
                i = i + 1
            end if

        case (STATE_ESC)
            if (str(i:i) == '[') then
                ! CSI sequence (most common: colors, cursor)
                esc_state = STATE_CSI
                i = i + 1
            else if (str(i:i) == ']') then
                ! OSC sequence (terminal title, hyperlinks)
                esc_state = STATE_OSC
                i = i + 1
            else
                ! Other escape sequence, skip next char
                esc_state = STATE_NORMAL
                i = i + 1
            end if

        case (STATE_CSI)
            ! CSI sequences end with [@-~]
            if (str(i:i) >= '@' .and. str(i:i) <= '~') then
                esc_state = STATE_NORMAL
            end if
            i = i + 1

        case (STATE_OSC)
            ! OSC sequences end with BEL or ST (ESC\)
            if (str(i:i) == char(7)) then  ! BEL
                esc_state = STATE_NORMAL
                i = i + 1
            else if (i < len_str .and. str(i:i+1) == char(27) // '\') then
                esc_state = STATE_NORMAL
                i = i + 2
            else
                i = i + 1
            end if
        end select
    end do
end function calculate_visible_width
```

#### Step 3.2: Apply to Prompt Rendering (1 hour)

**File:** `src/io/readline.f90`

```fortran
! When rendering prompt:
subroutine display_prompt(prompt_str)
    character(len=*), intent(in) :: prompt_str
    integer :: visual_width

    ! Display the full prompt (including ANSI codes)
    write(STDOUT_FILENO, '(A)', advance='no') trim(prompt_str)

    ! Calculate width for cursor positioning
    visual_width = calculate_visible_width(prompt_str)

    ! Store for later use in cursor calculations
    module_prompt_width = visual_width
end subroutine display_prompt

! When calculating cursor position:
function get_cursor_column(line_buffer, cursor_pos) result(col)
    character(len=*), intent(in) :: line_buffer
    integer, intent(in) :: cursor_pos
    integer :: col

    ! Cursor column = prompt width + position in buffer
    col = module_prompt_width + cursor_pos

    ! Handle line wrapping if exceeds terminal width
    if (col > shell%term_cols) then
        col = mod(col - 1, shell%term_cols) + 1
    end if
end function get_cursor_column
```

#### Step 3.3: Handle Multi-line Prompts (30 min)

```fortran
! Count newlines in prompt
function count_prompt_lines(prompt_str) result(lines)
    character(len=*), intent(in) :: prompt_str
    integer :: lines, i

    lines = 1
    do i = 1, len_trim(prompt_str)
        if (prompt_str(i:i) == char(10)) then  ! LF
            lines = lines + 1
        end if
    end do
end function count_prompt_lines

! Calculate last line width (for cursor positioning)
function get_prompt_last_line_width(prompt_str) result(width)
    character(len=*), intent(in) :: prompt_str
    integer :: width, last_newline, len_str

    len_str = len_trim(prompt_str)
    last_newline = index(prompt_str, char(10), back=.true.)

    if (last_newline > 0) then
        ! Multi-line prompt - measure only last line
        width = calculate_visible_width(prompt_str(last_newline+1:len_str))
    else
        ! Single line prompt
        width = calculate_visible_width(prompt_str)
    end if
end function get_prompt_last_line_width
```

### Testing Strategy

```bash
# Test 1: Colored single-line prompt
$ export PS1='\[\e[31m\]fortsh\[\e[0m\]$ '
$ # Type long command, verify cursor position

# Test 2: Multi-line prompt
$ export PS1='┌─[\u@\h]\n└─$ '
$ # Verify cursor on second line

# Test 3: Emoji prompt
$ export PS1='🚀 '
$ # Check cursor position (emoji = 2 visual columns)

# Test 4: Complex colors
$ export PS1='\[\e[38;2;255;100;0m\]\w\[\e[0m\] > '
$ # True color prompt should work
```

### Completion Criteria
- ✅ Colored prompts don't break cursor positioning
- ✅ Multi-line prompts work correctly
- ✅ Emoji/wide characters handled (if UTF-8 support exists)
- ✅ Line wrapping calculations accurate

---

## PHASE 4: Job Specs & Terminal Title (3-4 hours)

### Part A: Job Spec Parsing (2 hours)

**File:** `src/execution/jobs.f90`

```fortran
! Parse job specification string
function parse_job_spec(shell, spec_str, job_id) result(success)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: spec_str
    integer, intent(out) :: job_id
    logical :: success

    character(len=256) :: spec
    integer :: num, i

    spec = trim(spec_str)
    success = .false.

    if (len_trim(spec) == 0) then
        ! Empty spec = current job
        job_id = shell%current_job
        success = (job_id > 0)
        return
    end if

    if (spec(1:1) == '%') then
        spec = spec(2:)  ! Remove leading %
    end if

    select case (trim(spec))
    case ('', '+', '%')
        ! Current job
        job_id = shell%current_job
        success = (job_id > 0)

    case ('-')
        ! Previous job
        job_id = shell%previous_job
        success = (job_id > 0)

    case default
        ! Check if it's a number
        if (spec(1:1) >= '0' .and. spec(1:1) <= '9') then
            read(spec, *, iostat=i) num
            if (i == 0 .and. num > 0 .and. num <= shell%num_jobs) then
                job_id = num
                success = .true.
            end if
        else if (spec(1:1) == '?') then
            ! Search for substring in command
            do i = 1, shell%num_jobs
                if (index(shell%jobs(i)%command, trim(spec(2:))) > 0) then
                    job_id = i
                    success = .true.
                    return
                end if
            end do
        end if
    end select
end function parse_job_spec

! Modify fg/bg builtins to use parse_job_spec:
subroutine builtin_fg(shell, args, num_args)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), dimension(:), intent(in) :: args
    integer, intent(in) :: num_args

    integer :: job_id
    logical :: success

    if (num_args == 1) then
        ! No argument - use current job
        success = parse_job_spec(shell, '', job_id)
    else
        ! Parse job spec
        success = parse_job_spec(shell, args(2), job_id)
    end if

    if (.not. success) then
        write(STDERR_FILENO, '(A)') 'fg: no such job'
        return
    end if

    ! ... rest of fg implementation ...
end subroutine builtin_fg
```

### Part B: Terminal Title (1-2 hours)

**File:** `src/io/readline.f90` or main REPL loop

```fortran
! Set terminal title
subroutine set_terminal_title(title_str)
    character(len=*), intent(in) :: title_str

    ! OSC 0 = set icon + window title
    ! Format: ESC]0;title BEL
    write(STDOUT_FILENO, '(A)', advance='no') &
        char(27) // ']0;' // trim(title_str) // char(7)
end subroutine set_terminal_title

! Update title after each command
subroutine update_title_for_command(shell)
    type(shell_state_t), intent(in) :: shell
    character(len=256) :: title_str
    character(len=256) :: cwd, username, hostname

    ! Get current directory
    cwd = get_shell_variable(shell, 'PWD')
    username = get_shell_variable(shell, 'USER')
    hostname = get_shell_variable(shell, 'HOSTNAME')

    ! Format: user@host:cwd
    write(title_str, '(A,A,A,A,A)') &
        trim(username), '@', trim(hostname), ':', trim(cwd)

    call set_terminal_title(title_str)
end subroutine update_title_for_command

! Call after each command execution:
! In main REPL:
do while (.not. exit_requested)
    call display_prompt(shell%ps1)
    call readline(input_line)
    call execute_command(shell, input_line)

    ! Update terminal title
    call update_title_for_command(shell)
end do
```

### Testing Strategy

```bash
# Job specs:
$ sleep 100 &
[1] 12345
$ sleep 200 &
[2] 12346
$ jobs
[1]- Running   sleep 100 &
[2]+ Running   sleep 200 &

$ fg %1        # Job 1
$ fg %%        # Current job (2)
$ fg %+        # Same as %%
$ fg %-        # Previous job (1)
$ fg %?sleep   # First job matching "sleep"
$ fg 1         # Job 1 (without %)

# Terminal title:
# Check terminal window/tab title
# Should show: user@host:/current/path
```

---

## PHASE 5: Terminal Type Adaptation (2-3 hours)

### Implementation

**File:** `src/io/readline.f90` or new `src/terminal/terminfo.f90`

```fortran
! Check if terminal supports ANSI codes
function terminal_supports_ansi() result(supports)
    logical :: supports
    character(len=256) :: term_type
    integer :: status

    call get_environment_variable('TERM', term_type, status=status)

    if (status /= 0) then
        ! No TERM set - assume dumb
        supports = .false.
        return
    end if

    ! Known dumb terminals
    select case (trim(term_type))
    case ('dumb', 'unknown', '')
        supports = .false.
    case default
        supports = .true.
    end select
end function terminal_supports_ansi

! Initialize terminal capabilities
subroutine init_terminal_caps(shell)
    type(shell_state_t), intent(inout) :: shell

    shell%term_supports_color = terminal_supports_ansi()

    ! Disable syntax highlighting if no ANSI support
    if (.not. shell%term_supports_color) then
        shell%enable_syntax_highlighting = .false.
    end if
end subroutine init_terminal_caps
```

### Testing

```bash
# Test 1: Normal terminal
$ echo $TERM
xterm-256color
$ # Should have colors

# Test 2: Dumb terminal
$ TERM=dumb ./bin/fortsh
$ # Should disable colors

# Test 3: Emacs shell
$ # Open emacs shell (M-x shell)
$ # Should detect and disable colors
```

---

## PHASE 6: Polish & Optional Features (2-4 hours)

### True Color Support (30 min)

Likely already works (pass-through). Test:

```bash
$ echo -e "\e[38;2;255;100;50mTRUE COLOR\e[0m"
```

If it works, just document it.

### Alternative Screen Buffer (1 hour)

Only if implementing full-screen mode:

```fortran
subroutine enter_alt_screen()
    write(STDOUT_FILENO, '(A)', advance='no') char(27) // '[?1049h'
end subroutine enter_alt_screen

subroutine exit_alt_screen()
    write(STDOUT_FILENO, '(A)', advance='no') char(27) // '[?1049l'
end subroutine exit_alt_screen
```

### UTF-8 Wide Character Support (1-2 hours)

If not already working, add:

```fortran
! Calculate width of UTF-8 character
function utf8_char_width(char_bytes) result(width)
    character(len=*), intent(in) :: char_bytes
    integer :: width

    ! Emoji and CJK = 2 columns
    ! ASCII = 1 column
    ! Combining characters = 0 columns

    ! Simple heuristic (can improve with Unicode tables)
    if (ichar(char_bytes(1:1)) < 128) then
        width = 1  ! ASCII
    else
        width = 2  ! Assume wide (emoji, CJK)
    end if
end function utf8_char_width
```

---

## Implementation Order Recommendations

### Option A: Maximum Impact (Recommended)

```
1. Phase 1 (window size + SIGWINCH) - 2-3h
   → Fixes resize bugs immediately

2. Phase 3 (prompt width) - 2-3h
   → Unblocks colored prompts (common user request)

3. Phase 2 (bracketed paste) - 4-6h
   → Huge UX and security improvement

4. Phase 4 (job specs + title) - 3-4h
   → Polish for power users

Total: 11-16 hours for "feels like bash" experience
```

### Option B: Low-Hanging Fruit First

```
1. Phase 1 (window size) - 2-3h
2. Phase 4B (terminal title) - 1h
3. Phase 3 (prompt width) - 2-3h
4. Phase 2 (bracketed paste) - 4-6h
5. Phase 4A (job specs) - 2h

Total: 11-15 hours
```

### Option C: Security First

```
1. Phase 2 (bracketed paste) - 4-6h
   → Prevents paste execution exploit

2. Phase 1 (window size) - 2-3h
3. Phase 3 (prompt width) - 2-3h
4. Phase 4 (job specs + title) - 3-4h

Total: 11-16 hours
```

---

## Testing Checklist

After each phase, verify:

### Automated Tests

Create `tests/terminal_integration.sh`:

```bash
#!/bin/bash

# Test 1: Window size
test_window_size() {
    cols=$(./bin/fortsh -c 'echo $COLUMNS')
    [[ $cols =~ ^[0-9]+$ ]] || fail "COLUMNS not set"
}

# Test 2: Bracketed paste
test_bracketed_paste() {
    # Send paste escape codes
    echo -e '\e[?2004h\e[200~echo hello\e[201~' | ./bin/fortsh
    # Should not execute until Enter
}

# Test 3: Job specs
test_job_specs() {
    ./bin/fortsh -c 'sleep 1 & sleep 2 & fg %1' || fail
}

# Run all tests
test_window_size
test_bracketed_paste
test_job_specs
```

### Manual Tests

- [ ] Resize terminal during input → cursor stays correct
- [ ] Paste multi-line code → doesn't execute
- [ ] Colored prompt → cursor positioned correctly
- [ ] `fg %1`, `bg %%` work as expected
- [ ] Terminal title updates after cd
- [ ] Works in emacs shell (no escape code garbage)

---

## Code Organization

### New Files to Create

```
src/terminal/
    capabilities.f90    # terminfo/TERM detection
    escape_codes.f90    # ANSI sequence constants
    title.f90           # Terminal title management

tests/
    terminal_integration.sh   # Automated terminal tests
```

### Files to Modify

```
src/system/interface.f90    # Add winsize_t, ioctl binding
src/system/signals.f90      # Add SIGWINCH handler
src/io/readline.f90         # Bracketed paste, prompt width
src/execution/jobs.f90      # Job spec parsing
src/fortsh_ast.f90          # Add term_rows, term_cols
```

---

## References & Resources

### C Bindings to Add

```fortran
! src/system/interface.f90

! Window size query
function c_ioctl_winsize(fd, request, ws) bind(C, name="ioctl")

! Flush output (for escape sequences)
function c_fflush(stream) bind(C, name="fflush")

! Optional: terminfo access
function c_setupterm(term, fd, errret) bind(C, name="setupterm")
function c_tigetstr(capname) bind(C, name="tigetstr")
```

### ANSI Escape Sequences

```
ESC = \x1B = char(27)

Cursor movement:
  ESC[H        Home
  ESC[{row};{col}H   Move to position

Colors:
  ESC[0m       Reset
  ESC[31m      Red foreground
  ESC[38;2;R;G;Bm   True color foreground

Terminal control:
  ESC[?2004h   Enable bracketed paste
  ESC[?1049h   Use alternate screen
  ESC]0;title BEL   Set terminal title
```

### Standards Documents

- POSIX.1-2017 Chapter 11 (Terminal Interface)
- XTerm Control Sequences (ctlseqs.txt)
- ISO/IEC 6429:1992 (ANSI escape codes)

---

## Expected Outcomes

### After Phase 1 (Window Size)
- ✅ `ls` formats columns correctly
- ✅ Long commands wrap properly
- ✅ Window resize doesn't break editing

### After Phase 2 (Bracketed Paste)
- ✅ Pasting code is safe
- ✅ Multi-line paste works naturally
- ✅ Security vulnerability closed

### After Phase 3 (Prompt Width)
- ✅ Colored prompts work
- ✅ No cursor positioning glitches
- ✅ Multi-line prompts supported

### After Phase 4 (Job Specs + Title)
- ✅ Full POSIX job control
- ✅ Terminal title shows context
- ✅ Power user features complete

### Final Result
**fortsh = indistinguishable from bash/zsh for terminal interaction**

---

## Risk Assessment

### Low Risk
- Phase 1 (window size) - Simple ioctl, well-tested API
- Phase 3 (prompt width) - Pure string processing
- Phase 4B (title) - Send-and-forget escape codes

### Medium Risk
- Phase 2 (bracketed paste) - Complex state machine, needs thorough testing
- Phase 4A (job specs) - String parsing edge cases

### High Risk
- None! All features are well-documented and widely implemented

### Mitigation Strategies

1. **Test incrementally** - Each phase is independent
2. **Feature flags** - Add `FORTSH_ENABLE_BRACKETED_PASTE` env var for testing
3. **Fallback gracefully** - If ioctl fails, use $COLUMNS/$LINES
4. **Reference implementations** - bash and zsh source code available

---

## Success Metrics

| Metric | Before | Target |
|--------|--------|--------|
| Terminal parity | 85% | 100% |
| User-reported bugs | ? | 0 |
| Resize issues | Common | None |
| Paste issues | Common | None |
| Prompt bugs | Occasional | None |

**Timeline:** 15-20 hours of focused work → production-ready terminal integration

---

## Next Steps

1. **Choose implementation order** (recommend Option A - Maximum Impact)
2. **Create feature branch:** `git checkout -b feature/terminal-integration`
3. **Start with Phase 1** (window size) - quick win!
4. **Test incrementally** after each phase
5. **Document completion** in TARGET/05_COMPLETION_LOG.md (create as you go)

**Ready to start? Phase 1 (window size) takes only 2-3 hours and fixes the most common user complaint!**
