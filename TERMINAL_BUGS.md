# Terminal Standardization Bug Report

**Date**: 2025-11-14
**Test Environment**: WezTerm on macOS, fortsh trunk branch

## Critical Issues Found During Manual Testing

### Issue 1: SIGWINCH Not Working ❌
**Test**: Window resize detection
**Expected**: `$COLUMNS` and `$LINES` update after terminal resize
**Actual**: Always returns 80x24 regardless of window size

**Root Cause Analysis**:
- SIGWINCH handler may not be properly registered
- Terminal size may not be queried on startup
- Size variables not being updated in shell state

**Files to Check**:
- `src/system/signal_handling.f90` - SIGWINCH handler
- `src/fortsh.f90` - Initialization of COLUMNS/LINES
- `src/system/interface.f90` - get_window_size()

**Fix Priority**: HIGH - This is Phase 1 Critical feature

---

### Issue 2: Arrow Key Navigation Broken ❌
**Test**: Multi-line command cursor positioning
**Expected**: Arrow keys move cursor correctly through wrapped lines
**Actual**: Display corruption, cursor jumps, prompt appears mid-command

**Symptoms**:
```
matthewwolffe@Mac :: ~/D/G/F/fortsh > this is a very fy_fix.smatthewwolffe@Mac :: ~/D/G/F/fortsh >
```

**Root Cause Analysis**:
- Cursor positioning calculation incorrect in readline
- visual_length() may not account for prompt correctly
- Escape sequence handling broken for wrapped lines
- Redraw logic corrupted

**Files to Check**:
- `src/io/readline.f90` - Lines 4800-5000 (escape sequence handling)
- `src/io/readline.f90` - visual_length() function
- `src/io/readline.f90` - Redraw logic for multi-line

**Fix Priority**: CRITICAL - Makes fortsh unusable for long commands

---

### Issue 3: Background Jobs Not Working ❌
**Test**: `sleep 100 &`
**Expected**: Job runs in background, returns control to prompt
**Actual**: Strange output, jobs don't background properly

**Symptoms**:
```
matthewwolffe@Mac :: ~/D/G/F/fortsh > sleep 100 &-
sleep 200 &
jobs
```

**Root Cause Analysis**:
- Background job execution broken in executor
- Job control implementation incomplete
- Pipeline parsing may not handle `&` correctly

**Files to Check**:
- `src/execution/executor.f90` - Background job handling
- `src/execution/jobs.f90` - add_job() logic
- `src/parsing/parser.f90` - `&` token parsing

**Fix Priority**: HIGH - Core shell functionality

---

### Issue 4: Terminal Title Not Updating ❌
**Test**: Title should show `user@host:path`
**Expected**: Title updates on cd and after commands
**Actual**: Title stays as "./bin/fortsh"

**Root Cause Analysis**:
- set_terminal_title() may not be called at right times
- Escape sequences may not be flushed
- Interactive mode detection may be wrong

**Files to Check**:
- `src/system/interface.f90:905` - set_terminal_title()
- `src/fortsh.f90` - Where set_terminal_title() is called
- `src/execution/builtins.f90` - cd command title update

**Fix Priority**: MEDIUM - Nice-to-have Phase 4 feature

---

### Issue 5: Wide Characters Can't Be Inserted ❌
**Test**: Paste emoji or CJK characters
**Expected**: Characters inserted at cursor
**Actual**: Nothing happens, characters don't appear

**Root Cause Analysis**:
- UTF-8 input handling broken in read_single_char()
- Multi-byte character assembly incomplete
- Paste handling may consume UTF-8 bytes incorrectly

**Files to Check**:
- `src/io/readline.f90` - read_single_char() UTF-8 handling
- `src/io/readline.f90` - insert_char_wrapper() UTF-8 support
- `src/system/interface.f90:906` - read_single_char() implementation

**Fix Priority**: MEDIUM - Phase 6 polish feature

---

### Issue 6: Output Corruption to fort.1 File ❌
**Observed**: Terminal escape sequences written to `fort.1` file
**File contents**:
```
]0;matthewwolffe@Mac: /path[?2004h[?2004l
```

**Root Cause Analysis**:
- File descriptor confusion (STDOUT vs FD 1)
- Escape sequences being written to wrong output
- Possible file descriptor leak

**Files to Check**:
- `src/system/interface.f90` - STDOUT_FD constant definition
- `src/io/readline.f90` - Any writes to FD 1
- All write() statements using STDOUT_FD

**Fix Priority**: HIGH - Data corruption issue

---

## Test Results Summary

| Test | Feature | Status | Priority |
|------|---------|--------|----------|
| 1 | Bracketed Paste | ⊘ SKIP | LOW (terminal dependent) |
| 2 | SIGWINCH | ❌ FAIL | HIGH |
| 3 | Cursor Positioning | ❌ FAIL | CRITICAL |
| 4 | Job Control | ❌ FAIL | HIGH |
| 5 | Terminal Title | ❌ FAIL | MEDIUM |
| 6 | UTF-8 Wide Chars | ❌ FAIL | MEDIUM |

**Passing**: 0/6
**Failing**: 5/6
**Skipped**: 1/6

---

## Fix Plan

### Phase 1: Fix Critical Issues (Blocking)
1. **Fix cursor positioning and display corruption** (Issue 2)
   - Debug visual_length() calculation
   - Fix escape sequence handling in readline
   - Verify prompt width calculation
   - Test with wrapped lines

2. **Fix background jobs** (Issue 3)
   - Debug `&` token parsing
   - Verify job control in executor
   - Test job backgrounding

3. **Fix fort.1 corruption** (Issue 6)
   - Find all STDOUT writes
   - Verify file descriptor usage
   - Ensure escape sequences go to terminal, not files

### Phase 2: Fix High Priority Issues
4. **Fix SIGWINCH** (Issue 1)
   - Verify signal handler registration
   - Test get_window_size() on startup
   - Update COLUMNS/LINES on resize

### Phase 3: Fix Medium Priority Issues
5. **Fix terminal title** (Issue 4)
   - Verify set_terminal_title() calls
   - Add flush after OSC sequences
   - Test in multiple terminals

6. **Fix UTF-8 input** (Issue 5)
   - Fix multi-byte character reading
   - Handle UTF-8 properly in read_single_char()
   - Test emoji and CJK input

---

## Next Steps

1. Start with Issue 2 (cursor positioning) - most critical
2. Then fix Issue 3 (background jobs) and Issue 6 (fort.1 corruption)
3. Move to SIGWINCH once display is stable
4. Polish with title and UTF-8 support

**All terminal standardization features need significant debugging before they work correctly.**
