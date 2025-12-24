# fortsh Interactive Test Framework

Automated testing framework for fortsh's interactive features using Python and pexpect.

## Quick Start

```bash
# Activate the virtual environment
source tests/interactive/.venv/bin/activate

# Run all YAML spec tests
python tests/interactive/run_tests.py

# Run with specific fortsh binary
python tests/interactive/run_tests.py --fortsh ./bin/fortsh

# Run pytest tests
python tests/interactive/run_tests.py --pytest

# Generate markdown report
python tests/interactive/run_tests.py --report manual/results/$(date +%Y%m%d).md
```

## Directory Structure

```
tests/interactive/
├── run_tests.py              # Main test runner
├── fortsh_pty.py             # PTY management class
├── conftest.py               # Pytest fixtures
├── requirements.txt          # Python dependencies
├── test_specs/               # YAML test specifications
│   ├── line_editing.yaml     # Line editing tests (49 tests)
│   ├── history.yaml          # History navigation/expansion (37 tests)
│   ├── completion.yaml       # Tab completion tests (37 tests)
│   ├── signals_jobs.yaml     # Signals and job control (40 tests)
│   ├── prompt_display.yaml   # Prompt and display tests (39 tests)
│   └── posix.yaml            # POSIX shell features (119 tests)
├── utils/
│   ├── keys.py               # Key sequence definitions
│   └── matchers.py           # Output matching utilities
├── manual/
│   └── results/              # Test result reports
└── README.md                 # This file
```

## Writing Tests

### YAML Specification Format

Tests can be defined declaratively in YAML:

```yaml
metadata:
  category: "Line Editing"
  description: "Tests for cursor movement"

tests:
  - name: "Left arrow moves cursor back"
    steps:
      - send: "echo test"
      - send_key: "Left"
      - send_key: "Left"
      - send: "X"
      - send_key: "Enter"
    expect_output: "teXst"
    match_type: "contains"
```

#### Available Step Types

| Step | Description | Example |
|------|-------------|---------|
| `send` | Send text without newline | `send: "echo hello"` |
| `send_line` | Send text with Enter | `send_line: "echo hello"` |
| `send_key` | Send special key | `send_key: "C-a"` |
| `send_keys` | Send multiple keys | `send_keys: ["Left", "Left"]` |
| `wait` | Sleep for seconds | `wait: 0.5` |
| `wait_for_prompt` | Wait for shell prompt | `wait_for_prompt: true` |
| `expect` | Wait for pattern | `expect: "hello"` |
| `resize` | Change terminal size | `resize: {rows: 40, cols: 120}` |

#### Match Types

| Type | Description |
|------|-------------|
| `exact` | Exact match (after strip) |
| `contains` | Substring match |
| `regex` | Regular expression |
| `startswith` | Prefix match |
| `endswith` | Suffix match |

### Pytest Tests

For complex tests, use Python with pytest fixtures:

```python
import pytest

@pytest.mark.line_editing
def test_ctrl_a_moves_to_beginning(fortsh):
    fortsh.send("hello world")
    fortsh.send_key("C-a")
    fortsh.send("echo ")
    fortsh.send_key("Enter")
    output = fortsh.wait_for_prompt()
    assert "hello world" in output
```

#### Available Fixtures

- `fortsh` - Running fortsh session (rc disabled)
- `fortsh_with_rc` - Session with user's .fortshrc
- `fortsh_factory` - Create multiple sessions
- `fortsh_path` - Path to fortsh binary

## Key Sequences

Common keys are defined in `utils/keys.py`:

```python
# Control keys
"C-a"  # Beginning of line
"C-e"  # End of line
"C-k"  # Kill to end
"C-u"  # Kill to beginning
"C-w"  # Kill word
"C-y"  # Yank
"C-c"  # Interrupt
"C-z"  # Suspend
"C-d"  # EOF/Delete
"C-r"  # Reverse search

# Alt/Meta keys
"M-b"  # Back word
"M-f"  # Forward word

# Arrow keys
"Up", "Down", "Left", "Right"

# Special
"Tab", "Enter", "Backspace", "Delete"
"Home", "End", "PageUp", "PageDown"
```

## Test Categories

Tests are organized by feature (total 321 tests):

1. **POSIX Shell Features** (120+ tests)
   - Basic operations
   - Quoting and escaping
   - Variables and expansion
   - Pipelines and redirections
   - Control structures (if/for/while/case)
   - Functions and arithmetic
   - Builtins

2. **Line Editing** (49 tests)
   - Cursor movement
   - Text modification
   - Kill ring operations
   - Word operations

3. **History** (37 tests)
   - Arrow key navigation
   - Ctrl+R search
   - History expansion (!!, !$, etc.)

4. **Completion** (37 tests)
   - Command completion
   - Path/file completion
   - Variable completion

5. **Signals & Job Control** (40 tests)
   - SIGINT (Ctrl+C)
   - SIGTSTP (Ctrl+Z)
   - Background jobs
   - Job specs (%n, %%, %+)
   - fg/bg/jobs builtins

6. **Prompt & Display** (39 tests)
   - PS1/PS2 escapes
   - Terminal resize
   - Colors and Unicode

## Running Specific Tests

```bash
# Run single spec file
python tests/interactive/run_tests.py --spec line_editing.yaml

# Run pytest with markers
pytest tests/interactive -m line_editing
pytest tests/interactive -m "not slow"

# Run with verbose output
python tests/interactive/run_tests.py -v
```

## Environment Variables

- `FORTSH` - Path to fortsh binary
- `FORTSH_RC_FILE` - Override rc file path

## Adding New Tests

### 1. Add to existing YAML spec

```yaml
# In test_specs/line_editing.yaml
tests:
  - name: "My new test"
    steps:
      - send_line: "echo test"
    expect_output: "test"
```

### 2. Create new YAML spec

```bash
# Create tests/interactive/test_specs/my_feature.yaml
```

### 3. Add pytest test

```python
# Create tests/interactive/test_my_feature.py

def test_my_feature(fortsh):
    output = fortsh.run_command("echo hello")
    assert "hello" in output
```

## CI Integration

For GitHub Actions with tmux:

```yaml
- name: Run interactive tests
  run: |
    tmux new-session -d -s test
    tmux send-keys -t test "python tests/interactive/run_tests.py" Enter
    sleep 60
    tmux capture-pane -t test -p > test_output.txt
    grep -q "ALL TESTS PASSED" test_output.txt
```

## Troubleshooting

### "fortsh binary not found"

```bash
# Build fortsh first
make clean && make

# Or specify path
python tests/interactive/run_tests.py --fortsh /path/to/fortsh
```

### Test timeouts

Increase timeout in test or PTY initialization:

```python
pty = FortshPTY(timeout=10.0)  # 10 seconds
```

### Debugging tests

```python
# In pytest test
def test_debug(fortsh):
    fortsh.send_line("echo hello")
    import time; time.sleep(5)  # Pause to observe
    output = fortsh.wait_for_prompt()
    print(f"Output: {output}")  # Will show with -s flag
```

Run with:
```bash
pytest tests/interactive -s --tb=long
```

## Dependencies

- Python 3.8+
- pexpect >= 4.8
- PyYAML >= 6.0
- pytest >= 7.0
- colorama >= 0.4

Install with:
```bash
pip install -r tests/interactive/requirements.txt
```
