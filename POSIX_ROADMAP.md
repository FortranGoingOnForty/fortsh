# POSIX Compliance Roadmap for fortsh

**Current Status: 321/389 tests passing (82.5%)**
- Core POSIX: 272/272 (100%) ✓
- Advanced POSIX: 49/117 (41%)

**Goal: 100% POSIX.1-2017 Compliance**

---

## Phase 1: Parser & Control Flow Fixes (Target: +20 tests, ~2 weeks)

**Priority: HIGH** - These are commonly used features with moderate complexity

### 1.1 Line Continuation (3 tests)
- [ ] Implement backslash-newline continuation in parser
- [ ] Handle continuation in commands: `ec\<newline>ho test` → `echo test`
- [ ] Handle continuation in strings: `"hel\<newline>lo"` → `"hello"`
- **File**: `src/parsing/parser.f90`
- **Complexity**: Medium

### 1.2 Quote Handling Edge Cases (2 tests)
- [ ] Adjacent quotes should merge: `"a"b"c"` → `abc`
- [ ] Fix quote stripping logic in tokenization
- **File**: `src/parsing/parser.f90:strip_outer_quotes()`
- **Complexity**: Low

### 1.3 Multi-Level Break/Continue (5 tests)
- [ ] Add level argument support: `break 2`, `continue 3`
- [ ] Track loop depth in control flow stack
- [ ] Validate level <= current loop depth
- **Files**: `src/scripting/control_flow.f90`
- **Complexity**: Medium

### 1.4 For Loop Edge Cases (3 tests)
- [ ] Handle `for var in; do` (empty word list)
- [ ] Fix glob expansion in for loops causing premature termination
- [ ] Handle quoted items: `for i in "a b" "c d"`
- **File**: `src/scripting/control_flow.f90`
- **Complexity**: Low-Medium

### 1.5 Case Pattern Matching (2 tests)
- [ ] Implement `?` (single character) pattern
- [ ] Implement `[abc]` (character class) pattern
- [ ] Ensure patterns work in case statement contexts
- **File**: `src/scripting/control_flow.f90`, `src/parsing/glob.f90`
- **Complexity**: Medium

### 1.6 Comment Handling (1 test)
- [ ] Fix comment-only lines causing output issues
- [ ] Ensure `# comment\necho after` works correctly
- **File**: `src/parsing/parser.f90`
- **Complexity**: Low

### 1.7 Function Recursion (1 test)
- [ ] **CRITICAL BUG**: Fix function recursion (currently returns 0)
- [ ] Ensure stack frames don't interfere
- [ ] Test: `fact 5` should return 120, not 0
- **File**: `src/scripting/control_flow.f90`, `src/execution/executor.f90`
- **Complexity**: Medium-High

### 1.8 Semicolon Edge Cases (2 tests)
- [ ] Handle `;;` outside case (should error, currently succeeds)
- [ ] Handle `;` at start (should error, currently succeeds)
- [ ] Add proper syntax validation
- **File**: `src/parsing/parser.f90`
- **Complexity**: Low

### 1.9 Function Unset (1 test)
- [ ] Implement `unset -f function_name`
- [ ] Fix `command -v` to return proper exit code after unset
- **File**: `src/scripting/command_builtin.f90`
- **Complexity**: Low

**Phase 1 Estimated Completion: 20 tests → 341/389 (87.7%)**

---

## Phase 2: Arithmetic Extensions (Target: +20 tests, ~2-3 weeks)

**Priority: MEDIUM-HIGH** - Used in scripts but not critical

### 2.1 Bitwise Operators (6 tests)
- [ ] Implement `&` (bitwise AND)
- [ ] Implement `|` (bitwise OR)
- [ ] Implement `^` (bitwise XOR)
- [ ] Implement `~` (bitwise NOT)
- [ ] Implement `<<` (left shift)
- [ ] Implement `>>` (right shift)
- **File**: `src/scripting/expansion.f90:evaluate_arithmetic()`
- **Complexity**: Low-Medium (operator precedence matters)

### 2.2 Assignment Operators (5 tests)
- [ ] Implement `+=` (add assign)
- [ ] Implement `-=` (subtract assign)
- [ ] Implement `*=` (multiply assign)
- [ ] Implement `/=` (divide assign)
- [ ] Implement `%=` (modulo assign)
- **File**: `src/scripting/expansion.f90`
- **Complexity**: Medium (must handle lvalue assignment)

### 2.3 Increment/Decrement Operators (4 tests)
- [ ] Implement `++X` (pre-increment)
- [ ] Implement `X++` (post-increment)
- [ ] Implement `--X` (pre-decrement)
- [ ] Implement `X--` (post-decrement)
- **File**: `src/scripting/expansion.f90`
- **Complexity**: Medium (pre vs post semantics differ)

### 2.4 Ternary Operator (3 tests)
- [ ] Implement `condition ? true_val : false_val`
- [ ] Handle nested ternary: `a ? b : c ? d : e`
- [ ] Ensure proper precedence with other operators
- **File**: `src/scripting/expansion.f90`
- **Complexity**: Medium

### 2.5 Division by Zero Handling (1 test)
- [ ] Detect division by zero in arithmetic
- [ ] Return proper error exit code (127)
- **File**: `src/scripting/expansion.f90`
- **Complexity**: Low

### 2.6 Error Propagation in Expansions (1 test)
- [ ] Fix `set -u` exit code for undefined variables
- [ ] Should exit 127, currently exits 1
- **File**: `src/scripting/variables.f90`
- **Complexity**: Low

**Phase 2 Estimated Completion: 20 tests → 361/389 (92.8%)**

---

## Phase 3: Redirection & I/O (Target: +10 tests, ~1-2 weeks)

**Priority: MEDIUM** - Advanced features, less commonly used

### 3.1 Redirection Order/Precedence (2 tests)
- [ ] Fix: `echo test >/tmp/f1 2>&1 >/tmp/f2` (order matters)
- [ ] Ensure redirects are processed left-to-right
- [ ] Ensure FD duplication happens at the right time
- **File**: `src/parsing/parser.f90`, `src/io/fd_redirection.f90`
- **Complexity**: Medium-High

### 3.2 Compound Command Redirection (2 tests)
- [ ] Fix: `{ cmd1; cmd2; } > file` not working
- [ ] Handle brace group redirects
- [ ] Handle if/while/for statement redirects
- **File**: `src/execution/executor.f90`
- **Complexity**: Medium

### 3.3 Exec Without Command (1 test)
- [ ] Fix: `exec 2>&1` should only affect redirections
- [ ] Should not replace shell process
- **File**: `src/execution/builtins.f90:builtin_exec()`
- **Complexity**: Low

### 3.4 File Descriptor Edge Cases (3 tests)
- [ ] Close stdout: `exec 1>&-` should work
- [ ] Duplicate from closed FD should fail gracefully
- [ ] FD operations in subshells shouldn't affect parent
- **File**: `src/io/fd_redirection.f90`
- **Complexity**: Medium

### 3.5 Read Builtin Edge Cases (2 tests)
- [ ] Fix: `read` in pipeline: `echo hello | read VAR`
- [ ] Handle read with custom IFS properly
- **File**: `src/scripting/read_builtin.f90`
- **Complexity**: Low-Medium

**Phase 3 Estimated Completion: 10 tests → 371/389 (95.4%)**

---

## Phase 4: Shell Options & Environment (Target: +10 tests, ~1 week)

**Priority: LOW-MEDIUM** - Useful but not critical

### 4.1 Set -f (noglob) (3 tests)
- [ ] Implement `set -f` to disable pathname expansion
- [ ] Implement `set +f` to re-enable
- [ ] Track state in `shell%options`
- **File**: `src/scripting/shell_options.f90`
- **Complexity**: Low

### 4.2 Set -x (xtrace) (2 tests)
- [ ] Implement `set -x` to print commands before execution
- [ ] Print to stderr with `+` prefix (bash style)
- [ ] Handle in functions
- **File**: `src/execution/executor.f90`
- **Complexity**: Low

### 4.3 Set -v (verbose) (1 test)
- [ ] Implement `set -v` to print input lines
- [ ] Print to stderr as lines are read
- **File**: `src/fortsh.f90`
- **Complexity**: Low

### 4.4 Set -a (allexport) (2 tests)
- [ ] Implement `set -a` to export all variables
- [ ] Mark all assignments as exported
- [ ] Implement `set +a` to disable
- **File**: `src/scripting/variables.f90`
- **Complexity**: Low

### 4.5 CDPATH Variable (1 test)
- [ ] Implement CDPATH search for `cd` command
- [ ] Colon-separated directory list
- [ ] Search directories in order
- **File**: `src/scripting/directory_builtin.f90`
- **Complexity**: Low-Medium

### 4.6 Alias Unset (1 test)
- [ ] Fix: `unalias` should make alias not found
- [ ] Currently returns 0, should return error
- **File**: `src/scripting/aliases.f90`
- **Complexity**: Low

**Phase 4 Estimated Completion: 10 tests → 381/389 (97.9%)**

---

## Phase 5: Advanced Features & Edge Cases (Target: +8 tests, ~1 week)

**Priority: LOW** - Rarely used features

### 5.1 IFS Edge Cases (4 tests)
- [ ] Empty IFS: `IFS=` should disable field splitting
- [ ] IFS whitespace-only: handle properly
- [ ] IFS custom delimiter: `:` or `,`
- [ ] IFS leading delimiters: `:a:b` splits correctly
- **File**: `src/parsing/parser.f90`
- **Complexity**: Medium

### 5.2 Wait with Arguments (1 test)
- [ ] Fix: `wait 999999` (nonexistent PID) should return error
- [ ] Currently not handling error case
- **File**: `src/execution/jobs.f90`
- **Complexity**: Low

### 5.3 Trap Inheritance (2 tests)
- [ ] Verify traps don't inherit to subshells (correct behavior)
- [ ] Ensure subshell can set own traps
- **File**: `src/system/signal_handling.f90`
- **Complexity**: Low

### 5.4 Pathname Expansion - Dotfiles (1 test)
- [ ] Fix: `*` should not match dotfiles
- [ ] Currently matching `.hidden` files
- **File**: `src/parsing/glob.f90`
- **Complexity**: Low-Medium

**Phase 5 Estimated Completion: 8 tests → 389/389 (100%)**

---

## Summary Timeline

| Phase | Focus | Tests Added | Cumulative | Duration | Complexity |
|-------|-------|-------------|------------|----------|------------|
| **Phase 1** | Parser & Control Flow | +20 | 341/389 (87.7%) | 2 weeks | Medium |
| **Phase 2** | Arithmetic Extensions | +20 | 361/389 (92.8%) | 2-3 weeks | Medium-High |
| **Phase 3** | Redirection & I/O | +10 | 371/389 (95.4%) | 1-2 weeks | Medium |
| **Phase 4** | Shell Options | +10 | 381/389 (97.9%) | 1 week | Low |
| **Phase 5** | Edge Cases | +8 | 389/389 (100%) | 1 week | Low-Medium |
| **TOTAL** | | **68 tests** | **100%** | **7-9 weeks** | |

---

## Risk Assessment

### Low Risk (Can implement without breaking existing tests):
- ✅ Quote handling edge cases
- ✅ Comment handling
- ✅ Shell options (set -f, -x, -v, -a)
- ✅ CDPATH
- ✅ Wait error handling
- ✅ Arithmetic operators (additive, not replacing)

### Medium Risk (Requires careful testing):
- ⚠️ Backslash line continuation (parser changes)
- ⚠️ Multi-level break/continue (control flow changes)
- ⚠️ Redirection order (subtle precedence rules)
- ⚠️ IFS edge cases (tokenization changes)

### High Risk (Could break existing functionality):
- ⛔ Function recursion fix (currently broken)
- ⛔ Compound command redirects (execution model changes)

---

## Testing Strategy

### Per-Phase:
1. **Implement feature** in isolated branch
2. **Run all 389 tests** to ensure no regressions
3. **Fix any breakages** before proceeding
4. **Merge to trunk** only when tests pass

### Continuous Validation:
```bash
# Run after each commit
./tests/run_posix_tests.sh

# Track progress
echo "Progress: $(grep -o 'Passed:.*[0-9]*' | awk '{sum+=$2} END {print sum}')/389"
```

---

## Recommended Phase Ordering (by ROI)

If prioritizing by **impact vs effort**:

1. **Phase 1** (High impact, medium effort) - Fixes common issues
2. **Phase 4** (Medium impact, low effort) - Quick wins
3. **Phase 3** (Medium impact, medium effort) - I/O completeness
4. **Phase 2** (Low-medium impact, medium effort) - Advanced arithmetic
5. **Phase 5** (Low impact, low-medium effort) - Polish

---

## Success Criteria

- ✅ All 389 POSIX tests passing
- ✅ No regressions in existing 321 passing tests
- ✅ Clean compilation on both macOS ARM64 (flang-new) and Linux (gfortran)
- ✅ All changes use platform guards (`#ifdef __APPLE__`) where needed
- ✅ Code remains maintainable and well-documented

---

## The Ambitious Goal

> **"A POSIX-compliant Fortran shell - because why the hell not?"**

Let's make this happen! 🚀

---

*Last Updated: 2025-11-05*
*Current Maintainer: Matthew Wolffe*
*Target Completion: Q1 2026*
