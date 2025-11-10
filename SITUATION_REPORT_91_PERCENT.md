# FORTSH SITUATION REPORT - 91% POSIX Compliance

## Executive Summary
We're at 91% POSIX compliance (91/99 tests) with 8 remaining failures across 4 categories. Each category has distinct architectural challenges that require careful approach.

## Architecture Overview

### Current Pipeline
```
Input → Lexer → Parser → AST → AST Executor → Old Executor → Output
         ↓        ↓       ↓          ↓              ↓
      tokens   grammar  tree    pipeline_t    execution
```

### Key Data Structures
- **token_t**: Has `quoted` flag (boolean) and `escaped` flag
- **command_t**: Has metadata arrays: `token_quoted[]`, `token_escaped[]`
- **Problem**: No distinction between single vs double quotes after lexing

## Remaining 8 Failures - Detailed Analysis

### 1. Command Substitution (3 tests) - ARCHITECTURAL BLOCKER
**Tests failing:**
- Backtick substitution: `` `echo test` ``
- Dollar paren: `$(echo test)`
- Nested: `$(echo $(echo test))`

**Current State:**
- `execute_command_and_capture` is STUBBED to return empty string
- Located in: `/src/execution/command_capture.f90`

**Circular Dependency Chain:**
```
command_capture → ast_executor → executor → expansion → substitution → command_capture
```

**Past Attempts:**
- Tried stubbing (current state) - breaks functionality
- Cannot simply reorder modules due to tight coupling

**Recommended Fix:**
1. Create interface module with deferred implementation
2. Use function pointers or callback pattern
3. OR: Refactor substitution to not need command_capture directly

**Risk**: HIGH - touches core execution path

### 2. Heredocs with -c Flag (3 tests) - DESIGN LIMITATION
**Tests failing:**
- Simple heredoc: `cat <<EOF\nline1\nEOF`
- With variables: `VAR=test; cat <<EOF\n$VAR\nEOF`
- Quoted delimiter: `cat <<'EOF'\n$VAR\nEOF`

**Current State:**
- Heredocs WORK interactively (via pipe)
- FAIL with `-c` flag (command line argument)

**Root Cause:**
- With `-c`, entire multi-line command is passed as single argument
- Parser gets tokenized single line, not multi-line input
- Old parser handles this correctly somehow

**Past Attempts:**
- Tried extracting content from `raw_input` in parser
- Failed: `raw_input` only contains first line with `-c`
- Reverted to just storing delimiter

**Recommended Fix:**
1. Special case in fortsh.f90 when `-c` flag is used
2. Pre-process heredocs before sending to parser
3. OR: Modify parser to handle multi-line tokens

**Risk**: MEDIUM - requires special handling path

### 3. Single Quote Literal (1 test) - METADATA LOSS
**Test failing:**
- `echo '$VAR'` should output `$VAR` literally

**Current State:**
- Outputs empty string
- Lexer correctly captures content
- Lost during expansion phase

**Root Cause:**
- Lexer strips quotes, sets `quoted=.true.` for BOTH single and double
- `expand_variables` can't distinguish quote types
- Double quotes need expansion, single quotes don't

**Past Attempts:**
1. Skip expansion for all quoted tokens → broke double quotes (73% compliance)
2. Heuristic: if quoted AND has `$` → single quote → broke some cases (75%)
3. Re-wrap in quotes before expansion → still failed
4. REVERTED all attempts

**Recommended Fix:**
Add quote type tracking throughout pipeline:
1. Add `quote_type` to token_t (QUOTE_NONE, QUOTE_SINGLE, QUOTE_DOUBLE)
2. Preserve through parser to command_t
3. Check in executor before calling expand_variables

**Risk**: LOW-MEDIUM - well understood, just needs plumbing

### 4. Export Variable (1 test) - SECONDARY EFFECT
**Test failing:**
- `export VAR=test; sh -c 'echo $VAR'` should output `test`

**Current State:**
- Outputs empty string
- Export itself might work, but nested shell invocation fails

**Likely Cause:**
- Related to quote handling in the nested command
- The single quotes around `'echo $VAR'` not handled correctly

**Recommended Fix:**
- Will likely resolve when single quote handling is fixed
- May need to verify export actually sets environment variables

**Risk**: LOW - likely fixed by single quote fix

## Risk Matrix

| Issue | Impact | Difficulty | Risk | Priority |
|-------|--------|------------|------|----------|
| Command Substitution | 3 tests | HIGH - circular deps | HIGH | 2 |
| Heredocs | 3 tests | MEDIUM - design change | MEDIUM | 3 |
| Single Quotes | 1 test (+export) | LOW - just plumbing | LOW | 1 |
| Export | 1 test | LOW - secondary | LOW | 4 |

## Recommended Action Plan

### Phase 1: Single Quote Fix (LOW RISK)
- Add quote_type enum to types.f90
- Update lexer to track quote type
- Plumb through parser → AST → executor
- Test: Should fix 2 tests (single quote + maybe export)
- **Target: 91% → 93%**

### Phase 2: Command Substitution (HIGH RISK)
- Design interface/callback pattern
- Break circular dependency
- Implement proper command capture
- Test: Should fix 3 tests
- **Target: 93% → 96%**

### Phase 3: Heredocs (MEDIUM RISK)
- Add multi-line command preprocessing
- Special handling for `-c` flag
- Test: Should fix 3 tests
- **Target: 96% → 99% or 100%**

## Technical Debt Considerations

1. **Two Parser Problem**: Currently maintaining old and new parsers
2. **Metadata Arrays**: Growing number of parallel arrays (quoted, escaped, etc)
3. **Module Dependencies**: Tight coupling making changes risky
4. **Test Coverage**: Need regression tests for each fix

## Success Metrics

- Each fix should maintain or improve compliance
- No fix should break previously passing tests
- Document each architectural decision
- Maintain clean reversion points

## Conclusion

We're close to 100% but the remaining issues require careful architectural decisions. The single quote fix is the safest starting point with good ROI (potentially 2 tests for low risk). Command substitution is the biggest blocker but also highest risk. Heredocs need design consideration for the `-c` flag special case.