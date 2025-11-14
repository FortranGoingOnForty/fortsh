# Gap Analysis: fortsh vs Standard Shells

Comparing fortsh terminal behavior to bash 5.x, zsh 5.x, and fish 3.x

---

## Testing Methodology

For each feature, we test:
1. Does it work in fortsh?
2. How does it compare to bash/zsh/fish?
3. What's the user-visible impact?

---

## 🔍 CRITICAL GAPS (User-Facing Issues)

### 1. Bracketed Paste Mode

**What bash/zsh/fish do:**
```bash
# In bash:
$ set enable-bracketed-paste on  # (default in bash 5+)
# Paste multi-line code → doesn't execute until Enter
```

**Terminal sequence:**
```
# Shell sends to terminal:
ESC[?2004h   # Enable bracketed paste

# Terminal wraps pasted text:
ESC[200~<pasted text>ESC[201~

# Shell can now:
# - Insert all text before executing
# - Show "(paste)" indicator
# - Allow user to review before Enter
```

**What fortsh does:**
```
❌ NOT IMPLEMENTED
```

**User Impact:**
```bash
# Paste this code in bash → waits for review:
for i in 1 2 3; do
  echo $i
done

# Paste in fortsh (without bracketed paste) → executes immediately:
for i in 1 2 3; do    # <-- EXECUTES
# Shell waits for done, user confused
```

**Why Critical:**
- Security: Pasted code with `sudo rm -rf` executes immediately
- UX: Unexpected behavior frustrates users
- Standard: All modern shells have this

**Fix Effort:** ⭐⭐⭐ MEDIUM
- Send enable sequence on startup
- Parse `ESC[200~` ... `ESC[201~` markers
- Buffer paste, insert at once

---

### 2. Window Size Detection (TIOCGWINSZ)

**What bash/zsh/fish do:**
```bash
$ echo $COLUMNS $LINES
80 24

# After window resize:
$ echo $COLUMNS $LINES
120 40
```

**System Call:**
```c
struct winsize ws;
ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
// ws.ws_col = 80, ws.ws_row = 24
```

**What fortsh likely does:**
```
❓ UNKNOWN - may rely on $COLUMNS env var
```

**User Impact:**
```bash
# bash adjusts to terminal width:
$ ls -l
# <-- formatted for 80 columns

# Resize to 120 columns
$ ls -l
# <-- formatted for 120 columns

# fortsh (without detection):
$ ls -l
# <-- still formatted for old width
```

**Why Critical:**
- Line wrapping in readline incorrect after resize
- Output formatting suboptimal
- Multi-line editing breaks

**Fix Effort:** ⭐ LOW
- Add `ioctl(TIOCGWINSZ)` binding
- Query on startup and SIGWINCH
- Update `$COLUMNS`, `$LINES`

---

### 3. SIGWINCH Handling

**What bash/zsh/fish do:**
```bash
# User resizes terminal window
# → SIGWINCH signal sent to shell
# → Shell re-queries terminal size
# → Shell updates $COLUMNS/$LINES
# → Readline adjusts line wrapping
```

**What fortsh does:**
```
❌ NOT IMPLEMENTED (SIGWINCH not in signal handlers)
```

**User Impact:**
```bash
# Resize terminal mid-command:
$ echo "very long command that wraps across multiple lines when the
# <-- Cursor positioning breaks
# <-- Text overwrites prompt
```

**Why Critical:**
- Breaks multi-line editing after resize
- Affects all readline operations
- Common user action

**Fix Effort:** ⭐ LOW
- Add SIGWINCH to signal handlers
- Call `ioctl(TIOCGWINSZ)` on signal
- Notify readline of size change

---

### 4. Prompt Width Calculation

**What bash/zsh/fish do:**
```bash
# Bash recognizes non-printing sequences:
PS1='\[\e[31m\]$\[\e[0m\] '
#     ^------^        ^------^
#     ignored for width calculation

# Actual width: 2 characters ('$ ')
# Not 12 characters (with escape codes)
```

**Testing Needed in fortsh:**
```bash
PS1="$(tput setaf 1)fortsh$(tput sgr0)> "
# Does cursor position correctly?
```

**Potential Issue:**
If fortsh counts escape codes in width:
```
fortsh> ls<cursor>
       ^-- cursor 7 chars over (wrong!)

Should be:
fortsh> ls<cursor>
        ^-- cursor 3 chars over (right!)
```

**Why Critical:**
- Cursor positioning incorrect
- Multi-line prompts broken
- Text overwrites prompt

**Fix Effort:** ⭐⭐ LOW-MEDIUM
- Strip ANSI codes when calculating width
- Use state machine to track escape sequences

---

## ⚠️ MODERATE GAPS (Quality of Life)

### 5. Job Spec Parsing

**What bash/zsh/fish do:**
```bash
$ sleep 100 &
[1] 12345
$ sleep 200 &
[2] 12346

$ fg %1      # Job 1
$ fg %%      # Current job (most recent)
$ fg %+      # Current job (same as %%)
$ fg %-      # Previous job
$ fg %?sle   # Job with 'sle' in command
$ fg %2      # Job 2
```

**What fortsh supports:**
```bash
# Need to test:
$ fg         # ✓ Probably works (default job)
$ bg         # ✓ Probably works
$ fg %1      # ❓ Needs testing
$ fg %%      # ❓ Needs testing
```

**Why Moderate:**
- Job control works without specs (fg/bg alone)
- Power users expect full syntax
- POSIX compliance

**Fix Effort:** ⭐⭐ MEDIUM
- Parse % syntax in fg/bg commands
- Match job by number, current, previous
- Add %?string pattern matching

---

### 6. Terminal Title Setting

**What bash/zsh/fish do:**
```bash
# Bash sets terminal title:
PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"'

# Terminal title shows: user@host:/path
```

**Terminal sequences:**
```
ESC]0;title BEL    # Set icon + window title
ESC]1;title BEL    # Set icon title
ESC]2;title BEL    # Set window title
```

**What fortsh does:**
```
❓ UNKNOWN - needs testing
```

**User Impact:**
```
Terminal tab shows:
bash:    "user@host:/home/user"
fortsh:  "fortsh" or "Terminal" (default)
```

**Why Moderate:**
- Doesn't affect functionality
- Nice for tab management
- User expectation

**Fix Effort:** ⭐ LOW
- Send OSC sequence after each command
- Format: `$USER@$HOST:$PWD`

---

### 7. Terminal Type Adaptation

**What bash/zsh/fish do:**
```bash
# Check $TERM
case $TERM in
  dumb|unknown)
    # Disable colors, fancy features
    ;;
  xterm*|screen*|tmux*)
    # Enable full features
    ;;
esac
```

**What fortsh does:**
```
❓ UNKNOWN - likely assumes ANSI always works
```

**User Impact:**
```bash
# On dumb terminal (emacs shell):
bash:   Clean output, no colors
fortsh: Garbage escape codes like ^[[31m
```

**Why Moderate:**
- 99% of terminals support ANSI
- Edge case: Emacs shell, serial console
- Graceful degradation expected

**Fix Effort:** ⭐⭐ MEDIUM
- Check `$TERM` environment variable
- Disable colors if dumb/unknown
- Optional: Query terminfo database

---

## 📉 MINOR GAPS (Advanced Features)

### 8. Alternative Screen Buffer

**What vim/less do:**
```
Enter vim:
  ESC[?1049h    # Save screen, switch to alt buffer
Exit vim:
  ESC[?1049l    # Restore original screen
```

**What shells do:**
- Most shells don't use this
- Feature for TUI apps (vim, less, htop)

**fortsh:**
```
❌ NOT NEEDED for basic shell
```

**Potential Use:**
- Full-screen file browser (`Ctrl-O`?)
- Interactive menu system
- Built-in pager

**Fix Effort:** ⭐ LOW (if needed)
- Send escape sequences
- Manage buffer state

---

### 9. Mouse Support

**What some shells do:**
```bash
# fish has limited mouse support
# Click to position cursor (fish 3.2+)

ESC[?1000h  # Enable mouse tracking
ESC[?1006h  # SGR extended coordinates
```

**fortsh:**
```
❌ NOT IMPLEMENTED (not expected in shell)
```

**User Impact:**
- Cannot click to position cursor
- No scroll wheel in readline
- **NOT a standard shell feature**

**Fix Effort:** ⭐⭐⭐ HIGH
- Complex protocol parsing
- State management
- Questionable value

---

### 10. True Color (24-bit RGB)

**What modern shells do:**
```bash
# 256 color (older):
echo -e "\e[38;5;196mRed\e[0m"

# True color (modern):
echo -e "\e[38;2;255;0;0mRed\e[0m"
```

**fortsh:**
```
❓ UNKNOWN - likely passes through

$ echo -e "\e[38;2;255;0;0mTRUE COLOR\e[0m"
# Does this work?
```

**User Impact:**
- Limited color palette for themes
- Syntax highlighting less vibrant

**Fix Effort:** ⭐ VERY LOW
- Likely already works (pass-through)
- Just document support

---

### 11. Synchronized Output (DEC Private Mode 2026)

**What it does:**
```bash
# Enable synchronized output
ESC[?2026h

# Start buffered region
ESC[?2026$p
# ... output commands ...
ESC[?2026$q
# Flush to screen atomically

# Disable
ESC[?2026l
```

**Use Case:**
- Prevents tearing with concurrent output
- Multiple background jobs writing

**fortsh:**
```
❌ NOT IMPLEMENTED (very new feature)
```

**User Impact:**
- Minimal (rarely needed)
- Edge case: parallel command output

**Fix Effort:** ⭐ LOW (if needed)

---

## 🔬 NEEDS TESTING

These require hands-on testing in fortsh:

### Test 1: Color Prompt Width
```bash
PS1='\[\e[31m\]fortsh\[\e[0m\]$ '
# Type long command, observe cursor position
# Does it account for invisible escape codes?
```

### Test 2: Multi-line Prompt
```bash
PS1='Line 1\nLine 2> '
# Does prompt render correctly?
# Cursor on correct line?
```

### Test 3: Window Resize During Input
```bash
$ echo "Long command here"
# Resize window
# Continue typing
# Does readline adapt?
```

### Test 4: Job Specs
```bash
$ sleep 100 &
$ sleep 200 &
$ fg %1    # Does this work?
$ fg %%    # Current job?
$ fg %-    # Previous job?
```

### Test 5: UTF-8 / Emoji
```bash
$ echo "Hello 👋 World 🌍"
# Displays correctly?

$ PS1="🚀 "
# Prompt width calculated correctly?
```

### Test 6: Paste Multi-line
```bash
# Paste this:
for i in 1 2 3; do
  echo $i
done
# Does it execute immediately or wait?
```

### Test 7: Terminal Title
```bash
# Check terminal tab/window title
# Does it show anything custom?
# Or just "fortsh" / "Terminal"?
```

### Test 8: Background Job Output
```bash
$ { sleep 1; echo "BG OUTPUT"; } &
# Does output appear?
# Is it garbled / interfere with prompt?
```

---

## 📊 Gap Priority Matrix

| Feature | User Impact | Frequency | Standard? | Priority |
|---------|------------|-----------|-----------|----------|
| **Bracketed paste** | HIGH | High | Yes | 🔴 CRITICAL |
| **Window size** | HIGH | Medium | Yes | 🔴 CRITICAL |
| **SIGWINCH** | HIGH | Medium | Yes | 🔴 CRITICAL |
| **Prompt width** | MEDIUM | Constant | Yes | 🟡 HIGH |
| Job specs | MEDIUM | Low | Yes | 🟡 MEDIUM |
| Terminal title | LOW | Constant | No | 🟢 LOW |
| Terminal type | LOW | Rare | Yes | 🟢 LOW |
| Alt screen | NONE | Never | No | ⚪ SKIP |
| Mouse | NONE | Never | No | ⚪ SKIP |
| True color | LOW | Constant | No | 🟢 LOW |

---

## 🎯 Recommended Testing Plan

### Phase 1: Document Current Behavior (1-2 hours)
1. Test all scenarios in "NEEDS TESTING"
2. Record actual vs expected behavior
3. Update audit document

### Phase 2: Quick Wins (2-4 hours)
1. Add `TIOCGWINSZ` ioctl binding
2. Implement SIGWINCH handler
3. Test window resize behavior

### Phase 3: Bracketed Paste (4-6 hours)
1. Send enable sequence on startup
2. Parse paste markers in readline
3. Buffer pasted text
4. Test multi-line paste

### Phase 4: Polish (4-6 hours)
1. Fix prompt width calculation
2. Implement job spec parsing
3. Add terminal title updates

---

## 🏁 Conclusion

**fortsh is remarkably close to standard shell behavior!**

**Critical gaps:** 3 items (bracketed paste, window size, SIGWINCH)
**Medium gaps:** 4 items (prompt width, job specs, title, term type)
**Minor gaps:** 4 items (alt screen, mouse, true color, sync output)

**Estimated effort to reach parity:** 15-20 hours

**Best ROI:**
1. Window size + SIGWINCH (2-3 hours) → fixes resize issues
2. Bracketed paste (4-6 hours) → huge UX improvement
3. Prompt width (2-3 hours) → fixes common annoyance

**Total for "feels like bash":** ~10 hours of focused work

The terminal integration foundation is already excellent - just needs polish!
