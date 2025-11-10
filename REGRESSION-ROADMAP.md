# REGRESSION ROADMAP - Parser Migration

## Current State (November 2025)

After migrating to the new AST-based parser, we've made significant progress but still have regressions compared to the old parser which achieved 100% on all test suites.

### Current POSIX Compliance

| Test Suite | Current | Target | Status |
|------------|---------|--------|--------|
| Basic | **100%** (99/99) | 100% | ✅ **ACHIEVED!** |
| Extended | 97% (118/121) | 100% | 🔧 3 failures remaining |
| Builtins | 79% (41/52) | 100% | ⚠️ 11 failures |
| Advanced | 50% (59/117) | 100% | ⚠️ 58 failures |
| **Overall** | **80.5%** (317/389) | 100% | 📈 Progress |

## Recent Achievements

### ✅ Fixed Issues
1. **Single Quote Preservation** - Fixed literal preservation in single quotes
2. **Command Substitution** - Resolved circular dependency with callback pattern
3. **Output Capture** - Migrated from temp files to pipe-based capture
4. **Single-Quoted Arguments** - Fixed IFS splitting to respect quote metadata
5. **Heredoc Variable Expansion** - Fixed heredocs with `-c` flag to properly expand variables

## Remaining Regressions

### Extended Test Suite (3 failures)
- [ ] Investigate and fix remaining 3 failures
- [ ] Likely related to complex quoting or expansion edge cases

### Builtins Test Suite (11 failures)
- [ ] `set` builtin edge cases
- [ ] `export` with special characters
- [ ] `readonly` variable handling
- [ ] `shift` parameter handling
- [ ] `getopts` option parsing
- [ ] `trap` signal handling
- [ ] `wait` job control
- [ ] `umask` permission handling
- [ ] `ulimit` resource limits
- [ ] `times` process timing
- [ ] `type` command lookup

### Advanced Test Suite (58 failures)
Major categories of failures:
- [ ] Complex parameter expansion (${var##pattern}, ${var%%pattern}, etc.)
- [ ] Array operations
- [ ] Process substitution <() and >()
- [ ] Complex redirection (>&2, 2>&1, etc.)
- [ ] Job control (bg, fg, jobs)
- [ ] Complex glob patterns
- [ ] Arithmetic expansion $((...))
- [ ] Complex case patterns
- [ ] Function scoping
- [ ] Complex heredoc edge cases

## Action Plan

### Phase 1: Extended Test Suite (Target: 100%)
1. Run extended tests with VERBOSE=1
2. Identify specific failing tests
3. Fix remaining 3 failures
4. **Goal: 100% on Extended**

### Phase 2: Builtins (Target: 100%)
1. Run builtins tests with VERBOSE=1
2. Group failures by builtin command
3. Fix each builtin systematically
4. **Goal: 100% on Builtins**

### Phase 3: Advanced Features (Target: 100%)
1. Prioritize by impact:
   - Parameter expansion (high impact)
   - Arrays (medium impact)
   - Process substitution (medium impact)
   - Job control (low impact for scripts)
2. Fix systematically by category
3. **Goal: 100% on Advanced**

## Implementation Strategy

### For Each Regression:
1. **Isolate** - Create minimal test case
2. **Debug** - Add targeted debug output
3. **Fix** - Implement solution
4. **Test** - Verify fix doesn't break other tests
5. **Document** - Update this roadmap

### Key Files to Monitor:
- `/src/execution/ast_executor.f90` - AST execution logic
- `/src/parsing/grammar_parser.f90` - Grammar parsing
- `/src/parsing/lexer.f90` - Token generation
- `/src/execution/executor.f90` - Command execution
- `/src/scripting/expansion.f90` - Variable/parameter expansion
- `/src/scripting/substitution.f90` - Command substitution

## Success Metrics

- **Milestone 1**: 100% on Basic ✅ **ACHIEVED!**
- **Milestone 2**: 100% on Extended (97% → 100%)
- **Milestone 3**: 100% on Builtins (79% → 100%)
- **Milestone 4**: 100% on Advanced (50% → 100%)
- **Final Goal**: 100% across all 389 tests

## Notes

The old parser achieved 100% on all test suites. While the new AST-based parser offers better architecture and maintainability, we must achieve feature parity. The regression from 100% to 80.5% is temporary - each issue is solvable with targeted fixes.

### Why This Matters
- **Correctness**: POSIX compliance ensures scripts work as expected
- **Compatibility**: Users rely on standard behavior
- **Trust**: Regressions erode confidence in the new parser
- **Pride**: We had 100% - we can achieve it again!

---

*Last Updated: November 2025*
*Next Review: After Phase 1 completion*