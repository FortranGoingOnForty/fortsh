# Interactive Test Expansion - Quick Reference

## Current State
- **Interactive Tests**: 321 tests (72.6% pass rate)
- **Non-Interactive Tests**: ~656 POSIX compliance tests
- **Coverage Gap**: ~335 tests (mostly edge cases and builtin testing)

## What We're Missing

### 1. Edge Case Coverage (~200 tests)
From `posix_compliance_gaps.sh` (180 tests):
- Parameter expansion edge cases (nested, complex patterns)
- Builtin edge cases (set, shift, eval, return, break/continue)
- Quoting and escaping complexity
- Here-document variations (<<-, <<EOF)
- Function scope and recursion
- Special parameter edge cases ($@, $*, IFS interactions)
- Redirection edge cases (<>, append with FD)

### 2. Interactive-Specific Depth (~150 tests)
Areas where we have basic tests but need edge cases:
- **Line Editing**: Undo, macros, very long lines, Unicode edge cases
- **History**: File operations, size limits, multi-line commands, sharing
- **Completion**: Programmable completion, special chars, long lists, context-sensitive
- **Job Control**: Multiple job specs, notification timing, wait variants

### 3. Cross-Feature Interactions (~100 tests)
Combinations that reveal bugs:
- Editing + History (edit recalled command, Ctrl+R while editing)
- Completion + Variables (complete with spaces, inside ${VAR[TAB]})
- Job Control + Signals (Ctrl+C during completion, notification while editing)
- Prompt + Escape Sequences (command substitution in prompt, resize behavior)

### 4. Error Handling & Resources (~80 tests)
- Input edge cases (binary input, invalid UTF-8, very fast typing)
- Output edge cases (> buffer size, control chars, broken pipe)
- Resource limits (max history, FD exhaustion, process limits)
- Error recovery (undefined HOME/PATH, terminal errors)

## How to Expand

### Quick Wins (Easiest First)

#### 1. Use the Converter Tool (30 minutes)
```bash
# Convert simple tests from POSIX suite
cd tests/interactive
.venv/bin/python utils/convert_posix_tests.py \
  ../../fortsh/tests/posix_compliance_test.sh \
  test_specs/posix_basic_converted.yaml

# Review and fix MANUAL_REVIEW items
# Most echo commands auto-convert well
```

**Expected**: ~60-80 usable tests from the 96 in posix_compliance_test.sh

#### 2. Hand-Craft Edge Cases (2-3 hours)
Pick 30-40 edge cases from `posix_compliance_gaps.sh` that are interesting:
```yaml
# Example: Builtin edge cases
- name: "shift with no arguments uses $@"
  steps:
    - send_line: "set -- a b c"
    - send_line: "shift"
    - send_line: "echo $@"
  expect_output: "b c"

- name: "shift beyond available args is error"
  steps:
    - send_line: "set -- a"
    - send_line: "shift 2; echo $?"
  expect_output: "1"

- name: "eval with empty string"
  steps:
    - send_line: "eval ''; echo $?"
  expect_output: "0"
```

#### 3. Extend Existing Categories (1-2 hours)
Add variations to existing tests:
```yaml
# In history.yaml, add:
- name: "History with very long command (>1000 chars)"
  steps:
    - send_line: "echo <1000 char string>"
    - send_key: "Up"
  expect_output: "<verify it appears>"

# In completion.yaml, add:
- name: "Complete filename with spaces and quotes"
  steps:
    - send: "ls 'file with "
    - send_key: "Tab"
  expect_output: "file with spaces.txt"
```

### Medium Effort (More Time Investment)

#### 4. Create New Spec Files (3-4 hours each)
Add comprehensive coverage for specific areas:

**test_specs/builtins_edge_cases.yaml**:
- All edge cases for cd, set, shift, eval, return, break, continue
- Readonly and unset interactions
- Alias edge cases
- getopts comprehensive testing

**test_specs/parameter_expansion_advanced.yaml**:
- Nested parameter expansion
- All pattern matching variations (%, %%, #, ##)
- Substring operations
- Complex default/assign/error patterns

**test_specs/cross_feature_interactions.yaml**:
- Editing while history search active
- Completion during variable expansion
- Job control notification during prompt display
- Signal handling during different interactive states

### Tools We Created

1. **convert_posix_tests.py**
   - Parses `compare_posix_output` calls from shell scripts
   - Generates YAML test specs
   - Marks complex cases for manual review
   - ~60-70% of tests auto-convert successfully

2. **Session Reuse Framework**
   - Reuses PTY sessions (10 tests per session)
   - Automatic reset between tests
   - Handles ~300+ tests without resource exhaustion

## Recommended Priorities

### Phase 1: Foundation (Week 1) - Target: +100 tests
1. Convert basic POSIX tests (echo, variables, simple commands)
2. Add builtin edge cases (shift, set, eval - highest value)
3. Extend parameter expansion tests

**Outcome**: 421 tests (~74% pass rate expected)

### Phase 2: Interactive Depth (Week 2) - Target: +80 tests
1. Line editing edge cases (long lines, Unicode, special chars)
2. History edge cases (multi-line, file operations, size limits)
3. Completion improvements (special chars, long lists)

**Outcome**: 501 tests (~73% pass rate expected, interactive-specific may reveal bugs)

### Phase 3: Interactions & Edge Cases (Week 3) - Target: +70 tests
1. Cross-feature interaction tests
2. Job control comprehensive testing
3. Error handling and resource limit tests

**Outcome**: 571 tests (~72% pass rate expected)

### Phase 4: Coverage Complete (Week 4) - Target: +80 tests
1. Remaining POSIX gaps conversions
2. Stress and performance tests
3. Documentation and CI integration

**Outcome**: 650+ tests (parity with non-interactive suite)

## Quick Start Example

Here's how to add 10 new tests in 15 minutes:

1. **Pick a category** (e.g., "shift builtin edge cases")

2. **Create tests** in existing spec or new file:
```bash
# Add to test_specs/posix.yaml or create test_specs/builtins.yaml
```

3. **Write 10 variations**:
```yaml
- name: "shift no args"
  steps:
    - send_line: "set -- a b; shift; echo $@"
  expect_output: "b"

- name: "shift with count"
  steps:
    - send_line: "set -- a b c; shift 2; echo $@"
  expect_output: "c"

- name: "shift all"
  steps:
    - send_line: "set -- a; shift; echo $#"
  expect_output: "0"

# ... 7 more variations
```

4. **Run tests**:
```bash
tests/interactive/.venv/bin/python tests/interactive/run_tests.py \
  --fortsh ../fortsh/bin/fortsh --spec builtins.yaml
```

5. **Fix failures** and commit.

## Metrics

**Time Estimates**:
- Convert 100 tests: ~2 hours (with converter)
- Hand-write 50 tests: ~3 hours
- Review/fix converted tests: ~1 hour per 50 tests
- **Total for 500+ test expansion**: ~20-25 hours

**Expected Outcomes**:
- **Coverage**: Match non-interactive test count (650+)
- **Pass Rate**: 70-75% (some new tests will reveal bugs)
- **Quality**: Better edge case coverage
- **Maintenance**: Easier to identify gaps

## Resources

- **Expansion Plan**: `EXPANSION_PLAN.md` (detailed strategy)
- **Converter Tool**: `utils/convert_posix_tests.py`
- **Non-Interactive Tests**: `../../fortsh/tests/posix_compliance*.sh`
- **Current Tests**: `test_specs/*.yaml`
