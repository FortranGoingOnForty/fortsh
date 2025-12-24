# Interactive Test Expansion Plan

## Current State
- **Interactive tests**: 321 tests (72.6% pass rate)
- **Non-interactive tests**: ~656 test assertions across POSIX compliance suite
- **Gap**: Interactive tests lack edge case coverage and comprehensive builtin testing

## Analysis of Non-Interactive Test Coverage

### Categories in Non-Interactive Tests
1. **posix_compliance_test.sh** (101 tests) - Basic POSIX features
   - Commands, variables, parameter expansion, command substitution
   - Arithmetic, redirections, pipelines, conditionals, loops
   - Functions, special parameters, builtins

2. **posix_compliance_extended.sh** (119 tests) - Extended features
   - Advanced parameter expansion, globbing patterns
   - Complex redirections, subshells, job control
   - Advanced arithmetic, error handling

3. **posix_compliance_advanced.sh** (119 tests) - Advanced features
   - Complex quoting, nested structures
   - Advanced control flow, signal handling
   - Performance edge cases

4. **posix_compliance_gaps.sh** (180 tests) - Edge cases
   - Here-document tab stripping, complex IFS splitting
   - Function recursion, readonly/unset interactions
   - Builtin edge cases (set, shift, eval, return, etc.)
   - Alias, getopts, umask, hash, type, times, trap
   - Empty/whitespace edge cases

5. **posix_compliance_coverage.sh** (100 tests) - Coverage gaps
   - Untested combinations, boundary conditions

6. **posix_compliance_untested.sh** (37 tests) - Known gaps

## Expansion Strategy

### Phase 1: Port Non-Interactive Tests (Target: +300 tests)

Many non-interactive tests can be adapted to interactive mode by:
1. Sending commands instead of using `-c` flag
2. Waiting for output instead of capturing stdout
3. Grouping related tests for session reuse

**Approach**: Create a converter script/tool to semi-automate this:
```python
# Example: Convert from
compare_posix_output "echo simple" "echo hello"

# To YAML:
- name: "echo simple"
  steps:
    - send_line: "echo hello"
  expect_output: "hello"
```

**Priority Categories**:
- [ ] Edge case builtins (set, shift, eval, return, dot, break/continue)
- [ ] Parameter expansion edge cases (nested, complex patterns)
- [ ] Quoting and escaping edge cases
- [ ] Redirection edge cases (here-doc, read/write mode <>, etc.)
- [ ] Function scope and recursion
- [ ] Special parameter edge cases ($@, $*, $#, etc.)

### Phase 2: Interactive-Specific Features (Target: +150 tests)

Features unique to interactive mode that need deeper testing:

#### 2.1 Advanced Line Editing (Target: +50 tests)
- [ ] Undo/redo operations (if supported)
- [ ] Macro recording/playback
- [ ] Multiple cursor positions
- [ ] Copy/paste with system clipboard
- [ ] Mouse support (if applicable)
- [ ] Unicode edge cases (emoji, RTL text, combining characters)
- [ ] Very long lines (> 1000 chars)
- [ ] Line editing with terminal resize
- [ ] Incremental search (Ctrl+R) edge cases
- [ ] Argument history (Alt+., M-C-y)

#### 2.2 Advanced History (Target: +40 tests)
- [ ] History file operations (load, save, corruption handling)
- [ ] History size limits and rotation
- [ ] History ignoring patterns (HISTIGNORE)
- [ ] History timestamps
- [ ] Multi-line command history
- [ ] History sharing between sessions
- [ ] History search edge cases (empty pattern, special chars)
- [ ] History expansion with quoting
- [ ] History substitution modifiers (:p, :s, :g, etc.)

#### 2.3 Advanced Completion (Target: +40 tests)
- [ ] Programmable completion scripts
- [ ] Custom completion functions
- [ ] Completion with special characters in filenames
- [ ] Completion case-insensitivity options
- [ ] Completion menu navigation edge cases
- [ ] Completion with very long lists (> 1000 items)
- [ ] Completion timeout handling
- [ ] Context-sensitive completion (git, make, custom commands)

#### 2.4 Job Control Edge Cases (Target: +20 tests)
- [ ] Multiple job spec formats (%%, %+, %-, %n, %string, %?string)
- [ ] Job notification timing
- [ ] Job control with pipelines
- [ ] disown edge cases
- [ ] wait edge cases (wait %n, wait -n, wait with no jobs)
- [ ] Job control state after shell builtin failures
- [ ] Job control with subshells
- [ ] SIGCHLD handling

### Phase 3: Cross-Feature Interaction Tests (Target: +100 tests)

Test combinations that may reveal bugs:

#### 3.1 Editing + History
- [ ] Edit command from history, then recall it again
- [ ] Ctrl+R while editing a command
- [ ] History expansion while using line editing
- [ ] Multi-line command editing and recall

#### 3.2 Completion + Variables/Functions
- [ ] Complete with variable containing spaces
- [ ] Complete inside parameter expansion ${VAR[TAB]}
- [ ] Complete function names after definition
- [ ] Complete with exported vs local variables

#### 3.3 Job Control + Signals
- [ ] Ctrl+C during completion
- [ ] Ctrl+Z during history search
- [ ] Signal handling while editing
- [ ] Background job completion notification during editing

#### 3.4 Prompt + Escape Sequences
- [ ] Prompt with command substitution that fails
- [ ] Prompt with very long expansion
- [ ] Prompt during terminal resize
- [ ] Prompt with non-printing characters
- [ ] PS2 in various multi-line contexts

### Phase 4: Error Handling & Edge Cases (Target: +80 tests)

#### 4.1 Input Edge Cases
- [ ] Binary input (Ctrl+@, Ctrl+A-Z all combinations)
- [ ] Invalid UTF-8 sequences
- [ ] Terminal escape sequences as input
- [ ] Very fast input (paste simulation)
- [ ] Input buffer overflow scenarios

#### 4.2 Output Edge Cases
- [ ] Output > terminal buffer size
- [ ] Output with mixed control characters
- [ ] Output to full/broken pipe
- [ ] Output during terminal disconnect

#### 4.3 Resource Limits
- [ ] Maximum history size reached
- [ ] File descriptor exhaustion
- [ ] Memory limits (very long command line)
- [ ] Process limits (max jobs)

#### 4.4 Error Recovery
- [ ] Recovery from read error
- [ ] Recovery from terminal configuration errors
- [ ] Behavior when HOME undefined
- [ ] Behavior when PATH undefined/empty

### Phase 5: Stress & Performance Tests (Target: +50 tests)

- [ ] Rapid command execution (typing speed test)
- [ ] Large history file loading
- [ ] Completion with huge directory (1000+ files)
- [ ] Very deep directory structures
- [ ] Long-running command interruption patterns
- [ ] Memory leak detection (long session)
- [ ] Session with 1000+ commands

## Implementation Approach

### Option 1: Manual YAML Creation
- Pros: Full control, can optimize for interactive mode
- Cons: Tedious, error-prone, time-consuming
- Estimate: ~40 hours for 500 tests

### Option 2: Semi-Automated Conversion Tool
Create Python script to convert non-interactive tests:

```python
#!/usr/bin/env python3
"""Convert non-interactive POSIX tests to interactive YAML format."""

import re
import yaml

def parse_compare_posix_test(line):
    """Parse: compare_posix_output "test name" "command" """
    match = re.match(r'compare_posix_output "([^"]+)" "([^"]+)"', line)
    if match:
        name, command = match.groups()
        # Estimate expected output
        return {
            'name': name,
            'steps': [{'send_line': command}],
            'expect_output': estimate_output(command),
            'match_type': 'contains'
        }
    return None
```

- Pros: Fast initial creation, consistency
- Cons: May need manual adjustment, output estimation tricky
- Estimate: ~5 hours to write tool + ~10 hours to review/adjust

### Option 3: Hybrid Approach (RECOMMENDED)
1. Use converter for straightforward tests (commands, variables, etc.)
2. Manually create complex interactive tests
3. Use test generation for repetitive patterns

Estimate: ~15 hours total

## Prioritization

### High Priority (Do First)
1. **Builtin edge cases** from posix_compliance_gaps.sh
   - These are well-defined and easy to convert
   - High value for POSIX compliance

2. **Parameter expansion edge cases**
   - Already have some coverage, extend it
   - Clear expected outputs

3. **Job control improvements**
   - Currently weakest area (52.5% pass rate)
   - Critical for interactive shell

### Medium Priority
4. **Advanced line editing features**
5. **History expansion edge cases**
6. **Cross-feature interaction tests**

### Lower Priority (Nice to Have)
7. **Stress tests**
8. **Performance benchmarks**
9. **Resource limit tests**

## Success Metrics

- **Target coverage**: 650+ interactive tests (matching non-interactive count)
- **Target pass rate**: Maintain or improve 72%+ overall
- **Target time**: All tests complete in < 10 minutes
- **Coverage**: Each POSIX shell feature has ≥3 tests (basic, edge case, error)

## Next Steps

1. **Create converter tool** for simple test translation
2. **Port 50 builtin edge case tests** from gaps.sh
3. **Add 30 job control edge case tests**
4. **Review and document patterns** for future expansion
5. **Update test framework** if needed for new test types

## Questions to Resolve

1. Should we maintain 1:1 parity with non-interactive tests, or create interactive-specific variants?
2. How do we handle tests that are inherently non-interactive (e.g., exit code of entire script)?
3. Should we have separate "fast" and "comprehensive" test suites?
4. How do we test readline features that may not be present (compile-time options)?
