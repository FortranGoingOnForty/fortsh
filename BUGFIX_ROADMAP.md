# Terminal Standardization Bugfix Roadmap

**Date**: 2025-11-14
**Branch**: trunk (terminal-standardization work)

## Test Results Summary

| Test | Feature | Status | Priority |
|------|---------|--------|----------|
| 1 | Bracketed Paste | ⊘ SKIP | LOW (WezTerm doesn't support) |
| 2 | SIGWINCH | ❌ FAIL | HIGH |
| 3 | Cursor Positioning | ❌ FAIL | CRITICAL |
| 4 | Job Control | ❌ FAIL | HIGH |
| 5 | Terminal Title | ❌ FAIL | MEDIUM |
| 6 | UTF-8 Wide Chars | ❌ FAIL | MEDIUM |

**Passing**: 0/6 | **Failing**: 5/6 | **Skipped**: 1/6

---

## Fix Order & Rationale

### 1. Fort.1 File Corruption ⚠️ DATA CORRUPTION
**Priority**: CRITICAL - Fix first
**Estimated effort**: 1-2 hours

**Issue**: Terminal escape sequences being written to `fort.1` file
```
]0;matthewwolffe@Mac: /path[?2004h[?2004l
```

**Why first**:
- Data corruption is always highest priority
- May interfere with testing all other features
- Could indicate fundamental file descriptor handling bug
- Needs to be clean before we can trust test output

**Fix approach**:
- Search for all writes to FD 1 or STDOUT_FD
- Verify STDOUT_FD constant is correct
- Check if fortsh is accidentally redirecting stdout
- Ensure escape sequences only go to terminal, not files

**Files to investigate**:
- `src/system/interface.f90` - STDOUT_FD definition
- All write() statements in codebase
- `src/io/readline.f90` - Prompt and escape sequence writes

**Success criteria**: No escape sequences written to fort.1 or any files

---

### 2. SIGWINCH Not Working 📏
**Priority**: HIGH - Fix second
**Estimated effort**: 2-3 hours

**Issue**: `$COLUMNS` and `$LINES` always return 80x24 regardless of window size

**Why second**:
- Relatively isolated issue
- Should be quick win to build momentum
- No dependencies on other bugs
- Clean signal handling issue

**Fix approach**:
- Verify SIGWINCH handler is registered correctly
- Check get_window_size() is called on startup
- Ensure SIGWINCH updates shell%term_cols and shell%term_rows
- Verify COLUMNS/LINES environment variables are updated

**Files to investigate**:
- `src/system/signal_handling.f90` - SIGWINCH handler
- `src/fortsh.f90` - Initialization and signal registration
- `src/system/interface.f90` - get_window_size()

**Success criteria**: COLUMNS/LINES update correctly after terminal resize

---

### 3. Cursor Positioning Broken 🖱️
**Priority**: CRITICAL - Fix third
**Estimated effort**: 4-6 hours

**Issue**: Arrow keys cause display corruption, prompt appears mid-command
```
matthewwolffe@Mac :: ~/D/G/F/fortsh > this is a very fy_fix.smatthewwolffe@Mac :: ~/D/G/F/fortsh >
```

**Why third**:
- Makes fortsh unusable for any real work
- Must be fixed before we can properly test other features
- Complex but contained to readline.f90
- Affects all subsequent testing

**Fix approach**:
- Debug visual_length() calculation
- Verify prompt width calculation excludes ANSI codes
- Check cursor position tracking in input_state
- Fix redraw logic for wrapped lines
- Test escape sequence handling for arrow keys

**Files to investigate**:
- `src/io/readline.f90` - Lines 4800-5000 (escape sequence handling)
- `src/io/readline.f90` - visual_length() function
- `src/io/readline.f90` - Redraw logic

**Success criteria**: Long commands wrap correctly, arrow keys navigate without corruption

---

### 4. Background Jobs Don't Work 💼
**Priority**: HIGH - Fix fourth
**Estimated effort**: 3-4 hours

**Issue**: `sleep 100 &` doesn't background properly, strange output

**Why fourth**:
- Core shell functionality
- Easier to test once display is stable
- May depend on clean readline working

**Fix approach**:
- Debug `&` token parsing in parser
- Verify background job creation in executor
- Check job control flags (foreground vs background)
- Test job list management

**Files to investigate**:
- `src/parsing/parser.f90` - `&` token parsing
- `src/execution/executor.f90` - Background job handling
- `src/execution/jobs.f90` - add_job() logic

**Success criteria**: `sleep 100 &` returns immediately, `jobs` shows background job

---

### 5. Terminal Title Not Updating 📋
**Priority**: MEDIUM - Fix fifth
**Estimated effort**: 1-2 hours

**Issue**: Terminal title stays as "./bin/fortsh" instead of "user@host:path"

**Why fifth**:
- Nice-to-have polish feature
- Doesn't block other functionality
- Quick fix once we verify OSC sequences work

**Fix approach**:
- Verify set_terminal_title() is called at startup
- Add flush after OSC sequences
- Check if interactive mode detection is correct
- Verify cd command updates title

**Files to investigate**:
- `src/system/interface.f90` - set_terminal_title()
- `src/fortsh.f90` - Startup title setting
- `src/execution/builtins.f90` - cd command

**Success criteria**: Title shows "user@host:path" and updates on cd

---

### 6. UTF-8 Wide Characters Can't Be Inserted 🌏
**Priority**: MEDIUM - Fix last
**Estimated effort**: 3-5 hours

**Issue**: Can't paste emoji or CJK characters, nothing happens

**Why last**:
- Polish feature, not core functionality
- Complex (multi-byte character handling)
- Least impactful to core shell usage
- Can be deferred if time-limited

**Fix approach**:
- Fix UTF-8 multi-byte character reading in read_single_char()
- Handle paste of multi-byte sequences
- Ensure insert_char_wrapper() handles UTF-8
- Test with emoji and CJK input

**Files to investigate**:
- `src/system/interface.f90` - read_single_char() UTF-8 handling
- `src/io/readline.f90` - Character insertion logic

**Success criteria**: Emoji and CJK characters can be typed/pasted and display correctly

---

## Progress Tracking

- [ ] 1. Fort.1 corruption
- [ ] 2. SIGWINCH
- [ ] 3. Cursor positioning
- [ ] 4. Background jobs
- [ ] 5. Terminal title
- [ ] 6. UTF-8 input

**Current Status**: Starting Issue 1
**Last Updated**: 2025-11-14
