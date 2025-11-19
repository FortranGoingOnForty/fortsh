# Cursor Positioning and Redraw Issues

**Status**: Bug 3 - Cursor positioning work in progress

## Fixed Issues ✅

1. **Arrow keys couldn't navigate across wrapped lines**
   - Fixed by implementing (row, col) cursor tracking
   - Added `cursor_get_row_col()` and `cursor_move()` helpers
   - Rewrote `handle_cursor_left()` and `handle_cursor_right()`

2. **Ctrl-U cleared only line 2 and inserted new prompt on line 2**
   - Fixed by moving cursor to start BEFORE clearing buffer
   - Modified `handle_kill_line()` to calculate cursor position first

## Final Status (After commits ba9a1b5, 23611e2, 040c2aa)

**All Critical Issues Fixed:**
✅ Syntax highlighting - "exit" correctly turns green on "t"
✅ Ctrl-U doesn't eat line above prompt
✅ Characters on line 2 don't cause above-line deletion
✅ Ctrl-L heap corruption fixed (commit ba9a1b5) - cursor tracking updated after screen clear
✅ Cursor snap-back at last column fixed (commit 23611e2) - skip redraw after line wrap
✅ Backspace eating line above fixed (commit 040c2aa) - simplified to only use redraw

**Key Fixes Applied:**
1. **Cursor tracking system**: Module-level variables track actual screen position
2. **Direct character output**: Append at end outputs directly without redraw (except at line wrap)
3. **Ctrl-L fix**: Update cursor tracking after clearing screen
4. **Line wrap fix**: Skip syntax highlighting redraw when wrapping to avoid snap-back
5. **Backspace fix**: Simplified to only trigger redraw, avoiding cursor movement conflicts

**Issue 1 Analysis:**
- CR+LF moves cursor to next line (correct)
- But then dirty=true (for syntax highlighting) triggers redraw
- Redraw repositions cursor back to wrong place
- Need to skip redraw when just wrapped OR update tracking before redraw

**Issue 2 Analysis - HEAP CORRUPTION:**
```
malloc: Heap corruption detected, free list is damaged at 0x6000011e8010
*** Incorrect guard value: 2314885530818453536
```
- Ctrl-L with multi-line command causes SIGABRT
- Likely buffer operation issue during screen clear
- CRITICAL - must fix before continuing

**Issue 3 Analysis:**
- Type multi-line, backspace to previous line works
- Next backspace eats line above prompt
- Different from "second backspace" - this is first backspace after moving up

**New Issue 1 - Cursor snap-back at last column:**
- Type "asdf" with "f" landing on last column (e.g., col 80)
- Cursor briefly flashes to col 1 of next line
- Then snaps back to last column of previous line
- Root cause: CR+LF moves cursor, but then redraw (from dirty=true) repositions it wrong

**New Issue 2 - Syntax highlighting regression:**
- Type "exit" character by character
- "e", "ex", "exi" all correctly red (invalid command)
- When "t" typed, should turn entire word green (valid command)
- Instead: "exi" stays red, "t" appears white
- Root cause: Triggering redraw on space only doesn't update after command completion

**New Issue 3 - Second backspace eats line above:**
- Type multi-line command (wraps to line 2)
- First backspace from line 2 to line 1 works correctly
- Second backspace (while on line 1) eats line above prompt
- Root cause: Cursor tracking not updated correctly after first backspace's redraw

**Issue 1 Analysis - Cursor at last column:**
- When cursor is at column 79 (last col), typing a character doesn't wrap cursor to next line
- Character appears but cursor stays on same line
- Next character typed causes cursor to finally advance
- Root cause: Terminal auto-wrap behavior - cursor doesn't visually move until NEXT character

**Issue 2 Analysis - Backspace eating line above:**
- Similar to earlier Ctrl-U bug
- Backspace handler triggers redraw with stale cursor position
- Redraw moves "up" from wrong position, erasing line above prompt

**Issue 3 Analysis - Syntax highlighting:**
- Direct character output bypasses syntax highlighting
- Only full redraws trigger highlighting
- Commands at line boundaries never trigger redraw until backspace forces one

## Remaining Issues ❌

### Issue 3a: Above-line deletion on character insertion after line crossing

**Symptom**: When typing characters that cross from line 1 to line 2, every character insertion causes the line above to be deleted/erased.

**Test case**:
```
1. Type a long command that wraps to line 2
2. Continue typing on line 2
3. Observe: each character typed causes line 1 to disappear/flicker
```

**Root cause hypothesis**: The redraw logic calculates cursor position from buffer state, but doesn't account for where the cursor actually is on screen before character output.

**Files to investigate**:
- `src/io/readline.f90:1180-1300` - Main redraw logic
- Character insertion handlers that set `dirty = .true.`

---

### Issue 3b: Cursor doesn't advance to line 2 when typing on last column of line 1

**Symptom**: After Ctrl-U, when typing a character that should fill the last column of line 1, the cursor doesn't advance to line 2.

**Test case**:
```
1. Type command until line wraps
2. Press Ctrl-U to clear
3. Type characters until reaching last column of line 1 (e.g., column 80)
4. Type one more character
5. Expected: cursor wraps to line 2
6. Actual: "above-line deletion" occurs, cursor stays on line 1
```

**Root cause hypothesis**: Terminal line wrapping behavior at column boundary not handled correctly. When character fills the last column, terminal may or may not auto-wrap depending on implementation.

**Files to investigate**:
- Character insertion code
- Terminal width calculation (off-by-one at boundary?)

---

### Issue 3c: Cursor flashing with backspace after traversing back to line 1

**Symptom**: When using backspace to go from line 2 back to line 1, cursor flashes/flickers.

**Test case**:
```
1. Type command that wraps to line 2
2. Press left arrow to go to line 2
3. Press backspace repeatedly
4. When backspace crosses from line 2 to line 1, cursor flashes
```

**Root cause hypothesis**: Backspace handler triggers a redraw that causes cursor position to be recalculated incorrectly.

**Files to investigate**:
- `src/io/readline.f90` - `handle_backspace()` or similar
- Redraw logic when `dirty = .true.` after backspace

---

## Analysis: Core Redraw Problem

The fundamental issue is that fortsh's redraw logic was designed for single-line editing. When `dirty = .true.` is set:

1. Current code calculates "where cursor should be" from buffer state
2. Moves cursor to start of prompt using ESC[A (up) based on calculation
3. Clears screen from cursor down with ESC[J
4. Redraws entire line

**The problem**: If we just output a character to screen and THEN set `dirty=true`, the cursor is already in the wrong place when we try to move it "up" based on buffer calculation.

**Possible solutions**:
1. Track actual cursor position on screen separately from buffer position
2. Don't trigger full redraw for simple character insertion
3. Use more precise cursor positioning (ESC[row;colH absolute positioning)
4. Only redraw when truly necessary (completion, suggestion update, etc)

---

## Fix Order

1. Fix Issue 3a (above-line deletion) - **HIGHEST PRIORITY**
   - This affects all multi-line editing
   - Likely requires rethinking when/how we trigger redraws

2. Fix Issue 3b (cursor doesn't advance to line 2)
   - Terminal wrapping edge case
   - May be related to 3a or separate issue

3. Fix Issue 3c (cursor flashing on backspace)
   - Lower priority visual glitch
   - May be fixed automatically by 3a fix

---

## Testing After Fixes

Once all three issues are fixed, test:
- Type long command spanning 3+ lines
- Arrow left/right across all lines
- Backspace across all lines
- Ctrl-U from various positions
- Character insertion at line boundaries
- Home/End keys across lines
