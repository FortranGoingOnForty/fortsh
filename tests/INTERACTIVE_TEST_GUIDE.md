# Interactive Testing Guide for fortsh

Quick guide to manually test the 7 features that require interactive mode.

## Running the Interactive Test Suite

```bash
# Launch the interactive test menu
./tests/terminal_interactive_tests.sh

# You'll see a menu:
# 1) Bracketed Paste Mode
# 2) Window Resize (SIGWINCH)
# 3) Colored Prompts & Cursor Positioning
# 4) Job Control & Job Specs
# 5) Terminal Title Updates
# 6) UTF-8 Wide Characters
# 7) Run ALL tests
# 0) Exit
```

## Quick Manual Tests (Without the Script)

If you want to quickly test features manually, here's what to do:

### 1. Test Bracketed Paste Mode

```bash
# Start fortsh
./bin/fortsh

# Copy this multi-line code:
for i in 1 2 3; do
  echo "Number: $i"
done

# Paste it into fortsh
# ✅ PASS: The entire block appears without executing immediately
# ✗ FAIL: Each line executes as you paste it

# Press Enter to execute
# Type: exit
```

### 2. Test Window Resize (SIGWINCH)

```bash
# Start fortsh
./bin/fortsh

# Check initial size
echo $COLUMNS $LINES

# Resize your terminal window (drag corner or maximize)

# Check size again
echo $COLUMNS $LINES

# ✅ PASS: Values changed to match new window size
# ✗ FAIL: Values stayed the same

# Type: exit
```

### 3. Test Colored Prompts & Cursor Positioning

```bash
# Start fortsh with colored prompt
./bin/fortsh

# Set a colored prompt (once inside fortsh)
PS1='\[\e[1;32m\]fortsh\[\e[0m\]> '

# Type a very long command that wraps multiple lines
echo "This is a very long command that should wrap across multiple lines when the terminal width is narrow and we keep typing and typing"

# Use arrow keys to move cursor around

# ✅ PASS: Cursor stays in correct position, no visual glitches
# ✗ FAIL: Cursor jumps around, text overwrites prompt

# Type: exit
```

### 4. Test Job Control & Job Specs

```bash
# Start fortsh
./bin/fortsh

# Start two background jobs
sleep 100 &
sleep 200 &

# List jobs
jobs

# Test job spec %%  (current job - most recent)
fg %%
# Press Ctrl-Z to suspend

# Test job spec %-  (previous job)
fg %-
# Press Ctrl-Z to suspend

# Test job spec %1  (job number 1)
fg %1
# Press Ctrl-C to kill

# Test job spec %?sleep  (search for "sleep" in command)
fg %?sleep
# Press Ctrl-C to kill

# ✅ PASS: All job specs work correctly
# ✗ FAIL: Job specs don't work or error

# Clean up any remaining jobs
kill %1 %2
exit
```

### 5. Test Terminal Title Updates

```bash
# BEFORE starting fortsh:
# Look at your terminal window/tab title - note what it says

# Start fortsh
./bin/fortsh

# Check if title changed
# ✅ PASS: Title now shows "user@host:/path/to/dir"
# ✗ FAIL: Title still shows "Terminal" or "bash" or unchanged

# Change directory
cd /tmp

# Check title again
# ✅ PASS: Title updated to show "user@host:/tmp"
# ✗ FAIL: Title didn't update

# Type: exit
```

### 6. Test UTF-8 Wide Characters

```bash
# Start fortsh
./bin/fortsh

# Test emoji display
echo "🚀 Rocket emoji"
# ✅ PASS: Emoji displays correctly

# Test CJK characters
echo "中文字"
# ✅ PASS: Chinese characters display correctly

# Test cursor positioning with wide chars
PS1="🚀 > "
echo "test"
# Type a long command and use arrow keys

# ✅ PASS: Cursor positions correctly with emoji in prompt
# ✗ FAIL: Cursor is off by 1-2 positions (counting emoji as 1 char instead of 2)

# Type: exit
```

## Expected Results

All 6 interactive tests should **PASS**. Here's what each validates:

| Test | What It Validates | Implementation |
|------|-------------------|----------------|
| Bracketed Paste | Multi-line paste buffering | Phase 2 - ESC[200~ markers |
| SIGWINCH | Terminal resize detection | Phase 1 - Signal handler |
| Colored Prompts | Visual length calculation | Phase 3 - ANSI parsing |
| Job Specs | Job control syntax | Phase 4 - %%, %-, %n, %?str |
| Terminal Title | OSC title updates | Phase 4 - ESC]0;...BEL |
| UTF-8 Wide Chars | Character width detection | Phase 6 - utf8_char_width() |

## Quick Automated Tests (No Interaction Needed)

If you just want to verify the automated tests work:

```bash
# Run automated test suite (30 seconds)
./tests/terminal_integration_tests.sh

# Expected result:
# Total tests run:    23
# Passed:             16
# Failed:             0
# Skipped:            7
# ✓ ALL TESTS PASSED!
```

## Testing Individual Features

### Just test bracketed paste:
```bash
./tests/terminal_interactive_tests.sh
# Choose: 1
```

### Just test SIGWINCH:
```bash
./tests/terminal_interactive_tests.sh
# Choose: 2
```

### Run all interactive tests sequentially:
```bash
./tests/terminal_interactive_tests.sh --all
```

## Common Issues

### Bracketed paste not working
- **Issue**: Pasted code executes line-by-line
- **Fix**: Your terminal may not support bracketed paste. Try iTerm2, modern terminals.

### SIGWINCH not updating
- **Issue**: $COLUMNS/$LINES don't change after resize
- **Fix**: Make sure you're in a real terminal, not a CI environment

### Terminal title not showing
- **Issue**: Title doesn't update or shows "Terminal"
- **Fix**: Some terminals ignore OSC sequences. Try iTerm2, gnome-terminal, or xterm

### UTF-8 cursor positioning off
- **Issue**: Cursor is 1-2 positions off with emoji
- **Fix**: This was the bug we fixed! If still broken, file an issue.

## Video Demo Recording

To record a demo of all tests passing:

```bash
# Use 'script' command to record terminal session
script -q test_session.log

# Run all interactive tests
./tests/terminal_interactive_tests.sh --all

# Exit recording
exit

# View recording
cat test_session.log
```

## CI/CD Note

Interactive tests **cannot** run in CI/CD pipelines because they require:
- Real terminal (not a pipe)
- User interaction
- Visual verification

For CI/CD, use the automated suite:
```bash
./tests/terminal_integration_tests.sh
```

This runs 16 automated tests that don't require interaction.
