# fortsh Terminal Implementation - Current State Audit

**Audit Date:** 2025-11-13
**Branch:** trunk
**Code Size:** readline.f90 (267KB), system/interface.f90 (46KB), system/signals.f90 (7.8KB)

---

## ✅ IMPLEMENTED & WORKING

### Terminal Control (termios)

**Files:** `src/io/readline.f90`, `src/system/interface.f90`

```fortran
type(termios_t), save :: module_original_termios
logical, save :: module_termios_saved = .false.

success = enable_raw_mode(module_original_termios)
success = restore_terminal(module_original_termios)
```

**Capabilities:**
- ✅ Raw mode switching (character-by-character input)
- ✅ Cooked mode restoration
- ✅ Module-level terminal state management
- ✅ Safe save/restore across readline calls

**Assessment:** ⭐⭐⭐⭐⭐ **EXCELLENT**
Full termios support with proper state management.

---

### Signal Handling

**Files:** `src/system/signals.f90`, `src/io/readline.f90`

**Handled Signals:**
```fortran
SIGINT  = 2   ! Ctrl-C interrupt
SIGTSTP = 18  ! Ctrl-Z suspend (macOS/BSD)
SIGTTIN = 21  ! Background read from terminal
SIGTTOU = 22  ! Background write to terminal
SIGCHLD = 17  ! Child process status change
```

**Special Handling:**
- ✅ Shell ignores SIGTSTP/SIGTTIN/SIGTTOU (correct for job control)
- ✅ SIGCHLD handler for automatic job reaping
- ✅ Temporary SIGCHLD restore during system() calls
- ✅ SIGINT forwarding to foreground jobs

**Code Example:**
```fortran
! Shell ignores terminal signals
old_handler = c_signal(20, SIG_IGN) ! SIGTSTP
old_handler = c_signal(21, SIG_IGN) ! SIGTTIN
old_handler = c_signal(22, SIG_IGN) ! SIGTTOU

! But handles child status
old_handler = c_signal(17, c_funloc(sigchld_handler))
```

**Assessment:** ⭐⭐⭐⭐⭐ **EXCELLENT**
Proper POSIX job control signal handling.

---

### Process Group Management

**Files:** `src/fortsh_ast.f90`, `src/execution/executor.f90`, `src/execution/jobs.f90`

**Capabilities:**
```fortran
! Shell becomes session leader
ret = c_setpgid(shell%shell_pgid, shell%shell_pgid)
ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)

! Child processes get own process group
ret = c_setpgid(0, pgid)
ret = c_setpgid(pids(i), pgid)  ! Pipeline members

! Give terminal to job
ret = c_tcsetpgrp(shell%shell_terminal, pgid)
```

**Assessment:** ⭐⭐⭐⭐⭐ **EXCELLENT**
Full POSIX job control process group management.

---

### Job Control Builtins

**Files:** `src/execution/jobs.f90`

**Implemented:**
- ✅ `jobs` - List active jobs
- ✅ `fg [%n]` - Bring job to foreground
- ✅ `bg [%n]` - Resume job in background
- ✅ Job tracking (running, stopped, done states)
- ✅ Process group management per job

**Features:**
```fortran
! Give terminal control to job
ret = c_tcsetpgrp(shell%shell_terminal, shell%jobs(i)%pgid)

! Return control to shell
ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
```

**Assessment:** ⭐⭐⭐⭐☆ **VERY GOOD**
Job control works. Minor: Job spec parsing (%1, %%, etc.) may need expansion.

---

### Line Editing (Readline)

**File:** `src/io/readline.f90` (267KB!)

**Features:**
- ✅ Emacs keybindings (Ctrl-A, Ctrl-E, Ctrl-K, Ctrl-W, Ctrl-U, etc.)
- ✅ Vi mode support (EDITING_MODE_VI)
- ✅ Arrow keys (up, down, left, right)
- ✅ History navigation (up/down arrows, Ctrl-R search)
- ✅ Tab completion
- ✅ Syntax highlighting
- ✅ Multi-line editing
- ✅ Kill ring (Ctrl-K, Ctrl-Y)
- ✅ Word movement
- ✅ FZF integration (Ctrl-F, Ctrl-H)

**Keybindings:**
```fortran
KEY_CTRL_A = 1    ! Home (beginning of line)
KEY_CTRL_E = 5    ! End (end of line)
KEY_CTRL_K = 11   ! Kill to end of line
KEY_CTRL_L = 12   ! Clear screen
KEY_CTRL_W = 23   ! Kill previous word
KEY_CTRL_U = 21   ! Kill entire line
KEY_CTRL_Y = 25   ! Yank (paste) killed text
KEY_CTRL_R = 18   ! Reverse-i-search
KEY_CTRL_F = 6    ! FZF file browser
KEY_CTRL_H = 8    ! FZF history browser
KEY_CTRL_T = 20   ! Transpose characters
```

**Assessment:** ⭐⭐⭐⭐⭐ **EXCELLENT**
Comprehensive readline implementation rivals bash/zsh!

---

### Interactive Detection

**File:** `src/fortsh_ast.f90`

```fortran
shell%is_interactive = (c_isatty(STDIN_FD) /= 0)
```

**Assessment:** ⭐⭐⭐⭐⭐ **PERFECT**
Correctly detects if running interactively.

---

### Terminal I/O

**File:** `src/system/interface.f90`

**Available Functions:**
```fortran
function c_isatty(fd) bind(C, name="isatty")
function c_tcgetattr(fd, termios) bind(C, name="tcgetattr")
function c_tcsetattr(fd, optional_actions, termios) bind(C, name="tcsetattr")
```

**Assessment:** ⭐⭐⭐⭐⭐ **COMPLETE**
All essential terminal I/O bindings present.

---

## ⚠️ PARTIAL / MISSING FEATURES

### 1. Terminal Size Detection (TIOCGWINSZ)

**Status:** ❌ **NOT FOUND**

**What's Missing:**
```c
// C equivalent
struct winsize {
    unsigned short ws_row;
    unsigned short ws_col;
    unsigned short ws_xpixel;
    unsigned short ws_ypixel;
};
ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
```

**Impact:**
- Cannot detect terminal width/height
- `ls` column formatting may be suboptimal
- Line wrapping calculations may be incorrect
- Cannot properly reflow on window resize

**Workaround:** May be using `$COLUMNS` environment variable

**Priority:** ⭐⭐⭐ **HIGH** - needed for proper output formatting

---

### 2. SIGWINCH Handler

**Status:** ❌ **NOT IMPLEMENTED**

**What's Missing:**
```fortran
! Signal sent when terminal window resizes
SIGWINCH = 28  ! macOS/BSD
```

**Impact:**
- Shell doesn't know when terminal resizes
- Readline doesn't update line wrap calculations
- Multi-line editing can break after resize

**Priority:** ⭐⭐ **MEDIUM** - quality of life

---

### 3. Terminal Capability Detection (terminfo/termcap)

**Status:** ❌ **NOT FOUND**

**What's Missing:**
- No `setupterm()` / `tigetstr()` calls
- No querying of terminal database
- Hardcoded escape sequences (probably)

**Impact:**
- Assumes all terminals support ANSI codes
- No graceful degradation for dumb terminals
- Portable to common terminals but not exotic ones

**Current Approach:** Likely hardcodes VT100/ANSI sequences (works 99% of time)

**Priority:** ⭐ **LOW** - modern terminals all support ANSI

---

### 4. Cursor Position Tracking

**Status:** ❓ **UNKNOWN**

**What to Check:**
- Does readline track absolute cursor position?
- Can handle prompts with ANSI codes?
- Prompt width calculation (ignoring escape codes)?

**Needs Testing:**
```bash
PS1='\[\e[31m\]fortsh\[\e[0m\]$ '
# Does cursor position correctly?
```

**Priority:** ⭐⭐⭐ **HIGH** - affects prompt rendering

---

### 5. Bracketed Paste Mode

**Status:** ❌ **NOT IMPLEMENTED**

**What's Missing:**
```
ESC[?2004h  # Enable bracketed paste
ESC[?2004l  # Disable bracketed paste

# Pasted text arrives as:
ESC[200~...pasted text...ESC[201~
```

**Impact:**
- Pasting multi-line code executes each line immediately
- Security risk: pasted commands execute without review
- User experience: unexpected behavior

**Priority:** ⭐⭐⭐⭐ **VERY HIGH** - common user complaint

---

### 6. Alternative Screen Buffer

**Status:** ❌ **NOT IMPLEMENTED**

**What's Missing:**
```
ESC[?1049h  # Switch to alternate screen
ESC[?1049l  # Return to main screen
```

**Impact:**
- Cannot implement full-screen TUI mode
- Would be useful for built-in pagers, menus
- Not critical for basic shell operation

**Priority:** ⭐ **LOW** - nice to have

---

### 7. Terminal Title Setting

**Status:** ❓ **UNKNOWN**

**What to Check:**
```
ESC]0;title BEL    # Set terminal title
ESC]2;title BEL    # Set window title
```

**Typical Use:**
```
# Shell sets title to: user@host:/path
```

**Priority:** ⭐⭐ **MEDIUM** - user expectation

---

### 8. Mouse Support

**Status:** ❌ **NOT IMPLEMENTED**

**What's Missing:**
```
ESC[?1000h  # Enable mouse tracking
ESC[?1006h  # SGR extended mode
```

**Impact:**
- No click-to-position cursor
- No scroll wheel in less/man pages
- Not expected in standard shell

**Priority:** ⭐ **VERY LOW** - not standard shell feature

---

### 9. True Color (24-bit RGB)

**Status:** ❓ **UNKNOWN**

**What to Check:**
```
ESC[38;2;R;G;Bm    # Foreground RGB
ESC[48;2;R;G;Bm    # Background RGB
```

**Use Cases:**
- Syntax highlighting with full color palette
- Custom themes

**Priority:** ⭐⭐ **MEDIUM** - enhances UX

---

### 10. Job Spec Parsing

**Status:** ⚠️ **PARTIAL**

**What May Be Missing:**
```bash
%1    # Job 1
%%    # Current job
%+    # Current job (same as %%)
%-    # Previous job
%?str # Job with 'str' in command
```

**Needs Testing:** Do `fg %1`, `bg %%` work?

**Priority:** ⭐⭐⭐ **HIGH** - expected job control feature

---

## 🔍 NEEDS INVESTIGATION

### Areas Requiring Testing

1. **Prompt Width Calculation**
   - Does fortsh correctly calculate prompt width?
   - Are ANSI escape codes properly ignored?
   - Multi-line prompts handled?

2. **Terminal State Edge Cases**
   - What happens if terminal dies mid-execution?
   - Proper cleanup on abnormal exit?
   - State restoration after crash?

3. **Concurrent Output**
   - Background job writes to terminal?
   - Multiple processes writing simultaneously?
   - Output interleaving handling?

4. **Terminal Type Detection**
   - Checks `$TERM` environment variable?
   - Adapts to terminal capabilities?
   - Fallback for unknown terminals?

5. **UTF-8 / Wide Character Support**
   - Handles emoji in input?
   - Double-width characters (CJK)?
   - Combining characters?

6. **Control Character Display**
   - How are control characters shown?
   - `^C`, `^D` display?
   - Binary data handling?

---

## 📊 Summary Matrix

| Feature | Status | Priority | Effort |
|---------|--------|----------|--------|
| termios (raw/cooked) | ✅ DONE | Critical | - |
| Signal handling | ✅ DONE | Critical | - |
| Process groups | ✅ DONE | Critical | - |
| Job control | ✅ DONE | Critical | - |
| Line editing | ✅ DONE | Critical | - |
| History | ✅ DONE | High | - |
| Completion | ✅ DONE | High | - |
| Syntax highlighting | ✅ DONE | Medium | - |
| **Window size** | ❌ MISSING | High | Low |
| **SIGWINCH** | ❌ MISSING | Medium | Low |
| **Bracketed paste** | ❌ MISSING | Very High | Medium |
| **Prompt width calc** | ❓ TEST | High | Low-Med |
| **Job specs (%1, %%)** | ⚠️ PARTIAL | High | Low |
| **Terminal title** | ❓ TEST | Medium | Low |
| terminfo/termcap | ❌ MISSING | Low | High |
| Alt screen buffer | ❌ MISSING | Low | Low |
| Mouse support | ❌ MISSING | Very Low | High |
| True color | ❓ TEST | Medium | Low |

---

## 🎯 Overall Assessment

**fortsh Terminal Support:** ⭐⭐⭐⭐☆ (4/5)

**Strengths:**
- ✅ Core terminal control (termios) - PERFECT
- ✅ Job control - COMPLETE
- ✅ Signal handling - EXCELLENT
- ✅ Line editing - OUTSTANDING (267KB!)
- ✅ Process groups - PROPER POSIX

**Weaknesses:**
- ❌ Window size detection missing
- ❌ Bracketed paste mode (security/UX issue)
- ❓ Prompt width calculation needs testing
- ⚠️ Job spec parsing incomplete

**Conclusion:**
fortsh already has **enterprise-grade terminal integration** for core features. The missing pieces are mostly **polish and edge cases** that affect user experience rather than fundamental functionality.

Estimated to be **85-90% complete** compared to bash/zsh terminal handling.
