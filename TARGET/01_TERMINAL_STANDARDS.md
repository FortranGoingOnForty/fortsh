# Terminal Standards & Why They Matter

## What is Terminal-Shell Interaction?

When you type in a terminal emulator (like iTerm2, gnome-terminal, xterm), there's a complex dance happening between:

1. **Terminal Emulator** - The GUI application that displays text and sends keystrokes
2. **Shell** - The command interpreter (bash, zsh, **fortsh**)
3. **Operating System** - Manages processes, signals, and TTY devices

---

## Historical Context: Why These Standards Exist

### The TTY Legacy (1960s-1970s)

**Original Problem:** Physical teletypewriters (TTYs) connected to mainframes.
- Had physical keyboards and paper output
- Needed character-by-character transmission
- Required flow control (mechanical limitations)

**Solution:** POSIX terminal interface (`termios`)
- **Canonical mode** (cooked): Line buffering, editing with backspace
- **Raw mode**: Character-by-character input for full-screen apps

**Why it matters today:**
- Even though we use GUI terminals, the OS still emulates TTY devices
- `/dev/pts/0`, `/dev/tty` are virtual TTY devices
- All terminal I/O goes through this abstraction layer

---

### ANSI Escape Codes (1970s-1980s)

**Problem:** Different terminals had different control codes
- DEC VT100, IBM 3270, Wyse, etc. all incompatible
- Moving cursor required different byte sequences

**Solution:** ANSI X3.64 standard (became ISO/IEC 6429)
- `ESC[` prefix for control sequences
- `ESC[2J` = clear screen
- `ESC[H` = cursor home
- `ESC[31m` = red text

**Why it matters:**
- Modern terminals still speak ANSI/VT100
- Required for: cursor movement, colors, clearing screen
- Shell prompts with colors use ANSI codes

---

### terminfo/termcap (1980s)

**Problem:** Even with ANSI, terminals had variations
- Different capabilities (some support colors, some don't)
- Different terminal sizes
- Different key encodings

**Solution:** Terminal capability database
- **termcap**: Simple text database (older, legacy)
- **terminfo**: Binary database in `/usr/share/terminfo/`
- Programs query: "Does this terminal support bold?"

**Why it matters:**
- Portable full-screen applications (vim, less, top)
- Correct cursor positioning across terminals
- Graceful degradation on limited terminals

---

### Job Control (1980s - BSD Unix)

**Problem:** Early Unix couldn't suspend programs
- Ctrl-C killed programs, no way to pause
- No background jobs
- No returning to suspended programs

**Solution:** POSIX job control
- **Process groups**: Related processes grouped together
- **Session leader**: Shell controls the terminal
- **Foreground process group**: Gets keyboard input & signals
- **Background jobs**: Run without terminal access

**Signals:**
- `SIGTSTP` (Ctrl-Z): Suspend foreground job
- `SIGCONT`: Resume suspended job
- `SIGTTIN`: Background job tried to read from terminal
- `SIGTTOU`: Background job tried to write to terminal
- `SIGINT` (Ctrl-C): Interrupt foreground job

**Why it matters:**
- Modern shells: `command &` (background), `fg`, `bg`, `jobs`
- Editors can suspend and resume (vim Ctrl-Z)
- Job control is fundamental to interactive shell usage

---

### Readline / Line Editing (1980s - GNU)

**Problem:** Raw terminal input is painful
- No arrow keys for editing
- No history navigation
- No tab completion

**Solution:** GNU Readline library
- Emacs/vi key bindings (Ctrl-A, Ctrl-E, etc.)
- History search (Ctrl-R)
- Tab completion
- Multi-line editing

**Why it matters:**
- User expectation: shells should feel "nice"
- Bash, zsh, fish all have sophisticated line editing
- fortsh already has this! (readline.f90)

---

### Window Size & SIGWINCH (1990s)

**Problem:** Terminals can resize
- User drags window corner
- Full-screen apps need to reflow

**Solution:**
- `ioctl(TIOCGWINSZ)`: Query terminal size
- `SIGWINCH`: Signal sent when window resizes
- Apps re-query size and redraw

**Why it matters:**
- Shells need to know terminal width for line wrapping
- `ls` formats columns based on width
- Vim reflows text on resize

---

### Modern Extensions (2000s-2020s)

**Bracketed Paste Mode** (`ESC[?2004h`)
- **Problem:** Pasting code with newlines executed each line
- **Solution:** Terminal wraps pasted text in `ESC[200~` ... `ESC[201~`
- Shell can treat as single block

**True Color** (24-bit RGB)
- **Problem:** Limited 256 color palette
- **Solution:** `ESC[38;2;R;G;Bm` for millions of colors

**Hyperlinks** (OSC 8)
- **Problem:** URLs in terminal not clickable
- **Solution:** `OSC 8 ; ; url ST text OSC 8 ; ; ST`

**Synchronized Output** (`ESC[?2026h`)
- **Problem:** Concurrent writes cause tearing
- **Solution:** Buffer output until sync point

---

## The Shell's Responsibilities

A "true" shell must:

### 1. **Terminal State Management**
- Save/restore `termios` settings
- Switch between raw/cooked mode
- Handle canonical vs non-canonical input

### 2. **Signal Handling**
- Ignore `SIGTSTP`, `SIGTTIN`, `SIGTTOU` in shell
- Forward `SIGINT` to foreground job
- Reap children on `SIGCHLD`
- Handle `SIGWINCH` for resize

### 3. **Process Group Management**
- Create process groups for pipelines
- Set foreground process group with `tcsetpgrp()`
- Give terminal control back to shell

### 4. **Line Editing**
- Read input character-by-character
- Handle arrow keys, editing keys
- Maintain cursor position
- Support multi-line input

### 5. **Terminal Capabilities**
- Query terminal type (`$TERM`)
- Use terminfo to get capabilities
- Gracefully degrade if terminal limited

### 6. **Prompt Rendering**
- Calculate prompt width (ignoring escape codes)
- Position cursor correctly
- Handle multi-line prompts

---

## Why This is Complex

The interaction is **stateful** and **asynchronous**:

```
User types 'a' → Terminal → Shell (raw mode)
                           ↓
                    Display 'a', update cursor
                           ↓
User types Ctrl-C → Terminal → Shell intercepts
                           ↓
                    Send SIGINT to foreground job
                           ↓
                    Job exits → SIGCHLD → Shell reaps
                           ↓
                    Display new prompt
```

### Race Conditions
- Window resize during output
- Job exits while shell reading input
- Multiple background jobs finishing

### State Synchronization
- Terminal state (raw/cooked)
- Process group ownership
- Signal mask inheritance
- File descriptor inheritance

---

## References

**Standards:**
- POSIX.1-2017 Chapter 11: Terminal Interface
- ISO/IEC 6429:1992 (ANSI X3.64) - Control Functions
- terminfo(5) man page

**Classic Papers:**
- "The TTY demystified" by Linus Åkesson
- "Job Control" - POSIX rationale

**Modern Resources:**
- XTerm Control Sequences (ctlseqs.txt)
- terminal.sexy - ANSI escape code reference
- VT100.net - Terminal history and specs

---

## What fortsh Already Has ✅

Based on code audit:
- ✅ termios raw/cooked mode switching
- ✅ Signal handling (SIGINT, SIGTSTP, SIGCHLD, etc.)
- ✅ Process groups (setpgid, tcsetpgrp)
- ✅ Job control (jobs, fg, bg)
- ✅ Advanced readline (267KB implementation!)
- ✅ Syntax highlighting
- ✅ Tab completion
- ✅ History

**fortsh is already 80% of the way to full terminal integration!**

The gaps are mostly polish and edge cases - covered in the next documents.
