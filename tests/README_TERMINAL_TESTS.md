# Terminal Integration Test Suite

Comprehensive test suite for fortsh terminal standardization features.

## Overview

This test suite validates all 6 phases of terminal standardization implemented in fortsh:

- **Phase 1**: Window Size Detection & SIGWINCH
- **Phase 2**: Bracketed Paste Mode
- **Phase 3**: Prompt Width Calculation
- **Phase 4**: Job Specs & Terminal Title
- **Phase 5**: Terminal Type Adaptation
- **Phase 6**: Polish & Optional Features (UTF-8, True Color)

## Test Files

### `terminal_integration_tests.sh`
**Automated tests** that can run in CI/CD environments.

```bash
# Run all automated tests
./tests/terminal_integration_tests.sh

# Set custom fortsh binary
FORTSH=./bin/fortsh ./tests/terminal_integration_tests.sh
```

**What it tests:**
- ✅ Environment variables (`$COLUMNS`, `$LINES`)
- ✅ Terminal type detection (`TERM=dumb`, `TERM=xterm`, etc.)
- ✅ UTF-8 character handling
- ✅ True color pass-through
- ✅ Integration across phases

**Limitations:**
- Cannot test interactive features (paste, job control, resize)
- Cannot verify visual output (colors, cursor positioning)
- Runs in non-interactive mode (`-c` flag)

### `terminal_interactive_tests.sh`
**Manual tests** requiring user interaction.

```bash
# Run interactive test menu
./tests/terminal_interactive_tests.sh

# Run all tests sequentially
./tests/terminal_interactive_tests.sh --all
```

**What it tests:**
- ✅ Bracketed paste mode (multi-line paste behavior)
- ✅ Window resize (SIGWINCH) handling
- ✅ Colored prompts & cursor positioning
- ✅ Job control & job specs (`%%`, `%-`, `%1`, `%?string`)
- ✅ Terminal title updates
- ✅ UTF-8 wide character cursor positioning

**Menu Options:**
1. Bracketed Paste Mode
2. Window Resize (SIGWINCH)
3. Colored Prompts & Cursor Positioning
4. Job Control & Job Specs
5. Terminal Title Updates
6. UTF-8 Wide Characters
7. Run ALL tests
0. Exit

## Quick Start

### Run Automated Tests

```bash
# Build fortsh first
make clean && make

# Run automated test suite
./tests/terminal_integration_tests.sh
```

Expected output:
```
╔══════════════════════════════════════════════════════════════╗
║    Terminal Integration Test Suite for fortsh               ║
╚══════════════════════════════════════════════════════════════╝

fortsh binary: ./bin/fortsh
Test output: /tmp/tmp.XXXXXXXXXX

═══ Phase 1: Window Size Detection & SIGWINCH ═══

[TEST 1] Window size: COLUMNS env var set
  ✓ PASS
[TEST 2] Window size: LINES env var set
  ✓ PASS
...
═══════════════════════════════════════════════════
Test Summary
═══════════════════════════════════════════════════

Total tests run:    21
Passed:             15
Failed:             0
Skipped:            6

✓ ALL TESTS PASSED!
```

### Run Interactive Tests

```bash
# Launch interactive test menu
./tests/terminal_interactive_tests.sh
```

Follow on-screen instructions for each test.

## Test Coverage Matrix

| Phase | Feature | Automated | Interactive | Manual |
|-------|---------|-----------|-------------|--------|
| 1 | Window size env vars | ✅ | ✅ | - |
| 1 | SIGWINCH handling | - | ✅ | - |
| 2 | Bracketed paste mode | - | ✅ | - |
| 2 | Paste marker detection | - | ✅ | - |
| 3 | ANSI code width calc | ✅ | ✅ | - |
| 3 | Multi-line prompts | ✅ | ✅ | - |
| 4 | Job spec %% (current) | - | ✅ | - |
| 4 | Job spec %- (previous) | - | ✅ | - |
| 4 | Job spec %n (number) | - | ✅ | - |
| 4 | Job spec %?string | - | ✅ | - |
| 4 | Terminal title OSC | - | ✅ | - |
| 5 | TERM=dumb detection | ✅ | - | - |
| 5 | Color disabling | ✅ | - | - |
| 6 | UTF-8 emoji | ✅ | ✅ | - |
| 6 | UTF-8 CJK | ✅ | ✅ | - |
| 6 | UTF-8 wide width | ✅ | ✅ | - |
| 6 | True color RGB | ✅ | - | - |

**Legend:**
- ✅ = Fully tested
- - = Not applicable / Cannot test automatically

## Test Results Interpretation

### Automated Tests

**PASS**: Feature working correctly
- Green ✓ checkmark
- Increments pass counter

**FAIL**: Feature not working
- Red ✗ mark with error message
- Increments fail counter
- Test suite exits with code 1

**SKIP**: Test cannot run in current environment
- Yellow ⊘ mark with reason
- Increments skip counter
- Examples: interactive features, terminal-specific tests

### Interactive Tests

User manually verifies behavior and responds with `y/N`:
- `y` = Test passed (feature works)
- `N` = Test failed (feature broken)

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Terminal Tests

on: [push, pull_request]

jobs:
  terminal-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build fortsh
        run: make
      - name: Run terminal integration tests
        run: ./tests/terminal_integration_tests.sh
```

### Expected Results in CI

In CI environments (non-interactive), many tests will **SKIP**:
- Bracketed paste (requires terminal)
- SIGWINCH (requires resize event)
- Job control (requires interactive mode)
- Terminal title (requires real terminal)

This is **normal and expected**. The automated tests focus on:
- Environment variable correctness
- Terminal type detection logic
- UTF-8 handling
- Output correctness

## Troubleshooting

### "fortsh binary not found"

```bash
# Build fortsh first
make clean && make

# Or specify path
FORTSH=/path/to/fortsh ./tests/terminal_integration_tests.sh
```

### "Test skipped: Requires interactive mode"

This is normal for automated tests. Run interactive tests instead:

```bash
./tests/terminal_interactive_tests.sh
```

### Interactive tests don't work

Ensure you're in a real terminal (not CI):
```bash
# Check if terminal
if [[ -t 0 ]]; then echo "Terminal"; else echo "Not a terminal"; fi
```

### Colors not showing in output

Check `$TERM`:
```bash
echo $TERM  # Should be xterm-256color or similar
```

If `TERM=dumb`, colors are intentionally disabled (this is correct behavior).

## Adding New Tests

### Automated Test Template

```bash
test_start "My new feature"
output=$(run_fortsh 'echo "test"')
if assert_equals "test" "$output"; then
    test_pass
else
    test_fail "Feature broken"
fi
```

### Interactive Test Template

```bash
test_my_feature() {
    test_section "Test: My Feature"

    cat <<EOF
${BOLD}This test verifies my feature.${RESET}

Instructions:
1. Do something
2. Verify behavior
3. Type 'exit'
EOF

    prompt_user "Ready to test?"
    FORTSH_RC_FILE=/dev/null "$FORTSH"

    read -p "Did it work? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Test PASSED${RESET}"
    else
        echo -e "${RED}✗ Test FAILED${RESET}"
    fi
}
```

## Test Development Guidelines

1. **Keep automated tests fast** - No sleep, no timeouts
2. **Make interactive tests clear** - Explicit instructions
3. **Test one thing at a time** - Focused, isolated tests
4. **Document expected behavior** - What should happen
5. **Handle both pass and fail** - Don't assume success

## Related Documentation

- `TARGET/01_TERMINAL_STANDARDS.md` - Background on terminal standards
- `TARGET/02_CURRENT_STATE_AUDIT.md` - Initial capability audit
- `TARGET/03_GAP_ANALYSIS.md` - Gap priority matrix
- `TARGET/04_IMPLEMENTATION_ROADMAP.md` - Implementation phases

## License

Same as fortsh project.

## Contributing

When adding new terminal features:

1. Write automated tests first (if possible)
2. Add interactive tests for visual/behavioral features
3. Update this README with new test coverage
4. Run full test suite before committing
